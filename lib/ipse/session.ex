defmodule Ipse.Session do
  alias Ipse.Session.Turn

  @moduledoc "One supervised owner per agent conversation. I/O runs in monitored tasks."

  use GenServer

  alias Ipse.Journal
  alias Ipse.Workspace
  alias Ipse.Tools
  alias Ipse.Tools.Questions

  alias Ipse.Journal.Writer

  alias Ipse.Session.Saved

  alias Ipse.Session.Invocation, as: CurrentInvocation

  @synthetic_review_text "Synthetic grouped review.\nType pin 0123456789abcdef to confirm, or anything else to cancel.\n> "

  alias Ipse.Extension.{
    Projection,
    Catalog,
    Invocation,
    ModelCall,
    EmbeddingCall,
    DecisionCall,
    Subscriptions,
    Feeds,
    FeedChannel,
    ResultSource
  }

  def start_link(opts), do: start_session(opts, :legacy)

  @doc false
  # Inactive experiment; same-VM callers are trusted, not access-controlled.
  # No CLI, config, or worker option selects this path.
  def start_export_candidate_link(opts), do: start_session(opts, :export_v1)

  @doc false
  # Host-only candidate; no CLI, configuration, or worker selector exposes it.
  def start_share_candidate_link(opts), do: start_session(opts, :share_candidate_v2)

  defp start_session(opts, lock_mode) do
    config = Keyword.fetch!(opts, :config)
    init_arg = if lock_mode == :legacy, do: opts, else: {lock_mode, opts}

    cond do
      not Ipse.Extension.Registry.valid_entries?(config) ->
        {:error, :invalid_extension_configuration}

      Ipse.Observability.runtime(config) != :ok ->
        {:error, :invalid_observability_policy}

      Map.get(config, :extensions, []) == [] ->
        GenServer.start_link(__MODULE__, init_arg)

      true ->
        task = owned_task(fn -> Ipse.Extension.Registry.revalidate(config) end)

        result = Task.yield(task, 5_000) || Task.shutdown(task, :brutal_kill)
        Ipse.Session.Resources.close_task(task.pid)

        case result do
          {:ok, :ok} -> GenServer.start_link(__MODULE__, init_arg)
          _ -> {:error, :extension_admission_refused}
        end
    end
  end

  def child_spec(opts),
    do: %{id: make_ref(), start: {__MODULE__, :start_link, [opts]}, restart: :temporary}

  def prompt(pid, text), do: GenServer.call(pid, {:prompt, text})
  @doc false
  def start_draft(pid, text), do: GenServer.call(pid, {:start_draft, text})
  @doc false
  def start_draft_observed(pid, channel, text, ticket),
    do: GenServer.call(pid, {:start_draft_observed, channel, text, ticket})

  @doc false
  def cancel_draft(pid), do: GenServer.call(pid, :cancel_draft, 10_000)
  @doc false
  def rebase_draft(pid), do: GenServer.call(pid, :rebase_draft, 10_000)

  @doc false
  def rebase_for_extensions(%{draft: nil} = s), do: {:ok, s}

  def rebase_for_extensions(s) do
    with {:ok, event, projected} <-
           Ipse.Session.Draft.rebased(
             s.draft,
             s.messages,
             s.reference_occurrences,
             Ipse.Session.DraftNative.policy(s.config)
           ) do
      record(s, event)
      s = managed_event(s, event, projected)
      {:ok, %{s | draft: nil, messages: projected}}
    end
  end

  @doc false
  def draft(pid), do: GenServer.call(pid, :draft)
  @doc false
  def render_draft(pid, channel, id, revision),
    do: GenServer.call(pid, {:render_draft, channel, id, revision})

  @doc false
  def accept_draft_observed(pid, channel, render_id, text, witness),
    do: GenServer.call(pid, {:accept_draft_observed, channel, render_id, text, witness})

  @doc false
  def prepare_assertion(pid, channel, text, ticket),
    do: GenServer.call(pid, {:prepare_assertion, channel, text, ticket})

  @doc false
  def accept_assertion_observed(pid, channel, render_id, text, witness),
    do: GenServer.call(pid, {:accept_assertion_observed, channel, render_id, text, witness})

  @doc false
  def prepare_planning_decision(pid, channel, command, ticket),
    do: GenServer.call(pid, {:prepare_planning_decision, channel, command, ticket})

  @doc false
  def accept_planning_decision(pid, channel, render_id, text, witness),
    do: GenServer.call(pid, {:accept_planning_decision, channel, render_id, text, witness})

  @doc false
  def prepare_planning_save(pid, channel, command, ticket),
    do: GenServer.call(pid, {:prepare_planning_save, channel, command, ticket})

  @doc false
  def replace_draft(pid, id, revision, text),
    do: GenServer.call(pid, {:replace_draft, id, revision, text})

  @doc false
  def replace_draft_observed(pid, channel, id, revision, text, ticket),
    do: GenServer.call(pid, {:replace_draft_observed, channel, id, revision, text, ticket})

  @doc false
  def replace_draft_command_observed(pid, channel, id, revision, command, ticket),
    do:
      GenServer.call(
        pid,
        {:replace_draft_command_observed, channel, id, revision, command, ticket}
      )

  @doc false
  def replace_draft_lines_observed(pid, channel, id, revision, lines),
    do: GenServer.call(pid, {:replace_draft_lines_observed, channel, id, revision, lines})

  @doc false
  def accept_draft(pid, id, revision), do: GenServer.call(pid, {:accept_draft, id, revision})
  @doc false
  def consume_draft(pid, id, revision), do: GenServer.call(pid, {:consume_draft, id, revision})
  @doc "Submit exact observed text with a volatile, single-use input witness."
  def prompt(pid, text, witness), do: GenServer.call(pid, {:prompt, text, witness})

  @doc "Observe one native terminal input for the current idle Session generation."
  def observe_input(pid, display, timeout \\ 120_000) do
    with true <- is_integer(timeout) and timeout in 1000..600_000,
         {:ok, lease} <- GenServer.call(pid, {:observe_input, display, timeout}) do
      Ipse.Session.Input.await(lease, timeout)
    else
      false -> {:error, :operator_input_unavailable}
      error -> error
    end
  catch
    :exit, _ -> {:error, :operator_input_unavailable}
  end

  def approve(pid, ref, allowed), do: GenServer.call(pid, {:approve, ref, allowed})
  def permissions(pid), do: GenServer.call(pid, :permissions)
  def clear_permissions(pid), do: GenServer.call(pid, :clear_permissions)
  def answer(pid, id, answers), do: GenServer.call(pid, {:answer, id, answers})
  @doc false
  def open_input_channel(pid, reader), do: GenServer.call(pid, {:open_input_channel, reader})
  @doc false
  def observe_channel(pid, channel, request, timeout \\ 120_000) do
    with {:ok, lease} <- GenServer.call(pid, {:observe_channel, channel, request, timeout}) do
      Ipse.Session.Input.await(lease, timeout)
    end
  end

  @doc false
  def cancel_input_read(pid, channel), do: GenServer.call(pid, {:cancel_input_read, channel})
  @doc false
  def stage_input(pid, channel, text, witness),
    do: GenServer.call(pid, {:stage_input, channel, text, witness})

  @doc false
  def enter_planning_observed(pid, channel, ticket),
    do: GenServer.call(pid, {:enter_planning_observed, channel, ticket}, 15_000)

  @doc false
  def exit_planning_observed(pid, channel, ticket),
    do: GenServer.call(pid, {:exit_planning_observed, channel, ticket}, 15_000)

  @doc false
  def discard_input(pid, channel, witness),
    do: GenServer.call(pid, {:discard_input, channel, witness})

  @doc false
  def render_question(pid, channel, item),
    do: GenServer.call(pid, {:render_question, channel, item})

  @doc false
  def answer_observed(pid, channel, render, text, witness),
    do: GenServer.call(pid, {:answer_observed, channel, render, text, witness})

  @doc false
  def question_eof(pid, channel), do: GenServer.call(pid, {:question_eof, channel}, 10_000)

  @doc "Read only this subscribed client's admitted source window; tokens grant no authority."
  def sources(pid, operation, request),
    do: GenServer.call(pid, {:session_sources, operation, request})

  @doc false
  def source_snapshot(s) do
    case Writer.source_query(s.journal_writer, :snapshot) do
      {:ok, snapshot} -> snapshot
      _ -> %{"version" => 1, "available" => false}
    end
  end

  @doc false
  def managed_event(s, event, messages \\ nil) do
    messages = messages || s.messages

    case Ipse.Session.ManagedLineage.advance(s.managed_lineage, event, s.messages, messages) do
      {:ok, lineage} -> %{s | managed_lineage: lineage}
      _ -> %{s | managed_lineage: {:error, :managed_lineage_unavailable}}
    end
  end

  @doc false
  def managed_dependencies(s, "extension.result"), do: Ipse.Session.ManagedOutput.snapshot(s)
  def managed_dependencies(s, "extension.input"), do: Ipse.Session.WorkerInput.snapshot(s)
  def managed_dependencies(s, "tool.effect"), do: Ipse.Session.ManagedToolUse.snapshot(s)
  def managed_dependencies(s, "tool.result"), do: Ipse.Session.ManagedToolUse.result_snapshot(s)
  def managed_dependencies(s, "tool.approval"), do: Ipse.Session.ManagedApproval.snapshot(s)

  def managed_dependencies(s, phase) do
    with {:ok, dependencies} <-
           Ipse.Session.ManagedLineage.dependencies(s.managed_lineage, s.messages),
         {:ok, input, extra, plan} <- managed_input(s, phase),
         {:ok, dependencies} <- Ipse.Session.ManagedReference.union([dependencies, extra]) do
      {:ok,
       %{
         dependencies: dependencies,
         input_sha256: Ipse.JSON.digest([input]),
         sha256: Ipse.JSON.digest([phase, input, dependencies]),
         plan: plan
       }}
    else
      _ -> {:error, :managed_lineage_unavailable}
    end
  rescue
    _ -> {:error, :managed_lineage_unavailable}
  end

  @doc false
  def managed_empty?(s) do
    managed_input_dependencies(s) == {:ok, []}
  end

  defp managed_input_dependencies(s) do
    with {:ok, active} <- Ipse.Session.ManagedLineage.dependencies(s.managed_lineage, s.messages),
         {:ok, inherited} <-
           Ipse.Session.ManagedLineage.invocation_dependencies(
             s.managed_lineage,
             if(s.invocation.parent, do: s.invocation.parent["invocation_id"])
           ),
         {:ok, dependencies} <-
           Ipse.Session.ManagedReference.union([active, inherited, s.invocation.managed_reads]) do
      {:ok, dependencies}
    else
      _ -> {:error, :managed_lineage_unavailable}
    end
  rescue
    _ -> {:error, :managed_lineage_unavailable}
  end

  # Root-only observations contain no selected note bytes. Their committed
  # classification does not replace the capture's independent current-use and
  # publication barriers.
  @doc false
  def post_reply_capture_inputs?(s) do
    case managed_input_dependencies(s) do
      {:ok, []} -> true
      {:ok, dependencies} -> Ipse.Session.ManagedToolUse.root_only?(s, dependencies)
      _ -> false
    end
  end

  # The ordinary reply has completed and its original source is durable before
  # this host-owned capture begins. Its result selects a candidate for a later,
  # independent native review; it never accepts or publishes that candidate.
  @doc false
  def start_post_reply_capture(s, :ok) do
    attempts = Map.get(s, :post_reply_capture_attempts, %{})
    answer_key = {s.turn_id, s.last_request_id}

    if Map.has_key?(attempts, answer_key) or
         not is_map(Map.get(s, :pending_nomination)) do
      if Map.get(s, :pending_nomination) in [:conflicted, :unavailable],
        do: notify(s, {:decision_card_unavailable, :post_reply_review_unavailable})

      :skip
    else
      with %{event: nomination, arguments: arguments} <- s.pending_nomination,
           true <- Ipse.Session.PendingNomination.arguments?(arguments),
           nil <- s.draft,
           nil <- s.text_stream,
           true <- post_reply_capture_inputs?(s),
           false <- Ipse.Extension.Host.enabled?(s.config, "transform.presentation"),
           [] <- Ipse.Extension.Subscriptions.declarations(s.config, "after_turn"),
           {:ok, mode} <- Ipse.Extension.Mode.capture(s.config),
           false <- mode["headless"],
           :ok <- Ipse.Extension.Mode.knowledge(mode, "collection.publish"),
           %{client: client, reader: reader} <- s.operator_channel,
           true <- Process.alive?(client) and Process.alive?(reader),
           {:ok, request} <-
             Writer.source_query(
               s.journal_writer,
               {:answer_request, s.turn_id, s.last_request_id, arguments["text"]}
             ),
           {:ok, %{"proof" => proof}} <- Writer.source_query(s.journal_writer, {:proof, request}),
           true <-
             proof["kind"] === "answer.original" and
               proof["origin"] === "assistant_proposal" and
               proof["content_sha256"] === Ipse.JSON.sha256(s.final),
           true <- map_size(attempts) < Ipse.Extension.Invocation.limit(),
           {:ok, attempt} <-
             Ipse.Session.PendingNomination.capture_attempt(
               s.id,
               s.turn_id,
               s.last_request_id,
               nomination,
               proof
             ) do
        record(s, attempt)

        next =
          s
          |> Map.put(
            :post_reply_capture_attempts,
            Map.put(attempts, answer_key, attempt["capture_attempt_id"])
          )
          |> Map.put(:post_reply_answer_recorded, {s.turn_id, s.last_request_id})
          |> Map.put(:post_reply_capture, %{proof: proof})

        capture = %{
          "text" => arguments["text"],
          "category" => arguments["category"],
          "reason" => arguments["reason"],
          "event_at_ms" => nil,
          "source" => request
        }

        case CurrentInvocation.invoke_export(next, :command, "ext__knowledge__capture", capture) do
          {:reply, :ok, started} ->
            {:ok, started}

          _ ->
            notify(next, {:decision_card_unavailable, :post_reply_review_unavailable})
            {:ok, Turn.finish(next, :ok)}
        end
      else
        _ ->
          notify(s, {:decision_card_unavailable, :post_reply_review_unavailable})
          :skip
      end
    end
  end

  def start_post_reply_capture(_, _), do: :skip

  @doc false
  def ready_chat_review(s, event) do
    source = record_source(s, event)
    binding = %{"event" => event, "source" => source}
    token = make_ref()

    next =
      Map.put(s, :pending_chat_review, %{
        state: :ready,
        token: token,
        event: binding,
        input_generation: s.input_generation
      })

    notify(next, {:pending_chat_review, token})
    next
  end

  defp chat_review_current?(s, pending) do
    event = pending.event["event"]

    with true <- pending.input_generation === s.input_generation,
         true <-
           event["session_id"] === s.id and chat_review_focus_current?(s, pending),
         %{id: channel, generation: generation, client: client} <- s.operator_channel,
         true <-
           Process.alive?(client) and
             Ipse.Session.ChatReviewHandoff.client_id(pending.event) === channel and
             Ipse.Session.ChatReviewHandoff.client_generation(pending.event) === generation,
         nil <- s.draft,
         {:ok, mode} <- Ipse.Extension.Mode.capture(s.config),
         false <- mode["headless"],
         :ok <- Ipse.Extension.Mode.knowledge(mode, "collection.publish"),
         admission = s.config[:semantic_admission],
         true <-
           Ipse.Extension.SemanticAdmission.valid?(admission, s.id) and
             admission["pin"] === event["pin"] do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp chat_review_focus_current?(s, %{focus: focus, event: %{"version" => 2, "review" => review}}),
       do:
         focus.turn === s.turn_id and focus.request === s.last_request_id and
           focus.id === review["focus_id"]

  defp chat_review_focus_current?(s, %{event: %{"event" => event}}),
    do: event["turn_id"] === s.turn_id and event["request_id"] === s.last_request_id

  defp reoffer_snapshot_current?(s, snapshot, client, channel) do
    with %{id: ^channel, client: ^client, reader: reader, generation: generation} <-
           s.operator_channel,
         true <- Process.alive?(client) and Process.alive?(reader),
         true <- snapshot.channel === channel and snapshot.generation === generation,
         true <- snapshot.input_generation === s.input_generation,
         true <- snapshot.turn === s.turn_id and snapshot.request === s.last_request_id,
         {:ok, mode} <- Ipse.Extension.Mode.capture(s.config),
         true <- mode === snapshot.mode and Ipse.Extension.Mode.nomination(mode) === :ok,
         true <- Ipse.Extension.SemanticAdmission.valid?(s.config[:semantic_admission], s.id) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc false
  def managed_preflight(owner, job, phase) do
    case GenServer.call(owner, {:managed_preflight_begin, job, phase}, 5_000) do
      {:ok, :empty, view} ->
        {:ok, view}

      {:ok, context, dependencies, intent, candidate} ->
        verdicts = Ipse.Session.ManagedUse.verdicts(context, dependencies)

        result =
          if is_map(candidate) and Enum.any?(verdicts, &(&1["status"] != "eligible")) do
            case candidate do
              %{management: selected} ->
                if management_root_verdicts?(dependencies, verdicts) do
                  case Ipse.Session.ManagedUse.management_root_transition_observation(
                         context,
                         dependencies,
                         selected
                       ) do
                    {:ok,
                     %{observation: observation, inspected: inspection, management: management}} ->
                      {:management_root_transition, observation, inspection,
                       Map.new(management, fn {key, value} -> {Atom.to_string(key), value} end)}

                    _ ->
                      verdicts
                  end
                else
                  verdicts
                end

              _ ->
                case Ipse.Session.ManagedUse.root_transition_observation(
                       context,
                       dependencies,
                       candidate
                     ) do
                  {:ok, %{observation: observation, inspected: inspection}} ->
                    {:root_transition, observation, inspection}

                  _ ->
                    verdicts
                end
            end
          else
            verdicts
          end

        GenServer.call(
          owner,
          {:managed_preflight_commit, job, intent["intent_id"], result},
          5_000
        )

      _ ->
        {:error, :managed_reference_projection_unsafe}
    end
  catch
    :exit, _ -> {:error, :managed_reference_projection_unsafe}
  end

  @doc false
  def management_root_verdicts?(dependencies, verdicts) do
    by_id = Map.new(verdicts, &{&1["dependency_sha256"], &1})
    now = System.system_time(:millisecond)

    length(verdicts) === map_size(by_id) and length(verdicts) === length(dependencies) and
      Enum.all?(dependencies, fn dependency ->
        verdict = by_id[Ipse.JSON.digest([dependency])]

        is_map(verdict) and
          (dependency["version"] === 3 or
             (verdict["status"] === "eligible" and
                Ipse.Session.ManagedReference.current?(dependency, verdict["current"], now)))
      end)
  rescue
    _ -> false
  end

  defp managed_preflight_view(s, phase) do
    with {:ok, snapshot} <- managed_dependencies(s, phase),
         {:ok, runtime, input, tools, admission} <- managed_dispatch_view(s, phase),
         {:ok, %{route: route}} <-
           Ipse.InferenceDispatch.selection(
             s.config,
             runtime,
             Ipse.Session.InferenceDispatch.operation(phase),
             Ipse.Session.InferenceDispatch.profile(phase, admission)
           ) do
      {:ok, snapshot, runtime, input, tools, admission, route}
    else
      _ -> {:error, :managed_reference_projection_unsafe}
    end
  end

  defp managed_dispatch_view(s, phase) when phase in ["model", "compaction"],
    do: Ipse.Session.Turn.dispatch_view(s, phase)

  defp managed_dispatch_view(s, phase), do: Ipse.Session.Invocation.dispatch_view(s, phase)

  defp managed_worker?(s, caller) do
    s.task != nil and
      (caller == s.task.pid or Ipse.Session.Resources.authorized_effect?(s.task.pid, caller))
  end

  defp managed_preflight_start(s, caller, phase) do
    with true <- managed_worker?(s, caller),
         {:ok, snapshot, runtime, input, tools, admission, route} <-
           managed_preflight_view(s, phase) do
      if snapshot.dependencies == [] do
        dispatch =
          Ipse.Session.InferenceDispatch.prepare(s, runtime, input, tools, phase, admission)

        {:reply, {:ok, :empty, {runtime, input, tools, dispatch}}, s}
      else
        now = System.system_time(:millisecond)
        source = source_snapshot(s)

        intent = %{
          "type" => "managed_preflight_intent",
          "version" => 1,
          "intent_id" => Ipse.Usage.id(),
          "session_id" => s.id,
          "turn_id" => admission["turn_id"],
          "request_id" => admission["request_id"],
          "phase" => phase,
          "admission_sha256" => Ipse.JSON.digest([admission]),
          "input_sha256" => Ipse.JSON.digest([input]),
          "tools_sha256" => Ipse.JSON.digest([tools]),
          "snapshot_sha256" => snapshot.sha256,
          "before_sha256" => Ipse.JSON.digest(s.messages),
          "dependencies_sha256" => Ipse.JSON.digest(snapshot.dependencies),
          "route_sha256" => Ipse.JSON.digest([route]),
          "source_generation" => source["generation"] || 0,
          "policy_generation" => get_in(s.config, [:semantic_admission, "pin", "epoch"]) || 0,
          "checked_at_ms" => now,
          "deadline_ms" => now + 120_000
        }

        with {:ok, lineage} <-
               Ipse.Session.ManagedLineage.advance(
                 s.managed_lineage,
                 intent,
                 s.messages,
                 s.messages
               ),
             true <- is_map(lineage) and not lineage.unavailable do
          record(s, intent)

          context = %{
            config: s.config,
            cwd: s.cwd,
            session_id: s.id,
            history_dir: s.dir,
            owner: self(),
            job_ref: s.job_ref,
            source_binding: {:snapshot, phase, snapshot.sha256}
          }

          candidate =
            case if(phase == "model",
                   do:
                     Ipse.Session.ManagedLineage.root_projection_candidate(
                       lineage,
                       snapshot.dependencies
                     ),
                   else:
                     Ipse.Session.ManagedLineage.root_candidate(lineage, snapshot.dependencies)
                 ) do
              {:ok, action} ->
                action

              _ ->
                if phase == "model" do
                  case Ipse.Session.ManagedLineage.management_root_candidate(
                         lineage,
                         snapshot.dependencies
                       ) do
                    {:ok, selected} -> %{management: selected}
                    _ -> nil
                  end
                end
            end

          {:reply, {:ok, context, snapshot.dependencies, intent, candidate},
           %{s | managed_lineage: lineage}}
        else
          _ -> {:reply, {:error, :managed_reference_projection_unsafe}, s}
        end
      end
    else
      _ -> {:reply, {:error, :managed_reference_projection_unsafe}, s}
    end
  end

  defp managed_preflight_finish(s, caller, id, verdicts) do
    with true <- managed_worker?(s, caller),
         intent when is_map(intent) <- s.managed_lineage.preflight,
         true <-
           intent["intent_id"] == id and System.system_time(:millisecond) <= intent["deadline_ms"],
         phase = intent["phase"],
         {:ok, snapshot, _, input, tools, admission, route} <- managed_preflight_view(s, phase),
         true <-
           snapshot.sha256 == intent["snapshot_sha256"] and
             Ipse.JSON.digest([input]) == intent["input_sha256"] and
             Ipse.JSON.digest([tools]) == intent["tools_sha256"] and
             Ipse.JSON.digest([admission]) == intent["admission_sha256"] and
             Ipse.JSON.digest([route]) == intent["route_sha256"],
         binding = Ipse.Session.ManagedLineage.preflight_binding(intent),
         {:ok, projection} <-
           managed_projection(s, snapshot, verdicts, binding, phase),
         event = %{
           "type" => "managed_preflight_result",
           "version" => 1,
           "intent_id" => id,
           "projection" => projection,
           "verdicts" => if(projection, do: nil, else: verdicts)
         },
         {:ok, messages, lineage} <-
           Ipse.Session.ManagedLineage.replay_projection(s.managed_lineage, event, s.messages),
         next = %{s | messages: messages, managed_lineage: lineage},
         {:ok, _, runtime, input, tools, admission, _} <- managed_preflight_view(next, phase) do
      record(s, event)

      dispatch =
        Ipse.Session.InferenceDispatch.prepare(next, runtime, input, tools, phase, admission)

      {:reply, {:ok, {runtime, input, tools, dispatch}}, next}
    else
      _ -> managed_preflight_refused(s, caller, id)
    end
  rescue
    _ -> managed_preflight_refused(s, caller, id)
  end

  defp managed_preflight_refused(s, caller, id) do
    next =
      if managed_worker?(s, caller) and is_map(s.managed_lineage) and
           is_map(s.managed_lineage.preflight) and s.managed_lineage.preflight["intent_id"] == id do
        event = %{"type" => "managed_preflight_refused", "version" => 1, "intent_id" => id}
        record(s, event)
        managed_event(s, event)
      else
        s
      end

    {:reply, {:error, :managed_reference_projection_unsafe}, next}
  end

  defp managed_projection(s, _, {:root_transition, observation, inspection}, binding, "model") do
    with {:ok, event, _, _, _} <-
           Ipse.Session.ManagedLineage.root_projection(
             s.managed_lineage,
             s.messages,
             binding,
             observation,
             inspection
           ),
         do: {:ok, event},
         else: (_ -> {:error, :managed_reference_projection_unsafe})
  end

  defp managed_projection(
         s,
         _,
         {:management_root_transition, observation, inspection, management},
         binding,
         "model"
       ) do
    with {:ok, event, _, _, _} <-
           Ipse.Session.ManagedLineage.management_root_projection(
             s.managed_lineage,
             s.messages,
             binding,
             observation,
             inspection,
             management
           ),
         do: {:ok, event},
         else: (_ -> {:error, :managed_reference_projection_unsafe})
  end

  defp managed_projection(s, snapshot, verdicts, binding, phase)
       when phase in ["model", "compaction"] do
    with {:ok, event, _, _} <-
           Ipse.Session.ManagedReference.project(
             snapshot.plan,
             verdicts,
             binding,
             s.managed_lineage.write_facts
           ),
         true <- is_map(event),
         do: {:ok, event},
         else: (_ -> {:error, :managed_reference_projection_unsafe})
  end

  defp managed_projection(_, snapshot, verdicts, binding, _) do
    with {:ok, _} <-
           Ipse.Session.ManagedReference.refresh(snapshot.dependencies, verdicts, binding),
         do: {:ok, nil},
         else: (_ -> {:error, :managed_reference_projection_unsafe})
  end

  defp managed_input(s, phase) when phase in ["model", "compaction"] do
    with {:ok, plan} <-
           Ipse.Session.ManagedReference.plan(s.managed_lineage.reference, s.messages),
         {:ok, messages} <-
           Ipse.Session.Draft.project(
             s.draft,
             s.messages,
             s.reference_occurrences,
             Ipse.Session.DraftNative.policy(s.config)
           ) do
      input =
        if phase == "compaction",
          do: s.compaction.summary_messages,
          else: Ipse.Session.Context.header(s) ++ messages

      {:ok, input, [], plan}
    end
  end

  defp managed_input(s, phase) do
    with {:ok, _, input, _, _} <- Ipse.Session.Invocation.dispatch_view(s, phase),
         {:ok, inherited} <-
           Ipse.Session.ManagedLineage.invocation_dependencies(
             s.managed_lineage,
             s.invocation.parent["invocation_id"]
           ),
         {:ok, dependencies} <-
           Ipse.Session.ManagedReference.union([inherited, s.invocation.managed_reads]) do
      {:ok, input, dependencies, nil}
    end
  end

  def cancel(pid), do: GenServer.call(pid, :cancel, 10_000)
  def materialize_result(pid, delivery), do: ResultSource.materialize_session(pid, delivery)
  def read_saved_result(pid, request), do: ResultSource.read_session(pid, request)

  def close(pid), do: close(pid, false)

  @doc "Require the owned session's actual cleanup acknowledgment as well as process exit."

  def close_confirmed(pid), do: close(pid, true)

  defp close(pid, require_ack) do
    monitor = Process.monitor(pid)
    drain_observations(pid, System.monotonic_time(:millisecond) + 500)

    result =
      try do
        GenServer.call(pid, :close, 5_000)
      catch
        :exit, _ ->
          if require_ack or Process.alive?(pid), do: {:error, :cleanup_unconfirmed}, else: :ok
      end

    result =
      receive do
        {:DOWN, ^monitor, :process, ^pid, _} -> result
      after
        1_000 -> {:error, :cleanup_unconfirmed}
      end

    Process.demonitor(monitor, [:flush])
    result
  end

  defp drain_observations(pid, deadline) do
    try do
      case GenServer.call(pid, :observation_drain_state, 500) do
        %{idle: idle, capture: capture} ->
          if idle and capture["mode"] != "off" and
               Enum.any?(
                 capture["sinks"],
                 &(&1["closed"] == false and
                     (not &1["ready"] or &1["pending"] > 0))
               ) and
               System.monotonic_time(:millisecond) < deadline do
            Process.sleep(10)
            drain_observations(pid, deadline)
          end

        _ ->
          :ok
      end
    catch
      :exit, _ -> :ok
    end
  end

  def refresh_context(pid), do: GenServer.call(pid, :refresh_context)
  def info(pid), do: GenServer.call(pid, :info)
  @doc false
  def planning_decisions(pid), do: GenServer.call(pid, :planning_decisions)

  defp input_binding(s),
    do: %{session_id: s.id, cwd: s.cwd, generation: s.input_generation}

  defp operator_binding(s, purpose, render),
    do: %{
      session_id: s.id,
      cwd: s.cwd,
      generation: s.operator_channel.generation,
      channel_id: s.operator_channel.id,
      purpose: purpose,
      render_id: render
    }

  defp operator_request(s, %{"kind" => "question", "render_id" => id} = request)
       when map_size(request) == 2 do
    case s.operator_render do
      %{"render_id" => ^id, "display" => display} -> {:ok, display, "question", id}
      _ -> :error
    end
  end

  defp operator_request(s, %{"kind" => "draft", "render_id" => id} = request)
       when map_size(request) == 2 do
    case s.draft_render do
      %{"render_id" => ^id, "display" => display} -> {:ok, display, "draft", id}
      _ -> :error
    end
  end

  defp operator_request(_s, %{"kind" => "prompt"} = request) when map_size(request) == 1,
    do: {:ok, "you> ", "prompt", nil}

  defp operator_request(s, %{"kind" => "assertion", "render_id" => id} = request)
       when map_size(request) == 2 do
    case s.assertion_render do
      %{render: %{"id" => ^id, "display" => display}} -> {:ok, display, "assertion", id}
      _ -> :error
    end
  end

  defp operator_request(s, %{"kind" => "planning_decision", "render_id" => id} = request)
       when map_size(request) == 2 do
    case s.planning_decision_render do
      %{render: %{"id" => ^id, "display" => display}} ->
        {:ok, display, "planning_decision", id}

      _ ->
        :error
    end
  end

  defp operator_request(_s, %{"kind" => "control", "display" => display} = request)
       when map_size(request) == 2 and is_binary(display) do
    {:ok, display, "control", nil}
  end

  defp operator_request(_, _), do: :error

  def diagnostics(pid), do: GenServer.call(pid, :diagnostics)
  def stop_observability(pid), do: GenServer.call(pid, :stop_observability)
  def stop_feeds(pid), do: GenServer.call(pid, :stop_feeds, :infinity)
  def subscribe_text(pid), do: GenServer.call(pid, :subscribe_text)
  def subscribe_text(pid, version), do: GenServer.call(pid, {:subscribe_text, version})
  def unsubscribe_text(pid, handle), do: GenServer.call(pid, {:unsubscribe_text, handle})

  def subscribe_text(pid, version, opts) do
    if is_list(opts) and Keyword.keyword?(opts) and Keyword.keys(opts) in [[], [:required]] and
         is_boolean(Keyword.get(opts, :required, false)),
       do: GenServer.call(pid, {:subscribe_text, version, Keyword.get(opts, :required, false)}),
       else: {:error, :invalid_text_policy}
  end

  def exports(pid), do: GenServer.call(pid, :exports)

  def invoke_export(pid, kind, name, arguments),
    do: GenServer.call(pid, {:invoke_export, kind, name, arguments})

  @doc false
  def release_input_read(pid, channel),
    do: GenServer.call(pid, {:release_input_read, channel}, 5_000)

  @doc false
  def chat_reoffer_snapshot(pid, channel),
    do: GenServer.call(pid, {:chat_reoffer_snapshot, channel})

  @doc false
  def abort_chat_reoffer(pid, channel, ref),
    do: GenServer.call(pid, {:abort_chat_reoffer, channel, ref})

  @doc false
  def activate_chat_reoffer(pid, channel, ref, original, revision),
    do:
      GenServer.call(
        pid,
        {:activate_chat_reoffer, channel, ref, original, revision},
        10_000
      )

  @doc false
  def claim_chat_review(pid, token),
    do: GenServer.call(pid, {:claim_chat_review, token}, 5_000)

  @impl true

  # Header creation can outlive a dead Session through its file-server peer.
  # Keep every selector closed until that IO is fenced by the lock owner.
  def init({:export_v1, opts}) when is_list(opts), do: {:stop, :export_candidate_unavailable}

  def init({:share_candidate_v2, opts}) when is_list(opts),
    do: init_session(opts, :share_candidate_v2)

  def init(opts) when is_list(opts), do: init_session(opts, :legacy)

  defp init_session(opts, lock_mode) do
    config = Keyword.fetch!(opts, :config)
    requested_cwd = Keyword.fetch!(opts, :cwd)
    home = Map.get(config, :home) || System.get_env("IPSE_HOME") || Path.expand("~/.ipse")
    config = Map.put(config, :home, home)
    dir = Keyword.fetch!(opts, :state_dir) |> Path.expand()
    id = Keyword.get(opts, :id)
    owner_ref = if is_pid(opts[:owner]), do: Process.monitor(opts[:owner])

    with {:ok, handoff} <- handoff_option(opts),
         :ok <- planning_cli_start_valid(config),
         :ok <- extension_configuration(config),
         :ok <- Ipse.MCP.Planning.runtime_configuration(config),
         :ok <- Ipse.Observability.runtime(config),
         :ok <- Ipse.Usage.configuration(config),
         :ok <- ModelCall.configuration(config),
         :ok <- Ipse.Config.Profiles.embedding_configuration(config),
         :ok <- Ipse.Config.Decisions.configuration(config),
         :ok <- Ipse.Provider.validate_output_limit(config),
         :ok <- Ipse.Provider.Registry.validate_request(config),
         :ok <- provider_configuration(config),
         :ok <- Ipse.Usage.Budget.validate_configuration(config),
         {:ok, _journal_limits} <- Ipse.Journal.normalize_limits(config[:journal]),
         {:ok, cwd} <- Workspace.canonical_path(requested_cwd),
         true <- File.dir?(cwd),
         {:ok, _sandbox} <- Ipse.Tools.Sandbox.resolve(Map.get(config, :sandbox, :off), cwd),
         {:ok, id, _events, config, lock} <- open_and_lock(dir, id, cwd, config, lock_mode),
         {:ok, locked_events} <- Journal.load(dir, id, config[:journal]),
         :ok <-
           Ipse.Journal.SourceOrigin.check_path(dir, id, hd(locked_events)["metadata"]),
         actual_lock_mode = Ipse.Session.Lock.mode(Ipse.Session.Lock.current()),
         :ok <- verify_resume_lock(actual_lock_mode, locked_events, id),
         {:ok, fresh_release_owner} <-
           if(opts[:id] == nil,
             do: start_release_owner(dir, id, config, locked_events, actual_lock_mode),
             else: {:ok, nil}
           ),
         {:ok, locked_mode} <- Saved.execution_mode(locked_events, id),
         {:ok, startup_mode} <-
           if(opts[:id] == nil,
             do: Ipse.Extension.Mode.capture(config),
             else: resume_execution_mode(locked_mode, config)
           ),
         config = apply_execution_mode(config, startup_mode),
         {:ok, config} <- Ipse.Usage.BudgetStore.attach(config, dir, id, opts[:id] == nil),
         {:ok, _} <- restore_context(locked_events),
         :ok <- Ipse.Observability.validate_events(locked_events, id),
         :ok <- Ipse.Extension.TextResources.validate_events(locked_events, id),
         :ok <- Subscriptions.validate_sources(dir, id, locked_events),
         {:ok, validated_prefix} <- Saved.restore(locked_events, id),
         :ok <- Ipse.Session.SourceWindow.validate_sources(dir, id, locked_events),
         :ok <- Ipse.Usage.Budget.validate_sources(config, id, locked_events),
         {_prefix, prefix_config} = restore_draft_mode(validated_prefix, config),
         :ok <- question_available(validated_prefix.question, prefix_config),
         {:ok, prefix_event_question} <-
           Invocation.restore_event_question(validated_prefix.question, dir, id, locked_events),
         {:ok, _} <-
           Subscriptions.restore_question(
             validated_prefix.question,
             prefix_event_question,
             dir,
             id,
             locked_events
           ),
         {:ok, release_owner} <-
           if(opts[:id] == nil,
             do: {:ok, fresh_release_owner},
             else: start_release_owner(dir, id, config, locked_events, actual_lock_mode)
           ),
         :ok <- repair_session_tail(dir, id, config, actual_lock_mode),
         {:ok, events} <- Journal.load(dir, id, config[:journal]),
         {:ok, saved} <- Saved.restore(events, id),
         {:ok, _saved_mode, planning_entry} <-
           Ipse.Session.PlanningTransition.reconstruct(events, id),
         {saved, config} <- restore_draft_mode(saved, config),
         {:ok, source_window} <-
           Ipse.Session.SourceWindow.attach_effective_source(saved.source_window, dir, id),
         %{
           accounting: accounting,
           extension_state: extension_state,
           result_sources: result_sources,
           messages: messages,
           question: question
         } = saved,
         :ok <- question_available(question, config),
         {:ok, event_question} <- Invocation.restore_event_question(question, dir, id, events),
         {:ok, event_question} <-
           Subscriptions.restore_question(question, event_question, dir, id, events),
         {:ok, context_snapshot, context_is_new} <-
           workspace_snapshot(events, cwd, home, opts[:context_snapshot]),
         discovered =
           Workspace.discover_skills(
             cwd,
             Path.join(Path.expand(home), "skills"),
             skill_discovery_options(config)
           ),
         {:ok, skills, skills_saved} <- Workspace.restore_skills(events, discovered),
         {:ok, source_runtime} <- Ipse.Session.RuntimeLifecycle.restore(events, id),
         {:ok, source_tools} <- Ipse.Session.ToolLifecycle.restore(events, id),
         {:ok, capture_attempts} <- Ipse.Session.PendingNomination.capture_attempts(events, id),
         {:ok, writer} <- startup_writer(dir, id, config, release_owner) do
      :ok = Writer.install_source_window(writer, source_window)

      state = %{
        id: id,
        dir: dir,
        journal_writer: writer,
        journal_writer_ref: Process.monitor(writer),
        cwd: cwd,
        config: config,
        context_home: Path.expand(home),
        context_snapshot: context_snapshot,
        context_drift: Workspace.drift(context_snapshot),
        reported_model: nil,
        historical_model: saved.historical_model,
        subscriber: Keyword.fetch!(opts, :subscriber),
        skills: skills,
        skills_saved: skills_saved,
        skill_drift:
          if(skills == discovered,
            do: [],
            else: ["Skill catalog changed; use /context refresh to adopt current discovery."]
          ),
        messages: messages,
        draft: saved.draft,
        draft_lineages: saved.draft_lineages,
        draft_history_restricted: saved.draft_history_restricted,
        extension_contributions: extension_state.contributions,
        compaction: nil,
        tool_decision:
          if(question && question[:kind] == :extension,
            do: question.parent["approval"],
            else: "not_decided"
          ),
        task: nil,
        prompt_from: nil,
        input_generation: Ipse.Usage.id(),
        operator_channel: nil,
        operator_render: nil,
        draft_render: nil,
        assertion_render: nil,
        planning_decision_render: nil,
        planning_decisions: saved.planning_decisions,
        planning_save_active: nil,
        managed_supersession: nil,
        pending_acceptance_layout: get_in(hd(events), ["metadata", "pending_acceptance_layout"]),
        post_reply_capture_attempts: capture_attempts,
        chat_review_reoffer: Keyword.get(opts, :chat_review_reoffer, false) === true,
        chat_reoffer_choices: Ipse.Session.ChatReviewHandoff.reoffer_choices(events),
        chat_reoffer_snapshot: nil,
        operator_answers: %{},
        operator_pieces: [],
        planning_entry: if(startup_mode["ceiling"] == "planning", do: planning_entry),
        reference: saved.reference,
        reference_occurrences: Ipse.Session.Reference.occurrences(events),
        task_cleanup_failed: false,
        share_barrier: nil,
        share_ticket: nil,
        job_ref: nil,
        phase: if(question, do: :question, else: :idle),
        calls: if(question && question.call, do: [question.call], else: []),
        question: question,
        question_recovery: saved.question_recovery,
        approval: nil,
        permissions: Ipse.Session.Permissions.new(config),
        steps: if(question, do: question.steps, else: 0),
        tool_budget: Tools.restore_call_budget(messages),
        lock: lock,
        lock_mode: actual_lock_mode,
        lock_guard: Ipse.Session.Lock.current(),
        lock_guard_ref: Process.monitor(Ipse.Session.Lock.current()),
        release_owner: if(release_owner, do: release_owner.marker),
        release_origin: get_in(hd(locked_events), ["metadata", "source_origin"]),
        usage: %{},
        accounting: accounting,
        usage_reads: extension_state.usage_reads,
        child_usage: extension_state.child_usage,
        active_request: nil,
        managed_result_seal: nil,
        managed_output_release: nil,
        managed_approval: nil,
        managed_tool_effect: nil,
        managed_tool_result: nil,
        extension_model: nil,
        last_request_id: saved.last_request_id,
        turn_id:
          if(question && question[:kind] == :extension,
            do: question.parent["payload"]["turn_id"],
            else: saved.turn_id || Ipse.Usage.id()
          ),
        text_stream: nil,
        text_stream_monitor: nil,
        text_stream_policy_ref: nil,
        text_required: false,
        extension_text: %{},
        extension_text_count: Ipse.Extension.TextResources.count(events),
        extension_text_turn: nil,
        extension_text_cleanup_failed: false,
        event_received: if(event_question, do: event_question.received),
        event_committed: if(event_question, do: event_question.effective),
        event_answer: if(event_question, do: event_question.answer),
        event_turn: if(event_question, do: event_question.turn),
        event_intent: if(event_question, do: event_question.intent),
        event_schedule: if(event_question, do: event_question.schedule, else: "before_request"),
        event_after_started: event_question != nil and event_question.schedule == "after_turn",
        event_count: Enum.count(events, &(&1["type"] == "extension_event_intent")),
        event_cleanup_failed: false,
        final:
          if(event_question && event_question.schedule == "after_turn",
            do: Saved.event_final(events, messages),
            else: Projection.presentation(events)
          ),
        extension_intent: nil,
        extension_result_sources: result_sources,
        extension_output: nil,
        extension_output_clock: nil,
        invocation:
          CurrentInvocation.restore(
            question,
            extension_state.effect_sources,
            saved.managed_reads.invocations
          ),
        managed_outputs: saved.managed_reads.outputs,
        managed_lineage: saved.managed_lineage,
        extension_tool_context: nil,
        extension_mcp_context: nil,
        extension_result: extension_state.last_display,
        extension_catalog: extension_catalog(config),
        extension_invocations: Invocation.count(events),
        mcp_tools: [],
        mcp_ready: false,
        mcp_discovered: false,
        draft_mcp_definitions: saved.draft_mcp_definitions,
        draft_mcp_snapshot: saved.draft_mcp_snapshot,
        draft_mcp_interrupted: saved.draft_mcp_interrupted,
        draft_mcp_pending: saved.draft_mcp_pending,
        draft_mcp_attempts: saved.draft_mcp_attempts,
        draft_mcp_revalidation: nil,
        draft_mcp_initial: false,
        mcp_resources: %{},
        delegation_resources: %{},
        delegation_workers: MapSet.new(),
        delegation_queue: [],
        delegation_effect: nil,
        delegation_claims: %{},
        delegations: 0,
        owner_ref: owner_ref,
        request_started_at: nil,
        observation: nil,
        lifecycle: nil,
        tool_lifecycle: nil,
        source_runtime_summary: Map.take(source_runtime, [:epoch, :count, :closed, :stopped]),
        source_tool_summary: Map.take(source_tools, [:count, :stopped]),
        source_resumed: opts[:id] != nil,
        feeds: Feeds.new(events, id)
      }

      startup_checkpoint =
        if opts[:id] != nil and
             Ipse.Extension.Mode.checkpoint_required?(locked_mode, startup_mode) do
          checkpoint = %{
            "type" => "execution_mode_resumed",
            "version" => 2,
            "session_id" => id,
            "previous_sha256" => Ipse.JSON.digest([locked_mode]),
            "mode" => startup_mode
          }

          record(state, checkpoint)
          checkpoint
        end

      state =
        if Map.get(config, :planning_mcp_reads, %{}) != %{} do
          {:ok, mode} = Ipse.Extension.Mode.capture(config)
          epoch_id = Ipse.Usage.id()

          record(
            state,
            Ipse.Session.PlanningMCP.epoch(
              id,
              epoch_id,
              Ipse.Session.PlanningMCP.last_epoch(events),
              if(opts[:id] == nil, do: "fresh", else: "resume"),
              mode,
              config[:planning_mcp_reads]
            )
          )

          Map.put(state, :planning_mcp_epoch_id, epoch_id)
        else
          Map.put(state, :planning_mcp_epoch_id, nil)
        end

      state =
        if planning_cli_resume_entry?(
             config,
             locked_mode,
             startup_mode,
             startup_checkpoint
           ) do
          marker = Ipse.Session.PlanningTransition.startup_selected(id, startup_checkpoint)
          record(state, marker)
          %{state | planning_entry: marker}
        else
          state
        end

      state =
        %{
          state
          | reference:
              Ipse.Session.Reference.seed(
                state.reference,
                Ipse.Session.Context.admission_header(state),
                Ipse.Session.Context.admission_publishers(state)
              )
        }

      state =
        if handoff do
          record(state, handoff)
          state = managed_event(state, handoff, state.messages ++ [handoff["message"]])
          %{state | messages: state.messages ++ [handoff["message"]]}
        else
          state
        end

      capture =
        Ipse.Observability.prepare(
          self(),
          config,
          id,
          &record(state, &1),
          Enum.count(events, &(&1["type"] == "diagnostic_sink_intent"))
        )

      state = %{state | observation: capture}
      state = if context_is_new, do: persist_context(state, context_snapshot, true), else: state
      state = if opts[:id] == nil, do: persist_skills(state, skills), else: state

      state =
        lifecycle_records(
          state,
          Ipse.Session.RuntimeLifecycle.open(config, capture.policy, events, id, opts[:id] != nil)
        )

      state =
        Turn.tool_records(
          state,
          Ipse.Session.ToolLifecycle.open(
            Map.put(config, :source_layout, nil),
            events,
            id,
            state.lifecycle,
            dir,
            question
          )
        )

      state =
        if question,
          do:
            question_wait(
              state,
              question,
              Ipse.Session.RuntimeLifecycle.question_source(events, question),
              saved.turn_id
            ),
          else: state

      if config[:semantic_admission]["status"] not in ["off", "active"] do
        notify(
          state,
          {:status,
           "Knowledge inactive: saved permission was not admitted (" <>
             config[:semantic_admission]["status"] <> ")."}
        )
      end

      if question, do: {:ok, state, {:continue, :question}}, else: {:ok, state}
    else
      false -> {:stop, :workspace_not_found}
      {:error, reason} -> {:stop, reason}
    end
  end

  defp handoff_option(opts) do
    cond do
      not Keyword.has_key?(opts, :handoff) -> {:ok, nil}
      opts[:id] != nil -> {:error, :handoff_requires_fresh_session}
      true -> Ipse.Session.Saved.prepare_handoff(opts[:handoff])
    end
  end

  defp extension_configuration(config),
    do:
      if(Ipse.Extension.Registry.valid_entries?(config),
        do: :ok,
        else: {:error, :invalid_extension_configuration}
      )

  # Explicit application homes are commonly isolation fixtures. Shared discovery
  # requires a separate opt-in in that case; the CLI supplies the operator home.
  defp skill_discovery_options(config) do
    isolated_home? = Map.get(config, :home) || System.get_env("IPSE_HOME")
    default = if isolated_home?, do: nil, else: Workspace.operator_home()

    [operator_home: Map.get(config, :operator_home, default)] ++
      if(Map.has_key?(config, :shared_root), do: [shared_root: config.shared_root], else: [])
  end

  @impl true

  def handle_continue(:question, s) do
    notify(s, {:question, s.question.id, s.question.arguments})
    {:noreply, s}
  end

  @impl true

  # Core approval and private extension protocols seal Session state before
  # queuing the Writer drain. Cancellation quarantines an exported share.
  def handle_call(
        {:chat_reoffer_snapshot, channel},
        {client, _},
        %{
          phase: :idle,
          task: nil,
          share_barrier: nil,
          chat_review_reoffer: true,
          operator_channel: %{id: channel, client: client, reader: reader, generation: generation}
        } = s
      ) do
    next = %{s | chat_review_reoffer: false}

    with true <- Process.alive?(reader),
         nil <- Map.get(s, :pending_chat_review),
         nil <- s.draft,
         {:ok, mode} <- Ipse.Extension.Mode.capture(s.config),
         :ok <- Ipse.Extension.Mode.nomination(mode) do
      if s.chat_reoffer_choices === [] do
        {:reply, :none, next}
      else
        snapshot = %{
          ref: make_ref(),
          channel: channel,
          generation: generation,
          input_generation: s.input_generation,
          turn: s.turn_id,
          request: s.last_request_id,
          focus_id: Ipse.Usage.id(),
          mode: mode,
          choices: s.chat_reoffer_choices
        }

        {:reply, {:ok, %{ref: snapshot.ref, session_id: s.id, choices: snapshot.choices}},
         %{next | chat_reoffer_snapshot: snapshot}}
      end
    else
      _ -> {:reply, {:error, :chat_review_unavailable}, next}
    end
  end

  def handle_call({:chat_reoffer_snapshot, _}, _, s), do: {:reply, :none, s}

  def handle_call(
        {:abort_chat_reoffer, channel, ref},
        {client, _},
        %{operator_channel: %{id: channel, client: client}} = s
      ) do
    current =
      case s.chat_reoffer_snapshot do
        %{ref: ^ref} = snapshot -> reoffer_snapshot_current?(s, snapshot, client, channel)
        _ -> false
      end

    next =
      case s.chat_reoffer_snapshot do
        %{ref: ^ref} -> %{s | chat_reoffer_snapshot: nil}
        _ -> s
      end

    {:reply, {:ok, if(current, do: :current, else: :stale)}, next}
  end

  def handle_call({:abort_chat_reoffer, _, _}, _, s), do: {:reply, {:ok, :stale}, s}

  def handle_call(
        {:activate_chat_reoffer, channel, ref, original, revision},
        {client, _},
        %{
          phase: :idle,
          task: nil,
          share_barrier: nil,
          operator_channel: %{id: channel, client: client},
          chat_reoffer_snapshot: %{ref: ref} = snapshot
        } = s
      ) do
    next = %{s | chat_reoffer_snapshot: nil}

    with true <- reoffer_snapshot_current?(s, snapshot, client, channel),
         true <-
           Ipse.Session.ChatReviewHandoff.valid?(original) and
             Enum.sort(Map.keys(original)) === ~w(event source),
         true <-
           Enum.any?(
             snapshot.choices,
             &(&1.sha256 === Ipse.JSON.digest([original["event"]]) and
                 &1.key === original["event"]["pending_key"])
           ),
         {:ok, event} <-
           Ipse.Session.ChatReviewHandoff.reoffer(
             original,
             channel,
             snapshot.generation,
             snapshot.focus_id,
             revision,
             snapshot.mode
           ),
         source = record_source(next, event),
         {:ok, binding} <- Ipse.Session.ChatReviewHandoff.wrap_reoffer(original, event, source) do
      token = make_ref()

      pending = %{
        state: :ready,
        token: token,
        event: binding,
        input_generation: s.input_generation,
        focus: %{turn: snapshot.turn, request: snapshot.request, id: snapshot.focus_id}
      }

      notify(next, {:pending_chat_review, token})
      {:reply, {:ok, token}, Map.put(next, :pending_chat_review, pending)}
    else
      _ -> {:reply, {:error, :chat_review_unavailable}, next}
    end
  end

  def handle_call({:activate_chat_reoffer, _, _, _, _}, _, s),
    do: {:reply, {:error, :chat_review_unavailable}, s}

  def handle_call(
        {:release_input_read, channel},
        {client, _},
        %{
          phase: :idle,
          task: nil,
          share_barrier: nil,
          pending_chat_review: %{state: state} = pending,
          operator_channel: %{id: channel, client: client}
        } = s
      )
      when state in [:ready, :claimed] do
    if chat_review_current?(s, pending),
      do: {:reply, Ipse.Session.Input.release_for_output(), s},
      else: {:reply, {:error, :operator_input_unavailable}, Map.delete(s, :pending_chat_review)}
  end

  def handle_call({:release_input_read, _}, _, s),
    do: {:reply, {:error, :operator_input_unavailable}, s}

  def handle_call(
        {:claim_chat_review, token},
        {client, _},
        %{
          phase: :idle,
          task: nil,
          share_barrier: nil,
          pending_chat_review: %{state: :ready, token: token, event: event} = pending,
          operator_channel: %{client: client, id: channel, generation: generation}
        } = s
      )
      when is_reference(token) do
    with true <- Ipse.Session.ChatReviewHandoff.client_id(event) === channel,
         true <- Ipse.Session.ChatReviewHandoff.client_generation(event) === generation,
         true <- chat_review_current?(s, pending),
         {:ok, mode} <- Ipse.Extension.Mode.capture(s.config),
         :ok <- Ipse.Extension.Mode.nomination(mode) do
      {:reply, {:ok, event, mode}, %{s | pending_chat_review: %{pending | state: :claimed}}}
    else
      _ -> {:reply, {:error, :chat_review_unavailable}, Map.delete(s, :pending_chat_review)}
    end
  end

  def handle_call({:claim_chat_review, _}, _, s),
    do: {:reply, {:error, :chat_review_unavailable}, s}

  def handle_call({:managed_capture_prepare, ref, intent}, {caller, _}, %{job_ref: ref} = s)
      when ref != nil,
      do: {:reply, Ipse.Session.ManagedCapture.prepare(s, caller, intent), s}

  def handle_call({:managed_capture_prepare, _, _}, _, s),
    do: {:reply, {:error, :managed_capture_unavailable}, s}

  def handle_call(
        {:session_control_ticket_capture, ref, intent, sha, proofs, wall},
        {caller, _},
        s
      )
      when is_list(proofs) and length(proofs) <= 128 do
    with true <- Enum.all?(proofs, &is_map/1),
         active = Enum.filter(proofs, &(&1["session_id"] == s.id)),
         {:ok, sources} <- supersession_proofs(s, active) do
      Ipse.Session.ManagedCapture.ticket(s, caller, ref, intent, sha, proofs, wall, sources)
    else
      _ -> {:reply, {:error, :session_share_refused}, s}
    end
  end

  def handle_call({:session_control_ticket_capture, _, _, _, _, _}, _, s),
    do: {:reply, {:error, :session_share_refused}, s}

  def handle_call(
        {:session_control_ticket_worker_input, ref, intent, sha, proofs, wall},
        {caller, _},
        s
      )
      when is_list(proofs) and length(proofs) <= 128 do
    with true <- Enum.all?(proofs, &is_map/1),
         active = Enum.filter(proofs, &(&1["session_id"] == s.id)),
         {:ok, sources} <- supersession_proofs(s, active) do
      Ipse.Session.WorkerInput.ticket(s, caller, ref, intent, sha, proofs, wall, sources)
    else
      _ -> {:reply, {:error, :session_share_refused}, s}
    end
  end

  def handle_call({:session_control_ticket_worker_input, _, _, _, _, _}, _, s),
    do: {:reply, {:error, :session_share_refused}, s}

  def handle_call({:session_control_ticket_approval, ref, input, proofs, wall}, {caller, _}, s)
      when is_list(proofs) and length(proofs) <= 128 do
    with true <- Enum.all?(proofs, &is_map/1),
         active = Enum.filter(proofs, &(&1["session_id"] == s.id)),
         {:ok, sources} <- supersession_proofs(s, active) do
      Ipse.Session.ManagedApproval.ticket(s, caller, ref, input, proofs, wall, sources)
    else
      _ -> {:reply, {:error, :session_share_refused}, s}
    end
  end

  def handle_call({:session_control_ticket_approval, _, _, _, _}, _, s),
    do: {:reply, {:error, :session_share_refused}, s}

  def handle_call(
        {:session_control_ticket_relation_display, ref, intent, sha, proofs, wall},
        {caller, _},
        %{
          share_barrier: nil,
          job_ref: ref,
          managed_supersession: %{prepared: prepared, candidate: candidate, records: [event]}
        } = s
      )
      when ref != nil do
    with true <- candidate === intent and sha === Ipse.JSON.digest([prepared, intent]),
         true <- s.lock_mode in [:header_share_v2, :resume_share_v2],
         true <- supersession_worker?(s, caller, intent),
         true <-
           Enum.any?(s.config.extensions, &(&1.identity == s.invocation.parent["identity"])),
         {:ok, binding} when is_map(binding) <- supersession_lookup(s, caller, intent),
         true <- binding.source_binding === {:supersession, sha},
         true <- Ipse.Session.ManagedSupersession.record?(event, prepared, candidate, []),
         facts = event["facts"],
         {:ok, selected} <-
           Ipse.Session.ManagedSupersession.reviewed_display_sources(
             facts,
             s.id,
             System.system_time(:millisecond)
           ),
         true <- is_list(proofs) and length(Enum.uniq(proofs)) == length(proofs),
         true <- Enum.sort(proofs) === Enum.sort(selected.active ++ selected.inactive),
         {:ok, sources} <- supersession_proofs(s, selected.active),
         %{client: client, reader: reader} = channel <- s.operator_channel,
         true <- Process.alive?(client) and Process.alive?(reader),
         true <- Ipse.JSON.safe_uint?(wall) and wall > System.system_time(:millisecond),
         command = if(prepared["mode"] == "ordinary", do: "correct", else: "supersede"),
         {:ok, payload, challenge} <- Ipse.Runner.Review.preview_display(command, facts) do
      now = System.monotonic_time(:millisecond)
      wall = min(wall, System.system_time(:millisecond) + 5_000)
      deadline = now + min(wall - System.system_time(:millisecond), 5_000)
      overall = now + 120_000

      ticket = %{
        ticket: make_ref(),
        operation: :crypto.strong_rand_bytes(16),
        deadline: deadline,
        caller: caller,
        job_ref: ref,
        intent: intent,
        parent: s.invocation.parent,
        phase: s.phase,
        channel: channel,
        relation_publisher: true,
        protocol: :managed_relation_review,
        terminal_purpose: :review,
        source_proofs: selected.active,
        expected_sources: sources,
        wall_deadline: wall,
        overall_deadline: overall,
        overall_wall: System.system_time(:millisecond) + 120_000,
        relation_display_purpose_sha256: sha,
        relation_display_facts_sha256: selected.facts_sha256,
        relation_display_inactive_sources: selected.inactive,
        review_payload: payload,
        review_challenge: challenge,
        review_command: command,
        review_facts: facts
      }

      {:reply, {:ok, ticket.ticket, ticket.operation, deadline, overall},
       %{s | share_ticket: ticket}}
    else
      _ -> {:reply, {:error, :session_share_refused}, s}
    end
  end

  def handle_call({:session_control_ticket_relation_display, _, _, _, _, _}, _, s),
    do: {:reply, {:error, :session_share_refused}, s}

  def handle_call(
        {:session_control_ticket, ref, intent},
        {caller, _},
        %{share_barrier: nil, job_ref: ref, task: %{pid: caller}, lock_mode: mode} = s
      )
      when ref != nil and mode in [:header_share_v2, :resume_share_v2] do
    with %{action: %{intent: ^intent}, parent: parent, interrupted: false} <- s.invocation,
         true <- is_map(parent) and is_map(parent["identity"]),
         true <-
           Enum.any?(Map.get(s.config, :extensions, []), &(&1.identity == parent["identity"])),
         true <- Ipse.Extension.Registry.live?(parent["identity"]),
         true <- s.phase in [:tool, :extension_command, :extension_service, :extension_events],
         %{client: client, reader: reader} = channel <- s.operator_channel,
         true <-
           is_pid(client) and is_pid(reader) and Process.alive?(client) and Process.alive?(reader) do
      ticket = make_ref()
      operation = :crypto.strong_rand_bytes(16)
      deadline = System.monotonic_time(:millisecond) + 5_000

      binding = %{
        ticket: ticket,
        operation: operation,
        deadline: deadline,
        caller: caller,
        job_ref: ref,
        intent: intent,
        parent: parent,
        phase: s.phase,
        channel: channel
      }

      {:reply, {:ok, ticket, operation, deadline}, %{s | share_ticket: binding}}
    else
      _ -> {:reply, {:error, :session_share_refused}, %{s | share_ticket: nil}}
    end
  end

  def handle_call({:session_control_ticket, _, _}, _, s),
    do: {:reply, {:error, :session_share_refused}, s}

  # Fixed-purpose host fixture: this establishes no publication authority.
  def handle_call({:session_control_ticket_source_fixture, ref, intent, proofs}, from, s) do
    case handle_call({:session_control_ticket, ref, intent}, from, s) do
      {:reply, {:ok, _, _, _} = result, next} ->
        with true <-
               is_list(proofs) and length(proofs) in 1..8 and
                 length(Enum.uniq(proofs)) == length(proofs),
             true <- Enum.all?(proofs, &(is_map(&1) and &1["session_id"] == s.id)),
             {:ok, sources} <- supersession_proofs(s, proofs) do
          {:reply, result,
           update_in(
             next.share_ticket,
             &Map.merge(&1, %{source_proofs: proofs, expected_sources: sources})
           )}
        else
          _ -> {:reply, {:error, :session_share_refused}, %{next | share_ticket: nil}}
        end

      other ->
        other
    end
  end

  def handle_call(
        {:session_control_ticket_supersession, ref, intent, sha},
        {caller, _} = from,
        %{
          job_ref: ref,
          managed_supersession: %{
            prepared: prepared,
            candidate: candidate,
            records: [event, review_event]
          }
        } = s
      )
      when ref != nil and is_binary(sha) do
    with true <- candidate === intent and sha === Ipse.JSON.digest([prepared, intent]),
         {:ok, binding} when is_map(binding) <- supersession_lookup(s, caller, intent),
         true <- binding.source_binding === {:supersession, sha},
         true <- Ipse.Session.ManagedSupersession.record?(event, prepared, candidate, []),
         true <-
           Ipse.Session.ManagedSupersession.record?(review_event, prepared, candidate, [event]),
         {:ok, sources} <-
           Ipse.Session.ManagedSupersession.reviewed_publication_sources(
             event["facts"],
             review_event["review"],
             s.id,
             System.system_time(:millisecond)
           ),
         true <- binding.proof in sources.active,
         {:reply, {:ok, _, _, _} = result, next} <-
           supersession_effect_ticket(s, from, ref, intent, sources.active) do
      ticket =
        Map.merge(next.share_ticket, %{
          relation_facts_sha256: sources.facts_sha256,
          relation_review_sha256: Ipse.JSON.digest([review_event]),
          relation_inactive_sources: sources.inactive,
          relation_purpose_sha256: sha
        })

      {:reply, result, %{next | share_ticket: ticket}}
    else
      _ -> {:reply, {:error, :session_share_refused}, s}
    end
  end

  def handle_call({:session_control_ticket_supersession, _, _, _}, _, s),
    do: {:reply, {:error, :session_share_refused}, s}

  # Private fixed-text bridge only. The eventual protected display needs a
  # separate native recipient and full-facts authorization; this ticket merely
  # binds the recorded pre-review relation and active source to that bridge.
  def handle_call(
        {:session_control_ticket_supersession_display_fixture, ref, intent, sha},
        {caller, _} = from,
        %{
          job_ref: ref,
          managed_supersession: %{prepared: prepared, candidate: candidate, records: [event]}
        } = s
      )
      when ref != nil and is_binary(sha) do
    with true <- candidate === intent and sha === Ipse.JSON.digest([prepared, intent]),
         {:ok, binding} when is_map(binding) <- supersession_lookup(s, caller, intent),
         true <- binding.source_binding === {:supersession, sha},
         true <- Ipse.Session.ManagedSupersession.record?(event, prepared, candidate, []),
         {:ok, sources} <-
           Ipse.Session.ManagedSupersession.reviewed_display_sources(
             event["facts"],
             s.id,
             System.system_time(:millisecond)
           ),
         true <- binding.proof in sources.active,
         {:reply, {:ok, ticket, operation, deadline}, next} <-
           handle_call(
             {:session_control_ticket_source_fixture, ref, intent, sources.active},
             from,
             s
           ) do
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)
      overall = System.monotonic_time(:millisecond) + 15_000
      overall_wall = System.system_time(:millisecond) + 15_000

      bound =
        Map.merge(next.share_ticket, %{
          protocol: :synthetic_review,
          terminal_purpose: :review,
          wall_deadline: System.system_time(:millisecond) + remaining,
          overall_deadline: overall,
          overall_wall: overall_wall,
          relation_display_purpose_sha256: sha,
          relation_display_facts_sha256: sources.facts_sha256,
          relation_display_inactive_sources: sources.inactive
        })

      {:reply, {:ok, ticket, operation, deadline, overall}, %{next | share_ticket: bound}}
    else
      _ -> {:reply, {:error, :session_share_refused}, s}
    end
  end

  def handle_call({:session_control_ticket_supersession_display_fixture, _, _, _}, _, s),
    do: {:reply, {:error, :session_share_refused}, s}

  def handle_call({:session_control_ticket_synthetic, ref, intent}, from, s) do
    case handle_call({:session_control_ticket, ref, intent}, from, s) do
      {:reply, {:ok, _, _, _} = result, next} ->
        remaining = max(next.share_ticket.deadline - System.monotonic_time(:millisecond), 0)
        wall_deadline = System.system_time(:millisecond) + remaining

        {:reply, result,
         update_in(
           next.share_ticket,
           &Map.merge(&1, %{protocol: :synthetic_notice, wall_deadline: wall_deadline})
         )}

      other ->
        other
    end
  end

  def handle_call({:session_control_ticket_synthetic_review, ref, intent}, from, s) do
    case handle_call({:session_control_ticket_synthetic, ref, intent}, from, s) do
      {:reply, {:ok, ticket, operation, deadline}, next} ->
        overall = System.monotonic_time(:millisecond) + 15_000
        overall_wall = System.system_time(:millisecond) + 15_000

        binding =
          Map.merge(next.share_ticket, %{
            protocol: :synthetic_review,
            terminal_purpose: :review,
            overall_deadline: overall,
            overall_wall: overall_wall
          })

        {:reply, {:ok, ticket, operation, deadline, overall}, %{next | share_ticket: binding}}

      other ->
        other
    end
  end

  def handle_call({:session_control_ticket_synthetic_accepted, ref, intent, cutoff}, from, s)
      when is_nil(cutoff) or (is_integer(cutoff) and cutoff in 1..9_007_199_254_740_991) do
    case handle_call({:session_control_ticket_synthetic, ref, intent}, from, s) do
      {:reply, {:ok, _, _, _} = result, next} ->
        ticket = next.share_ticket

        wall =
          if is_nil(cutoff), do: ticket.wall_deadline, else: min(ticket.wall_deadline, cutoff)

        if wall > System.system_time(:millisecond) do
          {:reply, result,
           %{
             next
             | share_ticket:
                 Map.merge(ticket, %{terminal_purpose: :accepted, wall_deadline: wall})
           }}
        else
          {:reply, {:error, :session_share_refused}, %{next | share_ticket: nil}}
        end

      other ->
        other
    end
  end

  def handle_call({:session_control_ticket_synthetic_accepted, _, _, _}, _, s),
    do: {:reply, {:error, :session_share_refused}, s}

  def handle_call(
        {:session_share_begin_controlled, ref, intent, prepared, host_port},
        {caller, _} = from,
        %{share_barrier: nil, job_ref: ref, task: %{pid: _}, share_ticket: ticket} = s
      )
      when ref != nil and is_map(ticket) and is_port(host_port) do
    valid =
      ticket.caller == caller and ticket.job_ref == ref and ticket.intent == intent and
        share_binding_current?(s, ticket) and
        ticket.phase == s.phase and controlled_actor_current?(s, ticket) and
        relation_ticket_current?(s, ticket) and
        Port.info(host_port, :connected) == {:connected, caller} and
        Ipse.Runner.valid_owner_preparation?(prepared, caller, ref, intent) and
        prepared.ticket == ticket.ticket and prepared.operation == ticket.operation and
        prepared.deadline == ticket.deadline

    if valid do
      protocol = Map.get(ticket, :protocol, :legacy)

      opened =
        if protocol in [:synthetic_review, :managed_approval, :managed_relation_review],
          do:
            Ipse.Runner.open_prepared_review_notice_owner_control(
              prepared,
              caller,
              ref,
              intent,
              ticket.overall_deadline
            ),
          else: Ipse.Runner.open_prepared_owner_control(prepared, caller, ref, intent, protocol)

      case opened do
        {:ok, port} ->
          generation = make_ref()

          timer =
            Process.send_after(
              self(),
              {:session_share_timeout, generation},
              max(ticket.deadline - System.monotonic_time(:millisecond), 0)
            )

          request =
            cond do
              Map.has_key?(ticket, :worker_source_proofs) ->
                inactive_ids =
                  ticket.worker_source_proofs
                  |> Enum.map(& &1["session_id"])
                  |> Enum.uniq()
                  |> Enum.sort()

                Writer.request_share_barrier_display_sources(
                  s.journal_writer,
                  ticket.operation,
                  ref,
                  generation,
                  ticket.source_proofs,
                  inactive_ids
                )

              Map.has_key?(ticket, :approval_journals) ->
                inactive_ids =
                  ticket.relation_display_inactive_sources
                  |> Enum.map(& &1["session_id"])
                  |> Enum.uniq()
                  |> Enum.sort()

                Writer.request_share_barrier_display_sources(
                  s.journal_writer,
                  ticket.operation,
                  ref,
                  generation,
                  ticket.source_proofs,
                  inactive_ids,
                  ticket.approval_journals
                )

              Map.has_key?(ticket, :relation_display_inactive_sources) ->
                inactive_ids =
                  ticket.relation_display_inactive_sources
                  |> Enum.map(& &1["session_id"])
                  |> Enum.uniq()
                  |> Enum.sort()

                Writer.request_share_barrier_display_sources(
                  s.journal_writer,
                  ticket.operation,
                  ref,
                  generation,
                  ticket.source_proofs,
                  inactive_ids
                )

              Map.has_key?(ticket, :source_proofs) ->
                Writer.request_share_barrier_sources(
                  s.journal_writer,
                  ticket.operation,
                  ref,
                  generation,
                  ticket.source_proofs
                )

              true ->
                Writer.request_share_barrier(s.journal_writer, ticket.operation, ref, generation)
            end

          barrier = %{
            phase: :draining,
            request: request,
            from: from,
            caller: caller,
            job_ref: ref,
            operation: ticket.operation,
            generation: generation,
            deadline: ticket.deadline,
            timer: timer,
            intent: intent,
            parent: ticket.parent,
            session_phase: s.phase,
            controlled: true,
            owner_protocol: protocol,
            terminal_purpose: Map.get(ticket, :terminal_purpose, :ordinary),
            wall_deadline: Map.get(ticket, :wall_deadline),
            overall_deadline: Map.get(ticket, :overall_deadline),
            overall_wall: Map.get(ticket, :overall_wall),
            owner_port: port,
            host_port: host_port,
            owner_phase: :starting,
            owner_buffer: <<>>,
            channel: ticket.channel
          }

          barrier =
            if Map.has_key?(ticket, :source_proofs),
              do: Map.put(barrier, :expected_sources, ticket.expected_sources),
              else: barrier

          barrier =
            Map.merge(
              barrier,
              Map.take(ticket, [
                :relation_publisher,
                :review_payload,
                :review_facts,
                :review_command,
                :review_challenge,
                :relation_facts_sha256,
                :relation_review_sha256,
                :relation_inactive_sources,
                :relation_purpose_sha256,
                :relation_display_purpose_sha256,
                :relation_display_facts_sha256,
                :relation_display_inactive_sources,
                :approval_journals,
                :source_proofs,
                :worker_input,
                :managed_capture,
                :worker_source_proofs
              ])
            )

          {:noreply, %{s | share_ticket: nil, share_barrier: barrier}}

        _ ->
          {:reply, {:error, :session_share_refused}, %{s | share_ticket: nil}}
      end
    else
      {:reply, {:error, :session_share_refused}, %{s | share_ticket: nil}}
    end
  end

  def handle_call({:session_share_begin_controlled, _, _, _, _}, _, %{share_barrier: nil} = s),
    do: {:reply, {:error, :session_share_refused}, %{s | share_ticket: nil}}

  def handle_call(
        {:session_share_begin, ref, intent},
        {caller, _} = from,
        %{share_barrier: nil, job_ref: ref, task: %{pid: caller}, lock_mode: mode} = s
      )
      when ref != nil and mode in [:header_share_v2, :resume_share_v2] do
    with %{action: %{intent: ^intent}, parent: parent, interrupted: false} <- s.invocation,
         true <- is_map(parent) and is_map(parent["identity"]),
         true <-
           Enum.any?(Map.get(s.config, :extensions, []), &(&1.identity == parent["identity"])),
         true <- Ipse.Extension.Registry.live?(parent["identity"]),
         true <- s.phase in [:tool, :extension_command, :extension_service, :extension_events] do
      operation = :crypto.strong_rand_bytes(16)
      generation = make_ref()
      deadline = System.monotonic_time(:millisecond) + 5_000
      timer = Process.send_after(self(), {:session_share_timeout, generation}, 5_000)
      request = Writer.request_share_barrier(s.journal_writer, operation, ref, generation)

      barrier = %{
        phase: :draining,
        request: request,
        from: from,
        caller: caller,
        job_ref: ref,
        operation: operation,
        generation: generation,
        deadline: deadline,
        timer: timer,
        intent: intent,
        parent: parent,
        session_phase: s.phase
      }

      {:noreply, %{s | share_ticket: nil, share_barrier: barrier}}
    else
      _ -> {:reply, {:error, :session_share_refused}, s}
    end
  end

  def handle_call({:session_share_begin, _, _}, _, %{share_barrier: nil} = s),
    do: {:reply, {:error, :session_share_refused}, s}

  # Only the fixed-marker synthetic helper is available here. Session chooses
  # the executable and mode before transferring its Port to the current Host.
  def handle_call(
        {:session_share_spawn_synthetic_terminal, ref, capability},
        {caller, _},
        %{
          share_barrier:
            %{
              controlled: true,
              phase: :armed,
              owner_phase: :ready,
              caller: caller,
              job_ref: ref,
              capability: capability
            } = b
        } = s
      ) do
    remaining =
      if b.owner_protocol in [:synthetic_review, :managed_approval, :managed_relation_review],
        do: b.overall_deadline - System.monotonic_time(:millisecond),
        else: min(b.deadline - System.monotonic_time(:millisecond), 5_000)

    if remaining > 0 and not Map.has_key?(b, :worker_input) and
         not Map.has_key?(b, :managed_capture) and Process.alive?(caller) and
         share_deadline_current?(b) and
         not Map.has_key?(b, :issued_terminal) do
      case Ipse.Runner.open_synthetic_notice_terminal(s.cwd, remaining, b.terminal_purpose) do
        {:ok, port} ->
          case transfer_synthetic_terminal(port, caller) do
            {:ok, pid} ->
              next = Map.put(b, :issued_terminal, %{port: port, pid: pid})
              {:reply, {:ok, port}, %{s | share_barrier: next}}

            _ ->
              {:reply, {:error, :cleanup_unconfirmed}, poison_session_share(s)}
          end

        _ ->
          {:reply, {:error, :session_share_refused}, s}
      end
    else
      {:reply, {:error, :session_share_refused}, s}
    end
  rescue
    _ -> {:reply, {:error, :cleanup_unconfirmed}, poison_session_share(s)}
  end

  def handle_call(
        {:session_share_writer_open, ref, capability},
        {caller, _} = from,
        %{
          share_barrier:
            %{
              controlled: true,
              owner_protocol: :legacy,
              phase: :armed,
              job_ref: ref,
              caller: caller,
              capability: capability
            } = b
        } = s
      ) do
    if not Map.has_key?(b, :writer_control) and share_deadline_current?(b) do
      request =
        Writer.request_share_control_open(s.journal_writer, b.token, b.operation, b.deadline)

      {:noreply,
       %{s | share_barrier: %{b | phase: :writer_opening, request: request, from: from}}}
    else
      {:reply, {:error, :cleanup_unconfirmed}, poison_session_share(s)}
    end
  end

  def handle_call(
        {:session_share_writer_transfer, ref, capability, recipient, name, secret},
        {caller, _} = from,
        %{
          share_barrier:
            %{
              controlled: true,
              owner_protocol: :legacy,
              phase: :armed,
              owner_phase: :ready,
              writer_control: :ready,
              job_ref: ref,
              caller: caller,
              capability: capability
            } = b
        } = s
      ) do
    if is_integer(recipient) and recipient > 0 and is_binary(name) and byte_size(name) == 16 and
         is_binary(secret) and byte_size(secret) == 32 and share_deadline_current?(b) do
      request =
        Writer.request_share_control_transfer(
          s.journal_writer,
          b.token,
          b.operation,
          recipient,
          name,
          secret,
          b.deadline
        )

      {:noreply,
       %{
         s
         | share_barrier:
             Map.merge(b, %{
               phase: :writer_transferring,
               request: request,
               from: from,
               writer_recipient: recipient
             })
       }}
    else
      {:reply, {:error, :cleanup_unconfirmed}, poison_session_share(s)}
    end
  end

  def handle_call(
        {:session_share_writer_prepare_close, ref, capability},
        {caller, _} = from,
        %{
          share_barrier:
            %{
              controlled: true,
              owner_protocol: :legacy,
              phase: :settled,
              owner_phase: :transferred,
              writer_control: :transferred,
              job_ref: ref,
              caller: caller,
              capability: capability
            } = b
        } = s
      ) do
    if share_deadline_current?(b) and b.owner_recipient == b.writer_recipient do
      request = Writer.request_share_control_prepare_close(s.journal_writer, b.token, b.operation)

      {:noreply,
       %{s | share_barrier: %{b | phase: :writer_preparing, request: request, from: from}}}
    else
      {:reply, {:error, :cleanup_unconfirmed}, poison_session_share(s)}
    end
  end

  def handle_call(
        {:session_share_transaction_close, ref, capability},
        {caller, _},
        %{
          share_barrier:
            %{
              controlled: true,
              owner_protocol: :legacy,
              phase: :settled,
              owner_phase: :transferred,
              writer_control: :closing,
              job_ref: ref,
              caller: caller,
              capability: capability
            } = b
        } = s
      ) do
    if share_deadline_current?(b) and b.owner_recipient == b.writer_recipient do
      {:reply, :ok, %{s | share_barrier: %{b | phase: :transaction_closing}}}
    else
      {:reply, {:error, :cleanup_unconfirmed}, poison_session_share(s)}
    end
  end

  def handle_call(
        {:session_share_writer_close, ref, capability},
        {caller, _} = from,
        %{
          share_barrier:
            %{
              controlled: true,
              owner_protocol: :legacy,
              phase: :transaction_closed,
              writer_control: :closing,
              job_ref: ref,
              caller: caller,
              capability: capability
            } = b
        } = s
      ) do
    if share_deadline_current?(b) do
      request = Writer.request_share_control_close(s.journal_writer, b.token, b.operation)

      {:noreply,
       %{s | share_barrier: %{b | phase: :writer_closing, request: request, from: from}}}
    else
      {:reply, {:error, :cleanup_unconfirmed}, poison_session_share(s)}
    end
  end

  def handle_call(
        {:session_share_synthetic_review_manifest, ref, capability, prefix},
        {caller, _},
        %{
          share_barrier:
            %{
              controlled: true,
              owner_protocol: protocol,
              phase: :armed,
              owner_phase: :ready,
              job_ref: ref,
              caller: caller,
              capability: capability,
              issued_terminal: %{port: port}
            } = b
        } = s
      )
      when is_binary(prefix) and
             protocol in [:synthetic_review, :managed_approval, :managed_relation_review] do
    if not Map.get(b, :manifest_issued, false) and share_deadline_current?(b) and
         Port.info(port, :connected) == {:connected, caller} and
         synthetic_review_manifest?(prefix, b) do
      payload =
        case protocol do
          :managed_approval -> s.managed_approval.display
          :managed_relation_review -> b.review_payload
          _ -> @synthetic_review_text
        end

      body = <<prefix::binary, byte_size(payload)::32, payload::binary>>

      if Port.command(port, <<?I, byte_size(body)::32, body::binary>>, [:nosuspend]) do
        {:reply, :ok, %{s | share_barrier: Map.put(b, :manifest_issued, true)}}
      else
        {:reply, {:error, :cleanup_unconfirmed}, poison_session_share(s)}
      end
    else
      {:reply, {:error, :cleanup_unconfirmed}, poison_session_share(s)}
    end
  rescue
    _ -> {:reply, {:error, :cleanup_unconfirmed}, poison_session_share(s)}
  end

  def handle_call(
        {:session_control_configure, ref, capability, recipient, name, secret},
        {caller, _},
        %{
          share_barrier:
            %{
              controlled: true,
              phase: :armed,
              owner_phase: :ready,
              caller: caller,
              job_ref: ref,
              capability: capability
            } = b
        } = s
      ) do
    if (b.owner_protocol not in [
          :synthetic_notice,
          :synthetic_review,
          :managed_approval,
          :managed_relation_review
        ] or
          Map.has_key?(b, :issued_terminal)) and
         (b.owner_protocol not in [:synthetic_review, :managed_approval, :managed_relation_review] or
            Map.get(b, :manifest_issued, false)) and
         (not Map.has_key?(b, :writer_control) or
            (b.writer_control == :transferred and b.writer_recipient == recipient)) and
         (not Map.has_key?(b, :issued_terminal) or b.issued_terminal.pid == recipient) and
         System.monotonic_time(:millisecond) < b.deadline and
         Ipse.Runner.send_owner_control(
           b.owner_port,
           b.operation,
           :session,
           recipient,
           name,
           secret
         ) == :ok do
      {:reply, :ok,
       %{s | share_barrier: Map.merge(b, %{owner_phase: :sending, owner_recipient: recipient})}}
    else
      {:reply, {:error, :cleanup_unconfirmed}, poison_session_share(s)}
    end
  end

  def handle_call(
        {:session_share_review_thaw, ref, capability, terminal_port},
        {caller, _} = from,
        %{
          share_barrier:
            %{
              owner_protocol: protocol,
              phase: :settled,
              owner_phase: :transferred,
              job_ref: ref,
              caller: caller,
              capability: capability,
              issued_terminal: %{port: terminal_port, pid: recipient}
            } = b
        } = s
      )
      when is_port(terminal_port) and
             protocol in [:synthetic_review, :managed_approval, :managed_relation_review] do
    if Map.get(b, :notice_received, false) and
         Port.info(terminal_port, :connected) == {:connected, caller} and
         Port.info(terminal_port, :os_pid) == {:os_pid, recipient} and Process.alive?(caller) and
         share_deadline_current?(b) do
      request = :gen_server.send_request(s.journal_writer, {:share_thaw, b.token, b.operation})

      {:noreply,
       %{s | share_barrier: %{b | phase: :review_thawing, request: request, from: from}}}
    else
      {:reply, {:error, :cleanup_unconfirmed}, poison_session_share(s)}
    end
  end

  def handle_call(
        {:session_share_finish, ref, capability},
        {caller, _},
        %{
          share_barrier:
            %{
              owner_protocol: protocol,
              phase: :review_closed,
              job_ref: ref,
              caller: caller,
              capability: capability
            } = b
        } = s
      )
      when protocol in [:synthetic_review, :managed_approval, :managed_relation_review] do
    if share_deadline_current?(b) and Port.info(b.host_port) == nil and
         Port.info(b.owner_port) == nil and Port.info(b.issued_terminal.port) == nil do
      Process.cancel_timer(b.timer)
      {:reply, :ok, %{s | share_barrier: nil}}
    else
      {:reply, {:error, :cleanup_unconfirmed}, poison_session_share(s)}
    end
  end

  def handle_call(
        {:session_share_identity, ref, capability},
        {caller, _} = from,
        %{
          share_barrier:
            %{
              controlled: true,
              phase: :armed,
              job_ref: ref,
              caller: caller,
              capability: capability
            } = b
        } = s
      ) do
    if System.monotonic_time(:millisecond) < b.deadline do
      request =
        Ipse.Session.Lock.request_share_identity(s.lock_guard, b.token, b.operation, b.deadline)

      {:noreply, %{s | share_barrier: %{b | phase: :identifying, request: request, from: from}}}
    else
      {:reply, {:error, :cleanup_unconfirmed}, poison_session_share(s)}
    end
  end

  def handle_call(
        {:session_share_export, ref, capability, request},
        {caller, _} = from,
        %{
          share_barrier:
            %{phase: :armed, job_ref: ref, caller: caller, capability: capability} = b
        } = s
      )
      when is_binary(request) and byte_size(request) == 68 do
    if System.monotonic_time(:millisecond) < b.deadline do
      pending =
        Ipse.Session.Lock.request_share_export(
          s.lock_guard,
          b.token,
          b.operation,
          request,
          b.deadline
        )

      {:noreply, %{s | share_barrier: %{b | phase: :exporting, request: pending, from: from}}}
    else
      {:reply, {:error, :cleanup_unconfirmed}, poison_session_share(s)}
    end
  end

  def handle_call(
        {:session_share_settle, ref, capability},
        {caller, _} = from,
        %{
          share_barrier:
            %{phase: :exported, job_ref: ref, caller: caller, capability: capability} = b
        } = s
      ) do
    if System.monotonic_time(:millisecond) < b.deadline do
      pending =
        Ipse.Session.Lock.request_share_settle(s.lock_guard, b.token, b.operation, b.deadline)

      {:noreply, %{s | share_barrier: %{b | phase: :settling, request: pending, from: from}}}
    else
      {:reply, {:error, :cleanup_unconfirmed}, poison_session_share(s)}
    end
  end

  def handle_call(
        {:session_share_terminal_close, ref, capability, terminal_port},
        {caller, _},
        %{
          share_barrier:
            %{
              controlled: true,
              phase: :settled,
              owner_phase: :transferred,
              owner_recipient: recipient,
              job_ref: ref,
              caller: caller,
              capability: capability
            } = b
        } = s
      )
      when is_port(terminal_port) do
    if b.owner_protocol not in [:synthetic_review, :managed_approval, :managed_relation_review] and
         (b.owner_protocol != :synthetic_notice or Map.get(b, :notice_received, false)) and
         (not Map.has_key?(b, :issued_terminal) or b.issued_terminal.port == terminal_port) and
         Port.info(terminal_port, :connected) == {:connected, caller} and
         Port.info(terminal_port, :os_pid) == {:os_pid, recipient} and
         Process.alive?(caller) and share_deadline_current?(b) do
      {:reply, :ok,
       %{
         s
         | share_barrier: Map.merge(b, %{phase: :terminal_closing, terminal_port: terminal_port})
       }}
    else
      {:reply, {:error, :cleanup_unconfirmed}, poison_session_share(s)}
    end
  end

  def handle_call(
        {:session_share_finish, ref, capability},
        {caller, _} = from,
        %{
          share_barrier: %{phase: phase, job_ref: ref, caller: caller, capability: capability} = b
        } = s
      )
      when phase in [:settled, :terminal_closed, :transaction_closed] do
    case if(
           not share_deadline_current?(b) or Map.has_key?(b, :writer_control) or
             (Map.has_key?(b, :issued_terminal) and phase != :terminal_closed),
           do: {:error, :cleanup_unconfirmed},
           else: close_share_controls(b)
         ) do
      {:ok, next} ->
        request = :gen_server.send_request(s.journal_writer, {:share_thaw, b.token, b.operation})
        {:noreply, %{s | share_barrier: %{next | phase: :thawing, request: request, from: from}}}

      _ ->
        {:reply, {:error, :cleanup_unconfirmed}, poison_session_share(s)}
    end
  end

  def handle_call(
        {:session_share_abort, ref, capability},
        {caller, _} = from,
        %{
          share_barrier:
            %{phase: :armed, job_ref: ref, caller: caller, capability: capability} = b
        } = s
      ) do
    case close_share_controls(b) do
      {:ok, next} ->
        request = Ipse.Session.Lock.request_share_cancel(s.lock_guard, b.token, b.operation)

        {:noreply,
         %{s | share_barrier: %{next | phase: :cancelling, request: request, from: from}}}

      _ ->
        {:reply, {:error, :cleanup_unconfirmed}, poison_session_share(s)}
    end
  end

  def handle_call(
        {:session_share_abort, ref, capability},
        {caller, _},
        %{share_barrier: %{job_ref: ref, caller: caller, capability: capability}} = s
      ),
      do: {:reply, {:error, :cleanup_unconfirmed}, poison_session_share(s)}

  def handle_call(
        {:managed_sources, ref, {:snapshot, "tool.approval", _} = binding, proofs},
        {caller, _},
        %{
          phase: :managed_approval,
          job_ref: ref,
          share_barrier: %{
            owner_protocol: :managed_approval,
            phase: :review_input,
            caller: caller,
            source_proofs: expected
          }
        } = s
      )
      when ref != nil do
    result =
      if proofs === expected,
        do: Ipse.Session.ManagedUse.sources(s, caller, binding, proofs),
        else: {:error, :collection_source_refused}

    {:reply, result, s}
  end

  def handle_call(
        {:managed_sources, ref, {:supersession, sha}, proofs},
        {caller, _},
        %{
          job_ref: ref,
          share_barrier: %{
            owner_protocol: :managed_relation_review,
            phase: :review_input,
            caller: caller,
            source_proofs: expected,
            relation_display_purpose_sha256: sha
          }
        } = s
      )
      when ref != nil do
    result =
      if proofs === expected,
        do: supersession_source_proofs(s, caller, sha, proofs),
        else: {:error, :collection_source_refused}

    {:reply, result, s}
  end

  def handle_call(
        {:observe_channel, channel, _, _},
        {reader, _},
        %{phase: :managed_approval, operator_channel: %{id: channel, reader: reader}} = s
      ),
      do: {:reply, {:error, :operator_input_busy}, %{s | chat_reoffer_snapshot: nil}}

  def handle_call(command, _from, %{share_barrier: barrier} = s)
      when command in [:cancel, :cancel_draft] and not is_nil(barrier),
      do: {:reply, {:error, :cleanup_unconfirmed}, poison_session_share(s)}

  def handle_call(:close, _from, %{share_barrier: barrier} = s) when not is_nil(barrier),
    do: {:stop, :normal, {:error, :cleanup_unconfirmed}, poison_session_share(s)}

  def handle_call(
        {:worker_input_select, ref, stage, payload},
        {caller, _},
        %{share_barrier: nil, job_ref: ref} = s
      )
      when ref != nil,
      do: Ipse.Session.WorkerInput.select(s, caller, stage, payload)

  def handle_call(
        {:worker_input_prepare, ref, worker, handle, stage, payload},
        {caller, _},
        %{share_barrier: nil, job_ref: ref} = s
      )
      when ref != nil,
      do: Ipse.Session.WorkerInput.prepare(s, caller, worker, handle, stage, payload)

  def handle_call(
        {:worker_input_finish, ref, id, status},
        {caller, _},
        %{share_barrier: nil, job_ref: ref} = s
      )
      when ref != nil,
      do: Ipse.Session.WorkerInput.finish(s, caller, id, status)

  def handle_call(
        {:worker_input_rebase, ref, id, observation, inspection},
        {caller, _},
        %{share_barrier: nil, job_ref: ref} = s
      )
      when ref != nil,
      do: Ipse.Session.WorkerInput.rebase(s, caller, id, observation, inspection)

  def handle_call(request, _, s)
      when elem(request, 0) in [
             :worker_input_select,
             :worker_input_prepare,
             :worker_input_finish,
             :worker_input_rebase
           ],
      do: {:reply, {:error, :worker_input_unavailable}, s}

  def handle_call(_, _, %{share_barrier: barrier} = s) when not is_nil(barrier),
    do: {:reply, {:error, :session_share_frozen}, s}

  def handle_call(
        {:extension_begin, ref, instance, stage},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, extension_intent: nil, phase: phase} = s
      )
      when ref != nil and phase in [:extension_prompt, :extension_presentation] do
    expected =
      if phase == :extension_prompt, do: "transform.prompt", else: "transform.presentation"

    entry = Enum.find(Map.get(s.config, :extensions, []), &(&1.identity["instance"] == instance))
    input = if phase == :extension_prompt, do: List.last(s.messages)["content"], else: s.final

    if stage == expected and entry != nil and stage in entry.identity["capabilities"] and
         Ipse.Extension.Registry.live?(entry.identity) do
      if stage == "transform.presentation" and not managed_empty?(s) do
        {:reply, {:error, :managed_presentation_input_unavailable}, s}
      else
        intent = Projection.intent(entry.identity, stage, input, s.messages)
        record(s, intent)
        {:reply, {:ok, intent, input}, %{s | extension_intent: intent}}
      end
    else
      {:reply, {:error, :extension_admission_refused}, s}
    end
  end

  def handle_call({:extension_begin, _, _, _}, _, s), do: {:reply, {:error, :cancelled}, s}

  def handle_call(
        {:extension_commit, ref, event},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, extension_intent: intent, phase: phase} = s
      )
      when ref != nil and intent != nil and phase in [:extension_prompt, :extension_presentation] do
    with {:ok, expected} <- Projection.build(intent, event["input"], event["result"]),
         true <- expected == event,
         true <- phase != :extension_presentation or event["input"] == s.final,
         true <- Ipse.Extension.Registry.live?(intent["identity"]),
         {:ok, messages} <- Projection.apply(s.messages, event) do
      record(s, event)
      s = managed_event(s, event, messages)
      final = if phase == :extension_presentation, do: event["output"], else: s.final
      {:reply, :ok, %{s | messages: messages, final: final, extension_intent: nil}}
    else
      _ -> {:reply, {:error, :invalid_extension_projection}, s}
    end
  end

  def handle_call({:extension_commit, _, _}, _, s), do: {:reply, {:error, :cancelled}, s}

  def handle_call(
        {:extension_event_begin, ref, instance, subscription, binding},
        {caller, _} = from,
        %{job_ref: ref, task: %{pid: caller}, phase: :extension_events, event_intent: nil} = s
      )
      when ref != nil do
    handle_call({:extension_event_begin, ref, instance, subscription}, from, %{
      s
      | invocation: %CurrentInvocation{semantic_binding: binding}
    })
  end

  def handle_call({:extension_event_begin, _, _, _, _}, _, s),
    do: {:reply, {:error, :cancelled}, s}

  def handle_call(
        {:extension_event_begin, ref, instance, subscription},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, phase: :extension_events, event_intent: nil} = s
      )
      when ref != nil do
    with entry when is_map(entry) <-
           Enum.find(s.config.extensions, &(&1.identity["instance"] == instance)),
         declaration when is_map(declaration) <-
           Enum.find(entry.subscriptions, &(&1["id"] == subscription)),
         true <- s.event_count < 10_000 and Ipse.Extension.Registry.live?(entry.identity),
         true <- Invocation.event_schedule(declaration) == s.event_schedule,
         fact =
           (case declaration["event"] do
              "prompt.received" -> s.event_received
              "prompt.effective_committed" -> s.event_committed
              "answer.committed" -> s.event_answer
            end),
         true <- fact != nil,
         {intent, payload} =
           Subscriptions.intent(entry.identity, declaration, fact.source, fact.record, s.turn_id) do
      record(s, intent)
      s = %{s | event_intent: intent, event_count: s.event_count + 1}

      if declaration["mode"] == "job" do
        facts = %{
          received: s.event_received,
          effective: s.event_committed,
          answer: s.event_answer
        }

        admission = s.config[:semantic_admission]

        protected =
          is_map(admission) and is_map(admission["pin"]) and admission["instance"] == instance

        binding = if protected, do: s.invocation.semantic_binding, else: {:ok, nil}

        prepared =
          with {:ok, binding} <- binding,
               true <- not protected or is_map(binding),
               do:
                 Invocation.prepare_event(
                   s.config,
                   entry,
                   intent,
                   payload,
                   facts,
                   s.id,
                   s.turn_id,
                   binding
                 )

        entry = Map.merge(entry, %{host_config: s.config, host_cwd: s.cwd})

        case prepared do
          {:ok, parent} when s.extension_invocations < 10_000 ->
            record(s, parent)
            s = managed_event(s, parent)

            {:reply, {:job, intent, entry, parent},
             %{
               s
               | invocation: %CurrentInvocation{parent: parent},
                 extension_invocations: s.extension_invocations + 1,
                 extension_mcp_context: nil
             }}

          _ ->
            {:reply, {:ok, intent, entry, nil}, s}
        end
      else
        payload =
          if declaration["view"] != "metadata" and not managed_empty?(s) do
            notify(
              s,
              {:status,
               "Managed private event delivery is unavailable; notification not started."}
            )

            nil
          else
            payload
          end

        {:reply, {:ok, intent, entry, payload}, s}
      end
    else
      _ -> {:reply, {:error, :event_admission_refused}, s}
    end
  end

  def handle_call(
        {:extension_event_commit, ref, result},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, phase: :extension_events, event_intent: intent} = s
      )
      when ref != nil and intent != nil do
    if Subscriptions.valid_result?(result, intent) and
         result["outcome"] not in ~w(completed failed) and
         (result["outcome"] != "not_started" or is_nil(s.invocation.parent)) and
         (result["outcome"] != "acknowledged" or
            Ipse.Extension.Registry.live?(intent["identity"])) do
      record(s, result)

      if result["outcome"] != "acknowledged" and not intent["declaration"]["required"],
        do:
          notify(
            s,
            {:status,
             "Optional event subscriber did not acknowledge; inspect its saved delivery receipt."}
          )

      {:reply, :ok,
       %{
         s
         | event_intent: nil,
           invocation:
             if(is_nil(s.invocation.parent), do: %CurrentInvocation{}, else: s.invocation),
           event_cleanup_failed: s.event_cleanup_failed or not result["cleanup_confirmed"]
       }}
    else
      {:reply, {:error, :event_result_refused}, s}
    end
  end

  def handle_call({:extension_event_begin, _, _, _}, _, s), do: {:reply, {:error, :cancelled}, s}
  def handle_call({:extension_event_commit, _, _}, _, s), do: {:reply, {:error, :cancelled}, s}

  def handle_call(
        {:extension_event_job_commit, ref, result},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, phase: :extension_events, event_intent: delivery} =
          s
      )
      when ref != nil and delivery != nil do
    case CurrentInvocation.commit_event_job(s, result) do
      {:ok, next, outcome} -> {:reply, {:ok, outcome}, next}
      _ -> {:reply, {:error, :event_job_result_refused}, s}
    end
  end

  def handle_call({:extension_event_job_commit, _, _}, _, s),
    do: {:reply, {:error, :cancelled}, s}

  def handle_call({:mcp_register, ref, resource}, _from, %{job_ref: ref} = s) when ref != nil do
    monitor = Process.monitor(resource)
    {:reply, :ok, %{s | mcp_resources: Map.put(s.mcp_resources, resource, monitor)}}
  end

  def handle_call({:mcp_register, _, _}, _from, s), do: {:reply, {:error, :cancelled}, s}

  def handle_call(
        {:delegation_register, ref, child, id, origin_call},
        {worker, _},
        %{job_ref: ref, task: %{pid: coordinator}, phase: phase} = s
      )
      when ref != nil and phase in [:tool, :delegated_approval] do
    call = hd(s.calls)

    expected =
      if call["function"]["name"] == "delegate_parallel",
        do: [call["id"] <> "/0", call["id"] <> "/1"],
        else: [call["id"]]

    if (worker == coordinator or MapSet.member?(s.delegation_workers, worker)) and
         origin_call in expected do
      :ok = Ipse.Session.Lock.track_session(child)

      event = %{
        "type" => "delegation_started",
        "child_id" => id,
        "call_id" => call["id"],
        "origin_call_id" => origin_call
      }

      source =
        record_source(s, event)

      monitor = Process.monitor(child)
      notify(s, {:subagent, id, :started})

      {:reply, :ok,
       %{
         s
         | child_usage: Ipse.Extension.ChildUsage.apply_parent(s.child_usage, event),
           delegation_resources:
             Map.put(s.delegation_resources, child, %{
               monitor: monitor,
               id: id,
               worker: worker,
               source: source,
               turn: s.turn_id,
               request: s.last_request_id,
               job_ref: ref,
               started: System.monotonic_time(:millisecond),
               down: false,
               finished: false
             })
       }}
    else
      {:reply, {:error, :cancelled}, s}
    end
  end

  def handle_call(
        {:delegation_worker, ref, worker},
        {coordinator, _},
        %{job_ref: ref, task: %{pid: coordinator}} = s
      )
      when ref != nil do
    if MapSet.size(s.delegation_workers) < 2,
      do: {:reply, :ok, %{s | delegation_workers: MapSet.put(s.delegation_workers, worker)}},
      else: {:reply, {:error, :worker_limit}, s}
  end

  def handle_call(
        {:delegation_children, ref},
        {coordinator, _},
        %{job_ref: ref, task: %{pid: coordinator}} = s
      )
      when ref != nil,
      do: {:reply, Map.keys(s.delegation_resources), s}

  def handle_call({:delegation_worker, _, _}, _, s), do: {:reply, {:error, :cancelled}, s}
  def handle_call({:delegation_children, _}, _, s), do: {:reply, [], s}

  def handle_call({:delegation_register, _, _, _, _}, _from, s),
    do: {:reply, {:error, :cancelled}, s}

  def handle_call({:delegation_finished, ref, child, status, reason, cleanup}, {worker, _}, s) do
    case s.delegation_resources[child] do
      %{worker: ^worker, job_ref: ^ref, finished: false} = resource when ref == s.job_ref ->
        event = Ipse.Tools.Delegation.child_finished(resource, status, reason, cleanup)

        if s.task != nil and Ipse.Tools.Delegation.valid_child_record?(event) do
          s = record_child_outcome(s, event)
          Process.demonitor(resource.monitor, [:flush])
          {:reply, :ok, next_delegated_approval(retire_child(s, child))}
        else
          {:reply, {:error, :cancelled}, s}
        end

      _ ->
        {:reply, {:error, :cancelled}, s}
    end
  end

  def handle_call(:planning_decisions, _from, s) do
    decisions =
      s.planning_decisions
      |> Enum.map(fn {id, decision} ->
        assistant_current? =
          if decision.receipt["version"] == 2 and decision.exited and not decision.attempted,
            do: planning_decision_source_current?(s, decision.receipt),
            else: true

        status = Ipse.Session.PlanningDecisions.status(decision, assistant_current?)

        %{"id" => id, "text" => decision.receipt["text"], "status" => status}
      end)
      |> Enum.sort_by(& &1["id"])

    {:reply, decisions, s}
  end

  def handle_call(:info, _from, s) do
    {:ok, execution_mode} = Ipse.Extension.Mode.capture(s.config)

    info =
      Map.take(s, [:id, :cwd, :phase, :usage, :final])
      |> Map.put(:runtime, runtime(s))
      |> Map.put(:execution_mode, execution_mode)
      |> Map.put(
        :context,
        Ipse.Session.Context.manifest(
          s.context_snapshot,
          s.context_drift,
          s.skill_drift,
          s.skills
        )
      )
      |> Map.put(:sandbox, Ipse.Tools.Sandbox.info(Map.get(s.config, :sandbox, :off)))
      |> Map.put(:mcp, Enum.map(Map.get(s.config, :mcp_servers, []), &Ipse.MCP.Config.manifest/1))
      |> Map.put(:subagents, Ipse.Tools.Delegation.enabled?(s.config))
      |> Map.put(:configuration, Map.get(s.config, :configuration))
      |> Map.put(:extensions, Ipse.Extension.Registry.manifests(s.config))
      |> Map.put(:accounting, Ipse.Usage.snapshot(s.accounting))
      |> Map.put(:extension_result, s.extension_result)
      |> Map.put(:draft, if(s.draft, do: Map.take(s.draft, [:id, :revision, :status])))
      |> Map.put(:question, if(s.question, do: Map.take(s.question, [:id, :arguments])))
      |> Map.put(:question_recovery, s.question_recovery)

    {:reply, info, s}
  end

  def handle_call(:subscribe_text, from, s), do: handle_call({:subscribe_text, 1}, from, s)

  def handle_call({:subscribe_text, version}, from, s),
    do: handle_call({:subscribe_text, version, false}, from, s)

  def handle_call({:subscribe_text, version, required}, {consumer, _}, %{phase: :idle} = s)
      when version in [1, 2] and is_boolean(required) do
    s = Turn.ensure_text_stream(s)
    result = Turn.subscribe_text_stream(s.text_stream, consumer, version, required)

    next =
      if match?({:ok, _}, result), do: %{s | text_required: s.text_required or required}, else: s

    {:reply, result, next}
  end

  def handle_call({:subscribe_text, version, _}, _, s) when version not in [1, 2],
    do: {:reply, {:error, :unsupported_text_version}, s}

  def handle_call({:subscribe_text, _, _}, _, s), do: {:reply, {:error, :busy}, s}

  def handle_call(
        {:unsubscribe_text, %{server: stream, subscription_id: id} = handle},
        _,
        %{phase: :idle, text_stream: stream} = s
      )
      when is_pid(stream) and is_binary(id) do
    if Process.alive?(stream) do
      result =
        try do
          Ipse.Session.TextStream.unsubscribe(handle)
        catch
          :exit, _ -> {:error, :text_stream_unavailable}
        end

      {:reply, result, s}
    else
      if s.text_stream_monitor, do: Process.demonitor(s.text_stream_monitor, [:flush])
      {:reply, :ok, %{s | text_stream: nil, text_stream_monitor: nil, text_required: false}}
    end
  end

  def handle_call({:unsubscribe_text, _}, _, s),
    do: {:reply, {:error, :text_unsubscribe_refused}, s}

  def handle_call(
        {:extension_text_begin, ref, identity},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, phase: :extension_text_start} = s
      )
      when ref != nil do
    duplicate =
      Enum.any?(s.extension_text, fn {_, resource} ->
        resource.intent["identity"]["instance"] == identity["instance"]
      end)

    if identity in Ipse.Extension.Registry.manifests(s.config) and
         "stream.text" in identity["capabilities"] and
         Ipse.Extension.Registry.live?(identity) and not duplicate and
         s.extension_text_count < 10_000 and map_size(s.extension_text) < 4 do
      intent = Ipse.Extension.TextResources.intent(identity, s.id, s.turn_id)
      record(s, intent)

      resource = %{
        intent: intent,
        pid: nil,
        worker: nil,
        monitor: nil,
        subscription_id: nil,
        ready: false,
        closed: false
      }

      {:reply, {:ok, intent},
       %{
         s
         | extension_text: Map.put(s.extension_text, intent["resource_id"], resource),
           extension_text_count: s.extension_text_count + 1
       }}
    else
      {:reply, {:error, :extension_text_refused}, s}
    end
  end

  def handle_call(
        {:extension_text_register, ref, intent, consumer},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, phase: :extension_text_start} = s
      )
      when ref != nil do
    with %{intent: ^intent, pid: nil} = resource <- s.extension_text[intent["resource_id"]],
         true <- is_pid(consumer) and Process.alive?(consumer),
         s = Turn.ensure_text_stream(s),
         {:ok, handle} <-
           Turn.subscribe_text_stream(
             s.text_stream,
             consumer,
             Ipse.Extension.TextResources.frame_version(intent["identity"]),
             intent["identity"]["text_required"] == true
           ) do
      resource = %{
        resource
        | pid: consumer,
          monitor: Process.monitor(consumer),
          subscription_id: handle.subscription_id
      }

      s = %{s | text_required: s.text_required or intent["identity"]["text_required"] == true}

      {:reply, {:ok, handle},
       %{s | extension_text: Map.put(s.extension_text, intent["resource_id"], resource)}}
    else
      _ -> {:reply, {:error, :extension_text_refused}, s}
    end
  end

  def handle_call({:extension_text_worker, id, worker}, {consumer, _}, s) do
    case s.extension_text[id] do
      %{pid: ^consumer, worker: nil} = resource when is_pid(worker) ->
        if Process.alive?(consumer) and Process.alive?(worker) do
          {:reply, :ok,
           %{s | extension_text: Map.put(s.extension_text, id, %{resource | worker: worker})}}
        else
          {:reply, {:error, :extension_text_refused}, s}
        end

      _ ->
        {:reply, {:error, :extension_text_refused}, s}
    end
  end

  def handle_call(
        {:extension_text_ready, ref, intent, consumer},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, phase: :extension_text_start} = s
      )
      when ref != nil do
    with %{intent: ^intent, pid: ^consumer, ready: false, closed: false} = resource <-
           s.extension_text[intent["resource_id"]],
         true <- Process.alive?(consumer) and Process.alive?(resource.worker),
         true <-
           Ipse.Session.TextStream.enrolled?(s.text_stream, resource.subscription_id, consumer),
         true <- Ipse.Extension.Registry.live?(intent["identity"]) do
      record(s, Ipse.Extension.TextResources.ready(intent))

      {:reply, :ok,
       %{
         s
         | extension_text:
             Map.put(s.extension_text, intent["resource_id"], %{resource | ready: true})
       }}
    else
      _ -> {:reply, {:error, :extension_text_refused}, s}
    end
  end

  def handle_call({:extension_text_begin, _, _}, _, s),
    do: {:reply, {:error, :extension_text_refused}, s}

  def handle_call(
        {:extension_text_abort, ref, intent},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, phase: :extension_text_start} = s
      )
      when ref != nil do
    case s.extension_text[intent["resource_id"]] do
      %{intent: ^intent, pid: nil} ->
        record(s, Ipse.Extension.TextResources.closed(intent, "startup_failed", nil, nil, true))
        {:reply, :ok, %{s | extension_text: Map.delete(s.extension_text, intent["resource_id"])}}

      _ ->
        {:reply, :ok, s}
    end
  end

  def handle_call({:extension_text_abort, _, _}, _, s),
    do: {:reply, {:error, :extension_text_refused}, s}

  def handle_call({:extension_text_register, _, _, _}, _, s),
    do: {:reply, {:error, :extension_text_refused}, s}

  def handle_call({:extension_text_ready, _, _, _}, _, s),
    do: {:reply, {:error, :extension_text_refused}, s}

  def handle_call(:exports, _, s), do: {:reply, s.extension_catalog, s}

  def handle_call({:invoke_export, _, _, _}, _, %{draft: %{status: status}} = s)
      when status in [:pending, :completed, :accepted],
      do: {:reply, {:error, :draft_recovery_required}, s}

  def handle_call(
        {:invoke_export, _, _, _},
        _,
        %{draft: %{status: :cancelled, notice: false}} = s
      ),
      do: {:reply, {:error, :draft_recovery_required}, s}

  def handle_call(
        {:invoke_export, _, _, _},
        _,
        %{draft: %{status: :consumed, accepted_message: false}} = s
      ),
      do: {:reply, {:error, :draft_recovery_required}, s}

  def handle_call({:invoke_export, kind, name, arguments}, _, %{phase: :idle} = s)
      when kind in [:command, :service] do
    CurrentInvocation.invoke_export(s, kind, name, arguments)
  end

  def handle_call({:invoke_export, _, _, _}, _, s),
    do: {:reply, {:error, :extension_unavailable_or_busy}, s}

  def handle_call(
        {:extension_invoke_begin, ref, stage, name, arguments},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, invocation: %{parent: nil}, phase: phase} = s
      )
      when ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events] do
    CurrentInvocation.begin(s, ref, stage, name, arguments, phase)
  end

  def handle_call({:extension_invoke_begin, _, _, _, _}, _, s),
    do: {:reply, {:error, :cancelled}, s}

  def handle_call(
        {:extension_output_begin, ref, offer},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, extension_output: nil, phase: phase} = s
      )
      when ref != nil and phase in [:tool, :extension_command] do
    CurrentInvocation.open_output(s, offer)
  end

  def handle_call(
        {:extension_output_chunk, ref, output_id, reply},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, extension_output: %{id: output_id} = active} = s
      )
      when ref != nil do
    CurrentInvocation.push_output(s, output_id, reply, active)
  end

  def handle_call(
        {:extension_output_seal, ref, %ResultSource.Sealed{} = proof},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, extension_output: active} = s
      )
      when ref != nil and active != nil do
    CurrentInvocation.seal_output(s, proof, active)
  end

  def handle_call({:extension_output_begin, _, _}, _, s),
    do: {:reply, {:error, :output_admission_refused}, s}

  def handle_call({:extension_output_chunk, _, _, _}, _, s),
    do: {:reply, {:error, :output_fragment_refused}, s}

  def handle_call({:extension_output_seal, _, _}, _, s),
    do: {:reply, {:error, :output_seal_refused}, s}

  def handle_call({:saved_result_materialize, delivery}, _, s),
    do: {:reply, ResultSource.readable_source(s.extension_result_sources, delivery), s}

  def handle_call({:saved_result_read, request}, _, s),
    do: {:reply, CurrentInvocation.readable_output(s, request, false), s}

  def handle_call(
        {:saved_result_model_read, ref, request},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, phase: :tool} = s
      )
      when ref != nil do
    CurrentInvocation.read_model_output(s, request)
  end

  def handle_call({:saved_result_model_read, _, _}, _, s),
    do: {:reply, {:error, :saved_result_read_refused}, s}

  def handle_call(
        {:extension_tool_context, ref, request},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, invocation: %{action: nil}, phase: phase} = s
      )
      when ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events] do
    CurrentInvocation.tool_context(s, request)
  end

  def handle_call({:extension_tool_context, _, _}, _, s),
    do: {:reply, {:error, :extension_tool_context_refused}, s}

  def handle_call(
        {:extension_tool_context_commit, ref, request, old_hash, snapshot, drift},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, invocation: %{action: nil}, phase: phase} = s
      )
      when ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events] do
    CurrentInvocation.commit_tool_context(s, ref, request, old_hash, snapshot, drift)
  end

  def handle_call({:extension_tool_context_commit, _, _, _, _, _}, _, s),
    do: {:reply, {:error, :extension_tool_context_refused}, s}

  def handle_call(
        {:extension_mcp_prepare, ref, request},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, invocation: %{action: nil}, phase: phase} = s
      )
      when ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events] do
    CurrentInvocation.prepare_mcp(s, ref, request)
  end

  def handle_call({:extension_mcp_prepare, _, _}, _, s),
    do: {:reply, {:error, :extension_mcp_refused}, s}

  def handle_call(
        {:extension_mcp_bound, ref, request, descriptor, binding},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, invocation: %{action: nil}, phase: phase} = s
      )
      when ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events] do
    CurrentInvocation.bind_mcp(s, ref, request, descriptor, binding)
  end

  def handle_call({:extension_mcp_bound, _, _, _, _}, _, s),
    do: {:reply, {:error, :extension_mcp_refused}, s}

  def handle_call(
        {:extension_document_prepare, ref, request},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, invocation: %{action: nil}, phase: phase} = s
      )
      when ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events],
      do: CurrentInvocation.prepare_document(s, ref, request)

  def handle_call(
        {:extension_document_bound, ref, request, binding},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, invocation: %{action: nil}, phase: phase} = s
      )
      when ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events],
      do: CurrentInvocation.bind_document(s, ref, request, binding)

  def handle_call(
        {:extension_document_current, ref, intent},
        {caller, _},
        %{
          job_ref: ref,
          task: %{pid: worker},
          invocation: %{action: %{intent: intent}},
          phase: phase
        } = s
      )
      when ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events] do
    if caller == worker or Ipse.Session.Resources.authorized_effect?(worker, caller),
      do: CurrentInvocation.document_current(s, intent),
      else: {:reply, {:error, :document_store_refused}, s}
  end

  # The actual Worker registers one live reader for this exact action.
  def handle_call(
        {:extension_workspace_snapshot_register, ref, intent, reader, peer, token},
        {worker, _},
        %{job_ref: ref, task: %{pid: worker}, invocation: %{action: %{intent: intent} = action}} =
          s
      )
      when ref != nil and is_pid(reader) and is_pid(peer) and is_reference(token) do
    if is_nil(action[:workspace_snapshot_reader]) and
         Ipse.Extension.Collection.WorkspaceDocumentGuard.guarded_request?(intent["request"]) and
         Ipse.Session.Resources.authorized_task?(worker, reader) and
         Process.alive?(peer) and peer != worker and peer != self() and
         match?({:reply, :ok, ^s}, CurrentInvocation.document_current(s, intent)) do
      bound = %{reader: reader, token: token, peer: peer, bound: false, used: false}

      {:reply, :ok,
       put_in(s.invocation.action, Map.put(action, :workspace_snapshot_reader, bound))}
    else
      {:reply, {:error, :document_store_refused}, s}
    end
  end

  def handle_call({:extension_workspace_snapshot_register, _, _, _, _, _}, _, s),
    do: {:reply, {:error, :document_store_refused}, s}

  # Only this actual Session can activate the already tracked dormant peer.
  def handle_call(
        {:extension_workspace_snapshot_activate, ref, intent, reader, peer, token},
        {worker, _},
        %{
          job_ref: ref,
          task: %{pid: worker},
          invocation: %{action: %{intent: intent, workspace_snapshot_reader: bound}}
        } = s
      )
      when ref != nil and is_pid(reader) and is_pid(peer) and is_reference(token) do
    if peer != worker and peer != self() and
         bound === %{reader: reader, token: token, peer: peer, bound: false, used: false} and
         Ipse.Session.Resources.authorized_task?(worker, reader) and
         Ipse.Session.Resources.authorized_effect?(worker, peer) and
         match?({:reply, :ok, ^s}, CurrentInvocation.document_current(s, intent)) and
         Ipse.Session.Resources.activate_document_effect(worker, peer) === :ok,
       do: {:reply, :ok, s},
       else: {:reply, {:error, :document_store_refused}, s}
  end

  def handle_call({:extension_workspace_snapshot_activate, _, _, _, _, _}, _, s),
    do: {:reply, {:error, :document_store_refused}, s}

  # Derive the peer from the actual caller, never from an embedded PID.
  def handle_call(
        {:extension_workspace_snapshot_bind, ref, intent, reader, token},
        {peer, _},
        %{
          job_ref: ref,
          task: %{pid: worker},
          invocation: %{action: %{intent: intent, workspace_snapshot_reader: bound} = action}
        } = s
      )
      when ref != nil and is_pid(reader) and is_reference(token) do
    if bound === %{reader: reader, token: token, peer: peer, bound: false, used: false} and
         Ipse.Session.Resources.authorized_task?(worker, reader) and
         Ipse.Session.Resources.authorized_effect?(worker, peer) and
         peer != worker and
         match?({:reply, :ok, ^s}, CurrentInvocation.document_current(s, intent)) do
      bound = %{bound | bound: true}

      {:reply, :ok,
       put_in(s.invocation.action, Map.put(action, :workspace_snapshot_reader, bound))}
    else
      {:reply, {:error, :document_store_refused}, s}
    end
  end

  def handle_call({:extension_workspace_snapshot_bind, _, _, _, _}, _, s),
    do: {:reply, {:error, :document_store_refused}, s}

  # Only that registered reader can consume the request for the bound peer.
  def handle_call(
        {:extension_workspace_snapshot_peer, ref, intent, peer, token},
        {reader, _},
        %{
          job_ref: ref,
          task: %{pid: worker},
          invocation: %{action: %{intent: intent, workspace_snapshot_reader: bound} = action}
        } = s
      )
      when ref != nil and is_pid(peer) and is_reference(token) do
    if bound === %{reader: reader, token: token, peer: peer, bound: true, used: false} and
         Ipse.Session.Resources.authorized_task?(worker, reader) and
         Ipse.Session.Resources.authorized_effect?(worker, peer) and
         match?({:reply, :ok, ^s}, CurrentInvocation.document_current(s, intent)) do
      bound = %{bound | used: true}

      {:reply, :ok,
       put_in(s.invocation.action, Map.put(action, :workspace_snapshot_reader, bound))}
    else
      {:reply, {:error, :document_store_refused}, s}
    end
  end

  def handle_call({:extension_workspace_snapshot_peer, _, _, _, _}, _, s),
    do: {:reply, {:error, :document_store_refused}, s}

  def handle_call(
        {:extension_workspace_document_authorize, ref, intent, document},
        {caller, _},
        %{
          job_ref: ref,
          task: %{pid: worker},
          invocation: %{action: %{intent: intent}},
          phase: phase
        } = s
      )
      when ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events] do
    reply =
      if caller == worker or Ipse.Session.Resources.authorized_effect?(worker, caller) do
        case CurrentInvocation.document_current(s, intent) do
          {:reply, :ok, ^s} ->
            Ipse.Extension.Collection.WorkspaceDocumentGuard.authorize(s, intent, document)

          _ ->
            {:error, :document_store_refused}
        end
      else
        {:error, :document_store_refused}
      end

    {:reply, reply, s}
  end

  def handle_call({:extension_workspace_document_authorize, _, _, _}, _, s),
    do: {:reply, {:error, :document_store_refused}, s}

  def handle_call({:extension_document_prepare, _, _}, _, s),
    do: {:reply, {:error, :document_store_refused}, s}

  def handle_call({:extension_document_bound, _, _, _}, _, s),
    do: {:reply, {:error, :document_store_refused}, s}

  def handle_call({:extension_document_current, _, _}, _, s),
    do: {:reply, {:error, :document_store_refused}, s}

  def handle_call(
        {:extension_document_embedding_prepare, ref, request},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, invocation: %{action: nil}, phase: phase} = s
      )
      when ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events],
      do: CurrentInvocation.prepare_document_embedding(s, ref, request)

  def handle_call(
        {:extension_document_embedding_bound, ref, request, binding},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}, invocation: %{action: nil}, phase: phase} = s
      )
      when ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events],
      do: CurrentInvocation.bind_document_embedding(s, ref, request, binding)

  def handle_call(
        {:document_embedding_admit, ref, phase, admission, expected, wire, sources},
        {caller, _},
        %{job_ref: ref, task: %{pid: worker}, invocation: %{action: %{intent: _}}, phase: current} =
          s
      )
      when ref != nil and
             current in [:tool, :extension_command, :extension_service, :extension_events] do
    if caller == worker or Ipse.Session.Resources.authorized_effect?(worker, caller),
      do:
        Ipse.Session.InferenceDispatch.document_admit(
          s,
          caller,
          phase,
          admission,
          expected,
          wire,
          sources
        ),
      else: {:reply, {:error, :document_source_use_refused}, s}
  end

  def handle_call({:extension_document_embedding_prepare, _, _}, _, s),
    do: {:reply, {:error, :document_source_use_refused}, s}

  def handle_call({:extension_document_embedding_bound, _, _, _}, _, s),
    do: {:reply, {:error, :document_source_use_refused}, s}

  def handle_call({:document_embedding_admit, _, _, _, _, _, _}, _, s),
    do: {:reply, {:error, :document_source_use_refused}, s}

  def handle_call(
        {:document_embedding_claim_put, ref, intent, observation},
        {caller, _},
        %{
          job_ref: ref,
          task: %{pid: worker},
          invocation: %{action: %{intent: intent}},
          phase: phase
        } = s
      )
      when ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events] do
    if caller == worker or Ipse.Session.Resources.authorized_effect?(worker, caller),
      do: Ipse.Session.DocumentEmbedding.prepare_inline(s, intent, observation),
      else: {:reply, {:error, :document_source_use_refused}, s}
  end

  def handle_call({:document_embedding_claim_put, _, _, _}, _, s),
    do: {:reply, {:error, :document_source_use_refused}, s}

  def handle_call(
        {:extension_action_begin, ref, request},
        from = {caller, _},
        %{job_ref: ref, task: %{pid: caller}, invocation: %{action: nil}, phase: phase} = s
      )
      when ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events] do
    CurrentInvocation.begin_action(s, request, from, phase)
  end

  def handle_call({:extension_action_begin, _, _}, _, s),
    do: {:reply, {:error, :extension_action_refused}, s}

  def handle_call(
        {:extension_managed_approval_finish, ref, result},
        {caller, _},
        %{
          job_ref: ref,
          task: %{pid: caller},
          phase: :managed_approval,
          managed_approval: %{input: %{"kind" => "extension.action.approval"}}
        } = s
      )
      when ref != nil,
      do: Ipse.Session.ManagedApproval.complete_extension(s, result)

  def handle_call({:extension_managed_approval_finish, _, _}, _, s),
    do: {:reply, {:error, :managed_argument_display_unavailable}, s}

  def handle_call(
        {:extension_collection_sources, ref, intent},
        {caller, _},
        %{job_ref: ref, task: %{pid: worker}, invocation: %{action: %{intent: intent}}} = s
      )
      when ref != nil do
    reply =
      with true <-
             Ipse.Extension.CollectionCall.operation?(intent["request"]) or
               Ipse.Extension.ManagedCollectionCall.operation?(intent["request"]),
           true <- not s.invocation.interrupted,
           true <- Ipse.Extension.Registry.live?(s.invocation.parent["identity"]),
           true <- Ipse.Session.Resources.authorized_effect?(worker, caller),
           {:ok, origin} <- Writer.source_query(s.journal_writer, :origin),
           true <-
             is_map(origin) or
               (not Ipse.Extension.ManagedCollectionCall.operation?(intent["request"]) and
                  Map.get(intent["request"], "proofs", []) == []),
           {:ok, window} <- Writer.source_query(s.journal_writer, :snapshot),
           {:ok, context} <-
             Ipse.Extension.SemanticAdmission.context(s.config, s.id, window["generation"]) do
        proofs =
          Enum.map(Map.get(intent["request"], "proofs", []), fn request ->
            Writer.source_query(s.journal_writer, {:proof, request})
          end)

        if Enum.all?(proofs, &match?({:ok, _}, &1)),
          do: {:ok, context, Enum.map(proofs, fn {:ok, proof} -> proof end)},
          else: {:error, :collection_source_refused}
      else
        _ -> {:error, :collection_source_refused}
      end

    {:reply, reply, s}
  end

  def handle_call(
        {:inference_dispatch_intent, ref, phase, admission, expected, facts},
        {caller, _},
        %{job_ref: ref} = s
      )
      when ref != nil do
    Ipse.Session.InferenceDispatch.commit(s, caller, phase, admission, expected, facts)
  end

  def handle_call({:inference_dispatch_intent, _, _, _, _, _}, _, s),
    do: {:reply, {:error, :inference_dispatch_refused}, s}

  def handle_call(
        {:inference_wire_use, ref, phase, admission, expected, wire},
        {caller, _},
        %{job_ref: ref} = s
      )
      when ref != nil,
      do: Ipse.Session.InferenceDispatch.wire_use(s, caller, phase, admission, expected, wire)

  def handle_call({:inference_wire_use, _, _, _, _, _}, _, s),
    do: {:reply, {:error, :inference_dispatch_refused}, s}

  def handle_call({:managed_tool_effect_prepare, ref, binding}, {caller, _}, %{job_ref: ref} = s)
      when ref != nil,
      do: Ipse.Session.ManagedToolUse.prepare(s, caller, binding)

  def handle_call({:managed_tool_effect_prepare, _, _}, _, s),
    do: {:reply, {:error, :managed_tool_inputs_unavailable}, s}

  def handle_call(
        {:managed_tool_effect_admit, ref, id, deadline},
        {caller, _},
        %{job_ref: ref} = s
      )
      when ref != nil,
      do: Ipse.Session.ManagedToolUse.admit(s, caller, id, deadline)

  def handle_call({:managed_tool_effect_admit, _, _, _}, _, s),
    do: {:reply, {:error, :managed_tool_inputs_unavailable}, s}

  def handle_call(
        {:managed_tool_effect_cleanup, ref, id, status},
        {caller, _},
        %{job_ref: ref} = s
      )
      when ref != nil,
      do: Ipse.Session.ManagedToolUse.finish_effect(s, caller, id, status)

  def handle_call({:managed_tool_effect_cleanup, _, _, _}, _, s),
    do: {:reply, {:error, :managed_tool_inputs_unavailable}, s}

  def handle_call(
        {:managed_tool_result_prepare, ref, outcome, text},
        {caller, _},
        %{job_ref: ref} = s
      )
      when ref != nil,
      do: Ipse.Session.ManagedToolUse.prepare_result(s, caller, outcome, text)

  def handle_call({:managed_tool_result_prepare, _, _, _}, _, s),
    do: {:reply, {:error, :managed_tool_inputs_unavailable}, s}

  def handle_call(
        {:managed_tool_result_admit, ref, id, mode, deadline},
        {caller, _},
        %{job_ref: ref} = s
      )
      when ref != nil,
      do: Ipse.Session.ManagedToolUse.admit_result(s, caller, id, mode, deadline)

  def handle_call({:managed_tool_result_admit, _, _, _, _}, _, s),
    do: {:reply, {:error, :managed_tool_inputs_unavailable}, s}

  def handle_call(
        {:managed_tool_result_cleanup, ref, id, status},
        {caller, _},
        %{job_ref: ref} = s
      )
      when ref != nil,
      do: Ipse.Session.ManagedToolUse.finish_result(s, caller, id, status)

  def handle_call({:managed_tool_result_cleanup, _, _, _}, _, s),
    do: {:reply, {:error, :managed_tool_inputs_unavailable}, s}

  def handle_call(
        {:managed_result_admit, ref, phase, admission, expected, result_sha},
        {caller, _},
        %{job_ref: ref} = s
      )
      when ref != nil,
      do:
        Ipse.Session.InferenceDispatch.result_admit(
          s,
          caller,
          phase,
          admission,
          expected,
          result_sha
        )

  def handle_call({:managed_result_admit, _, _, _, _, _}, _, s),
    do: {:reply, {:error, :inference_dispatch_refused}, s}

  def handle_call(
        {:inference_service_status, ref, {event, _} = status},
        {caller, _},
        %{job_ref: ref, task: %{pid: caller}} = s
      )
      when ref != nil and event in [:inference_service_status, :inference_service_timing] do
    notify(s, status)
    {:reply, :ok, s}
  end

  def handle_call({:inference_service_status, _, _}, _, s),
    do: {:reply, {:error, :inference_dispatch_refused}, s}

  def handle_call({:extension_collection_sources, _, _}, _, s),
    do: {:reply, {:error, :collection_source_refused}, s}

  def handle_call(
        {:extension_stored_sources, ref, intent, proofs},
        {caller, _},
        %{job_ref: ref, task: %{pid: worker}, invocation: %{action: %{intent: intent}}} = s
      )
      when ref != nil do
    reply =
      with true <- Ipse.Extension.CollectionCall.operation?(intent["request"]),
           true <- not s.invocation.interrupted,
           true <- Ipse.Extension.Registry.live?(s.invocation.parent["identity"]),
           true <- Ipse.Session.Resources.authorized_effect?(worker, caller),
           true <- is_list(proofs) and length(proofs) in 1..8,
           true <- Enum.all?(proofs, &(is_map(&1) and &1["session_id"] == s.id)),
           {:ok, origin} when is_map(origin) <- Writer.source_query(s.journal_writer, :origin) do
        Enum.reduce_while(proofs, {:ok, []}, fn proof, {:ok, acc} ->
          case Writer.source_query(s.journal_writer, {:stored_proof, proof}) do
            {:ok, checked} -> {:cont, {:ok, acc ++ [checked]}}
            _ -> {:halt, {:error, :collection_source_refused}}
          end
        end)
      else
        _ -> {:error, :collection_source_refused}
      end

    {:reply, reply, s}
  end

  def handle_call({:extension_stored_sources, _, _, _}, _, s),
    do: {:reply, {:error, :collection_source_refused}, s}

  def handle_call(
        {:extension_managed_read, ref, intent, value, dependencies},
        {caller, _},
        %{job_ref: ref, task: %{pid: worker}, invocation: %{action: %{intent: intent} = action}} =
          s
      )
      when ref != nil do
    with true <- not s.invocation.interrupted and is_nil(action[:managed_read]),
         true <- Ipse.Extension.Registry.live?(s.invocation.parent["identity"]),
         true <- Ipse.Session.Resources.authorized_effect?(worker, caller),
         true <-
           Ipse.Session.ManagedReads.managed_mapping?(
             s.config[:semantic_admission],
             s.invocation.parent,
             intent
           ),
         {:ok, receipt} <-
           Ipse.Session.ManagedReads.prepare(
             s.id,
             intent,
             value,
             dependencies,
             s.invocation.parent
           ),
         true <-
           Ipse.Session.ManagedReads.covered?(
             s.config[:semantic_admission],
             s.invocation.parent,
             intent,
             value,
             receipt["dependencies"]
           ) do
      {:reply, :ok,
       %{s | invocation: %{s.invocation | action: Map.put(action, :managed_read, receipt)}}}
    else
      _ -> {:reply, {:error, :collection_source_refused}, s}
    end
  end

  def handle_call({:extension_managed_read, _, _, _, _}, _, s),
    do: {:reply, {:error, :collection_source_refused}, s}

  def handle_call({:managed_preflight_begin, ref, phase}, {caller, _}, %{job_ref: ref} = s)
      when ref != nil,
      do: managed_preflight_start(s, caller, phase)

  def handle_call(
        {:managed_preflight_commit, ref, id, verdicts},
        {caller, _},
        %{job_ref: ref} = s
      )
      when ref != nil,
      do: managed_preflight_finish(s, caller, id, verdicts)

  def handle_call({:managed_preflight_begin, _, _}, _, s),
    do: {:reply, {:error, :managed_reference_projection_unsafe}, s}

  def handle_call({:managed_preflight_commit, _, _, _}, _, s),
    do: {:reply, {:error, :managed_reference_projection_unsafe}, s}

  def handle_call({:extension_supersession, ref, intent}, {caller, _}, %{job_ref: ref} = s)
      when ref != nil do
    case supersession_lookup(s, caller, intent) do
      {:ok, nil} ->
        {:reply, {:ok, nil}, s}

      {:ok, reply} ->
        next = put_in(s.managed_supersession.candidate, intent)
        {:reply, {:ok, reply}, next}

      _ ->
        {:reply, {:error, :managed_supersession_refused}, s}
    end
  end

  def handle_call({:extension_supersession, _, _}, _, s),
    do: {:reply, {:error, :managed_supersession_refused}, s}

  def handle_call({:supersession_record, ref, sha, event}, {caller, _}, %{job_ref: ref} = s)
      when ref != nil,
      do: supersession_record(s, caller, sha, event)

  def handle_call({:supersession_record, _, _, _}, _, s),
    do: {:reply, {:error, :managed_supersession_refused}, s}

  def handle_call(
        {:managed_sources, ref, {:supersession, sha}, proofs},
        {caller, _},
        %{job_ref: ref} = s
      )
      when ref != nil do
    reply = supersession_source_proofs(s, caller, sha, proofs)

    {:reply, reply, s}
  end

  def handle_call({:managed_sources, ref, binding, proofs}, {caller, _}, %{job_ref: ref} = s)
      when ref != nil do
    {:reply, Ipse.Session.ManagedUse.sources(s, caller, binding, proofs), s}
  end

  def handle_call({:managed_sources, _, _, _}, _, s),
    do: {:reply, {:error, :collection_source_refused}, s}

  def handle_call({:managed_output_prepare, ref, kind, payload}, {caller, _}, %{job_ref: ref} = s)
      when ref != nil,
      do: Ipse.Session.ManagedOutput.prepare(s, caller, kind, payload)

  def handle_call(
        {:managed_output_admit, ref, id, mode, deadline},
        {caller, _},
        %{job_ref: ref} = s
      )
      when ref != nil,
      do: Ipse.Session.ManagedOutput.admit(s, caller, id, mode, deadline)

  def handle_call({:managed_output_cleanup, ref, id, status}, {caller, _}, %{job_ref: ref} = s)
      when ref != nil,
      do: Ipse.Session.ManagedOutput.finish(s, caller, id, status)

  def handle_call({:managed_output_event_complete, ref, id}, {caller, _}, %{job_ref: ref} = s)
      when ref != nil,
      do: Ipse.Session.ManagedOutput.complete_event(s, caller, id)

  def handle_call({:managed_output_prepare, _, _, _}, _, s),
    do: {:reply, {:error, :managed_output_unavailable}, s}

  def handle_call({:managed_output_admit, _, _, _, _}, _, s),
    do: {:reply, {:error, :managed_output_unavailable}, s}

  def handle_call({:managed_output_cleanup, _, _, _}, _, s),
    do: {:reply, {:error, :managed_output_unavailable}, s}

  def handle_call({:managed_output_event_complete, _, _}, _, s),
    do: {:reply, {:error, :managed_output_unavailable}, s}

  def handle_call(
        {:extension_effect_source, ref, intent, kind, data},
        {caller, _},
        %{
          job_ref: ref,
          task: %{pid: caller},
          invocation: %{action: %{intent: intent}},
          phase: phase
        } =
          s
      )
      when ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events] do
    CurrentInvocation.bind_effect_source(s, intent, kind, data)
  end

  def handle_call({:extension_effect_source, _, _, _, _}, _, s),
    do: {:reply, {:error, :extension_effect_source_refused}, s}

  def handle_call(
        {message, ref, intent},
        {caller, _},
        %{
          job_ref: ref,
          task: %{pid: caller},
          invocation: %{action: %{intent: intent}},
          extension_model: nil,
          phase: phase
        } = s
      )
      when message in [
             :extension_model_begin,
             :extension_embedding_begin,
             :extension_decision_begin
           ] and ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events] do
    CurrentInvocation.begin_inference(s, message, intent)
  end

  def handle_call({:extension_model_begin, _, _}, _, s),
    do: {:reply, {:error, :extension_model_refused}, s}

  def handle_call({:extension_embedding_begin, _, _}, _, s),
    do: {:reply, {:error, :extension_embedding_refused}, s}

  def handle_call({:extension_decision_begin, _, _}, _, s),
    do: {:reply, {:error, :extension_decision_refused}, s}

  def handle_call(
        {message, ref, id, usage},
        {caller, _},
        %{
          job_ref: ref,
          task: %{pid: caller},
          extension_model: %{admission: %{"request_id" => id} = admission}
        } = s
      )
      when message in [
             :extension_model_usage,
             :extension_embedding_usage,
             :extension_decision_usage
           ] and ref != nil do
    CurrentInvocation.observe_inference(s, message, id, usage, admission)
  end

  def handle_call({:extension_model_usage, _, _, _}, _, s),
    do: {:reply, {:error, :extension_model_refused}, s}

  def handle_call({:extension_embedding_usage, _, _, _}, _, s),
    do: {:reply, {:error, :extension_embedding_refused}, s}

  def handle_call({:extension_decision_usage, _, _, _}, _, s),
    do: {:reply, {:error, :extension_decision_refused}, s}

  def handle_call(
        {:extension_model_finish, ref, intent, result, capture, reason},
        {caller, _},
        %{
          job_ref: ref,
          task: %{pid: caller},
          invocation: %{action: %{intent: intent}},
          extension_model: %{admission: admission}
        } = s
      )
      when ref != nil do
    CurrentInvocation.finish_model(s, intent, result, capture, reason, admission)
  end

  def handle_call({:extension_model_finish, _, _, _, _, _}, _, s),
    do: {:reply, {:error, :extension_model_refused}, s}

  def handle_call(
        {:extension_embedding_finish, ref, intent, result, capture, reason},
        {caller, _},
        %{
          job_ref: ref,
          task: %{pid: caller},
          invocation: %{action: %{intent: intent}},
          extension_model: %{admission: admission, started: started}
        } = s
      )
      when ref != nil do
    CurrentInvocation.finish_embedding(s, intent, result, capture, reason, admission, started)
  end

  def handle_call({:extension_embedding_finish, _, _, _, _, _}, _, s),
    do: {:reply, {:error, :extension_embedding_refused}, s}

  def handle_call(
        {:extension_decision_finish, ref, intent, result, capture, reason},
        {caller, _},
        %{
          job_ref: ref,
          task: %{pid: caller},
          invocation: %{action: %{intent: intent}},
          extension_model: %{admission: admission, started: started}
        } = s
      )
      when ref != nil do
    CurrentInvocation.finish_decision(s, intent, result, capture, reason, admission, started)
  end

  def handle_call({:extension_decision_finish, _, _, _, _, _}, _, s),
    do: {:reply, {:error, :extension_decision_refused}, s}

  def handle_call(
        {:extension_action_commit, ref, event},
        {caller, _},
        %{
          job_ref: ref,
          task: %{pid: caller},
          invocation: %{action: %{intent: intent}},
          phase: phase
        } =
          s
      )
      when ref != nil and
             phase in [:tool, :extension_command, :extension_service, :extension_events] do
    CurrentInvocation.commit_action(s, event, intent)
  end

  def handle_call({:extension_action_commit, _, _}, _, s),
    do: {:reply, {:error, :extension_action_refused}, s}

  def handle_call(:permissions, _from, s),
    do: {:reply, Ipse.Session.Permissions.snapshot(s), s}

  def handle_call(:clear_permissions, _from, s) do
    record(s, %{"type" => "approval_grants_cleared"})
    {:reply, :ok, %{s | permissions: %{edits: false, commands: []}}}
  end

  def handle_call(:diagnostics, _from, s) do
    {:reply,
     %{
       "version" => 1,
       "phase" => Atom.to_string(s.phase),
       "observability" => Ipse.Observability.snapshot(s.observation),
       "extension_feeds" => Feeds.snapshot(s.feeds),
       "tool_events" => Ipse.Session.ToolLifecycle.snapshot(s.tool_lifecycle),
       "steps" => s.steps,
       "max_steps" => Map.get(s.config, :max_steps, 30),
       "approval_waiting" => not is_nil(s.approval),
       "question_waiting" => not is_nil(s.question),
       "active_worker" => not is_nil(s.task),
       "accounting" => Ipse.Usage.snapshot(s.accounting),
       "context" =>
         Ipse.Session.Context.measure(s.messages, s.config, Ipse.Session.Context.header(s)),
       "extension_context" => Ipse.Extension.Context.summary(s.extension_contributions),
       "extension_events" => %{
         "admitted_deliveries" => s.event_count,
         "delivery_pending" => s.event_intent != nil,
         "unconfirmed_cleanup" => s.event_cleanup_failed
       },
       "extension_text" => %{
         "active_consumers" =>
           Enum.count(s.extension_text, fn {_, resource} ->
             resource.ready and not resource.closed
           end),
         "unconfirmed_cleanup" => s.extension_text_cleanup_failed
       }
     }, s}
  end

  def handle_call(:stop_observability, _from, s) do
    capture = Ipse.Observability.stop(s.observation)
    {:reply, :ok, %{s | observation: capture}}
  end

  def handle_call(:stop_feeds, _from, s) do
    {cleanup, feeds} = Feeds.close(s.feeds, "stopped", &record(s, &1))
    result = if Enum.all?(cleanup, &(&1 == :ok)), do: :ok, else: {:error, :cleanup_unconfirmed}
    {:reply, result, %{s | feeds: feeds}}
  end

  def handle_call({:feed_worker, id, worker}, {caller, _}, s) when is_pid(worker) do
    case s.feeds.resources[id] do
      %{pid: ^caller, worker: nil, closed: false} = resource ->
        if FeedChannel.active?(resource),
          do: {:reply, :ok, put_in(s, [:feeds, :resources, id], %{resource | worker: worker})},
          else: {:reply, {:error, :feed_stopped}, s}

      _ ->
        {:reply, {:error, :feed_refused}, s}
    end
  end

  def handle_call(:observation_drain_state, _from, s),
    do:
      {:reply, %{idle: s.phase == :idle, capture: Ipse.Observability.snapshot(s.observation)}, s}

  def handle_call({:observer_worker, id, worker}, {caller, _}, s) when is_pid(worker) do
    case s.observation.resources[id] do
      %{pid: ^caller, worker: nil, closed: false} = resource ->
        if s.observation.policy["mode"] != "off" do
          {:reply, :ok, put_in(s, [:observation, :resources, id], %{resource | worker: worker})}
        else
          {:reply, {:error, :observation_revoked}, s}
        end

      _ ->
        {:reply, {:error, :observation_refused}, s}
    end
  end

  def handle_call(:refresh_context, _from, %{phase: phase} = s) when phase != :idle,
    do: {:reply, {:error, :busy}, s}

  def handle_call(:refresh_context, _from, s) do
    s = enroll_feeds(s)

    task =
      owned_task(fn ->
        with {:ok, snapshot} <- Workspace.snapshot(s.cwd, s.context_home) do
          discovered =
            Workspace.discover_skills(
              s.cwd,
              Path.join(s.context_home, "skills"),
              skill_discovery_options(s.config)
            )

          with {:ok, skills, _} <- Workspace.restore_skills([], discovered),
               do: {:ok, snapshot, Workspace.drift(snapshot), skills}
        end
      end)

    notify(s, {:status, :refreshing_context})
    {:reply, :ok, %{s | task: task, phase: :context_refresh, job_ref: nil}}
  end

  def handle_call({:open_input_channel, reader}, {client, _}, %{subscriber: client} = s)
      when is_pid(reader) and node(reader) == node() do
    if Process.alive?(reader) do
      :ok = Ipse.Session.Input.invalidate()

      if s.operator_channel do
        Process.demonitor(s.operator_channel.client_monitor, [:flush])
        Process.demonitor(s.operator_channel.reader_monitor, [:flush])
      end

      channel = %{
        id: Ipse.Usage.id(),
        generation: Ipse.Usage.id(),
        client: client,
        reader: reader,
        client_monitor: Process.monitor(client),
        reader_monitor: Process.monitor(reader)
      }

      {:reply, {:ok, channel.id},
       %{
         s
         | operator_channel: channel,
           chat_reoffer_snapshot: nil,
           operator_render: nil,
           draft_render: nil,
           assertion_render: nil,
           planning_decision_render: nil,
           operator_answers: %{},
           operator_pieces: []
       }}
    else
      {:reply, {:error, :operator_input_unavailable}, s}
    end
  end

  def handle_call({:open_input_channel, _}, _, s),
    do: {:reply, {:error, :operator_input_unavailable}, s}

  def handle_call(
        {:observe_channel, channel, request, timeout},
        {reader, _},
        %{operator_channel: %{id: channel, reader: reader}} = s
      ) do
    s = %{s | chat_reoffer_snapshot: nil}

    case if(s.phase == :managed_approval, do: :busy, else: operator_request(s, request)) do
      :busy ->
        {:reply, {:error, :operator_input_busy}, s}

      {:ok, display, purpose, render} ->
        {:ok, scope} = Ipse.Session.Resources.start(self())
        :ok = Ipse.Session.Lock.track(scope, :scope)

        result =
          Ipse.Session.Input.start(
            operator_binding(s, purpose, render),
            display,
            timeout,
            reader,
            scope
          )

        if not match?({:ok, _}, result), do: Ipse.Session.Resources.stop_async(scope)
        {:reply, result, s}

      _ ->
        {:reply, {:error, :operator_input_unavailable}, s}
    end
  end

  def handle_call({:observe_channel, _, _, _}, _, s),
    do: {:reply, {:error, :operator_input_unavailable}, s}

  def handle_call(
        {:cancel_input_read, channel},
        {client, _},
        %{operator_channel: %{id: channel, client: client}} = s
      ) do
    {:reply, Ipse.Session.Input.cancel_read(), s}
  end

  def handle_call({:cancel_input_read, _}, _, s),
    do: {:reply, {:error, :operator_input_unavailable}, s}

  def handle_call(
        {:stage_input, channel, text, witness},
        {client, _},
        %{operator_channel: %{id: channel, client: client}} = s
      ) do
    result = Ipse.Session.Input.stage(witness, text, operator_binding(s, "prompt", nil))
    {:reply, result, if(match?({:ok, _}, result), do: %{s | chat_reoffer_snapshot: nil}, else: s)}
  end

  def handle_call({:stage_input, _, _, _}, _, s),
    do: {:reply, {:error, :invalid_input_witness}, s}

  def handle_call(
        {:prepare_planning_decision, channel, command, ticket},
        {client, _},
        %{phase: :idle, operator_channel: %{id: channel, client: client}} = s
      ) do
    with true <- planning_entry_quiet?(s) and is_map(s.planning_entry),
         true <- map_size(s.planning_decisions) < 16,
         {:ok, mode} <- Ipse.Extension.Mode.capture(s.config),
         true <- mode["ceiling"] == "planning",
         {:ok, observation} <-
           Ipse.Session.Input.submit(ticket, command, operator_binding(s, "prompt", nil)),
         true <- Ipse.Session.Input.valid_observation?(observation, command, 2),
         {:ok, render} <- planning_decision_render(s, channel, command),
         false <- Map.has_key?(s.planning_decisions, render["id"]) do
      pending = %{
        render: render,
        command: command,
        command_observation: observation,
        input_generation: s.input_generation
      }

      {:reply, {:ok, %{"render_id" => render["id"]}}, %{s | planning_decision_render: pending}}
    else
      _ ->
        Ipse.Session.Input.discard(ticket)
        {:reply, {:error, :planning_decision_refused}, %{s | planning_decision_render: nil}}
    end
  end

  def handle_call({:prepare_planning_decision, _, _, _}, _, s),
    do: {:reply, {:error, :planning_decision_refused}, s}

  def handle_call(
        {:accept_planning_decision, channel, render_id, text, witness},
        {client, _},
        %{
          phase: :idle,
          operator_channel: %{id: channel, client: client},
          planning_decision_render: %{render: %{"id" => render_id} = render} = pending
        } = s
      ) do
    with true <- planning_entry_quiet?(s) and is_map(s.planning_entry),
         true <- pending.input_generation == s.input_generation,
         true <- render["entry_sha256"] == Ipse.JSON.digest([s.planning_entry]),
         true <- planning_decision_source_current?(s, render),
         {:ok, mode} <- Ipse.Extension.Mode.capture(s.config),
         true <- mode["ceiling"] == "planning",
         {:ok, observation} <-
           Ipse.Session.Input.consume(
             witness,
             text,
             operator_binding(s, "planning_decision", render_id)
           ),
         {:ok, event} <-
           Ipse.Session.PlanningDecisions.accept(
             render,
             pending.command,
             pending.command_observation,
             text,
             observation
           ) do
      record(s, event)

      decision = %{
        receipt: event,
        exited: false,
        attempted: false,
        asserted: false,
        later_invocation_seen: false,
        refused: false
      }

      {:reply, {:ok, event["id"]},
       %{
         s
         | planning_decision_render: nil,
           planning_decisions: Map.put(s.planning_decisions, event["id"], decision),
           input_generation: Ipse.Usage.id()
       }}
    else
      _ ->
        Ipse.Session.Input.discard(witness)
        {:reply, {:error, :planning_decision_refused}, %{s | planning_decision_render: nil}}
    end
  end

  def handle_call({:accept_planning_decision, _, _, _, _}, _, s),
    do: {:reply, {:error, :planning_decision_refused}, s}

  def handle_call(
        {:prepare_planning_save, channel, command, ticket},
        {client, _},
        %{phase: :idle, operator_channel: %{id: channel, client: client}} = s
      ) do
    with true <- planning_entry_quiet?(s),
         {:ok, mode} <- Ipse.Extension.Mode.capture(s.config),
         true <- mode["ceiling"] == "normal" and mode["enclosing_ceiling"] == "normal",
         {:ok, id} <- Ipse.Session.PlanningDecisions.parse_save(command),
         %{receipt: decision, exited: true, attempted: false} <- s.planning_decisions[id],
         {:ok, _scope, name, render, kind} <- planning_save_render(s, channel, decision),
         {:ok, origin} when is_map(origin) <- Writer.source_query(s.journal_writer, :origin),
         {:ok, window} <- Writer.source_query(s.journal_writer, :snapshot),
         {:ok, observation} <-
           Ipse.Session.Input.submit(ticket, command, operator_binding(s, "prompt", nil)),
         true <- Ipse.Session.Input.valid_observation?(observation, command, 2),
         true <- observation["display_sha256"] == Ipse.JSON.sha256("you> ") do
      pending = %{
        render: render,
        kind: kind,
        purpose: nil,
        name: name,
        source_generation: window["generation"],
        input_generation: s.input_generation,
        planning_decision: decision,
        planning_save_observation: observation
      }

      {:reply, {:ok, %{"render_id" => render["id"]}}, %{s | assertion_render: pending}}
    else
      _ ->
        Ipse.Session.Input.discard(ticket)
        {:reply, {:error, :planning_save_refused}, %{s | assertion_render: nil}}
    end
  end

  def handle_call({:prepare_planning_save, _, _, _}, _, s),
    do: {:reply, {:error, :planning_save_refused}, s}

  def handle_call(
        {:prepare_assertion, channel, text, ticket},
        {client, _},
        %{phase: :idle, operator_channel: %{id: channel, client: client}} = s
      ) do
    with true <- planning_entry_quiet?(s),
         {:ok, category, statement, purpose} <- Ipse.Session.OperatorAssertion.parse_intake(text),
         {:ok, scope, name} <- Ipse.Session.OperatorAssertion.selection(s.config),
         {:ok, origin} when is_map(origin) <- Writer.source_query(s.journal_writer, :origin),
         {:ok, window} <- Writer.source_query(s.journal_writer, :snapshot),
         {:ok, _} <- Ipse.Session.Input.submit(ticket, text, operator_binding(s, "prompt", nil)),
         {:ok, render} <-
           Ipse.Session.OperatorAssertion.render(s.id, channel, category, statement, scope) do
      pending = %{
        render: render,
        purpose: purpose,
        name: name,
        source_generation: window["generation"],
        input_generation: s.input_generation
      }

      {:reply, {:ok, %{"render_id" => render["id"]}}, %{s | assertion_render: pending}}
    else
      _ ->
        Ipse.Session.Input.discard(ticket)
        {:reply, {:error, :operator_assertion_refused}, %{s | assertion_render: nil}}
    end
  end

  def handle_call({:prepare_assertion, _, _, _}, _, s),
    do: {:reply, {:error, :operator_assertion_refused}, s}

  def handle_call(
        {:accept_assertion_observed, channel, render_id, text, witness},
        {client, _},
        %{
          phase: :idle,
          operator_channel: %{id: channel, client: client},
          assertion_render:
            %{kind: :planning_assistant, render: %{"id" => render_id} = render} = pending
        } = s
      ) do
    decision = pending.planning_decision

    with true <- planning_entry_quiet?(s),
         true <- pending.input_generation === s.input_generation,
         %{receipt: ^decision, exited: true, attempted: false} = old <-
           s.planning_decisions[decision["id"]],
         true <- planning_decision_source_current?(s, decision),
         {:ok, scope, name} <- planning_proposal_selection(s),
         true <- scope === render["scope"] and name === pending.name,
         {:ok, window} <- Writer.source_query(s.journal_writer, :snapshot),
         true <- window["generation"] === pending.source_generation,
         {:ok, observation} <-
           Ipse.Session.Input.consume(witness, text, operator_binding(s, "assertion", render_id)),
         {:ok, event} <-
           Ipse.Session.PlanningDecisions.stage_started(
             render,
             decision,
             pending.planning_save_observation,
             text,
             observation
           ),
         :ok <- Writer.ensure_source_window(s.journal_writer),
         {:ok, source} <-
           Writer.source_query(
             s.journal_writer,
             {:answer_request, decision["turn_id"], decision["request_id"], decision["text"]}
           ),
         {:ok, %{"proof" => proof}} <- Writer.source_query(s.journal_writer, {:proof, source}),
         true <- proof === decision["source_proof"] do
      record(s, event)

      next =
        s
        |> Map.put(:assertion_render, nil)
        |> Map.put(:input_generation, Ipse.Usage.id())
        |> Map.put(
          :planning_decisions,
          Map.put(s.planning_decisions, decision["id"], %{old | attempted: true})
        )
        |> Map.put(:post_reply_answer_recorded, {s.turn_id, s.last_request_id})
        |> Map.put(:pending_nomination, nil)
        |> Map.put(:post_reply_capture, nil)

      args = %{
        "text" => decision["text"],
        "category" => "ordinary",
        "reason" => "Assistant proposal accepted during planning.",
        "event_at_ms" => nil,
        "source" => source
      }

      case CurrentInvocation.invoke_export(next, :command, name, args) do
        {:reply, :ok, _} = started -> started
        _ -> {:reply, {:error, :planning_save_refused}, next}
      end
    else
      _ ->
        Ipse.Session.Input.discard(witness)
        {:reply, {:error, :planning_save_refused}, %{s | assertion_render: nil}}
    end
  end

  def handle_call(
        {:accept_assertion_observed, channel, render_id, text, witness},
        {client, _},
        %{
          phase: :idle,
          operator_channel: %{id: channel, client: client},
          assertion_render: %{render: %{"id" => render_id} = render} = pending
        } = s
      ) do
    with true <- planning_entry_quiet?(s),
         true <-
           render["channel_id"] == channel and pending.input_generation == s.input_generation,
         {:ok, scope, name} <- Ipse.Session.OperatorAssertion.selection(s.config),
         true <- scope === render["scope"] and name === pending.name,
         {:ok, window} <- Writer.source_query(s.journal_writer, :snapshot),
         true <- window["generation"] === pending.source_generation,
         {:ok, observation} <-
           Ipse.Session.Input.consume(witness, text, operator_binding(s, "assertion", render_id)),
         {:ok, event} <- Ipse.Session.OperatorAssertion.receipt(render, text, observation),
         :ok <- Writer.ensure_source_window(s.journal_writer),
         {:ok, s, event} <- link_planning_assertion(s, pending, event) do
      record(s, event)
      s = %{s | assertion_render: nil, input_generation: Ipse.Usage.id()}

      case Writer.source_query(s.journal_writer, {:assertion_request, event["id"]}) do
        {:ok, source} ->
          args = %{
            "text" => event["text"],
            "category" => event["category"],
            "reason" => "Native operator statement and category review.",
            "event_at_ms" => nil,
            "source" => source
          }

          with {:ok, s} <- prepare_supersession_intake(s, pending, event, source) do
            invoke_assertion_capture(s, name, args)
          else
            _ ->
              {:reply, {:error, :operator_assertion_refused}, planning_save_refused_unstarted(s)}
          end

        _ ->
          {:reply, {:error, :operator_assertion_refused}, planning_save_refused_unstarted(s)}
      end
    else
      _ ->
        Ipse.Session.Input.discard(witness)
        {:reply, {:error, :operator_assertion_refused}, %{s | assertion_render: nil}}
    end
  end

  def handle_call({:accept_assertion_observed, _, _, _, _}, _, s),
    do: {:reply, {:error, :operator_assertion_refused}, s}

  def handle_call(
        {:enter_planning_observed, channel, ticket},
        {client, _},
        %{operator_channel: %{id: channel, client: client}, phase: :idle} = s
      ) do
    with true <- planning_entry_quiet?(s),
         {:ok, current} <- Ipse.Extension.Mode.capture(s.config),
         true <- current["ceiling"] == "normal" and current["enclosing_ceiling"] == "normal",
         {:ok, observation} <-
           Ipse.Session.Input.submit(ticket, "/plan", operator_binding(s, "prompt", nil)),
         true <- Ipse.Session.Input.valid_observation?(observation, "/plan", 2) do
      :ok = Ipse.Session.Input.invalidate()
      next_mode = Map.put(current, "ceiling", "planning")

      checkpoint = %{
        "type" => "execution_mode_resumed",
        "version" => 2,
        "session_id" => s.id,
        "previous_sha256" => Ipse.JSON.digest([current]),
        "mode" => next_mode
      }

      record(s, checkpoint)
      epoch_id = record_planning_epoch(s, next_mode)
      entry = Ipse.Session.PlanningTransition.entry(s.id, checkpoint, observation)
      record(s, entry)

      {:reply, :ok,
       %{
         s
         | config: apply_execution_mode(s.config, next_mode),
           planning_mcp_epoch_id: epoch_id,
           planning_entry: entry,
           input_generation: Ipse.Usage.id(),
           operator_channel: %{s.operator_channel | generation: Ipse.Usage.id()}
       }}
    else
      _ ->
        Ipse.Session.Input.discard(ticket)
        {:reply, {:error, :planning_entry_unavailable}, s}
    end
  end

  def handle_call(
        {:enter_planning_observed, channel, ticket},
        {client, _},
        %{operator_channel: %{id: channel, client: client}} = s
      ) do
    Ipse.Session.Input.discard(ticket)
    {:reply, {:error, :planning_entry_unavailable}, s}
  end

  def handle_call({:enter_planning_observed, _, _}, _, s),
    do: {:reply, {:error, :planning_entry_unavailable}, s}

  def handle_call(
        {:exit_planning_observed, channel, ticket},
        {client, _},
        %{operator_channel: %{id: channel, client: client}, phase: :idle} = s
      ) do
    with true <- planning_entry_quiet?(s) and is_map(s.planning_entry),
         {:ok, current} <- Ipse.Extension.Mode.capture(s.config),
         true <- current["ceiling"] == "planning",
         {:ok, observation} <-
           Ipse.Session.Input.submit(ticket, "/plan exit", operator_binding(s, "prompt", nil)),
         true <- Ipse.Session.Input.valid_observation?(observation, "/plan exit", 2) do
      :ok = Ipse.Session.Input.invalidate()
      event = Ipse.Session.PlanningTransition.exit(s.id, s.planning_entry, current, observation)
      next_mode = event["mode"]
      record(s, event)
      epoch_id = record_planning_epoch(s, next_mode)

      {:reply, :ok,
       %{
         s
         | config: apply_execution_mode(s.config, next_mode),
           planning_mcp_epoch_id: epoch_id,
           planning_entry: nil,
           planning_decisions:
             Map.new(s.planning_decisions, fn {id, decision} ->
               if decision.receipt["entry_sha256"] == event["entry_sha256"],
                 do: {id, %{decision | exited: true}},
                 else: {id, decision}
             end),
           input_generation: Ipse.Usage.id(),
           operator_channel: %{s.operator_channel | generation: Ipse.Usage.id()}
       }}
    else
      _ ->
        Ipse.Session.Input.discard(ticket)
        {:reply, {:error, :planning_exit_unavailable}, s}
    end
  end

  def handle_call(
        {:exit_planning_observed, channel, ticket},
        {client, _},
        %{operator_channel: %{id: channel, client: client}} = s
      ) do
    Ipse.Session.Input.discard(ticket)
    {:reply, {:error, :planning_exit_unavailable}, s}
  end

  def handle_call({:exit_planning_observed, _, _}, _, s),
    do: {:reply, {:error, :planning_exit_unavailable}, s}

  def handle_call(
        {:discard_input, channel, witness},
        {client, _},
        %{operator_channel: %{id: channel, client: client}} = s
      ) do
    {:reply, Ipse.Session.Input.discard(witness), %{s | chat_reoffer_snapshot: nil}}
  end

  def handle_call({:discard_input, _, _}, _, s), do: {:reply, {:error, :invalid_input_witness}, s}

  def handle_call(
        {:render_question, channel, item},
        {client, _},
        %{
          operator_channel: %{id: channel, client: client},
          phase: :question,
          question: %{id: _} = question
        } = s
      )
      when not is_map_key(question, :kind) do
    expected = Enum.at(question.arguments["questions"], length(s.operator_pieces))

    with true <- expected != nil and expected["id"] == item,
         {:ok, render} <- Ipse.Session.OperatorAnswer.render(question, item, channel) do
      :ok = Ipse.Session.Input.cancel_read()
      {:reply, {:ok, render}, %{s | operator_render: render}}
    else
      _ -> {:reply, {:error, :no_pending_question}, s}
    end
  end

  def handle_call(
        {:render_question, channel, _},
        {client, _},
        %{
          operator_channel: %{id: channel, client: client},
          question: %{kind: :extension},
          phase: :question
        } = s
      ),
      do: {:reply, {:error, :extension_question}, s}

  def handle_call({:render_question, _, _}, _, s), do: {:reply, {:error, :no_pending_question}, s}

  def handle_call(
        {:answer_observed, channel, render_id, text, witness},
        {client, _},
        %{
          operator_channel: %{id: channel, client: client},
          phase: :question,
          question: question,
          operator_render: %{"render_id" => render_id} = render
        } = s
      ) do
    with {:ok, observation} <-
           Ipse.Session.Input.consume(witness, text, operator_binding(s, "question", render_id)),
         {:ok, answer, piece} <-
           Ipse.Session.OperatorAnswer.parse(question, render, text, observation) do
      answers = Map.put(s.operator_answers, render["item_id"], answer)
      pieces = s.operator_pieces ++ [piece]
      next = %{s | operator_render: nil, operator_answers: answers, operator_pieces: pieces}

      if length(pieces) == length(question.arguments["questions"]) do
        Ipse.Session.Turn.answer(next, question.id, answers, question, %{
          client_id: channel,
          pieces: pieces
        })
      else
        {:reply, {:ok, :more}, next}
      end
    else
      _ -> {:reply, {:error, :invalid_operator_answer_origin}, s}
    end
  end

  def handle_call({:answer_observed, _, _, _, _}, _, s),
    do: {:reply, {:error, :invalid_operator_answer_origin}, s}

  def handle_call({:observe_input, display, timeout}, {client, _}, %{phase: :idle} = s) do
    {:ok, scope} = Ipse.Session.Resources.start(self())
    :ok = Ipse.Session.Lock.track(scope, :scope)
    result = Ipse.Session.Input.start(input_binding(s), display, timeout, client, scope)
    if not match?({:ok, _}, result), do: Ipse.Session.Resources.stop_async(scope)
    {:reply, result, s}
  end

  def handle_call({:observe_input, _, _}, _from, s), do: {:reply, {:error, :busy}, s}

  def handle_call({:start_draft, text}, _from, %{phase: :idle} = s)
      when is_binary(text) and byte_size(text) in 1..32_768,
      do: start_draft_work(s, text, nil)

  def handle_call({:start_draft, _}, _, s), do: {:reply, {:error, :draft_unavailable}, s}

  def handle_call(
        {:start_draft_observed, channel, text, ticket},
        {client, _},
        %{phase: :idle, operator_channel: %{id: channel, client: client}} = s
      )
      when is_binary(text) and byte_size(text) in 1..32_768 do
    case Ipse.Session.Input.submit(ticket, text, operator_binding(s, "prompt", nil)) do
      {:ok, observation} -> start_draft_work(s, text, observation)
      _ -> {:reply, {:error, :invalid_input_witness}, s}
    end
  end

  def handle_call(
        {:start_draft_observed, channel, _, ticket},
        {client, _},
        %{operator_channel: %{id: channel, client: client}} = s
      ) do
    Ipse.Session.Input.discard(ticket)
    {:reply, {:error, :invalid_input_witness}, s}
  end

  def handle_call({:start_draft_observed, _, _, _}, _, s),
    do: {:reply, {:error, :invalid_input_witness}, s}

  def handle_call(:rebase_draft, _, %{phase: :idle, draft: draft} = s) when is_map(draft) do
    case Ipse.Session.Draft.rebased(
           draft,
           s.messages,
           s.reference_occurrences,
           Ipse.Session.DraftNative.policy(s.config)
         ) do
      {:ok, event, projected} ->
        record(s, event)
        s = managed_event(s, event, projected)
        {:reply, :ok, %{s | draft: nil, messages: projected}}

      error ->
        {:reply, error, s}
    end
  end

  def handle_call(:rebase_draft, _, s), do: {:reply, {:error, :draft_unavailable}, s}

  def handle_call(:draft, _, %{draft: draft} = s) when is_map(draft),
    do: {:reply, {:ok, Map.take(draft, [:id, :revision, :status, :proposal])}, s}

  def handle_call(:draft, _, s), do: {:reply, {:error, :draft_unavailable}, s}

  def handle_call(
        {:render_draft, channel, id, revision},
        {client, _},
        %{
          phase: :idle,
          operator_channel: %{id: channel, client: client},
          draft: %{id: id, revision: revision, status: :completed} = draft
        } = s
      ) do
    with true <- length(s.draft_lineages) < Ipse.Session.DraftLineage.limit(),
         true <-
           Ipse.Session.Draft.withdrawable?(
             draft,
             s.messages,
             s.reference_occurrences,
             Ipse.Session.DraftNative.policy(s.config)
           ),
         {:ok, render} <- Ipse.Session.DraftAcceptance.render(draft, channel) do
      :ok = Ipse.Session.Input.cancel_read()
      {:reply, {:ok, Map.take(render, ["render_id"])}, %{s | draft_render: render}}
    else
      _ -> {:reply, {:error, :draft_projection_unsafe}, s}
    end
  end

  def handle_call({:render_draft, _, _, _}, _, s), do: {:reply, {:error, :stale_draft}, s}

  def handle_call(
        {:accept_draft_observed, channel, render_id, text, witness},
        {client, _},
        %{
          phase: :idle,
          operator_channel: %{id: channel, client: client},
          draft: %{status: :completed} = draft,
          draft_render: %{"render_id" => render_id} = render
        } = s
      ) do
    with true <- length(s.draft_lineages) < Ipse.Session.DraftLineage.limit(),
         true <-
           Ipse.Session.Draft.withdrawable?(
             draft,
             s.messages,
             s.reference_occurrences,
             Ipse.Session.DraftNative.policy(s.config)
           ),
         true <- Workspace.explicit_skills(draft.proposal, s.skills) == [],
         {:ok, observation} <-
           Ipse.Session.Input.consume(witness, text, operator_binding(s, "draft", render_id)),
         {:ok, receipt} <- Ipse.Session.DraftAcceptance.receipt(draft, render, text, observation) do
      accepted = Ipse.Session.Draft.accepted(draft, receipt)
      record(s, accepted)

      consume_accepted(%{
        s
        | draft: Map.merge(draft, %{status: :accepted, accepted_event: accepted}),
          draft_render: nil
      })
    else
      _ ->
        Ipse.Session.Input.discard(witness)
        {:reply, {:error, :invalid_draft_acceptance}, %{s | draft_render: nil}}
    end
  end

  def handle_call(
        {:accept_draft_observed, channel, _, _, witness},
        {client, _},
        %{operator_channel: %{id: channel, client: client}} = s
      ) do
    Ipse.Session.Input.discard(witness)
    {:reply, {:error, :invalid_draft_acceptance}, s}
  end

  def handle_call({:accept_draft_observed, _, _, _, _}, _, s),
    do: {:reply, {:error, :invalid_draft_acceptance}, s}

  def handle_call(
        {:replace_draft, id, revision, text},
        _,
        %{phase: :idle, draft: %{id: id, revision: revision, status: :completed} = draft} = s
      )
      when revision < 100 do
    if Ipse.Session.Draft.text?(text) do
      :ok = Ipse.Session.Input.cancel_read()
      record(s, Ipse.Session.Draft.replaced(draft, text))

      {:reply, :ok,
       %{s | draft: %{draft | revision: revision + 1, proposal: text}, draft_render: nil}}
    else
      {:reply, {:error, :invalid_draft_text}, s}
    end
  end

  def handle_call({:replace_draft, _, _, _}, _, s), do: {:reply, {:error, :stale_draft}, s}

  def handle_call(
        {:replace_draft_observed, channel, id, revision, text, ticket},
        {client, _},
        %{
          phase: :idle,
          operator_channel: %{id: channel, client: client},
          draft: %{id: id, revision: revision, status: :completed} = draft
        } = s
      )
      when revision < 100 do
    with true <- Ipse.Session.Draft.text?(text),
         {:ok, observation} <-
           Ipse.Session.Input.submit(ticket, text, operator_binding(s, "prompt", nil)) do
      :ok = Ipse.Session.Input.cancel_read()
      record(s, Ipse.Session.Draft.replaced(draft, text, observation))

      {:reply, :ok,
       %{s | draft: %{draft | revision: revision + 1, proposal: text}, draft_render: nil}}
    else
      _ ->
        Ipse.Session.Input.discard(ticket)
        {:reply, {:error, :invalid_input_witness}, s}
    end
  end

  def handle_call(
        {:replace_draft_observed, channel, _, _, _, ticket},
        {client, _},
        %{operator_channel: %{id: channel, client: client}} = s
      ) do
    Ipse.Session.Input.discard(ticket)
    {:reply, {:error, :invalid_input_witness}, s}
  end

  def handle_call({:replace_draft_observed, _, _, _, _, _}, _, s),
    do: {:reply, {:error, :invalid_input_witness}, s}

  def handle_call(
        {:replace_draft_command_observed, channel, id, revision, command, ticket},
        {client, _},
        %{
          phase: :idle,
          operator_channel: %{id: channel, client: client},
          draft: %{id: id, revision: revision, status: :completed} = draft
        } = s
      )
      when revision < 100 do
    with {:ok, text} <- Ipse.Session.Draft.inline_replacement(command),
         {:ok, observation} <-
           Ipse.Session.Input.submit(ticket, command, operator_binding(s, "prompt", nil)) do
      :ok = Ipse.Session.Input.cancel_read()
      record(s, Ipse.Session.Draft.replaced_command(draft, text, command, observation))

      {:reply, :ok,
       %{s | draft: %{draft | revision: revision + 1, proposal: text}, draft_render: nil}}
    else
      _ ->
        Ipse.Session.Input.discard(ticket)
        {:reply, {:error, :invalid_input_witness}, s}
    end
  end

  def handle_call(
        {:replace_draft_command_observed, channel, _, _, _, ticket},
        {client, _},
        %{operator_channel: %{id: channel, client: client}} = s
      ) do
    Ipse.Session.Input.discard(ticket)
    {:reply, {:error, :invalid_input_witness}, s}
  end

  def handle_call({:replace_draft_command_observed, _, _, _, _, _}, _, s),
    do: {:reply, {:error, :invalid_input_witness}, s}

  def handle_call(
        {:replace_draft_lines_observed, channel, id, revision, lines},
        {client, _},
        %{
          phase: :idle,
          operator_channel: %{id: channel, client: client},
          draft: %{id: id, revision: revision, status: :completed} = draft
        } = s
      )
      when revision < 100 and is_list(lines) and length(lines) in 1..16 do
    with true <-
           Enum.all?(lines, fn
             {line, _ticket} ->
               is_binary(line) and String.valid?(line) and
                 not String.contains?(line, ["\n", "\r"])

             _ ->
               false
           end),
         text = Enum.map_join(lines, "\n", &elem(&1, 0)),
         true <- Ipse.Session.Draft.text?(text),
         {:ok, pieces} <- consume_draft_lines(s, lines) do
      :ok = Ipse.Session.Input.cancel_read()
      record(s, Ipse.Session.Draft.replaced_lines(draft, text, pieces))

      {:reply, :ok,
       %{s | draft: %{draft | revision: revision + 1, proposal: text}, draft_render: nil}}
    else
      _ ->
        Enum.each(lines, fn
          {_text, ticket} -> Ipse.Session.Input.discard(ticket)
          _ -> :ok
        end)

        {:reply, {:error, :invalid_input_witness}, s}
    end
  end

  def handle_call(
        {:replace_draft_lines_observed, channel, _, _, lines},
        {client, _},
        %{operator_channel: %{id: channel, client: client}} = s
      )
      when is_list(lines) do
    Enum.each(lines, fn
      {_text, ticket} -> Ipse.Session.Input.discard(ticket)
      _ -> :ok
    end)

    {:reply, {:error, :invalid_input_witness}, s}
  end

  def handle_call({:replace_draft_lines_observed, _, _, _, _}, _, s),
    do: {:reply, {:error, :invalid_input_witness}, s}

  def handle_call({:accept_draft, _, _}, _, s),
    do: {:reply, {:error, :native_draft_acceptance_required}, s}

  def handle_call(
        {:consume_draft, id, revision},
        _,
        %{phase: :idle, draft: %{id: id, revision: revision, status: :accepted} = draft} = s
      ) do
    if length(s.draft_lineages) < Ipse.Session.DraftLineage.limit() and
         Ipse.Session.Draft.withdrawable?(
           draft,
           s.messages,
           s.reference_occurrences,
           Ipse.Session.DraftNative.policy(s.config)
         ) and
         Workspace.explicit_skills(draft.proposal, s.skills) == [],
       do: consume_accepted(s),
       else: {:reply, {:error, :draft_projection_unsafe}, s}
  end

  def handle_call({:consume_draft, _, _}, _, s), do: {:reply, {:error, :stale_draft}, s}

  def handle_call({:prompt, _, _}, _, %{draft: %{status: status}} = s)
      when status in [:pending, :completed, :accepted],
      do: {:reply, {:error, :draft_recovery_required}, s}

  def handle_call({:prompt, _}, _, %{draft: %{status: status}} = s)
      when status in [:pending, :completed, :accepted],
      do: {:reply, {:error, :draft_recovery_required}, s}

  def handle_call({:prompt, _, _}, _, %{draft: %{status: :cancelled, notice: false}} = s),
    do: {:reply, {:error, :draft_recovery_required}, s}

  def handle_call({:prompt, _}, _, %{draft: %{status: :cancelled, notice: false}} = s),
    do: {:reply, {:error, :draft_recovery_required}, s}

  def handle_call(
        {:prompt, _, _},
        _,
        %{draft: %{status: :consumed, accepted_message: false}} = s
      ),
      do: {:reply, {:error, :draft_recovery_required}, s}

  def handle_call({:prompt, _}, _, %{draft: %{status: :consumed, accepted_message: false}} = s),
    do: {:reply, {:error, :draft_recovery_required}, s}

  def handle_call({:prompt, _, _}, _from, %{phase: phase} = s) when phase != :idle,
    do: {:reply, {:error, :busy}, s}

  def handle_call({:prompt, text, witness}, from, s)
      when is_binary(text) and byte_size(text) > 0 do
    observed =
      case s.operator_channel do
        %{client: client} when elem(from, 0) == client ->
          case Ipse.Session.Input.submit(witness, text, operator_binding(s, "prompt", nil)) do
            {:ok, _} = result -> result
            _ -> Ipse.Session.Input.consume(witness, text, input_binding(s))
          end

        _ ->
          Ipse.Session.Input.consume(witness, text, input_binding(s))
      end

    case observed do
      {:ok, observation} ->
        Turn.prompt(%{s | input_generation: Ipse.Usage.id()}, text, from, observation)

      error ->
        {:reply, error, s}
    end
  end

  def handle_call({:prompt, _, _}, _from, s), do: {:reply, {:error, :invalid_input_witness}, s}

  def handle_call({:prompt, _}, _from, %{phase: phase} = s) when phase != :idle,
    do: {:reply, {:error, :busy}, s}

  def handle_call({:prompt, text}, from, s) when is_binary(text) and byte_size(text) > 0 do
    :ok = Ipse.Session.Input.invalidate()
    Turn.prompt(%{s | input_generation: Ipse.Usage.id()}, text, from)
  end

  def handle_call({:prompt, _}, _from, s), do: {:reply, {:error, :empty_prompt}, s}

  def handle_call({:approve, _, choice}, _from, %{approval: approval} = s)
      when choice in [:session_edits, :session_command] and
             (not is_tuple(approval) or tuple_size(approval) != 3),
      do: {:reply, {:error, :grant_unavailable}, s}

  def handle_call(
        {:approve, ref, allowed},
        _from,
        %{approval: {:delegated, ref, worker, child, child_ref, name, args}, task: %{}} =
          s
      ) do
    case s.delegation_resources[child] do
      %{id: id, worker: ^worker, down: false, finished: false} ->
        s = finish_wait(s, if(allowed == true, do: "approved", else: "denied"))

        record(s, %{
          "type" => "delegation_approval",
          "child_id" => id,
          "name" => name,
          "arguments" => args,
          "decision" => if(allowed == true, do: "approved", else: "denied")
        })

        send(worker, {:delegated_decision, child, child_ref, allowed == true})
        s = if allowed == true, do: claim_delegated_effect(s, child, name, args), else: s
        {:reply, :ok, next_delegated_approval(%{s | approval: nil, phase: :tool})}

      _ ->
        {:reply, {:error, :no_pending_approval}, s}
    end
  end

  def handle_call(
        {:approve, ref, allowed},
        _from,
        %{
          approval: {:extension, ref, caller, phase},
          invocation: %{action: action},
          phase: :extension_approval
        } = s
      ) do
    CurrentInvocation.approve(s, allowed, caller, phase, action)
  end

  def handle_call({:approve, ref, allowed}, _from, %{approval: {ref, call, args}} = s) do
    Turn.approve(s, allowed, call, args)
  end

  def handle_call({:approve, _, _}, _from, s), do: {:reply, {:error, :no_pending_approval}, s}

  def handle_call({:answer, _, _}, _from, %{draft: %{status: :pending}} = s),
    do: {:reply, {:error, :native_draft_answer_required}, s}

  def handle_call(
        {:answer, id, answers},
        _from,
        %{question: %{kind: :extension, id: id} = question, phase: :question} = s
      ) do
    CurrentInvocation.answer(s, answers, question)
  end

  def handle_call(
        {:answer, id, answers},
        _from,
        %{question: %{id: id} = question, phase: :question} = s
      ) do
    Turn.answer(s, id, answers, question)
  end

  def handle_call({:answer, _, _}, _from, s), do: {:reply, {:error, :no_pending_question}, s}

  def handle_call(
        {:question_eof, channel},
        {client, _},
        %{operator_channel: %{id: channel, client: client}, phase: :question, question: question} =
          s
      )
      when is_map(question) do
    cancel_work(s, true)
  end

  def handle_call({:question_eof, _}, _, s), do: {:reply, {:error, :no_pending_question}, s}

  def handle_call({:session_sources, operation, request}, {client, _}, %{subscriber: client} = s) do
    {:reply, source_query(s, operation, request), s}
  end

  def handle_call({:session_sources, _, _}, _, s),
    do: {:reply, {:error, :source_index_refused}, s}

  def handle_call(
        {:prepare_model_source, ref, operation, request},
        {worker, _},
        %{task: %{pid: worker}, job_ref: ref, phase: :tool} = s
      ) do
    call = List.first(s.calls)

    with true <- Ipse.Session.SourceWindow.enabled?(s.config),
         true <-
           get_in(call, ["function", "name"]) == Ipse.Extension.SourceRead.tool_name(operation),
         true <-
           Ipse.JSON.decode_unique(get_in(call, ["function", "arguments"])) == {:ok, request},
         false <- Map.has_key?(s.managed_lineage.source_lookups, call["id"]),
         {:ok, rows} <-
           Writer.source_query(
             s.journal_writer,
             {:tool_query_provenances, call["id"], operation, request}
           ),
         {:ok, lineage, dependencies} <-
           Ipse.Session.ManagedLineage.add_selected_source_dependencies(
             s.managed_lineage,
             call["id"],
             rows
           ),
         next = %{s | managed_lineage: lineage},
         true <- Ipse.Session.ManagedToolUse.source_dependencies_supported?(dependencies),
         event = %{
           "type" => "managed_source_lookup_prepared",
           "version" => 1,
           "session_id" => s.id,
           "call_id" => call["id"],
           "operation" => operation,
           "request_sha256" => Ipse.JSON.digest([Map.put(request, "op", operation)]),
           "selection_sha256" => Ipse.JSON.digest([rows]),
           "dependencies_sha256" => Ipse.JSON.digest(dependencies)
         } do
      record(next, event)
      next = managed_event(next, event)

      if match?(%Ipse.Session.ManagedLineage{unavailable: false}, next.managed_lineage),
        do: {:reply, :ok, next},
        else: {:reply, {:error, :source_index_refused}, next}
    else
      _ -> {:reply, {:error, :source_index_refused}, s}
    end
  end

  def handle_call({:prepare_model_source, _, _, _}, _, s),
    do: {:reply, {:error, :source_index_refused}, s}

  def handle_call(
        {:model_sources, ref, operation, request},
        {worker, _},
        %{task: %{pid: worker}, job_ref: ref, phase: :tool} = s
      ) do
    call = List.first(s.calls)

    if Ipse.Session.SourceWindow.enabled?(s.config) and
         source_lookup_prepared?(s, call, operation, request) and
         Ipse.Session.ManagedLineage.tool_dependencies(s.managed_lineage, call["id"]) == {:ok, []} and
         get_in(call, ["function", "name"]) == Ipse.Extension.SourceRead.tool_name(operation) and
         Ipse.JSON.decode_unique(get_in(call, ["function", "arguments"])) == {:ok, request},
       do: {:reply, source_query(s, operation, request), consume_source_lookup(s, call["id"])},
       else: {:reply, {:error, :source_index_refused}, s}
  end

  def handle_call(
        {:model_sources, ref, operation, request},
        {caller, _},
        %{task: %{pid: worker}, job_ref: ref, phase: :tool} = s
      ) do
    call = List.first(s.calls)
    pending = s.managed_tool_effect
    name = Ipse.Extension.SourceRead.tool_name(operation)

    if Ipse.Session.SourceWindow.enabled?(s.config) and
         source_lookup_prepared?(s, call, operation, request) and
         Ipse.Session.Resources.authorized_effect?(worker, caller) and
         is_map(pending) and pending.worker == worker and pending.job == ref and
         pending.admitted and is_nil(pending.cleanup) and
         System.system_time(:millisecond) < pending.deadline and
         get_in(call, ["function", "name"]) == name and
         Ipse.JSON.decode_unique(get_in(call, ["function", "arguments"])) == {:ok, request} and
         pending.binding == Ipse.Session.ManagedToolUse.native_binding(name, request) and
         Ipse.Session.ManagedToolUse.source_call_supported?(s, call),
       do: {:reply, source_query(s, operation, request), consume_source_lookup(s, call["id"])},
       else: {:reply, {:error, :source_index_refused}, s}
  end

  def handle_call({:model_sources, _, _, _}, _, s),
    do: {:reply, {:error, :source_index_refused}, s}

  def handle_call(
        :cancel_draft,
        _from,
        %{phase: :idle, draft: %{status: :cancelled, notice: false} = draft} = s
      ) do
    next = Turn.append_message(s, %{"role" => "user", "content" => Ipse.Session.Draft.notice()})
    {:reply, :ok, %{next | draft: %{draft | notice: true}}}
  end

  def handle_call(:cancel_draft, _from, %{draft: %{status: status}} = s)
      when status in [:pending, :completed, :accepted],
      do: cancel_draft_work(s)

  def handle_call(:cancel_draft, _from, s), do: {:reply, {:error, :no_active_draft}, s}

  def handle_call(:cancel, _from, %{draft: %{status: status}} = s)
      when status in [:pending, :completed, :accepted],
      do: cancel_draft_work(s)

  def handle_call(:cancel, _from, s),
    do: cancel_work(%{s | assertion_render: nil, planning_decision_render: nil}, false)

  def handle_call(:close, _from, %{lock_mode: mode} = s)
      when mode in [:export_v1, :header_v1, :resume_v1, :header_share_v2, :resume_share_v2] do
    {cleanup, next} = stop_work(s, s.phase != :idle, "cancelled", "session_close")
    observer_cleanup = Ipse.Observability.close(s.observation, &record(s, &1))
    # The Writer cannot append after lock release, so do not claim a clean
    # final lock outcome in the lifecycle journal before that outcome exists.
    {next, closure} = close_epoch_for_release(next)
    prepared = prepare_release(next, closure, cleanup ++ observer_cleanup)
    writer_cleanup = stop_writer_confirmed(next)

    lock_cleanup = release_lock_confirmed(next.lock_guard)

    result =
      complete_release(
        next,
        prepared,
        cleanup ++ observer_cleanup ++ [writer_cleanup, lock_cleanup]
      )

    {:stop, :normal, result, next}
  end

  def handle_call(:close, _from, s) do
    {cleanup, next} = stop_work(s, s.phase != :idle, "cancelled", "session_close")
    observer_cleanup = Ipse.Observability.close(s.observation, &record(s, &1))
    cleanup = cleanup ++ observer_cleanup

    result =
      if is_nil(s.release_owner) and Enum.all?(cleanup, &(&1 == :ok)),
        do: :ok,
        else: {:error, :cleanup_unconfirmed}

    {:stop, :normal, result, close_epoch(next, "close", result == :ok)}
  end

  defp start_draft_work(s, text, observation) do
    with true <-
           String.valid?(text) and next_draft_available?(s.draft) and
             draft_mcp_ready?(s) and
             draft_extension_quiet?(s) and
             Workspace.explicit_skills(text, s.skills) == [],
         {:ok, mcp_snapshot} <- draft_mcp_snapshot(s),
         {:ok, visible} <-
           Ipse.Session.Draft.project(
             s.draft,
             s.messages,
             s.reference_occurrences,
             Ipse.Session.DraftNative.policy(s.config)
           ) do
      models = Ipse.Session.DraftNative.visible_models(visible)
      prior_reported = if MapSet.member?(models, s.reported_model), do: s.reported_model
      prior_historical = if MapSet.member?(models, s.historical_model), do: s.historical_model
      :ok = Ipse.Session.Input.invalidate()
      id = Ipse.Usage.id()
      turn = Ipse.Usage.id()
      effective = Ipse.Session.Draft.effective(text)

      event =
        Ipse.Session.Draft.started(
          s.id,
          turn,
          id,
          text,
          effective,
          s.messages,
          prior_reported,
          prior_historical
        )
        |> then(fn event ->
          if mcp_snapshot, do: Map.put(event, "mcp_snapshot", mcp_snapshot), else: event
        end)

      record(s, event)

      draft = %{
        id: id,
        session_id: s.id,
        turn_id: turn,
        status: :pending,
        prior_config: s.config,
        prior_reported_model: prior_reported,
        prior_historical_model: prior_historical,
        revision: 1,
        proposal: nil,
        accepted_input: false,
        accepted_message: false,
        input_source_id: nil,
        question_ids: [],
        answer_source_ids: [],
        tool_success_count: 0,
        tool_evidence: [],
        accepted_event: nil,
        prefix_count: length(s.messages),
        prefix_sha256: Ipse.JSON.digest(s.messages),
        history: if(s.draft, do: s.draft.history ++ [Map.delete(s.draft, :history)], else: [])
      }

      config = Ipse.Session.Draft.draft_config(s.config)

      Turn.draft_prompt(
        %{
          s
          | draft: draft,
            draft_mcp_definitions: if(mcp_snapshot, do: mcp_snapshot["definitions"]),
            draft_mcp_snapshot: mcp_snapshot,
            draft_mcp_interrupted: false,
            draft_mcp_pending: nil,
            draft_mcp_attempts: 0,
            draft_mcp_initial: Map.get(s.config, :mcp_servers, []) != [] and not s.mcp_discovered,
            draft_history_restricted: true,
            config: config,
            input_generation: Ipse.Usage.id()
        },
        text,
        observation
      )
    else
      _ -> {:reply, {:error, :draft_unavailable}, s}
    end
  end

  defp consume_draft_lines(s, lines) do
    Enum.reduce_while(lines, {:ok, []}, fn {text, ticket}, {:ok, pieces} ->
      case Ipse.Session.Input.submit(ticket, text, operator_binding(s, "prompt", nil)) do
        {:ok, observation} ->
          {:cont, {:ok, pieces ++ [%{"text" => text, "observation" => observation}]}}

        _ ->
          {:halt, {:error, :invalid_input_witness}}
      end
    end)
  end

  defp consume_accepted(s) do
    draft = s.draft
    turn = Ipse.Usage.id()
    event = Ipse.Session.Draft.consumed(draft, turn, s.messages)
    record(s, event)
    lineage = Ipse.Session.DraftLineage.entry(draft.accepted_event, turn)

    draft =
      Map.merge(draft, %{
        status: :consumed,
        accepted_turn: turn,
        accepted_input: false,
        accepted_message: false,
        end_count: event["end_count"],
        segment_sha256: event["segment_sha256"]
      })

    config = Map.get(draft, :prior_config, s.config)

    Turn.accepted_prompt(
      %{
        s
        | draft: draft,
          draft_lineages: s.draft_lineages ++ [lineage],
          config: config,
          reported_model: draft.prior_reported_model,
          historical_model: draft.prior_historical_model,
          input_generation: Ipse.Usage.id()
      },
      draft.proposal
    )
  end

  @doc false
  def cancel_work(s, keep_queued) do
    relation = s.managed_supersession != nil
    {cleanup, next} = stop_work(s, true, "cancelled", "cancelled", keep_queued)

    if Enum.any?(cleanup, &(&1 != :ok)) do
      notify(
        s,
        {:error,
         "Owned work cleanup could not be confirmed. Inspect running processes before retrying."}
      )

      notify(s, {:done, :error})

      {:stop, :normal, {:error, :cleanup_unconfirmed},
       close_epoch(next, "cleanup_failure", false)}
    else
      if relation, do: notify(s, :native_relation_ready)
      notify(s, {:done, :cancelled})
      {:reply, :ok, next}
    end
  end

  defp cancel_draft_work(s) do
    :ok = Ipse.Session.Input.invalidate()
    s = %{s | draft_render: nil}
    active = s.phase != :idle
    {cleanup, next} = if active, do: stop_work(s, true, "cancelled"), else: {[], s}

    if Enum.all?(cleanup, &(&1 == :ok)) do
      next = Turn.settle_mcp_revalidation(next)
      event = Ipse.Session.Draft.cancelled(next.draft, next.messages)
      record(next, event)

      next =
        Turn.append_message(next, %{"role" => "user", "content" => Ipse.Session.Draft.notice()})

      config = Map.get(next.draft, :prior_config, next.config)

      draft =
        Map.merge(next.draft, %{
          status: :cancelled,
          notice: true,
          end_count: event["end_count"],
          segment_sha256: event["segment_sha256"]
        })

      next = %{
        next
        | config: config,
          draft: draft,
          reported_model: draft.prior_reported_model,
          historical_model: draft.prior_historical_model
      }

      if active, do: notify(s, {:done, :cancelled})
      {:reply, :ok, next}
    else
      {:stop, :normal, {:error, :cleanup_unconfirmed},
       close_epoch(next, "cleanup_failure", false)}
    end
  end

  defp source_query(s, operation, request) do
    if is_map(request) and
         Ipse.Extension.SourceRead.validate(Map.put(request, "op", operation)) == :ok,
       do: Writer.source_query(s.journal_writer, {operation, request}),
       else: {:error, :source_index_refused}
  end

  defp source_lookup_prepared?(s, call, operation, request) do
    event = s.managed_lineage.source_lookups[call["id"]]

    is_map(event) and event["used"] != true and event["operation"] === operation and
      event["request_sha256"] === Ipse.JSON.digest([Map.put(request, "op", operation)])
  rescue
    _ -> false
  end

  defp consume_source_lookup(s, call_id),
    do: put_in(s.managed_lineage.source_lookups[call_id]["used"], true)

  defp stop_work(
         s,
         record_cancel,
         wait_outcome,
         feed_reason \\ "cancelled",
         keep_queued \\ false
       ) do
    document_revocation =
      if s.task && s.invocation.action &&
           Ipse.Extension.Collection.WorkspaceDocumentGuard.guarded_request?(
             s.invocation.action.intent["request"]
           ),
         do: Ipse.Session.Resources.revoke_document_effects(s.task.pid),
         else: :ok

    s =
      s
      |> Map.delete(:pending_chat_review)
      |> Map.put(:chat_reoffer_snapshot, nil)
      |> Map.delete(:post_reply_capture)
      |> Map.delete(:pending_nomination)
      |> Ipse.Session.ManagedToolUse.interrupted()

    :ok =
      if keep_queued, do: Ipse.Session.Input.cancel_read(), else: Ipse.Session.Input.invalidate()

    s = %{
      s
      | operator_render: nil,
        planning_save_active: nil,
        operator_answers: %{},
        operator_pieces: [],
        managed_result_seal: nil,
        managed_output_release: nil,
        managed_tool_effect: nil,
        managed_tool_result: nil,
        managed_approval: nil,
        managed_supersession: release_supersession_reservation(s)
    }

    s = CurrentInvocation.release_output(s)
    s = finish_wait(s, wait_outcome)
    s = if s.task, do: measure_request(s, :cancelled), else: s
    s = Turn.close_question(s)
    child_cleanup = Enum.map(Map.keys(s.delegation_resources), &close/1)
    child_reason = if feed_reason == "consumer_down", do: "owner_down", else: "cancelled"
    s = settle_children(s, child_reason)

    Enum.each(s.delegation_resources, fn {_, child} ->
      Process.demonitor(child.monitor, [:flush])
    end)

    cleanup =
      s.mcp_resources
      |> Map.keys()
      |> Enum.filter(&Process.alive?/1)
      |> Enum.map(&Ipse.MCP.StdioTransport.close/1)

    Ipse.Session.WorkerInput.interrupt(s)

    task_cleanup =
      if s.task,
        do: [document_revocation, Ipse.Session.Resources.close_task(s.task.pid)],
        else: []

    if s.task, do: Task.shutdown(s.task, :brutal_kill)

    if s.prompt_from, do: GenServer.reply(s.prompt_from, {:error, :cancelled})

    text_cleanup =
      Enum.map(s.extension_text, fn {_, resource} ->
        result =
          cond do
            resource.closed ->
              if is_pid(resource.pid) and Process.alive?(resource.pid),
                do: Process.exit(resource.pid, :kill)

              :ok

            is_pid(resource.pid) ->
              Ipse.Extension.TextConsumer.close(resource)

            true ->
              :ok
          end

        if result == :ok and is_binary(resource.subscription_id) do
          try do
            Ipse.Session.TextStream.unsubscribe(%{
              server: s.text_stream,
              subscription_id: resource.subscription_id
            })
          catch
            :exit, _ -> :ok
          end
        end

        if not resource.closed,
          do:
            record(
              s,
              Ipse.Extension.TextResources.closed(
                resource.intent,
                "cancelled",
                nil,
                nil,
                result == :ok
              )
            )

        result
      end)

    s =
      Turn.settle_calls(
        s,
        "Cancelled. If execution had started, its effects may have occurred. Inspect the workspace before retrying."
      )

    if record_cancel, do: record(s, %{"type" => "cancelled"})

    next =
      %{
        s
        | phase: :idle,
          prompt_from: nil,
          input_generation: Ipse.Usage.id(),
          task: nil,
          approval: nil,
          job_ref: nil,
          compaction: nil,
          extension_intent: nil,
          invocation: %CurrentInvocation{},
          extension_mcp_context: nil,
          event_intent: nil,
          event_received: nil,
          event_committed: nil,
          event_answer: nil,
          event_turn: nil,
          event_schedule: "before_request",
          event_after_started: false,
          extension_text: %{},
          extension_text_turn: nil,
          tool_decision: "not_decided",
          mcp_resources: %{},
          delegation_resources: %{},
          delegation_workers: MapSet.new(),
          delegation_queue: [],
          delegation_effect: nil,
          delegation_claims: %{}
      }

    text_cleanup =
      if s.extension_text_cleanup_failed or s.event_cleanup_failed or s.task_cleanup_failed,
        do: [{:error, :cleanup_unconfirmed} | text_cleanup],
        else: text_cleanup

    {feed_cleanup, feeds} = Feeds.close(s.feeds, feed_reason, &record(s, &1))

    {child_cleanup ++ cleanup ++ task_cleanup ++ text_cleanup ++ feed_cleanup,
     %{next | feeds: feeds}}
  end

  @impl true

  def handle_info(
        :managed_approval_share_failed,
        %{share_barrier: %{phase: :poisoned} = barrier} = s
      )
      when barrier.owner_protocol in [:managed_approval, :managed_relation_review] or
             is_map_key(barrier, :relation_publisher) or is_map_key(barrier, :worker_input) or
             is_map_key(barrier, :managed_capture),
      do: {:stop, :normal, s}

  def handle_info(_, %{share_barrier: %{phase: :poisoned}} = s), do: {:noreply, s}

  def handle_info(
        {port, {:data, bytes}},
        %{share_barrier: %{controlled: true, owner_port: port} = b} = s
      )
      when is_binary(bytes) and byte_size(bytes) + byte_size(b.owner_buffer) <= 128 do
    if share_deadline_current?(b) do
      case session_control_frames(s, b, b.owner_buffer <> bytes) do
        {:ok, next} -> maybe_deliver_controlled(%{s | share_barrier: next})
        _ -> {:noreply, poison_session_share(s)}
      end
    else
      {:noreply, poison_session_share(s)}
    end
  end

  def handle_info(
        {port, {:exit_status, 0}},
        %{share_barrier: %{controlled: true, phase: :transaction_closing, owner_port: port} = b} =
          s
      ) do
    if Process.alive?(b.caller) and share_deadline_current?(b) do
      send(b.caller, {:session_owner_control, b.capability, :closed})
      {:noreply, %{s | share_barrier: %{b | phase: :transaction_closed, owner_phase: :closed}}}
    else
      {:noreply, poison_session_share(s)}
    end
  end

  def handle_info(
        {port, {:exit_status, 0}},
        %{
          share_barrier:
            %{
              controlled: true,
              owner_protocol: protocol,
              phase: :review_input,
              owner_port: port
            } = b
        } = s
      )
      when protocol in [:synthetic_review, :managed_approval, :managed_relation_review] do
    if Map.get(b, :notice_final, false) and Process.alive?(b.caller) and
         share_deadline_current?(b) do
      send(b.caller, {:session_owner_control, b.capability, :closed})
      {:noreply, %{s | share_barrier: %{b | phase: :review_closed, owner_phase: :closed}}}
    else
      {:noreply, poison_session_share(s)}
    end
  end

  def handle_info(
        {port, {:exit_status, 0}},
        %{share_barrier: %{controlled: true, phase: :terminal_closing, owner_port: port} = b} = s
      ) do
    if (b.owner_protocol != :synthetic_notice or Map.get(b, :notice_final, false)) and
         Process.alive?(b.caller) and share_deadline_current?(b) do
      send(b.caller, {:session_owner_control, b.capability, :closed})
      {:noreply, %{s | share_barrier: %{b | phase: :terminal_closed, owner_phase: :closed}}}
    else
      {:noreply, poison_session_share(s)}
    end
  end

  def handle_info(
        {port, {:exit_status, _}},
        %{share_barrier: %{controlled: true, owner_port: port, owner_phase: :closed}} = s
      ),
      do: {:noreply, s}

  def handle_info({port, _}, %{share_barrier: %{controlled: true, owner_port: port}} = s),
    do: {:noreply, poison_session_share(s)}

  def handle_info(
        {:session_share_timeout, generation},
        %{share_barrier: %{generation: current}} = s
      )
      when is_reference(generation) and is_reference(current) and generation != current,
      do: {:noreply, s}

  def handle_info(message, %{share_barrier: %{request: request} = b} = s)
      when not is_nil(request) do
    case :gen_server.check_response(message, request) do
      {:reply, reply} -> session_share_response(s, b, reply)
      {:error, _} -> {:noreply, poison_session_share(s)}
      :no_reply -> {:noreply, poison_session_share(s)}
    end
  end

  def handle_info(_, %{share_barrier: barrier} = s) when not is_nil(barrier),
    do: {:noreply, poison_session_share(s)}

  def handle_info(
        {:extension_output_deadline, ref},
        %{job_ref: ref, extension_output_clock: clock} = s
      )
      when ref != nil and clock != nil do
    {cleanup, next} = stop_work(s, true, "interrupted")

    notify(
      s,
      {:error, "Complete-result deadline exceeded. Inspect prior actions before retrying."}
    )

    notify(s, {:done, :error})

    if Enum.all?(cleanup, &(&1 == :ok)),
      do: {:noreply, next},
      else: {:stop, :normal, close_epoch(next, "cleanup_failure", false)}
  end

  def handle_info({:extension_output_deadline, _}, s), do: {:noreply, s}

  def handle_info(
        {:delegated_approval, ref, worker, child, child_ref, name, args},
        %{job_ref: ref, task: %{}, phase: phase} = s
      )
      when ref != nil and phase in [:tool, :delegated_approval] do
    case s.delegation_resources[child] do
      %{worker: ^worker, down: false, finished: false} when length(s.delegation_queue) < 2 ->
        item = {worker, child, child_ref, name, args}
        {:noreply, next_delegated_approval(%{s | delegation_queue: s.delegation_queue ++ [item]})}

      _ ->
        {:noreply, s}
    end
  end

  def handle_info({:delegated_progress, ref, child, event}, %{job_ref: ref} = s)
      when ref != nil do
    case {s.delegation_resources[child], event} do
      {%{id: id}, {:tool, name, args}} ->
        notify(s, {:tool, "child #{id}/#{name}", args})

      {%{id: id}, {:status, status}} ->
        notify(s, {:subagent, id, status})

      {%{id: id}, {:tool_result, name, text}} ->
        notify(s, {:tool_result, "child #{id}/#{name}", text})

      _ ->
        :ok
    end

    s =
      if match?({:tool_result, _, _}, event) and s.delegation_effect == child,
        do: %{s | delegation_effect: nil},
        else: s

    {:noreply, next_delegated_approval(s)}
  end

  def handle_info(
        {:progress, ref, {:provider_usage, usage}},
        %{job_ref: ref, active_request: request} = s
      )
      when ref != nil and request != nil do
    entry = s.accounting.requests[request["request_id"]]
    event = Ipse.Usage.observation(request, usage, entry.sequence + 1)

    if entry.sequence < 64 and event["usage"] != entry.observation do
      {:noreply, account(s, event)}
    else
      {:noreply, s}
    end
  end

  def handle_info({:progress, ref, {:provider_usage, _}}, %{job_ref: ref} = s),
    do: {:noreply, s}

  def handle_info({:progress, ref, event}, %{job_ref: ref} = s) when ref != nil do
    if s.phase != :idle, do: notify(s, event)
    {:noreply, s}
  end

  def handle_info({ref, result}, %{task: %{ref: ref}} = s) do
    cleanup = Ipse.Session.Resources.close_task(s.task.pid)
    result = if cleanup == :ok, do: result, else: :task_cleanup_unconfirmed

    {result, s} =
      if s.phase in [:model, :compaction],
        do: Ipse.Session.InferenceDispatch.consume_result(s, Atom.to_string(s.phase), result),
        else: {result, s}

    s = measure_request(s, result)
    Process.demonitor(ref, [:flush])
    phase = if s.phase == :delegated_approval, do: :tool, else: s.phase
    s = %{s | task: nil}

    s =
      if cleanup == :ok and phase == :extension_command and s.managed_supersession != nil and
           not match?({:extension_question, _}, result) do
        notify(s, :native_relation_ready)

        if match?({:managed_supersession_finished, _}, result),
          do: s,
          else: %{s | managed_supersession: release_supersession_reservation(s)}
      else
        s
      end

    case {phase, result} do
      {:extension_command, {:managed_supersession_finished, outcome}} ->
        finish_supersession(s, outcome)

      {_, :task_cleanup_unconfirmed} ->
        {_, next} =
          stop_work(%{s | task_cleanup_failed: true}, true, "interrupted", "cleanup_failure")

        notify(
          s,
          {:error, "Task-owned OS cleanup could not be confirmed. Inspect before retrying."}
        )

        notify(s, {:done, :error})
        {:stop, :normal, close_epoch(next, "cleanup_failure", false)}

      {:managed_approval, result} ->
        Ipse.Session.ManagedApproval.complete(s, result)

      {:semantic_outer, {:extension_command_outer, request, result}} ->
        case CurrentInvocation.command_outer(s, request, result) do
          {:noreply, %{task: nil} = next} ->
            if s.managed_supersession != nil, do: notify(s, :native_relation_ready)
            next = planning_save_refused_unstarted(next)
            {:noreply, %{next | managed_supersession: release_supersession_reservation(next)}}

          {:noreply, next} ->
            {:noreply, %{next | planning_save_active: nil}}

          other ->
            other
        end

      {:semantic_outer, result} ->
        Turn.semantic_outer_completed(s, result)

      {invocation_phase, {:extension_question, action}}
      when invocation_phase in [:tool, :extension_command, :extension_service, :extension_events] ->
        CurrentInvocation.suspend_for_question(s, invocation_phase, action)

      {:extension_events, {:extension_invocation_result, event}} ->
        CurrentInvocation.complete_event_job(s, event)

      {invocation_phase, {:extension_released, id}}
      when invocation_phase in [:tool, :extension_command, :extension_service] ->
        Ipse.Session.ManagedOutput.complete(s, id)

      {:tool, {:managed_tool_released, id}} ->
        Ipse.Session.ManagedToolUse.complete_result(s, id)

      {invocation_phase, {:extension_saved_result, delivery}}
      when invocation_phase in [:tool, :extension_command] ->
        CurrentInvocation.publish_saved_result(s, delivery)

      {invocation_phase, {:extension_invocation_result, event}}
      when invocation_phase in [:tool, :extension_command, :extension_service, :extension_events] ->
        CurrentInvocation.publish_inline_result(s, event)

      {:extension_events, {:unknown, error}} ->
        if s.event_intent, do: record(s, Subscriptions.result(s.event_intent, "unknown", false))
        {:noreply, Turn.fail(%{s | event_intent: nil, event_cleanup_failed: true}, error)}

      {invocation_phase, {:unknown, error}}
      when invocation_phase in [:extension_command, :extension_service] ->
        {:noreply, Turn.fail(s, error)}

      {:extension_prompt, :ok} ->
        {:noreply, Turn.model(%{s | extension_intent: nil})}

      {:extension_events, :ok} ->
        {:noreply,
         if(s.event_schedule == "after_turn", do: Turn.finish(s, :ok), else: Turn.model(s))}

      {:extension_events, {:error, error}} ->
        {:noreply, Turn.fail(s, error)}

      {:extension_text_start, :ok} ->
        {:noreply, Turn.model(s)}

      {:extension_text_start, {:error, error}} ->
        {:noreply, Turn.fail(s, error)}

      {:extension_presentation, :ok} ->
        notify(s, {:presentation, s.final})
        {:noreply, Turn.finish(s, :ok)}

      {extension_phase, {:error, error}}
      when extension_phase in [:extension_prompt, :extension_presentation] ->
        {:noreply, Turn.fail(s, error)}

      {:mcp_discovery, {:ok, tools}} ->
        Turn.mcp_discovered(s, tools)

      {:mcp_discovery, {status, error}} when status in [:error, :unknown] ->
        {:noreply, Turn.fail(Turn.mcp_revalidation_failed(s, error), error)}

      {:tool, {:unknown, error}} ->
        {:noreply, Turn.fail(s, error)}

      {:context_preflight, {:ok, snapshot, drift}} ->
        Turn.context_checked(s, snapshot, drift)

      {:prompt_preflight, prepared} ->
        Turn.prompt_prepared(s, prepared)

      {:context_preflight, {:error, reason}} ->
        Turn.context_check_failed(s, reason)

      {:context_refresh, {:ok, snapshot, drift, skills}} ->
        Turn.context_refreshed(s, snapshot, drift, skills)

      {:context_refresh, {:error, reason}} ->
        Turn.context_refresh_failed(s, reason)

      {:compaction, {:ok, assistant, usage}} ->
        {:noreply, Turn.complete_compaction(s, assistant, usage)}

      {:compaction, {:error, _error}} ->
        {:noreply,
         Turn.compaction_failed(s, "The selected provider's summary request failed.", "summary")}

      {:model, {:ok, assistant, usage}} ->
        Turn.model_completed(s, assistant, usage)

      {:model, {:error, error}} ->
        {:noreply, Turn.fail(s, error)}

      {:tool, {:research_record, event, text}} ->
        record(s, event)
        {:noreply, Turn.tool_result(s, hd(s.calls), text, "result_recorded", s.tool_decision)}

      {:tool, {status, text}} when is_binary(text) ->
        Turn.tool_completed(s, status, text)

      _ ->
        {:noreply, Turn.fail(s, "Unexpected worker result")}
    end
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{owner_ref: ref, question: question} = s
      )
      when ref != nil and question != nil do
    {_cleanup, next} =
      stop_work(%{s | question: nil, calls: []}, false, "interrupted", "consumer_down")

    {:stop, :normal, close_epoch(next, "owner_down", false)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{owner_ref: ref} = s) when ref != nil do
    {_cleanup, next} = stop_work(s, true, "interrupted", "consumer_down")
    {:stop, :normal, close_epoch(next, "owner_down", false)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{journal_writer_ref: ref} = s),
    do: {:stop, :journal_unavailable, s}

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{lock_guard_ref: ref} = s) do
    notify(s, {:error, "Session lock owner stopped. Inspect before resuming."})
    notify(s, {:done, :error})
    {:stop, :normal, s}
  end

  def handle_info({:owned_task_cleanup_failed, worker}, %{task: %{pid: worker}} = s) do
    {_, next} =
      stop_work(%{s | task_cleanup_failed: true}, true, "interrupted", "cleanup_failure")

    notify(
      s,
      {:error,
       "Task-owned OS cleanup could not be confirmed. Inspect running processes before retrying."}
    )

    notify(s, {:done, :error})
    {:stop, :normal, close_epoch(next, "cleanup_failure", false)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{task: %{ref: ref}} = s) do
    s = measure_request(s, :worker_down)

    {_, next} =
      stop_work(%{s | task_cleanup_failed: true}, true, "interrupted", "cleanup_failure")

    notify(s, {:error, "Worker stopped unexpectedly; effects and OS cleanup are unconfirmed."})
    notify(s, {:done, :error})
    {:stop, :normal, close_epoch(next, "cleanup_failure", false)}
  end

  def handle_info({:extension_text_closed, consumer, id, reason, frames, bytes, cleanup}, s) do
    case s.extension_text[id] do
      %{pid: ^consumer, closed: false} = resource ->
        event =
          Ipse.Extension.TextResources.closed(resource.intent, reason, frames, bytes, cleanup)

        if Ipse.Extension.TextResources.valid_closed?(event, resource.intent) do
          record(s, event)

          notify(
            s,
            {:status,
             "Extension text consumer closed incomplete; original provider history is retained."}
          )

          {:noreply,
           %{
             s
             | extension_text: Map.put(s.extension_text, id, %{resource | closed: true}),
               extension_text_cleanup_failed: s.extension_text_cleanup_failed or not cleanup
           }}
        else
          {:noreply, s}
        end

      _ ->
        {:noreply, s}
    end
  end

  def handle_info({:feed_ready, pid, id}, s) do
    case s.feeds.resources[id] do
      %{pid: ^pid, ready: false, closed: false} = r ->
        if FeedChannel.active?(r) do
          record(s, Feeds.ready(r.intent))
          FeedChannel.admit(r)
          {:noreply, put_in(s, [:feeds, :resources, id], %{r | ready: true})}
        else
          {:noreply, s}
        end

      _ ->
        {:noreply, s}
    end
  end

  def handle_info({:feed_ack, pid, id, sequence}, s) do
    case s.feeds.resources[id] do
      %{pid: ^pid, ready: true, closed: false} = r ->
        if FeedChannel.active?(r) and sequence == r.ack + 1 and
             Ipse.Extension.Registry.live?(r.intent["identity"]) do
          case :ets.take(r.pending, sequence) do
            [{^sequence, intent}] ->
              record(s, Feeds.result(intent))
              :atomics.add(r.counters, 4, 1)
              send(pid, {:ack_committed, sequence})
              {:noreply, put_in(s, [:feeds, :resources, id], %{r | ack: sequence})}

            _ ->
              {:noreply, s}
          end
        else
          {:noreply, s}
        end

      _ ->
        {:noreply, s}
    end
  end

  def handle_info({:feed_closed, pid, id, cleanup}, s) when is_boolean(cleanup) do
    case s.feeds.resources[id] do
      %{pid: ^pid, closed: false} = r ->
        {:noreply, record_feed_close(s, id, r, cleanup)}

      _ ->
        {:noreply, s}
    end
  end

  def handle_info(
        {:DOWN, ref, :process, reader, _},
        %{
          phase: :idle,
          task: nil,
          pending_chat_review: %{state: state},
          operator_channel: %{reader: reader, reader_monitor: ref} = channel
        } = s
      )
      when state in [:ready, :claimed] do
    # Preserve the authenticated client/channel identity through confirmed
    # reader shutdown. Input cancellation is separately acknowledged before
    # the client can claim this handoff; client death still invalidates it.
    {:noreply, %{s | operator_channel: Map.put(channel, :reader_closed, true)}}
  end

  def handle_info({:DOWN, ref, :process, _pid, _}, %{operator_channel: channel} = s)
      when is_map(channel) and (ref == channel.client_monitor or ref == channel.reader_monitor) do
    :ok = Ipse.Session.Input.invalidate()
    Process.demonitor(channel.client_monitor, [:flush])
    Process.demonitor(channel.reader_monitor, [:flush])

    {:noreply,
     %{
       s
       | operator_channel: nil,
         chat_reoffer_snapshot: nil,
         draft_render: nil,
         operator_render: nil,
         assertion_render: nil,
         planning_decision_render: nil,
         operator_answers: %{},
         operator_pieces: []
     }}
  end

  def handle_info({:DOWN, ref, :process, pid, _}, s) do
    s =
      Enum.reduce(s.feeds.resources, s, fn {id, r}, state ->
        if r.monitor == ref and r.pid == pid and not r.closed,
          do: record_feed_close(state, id, r, false),
          else: state
      end)

    observation =
      Enum.reduce(s.observation.resources, s.observation, fn {id, resource}, capture ->
        if resource.monitor == ref and resource.pid == pid and not resource.closed do
          Ipse.Observability.Channel.revoke(resource)
          record(s, Ipse.Observability.receipt(resource.intent, "closed", false))

          notify(
            s,
            {:status, "Diagnostic sink exited; inspect /diagnostics for unconfirmed cleanup."}
          )

          put_in(capture, [:resources, id], %{resource | closed: true, cleanup: false})
        else
          capture
        end
      end)

    s = %{s | observation: observation}

    unconfirmed_text =
      Enum.any?(s.extension_text, fn {_, resource} ->
        resource.monitor == ref and resource.pid == pid and not resource.closed
      end)

    extension_text =
      Enum.reduce(s.extension_text, s.extension_text, fn {id, resource}, resources ->
        if resource.monitor == ref and resource.pid == pid do
          if not resource.closed,
            do: record(s, Ipse.Extension.TextResources.closed(resource.intent, "consumer_down"))

          Map.delete(resources, id)
        else
          resources
        end
      end)

    s = %{
      s
      | extension_text: extension_text,
        extension_text_cleanup_failed: s.extension_text_cleanup_failed or unconfirmed_text
    }

    s =
      if ref == s.text_stream_monitor,
        do: %{
          s
          | text_stream: if(s.text_required, do: s.text_stream, else: nil),
            text_stream_monitor: nil
        },
        else: s

    resources =
      if s.mcp_resources[pid] == ref, do: Map.delete(s.mcp_resources, pid), else: s.mcp_resources

    {children, child_down, child_usage} =
      case s.delegation_resources[pid] do
        %{monitor: ^ref} = child ->
          if not child.finished and s.task != nil and s.job_ref == child.job_ref and
               Process.alive?(child.worker) do
            {Map.put(s.delegation_resources, pid, %{child | down: true}), true, s.child_usage}
          else
            next =
              if child.finished,
                do: s,
                else:
                  record_child_outcome(
                    s,
                    Ipse.Tools.Delegation.child_finished(child, "unknown", "worker_failed", false)
                  )

            {Map.delete(s.delegation_resources, pid), true, next.child_usage}
          end

        _ ->
          {s.delegation_resources, false, s.child_usage}
      end

    s = %{s | mcp_resources: resources, delegation_resources: children, child_usage: child_usage}

    s =
      case s.approval do
        {:delegated, _, _, ^pid, _, _, _} when child_down ->
          finish_wait(%{s | approval: nil, phase: :tool}, "interrupted")

        _ ->
          s
      end

    s = if s.delegation_effect == pid, do: %{s | delegation_effect: nil}, else: s
    {:noreply, next_delegated_approval(s)}
  end

  def handle_info({port, {:exit_status, _}}, %{lock: port} = s) do
    # Stop without appending: journal ownership is no longer guaranteed.
    notify(s, {:error, "Session lock helper exited; stopping to protect the journal."})
    notify(s, {:done, :error})
    {:stop, :normal, s}
  end

  def handle_info({:observer_ready, pid, id}, s) do
    case s.observation.resources[id] do
      %{pid: ^pid, ready: false, closed: false} = resource ->
        if s.observation.policy["mode"] != "off" do
          record(s, Ipse.Observability.receipt(resource.intent, "ready"))
          resource = %{resource | ready: true}
          Ipse.Observability.Channel.admit(resource)
          {:noreply, put_in(s, [:observation, :resources, id], resource)}
        else
          Ipse.Observability.Channel.stop(resource)
          {:noreply, s}
        end

      _ ->
        {:noreply, s}
    end
  end

  def handle_info(
        {:text_policy, stream, ref, required},
        %{text_stream: stream, text_stream_policy_ref: ref} = s
      )
      when is_boolean(required),
      do: {:noreply, %{s | text_required: required}}

  def handle_info({:observer_closed, pid, id, cleanup}, s) when is_boolean(cleanup) do
    case s.observation.resources[id] do
      %{pid: ^pid, closed: false} = resource ->
        record(s, Ipse.Observability.receipt(resource.intent, "closed", cleanup))

        notify(
          s,
          {:status,
           "Diagnostic sink stopped; inspect /diagnostics for bounded delivery counters."}
        )

        {:noreply,
         put_in(s, [:observation, :resources, id], %{resource | closed: true, cleanup: cleanup})}

      _ ->
        {:noreply, s}
    end
  end

  def handle_info(_, s), do: {:noreply, s}

  defp session_share_response(s, %{phase: :draining} = b, {:ok, token, snapshot}) do
    if is_reference(token) and is_map(snapshot) and snapshot[:session_id] == s.id and
         relation_ticket_current?(s, b) and
         (not Map.has_key?(b, :expected_sources) or
            snapshot[:verified_sources] === b.expected_sources) and
         snapshot[:job_ref] == b.job_ref and snapshot[:owner_generation] == b.generation and
         share_binding_current?(s, b) and
         s.phase == b.session_phase and Process.alive?(b.caller) and
         (not Map.get(b, :controlled, false) or controlled_actor_current?(s, b)) and
         System.monotonic_time(:millisecond) < b.deadline do
      request =
        Ipse.Session.Lock.request_share_arm(s.lock_guard, s.journal_writer, token, b.operation)

      barrier =
        Map.merge(b, %{phase: :arming, request: request, token: token, snapshot: snapshot})

      {:noreply, %{s | share_barrier: barrier}}
    else
      {:noreply, poison_session_share(s)}
    end
  end

  defp session_share_response(s, %{phase: :arming} = b, {:ok, transport})
       when is_binary(transport) and byte_size(transport) == 16 do
    if Process.alive?(b.caller) and share_deadline_current?(b) do
      capability = make_ref()

      if Map.get(b, :controlled, false) do
        barrier =
          Map.merge(b, %{
            phase: :armed_wait,
            request: nil,
            capability: capability,
            transport: transport
          })

        maybe_deliver_controlled(%{s | share_barrier: barrier})
      else
        GenServer.reply(b.from, {:ok, capability, transport, b.snapshot})

        {:noreply,
         %{
           s
           | share_barrier:
               Map.merge(b, %{phase: :armed, request: nil, from: nil, capability: capability})
         }}
      end
    else
      {:noreply, poison_session_share(s)}
    end
  end

  defp session_share_response(s, %{phase: :cancelling} = b, :ok) do
    if Process.alive?(b.caller) and System.monotonic_time(:millisecond) < b.deadline do
      request = :gen_server.send_request(s.journal_writer, {:share_thaw, b.token, b.operation})
      {:noreply, %{s | share_barrier: %{b | phase: :thawing, request: request}}}
    else
      {:noreply, poison_session_share(s)}
    end
  end

  defp session_share_response(s, %{phase: :identifying} = b, {:ok, identity})
       when is_map(identity) do
    if Process.alive?(b.caller) and System.monotonic_time(:millisecond) < b.deadline and
         is_integer(identity[:pid]) and identity.pid > 0 and is_integer(identity[:device]) and
         identity.device >= 0 and is_integer(identity[:inode]) and identity.inode > 0 do
      GenServer.reply(b.from, {:ok, identity})
      {:noreply, %{s | share_barrier: %{b | phase: :armed, request: nil, from: nil}}}
    else
      {:noreply, poison_session_share(s)}
    end
  end

  defp session_share_response(s, %{phase: :writer_opening} = b, {:ok, identity})
       when is_map(identity) do
    if Process.alive?(b.caller) and share_deadline_current?(b) and
         is_integer(identity[:pid]) and identity.pid > 0 and is_integer(identity[:device]) and
         identity.device >= 0 and
         is_integer(identity[:inode]) and identity.inode > 0 do
      GenServer.reply(b.from, {:ok, identity})

      {:noreply,
       %{
         s
         | share_barrier:
             Map.merge(b, %{phase: :armed, request: nil, from: nil, writer_control: :ready})
       }}
    else
      {:noreply, poison_session_share(s)}
    end
  end

  defp session_share_response(s, %{phase: phase} = b, :ok)
       when phase in [:writer_transferring, :writer_preparing, :writer_closing] do
    if Process.alive?(b.caller) and share_deadline_current?(b) do
      GenServer.reply(b.from, :ok)

      next =
        case phase do
          :writer_transferring ->
            Map.merge(b, %{phase: :armed, writer_control: :transferred})

          :writer_preparing ->
            Map.merge(b, %{phase: :settled, writer_control: :closing})

          :writer_closing ->
            b |> Map.delete(:writer_control) |> Map.put(:phase, :transaction_closed)
        end

      {:noreply, %{s | share_barrier: %{next | request: nil, from: nil}}}
    else
      {:noreply, poison_session_share(s)}
    end
  end

  defp session_share_response(s, %{phase: phase} = b, :ok)
       when phase in [:exporting, :settling] do
    if Process.alive?(b.caller) and System.monotonic_time(:millisecond) < b.deadline do
      GenServer.reply(b.from, :ok)
      next = if phase == :exporting, do: :exported, else: :settled
      {:noreply, %{s | share_barrier: %{b | phase: next, request: nil, from: nil}}}
    else
      {:noreply, poison_session_share(s)}
    end
  end

  defp session_share_response(s, %{phase: :thawing} = b, :ok) do
    if Process.alive?(b.caller) and share_deadline_current?(b) do
      Process.cancel_timer(b.timer)
      GenServer.reply(b.from, :ok)
      {:noreply, %{s | share_barrier: nil}}
    else
      {:noreply, poison_session_share(s)}
    end
  end

  defp session_share_response(s, %{phase: :review_thawing} = b, :ok) do
    if Process.alive?(b.caller) and share_deadline_current?(b) and
         System.monotonic_time(:millisecond) < b.overall_deadline and
         System.system_time(:millisecond) < b.overall_wall do
      Process.cancel_timer(b.timer)

      timer =
        Process.send_after(
          self(),
          {:session_share_timeout, b.generation},
          max(b.overall_deadline - System.monotonic_time(:millisecond), 0)
        )

      GenServer.reply(b.from, :ok)

      {:noreply,
       %{
         s
         | share_barrier: %{
             b
             | phase: :review_input,
               request: nil,
               from: nil,
               deadline: b.overall_deadline,
               wall_deadline: b.overall_wall,
               timer: timer
           }
       }}
    else
      {:noreply, poison_session_share(s)}
    end
  end

  defp session_share_response(s, _, _), do: {:noreply, poison_session_share(s)}

  defp maybe_deliver_controlled(
         %{share_barrier: %{controlled: true, phase: :armed_wait, owner_phase: :ready} = b} = s
       ) do
    if Process.alive?(b.caller) and controlled_actor_current?(s, b) and
         System.monotonic_time(:millisecond) < b.deadline and
         Port.info(b.host_port, :connected) == {:connected, b.caller} do
      case Port.info(b.owner_port, :os_pid) do
        {:os_pid, pid} ->
          controls = %{
            operation: b.operation,
            deadline: b.deadline,
            session_pid: pid,
            host_port: b.host_port,
            channel_id:
              if(Map.has_key?(b, :worker_input) or Map.has_key?(b, :managed_capture),
                do: nil,
                else: b.channel.id
              ),
            original_source_proofs:
              b[:worker_source_proofs] || b[:relation_inactive_sources] || []
          }

          controls =
            if b.owner_protocol in [
                 :synthetic_notice,
                 :synthetic_review,
                 :managed_approval,
                 :managed_relation_review
               ],
               do:
                 Map.merge(controls, %{
                   wall_deadline: b.wall_deadline,
                   overall_deadline: b.overall_deadline,
                   overall_wall: b.overall_wall
                 }),
               else: controls

          controls =
            if Map.has_key?(b, :relation_display_inactive_sources),
              do:
                Map.put(
                  controls,
                  :relation_inactive_sha256,
                  Ipse.JSON.digest([b.relation_display_inactive_sources])
                ),
              else: controls

          controls =
            if b.owner_protocol == :managed_approval,
              do:
                Map.merge(controls, %{
                  payload: s.managed_approval.display,
                  allow_sha256: b.intent["allow_sha256"]
                }),
              else: controls

          controls =
            if b.owner_protocol == :managed_relation_review do
              Map.merge(controls, %{
                payload: b.review_payload,
                review_facts: b.review_facts,
                review_command: b.review_command,
                review_challenge: b.review_challenge,
                review_session_id: s.id
              })
            else
              controls
            end

          controls =
            if Map.has_key?(b, :relation_inactive_sources),
              do: Map.put(controls, :relation_source_proofs, b.relation_inactive_sources),
              else: controls

          GenServer.reply(b.from, {:ok, b.capability, b.transport, b.snapshot, controls})
          {:noreply, %{s | share_barrier: %{b | phase: :armed, from: nil}}}

        _ ->
          {:noreply, poison_session_share(s)}
      end
    else
      {:noreply, poison_session_share(s)}
    end
  end

  defp maybe_deliver_controlled(s), do: {:noreply, s}

  defp controlled_actor_current?(s, %{worker_input: sha, intent: intent}) do
    Ipse.Session.WorkerInput.current?(s, intent) and
      s.invocation.worker_input.snapshot.sha256 === sha
  end

  defp controlled_actor_current?(s, %{managed_capture: sha, intent: intent, caller: caller}),
    do:
      Ipse.Session.ManagedCapture.actor?(s, caller, intent) and
        Ipse.Session.ManagedCapture.binding_current?(s, sha)

  defp controlled_actor_current?(s, %{channel: channel}) do
    is_map(channel) and s.operator_channel == channel and
      Process.alive?(channel.client) and Process.alive?(channel.reader)
  end

  defp share_binding_current?(s, %{worker_input: _} = ticket),
    do: controlled_actor_current?(s, ticket)

  defp share_binding_current?(s, %{managed_capture: _} = ticket),
    do: controlled_actor_current?(s, ticket)

  defp share_binding_current?(s, %{relation_publisher: true} = ticket) do
    s.task != nil and s.job_ref == ticket.job_ref and
      supersession_worker?(s, ticket.caller, ticket.intent) and
      relation_ticket_current?(s, ticket)
  end

  defp share_binding_current?(s, %{protocol: :managed_approval} = ticket) do
    s.task != nil and s.job_ref == ticket.job_ref and
      (s.task.pid == ticket.caller or
         Ipse.Session.Resources.authorized_effect?(s.task.pid, ticket.caller)) and
      Ipse.Session.ManagedApproval.current?(s, ticket.intent)
  end

  defp share_binding_current?(s, %{owner_protocol: :managed_approval} = barrier),
    do: share_binding_current?(s, Map.put(barrier, :protocol, :managed_approval))

  defp share_binding_current?(s, ticket) do
    s.task != nil and s.job_ref == ticket.job_ref and s.task.pid == ticket.caller and
      match?(%{parent: _, action: %{intent: _}, interrupted: false}, s.invocation) and
      s.invocation.parent == ticket.parent and s.invocation.action.intent == ticket.intent and
      Ipse.Extension.Registry.live?(ticket.parent["identity"])
  end

  defp relation_ticket_current?(s, %{protocol: :managed_approval, intent: input}),
    do: Ipse.Session.ManagedApproval.current?(s, input)

  defp relation_ticket_current?(s, %{owner_protocol: :managed_approval, intent: input}),
    do: Ipse.Session.ManagedApproval.current?(s, input)

  defp relation_ticket_current?(s, %{relation_display_purpose_sha256: sha} = ticket) do
    with %{prepared: prepared, candidate: candidate, records: [event]} <- s.managed_supersession,
         true <- sha === Ipse.JSON.digest([prepared, candidate]),
         true <- Ipse.Session.ManagedSupersession.record?(event, prepared, candidate, []),
         {:ok, sources} <-
           Ipse.Session.ManagedSupersession.reviewed_display_sources(
             event["facts"],
             s.id,
             System.system_time(:millisecond)
           ),
         true <- sources.facts_sha256 === ticket.relation_display_facts_sha256,
         true <- sources.active === ticket.source_proofs,
         true <- sources.inactive === ticket.relation_display_inactive_sources do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp relation_ticket_current?(s, %{relation_purpose_sha256: sha} = ticket) do
    with %{prepared: prepared, candidate: candidate, records: [event, review_event]} <-
           s.managed_supersession,
         true <- sha === Ipse.JSON.digest([prepared, candidate]),
         true <- ticket.relation_facts_sha256 === Ipse.JSON.digest([event["facts"]]),
         true <- ticket.relation_review_sha256 === Ipse.JSON.digest([review_event]),
         {:ok, sources} <-
           Ipse.Session.ManagedSupersession.reviewed_publication_sources(
             event["facts"],
             review_event["review"],
             s.id,
             System.system_time(:millisecond)
           ),
         true <- sources.active === ticket.source_proofs,
         true <- sources.inactive === ticket.relation_inactive_sources do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp relation_ticket_current?(_, _), do: true

  defp synthetic_review_manifest?(prefix, b) do
    with <<operation::binary-size(16), count, rest::binary>> <- prefix,
         true <- operation === b.operation and count in 4..132,
         true <-
           not Map.has_key?(b, :relation_display_inactive_sources) or
             count ===
               4 +
                 (b.relation_display_inactive_sources
                  |> Enum.map(& &1["session_id"])
                  |> Enum.uniq()
                  |> length()) + length(Map.get(b, :approval_journals, %{ids: []}).ids),
         <<session_pid::32, _session::binary-size(64), host_pid::32, _host::binary-size(64),
           entries::binary-size(^count * 85), _device::64, _inode::64, _rdev::64, expiry::64,
           native_deadline::64, overall_wall::64, native_overall::64>> <- rest,
         {:os_pid, ^session_pid} <- Port.info(b.owner_port, :os_pid),
         {:os_pid, ^host_pid} <- Port.info(b.host_port, :os_pid),
         true <- expiry === b.wall_deadline and overall_wall === b.overall_wall,
         true <- native_deadline > 0 and native_overall >= native_deadline,
         true <- synthetic_review_source_locks_match?(entries, b) do
      actual =
        for <<slot, op::binary-size(16), _identity::binary-size(68) <- entries>>,
          do: {slot, op}

      expected =
        [{0, b.transport}, {0, b.operation}, {1, b.operation}, {2, b.operation}] ++
          List.duplicate({0, b.operation}, count - 4)

      actual === expected
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp synthetic_review_source_locks_match?(entries, %{
         relation_display_inactive_sources: _,
         snapshot: snapshot
       }) do
    with locks when is_list(locks) <- snapshot[:inactive_source_locks] do
      actual =
        for <<_slot, _operation::binary-size(16), _pid::32, _name::binary-size(16),
              _secret::binary-size(32), device::64, inode::64 <- entries>>,
            do: {device, inode}

      expected = Enum.map(locks, &{&1.device, &1.inode})
      Enum.sort(Enum.drop(actual, 4)) === Enum.sort(expected)
    else
      _ -> false
    end
  end

  defp synthetic_review_source_locks_match?(_, _), do: true

  defp share_deadline_current?(%{deadline: deadline, wall_deadline: wall} = share)
       when is_map_key(share, :worker_input) or is_map_key(share, :managed_capture),
       do:
         System.monotonic_time(:millisecond) < deadline and
           System.system_time(:millisecond) < wall

  defp share_deadline_current?(%{
         owner_protocol: protocol,
         deadline: deadline,
         wall_deadline: wall
       })
       when protocol in [
              :synthetic_notice,
              :synthetic_review,
              :managed_approval,
              :managed_relation_review
            ] and
              is_integer(wall),
       do:
         System.monotonic_time(:millisecond) < deadline and
           System.system_time(:millisecond) < wall

  defp share_deadline_current?(%{owner_protocol: :synthetic_notice}), do: false
  defp share_deadline_current?(%{owner_protocol: :synthetic_review}), do: false
  defp share_deadline_current?(%{owner_protocol: :managed_approval}), do: false
  defp share_deadline_current?(%{owner_protocol: :managed_relation_review}), do: false

  defp share_deadline_current?(%{deadline: deadline}),
    do: System.monotonic_time(:millisecond) < deadline

  defp session_control_frames(_s, b, buffer) when byte_size(buffer) < 5,
    do: {:ok, %{b | owner_buffer: buffer}}

  defp session_control_frames(s, b, <<kind, size::32, rest::binary>> = buffer) when size <= 32 do
    if byte_size(rest) < size do
      {:ok, %{b | owner_buffer: buffer}}
    else
      <<body::binary-size(^size), tail::binary>> = rest

      next =
        case {kind, body, b.owner_phase} do
          {?R, "owner-control-v1", :starting} when b.owner_protocol == :legacy ->
            %{b | owner_phase: :ready}

          {?R, "owner-control-v2", :starting} when b.owner_protocol == :synthetic_notice ->
            %{b | owner_phase: :ready}

          {?R, "owner-control-v2", :starting}
          when b.owner_protocol in [
                 :synthetic_review,
                 :managed_approval,
                 :managed_relation_review
               ] ->
            %{b | owner_phase: :ready}

          {?H, <<operation::binary-size(16), 1>>, :sending} when operation == b.operation ->
            %{b | owner_phase: :bound}

          {?T, <<operation::binary-size(16), 1>>, :bound} when operation == b.operation ->
            send(b.caller, {:session_owner_control, b.capability, :transferred})
            %{b | owner_phase: :transferred}

          {?N, <<operation::binary-size(16), 1, expiry::64>>, :transferred}
          when operation == b.operation and
                 b.owner_protocol in [
                   :synthetic_notice,
                   :synthetic_review,
                   :managed_approval,
                   :managed_relation_review
                 ] and
                 b.phase in [:settling, :settled] ->
            if expiry == b.wall_deadline and Map.has_key?(b, :issued_terminal) and
                 not Map.get(b, :notice_received, false) do
              send(b.caller, {:session_owner_control, b.capability, :notice})
              Map.put(b, :notice_received, true)
            end

          {?F, <<operation::binary-size(16), 1>>, :transferred}
          when operation == b.operation and
                 b.owner_protocol in [
                   :synthetic_notice,
                   :synthetic_review,
                   :managed_approval,
                   :managed_relation_review
                 ] and
                 b.phase in [:terminal_closing, :review_input] ->
            if Map.get(b, :notice_received, false) and not Map.get(b, :notice_final, false),
              do: Map.put(b, :notice_final, true)

          _ ->
            nil
        end

      if next, do: session_control_frames(s, next, tail), else: :error
    end
  end

  defp session_control_frames(_, _, _), do: :error

  defp close_share_controls(
         %{controlled: true, phase: :transaction_closed, owner_phase: :closed} = b
       ) do
    if Port.info(b.host_port) == nil and Port.info(b.owner_port) == nil,
      do: {:ok, b},
      else: {:error, :cleanup_unconfirmed}
  end

  defp close_share_controls(
         %{controlled: true, phase: :terminal_closed, owner_phase: :closed} = b
       ) do
    if Port.info(b.host_port) == nil and Port.info(b.owner_port) == nil and
         (not Map.has_key?(b, :issued_terminal) or Port.info(b.issued_terminal.port) == nil),
       do: {:ok, b},
       else: {:error, :cleanup_unconfirmed}
  end

  defp close_share_controls(%{controlled: true} = b) do
    if Port.info(b.host_port) == nil and Ipse.Runner.close_owner_control(b.owner_port) == :ok,
      do: {:ok, %{b | owner_phase: :closed}},
      else: {:error, :cleanup_unconfirmed}
  end

  defp close_share_controls(b), do: {:ok, b}

  defp transfer_synthetic_terminal(port, caller) do
    with {:os_pid, pid} when is_integer(pid) and pid > 0 <- Port.info(port, :os_pid),
         true <- Port.connect(port, caller) do
      Process.unlink(port)
      {:ok, pid}
    else
      _ ->
        if Port.info(port, :connected) == {:connected, self()}, do: Port.close(port)
        :error
    end
  rescue
    _ ->
      if Port.info(port, :connected) == {:connected, self()}, do: Port.close(port)
      :error
  end

  defp poison_session_share(%{share_barrier: %{phase: :poisoned}} = s), do: s

  defp poison_session_share(%{share_barrier: b} = s) do
    Process.cancel_timer(b.timer)
    if Map.get(b, :controlled, false), do: Ipse.Runner.close_owner_control(b.owner_port)
    if b.from, do: GenServer.reply(b.from, {:error, :cleanup_unconfirmed})
    if s.task && Process.alive?(s.task.pid), do: Process.exit(s.task.pid, :kill)

    if b[:owner_protocol] in [:managed_approval, :managed_relation_review] or
         Map.get(b, :relation_publisher, false) or Map.has_key?(b, :worker_input) or
         Map.has_key?(b, :managed_capture) do
      notify(
        s,
        {:error, "Protected review ownership was lost; inspect the journal before further work."}
      )

      send(self(), :managed_approval_share_failed)
    end

    %{s | share_barrier: Map.merge(b, %{phase: :poisoned, from: nil, request: nil})}
  end

  @impl true

  def terminate(_reason, s) do
    if s.task, do: Ipse.Session.Resources.close_task(s.task.pid)
    if s.task, do: Task.shutdown(s.task, :brutal_kill)

    Enum.each(s.extension_text, fn {_, resource} ->
      if is_pid(resource.pid) and Process.alive?(resource.pid),
        do: Process.exit(resource.pid, :kill)
    end)

    Enum.each(s.observation.resources, fn {_, resource} ->
      Ipse.Observability.Channel.revoke(resource)
      if Process.alive?(resource.pid), do: Process.exit(resource.pid, :kill)
    end)

    Enum.each(s.feeds.resources, fn {_, resource} ->
      FeedChannel.stop(resource, "consumer_down")
      if Process.alive?(resource.pid), do: Process.exit(resource.pid, :kill)
    end)

    # A timed-out append may still be queued or inside IO. Stop its sole writer
    # before releasing the session lock; never retry an unconfirmed record.
    stop_writer(s)

    if Process.alive?(s.lock_guard), do: Ipse.Session.Lock.release(s.lock_guard)

    :ok
  end

  defp stop_writer(s) do
    Process.unlink(s.journal_writer)
    writer_ref = Process.monitor(s.journal_writer)
    Process.exit(s.journal_writer, :kill)

    receive do
      {:DOWN, ^writer_ref, :process, _, _} -> :ok
    end

    :ok
  end

  defp stop_writer_confirmed(s) do
    Process.unlink(s.journal_writer)
    writer_ref = Process.monitor(s.journal_writer)
    Process.exit(s.journal_writer, :kill)

    receive do
      {:DOWN, ^writer_ref, :process, _, :killed} -> :ok
      {:DOWN, ^writer_ref, :process, _, _} -> {:error, :cleanup_unconfirmed}
    end
  end

  defp release_lock_confirmed(guard) do
    if Process.alive?(guard),
      do: Ipse.Session.Lock.release(guard),
      else: {:error, :cleanup_unconfirmed}
  catch
    :exit, _ -> {:error, :cleanup_unconfirmed}
  end

  defp close_epoch_for_release(s) do
    {context, records} = Ipse.Session.RuntimeLifecycle.close(s.lifecycle, "close", false)
    next = lifecycle_records(s, {context, records})
    {next, Enum.find(records, &(&1["type"] == "lifecycle_epoch_closed"))}
  end

  defp prepare_release(%{lock_mode: mode, release_owner: owner} = s, closure, cleanup)
       when mode in [:header_v1, :resume_v1, :header_share_v2, :resume_share_v2] and is_map(owner) do
    with true <- Enum.all?(cleanup, &(&1 == :ok)),
         false <- is_map(s.lifecycle) and not s.lifecycle.active and is_nil(closure),
         {:ok, lock} <-
           Ipse.Session.Lock.header_identity(
             s.lock_guard,
             System.monotonic_time(:millisecond) + 2_000
           ),
         {:ok, helper} <- Ipse.Runner.protected_helper_digest(),
         {:ok, intent, key} <-
           Ipse.Session.ReleaseReceipt.prepare(
             s.id,
             owner["owner_id"],
             if(closure, do: closure["epoch_id"]),
             closure,
             s.release_origin,
             lock,
             helper
           ),
         :ok <- Writer.append(s.journal_writer, intent) do
      {:ok, intent, key, lock}
    else
      _ -> {:error, :cleanup_unconfirmed}
    end
  end

  defp prepare_release(_, _, _), do: {:error, :cleanup_unconfirmed}

  defp complete_release(s, {:ok, intent, key, lock}, cleanup) do
    with true <- Enum.all?(cleanup, &(&1 == :ok)),
         {:ok, bytes} <- Ipse.Session.ReleaseReceipt.seal(intent, key),
         :ok <-
           Ipse.Runner.publish_session_release(
             s.dir,
             s.id,
             intent["operation_id"],
             s.release_origin,
             lock,
             bytes
           ) do
      :ok
    else
      _ -> {:error, :cleanup_unconfirmed}
    end
  end

  defp complete_release(_, _, _), do: {:error, :cleanup_unconfirmed}

  @impl true

  def format_status(status) do
    Map.new(status, fn
      {:state, state} -> {:state, Map.take(state, [:id, :phase])}
      {:message, _} -> {:message, :redacted}
      {:reason, _} -> {:reason, :redacted}
      {:log, _} -> {:log, []}
      pair -> pair
    end)
  end

  defp workspace_snapshot(events, cwd, home, supplied) do
    case Enum.find(Enum.reverse(events), &(&1["type"] == "workspace_context_snapshot")) do
      nil when supplied != nil ->
        if Workspace.valid?(supplied) and supplied["cwd"] == cwd,
          do: {:ok, supplied, true},
          else: {:error, :invalid_workspace_context_snapshot}

      nil ->
        case Workspace.snapshot(cwd, home) do
          {:ok, snapshot} -> {:ok, snapshot, true}
          {:error, reason} -> {:error, {:workspace_context_unavailable, reason}}
        end

      %{"version" => 1, "snapshot" => snapshot} ->
        if Workspace.valid?(snapshot) and snapshot["cwd"] == cwd,
          do: {:ok, snapshot, false},
          else: {:error, :invalid_workspace_context_snapshot}

      _ ->
        {:error, :invalid_workspace_context_snapshot}
    end
  end

  @doc false
  def persist_context(s, snapshot, force \\ false) do
    if force or snapshot != s.context_snapshot do
      record(s, %{
        "type" => "workspace_context_snapshot",
        "version" => 1,
        "snapshot" => snapshot
      })
    end

    %{s | context_snapshot: snapshot}
  end

  @doc false
  def persist_skills(s, skills) do
    if not s.skills_saved or s.skills != skills do
      record(s, Workspace.skill_checkpoint(skills))
      %{s | skills: skills, skills_saved: true}
    else
      s
    end
  end

  defp inference_approval?(name, args),
    do:
      ModelCall.delegated_approval?(name, args) or EmbeddingCall.delegated_approval?(name, args) or
        DecisionCall.delegated_approval?(name, args)

  defp next_delegated_approval(%{approval: approval} = s) when approval != nil, do: s
  defp next_delegated_approval(%{delegation_queue: []} = s), do: s

  defp next_delegated_approval(s) do
    index =
      Enum.find_index(s.delegation_queue, fn {_, _, _, name, args} ->
        s.delegation_effect == nil or inference_approval?(name, args)
      end)

    if index == nil do
      s
    else
      {item, rest} = List.pop_at(s.delegation_queue, index)
      dispatch_delegated_approval(%{s | delegation_queue: rest}, item)
    end
  end

  defp dispatch_delegated_approval(s, {worker, child, ref, name, args}) do
    case s.delegation_resources[child] do
      %{id: id, worker: ^worker, down: false, finished: false} ->
        mode = Map.get(s.config, :approval, :ask)
        conflict = delegated_conflict?(s, child, name, args)

        cond do
          Ipse.Tools.Delegation.validate_approval(args) != :ok or conflict or mode == :deny ->
            record(s, %{
              "type" => "delegation_approval",
              "child_id" => id,
              "name" => name,
              "arguments" => args,
              "decision" => if(conflict, do: "conflict_denied", else: "policy_denied")
            })

            send(worker, {:delegated_decision, child, ref, false})
            next_delegated_approval(s)

          mode == :ask ->
            approval = make_ref()

            s =
              begin_wait(s, "delegated_tool", %{
                "turn_id" => s.turn_id,
                "request_id" => s.last_request_id,
                "child_id" => id
              })

            notify(s, {:approval, approval, "child #{id}/#{name}", args})

            %{
              s
              | phase: :delegated_approval,
                approval: {:delegated, approval, worker, child, ref, name, args}
            }

          true ->
            record(s, %{
              "type" => "delegation_approval",
              "child_id" => id,
              "name" => name,
              "arguments" => args,
              "decision" => "session_allow"
            })

            send(worker, {:delegated_decision, child, ref, true})
            claim_delegated_effect(s, child, name, args)
        end

      _ ->
        next_delegated_approval(s)
    end
  end

  defp delegated_target(s, name, args) when name in ["write", "edit"] do
    if is_binary(args["path"]),
      do: Tools.path_key(Path.expand(args["path"], s.cwd)) || "*",
      else: "*"
  end

  defp delegated_target(_, _, _), do: "*"

  defp retire_child(s, child) do
    s = %{s | delegation_resources: Map.delete(s.delegation_resources, child)}

    s =
      case s.approval do
        {:delegated, _, _, ^child, _, _, _} ->
          finish_wait(%{s | approval: nil, phase: :tool}, "interrupted")

        _ ->
          s
      end

    if s.delegation_effect == child, do: %{s | delegation_effect: nil}, else: s
  end

  @doc false
  def settle_children(s, reason) do
    Enum.reduce(s.delegation_resources, s, fn {pid, child}, state ->
      state =
        if child.finished,
          do: state,
          else:
            record_child_outcome(
              state,
              Ipse.Tools.Delegation.child_finished(child, "unknown", reason, false)
            )

      if child.down do
        Process.demonitor(child.monitor, [:flush])
        retire_child(state, pid)
      else
        put_in(state, [:delegation_resources, pid], %{child | finished: true})
      end
    end)
  end

  defp record_child_outcome(s, event) do
    record(s, event)
    %{s | child_usage: Ipse.Extension.ChildUsage.apply_parent(s.child_usage, event)}
  end

  defp delegated_conflict?(s, child, name, args) do
    target = delegated_target(s, name, args)

    not inference_approval?(name, args) and
      Enum.any?(s.delegation_claims, fn {claimed, owner} ->
        owner != child and (target == "*" or claimed == "*" or target == claimed)
      end)
  end

  defp claim_delegated_effect(s, child, name, args) do
    if inference_approval?(name, args) do
      s
    else
      %{
        s
        | delegation_effect: child,
          delegation_claims: Map.put(s.delegation_claims, delegated_target(s, name, args), child)
      }
    end
  end

  @doc false
  def optional_source(s, event) do
    record_extension_lineage(s, event)

    case Writer.append_observed(s.journal_writer, event) do
      {:ok, source} ->
        offer_record(s, source, event)
        source

      {:error, reason} ->
        journal_failed(s, reason)
    end
  end

  defp prepare_supersession_intake(s, %{purpose: nil}, _, _),
    do: {:ok, %{s | managed_supersession: release_supersession_reservation(s)}}

  defp prepare_supersession_intake(s, %{purpose: purpose}, assertion, source) do
    with {:ok, _, name} <- Ipse.Session.OperatorAssertion.selection(s.config),
         {:ok, _, descriptor} <- Ipse.Extension.Catalog.lookup(s.config, "invoke.command", name),
         {:ok, %{"proof" => proof}} <- Writer.source_query(s.journal_writer, {:proof, source}),
         prepared =
           Map.merge(purpose, %{
             "type" => "managed_supersession_prepared",
             "version" => 1,
             "id" => Ipse.Usage.id(),
             "session_id" => s.id,
             "assertion_id" => assertion["id"],
             "pin_sha256" => Ipse.JSON.digest([s.config.semantic_admission["pin"]]),
             "descriptor_sha256" => Ipse.JSON.digest([descriptor])
           }),
         true <- Ipse.Session.ManagedSupersession.prepared?(prepared, s.id) do
      {:ok,
       %{
         s
         | managed_supersession: %{
             prepared: prepared,
             source: source,
             proof: proof,
             candidate: nil,
             records: [],
             token: nil
           }
       }}
    else
      _ -> {:error, :managed_supersession_refused}
    end
  end

  defp link_planning_assertion(s, %{planning_decision: receipt} = pending, event) do
    id = receipt["id"]

    with %{receipt: ^receipt, exited: true, attempted: false} = decision <-
           s.planning_decisions[id],
         true <- Ipse.Session.PlanningDecisions.valid_accepted?(receipt, s.id),
         true <- event["text"] === receipt["text"] and event["category"] == "ordinary",
         true <- is_map(pending.planning_save_observation) do
      started =
        Ipse.Session.PlanningDecisions.save_started(
          s.id,
          receipt,
          pending.planning_save_observation
        )

      record(s, started)
      linked = Map.put(event, "planning_decision", receipt)
      decisions = Map.put(s.planning_decisions, id, %{decision | attempted: true, asserted: true})
      {:ok, %{s | planning_decisions: decisions, planning_save_active: id}, linked}
    else
      _ -> {:error, :planning_save_refused}
    end
  end

  defp link_planning_assertion(s, _, event), do: {:ok, s, event}

  defp planning_save_refused_unstarted(%{planning_save_active: id} = s) when is_binary(id) do
    case s.planning_decisions[id] do
      %{receipt: receipt, attempted: true, asserted: true, refused: false} = decision ->
        record(s, Ipse.Session.PlanningDecisions.refused_unstarted(s.id, receipt))
        decisions = Map.put(s.planning_decisions, id, %{decision | refused: true})
        %{s | planning_decisions: decisions, planning_save_active: nil}

      _ ->
        %{s | planning_save_active: nil}
    end
  end

  defp planning_save_refused_unstarted(s), do: s

  defp invoke_assertion_capture(s, name, args) do
    case CurrentInvocation.invoke_export(s, :command, name, args) do
      {:reply, :ok, started} = result ->
        if started.managed_supersession,
          do: record(started, started.managed_supersession.prepared)

        result

      {:reply, error, refused} ->
        refused = planning_save_refused_unstarted(refused)

        {:reply, error,
         %{refused | managed_supersession: release_supersession_reservation(refused)}}
    end
  end

  defp supersession_worker?(s, caller, intent) do
    s.phase in [:tool, :extension_command, :extension_service, :extension_events] and
      is_map(s.task) and
      (s.task.pid == caller or Ipse.Session.Resources.authorized_effect?(s.task.pid, caller)) and
      not s.invocation.interrupted and s.invocation.action != nil and
      s.invocation.action.intent === intent and
      Ipse.Extension.Registry.live?(s.invocation.parent["identity"])
  end

  defp supersession_lookup(s, caller, intent) do
    with true <- supersession_worker?(s, caller, intent) do
      case s.managed_supersession do
        nil ->
          {:ok, nil}

        %{prepared: prepared, candidate: candidate, proof: proof} = pending ->
          with true <- s.phase == :extension_command,
               true <-
                 s.config[:managed_supersession_layout] ==
                   Ipse.Session.ManagedSupersession.layout(),
               true <- is_nil(candidate) or candidate === intent,
               true <- Ipse.Extension.ManagedCollectionCall.operation?(intent["request"]),
               true <- intent["request"]["metadata_version"] === 3,
               true <-
                 prepared["pin_sha256"] == Ipse.JSON.digest([intent["effect_binding"]["pin"]]),
               true <-
                 prepared["descriptor_sha256"] ==
                   Ipse.JSON.digest([s.invocation.parent["descriptor"]]),
               {:ok, origin} when is_map(origin) <-
                 Writer.source_query(s.journal_writer, :origin),
               {:ok, _} <- Writer.source_query(s.journal_writer, {:stored_proof, proof}),
               [request] <- intent["request"]["proofs"],
               {:ok, actual} <- Writer.source_query(s.journal_writer, {:proof, request}),
               true <- actual["proof"] === proof do
            {:ok,
             %{
               purpose: prepared,
               prepared: prepared,
               proof: proof,
               source: pending.source,
               source_binding: {:supersession, Ipse.JSON.digest([prepared, intent])}
             }}
          else
            _ -> {:error, :managed_supersession_refused}
          end
      end
    else
      _ -> {:error, :managed_supersession_refused}
    end
  rescue
    _ -> {:error, :managed_supersession_refused}
  end

  defp supersession_source_proofs(s, caller, sha, proofs) do
    with %{candidate: intent} <- s.managed_supersession,
         {:ok, binding} when is_map(binding) <- supersession_lookup(s, caller, intent),
         true <- binding.source_binding == {:supersession, sha},
         true <- is_list(proofs) and length(proofs) in 1..8 and binding.proof in proofs,
         true <- Enum.all?(proofs, &(is_map(&1) and &1["session_id"] == s.id)),
         {:ok, verified} <- supersession_proofs(s, proofs) do
      {:ok, verified}
    else
      _ -> {:error, :managed_supersession_refused}
    end
  end

  defp supersession_effect_ticket(s, {caller, _} = from, ref, intent, proofs) do
    if s.task.pid == caller do
      handle_call({:session_control_ticket_source_fixture, ref, intent, proofs}, from, s)
    else
      with true <- s.share_barrier == nil and s.lock_mode in [:header_share_v2, :resume_share_v2],
           true <- supersession_worker?(s, caller, intent),
           true <-
             Enum.any?(s.config.extensions, &(&1.identity == s.invocation.parent["identity"])),
           {:ok, sources} <- supersession_proofs(s, proofs),
           %{client: client, reader: reader} = channel <- s.operator_channel,
           true <- Process.alive?(client) and Process.alive?(reader) do
        ticket = %{
          ticket: make_ref(),
          operation: :crypto.strong_rand_bytes(16),
          deadline: System.monotonic_time(:millisecond) + 5_000,
          caller: caller,
          job_ref: ref,
          intent: intent,
          parent: s.invocation.parent,
          phase: s.phase,
          channel: channel,
          relation_publisher: true,
          source_proofs: proofs,
          expected_sources: sources
        }

        {:reply, {:ok, ticket.ticket, ticket.operation, ticket.deadline},
         %{s | share_ticket: ticket}}
      else
        _ -> {:reply, {:error, :session_share_refused}, s}
      end
    end
  end

  defp supersession_proofs(s, proofs) do
    Enum.reduce_while(proofs, {:ok, []}, fn proof, {:ok, acc} ->
      case Writer.source_query(s.journal_writer, {:stored_proof, proof}) do
        {:ok, verified} -> {:cont, {:ok, acc ++ [verified]}}
        _ -> {:halt, {:error, :managed_supersession_refused}}
      end
    end)
  end

  defp supersession_record(s, caller, sha, event) do
    with %{candidate: candidate} = pending when is_map(candidate) <- s.managed_supersession,
         {:ok, binding} when is_map(binding) <- supersession_lookup(s, caller, candidate),
         true <- binding.source_binding == {:supersession, sha},
         true <-
           Ipse.Session.ManagedSupersession.record?(
             event,
             pending.prepared,
             candidate,
             pending.records
           ),
         {:ok, token} <- supersession_reservation(s, pending.token) do
      pending = %{pending | token: token}
      append_supersession(s, pending, event)
      {:reply, :ok, %{s | managed_supersession: %{pending | records: pending.records ++ [event]}}}
    else
      _ -> {:reply, {:error, :managed_supersession_refused}, s}
    end
  end

  defp supersession_reservation(s, nil),
    do: Writer.reserve(s.journal_writer, %{events: 4, bytes: 131_072})

  defp supersession_reservation(_, token), do: {:ok, token}

  defp append_supersession(s, pending, event) do
    record_extension_lineage(s, event)

    case Writer.append_reserved(s.journal_writer, pending.token, event) do
      :ok -> :ok
      {:error, reason} -> journal_failed(s, reason)
    end
  end

  defp release_supersession_reservation(s) do
    if is_map(s.managed_supersession) and s.managed_supersession.token != nil do
      case Writer.release(s.journal_writer, s.managed_supersession.token) do
        :ok -> :ok
        {:error, reason} -> journal_failed(s, reason)
      end
    end

    nil
  end

  defp finish_supersession(s, delivery) do
    with %{candidate: candidate} = pending <- s.managed_supersession,
         result when is_map(result) <- List.last(pending.records),
         true <- result["type"] == "managed_supersession_result",
         true <-
           delivery === %{
             "version" => 1,
             "kind" => "managed_supersession_delivery",
             "purpose_sha256" => result["purpose_sha256"],
             "status" => result["status"],
             "outcome" => result["outcome"]
           },
         action when is_map(action) <- List.last(s.invocation.results),
         event = %{
           "type" => "managed_supersession_delivered",
           "version" => 1,
           "purpose_sha256" => result["purpose_sha256"],
           "candidate_operation_id" => candidate["operation_id"],
           "operation_id" => result["operation_id"],
           "parent_invocation_id" => candidate["parent_invocation_id"],
           "delivery" => delivery
         },
         true <-
           Ipse.Session.ManagedSupersession.record?(
             event,
             pending.prepared,
             candidate,
             pending.records ++ [action]
           ) do
      append_supersession(s, pending, event)
      release_supersession_reservation(s)
      display = supersession_display(event)
      notify(s, {:extension_result, display})
      next = CurrentInvocation.release_output(s)

      {:noreply,
       Turn.finish(
         %{
           next
           | managed_supersession: nil,
             invocation: %CurrentInvocation{},
             extension_result: display
         },
         if(delivery["status"] == "settled", do: :ok, else: :error)
       )}
    else
      _ ->
        {:noreply,
         Turn.fail(
           %{s | managed_supersession: release_supersession_reservation(s)},
           "Supersession outcome or cleanup is unconfirmed; inspect the retained operation. No action was replayed."
         )}
    end
  end

  @doc false
  def supersession_display(event) do
    delivery = event["delivery"]
    normalized = get_in(delivery, ["outcome", "publication", "normalization"]) || %{}

    value = %{
      "version" => 1,
      "kind" => "managed_supersession_receipt",
      "status" => delivery["status"],
      "operation_id" => event["operation_id"],
      "historical_receipt" => true,
      "original_capture" => "not_executed"
    }

    value =
      Enum.reduce(~w(old_lineage new_lineage), value, fn key, acc ->
        if Ipse.JSON.sha256?(normalized[key]), do: Map.put(acc, key, normalized[key]), else: acc
      end)

    %{"name" => "knowledge.supersession", "stage" => "host.lifecycle", "value" => value}
  end

  @doc false
  def record(s, event) do
    record_extension_lineage(s, event)

    result =
      if event["type"] not in ~w(input_received reference_admitted reference_refresh reference_epoch reference_envelope) and
           ((s.observation != nil and s.observation.policy["mode"] != "off") or
              Feeds.active?(s.feeds)),
         do: Writer.append_observed(s.journal_writer, event),
         else: Writer.append(s.journal_writer, event)

    case result do
      :ok -> :ok
      {:ok, source} -> offer_record(s, source, event)
      {:error, reason} -> journal_failed(s, reason)
    end
  end

  @doc false
  def record_source(s, event) do
    record_extension_lineage(s, event)

    case Writer.append_with_source(s.journal_writer, event) do
      {:ok, source} ->
        offer_record(s, source, event)
        source

      {:error, reason} ->
        journal_failed(s, reason)
    end
  end

  defp record_extension_lineage(s, event) do
    if s.draft_lineages != [] and Ipse.Session.DraftLineage.extension_target?(event) do
      marker =
        Ipse.Session.DraftLineage.extension_intent(s.id, s.turn_id, event, s.draft_lineages)

      case Writer.append(s.journal_writer, marker) do
        :ok -> :ok
        {:error, reason} -> journal_failed(s, reason)
      end
    end
  end

  @doc false
  def journal_failed(s, :journal_limit_reached) do
    notify(
      s,
      {:error,
       "Journal resource limit reached. History was preserved; inspect it and use an explicit fresh-session handoff before continuing."}
    )

    exit(:journal_limit_reached)
  end

  @doc false
  def journal_failed(_s, _reason), do: exit(:journal_unavailable)

  @doc false
  def notify(s, event), do: send(s.subscriber, {:ipse, self(), event})

  @doc false
  def offer_record(s, source, event) do
    if s.observation, do: Ipse.Observability.offer(s.observation, source, event)

    if not match?(%{status: :pending}, s.draft) do
      Feeds.offer(
        s.feeds,
        source,
        event,
        fn intent ->
          record_extension_lineage(s, intent)

          case Writer.append(s.journal_writer, intent) do
            :ok -> :ok
            {:error, reason} -> journal_failed(s, reason)
          end
        end,
        fn -> managed_empty?(s) end
      )
    end

    :ok
  end

  @doc false
  def enroll_feeds(%{draft: %{status: :pending}} = s), do: s

  def enroll_feeds(s) do
    feeds = Feeds.enroll(s.feeds, s.config, self(), &record_source(s, &1))

    if s.tool_lifecycle != nil and not Ipse.Session.ToolLifecycle.recording?(s.tool_lifecycle) do
      Enum.each(feeds.resources, fn {_, resource} ->
        if resource.intent["declaration"]["event"] in ~w(tool.intent_committed tool.outcome_recorded tool.recording_stopped),
          do: FeedChannel.stop(resource, "source_unavailable")
      end)
    end

    if feeds.refused > s.feeds.refused,
      do:
        notify(
          s,
          {:status, "Event feed lease capacity refused enrollment; inspect /diagnostics."}
        )

    %{s | feeds: feeds}
  end

  defp record_feed_close(s, id, r, cleanup) do
    FeedChannel.stop(r, "consumer_down")
    record(s, Feeds.closed(r, cleanup))
    :ets.delete_all_objects(r.pending)

    notify(
      s,
      {:status, "Event feed closed; inspect /diagnostics for incomplete coverage and cleanup."}
    )

    put_in(s, [:feeds, :resources, id], %{r | closed: true, cleanup: cleanup})
  end

  @doc false
  def admit_request(s, config, kind) do
    event = Ipse.Usage.admission(s.id, config, kind, s.turn_id)
    s = account(s, event)

    %{
      s
      | active_request: event,
        last_request_id: event["request_id"],
        child_usage: Ipse.Extension.ChildUsage.apply_parent(s.child_usage, event)
    }
  end

  @doc false
  def account(s, event) do
    {:ok, accounting} = Ipse.Usage.apply_event(s.accounting, event)
    record(s, event)
    next = %{s | accounting: accounting}

    if event["type"] == "request_finished" and Map.has_key?(next, :managed_lineage),
      do: managed_event(next, event),
      else: next
  end

  @doc false
  def record_extension_action(s, event) do
    if Ipse.Extension.Actions.inference?(event["request"]) do
      account(s, event)
    else
      record(s, event)

      contributions =
        Ipse.Extension.Context.admit_replacement(
          s.extension_contributions,
          if(s.invocation.parent, do: s.invocation.parent["identity"]),
          event,
          if(s.reference, do: Ipse.Session.Reference.layout())
        )

      %{s | extension_contributions: contributions}
    end
  end

  @doc false
  def measure_request(%{extension_model: %{admission: admission, started: started}} = s, result) do
    observed = s.accounting.requests[admission["request_id"]].observation

    event =
      Ipse.Usage.completion(
        admission,
        result,
        max(System.monotonic_time(:millisecond) - started, 0),
        observed
      )

    s = account(s, event)
    %{s | extension_model: nil}
  end

  @doc false
  def measure_request(
        %{phase: phase, request_started_at: started, active_request: admission} = s,
        result
      )
      when phase in [:model, :compaction] and is_integer(started) and admission != nil do
    outcome =
      cond do
        result == :cancelled -> "cancelled"
        match?({:ok, _, _}, result) -> "completed"
        true -> "failed"
      end

    record(s, %{
      "type" => "request_measured",
      "kind" => Atom.to_string(phase),
      "outcome" => outcome,
      "duration_ms" => max(System.monotonic_time(:millisecond) - started, 0)
    })

    observed = s.accounting.requests[admission["request_id"]].observation

    event =
      Ipse.Usage.completion(
        admission,
        result,
        max(System.monotonic_time(:millisecond) - started, 0),
        observed
      )

    s = account(s, event)
    if phase == :model, do: Turn.finish_text(s.text_stream, admission["request_id"], outcome)
    %{s | active_request: nil, request_started_at: nil}
  end

  @doc false
  def measure_request(s, _), do: s

  defp usage_version(config) do
    cond do
      Ipse.Config.Decisions.enabled?(config) -> 3
      Ipse.Config.Profiles.embeddings_enabled?(config) -> 2
      true -> 1
    end
  end

  # Versioned journals identify each owner before it performs startup effects.
  # Repair a validated torn tail under the same retained lock first, because
  # Writer.open refuses a torn tail. It does not adopt any earlier receipt.
  defp start_release_owner(dir, id, config, events, mode) do
    case get_in(hd(events), ["metadata", "release_receipt_layout"]) do
      nil ->
        {:ok, nil}

      layout ->
        with true <- layout == Ipse.Session.ReleaseReceipt.layout(),
             true <- mode in [:header_v1, :resume_v1, :header_share_v2, :resume_share_v2],
             {:ok, _} <- Ipse.Session.ReleaseReceipt.intents(events, id),
             {:ok, _} <- Saved.restore(events, id),
             :ok <- repair_session_tail(dir, id, config, mode),
             {:ok, writer} <- Writer.start(dir, id, self(), config[:journal], mode),
             :ok <- Ipse.Session.Lock.track(writer, :writer),
             {:ok, marker} <- Ipse.Session.ReleaseReceipt.owner_started(id),
             :ok <- Writer.append(writer, marker) do
          {:ok, %{writer: writer, marker: marker}}
        else
          _ -> {:error, :session_release_owner_unconfirmed}
        end
    end
  end

  defp repair_session_tail(dir, id, config, mode)
       when mode in [:header_v1, :resume_v1, :header_share_v2, :resume_share_v2],
       do: Journal.repair_tail_fenced(dir, id, config[:journal], Ipse.Session.Lock.current())

  defp repair_session_tail(dir, id, config, _mode),
    do: Journal.repair_tail(dir, id, config[:journal])

  defp startup_writer(_dir, _id, _config, %{writer: writer}), do: {:ok, writer}

  defp startup_writer(dir, id, config, nil) do
    with {:ok, writer} <- Writer.start(dir, id, self(), config[:journal]),
         :ok <- Ipse.Session.Lock.track(writer, :writer),
         do: {:ok, writer}
  end

  defp open_and_lock(dir, nil, cwd, config, :export_v1),
    do: open_fresh(dir, cwd, config, :export_v1)

  defp open_and_lock(dir, nil, cwd, config, :share_candidate_v2),
    do: open_fresh(dir, cwd, config, :header_share_v2)

  defp open_and_lock(dir, nil, cwd, config, :legacy) do
    if :os.type() == {:unix, :linux},
      do: open_fresh(dir, cwd, config, :header_share_v2),
      else: open_then_lock(dir, nil, cwd, config, :legacy)
  end

  defp open_and_lock(dir, id, cwd, config, mode),
    do: open_then_lock(dir, id, cwd, config, mode)

  defp open_then_lock(dir, id, cwd, config, mode) do
    opened =
      if is_nil(id),
        do: open_fresh(dir, cwd, config, :legacy),
        else: open_existing(dir, id, cwd, config)

    with {:ok, id, events, config} <- opened,
         {:ok, selected_mode} <- select_resume_lock(mode, id, events),
         {:ok, _} <- Registry.register(Ipse.Registry, {dir, id}, nil),
         {:ok, lock} <- acquire_lock(Path.join(dir, id <> ".lock"), 10, selected_mode),
         do: {:ok, id, events, config, lock}
  end

  defp select_resume_lock(:legacy, id, [%{"metadata" => metadata} | _] = events) do
    if :os.type() == {:unix, :linux} and
         metadata["release_receipt_layout"] == Ipse.Session.ReleaseReceipt.layout() do
      with {:ok, anchor} <- header_lock_anchor(metadata),
           {:ok, intents} <- Ipse.Session.ReleaseReceipt.intents(events, id),
           true <- is_map(anchor) or intents != [] do
        {:ok, :resume_share_v2}
      else
        _ -> {:error, :session_lock_identity_unavailable}
      end
    else
      {:ok, :legacy}
    end
  end

  defp select_resume_lock(:share_candidate_v2, id, [%{"metadata" => metadata} | _] = events) do
    with true <- :os.type() == {:unix, :linux},
         true <- metadata["release_receipt_layout"] == Ipse.Session.ReleaseReceipt.layout(),
         {:ok, anchor} <- header_lock_anchor(metadata),
         {:ok, intents} <- Ipse.Session.ReleaseReceipt.intents(events, id),
         true <- is_map(anchor) or intents != [] do
      {:ok, :resume_share_v2}
    else
      _ -> {:error, :session_lock_identity_unavailable}
    end
  end

  defp select_resume_lock(mode, _, _), do: {:ok, mode}

  defp verify_resume_lock(mode, events, id) when mode in [:resume_v1, :resume_share_v2] do
    with true <-
           get_in(hd(events), ["metadata", "release_receipt_layout"]) ==
             Ipse.Session.ReleaseReceipt.layout(),
         {:ok, anchor} <- header_lock_anchor(hd(events)["metadata"]),
         {:ok, intents} <- Ipse.Session.ReleaseReceipt.intents(events, id),
         intent = List.last(intents),
         true <- is_map(anchor) or is_map(intent),
         {:ok, lock} <-
           Ipse.Session.Lock.header_identity(
             Ipse.Session.Lock.current(),
             System.monotonic_time(:millisecond) + 2_000
           ),
         true <-
           is_nil(anchor) or {lock.device, lock.inode} == {anchor["device"], anchor["inode"]},
         true <-
           is_nil(intent) or
             {lock.device, lock.inode} == {intent["lock_device"], intent["lock_inode"]} do
      :ok
    else
      _ -> {:error, :session_lock_identity_unavailable}
    end
  end

  defp verify_resume_lock(_, _, _), do: :ok

  defp header_lock_anchor(metadata) do
    case metadata["session_lock_identity"] do
      nil ->
        {:ok, nil}

      %{"version" => 1, "device" => device, "inode" => inode} = anchor
      when map_size(anchor) == 3 ->
        if Ipse.JSON.safe_uint?(device) and Ipse.JSON.safe_uint?(inode) and inode > 0,
          do: {:ok, anchor},
          else: {:error, :session_lock_identity_unavailable}

      _ ->
        {:error, :session_lock_identity_unavailable}
    end
  end

  defp open_fresh(dir, cwd, config, lock_mode) do
    config = Ipse.MCP.fingerprint_version(config, 2)
    config = Map.put(config, :source_layout, Ipse.Session.SourceWindow.layout())
    config = Map.put(config, :managed_read_layout, Ipse.Session.ManagedReads.layout())
    config = Map.put(config, :managed_tool_layout, Ipse.Session.ManagedToolUse.layout())
    config = Map.put(config, :managed_action_layout, Ipse.Session.ManagedToolUse.action_layout())

    config =
      Map.put(config, :managed_supersession_layout, Ipse.Session.ManagedSupersession.layout())

    with {:ok, config} <- Ipse.Config.Activation.fresh(config, cwd),
         {:ok, mode} <- Ipse.Extension.Mode.capture(config),
         config = apply_execution_mode(config, mode),
         selected_id = Ipse.Usage.id(),
         {:ok, semantic_admission} <-
           Ipse.Extension.SemanticAdmission.fresh(config, cwd, selected_id),
         :ok <- Ipse.Config.Activation.admitted(config, semantic_admission),
         config = Map.put(config, :semantic_admission, semantic_admission),
         {:ok, lock} <- fresh_candidate_lock(dir, selected_id, lock_mode),
         {:ok, lock_anchor} <- fresh_lock_anchor(lock_mode),
         {:ok, id} <-
           create_fresh_journal(
             lock_mode,
             dir,
             selected_id,
             Map.merge(
               %{
                 "cwd" => cwd,
                 "reference_layout" => Ipse.Session.Reference.layout(),
                 "source_layout" => Ipse.Session.SourceWindow.layout(),
                 "pending_acceptance_layout" => Ipse.Session.PendingAcceptance.layout(),
                 "source_origin_layout" => Ipse.Journal.SourceOrigin.layout(),
                 "release_receipt_layout" =>
                   if(lock_mode in [:header_v1, :header_share_v2],
                     do: Ipse.Session.ReleaseReceipt.layout()
                   ),
                 "session_lock_identity" => lock_anchor,
                 "managed_read_layout" => Ipse.Session.ManagedReads.layout(),
                 "managed_output_layout" => Ipse.Session.ManagedOutput.layout(),
                 "managed_tool_layout" => Ipse.Session.ManagedToolUse.layout(),
                 "managed_action_layout" => Ipse.Session.ManagedToolUse.action_layout(),
                 "managed_supersession_layout" => Ipse.Session.ManagedSupersession.layout(),
                 "execution_mode" => mode,
                 "semantic_admission" => semantic_admission,
                 "usage_version" => usage_version(config),
                 "embedding_profiles" => Ipse.Config.Profiles.embedding_snapshot(config),
                 "decision_profiles" => Ipse.Config.Decisions.snapshot(config),
                 "max_output_tokens" => config[:max_output_tokens],
                 "model_profiles" => ModelCall.snapshot(config),
                 "budget" => config[:budget],
                 "budget_root" => config[:budget_root],
                 "provider" => to_string(config.provider),
                 "provider_destination" => provider_destination(config),
                 "model" => config.model,
                 "sandbox" => to_string(Map.get(config, :sandbox, :off)),
                 "mcp_servers" => Ipse.MCP.fingerprints(config),
                 "mcp_fingerprint_version" => 2,
                 "subagents" => Ipse.Tools.Delegation.enabled?(config),
                 "subagent_concurrency" => Map.get(config, :subagent_concurrency, 1),
                 "delegation_origin" => config[:delegation_origin],
                 "configuration" => Map.get(config, :configuration),
                 "execution" => Map.get(config, :execution),
                 "extensions" => Ipse.Extension.Registry.manifests(config),
                 "extension_catalog" => extension_catalog(config),
                 "extension_subscriptions" => Subscriptions.snapshot(config)
               },
               Map.merge(
                 if(Map.get(config, :planning_mcp_reads, %{}) == %{},
                   do: %{},
                   else: %{"planning_mcp_protocol" => 1}
                 ),
                 if(config[:planning_cli_start] === true,
                   do: %{
                     "planning_local_start" =>
                       Ipse.Session.PlanningTransition.startup(selected_id, mode)
                   },
                   else: %{}
                 )
               )
             ),
             config[:journal]
           ),
         do:
           if(lock_mode == :legacy,
             do: {:ok, id, [], config},
             else: {:ok, id, [], config, lock}
           )
  end

  defp create_fresh_journal(mode, dir, id, metadata, policy)
       when mode in [:header_v1, :header_share_v2],
       do: Journal.create_with_locked_id(dir, id, metadata, policy, Ipse.Session.Lock.current())

  defp create_fresh_journal(_, dir, id, metadata, policy),
    do: Journal.create_with_id(dir, id, metadata, policy)

  defp fresh_lock_anchor(mode) when mode in [:header_v1, :header_share_v2] do
    with {:ok, lock} <-
           Ipse.Session.Lock.header_identity(
             Ipse.Session.Lock.current(),
             System.monotonic_time(:millisecond) + 2_000
           ),
         true <-
           Ipse.JSON.safe_uint?(lock.device) and Ipse.JSON.safe_uint?(lock.inode) and
             lock.inode > 0 do
      {:ok, %{"version" => 1, "device" => lock.device, "inode" => lock.inode}}
    else
      _ -> {:error, :session_lock_identity_unavailable}
    end
  end

  defp fresh_lock_anchor(_), do: {:ok, nil}

  defp fresh_candidate_lock(_dir, _id, :legacy), do: {:ok, nil}

  defp fresh_candidate_lock(dir, id, :export_v1) do
    with :ok <- File.mkdir_p(dir),
         :ok <- File.chmod(dir, 0o700),
         {:ok, _} <- Registry.register(Ipse.Registry, {dir, id}, nil),
         do: acquire_lock(Path.join(dir, id <> ".lock"), 10, :export_v1)
  end

  defp fresh_candidate_lock(dir, id, :header_v1) do
    with :ok <- File.mkdir_p(dir),
         :ok <- File.chmod(dir, 0o700),
         {:ok, _} <- Registry.register(Ipse.Registry, {dir, id}, nil),
         do: acquire_lock(Path.join(dir, id <> ".lock"), 10, :header_v1)
  end

  defp fresh_candidate_lock(dir, id, :header_share_v2) do
    with :ok <- File.mkdir_p(dir),
         :ok <- File.chmod(dir, 0o700),
         {:ok, _} <- Registry.register(Ipse.Registry, {dir, id}, nil),
         do: acquire_lock(Path.join(dir, id <> ".lock"), 10, :header_share_v2)
  end

  defp open_existing(dir, id, cwd, config) do
    with {:ok, [%{"metadata" => meta} | _] = events} <- Journal.load(dir, id, config[:journal]),
         :ok <- Ipse.Journal.writable_events(events),
         {:ok, version} <- Ipse.MCP.Config.journal_fingerprint_version(meta),
         config = Ipse.MCP.fingerprint_version(config, version),
         true <- meta["source_layout"] in [nil, Ipse.Session.SourceWindow.layout()],
         config = Map.put(config, :source_layout, meta["source_layout"]),
         {:ok, managed_layout} <- Ipse.Session.ManagedReads.marker(meta),
         config = Map.put(config, :managed_read_layout, managed_layout),
         {:ok, tool_layout} <- Ipse.Session.ManagedToolUse.marker(meta),
         config = Map.put(config, :managed_tool_layout, tool_layout),
         {:ok, action_layout} <- Ipse.Session.ManagedToolUse.action_marker(meta),
         config = Map.put(config, :managed_action_layout, action_layout),
         {:ok, supersession_layout} <- Ipse.Session.ManagedSupersession.marker(meta),
         config = Map.put(config, :managed_supersession_layout, supersession_layout),
         {:ok, saved_mode} <- Saved.execution_mode(events, id),
         {:ok, mode} <- resume_execution_mode(saved_mode, config),
         config = apply_execution_mode(config, mode),
         {:ok, saved_admission} <- Saved.semantic_admission(events, id),
         {:ok, config} <- Ipse.Config.Activation.resume(config, cwd, id, saved_admission),
         {:ok, semantic_admission} <-
           Ipse.Extension.SemanticAdmission.resume(config, cwd, id, saved_admission),
         :ok <- Ipse.Config.Activation.admitted(config, semantic_admission),
         config = Map.put(config, :semantic_admission, semantic_admission),
         {:ok, old_cwd} <- Workspace.canonical_path(meta["cwd"]),
         true <-
           old_cwd == cwd and meta["provider"] == to_string(config.provider) and
             matching_destination?(meta, config, events) and
             meta["model"] == config.model and
             meta["max_output_tokens"] === config[:max_output_tokens] and
             meta["model_profiles"] === ModelCall.snapshot(config) and
             meta["embedding_profiles"] === Ipse.Config.Profiles.embedding_snapshot(config) and
             meta["decision_profiles"] === Ipse.Config.Decisions.snapshot(config) and
             meta["budget"] === config[:budget] and meta["budget_root"] === config[:budget_root] and
             Map.get(meta, "sandbox", "off") == to_string(Map.get(config, :sandbox, :off)) and
             Map.get(meta, "mcp_servers", []) == Ipse.MCP.fingerprints(config) and
             Map.get(meta, "subagents", false) == Ipse.Tools.Delegation.enabled?(config) and
             Map.get(meta, "subagent_concurrency", 1) == Map.get(config, :subagent_concurrency, 1) and
             meta["delegation_origin"] == config[:delegation_origin] and
             compatible_configuration?(meta["configuration"], config[:configuration]) and
             Ipse.MCP.Planning.saved_configuration?(meta["configuration"], config) and
             meta["planning_mcp_protocol"] ===
               if(Map.get(config, :planning_mcp_reads, %{}) == %{}, do: nil, else: 1) and
             meta["execution"] == json_execution(config[:execution]) and
             Map.get(meta, "extensions", []) == Ipse.Extension.Registry.manifests(config),
         true <-
           Map.get(meta, "extension_catalog", %{"version" => 1, "entries" => []}) ==
             extension_catalog(config),
         true <-
           Map.get(meta, "extension_subscriptions", %{"version" => 1, "entries" => []}) ==
             Subscriptions.snapshot(config),
         :ok <- Ipse.Session.Saved.validate_handoff_events(events),
         {:ok, _} <- Ipse.Usage.restore(events, id),
         {:ok, _messages} <- restore_context(events) do
      {:ok, id, events, config}
    else
      false -> {:error, :resume_configuration_mismatch}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_session}
    end
  end

  defp planning_cli_start_valid(config) do
    case Map.get(config, :planning_cli_start, false) do
      false ->
        :ok

      true ->
        with nil <- config[:delegation_origin],
             {:ok, mode} <- Ipse.Extension.Mode.capture(config),
             true <- mode["ceiling"] == "planning" and mode["enclosing_ceiling"] == "normal" do
          :ok
        else
          _ -> {:error, :invalid_planning_start_origin}
        end

      _ ->
        {:error, :invalid_planning_start_origin}
    end
  end

  defp planning_cli_resume_entry?(config, previous, mode, checkpoint) do
    config[:planning_cli_start] === true and is_map(checkpoint) and
      Ipse.Extension.Mode.valid?(previous) and previous["ceiling"] == "normal" and
      previous["enclosing_ceiling"] == "normal" and mode["ceiling"] == "planning" and
      mode["enclosing_ceiling"] == "normal"
  end

  defp resume_execution_mode(nil, config), do: Ipse.Extension.Mode.capture(config)
  defp resume_execution_mode(saved, config), do: Ipse.Extension.Mode.resume(saved, config)

  defp apply_execution_mode(config, mode) do
    Map.merge(config, %{
      approval: String.to_existing_atom(mode["approval"]),
      approval_origin: mode["approval_origin"],
      headless: mode["headless"],
      execution_mode: mode["ceiling"],
      enclosing_mode: mode["enclosing_ceiling"],
      knowledge_ceiling: mode["knowledge"]
    })
  end

  defp extension_catalog(config) do
    {:ok, catalog} = Catalog.snapshot(config)
    catalog
  end

  defp provider_configuration(%{provider: :demo}), do: :ok

  defp provider_configuration(config) do
    case Ipse.Provider.destination(config) do
      {:ok, _} -> :ok
      _ -> {:error, :invalid_provider_endpoint}
    end
  end

  defp provider_destination(%{provider: :demo}), do: nil

  defp provider_destination(config) do
    {:ok, destination} = Ipse.Provider.destination(config)
    destination
  end

  defp matching_destination?(metadata, config, events) do
    if Map.has_key?(metadata, "provider_destination") do
      metadata["provider_destination"] === provider_destination(config)
    else
      expected =
        if is_binary(config[:base_url]), do: Ipse.JSON.sha256(config.base_url)

      requests =
        Enum.filter(
          events,
          &(&1["type"] == "request_admitted" and &1["kind"] in ~w(model compaction))
        )

      if requests == [],
        do:
          is_nil(expected) or
            (metadata["execution"] == json_execution(config[:execution]) and
               config[:execution] != nil),
        else: Enum.all?(requests, &(&1["endpoint_sha256"] === expected))
    end
  end

  defp compatible_configuration?(nil, nil), do: true
  defp compatible_configuration?(nil, %{"sources" => []}), do: true
  defp compatible_configuration?(nil, %{sources: []}), do: true

  defp compatible_configuration?(old, current) when is_map(old) and is_map(current) do
    old["fingerprint"] == (current[:fingerprint] || current["fingerprint"])
  end

  defp compatible_configuration?(_, _), do: false

  defp json_execution(nil), do: nil
  defp json_execution(execution), do: execution |> Jason.encode!() |> Jason.decode!()

  defp runtime(s),
    do: Ipse.Session.Context.runtime_snapshot(s.config, s.reported_model, s.historical_model)

  @doc "Validate saved effective context without starting inference, tools or a session."

  defdelegate restore_context(events), to: Ipse.Session.Saved, as: :context

  defp lifecycle_records(s, {context, records}) do
    Enum.each(records, &record(s, &1))
    %{s | lifecycle: context}
  end

  @doc false
  def ensure_source_window(s) do
    if Ipse.Session.SourceWindow.enabled?(s.config) do
      case Writer.ensure_source_window(s.journal_writer) do
        :ok -> :ok
        {:error, reason} -> journal_failed(s, reason)
      end
    end

    s
  end

  @doc false
  def ensure_source_tracking(s) do
    if Ipse.Session.SourceWindow.enabled?(s.config) do
      s = ensure_source_window(s)

      s =
        if s.lifecycle == nil,
          do:
            lifecycle_records(
              s,
              Ipse.Session.RuntimeLifecycle.open_source(
                s.source_runtime_summary,
                s.id,
                s.source_resumed
              )
            ),
          else: s

      if s.tool_lifecycle == nil,
        do:
          Turn.tool_records(
            s,
            Ipse.Session.ToolLifecycle.open_source(s.source_tool_summary, s.id, s.lifecycle)
          ),
        else: s
    else
      s
    end
  end

  @doc false
  def begin_wait(s, domain, links),
    do: lifecycle_records(s, Ipse.Session.RuntimeLifecycle.begin_wait(s.lifecycle, domain, links))

  @doc false
  def finish_wait(s, outcome),
    do: lifecycle_records(s, Ipse.Session.RuntimeLifecycle.finish_wait(s.lifecycle, outcome))

  defp close_epoch(s, reason, cleanup),
    do: lifecycle_records(s, Ipse.Session.RuntimeLifecycle.close(s.lifecycle, reason, cleanup))

  @doc false
  def record_wait_subject(s, event) do
    if match?(%{active: true}, s.lifecycle) or Feeds.active?(s.feeds) do
      case Writer.append_with_source(s.journal_writer, event) do
        {:ok, source} -> source
        {:error, reason} -> journal_failed(s, reason)
      end
    else
      record(s, event)
      nil
    end
  end

  @doc false
  def question_wait(s, question, source, turn \\ :current)

  @doc false
  def question_wait(s, %{kind: :extension} = question, source, _turn),
    do:
      begin_wait(s, "extension_question", %{
        "turn_id" => question.parent["payload"]["turn_id"],
        "parent_invocation_id" => question.parent["invocation_id"],
        "operation_id" => question.action["operation_id"],
        "subject_source" => source
      })

  @doc false
  def question_wait(s, _question, source, turn),
    do:
      begin_wait(s, "native_question", %{
        "turn_id" => if(turn == :current, do: s.turn_id, else: turn),
        "request_id" => s.last_request_id,
        "subject_source" => source
      })

  defp next_draft_available?(nil), do: true
  defp next_draft_available?(%{status: :cancelled, notice: true, history: h}), do: length(h) < 15

  defp next_draft_available?(%{status: :consumed, accepted_message: true, history: h}),
    do: length(h) < 15

  defp next_draft_available?(_), do: false

  defp restore_draft_mode(%{draft: %{status: :pending} = draft} = saved, config),
    do:
      {%{saved | draft: Map.put(draft, :prior_config, config)},
       Ipse.Session.Draft.draft_config(config)}

  defp restore_draft_mode(saved, config), do: {saved, config}

  defp draft_mcp_ready?(s),
    do: Map.get(s.config, :mcp_servers, []) == [] or s.reference != nil

  defp draft_mcp_snapshot(s) do
    if Map.get(s.config, :mcp_servers, []) == [] or not s.mcp_discovered do
      {:ok, nil}
    else
      snapshot = Ipse.Session.DraftMCP.event(s.id, s.mcp_tools, Turn.draft_base_definitions(s))
      manifests = s.mcp_tools |> Ipse.MCP.manifests() |> Jason.encode!() |> Jason.decode!()

      if Ipse.Session.DraftMCP.valid?(snapshot, s.id, manifests, s.reference.catalog),
        do: {:ok, snapshot},
        else: {:error, :invalid_draft_mcp_catalog}
    end
  end

  defp draft_extension_quiet?(s) do
    not Feeds.active?(s.feeds) and not s.extension_text_cleanup_failed and
      Enum.all?(s.feeds.resources, fn {_, resource} ->
        not is_pid(resource.pid) or not Process.alive?(resource.pid)
      end) and
      not Enum.any?(
        Ipse.Extension.TextResources.entries(s.config),
        &(&1.identity["text_required"] == true)
      ) and
      Enum.all?(s.extension_text, fn {_, resource} ->
        Map.get(resource, :closed, false) or not is_pid(resource.pid) or
          not Process.alive?(resource.pid)
      end)
  end

  defp record_planning_epoch(s, mode) do
    reads = Map.get(s.config, :planning_mcp_reads, %{})

    if reads != %{} do
      epoch = Ipse.Usage.id()

      record(
        s,
        Ipse.Session.PlanningMCP.epoch(
          s.id,
          epoch,
          s.planning_mcp_epoch_id,
          "resume",
          mode,
          reads
        )
      )

      epoch
    end
  end

  defp planning_save_render(s, channel, %{"version" => 1} = decision) do
    with {:ok, scope, name} <- Ipse.Session.OperatorAssertion.selection(s.config),
         {:ok, render} <-
           Ipse.Session.OperatorAssertion.render(
             s.id,
             channel,
             "ordinary",
             decision["text"],
             scope
           ) do
      {:ok, scope, name, render, :operator}
    end
  end

  defp planning_save_render(s, channel, %{"version" => 2} = decision) do
    with true <- planning_decision_source_current?(s, decision),
         {:ok, scope, name} <- planning_proposal_selection(s),
         {:ok, render} <-
           Ipse.Session.PlanningDecisions.stage_render(s.id, channel, decision, scope) do
      {:ok, scope, name, render, :planning_assistant}
    else
      _ -> {:error, :planning_save_refused}
    end
  end

  defp planning_save_render(_, _, _), do: {:error, :planning_save_refused}

  defp planning_proposal_selection(s) do
    admission = s.config[:semantic_admission]

    with true <- Ipse.Extension.SemanticAdmission.valid?(admission, s.id),
         {:ok, scope} <- Ipse.Session.OperatorAssertion.scope(admission),
         true <- admission["instance"] == "knowledge",
         %{"kind" => "reviewed.bundle", "artifact_sha256" => digest} <-
           get_in(admission, ["policy", "settings", "activation"]),
         true <- digest == scope["artifact_sha256"],
         settings when is_map(settings) <- get_in(admission, ["policy", "settings"]),
         categories when is_list(categories) <- get_in(settings, ["sources", "categories"]),
         true <- "assistant_proposal" in categories,
         {:ok, mode} <- Ipse.Extension.Mode.capture(s.config),
         false <- mode["headless"],
         :ok <- Ipse.Extension.Mode.knowledge(mode, "collection.publish"),
         name = "ext__knowledge__capture",
         {:ok, entry, descriptor} <-
           Ipse.Extension.Catalog.lookup(s.config, "invoke.command", name),
         true <- entry.identity["artifact_sha256"] == digest,
         true <- planning_proposal_contract?(settings, descriptor) do
      {:ok, scope, name}
    else
      _ -> {:error, :planning_save_refused}
    end
  rescue
    _ -> {:error, :planning_save_refused}
  end

  defp planning_proposal_contract?(settings, descriptor) do
    settings["effects"]
    |> Enum.filter(fn mapping ->
      mapping["class"] == "collection.publish" and
        mapping["outer_sha256"] == Ipse.JSON.digest([descriptor]) and
        mapping["inner_op"] == "collection.managed"
    end)
    |> Enum.any?(fn mapping ->
      with {:ok, recipe} <- Ipse.Extension.SemanticConsent.recipe(settings, mapping),
           {:ok, _} <- Ipse.Extension.SemanticConsent.constraints(settings, mapping),
           true <- Ipse.Extension.ManagedRecipe.valid?(recipe),
           true <- recipe["constraints_sha256"] == mapping["constraints_sha256"],
           true <- recipe["kind"] == "proposal" and recipe["key_prefix"] == "pending.",
           rule when is_map(rule) <- Enum.find(recipe["rules"], &(&1["category"] == "ordinary")) do
        "assistant_proposal" in rule["origins"]
      else
        _ -> false
      end
    end)
  rescue
    _ -> false
  end

  defp planning_decision_render(s, channel, command) do
    case Ipse.Session.PlanningDecisions.parse(command) do
      {:ok, text} ->
        Ipse.Session.PlanningDecisions.render(s.id, channel, s.planning_entry, text)

      _ ->
        with {:ok, text} <- Ipse.Session.PlanningDecisions.parse_assistant(command),
             true <- post_reply_capture_inputs?(s),
             false <- Ipse.Extension.Host.enabled?(s.config, "transform.presentation"),
             [] <- Ipse.Extension.Subscriptions.declarations(s.config, "after_turn"),
             {:ok, request} <-
               Writer.source_query(
                 s.journal_writer,
                 {:planning_answer_request, s.planning_entry, s.turn_id, s.last_request_id, text}
               ),
             {:ok, %{"proof" => proof}} <-
               Writer.source_query(s.journal_writer, {:proof, request}),
             true <- proof["content_sha256"] === Ipse.JSON.sha256(s.final) do
          Ipse.Session.PlanningDecisions.render_assistant(
            s.id,
            channel,
            s.planning_entry,
            text,
            s.turn_id,
            s.last_request_id,
            proof
          )
        else
          _ -> {:error, :planning_decision_refused}
        end
    end
  end

  defp planning_decision_source_current?(_s, %{"version" => 1}), do: true

  defp planning_decision_source_current?(s, render) do
    post_reply_capture_inputs?(s) and s.turn_id === render["turn_id"] and
      s.last_request_id === render["request_id"] and
      not Ipse.Extension.Host.enabled?(s.config, "transform.presentation") and
      Ipse.Extension.Subscriptions.declarations(s.config, "after_turn") == [] and
      Writer.source_query(
        s.journal_writer,
        {:planning_answer_current, render["entry_sha256"], render["turn_id"],
         render["request_id"], render["source_proof"]}
      ) == {:ok, true}
  end

  defp planning_entry_quiet?(s) do
    planning_draft_settled?(s.draft) and is_nil(s.task) and is_nil(s.job_ref) and
      is_nil(s.approval) and
      is_nil(s.question) and is_nil(s.active_request) and is_nil(s.text_stream) and
      is_nil(s.extension_intent) and is_nil(s.event_intent) and
      is_nil(s.invocation.parent) and is_nil(s.invocation.action) and
      s.mcp_resources == %{} and s.delegation_resources == %{} and
      MapSet.size(s.delegation_workers) == 0 and s.delegation_queue == [] and
      is_nil(s.delegation_effect) and not s.task_cleanup_failed and
      not s.event_cleanup_failed and not s.extension_text_cleanup_failed and
      not match?(%{wait: wait} when not is_nil(wait), s.lifecycle) and draft_extension_quiet?(s)
  end

  defp planning_draft_settled?(nil), do: true
  defp planning_draft_settled?(%{status: :cancelled, notice: true}), do: true
  defp planning_draft_settled?(%{status: :consumed, accepted_message: true}), do: true
  defp planning_draft_settled?(_), do: false

  defp question_available(nil, _), do: :ok

  defp question_available(_, config),
    do: if(Questions.enabled?(config), do: :ok, else: {:error, :operator_input_unavailable})

  @doc false
  def checkpoint_event_question(s, question) do
    if s.event_committed != nil and s.event_intent == nil do
      record(
        s,
        Subscriptions.question_sources(
          s.turn_id,
          question.id,
          s.event_received.source,
          s.event_committed.source
        )
      )
    end
  end

  @doc false
  def owned_task(fun, failure_status \\ :error) do
    owner = self()
    {:ok, scope} = Ipse.Session.Resources.start(owner)
    :ok = Ipse.Session.Lock.track(scope, :scope)

    task =
      Task.Supervisor.async_nolink(Ipse.Tasks, fn ->
        Ipse.Session.Resources.await_ready(scope, owner)
        Ipse.Session.Resources.bind(scope)

        result =
          try do
            fun.()
          rescue
            _ ->
              {failure_status, "Worker failed. Inspect the workspace before retrying any action."}
          catch
            _, _ ->
              {failure_status,
               "Worker interrupted. Inspect the workspace before retrying any action."}
          end

        if Ipse.Session.Resources.finish(scope) != :ok,
          do: send(owner, {:owned_task_cleanup_failed, self()})

        result
      end)

    :ok = Ipse.Session.Lock.track(task.pid, :worker)
    :ok = Ipse.Session.Resources.attach(scope, task.pid)
    send(task.pid, {:cleanup_scope_ready, scope})
    task
  end

  defp acquire_lock(path, retries, lock_mode) do
    result =
      case lock_mode do
        :legacy -> Ipse.Session.Lock.acquire(path)
        :export_v1 -> Ipse.Session.Lock.acquire_export_candidate(path)
        :header_v1 -> Ipse.Session.Lock.acquire_header(path)
        :resume_v1 -> Ipse.Session.Lock.acquire_resume(path)
        :header_share_v2 -> Ipse.Session.Lock.acquire_share_header(path)
        :resume_share_v2 -> Ipse.Session.Lock.acquire_share_resume(path)
      end

    case result do
      {:ok, port} ->
        {:ok, port}

      {:error, _} when retries > 0 ->
        Process.sleep(20)
        acquire_lock(path, retries - 1, lock_mode)

      error ->
        error
    end
  end
end
