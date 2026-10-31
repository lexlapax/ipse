ExUnit.start(autorun: false)
import ExUnit.Assertions
Code.require_file("cli_fixture.ex", __DIR__)

for key <-
      ~w(IPSE_PROVIDER IPSE_MODEL IPSE_SANDBOX IPSE_MAX_STEPS IPSE_CONTEXT_BYTES IPSE_COMPACT IPSE_SUBAGENTS IPSE_SUBAGENT_CONCURRENCY IPSE_TIMEOUT_MS IPSE_MAX_OUTPUT_TOKENS IPSE_PROFILE IPSE_CONFIG IPSE_WORKSPACE IPSE_RUNNER_PATH),
    do: System.delete_env(key)

for key <- ~w(IPSE_TEST_RELEASE_BEFORE_ACK IPSE_TEST_RELEASE_HOOK),
    do: System.delete_env(key)

[scenario, root] = System.argv()
assert scenario in ~w(clean already_dead lost_reply)
home = Path.join(root, "home")
File.mkdir!(home)
File.chmod!(home, 0o700)
System.put_env("IPSE_HOME", home)
if scenario == "lost_reply", do: System.put_env("IPSE_TEST_RELEASE_BEFORE_ACK", root)
{:ok, _} = Application.ensure_all_started(:ipse)

defmodule Ipse.Test.CLICleanupAck do
  import ExUnit.Assertions

  def await(check, attempts \\ 1_000)
  def await(_, 0), do: flunk("CLI cleanup fixture did not reach its boundary")

  def await(check, attempts) do
    if check.() do
      :ok
    else
      Process.sleep(5)
      await(check, attempts - 1)
    end
  end

  def pending_eof?(cli) do
    {:messages, messages} = Process.info(cli, :messages)
    {:input, :eof} in messages
  end

  def resume(pid) do
    :erlang.resume_process(pid)
  rescue
    ArgumentError -> :ok
  end
end

{:ok, stdio} = Ipse.CLITest.IOFixture.start_link(self())
{:ok, stderr} = Ipse.CLITest.IOFixture.start_link(self())
old_stderr = Process.whereis(:standard_error)
true = Process.unregister(:standard_error)
true = Process.register(stderr, :standard_error)
dir = Path.join(root, "state")

cli =
  Task.async(fn ->
    Process.group_leader(self(), stdio)

    Ipse.CLI.run([
      "chat",
      "--provider",
      "demo",
      "--cwd",
      root,
      "--state-dir",
      dir,
      "--no-project-config"
    ])
  end)

try do
  Ipse.Test.CLICleanupAck.await(fn -> Ipse.CLITest.IOFixture.pending?(stdio) end)
  [_, id] = Regex.run(~r/Session: ([a-f0-9]{32})/, Ipse.CLITest.IOFixture.output(stderr))
  [{session, _}] = Registry.lookup(Ipse.Registry, {dir, id})
  state = :sys.get_state(session)
  assert state.phase == :idle and state.config.provider == :demo
  assert state.config.sandbox == :off
  assert state.config.mcp_servers == []
  assert state.config.extensions == []
  assert is_nil(state.config.budget)
  assert {:ok, before} = Ipse.Journal.load(dir, id)
  refute Enum.any?(before, &(&1["type"] in ~w(request_admitted tool_started)))
  guard_monitor = Process.monitor(state.lock_guard)
  session_monitor = Process.monitor(session)

  case scenario do
    "clean" ->
      Ipse.CLITest.IOFixture.feed(stdio, :eof)

    "already_dead" ->
      :erlang.suspend_process(cli.pid)
      Ipse.CLITest.IOFixture.feed(stdio, :eof)
      Ipse.Test.CLICleanupAck.await(fn -> Ipse.Test.CLICleanupAck.pending_eof?(cli.pid) end)
      Process.exit(session, :kill)
      assert_receive {:DOWN, ^session_monitor, :process, ^session, :killed}, 5_000
      assert_receive {:DOWN, ^guard_monitor, :process, _, _}, 5_000
      :erlang.resume_process(cli.pid)

    "lost_reply" ->
      System.delete_env("IPSE_TEST_RELEASE_BEFORE_ACK")
      Ipse.CLITest.IOFixture.feed(stdio, :eof)

      Ipse.Test.CLICleanupAck.await(fn ->
        File.exists?(Path.join(root, "release-unlocked.ready"))
      end)

      Process.exit(session, :kill)
      assert_receive {:DOWN, ^session_monitor, :process, ^session, :killed}, 5_000
      File.write!(Path.join(root, "release-unlocked.go"), "go")
  end

  result = Task.await(cli, 8_000)
  error_output = Ipse.CLITest.IOFixture.output(stderr)
  warning = "Owned work cleanup could not be confirmed"

  if scenario == "clean" do
    assert result == 0
    refute error_output =~ warning
    assert_receive {:DOWN, ^guard_monitor, :process, _, _}, 5_000
    assert {:ok, events} = Ipse.Journal.load(dir, id)

    assert {:ok, intent} = Ipse.Session.ReleaseReceipt.current_intent(events, id)
    assert is_map(intent)

    receipt = File.read!(Path.join(dir, ".release-#{id}-#{intent["operation_id"]}"))

    assert :signed_release_claim ==
             Ipse.Session.ReleaseReceipt.classify_current(events, id, receipt)
  else
    assert result == 1
    assert error_output =~ warning
    assert {:ok, events} = Ipse.Journal.load(dir, id)
    refute Enum.any?(File.ls!(dir), &String.starts_with?(&1, ".release-#{id}-"))
    refute Enum.any?(events, &(&1["type"] in ~w(request_admitted tool_started)))
  end

  IO.puts(
    "CLI_CLEANUP_ACK_PASSED " <>
      Jason.encode!(%{scenario: scenario, exit_code: result, provider_requests: 0})
  )
after
  System.delete_env("IPSE_TEST_RELEASE_BEFORE_ACK")
  File.write(Path.join(root, "release-unlocked.go"), "go")
  if Process.alive?(cli.pid), do: Ipse.Test.CLICleanupAck.resume(cli.pid)
  if Process.alive?(cli.pid), do: Task.shutdown(cli, :brutal_kill)

  if Process.whereis(:standard_error) == stderr do
    Process.unregister(:standard_error)
    Process.register(old_stderr, :standard_error)
  end
end
