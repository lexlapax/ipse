defmodule Ipse.Journal.ManagementOwnerTest do
  use ExUnit.Case, async: false
  alias Ipse.{Journal, Runner, Usage}
  alias Ipse.Journal.Writer
  alias Ipse.Session.Lock

  @moduletag :management_journal_owner
  @moduletag skip: if(:os.type() == {:unix, :linux}, do: false, else: "Linux native owner")

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-management-owner-" <> Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, id: Usage.id()}
  end

  @tag :management_journal_metadata
  test "generic native ownership refuses unfenced creation without claiming Session release", c do
    for marker <- [Journal.native_owner_layout(), "unknown-native-layout"],
        key <- ["native_journal_layout", :native_journal_layout, ~c"native_journal_layout"] do
      assert {:error, :journal_lock_owner_required} =
               Journal.create(Path.join(c.root, "not-created"), %{key => marker})
    end

    for key <- ["release_receipt_layout", :release_receipt_layout, ~c"release_receipt_layout"] do
      assert {:error, :journal_lock_owner_required} =
               Journal.create(Path.join(c.root, "not-created"), %{key => "release-claim-v1"})
    end

    refute File.exists?(Path.join(c.root, "not-created"))
    assert Path.wildcard(Path.join(c.root, "*.jsonl")) == []
    assert {:ok, _} = Journal.create(c.root, %{"kind" => "legacy"})
  end

  @tag :management_journal_metadata
  test "duplicate encoded metadata names refuse before creating a directory", c do
    directory = Path.join(c.root, "not-created")

    assert {:error, %Jason.EncodeError{}} =
             Journal.create(directory, %{"kind" => "second", kind: "first"})

    refute File.exists?(directory)
  end

  test "management-layout reservations append in the actual owner and refuse every inactive writer",
       c do
    {guard, writer, _port} = open(c)
    assert {:ok, token} = Writer.reserve(writer, %{bytes: 4096, events: 2})
    assert :ok = Writer.append_reserved(writer, token, %{"type" => "managed_lifecycle_intent"})
    assert :ok = Writer.append_reserved(writer, token, %{"type" => "managed_lifecycle_result"})
    assert :ok = Writer.release(writer, token)
    assert :ok = Writer.close(writer)
    assert :ok = Lock.release(guard)
    Process.delete({Lock, :guard})
    assert {:ok, [header, intent, result]} = Journal.load(c.root, c.id)
    assert header["metadata"]["native_journal_layout"] == Journal.native_owner_layout()
    refute Map.has_key?(header["metadata"], "release_receipt_layout")
    assert intent["type"] == "managed_lifecycle_intent"
    assert result["type"] == "managed_lifecycle_result"
    path = Path.join(c.root, c.id <> ".jsonl")
    before = File.read!(path)

    for append <- [&Journal.append/3, &Journal.append_observed/3, &Journal.append_with_source/3] do
      assert {:error, :journal_lock_owner_required} = append.(c.root, c.id, %{"type" => "bad"})
    end

    assert {:error, :journal_lock_owner_required} = Journal.repair_tail(c.root, c.id)
    assert {:error, :journal_unavailable} = Writer.start(c.root, c.id, self())

    assert {:error, :journal_unavailable} =
             Writer.append_inactive(c.root, c.id, %{"type" => "bad"}, :plain)

    assert File.read!(path) == before
    assert {:ok, contender} = Runner.protected_resume_lock(Path.join(c.root, c.id <> ".lock"))
    assert :ok = Runner.unlock_export_candidate(contender)
  end

  test "lost native owner cannot append while an independent contender owns the lock", c do
    {guard, writer, port} = open(c)
    path = Path.join(c.root, c.id <> ".jsonl")
    before = File.read!(path)
    {:os_pid, native} = Port.info(port, :os_pid)
    assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(native)])
    assert_receive {^port, {:exit_status, :lock_lost}}, 5000
    assert {:ok, contender} = Runner.protected_resume_lock(Path.join(c.root, c.id <> ".lock"))
    assert {:error, _} = Writer.append(writer, %{"type" => "must_not_appear"})
    assert File.read!(path) == before
    if Process.alive?(writer), do: Writer.close(writer)
    assert {:error, _} = Lock.release(guard)
    assert :ok = Runner.unlock_export_candidate(contender)
  end

  @tag skip: System.get_env("IPSE_NATIVE_JOURNAL_HOOK_TEST") != "1"
  @tag :management_journal_hook
  test "standalone owner death retains the native lock through a pending append sync", c do
    System.put_env("IPSE_TEST_JOURNAL_HOOK", c.root)
    on_exit(fn -> System.delete_env("IPSE_TEST_JOURNAL_HOOK") end)
    parent = self()

    owner =
      spawn(fn ->
        {guard, writer, _port} = open(c)
        send(parent, {:management_owner, guard})
        receive do: (:append -> Writer.append(writer, %{"type" => "interrupted_management"}))
      end)

    assert_receive {:management_owner, guard}, 5000
    guard_ref = Process.monitor(guard)
    owner_ref = Process.monitor(owner)
    File.write!(Path.join(c.root, "journal-before-write.go"), "go")
    File.write!(Path.join(c.root, "journal-hook.arm"), "arm")

    on_exit(fn ->
      File.write(Path.join(c.root, "journal-before-write.go"), "go")
      File.write(Path.join(c.root, "journal-after-write.go"), "go")
      if Process.alive?(owner), do: Process.exit(owner, :kill)
    end)

    send(owner, :append)

    wait_file(
      Path.join(c.root, "journal-after-write.ready"),
      System.monotonic_time(:millisecond) + 5000
    )

    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^owner_ref, :process, ^owner, :killed}, 5000
    assert {:error, _} = Runner.protected_resume_lock(Path.join(c.root, c.id <> ".lock"))
    File.write!(Path.join(c.root, "journal-after-write.go"), "go")
    assert_receive {:DOWN, ^guard_ref, :process, ^guard, _}, 5000
    assert {:ok, contender} = Runner.protected_resume_lock(Path.join(c.root, c.id <> ".lock"))
    assert :ok = Runner.unlock_export_candidate(contender)
    assert {:ok, [_, %{"type" => "interrupted_management"}]} = Journal.load(c.root, c.id)
  end

  defp open(c) do
    assert {:ok, port} = Lock.acquire_header(Path.join(c.root, c.id <> ".lock"))
    guard = Lock.current()
    assert {:ok, id} = Journal.create_with_locked_id(c.root, c.id, metadata(), nil, guard)
    assert id == c.id
    assert {:ok, writer} = Writer.start(c.root, c.id, self(), nil, :header_v1)
    assert :ok = Lock.track(writer, :writer)
    {guard, writer, port}
  end

  defp metadata do
    %{
      "kind" => "knowledge_management",
      "version" => 1,
      "native_journal_layout" => Journal.native_owner_layout(),
      "source_origin_layout" => Ipse.Journal.SourceOrigin.layout()
    }
  end

  defp wait_file(path, deadline) do
    unless File.exists?(path) do
      assert System.monotonic_time(:millisecond) < deadline
      Process.sleep(10)
      wait_file(path, deadline)
    end
  end
end
