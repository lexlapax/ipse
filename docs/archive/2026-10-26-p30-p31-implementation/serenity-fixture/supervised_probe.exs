# Proposed actual Transaction-supervisor staging probe. Live entry remains
# disabled: mount identity, tool trust, resource cleanup and cgroup monitoring
# must be independently reviewed and implemented by the outer harness.
defmodule IpseSerenitySupervisedProbe do
  @live_enabled false
  @bytes 8_388_608
  @pending ".pending-" <> String.duplicate("b", 32)

  def eligible_size?(value), do: is_integer(value) and value > 0 and value < @bytes
  def fault_outcome({:unknown, _}), do: :native_io_unknown
  def fault_outcome(_), do: :not_proven

  def run(root, after_paused) do
    if @live_enabled,
      do: proposed_run(root, after_paused),
      else: {:error, :live_probe_not_reviewed}
  end

  # `after_paused` is trusted host code that must synchronously verify fixture
  # identities, install the exact error target, and independently confirm its
  # own EIO sentinel. This callback is not permission or proof of native errno.
  defp proposed_run("/work/mount/transaction" = root, after_paused)
       when is_function(after_paused, 0) do
    coordinator = self()
    tag = make_ref()
    path = Path.join(root, @pending)
    lock = Path.join(root, ".lock")

    task =
      Task.async(fn ->
        Ipse.Session.Resources.file_effect(fn ->
          with {:ok, cap} <- Ipse.Runner.Transaction.acquire(lock, cwd: root, timeout_ms: 90_000),
               :ok <- Ipse.Runner.Transaction.quota(cap, :flat, 67_108_864) do
            send(coordinator, {tag, :controller, cap.controller})

            Ipse.Runner.Transaction.stage(cap, ".", [
              {@pending, :crypto.strong_rand_bytes(@bytes)}
            ])
          end
        end)
      end)

    try do
      with {:ok, controller} <- controller(task, tag),
           :ok <- await_partial(path, controller, System.monotonic_time(:millisecond) + 10_000),
           :ok <- pause_guarded(path, controller, coordinator, after_paused),
           {:ok, result} <- Task.yield(task, 10_000) do
        %{
          outcome: fault_outcome(result),
          original_result: result,
          native_errno_proven: false,
          cleanup_confirmed: false
        }
      else
        _ -> %{outcome: :unknown, native_errno_proven: false, cleanup_confirmed: false}
      end
    after
      # This force-stops only the BEAM task. It is not evidence of complete OS,
      # helper, filesystem or cgroup cleanup; the outer harness must prove that.
      Task.shutdown(task, :brutal_kill)
    end
  end

  defp proposed_run(_, _), do: {:error, :invalid_fixture}

  defp controller(task, tag) do
    receive do
      {^tag, :controller, pid} when is_pid(pid) -> {:ok, pid}
      {ref, _} when ref == task.ref -> {:error, :owner_finished}
      {:DOWN, ref, :process, _, _} when ref == task.ref -> {:error, :owner_lost}
    after
      10_000 -> {:error, :owner_timeout}
    end
  end

  defp await_partial(path, controller, deadline) do
    if System.monotonic_time(:millisecond) >= deadline or not Process.alive?(controller) do
      {:error, :boundary_unobserved}
    else
      case File.stat(path) do
        {:ok, %File.Stat{type: :regular, size: size}} when size > 0 and size < @bytes ->
          :ok

        {:ok, %File.Stat{size: size}} when size >= @bytes ->
          {:error, :already_complete}

        _ ->
          Process.sleep(2)
          await_partial(path, controller, deadline)
      end
    end
  end

  defp pause_guarded(path, controller, coordinator, after_paused) do
    guardian =
      spawn(fn ->
        monitor = Process.monitor(coordinator)

        receive do
          {:pause, from, ref} ->
            result =
              try do
                :erlang.suspend_process(controller)
              rescue
                _ -> false
              end

            send(from, {ref, result})

            if result do
              receive do
                {:release, from, release_ref} ->
                  release_result = resume(controller)
                  send(from, {release_ref, release_result})

                {:DOWN, ^monitor, :process, ^coordinator, _} ->
                  resume(controller)
              end
            end

          {:DOWN, ^monitor, :process, ^coordinator, _} ->
            :ok
        end
      end)

    result =
      try do
        pause_ref = make_ref()
        send(guardian, {:pause, self(), pause_ref})

        true =
          receive do
            {^pause_ref, value} -> value
          after
            5_000 -> false
          end

        # A D command can have been in flight before the BEAM pause. Require a
        # stable, still-incomplete named file twice; this is not a dirty-page proof.
        Process.sleep(30)
        {:ok, %File.Stat{type: :regular, size: first, links: 1} = before} = File.lstat(path)
        Process.sleep(30)
        {:ok, %File.Stat{type: :regular, size: second, links: 1} = later} = File.lstat(path)

        true =
          eligible_size?(first) and first == second and before.inode == later.inode and
            before.major_device == later.major_device and
            before.minor_device == later.minor_device and
            Process.alive?(controller)

        :ok = after_paused.()
        :ok
      rescue
        _ -> {:error, :pause_or_fault_unconfirmed}
      catch
        _, _ -> {:error, :pause_or_fault_unconfirmed}
      end

    ref = make_ref()
    send(guardian, {:release, self(), ref})

    release =
      receive do
        {^ref, value} -> value
      after
        5_000 -> {:error, :resume_unconfirmed}
      end

    if release == :ok, do: result, else: {:error, :resume_unconfirmed}
  end

  defp resume(pid) do
    try do
      :erlang.resume_process(pid)
      :ok
    rescue
      _ -> {:error, :resume_unconfirmed}
    end
  end

  @doc false
  def guardian_test do
    path = Path.join(System.tmp_dir!(), "ipse-pause-mock-#{System.unique_integer([:positive])}")
    File.write!(path, "synthetic", [:exclusive])

    target =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    try do
      :ok =
        pause_guarded(path, target, self(), fn ->
          {:status, :suspended} = Process.info(target, :status)
          :ok
        end)

      {:status, :waiting} = Process.info(target, :status)
      parent = self()

      coordinator =
        spawn(fn ->
          pause_guarded(path, target, self(), fn ->
            send(parent, :paused)

            receive do
              :never -> :ok
            end
          end)
        end)

      receive do
        :paused -> :ok
      after
        5_000 -> raise "guardian did not pause"
      end

      Process.exit(coordinator, :kill)
      wait_resumed(target, System.monotonic_time(:millisecond) + 5_000)
      :ok
    after
      send(target, :stop)
      File.rm!(path)
    end
  end

  defp wait_resumed(target, deadline) do
    case Process.info(target, :status) do
      {:status, status} when status != :suspended ->
        :ok

      _ ->
        if System.monotonic_time(:millisecond) >= deadline, do: raise("guardian resume timeout")
        Process.sleep(10)
        wait_resumed(target, deadline)
    end
  end
end

case System.argv() do
  ["test"] ->
    true = IpseSerenitySupervisedProbe.eligible_size?(1)
    true = IpseSerenitySupervisedProbe.eligible_size?(8_388_607)
    false = IpseSerenitySupervisedProbe.eligible_size?(0)
    false = IpseSerenitySupervisedProbe.eligible_size?(8_388_608)
    :native_io_unknown = IpseSerenitySupervisedProbe.fault_outcome({:unknown, :fixture})
    :not_proven = IpseSerenitySupervisedProbe.fault_outcome(:ok)

    {:error, :live_probe_not_reviewed} =
      IpseSerenitySupervisedProbe.run("/work/mount/transaction", fn -> :ok end)

    :ok = IpseSerenitySupervisedProbe.guardian_test()
    IO.puts("supervised probe classification mock: passed")

  _ ->
    IO.puts(:stderr, "usage: MIX_ENV=test mix run supervised_probe.exs test")
    System.halt(2)
end
