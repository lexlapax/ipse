ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
[root, "terminal"] = System.argv()

for key <- ~w(IPSE_PROVIDER IPSE_MODEL IPSE_CONFIG IPSE_PROFILE IPSE_SANDBOX IPSE_SUBAGENTS),
    do: System.delete_env(key)

home = Path.join(root, "home")
cwd = Path.join(root, "project")

for path <- [home, cwd] do
  File.mkdir_p!(path)
  File.chmod!(path, 0o700)
end

System.put_env("IPSE_HOME", home)
config_path = Path.join(home, "config.json")

File.write!(
  config_path,
  Jason.encode!(%{"version" => 1, "settings" => %{"provider" => "demo", "model" => "scripted"}})
)

File.chmod!(config_path, 0o600)

assert Ipse.CLI.run([
         "knowledge",
         "enable",
         "--cwd",
         cwd,
         "--config",
         config_path,
         "--no-project-config"
       ]) == 0

client = %{
  workspace: cwd,
  home: home,
  auth_dir: Path.join(home, "auth"),
  operator_home: root,
  mcp_config: nil,
  base_url: nil,
  operator_questions: true,
  accept_edits: false,
  approval: :ask,
  approval_origin: :interactive,
  headless: false
}

{:ok, effective} =
  Ipse.Config.resolve(cwd, home, [config: config_path, project_config: false], %{})

{:ok, config} = Ipse.Config.runtime(effective, client)
dir = Path.join(home, "sessions")

assert {:ok, session} =
         DynamicSupervisor.start_child(
           Ipse.Sessions,
           {Ipse.Session, [config: config, cwd: cwd, state_dir: dir, subscriber: self()]}
         )

id = Ipse.Session.info(session).id
admission = :sys.get_state(session).config.semantic_admission
assert admission["status"] == "active"

text = "SYNTHETIC_TERMINAL_STATEMENT"
File.write!(Path.join(root, "supersession-terminal-command"), "/remember ordinary " <> text)
IO.puts("IPSE_SUPERSESSION_TERMINAL_READY")
assert Ipse.CLI.Terminal.interact(session, Process.monitor(session), true, nil, cwd) == 0
assert {:ok, events} = Ipse.Journal.load(dir, id)
IO.puts("TERMINAL_REMEMBER_EVENTS " <> Jason.encode!(events))

assert [%{"text" => ^text} = assertion] =
         Enum.filter(events, &(&1["type"] == "operator_assertion"))

assert Ipse.Session.OperatorAssertion.valid_event?(assertion, id)
refute Enum.any?(events, &(&1["type"] in ~w(inference_dispatch_intent request_admitted)))
assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
collection = Ipse.Extension.SemanticAdmission.collection_root(home)
namespace = admission["pin"]["namespace"]

assert {:ok, snapshot} =
         Ipse.Extension.Collection.execute(
           collection,
           namespace,
           %{"op" => "snapshot"},
           Ipse.Usage.id()
         )

assert {:ok, page} =
         Ipse.Extension.Collection.scan_visible(
           collection,
           namespace,
           %{
             "op" => "scan",
             "after" => nil,
             "generation" => snapshot["generation"],
             "limit" => 4
           },
           Ipse.Usage.id()
         )

assert [record] = page["records"]
assert record["value"]["text"] == text
control = Ipse.Extension.SemanticAdmission.control_root(home)
assert {:ok, consent} = Ipse.Extension.Consent.snapshot(control, admission["pin"]["project_id"])

intent =
  Enum.find(
    events,
    &(&1["type"] == "extension_action_intent" and
        get_in(&1, ["request", "op"]) == "collection.managed")
  )

assert is_map(intent) and consent["operations"][intent["operation_id"]]["status"] == "settled"
assert snapshot["floor_anchor"] == intent["operation_id"]
assert :ok = Ipse.Session.close_confirmed(session)
IO.puts("TERMINAL_REMEMBER_PUBLICATION_PASSED")
