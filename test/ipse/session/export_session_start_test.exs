defmodule Ipse.Session.ExportSessionStartTest do
  use ExUnit.Case, async: false
  alias Ipse.{Journal, Runner, Session}
  @moduletag skip: if(:os.type() == {:unix, :linux}, do: false, else: "Linux-only candidate")

  defmodule Model do
    def complete(_config, _messages, _tools, _emit),
      do: {:ok, %{"role" => "assistant", "content" => "fixture answer"}, %{}}
  end

  defmodule BlockingModel do
    def complete(config, _messages, _tools, _emit) do
      send(config.fixture_owner, {:provider_started, self()})

      receive do
        :finish -> {:ok, %{"role" => "assistant", "content" => "fixture answer"}, %{}}
      end
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-export-session-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    state = Path.join(root, "state")
    File.mkdir!(state)
    File.chmod!(state, 0o700)
    fixture = Path.join(root, "recipient")

    {_, 0} =
      System.cmd("rustc", [
        "--edition=2021",
        "-D",
        "warnings",
        "dev/fixtures/transaction_lease_export.rs",
        "-o",
        fixture
      ])

    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, state: state, fixture: fixture}
  end

  @tag skip: "candidate Session is unavailable until header IO is fenced"
  test "real Session starts with the candidate, writes through its Writer and closes cleanly",
       c do
    {session, state, path} = start_session(c, :candidate)
    assert state.lock_mode == :export_v1
    assert :sys.get_state(state.lock_guard).mode == :export_v1
    assert Process.alive?(state.journal_writer)
    assert {:error, _} = Runner.protected_lock(path)
    exercise_writer(session, c.state, state.id)
    writer_ref = Process.monitor(state.journal_writer)
    assert :ok = Session.close_confirmed(session)
    assert_lifecycle_cleanup(c.state, state.id, false)
    assert_receive {:DOWN, ^writer_ref, :process, _, _}, 5_000
    assert {:ok, reopened} = Runner.protected_lock(path)
    assert :ok = Runner.unlock(reopened)
  end

  @tag skip: "candidate Session is unavailable until header IO is fenced"
  test "real Session reports unconfirmed close while an exported recipient holds its lock", c do
    {session, state, path} = start_session(c, :candidate)
    exercise_writer(session, c.state, state.id)
    recipient = export_to_recipient(c.fixture, state.lock_guard, state.lock, path)
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(session)
    assert_lifecycle_cleanup(c.state, state.id, false)
    refute Process.alive?(state.journal_writer)
    assert {:error, _} = Runner.protected_lock(path)

    parent = self()
    opts = Keyword.put(session_options(c), :id, state.id)

    spawn(fn ->
      Process.flag(:trap_exit, true)
      send(parent, {:resume_while_held, Session.start_export_candidate_link(opts)})
    end)

    assert_receive {:resume_while_held, {:error, _}}, 5_000

    close_recipient(recipient)
    assert {:ok, reopened} = Runner.protected_lock(path)
    assert :ok = Runner.unlock(reopened)
    {resumed, resumed_state, _} = start_session(c, :candidate, state.id)
    assert resumed_state.id == state.id
    assert :ok = Session.close_confirmed(resumed)
  end

  @tag skip: "candidate Session is unavailable until header IO is fenced"
  test "real Session owner death stops its Writer while the exported recipient retains exclusion",
       c do
    {session, state, path} = start_session(c, :candidate)
    exercise_writer(session, c.state, state.id)
    recipient = export_to_recipient(c.fixture, state.lock_guard, state.lock, path)
    guard_ref = Process.monitor(state.lock_guard)
    writer_ref = Process.monitor(state.journal_writer)
    Process.exit(session, :kill)
    assert_receive {:DOWN, ^writer_ref, :process, _, _}, 5_000
    assert_receive {:DOWN, ^guard_ref, :process, _, :normal}, 5_000
    assert {:error, _} = Runner.protected_lock(path)
    close_recipient(recipient)
    assert {:ok, reopened} = Runner.protected_lock(path)
    assert :ok = Runner.unlock(reopened)
  end

  test "ordinary Session options do not select the candidate", c do
    {session, state, path} = start_session(c, :legacy)
    assert state.lock_mode == :header_v1
    assert :sys.get_state(state.lock_guard).mode == :header_v1
    assert {:error, _} = Runner.protected_lock(path)
    assert :ok = Session.close_confirmed(session)
    assert_lifecycle_cleanup(c.state, state.id, false)
    {resumed, resumed_state, _} = start_session(c, :legacy, state.id)
    assert resumed_state.lock_mode == :resume_v1
    assert :sys.get_state(resumed_state.lock_guard).mode == :resume_v1
    assert {:error, _} = Runner.protected_lock(path)
    assert :ok = Session.close_confirmed(resumed)
  end

  @tag skip: "candidate Session is unavailable until header IO is fenced"
  test "direct same-VM GenServer startup can select the candidate", c do
    {:ok, session} = GenServer.start_link(Session, {:export_v1, session_options(c)})
    Process.unlink(session)
    on_exit(fn -> if Process.alive?(session), do: Process.exit(session, :kill) end)
    assert :sys.get_state(session).lock_mode == :export_v1
    assert :ok = Session.close_confirmed(session)
  end

  @tag skip: "candidate Session is unavailable until header IO is fenced"
  test "candidate close stops an active provider task and its Writer before releasing lock", c do
    opts = session_options(c)

    config =
      opts[:config] |> Map.put(:provider_module, BlockingModel) |> Map.put(:fixture_owner, self())

    {:ok, session} = Session.start_export_candidate_link(Keyword.put(opts, :config, config))
    Process.unlink(session)
    on_exit(fn -> if Process.alive?(session), do: Process.exit(session, :kill) end)
    state = :sys.get_state(session)
    path = Path.join(c.state, state.id <> ".lock")
    assert :ok = Session.prompt(session, "synthetic in-flight close")
    assert_receive {:provider_started, provider}, 5_000
    task = :sys.get_state(session).task.pid
    writer_ref = Process.monitor(state.journal_writer)
    task_ref = Process.monitor(task)
    provider_ref = Process.monitor(provider)
    assert {:error, _} = Runner.protected_lock(path)
    assert :ok = Session.close_confirmed(session)
    assert_receive {:DOWN, ^task_ref, :process, ^task, _}, 5_000
    assert_receive {:DOWN, ^provider_ref, :process, ^provider, _}, 5_000
    assert_receive {:DOWN, ^writer_ref, :process, _, _}, 5_000
    assert_lifecycle_cleanup(c.state, state.id, false)
    assert {:ok, reopened} = Runner.protected_lock(path)
    assert :ok = Runner.unlock(reopened)
  end

  defp session_options(c) do
    [
      config: %{
        provider: :demo,
        provider_module: Model,
        model: "fixture",
        home: c.root,
        approval: :deny,
        observability: Map.put(Ipse.Observability.defaults(), "mode", "local")
      },
      cwd: c.root,
      state_dir: c.state,
      subscriber: self(),
      lock_mode: :export_v1
    ]
  end

  defp start_session(c, mode, id \\ nil) do
    opts = if id, do: Keyword.put(session_options(c), :id, id), else: session_options(c)

    {:ok, session} =
      if mode == :candidate,
        do: Session.start_export_candidate_link(opts),
        else: Session.start_link(opts)

    Process.unlink(session)
    on_exit(fn -> if Process.alive?(session), do: Process.exit(session, :kill) end)
    state = :sys.get_state(session)
    {session, state, Path.join(c.state, state.id <> ".lock")}
  end

  defp exercise_writer(session, dir, id) do
    assert :ok = Session.prompt(session, "synthetic Session writer check")
    assert_receive {:ipse, ^session, {:done, _}}, 10_000
    assert {:ok, events} = Journal.load(dir, id)
    assert Enum.any?(events, &(&1["type"] == "message"))
  end

  defp assert_lifecycle_cleanup(dir, id, expected) do
    assert {:ok, events} = Journal.load(dir, id)

    assert %{"cleanup_confirmed" => ^expected} =
             Enum.find(events, &(&1["type"] == "lifecycle_epoch_closed"))
  end

  # Deliberately injects a synthetic receiver through the diagnostic native
  # Port; no Session or worker export API is being claimed or enabled here.
  defp export_to_recipient(fixture, guard, port, path) do
    {:os_pid, helper_pid} = Port.info(port, :os_pid)
    stat = File.stat!(path)
    name = :crypto.strong_rand_bytes(16)
    secret = :crypto.strong_rand_bytes(32)

    recipient =
      Port.open({:spawn_executable, fixture}, [
        :binary,
        :exit_status,
        :use_stdio,
        args: [
          "--hold-export",
          Base.encode16(name, case: :lower),
          Base.encode16(secret, case: :lower),
          Integer.to_string(helper_pid),
          Integer.to_string(stat.uid),
          Integer.to_string(stat.major_device),
          Integer.to_string(stat.inode)
        ]
      ])

    on_exit(fn -> if Port.info(recipient), do: Port.close(recipient) end)
    {:os_pid, recipient_pid} = Port.info(recipient, :os_pid)
    1 = :erlang.trace(guard, true, [:receive])

    request =
      <<1::unsigned-big-64, 1, recipient_pid::unsigned-big-32, name::binary, secret::binary,
        stat.major_device::unsigned-big-64, stat.inode::unsigned-big-64>>

    assert Port.command(port, <<?X, byte_size(request)::unsigned-big-32, request::binary>>)
    pending = line(recipient, <<>>, "HELD\n", "CLOSED\n", deadline())
    export_reply(guard, port, <<>>, deadline())
    {recipient, pending}
  end

  defp close_recipient({port, pending}) do
    assert Port.command(port, "C")
    assert <<>> = line(port, pending, "CLOSED\n", "", deadline())

    receive do
      {^port, {:exit_status, 0}} -> :ok
      {^port, {:data, _}} -> flunk("unexpected recipient output")
      {^port, {:exit_status, _}} -> flunk("recipient failed")
    after
      5_000 -> flunk("recipient did not close")
    end
  end

  defp deadline, do: System.monotonic_time(:millisecond) + 5_000

  defp line(port, buffer, expected, next, deadline) do
    allowed = expected <> next
    assert byte_size(buffer) <= byte_size(allowed)
    assert binary_part(allowed, 0, byte_size(buffer)) == buffer

    if byte_size(buffer) >= byte_size(expected) do
      binary_part(buffer, byte_size(expected), byte_size(buffer) - byte_size(expected))
    else
      receive do
        {^port, {:data, bytes}} when byte_size(buffer) + byte_size(bytes) <= byte_size(allowed) ->
          line(port, buffer <> bytes, expected, next, deadline)

        {^port, {:data, _}} ->
          flunk("recipient output exceeded its bound")

        {^port, {:exit_status, _}} ->
          flunk("recipient exited early")
      after
        max(deadline - System.monotonic_time(:millisecond), 0) ->
          flunk("recipient output timed out")
      end
    end
  end

  defp export_reply(guard, port, buffer, deadline) do
    expected = <<?X, 10::unsigned-big-32, 1::unsigned-big-64, 1, 0>>
    assert byte_size(buffer) <= byte_size(expected)
    assert binary_part(expected, 0, byte_size(buffer)) == buffer

    if buffer != expected do
      receive do
        {:trace, ^guard, :receive, {^port, {:data, bytes}}} ->
          export_reply(guard, port, buffer <> bytes, deadline)
      after
        max(deadline - System.monotonic_time(:millisecond), 0) ->
          flunk("export response timed out")
      end
    end
  end
end
