Code.require_file("../support/stdio_probe.exs", __DIR__)

defmodule Ipse.MCP.SessionTest do
  use ExUnit.Case, async: false

  defmodule Model do
    def complete(config, messages, tools, _emit) do
      send(config.test_pid, {:model_input, messages, tools})

      if config[:model_gate] do
        send(config.model_gate, {:waiting_model, self()})
        receive do: (:release_model -> :ok)
      end

      if List.last(messages)["role"] == "tool" or List.last(messages)["content"] == "inspect" do
        {:ok, %{"role" => "assistant", "content" => "Fixture finished"}, %{}}
      else
        calls =
          for n <- 1..Map.get(config, :call_count, 1) do
            %{
              "id" => "external-#{n}",
              "type" => "function",
              "function" => %{
                "name" => "mcp__notes__write_note",
                "arguments" =>
                  Jason.encode!(%{"path" => "note.txt", "content" => "approved fixture #{n}"})
              }
            }
          end

        {:ok, %{"role" => "assistant", "content" => "", "tool_calls" => calls}, %{}}
      end
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-mcp-session-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, dir: Path.join(root, "state")}
  end

  test "external effects require exact approval and journal intent before dispatch", ctx do
    pid = session(ctx)
    :ok = Ipse.Session.prompt(pid, "write")
    assert_receive {:model_input, _, tools}, 5_000
    assert Enum.any?(tools, &(get_in(&1, ["function", "name"]) == "mcp__notes__write_note"))
    assert_receive {:ipse, ^pid, {:approval, ref, "mcp__notes__write_note", args}}, 5_000
    assert args == %{"path" => "note.txt", "content" => "approved fixture 1"}
    refute File.exists?(Path.join(ctx.root, "calls.log"))
    :ok = Ipse.Session.approve(pid, ref, true)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    assert File.read!(Path.join(ctx.root, "note.txt")) == "approved fixture 1"
    {:ok, events} = Ipse.Journal.load(ctx.dir, Ipse.Session.info(pid).id)
    intent = Enum.find_index(events, &(&1["type"] == "tool_started"))
    result = Enum.find_index(events, &(get_in(&1, ["message", "role"]) == "tool"))
    assert intent < result
    assert Enum.at(events, intent)["arguments"] == args
    assert Enum.at(events, intent)["mcp"]["server_id"] == "notes"
    assert Enum.at(events, intent)["approval"] == "approved"
  end

  test "pre-spawn MCP refusal leaves a recorded Session usable", ctx do
    pid = session(ctx, capture: true)
    id = Ipse.Session.info(pid).id
    path = Path.join(ctx.root, "nonexecutable-helper")
    File.write!(path, "fixture")
    File.chmod!(path, 0o600)
    previous = System.get_env("IPSE_RUNNER_PATH")
    System.put_env("IPSE_RUNNER_PATH", path)

    try do
      :ok = Ipse.Session.prompt(pid, "write")
      assert_receive {:ipse, ^pid, {:error, error}}, 5000
      assert error =~ "Could not launch"
      assert_receive {:ipse, ^pid, {:done, :error}}, 5000
      assert Ipse.Session.info(pid).phase == :idle
      refute File.exists?(Path.join(ctx.root, "calls.log"))
    after
      if previous,
        do: System.put_env("IPSE_RUNNER_PATH", previous),
        else: System.delete_env("IPSE_RUNNER_PATH")
    end

    :ok = Ipse.Session.prompt(pid, "inspect")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5000
    assert :ok = Ipse.Session.close_confirmed(pid)
    {:ok, events} = Ipse.Journal.load(ctx.dir, id)
    assert {:ok, _} = Ipse.Session.restore_context(events)

    refute Enum.any?(
             events,
             &(&1["type"] == "lifecycle_epoch_closed" and
                 &1["closure"] == "cleanup_failure")
           )
  end

  test "headless policy denies all external tools and resume never replays completed calls",
       ctx do
    denied = session(ctx, approval: :deny)
    :ok = Ipse.Session.prompt(denied, "write")
    assert_receive {:ipse, ^denied, {:done, :ok}}, 5_000
    refute File.exists?(Path.join(ctx.root, "calls.log"))
    DynamicSupervisor.terminate_child(Ipse.Sessions, denied)

    allowed = session(ctx, approval: :allow)
    :ok = Ipse.Session.prompt(allowed, "write")
    assert_receive {:ipse, ^allowed, {:tool, "mcp__notes__write_note", _}}, 5_000
    await_file(Path.join(ctx.root, "note.txt"), 1000)
    assert_receive {:ipse, ^allowed, {:done, :ok}}, 5_000
    id = Ipse.Session.info(allowed).id
    DynamicSupervisor.terminate_child(Ipse.Sessions, allowed)
    resumed = session(ctx, [approval: :allow], id)
    assert Ipse.Session.info(resumed).phase == :idle
    assert File.read!(Path.join(ctx.root, "calls.log")) == "write_note\n"
    :ok = Ipse.Session.prompt(resumed, "inspect")
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 5_000
    assert File.read!(Path.join(ctx.root, "calls.log")) == "write_note\n"
  end

  test "post-dispatch loss stops the batch, preserves unknown, and resume does not retry", ctx do
    pid = session(ctx, scenario: "controlled_disconnect", approval: :allow, call_count: 2)
    id = Ipse.Session.info(pid).id
    monitor = Process.monitor(pid)
    :ok = Ipse.Session.prompt(pid, "write")
    await_dispatch(pid, Path.join(ctx.root, "disconnect-ready"))

    [transport] =
      :sys.get_state(pid).mcp_resources |> Map.keys() |> Enum.filter(&Process.alive?/1)

    :erlang.trace(transport, true, [:send, :receive])
    File.write!(Path.join(ctx.root, "disconnect-now"), "exit normally")
    assert_receive {:ipse, ^pid, {:done, :error}}, 5_000
    assert File.read!(Path.join(ctx.root, "calls.log")) == "write_note\n"
    trace = cleanup_trace(transport, [])
    assert {:helper_exit, 0} in trace, inspect(trace)
    assert {:cleanup, :ok} in trace, inspect(trace)
    assert Ipse.Session.info(pid).phase == :idle
    assert :ok = Ipse.Session.close_confirmed(pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 5_000
    {:ok, events} = Ipse.Journal.load(ctx.dir, id)
    assert {:ok, _} = Ipse.Session.restore_context(events)

    outcomes =
      for e <- events,
          get_in(e, ["message", "role"]) == "tool",
          do: get_in(e, ["message", "ipse_tool_outcome", "status"])

    assert outcomes == ["unknown", "not_started"]

    resumed =
      session(ctx, [scenario: "controlled_disconnect", approval: :allow, call_count: 2], id)

    :ok = Ipse.Session.prompt(resumed, "inspect")
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 5_000
    assert File.read!(Path.join(ctx.root, "calls.log")) == "write_note\n"
  end

  test "tool batches run serially through separate confirmed connections", ctx do
    pid = session(ctx, approval: :allow, call_count: 2)
    :ok = Ipse.Session.prompt(pid, "write")
    # Discovery and both fresh connections each have a 10-second fixture budget.
    assert_receive {:ipse, ^pid, {:done, :ok}}, 35_000
    assert File.read!(Path.join(ctx.root, "calls.log")) == "write_note\nwrite_note\n"
    assert File.read!(Path.join(ctx.root, "note.txt")) == "approved fixture 2"
    assert Enum.all?(:sys.get_state(pid).mcp_resources |> Map.keys(), &(not Process.alive?(&1)))
  end

  test "immediate clean server exit retains a usable Session and confirmed cleanup", ctx do
    pid = session(ctx, scenario: "disconnect_after_dispatch", approval: :allow, capture: true)
    id = Ipse.Session.info(pid).id
    :ok = Ipse.Session.prompt(pid, "write")
    assert_receive {:ipse, ^pid, {:done, :error}}, 5000
    assert Ipse.Session.info(pid).phase == :idle
    assert :ok = Ipse.Session.close_confirmed(pid)
    {:ok, events} = Ipse.Journal.load(ctx.dir, id)
    assert {:ok, _} = Ipse.Session.restore_context(events)
    assert List.last(events)["cleanup_confirmed"] == true
    assert File.read!(Path.join(ctx.root, "calls.log")) == "write_note\n"
  end

  test "cleanup scope death still stops a worker blocked in MCP IO", ctx do
    pid = session(ctx, scenario: "hang", approval: :allow, capture: true)
    id = Ipse.Session.info(pid).id
    :ok = Ipse.Session.prompt(pid, "write")
    await_dispatch(pid, Path.join(ctx.root, "hang-ready"))
    worker = :sys.get_state(pid).task.pid
    [{scope, _}] = Registry.lookup(Ipse.Registry, {Ipse.TaskResources, worker})
    monitor = Process.monitor(worker)
    Process.exit(scope, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1000
    assert_receive {:ipse, ^pid, {:done, :error}}, 5000
    assert {:error, :cleanup_unconfirmed} = Ipse.Session.close_confirmed(pid)
    {:ok, events} = Ipse.Journal.load(ctx.dir, id)
    assert {:ok, _} = Ipse.Session.restore_context(events)
    assert List.last(events)["closure"] == "cleanup_failure"
    refute List.last(events)["cleanup_confirmed"]
  end

  test "abrupt stdio supervisor loss cannot become confirmed Session cleanup", ctx do
    pid = session(ctx, scenario: "hang", approval: :allow, capture: true)
    id = Ipse.Session.info(pid).id
    monitor = Process.monitor(pid)
    :ok = Ipse.Session.prompt(pid, "write")
    await_dispatch(pid, Path.join(ctx.root, "hang-ready"))
    [transport] = :sys.get_state(pid).mcp_resources |> Map.keys()
    port = :sys.get_state(transport).port
    {:os_pid, helper} = Port.info(port, :os_pid)
    assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(helper)])
    assert_receive {:ipse, ^pid, {:done, :error}}, 5000
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 5000
    assert {:error, :cleanup_unconfirmed} = Ipse.Session.close_confirmed(pid)
    assert {:ok, events} = Ipse.Journal.load(ctx.dir, id)
    assert {:ok, _} = Ipse.Session.restore_context(events)
    assert List.last(events)["type"] == "lifecycle_epoch_closed"
    assert List.last(events)["closure"] == "cleanup_failure"
    refute List.last(events)["cleanup_confirmed"]
    refute File.exists?(Path.join(ctx.root, "note.txt"))
  end

  test "resume cannot silently drop the explicitly configured servers", ctx do
    pid = session(ctx)
    id = Ipse.Session.info(pid).id
    config = :sys.get_state(pid).config |> Map.put(:mcp_servers, [])
    DynamicSupervisor.terminate_child(Ipse.Sessions, pid)

    assert {:error, :resume_configuration_mismatch} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Ipse.Session,
                config: config, cwd: ctx.root, state_dir: ctx.dir, id: id, subscriber: self()}
             )

    refute File.exists?(Path.join(ctx.root, "calls.log"))
  end

  test "server readiness starts at tool dispatch after a delayed model decision", ctx do
    gate =
      Task.async(fn ->
        receive do
          {:waiting_model, worker} ->
            Process.sleep(3_200)
            send(worker, :release_model)
        end
      end)

    pid = session(ctx, scenario: "hang", approval: :allow, model_gate: gate.pid)
    :ok = Ipse.Session.prompt(pid, "write")
    assert_receive {:model_input, _, _}, 5_000
    await_dispatch(pid, Path.join(ctx.root, "hang-ready"))
    Task.await(gate, 5_000)
    assert File.read!(Path.join(ctx.root, "calls.log")) == "write_note\n"
    assert :ok = Ipse.Session.cancel(pid)
    assert_receive {:ipse, ^pid, {:done, :cancelled}}, 5_000
    refute File.exists?(Path.join(ctx.root, "note.txt"))
  end

  test "cancellation closes an in-flight server before returning and keeps outcome unknown",
       ctx do
    pid = session(ctx, scenario: "hang", approval: :allow)
    :ok = Ipse.Session.prompt(pid, "write")
    await_dispatch(pid, Path.join(ctx.root, "hang-ready"))
    resources = :sys.get_state(pid).mcp_resources |> Map.keys()
    assert length(resources) == 1
    :ok = Ipse.Session.cancel(pid)
    assert_receive {:ipse, ^pid, {:done, :cancelled}}, 5_000
    assert Enum.all?(resources, &(not Process.alive?(&1)))
    server_pid = File.read!(Path.join(ctx.root, "hang-ready"))

    assert {:ok, %{exit_code: code}} =
             Ipse.Runner.run("kill -0 #{server_pid} 2>/dev/null", ctx.root)

    assert code != 0
    {:ok, events} = Ipse.Journal.load(ctx.dir, Ipse.Session.info(pid).id)

    assert Enum.any?(
             events,
             &(get_in(&1, ["message", "ipse_tool_outcome", "status"]) == "unknown")
           )

    refute File.exists?(Path.join(ctx.root, "note.txt"))
  end

  test "owner death stops the SDK client and native transport, preserving unknown on resume",
       ctx do
    pid = session(ctx, scenario: "hang", approval: :allow)
    :ok = Ipse.Session.prompt(pid, "write")
    await_dispatch(pid, Path.join(ctx.root, "hang-ready"))
    assert_receive {:model_input, _, _}, 5_000
    id = Ipse.Session.info(pid).id
    [transport] = :sys.get_state(pid).mcp_resources |> Map.keys()
    ref = Process.monitor(transport)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^transport, _}, 5_000
    resumed = session(ctx, [scenario: "hang", approval: :allow], id)
    :ok = Ipse.Session.prompt(resumed, "inspect")
    assert_receive {:ipse, ^resumed, {:status, "Thinking"}}, 15_000
    assert_receive {:model_input, messages, _}, 5_000
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 5_000
    assert File.read!(Path.join(ctx.root, "calls.log")) == "write_note\n"
    {:ok, events} = Ipse.Journal.load(ctx.dir, id)
    assert Enum.any?(messages, &(get_in(&1, ["ipse_tool_outcome", "status"]) == "unknown"))
    assert Enum.any?(events, &(&1["type"] == "tool_started"))
    refute File.exists?(Path.join(ctx.root, "note.txt"))
  end

  defp session(ctx, opts \\ [], id \\ nil) do
    scenario = Keyword.get(opts, :scenario, "normal")

    document = %{
      "servers" => [
        %{
          "id" => "notes",
          "command" => System.find_executable("elixir"),
          "args" => [
            "--erl",
            "+S 2:2",
            "-pa",
            Path.dirname(to_string(:code.which(Jason))),
            Path.expand("../support/mcp_server.exs", __DIR__),
            scenario
          ],
          "tools" => ["write_note"],
          "env" => %{"PATH" => Path.join(to_string(:code.root_dir()), "bin") <> ":/usr/bin:/bin"},
          "timeout_ms" => 10_000
        }
      ]
    }

    config_path = Path.join(ctx.root, "mcp.json")
    File.write!(config_path, Jason.encode!(document))
    {:ok, servers} = Ipse.MCP.Config.load(config_path)

    config = %{
      provider: :demo,
      model: "test",
      provider_module: Model,
      test_pid: self(),
      home: Path.join(ctx.root, "home"),
      approval: Keyword.get(opts, :approval, :ask),
      observability:
        Map.put(
          Ipse.Observability.Config.defaults(),
          "mode",
          if(opts[:capture], do: "local", else: "off")
        ),
      call_count: Keyword.get(opts, :call_count, 1),
      model_gate: Keyword.get(opts, :model_gate),
      mcp_servers: servers
    }

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Ipse.Session,
         config: config, cwd: ctx.root, state_dir: ctx.dir, id: id, subscriber: self()}
      )

    on_exit(fn ->
      if Process.alive?(pid), do: DynamicSupervisor.terminate_child(Ipse.Sessions, pid)
    end)

    if System.get_env("IPSE_TEST_STDIO_PROBE") == "1" and
         ctx.test ==
           :"test headless policy denies all external tools and resume never replays completed calls" do
      probe = Ipse.Test.StdioProbe.start(pid, Atom.to_string(ctx.test))
      on_exit(fn -> Ipse.Test.StdioProbe.stop(probe) end)
    end

    pid
  end

  defp await_file(path, retries \\ 300)
  defp await_file(_, 0), do: flunk("MCP fixture did not become ready")

  defp await_file(path, retries) do
    if File.exists?(path),
      do: :ok,
      else:
        (
          Process.sleep(10)
          await_file(path, retries - 1)
        )
  end

  defp await_dispatch(pid, path) do
    assert_receive {:ipse, ^pid, {:tool, "mcp__notes__write_note", _}}, 5_000
    await_file(path)
  end

  defp cleanup_trace(transport, events) do
    receive do
      {:trace, ^transport, :receive, {port, {:exit_status, status}}} when is_port(port) ->
        cleanup_trace(transport, [{:helper_exit, status} | events])

      {:trace, ^transport, :receive, {:EXIT, port, reason}} when is_port(port) ->
        cleanup_trace(transport, [{:helper_exit_signal, reason} | events])

      {:trace, ^transport, :send, {:mcp_cleanup, ^transport, result}, _} ->
        [{:cleanup, result} | events]

      {:trace, ^transport, _, _} ->
        cleanup_trace(transport, events)

      {:trace, ^transport, _, _, _} ->
        cleanup_trace(transport, events)
    after
      5000 -> flunk("missing cleanup receipt: #{inspect(events)}")
    end
  end
end
