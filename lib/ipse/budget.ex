defmodule Ipse.Budget do
  @moduledoc "Durable shared request admission and conservative token/cost reservations."
  alias Ipse.Budget.{Ledger, Policy, Store}

  def run(config, admission, emit, execute) do
    if config[:budget] == nil do
      execute.(config, emit)
    else
      with {:ok, config} <- Policy.request_config(config),
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
    error in Ipse.TextStream.RequiredFailure -> {:error, Exception.message(error)}
    _ -> {:error, "Budgeted provider request failed; its reservation remains accounted."}
  catch
    _, _ ->
      {:error, "Budgeted provider request was interrupted; its reservation remains accounted."}
  end

  def decide(config, admission) do
    transact(config, fn state ->
      case Ledger.decide(state, admission) do
        {:ok, event, _next, status} -> {:append, event, status}
        error -> error
      end
    end)
  end

  def event(config, event) do
    transact(config, fn state ->
      with {:ok, next} <- Ledger.apply_event(state, event),
           do: {:append, event, if(Ledger.overdrawn?(next), do: :overdrawn, else: :ok)}
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

        with {:ok, next} <- Ledger.apply_event(state, event),
             do: {:append, event, if(Ledger.overdrawn?(next), do: :overdrawn, else: :ok)}
      end
    end)
  end

  def settle(config, admission, result) do
    transact(config, fn state ->
      entry = state.requests[admission["request_id"]]

      if entry do
        completion = Ipse.Usage.completion(admission, result, 0, entry.observation)
        event = %{"type" => "settled", "completion" => completion}

        with {:ok, next} <- Ledger.apply_event(state, event),
             do: {:append, event, if(Ledger.overdrawn?(next), do: :overdrawn, else: :ok)}
      else
        {:error, :unknown_budget_request}
      end
    end)
  end

  def snapshot(config) do
    if config[:budget],
      do:
        Store.transaction(
          config.budget_root,
          config.budget,
          &{:read, Ledger.snapshot(&1)},
          false,
          config[:budget_checkpoint]
        ),
      else: {:ok, %{"version" => 1, "scope" => "none"}}
  end

  def saved(dir, id) do
    with {:ok, [%{"metadata" => meta} | _]} <- Ipse.Journal.load(dir, id),
         {:ok, config} <-
           Store.attach(
             %{
               provider:
                 %{
                   "chatgpt" => :chatgpt,
                   "openai" => :openai,
                   "ollama" => :ollama,
                   "anthropic" => :anthropic,
                   "demo" => :demo
                 }[meta["provider"]],
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
        Store.transaction(config.budget_root, config.budget, fun, false, config.budget_checkpoint),
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
                Policy.known(
                  state.policy,
                  actual.admission,
                  actual.observation,
                  actual.completion
                )

              own = Ledger.liability(state, request_id)

              observed =
                observations
                |> Map.get(request_id, [])
                |> Enum.flat_map(fn observation ->
                  Map.to_list(Policy.known(state.policy, actual.admission, observation, nil))
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
          Ipse.Extensions.ChildUsage.new(),
          &Ipse.Extensions.ChildUsage.apply_parent(&2, &1)
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
          case Ipse.Extensions.ChildUsage.read_for_budget(
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
end
