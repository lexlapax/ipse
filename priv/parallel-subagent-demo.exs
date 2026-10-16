defmodule Ipse.ParallelSubagentDemo do
  @moduledoc false
  alias Ipse.Session

  @args %{
    "tasks" => [
      %{"task" => "Inspect first synthetic task", "context" => "First"},
      %{"task" => "Inspect second synthetic task", "context" => "Second"}
    ]
  }

  defmodule Provider do
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

  def run do
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
        provider_module: Provider,
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
end
