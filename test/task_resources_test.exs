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
