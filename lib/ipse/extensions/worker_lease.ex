defmodule Ipse.Extensions.WorkerLease do
  @moduledoc "One bounded cleanup result shared by a worker resource's concurrent closing paths."
  def close(worker, counters, slot \\ 9) do
    case :atomics.compare_exchange(counters, slot, 0, 1) do
      :ok ->
        close_claimed(worker, counters, slot)

      _ ->
        await(counters, slot)
    end
  end

  def stop_async(worker, counters, slot \\ 9) do
    if :atomics.compare_exchange(counters, slot, 0, 1) == :ok do
      Task.start_link(fn -> close_claimed(worker, counters, slot) end)
    end

    :ok
  end

  defp close_claimed(worker, counters, slot) do
    result = Ipse.Extensions.Worker.close(worker)
    :atomics.put(counters, slot, if(result == :ok, do: 2, else: 3))
    result
  rescue
    _ ->
      :atomics.put(counters, slot, 3)
      {:error, :cleanup_unconfirmed}
  end

  def await(counters, slot \\ 9),
    do: await_result(counters, slot, System.monotonic_time(:millisecond) + 3_500)

  defp await_result(counters, slot, deadline) do
    case :atomics.get(counters, slot) do
      2 ->
        :ok

      1 ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(2)
          await_result(counters, slot, deadline)
        else
          {:error, :cleanup_unconfirmed}
        end

      _ ->
        {:error, :cleanup_unconfirmed}
    end
  end
end
