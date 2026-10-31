defmodule Ipse.Session.ShareCandidateTest do
  use ExUnit.Case, async: false
  @moduletag skip: if(:os.type() == {:unix, :linux}, do: false, else: "Linux native share")
  alias Ipse.{Journal, Runner, Session}

  defmodule Model do
    def complete(_, _, _, _),
      do: {:ok, %{"role" => "assistant", "content" => "fixture answer"}, %{}}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-share-session-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    dir = Path.join(root, "sessions")
    on_exit(fn -> File.rm_rf!(root) end)

    opts = [
      config: %{
        provider: :demo,
        provider_module: Model,
        model: "fixture",
        home: root,
        approval: :deny,
        observability: Map.put(Ipse.Observability.defaults(), "mode", "local")
      },
      cwd: root,
      state_dir: dir,
      subscriber: self()
    ]

    %{root: root, dir: dir, opts: opts}
  end

  test "candidate Session owns its original native header lock and resumes without a gap", c do
    assert {:ok, session} = Session.start_share_candidate_link(c.opts)
    Process.unlink(session)
    state = :sys.get_state(session)
    assert state.lock_mode == :header_share_v2
    assert :sys.get_state(state.lock_guard).mode == :header_share_v2
    lock = Path.join(c.dir, state.id <> ".lock")
    journal = Path.join(c.dir, state.id <> ".jsonl")
    before = File.stat!(lock)
    assert {:error, _} = Runner.protected_lock(lock)
    assert {:ok, [header | _]} = Journal.load(c.dir, state.id)
    assert :ok = Ipse.Journal.SourceOrigin.check_path(c.dir, state.id, header["metadata"])
    assert :ok = Session.prompt(session, "synthetic candidate session")
    assert_receive {:ipse, ^session, {:done, _}}, 10_000
    assert :ok = Session.close_confirmed(session)
    assert {:ok, resumed} = Session.start_share_candidate_link(Keyword.put(c.opts, :id, state.id))
    Process.unlink(resumed)
    assert :sys.get_state(resumed).lock_mode == :resume_share_v2
    assert File.stat!(lock).inode == before.inode
    assert {:error, _} = Runner.protected_lock(lock)
    assert {:ok, [^header | _]} = Journal.load(c.dir, state.id)
    assert File.regular?(journal)
    assert :ok = Session.close_confirmed(resumed)
  end

  test "real Session Writer exposes its frozen journal and source-window snapshot to its owner",
       c do
    assert {:ok, session} = Session.start_share_candidate_link(c.opts)
    Process.unlink(session)
    before = :sys.get_state(session)
    operation = :crypto.strong_rand_bytes(16)
    parent = self()
    job = make_ref()
    generation = make_ref()

    foreign =
      Ipse.Journal.Writer.request_share_barrier(before.journal_writer, operation, job, generation)

    assert {:reply, {:error, :journal_owner_or_record_invalid}} =
             :gen_server.receive_response(foreign, 5_000)

    :sys.replace_state(session, fn s ->
      request =
        Ipse.Journal.Writer.request_share_barrier(s.journal_writer, operation, job, generation)

      result = :gen_server.receive_response(request, 5_000)
      send(parent, {:writer_barrier, result})
      s
    end)

    assert_receive {:writer_barrier, {:reply, {:ok, token, snapshot}}}
    assert snapshot.session_id == before.id
    assert snapshot.job_ref == job and snapshot.owner_generation == generation
    assert is_map(snapshot.source_window)
    assert snapshot.offset == File.stat!(Path.join(c.dir, before.id <> ".jsonl")).size

    :sys.replace_state(session, fn s ->
      arm = Ipse.Session.Lock.request_share_arm(s.lock_guard, s.journal_writer, token, operation)
      arm_result = :gen_server.receive_response(arm, 5_000)
      cancel = Ipse.Session.Lock.request_share_cancel(s.lock_guard, token, operation)
      cancel_result = :gen_server.receive_response(cancel, 5_000)
      thaw_result = Ipse.Journal.Writer.thaw_share_barrier(s.journal_writer, token, operation)
      send(parent, {:writer_thaw, arm_result, cancel_result, thaw_result})
      s
    end)

    assert_receive {:writer_thaw, {:reply, {:ok, transport}}, {:reply, :ok}, :ok}
    assert is_binary(transport) and byte_size(transport) == 16
    assert :ok = Session.close_confirmed(session)
  end

  @tag :native_sandbox
  test "real Session owner death cannot release a flock still held by the stopped recipient", c do
    assert {:ok, session} = Session.start_share_candidate_link(c.opts)
    Process.unlink(session)
    state = :sys.get_state(session)
    operation = :crypto.strong_rand_bytes(16)
    parent = self()

    :sys.replace_state(session, fn s ->
      request =
        Ipse.Journal.Writer.request_share_barrier(
          s.journal_writer,
          operation,
          make_ref(),
          make_ref()
        )

      {:reply, {:ok, token, snapshot}} = :gen_server.receive_response(request, 5_000)
      arm = Ipse.Session.Lock.request_share_arm(s.lock_guard, s.journal_writer, token, operation)
      {:reply, {:ok, transport}} = :gen_server.receive_response(arm, 5_000)
      send(parent, {:session_barrier_ready, token, transport, snapshot})
      s
    end)

    assert_receive {:session_barrier_ready, token, transport, snapshot}
    assert snapshot.session_id == state.id and is_map(snapshot.source_window)
    helper = Path.join(to_string(:code.priv_dir(:ipse)), "ipse-runner")

    collector =
      Port.open({:spawn_executable, String.to_charlist(helper)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :hide,
        args: ["--lease-collect-close-ready-v3"]
      ])

    {:os_pid, collector_pid} = Port.info(collector, :os_pid)
    {:os_pid, exporter_pid} = Port.info(state.lock, :os_pid)
    path = Path.join(c.dir, state.id <> ".lock")
    stat = File.stat!(path)
    name = :crypto.strong_rand_bytes(16)
    secret = :crypto.strong_rand_bytes(32)

    entry =
      <<exporter_pid::32, name::binary, secret::binary, stat.major_device::64, stat.inode::64>>

    init = <<10_000::64, transport::binary, 1, 0, entry::binary>>
    assert Port.command(collector, <<?I, byte_size(init)::32, init::binary>>)
    assert receive_frame(collector, ?H) == <<transport::binary, 1>>

    request =
      <<collector_pid::32, name::binary, secret::binary, stat.major_device::64, stat.inode::64>>

    :sys.replace_state(session, fn s ->
      pending =
        Ipse.Session.Lock.request_share_export(
          s.lock_guard,
          token,
          operation,
          request,
          System.monotonic_time(:millisecond) + 5_000
        )

      send(parent, {:session_export, :gen_server.receive_response(pending, 5_000)})
      s
    end)

    assert_receive {:session_export, {:reply, :ok}}
    assert receive_frame(collector, ?L) == <<transport::binary, 1>>
    session_ref = Process.monitor(session)
    guard_ref = Process.monitor(state.lock_guard)
    assert {_, 0} = System.cmd("kill", ["-STOP", Integer.to_string(collector_pid)])

    try do
      Process.exit(session, :kill)
      assert_receive {:DOWN, ^session_ref, :process, ^session, _}, 8_000
      assert_receive {:DOWN, ^guard_ref, :process, _, _}, 8_000
      assert {:error, _} = Runner.protected_lock(path)
    after
      System.cmd("kill", ["-CONT", Integer.to_string(collector_pid)])
    end

    assert_eventually_unlocked(path, 300)
  end

  defp receive_frame(port, kind, buffer \\ <<>>) do
    case buffer do
      <<^kind, length::32, body::binary-size(length)>> ->
        body

      _ ->
        receive do
          {^port, {:data, bytes}} when byte_size(buffer) + byte_size(bytes) <= 256 ->
            receive_frame(port, kind, buffer <> bytes)

          {^port, {:exit_status, status}} ->
            flunk("collector exited before reply: #{status}")
        after
          8_000 -> flunk("collector response timed out")
        end
    end
  end

  defp assert_eventually_unlocked(_, 0), do: flunk("retained recipient did not release the flock")

  defp assert_eventually_unlocked(path, attempts) do
    case Runner.protected_lock(path) do
      {:ok, port} ->
        assert :ok = Runner.unlock(port)

      _ ->
        Process.sleep(10)
        assert_eventually_unlocked(path, attempts - 1)
    end
  end
end
