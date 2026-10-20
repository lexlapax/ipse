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
