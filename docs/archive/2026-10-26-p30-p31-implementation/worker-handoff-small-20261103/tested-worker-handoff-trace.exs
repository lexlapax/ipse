defmodule Ipse.Test.WorkerHandoffTrace do
  @moduledoc false

  @targets [
    {Ipse.Session.WorkerInput, :call, 6},
    {Ipse.Session.ManagedUse, :with_worker_dependencies, 3},
    {Ipse.Session.StoredSources, :with_shareable_union, 4},
    {Ipse.Runner.SessionSource, :with_worker_input, 8},
    {Ipse.Extension.Worker, :bind_stdin, 3},
    {Ipse.Extension.Worker, :export_stdin, 3},
    {Ipse.Extension.Worker, :settle_stdin, 2}
  ]
  @limit 2048

  def targets, do: @targets

  def start(owner) when is_pid(owner) do
    spawn_link(fn -> collect(owner, [], 0) end)
  end

  def enable(tracer) when is_pid(tracer) do
    for {module, function, arity} = target <- @targets do
      {:module, ^module} = Code.ensure_loaded(module)
      count = :erlang.trace_pattern(target, [{:_, [], [{:return_trace}]}], [:local])
      true = is_integer(count) and count > 0
      {function, arity}
    end

    :erlang.trace(:all, true, [:call, :arity, :monotonic_timestamp, {:tracer, tracer}])
    :ok
  end

  def disable do
    :erlang.trace(:all, false, [:call])
    for target <- @targets, do: :erlang.trace_pattern(target, false, [:local])
    :ok
  end

  def finish(tracer) do
    barrier = :erlang.trace_delivered(:all)

    receive do
      {:trace_delivered, :all, ^barrier} -> :ok
    after
      5_000 -> raise "trace delivery was not confirmed"
    end

    reference = make_ref()
    send(tracer, {:finish, self(), reference})

    receive do
      {:worker_handoff_trace, ^reference, value} -> value
    after
      5_000 -> raise "trace collector did not finish"
    end
  end

  def spans(%{"events" => events, "dropped" => dropped}) when is_list(events) do
    {pending, spans} =
      Enum.reduce(events, {%{}, []}, fn event, {pending, spans} ->
        key = {event["pid"], event["module"], event["function"], event["arity"]}

        case {event["kind"], Map.get(pending, key, [])} do
          {"call", starts} ->
            {Map.put(pending, key, [event["monotonic_native"] | starts]), spans}

          {"return", [started | rest]} ->
            elapsed = event["monotonic_native"] - started

            span =
              event
              |> Map.put("started_native", started)
              |> Map.put("elapsed_us", System.convert_time_unit(elapsed, :native, :microsecond))

            {Map.put(pending, key, rest), [span | spans]}

          _ ->
            {pending, spans}
        end
      end)

    %{
      "spans" => Enum.reverse(spans),
      "unmatched_calls" => Enum.sum(Enum.map(pending, fn {_, starts} -> length(starts) end)),
      "dropped" => dropped
    }
  end

  defp collect(owner, events, dropped) do
    receive do
      {:trace_ts, pid, :call, {module, function, arity}, timestamp}
      when is_pid(pid) and is_integer(arity) and is_integer(timestamp) ->
        {events, dropped} =
          append(events, dropped, event("call", pid, module, function, arity, timestamp, nil))

        collect(owner, events, dropped)

      {:trace_ts, pid, :return_from, {module, function, arity}, result, timestamp}
      when is_pid(pid) and is_integer(arity) and is_integer(timestamp) ->
        {events, dropped} =
          append(
            events,
            dropped,
            event("return", pid, module, function, arity, timestamp, outcome(result))
          )

        collect(owner, events, dropped)

      {:finish, ^owner, reference} ->
        send(
          owner,
          {:worker_handoff_trace, reference,
           %{"events" => Enum.reverse(events), "dropped" => dropped}}
        )

      _ ->
        collect(owner, events, dropped)
    end
  end

  defp append(events, dropped, event) do
    if length(events) < @limit, do: {[event | events], dropped}, else: {events, dropped + 1}
  end

  defp event(kind, pid, module, function, arity, timestamp, outcome) do
    %{
      "kind" => kind,
      "pid" => pid |> :erlang.pid_to_list() |> List.to_string(),
      "module" => Atom.to_string(module),
      "function" => Atom.to_string(function),
      "arity" => arity,
      "monotonic_native" => timestamp,
      "outcome" => outcome
    }
  end

  defp outcome(:ok), do: "ok"
  defp outcome({:ok, _}), do: "ok"
  defp outcome({:error, _}), do: "error"
  defp outcome({:unknown, _}), do: "unknown"
  defp outcome(_), do: "other"
end
