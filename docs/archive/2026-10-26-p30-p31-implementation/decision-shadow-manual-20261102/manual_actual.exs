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
dir = Path.join(home, "sessions")
File.mkdir_p!(home)
File.mkdir_p!(cwd)
File.chmod!(home, 0o700)
File.write!(Path.join(cwd, "synthetic.txt"), "Synthetic local observation.\n")
System.put_env("IPSE_HOME", home)

{:ok, listener} =
  :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

{:ok, {_, port}} = :inet.sockname(listener)
base = "http://127.0.0.1:#{port}"
{:ok, decision_listener} =
  :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])
{:ok, {_, decision_port}} = :inet.sockname(decision_listener)
decision_base = "http://127.0.0.1:#{decision_port}"
{:ok, calls} = Agent.start_link(fn -> [] end)
{:ok, assessed_key} = Agent.start_link(fn -> nil end)

servers =
  for active_listener <- [listener, decision_listener] do
  Task.async(fn ->
    loop = fn loop, step ->
      case :gen_tcp.accept(active_listener, 120_000) do
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

              key = Agent.get(assessed_key, & &1)
              action =
                if is_binary(key) and is_nil(tool.("ext__knowledge__assess")),
                  do: {"ext__knowledge__assess", %{"key" => key}},
                  else: nil

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
  end

config_path = Path.join(home, "config.json")

config = %{
  "version" => 1,
  "profiles" => %{
    "main" => %{
      "provider" => "ollama",
      "model" => "synthetic",
      "base_url" => base
    }
  },
  "roles" => %{"main" => "main"},
  "decision_profiles" => %{
    "advice" => %{
      "operation" => "decision",
      "provider" => "system_one_compatible",
      "model" => "synthetic",
      "service_id" => "local-advice",
      "credential" => "none",
      "base_url" => decision_base,
      "timeout_ms" => 30_000
    }
  },
  "inference_services" => %{
    "local-main" => %{"version" => 1, "origins" => [base]},
    "local-advice" => %{"version" => 1, "origins" => [decision_base]}
  }
}

File.write!(config_path, Jason.encode!(config))
File.chmod!(config_path, 0o600)

common = ["--config", config_path, "--no-project-config", "--cwd", cwd]
assert 0 == Ipse.CLI.run(["config"] ++ common)
assert 0 == Ipse.CLI.run(["knowledge", "experiment", "advice", "2", "300"] ++ common)

{:ok, binding} = Ipse.Extension.ProjectIdentity.existing(home, cwd)
control = Ipse.Extension.SemanticAdmission.control_root(home)
{:ok, grant} = Ipse.Extension.Consent.existing_snapshot(control, binding["project_id"])
assert grant["policy"]["limits"]["model_calls"] == 2

IO.puts("IPSE_ASSERTION_CLI_READY")
assert 0 == Ipse.CLI.run(["chat"] ++ common)
[seed_path] = Path.wildcard(Path.join(dir, "*.jsonl"))
seed_id = seed_path |> Path.basename(".jsonl")
{:ok, seed_events} = Ipse.Journal.load(dir, seed_id)
assert Enum.any?(seed_events, &(&1["type"] == "operator_assertion"))
assert Agent.get(calls, & &1) == []
assert {:ok, _} = Ipse.Session.Saved.restore(seed_events, seed_id)

namespace = grant["policy"]["settings"]["namespace"]
collection_root = Ipse.Extension.SemanticAdmission.collection_root(home)
{:ok, collection} =
  Ipse.Extension.Collection.execute(collection_root, namespace, %{"op" => "snapshot"}, Ipse.Usage.id())
{:ok, page} =
  Ipse.Extension.Collection.scan_visible(
    collection_root, namespace,
    %{"op" => "scan", "after" => nil, "generation" => collection["generation"], "limit" => 8},
    Ipse.Usage.id()
  )

[record] = page["records"]
key = record["key"]
assert record["value"]["text"] == "The release checklist requires a migration audit."
assert record["value"]["category"] == "ordinary"
[proof] = record["value"]["evidence"]["sources"]
assert proof["origin"] == "native_operator_assertion"
assert proof["kind"] == "input.assertion.ordinary"
Agent.update(assessed_key, fn _ -> key end)
File.write!(Path.join(root, "assessment-prompt"), "Use the knowledge assess tool on " <> key <> ".")

wait_file = fn wait_file, name, remaining ->
  unless File.exists?(Path.join(root, name)) do
    assert remaining > 0
    Process.sleep(10)
    wait_file.(wait_file, name, remaining - 1)
  end
end

{:ok, _watcher} = Task.start_link(fn ->
  wait_file.(wait_file, "managed-approval-input-ready", 2000)
  children = DynamicSupervisor.which_children(Ipse.Sessions)
  [{_, pid, _, _}] = Enum.filter(children, fn {_, p, _, _} -> is_pid(p) end)
  state = :sys.get_state(pid)
  assert state.phase == :managed_approval
  assert state.managed_approval.arguments["request"]["op"] == "decision.create"
  assert state.managed_approval.arguments["request"]["profile"] == "advice"
  assert state.managed_approval.arguments["request"]["input"] =~ "migration audit"
  File.write!(Path.join(root, "managed-approval-control-checked"), "checked")
  wait_idle = fn wait_idle, remaining ->
    unless :sys.get_state(pid).phase == :idle do
      assert remaining > 0
      Process.sleep(10)
      wait_idle.(wait_idle, remaining - 1)
    end
  end
  wait_idle.(wait_idle, 2000)
  File.write!(Path.join(root, "managed-approval-exit-ready"), "ready")
end)

IO.puts("IPSE_SECOND_CHAT_READY")
IO.puts("IPSE_MANAGED_APPROVAL_CLI_READY")
assert 0 == Ipse.CLI.run(["chat"] ++ common)
second_ids = Path.wildcard(Path.join(dir, "*.jsonl")) |> Enum.map(&(Path.basename(&1, ".jsonl"))) |> Enum.reject(&(&1 == seed_id))
[second_id] = second_ids
{:ok, events} = Ipse.Journal.load(dir, second_id)
assert {:ok, _} = Ipse.Session.Saved.restore(events, second_id)
assert Enum.any?(events, &(&1["type"] == "extension_decision_response"))
[action] = Enum.filter(events, &(&1["type"] == "extension_action_result" and get_in(&1, ["request", "op"]) == "decision.create"))
assert action["outcome"]["status"] == "ok"
assert Enum.count(Agent.get(calls, & &1), &(elem(&1, 0) == :decision)) == 1
refute Enum.any?(events, &(&1["type"] == "extension_action_intent" and get_in(&1, ["request", "op"]) == "collection.managed"))
{:ok, final} = Ipse.Extension.Consent.existing_snapshot(control, binding["project_id"])
assert final["operations"][action["operation_id"]]["status"] == "settled"
assert final["operations"][action["operation_id"]]["actual"]["model_calls"] == 1

:gen_tcp.close(listener)
:gen_tcp.close(decision_listener)
Enum.each(servers, &Task.shutdown(&1, :brutal_kill))
IO.puts("MANUAL_OPERATOR_JOURNEY_PASSED")
