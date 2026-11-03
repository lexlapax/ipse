ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("provider_fixture.ex", __DIR__)

for key <-
      ~w(IPSE_PROVIDER IPSE_MODEL IPSE_SANDBOX IPSE_MAX_STEPS IPSE_CONTEXT_BYTES IPSE_COMPACT IPSE_SUBAGENTS IPSE_SUBAGENT_CONCURRENCY IPSE_TIMEOUT_MS IPSE_MAX_OUTPUT_TOKENS IPSE_PROFILE IPSE_CONFIG),
    do: System.delete_env(key)

[root, scenario] = System.argv()
preflight_expiry? = scenario == "save_managed_approval_root_shadow_expiry"
release_expiry? = scenario == "save_managed_approval_root_shadow_release_expiry"
expiry? = preflight_expiry? or release_expiry?
denied? = scenario == "save_managed_approval_deny"
revoked? = scenario == "save_managed_approval_revoked_grant"
home = Path.join(root, "home")
cwd = Path.join(root, "project")
dir = Path.join(root, "sessions")
File.mkdir_p!(home)
File.mkdir_p!(cwd)
File.chmod!(home, 0o700)
File.write!(Path.join(cwd, "synthetic.txt"), "Synthetic local observation.\n")
System.put_env("IPSE_HOME", home)

{:ok, listener} =
  :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

{:ok, {_, port}} = :inet.sockname(listener)
base = "http://127.0.0.1:#{port}"
{:ok, calls} = Agent.start_link(fn -> [] end)
{:ok, assessed_key} = Agent.start_link(fn -> nil end)

server =
  Task.async(fn ->
    loop = fn loop, step ->
      case :gen_tcp.accept(listener, 30_000) do
        {:ok, socket} ->
          {headers, bytes} = Ipse.Test.ProviderFixture.request(socket, "")
          request = Jason.decode!(bytes)
          decision? = String.starts_with?(headers, "POST /systemone ")
          Agent.update(calls, &(&1 ++ [{if(decision?, do: :decision, else: :main), request}]))

          {response, next} =
            if decision? do
              {%{
                 "model" => "synthetic",
                 "answers" => %{
                   "candidate" => %{
                     "type" => "choice",
                     "choice" => "keep_baseline",
                     "confidence" => 0.9,
                     "probabilities" => %{"keep_baseline" => 0.9, "defer_candidate" => 0.1}
                   }
                 },
                 "usage" => %{"input_tokens" => 10, "output_tokens" => 2}
               }, step}
            else
              messages = request["messages"]

              tool = fn name ->
                Enum.find(
                  Enum.reverse(messages),
                  &(&1["role"] == "tool" and &1["tool_name"] == name)
                )
              end

              action =
                case step do
                  0 ->
                    {"read", %{"path" => "synthetic.txt"}}

                  1 ->
                    {"source_list", %{"limit" => 32}}

                  2 ->
                    page = tool.("source_list")["content"] |> Jason.decode!()

                    source =
                      Enum.find(
                        Enum.reverse(page["sources"]),
                        &(&1["kind"] == "tool.outcome" and &1["origin"] == "typed_host_outcome")
                      )

                    {"source_read", %{"handle" => source["read_handle"]}}

                  3 ->
                    page = tool.("source_read")["content"] |> Jason.decode!()

                    {"ext__knowledge__capture",
                     %{
                       "text" => page["text"],
                       "category" => "ordinary",
                       "reason" => "fixture host outcome",
                       "event_at_ms" => nil,
                       "source" => %{"handle" => page["handle"], "quote" => page["text"]}
                     }}

                  _ ->
                    key = Agent.get(assessed_key, & &1)

                    if is_binary(key) and is_nil(tool.("ext__knowledge__assess")),
                      do: {"ext__knowledge__assess", %{"key" => key}},
                      else: nil
                end

              message =
                if action,
                  do: %{
                    "role" => "assistant",
                    "content" => "",
                    "tool_calls" => [
                      %{
                        "function" => %{"name" => elem(action, 0), "arguments" => elem(action, 1)}
                      }
                    ]
                  },
                  else: %{"role" => "assistant", "content" => "Fixture finished."}

              {%{
                 "model" => "synthetic",
                 "message" => message,
                 "done" => true,
                 "prompt_eval_count" => 1,
                 "eval_count" => 1
               }, step + 1}
            end

          body = Jason.encode!(response) <> if(decision?, do: "", else: "\n")

          :ok =
            :gen_tcp.send(
              socket,
              "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                body
            )

          :gen_tcp.close(socket)
          loop.(loop, next)

        _ ->
          :ok
      end
    end

    loop.(loop, 0)
  end)

config_path = Path.join(home, "config.json")

config = %{
  "version" => 1,
  "profiles" => %{
    "main" => %{
      "provider" => "ollama",
      "model" => "synthetic",
      "base_url" => base,
      "max_output_tokens" => 64,
      "timeout_ms" => 90_000
    }
  },
  "roles" => %{"main" => "main"},
  "decision_profiles" => %{
    "advice" => %{
      "operation" => "decision",
      "provider" => "system_one_compatible",
      "model" => "synthetic",
      "service_id" => "fixture",
      "base_url" => base,
      "timeout_ms" => 3000
    }
  },
  "inference_services" => %{"fixture" => %{"version" => 1, "origins" => [base]}}
}

File.write!(config_path, Jason.encode!(config))
File.chmod!(config_path, 0o600)
duration = if expiry?, do: "35", else: "120"

assert 0 ==
         Ipse.CLI.run([
           "knowledge",
           "experiment",
           "advice",
           "1",
           duration,
           "--cwd",
           cwd,
           "--config",
           config_path,
           "--no-project-config"
         ])

{:ok, binding} = Ipse.Extension.ProjectIdentity.existing(home, cwd)
control = Ipse.Extension.SemanticAdmission.control_root(home)
{:ok, snapshot} = Ipse.Extension.Consent.existing_snapshot(control, binding["project_id"])
expires = snapshot["policy"]["expires_at_ms"]
assert snapshot["policy"]["limits"]["model_calls"] == 1

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

# Capture the literal in a separate, headless Session. Its ordinary saved-consent
# write is permitted and does not start an assessment. The second Session
# independently reads the saved eligible record before requesting advice.
seed_runtime = %{runtime | approval: :deny, approval_origin: :default_headless, headless: true}

{:ok, seed} =
  DynamicSupervisor.start_child(
    Ipse.Sessions,
    {Ipse.Session, config: seed_runtime, cwd: cwd, state_dir: dir, subscriber: self()}
  )

seed_id = Ipse.Session.info(seed).id
assert :ok = Ipse.Session.prompt(seed, "Capture the actual local tool outcome.")
assert_receive {:ipse, ^seed, {:done, :ok}}, 20_000
{:ok, seed_events} = Ipse.Journal.load(dir, seed_id)

assert [seed_write] =
         Enum.filter(seed_events, fn event ->
           event["type"] == "extension_action_result" and
             get_in(event, ["request", "op"]) == "collection.managed" and
             get_in(event, ["outcome", "status"]) == "ok"
         end)

[%{"key" => key}] = get_in(seed_write, ["request", "request", "changes"])
assert String.starts_with?(key, "note.")
Agent.update(assessed_key, fn _ -> key end)
refute Enum.any?(Agent.get(calls, & &1), &(elem(&1, 0) == :decision))
assert :ok = Ipse.Session.close_confirmed(seed)

if revoked? do
  {:ok, current} = Ipse.Extension.Consent.existing_snapshot(control, binding["project_id"])

  assert {:ok, _} =
           Ipse.Extension.Consent.revoke(control, binding["project_id"], current["epoch"])
end

{:ok, pid} =
  DynamicSupervisor.start_child(
    Ipse.Sessions,
    {Ipse.Session, config: runtime, cwd: cwd, state_dir: dir, subscriber: self()}
  )

id = Ipse.Session.info(pid).id

if revoked? do
  state = :sys.get_state(pid)
  refute get_in(state.config, [:semantic_admission, "status"]) == "active"

  assert :ok =
           Ipse.Session.prompt(pid, "Assess the previously saved synthetic note " <> key <> ".")

  assert_receive {:ipse, ^pid, {:done, _}}, 20_000
  {:ok, events} = Ipse.Journal.load(dir, id)
  refute Enum.any?(events, &(get_in(&1, ["request", "op"]) == "decision.create"))
  refute Enum.any?(Agent.get(calls, & &1), &(elem(&1, 0) == :decision))
  {:ok, final} = Ipse.Extension.Consent.existing_snapshot(control, binding["project_id"])
  assert is_nil(final["policy"])

  refute Enum.any?(final["operations"], fn {_, operation} ->
           operation["reserved"]["model_calls"] > 0
         end)

  assert :ok = Ipse.Session.close_confirmed(pid)
  :gen_tcp.close(listener)
  Task.shutdown(server, :brutal_kill)
  IO.puts("SHADOW_EXPERIMENT_SESSION_PASSED")
  System.halt(0)
end

wait_file = fn wait_file, path, remaining ->
  if File.exists?(path),
    do: :ok,
    else:
      (
        assert remaining > 0
        Process.sleep(10)
        wait_file.(wait_file, path, remaining - 1)
      )
end

{:ok, _watcher} =
  Task.start_link(fn ->
    wait_file.(wait_file, Path.join(root, "managed-approval-input-ready"), 1500)
    assert :sys.get_state(pid).phase == :managed_approval

    if expiry? do
      watcher = self()

      hook = fn
        count, {:in, {:"$gen_call", _, {:managed_preflight_begin, _, "decision.create"}}}, _
        when preflight_expiry? ->
          send(watcher, {:shadow_wire_blocked, self()})
          receive do: (:release_shadow_wire -> :ok)
          count + 1

        count, {:in, {:"$gen_call", _, {:managed_result_admit, _, "decision.create", _, _, _}}}, _
        when release_expiry? ->
          send(watcher, {:shadow_wire_blocked, self()})
          receive do: (:release_shadow_wire -> :ok)
          count + 1

        count, _, _ ->
          count
      end

      assert :ok = :sys.install(pid, {hook, 0})
      delay = max(expires - System.system_time(:millisecond) - 4_000, 0)
      Process.sleep(delay)
    end

    File.write!(Path.join(root, "managed-approval-control-checked"), "checked")

    if expiry? do
      assert_receive {:shadow_wire_blocked, ^pid}, 4_000
      Process.sleep(max(expires - System.system_time(:millisecond) + 50, 0))
      send(pid, :release_shadow_wire)
    end

    idle = fn idle, remaining ->
      if :sys.get_state(pid).phase == :idle,
        do: :ok,
        else:
          (
            assert remaining > 0
            Process.sleep(10)
            idle.(idle, remaining - 1)
          )
    end

    idle.(idle, 2000)
    File.write!(Path.join(root, "managed-approval-exit-ready"), "ready")
  end)

IO.puts("IPSE_MANAGED_APPROVAL_CLI_READY")

assert 0 ==
         Ipse.CLI.Terminal.interact(
           pid,
           Process.monitor(pid),
           true,
           "Assess the previously saved synthetic note " <> key <> ".",
           cwd
         )

{:ok, events} = Ipse.Journal.load(dir, id)
decisions = Enum.filter(Agent.get(calls, & &1), &(elem(&1, 0) == :decision))
assert length(decisions) == if(preflight_expiry? or denied?, do: 0, else: 1)

actions =
  Enum.filter(
    events,
    &(&1["type"] == "extension_action_result" and
        get_in(&1, ["request", "op"]) == "decision.create")
  )

assert [action] = actions
{:ok, final} = Ipse.Extension.Consent.existing_snapshot(control, binding["project_id"])
reservation = final["operations"][action["operation_id"]]

cond do
  denied? ->
    assert is_nil(reservation)

  preflight_expiry? ->
    assert is_nil(reservation)

  release_expiry? ->
    assert reservation["status"] == "unknown" and reservation["reserved"]["model_calls"] == 1
    refute Enum.any?(events, &(&1["type"] == "extension_decision_response"))

  true ->
    assert reservation["status"] == "settled" and reservation["actual"]["model_calls"] == 1
    assert action["outcome"]["status"] == "ok"
end

refute Enum.any?(events, fn event ->
         event["type"] == "extension_action_intent" and
           get_in(event, ["request", "op"]) == "collection.managed"
       end)

assert :ok = Ipse.Session.close_confirmed(pid)
:gen_tcp.close(listener)
Task.shutdown(server, :brutal_kill)
IO.puts("SHADOW_EXPERIMENT_SESSION_PASSED")
