defmodule Ipse.Development.Platform.MacProcessBoundary do
  def run!(helper, workspace, secret, rustc) do
    root = Path.join(workspace, ".ipse-process-probe-#{System.unique_integer([:positive])}")
    File.mkdir!(root)

    try do
      probe = Path.join(root, "process-probe")
      source = Path.join(__DIR__, "macos_process_probe.rs")

      {output, status} =
        System.cmd(rustc, ["--edition=2021", source, "-o", probe], stderr_to_stdout: true)

      if status != 0, do: raise("cannot compile process fixture: #{output}")

      gaps =
        for mode <- ["group", "setsid", "setpgid"],
            event <- [:exit, :timeout, :cancel, :owner_death],
            escaped = check!(helper, workspace, secret, probe, root, mode, event),
            escaped,
            do: "#{mode}/#{event}"

      if gaps != [] do
        raise "process containment failed: #{Enum.join(gaps, ", ")}; native macOS must remain unavailable"
      end

      IO.puts("PASS: all process-boundary cases contained descendants")
    after
      File.rm_rf!(root)
    end
  end

  defp check!(helper, workspace, secret, probe, root, mode, event) do
    prefix = Path.join(root, "#{mode}-#{event}")
    ready = prefix <> ".ready"
    release = prefix <> ".release"
    effect = prefix <> ".effect"
    role = if event == :exit, do: "exit", else: "hold"

    command =
      Enum.map_join(
        [probe, "parent", mode, role, ready, release, effect, secret],
        " ",
        &quote_shell/1
      )

    owner = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        port =
          Port.open({:spawn_executable, String.to_charlist(helper)}, [
            :binary,
            :exit_status,
            :use_stdio,
            args: [workspace, "1000", command]
          ])

        {:os_pid, helper_pid} = Port.info(port, :os_pid)
        send(owner, {:probe_port, self(), port, helper_pid})
        collect(port, owner, <<>>, event, System.monotonic_time(:millisecond) + 5_000)
      end)

    try do
      {port, helper_pid} =
        receive do
          {:probe_port, ^pid, port, helper_pid} ->
            {port, helper_pid}

          {:DOWN, ^monitor, :process, ^pid, reason} ->
            raise "probe owner failed: #{inspect(reason)}"
        after
          5_000 -> raise "probe owner did not start"
        end

      receive do
        {:probe_ready, ^pid} ->
          :ok

        {:DOWN, ^monitor, :process, ^pid, reason} ->
          raise "fixture failed before readiness: #{inspect(reason)}"
      after
        5_000 -> raise "descendant did not become ready"
      end

      # Readiness follows the actual group change and inherited-policy check.
      [child, group] = File.read!(ready) |> String.split() |> Enum.map(&String.to_integer/1)
      if mode != "group" and child != group, do: raise("escape did not create its own group")

      case event do
        :cancel -> send(pid, :cancel)
        :owner_death -> Process.exit(pid, :kill)
        _ -> :ok
      end

      receive do
        {:DOWN, ^monitor, :process, ^pid, reason} ->
          expected = if event == :owner_death, do: :killed, else: :normal
          if reason != expected, do: raise("fixture owner failed: #{inspect(reason)}")
      after
        5_000 -> raise "helper did not finish"
      end

      await!(fn -> Port.info(port) == nil end, 1_000, "helper port remained open")
      await!(fn -> not alive?(probe, helper_pid) end, 1_000, "helper process remained alive")
      File.write!(release, "release\n")
      Process.sleep(200)
      survived = File.exists?(effect)

      if survived do
        await!(
          fn -> not alive?(probe, child) end,
          2_000,
          "bounded descendant did not exit"
        )
      else
        if alive?(probe, child),
          do: raise("descendant still alive without an effect; inconclusive check")
      end

      if mode == "group" and survived, do: raise("ordinary group cleanup failed for #{event}")

      IO.puts(
        "#{if survived, do: "GAP", else: "PASS"}: #{mode}/#{event}, post-cleanup write=#{survived}"
      )

      survived
    after
      if Process.alive?(pid), do: Process.exit(pid, :kill)
      Process.demonitor(monitor, [:flush])
    end
  end

  defp alive?(probe, pid) do
    case System.cmd(probe, ["alive", Integer.to_string(pid)], stderr_to_stdout: true) do
      {"alive\n", 0} -> true
      {"gone\n", 0} -> false
      result -> raise "cannot check fixture liveness: #{inspect(result)}"
    end
  end

  defp collect(port, owner, buffer, event, deadline) do
    receive do
      {^port, {:data, data}} ->
        buffer = buffer <> data

        if String.contains?(buffer, "process-probe-ready\n"),
          do: send(owner, {:probe_ready, self()})

        collect(port, owner, buffer, event, deadline)

      {^port, {:exit_status, 0}} ->
        expected = if event == :timeout, do: "\"timed_out\":true", else: "\"timed_out\":false"

        unless String.contains?(buffer, expected),
          do: raise("missing expected helper result: #{inspect(buffer)}")

      {^port, {:exit_status, status}} ->
        raise "helper failed with #{status}: #{inspect(buffer)}"

      :cancel ->
        Port.close(port)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        Port.close(port)
        raise "helper exceeded probe deadline"
    end
  end

  defp await!(fun, milliseconds, error) do
    deadline = System.monotonic_time(:millisecond) + milliseconds
    await_until!(fun, deadline, error)
  end

  defp await_until!(fun, deadline, error) do
    unless fun.() do
      if System.monotonic_time(:millisecond) >= deadline, do: raise(error)
      Process.sleep(10)
      await_until!(fun, deadline, error)
    end
  end

  defp quote_shell(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"
end
