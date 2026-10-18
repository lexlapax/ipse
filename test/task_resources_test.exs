defmodule Ipse.TaskResourcesTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal}

  defmodule Model do
    def complete(config, messages, _, _) do
      if Enum.any?(messages, &(&1["role"] == "tool")) do
        {:ok, %{"role" => "assistant", "content" => "Done"}, %{}}
      else
        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => [
             %{
               "id" => "shell",
               "function" => %{
                 "name" => "shell",
                 "arguments" => Jason.encode!(%{"command" => config.command})
               }
             }
           ]
         }, %{}}
      end
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-task-cleanup-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, dir: Path.join(root, "sessions")}
  end

  defp start(c) do
    config = %{
      provider: :demo,
      model: "fixture",
      provider_module: Model,
      home: Path.join(c.root, "home"),
      approval: :allow,
      command: "printf $$ > shell.pid; sleep 120 & printf $! > child.pid; printf ready; wait"
    }

    {:ok, session} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: c.root, state_dir: c.dir, subscriber: self()}
      )

    on_exit(fn -> if Process.alive?(session), do: Session.close(session) end)
    :ok = Session.prompt(session, "Synthetic OS cleanup")
    assert_receive {:ipse, ^session, {:tool_output, "ready"}}, 5000
    session
  end

  test "confirmed close waits for native shell cleanup and leaves the effect unknown", c do
    session = start(c)
    id = Session.info(session).id
    assert :ok = Session.close_confirmed(session)
    assert_dead(File.read!(Path.join(c.root, "shell.pid")))
    assert_dead(File.read!(Path.join(c.root, "child.pid")))
    {:ok, events} = Journal.load(c.dir, id)

    assert Enum.any?(
             events,
             &(get_in(&1, ["message", "ipse_tool_outcome", "status"]) == "unknown")
           )
  end

  test "a stopped shell supervisor cannot yield confirmed cleanup", c do
    session = start(c)
    task = :sys.get_state(session).task.pid
    {:links, links} = Process.info(task, :links)
    [port] = Enum.filter(links, &is_port/1)
    {:os_pid, helper} = Port.info(port, :os_pid)
    assert {_, 0} = System.cmd("kill", ["-STOP", Integer.to_string(helper)])

    try do
      assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(session)
    after
      # The stopped fixture cannot exit or recycle its PID before this kill.
      System.cmd("kill", ["-KILL", Integer.to_string(helper)], stderr_to_stdout: true)
    end

    assert_dead(File.read!(Path.join(c.root, "shell.pid")))
    assert_dead(File.read!(Path.join(c.root, "child.pid")))
  end

  test "task-owned advisory locks report actual helper exit before completion", c do
    {:ok, scope} = Ipse.TaskResources.start(self())
    owner = self()

    task =
      Task.async(fn ->
        receive do
          :start -> :ok
        end

        Ipse.TaskResources.bind(scope)
        {:ok, port} = Ipse.Runner.lock(Path.join(c.root, "owned.lock"))
        {:os_pid, helper} = Port.info(port, :os_pid)
        assert :ok = Ipse.Runner.unlock(port)
        send(owner, {:released, helper})
        Ipse.TaskResources.close(scope)
      end)

    :ok = Ipse.TaskResources.attach(scope, task.pid)
    send(task.pid, :start)
    assert_receive {:released, helper}, 5000
    assert :ok = Task.await(task)
    assert_dead(Integer.to_string(helper))
  end

  test "finished tasks retain a single consumable cleanup receipt" do
    {:ok, scope} = Ipse.TaskResources.start(self())

    task =
      Task.async(fn ->
        receive do
          :start -> :ok
        end

        assert :ok = Ipse.TaskResources.finish(scope)
      end)

    assert :ok = Ipse.TaskResources.attach(scope, task.pid)
    send(task.pid, :start)
    assert :ok = Task.await(task)
    assert :ok = Ipse.TaskResources.close_task(task.pid)
    assert {:error, :cleanup_unconfirmed} = Ipse.TaskResources.close_task(task.pid)
  end

  test "a refused MCP launch with no process does not create cleanup liability", c do
    scoped(fn ->
      assert {:error, :launch_failed} =
               Ipse.MCP.Transport.start_link(
                 owner: self(),
                 cleanup_owner: self(),
                 cleanup_scope: Ipse.TaskResources.current(),
                 cwd: Path.join(c.root, "absent"),
                 server: %{command: "/bin/sh", args: [], env: %{}, timeout_ms: 1000}
               )
    end)
  end

  test "a shell or lock Port that cannot start leaves no cleanup liability", c do
    path = Path.join(c.root, "nonexecutable-helper")
    File.write!(path, "fixture")
    File.chmod!(path, 0o600)
    previous = System.get_env("IPSE_RUNNER_PATH")
    System.put_env("IPSE_RUNNER_PATH", path)

    try do
      for action <- [
            fn -> Ipse.Runner.run("true", c.root) end,
            fn -> Ipse.Runner.lock(Path.join(c.root, "refused.lock")) end
          ] do
        scoped(fn -> assert {:error, _} = action.() end)
      end
    after
      if previous,
        do: System.put_env("IPSE_RUNNER_PATH", previous),
        else: System.delete_env("IPSE_RUNNER_PATH")
    end
  end

  test "completed stdio helpers are awaited without writing into their closing input", c do
    path = Path.join(c.root, "closing-input-helper")

    File.write!(
      path,
      "#!/bin/sh\nsleep 0.1\nexec 0<&-\nprintf '\\130\\000\\000\\000\\002{}'\nsleep 0.2\n"
    )

    File.chmod!(path, 0o700)
    previous = System.get_env("IPSE_RUNNER_PATH")
    System.put_env("IPSE_RUNNER_PATH", path)

    try do
      scoped(fn ->
        {:ok, transport} =
          Ipse.MCP.Transport.start_link(
            owner: self(),
            cleanup_owner: self(),
            cleanup_scope: Ipse.TaskResources.current(),
            cwd: c.root,
            server: %{command: "/bin/sh", args: [], env: %{}, timeout_ms: 1000}
          )

        assert_receive {:mcp_transport_closed, :closed}, 2000
        assert :ok = Ipse.MCP.Transport.close(transport)
      end)
    after
      if previous,
        do: System.put_env("IPSE_RUNNER_PATH", previous),
        else: System.delete_env("IPSE_RUNNER_PATH")
    end
  end

  test "OS arguments cannot silently truncate an approved command or lock path", c do
    assert {:error, _} = Ipse.Runner.run("printf unsafe > nul-effect\0ignored", c.root)
    path = Path.join(c.root, "nul-lock")
    result = Ipse.Runner.lock(path <> <<0>> <> "ignored")
    if match?({:ok, _}, result), do: Ipse.Runner.unlock(elem(result, 1))
    assert {:error, _} = result
    refute File.exists?(Path.join(c.root, "nul-effect"))
    refute File.exists?(path)
  end

  defp scoped(fun) do
    {:ok, scope} = Ipse.TaskResources.start(self())

    task =
      Task.async(fn ->
        Process.flag(:trap_exit, true)
        receive do: (:start -> :ok)
        Ipse.TaskResources.bind(scope)
        fun.()
        Ipse.TaskResources.finish(scope)
      end)

    :ok = Ipse.TaskResources.attach(scope, task.pid)
    send(task.pid, :start)
    assert :ok = Task.await(task, 10_000)
    assert :ok = Ipse.TaskResources.close_task(task.pid)
  end

  test "owner or scope loss before attachment cannot orphan a dispatch-barrier worker" do
    for lost <- [:owner, :scope] do
      parent = self()
      owner = spawn(fn -> receive do: (:stop -> :ok) end)
      {:ok, scope} = Ipse.TaskResources.start(owner)

      {worker, ref} =
        spawn_monitor(fn ->
          send(parent, :at_dispatch_barrier)
          Ipse.TaskResources.await_ready(scope, owner)
          send(parent, :must_not_dispatch)
        end)

      try do
        assert_receive :at_dispatch_barrier, 1000
        Process.exit(if(lost == :owner, do: owner, else: scope), :kill)
        assert_receive {:DOWN, ^ref, :process, ^worker, :normal}, 1000
        refute_receive :must_not_dispatch, 20
      after
        Process.exit(worker, :kill)
        Process.exit(owner, :kill)
        Process.exit(scope, :kill)
      end
    end
  end

  defp assert_dead(pid, attempts \\ 100) do
    assert Regex.match?(~r/\A[0-9]+\z/, pid)
    {_, status} = System.cmd("kill", ["-0", pid], stderr_to_stdout: true)

    zombie? =
      case File.read("/proc/#{pid}/stat") do
        {:ok, stat} -> Regex.match?(~r/\) Z /, stat)
        _ -> false
      end

    if status == 0 and not zombie? do
      assert attempts > 0, "owned fixture process remains live"
      Process.sleep(10)
      assert_dead(pid, attempts - 1)
    end
  end
end
