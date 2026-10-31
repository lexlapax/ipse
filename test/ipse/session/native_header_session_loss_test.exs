defmodule Ipse.Session.NativeHeaderSessionLossTest do
  use ExUnit.Case, async: false

  @moduletag skip:
               if(System.get_env("IPSE_HEADER_SESSION_RACE") == "1",
                 do: false,
                 else: "requires the pinned header interposition helper"
               )
  alias Ipse.{Journal, Runner, Session}

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-header-loss-session-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    dir = Path.join(root, "state")
    File.mkdir!(dir)
    File.chmod!(dir, 0o700)
    previous = System.get_env("IPSE_TEST_HEADER_RACE")
    System.put_env("IPSE_TEST_HEADER_RACE", root)

    on_exit(fn ->
      for phase <- ~w(before after sync_before sync_after),
          do: File.write(Path.join(root, phase <> ".go"), "go")

      if previous,
        do: System.put_env("IPSE_TEST_HEADER_RACE", previous),
        else: System.delete_env("IPSE_TEST_HEADER_RACE")

      File.rm_rf!(root)
    end)

    opts = [
      config: %{provider: :demo, model: "fixture", home: root, approval: :deny},
      cwd: root,
      state_dir: dir,
      subscriber: self()
    ]

    %{root: root, dir: dir, opts: opts}
  end

  test "owner death during native write retains the lock and leaves only a pending header", c do
    start_async(c.opts)
    wait_until(fn -> File.exists?(Path.join(c.root, "before.ready")) end)
    {session, guard, id, lock} = active(c)
    guard_ref = Process.monitor(guard)
    ref = Process.monitor(session)
    assert {:error, _} = Runner.protected_lock(lock)
    Process.exit(session, :kill)
    assert_receive {:DOWN, ^ref, :process, ^session, :killed}, 5_000
    assert {:error, _} = Runner.protected_lock(lock)
    File.write!(Path.join(c.root, "before.go"), "go")
    wait_until(fn -> File.exists?(Path.join(c.root, "after.ready")) end)
    assert File.stat!(Path.join(c.dir, ".pending-header-" <> id)).size > 0
    refute File.exists?(Path.join(c.dir, id <> ".jsonl"))
    assert {:error, _} = Runner.protected_lock(lock)
    File.write!(Path.join(c.root, "after.go"), "go")
    assert_receive {:DOWN, ^guard_ref, :process, ^guard, _}, 5_000
    assert {:ok, contender} = Runner.protected_lock(lock)
    assert :ok = Runner.unlock(contender)
    assert {:error, _} = Journal.load(c.dir, id)
    assert_resume_refused(c.opts, id)
  end

  test "owner death during sync keeps exclusion through publication and permits explicit resume",
       c do
    File.write!(Path.join(c.root, "before.go"), "go")
    File.write!(Path.join(c.root, "after.go"), "go")
    start_async(c.opts)
    wait_until(fn -> File.exists?(Path.join(c.root, "sync_before.ready")) end)
    {session, guard, id, lock} = active(c)
    guard_ref = Process.monitor(guard)
    ref = Process.monitor(session)
    Process.exit(session, :kill)
    assert_receive {:DOWN, ^ref, :process, ^session, :killed}, 5_000
    assert {:error, _} = Runner.protected_lock(lock)
    File.write!(Path.join(c.root, "sync_before.go"), "go")
    wait_until(fn -> File.exists?(Path.join(c.root, "sync_after.ready")) end)
    assert {:error, _} = Runner.protected_lock(lock)
    assert {:ok, [%{"type" => "session"}]} = Journal.load(c.dir, id)
    File.write!(Path.join(c.root, "sync_after.go"), "go")
    assert_receive {:DOWN, ^guard_ref, :process, ^guard, _}, 5_000
    {:ok, resumed} = Session.start_link(Keyword.put(c.opts, :id, id))
    Process.unlink(resumed)
    assert :ok = Session.close_confirmed(resumed)
  end

  test "a malformed real helper release is reported unconfirmed", c do
    System.delete_env("IPSE_TEST_HEADER_RACE")
    System.put_env("IPSE_TEST_HEADER_BAD_RELEASE", "1")
    on_exit(fn -> System.delete_env("IPSE_TEST_HEADER_BAD_RELEASE") end)
    {:ok, session} = Session.start_link(c.opts)
    Process.unlink(session)
    state = :sys.get_state(session)
    writer_ref = Process.monitor(state.journal_writer)
    assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(session)
    assert_receive {:DOWN, ^writer_ref, :process, _, _}, 5_000
  end

  test "a native no-replace failure refuses genuine Session startup without fallback", c do
    System.delete_env("IPSE_TEST_HEADER_RACE")
    System.put_env("IPSE_TEST_HEADER_RENAME_UNSUPPORTED", "1")
    on_exit(fn -> System.delete_env("IPSE_TEST_HEADER_RENAME_UNSUPPORTED") end)
    parent = self()

    spawn(fn ->
      Process.flag(:trap_exit, true)
      send(parent, {:startup_result, Session.start_link(c.opts)})
    end)

    assert_receive {:startup_result, {:error, _}}, 5_000
    [stage] = Enum.filter(File.ls!(c.dir), &String.starts_with?(&1, ".pending-header-"))
    id = String.replace_prefix(stage, ".pending-header-", "")
    assert File.stat!(Path.join(c.dir, stage)).size > 0
    refute File.exists?(Path.join(c.dir, id <> ".jsonl"))
    lock = Path.join(c.dir, id <> ".lock")

    wait_until(fn ->
      case Runner.protected_lock(lock) do
        {:ok, port} ->
          Runner.unlock(port)
          true

        _ ->
          false
      end
    end)
  end

  defp start_async(opts) do
    spawn(fn ->
      Process.flag(:trap_exit, true)
      Session.start_link(opts)
    end)
  end

  defp active(c) do
    [stage] = Enum.filter(File.ls!(c.dir), &String.starts_with?(&1, ".pending-header-"))
    id = String.replace_prefix(stage, ".pending-header-", "")
    [{session, _}] = Registry.lookup(Ipse.Registry, {c.dir, id})
    guard = Ipse.Session.Lock.for_owner(session)
    assert is_pid(guard)
    {session, guard, id, Path.join(c.dir, id <> ".lock")}
  end

  defp assert_resume_refused(opts, id) do
    parent = self()

    spawn(fn ->
      Process.flag(:trap_exit, true)
      send(parent, {:resume_result, Session.start_link(Keyword.put(opts, :id, id))})
    end)

    assert_receive {:resume_result, {:error, _}}, 5_000
  end

  defp wait_until(fun), do: wait_until(fun, System.monotonic_time(:millisecond) + 5_000)

  defp wait_until(fun, deadline) do
    unless fun.() do
      if System.monotonic_time(:millisecond) >= deadline, do: flunk("condition timed out")
      Process.sleep(10)
      wait_until(fun, deadline)
    end
  end
end
