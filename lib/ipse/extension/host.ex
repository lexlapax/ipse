defmodule Ipse.Extension.Host do
  @moduledoc "Ordered bounded transform jobs, owned by Session's monitored task chain."
  alias Ipse.Extension.{Registry, Worker, Projection, Actions, State, ResultSource}

  def enabled?(config, stage),
    do: Enum.any?(Map.get(config, :extensions, []), &(stage in &1.identity["capabilities"]))

  def run(config, stage, owner, job_ref) do
    config
    |> Map.get(:extensions, [])
    |> Enum.filter(&(stage in &1.identity["capabilities"]))
    |> Enum.reduce_while(:ok, fn entry, :ok ->
      with true <- Registry.live?(entry.identity),
           {:ok, intent, input} <-
             GenServer.call(owner, {:extension_begin, job_ref, entry.identity["instance"], stage}),
           {:ok, result} <- invoke(entry, stage, input),
           {:ok, event} <- Projection.build(intent, input, result),
           :ok <- GenServer.call(owner, {:extension_commit, job_ref, event}) do
        {:cont, :ok}
      else
        _ ->
          {:halt,
           {:error,
            "Extension transform failed or expired; committed input/output remains available. No callback was replayed."}}
      end
    end)
  end

  defp invoke(entry, stage, input) do
    with {:ok, worker} <-
           Worker.start(
             owner: self(),
             store: entry.store,
             digest: entry.identity["artifact"],
             trusted: entry.identity["artifact"],
             artifact_sha256: entry.identity["artifact_sha256"],
             options: entry.options
           ) do
      try do
        with {:ok, _} <- Worker.call(worker, "initialize", entry.options),
             {:ok, result} <- Worker.call(worker, stage, %{"text" => input}),
             :ok <- Worker.close(worker) do
          {:ok, result}
        end
      after
        if Process.alive?(worker), do: Worker.close(worker)
      end
    end
  end

  def notify_events(plans, owner, ref) do
    Enum.reduce_while(plans, :ok, fn plan, :ok ->
      admission =
        GenServer.call(
          owner,
          {:extension_event_begin, ref, plan.instance, plan.declaration["id"]}
        )

      case admission do
        {:job, intent, entry, parent} ->
          case execute_export(entry, parent, "event.job", parent["payload"], owner, ref, []) do
            {:extension_invocation_result, result} ->
              case GenServer.call(owner, {:extension_event_job_commit, ref, result}) do
                {:ok, "completed"} ->
                  {:cont, :ok}

                {:ok, "failed"} ->
                  if not plan.declaration["required"],
                    do: {:cont, :ok},
                    else:
                      {:halt,
                       {:error,
                        "Required event job had a refused or failed action; inspect its receipts."}}

                _ ->
                  {:halt,
                   {:error, "Event job result could not be committed; inspect its saved intent."}}
              end

            {:extension_question, action} ->
              {:halt, {:extension_question, action}}

            _ ->
              result = Ipse.Extension.Subscriptions.result(intent, "unknown", false)
              GenServer.call(owner, {:extension_event_commit, ref, result})

              {:halt,
               {:error,
                "Event job outcome is unknown; earlier effects may have occurred. No job was replayed."}}
          end

        _ ->
          with {:ok, intent, entry, payload} <- admission,
               {outcome, cleanup} <- notify_event(entry, payload),
               result = Ipse.Extension.Subscriptions.result(intent, outcome, cleanup),
               :ok <- GenServer.call(owner, {:extension_event_commit, ref, result}) do
            if outcome == "acknowledged" or not plan.declaration["required"],
              do: {:cont, :ok},
              else:
                {:halt,
                 {:error,
                  "Required event subscriber did not acknowledge; no delivery was replayed."}}
          else
            _ ->
              {:halt, {:error, "Event subscription admission failed; no delivery was replayed."}}
          end
      end
    end)
  catch
    :exit, _ ->
      {:error, "Event subscription was interrupted; inspect its saved intent before retrying."}
  end

  defp notify_event(_entry, nil), do: {"not_started", true}

  defp notify_event(entry, payload) do
    with true <- Registry.live?(entry.identity),
         {:ok, worker} <-
           Worker.start(
             owner: self(),
             store: entry.store,
             digest: entry.identity["artifact"],
             trusted: entry.identity["artifact"],
             artifact_sha256: entry.identity["artifact_sha256"],
             options: entry.options
           ) do
      try do
        acknowledged =
          with {:ok, _} <- Worker.call(worker, "initialize", entry.options),
               {:ok, reply} <- Worker.call(worker, "event.notify", payload),
               true <-
                 reply == %{
                   "api_version" => 1,
                   "kind" => "ack",
                   "delivery_id" => payload["delivery_id"],
                   "event_id" => payload["event"]["event_id"]
                 },
               true <- Registry.live?(entry.identity),
               do: true

        cleanup = Worker.close(worker) == :ok

        {if(acknowledged == true and cleanup and Registry.live?(entry.identity),
           do: "acknowledged",
           else: "unknown"
         ), cleanup}
      after
        if Process.alive?(worker), do: Worker.close(worker)
      end
    else
      _ -> {"not_started", true}
    end
  catch
    :exit, _ -> {"unknown", false}
  end

  def invoke_export(stage, name, arguments, owner, job_ref) do
    with {:ok, intent, entry} <-
           GenServer.call(owner, {:extension_invoke_begin, job_ref, stage, name, arguments}) do
      execute_export(entry, intent, stage, intent["payload"], owner, job_ref, [])
    else
      _ -> invocation_unknown()
    end
  catch
    :exit, _ -> invocation_unknown()
  end

  def resume_export(entry, parent, result, owner, job_ref, actions) do
    execute_export(entry, parent, "host.actions", Actions.resume(result), owner, job_ref, actions)
  end

  defp execute_export(entry, intent, stage, payload, owner, job_ref, prior_actions) do
    entry =
      if Enum.any?(
           ~w(host.usage.scan host.state.scan host.results host.sources host.collection.read host.actions.mixed),
           &(&1 in entry.identity["capabilities"])
         ) do
        Map.put(entry, :read_deadline, System.monotonic_time(:millisecond) + 120_000)
      else
        entry
      end

    with :ok <- outer_current(entry, intent),
         {:ok, worker} <-
           Worker.start(
             owner: self(),
             store: entry.store,
             digest: entry.identity["artifact"],
             trusted: entry.identity["artifact"],
             artifact_sha256: entry.identity["artifact_sha256"],
             options: entry.options
           ) do
      try do
        with {:ok, _} <- export_call(worker, entry, "initialize", entry.options),
             {:ok, response} <- export_call(worker, entry, stage, payload) do
          case continue(worker, response, entry, owner, job_ref, prior_actions) do
            {:ok, %{"kind" => "result_producer"} = offer, _actions} ->
              with true <- Map.has_key?(entry, :output_started_ms),
                   {:ok, begin} <-
                     GenServer.call(owner, {:extension_output_begin, job_ref, offer}),
                   {:ok, ^begin, source} <-
                     ResultSource.open(intent, offer, begin["elapsed_ms"]),
                   {:ok, source} <- drain_output(worker, source, entry, owner, job_ref),
                   {:ok, proof, _sealed} <-
                     ResultSource.seal(source, output_elapsed(entry)),
                   :ok <- GenServer.call(owner, {:extension_output_seal, job_ref, proof}),
                   :ok <- Worker.close(worker),
                   true <- output_timely?(entry) do
                {:extension_saved_result, ResultSource.descriptor(source)}
              else
                _ -> invocation_unknown()
              end

            {:ok, response, actions} ->
              with {:ok, event} <-
                     Ipse.Extension.Invocation.build_result(intent, response, actions),
                   :ok <- Worker.close(worker) do
                {:extension_invocation_result, event}
              else
                _ -> invocation_unknown()
              end

            {:question, action} ->
              if Worker.close(worker) == :ok and output_timely?(entry),
                do: {:extension_question, action},
                else: invocation_unknown()

            _ ->
              invocation_unknown()
          end
        else
          _ -> invocation_unknown()
        end
      after
        if Process.alive?(worker), do: Worker.close(worker)
      end
    else
      _ -> invocation_unknown()
    end
  catch
    :exit, _ -> invocation_unknown()
  end

  defp drain_output(worker, source, entry, owner, job_ref) do
    if source.offset == source.begin["byte_count"] do
      {:ok, source}
    else
      with {:ok, request} <- ResultSource.request(source),
           {:ok, reply} <- export_call(worker, entry, "result.output", request),
           {:ok, _event, next} <- ResultSource.push(source, reply),
           :ok <-
             GenServer.call(
               owner,
               {:extension_output_chunk, job_ref, source.begin["output_id"], reply}
             ) do
        drain_output(worker, next, entry, owner, job_ref)
      else
        _ -> {:error, :extension_output_refused}
      end
    end
  end

  defp output_elapsed(entry),
    do: System.monotonic_time(:millisecond) - entry.output_started_ms

  defp output_timely?(entry),
    do:
      not Map.has_key?(entry, :output_started_ms) or
        output_elapsed(entry) in 0..119_999

  defp export_call(worker, entry, stage, payload) do
    remaining =
      if Map.has_key?(entry, :output_started_ms),
        do: 120_000 - output_elapsed(entry),
        else: 5_000

    with true <- remaining > 0,
         {:ok, reply} <- Worker.call(worker, stage, payload, min(5_000, remaining)),
         true <- output_timely?(entry) do
      {:ok, reply}
    else
      _ -> {:error, :extension_deadline_or_callback_failed}
    end
  end

  defp invocation_unknown,
    do:
      {:unknown,
       "Extension outcome unknown after refusal, failure or interruption. Inspect its receipt before retrying; no callback was replayed."}

  defp outer_current(entry, %{"version" => 3} = intent) do
    with {:ok, binding} <-
           Ipse.Extension.SemanticAdmission.outer(
             entry.host_config,
             entry.host_cwd,
             intent["payload"]["session_id"],
             intent["identity"],
             intent["descriptor"]
           ),
         true <- binding === intent["semantic_binding"] do
      :ok
    else
      _ -> {:error, :semantic_outer_denied}
    end
  end

  defp outer_current(_, _), do: :ok

  defp continue(worker, %{"kind" => "host_call"} = response, entry, owner, job_ref, actions) do
    with {:ok, request} <- Actions.proposal(response, entry.identity),
         true <- Actions.allowed?(entry.identity, request, actions),
         true <- output_timely?(entry),
         true <-
           not Map.has_key?(entry, :read_deadline) or
             System.monotonic_time(:millisecond) < entry.read_deadline do
      if Actions.question?(request) do
        GenServer.call(owner, {:extension_action_begin, job_ref, request}, :infinity)
      else
        continue_action(worker, request, entry, owner, job_ref, actions)
      end
    end
  end

  defp continue(_, response, _, _, _, actions), do: {:ok, response, actions}

  defp continue_action(worker, request, entry, owner, job_ref, actions) do
    with {:ok, intent, outcome} <- run_action(owner, job_ref, worker, request),
         {:ok, event} <- Actions.result(intent, outcome),
         {:ok, payload} <- GenServer.call(owner, {:extension_action_commit, job_ref, event}),
         true <- payload["outcome"]["status"] != "unknown",
         {:ok, response} <- export_call(worker, entry, "host.actions", payload) do
      continue(worker, response, entry, owner, job_ref, actions ++ [event])
    else
      _ -> {:error, :extension_action_stopped}
    end
  end

  defp run_action(owner, job_ref, worker, request) do
    with :ok <- tool_context(owner, job_ref, request),
         :ok <- mcp_context(owner, job_ref, request) do
      run_admitted_action(owner, job_ref, worker, request)
    end
  end

  defp run_admitted_action(owner, job_ref, worker, request) do
    case GenServer.call(owner, {:extension_action_begin, job_ref, request}, :infinity) do
      {:ok, intent, context} ->
        outcome =
          case execute_admitted_action(context, worker, intent, request) do
            {:ok, value} -> %{"status" => "ok", "value" => value}
            {:conflict, value} -> %{"status" => "conflict", "value" => value}
            {:failed, value} -> %{"status" => "failed", "value" => value}
            _ -> %{"status" => "unknown", "value" => %{}}
          end

        {:ok, intent, outcome}

      {:denied, intent} ->
        {:ok, intent, %{"status" => "denied", "value" => %{}}}

      _ ->
        {:error, :extension_action_refused}
    end
  end

  defp execute_admitted_action(context, worker, intent, request) do
    if is_nil(context[:output_deadline_ms]) or
         System.monotonic_time(:millisecond) < context.output_deadline_ms,
       do: execute_action(Map.put(context, :worker, worker), intent, request),
       else: :unknown
  end

  defp execute_action(context, intent, %{"op" => "model.complete"}),
    do: Ipse.Extension.ModelCall.execute(context, intent)

  defp execute_action(context, intent, %{"op" => "embedding.create"}),
    do: Ipse.Extension.EmbeddingCall.execute(context, intent)

  defp execute_action(context, intent, %{"op" => "decision.create"}),
    do: Ipse.Extension.DecisionCall.execute(context, intent)

  defp execute_action(context, intent, %{"op" => "collection.call"}),
    do: Ipse.Extension.CollectionCall.execute(context, intent)

  defp execute_action(context, intent, %{"op" => "mcp.call"}),
    do: Ipse.Extension.MCPCall.execute(context, intent)

  defp execute_action(context, intent, %{"op" => "effect.result.read"}),
    do: Ipse.Extension.EffectResult.execute(context, intent)

  defp execute_action(context, _intent, %{"op" => "tool.call"} = request),
    do: Ipse.Extension.ToolAction.execute(request, context)

  defp execute_action(context, intent, %{"op" => "service.call"}),
    do: execute_service(context, intent)

  defp execute_action(context, intent, %{"op" => "context.publish"}),
    do: Ipse.Extension.Context.execute(context, intent)

  defp execute_action(context, _intent, %{"op" => "usage.read"}), do: context.usage_read

  defp execute_action(context, _intent, %{"op" => op})
       when op in ~w(usage.children usage.child.read) do
    task =
      Ipse.Session.Resources.async(fn ->
        Ipse.Extension.ChildUsage.execute(context.child_usage)
      end)

    case Task.yield(task, 5000) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> {:failed, %{"code" => "usage_child_timeout"}}
    end
  end

  defp execute_action(context, intent, %{"op" => "history.read"}) do
    task = Ipse.Session.Resources.async(fn -> Ipse.Extension.History.execute(context, intent) end)

    case Task.yield(task, 5000) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> {:failed, %{"code" => "history_timeout"}}
    end
  end

  defp execute_action(context, intent, %{"op" => op})
       when op in ~w(source.list source.read source.quote),
       do: Ipse.Extension.SourceRead.execute(context, intent)

  defp execute_action(context, intent, request),
    do: State.execute(context.root, intent["namespace"], request, intent["operation_id"])

  defp tool_context(owner, job_ref, %{"op" => "tool.call"} = request) do
    with {:ok, snapshot} <- GenServer.call(owner, {:extension_tool_context, job_ref, request}),
         {:ok, updated} <- nested_context(snapshot, request),
         drift = Ipse.Workspace.drift(updated) do
      GenServer.call(
        owner,
        {:extension_tool_context_commit, job_ref, request, Ipse.JSON.digest([snapshot]), updated,
         drift}
      )
    end
  end

  defp tool_context(_, _, _), do: :ok

  defp mcp_context(owner, ref, %{"op" => "mcp.call"} = request) do
    with {:ok, server, tool_id, cwd, resource} <-
           GenServer.call(owner, {:extension_mcp_prepare, ref, request}),
         {:ok, descriptor, binding} <-
           Ipse.Extension.MCPCall.discover(server, tool_id, request, cwd, resource) do
      GenServer.call(owner, {:extension_mcp_bound, ref, request, descriptor, binding})
    end
  end

  defp mcp_context(_, _, _), do: :ok

  defp nested_context(snapshot, %{"name" => "shell"}), do: {:ok, snapshot}

  defp nested_context(snapshot, request) do
    with {:ok, updated, _} <- Ipse.Workspace.nested(snapshot, request["arguments"]["path"]) do
      {:ok, updated}
    end
  end

  alias Ipse.Extension.{Worker, Services, Catalog}

  defp execute_service(context, intent) do
    entry = context.service_entry

    payload =
      Services.payload(
        intent["request"],
        intent["service"],
        intent["operation_id"],
        intent["parent_invocation_id"],
        context.session_id,
        context.turn_id
      )

    with {:ok, worker} <-
           Worker.start(
             owner: self(),
             store: entry.store,
             digest: entry.identity["artifact"],
             trusted: entry.identity["artifact"],
             artifact_sha256: entry.identity["artifact_sha256"],
             options: entry.options
           ) do
      try do
        with {:ok, _} <- Worker.call(worker, "initialize", entry.options),
             {:ok, response} <- Worker.call(worker, "invoke.service", payload),
             {:ok, value} <- Catalog.validate_response(intent["service"]["descriptor"], response),
             :ok <- Worker.close(worker) do
          {:ok, Services.outcome(intent["service"], intent["operation_id"], value)}
        else
          _ -> {:unknown, %{}}
        end
      after
        if Process.alive?(worker), do: Worker.close(worker)
      end
    else
      _ -> {:unknown, %{}}
    end
  catch
    :exit, _ -> {:unknown, %{}}
  end
end
