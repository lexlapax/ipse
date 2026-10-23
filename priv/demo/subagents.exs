defmodule Ipse.DelegationDemo do
  @moduledoc false

  alias Ipse.Session

  @delegate_args %{
    "task" => "Create delegated-note.txt with the requested greeting.",
    "context" => "Write exactly the provided greeting as UTF-8 text."
  }
  @write_args %{
    "path" => "delegated-note.txt",
    "content" => "Hello from a child session!\n"
  }

  defmodule ScriptedProvider do
    @moduledoc false

    def complete(config, messages, _tools, _emit) do
      cond do
        is_map(config[:delegation_origin]) and Enum.any?(messages, &(&1["role"] == "tool")) ->
          {:ok, %{"role" => "assistant", "content" => "Child completed the requested write."},
           %{}}

        is_map(config[:delegation_origin]) ->
          tool_call("child-write", "write", %{
            "path" => "delegated-note.txt",
            "content" => "Hello from a child session!\n"
          })

        Enum.any?(messages, &(&1["role"] == "tool")) ->
          {:ok, %{"role" => "assistant", "content" => "Parent received the child result."}, %{}}

        true ->
          tool_call("parent-delegate", "delegate", %{
            "task" => "Create delegated-note.txt with the requested greeting.",
            "context" => "Write exactly the provided greeting as UTF-8 text."
          })
      end
    end

    defp tool_call(id, name, args) do
      {:ok,
       %{
         "role" => "assistant",
         "content" => "",
         "tool_calls" => [
           %{
             "id" => id,
             "type" => "function",
             "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
           }
         ]
       }, %{}}
    end
  end

  def run_serial do
    root = Path.join(System.tmp_dir!(), "ipse-subagent-demo-#{random_id()}")
    cwd = Path.join(root, "workspace")
    home = Path.join(root, "home")
    state_dir = Path.join(root, "state")
    File.mkdir_p!(cwd)
    File.mkdir_p!(home)

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: %{
           provider: :demo,
           model: "scripted-demo",
           provider_module: ScriptedProvider,
           home: home,
           approval: :ask,
           subagents: true,
           max_steps: 30,
           compact: true,
           mcp_servers: []
         },
         cwd: cwd,
         state_dir: state_dir,
         subscriber: self()}
      )

    try do
      :ok = Session.prompt(pid, "Delegate the requested note creation, then report completion.")

      approved =
        await_parent(pid, nil, MapSet.new(), System.monotonic_time(:millisecond) + 30_000)

      verify!(pid, approved, cwd, state_dir)

      IO.puts(
        "Subagent demo passed: the child wrote the approved note and the parent retained its result."
      )

      :ok
    after
      _ = Session.close(pid)
      File.rm_rf!(root)
    end
  end

  defp await_parent(pid, child_id, approved, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:ipse, ^pid, {:subagent, id, :started}} ->
        if is_nil(child_id),
          do: await_parent(pid, id, approved, deadline),
          else: raise("Unexpected second child session.")

      {:ipse, ^pid, {:approval, ref, "delegate", args}} ->
        if args != @delegate_args or MapSet.member?(approved, :delegate) do
          raise(
            "Unexpected or duplicate delegation approval: #{inspect(args, pretty: true, limit: :infinity)}"
          )
        end

        print_approval("delegate", args)
        :ok = Session.approve(pid, ref, true)
        await_parent(pid, child_id, MapSet.put(approved, :delegate), deadline)

      {:ipse, ^pid, {:approval, ref, "child " <> id_and_tool, args}} ->
        expected_name = "child #{child_id}/write"

        if is_nil(child_id) or id_and_tool != "#{child_id}/write" or args != @write_args or
             MapSet.member?(approved, :child_write) do
          raise(
            "Unexpected or duplicate child approval: #{inspect(args, pretty: true, limit: :infinity)}"
          )
        end

        print_approval(expected_name, args)
        :ok = Session.approve(pid, ref, true)
        await_parent(pid, child_id, MapSet.put(approved, :child_write), deadline)

      {:ipse, ^pid, {:done, :ok}} ->
        if approved == MapSet.new([:delegate, :child_write]),
          do: approved,
          else: raise("Demo completed without both exact approvals.")

      {:ipse, ^pid, {:done, status}} ->
        raise("Demo session ended with #{inspect(status)}.")

      {:ipse, ^pid, {:error, error}} ->
        raise("Demo session error: #{inspect(error)}")

      {:ipse, ^pid, _event} ->
        await_parent(pid, child_id, approved, deadline)
    after
      remaining -> raise("Timed out waiting for demo session completion.")
    end
  end

  defp verify!(pid, approved, cwd, state_dir) do
    true = approved == MapSet.new([:delegate, :child_write])
    true = File.read!(Path.join(cwd, "delegated-note.txt")) == "Hello from a child session!\n"

    parent_id = Session.info(pid).id
    {:ok, parent_events} = Ipse.Journal.load(state_dir, parent_id)
    [started] = Enum.filter(parent_events, &(&1["type"] == "delegation_started"))
    child_id = started["child_id"]
    true = is_binary(child_id)
    [finished] = Enum.filter(parent_events, &(&1["type"] == "delegation_finished"))
    ^child_id = finished["child_id"]
    "result_recorded" = finished["status"]
    true = finished["cleanup_confirmed"]
    :ok = Ipse.Tools.Delegation.validate_child_sources(state_dir, parent_id, parent_events)

    {:ok, %{records: [%{record: ^started}]}} =
      Ipse.Journal.source_page(state_dir, parent_id, finished["started_source"]["byte_offset"], 1)

    [parent_intent] =
      Enum.filter(parent_events, &(&1["type"] == "tool_started" and &1["name"] == "delegate"))

    true = parent_intent["approval"] == "approved"
    true = parent_intent["arguments"] == @delegate_args

    child_dir = Path.join([state_dir, "subagents", parent_id])
    {:ok, child_events} = Ipse.Journal.load(child_dir, child_id)

    [child_intent] =
      Enum.filter(child_events, &(&1["type"] == "tool_started" and &1["name"] == "write"))

    true = child_intent["approval"] == "approved"

    [child_approval] =
      Enum.filter(parent_events, fn event ->
        event["type"] == "delegation_approval" and event["child_id"] == child_id and
          event["name"] == "write"
      end)

    true = child_approval["decision"] == "approved"
    true = child_approval["arguments"] == @write_args

    true =
      Enum.any?(parent_events, fn event ->
        get_in(event, ["message", "role"]) == "tool" and
          get_in(event, ["message", "content"]) =~ "Child completed the requested write."
      end)
  end

  defp print_approval(name, args) do
    IO.puts("Approval requested for #{name}; full proposed arguments:")
    IO.puts(inspect(args, pretty: true, limit: :infinity))
  end

  defp random_id do
    :crypto.strong_rand_bytes(10) |> Base.url_encode64(padding: false)
  end

  @moduledoc false
  alias Ipse.Session

  @args %{
    "tasks" => [
      %{"task" => "Inspect first synthetic task", "context" => "First"},
      %{"task" => "Inspect second synthetic task", "context" => "Second"}
    ]
  }

  defmodule ParallelProvider do
    def complete(config, messages, _tools, _emit) do
      cond do
        config[:delegation_origin] ->
          {:ok, %{"role" => "assistant", "content" => "Synthetic child completed"}, %{}}

        Enum.any?(messages, &(&1["role"] == "tool")) ->
          {:ok, %{"role" => "assistant", "content" => "Parallel parent completed"}, %{}}

        true ->
          args = %{
            "tasks" => [
              %{"task" => "Inspect first synthetic task", "context" => "First"},
              %{"task" => "Inspect second synthetic task", "context" => "Second"}
            ]
          }

          {:ok,
           %{
             "role" => "assistant",
             "content" => "",
             "tool_calls" => [
               %{
                 "id" => "parallel-demo",
                 "type" => "function",
                 "function" => %{
                   "name" => "delegate_parallel",
                   "arguments" => Jason.encode!(args)
                 }
               }
             ]
           }, %{}}
      end
    end
  end

  def run_parallel do
    root =
      Path.join(
        System.tmp_dir!(),
        "ipse-parallel-demo-#{Base.encode16(:crypto.strong_rand_bytes(6), case: :lower)}"
      )

    File.mkdir_p!(root)

    opts = [
      cwd: root,
      state_dir: Path.join(root, "state"),
      subscriber: self(),
      config: %{
        provider: :demo,
        model: "parallel-demo",
        provider_module: ParallelProvider,
        home: Path.join(root, "home"),
        approval: :ask,
        subagents: true,
        subagent_concurrency: 2
      }
    ]

    {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts})

    try do
      :ok = Session.prompt(pid, "Run the exact two synthetic parallel tasks.")
      await(pid, false, MapSet.new(), System.monotonic_time(:millisecond) + 30_000)
      id = Session.info(pid).id
      {:ok, events} = Ipse.Journal.load(opts[:state_dir], id)
      2 = Enum.count(events, &(&1["type"] == "delegation_started"))
      [intent] = Enum.filter(events, &(&1["type"] == "tool_started"))
      "approved" = intent["approval"]
      "delegate_parallel" = intent["name"]
      true = intent["arguments"] == @args
      :ok = Session.close(pid)

      {:ok, resumed} =
        DynamicSupervisor.start_child(Ipse.Sessions, {Session, Keyword.put(opts, :id, id)})

      try do
        :idle = Session.info(resumed).phase
        {:ok, ^events} = Ipse.Journal.load(opts[:state_dir], id)
      after
        Session.close(resumed)
      end

      IO.puts("Parallel local delegation and idle resume passed without a model service.")
      :ok
    after
      if Process.alive?(pid), do: Session.close(pid)
      File.rm_rf!(root)
    end
  end

  defp await(pid, approved, ids, deadline) do
    receive do
      {:ipse, ^pid, {:approval, ref, "delegate_parallel", @args}} when not approved ->
        :ok = Session.approve(pid, ref, true)
        await(pid, true, ids, deadline)

      {:ipse, ^pid, {:subagent, id, :started}} ->
        await(pid, approved, MapSet.put(ids, id), deadline)

      {:ipse, ^pid, {:done, :ok}} ->
        true = approved and MapSet.size(ids) == 2

      {:ipse, ^pid, {:done, _}} ->
        raise "Parallel demo failed"

      {:ipse, ^pid, {:approval, _, _, _}} ->
        raise "Unexpected parallel demo approval"

      {:ipse, ^pid, _} ->
        await(pid, approved, ids, deadline)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> raise "Parallel demo timed out"
    end
  end

  def run do
    with :ok <- run_serial(), :ok <- run_parallel(), do: :ok
  end
end
