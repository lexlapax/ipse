defmodule Ipse.Test.StdioProbe do
  @moduledoc false
  @calls [
    {Ipse.Observability.Resources, :close, 2},
    {Ipse.Observability.Channel, :close, 1},
    {Ipse.Extensions.WorkerLease, :close, 3},
    {Ipse.Extensions.WorkerLease, :await, 2},
    {Ipse.TaskResources, :close_task, 1},
    {Ipse.Extensions.Worker, :call, 4},
    {Ipse.Extensions.Worker, :close, 2},
    {Ipse.Runner, :open_owned_stdio, 8},
    {Ipse.Runner, :close_stdio, 2}
  ]

  def start(target, label) do
    {:ok, pid} = :proc_lib.start(__MODULE__, :init, [self(), target, label])
    pid
  end

  def stop(pid) do
    monitor = Process.monitor(pid)
    send(pid, :stop)

    receive do
      {:DOWN, ^monitor, :process, ^pid, _} -> :ok
    after
      1000 -> raise "synthetic stdio probe did not stop"
    end
  end

  def trace_files(directory) do
    paths = [".", "trace-ring-v1", "trace-ring-v1/catalog.json", "trace-ring-v1/.catalog.next"]

    files =
      Map.new(paths, fn path ->
        value =
          case File.lstat(Path.join(directory, path)) do
            {:ok, stat} ->
              %{type: stat.type, mode: Bitwise.band(stat.mode, 0o777), bytes: stat.size}

            {:error, reason} ->
              %{error: reason}
          end

        {path, value}
      end)

    IO.puts(:stderr, Jason.encode!(%{synthetic_trace_files: files}))
  end

  def init(owner, target, label) do
    session = :trace.session_create(:ipse_synthetic_stdio, self(), [])
    owner_ref = Process.monitor(owner)

    for {module, _, _} = point <- @calls do
      Code.ensure_loaded!(module)
      1 = :trace.function(session, point, [{:_, [], [{:return_trace}]}], [:local])
    end

    Enum.each(List.wrap(target), fn root ->
      1 =
        :trace.process(session, root, true, [:call, :arity, :monotonic_timestamp, :set_on_spawn])
    end)

    :proc_lib.init_ack({:ok, self()})

    try do
      loop(owner_ref, System.monotonic_time(:millisecond) + 20_000, %{}, [], label)
    after
      :trace.session_destroy(session)
    end
  end

  defp loop(owner_ref, deadline, pending, samples, label) do
    if System.monotonic_time(:millisecond) >= deadline or map_size(pending) >= 64 do
      report(samples, label, "capture_limit", map_size(pending))
    else
      receive do
        {:trace_ts, pid, :call, point, time} when point in @calls ->
          loop(owner_ref, deadline, Map.put(pending, {pid, point}, time), samples, label)

        {:trace_ts, pid, :return_from, point, result, time} when point in @calls ->
          {started, pending} = Map.pop(pending, {pid, point})
          {module, function, arity} = point

          sample = %{
            module: inspect(module),
            function: Atom.to_string(function),
            arity: arity,
            elapsed_ms:
              if(started, do: System.convert_time_unit(time - started, :native, :millisecond)),
            result: category(result)
          }

          if length(samples) < 64,
            do: loop(owner_ref, deadline, pending, [sample | samples], label),
            else: report(samples, label, "sample_limit", map_size(pending))

        :stop ->
          report(samples, label, "stopped", map_size(pending))

        {:DOWN, ^owner_ref, :process, _, _} ->
          report(samples, label, "owner_down", map_size(pending))

        _ ->
          loop(owner_ref, deadline, pending, samples, label)
      after
        max(0, deadline - System.monotonic_time(:millisecond)) ->
          report(samples, label, "duration_limit", map_size(pending))
      end
    end
  end

  defp category(:ok), do: "ok"
  defp category({:ok, _}), do: "ok"
  defp category({:ok, _, _}), do: "ok"
  defp category({:error, reason}) when is_atom(reason), do: Atom.to_string(reason)
  defp category({:error, _}), do: "error"

  defp category(results) when is_list(results),
    do: if(Enum.all?(results, &(&1 == :ok)), do: "all_ok", else: "cleanup_error")

  defp category(_), do: "other"

  defp report(samples, label, reason, pending) do
    IO.puts(
      :stderr,
      Jason.encode!(%{
        synthetic_stdio_probe: label,
        complete: false,
        reason: reason,
        pending_calls: pending,
        samples: Enum.reverse(samples),
        arguments_captured: false,
        result_payloads_retained: false
      })
    )
  end
end
