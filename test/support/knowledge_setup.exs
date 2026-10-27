ExUnit.start(autorun: false)
import ExUnit.Assertions
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

config_bytes =
  Jason.encode!(%{"version" => 1, "settings" => %{"provider" => "demo", "model" => "scripted"}})

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

config = Map.put(config, :provider_module, KnowledgeCLINativeFixture)

{:ok, pid} =
  DynamicSupervisor.start_child(
    Ipse.Sessions,
    {Ipse.Session,
     config: config, cwd: cwd, state_dir: Path.join(root, "sessions"), subscriber: self()}
  )

assert :ok = Ipse.Session.prompt(pid, "Acme has owner Alex")
assert_receive {:ipse, ^pid, {:done, :ok}}, 30_000
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
IO.puts("KNOWLEDGE_NATIVE_SETUP_SAVE_DISABLE_PASSED")
