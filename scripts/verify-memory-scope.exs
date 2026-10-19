unless match?({:unix, :linux}, :os.type()),
  do: raise("exact aggregate scope verification requires Linux")

[helper] = System.argv()
helper = Path.expand(helper)

root =
  Path.join(
    System.tmp_dir!(),
    "ipse-memory-scope-" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  )

File.mkdir!(root)
File.chmod!(root, 0o700)
fixture = Path.join(root, "probe")

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

defmodule MemoryScopeVerification do
  def start(helper, output, command, timeout \\ 10_000, bootstrap \\ []) do
    token = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    unit = "ipse-measure-" <> token

    args =
      [
        "--user",
        "--wait",
        "--collect",
        "--quiet",
        "--pipe",
        "--expand-environment=no",
        "--unit=" <> unit,
        "--property=Type=exec",
        "--property=Delegate=memory",
        "--property=MemoryAccounting=yes",
        "--property=TimeoutStopSec=1s"
      ] ++
        bootstrap ++
        [
          helper,
          "--measure-cgroup",
          "root",
          token,
          Integer.to_string(timeout),
          output,
          "--" | command
        ]

    port =
      Port.open({:spawn_executable, System.find_executable("systemd-run")}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        {:args, args}
      ])

    System.at_exit(fn _ ->
      System.cmd("systemctl", ["--user", "stop", unit <> ".service"], stderr_to_stdout: true)
    end)

    %{port: port, output: output, token: token, unit: unit}
  end

  def finish(run) do
    {bytes, code} = receive_result(run, "", System.monotonic_time(:millisecond) + 30_000)

    case bytes do
      <<?M, size::32, body::binary-size(size)>> when code == 0 ->
        true = File.read!(Path.join(run.output, "receipt.json")) == body
        value = JSON.decode!(body)
        true = value["token"] == run.token
        value

      _ ->
        raise("collector failed: #{inspect({code, bytes})}")
    end
  end

  def refused(run) do
    {<<?E, size::32, error::binary-size(size)>>, 1} =
      receive_result(run, "", System.monotonic_time(:millisecond) + 30_000)

    true = String.contains?(error, "owner closed before admission")
    false = File.exists?(run.output)
  end

  defp receive_result(run, bytes, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {port, {:data, more}} when port == run.port ->
        if byte_size(bytes) + byte_size(more) > 8192, do: raise("collector output exceeds bound")
        receive_result(run, bytes <> more, deadline)

      {port, {:exit_status, code}} when port == run.port ->
        {bytes, code}
    after
      remaining -> raise("collector verification timed out")
    end
  end

  def wait_file(path, attempts \\ 500)
  def wait_file(_, 0), do: raise("probe did not reach expected state")

  def wait_file(path, attempts) do
    case File.read(path) do
      {:ok, bytes} ->
        bytes

      {:error, :enoent} ->
        Process.sleep(10)
        wait_file(path, attempts - 1)
    end
  end

  def assert_closed(value, complete) do
    true = value["cleanup_confirmed"] and value["born_in_scope"]
    true = value["complete"] == complete
    true = value["metric"] == "linux_memcg_charged_peak_bytes_v1"
    value
  end

  def exited(pid, attempts \\ 500)
  def exited(_, 0), do: raise("owned descendant still live")

  def exited(pid, attempts) do
    case File.read("/proc/#{pid}/status") do
      {:error, :enoent} ->
        :ok

      {:ok, text} ->
        if String.contains?(text, "State:\tZ"),
          do: :ok,
          else:
            (
              Process.sleep(10)
              exited(pid, attempts - 1)
            )
    end
  end
end

alias MemoryScopeVerification, as: Verify

serial =
  Verify.start(helper, Path.join(root, "serial"), [fixture, "serial"])
  |> Verify.finish()
  |> Verify.assert_closed(true)

overlap =
  Verify.start(helper, Path.join(root, "overlap"), [fixture, "overlap"])
  |> Verify.finish()
  |> Verify.assert_closed(true)

true = overlap["peak_bytes"] > serial["peak_bytes"] + 48 * 1024 * 1024
code = "{_, 0} = System.cmd(hd(System.argv()), [\"brief\"])"

erts =
  Verify.start(helper, Path.join(root, "erts"), [
    System.find_executable("elixir"),
    "-e",
    code,
    "--",
    fixture
  ])
  |> Verify.finish()
  |> Verify.assert_closed(true)

true = erts["peak_bytes"] > 200 * 1024 * 1024

nested =
  Verify.start(helper, Path.join(root, "nested"), [fixture, "nested", helper, root])
  |> Verify.finish()
  |> Verify.assert_closed(true)

for n <- 1..2 do
  value =
    Path.join([root, "cell-#{n}", "receipt.json"])
    |> File.read!()
    |> JSON.decode!()
    |> Verify.assert_closed(true)

  true = value["role"] == "cell" and value["peak_bytes"] > 48 * 1024 * 1024
  true = value["parent_interval_peak_bytes"] >= value["peak_bytes"]
  true = nested["peak_bytes"] >= value["parent_interval_peak_bytes"]
end

large = Path.join([root, "cell-1", "receipt.json"]) |> File.read!() |> JSON.decode!()
small = Path.join([root, "cell-2", "receipt.json"]) |> File.read!() |> JSON.decode!()

true =
  small["parent_interval_peak_bytes"] + 128 * 1024 * 1024 < large["parent_interval_peak_bytes"]

true = nested["peak_bytes"] >= large["parent_interval_peak_bytes"]

marker = Path.join(root, "preclosed-executed")

closed =
  Verify.start(
    helper,
    Path.join(root, "preclosed"),
    ["/bin/sh", "-c", "printf executed > \"$1\"", "ipse-fixture", marker],
    10000,
    [fixture, "closed-exec"]
  )

Verify.refused(closed)
false = File.exists?(marker)

cancel_pid = Path.join(root, "cancel-pid")
cancel = Verify.start(helper, Path.join(root, "cancel"), [fixture, "tree", cancel_pid])
pid = Verify.wait_file(cancel_pid) |> String.to_integer()
true = Port.command(cancel.port, String.duplicate("x", 4095) <> "C")
canceled = Verify.finish(cancel) |> Verify.assert_closed(false)
true = canceled["reason"] == "owner_closed"
Verify.exited(pid)

cell_lost =
  Verify.start(helper, Path.join(root, "cell-loss"), [fixture, "cell-loss", helper, root])
  |> Verify.finish()
  |> Verify.assert_closed(true)

true = cell_lost["complete"]

timeout_pid = Path.join(root, "timeout-pid")
timeout = Verify.start(helper, Path.join(root, "timeout"), [fixture, "tree", timeout_pid], 1000)
pid = Verify.wait_file(timeout_pid) |> String.to_integer()
timed = Verify.finish(timeout) |> Verify.assert_closed(false)
true = timed["reason"] == "timeout"
Verify.exited(pid)

owner_pid = Path.join(root, "owner-pid")
owner = Verify.start(helper, Path.join(root, "owner"), [fixture, "tree", owner_pid])
pid = Verify.wait_file(owner_pid) |> String.to_integer()
Port.close(owner.port)

lost =
  Verify.wait_file(Path.join(owner.output, "receipt.json"))
  |> JSON.decode!()
  |> Verify.assert_closed(false)

true = lost["reason"] == "owner_closed"
Verify.exited(pid)

collector_pid = Path.join(root, "collector-child-pid")
collector = Verify.start(helper, Path.join(root, "collector"), [fixture, "tree", collector_pid])
pid = Verify.wait_file(collector_pid) |> String.to_integer()

{_, 0} =
  System.cmd(
    "systemctl",
    ["--user", "kill", "--kill-whom=main", "--signal=SIGKILL", collector.unit <> ".service"],
    stderr_to_stdout: true
  )

Verify.exited(pid)
false = File.exists?(Path.join(collector.output, "receipt.json"))
true = File.exists?(Path.join(collector.output, "started.json"))

IO.puts(
  JSON.encode!(%{
    checks: 10,
    serial_peak: serial["peak_bytes"],
    overlapping_peak: overlap["peak_bytes"],
    erts_peak: erts["peak_bytes"],
    nested_peak: nested["peak_bytes"],
    timeout_cleanup: true,
    owner_loss_cleanup: true,
    collector_loss_incomplete: true,
    nested_collector_loss_cleanup: true,
    preclosed_owner_zero_execution: true,
    buffered_cancel_observed: true,
    independent_intervals: true,
    inherited_sigchld_normalized: true,
    inference_requests: 0,
    evidence: root
  })
)
