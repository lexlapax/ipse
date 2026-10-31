defmodule Ipse.Session.ShareOperationBarrierTest do
  use ExUnit.Case, async: false
  @moduletag skip: if(:os.type() == {:unix, :linux}, do: false, else: "Linux native share")

  alias Ipse.Session

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-share-operation-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)

    opts = [
      config: %{
        provider: :demo,
        model: "fixture",
        home: root,
        approval: :deny,
        observability: Map.put(Ipse.Observability.defaults(), "mode", "local")
      },
      cwd: root,
      state_dir: Path.join(root, "sessions"),
      subscriber: self()
    ]

    {:ok, session} = Session.start_share_candidate_link(opts)
    Process.unlink(session)
    on_exit(fn -> if Process.alive?(session), do: Process.exit(session, :kill) end)
    %{session: session}
  end

  test "Session seals calls before Writer drain and safely aborts the armed share", c do
    {task, job, intent} = install_task(c.session)
    before = :sys.get_state(c.session)
    :ok = :sys.suspend(before.journal_writer)
    send(task.pid, {:begin, c.session, job, intent})
    await_phase(c.session, :draining)

    assert {:error, :session_share_frozen} =
             GenServer.call(c.session, {:managed_sources, job, nil, []})

    assert {:error, :session_share_frozen} = GenServer.call(c.session, {:prompt, "blocked"})
    :ok = :sys.resume(before.journal_writer)
    assert_receive {:begun, {:ok, capability, transport, snapshot}}, 5_000
    assert is_reference(capability) and byte_size(transport) == 16
    assert snapshot.job_ref == job and snapshot.session_id == before.id

    assert {:error, :session_share_frozen} =
             GenServer.call(c.session, {:session_share_abort, job, capability})

    send(task.pid, {:abort, c.session, job, capability})
    assert_receive {:aborted, :ok}, 5_000
    assert :sys.get_state(c.session).share_barrier == nil
    restore_idle(c.session, task)
    assert :ok = Session.close_confirmed(c.session)
  end

  test "cancellation quarantines promptly while Writer is suspended", c do
    {task, job, intent} = install_task(c.session)
    writer = :sys.get_state(c.session).journal_writer
    :ok = :sys.suspend(writer)
    send(task.pid, {:begin, c.session, job, intent})
    await_phase(c.session, :draining)
    started = System.monotonic_time(:millisecond)
    assert {:error, :cleanup_unconfirmed} = Session.cancel(c.session)
    assert System.monotonic_time(:millisecond) - started < 1_000
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned

    assert {:error, :session_share_frozen} =
             GenServer.call(c.session, {:managed_sources, job, nil, []})

    :ok = :sys.resume(writer)
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  test "an unexpected Session event quarantines an armed operation", c do
    {task, job, intent} = install_task(c.session)
    send(task.pid, {:begin, c.session, job, intent})
    assert_receive {:begun, {:ok, _capability, _transport, _snapshot}}, 5_000
    send(c.session, {:fixture_competing_event, make_ref()})
    await_phase(c.session, :poisoned)

    assert {:error, :session_share_frozen} =
             GenServer.call(c.session, {:session_share_begin, job, intent})

    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  test "draft cancellation also poisons without waiting for Writer", c do
    {task, job, intent} = install_task(c.session)
    writer = :sys.get_state(c.session).journal_writer
    :ok = :sys.suspend(writer)
    send(task.pid, {:begin, c.session, job, intent})
    await_phase(c.session, :draining)
    assert {:error, :cleanup_unconfirmed} = Session.cancel_draft(c.session)
    assert :sys.get_state(c.session).share_barrier.phase == :poisoned
    :ok = :sys.resume(writer)
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  @tag :share_timeout
  test "the setup timer quarantines a stalled Writer without waiting for it", c do
    {task, job, intent} = install_task(c.session)
    writer = :sys.get_state(c.session).journal_writer
    :ok = :sys.suspend(writer)
    send(task.pid, {:begin, c.session, job, intent})
    await_phase(c.session, :draining)
    await_phase(c.session, :poisoned, 700)
    assert {:error, :session_share_frozen} = GenServer.call(c.session, {:prompt, "blocked"})
    :ok = :sys.resume(writer)
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(c.session)
  end

  defp install_task(session) do
    parent = self()
    job = make_ref()
    intent = %{"type" => "fixture_action"}

    invocation = %Ipse.Session.Invocation{
      parent: %{"identity" => %{}},
      action: %{intent: intent}
    }

    :sys.replace_state(session, fn s ->
      task = Task.Supervisor.async_nolink(Ipse.Tasks, fn -> task_loop(parent) end)
      send(parent, {:fixture_task, task})
      config = Map.put(s.config, :extensions, [%{identity: %{}}])

      %{
        s
        | task: task,
          job_ref: job,
          phase: :extension_command,
          invocation: invocation,
          config: config
      }
    end)

    assert_receive {:fixture_task, task}
    {task, job, intent}
  end

  defp task_loop(parent) do
    receive do
      {:begin, session, job, intent} ->
        send(
          parent,
          {:begun, GenServer.call(session, {:session_share_begin, job, intent}, 10_000)}
        )

        task_loop(parent)

      {:abort, session, job, capability} ->
        send(
          parent,
          {:aborted, GenServer.call(session, {:session_share_abort, job, capability}, 10_000)}
        )

        task_loop(parent)
    end
  end

  defp await_phase(session, phase, attempts \\ 100)

  defp await_phase(session, phase, 0),
    do: assert(%{phase: ^phase} = :sys.get_state(session).share_barrier)

  defp await_phase(session, phase, attempts) do
    case :sys.get_state(session).share_barrier do
      %{phase: ^phase} ->
        :ok

      _ ->
        Process.sleep(10)
        await_phase(session, phase, attempts - 1)
    end
  end

  defp restore_idle(session, task) do
    Process.exit(task.pid, :kill)

    :sys.replace_state(session, fn s ->
      config = Map.put(s.config, :extensions, [])

      %{
        s
        | task: nil,
          job_ref: nil,
          phase: :idle,
          invocation: %Ipse.Session.Invocation{},
          config: config
      }
    end)
  end
end
