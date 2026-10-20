defmodule Ipse.Budget.Ledger do
  @moduledoc "Pure validated reservation ledger; interrupted attempts retain their liability."
  alias Ipse.Budget.Policy
  @safe 9_007_199_254_740_991
  def header(root, policy),
    do: %{
      "type" => "budget",
      "version" => 1,
      "root" => root,
      "policy" => policy,
      "policy_sha256" => Ipse.JSON.digest([policy])
    }

  def restore([header | events], root, policy) do
    if header === header(root, policy) and Policy.validate(policy) == :ok do
      initial = %{
        root: root,
        policy: policy,
        requests: %{},
        refusals: %{},
        attempts: MapSet.new(),
        booked: Map.new(Policy.limits(policy), fn {key, _} -> {key, 0} end)
      }

      Enum.reduce_while(events, {:ok, initial}, fn event, {:ok, state} ->
        case apply_event(state, event) do
          {:ok, next} -> {:cont, {:ok, next}}
          _ -> {:halt, {:error, :invalid_budget_ledger}}
        end
      end)
    else
      {:error, :budget_identity_mismatch}
    end
  rescue
    _ -> {:error, :invalid_budget_ledger}
  end

  def restore(_, _, _), do: {:error, :invalid_budget_ledger}

  def reserve(state, admission) do
    event = %{"type" => "reserved", "admission" => admission}

    with {:ok, next} <- apply_event(state, event),
         false <- overdrawn?(next) do
      {:ok, event, next}
    else
      true -> {:error, :budget_exhausted}
      {:error, :budget_exhausted} = error -> error
      _ -> {:error, :invalid_budget_admission}
    end
  end

  def decide(state, admission) do
    case reserve(state, admission) do
      {:ok, event, next} ->
        {:ok, event, next, :reserved}

      {:error, :budget_exhausted} ->
        event = %{"type" => "refused", "admission" => admission}
        with {:ok, next} <- apply_event(state, event), do: {:ok, event, next, :refused}

      error ->
        error
    end
  end

  def apply_event(state, %{"type" => "reserved", "admission" => admission} = event) do
    id = admission["request_id"]

    with true <- Map.keys(event) |> Enum.sort() == ~w(admission type),
         true <- valid_admission?(admission),
         true <- scope?(state, admission),
         false <- Map.has_key?(state.requests, id),
         false <- Map.has_key?(state.refusals, id),
         true <- map_size(state.requests) < 40_000,
         false <- MapSet.member?(state.attempts, admission["attempt_id"]) do
      entry = %{
        admission: admission,
        dispatch: false,
        observation: nil,
        observations: 0,
        completion: nil,
        reserve: Policy.reservation(state.policy, admission),
        peak: Map.new(Policy.limits(state.policy), fn {key, _} -> {key, 0} end)
      }

      next =
        %{state | attempts: MapSet.put(state.attempts, admission["attempt_id"])}
        |> put_entry(id, entry)

      if overdrawn?(next), do: {:error, :budget_exhausted}, else: {:ok, next}
    else
      _ -> {:error, :invalid_budget_ledger}
    end
  end

  def apply_event(state, %{"type" => "refused", "admission" => admission} = event) do
    with true <- Enum.sort(Map.keys(event)) == ~w(admission type),
         true <- map_size(state.refusals) < 40_000,
         {:error, :budget_exhausted} <- reserve(state, admission) do
      {:ok,
       %{
         state
         | refusals: Map.put(state.refusals, admission["request_id"], admission),
           attempts: MapSet.put(state.attempts, admission["attempt_id"])
       }}
    else
      _ -> {:error, :invalid_budget_ledger}
    end
  end

  def apply_event(
        state,
        %{"type" => "dispatch_intent", "request_id" => id, "attempt_id" => attempt} = event
      ) do
    with true <- Enum.sort(Map.keys(event)) == ~w(attempt_id request_id type),
         false <- overdrawn?(state),
         %{dispatch: false, completion: nil} = entry <- state.requests[id],
         true <- entry.admission["attempt_id"] == attempt do
      {:ok, put_in(state, [:requests, id, :dispatch], true)}
    else
      _ -> {:error, :invalid_budget_ledger}
    end
  end

  def apply_event(
        state,
        %{"type" => "observed", "request_id" => id, "attempt_id" => attempt, "usage" => usage} =
          event
      ) do
    with true <- Enum.sort(Map.keys(event)) == ~w(attempt_id request_id type usage),
         %{dispatch: true, completion: nil} = entry <- state.requests[id],
         true <- entry.admission["attempt_id"] == attempt,
         true <- entry.observations < 64,
         true <- Ipse.Usage.Normalizer.valid?(usage, Ipse.Usage.operation(entry.admission)) do
      known = Policy.observed(state.policy, entry.admission, usage)
      peak = Map.new(entry.peak, fn {key, value} -> {key, max(value, known[key] || 0)} end)

      {:ok,
       put_entry(state, id, %{
         entry
         | observation: usage,
           observations: entry.observations + 1,
           peak: peak
       })}
    else
      _ -> {:error, :invalid_budget_ledger}
    end
  end

  def apply_event(state, %{"type" => "settled", "completion" => completion} = event) do
    id = completion["request_id"]

    with true <- Enum.sort(Map.keys(event)) == ~w(completion type),
         %{dispatch: true, completion: nil} = entry <- state.requests[id],
         true <- completion["attempt_id"] == entry.admission["attempt_id"],
         true <- valid_completion?(entry, completion) do
      {:ok, put_entry(state, id, %{entry | completion: completion})}
    else
      _ -> {:error, :invalid_budget_ledger}
    end
  end

  def apply_event(_, _), do: {:error, :invalid_budget_ledger}

  def totals(state), do: state.booked
  def liability(state, id), do: charge(state.policy, Map.fetch!(state.requests, id))

  defp charge(policy, entry) do
    final =
      if entry.completion && entry.completion["outcome"] == "completed",
        do: Policy.observed(policy, entry.admission, entry.observation, entry.completion),
        else: %{}

    Map.new(entry.reserve, fn {key, reserved} ->
      {key,
       if(is_integer(final[key]),
         do: max(final[key], entry.peak[key]),
         else: max(reserved, entry.peak[key])
       )}
    end)
  end

  defp put_entry(state, id, entry) do
    old = if state.requests[id], do: charge(state.policy, state.requests[id]), else: %{}
    new = charge(state.policy, entry)

    booked =
      Map.new(state.booked, fn {key, value} -> {key, value - (old[key] || 0) + new[key]} end)

    %{state | booked: booked, requests: Map.put(state.requests, id, entry)}
  end

  def overdrawn?(state),
    do: Enum.any?(totals(state), fn {key, value} -> value > Policy.limits(state.policy)[key] end)

  def snapshot(state) do
    totals = totals(state)

    %{
      "version" => 1,
      "scope" => "session_tree",
      "root_session_id" => state.root["session_id"],
      "currency" => get_in(state.policy, ["rate_card", "currency"]),
      "currency_scale" => if(state.policy["rate_card"], do: 9),
      "request_count" => map_size(state.requests),
      "refused_count" => map_size(state.refusals),
      "unsettled_count" => Enum.count(state.requests, fn {_, e} -> e.completion == nil end),
      "partial_count" =>
        Enum.count(state.requests, fn {_, e} ->
          e.completion != nil and e.completion["outcome"] != "completed"
        end),
      "unknown_liability_count" =>
        Enum.count(state.requests, fn {_, entry} ->
          if entry.completion && entry.completion["outcome"] == "completed" do
            Enum.any?(
              Policy.observed(state.policy, entry.admission, entry.observation, entry.completion),
              fn {_, value} -> is_nil(value) end
            )
          else
            true
          end
        end),
      "overdrawn" => overdrawn?(state),
      "policy_sha256" => Ipse.JSON.digest([state.policy]),
      "dimensions" =>
        Enum.map(Enum.sort(totals), fn {key, value} ->
          %{
            "unit" => key,
            "limit" => Policy.limits(state.policy)[key],
            "booked" => if(value <= @safe, do: value),
            "overflow" => value > @safe
          }
        end)
    }
  end

  defp valid_admission?(admission) do
    record = Ipse.Usage.request_record(%{admission: admission, observation: nil, completion: nil})
    admission["type"] == "request_admitted" and Ipse.Usage.valid_request_record?(record)
  rescue
    _ -> false
  end

  defp valid_completion?(entry, completion) do
    fields =
      ~w(attempt_id duration_ms finality outcome reported_model request_id type usage version)

    fields = if entry.admission["version"] === 2, do: fields ++ ["operation"], else: fields

    Enum.sort(Map.keys(completion)) ==
      Enum.sort(fields) and
      completion["version"] === entry.admission["version"] and
      completion["type"] == "request_finished" and
      completion["operation"] === entry.admission["operation"] and
      Ipse.Usage.Normalizer.valid?(completion["usage"], Ipse.Usage.operation(entry.admission)) and
      Ipse.Usage.valid_request_record?(
        Ipse.Usage.request_record(%{entry | completion: completion})
      )
  rescue
    _ -> false
  end

  defp scope?(state, admission) do
    root = state.root["session_id"]

    if admission["session_id"] == root do
      admission["parent_session_id"] == nil and admission["parent_request_id"] == nil
    else
      parent = state.requests[admission["parent_request_id"]]

      admission["parent_session_id"] == root and parent != nil and
        parent.admission["session_id"] == root
    end
  end
end
