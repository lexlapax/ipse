defmodule Ipse.Session.NativeHeaderSessionTest do
  use ExUnit.Case, async: false
  @moduletag skip: if(:os.type() == {:unix, :linux}, do: false, else: "Linux header helper")
  alias Ipse.{Journal, Runner, Session}

  defmodule Model do
    def complete(_, _, _, _),
      do: {:ok, %{"role" => "assistant", "content" => "fixture answer"}, %{}}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-native-header-session-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    dir = Path.join(root, "state")
    File.mkdir!(dir)
    File.chmod!(dir, 0o700)
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

  test "fresh Session binds actual header inode under the lock and resumes", c do
    {:ok, session} = Session.start_link(c.opts)
    Process.unlink(session)
    state = :sys.get_state(session)
    assert state.lock_mode == :header_v1
    assert :sys.get_state(state.lock_guard).mode == :header_v1
    journal = Path.join(c.dir, state.id <> ".jsonl")
    lock = Path.join(c.dir, state.id <> ".lock")
    refute Enum.any?(File.ls!(c.dir), &String.starts_with?(&1, ".pending-header-"))
    assert {:ok, [%{"metadata" => metadata} | _]} = Journal.load(c.dir, state.id)
    assert metadata["release_receipt_layout"] == Ipse.Session.ReleaseReceipt.layout()
    assert {:ok, initial_events} = Journal.load(c.dir, state.id)

    assert [first_owner] =
             Enum.filter(initial_events, &(&1["type"] == "session_release_owner_started"))

    assert first_owner == state.release_owner
    origin = metadata["source_origin"]
    stat = File.stat!(journal)

    assert {origin["major_device"], origin["inode"], origin["uid"]} ==
             {stat.major_device, stat.inode, stat.uid}

    assert :ok = Ipse.Journal.SourceOrigin.check_path(c.dir, state.id, metadata)
    assert {:error, _} = Runner.protected_lock(lock)

    assert {:error, _} =
             Ipse.Session.Lock.header_identity(
               state.lock_guard,
               System.monotonic_time(:millisecond) + 2_000
             )

    parent = self()

    :sys.replace_state(session, fn s ->
      send(
        parent,
        {:lock_identity,
         Ipse.Session.Lock.header_identity(
           s.lock_guard,
           System.monotonic_time(:millisecond) + 2_000
         )}
      )

      s
    end)

    lock_stat = File.stat!(lock)
    assert_receive {:lock_identity, {:ok, %{device: device, inode: inode}}}
    assert {device, inode} == {lock_stat.major_device, lock_stat.inode}
    assert :ok = Session.prompt(session, "synthetic header session")
    assert_receive {:ipse, ^session, {:done, _}}, 10_000
    assert :ok = Session.close_confirmed(session)
    assert {:ok, events} = Journal.load(c.dir, state.id)
    assert {:ok, intent} = Ipse.Session.ReleaseReceipt.current_intent(events, state.id)
    assert is_map(intent)
    receipt_path = Path.join(c.dir, ".release-#{state.id}-#{intent["operation_id"]}")
    assert {:ok, receipt} = File.read(receipt_path)
    assert Bitwise.band(File.stat!(receipt_path).mode, 0o077) == 0

    assert :signed_release_claim ==
             Ipse.Session.ReleaseReceipt.classify_current(events, state.id, receipt)

    lock_identity = %{device: intent["lock_device"], inode: intent["lock_inode"]}

    assert {:error, :cleanup_unconfirmed} =
             Runner.publish_session_release(
               c.dir,
               state.id,
               intent["operation_id"],
               origin,
               lock_identity,
               receipt
             )

    assert File.read!(receipt_path) == receipt
    wrong_operation = Ipse.Usage.id()

    assert {:error, :cleanup_unconfirmed} =
             Runner.publish_session_release(
               c.dir,
               state.id,
               wrong_operation,
               Map.update!(origin, "inode", &(&1 + 1)),
               lock_identity,
               receipt
             )

    refute File.exists?(Path.join(c.dir, ".release-#{state.id}-#{wrong_operation}"))

    wrong_lock_operation = Ipse.Usage.id()

    assert {:error, :cleanup_unconfirmed} =
             Runner.publish_session_release(
               c.dir,
               state.id,
               wrong_lock_operation,
               origin,
               %{lock_identity | inode: lock_identity.inode + 1},
               receipt
             )

    refute File.exists?(Path.join(c.dir, ".release-#{state.id}-#{wrong_lock_operation}"))

    assert %{"cleanup_confirmed" => false} =
             closure =
             Enum.find(events, &(&1["type"] == "lifecycle_epoch_closed"))

    assert {:ok, "session.close_committed", nil, nil, %{"cleanup_confirmed" => false}, _} =
             Ipse.Session.RuntimeLifecycle.describe(closure)

    assert {:ok, diagnosis} = Ipse.Session.Saved.inspect_saved(c.dir, state.id)
    assert diagnosis["release_claim"] == "signed_release_claim"
    File.write!(receipt_path, receipt <> "x")

    assert {:ok, %{"release_claim" => "unknown"}} =
             Ipse.Session.Saved.inspect_saved(c.dir, state.id)

    File.write!(receipt_path, receipt)
    refute Map.has_key?(diagnosis, "cleanup_confirmed")
    {:ok, resumed} = Session.start_link(Keyword.put(c.opts, :id, state.id))
    Process.unlink(resumed)
    assert :sys.get_state(:sys.get_state(resumed).lock_guard).mode == :resume_v1
    assert :sys.get_state(resumed).lock_mode == :resume_v1
    assert {:ok, resumed_events} = Journal.load(c.dir, state.id)

    assert [^first_owner, second_owner] =
             Enum.filter(resumed_events, &(&1["type"] == "session_release_owner_started"))

    refute first_owner["owner_id"] == second_owner["owner_id"]
    assert {:ok, nil} = Ipse.Session.ReleaseReceipt.current_intent(resumed_events, state.id)

    assert :unknown ==
             Ipse.Session.ReleaseReceipt.classify_current(resumed_events, state.id, receipt)

    assert {:ok, %{"release_claim" => "unknown"}} =
             Ipse.Session.Saved.inspect_saved(c.dir, state.id)

    assert :ok = Session.close_confirmed(resumed)

    assert {:ok, after_resume} = Journal.load(c.dir, state.id)
    assert hd(after_resume) == hd(events)
    assert File.stat!(journal).inode == stat.inode

    assert {:ok, [^intent, next_intent]} =
             Ipse.Session.ReleaseReceipt.intents(after_resume, state.id)

    assert next_intent["owner_id"] == second_owner["owner_id"]
    assert next_intent["epoch_id"] != intent["epoch_id"]
    assert Enum.find(after_resume, &(&1["type"] == "lifecycle_epoch_closed")) == closure

    assert {:ok, ^next_intent} =
             Ipse.Session.ReleaseReceipt.current_intent(after_resume, state.id)

    assert :unknown ==
             Ipse.Session.ReleaseReceipt.classify_current(after_resume, state.id, receipt)

    assert {:ok, %{"release_claim" => "signed_release_claim"}} =
             Ipse.Session.Saved.inspect_saved(c.dir, state.id)
  end

  test "close reports unknown when the actual lock helper dies before its release reply", c do
    {:ok, session} = Session.start_link(c.opts)
    Process.unlink(session)
    state = :sys.get_state(session)
    {:os_pid, native} = Port.info(state.lock, :os_pid)
    :ok = :sys.suspend(session)

    on_exit(fn ->
      if Process.alive?(session), do: :sys.resume(session)
      if Process.alive?(session), do: Process.exit(session, :kill)
    end)

    parent = self()
    writer_ref = Process.monitor(state.journal_writer)
    spawn(fn -> send(parent, {:close_result, Session.close_confirmed(session)}) end)
    wait_for_close(session, System.monotonic_time(:millisecond) + 5_000)
    {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(native)])
    wait_for_lock_loss(session, state.lock, System.monotonic_time(:millisecond) + 5_000)
    :ok = :sys.resume(session)
    assert_receive {:DOWN, ^writer_ref, :process, _, _}, 5_000
    assert_receive {:close_result, {:error, :cleanup_unconfirmed}}, 5_000
    assert {:ok, events} = Journal.load(c.dir, state.id)
    assert {:ok, nil} = Ipse.Session.ReleaseReceipt.current_intent(events, state.id)
    refute Enum.any?(File.ls!(c.dir), &String.starts_with?(&1, ".release-#{state.id}-"))

    assert {:ok, %{"release_claim" => "unknown"}} =
             Ipse.Session.Saved.inspect_saved(c.dir, state.id)
  end

  test "versioned journal repairs a torn tail before recording a new owner", c do
    {:ok, session} = Session.start_link(c.opts)
    Process.unlink(session)
    id = :sys.get_state(session).id
    assert :ok = Session.close_confirmed(session)
    path = Path.join(c.dir, id <> ".jsonl")
    File.write!(path, ~s({"type":"interrupted), [:append])
    {:ok, resumed} = Session.start_link(Keyword.put(c.opts, :id, id))
    Process.unlink(resumed)
    assert {:ok, events} = Journal.load(c.dir, id)
    assert length(Enum.filter(events, &(&1["type"] == "session_release_owner_started"))) == 2
    assert {:ok, nil} = Ipse.Session.ReleaseReceipt.current_intent(events, id)
    assert :ok = Session.close_confirmed(resumed)
  end

  test "a fresh header lock anchor permits recovery after the owner dies before an intent", c do
    {:ok, session} = Session.start_link(c.opts)
    Process.unlink(session)
    state = :sys.get_state(session)
    guard = Process.monitor(state.lock_guard)
    Process.exit(session, :kill)
    assert_receive {:DOWN, ^guard, :process, _, _}, 5_000
    assert {:ok, events} = Journal.load(c.dir, state.id)
    assert {:ok, []} = Ipse.Session.ReleaseReceipt.intents(events, state.id)

    anchor = hd(events)["metadata"]["session_lock_identity"]
    assert %{"version" => 1, "device" => _, "inode" => _} = anchor
    lock_stat = File.stat!(Path.join(c.dir, state.id <> ".lock"))
    assert {anchor["device"], anchor["inode"]} == {lock_stat.major_device, lock_stat.inode}
    old_epoch = Enum.find(events, &(&1["type"] == "lifecycle_epoch_started"))["epoch_id"]
    {:ok, resumed} = Session.start_link(Keyword.put(c.opts, :id, state.id))
    Process.unlink(resumed)
    assert :sys.get_state(resumed).lock_mode == :resume_v1
    assert :ok = Session.close_confirmed(resumed)

    assert {:ok, after_resume} = Journal.load(c.dir, state.id)
    assert hd(after_resume) == hd(events)

    refute Enum.any?(
             after_resume,
             &(&1["type"] == "lifecycle_epoch_closed" and &1["epoch_id"] == old_epoch)
           )

    assert {:ok, [_]} = Ipse.Session.ReleaseReceipt.intents(after_resume, state.id)

    assert {:ok, %{"release_claim" => "signed_release_claim"}} =
             Ipse.Session.Saved.inspect_saved(c.dir, state.id)
  end

  test "an older opted-in header without any lock anchor refuses unfenced resume", c do
    {:ok, first} = Session.start_link(c.opts)
    Process.unlink(first)
    state = :sys.get_state(first)
    guard = Process.monitor(state.lock_guard)
    Process.exit(first, :kill)
    assert_receive {:DOWN, ^guard, :process, _, _}, 5_000
    assert {:ok, [header | tail]} = Journal.load(c.dir, state.id)
    older_header = update_in(header, ["metadata"], &Map.delete(&1, "session_lock_identity"))
    path = Path.join(c.dir, state.id <> ".jsonl")
    File.write!(path, Enum.map_join([older_header | tail], "", &(Jason.encode!(&1) <> "\n")))
    before = File.read!(path)

    assert {:error, :session_lock_identity_unavailable} =
             refused_start(Keyword.put(c.opts, :id, state.id))

    assert File.read!(path) == before
  end

  test "a legacy header is not upgraded to the release-claim layout", c do
    {:ok, first} = Session.start_link(c.opts)
    Process.unlink(first)
    state = :sys.get_state(first)
    guard = Process.monitor(state.lock_guard)
    Process.exit(first, :kill)
    assert_receive {:DOWN, ^guard, :process, _, _}, 5_000
    assert {:ok, [header | _]} = Journal.load(c.dir, state.id)
    legacy_header = update_in(header, ["metadata"], &Map.delete(&1, "release_receipt_layout"))
    path = Path.join(c.dir, state.id <> ".jsonl")
    File.write!(path, Jason.encode!(legacy_header) <> "\n")
    before = File.stat!(path).inode
    {:ok, resumed} = Session.start_link(Keyword.put(c.opts, :id, state.id))
    Process.unlink(resumed)
    assert :sys.get_state(resumed).lock_mode == :legacy
    assert :ok = Session.close_confirmed(resumed)
    assert {:ok, [^legacy_header | events]} = Journal.load(c.dir, state.id)
    assert File.stat!(path).inode == before

    refute Enum.any?(
             events,
             &(&1["type"] in ~w(session_release_owner_started session_release_intent))
           )

    assert {:ok, %{"release_claim" => "unknown"}} =
             Ipse.Session.Saved.inspect_saved(c.dir, state.id)
  end

  test "framed resume refuses a missing or substituted lock inode", c do
    {:ok, session} = Session.start_link(c.opts)
    Process.unlink(session)
    id = :sys.get_state(session).id
    assert :ok = Session.close_confirmed(session)
    journal_path = Path.join(c.dir, id <> ".jsonl")
    lock_path = Path.join(c.dir, id <> ".lock")
    saved_lock = lock_path <> ".fixture-original"
    original = File.read!(journal_path)
    File.rename!(lock_path, saved_lock)
    assert {:error, _} = refused_start(Keyword.put(c.opts, :id, id))
    refute File.exists?(lock_path)
    assert File.read!(journal_path) == original
    File.write!(lock_path, "")
    File.chmod!(lock_path, 0o600)

    assert {:error, :session_lock_identity_unavailable} =
             refused_start(Keyword.put(c.opts, :id, id))

    assert File.read!(journal_path) == original
    File.rm!(lock_path)
    File.rename!(saved_lock, lock_path)
    {:ok, resumed} = Session.start_link(Keyword.put(c.opts, :id, id))
    Process.unlink(resumed)
    assert :sys.get_state(resumed).lock_mode == :resume_v1
    assert :ok = Session.close_confirmed(resumed)
  end

  @tag skip: System.get_env("IPSE_OLD_RESUME_GRAPH") == nil
  test "an old pinned helper refuses framed resume without legacy fallback", c do
    {:ok, first} = Session.start_link(c.opts)
    Process.unlink(first)
    id = :sys.get_state(first).id
    assert :ok = Session.close_confirmed(first)
    journal_path = Path.join(c.dir, id <> ".jsonl")
    before = File.read!(journal_path)
    helper_graph = System.fetch_env!("IPSE_OLD_RESUME_GRAPH")

    child =
      Port.open({:spawn_executable, System.find_executable("elixir")}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        :hide,
        args: ["test/support/release_resume_old_helper.exs"],
        env: [
          {~c"IPSE_RELEASE_TEST_ROOT", String.to_charlist(c.root)},
          {~c"IPSE_RELEASE_TEST_SESSION", String.to_charlist(id)},
          {~c"ERL_LIBS", String.to_charlist(helper_graph)}
        ]
      ])

    on_exit(fn -> if Port.info(child), do: Port.close(child) end)
    assert {output, 0} = await_child(child, "", System.monotonic_time(:millisecond) + 5_000)
    assert output =~ "OLD_RESUME_HELPER_REFUSED_UNKNOWN_COMMAND"
    assert File.read!(journal_path) == before
  end

  defp refused_start(opts) do
    Task.async(fn ->
      Process.flag(:trap_exit, true)
      Session.start_link(opts)
    end)
    |> Task.await(5_000)
  end

  test "lost resumed helper cannot produce a new release claim", c do
    {:ok, first} = Session.start_link(c.opts)
    Process.unlink(first)
    id = :sys.get_state(first).id
    assert :ok = Session.close_confirmed(first)
    {:ok, resumed} = Session.start_link(Keyword.put(c.opts, :id, id))
    Process.unlink(resumed)
    state = :sys.get_state(resumed)
    assert state.lock_mode == :resume_v1
    {:os_pid, native} = Port.info(state.lock, :os_pid)
    :ok = :sys.suspend(resumed)
    parent = self()
    spawn(fn -> send(parent, {:resume_close, Session.close_confirmed(resumed)}) end)
    wait_for_close(resumed, System.monotonic_time(:millisecond) + 5_000)
    {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(native)])
    wait_for_lock_loss(resumed, state.lock, System.monotonic_time(:millisecond) + 5_000)
    :ok = :sys.resume(resumed)
    assert_receive {:resume_close, {:error, :cleanup_unconfirmed}}, 5_000
    assert {:ok, events} = Journal.load(c.dir, id)
    assert {:ok, [_old]} = Ipse.Session.ReleaseReceipt.intents(events, id)
    assert {:ok, nil} = Ipse.Session.ReleaseReceipt.current_intent(events, id)
    assert {:ok, %{"release_claim" => "unknown"}} = Ipse.Session.Saved.inspect_saved(c.dir, id)
  end

  test "the existing-journal native lock refuses header creation", c do
    {:ok, first} = Session.start_link(c.opts)
    Process.unlink(first)
    id = :sys.get_state(first).id
    assert :ok = Session.close_confirmed(first)
    journal = Path.join(c.dir, id <> ".jsonl")
    before = File.read!(journal)
    assert {:ok, port} = Runner.protected_resume_lock(Path.join(c.dir, id <> ".lock"))

    assert {:error, :header_unconfirmed} =
             Runner.session_header_begin(port, System.monotonic_time(:millisecond) + 2_000)

    assert {:error, :cleanup_unconfirmed} = Runner.unlock_export_candidate(port)
    assert File.read!(journal) == before
    refute File.exists?(Path.join(c.dir, ".pending-header-" <> id))
  end

  @tag skip: System.get_env("IPSE_RELEASE_HOOK_TEST") != "1"
  test "owner death after durable publication leaves the close reply unknown", c do
    System.put_env("IPSE_TEST_RELEASE_HOOK", c.root)
    on_exit(fn -> System.delete_env("IPSE_TEST_RELEASE_HOOK") end)
    {:ok, session} = Session.start_link(c.opts)
    Process.unlink(session)
    state = :sys.get_state(session)
    monitor = Process.monitor(session)
    parent = self()
    spawn(fn -> send(parent, {:interrupted_close, Session.close_confirmed(session)}) end)
    ready = Path.join(c.root, "release-published.ready")
    wait_file(ready, System.monotonic_time(:millisecond) + 5_000)
    Process.exit(session, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^session, :killed}, 5_000
    File.write!(Path.join(c.root, "release-published.go"), "go")
    assert_receive {:interrupted_close, {:error, :cleanup_unconfirmed}}, 5_000
    assert {:ok, events} = Journal.load(c.dir, state.id)
    assert {:ok, intent} = Ipse.Session.ReleaseReceipt.current_intent(events, state.id)
    assert is_map(intent)

    assert {:ok, %{"release_claim" => "signed_release_claim"}} =
             Ipse.Session.Saved.inspect_saved(c.dir, state.id)
  end

  @tag skip: System.get_env("IPSE_RELEASE_HOOK_TEST") != "1"
  test "owner death after native unlock before its reply never signs", c do
    System.put_env("IPSE_TEST_RELEASE_BEFORE_ACK", c.root)
    on_exit(fn -> System.delete_env("IPSE_TEST_RELEASE_BEFORE_ACK") end)
    {:ok, session} = Session.start_link(c.opts)
    System.delete_env("IPSE_TEST_RELEASE_BEFORE_ACK")
    Process.unlink(session)
    state = :sys.get_state(session)
    monitor = Process.monitor(session)
    parent = self()
    spawn(fn -> send(parent, {:interrupted_unlock, Session.close_confirmed(session)}) end)

    wait_file(
      Path.join(c.root, "release-unlocked.ready"),
      System.monotonic_time(:millisecond) + 5_000
    )

    lock_path = Path.join(c.dir, state.id <> ".lock")
    assert {:ok, contender} = Runner.protected_header_lock(lock_path)
    assert :ok = Runner.unlock_export_candidate(contender)
    Process.exit(session, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^session, :killed}, 5_000
    File.write!(Path.join(c.root, "release-unlocked.go"), "go")
    assert_receive {:interrupted_unlock, {:error, :cleanup_unconfirmed}}, 5_000
    assert {:ok, events} = Journal.load(c.dir, state.id)
    assert {:ok, intent} = Ipse.Session.ReleaseReceipt.current_intent(events, state.id)
    assert is_map(intent)
    refute Enum.any?(File.ls!(c.dir), &String.starts_with?(&1, ".release-#{state.id}-"))

    assert {:ok, %{"release_claim" => "unknown"}} =
             Ipse.Session.Saved.inspect_saved(c.dir, state.id)
  end

  @tag skip: System.get_env("IPSE_RELEASE_HOOK_TEST") != "1"
  test "a different VM reopens after unlock before the old publisher completes", c do
    System.put_env("IPSE_TEST_RELEASE_BEFORE_ACK", c.root)
    on_exit(fn -> System.delete_env("IPSE_TEST_RELEASE_BEFORE_ACK") end)
    {:ok, session} = Session.start_link(c.opts)
    System.delete_env("IPSE_TEST_RELEASE_BEFORE_ACK")
    Process.unlink(session)
    state = :sys.get_state(session)
    parent = self()
    spawn(fn -> send(parent, {:old_close, Session.close_confirmed(session)}) end)

    wait_file(
      Path.join(c.root, "release-unlocked.ready"),
      System.monotonic_time(:millisecond) + 5_000
    )

    child =
      Port.open({:spawn_executable, System.find_executable("elixir")}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        :hide,
        args: ["test/support/release_reopen_child.exs"],
        env: [
          {~c"IPSE_RELEASE_TEST_ROOT", String.to_charlist(c.root)},
          {~c"IPSE_RELEASE_TEST_SESSION", String.to_charlist(state.id)}
        ]
      ])

    on_exit(fn -> if Port.info(child), do: Port.close(child) end)
    wait_file(Path.join(c.root, "reopen.ready"), System.monotonic_time(:millisecond) + 5_000)
    File.write!(Path.join(c.root, "release-unlocked.go"), "go")
    assert_receive {:old_close, :ok}, 5_000
    assert {:ok, events} = Journal.load(c.dir, state.id)
    assert {:ok, [old_intent]} = Ipse.Session.ReleaseReceipt.intents(events, state.id)

    old_receipt =
      File.read!(Path.join(c.dir, ".release-#{state.id}-#{old_intent["operation_id"]}"))

    assert :ok = Ipse.Session.ReleaseReceipt.verify(old_intent, old_receipt)
    assert :unknown == Ipse.Session.ReleaseReceipt.classify_current(events, state.id, old_receipt)

    assert {:ok, %{"release_claim" => "unknown"}} =
             Ipse.Session.Saved.inspect_saved(c.dir, state.id)

    File.write!(Path.join(c.root, "reopen.stop"), "go")
    assert {output, 0} = await_child(child, "", System.monotonic_time(:millisecond) + 5_000)
    assert output =~ "REOPEN_CHILD_OK"

    assert {:ok, %{"release_claim" => "signed_release_claim"}} =
             Ipse.Session.Saved.inspect_saved(c.dir, state.id)
  end

  @tag skip: System.get_env("IPSE_RELEASE_HOOK_TEST") != "1"
  test "resumed owner death after unlock before acknowledgment leaves its claim unknown", c do
    {:ok, first} = Session.start_link(c.opts)
    Process.unlink(first)
    id = :sys.get_state(first).id
    assert :ok = Session.close_confirmed(first)
    System.put_env("IPSE_TEST_RELEASE_BEFORE_ACK", c.root)
    on_exit(fn -> System.delete_env("IPSE_TEST_RELEASE_BEFORE_ACK") end)
    {:ok, resumed} = Session.start_link(Keyword.put(c.opts, :id, id))
    System.delete_env("IPSE_TEST_RELEASE_BEFORE_ACK")
    Process.unlink(resumed)

    on_exit(fn ->
      File.write(Path.join(c.root, "release-unlocked.go"), "go")
      if Process.alive?(resumed), do: Process.exit(resumed, :kill)
    end)

    assert :sys.get_state(resumed).lock_mode == :resume_v1
    ref = Process.monitor(resumed)
    parent = self()
    spawn(fn -> send(parent, {:resume_interrupted, Session.close_confirmed(resumed)}) end)

    wait_file(
      Path.join(c.root, "release-unlocked.ready"),
      System.monotonic_time(:millisecond) + 5_000
    )

    Process.exit(resumed, :kill)
    assert_receive {:DOWN, ^ref, :process, ^resumed, :killed}, 5_000
    File.write!(Path.join(c.root, "release-unlocked.go"), "go")
    assert_receive {:resume_interrupted, {:error, :cleanup_unconfirmed}}, 5_000
    assert {:ok, events} = Journal.load(c.dir, id)
    assert {:ok, [old_intent, new_intent]} = Ipse.Session.ReleaseReceipt.intents(events, id)
    refute old_intent["owner_id"] == new_intent["owner_id"]
    refute File.exists?(Path.join(c.dir, ".release-#{id}-#{new_intent["operation_id"]}"))
    assert {:ok, %{"release_claim" => "unknown"}} = Ipse.Session.Saved.inspect_saved(c.dir, id)
  end

  defp await_child(port, output, deadline) do
    receive do
      {^port, {:data, data}} -> await_child(port, output <> data, deadline)
      {^port, {:exit_status, status}} -> {output, status}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        flunk("reopen child timed out: #{output}")
    end
  end

  defp wait_file(path, deadline) do
    unless File.exists?(path) do
      if System.monotonic_time(:millisecond) >= deadline, do: flunk("release hook timed out")
      Process.sleep(10)
      wait_file(path, deadline)
    end
  end

  defp wait_for_close(session, deadline) do
    wait_until(session, deadline, fn messages ->
      Enum.any?(messages, &match?({:"$gen_call", _, :close}, &1))
    end)
  end

  defp wait_for_lock_loss(session, port, deadline) do
    wait_until(session, deadline, fn messages ->
      Enum.any?(messages, &match?({^port, {:exit_status, :lock_lost}}, &1))
    end)
  end

  defp wait_until(session, deadline, predicate) do
    {:messages, messages} = Process.info(session, :messages)

    unless predicate.(messages) do
      if System.monotonic_time(:millisecond) >= deadline, do: flunk("Session message timed out")
      Process.sleep(10)
      wait_until(session, deadline, predicate)
    end
  end
end
