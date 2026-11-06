ExUnit.start(autorun: false)
import ExUnit.Assertions
Code.require_file("provider_fixture.ex", __DIR__)
Code.require_file("planning_result_gate.ex", __DIR__)
{:ok, _} = Application.ensure_all_started(:ipse)

for key <- ~w(IPSE_PROVIDER IPSE_MODEL IPSE_CONFIG IPSE_PROFILE IPSE_SANDBOX IPSE_SUBAGENTS),
    do: System.delete_env(key)

[root, scenario] = System.argv()

assert scenario in ~w(plan_assistant plan_assistant_stale plan_assistant_revoke plan_assistant_withdraw plan_assistant_root_changed plan_assistant_unknown)

home = Path.join(root, "home")
cwd = Path.join(root, "work")
dir = Path.join(home, "sessions")
File.mkdir_p!(home)
File.mkdir_p!(cwd)
File.chmod!(home, 0o700)
System.put_env("IPSE_HOME", home)
config_path = Path.join(home, "config.json")

{:ok, listener} =
  :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

{:ok, {{127, 0, 0, 1}, port}} = :inet.sockname(listener)
base = "http://127.0.0.1:#{port}"
server_owner = self()
server_finished = make_ref()

server =
  Task.async(fn ->
    result =
      try do
        turns = if scenario == "plan_assistant_stale", do: 2, else: 1

        for _ <- 1..turns do
          {:ok, socket} = :gen_tcp.accept(listener, 60_000)

          try do
            {_headers, bytes} = Ipse.Test.ProviderFixture.request(socket, "")
            request = Jason.decode!(bytes)
            assert request["model"] == "synthetic"

            assert Enum.any?(
                     request["messages"],
                     &(&1["role"] == "user" and String.starts_with?(&1["content"], "Suggest "))
                   )

            body =
              Jason.encode!(%{
                "model" => "synthetic",
                "message" => %{
                  "role" => "assistant",
                  "content" => "Use a synthetic local fixture."
                },
                "done" => true,
                "prompt_eval_count" => 1,
                "eval_count" => 1
              }) <> "\n"

            :ok =
              :gen_tcp.send(
                socket,
                "HTTP/1.1 200 Fixture\r\ncontent-type: application/x-ndjson\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                  body
              )

            :ok
          after
            :gen_tcp.close(socket)
          end
        end
      after
        :gen_tcp.close(listener)
      end

    receive do
      {^server_finished, ^server_owner} -> result
    after
      60_000 -> flunk("terminal did not return before synthetic server handoff")
    end
  end)

File.write!(
  config_path,
  Jason.encode!(%{
    "version" => 1,
    "profiles" => %{
      "local" => %{
        "provider" => "ollama",
        "model" => "synthetic",
        "base_url" => base,
        "timeout_ms" => 90_000,
        "max_output_tokens" => 128
      }
    },
    "roles" => %{"main" => "local"},
    "inference_services" => %{"local" => %{"version" => 1, "origins" => [base]}}
  })
)

File.chmod!(config_path, 0o600)
options = ["--cwd", cwd, "--config", config_path, "--no-project-config"]
assert 0 == Ipse.CLI.run(["knowledge", "enable"] ++ options)

defmodule AssistantPlanningResultBoundary do
  use GenServer

  def start(writer, observer, kind),
    do:
      GenServer.start(__MODULE__, %{writer: writer, observer: observer, kind: kind, pending: nil})

  def init(state), do: {:ok, state}

  def handle_call(
        {:append, _, %{"type" => "planning_decision_save_started", "version" => 2}} = request,
        from,
        %{kind: :stage, writer: writer, observer: observer, pending: nil} = state
      ) do
    result = GenServer.call(writer, request, 5_000)

    unless result == :ok or match?({:ok, %{}}, result),
      do: raise("stage intent was not durably appended: #{inspect(result)}")

    send(observer, {:stage_committed_before_dispatch, self()})
    {:noreply, %{state | pending: {from, result}}}
  end

  def handle_call(request, _from, %{writer: writer} = state),
    do: {:reply, GenServer.call(writer, request, 5_000), state}

  def handle_cast(:release, %{pending: {from, result}} = state) do
    GenServer.reply(from, result)
    {:noreply, %{state | pending: nil}}
  end
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

assert {:ok, %{route: %{"endpoint" => endpoint, "provider" => "ollama"}}} =
         Ipse.InferenceDispatch.selection(runtime, runtime, "main", nil)

assert endpoint == base <> "/api/chat"

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
watcher_owner = self()
watcher_finished = make_ref()

watcher =
  Task.async(fn ->
    wait = fn wait, remaining ->
      unless File.exists?(Path.join(root, "plan-decision-exited")) do
        assert remaining > 0
        Process.sleep(10)
        wait.(wait, remaining - 1)
      end
    end

    wait.(wait, 2500)

    expected_status =
      if scenario == "plan_assistant_stale",
        do: "source_unavailable_for_save",
        else: "ready_for_save_review"

    assert [%{"text" => "Use a synthetic local fixture.", "status" => ^expected_status}] =
             Ipse.Session.planning_decisions(session)

    {:ok, snapshot} = Ipse.Extension.Consent.existing_snapshot(control, binding["project_id"])
    assert snapshot["operations"] == %{}

    result =
      if scenario in ~w(plan_assistant_revoke plan_assistant_withdraw plan_assistant_root_changed plan_assistant_unknown) do
        session_state = :sys.get_state(session)
        writer = session_state.journal_writer
        kind = if scenario == "plan_assistant_unknown", do: :result, else: :stage

        proxy =
          if kind == :stage do
            {:ok, proxy} = AssistantPlanningResultBoundary.start(writer, self(), kind)
            :sys.replace_state(writer, &%{&1 | owner: proxy})
            :sys.replace_state(session, &%{&1 | journal_writer: proxy})
            proxy
          else
            assert :ok = :sys.install(writer, {Ipse.Test.PlanningResultGate.hook(self()), nil})
            nil
          end

        File.write!(Path.join(root, "plan-decision-proceed"), "ready")

        if kind == :stage do
          assert_receive {:stage_committed_before_dispatch, ^proxy}, 15_000

          case scenario do
            "plan_assistant_revoke" ->
              assert {:ok, _} =
                       Ipse.Extension.Consent.revoke(
                         control,
                         binding["project_id"],
                         snapshot["epoch"]
                       )

            "plan_assistant_withdraw" ->
              original = Path.join(dir, id <> ".jsonl")
              held = Path.join(root, "original-session-held")
              File.rename!(original, held)
              File.cp!(held, original)
              File.chmod!(original, 0o600)

            "plan_assistant_root_changed" ->
              request = %{
                "op" => "commit",
                "expected_generation" => 0,
                "advance_floor" => false,
                "changes" => [
                  %{
                    "key" => "fixture.root-change",
                    "expected_revision" => 0,
                    "value" => %{"synthetic" => true}
                  }
                ]
              }

              assert {:ok, %{"generation" => 1}} =
                       Ipse.Extension.Collection.execute(
                         collection,
                         namespace,
                         request,
                         Ipse.Usage.id()
                       )
          end

          GenServer.cast(proxy, :release)
          %{proxy: proxy, writer: writer, interposed: scenario}
        else
          assert_receive {:managed_result_after_dispatch, ^writer, action_result}, 15_000
          assert Ipse.Extension.Actions.valid_result?(action_result)
          [%{"key" => target}] = get_in(action_result, ["request", "request", "changes"])
          assert String.starts_with?(target, "pending.")
          monitor = Process.monitor(session)
          writer_monitor = Process.monitor(writer)
          guard_monitor = Process.monitor(session_state.lock_guard)
          Process.exit(session, :kill)
          assert_receive {:DOWN, ^monitor, :process, ^session, :killed}, 5_000
          Process.exit(writer, :kill)
          assert_receive {:DOWN, ^writer_monitor, :process, ^writer, _}, 5_000
          assert_receive {:DOWN, ^guard_monitor, :process, _, _}, 15_000

          {:ok, %{"record" => record}} =
            Ipse.Extension.Collection.execute(
              collection,
              namespace,
              %{"op" => "get", "key" => target},
              Ipse.Usage.id()
            )

          assert is_map(record)
          assert record["operation_id"] == action_result["operation_id"]
          assert is_integer(record["revision"]) and record["revision"] > 0

          {:ok, collection_before_resume} =
            Ipse.Extension.Collection.execute(
              collection,
              namespace,
              %{"op" => "snapshot"},
              Ipse.Usage.id()
            )

          {:ok, control_before_resume} =
            Ipse.Extension.Consent.existing_snapshot(control, binding["project_id"])

          assert %{"operation" => "notes.propose"} =
                   control_before_resume["operations"][action_result["operation_id"]]

          %{
            proxy: proxy,
            writer: writer,
            unknown_checkpoint: %{
              target: target,
              record: record,
              collection: collection_before_resume,
              control: control_before_resume,
              operation_id: action_result["operation_id"]
            }
          }
        end
      else
        File.write!(Path.join(root, "plan-decision-proceed"), "ready")
        %{}
      end

    receive do
      {^watcher_finished, ^watcher_owner} -> result
    after
      60_000 -> flunk("terminal did not return before synthetic watcher handoff")
    end
  end)

IO.puts("IPSE_PLAN_DECISION_READY")
terminal_status = Ipse.CLI.Terminal.interact(session, Process.monitor(session), true, nil, cwd)
send(server.pid, {server_finished, self()})

assert Task.await(server, 5_000) ==
         List.duplicate(:ok, if(scenario == "plan_assistant_stale", do: 2, else: 1))

send(watcher.pid, {watcher_finished, self()})
watcher_result = Task.await(watcher, 40_000)

if scenario == "plan_assistant_withdraw" do
  assert terminal_status in [0, 1]
  original = Path.join(dir, id <> ".jsonl")
  File.rm!(original)
  File.rename!(Path.join(root, "original-session-held"), original)
else
  if scenario == "plan_assistant_unknown",
    do: assert(terminal_status == 1),
    else: assert(terminal_status == 0)
end

if scenario in ~w(plan_assistant_revoke plan_assistant_withdraw plan_assistant_root_changed plan_assistant_unknown) do
  %{proxy: proxy, writer: writer} = watcher_result

  if scenario != "plan_assistant_unknown" do
    assert watcher_result.interposed == scenario

    if Process.alive?(session) and Process.alive?(writer) do
      :sys.replace_state(writer, &%{&1 | owner: session})
      :sys.replace_state(session, &%{&1 | journal_writer: writer})
    end

    if Process.alive?(proxy), do: GenServer.stop(proxy)
  end
end

unknown_checkpoint = watcher_result[:unknown_checkpoint]
if scenario == "plan_assistant_unknown", do: assert(is_map(unknown_checkpoint))

{:ok, events} = Ipse.Journal.load(dir, id)
assert {:ok, saved} = Ipse.Session.Saved.restore(events, id)
[decision] = Enum.filter(events, &(&1["type"] == "planning_decision_accepted"))
stages = Enum.filter(events, &(&1["type"] == "planning_decision_save_started"))
assert decision["version"] == 2

assert length(stages) ==
         if(
           scenario in ~w(plan_assistant plan_assistant_revoke plan_assistant_withdraw plan_assistant_root_changed plan_assistant_unknown),
           do: 1,
           else: 0
         )

assert Enum.all?(stages, &(&1["version"] == 2))
assert decision["source_proof"]["origin"] == "assistant_proposal"
assert saved.planning_decisions[decision["id"]].attempted == (stages != [])
refute Enum.any?(events, &(&1["type"] == "operator_assertion"))

if scenario == "plan_assistant_unknown" do
  assert Enum.any?(
           events,
           &(&1["type"] == "extension_action_intent" and
               get_in(&1, ["request", "op"]) == "collection.managed")
         )

  refute Enum.any?(
           events,
           &(&1["type"] == "extension_action_result" and
               get_in(&1, ["request", "op"]) == "collection.managed")
         )

  assert %{"type" => "extension_action_intent", "request" => %{"op" => "collection.managed"}} =
           saved.extension_state.action
end

if Process.alive?(session), do: assert(:ok == Ipse.Session.close_confirmed(session))

{:ok, before_resume} = Ipse.Journal.load(dir, id)

{:ok, resumed} =
  DynamicSupervisor.start_child(
    Ipse.Sessions,
    {Ipse.Session, config: runtime, cwd: cwd, state_dir: dir, id: id, subscriber: self()}
  )

expected_resume_status =
  cond do
    stages != [] -> "save_started_inspect_journal"
    scenario == "plan_assistant_stale" -> "source_unavailable_for_save"
    true -> "ready_for_save_review"
  end

assert [%{"status" => ^expected_resume_status}] = Ipse.Session.planning_decisions(resumed)
assert :ok == Ipse.Session.close_confirmed(resumed)
{:ok, after_resume} = Ipse.Journal.load(dir, id)

for type <-
      ~w(planning_decision_save_started extension_invocation_intent extension_action_intent extension_action_result) do
  assert Enum.count(after_resume, &(&1["type"] == type)) ==
           Enum.count(before_resume, &(&1["type"] == type))
end

{:ok, snapshot} =
  Ipse.Extension.Collection.execute(collection, namespace, %{"op" => "snapshot"}, Ipse.Usage.id())

if unknown_checkpoint do
  {:ok, %{"record" => record}} =
    Ipse.Extension.Collection.execute(
      collection,
      namespace,
      %{"op" => "get", "key" => unknown_checkpoint.target},
      Ipse.Usage.id()
    )

  assert record == unknown_checkpoint.record
  assert snapshot == unknown_checkpoint.collection
  {:ok, after_control} = Ipse.Extension.Consent.existing_snapshot(control, binding["project_id"])
  assert after_control["operations"] == unknown_checkpoint.control["operations"]

  assert Enum.any?(
           before_resume,
           &(&1["type"] == "extension_action_intent" and
               &1["operation_id"] == unknown_checkpoint.operation_id)
         )
end

{:ok, page} =
  Ipse.Extension.Collection.scan_visible(
    collection,
    namespace,
    %{"op" => "scan", "after" => nil, "generation" => snapshot["generation"], "limit" => 8},
    Ipse.Usage.id()
  )

if scenario != "plan_assistant" do
  cond do
    scenario == "plan_assistant_root_changed" ->
      assert [%{"key" => "fixture.root-change"}] = page["records"]

    scenario != "plan_assistant_unknown" ->
      assert page["records"] == []

    true ->
      :ok
  end

  IO.puts("ASSISTANT_PLANNING_JOURNEY_PASSED")
  System.halt(0)
end

[proposal] = page["records"]
assert String.starts_with?(proposal["key"], "pending.")
assert proposal["value"]["text"] == decision["text"]
assert proposal["value"]["evidence"]["sources"] == [decision["source_proof"]]
before_management = Path.wildcard(Path.join(home, "knowledge-management/*.jsonl"))
assert 0 == Ipse.CLI.run(["knowledge", "review", proposal["key"], "--state-dir", dir] ++ options)

[management_path] =
  Path.wildcard(Path.join(home, "knowledge-management/*.jsonl")) -- before_management

{:ok, %{events: management, tail: :none}} = Ipse.Journal.read_path(management_path)
[acceptance] = Enum.filter(management, &(&1["type"] == "pending_proposal_accepted"))
assert Ipse.Session.PendingAcceptance.valid_event?(acceptance)
assert acceptance["facts"]["pending_key"] == proposal["key"]
assert acceptance["facts"]["source_proof"] == decision["source_proof"]
assert {:ok, note_key} = Ipse.Session.PendingAcceptance.accepted_note_key(acceptance)

assert {:ok, %{"record" => note}} =
         Ipse.Extension.Collection.execute(
           collection,
           namespace,
           %{"op" => "get", "key" => note_key},
           Ipse.Usage.id()
         )

assert note["value"]["kind"] == "accepted_decision"
assert note["value"]["text"] == decision["text"]
assert note["value"]["source_proof"] == decision["source_proof"]

assert {:ok, expected} =
         Ipse.Session.PendingAcceptance.accepted_values(
           acceptance,
           note["value"]["valid_until_ms"]
         )

assert note["value"] == expected["note"]

assert {:ok, %{"record" => link}} =
         Ipse.Extension.Collection.execute(
           collection,
           namespace,
           %{"op" => "get", "key" => expected["link_key"]},
           Ipse.Usage.id()
         )

assert link["value"] == expected["link"]
IO.puts("ASSISTANT_PLANNING_JOURNEY_PASSED")
