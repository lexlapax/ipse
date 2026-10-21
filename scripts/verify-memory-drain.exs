unless match?({:unix, :linux}, :os.type()),
  do: raise("population drain verification requires Linux")

Code.require_file("../dev/platform/memory_scope.exs", __DIR__)
alias Ipse.Development.Platform.MemoryScope, as: Verify
[helper] = System.argv()
helper = Path.expand(helper)

root =
  Path.join(
    System.tmp_dir!(),
    "ipse-memory-drain-" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  )

File.mkdir!(root)
File.chmod!(root, 0o700)
fixture = Path.join(root, "probe")

{_, 0} =
  System.cmd(
    "rustc",
    [
      "--edition=2021",
      "-D",
      "warnings",
      "-O",
      Path.expand("../dev/platform/memory_scope_probe.rs", __DIR__),
      "-o",
      fixture
    ],
    stderr_to_stdout: true
  )

start = fn name, group, code, timeout ->
  pid_file = Path.join(root, name <> "-child")
  leader_file = Path.join(root, name <> "-leader")

  run =
    Verify.start(
      helper,
      Path.join(root, name),
      [fixture, "tail", pid_file, leader_file, group, Integer.to_string(code)],
      timeout
    )

  pid = Verify.wait_file(pid_file) |> String.to_integer()
  leader = Verify.wait_file(leader_file) |> String.to_integer()
  Verify.exited(leader)
  reaped = Verify.wait_json(Path.join(run.output, "leader-exited.json"))
  true = reaped["token"] == run.token and reaped["exit_code"] == code
  {run, pid, pid_file}
end

for group <- ["ordinary", "detached"] do
  {run, pid, pid_file} = start.("natural-" <> group, group, 0, 10_000)
  File.write!(pid_file <> ".release", "go")
  value = Verify.finish(run) |> Verify.assert_closed(true)
  true = value["population_exit"] == "natural"
  true = value["population_drain_limit_ms"] == 2000
  true = value["population_drain_ms"] >= 50 and value["population_drain_ms"] < 2000
  true = value["peak_bytes"] >= 128 * 1024 * 1024
  Verify.exited(pid)
end

pid_file = Path.join(root, "nested-child")
leader_file = Path.join(root, "nested-leader")
cell_output = Path.join(root, "nested-cell")

run =
  Verify.start(helper, Path.join(root, "nested"), [
    fixture,
    "tail-nested",
    helper,
    cell_output,
    pid_file,
    leader_file
  ])

pid = Verify.wait_file(pid_file) |> String.to_integer()
Verify.wait_file(leader_file) |> String.to_integer() |> Verify.exited()
true = Verify.wait_json(Path.join(cell_output, "leader-exited.json"))["exit_code"] == 0
File.write!(pid_file <> ".release", "go")
whole = Verify.finish(run) |> Verify.assert_closed(true)

cell =
  File.read!(Path.join(cell_output, "receipt.json"))
  |> JSON.decode!()
  |> Verify.assert_closed(true)

true = cell["population_drain_ms"] >= 50 and cell["population_drain_ms"] < 2000
true = cell["peak_bytes"] >= 128 * 1024 * 1024
true = cell["parent_interval_peak_bytes"] >= cell["peak_bytes"]
true = whole["peak_bytes"] >= cell["parent_interval_peak_bytes"]
Verify.exited(pid)

for {name, code, timeout, reason} <- [
      {"persistent", 0, 10_000, "residual_descendants"},
      {"nonzero", 7, 10_000, "command_failed"},
      {"deadline", 0, 500, "timeout"}
    ] do
  {run, pid, _} = start.(name, "detached", code, timeout)
  value = Verify.finish(run) |> Verify.assert_closed(false)
  true = value["reason"] == reason and value["population_exit"] == "forced"
  if name == "persistent", do: true = value["population_drain_ms"] >= 2000
  Verify.exited(pid)
end

{run, pid, _} = start.("owner", "detached", 0, 10_000)
true = Port.command(run.port, "C")
value = Verify.finish(run) |> Verify.assert_closed(false)
true = value["reason"] == "owner_closed" and value["population_exit"] == "forced"
Verify.exited(pid)

{run, pid, _} = start.("anchor", "detached", 0, 10_000)
started = Verify.wait_json(Path.join(run.output, "started.json"))
{_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(started["anchor_pid"])])
Verify.failed(run, "scope anchor failed")
Verify.exited(pid)

{run, pid, _} = start.("collector", "detached", 0, 10_000)

{_, 0} =
  System.cmd(
    "systemctl",
    ["--user", "kill", "--kill-whom=main", "--signal=SIGKILL", run.unit <> ".service"],
    stderr_to_stdout: true
  )

Verify.exited(pid)
false = File.exists?(Path.join(run.output, "receipt.json"))
true = File.exists?(Path.join(run.output, "started.json"))

{run, pid, _} = start.("owner-eof", "detached", 0, 10_000)
Port.close(run.port)

value =
  Verify.wait_file(Path.join(run.output, "receipt.json"))
  |> JSON.decode!()
  |> Verify.assert_closed(false)

true = value["reason"] == "owner_closed" and value["population_exit"] == "forced"
Verify.exited(pid)

leader_file = Path.join(root, "late-zero-leader")
release_file = leader_file <> ".release"

run =
  Verify.start(
    helper,
    Path.join(root, "late-zero"),
    [fixture, "held-leader", leader_file, release_file],
    1000
  )

leader = Verify.wait_file(leader_file) |> String.to_integer()
started = Verify.wait_file(Path.join(run.output, "started.json")) |> JSON.decode!()
collector = Integer.to_string(started["collector_pid"])

try do
  {_, 0} = System.cmd("kill", ["-STOP", collector])
  File.write!(release_file, "go")
  Verify.exited(leader)
  Process.sleep(1100)
after
  {_, 0} = System.cmd("kill", ["-CONT", collector])
end

value = Verify.finish(run) |> Verify.assert_closed(false)
true = value["reason"] == "timeout"

base = Path.join(root, "authority")
File.mkdir!(base)
File.chmod!(base, 0o700)
registry = Path.join(base, "attempts")
File.mkdir!(registry)
File.chmod!(registry, 0o700)
native = Path.join(base, "native-root")
bootstrap = Path.join(base, "bootstrap.bin")
cells = Path.join(native, "prepared/cells.bin")
seed = Path.join(base, "cells-seed.bin")
pid_file = Path.join(base, "child")
leader_file = Path.join(base, "leader")
string = fn value -> <<byte_size(value)::32, value::binary>> end

stage = fn output, arguments ->
  token = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

  IO.iodata_to_binary([
    string.(token),
    <<10000::64>>,
    string.(output),
    <<length(arguments)::32>>,
    Enum.map(arguments, string)
  ])
end

save = fn path, bytes ->
  File.write!(path, bytes, [:exclusive, :sync])
  File.chmod!(path, 0o600)
end

save.(seed, [
  "IPSCELL1",
  <<1::32>>,
  stage.(Path.join(native, "metric-cell"), [
    fixture,
    "tail",
    pid_file,
    leader_file,
    "detached",
    "0"
  ])
])

save.(bootstrap, [
  "IPSEQ001",
  string.(Path.join(native, "sequence")),
  string.(cells),
  stage.(Path.join(native, "metric-prepare"), [fixture, "prepare-tail", seed, cells]),
  stage.(Path.join(native, "metric-final"), ["/bin/true"])
])

identity = File.stat!(registry)
authority = Path.join(base, "native-authority.bin")

save.(authority, [
  "IPBND001",
  string.(registry),
  <<identity.major_device::64, identity.inode::64>>,
  string.(native),
  string.(bootstrap)
])

run =
  Verify.start(helper, native, [helper, "--measure-sequence", bootstrap], 10000, [], authority)

pid = Verify.wait_file(pid_file) |> String.to_integer()
true = Verify.wait_json(Path.join(native, "metric-cell/leader-exited.json"))["exit_code"] == 0
File.rename!(registry, registry <> "-retained")
File.mkdir!(registry)
File.chmod!(registry, 0o700)
value = Verify.finish(run) |> Verify.assert_closed(false)
true = value["reason"] == "authority_lost"
false = File.exists?(Path.join(native, "metric-final/started.json"))
Verify.exited(pid)

IO.puts(
  JSON.encode!(%{
    checks: 12,
    natural_descendants_included: true,
    allocation_after_leader_exit_included: true,
    nested_tail_and_parent_interval_included: true,
    closed_output_is_not_population_exit: true,
    persistent_descendants_refused: true,
    nonzero_refused: true,
    original_deadline_preserved: true,
    late_zero_exit_refused: true,
    owner_loss_during_drain: true,
    owner_eof_during_drain: true,
    anchor_loss_during_drain: true,
    collector_loss_during_drain_incomplete: true,
    authority_loss_during_drain: true,
    inference_requests: 0,
    evidence: root
  })
)
