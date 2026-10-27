Code.require_file(Path.expand("../../support/transaction_fixture.exs", __DIR__))
:ok = Ipse.Test.TransactionFixtureLoader.load()

source = File.read!(Path.expand("../../../lib/ipse/runner/transaction.ex", __DIR__))

parser =
  source
  |> String.replace("Ipse.Runner.Transaction", "Ipse.Test.TransactionFramingParser")
  |> String.replace(
    ~r/    defimpl Inspect do\n      def inspect\(_, _\), do: "#Transaction.Capability<private>"\n    end\n/,
    ""
  )
  |> String.replace("defp outer(", "def outer(")
  |> String.replace("defp await_reply(", "def await_reply(")
  |> String.replace("defp await_finished(", "def await_finished(")

Code.compile_string(parser, "transaction-framing-parser-fixture.ex")

defmodule Ipse.Runner.TransactionFramingTest do
  use ExUnit.Case, async: false
  alias Ipse.Runner.Transaction, as: T
  alias Ipse.Test.TransactionFixture, as: Fault
  alias Ipse.Test.TransactionFramingParser.Controller, as: Parser
  @root Path.expand("../../..", __DIR__)

  setup_all do
    base = Path.join(System.tmp_dir!(), "ipse-framing-fixture-" <> Ipse.Usage.id())
    private(base)
    mode = Path.join(base, "mode")
    helper = Path.join(base, "helper")
    rust = Path.join(base, "helper.rs")
    bundled = Application.app_dir(:ipse, "priv/ipse-runner")

    File.write!(rust, """
    #[path=#{inspect(Path.join(@root, "native/ipse-transaction.rs"))}] mod ipse_transaction;
    #[path=#{inspect(Path.join(@root, "native/ipse-storage.rs"))}] mod ipse_storage;
    use std::{io::{self,Write},process::Command};
    use std::os::unix::process::CommandExt;
    fn frame(kind:u8,bytes:&[u8])->io::Result<()>{
      let mut output=vec![kind];output.extend_from_slice(&(bytes.len() as u32).to_be_bytes());output.extend_from_slice(bytes);
      if std::fs::read(#{inspect(mode)}).unwrap_or_default()==[kind]{output.push(kind);}
      let mut out=io::stdout().lock();out.write_all(&output)?;out.flush()
    }
    fn main(){let args:Vec<_>=std::env::args().collect();
      if args.get(1).is_some_and(|s|s=="--transaction-lock"){
        if ipse_transaction::run(&args).is_err(){std::process::exit(1)}
      }else{let _=Command::new(#{inspect(bundled)}).args(&args[1..]).exec();std::process::exit(70)}
    }
    """)

    assert {_, 0} =
             System.cmd("rustc", ["--edition=2021", "-A", "dead_code", rust, "-o", helper],
               stderr_to_stdout: true
             )

    on_exit(fn -> File.rm_rf!(base) end)
    %{mode: mode, helper: helper}
  end

  setup c do
    root = Path.join(System.tmp_dir!(), "ipse-framing-" <> Ipse.Usage.id())
    private(root)
    prior = System.get_env("IPSE_RUNNER_PATH")
    System.put_env("IPSE_RUNNER_PATH", c.helper)
    File.write!(c.mode, "")

    on_exit(fn ->
      if prior,
        do: System.put_env("IPSE_RUNNER_PATH", prior),
        else: System.delete_env("IPSE_RUNNER_PATH")

      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "actual acquire and check acknowledgements with partial next frames never succeed", c do
    File.write!(c.mode, "A")
    assert {:unknown, :transaction_lost} = Fault.acquire(lock(c))
    reacquire(c)
    File.write!(c.mode, "")
    assert {:ok, cap} = Fault.acquire(lock(c))
    File.write!(c.mode, "P")
    assert {:unknown, :transaction_lost} = Fault.check(cap)
    reacquire(c)
  end

  test "actual required and optional reads reject an already buffered partial next frame", c do
    File.write!(Path.join(c.root, "root.json"), "selected data")
    File.chmod!(Path.join(c.root, "root.json"), 0o600)

    for {tag, fun} <- [{"G", &Fault.read/4}, {"H", &Fault.read_optional/4}] do
      File.write!(c.mode, "")
      assert {:ok, cap} = Fault.acquire(lock(c))
      File.write!(c.mode, tag)
      assert {:unknown, :transaction_lost} = fun.(cap, ".", "root.json", 100)
      reacquire(c)
    end

    File.rm!(Path.join(c.root, "root.json"))
    File.write!(c.mode, "")
    assert {:ok, cap} = Fault.acquire(lock(c))
    File.write!(c.mode, "H")
    assert {:unknown, :transaction_lost} = Fault.read_optional(cap, ".", "root.json", 100)
    reacquire(c)
  end

  test "actual stage readiness and data acknowledgements reject tails without replay", c do
    for tag <- ~w(W D) do
      File.write!(c.mode, "")
      assert {:ok, cap} = Fault.acquire(lock(c))
      name = pending(if(tag == "W", do: "a", else: "b"))
      File.write!(c.mode, tag)

      assert {:unknown, :transaction_lost} =
               Fault.stage(cap, ".", [{name, :binary.copy("x", 20_000)}])

      if tag == "W" do
        refute File.exists?(Path.join(c.root, name))
      else
        assert File.stat!(Path.join(c.root, name)).size == 16_384
      end

      reacquire(c)
    end

    refute File.exists?(Path.join(c.root, "root.json"))
  end

  test "actual known-error and root-release acknowledgements also refuse partial tails", c do
    assert {:ok, cap} = Fault.acquire(lock(c))
    File.write!(c.mode, "E")
    assert {:unknown, :transaction_lost} = Fault.read(cap, ".", "root.json", 100)
    reacquire(c)
    File.write!(c.mode, "")
    assert {:ok, cap} = Fault.acquire(lock(c))
    File.write!(c.mode, "R")
    assert {:unknown, :transaction_lost} = Fault.release(cap)
    reacquire(c)
  end

  test "known buffered corruption prevents the next actual native root switch", c do
    for field <- [:inner, :outer, :replies, :finished] do
      assert {:ok, cap} = T.acquire(lock(c))
      name = pending("c")
      assert :ok = T.stage(cap, ".", [{name, "candidate"}])

      value =
        case field do
          :replies -> [{?P, <<0::64, 1>>}]
          :finished -> true
          _ -> "H"
        end

      :sys.replace_state(cap.controller, &Map.put(&1, field, value))
      assert {:unknown, :transaction_lost} = T.switch(cap, name, "root.json")
      refute File.exists?(Path.join(c.root, "root.json"))
      assert File.read!(Path.join(c.root, name)) == "candidate"
      reacquire(c)
      File.rm!(Path.join(c.root, name))
    end
  end

  test "pure parser rejects every buffered tail or queued extra before a nonterminal ack" do
    for tag <- ~c"AGHPWD", field <- [:inner, :outer, :replies, :finished] do
      state = state(%{replies: [{tag, <<1::64, 1>>}]})

      state =
        case field do
          :inner -> %{state | inner: "H"}
          :outer -> %{state | outer: "X"}
          :replies -> %{state | replies: [{tag, <<1::64, 1>>}, {tag, <<2::64, 1>>}]}
          :finished -> %{state | finished: true}
        end

      assert :unknown = Parser.await_reply(state, deadline(), {tag, 1, 1})
    end
  end

  test "pure parser assembles valid fragmented/coalesced outer data and keeps clean acks immediate" do
    ack = frame(?H, <<1::64, 1, 1, 0>>)
    <<first::binary-size(4), last::binary>> = ack
    assert {:ok, parsed} = Parser.outer(state(%{outer: frame(?O, first) <> frame(?O, last)}))

    assert {:ok, ?H, <<1::64, 1, 1, 0>>, %{inner: "", outer: "", replies: []}} =
             Parser.await_reply(parsed, deadline(), {?H, 1, 1})

    for tag <- ~c"APWD" do
      assert {:ok, ^tag, _, _} =
               Parser.await_reply(
                 state(%{replies: [{tag, <<1::64, 1>>}]}),
                 deadline(),
                 {tag, 1, 1}
               )
    end
  end

  test "pure final root release accepts coalesced X and already buffered fragmented X only" do
    ack = frame(?O, frame(?R, <<1::64, 0>>))
    terminal = frame(?X, Jason.encode!(%{"exit_code" => 0, "timed_out" => false}))
    assert {:ok, parsed} = Parser.outer(state(%{outer: ack <> terminal}))
    assert {:ok, ?R, <<1::64, 0>>, released} = Parser.await_reply(parsed, deadline(), {?R, 1, 0})
    assert {:ok, _} = Parser.await_finished(released, deadline())
    <<first::binary-size(3), last::binary>> = terminal
    assert {:ok, partial} = Parser.outer(state(%{outer: ack <> first}))
    send(self(), {partial.port, {:data, last}})
    assert {:ok, ?R, <<1::64, 0>>, released} = Parser.await_reply(partial, deadline(), {?R, 1, 0})
    assert {:ok, _} = Parser.await_finished(released, deadline())

    assert :unknown =
             Parser.await_reply(partial, System.monotonic_time(:millisecond) + 10, {?R, 1, 0})

    for expected <- [{?R, 2, 0}, {?R, 1, 1}, {?H, 1, 0}] do
      assert :unknown = Parser.await_reply(parsed, deadline(), expected)
    end
  end

  test "pure terminal state never accepts buffered bytes, duplicate X or pending replies" do
    ack = frame(?O, frame(?R, <<1::64, 0>>))
    terminal = frame(?X, Jason.encode!(%{"exit_code" => 0, "timed_out" => false}))

    for tail <- ["H", frame(?O, ""), terminal] do
      assert :unknown = Parser.outer(state(%{outer: ack <> terminal <> tail}))
    end

    for patch <- [%{inner: "H"}, %{outer: "X"}, %{replies: [{?R, <<1::64, 0>>}]}] do
      assert :unknown =
               Parser.await_finished(state(Map.merge(%{finished: true}, patch)), deadline())
    end

    assert :unknown =
             Parser.await_finished(
               state(%{finished: true}),
               System.monotonic_time(:millisecond) - 1
             )
  end

  defp reacquire(c) do
    assert {:ok, fresh} = T.acquire(lock(c))
    assert :ok = T.check(fresh)
    assert :ok = T.release(fresh)
  end

  defp state(patch),
    do:
      Map.merge(
        %{
          owner: self(),
          upstream: self(),
          inner: <<>>,
          outer: <<>>,
          replies: [],
          finished: false,
          port: make_ref(),
          monitor: make_ref(),
          upstream_monitor: make_ref(),
          ticket: nil
        },
        patch
      )

  defp deadline, do: System.monotonic_time(:millisecond) + 1_000
  defp frame(tag, bytes), do: <<tag, byte_size(bytes)::32, bytes::binary>>

  defp private(path),
    do:
      (
        File.mkdir!(path)
        File.chmod!(path, 0o700)
      )

  defp lock(c), do: Path.join(c.root, ".lock")
  defp pending(hex), do: ".pending-" <> String.duplicate(hex, 32)
end
