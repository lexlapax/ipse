defmodule Ipse.FileEffectTest do
  use ExUnit.Case, async: false

  defmodule Model do
    def complete(_, _, _, _) do
      {:ok,
       %{
         "role" => "assistant",
         "content" => "",
         "tool_calls" => [
           %{
             "id" => "fifo-write",
             "function" => %{
               "name" => "write",
               "arguments" =>
                 Jason.encode!(%{"path" => "fifo", "content" => String.duplicate("x", 262_144)})
             }
           }
         ]
       }, %{}}
    end
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-file-effect-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    probe = Path.join(root, "probe")
    on_exit(fn -> File.rm_rf!(root) end)

    assert {_, 0} =
             System.cmd(
               "rustc",
               ["--edition=2021", "test/support/file_effect_probe.rs", "-o", probe],
               stderr_to_stdout: true
             )

    %{root: root, probe: probe}
  end

  test "a blocked workspace write retains the session lock after abrupt Session death", c do
    dir = Path.join(c.root, Ipse.Usage.id())
    File.mkdir_p!(dir)
    gate = Path.join(dir, "gate")
    drained = Path.join(dir, "drained")

    port =
      Port.open({:spawn_executable, c.probe}, [
        :binary,
        :exit_status,
        {:line, 100},
        args: [Path.join(dir, "fifo"), gate, drained]
      ])

    assert_receive {^port, {:data, {:eol, "ready"}}}, 5_000

    config = %{
      provider: :demo,
      model: "fixture",
      provider_module: Model,
      home: Path.join(dir, "home"),
      approval: :allow
    }

    opts = [config: config, cwd: dir, state_dir: dir, subscriber: self()]
    {:ok, session} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
    state = :sys.get_state(session)
    guard_monitor = Process.monitor(state.lock_guard)

    try do
      :ok = Ipse.Session.prompt(session, "synthetic blocked filesystem write")
      assert_receive {^port, {:data, {:eol, "writing"}}}, 5_000
      monitor = Process.monitor(session)
      Process.exit(session, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^session, :killed}, 2_000

      result =
        DynamicSupervisor.start_child(
          Ipse.Sessions,
          {Ipse.Session, Keyword.put(opts, :id, state.id)}
        )

      if match?({:ok, _}, result), do: Ipse.Session.close(elem(result, 1))
      assert match?({:error, _}, result)
      refute_receive {:DOWN, ^guard_monitor, :process, _, _}, 100
      File.write!(gate, "go")
      assert_receive {^port, {:exit_status, 0}}, 5_000
      assert File.read!(drained) == "drained"
      assert_receive {:DOWN, ^guard_monitor, :process, _, :normal}, 6_000

      assert {:ok, resumed} =
               DynamicSupervisor.start_child(
                 Ipse.Sessions,
                 {Ipse.Session, Keyword.put(opts, :id, state.id)}
               )

      assert {:ok, events} = Ipse.Journal.load(dir, state.id)
      assert {:ok, messages} = Ipse.Session.restore_context(events)
      assert Enum.any?(messages, &(get_in(&1, ["ipse_tool_outcome", "status"]) == "unknown"))
      assert :ok = Ipse.Session.close(resumed)
    after
      File.write!(gate, "go")
      if Process.alive?(session), do: Process.exit(session, :kill)
    end
  end

  test "a budget transaction keeps its real lock through caller death", c do
    parent = self()
    id = Ipse.Usage.id()
    policy = %{"version" => 1, "max_requests" => 2}
    config = %{provider: :openai, model: "fixture", budget: policy}
    assert {:ok, config} = Ipse.Budget.Store.attach(config, c.root, id, true)
    lock = Path.join([c.root, "budgets", id <> ".lock"])

    caller =
      spawn(fn ->
        Ipse.Budget.Store.transaction(config.budget_root, policy, fn state ->
          send(parent, {:effect_started, self()})
          receive do: (:finish -> {:read, state})
        end)
      end)

    assert_receive {:effect_started, effect}
    monitor = Process.monitor(effect)
    Process.exit(caller, :kill)

    try do
      assert {:error, _} = Ipse.Runner.lock(lock)
      refute_receive {:DOWN, ^monitor, :process, _, _}, 100
    after
      send(effect, :finish)
    end

    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    assert {:ok, port} = Ipse.Runner.lock(lock)
    assert :ok = Ipse.Runner.unlock(port)
  end
end
