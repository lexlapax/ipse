ExUnit.start(autorun: false)
import ExUnit.Assertions
alias Ipse.{CLI, JSON, Journal, Usage}
alias Ipse.Extension.{Collection, Consent, ProjectIdentity, SemanticAdmission}
alias Ipse.Extension.Collection.ManagedPages
alias Ipse.Session.PendingAcceptance
{:ok, _} = Application.ensure_all_started(:ipse)
[root, mode] = System.argv()
assert mode in ~w(stale cancel source-loss correct grant-race deadline)
home = Path.join(root, "home")
cwd = Path.join(root, "work")
System.put_env("IPSE_HOME", home)

for env <-
      ~w(IPSE_PROVIDER IPSE_MODEL IPSE_SANDBOX IPSE_MAX_STEPS IPSE_CONTEXT_BYTES IPSE_COMPACT IPSE_SUBAGENTS IPSE_SUBAGENT_CONCURRENCY IPSE_TIMEOUT_MS IPSE_MAX_OUTPUT_TOKENS IPSE_PROFILE IPSE_CONFIG),
    do: System.delete_env(env)

fixture = root |> Path.join("pending-correction.json") |> File.read!() |> Jason.decode!()
namespace = fixture["namespace"]
collection = SemanticAdmission.collection_root(home)

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

key = if mode == "grant-race", do: fixture["peer_key"], else: fixture["key"]

peer_key =
  if mode == "grant-race" do
    root
    |> Path.join("pending-correction-success.json")
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("accepted_note_key")
  else
    fixture["peer_key"]
  end

target = read.(key)
peer = read.(peer_key)
[proof] = get_in(target, ["value", "evidence", "sources"])
sessions = Map.new(Path.wildcard(fixture["history_dir"] <> "/*.jsonl"), &{&1, File.read!(&1)})
{:ok, binding} = ProjectIdentity.existing(home, cwd)
control = SemanticAdmission.control_root(home)
assert {:ok, before_control} = Consent.existing_snapshot(control, binding["project_id"])
assert is_map(before_control["policy"])

if mode == "deadline" do
  # Trusted fixture policy, actual saved epoch and host wall time. No native
  # review, retention clock or publication result is manufactured here.
  policy =
    Map.put(before_control["policy"], "expires_at_ms", System.system_time(:millisecond) + 4000)

  assert {:ok, _} =
           Consent.replace(
             control,
             binding["project_id"],
             before_control["epoch"],
             policy,
             System.system_time(:millisecond)
           )
end

assert {:ok, before_control} = Consent.existing_snapshot(control, binding["project_id"])
{:ok, view} = Collection.open_view(collection, namespace)

anchor_key =
  try do
    {:ok, selected} =
      Collection.view_neighbors(view, %{
        "version" => 1,
        "prefix" => ManagedPages.prefix(:anchor),
        "fence_bytes" => ManagedPages.width(:anchor),
        "needle" => target["value"]["lineage"]
      })

    selected["neighbors"]["selected"]["key"]
  after
    :ok = Collection.close_view(view)
  end

anchor = read.(anchor_key)
{:ok, before_state} = Collection.execute(collection, namespace, %{"op" => "snapshot"}, Usage.id())
old_journals = Path.wildcard(Path.join(home, "knowledge-management/*.jsonl"))
text = "Use ISO dates in the release report; this is a corrected pending proposal."

options = [
  "--cwd",
  cwd,
  "--config",
  Path.join(home, "config.json"),
  "--no-project-config",
  "--state-dir",
  fixture["history_dir"]
]

source_path = Path.join(fixture["history_dir"], proof["session_id"] <> ".jsonl")
held_path = source_path <> ".correction-unavailable"

if mode in ~w(correct grant-race) do
  # Actual Session-produced candidate; read-only deferral does not require its
  # source journal to be available and leaves the later review unchanged.
  assert {:ok, lock} = Ipse.Runner.lock(Path.rootname(source_path) <> ".lock")
  File.rename!(source_path, held_path)
  assert :ok = Ipse.Runner.unlock(lock)

  try do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert CLI.run([
                 "knowledge",
                 "defer",
                 key,
                 "--json",
                 "--cwd",
                 cwd,
                 "--config",
                 Path.join(home, "config.json"),
                 "--no-project-config"
               ]) == 0
      end)

    deferred = Jason.decode!(output)
    assert deferred["status"] == "pending" and deferred["stored_effect"] == "none"
    assert deferred["key"] === target["key"] and deferred["record_sha256"] === target["sha256"]
    assert {:ok, ^before_control} = Consent.existing_snapshot(control, binding["project_id"])

    assert {:ok, ^before_state} =
             Collection.execute(collection, namespace, %{"op" => "snapshot"}, Usage.id())

    assert old_journals === Path.wildcard(Path.join(home, "knowledge-management/*.jsonl"))
  after
    assert {:ok, lock} = Ipse.Runner.lock(Path.rootname(source_path) <> ".lock")
    File.rename!(held_path, source_path)
    assert :ok = Ipse.Runner.unlock(lock)
  end
end

if mode == "deadline" do
  owner = self()

  assert :ok =
           :telemetry.attach(
             "pending-correction-real-deadline",
             [:ipse, :extension, :collection, :staged],
             fn _, _, _, _ ->
               deadline = Process.get({Collection, :switch_deadline})
               assert deadline === before_control["policy"]["expires_at_ms"]
               assert System.system_time(:millisecond) < deadline
               send(owner, {:pending_correction_staged, deadline})
               Process.sleep(max(0, deadline - System.system_time(:millisecond)) + 50)
             end,
             nil
           )
end

race =
  if mode in ~w(source-loss grant-race) do
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

      if mode == "source-loss" do
        assert {:ok, lock} = Ipse.Runner.lock(Path.rootname(source_path) <> ".lock")
        File.rename!(source_path, held_path)
        assert :ok = Ipse.Runner.unlock(lock)
      else
        assert {:ok, %{"epoch" => epoch}} =
                 Consent.revoke(control, binding["project_id"], before_control["epoch"])

        assert epoch == before_control["epoch"] + 1
      end

      File.write!(Path.join(root, "management-review-race-complete"), "done", [:exclusive])
    end)
  end

code =
  try do
    CLI.run(["knowledge", "correct", key, text] ++ options)
  after
    if File.exists?(held_path) do
      assert {:ok, lock} = Ipse.Runner.lock(Path.rootname(source_path) <> ".lock")
      File.rename!(held_path, source_path)
      assert :ok = Ipse.Runner.unlock(lock)
    end
  end

if race, do: Task.await(race, 20_000)
assert code == if(mode == "correct", do: 0, else: 1)
assert read.(peer_key) === peer
assert read.(anchor_key) === anchor

assert sessions ===
         Map.new(Path.wildcard(fixture["history_dir"] <> "/*.jsonl"), &{&1, File.read!(&1)})

assert {:ok, after_control} = Consent.existing_snapshot(control, binding["project_id"])
[id] = Map.keys(after_control["operations"]) -- Map.keys(before_control["operations"])
operation = after_control["operations"][id]
assert operation["status"] === if(mode == "deadline", do: "unknown", else: "settled")
assert operation["operation"] === "notes.capture"
[journal] = Path.wildcard(Path.join(home, "knowledge-management/*.jsonl")) -- old_journals
assert {:ok, %{events: events, tail: :none}} = Journal.read_path(journal)

if mode == "deadline" do
  assert_receive {:pending_correction_staged, deadline}, 1000
  assert deadline === before_control["policy"]["expires_at_ms"]
  assert read.(key) === target

  assert {:ok, ^before_state} =
           Collection.execute(collection, namespace, %{"op" => "snapshot"}, Usage.id())

  assert operation["actual"] === nil and operation["receipt"] === nil
  assert operation["reserved"]["operations"] === 1
  [intent] = Enum.filter(events, &(&1["type"] == "managed_lifecycle_intent"))
  [result] = Enum.filter(events, &(&1["type"] == "managed_lifecycle_result"))
  assert result["status"] === "unconfirmed"
  assert intent["facts"]["publish_before_ms"] === deadline
  assert System.system_time(:millisecond) >= deadline
  before_inspection = File.read!(journal)

  for _ <- 1..2 do
    assert {:ok,
            %{
              "control_status" => "unknown",
              "journal_status" => "unconfirmed",
              "replayed" => false
            }} =
             CLI.Knowledge.Management.operation(
               %{home: home},
               cwd,
               Path.basename(journal, ".jsonl")
             )

    assert {:ok, ^after_control} = Consent.existing_snapshot(control, binding["project_id"])
    assert File.read!(journal) === before_inspection
  end
else
  if mode in ~w(stale cancel source-loss grant-race) do
    assert read.(key) === target

    assert {:ok, ^before_state} =
             Collection.execute(collection, namespace, %{"op" => "snapshot"}, Usage.id())

    assert operation["actual"] === Consent.zero()
    refute Enum.any?(events, &(&1["type"] == "managed_lifecycle_intent"))
  else
    [intent] = Enum.filter(events, &(&1["type"] == "managed_lifecycle_intent"))
    facts = intent["facts"]
    assert facts["target"] === target
    assert facts["source_card"]["source_proof"] === proof
    assert operation["actual"]["operations"] === 1 and operation["actual"]["model_calls"] === 0
    assert operation["actual"]["download_bytes"] === 0 and operation["actual"]["cost_nanos"] === 0
    key = Enum.at(facts["request"]["changes"], 1)["key"]
    corrected = read.(key)
    assert corrected["value"]["text"] === text
    assert corrected["value"]["kind"] === "proposal" and corrected["value"]["state"] === "pending"
    assert Map.drop(corrected["value"], ~w(id text)) === Map.drop(target["value"], ~w(id text))
    assert read.(target["key"]) === nil
    suppression = read.("reject." <> target["value"]["id"])
    assert suppression["value"]["replacement_key"] === key

    assert {:ok,
            %{
              "control_status" => "settled",
              "journal_status" => "settled",
              "replayed" => false,
              "replacement_pending_key" => ^key
            }} =
             CLI.Knowledge.Management.operation(
               %{home: home},
               cwd,
               Path.basename(journal, ".jsonl")
             )

    # Editing supplies no acceptance event or current-note publication.
    assert read.("accept." <> corrected["value"]["id"]) === nil
    refute Enum.any?(events, &(&1["type"] == "pending_proposal_accepted"))

    assert {:ok, after_correction} =
             Collection.execute(collection, namespace, %{"op" => "snapshot"}, Usage.id())

    assert 1 == CLI.run(["knowledge", "review", target["key"]] ++ options)

    assert {:ok, ^after_correction} =
             Collection.execute(collection, namespace, %{"op" => "snapshot"}, Usage.id())

    correction_journals = Path.wildcard(Path.join(home, "knowledge-management/*.jsonl"))
    assert 0 == CLI.run(["knowledge", "review", key] ++ options)

    [accepted_journal] =
      Path.wildcard(Path.join(home, "knowledge-management/*.jsonl")) -- correction_journals

    assert {:ok, %{events: accepted_events, tail: :none}} = Journal.read_path(accepted_journal)
    [event] = Enum.filter(accepted_events, &(&1["type"] == "pending_proposal_accepted"))
    assert PendingAcceptance.valid_event?(event)
    assert event["facts"]["text"] === text and event["facts"]["source_proof"] === proof
    assert {:ok, note_key} = PendingAcceptance.accepted_note_key(event)
    assert read.(note_key)["value"]["kind"] === "accepted_decision"
    assert read.(note_key)["value"]["text"] === text

    File.write!(
      Path.join(root, "pending-correction-success.json"),
      Jason.encode!(%{"accepted_note_key" => note_key}),
      [:exclusive]
    )
  end
end

IO.puts("PUBLIC_SESSION_PENDING_CORRECTION_#{String.upcase(mode)}_PASSED")
