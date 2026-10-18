defmodule Ipse.DelegationSessionTest do
  use ExUnit.Case, async: false

  alias Ipse.{Journal, Session}

  defmodule Provider do
    def complete(config, messages, tools, _emit) do
      send(
        config.test_pid,
        {:delegation_provider, Map.get(config, :delegation_origin), config, messages, tools,
         self()}
      )

      if Map.get(config, :delegation_origin) do
        child_complete(config, messages)
      else
        parent_complete(config, messages, tools)
      end
    end

    defp parent_complete(config, messages, tools) do
      if Enum.any?(messages, &(&1["role"] == "tool")) do
        {:ok, %{"role" => "assistant", "content" => "Parent finished"}, %{}}
      else
        tool_calls =
          case config[:delegation_plan] do
            :three -> Enum.map(1..3, &delegate_call("call-#{&1}", &1))
            :delegate_then_write -> [delegate_call("call-delegate", 1), write_call("call-write")]
            _ -> [delegate_call("call-delegate", 1)]
          end

        # A disabled-session test deliberately forges the otherwise unavailable tool.
        _ = tools
        {:ok, %{"role" => "assistant", "content" => "", "tool_calls" => tool_calls}, %{}}
      end
    end

    defp child_complete(config, messages) do
      case config[:delegation_behavior] do
        :write ->
          if Enum.any?(messages, &(&1["role"] == "tool")) do
            {:ok, %{"role" => "assistant", "content" => "Child write reviewed"}, %{}}
          else
            {:ok,
             %{
               "role" => "assistant",
               "content" => "",
               "tool_calls" => [write_call("child-write")]
             }, %{}}
          end

        :wait ->
          send(config.test_pid, {:delegation_child_waiting, config.delegation_origin, self()})
          Process.sleep(:infinity)

        :shell ->
          {:ok,
           %{
             "role" => "assistant",
             "content" => "",
             "tool_calls" => [shell_call(config.delegation_shell_command)]
           }, %{}}

        :recursive ->
          if Enum.any?(messages, &(&1["role"] == "tool")) do
            {:ok, %{"role" => "assistant", "content" => "Recursive call rejected"}, %{}}
          else
            {:ok,
             %{
               "role" => "assistant",
               "content" => "",
               "tool_calls" => [delegate_call("child-recursive", 2)]
             }, %{}}
          end

        :oversized ->
          {:ok, %{"role" => "assistant", "content" => String.duplicate("x", 16_385)}, %{}}

        _ ->
          {:ok, %{"role" => "assistant", "content" => "Child finished with evidence"}, %{}}
      end
    end

    defp delegate_call(id, index) do
      %{
        "id" => id,
        "type" => "function",
        "function" => %{
          "name" => "delegate",
          "arguments" =>
            Jason.encode!(%{
              "task" => "Inspect child task #{index}",
              "context" => "Selected context #{index}"
            })
        }
      }
    end

    defp write_call(id) do
      %{
        "id" => id,
        "type" => "function",
        "function" => %{
          "name" => "write",
          "arguments" => Jason.encode!(%{"path" => "child.txt", "content" => "child effect"})
        }
      }
    end

    defp shell_call(command) do
      %{
        "id" => "child-shell",
        "type" => "function",
        "function" => %{
          "name" => "shell",
          "arguments" => Jason.encode!(%{"command" => command})
        }
      }
    end
  end

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "ipse-delegation-session-#{System.unique_integer([:positive])}"
      )

    home = Path.join(root, "home")
    File.mkdir_p!(Path.join(root, "workspace"))
    File.mkdir_p!(home)
    File.write!(Path.join(home, "AGENTS.md"), "Child inherits this saved global guidance.\n")
    File.write!(Path.join(root, "workspace/AGENTS.md"), "Workspace guidance fixture.\n")

    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, cwd: Path.join(root, "workspace"), home: home, dir: Path.join(root, "state")}
  end

  test "parent approval precedes child start and exact child mutation approval is forwarded",
       ctx do
    parent = start(ctx, %{subagents: true, delegation_behavior: :write, sandbox: :native})
    parent_id = Session.info(parent).id
    :ok = Session.prompt(parent, "Parent private history: DO_NOT_FORWARD_THIS")

    args = %{"task" => "Inspect child task 1", "context" => "Selected context 1"}
    assert_receive {:ipse, ^parent, {:approval, parent_ref, "delegate", ^args}}, 2_000
    refute_receive {:ipse, ^parent, {:subagent, _, :started}}, 50
    refute File.exists?(Path.join(ctx.cwd, "child.txt"))

    parent_events = events(ctx.dir, parent_id)
    refute Enum.any?(parent_events, &(&1["type"] == "delegation_started"))

    File.write!(
      Path.join(ctx.cwd, "AGENTS.md"),
      "Changed after parent snapshot; not implicitly adopted.\n"
    )

    assert :ok = Session.approve(parent, parent_ref, true)
    assert_receive {:ipse, ^parent, {:subagent, child_id, :started}}, 2_000
    parent_events = events(ctx.dir, parent_id)
    assert Enum.any?(parent_events, &(&1["type"] == "tool_started" and &1["name"] == "delegate"))
    {origin, child_config, child_messages, child_tools, _provider_pid} = child_provider_call()
    assert origin["parent_session_id"] == parent_id
    assert origin["call_id"] == "call-delegate"

    assert origin["parent_request_id"] ==
             Enum.find(parent_events, &(&1["type"] == "request_admitted"))["request_id"]

    assert child_config.provider == :demo
    assert child_config.model == "fixture-model"
    assert child_config.sandbox == :native
    assert child_config.subagents == false
    assert child_config.mcp_servers == []
    refute Enum.any?(child_tools, &(get_in(&1, ["function", "name"]) == "delegate"))
    refute Jason.encode!(child_messages) =~ "DO_NOT_FORWARD_THIS"
    assert Jason.encode!(child_messages) =~ "Inspect child task 1"
    assert Jason.encode!(child_messages) =~ "Selected context 1"
    assert Jason.encode!(child_messages) =~ "Workspace guidance fixture."
    refute Jason.encode!(child_messages) =~ "Changed after parent snapshot"

    assert_receive {:ipse, ^parent, {:approval, child_ref, child_approval_name, child_args}},
                   2_000

    assert child_approval_name == "child #{child_id}/write"

    assert child_args == %{"path" => "child.txt", "content" => "child effect"}
    refute File.exists?(Path.join(ctx.cwd, "child.txt"))
    assert {:error, :no_pending_approval} = Session.approve(parent, make_ref(), true)
    assert :ok = Session.approve(parent, child_ref, true)
    assert_receive {:ipse, ^parent, {:done, :ok}}, 2_000
    assert File.read!(Path.join(ctx.cwd, "child.txt")) == "child effect"

    parent_events = events(ctx.dir, parent_id)

    intent =
      event_index(parent_events, &(&1["type"] == "tool_started" and &1["name"] == "delegate"))

    started = event_index(parent_events, &(&1["type"] == "delegation_started"))
    approved = event_index(parent_events, &(&1["type"] == "delegation_approval"))
    assert intent < started
    assert started < approved
    assert Enum.at(parent_events, started)["child_id"] == child_id
    assert_child_receipt(ctx, parent_id, child_id, "result_recorded", "completed", true)

    child_dir = Path.join([ctx.dir, "subagents", parent_id])
    assert [{^child_id, child_events}] = child_journals(child_dir)
    parent_snapshot = Enum.find(parent_events, &(&1["type"] == "workspace_context_snapshot"))
    child_snapshot = Enum.find(child_events, &(&1["type"] == "workspace_context_snapshot"))
    assert child_snapshot["snapshot"] == parent_snapshot["snapshot"]
    refute Enum.any?(child_events, &(&1["type"] == "mcp_catalog"))
  end

  test "headless denial and a forged disabled delegate start no child", ctx do
    denied = start(ctx, %{subagents: true, approval: :deny})
    :ok = Session.prompt(denied, "deny the delegated task")
    assert_receive {:ipse, ^denied, {:done, :ok}}, 2_000
    assert [] == child_journals(Path.join([ctx.dir, "subagents", Session.info(denied).id]))
    refute_receive {:ipse, ^denied, {:subagent, _, :started}}, 50

    disabled = start(ctx, %{subagents: false})
    :ok = Session.prompt(disabled, "provider may forge delegate")
    assert_receive {:ipse, ^disabled, {:done, :ok}}, 2_000
    disabled_id = Session.info(disabled).id
    assert [] == child_journals(Path.join([ctx.dir, "subagents", disabled_id]))
    refute_receive {:ipse, ^disabled, {:approval, _, "delegate", _}}, 50
    refute_receive {:ipse, ^disabled, {:subagent, _, :started}}, 50
  end

  test "human child approval pauses the active work budget and normal close is not cancellation",
       ctx do
    parent =
      start(ctx, %{subagents: true, delegation_behavior: :write, delegation_timeout_ms: 500})

    :ok = Session.prompt(parent, "delegate a reviewed change")
    assert_receive {:ipse, ^parent, {:approval, delegate_ref, "delegate", _}}, 2_000
    :ok = Session.approve(parent, delegate_ref, true)
    assert_receive {:ipse, ^parent, {:subagent, child_id, :started}}, 2_000
    assert_receive {:ipse, ^parent, {:approval, child_ref, _, _}}, 2_000
    Process.sleep(650)
    assert Session.info(parent).phase == :delegated_approval
    :ok = Session.approve(parent, child_ref, true)
    assert_receive {:ipse, ^parent, {:done, :ok}}, 2_000
    assert File.read!(Path.join(ctx.cwd, "child.txt")) == "child effect"
    child_dir = Path.join([ctx.dir, "subagents", Session.info(parent).id])
    assert [{^child_id, child_events}] = child_journals(child_dir)
    refute Enum.any?(child_events, &(&1["type"] == "cancelled"))
  end

  test "completed parent resumes idle without creating or prompting a child", ctx do
    parent = start(ctx, %{subagents: true, approval: :allow})
    :ok = Session.prompt(parent, "delegate and finish")
    assert_receive {:ipse, ^parent, {:done, :ok}}, 3_000
    parent_id = Session.info(parent).id
    child_dir = Path.join([ctx.dir, "subagents", parent_id])
    assert [{child_id, _}] = child_journals(child_dir)
    child_root_config = :sys.get_state(parent).config |> Map.put(:subagents, false)

    assert {:error, :resume_configuration_mismatch} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                config: child_root_config,
                cwd: ctx.cwd,
                state_dir: child_dir,
                id: child_id,
                subscriber: self()}
             )

    flush_provider_events()

    parent_monitor = Process.monitor(parent)
    Process.exit(parent, :kill)
    assert_receive {:DOWN, ^parent_monitor, :process, ^parent, :killed}, 2_000
    resumed = start(ctx, %{subagents: true, approval: :ask}, parent_id)
    assert Session.info(resumed).phase == :idle
    assert [{^child_id, _}] = child_journals(child_dir)
    refute_receive {:delegation_provider, _, _, _, _, _}, 100
    refute_receive {:ipse, ^resumed, {:subagent, _, :started}}, 50
    assert_child_receipt(ctx, parent_id, child_id, "result_recorded", "completed", true)
  end

  test "parent cancellation marks its started delegation unknown and child approval not started",
       ctx do
    parent = start(ctx, %{subagents: true, delegation_behavior: :write})
    :ok = Session.prompt(parent, "delegate and wait for child approval")
    assert_receive {:ipse, ^parent, {:approval, parent_ref, "delegate", _}}, 2_000
    :ok = Session.approve(parent, parent_ref, true)
    assert_receive {:ipse, ^parent, {:subagent, child_id, :started}}, 2_000
    assert_receive {:ipse, ^parent, {:approval, _, approval_name, _}}, 2_000
    assert approval_name == "child #{child_id}/write"

    assert :ok = Session.cancel(parent)
    assert_receive {:ipse, ^parent, {:done, :cancelled}}, 2_000
    refute File.exists?(Path.join(ctx.cwd, "child.txt"))

    parent_events = events(ctx.dir, Session.info(parent).id)

    assert_child_receipt(ctx, Session.info(parent).id, child_id, "unknown", "cancelled", false)

    assert Enum.any?(parent_events, fn event ->
             get_in(event, ["message", "ipse_tool_outcome", "status"]) == "unknown"
           end)

    child_dir = Path.join([ctx.dir, "subagents", Session.info(parent).id])
    assert [{^child_id, child_events}] = child_journals(child_dir)

    assert Enum.any?(child_events, fn event ->
             get_in(event, ["message", "ipse_tool_outcome"]) ==
               %{"status" => "not_started", "approval" => "not_decided"}
           end)

    refute Enum.any?(child_events, &(&1["type"] == "tool_started"))
  end

  test "parent death stops a blocked child and resume restores unknown without replay", ctx do
    parent = start(ctx, %{subagents: true, delegation_behavior: :wait})
    parent_id = Session.info(parent).id
    :ok = Session.prompt(parent, "start blocked child")
    assert_receive {:ipse, ^parent, {:approval, ref, "delegate", _}}, 2_000
    :ok = Session.approve(parent, ref, true)
    assert_receive {:ipse, ^parent, {:subagent, child_id, :started}}, 2_000
    assert_receive {:delegation_child_waiting, origin, provider_pid}, 2_000
    assert origin["parent_session_id"] == parent_id
    child_dir = Path.join([ctx.dir, "subagents", parent_id])
    [child_pid] = Registry.lookup(Ipse.Registry, {child_dir, child_id}) |> Enum.map(&elem(&1, 0))
    child_monitor = Process.monitor(child_pid)
    provider_monitor = Process.monitor(provider_pid)

    Process.exit(parent, :kill)
    assert_receive {:DOWN, ^child_monitor, :process, ^child_pid, _}, 3_000
    assert_receive {:DOWN, ^provider_monitor, :process, ^provider_pid, _}, 3_000

    resumed = start(ctx, %{subagents: true}, parent_id)
    assert Session.info(resumed).phase == :idle
    refute Enum.any?(events(ctx.dir, parent_id), &(&1["type"] == "delegation_finished"))

    assert Enum.any?(:sys.get_state(resumed).messages, fn message ->
             get_in(message, ["ipse_tool_outcome", "status"]) == "unknown"
           end)

    refute_receive {:ipse, ^resumed, {:subagent, _, :started}}, 100
    refute_receive {:delegation_provider, %{parent_session_id: _}, _, _, _, _}, 100
  end

  test "parent lock remains held until a delegated child's stalled scope exits", ctx do
    parent = start(ctx, %{subagents: true, approval: :allow, delegation_behavior: :wait})
    id = Session.info(parent).id
    :ok = Session.prompt(parent, "hold delegated cleanup")
    assert_receive {:delegation_child_waiting, _, worker}, 3_000
    [{scope, _}] = Registry.lookup(Ipse.Registry, {Ipse.TaskResources, worker})
    guard = :sys.get_state(parent).lock_guard
    monitor = Process.monitor(guard)
    :erlang.suspend_process(scope)

    try do
      Process.exit(parent, :kill)

      assert eventually(
               fn -> not Process.alive?(parent) and not Process.alive?(worker) end,
               2_000
             )

      result = Ipse.Runner.lock(Path.join(ctx.dir, id <> ".lock"))
      if match?({:ok, _}, result), do: Ipse.Runner.unlock(elem(result, 1))
      assert match?({:error, _}, result)
      assert Process.alive?(guard)
    after
      :erlang.resume_process(scope)
    end

    assert_receive {:DOWN, ^monitor, :process, ^guard, :normal}, 5_000
    assert {:ok, lock} = Ipse.Runner.lock(Path.join(ctx.dir, id <> ".lock"))
    assert :ok = Ipse.Runner.unlock(lock)
  end

  test "denying a child's proposed write keeps the workspace unchanged", ctx do
    parent = start(ctx, %{subagents: true, delegation_behavior: :write})
    :ok = Session.prompt(parent, "delegate a change")
    assert_receive {:ipse, ^parent, {:approval, delegate_ref, "delegate", _}}, 2_000
    assert :ok = Session.approve(parent, delegate_ref, true)
    assert_receive {:ipse, ^parent, {:subagent, child_id, :started}}, 2_000
    assert_receive {:ipse, ^parent, {:approval, child_ref, approval_name, args}}, 2_000
    assert approval_name == "child #{child_id}/write"
    assert args == %{"path" => "child.txt", "content" => "child effect"}

    assert :ok = Session.approve(parent, child_ref, false)
    assert_receive {:ipse, ^parent, {:done, :ok}}, 2_000
    refute File.exists?(Path.join(ctx.cwd, "child.txt"))

    child_dir = Path.join([ctx.dir, "subagents", Session.info(parent).id])
    assert [{^child_id, child_events}] = child_journals(child_dir)

    assert Enum.any?(child_events, fn event ->
             get_in(event, ["message", "ipse_tool_outcome"]) ==
               %{"status" => "denied", "approval" => "denied"}
           end)
  end

  test "parent cancellation stops the child shell before returning", ctx do
    ready = Path.join(ctx.root, "shell-ready")
    delayed = Path.join(ctx.root, "shell-delayed")
    command = "printf ready > '#{ready}'; sleep 1; printf late > '#{delayed}'"

    parent =
      start(ctx, %{
        subagents: true,
        delegation_behavior: :shell,
        delegation_shell_command: command
      })

    :ok = Session.prompt(parent, "start child shell")
    assert_receive {:ipse, ^parent, {:approval, delegate_ref, "delegate", _}}, 2_000
    assert :ok = Session.approve(parent, delegate_ref, true)
    assert_receive {:ipse, ^parent, {:subagent, child_id, :started}}, 2_000
    child_dir = Path.join([ctx.dir, "subagents", Session.info(parent).id])
    [{child_pid, _}] = Registry.lookup(Ipse.Registry, {child_dir, child_id})
    child_monitor = Process.monitor(child_pid)
    assert_receive {:ipse, ^parent, {:approval, child_ref, approval_name, _}}, 2_000
    assert approval_name == "child #{child_id}/shell"
    assert :ok = Session.approve(parent, child_ref, true)

    assert eventually(fn -> File.read(ready) == {:ok, "ready"} end, 2_000)
    assert :ok = Session.cancel(parent)
    assert_receive {:ipse, ^parent, {:done, :cancelled}}, 2_000
    assert_receive {:DOWN, ^child_monitor, :process, ^child_pid, _}, 1_000

    Process.sleep(1_200)
    refute File.exists?(delayed)

    parent_events = events(ctx.dir, Session.info(parent).id)

    assert Enum.any?(parent_events, fn event ->
             get_in(event, ["message", "ipse_tool_outcome", "status"]) == "unknown"
           end)
  end

  test "a forged recursive delegate in a child is rejected without a grandchild", ctx do
    parent = start(ctx, %{subagents: true, approval: :allow, delegation_behavior: :recursive})
    :ok = Session.prompt(parent, "ask child to delegate again")
    assert_receive {:ipse, ^parent, {:done, :ok}}, 3_000

    parent_id = Session.info(parent).id
    child_dir = Path.join([ctx.dir, "subagents", parent_id])
    assert [{child_id, child_events}] = child_journals(child_dir)
    assert [] == child_journals(Path.join([child_dir, "subagents", child_id]))
    refute Enum.any?(child_events, &(&1["type"] == "delegation_started"))

    assert Enum.any?(child_events, fn event ->
             get_in(event, ["message", "ipse_tool_outcome", "status"]) == "invalid_arguments"
           end)
  end

  test "delegation timeout records unknown, stops the batch, and closes the child", ctx do
    parent =
      start(ctx, %{
        subagents: true,
        approval: :allow,
        delegation_behavior: :wait,
        delegation_timeout_ms: 100,
        delegation_plan: :delegate_then_write
      })

    :ok = Session.prompt(parent, "delegate then write")
    assert_receive {:ipse, ^parent, {:subagent, child_id, :started}}, 2_000
    assert_receive {:ipse, ^parent, {:done, :error}}, 2_000
    assert File.dir?(ctx.cwd)
    refute File.exists?(Path.join(ctx.cwd, "child.txt"))

    parent_events = events(ctx.dir, Session.info(parent).id)

    tool_outcomes =
      parent_events
      |> Enum.filter(&(&1["type"] == "message" and get_in(&1, ["message", "role"]) == "tool"))
      |> Enum.map(&get_in(&1, ["message", "ipse_tool_outcome", "status"]))

    assert tool_outcomes == ["unknown", "not_started"]
    assert_child_receipt(ctx, Session.info(parent).id, child_id, "unknown", "timeout", true)
    child_dir = Path.join([ctx.dir, "subagents", Session.info(parent).id])
    assert [{^child_id, _}] = child_journals(child_dir)
    refute Registry.lookup(Ipse.Registry, {child_dir, child_id}) |> Enum.any?()
  end

  test "the turn starts at most two children and an oversized final stops the parent batch",
       ctx do
    parent = start(ctx, %{subagents: true, approval: :allow, delegation_plan: :three})
    :ok = Session.prompt(parent, "make three delegations")
    assert_receive {:ipse, ^parent, {:done, :ok}}, 5_000
    parent_id = Session.info(parent).id
    events = events(ctx.dir, parent_id)
    assert Enum.count(events, &(&1["type"] == "delegation_started")) == 2
    assert length(child_journals(Path.join([ctx.dir, "subagents", parent_id]))) == 2

    oversized = start(ctx, %{subagents: true, approval: :allow, delegation_behavior: :oversized})
    :ok = Session.prompt(oversized, "child returns too much")
    assert_receive {:ipse, ^oversized, {:done, :error}}, 3_000
    oversized_events = events(ctx.dir, Session.info(oversized).id)

    refute Enum.any?(oversized_events, fn event ->
             event["type"] == "message" and
               get_in(event, ["message", "content"]) == "Parent finished"
           end)

    assert Enum.any?(oversized_events, fn event ->
             get_in(event, ["message", "ipse_tool_outcome", "status"]) == "unknown"
           end)
  end

  test "only the registered worker can report completion and cancellation records it once", ctx do
    parent = start(ctx, %{subagents: true, approval: :allow, delegation_behavior: :wait})
    :ok = Session.prompt(parent, "wait for an authenticated child receipt")
    assert_receive {:ipse, ^parent, {:subagent, child_id, :started}}, 2_000
    assert_receive {:delegation_child_waiting, _, _}, 2_000
    state = :sys.get_state(parent)
    [{child, _}] = Map.to_list(state.delegation_resources)

    assert {:error, :cancelled} =
             GenServer.call(
               parent,
               {:delegation_finished, state.job_ref, child, "result_recorded", "completed", true}
             )

    refute Enum.any?(events(ctx.dir, state.id), &(&1["type"] == "delegation_finished"))
    assert :ok = Session.cancel(parent)
    assert_child_receipt(ctx, state.id, child_id, "unknown", "cancelled", false)
  end

  test "physical child source refusal precedes torn-tail repair", ctx do
    parent = start(ctx, %{subagents: true, approval: :allow})
    :ok = Session.prompt(parent, "complete before corrupting the synthetic source")
    assert_receive {:ipse, ^parent, {:subagent, child_id, :started}}, 2_000
    assert_receive {:ipse, ^parent, {:done, :ok}}, 3_000
    id = Session.info(parent).id
    config = :sys.get_state(parent).config
    assert :ok = Session.close(parent)
    saved = events(ctx.dir, id)
    start = Enum.find(saved, &(&1["type"] == "delegation_started"))
    done = Enum.find(saved, &(&1["type"] == "delegation_finished"))
    assert done["child_id"] == child_id

    {:ok, wrong} =
      Ipse.Lifecycle.Source.build(id, done["started_source"]["byte_offset"] + 1, start)

    forged =
      Enum.map(saved, fn e ->
        if e == done, do: Map.put(done, "started_source", wrong), else: e
      end)

    assert {:ok, _} = Ipse.Lifecycle.Child.restore(forged)
    path = Path.join(ctx.dir, id <> ".jsonl")
    bytes = Enum.map_join(forged, "", &(Jason.encode!(&1) <> "\n")) <> "{\"torn\":"
    File.write!(path, bytes)

    assert {:error, :invalid_child_lifecycle} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                config: config, cwd: ctx.cwd, state_dir: ctx.dir, id: id, subscriber: self()}
             )

    assert File.read!(path) == bytes
  end

  defp assert_child_receipt(ctx, parent, child, status, reason, cleanup) do
    saved = events(ctx.dir, parent)

    assert [receipt] =
             Enum.filter(
               saved,
               &(&1["type"] == "delegation_finished" and &1["child_id"] == child)
             )

    assert receipt["status"] == status
    assert receipt["reason"] == reason
    assert receipt["cleanup_confirmed"] == cleanup
    assert {:ok, _} = Ipse.Lifecycle.Child.restore(saved)
    assert :ok = Ipse.Lifecycle.Child.validate_sources(ctx.dir, parent, saved)
    receipt
  end

  defp start(ctx, overrides, id \\ nil) do
    config =
      Map.merge(
        %{
          provider: :demo,
          model: "fixture-model",
          provider_module: Provider,
          test_pid: self(),
          home: ctx.home,
          approval: :ask,
          sandbox: :off,
          subagents: false,
          delegation_behavior: :simple,
          delegation_timeout_ms: 2_000
        },
        overrides
      )

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: ctx.cwd, state_dir: ctx.dir, id: id, subscriber: self()}
      )

    on_exit(fn ->
      if Process.alive?(pid), do: DynamicSupervisor.terminate_child(Ipse.Sessions, pid)
    end)

    pid
  end

  defp child_provider_call do
    receive do
      {:delegation_provider, origin, config, messages, tools, provider_pid} when is_map(origin) ->
        {origin, config, messages, tools, provider_pid}
    after
      2_000 -> flunk("child provider did not start")
    end
  end

  defp child_journals(dir) do
    Journal.list(dir)
    |> Enum.map(fn %{"id" => id} ->
      {:ok, loaded} = Journal.load(dir, id)
      {id, loaded}
    end)
  end

  defp events(dir, id) do
    {:ok, loaded} = Journal.load(dir, id)
    loaded
  end

  defp event_index(events, predicate) do
    Enum.find_index(events, predicate) || flunk("expected journal event was absent")
  end

  defp eventually(predicate, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    eventually_until(predicate, deadline)
  end

  defp eventually_until(predicate, deadline) do
    cond do
      predicate.() ->
        true

      System.monotonic_time(:millisecond) >= deadline ->
        false

      true ->
        Process.sleep(10)
        eventually_until(predicate, deadline)
    end
  end

  defp flush_provider_events do
    receive do
      {:delegation_provider, _, _, _, _, _} -> flush_provider_events()
    after
      0 -> :ok
    end
  end
end
