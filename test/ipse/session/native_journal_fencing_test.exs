defmodule Ipse.Session.NativeJournalFencingTest do
  use ExUnit.Case, async: false
  @moduletag skip: if(:os.type() == {:unix, :linux}, do: false, else: "Linux helper")
  alias Ipse.{Journal, Session}

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-native-journal-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    dir = Path.join(root, "state")
    File.mkdir!(dir)
    File.chmod!(dir, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)

    opts = [
      config: %{provider: :demo, model: "fixture", home: root, approval: :deny},
      cwd: root,
      state_dir: dir,
      subscriber: self()
    ]

    %{root: root, dir: dir, opts: opts}
  end

  @tag timeout: 30_000
  test "large admitted records and a journal above 16 MiB close with a real release claim", c do
    {:ok, session} = Session.start_link(c.opts)
    Process.unlink(session)
    state = :sys.get_state(session)
    parent = self()
    blob = String.duplicate("x", 8_500_000)

    for n <- 1..2 do
      :sys.replace_state(
        session,
        fn s ->
          result =
            Journal.Writer.append(s.journal_writer, %{
              "type" => "large_journal_fixture",
              "n" => n,
              "payload" => blob
            })

          send(parent, {:large_append, n, result})
          s
        end,
        10_000
      )

      assert_receive {:large_append, ^n, :ok}, 10_000
    end

    assert File.stat!(Path.join(c.dir, state.id <> ".jsonl")).size > 16_777_217
    assert :ok = Session.close_confirmed(session)

    assert {:ok, %{"release_claim" => "signed_release_claim"}} =
             Session.Saved.inspect_saved(c.dir, state.id)
  end

  test "only the tracked Writer can request native journal mutation", c do
    {:ok, session} = Session.start_link(c.opts)
    Process.unlink(session)
    state = :sys.get_state(session)
    path = Path.join(c.dir, state.id <> ".jsonl")
    before = File.read!(path)
    stat = File.stat!(path)
    identity = %{device: stat.major_device, inode: stat.inode}

    assert {:error, :journal_write_unconfirmed} =
             Session.Lock.journal_append(state.lock_guard, identity, stat.size, "{}\n")

    assert File.read!(path) == before
    assert :ok = Session.close_confirmed(session)
  end

  test "inactive and legacy write entry points cannot mutate a protected journal", c do
    {:ok, session} = Session.start_link(c.opts)
    Process.unlink(session)
    id = :sys.get_state(session).id
    assert :ok = Session.close_confirmed(session)
    path = Path.join(c.dir, id <> ".jsonl")
    before = File.read!(path)

    assert {:error, :journal_lock_owner_required} =
             Journal.append(c.dir, id, %{"type" => "fixture"})

    assert {:error, :journal_lock_owner_required} = Journal.repair_tail(c.dir, id)
    assert {:error, :journal_unavailable} = Journal.Writer.start(c.dir, id, self())

    assert {:error, :journal_unavailable} =
             Journal.Writer.append_inactive(c.dir, id, %{"type" => "fixture"}, :plain)

    assert File.read!(path) == before
  end

  test "a complete unterminated final record is repaired by the native lock owner", c do
    {:ok, first} = Session.start_link(c.opts)
    Process.unlink(first)
    id = :sys.get_state(first).id
    assert :ok = Session.close_confirmed(first)
    path = Path.join(c.dir, id <> ".jsonl")
    File.write!(path, ~s({"type":"fixture_tail"}), [:append])
    {:ok, resumed} = Session.start_link(Keyword.put(c.opts, :id, id))
    Process.unlink(resumed)
    assert {:ok, events} = Journal.load(c.dir, id)
    assert Enum.any?(events, &(&1["type"] == "fixture_tail"))
    assert :ok = Session.close_confirmed(resumed)
  end

  test "quota sealing uses the same native journal owner", c do
    opts =
      Keyword.update!(c.opts, :config, &Map.put(&1, :journal, %{"max_record_bytes" => 4_096}))

    {:ok, session} = Session.start_link(opts)
    Process.unlink(session)
    id = :sys.get_state(session).id
    parent = self()

    :sys.replace_state(session, fn s ->
      send(
        parent,
        {:quota_append,
         Journal.Writer.append(s.journal_writer, %{
           "type" => "fixture",
           "body" => String.duplicate("x", 4_096)
         })}
      )

      s
    end)

    assert_receive {:quota_append, {:error, :journal_limit_reached}}, 5_000
    assert {:ok, events} = Journal.load(c.dir, id)
    assert :ok = Journal.validate_limit_events(events)
    assert List.last(events)["type"] == "journal_limit_reached"
    Process.exit(session, :kill)
  end

  @tag skip: System.get_env("IPSE_NATIVE_JOURNAL_HOOK_TEST") != "1"
  test "native owner death before append leaves no journal write under a contender", c do
    System.put_env("IPSE_TEST_JOURNAL_HOOK", c.root)
    on_exit(fn -> System.delete_env("IPSE_TEST_JOURNAL_HOOK") end)
    {:ok, session} = Session.start_link(c.opts)
    Process.unlink(session)
    state = :sys.get_state(session)
    path = Path.join(c.dir, state.id <> ".jsonl")
    before = File.read!(path)

    on_exit(fn ->
      File.write(Path.join(c.root, "journal-before-write.go"), "go")
      File.write(Path.join(c.root, "journal-after-write.go"), "go")
      if Process.alive?(session), do: Process.exit(session, :kill)
    end)

    File.write!(Path.join(c.root, "journal-hook.arm"), "arm")
    parent = self()

    spawn(fn ->
      result =
        try do
          Session.prompt(session, "synthetic interrupted input")
        catch
          :exit, _ -> :unknown
        end

      send(parent, {:prompt_interrupted, result})
    end)

    wait_file(
      Path.join(c.root, "journal-before-write.ready"),
      System.monotonic_time(:millisecond) + 5_000
    )

    {:os_pid, native} = Port.info(state.lock, :os_pid)
    assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(native)])
    assert_receive {:prompt_interrupted, result}, 5_000
    assert result != :ok

    assert {:ok, contender} =
             Ipse.Runner.protected_resume_lock(Path.join(c.dir, state.id <> ".lock"))

    assert File.read!(path) == before
    assert :ok = Ipse.Runner.unlock_export_candidate(contender)
  end

  @tag skip: System.get_env("IPSE_NATIVE_JOURNAL_HOOK_TEST") != "1"
  test "owner death during a native append retains the flock through pending sync", c do
    System.put_env("IPSE_TEST_JOURNAL_HOOK", c.root)
    on_exit(fn -> System.delete_env("IPSE_TEST_JOURNAL_HOOK") end)
    {:ok, session} = Session.start_link(c.opts)
    Process.unlink(session)
    state = :sys.get_state(session)
    path = Path.join(c.dir, state.id <> ".jsonl")
    before = File.read!(path)

    on_exit(fn ->
      File.write(Path.join(c.root, "journal-before-write.go"), "go")
      File.write(Path.join(c.root, "journal-after-write.go"), "go")
      if Process.alive?(session), do: Process.exit(session, :kill)
    end)

    File.write!(Path.join(c.root, "journal-before-write.go"), "go")
    File.write!(Path.join(c.root, "journal-hook.arm"), "arm")
    parent = self()

    spawn(fn ->
      result =
        try do
          Session.prompt(session, "synthetic interrupted input")
        catch
          :exit, _ -> :unknown
        end

      send(parent, {:prompt_interrupted, result})
    end)

    wait_file(
      Path.join(c.root, "journal-after-write.ready"),
      System.monotonic_time(:millisecond) + 5_000
    )

    assert File.stat!(path).size > byte_size(before)
    guard_ref = Process.monitor(state.lock_guard)
    session_ref = Process.monitor(session)
    Process.exit(session, :kill)
    assert_receive {:DOWN, ^session_ref, :process, ^session, :killed}, 5_000
    assert {:error, _} = Ipse.Runner.protected_resume_lock(Path.join(c.dir, state.id <> ".lock"))
    File.write!(Path.join(c.root, "journal-after-write.go"), "go")
    assert_receive {:DOWN, ^guard_ref, :process, _, _}, 5_000
    assert_receive {:prompt_interrupted, result}, 5_000
    assert result != :ok

    assert {:ok, contender} =
             Ipse.Runner.protected_resume_lock(Path.join(c.dir, state.id <> ".lock"))

    assert {:ok, events} = Journal.load(c.dir, state.id)
    refute Enum.any?(events, &(&1["type"] == "tool_started"))
    assert :ok = Ipse.Runner.unlock_export_candidate(contender)
  end

  @tag skip: System.get_env("IPSE_NATIVE_JOURNAL_HOOK_TEST") != "1"
  test "native owner death before torn-tail repair prevents mutation under a contender", c do
    {:ok, first} = Session.start_link(c.opts)
    Process.unlink(first)
    id = :sys.get_state(first).id
    assert :ok = Session.close_confirmed(first)
    path = Path.join(c.dir, id <> ".jsonl")
    File.write!(path, ~s({"type":"interrupted), [:append])
    before = File.read!(path)
    System.put_env("IPSE_TEST_JOURNAL_HOOK", c.root)

    on_exit(fn ->
      System.delete_env("IPSE_TEST_JOURNAL_HOOK")
      File.write(Path.join(c.root, "journal-before-repair.go"), "go")
      File.write(Path.join(c.root, "journal-after-repair.go"), "go")
    end)

    File.write!(Path.join(c.root, "journal-hook.arm"), "arm")
    parent = self()

    spawn(fn ->
      Process.flag(:trap_exit, true)
      send(parent, {:repair_start, Session.start_link(Keyword.put(c.opts, :id, id))})
    end)

    wait_file(
      Path.join(c.root, "journal-before-repair.ready"),
      System.monotonic_time(:millisecond) + 5_000
    )

    [{owner, _}] = Registry.lookup(Ipse.Registry, {c.dir, id})
    guard = Session.Lock.for_owner(owner)
    {:links, links} = Process.info(guard, :links)
    port = Enum.find(links, &is_port/1)
    assert is_port(port)
    {:os_pid, native} = Port.info(port, :os_pid)
    assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(native)])
    assert_receive {:repair_start, {:error, _}}, 5_000
    assert {:ok, contender} = Ipse.Runner.protected_resume_lock(Path.join(c.dir, id <> ".lock"))
    assert File.read!(path) == before
    assert :ok = Ipse.Runner.unlock_export_candidate(contender)
  end

  defp wait_file(path, deadline) do
    unless File.exists?(path) do
      if System.monotonic_time(:millisecond) >= deadline, do: flunk("journal hook timed out")
      Process.sleep(10)
      wait_file(path, deadline)
    end
  end
end
