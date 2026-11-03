defmodule Ipse.Test.ShadowAllowanceTrace do
  @moduledoc false
  alias Ipse.Extension.Consent
  @resources ~w(operations model_calls input_bytes output_bytes download_bytes cost_nanos)

  def start(root, project) do
    tracer =
      spawn_link(fn ->
        loop(%{root: root, project: project, parents: %{}, reserves: %{}, fits: %{}})
      end)

    match = [{:_, [], [{:return_trace}]}]
    1 = :erlang.trace_pattern({Consent, :reserve_experiment, 4}, match, [:local])
    1 = :erlang.trace_pattern({Consent, :fits?, 3}, match, [:local])

    count =
      :erlang.trace(:all, true, [
        :call,
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
    :erlang.trace(:all, false, [:call, :procs, :set_on_spawn, :monotonic_timestamp])
    :erlang.trace_pattern({Consent, :reserve_experiment, 4}, false, [:local])
    :erlang.trace_pattern({Consent, :fits?, 3}, false, [:local])
    send(tracer, :stop)
  end

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

      {:trace_ts, pid, :call, {Consent, :reserve_experiment, [root, project, request, _now]}, at} ->
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

      {:trace_ts, pid, :call, {Consent, :fits?, [ledger, requested, now]}, at} ->
        observation =
          summarize(ledger, requested, now) |> Map.merge(%{started_at: at, finished_at: nil})

        loop(update_in(state.fits[pid], fn xs -> [observation | xs || []] end))

      {:trace_ts, pid, :return_from, {Consent, :fits?, 3}, result, at} ->
        loop(update_in(state.fits[pid], &record_return(&1, result, at)))

      {:collect, from, ref} ->
        send(from, {:allowance_trace, ref, Map.take(state, [:parents, :reserves, :fits])})
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
