ExUnit.start(autorun: false)
import ExUnit.Assertions
Code.require_file("knowledge_helper_route.exs", __DIR__)
{:ok, _} = Application.ensure_all_started(:ipse)

for key <-
      ~w(IPSE_PROVIDER IPSE_MODEL IPSE_SANDBOX IPSE_MAX_STEPS IPSE_CONTEXT_BYTES IPSE_COMPACT IPSE_SUBAGENTS IPSE_SUBAGENT_CONCURRENCY IPSE_TIMEOUT_MS IPSE_MAX_OUTPUT_TOKENS IPSE_PROFILE IPSE_CONFIG),
    do: System.delete_env(key)

[root, scenario] = System.argv()
home = Path.join(root, "home")
cwd = Path.join(root, "project")
File.mkdir_p!(home)
File.mkdir_p!(cwd)
File.chmod!(home, 0o700)
config_path = Path.join(home, "config.json")

defmodule KnowledgeRegisteredFixture do
  def start do
    Code.require_file("provider_fixture.ex", __DIR__)

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    base = "http://127.0.0.1:#{port}"

    server =
      Task.async(fn ->
        try do
          for step <- 1..3 do
            {:ok, socket} = :gen_tcp.accept(listener, 60_000)

            try do
              {_, bytes} = Ipse.Test.ProviderFixture.request(socket, "")
              request = Jason.decode!(bytes)
              calls = calls(step, request)

              message =
                if calls == [],
                  do: %{"role" => "assistant", "content" => "Fixture finished."},
                  else: %{"role" => "assistant", "content" => "", "tool_calls" => calls}

              body =
                Jason.encode!(%{
                  "model" => "synthetic",
                  "message" => message,
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
            after
              :gen_tcp.close(socket)
            end
          end
        after
          :gen_tcp.close(listener)
        end
      end)

    {base, server}
  end

  defp calls(1, _),
    do: [%{"function" => %{"name" => "source_list", "arguments" => %{"limit" => 32}}}]

  defp calls(2, request) do
    result =
      Enum.find(
        Enum.reverse(request["messages"]),
        &(&1["role"] == "tool" and &1["tool_name"] == "source_list")
      )

    page = Jason.decode!(result["content"])
    source = Enum.find(page["sources"], &(&1["kind"] == "input.original"))

    [
      %{
        "function" => %{
          "name" => "ext__knowledge__capture",
          "arguments" => %{
            "text" => "Acme has owner Alex",
            "category" => "ordinary",
            "reason" => "fixture observation",
            "event_at_ms" => nil,
            "source" => %{"handle" => source["read_handle"], "quote" => "Acme has owner Alex"}
          }
        }
      }
    ]
  end

  defp calls(3, request) do
    capture =
      Enum.find(
        request["messages"],
        &(&1["role"] == "tool" and &1["tool_name"] == "ext__knowledge__capture")
      )

    true = is_map(capture) and is_binary(capture["content"])
    []
  end
end

{base, server} = if scenario == "save", do: KnowledgeRegisteredFixture.start(), else: {nil, nil}

config_bytes =
  if scenario in ~w(experiment-helper experiment-helper-config) do
    data =
      %{"version" => 1, "settings" => %{"provider" => "demo", "model" => "scripted"}}
      |> Map.merge(Ipse.Test.KnowledgeHelperRoute.profiles())
      |> Map.merge(Ipse.Test.KnowledgeHelperRoute.install(root, home))

    Jason.encode!(data)
  else
    if server do
      Jason.encode!(%{
        "version" => 1,
        "profiles" => %{
          "local_fixture" => %{
            "provider" => "ollama",
            "model" => "synthetic",
            "base_url" => base,
            "max_output_tokens" => 64,
            "timeout_ms" => 90_000
          }
        },
        "roles" => %{"main" => "local_fixture"},
        "inference_services" => %{"local" => %{"version" => 1, "origins" => [base]}}
      })
    else
      Jason.encode!(%{
        "version" => 1,
        "settings" => %{"provider" => "demo", "model" => "scripted"}
      })
    end
  end

File.write!(config_path, config_bytes)
File.chmod!(config_path, 0o600)
opts = [config: config_path, project_config: false]
System.put_env("IPSE_HOME", home)

command = fn action ->
  Ipse.CLI.run([
    "knowledge",
    action,
    "--cwd",
    cwd,
    "--config",
    config_path,
    "--no-project-config"
  ])
end

if scenario in ~w(experiment-helper experiment-helper-config) do
  race =
    if scenario == "experiment-helper-config" do
      Task.async(fn ->
        deadline = System.monotonic_time(:millisecond) + 10_000

        wait = fn wait ->
          if File.exists?(Path.join(root, "native-review-ready")) do
            :ok
          else
            assert System.monotonic_time(:millisecond) < deadline
            Process.sleep(5)
            wait.(wait)
          end
        end

        wait.(wait)

        changed =
          Jason.decode!(config_bytes) |> put_in(["profiles", "extract", "model"], "changed")

        File.write!(config_path, Jason.encode!(changed))
        File.write!(Path.join(root, "consent-raced"), "done")
      end)
    end

  code =
    Ipse.CLI.run([
      "knowledge",
      "experiment",
      "advice",
      "2",
      "300",
      "--helper-profile",
      "extract",
      "--cwd",
      cwd,
      "--config",
      config_path,
      "--no-project-config"
    ])

  if race do
    assert code === 1
    Task.await(race, 1000)
    assert {:ok, binding} = Ipse.Extension.ProjectIdentity.existing(home, cwd)

    assert {:ok, unchanged} =
             Ipse.Extension.Consent.existing_snapshot(
               Ipse.Extension.SemanticAdmission.control_root(home),
               binding["project_id"]
             )

    assert unchanged === nil

    refute File.exists?(
             Path.join([
               Ipse.Extension.SemanticAdmission.control_root(home),
               binding["project_id"],
               "control.json"
             ])
           )

    IO.puts("KNOWLEDGE_NATIVE_HELPER_ROUTE_CHANGED_REFUSED")
    System.halt(0)
  end

  assert code === 0
  assert File.read!(config_path) === config_bytes
  assert {:ok, binding} = Ipse.Extension.ProjectIdentity.existing(home, cwd)
  control = Ipse.Extension.SemanticAdmission.control_root(home)

  assert {:ok, snapshot} =
           Ipse.Extension.Consent.existing_snapshot(control, binding["project_id"])

  policy = snapshot["policy"]

  assert Enum.map(policy["settings"]["routes"], &{&1["operation"], &1["profile"]}) ===
           [{"decision.create", "advice"}, {"main", nil}, {"model.complete", "extract"}]

  assert policy["limits"]["model_calls"] === 2 and snapshot["operations"] === %{}
  assert {:ok, effective} = Ipse.Config.resolve(cwd, home, opts, %{})

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

  assert {:ok, runtime} = Ipse.Config.runtime(effective, client)
  assert {:ok, active} = Ipse.Config.Activation.fresh(runtime, cwd)
  knowledge = Enum.find(active.extensions, &(&1.identity["instance"] === "knowledge"))
  assert Ipse.JSON.digest([knowledge.identity]) === policy["settings"]["identity_sha256"]
  refute "host.model" in knowledge.identity["capabilities"]

  assert Enum.any?(
           active.extensions,
           &(&1.identity["instance"] === "helper" and "host.model" in &1.identity["capabilities"])
         )

  assert {:ok, pid} =
           DynamicSupervisor.start_child(
             Ipse.Sessions,
             {Ipse.Session,
              [
                config: runtime,
                cwd: cwd,
                state_dir: Path.join(root, "sessions"),
                subscriber: self()
              ]}
           )

  state = :sys.get_state(pid)
  assert state.config.semantic_admission["status"] === "active"
  assert state.config.semantic_admission["policy"] === policy
  assert state.phase === :idle
  assert :ok = Ipse.Session.close_confirmed(pid)
  assert {:ok, events} = Ipse.Journal.load(Path.join(root, "sessions"), state.id)
  assert {:ok, _} = Ipse.Session.Saved.restore(events, state.id)

  refute Enum.any?(
           events,
           &(&1["type"] in ~w(request_admitted inference_dispatch_intent extension_action_intent))
         )

  assert {:ok, ^snapshot} =
           Ipse.Extension.Consent.existing_snapshot(control, binding["project_id"])

  IO.puts("KNOWLEDGE_NATIVE_HELPER_ROUTE_PASSED")
  System.halt(0)
end

if scenario == "pipe" do
  assert command.("enable") == 1
  assert {:ok, nil} = Ipse.Extension.ProjectIdentity.existing(home, cwd)
  assert File.read!(config_path) == config_bytes
  IO.puts("KNOWLEDGE_NATIVE_PIPE_REFUSED")
  System.halt(0)
end

race =
  if scenario == "cas" or String.starts_with?(scenario, "config-") do
    Task.async(fn ->
      deadline = System.monotonic_time(:millisecond) + 10_000

      wait = fn wait ->
        if File.exists?(Path.join(root, "native-review-ready")) do
          :ok
        else
          assert System.monotonic_time(:millisecond) < deadline
          Process.sleep(5)
          wait.(wait)
        end
      end

      wait.(wait)

      if scenario == "cas" do
        {:ok, binding} = Ipse.Extension.ProjectIdentity.existing(home, cwd)
        control = Ipse.Extension.SemanticAdmission.control_root(home)
        {:ok, before} = Ipse.Extension.Consent.snapshot(control, binding["project_id"])
        assert before["epoch"] == 0 and before["policy"] == nil

        assert {:ok, %{"epoch" => 1}} =
                 Ipse.Extension.Consent.revoke(control, binding["project_id"], 0)
      else
        changed =
          case scenario do
            "config-model" ->
              Jason.encode!(%{
                "version" => 1,
                "settings" => %{"provider" => "demo", "model" => "changed"}
              })

            "config-timeout" ->
              Jason.encode!(%{
                "version" => 1,
                "settings" => %{
                  "provider" => "demo",
                  "model" => "scripted",
                  "timeout_ms" => 30_000
                }
              })

            "config-malformed" ->
              "{"

            "config-format" ->
              config_bytes <> "\n"
          end

        File.write!(config_path, changed)
      end

      File.write!(Path.join(root, "consent-raced"), "done")
    end)
  end

if scenario in ["cancel", "stale", "cas"] or String.starts_with?(scenario, "config-") do
  assert command.("enable") == 1
  if race, do: Task.await(race, 1_000)
  {:ok, binding} = Ipse.Extension.ProjectIdentity.existing(home, cwd)
  assert binding

  {:ok, snapshot} =
    Ipse.Extension.Consent.snapshot(
      Ipse.Extension.SemanticAdmission.control_root(home),
      binding["project_id"]
    )

  assert snapshot["policy"] == nil
  assert snapshot["epoch"] == if(scenario == "cas", do: 1, else: 0)
  assert snapshot["operations"] == %{}

  if String.starts_with?(scenario, "config-") do
    refute File.read!(config_path) == config_bytes
  else
    assert File.read!(config_path) == config_bytes
  end

  IO.puts("KNOWLEDGE_NATIVE_REVIEW_CANCELLED")
  System.halt(0)
end

assert command.("enable") == 0
assert File.read!(config_path) == config_bytes
{:ok, binding} = Ipse.Extension.ProjectIdentity.existing(home, cwd)

{:ok, snapshot} =
  Ipse.Extension.Consent.snapshot(
    Ipse.Extension.SemanticAdmission.control_root(home),
    binding["project_id"]
  )

assert snapshot["policy"]["headless"]
assert snapshot["policy"]["settings"]["activation"]["main_timeout_ms"] == 90_000
assert map_size(snapshot["operations"]) == 0

pending = [
  Path.join([home, "project-identities", ".pending-" <> Ipse.Usage.id()]),
  Path.join([
    Ipse.Extension.SemanticAdmission.control_root(home),
    binding["project_id"],
    ".pending-" <> Ipse.Usage.id()
  ])
]

for path <- pending do
  File.write!(path, "synthetic pending record")
  File.chmod!(path, 0o600)
end

status =
  ExUnit.CaptureIO.capture_io(fn ->
    assert Ipse.CLI.Knowledge.run("status", Keyword.put(opts, :json, true), home, cwd) == 0
  end)
  |> Jason.decode!()

assert status["activation_ready_now"] == true
assert status["worktree_admitted"] == true
assert status["policy_sha256"] == Ipse.JSON.digest([snapshot["policy"]])
for path <- pending, do: assert(File.read!(path) == "synthetic pending record")
for path <- pending, do: File.rm!(path)

if scenario == "readiness" do
  assert status["publication_supported_now"] == false
  assert status["capture_ready_now"] == false
  assert status["publication_unavailable_reason"] == "collection_deadline_fence_unavailable"

  text =
    ExUnit.CaptureIO.capture_io(fn ->
      assert Ipse.CLI.Knowledge.run("status", opts, home, cwd) == 0
    end)

  assert text =~ "Saved knowledge selection matches the next new session."
  assert text =~ "Broad protected note saving is not ready"
  assert text =~ "A new statement may be saved through separate native review"
  refute text =~ "selection is ready"

  permissions =
    ExUnit.CaptureIO.capture_io(fn ->
      assert Ipse.CLI.Knowledge.run("permissions", opts, home, cwd) == 0
    end)
    |> Jason.decode!()

  assert permissions["activation_ready_now"] == nil
  assert permissions["publication_supported_now"] == false
  assert permissions["capture_ready_now"] == false
  assert permissions["policy"] == snapshot["policy"]
  assert permissions["epoch"] == snapshot["epoch"]
  assert File.read!(config_path) == config_bytes
  IO.puts("KNOWLEDGE_NATIVE_READINESS_PUBLICATION_UNAVAILABLE")
  System.halt(0)
end

writers = [
  Path.join([home, "project-identities", ".writer.lock"]),
  Path.join([
    Ipse.Extension.SemanticAdmission.control_root(home),
    binding["project_id"],
    ".writer.lock"
  ])
]

for writer <- writers do
  assert File.read!(writer) == ""
  File.rm!(writer)

  for action <- ["status", "permissions"] do
    ExUnit.CaptureIO.capture_io(:stderr, fn -> assert command.(action) == 1 end)
    refute File.exists?(writer)
  end

  File.write!(writer, "", [:exclusive])
  File.chmod!(writer, 0o600)
end

File.write!(
  config_path,
  Jason.encode!(%{"version" => 1, "settings" => %{"provider" => "demo", "model" => "changed"}})
)

ExUnit.CaptureIO.capture_io(:stderr, fn -> assert command.("status") == 1 end)

permissions =
  ExUnit.CaptureIO.capture_io(fn -> assert command.("permissions") == 0 end)
  |> Jason.decode!()

assert permissions["policy"] == snapshot["policy"]
assert permissions["activation_ready_now"] == nil
File.write!(config_path, config_bytes)
{:ok, effective} = Ipse.Config.resolve(cwd, home, opts, %{})

client = %{
  workspace: cwd,
  home: home,
  auth_dir: Path.join(home, "auth"),
  operator_home: root,
  mcp_config: nil,
  base_url: nil,
  operator_questions: false,
  accept_edits: false,
  approval: :deny,
  approval_origin: :default_headless,
  headless: true
}

{:ok, config} = Ipse.Config.runtime(effective, client)

defmodule KnowledgeCLINativeFixture do
  def complete(_, messages, _, _) do
    results = Enum.filter(messages, &(&1["role"] == "tool"))

    case results do
      [] ->
        tool("list", "source_list", %{"limit" => 32})

      [result] ->
        list = Jason.decode!(result["content"])
        source = Enum.find(list["sources"], &(&1["kind"] == "input.original"))

        tool("capture", "ext__knowledge__capture", %{
          "text" => "Acme has owner Alex",
          "category" => "ordinary",
          "reason" => "fixture observation",
          "event_at_ms" => nil,
          "source" => %{"handle" => source["read_handle"], "quote" => "Acme has owner Alex"}
        })

      _ ->
        {:ok, %{"role" => "assistant", "content" => "Fixture finished."}, %{}}
    end
  end

  defp tool(id, name, args),
    do:
      {:ok,
       %{
         "role" => "assistant",
         "content" => "",
         "tool_calls" => [
           %{
             "id" => id,
             "type" => "function",
             "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
           }
         ]
       }, %{}}
end

config = if server, do: config, else: Map.put(config, :provider_module, KnowledgeCLINativeFixture)

{:ok, pid} =
  DynamicSupervisor.start_child(
    Ipse.Sessions,
    {Ipse.Session,
     config: config, cwd: cwd, state_dir: Path.join(root, "sessions"), subscriber: self()}
  )

assert :ok = Ipse.Session.prompt(pid, "Acme has owner Alex")

receive do
  {:ipse, ^pid, {:done, :ok}} ->
    :ok

  {:ipse, ^pid, {:done, :error}} ->
    state = :sys.get_state(pid)
    dependencies_ok = match?({:ok, _}, Ipse.Session.managed_dependencies(state, "model"))

    route_unregistered =
      Ipse.InferenceDispatch.selection(state.config, state.config, "main", nil) ==
        {:ok, :unregistered}

    IO.puts(
      "HEADLESS_POST_FAILURE_CHECK=" <>
        Jason.encode!(%{
          "dependencies_ok" => dependencies_ok,
          "route_unregistered" => route_unregistered,
          "managed_empty" => Ipse.Session.managed_empty?(state)
        })
    )

    flunk("headless fixture did not complete")
after
  30_000 -> flunk("headless fixture timed out")
end

{:ok, events} = Ipse.Journal.load(Path.join(root, "sessions"), Ipse.Session.info(pid).id)

commit =
  Enum.find(
    events,
    &(&1["type"] == "extension_action_result" and
        get_in(&1, ["request", "op"]) == "collection.managed")
  )

assert commit, inspect(Enum.map(events, & &1["type"]))
assert commit["approval"] == "saved_consent"
assert commit["outcome"]["status"] == "ok"
assert commit["outcome"]["value"]["normalization"]["eligibility"] == "never_current"
{:ok, mode} = Ipse.Extension.Mode.capture(config)
assert Ipse.Extension.Mode.ordinary(mode, true) == :deny
assert :ok = Ipse.Session.close_confirmed(pid)
assert command.("disable") == 0

{:ok, revoked} =
  Ipse.Extension.Consent.snapshot(
    Ipse.Extension.SemanticAdmission.control_root(home),
    binding["project_id"]
  )

assert revoked["policy"] == nil
assert map_size(revoked["operations"]) == 1
{:ok, off} = Ipse.Config.Activation.fresh(config, cwd)
assert off.extensions == []
assert File.read!(config_path) == config_bytes
assert Task.await(server, 5_000) == [:ok, :ok, :ok]
IO.puts("KNOWLEDGE_NATIVE_SETUP_SAVE_DISABLE_PASSED")
