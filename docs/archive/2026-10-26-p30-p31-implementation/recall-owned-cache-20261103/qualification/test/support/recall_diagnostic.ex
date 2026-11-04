defmodule Ipse.Test.RecallDiagnostic do
  @moduledoc false
  alias Ipse.Test.RecallDiagnosticTrace, as: Trace

  def listener(owner, phase, bytes, code) do
    send(
      owner,
      {:recall_listener_phase,
       %{
         "phase" => phase,
         "at_us" => System.monotonic_time(:microsecond),
         "bytes" => bytes,
         "code" => code
       }}
    )
  end

  def request(session, server, root, nil, started_at) do
    state = %{
      root: root,
      started_at: started_at,
      errors: [],
      listener: [],
      overflow: false
    }

    wait(session, server, state, :request, System.monotonic_time(:millisecond) + 120_000)
  end

  def complete(session, server, state) do
    wait(session, server, state, :done, System.monotonic_time(:millisecond) + 30_000)
  end

  defp wait(session, server, state, phase, deadline) do
    receive do
      {:recall_many_request, request} when phase == :request ->
        {:ok, request, state}

      {:recall_listener_phase, metadata} ->
        wait(session, server, add(state, :listener, metadata), phase, deadline)

      {:ipse, ^session, {:error, reason}} ->
        row = %{
          "at_us" => System.monotonic_time(:microsecond),
          "reason" => Trace.safe_error(reason)
        }

        wait(session, server, add(state, :errors, row), phase, deadline)

      {:ipse, ^session, {:done, status}} ->
        finish(state, server, status)
        if phase == :request, do: {:ended, status_code(status)}, else: status
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        finish(state, server, :observation_timeout)
        {:ended, "observation_timeout"}
    end
  end

  defp add(state, key, row) do
    if length(Map.fetch!(state, key)) < 8,
      do: Map.update!(state, key, &(&1 ++ [row])),
      else: %{state | overflow: true}
  end

  defp finish(state, server, status) do
    done_at = System.monotonic_time(:microsecond)

    server_result =
      case Task.yield(server, 5_000) do
        {:ok, result} -> Trace.safe_return(result)
        {:exit, reason} -> %{"class" => "exit", "reason" => Trace.safe_error(reason)}
        nil -> %{"class" => "unobserved"}
      end

    state = drain_listener(state)

    summary = %{"enabled" => false, "reason" => "qualification_trace_disabled"}

    outcome = %{
      "version" => 1,
      "prompt_started_at_us" => state.started_at,
      "done_observed_at_us" => done_at,
      "status" => status_code(status),
      "errors" => state.errors,
      "listener" => state.listener,
      "collector_overflow" => state.overflow,
      "listener_task" => server_result,
      "trace" => summary
    }

    File.write!(Path.join(state.root, "diagnostic-outcome.json"), Jason.encode!(outcome), [
      :exclusive
    ])
  end

  defp drain_listener(state) do
    receive do
      {:recall_listener_phase, metadata} -> drain_listener(add(state, :listener, metadata))
    after
      0 -> state
    end
  end

  defp status_code(status) when status in [:ok, :error, :cancelled, :observation_timeout],
    do: Atom.to_string(status)

  defp status_code({:error, _}), do: "error_tuple"
  defp status_code(_), do: "other"
end
