Code.require_file(Path.expand("../../support/transaction_fixture.exs", __DIR__))
:ok = Ipse.Test.TransactionFixtureLoader.load()

defmodule Ipse.Runner.TransactionOptionalReadTest do
  use ExUnit.Case, async: false
  alias Ipse.Runner.Transaction, as: T
  alias Ipse.Test.TransactionFixture, as: Fault
  alias Ipse.Session.Resources
  @root Path.expand("../../..", __DIR__)

  setup_all do
    base = Path.join(System.tmp_dir!(), "ipse-optional-fixture-" <> Ipse.Usage.id())
    private(base)
    mode = Path.join(base, "mode")
    marker = Path.join(base, "pid")
    paused = Path.join(base, "paused")
    helper = Path.join(base, "fault")
    source = Path.join(base, "fault.rs")
    transaction = Path.join(@root, "native/ipse-transaction.rs")
    storage = Path.join(@root, "native/ipse-storage.rs")
    bundled = Application.app_dir(:ipse, "priv/ipse-runner")

    template = """
    #[path=TRANSACTION] mod ipse_transaction;
    #[path=#{inspect(storage)}] mod ipse_storage;
    use std::{io::{self,Write},process::Command};
    use std::os::unix::process::CommandExt;
    unsafe extern "C" {fn kill(pid:i32,signal:i32)->i32;}
    #[cfg(target_os="linux")] const STOP:i32=19;
    #[cfg(target_os="macos")] const STOP:i32=17;
    fn frame(kind:u8,bytes:&[u8])->io::Result<()>{
      if kind==b'A'{std::fs::write(#{inspect(marker)},std::process::id().to_string())?;}
      let mode=std::fs::read_to_string(#{inspect(mode)}).unwrap_or_default();
      let mut payload=bytes.to_vec();
      if kind==b'H'{
        match mode.as_str(){
          "version"=>payload[9]=2,
          "extra"=>payload.push(0),
          "prefix_absent" if payload.len()>19 && payload[15..19]!=[0,0,0,0]=>{payload.truncate(9);payload.extend_from_slice(&[1,0]);},
          "identity" if payload.len()>34 && payload[15..19]!=[0,0,0,0]=>payload[27]^=1,
          "pause"=>{std::fs::write(#{inspect(paused)},std::process::id().to_string())?;unsafe{kill(std::process::id() as i32,STOP);}},
          _=>{},
        }
      }
      let mut out=io::stdout().lock();out.write_all(&[kind])?;
      out.write_all(&(payload.len() as u32).to_be_bytes())?;
      if kind==b'H' && mode=="truncate"{out.write_all(&payload[..10])?;out.flush()?;std::process::exit(0);}
      out.write_all(&payload)?;out.flush()
    }
    fn main(){let args:Vec<_>=std::env::args().collect();
      if args.get(1).is_some_and(|s|s=="--transaction-lock"){
        if ipse_transaction::run(&args).is_err(){std::process::exit(1);}
      }else{let _=Command::new(#{inspect(bundled)}).args(&args[1..]).exec();std::process::exit(70);}
    }
    """

    File.write!(source, String.replace(template, "TRANSACTION", inspect(transaction)))

    assert {_, 0} =
             System.cmd("rustc", ["--edition=2021", "-A", "dead_code", source, "-o", helper],
               stderr_to_stdout: true
             )

    old_transaction = Path.join(base, "old-transaction.rs")

    File.write!(
      old_transaction,
      transaction |> File.read!() |> String.replace("b'G' | b'H'", "b'G'")
    )

    old_source = Path.join(base, "old.rs")
    old_helper = Path.join(base, "old")
    File.write!(old_source, String.replace(template, "TRANSACTION", inspect(old_transaction)))

    assert {_, 0} =
             System.cmd(
               "rustc",
               ["--edition=2021", "-A", "dead_code", old_source, "-o", old_helper],
               stderr_to_stdout: true
             )

    on_exit(fn -> File.rm_rf!(base) end)

    %{
      fault: helper,
      old: old_helper,
      mode: mode,
      marker: marker,
      paused: paused,
      bundled: bundled
    }
  end

  setup c do
    parent = Path.join(System.tmp_dir!(), "ipse-optional-read-" <> Ipse.Usage.id())
    private(parent)
    root = Path.join(parent, "store")
    private(root)
    for name <- ~w(objects manifests), do: private(Path.join(root, name))
    File.write!(c.mode, "")
    File.rm(c.marker)
    File.rm(c.paused)
    prior = System.get_env("IPSE_RUNNER_PATH")

    on_exit(fn ->
      if prior,
        do: System.put_env("IPSE_RUNNER_PATH", prior),
        else: System.delete_env("IPSE_RUNNER_PATH")

      File.rm_rf!(parent)
    end)

    %{parent: parent, root: root}
  end

  test "production pinned helper distinguishes missing, empty and multiframe bytes", c do
    System.put_env("IPSE_RUNNER_PATH", "/nonexistent/ambient-helper")
    assert {:ok, cap} = T.acquire(lock(c.root))
    assert :absent = T.read_optional(cap, ".", "root.json", 1024)
    assert :absent = T.read_optional(cap, "objects", immutable(), 100)
    assert {:error, :transaction_io} = T.read(cap, ".", "root.json", 1024)
    write(c.root, "root.json", "")
    assert {:ok, ""} = T.read_optional(cap, ".", "root.json", 1)
    bytes = :binary.copy(<<0, 255, 206, 187>>, 2_097_152)
    write(c.root, "control.json", bytes)
    assert {:ok, ^bytes} = T.read_optional(cap, ".", "control.json", 8_388_608)
    assert {:error, :transaction_unsafe} = T.read_optional(cap, ".", "control.json", 8_388_607)
    assert :ok = T.check(cap)
    assert :ok = T.release(cap)
    refute File.exists?(Path.join(c.root, "index.json"))
  end

  test "dangling and live symlinks, hardlinks, FIFO, directories and permissions are never absent",
       c do
    assert {:ok, cap} = T.acquire(lock(c.root))
    path = Path.join(c.root, "root.json")

    for target <- ["missing", "control.json"] do
      unless File.exists?(Path.join(c.root, "control.json")),
        do: write(c.root, "control.json", "safe")

      File.ln_s!(target, path)
      assert {:error, :transaction_io} = T.read_optional(cap, ".", "root.json", 100)
      File.rm!(path)
    end

    File.ln!(Path.join(c.root, "control.json"), path)
    assert {:error, :transaction_unsafe} = T.read_optional(cap, ".", "root.json", 100)
    File.rm!(path)
    Ipse.Test.FileEffectProbe.fifo!(path)
    assert {:error, :transaction_unsafe} = T.read_optional(cap, ".", "root.json", 100)
    File.rm!(path)
    private(path)
    assert {:error, :transaction_unsafe} = T.read_optional(cap, ".", "root.json", 100)
    File.rmdir!(path)
    write(c.root, "root.json", "private")

    for mode <- [0o644, 0o000] do
      File.chmod!(path, mode)
      assert {:error, _} = T.read_optional(cap, ".", "root.json", 100)
    end

    File.chmod!(path, 0o600)
    assert {:ok, "private"} = T.read_optional(cap, ".", "root.json", 100)
    assert :ok = T.release(cap)
  end

  test "unsafe or absent child directories and lexical requests never mean missing data", c do
    assert {:ok, cap} = T.acquire(lock(c.root))
    File.rmdir!(Path.join(c.root, "objects"))
    assert {:error, :transaction_io} = T.read_optional(cap, "objects", immutable(), 100)
    File.ln_s!("missing", Path.join(c.root, "objects"))
    assert {:error, :transaction_io} = T.read_optional(cap, "objects", immutable(), 100)
    File.rm!(Path.join(c.root, "objects"))
    private(Path.join(c.root, "objects"))
    File.chmod!(Path.join(c.root, "objects"), 0o755)
    assert {:error, :transaction_unsafe} = T.read_optional(cap, "objects", immutable(), 100)
    File.chmod!(Path.join(c.root, "objects"), 0o700)

    for {directory, name, maximum} <- [
          {"..", "root.json", 1},
          {".", "../root.json", 1},
          {".", "other.json", 1},
          {".", "root.json", 0},
          {".", "root.json", 1.0},
          {".", "root.json", 8_388_609}
        ] do
      assert {:error, :invalid_transaction_request} =
               T.read_optional(cap, directory, name, maximum)
    end

    assert :absent = T.read_optional(cap, "objects", immutable(), 100)
    assert :ok = T.release(cap)
  end

  test "optional reads keep exact owner, generation and current stack position", c do
    assert {:ok, a} = T.acquire(lock(c.root))
    child = Path.join(c.parent, "child")
    private(child)
    assert {:ok, b} = T.acquire(lock(child))
    assert {:error, :invalid_transaction_capability} = T.read_optional(a, ".", "root.json", 100)

    assert {:error, :invalid_transaction_capability} =
             T.read_optional(%{b | generation: make_ref()}, ".", "root.json", 100)

    assert {:error, :invalid_transaction_capability} =
             Task.async(fn -> T.read_optional(b, ".", "root.json", 100) end) |> Task.await()

    assert :absent = T.read_optional(b, ".", "root.json", 100)
    assert :ok = T.release(b)
    assert :absent = T.read_optional(a, ".", "root.json", 100)
    assert :ok = T.release(a)
  end

  test "old command inventory and malformed optional replies fail closed without fallback", c do
    System.put_env("IPSE_RUNNER_PATH", c.old)
    assert {:ok, old} = Fault.acquire(lock(c.root))
    assert {:unknown, :transaction_lost} = Fault.read_optional(old, ".", "root.json", 100)
    System.put_env("IPSE_RUNNER_PATH", c.fault)

    for mode <- ~w(version extra truncate) do
      File.write!(c.mode, mode)
      assert {:ok, cap} = Fault.acquire(lock(c.root))
      assert {:unknown, :transaction_lost} = Fault.read_optional(cap, ".", "root.json", 100)
      assert {:error, :invalid_transaction_capability} = Fault.check(cap)
    end

    File.write!(c.mode, "")
    assert {:ok, fresh} = T.acquire(lock(c.root))
    assert :absent = T.read_optional(fresh, ".", "root.json", 100)
    assert :ok = T.release(fresh)
  end

  test "absence or changed identity after a valid prefix returns no bytes", c do
    write(c.root, "root.json", :binary.copy("x", 20_000))
    System.put_env("IPSE_RUNNER_PATH", c.fault)

    for mode <- ~w(prefix_absent identity) do
      File.write!(c.mode, mode)
      assert {:ok, cap} = Fault.acquire(lock(c.root))
      assert {:unknown, :transaction_lost} = Fault.read_optional(cap, ".", "root.json", 20_000)
    end
  end

  test "raw H version and offset checks are closed and leave the stack intact", c do
    port =
      Port.open({:spawn_executable, c.bundled}, [
        :binary,
        :exit_status,
        args: ["--transaction-lock", "2000"]
      ])

    on_exit(fn -> if Port.info(port), do: Port.close(port) end)
    assert {?A, <<1::64, 1>>} = raw(port, ?A, 1, 0, lock(c.root))
    suffix = <<0, 9, "root.json", 0::32, 100::32>>

    for {seq, payload} <- [{2, <<2, suffix::binary>>}, {3, <<1, suffix::binary, 0>>}] do
      assert {?E, <<^seq::64, 1, 3>>} = raw(port, ?H, seq, 1, payload)
    end

    assert {?E, <<4::64, 1, 2>>} = raw(port, ?H, 4, 1, <<1, 0, 9, "root.json", 1::32, 100::32>>)
    assert {?H, <<5::64, 1, 1, 0>>} = raw(port, ?H, 5, 1, <<1, suffix::binary>>)
    assert {?R, <<6::64, 0>>} = raw(port, ?R, 6, 1, <<>>)
    assert_receive {^port, {:exit_status, 0}}, 2_000
  end

  test "replaced root is uncertainty, never an absent result under the old capability", c do
    System.put_env("IPSE_RUNNER_PATH", c.fault)
    parent = self()

    owner =
      spawn(fn ->
        {:ok, cap} = Fault.acquire(lock(c.root))
        send(parent, {:ready, self()})

        receive do
          :read -> send(parent, {:result, Fault.read_optional(cap, ".", "root.json", 100)})
        end
      end)

    on_exit(fn -> Process.exit(owner, :kill) end)
    assert_receive {:ready, ^owner}, 3_000
    pid = File.read!(c.marker)
    assert {_, 0} = System.cmd("kill", ["-STOP", pid])
    moved = c.root <> ".moved"
    File.rename!(c.root, moved)
    private(c.root)
    send(owner, :read)
    assert {_, 0} = System.cmd("kill", ["-CONT", pid])
    assert_receive {:result, {:unknown, :transaction_lost}}, 5_000
    assert {:ok, fresh} = T.acquire(lock(c.root))
    assert :absent = T.read_optional(fresh, ".", "root.json", 100)
    assert :ok = T.release(fresh)
  end

  test "upstream owner loss kills a stopped native read and frees the actual lease", c do
    System.put_env("IPSE_RUNNER_PATH", c.fault)
    File.write!(c.mode, "pause")
    parent = self()

    owner =
      spawn(fn ->
        Resources.file_effect(fn ->
          {:ok, cap} = Fault.acquire(lock(c.root))
          send(parent, {:reading, self(), cap.controller})
          send(parent, {:finished, Fault.read_optional(cap, ".", "root.json", 100)})
        end)
      end)

    on_exit(fn -> Process.exit(owner, :kill) end)
    assert_receive {:reading, borrower, controller}, 3_000
    await_file(c.paused)
    Process.exit(owner, :kill)
    monitor = Process.monitor(controller)
    assert_receive {:DOWN, ^monitor, :process, ^controller, _}, 5_000
    assert_receive {:finished, {:unknown, :transaction_lost}}, 5_000
    refute borrower == owner
    assert {:ok, fresh} = T.acquire(lock(c.root))
    assert :absent = T.read_optional(fresh, ".", "root.json", 100)
    assert :ok = T.release(fresh)
  end

  test "scope cancellation fences a stopped optional read while its owner remains alive", c do
    System.put_env("IPSE_RUNNER_PATH", c.fault)
    File.write!(c.mode, "pause")
    parent = self()

    owner =
      spawn(fn ->
        {:ok, scope} = Resources.start(self())
        Resources.bind(scope)
        send(parent, {:scope, scope})

        result =
          Resources.file_effect(fn ->
            {:ok, cap} = Fault.acquire(lock(c.root))
            Fault.read_optional(cap, ".", "root.json", 100)
          end)

        send(parent, {:cancelled, result})

        receive do
          :stop -> :ok
        end
      end)

    on_exit(fn -> Process.exit(owner, :kill) end)
    assert_receive {:scope, scope}, 3_000
    await_file(c.paused)
    assert :ok = Resources.finish(scope)
    assert_receive {:cancelled, {:unknown, :transaction_lost}}, 5_000
    assert Process.alive?(owner)
    assert {:ok, fresh} = T.acquire(lock(c.root))
    assert :absent = T.read_optional(fresh, ".", "root.json", 100)
    assert :ok = T.release(fresh)
  end

  test "an unchanged absolute deadline cancels a stopped optional reply without absence", c do
    System.put_env("IPSE_RUNNER_PATH", c.fault)
    File.write!(c.mode, "pause")
    assert {:ok, cap} = Fault.acquire(lock(c.root), timeout_ms: 750)
    started = System.monotonic_time(:millisecond)
    assert {:unknown, :transaction_lost} = Fault.read_optional(cap, ".", "root.json", 100)
    assert System.monotonic_time(:millisecond) - started < 3_000
    assert File.exists?(c.paused)
    assert {:ok, fresh} = T.acquire(lock(c.root))
    assert :ok = T.release(fresh)
  end

  @tag skip: not match?({:unix, :linux}, :os.type())
  test "optional read acknowledgements leave no native or VM data descriptor", c do
    path = Path.join(c.root, "root.json")
    write(c.root, "root.json", "data")
    assert {:ok, cap} = T.acquire(lock(c.root))
    assert {:ok, "data"} = T.read_optional(cap, ".", "root.json", 100)
    assert :absent = T.read_optional(cap, ".", "index.json", 100)
    {:os_pid, supervisor} = Port.info(cap.port, :os_pid)
    children = File.read!("/proc/#{supervisor}/task/#{supervisor}/children") |> String.split()
    assert length(children) in 1..4

    descriptors =
      for pid <- [System.pid(), Integer.to_string(supervisor) | children],
          name <- File.ls!("/proc/#{pid}/fd"),
          do: File.read_link("/proc/#{pid}/fd/#{name}")

    assert {:ok, lock(c.root)} in descriptors
    refute {:ok, path} in descriptors
    assert :ok = T.release(cap)
  end

  defp raw(port, tag, seq, depth, payload) do
    body = <<seq::64, depth, payload::binary>>
    true = Port.command(port, <<tag, byte_size(body)::32, body::binary>>)
    raw_reply(port, <<>>)
  end

  defp raw_reply(_port, <<tag, length::32, bytes::binary>>) when byte_size(bytes) == length,
    do: {tag, bytes}

  defp raw_reply(port, bytes) when byte_size(bytes) < 1024 do
    receive do
      {^port, {:data, more}} -> raw_reply(port, bytes <> more)
    after
      2_000 -> flunk("bounded raw transaction response missing")
    end
  end

  defp await_file(path), do: await_file(path, System.monotonic_time(:millisecond) + 3_000)

  defp await_file(path, deadline) do
    cond do
      File.exists?(path) ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("native pause fixture missing")

      true ->
        Process.sleep(10)
        await_file(path, deadline)
    end
  end

  defp private(path),
    do:
      (
        File.mkdir!(path)
        File.chmod!(path, 0o700)
      )

  defp write(root, name, bytes) do
    path = Path.join(root, name)
    File.write!(path, bytes, [:exclusive])
    File.chmod!(path, 0o600)
  end

  defp lock(root), do: Path.join(root, ".lock")
  defp immutable, do: String.duplicate("a", 64) <> ".json"
end
