defmodule Ipse.Session.NativeHeaderExperimentTest do
  use ExUnit.Case, async: false

  @moduletag skip:
               if(System.get_env("IPSE_HEADER_HELPER"),
                 do: false,
                 else: "requires isolated native header helper fixtures"
               )
  @id "0123456789abcdef0123456789abcdef"

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-native-header-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      root: root,
      lock: Path.join(root, @id <> ".lock"),
      journal: Path.join(root, @id <> ".jsonl"),
      stage: Path.join(root, ".pending-header-" <> @id),
      helper: Path.expand(System.fetch_env!("IPSE_HEADER_HELPER")),
      race: Path.expand(System.fetch_env!("IPSE_HEADER_RACE_HELPER")),
      disabled: Path.expand(System.fetch_env!("IPSE_HEADER_DISABLED_HELPER"))
    }
  end

  test "exclusive header returns exact file identity and synchronizes the complete payload", c do
    p = start_lock(c.helper, c.lock)
    payload = ~s({"type":"session","metadata":{}}\n)

    assert {?B, <<1::64, 1, dev::64, inode::64, uid::32>>} =
             command(p, ?B, 1, <<byte_size(payload)::32>>)

    stat = File.stat!(c.stage)
    assert {stat.major_device, stat.inode, stat.uid} == {dev, inode, uid}
    assert Bitwise.band(stat.mode, 0o777) == 0o600
    assert {?D, <<2::64, 1>>} = command(p, ?D, 2, payload)
    assert {?F, <<3::64, 1>>} = command(p, ?F, 3, <<>>)
    assert File.read!(c.journal) == payload
    assert :busy == try_lock(c.helper, c.lock)
    close_lock(p)
    assert :available == try_lock(c.helper, c.lock)
  end

  test "owner loss leaves a partial header unavailable for replay", c do
    p = start_lock(c.helper, c.lock)
    assert {?B, _} = command(p, ?B, 1, <<100::32>>)
    assert {?D, _} = command(p, ?D, 2, ~s({"type":))
    assert Port.close(p)
    wait_until(fn -> try_lock(c.helper, c.lock) == :available end)
    assert File.read!(c.stage) == ~s({"type":)
    refute File.exists?(c.journal)
    assert_incomplete_session(c)
  end

  test "existing file and symlink refuse exclusive creation without overwriting", c do
    target = Path.join(c.root, "target")
    File.write!(target, "unchanged")
    File.ln_s!(target, c.journal)
    p = start_lock(c.helper, c.lock)
    assert {?E, _} = command(p, ?B, 1, <<50::32>>)
    assert File.read!(target) == "unchanged"
    close_lock(p)
  end

  test "partial cancellation is unconfirmed and never reports an unlocked completion", c do
    p = start_lock(c.helper, c.lock)
    assert {?B, _} = command(p, ?B, 1, <<50::32>>)
    assert {?D, _} = command(p, ?D, 2, "partial")
    Port.command(p, <<?C, 0::32>>)
    assert {?E, "header unconfirmed"} = frame(p)
    wait_until(fn -> try_lock(c.helper, c.lock) == :available end)
    assert File.read!(c.stage) == "partial"
    refute File.exists?(c.journal)
  end

  test "oversized declaration refuses before creating the header", c do
    p = start_lock(c.helper, c.lock)
    assert {?E, _} = command(p, ?B, 1, <<16_777_218::32>>)
    refute File.exists?(c.journal)
    close_lock(p)
  end

  test "header size can be declared after creation returns the actual inode", c do
    p = start_lock(c.helper, c.lock)
    assert {?B, <<1::64, 1, dev::64, inode::64, uid::32>>} = command(p, ?B, 1, <<0::32>>)
    stat = File.stat!(c.stage)
    assert {stat.major_device, stat.inode, stat.uid} == {dev, inode, uid}
    payload = ~s({"type":"session","metadata":{}}\n)
    assert {?H, <<2::64, 1>>} = command(p, ?H, 2, <<byte_size(payload)::32>>)
    assert {?D, <<3::64, 1>>} = command(p, ?D, 3, payload)
    assert {?F, <<4::64, 1>>} = command(p, ?F, 4, <<>>)
    assert File.read!(c.journal) == payload
    close_lock(p)
  end

  @tag timeout: 30_000
  test "declared header supports the maximum journal record size", c do
    p = start_lock(c.helper, c.lock)
    assert {?B, _} = command(p, ?B, 1, <<0::32>>)
    assert {?H, _} = command(p, ?H, 2, <<16_777_217::32>>)
    chunk = :binary.copy("a", 16_384)

    for n <- 1..1024 do
      seq = n + 2
      assert {?D, <<^seq::64, 1>>} = command(p, ?D, seq, chunk)
    end

    assert {?D, _} = command(p, ?D, 1027, "\n")
    assert {?F, _} = command(p, ?F, 1028, <<>>)
    assert File.stat!(c.journal).size == 16_777_217
    close_lock(p)
  end

  test "substituting the created journal refuses the write and leaves the substitute untouched",
       c do
    p = start_lock(c.helper, c.lock)
    assert {?B, _} = command(p, ?B, 1, <<8::32>>)
    File.rename!(c.stage, Path.join(c.root, "original"))
    target = Path.join(c.root, "target")
    File.write!(target, "unchanged")
    File.ln_s!(target, c.stage)
    assert {?U, _} = command(p, ?D, 2, "partial!")
    assert File.read!(target) == "unchanged"
  end

  test "a final-path collision after staging never replaces the existing journal", c do
    p = start_lock(c.disabled, c.lock, [], "--session-header-v1")
    payload = ~s({"type":"session"}\n)
    assert {?B, _} = command(p, ?B, 1, <<byte_size(payload)::32>>)
    assert {?D, _} = command(p, ?D, 2, payload)
    File.write!(c.journal, "existing")
    assert {?U, _} = command(p, ?F, 3, <<>>)
    assert File.read!(c.journal) == "existing"
    assert File.read!(c.stage) == payload
  end

  test "standard helper rejects the experimental command", c do
    p = start_lock(c.disabled, c.lock)
    Port.command(p, <<?B, 13::32, 1::64, 1, 50::32>>)
    assert_receive {^p, {:exit_status, _}}, 5_000
    refute File.exists?(c.journal)
  end

  test "dedicated standard helper mode creates a synchronized header without export", c do
    p = start_lock(c.disabled, c.lock, [], "--session-header-v1")
    assert {?B, _} = command(p, ?B, 1, <<0::32>>)
    payload = ~s({"type":"session","metadata":{}}\n)
    assert {?H, _} = command(p, ?H, 2, <<byte_size(payload)::32>>)
    assert {?D, _} = command(p, ?D, 3, payload)
    assert {?F, _} = command(p, ?F, 4, <<>>)
    assert File.read!(c.journal) == payload
    assert Port.command(p, <<?X, 77::32, 5::64, 1, 0::544>>)
    assert_receive {^p, {:exit_status, _}}, 5_000
    assert :available == try_lock(c.disabled, c.lock)
  end

  test "native lock persists across owner death and the in-flight header write", c do
    parent = self()

    on_exit(fn ->
      File.write(Path.join(c.root, "before.go"), "go")
      File.write(Path.join(c.root, "after.go"), "go")
    end)

    actor =
      spawn(fn ->
        p = start_lock(c.race, c.lock, [{~c"IPSE_TEST_HEADER_RACE", String.to_charlist(c.root)}])
        assert {?B, _} = command(p, ?B, 1, <<8::32>>)
        send(parent, :begun)

        receive do
          :write -> :ok
        end

        Port.command(p, <<?D, 17::32, 2::64, 1, "partial!">>)

        receive do
          :never -> :ok
        end
      end)

    ref = Process.monitor(actor)
    assert_receive :begun, 5_000
    send(actor, :write)
    wait_until(fn -> File.exists?(Path.join(c.root, "before.ready")) end)
    assert :busy == try_lock(c.helper, c.lock)
    Process.exit(actor, :kill)
    assert_receive {:DOWN, ^ref, :process, ^actor, :killed}, 5_000
    assert :busy == try_lock(c.helper, c.lock)
    File.write!(Path.join(c.root, "before.go"), "go")
    wait_until(fn -> File.exists?(Path.join(c.root, "after.ready")) end)
    assert File.read!(c.stage) == "partial!"
    refute File.exists?(c.journal)
    assert :busy == try_lock(c.helper, c.lock)
    File.write!(Path.join(c.root, "after.go"), "go")
    wait_until(fn -> try_lock(c.helper, c.lock) == :available end)
    assert_incomplete_session(c)
  end

  test "native lock remains held while a complete header is synced after owner death", c do
    parent = self()
    payload = ~s({"type":"session","metadata":{}}\n)
    File.write!(Path.join(c.root, "before.go"), "go")
    File.write!(Path.join(c.root, "after.go"), "go")

    on_exit(fn ->
      File.write(Path.join(c.root, "sync_before.go"), "go")
      File.write(Path.join(c.root, "sync_after.go"), "go")
    end)

    actor =
      spawn(fn ->
        p = start_lock(c.race, c.lock, [{~c"IPSE_TEST_HEADER_RACE", String.to_charlist(c.root)}])
        assert {?B, _} = command(p, ?B, 1, <<byte_size(payload)::32>>)
        assert {?D, _} = command(p, ?D, 2, payload)
        send(parent, :written)
        Port.command(p, <<?F, 9::32, 3::64, 1>>)

        receive do
          :never -> :ok
        end
      end)

    ref = Process.monitor(actor)
    assert_receive :written, 5_000
    wait_until(fn -> File.exists?(Path.join(c.root, "sync_before.ready")) end)
    Process.exit(actor, :kill)
    assert_receive {:DOWN, ^ref, :process, ^actor, :killed}, 5_000
    assert :busy == try_lock(c.helper, c.lock)
    File.write!(Path.join(c.root, "sync_before.go"), "go")
    wait_until(fn -> File.exists?(Path.join(c.root, "sync_after.ready")) end)
    assert :busy == try_lock(c.helper, c.lock)
    assert File.read!(c.journal) == payload
    File.write!(Path.join(c.root, "sync_after.go"), "go")
    wait_until(fn -> try_lock(c.helper, c.lock) == :available end)
    assert {:ok, [%{"type" => "session", "metadata" => %{}}]} = Ipse.Journal.load(c.root, @id)
  end

  defp start_lock(helper, path, env \\ [], mode \\ "--lock-export-v1") do
    p =
      Port.open({:spawn_executable, helper}, [
        :binary,
        :exit_status,
        :use_stdio,
        args: [mode, path],
        env: env
      ])

    assert {?L, "locked"} = frame(p)
    p
  end

  defp try_lock(helper, path) do
    p =
      Port.open({:spawn_executable, helper}, [
        :binary,
        :exit_status,
        :use_stdio,
        args: ["--lock-export-v1", path]
      ])

    case frame_or_exit(p) do
      {:frame, {?L, "locked"}} ->
        close_lock(p)
        :available

      {:frame, {?E, _}} ->
        if Port.info(p), do: Port.close(p)
        :busy

      {:exit, _} ->
        :busy
    end
  end

  defp close_lock(p) do
    Port.command(p, <<?C, 0::32>>)
    assert {?U, "unlocked"} = frame(p)
  end

  defp command(p, tag, seq, body) do
    payload = <<seq::64, 1, body::binary>>
    assert Port.command(p, <<tag, byte_size(payload)::32, payload::binary>>)
    frame(p)
  end

  defp frame(p),
    do:
      (case frame_or_exit(p) do
         {:frame, result} -> result
         other -> flunk("expected frame, got #{inspect(other)}")
       end)

  defp frame_or_exit(p), do: read_frame(p, <<>>, System.monotonic_time(:millisecond) + 5_000)

  defp read_frame(_p, <<tag, size::32, body::binary-size(size)>>, _deadline),
    do: {:frame, {tag, body}}

  defp read_frame(p, bytes, deadline) when byte_size(bytes) <= 16_389 do
    receive do
      {^p, {:data, data}} -> read_frame(p, bytes <> data, deadline)
      {^p, {:exit_status, status}} -> {:exit, status}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> flunk("native frame timed out")
    end
  end

  defp wait_until(fun), do: wait_until(fun, System.monotonic_time(:millisecond) + 5_000)

  defp wait_until(fun, deadline) do
    if !fun.() do
      if System.monotonic_time(:millisecond) >= deadline, do: flunk("condition timed out")
      Process.sleep(10)
      wait_until(fun, deadline)
    end
  end

  defp assert_incomplete_session(c) do
    # An interrupted pending file is not a published Session journal.
    assert {:error, _} = Ipse.Journal.load(c.root, @id)
    parent = self()

    spawn(fn ->
      Process.flag(:trap_exit, true)

      opts = [
        config: %{provider: :demo, model: "fixture", home: c.root, approval: :deny},
        cwd: c.root,
        state_dir: c.root,
        id: @id,
        subscriber: parent
      ]

      send(parent, {:incomplete_resume, Ipse.Session.start_link(opts)})
    end)

    assert_receive {:incomplete_resume, {:error, _}}, 5_000
  end
end
