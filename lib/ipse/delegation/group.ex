defmodule Ipse.Delegation.Group do
  @moduledoc "Two owned local children with bounded ordered results and sibling cleanup."
  alias Ipse.{Delegation, Session}

  def run(host, %{"tasks" => tasks}) do
    workers =
      Enum.with_index(tasks, fn args, index ->
        task =
          Task.async(fn ->
            receive do
              :start ->
                Delegation.Worker.run(
                  %{
                    host
                    | call_id: "#{host.call_id}/#{index}",
                      config: Map.put(host.config, :parallel_child, true)
                  },
                  args
                )
            end
          end)

        :ok = GenServer.call(host.owner, {:delegation_worker, host.job_ref, task.pid})
        send(task.pid, :start)
        {task, index}
      end)

    try do
      await(workers, %{})
    after
      Enum.each(workers, fn {task, _} ->
        if Process.alive?(task.pid), do: Task.shutdown(task, :brutal_kill)
      end)

      children =
        try do
          GenServer.call(host.owner, {:delegation_children, host.job_ref})
        catch
          :exit, _ -> []
        end

      Enum.each(children, &Session.close/1)
    end
  end

  defp await([], results) do
    text =
      results
      |> Enum.sort()
      |> Enum.map_join("\n\n", fn {index, text} -> "Task #{index + 1}:\n#{text}" end)

    {:ok, text}
  end

  defp await(workers, results) do
    receive do
      {ref, {:ok, text}} when is_reference(ref) and is_binary(text) ->
        case Enum.find(workers, fn {task, _} -> task.ref == ref end) do
          {task, index} ->
            Process.demonitor(ref, [:flush])

            await(
              Enum.reject(workers, fn {other, _} -> other.ref == task.ref end),
              Map.put(results, index, text)
            )

          nil ->
            unknown()
        end

      {_ref, _result} ->
        unknown()

      {:DOWN, _, :process, _, _} ->
        unknown()
    end
  end

  defp unknown,
    do:
      {:unknown,
       "Parallel delegated outcome unknown. Inspect all child journals and workspace effects before any new attempt; no child was replayed."}
end
