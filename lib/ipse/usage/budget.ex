defmodule Ipse.Usage.Budget do
  @moduledoc "Durable shared request admission and conservative token/cost reservations."
  alias Ipse.Usage.BudgetStore

  def run(config, admission, emit, execute) do
    if config[:budget] == nil do
      execute.(config, emit)
    else
      with {:ok, config} <- request_config(config),
           {:ok, :reserved} <- decide(config, admission),
           {:ok, :ok} <-
             event(config, %{
               "type" => "dispatch_intent",
               "request_id" => admission["request_id"],
               "attempt_id" => admission["attempt_id"]
             }) do
        result = execute_guarded(config, admission, emit, execute)

        case settle(config, admission, result) do
          {:ok, :overdrawn} ->
            emit_final_usage(result, emit)

            {:error,
             "Budget liability exceeds the shared limit. Usage remains accounted; no assistant or tool result was admitted."}

          {:ok, :ok} ->
            result

          _ ->
            {:error,
             "Budget settlement is unconfirmed. Inspect the original ledger before continuing; no request was replayed."}
        end
      else
        {:ok, :refused} ->
          {:error,
           "Budget admission refused: shared reservation limit reached; no provider request was dispatched."}

        _ ->
          {:error,
           "Budget admission unavailable. Inspect the original ledger; no provider request was dispatched."}
      end
    end
  end

  defp emit_final_usage({:ok, _, raw}, emit), do: emit.({:provider_usage, raw})
  defp emit_final_usage(_, _), do: :ok

  defp execute_guarded(config, admission, emit, execute) do
    execute.(config, fn message ->
      case message do
        {:provider_usage, raw} ->
          usage = Ipse.Usage.observation(admission, raw, 1)["usage"]

          case observe(config, admission, usage) do
            {:ok, status} when status in [:ok, :overdrawn] ->
              emit.(message)
              if status == :overdrawn, do: throw(:budget_observation_refused), else: :ok

            _ ->
              throw(:budget_observation_refused)
          end

        _ ->
          emit.(message)
      end
    end)
  rescue
    error in Ipse.Session.TextStream.RequiredFailure -> {:error, Exception.message(error)}
    _ -> {:error, "Budgeted provider request failed; its reservation remains accounted."}
  catch
    _, _ ->
      {:error, "Budgeted provider request was interrupted; its reservation remains accounted."}
  end

  def decide(config, admission) do
    transact(config, fn state ->
      case decide_reservation(state, admission) do
        {:ok, event, _next, status} -> {:append, event, status}
        error -> error
      end
    end)
  end

  def event(config, event) do
    transact(config, fn state ->
      with {:ok, next} <- apply_reservation_event(state, event),
           do: {:append, event, if(overdrawn?(next), do: :overdrawn, else: :ok)}
    end)
  end

  def observe(config, admission, usage) do
    transact(config, fn state ->
      entry = state.requests[admission["request_id"]]

      if entry && entry.observation == usage do
        {:read, :ok}
      else
        event = %{
          "type" => "observed",
          "request_id" => admission["request_id"],
          "attempt_id" => admission["attempt_id"],
          "usage" => usage
        }

        with {:ok, next} <- apply_reservation_event(state, event),
             do: {:append, event, if(overdrawn?(next), do: :overdrawn, else: :ok)}
      end
    end)
  end

  def settle(config, admission, result) do
    transact(config, fn state ->
      entry = state.requests[admission["request_id"]]

      if entry do
        completion = Ipse.Usage.completion(admission, result, 0, entry.observation)
        event = %{"type" => "settled", "completion" => completion}

        with {:ok, next} <- apply_reservation_event(state, event),
             do: {:append, event, if(overdrawn?(next), do: :overdrawn, else: :ok)}
      else
        {:error, :unknown_budget_request}
      end
    end)
  end

  def snapshot(config) do
    if config[:budget],
      do:
        BudgetStore.transaction(
          config.budget_root,
          config.budget,
          &{:read, ledger_snapshot(&1)},
          false,
          config[:budget_checkpoint]
        ),
      else: {:ok, %{"version" => 1, "scope" => "none"}}
  end

  def saved(dir, id) do
    with {:ok, [%{"metadata" => meta} | _]} <- Ipse.Journal.load(dir, id),
         {:ok, config} <-
           BudgetStore.attach(
             %{
               provider: Ipse.Provider.Registry.atoms()[meta["provider"]],
               max_output_tokens: meta["max_output_tokens"],
               budget: meta["budget"],
               budget_root: meta["budget_root"],
               delegation_origin: meta["delegation_origin"]
             },
             dir,
             id,
             false,
             :inspect
           ) do
      snapshot(config)
    end
  end

  defp transact(config, fun) do
    if is_reference(config[:budget_checkpoint]),
      do:
        BudgetStore.transaction(
          config.budget_root,
          config.budget,
          fun,
          false,
          config.budget_checkpoint
        ),
      else: {:error, :budget_checkpoint_unavailable}
  end

  def validate_sources(%{budget: nil}, _id, _events), do: :ok

  def validate_sources(config, id, events) do
    if config[:budget] do
      case transact(config, fn state ->
             with {:ok, usage} <- Ipse.Usage.restore(events, id),
                  :ok <- validate_usage(state, usage, id, events),
                  :ok <- validate_children(state, config, id, events) do
               {:read, :ok}
             end
           end) do
        {:ok, :ok} -> :ok
        _ -> {:error, :budget_sources_unavailable}
      end
    else
      :ok
    end
  end

  defp validate_usage(state, usage, id, events) do
    observations =
      events
      |> Enum.filter(&(&1["type"] == "request_usage_observed"))
      |> Enum.group_by(& &1["request_id"], & &1["usage"])

    entries =
      Map.merge(
        state.refusals,
        Map.new(state.requests, fn {key, value} -> {key, value.admission} end)
      )

    matching = Enum.filter(entries, fn {_, a} -> a["session_id"] == id end)

    valid =
      length(matching) == map_size(usage.requests) and
        Enum.all?(usage.requests, fn {request_id, actual} ->
          admission = entries[request_id]
          entry = state.requests[request_id]

          cond do
            admission !== actual.admission ->
              false

            entry == nil ->
              actual.observation == nil and
                (actual.completion == nil or
                   (actual.completion["outcome"] != "completed" and
                      actual.completion["usage"]["quality"] in ~w(unavailable not_applicable)))

            true ->
              known =
                known(
                  state.policy,
                  actual.admission,
                  actual.observation,
                  actual.completion
                )

              own = liability(state, request_id)

              observed =
                observations
                |> Map.get(request_id, [])
                |> Enum.flat_map(fn observation ->
                  Map.to_list(known(state.policy, actual.admission, observation, nil))
                end)

              Enum.all?(Map.to_list(known) ++ observed, fn {key, value} ->
                is_nil(value) or own[key] >= value
              end)
          end
        end)

    if valid, do: :ok, else: {:error, :budget_source_mismatch}
  end

  defp validate_children(state, config, id, events) do
    if id == config.budget_root["session_id"] do
      index =
        Enum.reduce(
          events,
          Ipse.Extension.ChildUsage.new(),
          &Ipse.Extension.ChildUsage.apply_parent(&2, &1)
        )

      ids =
        state.requests
        |> Map.values()
        |> Enum.map(& &1.admission["session_id"])
        |> Kernel.++(Enum.map(Map.values(state.refusals), & &1["session_id"]))
        |> Enum.uniq()
        |> List.delete(id)

      if not index.overflow and Enum.all?(ids, &Map.has_key?(index.index, &1)) do
        Enum.reduce_while(index.index, :ok, fn {child_id, child}, :ok ->
          case Ipse.Extension.ChildUsage.read_for_budget(
                 config.budget_root["state_dir"],
                 id,
                 child
               ) do
            {:ok, usage, _, _, accounting_events} ->
              case validate_usage(state, usage, child_id, accounting_events) do
                :ok -> {:cont, :ok}
                error -> {:halt, error}
              end

            _ ->
              {:halt, {:error, :budget_child_source_unavailable}}
          end
        end)
      else
        {:error, :budget_child_source_mismatch}
      end
    else
      :ok
    end
  end

  @safe 9_007_199_254_740_991
  def ledger_header(root, policy),
    do: %{
      "type" => "budget",
      "version" => 1,
      "root" => root,
      "policy" => policy,
      "policy_sha256" => Ipse.JSON.digest([policy])
    }

  def restore_ledger([header | events], root, policy) do
    if header === ledger_header(root, policy) and validate_policy(policy) == :ok do
      initial = %{
        root: root,
        policy: policy,
        requests: %{},
        refusals: %{},
        attempts: MapSet.new(),
        booked: Map.new(limits(policy), fn {key, _} -> {key, 0} end)
      }

      Enum.reduce_while(events, {:ok, initial}, fn event, {:ok, state} ->
        case apply_reservation_event(state, event) do
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

  def restore_ledger(_, _, _), do: {:error, :invalid_budget_ledger}

  def reserve_request(state, admission) do
    event = %{"type" => "reserved", "admission" => admission}

    with {:ok, next} <- apply_reservation_event(state, event),
         false <- overdrawn?(next) do
      {:ok, event, next}
    else
      true -> {:error, :budget_exhausted}
      {:error, :budget_exhausted} = error -> error
      _ -> {:error, :invalid_budget_admission}
    end
  end

  def decide_reservation(state, admission) do
    case reserve_request(state, admission) do
      {:ok, event, next} ->
        {:ok, event, next, :reserved}

      {:error, :budget_exhausted} ->
        event = %{"type" => "refused", "admission" => admission}

        with {:ok, next} <- apply_reservation_event(state, event),
             do: {:ok, event, next, :refused}

      error ->
        error
    end
  end

  def apply_reservation_event(state, %{"type" => "reserved", "admission" => admission} = event) do
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
        reserve: reservation(state.policy, admission),
        peak: Map.new(limits(state.policy), fn {key, _} -> {key, 0} end)
      }

      next =
        %{state | attempts: MapSet.put(state.attempts, admission["attempt_id"])}
        |> put_entry(id, entry)

      if overdrawn?(next), do: {:error, :budget_exhausted}, else: {:ok, next}
    else
      _ -> {:error, :invalid_budget_ledger}
    end
  end

  def apply_reservation_event(state, %{"type" => "refused", "admission" => admission} = event) do
    with true <- Enum.sort(Map.keys(event)) == ~w(admission type),
         true <- map_size(state.refusals) < 40_000,
         {:error, :budget_exhausted} <- reserve_request(state, admission) do
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

  def apply_reservation_event(
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

  def apply_reservation_event(
        state,
        %{"type" => "observed", "request_id" => id, "attempt_id" => attempt, "usage" => usage} =
          event
      ) do
    with true <- Enum.sort(Map.keys(event)) == ~w(attempt_id request_id type usage),
         %{dispatch: true, completion: nil} = entry <- state.requests[id],
         true <- entry.admission["attempt_id"] == attempt,
         true <- entry.observations < 64,
         true <- Ipse.Usage.valid_usage?(usage, Ipse.Usage.operation(entry.admission)) do
      known = observed(state.policy, entry.admission, usage)
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

  def apply_reservation_event(state, %{"type" => "settled", "completion" => completion} = event) do
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

  def apply_reservation_event(_, _), do: {:error, :invalid_budget_ledger}

  def totals(state), do: state.booked
  def liability(state, id), do: charge(state.policy, Map.fetch!(state.requests, id))

  defp charge(policy, entry) do
    final =
      if entry.completion && entry.completion["outcome"] == "completed",
        do: observed(policy, entry.admission, entry.observation, entry.completion),
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
    do: Enum.any?(totals(state), fn {key, value} -> value > limits(state.policy)[key] end)

  def ledger_snapshot(state) do
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
              observed(state.policy, entry.admission, entry.observation, entry.completion),
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
            "limit" => limits(state.policy)[key],
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
      Ipse.Usage.valid_usage?(completion["usage"], Ipse.Usage.operation(entry.admission)) and
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

  alias Ipse.Usage
  alias Ipse.JSON, as: Schema
  @bases ~w(api_estimate api_equivalent local_estimate)
  def bases, do: @bases

  def schema do
    count = integer(0, Usage.counter_limit())
    positive = integer(1, Usage.counter_limit())

    money = %{
      "type" => "object",
      "properties" => %{
        "basis" => %{"type" => "string", "enum" => @bases},
        "limit_nanos" => integer(0, @safe),
        "reserve_nanos" => integer(1, @safe)
      },
      "required" => ~w(basis limit_nanos reserve_nanos),
      "additionalProperties" => false
    }

    %{
      "type" => "object",
      "properties" => %{
        "version" => %{"type" => "integer", "enum" => [1]},
        "max_requests" => integer(0, 40_000),
        "max_input_tokens" => count,
        "max_output_tokens" => count,
        "reserve_input_tokens" => positive,
        "reserve_output_tokens" => integer(1, Ipse.Provider.max_output_tokens()),
        "money" => %{"type" => "array", "minItems" => 1, "maxItems" => 3, "items" => money},
        "rate_card" => Ipse.Usage.Costs.schema()
      },
      "required" => ["version"],
      "additionalProperties" => false
    }
  end

  def validate_policy(nil), do: :ok

  def validate_policy(policy) do
    with :ok <- Schema.validate_arguments(schema(), policy),
         true <- policy["version"] === 1,
         true <-
           Enum.all?(
             Map.take(
               policy,
               ~w(max_requests max_input_tokens max_output_tokens reserve_input_tokens reserve_output_tokens)
             ),
             fn {_, value} -> is_integer(value) end
           ),
         true <-
           Enum.any?(
             ~w(max_requests max_input_tokens max_output_tokens money),
             &Map.has_key?(policy, &1)
           ),
         true <- paired?(policy, "max_input_tokens", "reserve_input_tokens"),
         true <- paired?(policy, "max_output_tokens", "reserve_output_tokens"),
         true <- paired?(policy, "money", "rate_card"),
         true <-
           length(Enum.uniq_by(policy["money"] || [], & &1["basis"])) ==
             length(policy["money"] || []),
         true <-
           Enum.all?(
             policy["money"] || [],
             &(is_integer(&1["limit_nanos"]) and is_integer(&1["reserve_nanos"]))
           ),
         :ok <-
           if(policy["rate_card"],
             do: Ipse.Usage.Costs.validate(policy["rate_card"]),
             else: :ok
           ) do
      :ok
    else
      _ -> {:error, :invalid_budget_policy}
    end
  rescue
    _ -> {:error, :invalid_budget_policy}
  end

  def resolve_policy(sources) do
    if Enum.any?(sources, &(&1.scope != "operator" and Map.has_key?(&1.data, "budget"))) do
      {:error, "Budget policy is operator-only; project configuration cannot replace it."}
    else
      policy = Enum.find_value(sources, & &1.data["budget"])
      with :ok <- validate_policy(policy), do: {:ok, policy}
    end
  end

  def validate_configuration(config) do
    with :ok <- validate_policy(config[:budget]),
         true <- is_nil(config[:budget_root]) or is_map(config[:budget]),
         true <-
           is_nil(config[:budget]) or is_nil(config[:delegation_origin]) or
             is_map(config[:budget_root]) do
      request_config(config)
      |> case do
        {:ok, _} -> :ok
        error -> error
      end
    else
      _ -> {:error, :invalid_budget_policy}
    end
  end

  def request_config(%{operation: :embedding} = config), do: {:ok, config}

  def request_config(config) do
    case config[:budget] do
      %{"reserve_output_tokens" => reserve} ->
        capped =
          Map.put(
            config,
            :max_output_tokens,
            Ipse.Provider.narrow_output_tokens(config[:max_output_tokens], reserve)
          )

        if Ipse.Provider.Registry.fetch!(config.provider).output_limit_scope == :visible do
          {:error,
           "The selected provider caps visible text only, excluding reasoning and function calls. A total-output token reservation cannot be enforced; choose a request-count policy or another provider."}
        else
          with :ok <- Ipse.Provider.validate_output_limit(capped), do: {:ok, capped}
        end

      _ ->
        {:ok, config}
    end
  end

  def limits(policy) do
    ordinary =
      for {source, target} <- [
            {"max_requests", "requests"},
            {"max_input_tokens", "input_tokens"},
            {"max_output_tokens", "output_tokens"}
          ],
          Map.has_key?(policy, source),
          into: %{},
          do: {target, policy[source]}

    Enum.reduce(policy["money"] || [], ordinary, fn bucket, acc ->
      Map.put(acc, "money:" <> bucket["basis"], bucket["limit_nanos"])
    end)
  end

  def reservation(policy, admission) do
    basis = basis(admission["billing_mode"])

    for key <- Map.keys(limits(policy)), into: %{} do
      value =
        case key do
          "requests" ->
            1

          "input_tokens" ->
            policy["reserve_input_tokens"]

          "output_tokens" ->
            if Ipse.Usage.operation(admission) == "embedding",
              do: 0,
              else: policy["reserve_output_tokens"]

          "money:" <> selected ->
            if selected == basis,
              do: Enum.find(policy["money"], &(&1["basis"] == selected))["reserve_nanos"],
              else: 0
        end

      {key, value}
    end
  end

  def observed(policy, admission, usage, completion \\ nil),
    do: measure(policy, admission, usage, completion, true)

  def known(policy, admission, usage, completion),
    do: measure(policy, admission, usage, completion, false)

  defp measure(policy, admission, usage, completion, final_only) do
    record =
      Ipse.Usage.request_record(%{
        admission: admission,
        observation: usage,
        completion: completion
      })

    estimate = if policy["rate_card"], do: estimate(policy, record)

    for key <- Map.keys(limits(policy)), into: %{} do
      value =
        case key do
          "requests" ->
            1

          "input_tokens" ->
            record["usage"]["counts"]["input_tokens"]

          "output_tokens" ->
            if Ipse.Usage.operation(admission) == "embedding",
              do: 0,
              else: record["usage"]["counts"]["output_tokens"]

          "money:" <> selected ->
            cond do
              selected != basis(admission["billing_mode"]) -> 0
              is_nil(estimate) -> nil
              "amount_overflow" in estimate["missing"] -> @safe + 1
              completion && estimate["status"] == "estimated" -> estimate["amount_nanos"]
              completion && completion["outcome"] == "completed" && final_only -> nil
              true -> estimate["known_amount_nanos"]
            end
        end

      {key, value}
    end
  end

  defp estimate(policy, record) do
    fields =
      ~w(provider billing_mode model reported_model endpoint_sha256 admitted_at_ms outcome finality usage)

    fields = if record["version"] == 2, do: fields ++ ["operation"], else: fields

    case Ipse.Usage.Costs.estimate(policy["rate_card"], Map.take(record, fields)) do
      {:ok, value} -> value
      _ -> nil
    end
  end

  defp basis(billing), do: Ipse.Provider.Registry.cost_basis(billing)
  defp paired?(map, left, right), do: Map.has_key?(map, left) == Map.has_key?(map, right)
  defp integer(low, high), do: %{"type" => "integer", "minimum" => low, "maximum" => high}
end
