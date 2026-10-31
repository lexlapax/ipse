ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
[root, scenario] = System.argv()

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
config = if scenario == "mode", do: Map.put(config, :execution_mode, :planning), else: config
dir = Path.join(home, "sessions")

assert {:ok, session} =
         DynamicSupervisor.start_child(
           Ipse.Sessions,
           {Ipse.Session, [config: config, cwd: cwd, state_dir: dir, subscriber: self()]}
         )

id = Ipse.Session.info(session).id
admission = :sys.get_state(session).config.semantic_admission
assert admission["status"] == "active"
assert {:ok, channel} = Ipse.Session.open_input_channel(session, self())

text = "Synthetic new operator statement"

command =
  case scenario do
    "relation" -> "/correct note." <> String.duplicate("a", 64) <> " " <> text
    "supersede" -> "/supersede note." <> String.duplicate("a", 64) <> " " <> text
    _ -> "/remember ordinary " <> text
  end

File.write!(Path.join(root, "supersession-input-1"), command)
IO.write("IPSE_SUPERSESSION_READ_1> ")

assert {:ok, ^command, witness} =
         Ipse.Session.observe_channel(session, channel, %{"kind" => "prompt"}, 30_000)

assert {:ok, ticket} = Ipse.Session.stage_input(session, channel, command, witness)

if scenario == "foreign" do
  task = Task.async(fn -> Ipse.Session.prepare_assertion(session, channel, command, ticket) end)
  assert {:error, :operator_assertion_refused} = Task.await(task)
end

if scenario in ["relation", "supersede", "mode"] do
  assert {:error, :operator_assertion_refused} =
           Ipse.Session.prepare_assertion(session, channel, command, ticket)
else
  assert {:ok, %{"render_id" => render}} =
           Ipse.Session.prepare_assertion(session, channel, command, ticket)

  assert :sys.get_state(session).assertion_render.purpose == nil

  if scenario == "generation" do
    :sys.replace_state(session, &%{&1 | input_generation: Ipse.Usage.id()})
  end

  if scenario == "source_generation" do
    :sys.replace_state(session, fn s ->
      put_in(s.assertion_render.source_generation, "different-fixture-generation")
    end)
  end

  if scenario == "selection" do
    :sys.replace_state(session, fn s ->
      put_in(s.config.semantic_admission["status"], "inactive")
    end)
  end

  assert {:ok, input, review_witness} =
           Ipse.Session.observe_channel(
             session,
             channel,
             %{"kind" => "assertion", "render_id" => render},
             30_000
           )

  result = Ipse.Session.accept_assertion_observed(session, channel, render, input, review_witness)

  if scenario in ["positive", "foreign"] do
    assert result == :ok
    assert_receive {:ipse, ^session, {:done, :error}}, 20_000
  else
    assert result == {:error, :operator_assertion_refused}
  end
end

assert {:ok, events} = Ipse.Journal.load(dir, id)
assertions = Enum.filter(events, &(&1["type"] == "operator_assertion"))

if scenario in ["positive", "foreign"] do
  assert [%{"text" => ^text, "category" => "ordinary"} = assertion] = assertions
  assert Ipse.Session.OperatorAssertion.valid_event?(assertion, id)
else
  assert assertions == []
end

refute Enum.any?(events, &(&1["type"] == "inference_dispatch_intent"))
assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
assert :ok = Ipse.Session.close_confirmed(session)
IO.puts("REMEMBER_INTAKE_#{String.upcase(scenario)}_PASSED")
