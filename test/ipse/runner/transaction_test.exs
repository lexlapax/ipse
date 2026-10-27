Code.require_file(Path.expand("../../support/transaction_fixture.exs", __DIR__))
:ok = Ipse.Test.TransactionFixtureLoader.load()

defmodule Ipse.Runner.TransactionTest do
  use ExUnit.Case, async: false
  alias Ipse.Test.TransactionFixture, as: T
  @root Path.expand("../../..", __DIR__)

  setup_all do
    base = Path.join(System.tmp_dir!(), "ipse-transaction-helper-" <> id())
    File.mkdir!(base)
    File.chmod!(base, 0o700)
    helper = Path.join(base, "runner")

    assert {_, 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 Path.join(@root, "native/ipse-runner.rs"),
                 "-o",
                 helper
               ],
               stderr_to_stdout: true
             )

    fault = Path.join(base, "fault")
    marker = Path.join(base, "pid")
    source = Path.join(base, "fault.rs")

    File.write!(source, """
    #[path=#{inspect(Path.join(@root, "native/ipse-transaction.rs"))}] mod ipse_transaction;
    #[path=#{inspect(Path.join(@root, "native/ipse-storage.rs"))}] mod ipse_storage;
    use std::{io::{self,Write},process::Command};
    use std::os::unix::process::CommandExt;
    unsafe extern "C" {fn kill(pid:i32,signal:i32)->i32;}
    fn frame(kind:u8,bytes:&[u8])->io::Result<()>{
      if kind==b'A'{std::fs::write(#{inspect(marker)},std::process::id().to_string())?;}
      if kind==b'S'{unsafe{kill(std::process::id() as i32,9);}}
      let mut out=io::stdout().lock();out.write_all(&[kind])?;
      out.write_all(&(bytes.len() as u32).to_be_bytes())?;out.write_all(bytes)?;out.flush()
    }
    fn main(){std::fs::write(#{inspect(marker)},std::process::id().to_string()).unwrap();let args:Vec<_>=std::env::args().collect();
      if args.get(1).is_some_and(|s|s=="--transaction-lock"){
        if ipse_transaction::run(&args).is_err(){std::process::exit(1);}
      }else{let _=Command::new(#{inspect(helper)}).args(&args[1..]).exec();std::process::exit(70);}
    }
    """)

    assert {_, 0} =
             System.cmd("rustc", ["--edition=2021", "-A", "dead_code", source, "-o", fault],
               stderr_to_stdout: true
             )

    on_exit(fn -> File.rm_rf!(base) end)
    %{helper: helper, fault: fault, marker: marker}
  end

  setup c do
    base = Path.join(System.tmp_dir!(), "ipse-transaction-test-" <> id())
    File.mkdir!(base)
    File.chmod!(base, 0o700)
    for name <- ~w(a b c d), do: private(Path.join(base, name))
    for name <- ~w(objects manifests), do: private(Path.join([base, "a", name]))
    old = System.get_env("IPSE_RUNNER_PATH")
    System.put_env("IPSE_RUNNER_PATH", c.helper)

    on_exit(fn ->
      if old,
        do: System.put_env("IPSE_RUNNER_PATH", old),
        else: System.delete_env("IPSE_RUNNER_PATH")

      File.rm_rf!(base)
    end)

    %{base: base, root: Path.join(base, "a")}
  end

  test "same owner stages bounded multiframe bytes, switches and installs without replacement",
       c do
    assert {:ok, cap} = T.acquire(lock(c.root))
    name = pending(1)
    bytes = String.duplicate("λ", 20_001)
    assert :ok = T.stage(cap, ".", [{name, bytes}])
    assert File.read!(Path.join(c.root, name)) == bytes
    assert :ok = T.switch(cap, name, "index.json")
    assert File.read!(Path.join(c.root, "index.json")) == bytes
    assert :ok = T.stage(cap, "objects", [{pending(2), "object"}, {pending(3), "other"}])
    object = immutable(2)
    assert :ok = T.install(cap, "objects", pending(2), object)
    assert {:error, :transaction_exists} = T.install(cap, "objects", pending(3), object)
    assert File.read!(Path.join([c.root, "objects", object])) == "object"
    assert :ok = T.reclaim(cap, "objects", [pending(3), object])
    refute File.exists?(Path.join([c.root, "objects", object]))
    assert {:ok, %{logical: logical, allocated: allocated, entries: entries}} = T.allocation(cap)
    assert logical >= byte_size(bytes) and allocated >= byte_size(bytes) and entries >= 6
    assert :ok = T.check(cap)
    assert :ok = T.release(cap)
    assert {:error, :invalid_transaction_capability} = T.check(cap)
  end

  test "capability owner, generation, exact top and depth are enforced", c do
    assert {:ok, a} = T.acquire(lock(c.root))
    assert {:ok, b} = T.acquire(lock(Path.join(c.base, "b")))
    assert a.port == b.port and a.controller == b.controller
    assert {:error, :invalid_transaction_capability} = T.check(a)
    assert {:error, :invalid_transaction_capability} = T.release(a)
    assert {:error, :invalid_transaction_capability} = T.check(%{b | generation: make_ref()})

    assert {:error, :invalid_transaction_capability} =
             Task.async(fn -> T.check(b) end) |> Task.await()

    assert {:ok, d3} = T.acquire(lock(Path.join(c.base, "c")))
    assert {:error, :invalid_transaction_request} = T.acquire(lock(Path.join(c.base, "d")))
    assert :ok = T.release(d3)
    assert :ok = T.release(b)
    assert {:error, :invalid_transaction_capability} = T.check(b)
    assert :ok = T.check(a)
    assert :ok = T.release(a)
  end

  test "protected paths, types, names, limits and writer conflicts refuse without effects", c do
    assert {:ok, cap} = T.acquire(lock(c.root))
    assert {:error, :invalid_transaction_request} = T.switch(cap, pending(1), "../index.json")
    assert {:error, :invalid_transaction_request} = T.stage(cap, ".", [{pending(1), <<>>}])

    assert {:error, :invalid_transaction_request} =
             T.stage(cap, ".", [{pending(1), :binary.copy("x", 8 * 1024 * 1024 + 1)}])

    assert {:error, :invalid_transaction_request} =
             T.reclaim(cap, ".", List.duplicate(pending(1), 65))

    assert {:error, :invalid_transaction_request} = T.reclaim(cap, ".", ["index.json"])
    assert :ok = T.stage(cap, ".", [{pending(1), "safe"}])
    File.ln!(Path.join(c.root, pending(1)), Path.join(c.root, "hardlink"))
    assert {:error, :transaction_unsafe} = T.switch(cap, pending(1), "root.json")
    refute File.exists?(Path.join(c.root, "root.json"))
    File.rm!(Path.join(c.root, "hardlink"))
    File.ln_s!(Path.join(c.root, pending(1)), Path.join(c.root, "control.json"))
    assert {:error, :transaction_unsafe} = T.switch(cap, pending(1), "control.json")
    assert {:ok, writer} = Ipse.Runner.lock(Path.join(c.root, ".writer.lock"))
    assert {:error, :transaction_busy} = T.stage(cap, ".", [{pending(2), "not written"}])
    assert {:error, :transaction_busy} = T.reclaim(cap, ".", [pending(1)])
    refute File.exists?(Path.join(c.root, pending(2)))
    assert :ok = Ipse.Runner.unlock(writer)
    assert :ok = T.release(cap)
    assert {:error, _} = T.acquire(Path.join([c.base, "a", "..", "b", ".lock"]))
  end

  test "root absolute lifetime expires without resetting on successful checks", c do
    assert {:ok, cap} = T.acquire(lock(c.root), timeout_ms: 350)

    for _ <- 1..3 do
      assert :ok = T.check(cap)
      Process.sleep(60)
    end

    Process.sleep(200)
    assert {:unknown, _} = T.check(cap)
    assert {:ok, fresh} = T.acquire(lock(c.root))
    assert :ok = T.release(fresh)
  end

  test "actual helper loss before switch cannot publish later", c do
    System.put_env("IPSE_RUNNER_PATH", c.fault)
    File.rm(c.marker)
    assert {:ok, cap} = T.acquire(lock(c.root))
    assert :ok = T.stage(cap, ".", [{pending(1), "candidate"}])
    pid = File.read!(c.marker)
    assert {_, 0} = System.cmd("kill", ["-KILL", pid])
    assert {:unknown, _} = T.switch(cap, pending(1), "index.json")
    refute File.exists?(Path.join(c.root, "index.json"))
    assert File.read!(Path.join(c.root, pending(1))) == "candidate"
  end

  test "actual helper kill after rename and before ACK is unknown with inspectable publication",
       c do
    System.put_env("IPSE_RUNNER_PATH", c.fault)
    assert {:ok, cap} = T.acquire(lock(c.root))
    assert :ok = T.stage(cap, ".", [{pending(1), "candidate"}])
    assert {:unknown, _} = T.switch(cap, pending(1), "index.json")
    assert File.read!(Path.join(c.root, "index.json")) == "candidate"
    refute File.exists?(Path.join(c.root, pending(1)))
    System.put_env("IPSE_RUNNER_PATH", c.helper)
    assert {:ok, next} = T.acquire(lock(c.root))
    assert :ok = T.check(next)
    assert :ok = T.release(next)
  end

  test "owner death and resource scope cancellation release idle native locks", c do
    parent = self()

    owner =
      spawn(fn ->
        {:ok, scope} = Ipse.Session.Resources.start(self())
        Ipse.Session.Resources.bind(scope)
        {:ok, cap} = T.acquire(lock(c.root))
        send(parent, {:ready, self(), scope, cap.controller})

        receive do
          :wait -> :ok
        end
      end)

    assert_receive {:ready, ^owner, scope, controller}, 5_000
    assert :ok = Ipse.Session.Resources.finish(scope)
    refute Process.alive?(controller)
    Process.exit(owner, :kill)
    assert {:ok, cap} = T.acquire(lock(c.root))
    assert :ok = T.release(cap)

    owner =
      spawn(fn ->
        {:ok, cap} = T.acquire(lock(c.root))
        send(parent, {:held, self(), cap.controller})

        receive do
          :wait -> :ok
        end
      end)

    assert_receive {:held, ^owner, controller}, 5_000
    monitor = Process.monitor(controller)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^controller, _}, 3_000
    assert {:ok, cap} = T.acquire(lock(c.root))
    assert :ok = T.release(cap)
  end

  test "separate VM cannot revoke either parent or child lock while stack is retained", c do
    assert {:ok, a} = T.acquire(lock(c.root))
    assert {:ok, b} = T.acquire(lock(Path.join(c.base, "b")))

    for path <- [lock(c.root), lock(Path.join(c.base, "b"))] do
      code =
        "Application.load(:ipse); Code.require_file(#{inspect(Path.join(@root, "test/support/transaction_fixture.exs"))}); Ipse.Test.TransactionFixtureLoader.load(); IO.inspect(Ipse.Test.TransactionFixture.acquire(#{inspect(path)}))"

      paths =
        :code.get_path()
        |> Enum.reject(&(Path.basename(List.to_string(&1)) == "consolidated"))
        |> Enum.flat_map(&["-pa", List.to_string(&1)])

      assert {"{:error, :transaction_busy}\n", 0} =
               System.cmd("elixir", paths ++ ["-e", code], stderr_to_stdout: true)
    end

    assert :ok = T.release(b)
    assert :ok = T.check(a)
    assert :ok = T.release(a)
  end

  test "file effect upstream owner death fences paused work with and without a scope", c do
    parent = self()

    for scoped? <- [false, true] do
      owner =
        spawn(fn ->
          scope =
            if scoped? do
              {:ok, scope} = Ipse.Session.Resources.start(self())
              Ipse.Session.Resources.bind(scope)
              scope
            end

          original = self()

          Ipse.Session.Resources.file_effect(fn ->
            assert Ipse.Session.Resources.current() == scope
            assert Ipse.Session.Resources.file_effect_owner() == original

            Ipse.Session.Resources.file_effect(fn ->
              assert Ipse.Session.Resources.file_effect_owner() == original
            end)

            {:ok, cap} = T.acquire(lock(c.root))
            send(parent, {:effect_held, original, self(), cap.controller})
            receive do: (:continue -> :ok)
            result = T.stage(cap, ".", [{pending(91), "late candidate"}])
            switched = T.switch(cap, pending(91), "root.json")
            send(parent, {:late_result, self(), result, switched})
          end)
        end)

      assert_receive {:effect_held, ^owner, worker, controller}, 5_000
      controller_ref = Process.monitor(controller)
      Process.exit(owner, :kill)
      assert_receive {:DOWN, ^controller_ref, :process, ^controller, _}, 3_000
      assert Process.alive?(worker)
      send(worker, :continue)

      assert_receive {:late_result, ^worker, {:unknown, _},
                      {:error, :invalid_transaction_capability}},
                     3_000

      refute File.exists?(Path.join(c.root, pending(91)))
      refute File.exists?(Path.join(c.root, "root.json"))
      assert {:ok, fresh} = T.acquire(lock(c.root))
      assert :ok = T.release(fresh)
    end
  end

  test "scope cancellation reaches a transaction inside an otherwise live file effect", c do
    parent = self()

    owner =
      spawn(fn ->
        {:ok, scope} = Ipse.Session.Resources.start(self())
        Ipse.Session.Resources.bind(scope)

        result =
          Ipse.Session.Resources.file_effect(fn ->
            {:ok, cap} = T.acquire(lock(c.root))
            send(parent, {:effect_scoped, self(), scope, cap.controller})
            receive do: (:continue -> :ok)
            result = T.stage(cap, ".", [{pending(92), "cancelled candidate"}])
            switched = T.switch(cap, pending(92), "root.json")
            send(parent, {:cancelled_result, self(), result, switched})
          end)

        send(parent, {:effect_returned, self(), result})
      end)

    assert_receive {:effect_scoped, worker, scope, controller}, 5_000
    controller_ref = Process.monitor(controller)
    finish = Task.async(fn -> Ipse.Session.Resources.finish(scope) end)
    assert_receive {:DOWN, ^controller_ref, :process, ^controller, _}, 3_000
    assert Process.alive?(owner) and Process.alive?(worker)
    send(worker, :continue)

    assert_receive {:cancelled_result, ^worker, {:unknown, _},
                    {:error, :invalid_transaction_capability}},
                   3_000

    assert :ok = Task.await(finish)
    assert_receive {:effect_returned, ^owner, _}, 3_000
    refute File.exists?(Path.join(c.root, pending(92)))
    assert {:ok, fresh} = T.acquire(lock(c.root))
    assert :ok = T.release(fresh)
  end

  test "exact eight MiB stage succeeds and metadata over bounds creates nothing", c do
    assert {:ok, cap} = T.acquire(lock(c.root))
    entries = for n <- 1..128, do: {pending(n), :binary.copy(<<n>>, 65_536)}
    assert :ok = T.stage(cap, "objects", entries)
    assert File.stat!(Path.join([c.root, "objects", pending(128)])).size == 65_536

    assert {:error, :invalid_transaction_request} =
             T.stage(cap, "manifests", entries ++ [{pending(129), "x"}])

    assert File.ls!(Path.join(c.root, "manifests")) == []

    for names <- entries |> Enum.map(&elem(&1, 0)) |> Enum.chunk_every(64),
        do: assert(:ok == T.reclaim(cap, "objects", names))

    assert :ok = T.release(cap)
  end

  test "stale capability cannot clear a later transaction's process marker", c do
    assert {:ok, old} = T.acquire(lock(c.root))
    assert :ok = T.release(old)
    assert {:ok, current} = T.acquire(lock(c.root))
    assert {:error, :invalid_transaction_capability} = T.check(old)
    assert {:ok, child} = T.acquire(lock(Path.join(c.base, "b")))
    assert child.controller == current.controller
    assert :ok = T.release(child)
    assert :ok = T.release(current)
  end

  test "native closed schema refuses oversize, invalid UTF8 and stale sequences without panic",
       c do
    path = lock(c.root)
    acquire = frame(?A, <<1::64, 0, path::binary>>)

    cases = [
      {<<?A, 8193::32>>, false},
      {frame(?A, <<2::64, 0, path::binary>>), false},
      {acquire <> frame(?P, <<1::64, 1>>), true},
      {acquire <> frame(?S, <<2::64, 1, :binary.copy("a", 40)::binary, 0xC2, 0xA2, "index.json">>),
       true}
    ]

    for {bytes, _acquired} <- cases do
      {:ok, port} =
        Ipse.Runner.open_stdio(c.helper, ["--transaction-lock", "1000"], c.root, %{}, 2000)

      assert :ok = Ipse.Runner.send_stdio(port, bytes)
      output = drain(port, <<>>)
      refute output =~ "panicked"
      assert output =~ "\"exit_code\":1"
      refute File.exists?(Path.join(c.root, "index.json"))
      assert {:ok, cap} = T.acquire(path)
      assert :ok = T.release(cap)
    end
  end

  test "native partial-frame and idle deadlines release actual locks", c do
    for bytes <- [<<>>, <<?A, 20::32, 1, 2>>] do
      {:ok, port} =
        Ipse.Runner.open_stdio(c.helper, ["--transaction-lock", "100"], c.root, %{}, 1100)

      assert :ok = Ipse.Runner.send_stdio(port, bytes)
      output = drain(port, <<>>)
      assert output =~ "\"exit_code\":1"
      assert {:ok, cap} = T.acquire(lock(c.root))
      assert :ok = T.release(cap)
    end
  end

  test "flat allocation refuses unleased child namespaces and accepts a bounded flat control root",
       c do
    assert {:ok, cap} = T.acquire(lock(c.root))
    assert {:error, :transaction_unsafe} = T.allocation(cap, :flat)
    assert :ok = T.release(cap)
    flat = Path.join(c.base, "b")
    assert {:ok, cap} = T.acquire(lock(flat))
    assert :ok = T.stage(cap, ".", [{pending(1), "control"}])
    assert {:ok, %{logical: logical}} = T.allocation(cap, :flat)
    assert logical >= 7
    assert {:error, :invalid_transaction_request} = T.allocation(cap, :other)
    assert :ok = T.release(cap)
  end

  test "production helper selection ignores the ambient general helper override", c do
    System.put_env("IPSE_RUNNER_PATH", c.fault)
    File.rm(c.marker)

    case Ipse.Runner.Transaction.acquire(lock(c.root)) do
      {:ok, cap} ->
        assert :ok =
                 Ipse.Runner.Transaction.stage(cap, ".", [
                   {pending(1), "private synthetic control"}
                 ])

        assert :ok = Ipse.Runner.Transaction.switch(cap, pending(1), "control.json")
        assert :ok = Ipse.Runner.Transaction.release(cap)

      {:error, :transaction_unavailable} ->
        # A source-only native rebuild invalidates the compile-bound checksum
        # until Runner is rebuilt. Refusal still cannot invoke the override.
        refute File.exists?(Path.join(c.root, "control.json"))
    end

    refute File.exists?(c.marker)
  end

  test "native quota preflight refuses payload before creation and cannot be widened", c do
    root = Path.join(c.base, "b")
    assert {:ok, cap} = T.acquire(lock(root))

    case T.quota(cap, :flat, 2 * 1024 * 1024) do
      :ok ->
        assert {:error, :transaction_capacity} = T.preflight(cap, [1024 * 1024 + 1])

        assert {:error, :transaction_capacity} =
                 T.stage(cap, ".", [{pending(1), :binary.copy("x", 1024 * 1024 + 1)}])

        refute File.exists?(Path.join(root, pending(1)))
        assert :ok = T.preflight(cap, [1024 * 1024])
        assert :ok = T.stage(cap, ".", [{pending(1), :crypto.strong_rand_bytes(1024 * 1024)}])
        assert {:ok, %{allocated: actual}} = T.allocation(cap, :flat)
        assert actual > 0 and actual <= 2 * 1024 * 1024
        assert :ok = T.quota(cap, :flat, actual)
        assert {:error, :invalid_transaction_request} = T.quota(cap, :flat, 2 * 1024 * 1024)
        assert {:error, :invalid_transaction_request} = T.quota(cap, :collection, actual)
        assert {:error, :transaction_capacity} = T.stage(cap, ".", [{pending(2), "x"}])
        refute File.exists?(Path.join(root, pending(2)))

      {:error, :transaction_filesystem_unsupported} ->
        refute File.exists?(Path.join(root, pending(1)))
    end

    assert :ok = T.release(cap)
  end

  defp frame(tag, bytes), do: <<tag, byte_size(bytes)::32, bytes::binary>>

  defp drain(port, bytes) do
    receive do
      {^port, {:data, chunk}} -> drain(port, bytes <> chunk)
      {^port, {:exit_status, 0}} -> bytes
      {:EXIT, ^port, _} -> drain(port, bytes)
    after
      3000 ->
        Ipse.Runner.close_stdio(port)
        flunk("transaction protocol did not terminate")
    end
  end

  defp pending(n),
    do: ".pending-" <> String.pad_leading(String.downcase(Integer.to_string(n, 16)), 32, "0")

  defp immutable(n),
    do: String.pad_leading(String.downcase(Integer.to_string(n, 16)), 64, "0") <> ".json"

  defp lock(root), do: Path.join(root, ".lock")
  defp id, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

  defp private(path) do
    File.mkdir!(path)
    File.chmod!(path, 0o700)
  end
end
