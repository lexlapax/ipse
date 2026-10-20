unless match?({:unix, :linux}, :os.type()),
  do: raise("measured sequence verification requires Linux")

Code.require_file("../test/support/memory_scope_verification.exs", __DIR__)
alias MemoryScopeVerification, as: Verify
[helper] = System.argv()
helper = Path.expand(helper)

root =
  Path.join(
    System.tmp_dir!(),
    "ipse-memory-sequence-" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  )

File.mkdir!(root)
File.chmod!(root, 0o700)
fixture = Path.join(root, "allocate")

{_, 0} =
  System.cmd(
    "rustc",
    [
      "--edition=2021",
      "-O",
      Path.expand("../test/support/memory_scope_probe.rs", __DIR__),
      "-o",
      fixture
    ],
    stderr_to_stdout: true
  )

probe = Path.expand("../test/support/memory_sequence_probe.exs", __DIR__)
elixir = System.find_executable("elixir")

defmodule MemorySequenceVerification do
  def token, do: Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

  def await_ready(port, bytes) do
    receive do
      {^port, {:data, more}} when byte_size(bytes) + byte_size(more) <= 64 ->
        bytes = bytes <> more
        if bytes == "ready\n", do: :ok, else: await_ready(port, bytes)

      {^port, _} ->
        raise "unrelated allocator stopped before readiness"
    after
      5000 -> raise "unrelated allocator did not become ready"
    end
  end

  def string(value), do: <<byte_size(value)::32, value::binary>>

  def stage(value) do
    IO.iodata_to_binary([
      string(value.token),
      <<value.timeout::64>>,
      string(value.output),
      <<length(value.argv)::32>>,
      Enum.map(value.argv, &string/1)
    ])
  end

  def save(path, bytes) do
    File.write!(path, bytes, [:exclusive, :sync])
    File.chmod!(path, 0o600)
    {:ok, :ok} = File.open(Path.dirname(path), [:read, :raw, :directory], &:file.sync/1)
  end

  def scenario(root, name, fixture, elixir, probe, outcome \\ :success) do
    base = Path.join(root, name)
    File.mkdir!(base)
    File.chmod!(base, 0o700)
    descriptor = Path.join(base, "generated-cells.bin")
    seed = Path.join(base, "seed.bin")
    sequence = Path.join(base, "sequence")

    stage = fn id, mode, arguments ->
      %{
        token: token(),
        timeout: 15_000,
        output: Path.join(base, "metric-" <> id),
        argv: [elixir, probe, mode | arguments]
      }
    end

    first =
      if outcome == :loss,
        do: stage.("one", "hold", [fixture, Path.join(base, "held-descendant")]),
        else:
          stage.("one", "stage", [fixture, "64", Path.join(base, "one-executed"), "0", "false"])

    second =
      stage.("two", "stage", [
        fixture,
        "128",
        Path.join(base, "two-executed"),
        if(outcome == :failure, do: "7", else: "0"),
        if(outcome == :failure, do: "true", else: "false")
      ])

    save(seed, IO.iodata_to_binary(["IPSCELL1", <<2::32>>, stage(first), stage(second)]))

    preparation =
      stage.("prepare", if(outcome == :fifo, do: "prepare-fifo", else: "prepare"), [
        descriptor,
        seed,
        fixture,
        Path.join(base, "prepared")
      ])

    finalization =
      stage.("finalize", "stage", [fixture, "256", Path.join(base, "finalized"), "0", "false"])

    bootstrap = Path.join(base, "bootstrap.bin")

    save(
      bootstrap,
      IO.iodata_to_binary([
        "IPSEQ001",
        string(sequence),
        string(descriptor),
        stage(preparation),
        stage(finalization)
      ])
    )

    %{
      base: base,
      bootstrap: bootstrap,
      sequence: sequence,
      preparation: preparation,
      first: first,
      second: second,
      finalization: finalization
    }
  end

  def receipt(path), do: path |> Path.join("receipt.json") |> File.read!() |> JSON.decode!()

  def summary(run),
    do: run.sequence |> Path.join("sequence.json") |> File.read!() |> JSON.decode!()

  def snapshot(root) do
    Path.wildcard(Path.join(root, "**/*"))
    |> Enum.filter(&File.regular?/1)
    |> Map.new(fn path -> {path, :crypto.hash(:sha256, File.read!(path))} end)
  end

  def kill(pid) do
    {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(pid)], stderr_to_stdout: true)
  end
end

alias MemorySequenceVerification, as: Sequence

unrelated =
  Port.open({:spawn_executable, fixture}, [:binary, :exit_status, {:args, ["allocate", "256"]}])

Sequence.await_ready(unrelated, "")

positive = Sequence.scenario(root, "positive", fixture, elixir, probe)

whole =
  Verify.start(
    helper,
    Path.join(positive.base, "whole"),
    [helper, "--measure-sequence", positive.bootstrap],
    30_000
  )
  |> Verify.finish()
  |> Verify.assert_closed(true)

true =
  Sequence.summary(positive) == %{
    "version" => 1,
    "stages" => 4,
    "complete" => true,
    "cleanup_confirmed" => true
  }

for index <- 0..3 do
  <<1, 1>> =
    File.read!(
      Path.join(
        positive.sequence,
        "stage-#{String.pad_leading(Integer.to_string(index), 3, "0")}.status"
      )
    )
end

prep = Sequence.receipt(positive.preparation.output)
last = Sequence.receipt(positive.finalization.output)
true = prep["peak_bytes"] >= 128 * 1024 * 1024
true = last["peak_bytes"] >= 256 * 1024 * 1024
true = whole["peak_bytes"] >= max(prep["peak_bytes"], last["peak_bytes"])
true = prep["parent_interval_peak_bytes"] >= prep["peak_bytes"]
true = last["parent_interval_peak_bytes"] >= last["peak_bytes"]
true = whole["peak_bytes"] < 512 * 1024 * 1024
true = Port.command(unrelated, "x")

receive do
  {^unrelated, {:exit_status, 0}} -> :ok
  {^unrelated, event} -> raise("unrelated allocation cleanup failed: #{inspect(event)}")
after
  5000 -> raise "unrelated allocation did not exit"
end

before = Sequence.snapshot(positive.sequence)

refused =
  Verify.start(
    helper,
    Path.join(positive.base, "repeat-whole"),
    [helper, "--measure-sequence", positive.bootstrap],
    30_000
  )
  |> Verify.finish()
  |> Verify.assert_closed(false)

true = refused["exit_code"] != 0
true = before == Sequence.snapshot(positive.sequence)
true = File.read!(Path.join(positive.base, "prepared")) == "prepared\n"

failed = Sequence.scenario(root, "failed-stage", fixture, elixir, probe, :failure)

Verify.start(
  helper,
  Path.join(failed.base, "whole"),
  [helper, "--measure-sequence", failed.bootstrap],
  30_000
)
|> Verify.finish()
|> Verify.assert_closed(false)

false = Sequence.summary(failed)["complete"]
true = Sequence.summary(failed)["cleanup_confirmed"]
<<0, 1>> = File.read!(Path.join(failed.sequence, "stage-002.status"))
true = File.read!(Path.join(failed.base, "finalized")) == "executed\n"
true = String.starts_with?(File.read!(Path.join(failed.second.output, "process.log")), "M")

lost = Sequence.scenario(root, "collector-loss", fixture, elixir, probe, :loss)

run =
  Verify.start(
    helper,
    Path.join(lost.base, "whole"),
    [helper, "--measure-sequence", lost.bootstrap],
    30_000
  )

Verify.wait_file(Path.join(lost.base, "held-descendant"))
started = Verify.wait_file(Path.join(lost.first.output, "started.json")) |> JSON.decode!()
Sequence.kill(started["collector_pid"])
Verify.finish(run) |> Verify.assert_closed(false)
true = File.regular?(Path.join(lost.sequence, "stage-001.claim"))
false = File.exists?(Path.join(lost.sequence, "stage-001.status"))
false = File.exists?(Path.join(lost.sequence, "sequence.json"))
false = File.exists?(Path.join(lost.base, "two-executed"))
false = File.exists?(Path.join(lost.base, "finalized"))

bootstrap_fifo = Sequence.scenario(root, "bootstrap-fifo", fixture, elixir, probe)
File.rm!(bootstrap_fifo.bootstrap)
{_, 0} = System.cmd(fixture, ["fifo", bootstrap_fifo.bootstrap], stderr_to_stdout: true)
started_at = System.monotonic_time(:millisecond)

Verify.start(
  helper,
  Path.join(bootstrap_fifo.base, "whole"),
  [helper, "--measure-sequence", bootstrap_fifo.bootstrap],
  30_000
)
|> Verify.finish()
|> Verify.assert_closed(false)

true = System.monotonic_time(:millisecond) - started_at < 5000
false = File.exists?(bootstrap_fifo.sequence)
false = File.exists?(Path.join(bootstrap_fifo.base, "prepared"))

cells_fifo = Sequence.scenario(root, "cells-fifo", fixture, elixir, probe, :fifo)
started_at = System.monotonic_time(:millisecond)

Verify.start(
  helper,
  Path.join(cells_fifo.base, "whole"),
  [helper, "--measure-sequence", cells_fifo.bootstrap],
  30_000
)
|> Verify.finish()
|> Verify.assert_closed(false)

true = System.monotonic_time(:millisecond) - started_at < 5000
true = File.regular?(Path.join(cells_fifo.sequence, "stage-000.claim"))
<<1, 1>> = File.read!(Path.join(cells_fifo.sequence, "stage-000.status"))
false = File.exists?(Path.join(cells_fifo.sequence, "stage-001.claim"))
false = File.exists?(Path.join(cells_fifo.sequence, "sequence.json"))
false = File.exists?(Path.join(cells_fifo.base, "one-executed"))
false = File.exists?(Path.join(cells_fifo.base, "finalized"))

IO.puts(
  JSON.encode!(%{
    checks: 6,
    bootstrap_fifo_refused: true,
    cells_fifo_refused: true,
    measured_preparation: true,
    measured_finalization: true,
    unrelated_sibling_excluded: true,
    no_replay: true,
    failed_closed_stage_finalized: true,
    forged_child_protocol_ignored: true,
    lost_collector_halts: true,
    whole_peak_bytes: whole["peak_bytes"],
    preparation_peak_bytes: prep["peak_bytes"],
    finalization_peak_bytes: last["peak_bytes"],
    inference_requests: 0,
    evidence: root
  })
)
