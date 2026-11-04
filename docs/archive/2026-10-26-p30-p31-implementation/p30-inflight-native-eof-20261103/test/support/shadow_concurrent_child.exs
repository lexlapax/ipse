ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("shadow_concurrent_trace.exs", __DIR__)

for name <-
      ~w(IPSE_PROVIDER IPSE_MODEL IPSE_SANDBOX IPSE_MAX_STEPS IPSE_CONTEXT_BYTES IPSE_COMPACT IPSE_SUBAGENTS IPSE_SUBAGENT_CONCURRENCY IPSE_TIMEOUT_MS IPSE_MAX_OUTPUT_TOKENS IPSE_PROFILE IPSE_CONFIG),
    do: System.delete_env(name)

[pty_root, _scenario] = System.argv()
root = Path.dirname(pty_root)
input = root |> Path.join("cross-process-input.json") |> File.read!() |> Jason.decode!()
home = Path.join(root, "home")
cwd = Path.join(root, "project")
dir = Path.join(root, "sessions")
System.put_env("IPSE_HOME", home)
assert System.pid() != input["parent_os_pid"]
{:ok, binding} = Ipse.Extension.ProjectIdentity.existing(home, cwd)
assert binding["project_id"] == input["project"]
control = Ipse.Extension.SemanticAdmission.control_root(home)
{:ok, snapshot} = Ipse.Extension.Consent.existing_snapshot(control, input["project"])
assert snapshot["epoch"] == input["epoch"]
assert Ipse.JSON.digest([snapshot["policy"]]) == input["policy_sha256"]
assert snapshot["policy"]["limits"]["model_calls"] == 1
assert input["winner_operation_id"] in Map.keys(snapshot["operations"])
assert snapshot["operations"][input["winner_operation_id"]]["status"] == "admitted"

{:ok, effective} =
  Ipse.Config.resolve(
    cwd,
    home,
    [config: Path.join(home, "config.json"), project_config: false],
    %{}
  )

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
tracer = Ipse.Test.ShadowConcurrentTrace.start(control, binding["project_id"])

{:ok, pid} =
  DynamicSupervisor.start_child(
    Ipse.Sessions,
    {Ipse.Session, config: runtime, cwd: cwd, state_dir: dir, subscriber: self()}
  )

id = Ipse.Session.info(pid).id
refute id in input["prior_session_ids"]

{:ok, _watcher} =
  Task.start_link(fn ->
    wait_file = fn wait_file, path, remaining ->
      if File.exists?(path) do
        :ok
      else
        assert remaining > 0
        Process.sleep(10)
        wait_file.(wait_file, path, remaining - 1)
      end
    end

    wait_file.(wait_file, Path.join(pty_root, "managed-approval-input-ready"), 3_000)
    assert :sys.get_state(pid).phase == :managed_approval
    File.write!(Path.join(pty_root, "managed-approval-control-checked"), "checked")

    idle = fn idle, remaining ->
      if :sys.get_state(pid).phase == :idle do
        :ok
      else
        assert remaining > 0
        Process.sleep(10)
        idle.(idle, remaining - 1)
      end
    end

    idle.(idle, 4_000)
    File.write!(Path.join(pty_root, "managed-approval-exit-ready"), "ready")
  end)

IO.puts("IPSE_MANAGED_APPROVAL_CLI_READY")

assert 0 ==
         Ipse.CLI.Terminal.interact(
           pid,
           Process.monitor(pid),
           true,
           "Assess the previously saved synthetic note " <> input["key"] <> ".",
           cwd
         )

{:ok, events} = Ipse.Journal.load(dir, id)

assert [action] =
         Enum.filter(events, fn event ->
           event["type"] == "extension_action_result" and
             get_in(event, ["request", "op"]) == "decision.create"
         end)

assert action["outcome"]["status"] != "ok"
{:ok, current} = Ipse.Extension.Consent.existing_snapshot(control, input["project"])
assert is_nil(current["operations"][action["operation_id"]])
assert current["operations"][input["winner_operation_id"]]["status"] == "admitted"
trace = Ipse.Test.ShadowConcurrentTrace.finish(tracer)
assert Ipse.Test.ShadowConcurrentTrace.reservation_count(trace, action["operation_id"]) == 1

assert [{attempt, observed}] =
         Ipse.Test.ShadowConcurrentTrace.matching(trace, action["operation_id"])

assert attempt.root_matches and attempt.project_matches
assert attempt.result == {:error, :consent_reservation_refused}
assert observed.result == false
assert observed.operation_statuses[input["winner_operation_id"]] == "admitted"
assert observed.project == binding["project_id"]

assert observed.policy_sha256 == input["policy_sha256"] and
         observed.policy_sha256 == attempt.policy_sha256

assert observed.requested == attempt.requested
assert observed.compacted_count == 0 and not observed.overrun
assert observed.settled_calls == 0
assert observed.used["model_calls"] == 1
assert observed.requested["model_calls"] == 1
assert observed.limits["model_calls"] == 1

assert Enum.all?(Ipse.Extension.Consent.resources() -- ["model_calls"], fn name ->
         observed.used[name] + observed.requested[name] <= observed.limits[name]
       end)

assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
intents_before = Enum.count(events, &(&1["type"] == "extension_action_intent"))
assert :ok = Ipse.Session.close_confirmed(pid)

{:ok, reopened} =
  DynamicSupervisor.start_child(
    Ipse.Sessions,
    {Ipse.Session, config: runtime, cwd: cwd, state_dir: dir, id: id, subscriber: self()}
  )

assert :sys.get_state(reopened).phase == :idle
assert :ok = Ipse.Session.close_confirmed(reopened)
{:ok, after_reopen} = Ipse.Journal.load(dir, id)
assert Enum.count(after_reopen, &(&1["type"] == "extension_action_intent")) == intents_before

File.write!(
  Path.join(root, "cross-process-summary.json"),
  Jason.encode!(%{
    "version" => 1,
    "distinct_os_process" => true,
    "distinct_session" => true,
    "same_project_and_policy" => true,
    "matched_contender_operation" => true,
    "strict_monotonic_call_interval" => true,
    "fits" => false,
    "reservation" => "consent_reservation_refused",
    "settled_model_calls" => observed.settled_calls,
    "used_model_calls" => observed.used["model_calls"],
    "requested_model_calls" => observed.requested["model_calls"],
    "model_call_limit" => observed.limits["model_calls"],
    "other_resources_fit" => true
  })
)

IO.puts("SHADOW_CONCURRENT_CHILD_PASSED")
