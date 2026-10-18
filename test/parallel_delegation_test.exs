defmodule Ipse.ParallelDelegationTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal}

  defmodule Provider do
    def complete(config, messages, tools, _emit) do
      if config[:delegation_origin] do
        index = if String.ends_with?(config.delegation_origin["call_id"], "/0"), do: 0, else: 1

        if Enum.any?(messages, &(&1["role"] == "tool")) do
          {:ok, %{"role" => "assistant", "content" => "child #{index} finished"}, %{}}
        else
          send(config.test_pid, {:child_started, index, self(), tools, config})

          case config.mode do
            mode when mode in [:shell, :shell_after] ->
              if index == 1,
                do:
                  (receive do
                     :release -> :ok
                   end)

              shell? = (mode == :shell and index == 0) or (mode == :shell_after and index == 1)

              {name, args} =
                if shell?,
                  do: {"shell", %{"command" => "printf approved > shell-owner.txt"}},
                  else: {"write", %{"path" => "file-owner.txt", "content" => "approved"}}

              {:ok, %{"role" => "assistant", "content" => "", "tool_calls" => [call(name, args)]},
               %{}}

            mode when mode in [:wait, :fail] ->
              receive do
                :release -> :ok
              end

              content =
                if config.mode == :fail and index == 0,
                  do: String.duplicate("x", 16_385),
                  else: "child #{index} finished"

              {:ok, %{"role" => "assistant", "content" => content}, %{}}

            _ ->
              path =
                case config.mode do
                  :conflict -> "same.txt"
                  :case_conflict -> Enum.at(["Case.txt", "case.txt"], index)
                  :normalization_conflict -> Enum.at(["café.txt", "cafe\u0301.txt"], index)
                  :format_conflict -> Enum.at(["memory.txt", "me\u200Bmory.txt"], index)
                  _ -> "child-#{index}.txt"
                end

              {:ok,
               %{
                 "role" => "assistant",
                 "content" => "",
                 "tool_calls" => [call("write", %{"path" => path, "content" => "child #{index}"})]
               }, %{}}
          end
        end
      else
        if Enum.any?(messages, &(&1["role"] == "tool")) do
          result = Enum.find(messages, &(&1["role"] == "tool"))["content"]
          {:ok, %{"role" => "assistant", "content" => result}, %{}}
        else
          args = %{
            "tasks" => [
              %{"task" => "First", "context" => "One"},
              %{"task" => "Second", "context" => "Two"}
            ]
          }

          {:ok,
           %{
             "role" => "assistant",
             "content" => "",
             "tool_calls" => [call("delegate_parallel", args)]
           }, %{}}
        end
      end
    end

    defp call(name, args),
      do: %{
        "id" => "#{name}-call",
        "type" => "function",
        "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
      }
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-parallel-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, state: Path.join(root, "state")}
  end

  defp start(ctx, mode, extra \\ %{}) do
    config =
      Map.merge(
        %{
          provider: :demo,
          model: "parallel",
          provider_module: Provider,
          home: Path.join(ctx.root, "home"),
          test_pid: self(),
          subagents: true,
          subagent_concurrency: 2,
          approval: :ask,
          mode: mode
        },
        extra
      )

    opts = [config: config, cwd: ctx.root, state_dir: ctx.state, subscriber: self()]
    {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts})
    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    {pid, opts}
  end

  defp approve_group(pid) do
    assert_receive {:ipse, ^pid, {:approval, ref, "delegate_parallel", %{"tasks" => tasks}}}, 3000
    assert length(tasks) == 2
    assert :ok = Session.approve(pid, ref, true)
  end

  test "two children overlap, keep routing/context boundaries and return results in task order",
       ctx do
    {pid, opts} = start(ctx, :wait)
    :ok = Session.prompt(pid, "Private parent transcript must not transfer")
    approve_group(pid)
    assert_receive {:child_started, 0, worker0, tools0, config0}, 3000
    assert_receive {:child_started, 1, worker1, tools1, config1}, 3000

    for {tools, config} <- [{tools0, config0}, {tools1, config1}] do
      refute Enum.any?(
               tools,
               &(get_in(&1, ["function", "name"]) in ["delegate", "delegate_parallel"])
             )

      assert config.mcp_servers == []
      assert config.max_steps <= 6
      assert config.subagent_concurrency == 1
    end

    send(worker1, :release)
    refute_receive {:ipse, ^pid, {:done, :ok}}, 50
    send(worker0, :release)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert Session.info(pid).final =~ ~r/Task 1:.*child 0 finished.*Task 2:.*child 1 finished/s
    id = Session.info(pid).id
    {:ok, events} = Journal.load(ctx.state, id)
    assert Enum.count(events, &(&1["type"] == "delegation_started")) == 2
    completed = Enum.filter(events, &(&1["type"] == "delegation_finished"))
    assert length(completed) == 2
    assert Enum.all?(completed, &(&1["status"] == "result_recorded" and &1["cleanup_confirmed"]))
    assert :ok = Ipse.Lifecycle.Child.validate_sources(ctx.state, id, events)
    parent_request = Enum.find(events, &(&1["type"] == "request_admitted"))["request_id"]

    for config <- [config0, config1] do
      assert config.delegation_origin["parent_session_id"] == id
      assert config.delegation_origin["parent_request_id"] == parent_request
    end

    child_paths = Path.wildcard(Path.join([ctx.state, "subagents", id, "*.jsonl"]))
    assert length(child_paths) == 2

    for path <- child_paths do
      {:ok, child_events} = Journal.load(Path.dirname(path), Path.basename(path, ".jsonl"))

      assert [%{"parent_request_id" => ^parent_request}] =
               Enum.filter(child_events, &(&1["type"] == "request_admitted"))
    end

    assert :sys.get_state(pid).delegations == 2
    :ok = Session.close(pid)

    {:ok, resumed} =
      DynamicSupervisor.start_child(Ipse.Sessions, {Session, Keyword.put(opts, :id, id)})

    assert {:ok, ^events} = Journal.load(ctx.state, id)
    assert Session.info(resumed).phase == :idle
    :ok = Session.close(resumed)
    mismatched = Keyword.put(opts, :config, %{opts[:config] | subagent_concurrency: 1})

    assert {:error, :resume_configuration_mismatch} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, Keyword.put(mismatched, :id, id)}
             )
  end

  test "distinct file mutations have individual approvals and execute serially", ctx do
    {pid, _} =
      start(ctx, :write, %{
        observability: Map.put(Ipse.Observability.Config.defaults(), "mode", "local")
      })

    :ok = Session.prompt(pid, "Run two child writes")
    approve_group(pid)
    assert_receive {:ipse, ^pid, {:approval, first, first_name, first_args}}, 3000
    assert String.starts_with?(first_name, "child ")
    refute_receive {:ipse, ^pid, {:approval, _, _, _}}, 50
    :ok = Session.approve(pid, first, true)
    assert_receive {:ipse, ^pid, {:tool_result, ^first_name, _}}, 3000
    assert_receive {:ipse, ^pid, {:approval, second, second_name, second_args}}, 3000
    assert first_args["path"] != second_args["path"]
    assert first_name != second_name
    assert {:error, :no_pending_approval} = Session.approve(pid, first, true)
    :ok = Session.approve(pid, second, true)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert File.read!(Path.join(ctx.root, "child-0.txt")) == "child 0"
    assert File.read!(Path.join(ctx.root, "child-1.txt")) == "child 1"
    id = Session.info(pid).id
    :ok = Session.close(pid)
    {:ok, events} = Journal.load(ctx.state, id)
    waits = Enum.filter(events, &(&1["type"] == "lifecycle_wait_started"))
    assert Enum.map(waits, & &1["domain"]) == ["tool", "delegated_tool", "delegated_tool"]
    children = for %{"type" => "delegation_started", "child_id" => child} <- events, do: child
    assert Enum.map(tl(waits), & &1["child_id"]) |> Enum.sort() == Enum.sort(children)

    assert Enum.all?(
             Enum.filter(events, &(&1["type"] == "lifecycle_wait_finished")),
             &(&1["outcome"] == "approved")
           )

    assert {:ok, _} = Session.restore_context(events)
  end

  test "nonboolean child decisions deny effects and record the same denial", ctx do
    {pid, _} = start(ctx, :shell)
    :ok = Session.prompt(pid, "Synthetic child decision")
    approve_group(pid)
    assert_receive {:child_started, 0, _, _, _}, 3000
    assert_receive {:child_started, 1, _, _, _}, 3000
    assert_receive {:ipse, ^pid, {:approval, ref, name, _}}, 3000
    assert String.ends_with?(name, "/shell")
    assert :ok = Session.approve(pid, ref, "no")
    refute File.exists?(Path.join(ctx.root, "shell-owner.txt"))
    {:ok, events} = Journal.load(ctx.state, Session.info(pid).id)

    assert Enum.any?(
             events,
             &(&1["type"] == "delegation_approval" and &1["name"] == "shell" and
                 &1["decision"] == "denied")
           )

    assert :ok = Session.cancel(pid)
  end

  test "child loss interrupts its pending approval wait without accepting a stale decision",
       ctx do
    {pid, _} =
      start(ctx, :write, %{
        observability: Map.put(Ipse.Observability.Config.defaults(), "mode", "local")
      })

    id = Session.info(pid).id
    :ok = Session.prompt(pid, "Run child writes")
    approve_group(pid)
    assert_receive {:child_started, 0, _, _, _}, 3_000
    assert_receive {:child_started, 1, _, _, _}, 3_000
    assert_receive {:ipse, ^pid, {:approval, ref, _, _}}, 3_000
    {:delegated, ^ref, _, child, _, _, _} = :sys.get_state(pid).approval
    Process.exit(child, :kill)
    assert_receive {:ipse, ^pid, {:done, :error}}, 5_000
    assert {:error, :no_pending_approval} = Session.approve(pid, ref, true)
    :ok = Session.close(pid)
    {:ok, events} = Journal.load(ctx.state, id)

    wait =
      Enum.find(
        events,
        &(&1["type"] == "lifecycle_wait_started" and &1["domain"] == "delegated_tool")
      )

    assert wait != nil

    finish =
      Enum.find(
        events,
        &(&1["type"] == "lifecycle_wait_finished" and &1["wait_id"] == wait["wait_id"])
      )

    assert finish["outcome"] == "interrupted"
    receipts = Enum.filter(events, &(&1["type"] == "delegation_finished"))
    assert length(receipts) == 2
    assert Enum.all?(receipts, &(&1["status"] == "unknown"))

    assert Enum.any?(
             receipts,
             &(&1["child_id"] == wait["child_id"] and not &1["cleanup_confirmed"])
           )

    refute File.exists?(Path.join(ctx.root, "child-0.txt"))
    refute File.exists?(Path.join(ctx.root, "child-1.txt"))
    assert {:ok, _} = Session.restore_context(events)
  end

  test "an exited queued child cannot acquire a stale approval while its report is pending",
       ctx do
    {pid, _} = start(ctx, :write)
    parent_id = Session.info(pid).id
    :ok = Session.prompt(pid, "Queue two child approvals")
    approve_group(pid)
    assert_receive {:child_started, 0, _, _, _}, 3_000
    assert_receive {:child_started, 1, _, _, _}, 3_000
    assert_receive {:ipse, ^pid, {:approval, first, _, _}}, 3_000
    eventually(fn -> length(:sys.get_state(pid).delegation_queue) == 1 end)
    [{worker, child, _, _, _}] = :sys.get_state(pid).delegation_queue
    id = :sys.get_state(pid).delegation_resources[child].id
    true = :erlang.suspend_process(worker)
    Process.exit(child, :kill)
    eventually(fn -> :sys.get_state(pid).delegation_resources[child].down end)
    :ok = Session.approve(pid, first, false)
    refute_receive {:ipse, ^pid, {:approval, _, _, _}}, 100
    Process.exit(worker, :kill)
    assert_receive {:ipse, ^pid, {:done, :error}}, 3_000
    :ok = Session.close(pid)
    {:ok, events} = Journal.load(ctx.state, parent_id)

    receipts =
      Enum.filter(events, &(&1["type"] == "delegation_finished" and &1["child_id"] == id))

    assert [%{"status" => "unknown", "cleanup_confirmed" => false}] = receipts
  end

  defp eventually(fun, attempts \\ 100)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, attempts) do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      eventually(fun, attempts - 1)
    end
  end

  test "cross-child target conflicts are denied rather than overwrite a sibling result", ctx do
    {pid, _} = start(ctx, :conflict)
    :ok = Session.prompt(pid, "Conflicting child writes")
    approve_group(pid)
    assert_receive {:ipse, ^pid, {:approval, ref, _name, args}}, 3000
    :ok = Session.approve(pid, ref, true)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
    assert File.read!(Path.join(ctx.root, "same.txt")) == args["content"]
    {:ok, events} = Journal.load(ctx.state, Session.info(pid).id)
    assert Enum.any?(events, &(&1["decision"] == "conflict_denied"))
  end

  test "case, normalization and ignorable variants cannot claim a sibling's mutation target",
       ctx do
    for mode <- [:case_conflict, :normalization_conflict, :format_conflict] do
      {pid, _} = start(ctx, mode)
      :ok = Session.prompt(pid, "Synthetic aliased child targets")
      approve_group(pid)
      assert_receive {:ipse, ^pid, {:approval, ref, _name, args}}, 3000
      :ok = Session.approve(pid, ref, true)
      assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
      assert File.read!(Path.join(ctx.root, args["path"])) == args["content"]
      {:ok, events} = Journal.load(ctx.state, Session.info(pid).id)
      assert Enum.any?(events, &(&1["decision"] == "conflict_denied"))
      assert :ok = Session.close(pid)
    end
  end

  test "cancellation stops both active children and resume never starts them again", ctx do
    {pid, opts} = start(ctx, :wait)
    :ok = Session.prompt(pid, "Concurrent waiting children")
    approve_group(pid)
    assert_receive {:child_started, 0, worker0, _, _}, 3000
    assert_receive {:child_started, 1, worker1, _, _}, 3000
    refs = Enum.map([worker0, worker1], &Process.monitor/1)
    :ok = Session.cancel(pid)
    for ref <- refs, do: assert_receive({:DOWN, ^ref, :process, _, _}, 3000)
    id = Session.info(pid).id
    {:ok, events} = Journal.load(ctx.state, id)

    assert Enum.any?(
             events,
             &(get_in(&1, ["message", "ipse_tool_outcome", "status"]) == "unknown")
           )

    :ok = Session.close(pid)

    {:ok, resumed} =
      DynamicSupervisor.start_child(Ipse.Sessions, {Session, Keyword.put(opts, :id, id)})

    assert {:ok, ^events} = Journal.load(ctx.state, id)
    refute_receive {:child_started, _, _, _, _}, 50
    :ok = Session.close(resumed)
  end

  test "a failed child stops its waiting sibling and records the group unknown", ctx do
    {pid, _} = start(ctx, :fail)
    :ok = Session.prompt(pid, "Partial failure")
    approve_group(pid)
    assert_receive {:child_started, 0, worker0, _, _}, 3000
    assert_receive {:child_started, 1, worker1, _, _}, 3000
    monitor = Process.monitor(worker1)
    send(worker0, :release)
    assert_receive {:ipse, ^pid, {:done, :error}}, 3000
    assert_receive {:DOWN, ^monitor, :process, ^worker1, _}, 3000
  end

  test "parent death stops both owned child provider tasks", ctx do
    {pid, _} = start(ctx, :wait)
    :ok = Session.prompt(pid, "Owner death")
    approve_group(pid)
    assert_receive {:child_started, 0, worker0, _, _}, 3000
    assert_receive {:child_started, 1, worker1, _, _}, 3000
    state = :sys.get_state(pid)
    children = Map.keys(state.delegation_resources)
    assert length(children) == 2
    monitors = Enum.map([worker0, worker1, state.task.pid | children], &Process.monitor/1)
    Process.exit(pid, :kill)
    for monitor <- monitors, do: assert_receive({:DOWN, ^monitor, :process, _, _}, 3000)
  end

  test "parallel file mutations reject hardlink aliases", ctx do
    original = Path.join(ctx.root, "original.txt")
    alias_path = Path.join(ctx.root, "alias.txt")
    File.write!(original, "manual content")
    File.ln!(original, alias_path)

    assert {:error, _} =
             Ipse.Tools.execute("write", %{"path" => "alias.txt", "content" => "overwritten"}, %{
               cwd: ctx.root,
               parallel_child: true
             })

    assert File.read!(original) == "manual content"
  end

  test "a shell mutation claims the workspace exclusively in either ordering", ctx do
    for mode <- [:shell, :shell_after] do
      {pid, _} = start(ctx, mode)
      :ok = Session.prompt(pid, "Shell/file conflict")
      approve_group(pid)
      assert_receive {:child_started, 1, waiting, _, _}, 3000
      assert_receive {:ipse, ^pid, {:approval, ref, name, _args}}, 3000
      :ok = Session.approve(pid, ref, true)
      assert_receive {:ipse, ^pid, {:tool_result, ^name, _}}, 3000
      send(waiting, :release)
      assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
      {:ok, events} = Journal.load(ctx.state, Session.info(pid).id)
      assert Enum.any?(events, &(&1["decision"] == "conflict_denied"))
    end
  end

  test "parallel tool is disabled by default and headless requests are denied", ctx do
    for extra <- [%{subagent_concurrency: 1}, %{approval: :deny}] do
      {pid, _} = start(ctx, :wait, extra)
      :ok = Session.prompt(pid, "Forged parallel request")
      assert_receive {:ipse, ^pid, {:done, :ok}}, 3000
      refute_receive {:child_started, _, _, _, _}, 50
    end
  end
end
