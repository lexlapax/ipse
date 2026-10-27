defmodule Ipse.RunnerStorageBackpressureTest do
  use ExUnit.Case, async: false

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-storage-pressure-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    {:ok, real} = Ipse.Runner.native_helper(parent)
    probe = Path.join(parent, "probe")

    assert {_, 0} =
             System.cmd(
               "rustc",
               [
                 "--edition=2021",
                 "-D",
                 "warnings",
                 "test/support/storage_backpressure_probe.rs",
                 "-o",
                 probe
               ],
               env: [{"IPSE_REAL_HELPER", real}],
               stderr_to_stdout: true
             )

    previous = System.get_env("IPSE_RUNNER_PATH")
    System.put_env("IPSE_RUNNER_PATH", probe)

    on_exit(fn ->
      if previous,
        do: System.put_env("IPSE_RUNNER_PATH", previous),
        else: System.delete_env("IPSE_RUNNER_PATH")

      File.rm_rf!(parent)
    end)

    %{parent: parent}
  end

  @tag timeout: 20_000
  test "maximum input cannot suspend forever behind a stopped nonreading helper", c do
    path = Path.join(c.parent, ".pending-" <> Ipse.Usage.id())
    started = System.monotonic_time(:millisecond)

    task =
      Task.async(fn ->
        Ipse.Runner.protected_staging_write(path, String.duplicate("x", 8 * 1024 * 1024))
      end)

    result = Task.await(task, 12_000)
    assert System.monotonic_time(:millisecond) - started < 10_000
    assert File.exists?(path <> ".pid")
    pid = File.read!(path <> ".pid")
    assert Regex.match?(~r/\A[0-9]+\z/, pid)

    await(fn ->
      match?({_, code} when code != 0, System.cmd("kill", ["-0", pid], stderr_to_stdout: true))
    end)

    assert {:error, :protected_staging_write_unavailable} = result
  end

  @tag timeout: 20_000
  test "resource cancellation interrupts a backpressured maximum write and confirms owned cleanup",
       c do
    path = Path.join(c.parent, ".pending-" <> Ipse.Usage.id())
    {:ok, scope} = Ipse.Session.Resources.start(self())

    task =
      Task.async(fn ->
        Ipse.Session.Resources.bind(scope)
        Ipse.Runner.protected_staging_write(path, String.duplicate("x", 8 * 1024 * 1024))
      end)

    await(fn -> map_size(:sys.get_state(scope).resources) == 1 end)
    await(fn -> File.exists?(path <> ".pid") end)
    [{id, _}] = Map.to_list(:sys.get_state(scope).resources)
    send(task.pid, {:ipse_cancel_resource, id})
    started = System.monotonic_time(:millisecond)
    assert {:error, :protected_staging_write_unavailable} = Task.await(task, 8_000)
    assert System.monotonic_time(:millisecond) - started < 5_000
    await(fn -> :sys.get_state(scope).resources == %{} end)
    assert :ok = Ipse.Session.Resources.finish(scope)
  end

  @tag timeout: 20_000
  test "owner death stops a stopped writer and releases the retained kernel lease", c do
    path = Path.join(c.parent, ".pending-" <> Ipse.Usage.id())

    worker =
      spawn(fn ->
        Ipse.Runner.protected_staging_write(path, String.duplicate("x", 8 * 1024 * 1024))
      end)

    monitor = Process.monitor(worker)
    await(fn -> File.exists?(path <> ".pid") end)
    lease = Path.join(c.parent, ".writer.lock")
    inode = File.stat!(lease).inode
    assert {:error, _} = Ipse.Runner.lock(lease)
    Process.exit(worker, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}, 1000

    await(fn ->
      case Ipse.Runner.lock(lease) do
        {:ok, lock} ->
          Ipse.Runner.unlock(lock)
          true

        _ ->
          false
      end
    end)

    assert File.stat!(lease).inode == inode
    refute File.exists?(path)
    pid = File.read!(path <> ".pid")

    await(fn ->
      match?({_, code} when code != 0, System.cmd("kill", ["-0", pid], stderr_to_stdout: true))
    end)
  end

  defp await(fun, attempts \\ 2000)

  defp await(fun, attempts) when attempts > 0 do
    unless fun.() do
      Process.sleep(1)
      await(fun, attempts - 1)
    end
  end

  defp await(_, _), do: flunk("storage helper barrier timed out")
end
