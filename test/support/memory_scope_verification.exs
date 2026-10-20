defmodule MemoryScopeVerification do
  def start(helper, output, command, timeout \\ 10_000, bootstrap \\ [], authority \\ nil) do
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
          output
        ] ++ if(authority, do: ["--bound-root", authority], else: []) ++ ["--" | command]

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

    %{port: port, output: output, token: token, unit: unit, timeout: timeout}
  end

  def finish(run) do
    {bytes, code} = receive_result(run, "", System.monotonic_time(:millisecond) + 30_000)

    case bytes do
      <<?M, size::32, body::binary-size(size)>> when code == 0 ->
        true = File.read!(Path.join(run.output, "receipt.json")) == body
        value = JSON.decode!(body)
        true = value["token"] == run.token
        if value["complete"], do: assert_closed(value, true, run.timeout)
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

  def failed(run, expected) do
    {<<?E, size::32, error::binary-size(size)>>, 1} =
      receive_result(run, "", System.monotonic_time(:millisecond) + 30_000)

    true = error == expected
    false = File.exists?(Path.join(run.output, "receipt.json"))
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

  def wait_json(path, attempts \\ 500)
  def wait_json(_, 0), do: raise("probe did not persist expected observation")

  def wait_json(path, attempts) do
    with {:ok, bytes} <- File.read(path), {:ok, value} when is_map(value) <- JSON.decode(bytes) do
      value
    else
      _ ->
        Process.sleep(10)
        wait_json(path, attempts - 1)
    end
  end

  def assert_closed(value, complete, timeout \\ nil) do
    true = value["cleanup_confirmed"] and value["born_in_scope"]
    true = value["complete"] == complete
    true = value["metric"] == "linux_memcg_charged_peak_bytes_v1"

    if complete do
      true = value["version"] == 2 and value["exit_code"] == 0 and value["reason"] == "completed"

      true =
        value["completion_policy"] == "bounded_natural_drain_v1" and
          value["population_drain_limit_ms"] == 2000

      true = value["population_exit"] == "natural"
      drain = value["natural_drain_us"]
      elapsed = value["elapsed_us"]
      true = is_integer(drain) and drain >= 0 and drain < 2_000_000
      true = value["population_drain_ms"] == div(drain, 1000)
      true = is_integer(elapsed) and elapsed >= drain
      true = is_nil(timeout) or elapsed < timeout * 1000
    end

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
