defmodule Ipse.Session.ShareBarrierTest do
  use ExUnit.Case, async: false
  @moduletag skip: if(:os.type() == {:unix, :linux}, do: false, else: "Linux native share")
  alias Ipse.{Journal, Runner}
  alias Ipse.Journal.Writer
  alias Ipse.Session.Lock

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-share-barrier-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  defp start_owned(c) do
    id = Ipse.Usage.id()
    path = Path.join(c.root, id <> ".lock")
    assert {:ok, port} = Lock.acquire_share_header(path)
    guard = Lock.current()
    metadata = %{"source_origin_layout" => Ipse.Journal.SourceOrigin.layout()}
    assert {:ok, ^id} = Journal.create_with_locked_id(c.root, id, metadata, nil, guard)
    assert {:ok, writer} = Writer.start(c.root, id, self(), nil, :header_share_v2)
    assert :ok = Lock.track(writer, :writer)
    assert :ok = Writer.append(writer, %{"type" => "fixture_before"})
    %{id: id, path: path, port: port, guard: guard, writer: writer}
  end

  defp response(request) do
    assert {:reply, value} = :gen_server.receive_response(request, 8_000)
    value
  end

  defp barrier(s, operation) do
    request = Writer.request_share_barrier(s.writer, operation, make_ref(), make_ref())
    assert {:ok, token, snapshot} = response(request)
    assert snapshot.session_id == s.id
    assert snapshot.offset == File.stat!(Path.join(Path.dirname(s.path), s.id <> ".jsonl")).size

    assert {:ok, transport} =
             response(Lock.request_share_arm(s.guard, s.writer, token, operation))

    assert is_binary(transport) and byte_size(transport) == 16
    {token, transport}
  end

  defp finish(s) do
    assert :ok = Writer.close(s.writer)
    assert :ok = Lock.release(s.guard)
  end

  test "writer barrier drains, refuses new mutations, and cancels before export", c do
    s = start_owned(c)
    operation = :crypto.strong_rand_bytes(16)
    {token, _transport} = barrier(s, operation)
    assert {:error, :journal_share_frozen} = Writer.append(s.writer, %{"type" => "forbidden"})

    assert {:error, :journal_write_unconfirmed} =
             Writer.thaw_share_barrier(s.writer, token, operation)

    assert :ok = response(Lock.request_share_cancel(s.guard, token, operation))
    assert :ok = Writer.thaw_share_barrier(s.writer, token, operation)
    assert :ok = Writer.append(s.writer, %{"type" => "fixture_after"})
    finish(s)
    assert {:ok, events} = Journal.load(c.root, s.id)
    refute Enum.any?(events, &(&1["type"] == "forbidden"))
    assert Enum.any?(events, &(&1["type"] == "fixture_after"))
  end

  defp source_window(s, root) do
    assert {:ok, events} = Journal.load(root, s.id)
    assert {:ok, window} = Ipse.Session.SourceWindow.restore(events, s.id)
    assert :ok = Writer.install_source_window(s.writer, window)
  end

  defp private_lock(directory, id) do
    path = Path.join(directory, id <> ".lock")
    File.write!(path, "", [:exclusive])
    File.chmod!(path, 0o600)
    path
  end

  @tag :approval_journal_snapshot
  test "approval barrier binds both inactive source and management journal inodes", c do
    s = start_owned(c)
    source_window(s, c.root)
    directory = Path.join(c.root, "knowledge-management")
    File.mkdir!(directory)
    File.chmod!(directory, 0o700)
    source = Ipse.Usage.id()
    journal = Ipse.Usage.id()
    source_path = private_lock(c.root, source)
    journal_path = private_lock(directory, journal)
    operation = :crypto.strong_rand_bytes(16)

    request =
      Writer.request_share_barrier_display_sources(
        s.writer,
        operation,
        make_ref(),
        make_ref(),
        [],
        [source],
        %{directory: directory, ids: [journal]}
      )

    assert {:ok, token, snapshot} = response(request)

    expected =
      for {id, path} <- [{source, source_path}, {journal, journal_path}] do
        stat = File.stat!(path)
        %{session_id: id, device: stat.major_device, inode: stat.inode}
      end

    assert snapshot.inactive_source_locks == expected

    assert {:ok, _} = response(Lock.request_share_arm(s.guard, s.writer, token, operation))
    assert :ok = response(Lock.request_share_cancel(s.guard, token, operation))
    assert :ok = Writer.thaw_share_barrier(s.writer, token, operation)
    assert :ok = Writer.append(s.writer, %{"type" => "after_approval_snapshot"})
    finish(s)
  end

  for fault <- [:missing, :symlink, :hardlink, :permissions, :duplicate, :invalid_id] do
    @tag :approval_journal_snapshot
    test "approval journal #{fault} refuses before freezing the writer", c do
      s = start_owned(c)
      source_window(s, c.root)
      directory = Path.join(c.root, "knowledge-management")
      File.mkdir!(directory)
      File.chmod!(directory, 0o700)
      id = Ipse.Usage.id()
      path = private_lock(directory, id)

      ids =
        case unquote(fault) do
          :missing ->
            File.rm!(path)
            [id]

          :symlink ->
            File.rename!(path, path <> ".real")
            File.ln_s!(path <> ".real", path)
            [id]

          :hardlink ->
            File.ln!(path, path <> ".copy")
            [id]

          :permissions ->
            File.chmod!(path, 0o644)
            [id]

          :duplicate ->
            [id, id]

          :invalid_id ->
            ["../" <> id]
        end

      assert {:error, :source_index_refused} =
               response(
                 Writer.request_share_barrier_display_sources(
                   s.writer,
                   :crypto.strong_rand_bytes(16),
                   make_ref(),
                   make_ref(),
                   [],
                   [],
                   %{directory: directory, ids: ids}
                 )
               )

      assert :sys.get_state(s.writer).share_barrier == nil
      assert :ok = Writer.append(s.writer, %{"type" => "after_refused_approval_snapshot"})
      finish(s)
    end
  end

  @tag :approval_journal_snapshot
  test "approval barrier refuses a combined source and journal count above 128", c do
    s = start_owned(c)
    source_window(s, c.root)
    directory = Path.join(c.root, "knowledge-management")
    File.mkdir!(directory)
    File.chmod!(directory, 0o700)

    sources = for _ <- 1..64, do: Ipse.Usage.id()
    journals = for _ <- 1..65, do: Ipse.Usage.id()
    for id <- sources, do: private_lock(c.root, id)
    for id <- journals, do: private_lock(directory, id)

    assert {:error, :source_index_refused} =
             response(
               Writer.request_share_barrier_display_sources(
                 s.writer,
                 :crypto.strong_rand_bytes(16),
                 make_ref(),
                 make_ref(),
                 [],
                 Enum.sort(sources),
                 %{directory: directory, ids: Enum.sort(journals)}
               )
             )

    assert :sys.get_state(s.writer).share_barrier == nil
    assert :ok = Writer.append(s.writer, %{"type" => "after_refused_approval_capacity"})
    finish(s)
  end

  test "barrier records only the two immediately preceding acceptance event digests", c do
    s = start_owned(c)
    event = %{"type" => "pending_proposal_accepted", "fixture" => "review"}
    intent = %{"type" => "pending_acceptance_intent", "fixture" => "intent"}
    assert {:ok, reserved} = Writer.reserve(s.writer, %{bytes: 4096, events: 3})
    assert :ok = Writer.append_reserved(s.writer, reserved, event)
    assert :ok = Writer.append_reserved(s.writer, reserved, intent)

    operation = :crypto.strong_rand_bytes(16)

    assert {:ok, token, snapshot} =
             response(Writer.request_share_barrier(s.writer, operation, make_ref(), make_ref()))

    assert snapshot.recent_acceptance === [Ipse.JSON.digest([event]), Ipse.JSON.digest([intent])]
    assert {:ok, _} = response(Lock.request_share_arm(s.guard, s.writer, token, operation))
    assert :ok = response(Lock.request_share_cancel(s.guard, token, operation))
    assert :ok = Writer.thaw_share_barrier(s.writer, token, operation)
    assert :ok = Writer.append_reserved(s.writer, reserved, %{"type" => "unrelated"})

    operation = :crypto.strong_rand_bytes(16)

    assert {:ok, token, snapshot} =
             response(Writer.request_share_barrier(s.writer, operation, make_ref(), make_ref()))

    assert snapshot.recent_acceptance === [Ipse.JSON.digest([intent]), nil]
    assert {:ok, _} = response(Lock.request_share_arm(s.guard, s.writer, token, operation))
    assert :ok = response(Lock.request_share_cancel(s.guard, token, operation))
    assert :ok = Writer.thaw_share_barrier(s.writer, token, operation)
    assert :ok = Writer.release(s.writer, reserved)
    finish(s)
  end

  test "barrier binds only the immediately preceding synced lifecycle intent", c do
    s = start_owned(c)
    intent = %{"type" => "managed_lifecycle_intent", "fixture" => "intent"}
    assert {:ok, reserved} = Writer.reserve(s.writer, %{bytes: 4096, events: 2})
    assert :ok = Writer.append_reserved(s.writer, reserved, intent)

    operation = :crypto.strong_rand_bytes(16)

    assert {:ok, token, snapshot} =
             response(Writer.request_share_barrier(s.writer, operation, make_ref(), make_ref()))

    assert snapshot.recent_lifecycle_intent === Ipse.JSON.digest([intent])
    assert {:ok, _} = response(Lock.request_share_arm(s.guard, s.writer, token, operation))
    assert :ok = response(Lock.request_share_cancel(s.guard, token, operation))
    assert :ok = Writer.thaw_share_barrier(s.writer, token, operation)
    assert :ok = Writer.append_reserved(s.writer, reserved, %{"type" => "unrelated"})

    operation = :crypto.strong_rand_bytes(16)

    assert {:ok, token, snapshot} =
             response(Writer.request_share_barrier(s.writer, operation, make_ref(), make_ref()))

    assert snapshot.recent_lifecycle_intent === nil
    assert {:ok, _} = response(Lock.request_share_arm(s.guard, s.writer, token, operation))
    assert :ok = response(Lock.request_share_cancel(s.guard, token, operation))
    assert :ok = Writer.thaw_share_barrier(s.writer, token, operation)
    assert :ok = Writer.release(s.writer, reserved)
    finish(s)
  end

  test "a concurrent premature thaw cannot deadlock the Writer and lock guard", c do
    s = start_owned(c)
    operation = :crypto.strong_rand_bytes(16)
    request = Writer.request_share_barrier(s.writer, operation, make_ref(), make_ref())
    assert {:ok, token, _snapshot} = response(request)
    :ok = :sys.suspend(s.writer)
    thaw = :gen_server.send_request(s.writer, {:share_thaw, token, operation})
    arm = Lock.request_share_arm(s.guard, s.writer, token, operation)
    :ok = :sys.resume(s.writer)
    assert {:ok, _transport} = response(arm)
    assert {:error, :journal_write_unconfirmed} = response(thaw)
    assert :ok = response(Lock.request_share_cancel(s.guard, token, operation))
    assert :ok = Writer.thaw_share_barrier(s.writer, token, operation)
    finish(s)
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

  defp share_once(s) do
    operation = :crypto.strong_rand_bytes(16)
    {token, transport} = barrier(s, operation)
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
    {:os_pid, exporter_pid} = Port.info(s.port, :os_pid)
    stat = File.stat!(s.path)
    name = :crypto.strong_rand_bytes(16)
    secret = :crypto.strong_rand_bytes(32)

    entry =
      <<exporter_pid::32, name::binary, secret::binary, stat.major_device::64, stat.inode::64>>

    init = <<10_000::64, transport::binary, 1, 0, entry::binary>>
    assert Port.command(collector, <<?I, byte_size(init)::32, init::binary>>)
    assert receive_frame(collector, ?H) == <<transport::binary, 1>>

    request =
      <<collector_pid::32, name::binary, secret::binary, stat.major_device::64, stat.inode::64>>

    deadline = System.monotonic_time(:millisecond) + 5_000
    assert :ok = response(Lock.request_share_export(s.guard, token, operation, request, deadline))
    assert receive_frame(collector, ?L) == <<transport::binary, 1>>
    assert {:error, _} = Runner.protected_lock(s.path)
    assert {:error, :journal_share_frozen} = Writer.append(s.writer, %{"type" => "forbidden"})

    assert {:error, :journal_write_unconfirmed} =
             Writer.thaw_share_barrier(s.writer, token, operation)

    assert Port.command(collector, <<?C, transport::binary>>)
    deadline = System.monotonic_time(:millisecond) + 5_000
    assert :ok = response(Lock.request_share_settle(s.guard, token, operation, deadline))
    assert receive_frame(collector, ?C) == <<transport::binary, 1>>
    assert_receive {^collector, {:exit_status, 0}}, 8_000
    assert {:error, _} = Runner.protected_lock(s.path)
    assert :ok = Writer.thaw_share_barrier(s.writer, token, operation)
    :ok
  end

  @tag :native_sandbox
  test "original header owner stays locked through recipient close, then writer thaws", c do
    s = start_owned(c)
    assert :ok = share_once(s)
    assert :ok = share_once(s)
    assert :ok = Writer.append(s.writer, %{"type" => "fixture_after_share"})
    finish(s)
    assert {:ok, events} = Journal.load(c.root, s.id)
    refute Enum.any?(events, &(&1["type"] == "forbidden"))
    assert Enum.any?(events, &(&1["type"] == "fixture_after_share"))
  end

  @tag :native_sandbox
  test "resume owner shares the original lock without replacing the journal", c do
    original = start_owned(c)
    inode = File.stat!(original.path).inode
    journal = Path.join(c.root, original.id <> ".jsonl")
    before = File.read!(journal)
    finish(original)
    assert {:ok, port} = Lock.acquire_share_resume(original.path)
    guard = Lock.current()
    assert {:ok, writer} = Writer.start(c.root, original.id, self(), nil, :resume_share_v2)
    assert :ok = Lock.track(writer, :writer)
    resumed = %{original | port: port, guard: guard, writer: writer}
    assert File.stat!(resumed.path).inode == inode
    assert :ok = share_once(resumed)
    assert File.read!(journal) == before
    finish(resumed)
  end

  @tag :native_sandbox
  test "owner death leaves the original flock held by a stopped recipient until it exits", c do
    parent = self()

    {owner, owner_monitor} =
      spawn_monitor(fn ->
        s = start_owned(c)
        operation = :crypto.strong_rand_bytes(16)
        {token, transport} = barrier(s, operation)
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
        {:os_pid, exporter_pid} = Port.info(s.port, :os_pid)
        stat = File.stat!(s.path)
        name = :crypto.strong_rand_bytes(16)
        secret = :crypto.strong_rand_bytes(32)

        entry =
          <<exporter_pid::32, name::binary, secret::binary, stat.major_device::64,
            stat.inode::64>>

        init = <<10_000::64, transport::binary, 1, 0, entry::binary>>
        assert Port.command(collector, <<?I, byte_size(init)::32, init::binary>>)
        assert receive_frame(collector, ?H) == <<transport::binary, 1>>

        request =
          <<collector_pid::32, name::binary, secret::binary, stat.major_device::64,
            stat.inode::64>>

        assert :ok =
                 response(
                   Lock.request_share_export(
                     s.guard,
                     token,
                     operation,
                     request,
                     System.monotonic_time(:millisecond) + 5_000
                   )
                 )

        assert receive_frame(collector, ?L) == <<transport::binary, 1>>
        send(parent, {:share_held, self(), s.path, s.guard, collector_pid})

        receive do
          :finish -> :ok
        end
      end)

    assert_receive {:share_held, ^owner, path, guard, collector_pid}, 8_000
    guard_monitor = Process.monitor(guard)
    assert {_, 0} = System.cmd("kill", ["-STOP", Integer.to_string(collector_pid)])

    try do
      Process.exit(owner, :kill)
      assert_receive {:DOWN, ^owner_monitor, :process, ^owner, _}, 8_000
      assert_receive {:DOWN, ^guard_monitor, :process, ^guard, _}, 8_000
      assert {:error, _} = Runner.protected_lock(path)
    after
      System.cmd("kill", ["-CONT", Integer.to_string(collector_pid)])
    end

    assert_eventually_unlocked(path, 300)
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
