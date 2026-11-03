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
    count = :erlang.trace(:all, true, [:call, :procs, :set_on_spawn, {:tracer, tracer}])
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
    :erlang.trace(:all, false, [:call, :procs, :set_on_spawn])
    :erlang.trace_pattern({Consent, :reserve_experiment, 4}, false, [:local])
    :erlang.trace_pattern({Consent, :fits?, 3}, false, [:local])
    send(tracer, :stop)
  end

  def matching(%{parents: parents, reserves: reserves, fits: fits}, operation) do
    for {caller, attempts} <- reserves,
        attempt <- attempts,
        attempt.id == operation,
        {effect, observations} <- fits,
        descendant?(effect, caller, parents, 16),
        observation <- observations,
        do: {attempt, observation}
  end

  defp descendant?(pid, pid, _parents, _remaining), do: true
  defp descendant?(_pid, _caller, _parents, 0), do: false

  defp descendant?(pid, caller, parents, remaining) do
    case parents[pid] do
      nil -> false
      parent -> descendant?(parent, caller, parents, remaining - 1)
    end
  end

  defp loop(state) do
    receive do
      {:trace, parent, :spawn, child, _} ->
        loop(put_in(state.parents[child], parent))

      {:trace, pid, :call, {Consent, :reserve_experiment, [root, project, request, _now]}} ->
        attempt = %{
          id: request["id"],
          root_matches: root == state.root,
          project_matches: project == state.project,
          policy_sha256: request["policy_sha256"],
          requested: request["reserved"],
          result: :pending
        }

        loop(update_in(state.reserves[pid], fn xs -> [attempt | xs || []] end))

      {:trace, pid, :return_from, {Consent, :reserve_experiment, 4}, result} ->
        loop(update_in(state.reserves[pid], &record_return(&1, result)))

      {:trace, pid, :call, {Consent, :fits?, [ledger, requested, now]}} ->
        observation = summarize(ledger, requested, now)
        loop(update_in(state.fits[pid], fn xs -> [observation | xs || []] end))

      {:trace, pid, :return_from, {Consent, :fits?, 3}, result} ->
        loop(update_in(state.fits[pid], &record_return(&1, result)))

      {:collect, from, ref} ->
        send(from, {:allowance_trace, ref, Map.take(state, [:parents, :reserves, :fits])})
        loop(state)

      :stop ->
        :ok

      _ ->
        loop(state)
    end
  end

  defp record_return([%{result: :pending} = head | tail], result),
    do: [%{head | result: result} | tail]

  defp record_return(other, _), do: other

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
