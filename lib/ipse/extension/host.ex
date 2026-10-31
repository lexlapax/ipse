defmodule Ipse.Extension.Host do
  @moduledoc "Ordered bounded transform jobs, owned by Session's monitored task chain."
  alias Ipse.Extension.{Registry, Worker, Projection, Actions, State, ResultSource}

  def enabled?(config, stage),
    do: Enum.any?(Map.get(config, :extensions, []), &(stage in &1.identity["capabilities"]))

  # Host-only primitives for the inactive native sharing path. Their results
  # are never returned to an extension worker and do not admit output.
  @doc false
  def begin_session_share(owner, job_ref, intent),
    do: session_share_call(owner, {:session_share_begin, job_ref, intent})

  @doc false
  def begin_controlled_session_share(owner, job_ref, intent),
    do: begin_controlled_session_share(owner, job_ref, intent, :legacy)

  @doc false
  def begin_synthetic_notice_share(owner, job_ref, intent),
    do: begin_controlled_session_share(owner, job_ref, intent, :synthetic_notice)

  @doc false
  def begin_synthetic_review_share(owner, job_ref, intent),
    do: begin_controlled_session_share(owner, job_ref, intent, :synthetic_review)

  @doc false
  def begin_synthetic_source_share(owner, job_ref, intent, proofs),
    do: begin_controlled_session_share(owner, job_ref, intent, {:synthetic_source, proofs})

  @doc false
  def begin_supersession_source_share(owner, job_ref, intent, sha),
    do: begin_controlled_session_share(owner, job_ref, intent, {:supersession_source, sha})

  @doc false
  def begin_synthetic_supersession_review_share(owner, job_ref, intent, sha),
    do:
      begin_controlled_session_share(owner, job_ref, intent, {:supersession_display_fixture, sha})

  @doc false
  def begin_synthetic_accepted_notice_share(owner, job_ref, intent, cutoff \\ nil),
    do:
      begin_controlled_session_share(owner, job_ref, intent, {:synthetic_accepted_notice, cutoff})

  defp begin_controlled_session_share(owner, job_ref, intent, mode) do
    ticket_request =
      case mode do
        :synthetic_notice ->
          {:session_control_ticket_synthetic, job_ref, intent}

        :synthetic_review ->
          {:session_control_ticket_synthetic_review, job_ref, intent}

        {:synthetic_source, proofs} ->
          {:session_control_ticket_source_fixture, job_ref, intent, proofs}

        {:supersession_source, sha} ->
          {:session_control_ticket_supersession, job_ref, intent, sha}

        {:supersession_display_fixture, sha} ->
          {:session_control_ticket_supersession_display_fixture, job_ref, intent, sha}

        {:synthetic_accepted_notice, cutoff} ->
          {:session_control_ticket_synthetic_accepted, job_ref, intent, cutoff}

        :legacy ->
          {:session_control_ticket, job_ref, intent}
      end

    with {:ok, ticket, operation, deadline, _overall} <-
           review_ticket(session_share_call(owner, ticket_request)),
         {:ok, prepared} <-
           Ipse.Runner.prepare_owner_control(job_ref, intent, ticket, operation, deadline),
         {:ok, port} <- Ipse.Runner.open_prepared_owner_control(prepared, self(), job_ref, intent) do
      result =
        with :ok <- await_owner_ready(port, owner, deadline),
             {:ok, _, _, _, _} = result <-
               session_share_call(
                 owner,
                 {:session_share_begin_controlled, job_ref, intent, prepared, port}
               ) do
          result
        else
          _ -> {:error, :cleanup_unconfirmed}
        end

      if not match?({:ok, _, _, _, _}, result), do: Ipse.Runner.close_owner_control(port)
      result
    else
      _ -> {:error, :owner_control_unavailable}
    end
  end

  defp review_ticket({:ok, ticket, operation, deadline}),
    do: {:ok, ticket, operation, deadline, nil}

  defp review_ticket({:ok, _, _, _, _} = result), do: result
  defp review_ticket(other), do: other

  defp await_owner_ready(port, owner, deadline) do
    monitor = Process.monitor(owner)

    try do
      await_owner_ready(port, monitor, deadline, <<>>)
    after
      Process.demonitor(monitor, [:flush])
    end
  end

  defp await_owner_ready(port, monitor, deadline, buffer) do
    case buffer do
      <<?R, 16::32, "owner-control-v1">> ->
        :ok

      _ when byte_size(buffer) > 64 ->
        {:error, :owner_control_unavailable}

      _ ->
        receive do
          {^port, {:data, bytes}} -> await_owner_ready(port, monitor, deadline, buffer <> bytes)
          {^port, {:exit_status, _}} -> {:error, :owner_control_unavailable}
          {:DOWN, ^monitor, :process, _, _} -> {:error, :owner_control_unavailable}
        after
          max(deadline - System.monotonic_time(:millisecond), 0) ->
            {:error, :owner_control_unavailable}
        end
    end
  end

  @doc false
  def configure_session_control(owner, job_ref, capability, recipient, name, secret),
    do:
      session_share_call(
        owner,
        {:session_control_configure, job_ref, capability, recipient, name, secret}
      )

  @doc false
  def session_share_identity(owner, job_ref, capability),
    do: session_share_call(owner, {:session_share_identity, job_ref, capability})

  @doc false
  def session_share_writer_open(owner, job_ref, capability),
    do: session_share_call(owner, {:session_share_writer_open, job_ref, capability})

  @doc false
  def session_share_writer_transfer(owner, job_ref, capability, recipient, name, secret),
    do:
      session_share_call(
        owner,
        {:session_share_writer_transfer, job_ref, capability, recipient, name, secret}
      )

  @doc false
  def session_share_writer_prepare_close(owner, job_ref, capability),
    do: session_share_call(owner, {:session_share_writer_prepare_close, job_ref, capability})

  @doc false
  def prepare_transaction_share_close(owner, job_ref, capability),
    do: session_share_call(owner, {:session_share_transaction_close, job_ref, capability})

  @doc false
  def session_share_writer_close(owner, job_ref, capability),
    do: session_share_call(owner, {:session_share_writer_close, job_ref, capability})

  @doc false
  def spawn_synthetic_notice_terminal(owner, job_ref, capability),
    do: session_share_call(owner, {:session_share_spawn_synthetic_terminal, job_ref, capability})

  @doc false
  def send_synthetic_review_manifest(owner, job_ref, capability, prefix),
    do:
      session_share_call(
        owner,
        {:session_share_synthetic_review_manifest, job_ref, capability, prefix}
      )

  @doc false
  def prepare_terminal_share_close(owner, job_ref, capability, port),
    do: session_share_call(owner, {:session_share_terminal_close, job_ref, capability, port})

  @doc false
  def abort_controlled_session_share(owner, job_ref, capability, host_port) do
    with :ok <- Ipse.Runner.close_owner_control(host_port),
         do: abort_session_share(owner, job_ref, capability)
  end

  @doc false
  def finish_controlled_session_share(owner, job_ref, capability, host_port) do
    with :ok <- Ipse.Runner.close_owner_control(host_port),
         do: finish_session_share(owner, job_ref, capability)
  end

  @doc false
  def export_session_share(owner, job_ref, capability, recipient),
    do: session_share_call(owner, {:session_share_export, job_ref, capability, recipient})

  @doc false
  def settle_session_share(owner, job_ref, capability),
    do: session_share_call(owner, {:session_share_settle, job_ref, capability})

  @doc false
  def thaw_synthetic_review(owner, job_ref, capability, port),
    do: session_share_call(owner, {:session_share_review_thaw, job_ref, capability, port})

  @doc false
  def finish_session_share(owner, job_ref, capability),
    do: session_share_call(owner, {:session_share_finish, job_ref, capability})

  @doc false
  def abort_session_share(owner, job_ref, capability),
    do: session_share_call(owner, {:session_share_abort, job_ref, capability})

  defp session_share_call(owner, message) when is_pid(owner) do
    GenServer.call(owner, message, 6_000)
  catch
    :exit, _ -> {:error, :cleanup_unconfirmed}
  end

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

  def notify_events(plans, owner, ref, context \\ nil) do
    Enum.reduce_while(plans, :ok, fn plan, :ok ->
      admission =
        GenServer.call(
          owner,
          {:extension_event_begin, ref, plan.instance, plan.declaration["id"],
           event_outer(context, plan)}
        )

      case admission do
        {:job, intent, entry, parent} ->
          case execute_export(entry, parent, "event.job", parent["payload"], owner, ref, []) do
            {:extension_released, id} ->
              case GenServer.call(owner, {:managed_output_event_complete, ref, id}) do
                {:ok, "completed"} ->
                  {:cont, :ok}

                {:ok, "failed"} ->
                  if not plan.declaration["required"],
                    do: {:cont, :ok},
                    else: {:halt, {:error, "Required managed event output was withheld."}}

                _ ->
                  {:halt,
                   {:error, "Managed event output could not be released; inspect its receipts."}}
              end

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

  defp event_outer(nil, _), do: {:ok, nil}

  defp event_outer(context, plan) do
    admission = context.config[:semantic_admission]

    if plan.declaration["mode"] == "job" and is_map(admission) and is_map(admission["pin"]) and
         admission["instance"] == plan.instance do
      name = "ext__" <> plan.instance <> "__" <> plan.declaration["handler"]

      with {:ok, entry, descriptor} <-
             Ipse.Extension.Catalog.lookup(context.config, "event.job", name),
           do:
             Ipse.Extension.SemanticAdmission.outer(
               context.config,
               context.cwd,
               context.session_id,
               entry.identity,
               descriptor
             )
    else
      {:ok, nil}
    end
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
            {:supersession, delivery} ->
              if Worker.close(worker) == :ok,
                do: {:managed_supersession_finished, delivery},
                else: invocation_unknown()

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
                case Ipse.Session.ManagedOutput.release(
                       owner,
                       job_ref,
                       :saved,
                       ResultSource.descriptor(source)
                     ) do
                  {:ordinary, delivery} -> {:extension_saved_result, delivery}
                  result -> result
                end
              else
                _ -> invocation_unknown()
              end

            {:ok, response, actions} ->
              with {:ok, event} <-
                     Ipse.Extension.Invocation.build_result(intent, response, actions),
                   :ok <- Worker.close(worker) do
                case Ipse.Session.ManagedOutput.release(owner, job_ref, :inline, event) do
                  {:ordinary, event} -> {:extension_invocation_result, event}
                  result -> result
                end
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
    case run_action(owner, job_ref, worker, request) do
      {:supersession, intent, delivery} ->
        with {:ok, event} <-
               Actions.result(intent, %{
                 "status" => "failed",
                 "value" => %{"code" => "collection_policy_refused"}
               }),
             {:ok, _} <- GenServer.call(owner, {:extension_action_commit, job_ref, event}) do
          {:supersession, delivery}
        else
          _ -> {:error, :extension_action_stopped}
        end

      result ->
        continue_ordinary_action(result, worker, entry, owner, job_ref, actions)
    end
  end

  defp continue_ordinary_action(result, worker, entry, owner, job_ref, actions) do
    with {:ok, intent, outcome} <- result,
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
         :ok <- document_context(owner, job_ref, request),
         :ok <- document_embedding_context(owner, job_ref, request),
         :ok <- mcp_context(owner, job_ref, request) do
      run_admitted_action(owner, job_ref, worker, request)
    end
  end

  defp run_admitted_action(owner, job_ref, worker, request) do
    case GenServer.call(owner, {:extension_action_begin, job_ref, request}, :infinity) do
      {:ok, intent, context} ->
        case execute_admitted_action(context, worker, intent, request) do
          {:supersession, delivery} ->
            {:supersession, intent, delivery}

          result ->
            outcome =
              case result do
                {:ok, value} -> %{"status" => "ok", "value" => value}
                {:conflict, value} -> %{"status" => "conflict", "value" => value}
                {:failed, value} -> %{"status" => "failed", "value" => value}
                _ -> %{"status" => "unknown", "value" => %{}}
              end

            {:ok, intent, outcome}
        end

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

  defp execute_action(_context, intent, %{"op" => "embedding.profile"}),
    do: {:ok, Ipse.Extension.EmbeddingCall.profile_value(intent["effect_binding"])}

  defp execute_action(context, intent, %{"op" => "decision.create"}),
    do: Ipse.Extension.DecisionCall.execute(context, intent)

  defp execute_action(context, intent, %{"op" => "collection.call"}),
    do: Ipse.Extension.CollectionCall.execute(context, intent)

  defp execute_action(context, intent, %{"op" => "collection.store"}),
    do: Ipse.Extension.CollectionStore.execute(context, intent)

  defp execute_action(context, intent, %{"op" => "collection.managed"}),
    do: Ipse.Extension.ManagedCollectionCall.execute(context, intent)

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

  defp execute_action(context, _, %{"op" => "context.available"}),
    do:
      {:ok,
       Ipse.Extension.Context.available(
         context.contributions,
         context.identity["instance"],
         context.reference_layout
       )}

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
    key = {__MODULE__, :history_policy}
    cached = Process.get(key)

    task =
      Ipse.Session.Resources.async(fn ->
        Ipse.Extension.History.execute_cached(context, intent, cached)
      end)

    case Task.yield(task, 5000) || Task.shutdown(task, :brutal_kill) do
      {:ok, {result, cache}} ->
        Process.put(key, cache)
        result

      _ ->
        {:failed, %{"code" => "history_timeout"}}
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

  defp document_context(owner, ref, %{"op" => "collection.store"} = request) do
    with {:ok, home, cwd, identity, session_id} <-
           GenServer.call(owner, {:extension_document_prepare, ref, request}),
         {:ok, binding} <-
           Ipse.Extension.CollectionStore.prepare(home, cwd, identity, request, session_id) do
      GenServer.call(owner, {:extension_document_bound, ref, request, binding})
    end
  end

  defp document_context(_, _, _), do: :ok

  defp document_embedding_context(owner, ref, %{"op" => "embedding.create"} = request) do
    case GenServer.call(owner, {:extension_document_embedding_prepare, ref, request}) do
      :ordinary ->
        :ok

      {:ok, home, cwd, identity, session_id} ->
        with {:ok, binding} <-
               Ipse.Extension.CollectionStore.prepare_source(
                 home,
                 cwd,
                 identity,
                 request,
                 session_id
               ) do
          GenServer.call(owner, {:extension_document_embedding_bound, ref, request, binding})
        end

      _ ->
        {:error, :document_source_use_refused}
    end
  end

  defp document_embedding_context(_, _, _), do: :ok

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
