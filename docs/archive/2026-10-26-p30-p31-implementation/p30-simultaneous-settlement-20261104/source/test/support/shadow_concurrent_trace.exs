defmodule Ipse.Test.ShadowConcurrentTrace do
  @moduledoc false
  alias Ipse.Extension.Consent
  alias Ipse.Runner.Transaction
  @resources ~w(operations model_calls input_bytes output_bytes download_bytes cost_nanos)

  def start(root, project) do
    {:module, Ipse.InferenceDispatch} = Code.ensure_loaded(Ipse.InferenceDispatch)

    tracer =
      spawn_link(fn ->
        loop(%{
          root: root,
          project: project,
          parents: %{},
          reserves: %{},
          fits: %{},
          acquires: %{},
          dispatch_errors: [],
          dispatch_errors_overflow: false
        })
      end)

    match = [{:"$1", [], [{:message, :"$1"}, {:return_trace}]}]
    1 = :erlang.trace_pattern({Consent, :reserve_experiment, 4}, match, [:local])
    1 = :erlang.trace_pattern({Consent, :fits?, 3}, match, [:local])
    1 = :erlang.trace_pattern({Transaction, :acquire, 2}, match, [:local])

    1 =
      :erlang.trace_pattern({Ipse.InferenceDispatch, :local_error, 1}, dispatch_error_pattern(), [
        :local
      ])

    count =
      :erlang.trace(:all, true, [
        :call,
        :arity,
        :procs,
        :set_on_spawn,
        :monotonic_timestamp,
        {:tracer, tracer}
      ])

    true = count > 0
    tracer
  end

  def finish(tracer) do
    ref = :erlang.trace_delivered(:all)

    receive do
      {:trace_delivered, :all, ^ref} -> :ok
    after
      5_000 -> raise "allowance trace delivery unconfirmed"
    end

    send(tracer, {:collect, self(), ref})

    receive do
      {:allowance_trace, ^ref, summary} -> summary
    after
      5_000 -> raise "allowance trace collection unconfirmed"
    end
  after
    :erlang.trace(:all, false, [:call, :arity, :procs, :set_on_spawn, :monotonic_timestamp])
    :erlang.trace_pattern({Consent, :reserve_experiment, 4}, false, [:local])
    :erlang.trace_pattern({Consent, :fits?, 3}, false, [:local])
    :erlang.trace_pattern({Transaction, :acquire, 2}, false, [:local])
    :erlang.trace_pattern({Ipse.InferenceDispatch, :local_error, 1}, false, [:local])
    send(tracer, :stop)
  end

  # New local_error trace messages contain an MFA arity and a constant label only.
  # The existing three legacy traces retain their prior argument observations.
  @gate_errors ~w(managed_dependency_unavailable inference_dispatch_refused consent_unavailable
                  dispatch_owner_lost dispatch_gate_timeout invalid_service_gate
                  service_gate_unavailable service_gate_timeout inference_route_changed)a
  @service_errors ~w(service_wait_timeout service_cancelled service_filesystem_unsupported)a

  def dispatch_error_pattern do
    Enum.map(@gate_errors, fn error ->
      {[{:service_gate_refused, error}], [], [{:message, {:const, gate_label(error)}}]}
    end) ++
      Enum.map(@service_errors, fn error ->
        {[error], [], [{:message, {:const, error}}]}
      end) ++ [{:_, [], [{:message, {:const, :unknown_dispatch_error}}]}]
  end

  def dispatch_error_labels do
    Enum.map(@gate_errors, &gate_label/1) ++ @service_errors ++ [:unknown_dispatch_error]
  end

  defp gate_label(:managed_dependency_unavailable), do: :gate_managed_dependency_unavailable
  defp gate_label(:inference_dispatch_refused), do: :gate_inference_dispatch_refused
  defp gate_label(:consent_unavailable), do: :gate_consent_unavailable
  defp gate_label(:dispatch_owner_lost), do: :gate_dispatch_owner_lost
  defp gate_label(:dispatch_gate_timeout), do: :gate_dispatch_gate_timeout
  defp gate_label(:invalid_service_gate), do: :gate_invalid_service_gate
  defp gate_label(:service_gate_unavailable), do: :gate_service_gate_unavailable
  defp gate_label(:service_gate_timeout), do: :gate_service_gate_timeout
  defp gate_label(:inference_route_changed), do: :gate_inference_route_changed

  def matching(%{parents: parents, reserves: reserves, fits: fits}, operation) do
    for {caller, [attempt]} <- reserves,
        attempt.id == operation,
        {effect, observations} <- fits,
        observation <- observations,
        correlated?(effect, caller, parents, attempt, observation),
        do: {attempt, observation}
  end

  def reservation_count(%{reserves: reserves}, operation) do
    Enum.count(
      for({_pid, attempts} <- reserves, attempt <- attempts, do: attempt),
      &(&1.id == operation)
    )
  end

  def attempts(%{reserves: reserves}, operation),
    do: for({_pid, rows} <- reserves, row <- rows, row.id == operation, do: row)

  def matching_locks(%{parents: parents, reserves: reserves, acquires: acquires}, operation) do
    for {caller, [attempt]} <- reserves,
        attempt.id == operation,
        {effect, rows} <- acquires,
        row <- rows || [],
        correlated?(effect, caller, parents, attempt, row),
        do: row
  end

  defp correlated?(effect, caller, parents, attempt, observation) do
    with start when is_integer(start) <- attempt.started_at,
         finish when is_integer(finish) <- attempt.finished_at,
         fit_start when is_integer(fit_start) <- observation.started_at,
         fit_finish when is_integer(fit_finish) <- observation.finished_at,
         true <- start < fit_start and fit_start < fit_finish and fit_finish < finish do
      effect == caller or
        case parents[effect] do
          {^caller, spawned_at} when is_integer(spawned_at) ->
            start < spawned_at and spawned_at <= fit_start

          _ ->
            false
        end
    else
      _ -> false
    end
  end

  defp loop(state) do
    receive do
      {:trace_ts, parent, :spawn, child, _, at} ->
        loop(put_in(state.parents[child], {parent, at}))

      {:trace_ts, pid, :call, {Consent, :reserve_experiment, 4}, [root, project, request, _now],
       at} ->
        attempt = %{
          id: request["id"],
          root_matches: root == state.root,
          project_matches: project == state.project,
          policy_sha256: request["policy_sha256"],
          requested: request["reserved"],
          started_at: at,
          finished_at: nil,
          result: :pending
        }

        loop(update_in(state.reserves[pid], fn xs -> [attempt | xs || []] end))

      {:trace_ts, pid, :return_from, {Consent, :reserve_experiment, 4}, result, at} ->
        loop(update_in(state.reserves[pid], &record_return(&1, result, at)))

      {:trace_ts, pid, :call, {Consent, :fits?, 3}, [ledger, requested, now], at} ->
        observation =
          summarize(ledger, requested, now) |> Map.merge(%{started_at: at, finished_at: nil})

        loop(update_in(state.fits[pid], fn xs -> [observation | xs || []] end))

      {:trace_ts, pid, :return_from, {Consent, :fits?, 3}, result, at} ->
        loop(update_in(state.fits[pid], &record_return(&1, result, at)))

      {:trace_ts, pid, :call, {Transaction, :acquire, 2}, [path, _opts], at} ->
        if path == Path.join([state.root, state.project, ".lock"]) do
          row = %{started_at: at, finished_at: nil, result: :pending}
          loop(update_in(state.acquires[pid], fn xs -> [row | xs || []] end))
        else
          loop(state)
        end

      {:trace_ts, pid, :return_from, {Transaction, :acquire, 2}, result, at} ->
        bounded =
          case result do
            {:ok, _} -> :ok
            {:error, code} when is_atom(code) -> {:error, code}
            {:unknown, _} -> :unknown
            _ -> :unrecognized
          end

        loop(update_in(state.acquires[pid], &record_return(&1, bounded, at)))

      {:trace_ts, _pid, :call, {Ipse.InferenceDispatch, :local_error, 1}, label, _at} ->
        if label in dispatch_error_labels() and length(state.dispatch_errors) < 16 do
          loop(%{state | dispatch_errors: state.dispatch_errors ++ [label]})
        else
          loop(%{state | dispatch_errors_overflow: true})
        end

      {:collect, from, ref} ->
        send(
          from,
          {:allowance_trace, ref,
           Map.take(state, [
             :parents,
             :reserves,
             :fits,
             :acquires,
             :dispatch_errors,
             :dispatch_errors_overflow
           ])}
        )

        loop(state)

      :stop ->
        :ok

      _ ->
        loop(state)
    end
  end

  defp record_return([%{result: :pending} = head | tail], result, at),
    do: [%{head | result: result, finished_at: at} | tail]

  defp record_return(other, _, _), do: other

  defp summarize(ledger, requested, now) do
    start = div(now, ledger["policy"]["period_ms"]) * ledger["policy"]["period_ms"]
    operations = Map.values(ledger["operations"])

    used =
      Enum.reduce(operations, Consent.zero(), fn entry, acc ->
        vector =
          cond do
            entry["status"] not in ~w(settled reconciled_overrun) -> entry["reserved"]
            entry["created_at_ms"] >= start -> entry["actual"]
            true -> Consent.zero()
          end

        Map.new(@resources, &{&1, acc[&1] + vector[&1]})
      end)

    %{
      operation_statuses: Map.new(operations, &{&1["id"], &1["status"]}),
      project: ledger["project"],
      policy_sha256: Ipse.JSON.digest([ledger["policy"]]),
      limits: ledger["policy"]["limits"],
      requested: requested,
      used: used,
      compacted_count: map_size(ledger["compacted"]),
      overrun: Enum.any?(operations, &(&1["status"] == "overrun")),
      settled_calls:
        Enum.count(operations, fn entry ->
          entry["status"] == "settled" and entry["created_at_ms"] >= start and
            entry["actual"]["model_calls"] == 1
        end),
      result: :pending
    }
  rescue
    _ -> %{result: :invalid}
  end
end
