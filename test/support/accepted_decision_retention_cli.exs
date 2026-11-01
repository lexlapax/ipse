ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
[root, mode] = System.argv()
assert mode in ~w(pin cancel automatic day_duration short_duration)
alias Ipse.{CLI, Journal, Usage}
alias Ipse.Extension.{Collection, Consent, ProjectIdentity, SemanticAdmission}
alias Ipse.Extension.Collection.ObservedRead

home = Path.join(root, "home")
cwd = Path.join(root, "work")
System.put_env("IPSE_HOME", home)
fixture = root |> Path.join("accepted-retention.json") |> File.read!() |> Jason.decode!()
collection = SemanticAdmission.collection_root(home)
namespace = fixture["namespace"]
options = ["--cwd", cwd, "--config", Path.join(home, "config.json"), "--no-project-config"]
assert {:ok, binding} = ProjectIdentity.existing(home, cwd)
control = SemanticAdmission.control_root(home)

read = fn key ->
  assert {:ok, result} =
           Collection.execute(collection, namespace, %{"op" => "get", "key" => key}, Usage.id())

  result["record"]
end

observe = fn ->
  ProjectIdentity.with_existing_domain_auth(
    home,
    cwd,
    binding,
    %{namespace: namespace, format: "managed-metadata-v3"},
    fn cap, catalog ->
      ObservedRead.with_managed_note_record(
        collection,
        namespace,
        %{"op" => "get_record", "key" => fixture["key"]},
        cap,
        catalog,
        fixture["recipe"],
        &{:ok, &1}
      )
    end
  )
end

target = read.(fixture["key"])
link = read.(fixture["link_key"])
peer = read.(fixture["peer_key"])
assert target["value"]["kind"] == "accepted_decision"
assert {:ok, observed_before} = observe.()
assert {:ok, before} = Consent.existing_snapshot(control, binding["project_id"])
sessions = Map.new(Path.wildcard(fixture["history_dir"] <> "/*.jsonl"), &{&1, File.read!(&1)})
management = Path.join(home, "knowledge-management")
old_journals = Path.wildcard(management <> "/*.jsonl")

selected =
  case mode do
    "pin" -> ["--policy", "pin"]
    "cancel" -> ["--policy", "automatic"]
    "automatic" -> ["--policy", "automatic"]
    "day_duration" -> ["--policy", "duration", "--days", "1"]
    "short_duration" -> nil
  end

result =
  if selected do
    assert CLI.run(["knowledge", "retention", fixture["key"]] ++ selected ++ options) ==
             if(mode == "cancel", do: 1, else: 0)
  else
    config = %{home: home, approval: :ask, approval_origin: :interactive, headless: false}

    assert {:ok, result} =
             CLI.Knowledge.Management.retain(config, cwd, fixture["key"], %{
               "kind" => "duration",
               "duration_ms" => 2000
             })

    result
  end

assert read.(fixture["key"]) == target
assert read.(fixture["link_key"]) == link
assert read.(fixture["peer_key"]) == peer
assert {:ok, observed_after} = observe.()

assert observed_after["metadata"]["first_admitted_ms"] ==
         observed_before["metadata"]["first_admitted_ms"]

if mode == "cancel" do
  assert observed_after == observed_before
  assert {:ok, ^before} = Consent.existing_snapshot(control, binding["project_id"])
else
  choice = observed_after["metadata"]["choice"]
  assert choice["kind"] == "native_management"
  assert choice["target_value_sha256"] == target["sha256"]

  if mode == "pin" do
    assert observed_after["metadata"]["category"] == "pin"
    assert observed_after["metadata"]["valid_until_ms"] == nil
  else
    assert observed_after["metadata"]["category"] == "ordinary"

    age =
      case mode do
        "automatic" -> 90 * 86_400_000
        "day_duration" -> 86_400_000
        "short_duration" -> 2000
      end

    assert observed_after["metadata"]["valid_until_ms"] == choice["observed_at_ms"] + age
  end

  assert {:ok, current} = Consent.existing_snapshot(control, binding["project_id"])
  assert [id] = Map.keys(current["operations"]) -- Map.keys(before["operations"])
  assert current["operations"][id]["status"] == "settled"
  assert current["operations"][id]["operation"] == "collection.retention"
  assert [journal] = Path.wildcard(management <> "/*.jsonl") -- old_journals
  assert {:ok, %{events: events, tail: :none}} = Journal.read_path(journal)
  assert [intent] = Enum.filter(events, &(&1["type"] == "managed_lifecycle_intent"))
  assert intent["facts"]["kind"] == "managed_accepted_decision_retention"
  assert intent["facts"]["target"] == target

  assert [%{"status" => "settled"}] =
           Enum.filter(events, &(&1["type"] == "managed_lifecycle_result"))

  for metric <- ~w(model_calls download_bytes cost_nanos),
      do: assert(current["operations"][id]["actual"][metric] == 0)
end

if mode == "short_duration" do
  deadline = result["receipt"]["publication"]["normalization"]["valid_until_ms"]
  wait = deadline - System.system_time(:millisecond) + 10
  assert wait in 1..2010
  Process.sleep(wait)
  assert System.system_time(:millisecond) >= deadline
  assert {:ok, before_expired_pin} = Consent.existing_snapshot(control, binding["project_id"])
  config = %{home: home, approval: :ask, approval_origin: :interactive, headless: false}

  assert {:error, _} =
           CLI.Knowledge.Management.retain(config, cwd, fixture["key"], %{"kind" => "pin"})

  assert read.(fixture["key"]) == target
  assert {:ok, ^before_expired_pin} = Consent.existing_snapshot(control, binding["project_id"])
  assert CLI.run(["knowledge", "disable"] ++ options) == 0

  source =
    Path.join(fixture["history_dir"], target["value"]["source_proof"]["session_id"] <> ".jsonl")

  held = source <> ".retention-unavailable"
  assert {:ok, lock} = Ipse.Runner.lock(Path.rootname(source) <> ".lock")
  File.rename!(source, held)
  assert :ok = Ipse.Runner.unlock(lock)

  try do
    assert CLI.run(["knowledge", "expire", fixture["key"]] ++ options) == 0
  after
    assert {:ok, lock} = Ipse.Runner.lock(Path.rootname(source) <> ".lock")
    File.rename!(held, source)
    assert :ok = Ipse.Runner.unlock(lock)
  end

  assert read.(fixture["key"]) == nil
  assert read.(fixture["link_key"]) == link
  assert read.(fixture["peer_key"]) == peer
end

assert sessions ==
         Map.new(Path.wildcard(fixture["history_dir"] <> "/*.jsonl"), &{&1, File.read!(&1)})

IO.puts("NATIVE_ACCEPTED_RETENTION_#{String.upcase(mode)}_PASSED")
