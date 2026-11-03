ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)

for key <- ~w(IPSE_PROVIDER IPSE_MODEL IPSE_CONFIG IPSE_PROFILE IPSE_SANDBOX IPSE_SUBAGENTS),
    do: System.delete_env(key)

[root, scenario] = System.argv()
home = Path.join(root, "home")
cwd = Path.join(root, "work")
dir = Path.join(home, "sessions")
File.mkdir_p!(home)
File.mkdir_p!(cwd)
File.chmod!(home, 0o700)
System.put_env("IPSE_HOME", home)
config_path = Path.join(home, "config.json")

File.write!(
  config_path,
  Jason.encode!(%{"version" => 1, "settings" => %{"provider" => "demo", "model" => "scripted"}})
)

File.chmod!(config_path, 0o600)

assert 0 ==
         Ipse.CLI.run([
           "knowledge",
           "enable",
           "--cwd",
           cwd,
           "--config",
           config_path,
           "--no-project-config"
         ])

defmodule PlanningDecisionUnexpectedModel do
  def complete(_, _, _, _), do: raise("planning decision fixture must not call a model")
end

defmodule PlanningDecisionBoundaryWriter do
  use GenServer

  def start(writer, observer, mode), do: GenServer.start(__MODULE__, {writer, observer, mode})
  def init(state), do: {:ok, state}

  def handle_call(
        {:append, _, %{"type" => "planning_decision_save_started"}} = request,
        _from,
        {writer, observer, :interrupt} = state
      ) do
    :ok = GenServer.call(writer, request, 5_000)
    send(observer, {:planning_save_started, self()})
    {:noreply, state}
  end

  def handle_call(
        {:source_query, {:assertion_request, _}},
        _from,
        {_, _, :query_failure} = state
      ),
      do: {:reply, {:error, :source_index_refused}, state}

  def handle_call(request, _from, {writer, _, _} = state),
    do: {:reply, GenServer.call(writer, request, 5_000), state}
end

{:ok, effective} =
  Ipse.Config.resolve(cwd, home, [config: config_path, project_config: false], %{})

client = %{
  workspace: cwd,
  home: home,
  auth_dir: Path.join(home, "auth"),
  operator_home: root,
  mcp_config: nil,
  base_url: nil,
  operator_questions: false,
  accept_edits: false,
  approval: :ask,
  approval_origin: :interactive,
  headless: false
}

{:ok, runtime} = Ipse.Config.runtime(effective, client)
runtime = Map.put(runtime, :provider_module, PlanningDecisionUnexpectedModel)

{:ok, session} =
  DynamicSupervisor.start_child(
    Ipse.Sessions,
    {Ipse.Session, config: runtime, cwd: cwd, state_dir: dir, subscriber: self()}
  )

id = Ipse.Session.info(session).id
{:ok, binding} = Ipse.Extension.ProjectIdentity.existing(home, cwd)
control = Ipse.Extension.SemanticAdmission.control_root(home)
{:ok, initial} = Ipse.Extension.Consent.existing_snapshot(control, binding["project_id"])
namespace = initial["policy"]["settings"]["namespace"]
collection = Ipse.Extension.SemanticAdmission.collection_root(home)

wait_file = fn wait_file, name, remaining ->
  unless File.exists?(Path.join(root, name)) do
    assert remaining > 0
    Process.sleep(10)
    wait_file.(wait_file, name, remaining - 1)
  end
end

{:ok, _watcher} =
  Task.start_link(fn ->
    wait_file.(wait_file, "plan-decision-exited", 2500)
    decisions = Ipse.Session.planning_decisions(session)

    if scenario in ["plan_cancel", "plan_stale"] do
      assert decisions == []
    else
      assert [%{"text" => "Use a synthetic local fixture.", "status" => "ready_for_save_review"}] =
               decisions

      [decision] = decisions
      {:ok, before_events} = Ipse.Journal.load(dir, id)
      refute Enum.any?(before_events, &(&1["type"] == "operator_assertion"))
      {:ok, source_window} = Ipse.Session.SourceWindow.restore(before_events, id)

      assert {:error, _} =
               Ipse.Session.SourceIndex.assertion_request(source_window.index, decision["id"])
    end

    {:ok, before_save} = Ipse.Extension.Consent.existing_snapshot(control, binding["project_id"])
    assert before_save["operations"] == %{}

    if scenario == "plan_revoked" do
      assert {:ok, _} =
               Ipse.Extension.Consent.revoke(control, binding["project_id"], before_save["epoch"])
    end

    if scenario == "plan_source" do
      original = Path.join(dir, id <> ".jsonl")
      held = Path.join(root, "original-session-held")
      File.rename!(original, held)
      File.cp!(held, original)
      File.chmod!(original, 0o600)
    end

    if scenario in ["plan_interrupted", "plan_query_failure"] do
      writer = :sys.get_state(session).journal_writer
      mode = if scenario == "plan_interrupted", do: :interrupt, else: :query_failure
      {:ok, proxy} = PlanningDecisionBoundaryWriter.start(writer, self(), mode)
      :sys.replace_state(writer, &%{&1 | owner: proxy})
      :sys.replace_state(session, &%{&1 | journal_writer: proxy})
      File.write!(Path.join(root, "plan-decision-proceed"), "ready")

      if scenario == "plan_interrupted" do
        assert_receive {:planning_save_started, ^proxy}, 15_000
        monitor = Process.monitor(session)
        Process.exit(session, :kill)
        assert_receive {:DOWN, ^monitor, :process, ^session, :killed}, 5_000
        Process.exit(proxy, :kill)
      end
    else
      File.write!(Path.join(root, "plan-decision-proceed"), "ready")
    end

    if scenario == "plan_intake_failure" do
      wait_file.(wait_file, "plan-intake-review-ready", 1500)

      :sys.replace_state(session, fn state ->
        put_in(state.assertion_render.purpose, %{
          "mode" => "invalid",
          "target_key" => "note." <> String.duplicate("0", 64)
        })
      end)

      File.write!(Path.join(root, "plan-intake-interposed"), "ready")
    end
  end)

IO.puts("IPSE_PLAN_DECISION_READY")
terminal_status = Ipse.CLI.Terminal.interact(session, Process.monitor(session), true, nil, cwd)

if scenario == "plan_source" do
  assert terminal_status in [0, 1]
  original = Path.join(dir, id <> ".jsonl")
  File.rm!(original)
  File.rename!(Path.join(root, "original-session-held"), original)
else
  assert terminal_status == if(scenario == "plan_interrupted", do: 1, else: 0)
end

{:ok, events} = Ipse.Journal.load(dir, id)
assert {:ok, saved} = Ipse.Session.Saved.restore(events, id)
accepted = Enum.filter(events, &(&1["type"] == "planning_decision_accepted"))
started = Enum.filter(events, &(&1["type"] == "planning_decision_save_started"))
assert length(accepted) == if(scenario in ["plan_cancel", "plan_stale"], do: 0, else: 1)

assert length(started) ==
         if(
           scenario in [
             "plan_save",
             "plan_revoked",
             "plan_interrupted",
             "plan_query_failure",
             "plan_intake_failure"
           ],
           do: 1,
           else: 0
         )

if scenario in ["plan_save", "plan_revoked", "plan_query_failure", "plan_intake_failure"] do
  [receipt] = accepted
  [assertion] = Enum.filter(events, &(&1["type"] == "operator_assertion"))
  assert assertion["planning_decision"] == receipt
  assert assertion["text"] == receipt["text"]
  assert assertion["category"] == "ordinary"
  assert saved.planning_decisions[receipt["id"]].attempted

  if scenario in ["plan_revoked", "plan_query_failure", "plan_intake_failure"] do
    assert saved.planning_decisions[receipt["id"]].refused

    assert Enum.any?(
             events,
             &(&1["type"] == "planning_decision_save_result" and
                 &1["status"] == "refused_unstarted")
           )

    refute Enum.any?(events, &(&1["type"] == "extension_invocation_intent"))
  end
end

{:ok, current} =
  Ipse.Extension.Collection.execute(collection, namespace, %{"op" => "snapshot"}, Ipse.Usage.id())

{:ok, page} =
  Ipse.Extension.Collection.scan_visible(
    collection,
    namespace,
    %{"op" => "scan", "after" => nil, "generation" => current["generation"], "limit" => 8},
    Ipse.Usage.id()
  )

if scenario == "plan_save" do
  [note] = page["records"]
  assert note["value"]["text"] == "Use a synthetic local fixture."
  [proof] = note["value"]["evidence"]["sources"]
  assert proof["origin"] == "native_operator_assertion"
  assert proof["kind"] == "input.assertion.ordinary"
  [assertion] = Enum.filter(events, &(&1["type"] == "operator_assertion"))
  assert proof["receipt_sha256"] == Ipse.JSON.digest([assertion])
  assert assertion["planning_decision"] == hd(accepted)
else
  assert page["records"] == []
end

if scenario == "plan_query_failure" do
  proxy = :sys.get_state(session).journal_writer
  {writer, _, :query_failure} = :sys.get_state(proxy)
  :sys.replace_state(writer, &%{&1 | owner: session})
  :sys.replace_state(session, &%{&1 | journal_writer: writer})
  GenServer.stop(proxy)
end

if scenario not in ["plan_interrupted", "plan_source"],
  do: assert(:ok = Ipse.Session.close_confirmed(session))

if scenario == "plan_source" and Process.alive?(session) do
  monitor = Process.monitor(session)
  Process.exit(session, :kill)
  assert_receive {:DOWN, ^monitor, :process, ^session, :killed}, 5_000
end

{:ok, before_resume} = Ipse.Journal.load(dir, id)

{:ok, resumed} =
  DynamicSupervisor.start_child(
    Ipse.Sessions,
    {Ipse.Session, config: runtime, cwd: cwd, state_dir: dir, id: id, subscriber: self()}
  )

if scenario in ["plan_cancel", "plan_stale"] do
  assert Ipse.Session.planning_decisions(resumed) == []
else
  [retained] = Ipse.Session.planning_decisions(resumed)

  expected =
    cond do
      scenario in ["plan_revoked", "plan_query_failure", "plan_intake_failure"] ->
        "save_refused_before_publication"

      scenario in ["plan_save", "plan_interrupted"] ->
        "save_started_inspect_journal"

      true ->
        "ready_for_save_review"
    end

  assert retained["status"] == expected
end

assert :ok = Ipse.Session.close_confirmed(resumed)
{:ok, after_resume} = Ipse.Journal.load(dir, id)

assert Enum.count(after_resume, &(&1["type"] == "planning_decision_save_started")) ==
         Enum.count(before_resume, &(&1["type"] == "planning_decision_save_started"))

assert Enum.count(after_resume, &(&1["type"] == "operator_assertion")) ==
         Enum.count(before_resume, &(&1["type"] == "operator_assertion"))

IO.puts("PLANNING_DECISION_JOURNEY_PASSED")
