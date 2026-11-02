ExUnit.start(autorun: false)
import ExUnit.Assertions
alias Ipse.{CLI, JSON, Journal, Usage}
alias Ipse.Extension.{Collection, Consent, ProjectIdentity, SemanticAdmission}
alias Ipse.Session.{PendingAcceptance, PendingBatch}
{:ok, _} = Application.ensure_all_started(:ipse)
[root, mode] = System.argv()
assert mode in ~w(cancel stale source-loss accept partial)
home = Path.join(root, "home")
cwd = Path.join(root, "work")
System.put_env("IPSE_HOME", home)

for env <-
      ~w(IPSE_PROVIDER IPSE_MODEL IPSE_SANDBOX IPSE_MAX_STEPS IPSE_CONTEXT_BYTES IPSE_COMPACT IPSE_SUBAGENTS IPSE_SUBAGENT_CONCURRENCY IPSE_TIMEOUT_MS IPSE_MAX_OUTPUT_TOKENS IPSE_PROFILE IPSE_CONFIG),
    do: System.delete_env(env)

fixture = root |> Path.join("pending-batch.json") |> File.read!() |> Jason.decode!()
keys = fixture["keys"] || [fixture["key"], fixture["peer_key"]]
collection = SemanticAdmission.collection_root(home)
namespace = fixture["namespace"]

read = fn key ->
  {:ok, view} = Collection.open_view(collection, namespace)

  try do
    assert {:ok, %{"records" => [record]}} =
             Collection.view_read(view, %{"op" => "get_many", "keys" => [key]})

    record
  after
    assert :ok = Collection.close_view(view)
  end
end

targets = Map.new(keys, &{&1, read.(&1)})
journals = Map.new(Path.wildcard(fixture["history_dir"] <> "/*.jsonl"), &{&1, File.read!(&1)})
{:ok, binding} = ProjectIdentity.existing(home, cwd)
control = SemanticAdmission.control_root(home)
assert {:ok, before_control} = Consent.existing_snapshot(control, binding["project_id"])

assert {:ok, before_state} =
         Collection.execute(collection, namespace, %{"op" => "snapshot"}, Usage.id())

old_management = Path.wildcard(Path.join(home, "knowledge-management/*.jsonl"))

options = [
  "--cwd",
  cwd,
  "--config",
  Path.join(home, "config.json"),
  "--no-project-config",
  "--state-dir",
  fixture["history_dir"]
]

source = hd(targets[hd(keys)]["value"]["evidence"]["sources"])
source_path = Path.join(fixture["history_dir"], source["session_id"] <> ".jsonl")
held = source_path <> ".batch-unavailable"

race =
  if mode == "source-loss" do
    for name <- ~w(management-review-input-ready management-review-race-complete),
        do: File.rm(Path.join(root, name))

    Task.async(fn ->
      deadline = System.monotonic_time(:millisecond) + 15_000

      wait = fn wait ->
        cond do
          File.exists?(Path.join(root, "management-review-input-ready")) ->
            :ok

          System.monotonic_time(:millisecond) >= deadline ->
            :timeout

          true ->
            Process.sleep(10)
            wait.(wait)
        end
      end

      assert :ok = wait.(wait)
      assert {:ok, lock} = Ipse.Runner.lock(Path.rootname(source_path) <> ".lock")
      File.rename!(source_path, held)
      assert :ok = Ipse.Runner.unlock(lock)
      File.write!(Path.join(root, "management-review-race-complete"), "done", [:exclusive])
    end)
  end

code =
  try do
    CLI.run(["knowledge", "review" | keys] ++ options)
  after
    if File.exists?(held) do
      assert {:ok, lock} = Ipse.Runner.lock(Path.rootname(source_path) <> ".lock")
      File.rename!(held, source_path)
      assert :ok = Ipse.Runner.unlock(lock)
    end
  end

if race, do: Task.await(race, 20_000)
assert code == if(mode == "accept", do: 0, else: 1)

assert journals ===
         Map.new(Path.wildcard(fixture["history_dir"] <> "/*.jsonl"), &{&1, File.read!(&1)})

assert {:ok, after_control} = Consent.existing_snapshot(control, binding["project_id"])
new_ids = Map.keys(after_control["operations"]) -- Map.keys(before_control["operations"])
paths = Path.wildcard(Path.join(home, "knowledge-management/*.jsonl")) -- old_management

expected_accepted =
  cond do
    mode == "accept" -> length(keys)
    mode == "partial" -> 1
    true -> 0
  end

expected_reviewed = if mode in ~w(accept partial), do: length(keys), else: 1
assert length(new_ids) == expected_reviewed and length(paths) == expected_reviewed

events =
  Enum.flat_map(paths, fn path ->
    assert {:ok, %{events: records, tail: :none}} = Journal.read_path(path)
    assert :ok = PendingAcceptance.validate_events(records, Path.basename(path, ".jsonl"))
    Enum.filter(records, &(&1["type"] == "pending_proposal_accepted"))
  end)

assert length(events) == expected_accepted

assert Enum.count(new_ids, &(after_control["operations"][&1]["actual"]["operations"] == 1)) ==
         expected_accepted

for id <- new_ids do
  operation = after_control["operations"][id]
  assert operation["status"] == "settled"
  assert operation["actual"]["model_calls"] == 0 and operation["actual"]["download_bytes"] == 0
  assert operation["actual"]["cost_nanos"] == 0
end

for event <- events do
  assert PendingAcceptance.valid_event?(event)
  facts = event["facts"]
  batch = facts["batch"]
  assert PendingBatch.member?(batch, facts)
  assert Enum.map(batch["manifest"]["items"], & &1["pending_key"]) === keys
  assert byte_size(Jason.encode!(batch["manifest"])) <= 8192
  assert facts["record_sha256"] === targets[facts["pending_key"]]["sha256"]

  assert facts["source_proof"] ===
           hd(targets[facts["pending_key"]]["value"]["evidence"]["sources"])

  assert facts["source_proof"]["origin"] === "unattended_input"
  assert is_nil(read.(facts["pending_key"]))
  assert {:ok, note_key} = PendingAcceptance.accepted_note_key(event)
  assert read.(note_key)["value"]["kind"] == "accepted_decision"
  assert read.(note_key)["value"]["text"] === facts["text"]

  assert {:ok, %{"control_status" => "settled", "journal_status" => "committed"} = inspected} =
           Ipse.CLI.Knowledge.Management.operation(%{home: home}, cwd, facts["journal_id"])

  assert inspected["batch_manifest_sha256"] === batch["manifest_sha256"]
  assert inspected["batch_index"] === batch["index"]
  assert inspected["batch_count"] === length(keys)
end

if mode == "accept" do
  assert Enum.uniq_by(events, & &1["facts"]["batch"]["manifest_sha256"]) |> length() == 1

  assert Enum.sort(Enum.map(events, & &1["facts"]["batch"]["index"])) ==
           Enum.to_list(0..(length(keys) - 1))

  assert length(Enum.uniq_by(events, & &1["review"]["event_id"])) == length(keys)
  assert length(Enum.uniq_by(events, & &1["review"]["challenge"])) == length(keys)
else
  remaining = if mode == "partial", do: [List.last(keys)], else: keys
  for key <- remaining, do: assert(read.(key) === targets[key])

  if mode != "partial" do
    assert {:ok, ^before_state} =
             Collection.execute(collection, namespace, %{"op" => "snapshot"}, Usage.id())
  else
    [event] = events
    assert event["facts"]["pending_key"] === hd(keys)
    before_inspection = Enum.map(paths, &{&1, File.read!(&1)})

    for _ <- 1..2, path <- paths do
      assert {:ok, _} =
               Ipse.CLI.Knowledge.Management.operation(
                 %{home: home},
                 cwd,
                 Path.basename(path, ".jsonl")
               )
    end

    assert before_inspection === Enum.map(paths, &{&1, File.read!(&1)})
    assert {:ok, ^after_control} = Consent.existing_snapshot(control, binding["project_id"])
  end
end

IO.puts("PUBLIC_SESSION_PENDING_BATCH_#{String.upcase(mode)}_PASSED")
