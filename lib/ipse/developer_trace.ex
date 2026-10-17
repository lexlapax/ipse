defmodule Ipse.DeveloperTrace do
  @moduledoc "Bounded one-in-flight dispatcher samples for synthetic conformance Sessions only."
  use GenServer

  @points [{Ipse.Session, :handle_call, 3}, {Ipse.Session, :handle_info, 2}]
  @pattern [{:_, [], [{:disable_trace, :call}]}]
  @reasons ~w(stopped event_limit duration_limit target_down owner_down collector_down watchdog_down trace_error collector_stopped)

  def policy(opts) do
    enabled = Keyword.get(opts, :developer_trace, false)
    duration = Keyword.get(opts, :trace_ms, 1000)
    events = Keyword.get(opts, :trace_events, 32)

    cond do
      enabled === true and is_integer(duration) and duration in 1..5000 and
        is_integer(events) and events in 1..128 ->
        {:ok, %{duration: duration, events: events}}

      enabled === false and not Keyword.has_key?(opts, :trace_ms) and
          not Keyword.has_key?(opts, :trace_events) ->
        {:ok, :off}

      true ->
        {:error, :invalid_developer_trace_policy}
    end
  end

  @doc false
  def start(_target, :off), do: {:ok, nil}
  def start(target, policy), do: GenServer.start(__MODULE__, {target, self(), policy})

  def stop(nil), do: {:ok, nil}

  def stop(pid) do
    GenServer.call(pid, :stop, 1000)
  catch
    :exit, _ -> {:error, :developer_trace_lost}
  end

  @impl true
  def init({target, owner, %{duration: duration, events: limit}})
      when is_pid(target) and is_integer(duration) and duration in 1..5000 and
             is_integer(limit) and limit in 1..128 do
    if Code.ensure_loaded?(:trace) and function_exported?(:trace, :session_create, 3) do
      enroll(target, owner, duration, limit)
    else
      {:stop, :developer_trace_unavailable}
    end
  end

  def init(_), do: {:stop, :invalid_developer_trace_policy}

  defp enroll(target, owner, duration, limit) do
    Code.ensure_loaded!(Ipse.Session)
    session = :trace.session_create(:ipse_conformance, self(), [])

    try do
      Enum.each(@points, fn point ->
        1 = :trace.function(session, point, @pattern, [])
      end)

      started = System.monotonic_time()
      deadline = started + System.convert_time_unit(duration, :millisecond, :native)
      collector = self()
      weak = elem(session, 1)
      closure = :atomics.new(1, signed: false)
      owner_ref = Process.monitor(owner)
      1 = :trace.process(session, target, true, [:call, :arity, :monotonic_timestamp])
      guardian = spawn(fn -> guard(weak, collector, owner, target, deadline, closure) end)
      guardian_ref = Process.monitor(guardian)

      {:ok,
       %{
         session: session,
         target: target,
         owner_ref: owner_ref,
         guardian: guardian,
         guardian_ref: guardian_ref,
         closure: closure,
         started: started,
         deadline: deadline,
         duration: duration,
         limit: limit,
         samples: [],
         count: 0,
         reason: nil,
         cleanup: false
       }}
    rescue
      _ ->
        destroy(session)
        {:stop, :developer_trace_unavailable}
    end
  end

  @impl true
  def handle_call(:stop, _from, state) do
    state = close(state, "stopped")
    {:stop, :normal, {:ok, report(state)}, state}
  end

  @impl true
  def handle_info({:trace_ts, target, :call, point, timestamp}, %{target: target} = state)
      when point in @points and is_integer(timestamp) do
    state =
      if state.session != nil and timestamp >= state.started and timestamp <= state.deadline do
        {_, function, arity} = point

        sample = %{
          "sequence" => state.count + 1,
          "elapsed_us" =>
            System.convert_time_unit(timestamp - state.started, :native, :microsecond),
          "module" => "Ipse.Session",
          "function" => Atom.to_string(function),
          "arity" => arity
        }

        %{state | samples: [sample | state.samples], count: state.count + 1}
      else
        state
      end

    cond do
      state.session == nil -> {:noreply, state}
      state.count >= state.limit -> {:noreply, close(state, "event_limit")}
      System.monotonic_time() >= state.deadline -> {:noreply, close(state, "duration_limit")}
      true -> {:noreply, rearm(state)}
    end
  end

  def handle_info({:trace_closed, reason, cleanup}, state) do
    state = close(state, reason)
    {:noreply, %{state | cleanup: state.cleanup or cleanup}}
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{owner_ref: ref} = state),
    do: {:stop, :normal, close(state, "owner_down")}

  def handle_info({:DOWN, ref, :process, _, _}, %{guardian_ref: ref} = state),
    do: {:noreply, close(state, "watchdog_down")}

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def terminate(_, state), do: close(state, "collector_stopped")

  defp rearm(state) do
    try do
      case :trace.process(state.session, state.target, true, [:call]) do
        1 -> state
        _ -> close(state, "target_down")
      end
    rescue
      _ ->
        reason =
          cond do
            not Process.alive?(state.target) -> "target_down"
            System.monotonic_time() >= state.deadline -> "duration_limit"
            true -> "trace_error"
          end

        close(state, reason)
    end
  end

  defp close(%{session: nil} = state, _), do: state

  defp close(state, reason) do
    reason = claim_reason(state.closure, reason)
    cleanup = destroy(state.session)
    send(state.guardian, :stop)
    %{state | session: nil, reason: reason, cleanup: cleanup}
  end

  defp claim_reason(closure, reason) do
    value = Enum.find_index(@reasons, &(&1 == reason)) + 1

    case :atomics.compare_exchange(closure, 1, 0, value) do
      :ok -> reason
      existing -> Enum.at(@reasons, existing - 1)
    end
  end

  defp destroy(session) do
    :trace.session_destroy(session) in [true, false]
  rescue
    _ -> false
  end

  # Only a weak handle crosses to this watchdog. Its own deadline and monitors
  # keep capture bounded even if the collector is suspended or killed.
  defp guard(weak, collector, owner, target, deadline, closure) do
    refs =
      Map.new(
        [{collector, "collector_down"}, {owner, "owner_down"}, {target, "target_down"}],
        fn {pid, reason} -> {Process.monitor(pid), reason} end
      )

    wait =
      max(System.convert_time_unit(deadline - System.monotonic_time(), :native, :millisecond), 0)

    reason =
      receive do
        :stop -> "stopped"
        {:DOWN, ref, :process, _, _} when is_map_key(refs, ref) -> Map.fetch!(refs, ref)
      after
        wait -> "duration_limit"
      end

    reason = claim_reason(closure, reason)
    cleanup = destroy(weak)
    send(collector, {:trace_closed, reason, cleanup})
  end

  defp report(state) do
    %{
      "version" => 1,
      "scope" => "synthetic_session_dispatch",
      "sampling" => "one_in_flight",
      "complete" => false,
      "reason" => state.reason,
      "cleanup_confirmed" => state.cleanup,
      "limits" => %{"duration_ms" => state.duration, "events" => state.limit},
      "captured" => state.count,
      "samples" => Enum.reverse(state.samples)
    }
  end
end
