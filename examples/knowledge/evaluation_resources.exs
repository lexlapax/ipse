defmodule IpseKnowledgeExample.EvaluationResources do
  @moduledoc "Sample the harness VM and count files, without claiming model or OS peak memory."

  def start(path, interval) when interval in 10..1000 do
    owner = self()
    token = make_ref()

    {pid, monitor} =
      spawn_monitor(fn ->
        reference = Process.monitor(owner)
        loop(path, interval, reference, owner, token, nil, 0, nil)
      end)

    %{pid: pid, monitor: monitor, token: token}
  end

  def stop(sampler) do
    send(sampler.pid, {:stop, sampler.token})

    receive do
      {token, report} when token == sampler.token ->
        receive do
          {:DOWN, ref, :process, _, :normal} when ref == sampler.monitor -> {:ok, report}
        after
          5000 -> {:error, :sampler_cleanup_unconfirmed}
        end

      {:DOWN, ref, :process, _, _} when ref == sampler.monitor ->
        {:error, :sampler_failed}
    after
      5000 -> {:error, :sampler_cleanup_unconfirmed}
    end
  end

  def measure(output, context, fun) do
    started = System.monotonic_time(:microsecond)

    try do
      result = fun.()
      timing(output, context, started, "returned")
      result
    rescue
      error ->
        timing(output, context, started, "raised")
        reraise error, __STACKTRACE__
    catch
      kind, reason ->
        timing(output, context, started, Atom.to_string(kind))
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  # Evaluations prohibit child sessions. Compare every admission and every known
  # usage observation with the locked, restored budget ledger after owner close.
  def reconcile_budget(state, usage, events, session_id) do
    entries =
      Map.merge(
        state.refusals,
        Map.new(state.requests, fn {id, entry} -> {id, entry.admission} end)
      )

    observations =
      events
      |> Enum.filter(&(&1["type"] == "request_usage_observed"))
      |> Enum.group_by(& &1["request_id"], & &1["usage"])

    valid =
      state.root["session_id"] == session_id and
        MapSet.new(Map.keys(entries)) == MapSet.new(Map.keys(usage.requests)) and
        Enum.all?(usage.requests, fn {id, actual} ->
          admission = entries[id]
          entry = state.requests[id]

          admission === actual.admission and admission["session_id"] == session_id and
            if entry do
              liability = Ipse.Budget.Ledger.liability(state, id)

              known =
                [
                  Ipse.Budget.Policy.known(
                    state.policy,
                    admission,
                    actual.observation,
                    actual.completion
                  )
                ] ++
                  Enum.map(Map.get(observations, id, []), fn observation ->
                    Ipse.Budget.Policy.known(state.policy, admission, observation, nil)
                  end)

              Enum.all?(known, fn counters ->
                Enum.all?(counters, fn {unit, value} ->
                  is_nil(value) or (is_integer(liability[unit]) and liability[unit] >= value)
                end)
              end)
            else
              actual.observation == nil and
                (actual.completion == nil or
                   (actual.completion["outcome"] != "completed" and
                      actual.completion["usage"]["quality"] in ~w(unavailable not_applicable)))
            end
        end)

    if valid, do: :ok, else: {:error, :evaluation_budget_source_mismatch}
  end

  def summary(rows, timings, requests, budgets, storage \\ []) do
    variants = rows |> Enum.map(& &1["variant"]) |> Enum.uniq() |> Enum.sort()

    reports =
      Enum.map(variants, fn variant ->
        selected_rows = Enum.filter(rows, &(&1["variant"] == variant))
        selected_timings = Enum.filter(timings, &(&1["variant"] == variant))
        selected_requests = Enum.filter(requests, &(&1["variant"] == variant))
        selected_budgets = Enum.filter(budgets, &(&1["variant"] == variant))
        selected_storage = Enum.filter(storage, &(&1["variant"] == variant))
        projects = MapSet.new(selected_rows, & &1["project"])
        budget_projects = MapSet.new(selected_budgets, & &1["project"])

        budgets_complete =
          projects == budget_projects and length(selected_budgets) == MapSet.size(projects) and
            Enum.all?(selected_budgets, &(&1["accounting_verified"] == true))

        query_keys = MapSet.new(selected_rows, &{&1["project"], &1["query_id"]})
        query_timings = Enum.filter(selected_timings, &(&1["phase"] == "query"))
        observed = MapSet.new(query_timings, &{&1["project"], &1["query_id"]})
        missing = MapSet.difference(query_keys, observed) |> MapSet.size()
        unexpected = MapSet.difference(observed, query_keys) |> MapSet.size()
        duplicate = length(query_timings) - MapSet.size(observed)
        unattributed = Enum.count(selected_requests, &(&1["attribution"] != "confirmed"))
        storage_queries = Enum.filter(selected_storage, &(&1["phase"] == "after_query"))
        storage_keys = MapSet.new(storage_queries, &{&1["project"], &1["query_id"]})

        storage_complete =
          query_keys == storage_keys and length(storage_queries) == MapSet.size(query_keys) and
            Enum.all?(
              selected_storage,
              &(get_in(&1, ["inventory", "status"]) in ~w(verified absent not_applicable))
            ) and
            Enum.all?(projects, fn project ->
              projection_count =
                Enum.count(
                  selected_timings,
                  &(&1["project"] == project and &1["phase"] in ~w(invoke_index invoke_extract))
                )

              measured_projections =
                Enum.count(
                  selected_storage,
                  &(&1["project"] == project and &1["phase"] == "after_projection")
                )

              projection_count == measured_projections and
                Enum.all?(
                  ~w(before_ingestion after_preparation after_forget after_collection),
                  fn phase ->
                    Enum.count(
                      selected_storage,
                      &(&1["project"] == project and &1["phase"] == phase)
                    ) ==
                      1
                  end
                )
            end)

        %{
          "variant" => variant,
          "storage_reachability_complete" => storage_complete,
          "storage_snapshots" => selected_storage,
          "complete" =>
            missing == 0 and unexpected == 0 and duplicate == 0 and unattributed == 0 and
              budgets_complete,
          "queries" => %{
            "declared" => length(selected_rows),
            "observed" => length(query_timings),
            "missing" => missing,
            "unexpected" => unexpected,
            "duplicate" => duplicate,
            "statuses" => Enum.frequencies_by(selected_rows, & &1["status"])
          },
          "phases" =>
            selected_timings
            |> Enum.group_by(& &1["phase"])
            |> Enum.sort()
            |> Enum.map(fn {phase, samples} ->
              Map.merge(distribution(Enum.map(samples, &(&1["elapsed_us"] / 1000))), %{
                "phase" => phase,
                "outcomes" => Enum.frequencies_by(samples, & &1["outcome"]),
                "unconfirmed_invocations" => Enum.count(samples, &(&1["censored"] == true))
              })
            end),
          "requests" => %{
            "attempted" => length(selected_requests),
            "budget_admitted" => Enum.count(selected_requests, &(&1["budget_admitted"] == true)),
            "budget_refused" => Enum.count(selected_requests, &(&1["budget_admitted"] == false)),
            "dispatch_intents" => Enum.count(selected_requests, &(&1["dispatch_intent"] == true)),
            "unsettled" =>
              Enum.count(
                selected_requests,
                &(&1["budget_admitted"] == true and &1["budget_settled"] == false)
              ),
            "unattributed" => unattributed,
            "groups" =>
              selected_requests
              |> Enum.group_by(&request_role/1)
              |> Enum.sort()
              |> Enum.map(fn {role, records} ->
                values = Enum.map(records, & &1["request"])

                %{
                  "role" => role,
                  "count" => length(values),
                  "outcomes" => Enum.frequencies_by(values, & &1["outcome"]),
                  "latency_ms" => distribution(Enum.map(values, & &1["duration_ms"])),
                  "input_tokens" => counters(values, "input_tokens"),
                  "output_tokens" => counters(values, "output_tokens")
                }
              end)
          },
          "accounting_verified" => budgets_complete,
          "budget_snapshots" => selected_budgets,
          "money" => %{
            "status" =>
              if(Enum.all?(selected_budgets, &(get_in(&1, ["budget", "currency"]) == nil)),
                do: "unpriced",
                else: "see_budget_liability_dimensions"
              ),
            "amount" => nil
          }
        }
      end)

    %{
      "version" => 1,
      "measurement_scope" => "query_and_phase_clocks_canonical_requests_and_budget_liability",
      "resource_evaluation_complete" => false,
      "unmeasured" =>
        if(Enum.all?(reports, & &1["storage_reachability_complete"]),
          do: [],
          else: ["storage_reachability"]
        ) ++
          ~w(os_process_peak_memory model_process_memory),
      "storage_reachability_complete" =>
        Enum.all?(reports, & &1["storage_reachability_complete"]),
      "complete" =>
        Enum.all?(reports, & &1["complete"]) and
          Enum.sum(Enum.map(reports, & &1["requests"]["attempted"])) == length(requests) and
          Enum.sum(Enum.map(reports, &length(&1["budget_snapshots"]))) == length(budgets),
      "latency_method" => "nearest_rank",
      "phase_scope" => "caller_observation_including_failures",
      "request_scope" => "canonical_request_duration; missing durations remain unknown",
      "variants" => reports,
      "global_phases" =>
        timings
        |> Enum.filter(&is_nil(&1["variant"]))
        |> Enum.group_by(& &1["phase"])
        |> Enum.sort()
        |> Enum.map(fn {phase, samples} ->
          Map.put(distribution(Enum.map(samples, &(&1["elapsed_us"] / 1000))), "phase", phase)
        end)
    }
  end

  def distribution(values) do
    observed = values |> Enum.reject(&is_nil/1) |> Enum.sort()

    %{
      "n" => length(values),
      "observed" => length(observed),
      "unknown" => length(values) - length(observed),
      "p50_ms" => percentile(observed, 0.50),
      "p95_ms" => percentile(observed, 0.95)
    }
  end

  defp percentile([], _), do: nil
  defp percentile(values, p), do: Enum.at(values, ceil(length(values) * p) - 1)

  defp counters(records, field) do
    applicable =
      Enum.reject(records, &(field == "output_tokens" and &1["operation"] == "embedding"))

    values = Enum.map(applicable, &get_in(&1, ["usage", "counts", field]))
    known = Enum.filter(values, &is_integer/1)

    %{
      "applicable_requests" => length(values),
      "unknown_requests" => length(values) - length(known),
      "known_sum" => Enum.sum(known),
      "total" => if(values != [] and length(known) == length(values), do: Enum.sum(known)),
      "status" =>
        cond do
          values == [] -> "not_applicable"
          length(known) == length(values) -> "known"
          true -> "partial"
        end
    }
  end

  defp request_role(record) do
    cond do
      record["verb"] == "index" ->
        "index_embedding"

      record["verb"] == "query" and record["request"]["operation"] == "embedding" ->
        "query_embedding"

      record["verb"] == "query" ->
        "rerank"

      record["verb"] == "extract" ->
        "extraction"

      record["verb"] == "answer" ->
        "answer"

      true ->
        "unattributed"
    end
  end

  defp timing(output, context, started, outcome) do
    record(output, context, System.monotonic_time(:microsecond) - started, outcome, nil)
  end

  def record(output, context, elapsed_us, outcome, censored)
      when is_integer(elapsed_us) and elapsed_us >= 0 do
    record =
      Map.merge(context, %{
        "elapsed_us" => elapsed_us,
        "outcome" => outcome,
        "censored" => censored
      })

    path = Path.join(output, "timings.jsonl")
    File.write!(path, JSON.encode!(record) <> "\n", [:append])
    File.chmod!(path, 0o600)
  end

  def storage(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.reduce(%{}, fn path, counts ->
      relative = Path.relative_to(path, root)
      components = "/" <> relative

      category =
        cond do
          String.starts_with?(relative, "preflight/") -> "preflight"
          String.starts_with?(relative, "author-") -> "source_authoring"
          String.contains?(components, "/home/extension-state-v1/") -> "store"
          String.contains?(components, "/home/extensions/artifacts/") -> "artifacts"
          String.contains?(components, "/sessions/") -> "journals_and_budgets"
          true -> "other"
        end

      case File.lstat!(path) do
        %{type: :regular, size: bytes} ->
          Map.update(
            counts,
            category,
            %{"files" => 1, "bytes" => bytes},
            &%{"files" => &1["files"] + 1, "bytes" => &1["bytes"] + bytes}
          )

        _ ->
          counts
      end
    end)
  end

  defp loop(path, interval, reference, owner, token, peak, count, first) do
    memory = :erlang.memory()

    sample = %{
      "at_monotonic_ms" => System.monotonic_time(:millisecond),
      "beam_total_bytes" => memory[:total],
      "beam_process_bytes" => memory[:processes]
    }

    File.write!(path, JSON.encode!(sample) <> "\n", [:append])
    peak = max(peak || 0, sample["beam_total_bytes"])
    first = first || sample

    receive do
      {:stop, ^token} ->
        send(
          owner,
          {token,
           %{
             "interval_ms" => interval,
             "samples" => count + 1,
             "sampled_beam_max_bytes" => peak,
             "start" => first,
             "end" => sample,
             "worker_rss" => nil,
             "model_rss" => nil,
             "whole_system_peak" => nil
           }}
        )

      {:DOWN, ^reference, :process, _, _} ->
        :ok
    after
      interval -> loop(path, interval, reference, owner, token, peak, count + 1, first)
    end
  end
end
