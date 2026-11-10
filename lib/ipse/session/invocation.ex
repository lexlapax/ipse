defmodule Ipse.Session.Invocation do
  @moduledoc "Extension invocation state and execution. Session retains caller and phase admission; all transitions run in that same process."
  alias Ipse.Session
  alias Ipse.Session.Invocation, as: CurrentInvocation
  alias Ipse.Workspace
  alias Ipse.Tools.Questions
  alias Ipse.Journal.Writer

  alias Ipse.Extension.{
    Host,
    Catalog,
    Invocation,
    Actions,
    ModelCall,
    EmbeddingCall,
    DecisionCall,
    Subscriptions,
    Feeds,
    ResultSource
  }

  alias Ipse.Session.{ProvidedSourceSet, Turn}

  @document_retirement_limit 32_768
  # Encoded record limits plus the JSONL newline: Invocation intent/result
  # validators, Actions.bounded?/1 and ManagedReads receipts.
  @intent_line_bytes 65_537
  @result_line_bytes 131_073
  @action_line_bytes 65_537
  # Fixed-shape exact_action_fence_attempt: 32-hex IDs, five SHA-256 digests and
  # an operation of at most 64 characters encode below 1,024 bytes.
  @fence_attempt_line_bytes 1_025

  defstruct parent: nil,
            request: nil,
            action: nil,
            step: 0,
            effect_sources: %{},
            results: [],
            managed_reads: [],
            worker_input: nil,
            pending_contributions: nil,
            semantic_binding: nil,
            document_context: nil,
            document_embedding_context: nil,
            document_producer: nil,
            provided_set: nil,
            interrupted: false

  @type t :: %__MODULE__{
          parent: map() | nil,
          request: map() | nil,
          action: map() | nil,
          step: non_neg_integer(),
          effect_sources: map(),
          results: [map()],
          managed_reads: [map()],
          interrupted: boolean()
        }

  def restore(question, effect_sources, managed_reads \\ %{})

  def restore(%{kind: :extension} = question, effect_sources, managed_reads) do
    %__MODULE__{
      parent: question.parent,
      action: %{intent: question.action},
      step: question.action["step"],
      effect_sources: effect_sources,
      results: question.results,
      managed_reads: Map.get(managed_reads, question.parent["invocation_id"], [])
    }
  end

  def restore(_, _, _), do: %__MODULE__{}

  def invoke_export(s, kind, name, arguments) do
    stage = "invoke." <> Atom.to_string(kind)

    with {:ok, entry, descriptor} <- Catalog.lookup(s.config, stage, name),
         true <- s.extension_invocations < Invocation.limit(),
         true <- Ipse.Extension.Registry.live?(entry.identity),
         :ok <- Catalog.validate_call(descriptor, arguments) do
      s = Session.enroll_feeds(s)
      owner = self()
      job_ref = make_ref()
      request = %{stage: stage, name: name, arguments: arguments}
      admission = s.config[:semantic_admission]

      protected =
        kind == :command and is_map(admission) and admission["pin"] != nil and
          admission["instance"] == entry.identity["instance"]

      task =
        Session.owned_task(fn ->
          if protected,
            do:
              {:extension_command_outer, request,
               Ipse.Extension.SemanticAdmission.outer(
                 s.config,
                 s.cwd,
                 s.id,
                 entry.identity,
                 descriptor
               )},
            else: Host.invoke_export(stage, name, arguments, owner, job_ref)
        end)

      phase =
        if protected,
          do: :semantic_outer,
          else: if(kind == :command, do: :extension_command, else: :extension_service)

      {:reply, :ok,
       %{
         s
         | phase: phase,
           task: task,
           job_ref: job_ref,
           invocation: %CurrentInvocation{request: request}
       }}
    else
      _ -> {:reply, {:error, :invalid_extension_call}, s}
    end
  end

  def command_outer(s, request, {:ok, binding}) do
    with true <- s.invocation.request === request,
         {:ok, entry, descriptor} <- Catalog.lookup(s.config, request.stage, request.name),
         true <-
           Ipse.Extension.SemanticAdmission.valid_outer_binding?(
             binding,
             entry.identity,
             descriptor,
             s.id
           ) do
      owner = self()
      ref = make_ref()

      task =
        Session.owned_task(fn ->
          Host.invoke_export(request.stage, request.name, request.arguments, owner, ref)
        end)

      {:noreply,
       %{
         s
         | task: task,
           job_ref: ref,
           phase: :extension_command,
           invocation: %{s.invocation | semantic_binding: binding}
       }}
    else
      _ -> command_outer(s, request, :refused)
    end
  end

  def command_outer(s, _, _),
    do:
      {:noreply,
       Turn.fail(
         s,
         "Saved semantic permission is unavailable or expired; no extension callback executed."
       )}

  def begin(s, ref, stage, name, arguments, phase) do
    origin =
      if phase == :tool do
        call = hd(s.calls)

        with {:ok, parsed} <- Jason.decode(get_in(call, ["function", "arguments"])),
             true <-
               stage == "invoke.tool" and get_in(call, ["function", "name"]) == name and
                 parsed == arguments do
          {:ok, call["id"], s.last_request_id, s.tool_decision}
        else
          _ -> :error
        end
      else
        if s.invocation.request == %{stage: stage, name: name, arguments: arguments},
          do:
            {:ok, nil, nil,
             if(s.invocation.semantic_binding, do: "saved_consent", else: "operator_request")},
          else: :error
      end

    with {:ok, parent_call, parent_request, approval} <- origin,
         true <- s.extension_invocations < Invocation.limit(),
         {:ok, entry, descriptor} <- Catalog.lookup(s.config, stage, name),
         true <- Ipse.Extension.Registry.live?(entry.identity),
         :ok <- Catalog.validate_call(descriptor, arguments),
         intent =
           Invocation.intent(
             entry.identity,
             descriptor,
             arguments,
             s.id,
             s.turn_id,
             parent_call,
             parent_request,
             approval,
             s.invocation.semantic_binding
           ),
         :ok <- Invocation.validate_intent(intent),
         {:ok, provided} <- provided_set(descriptor, intent),
         :ok <- journal_capacity(s, entry.identity),
         :ok <- record_begin(s, intent, provided) do
      entry = Map.merge(entry, %{host_config: s.config, host_cwd: s.cwd})
      {clock, entry} = output_clock(entry, descriptor["stage"], ref)
      s = Session.managed_event(s, intent)

      {:reply, {:ok, intent, entry},
       %{
         s
         | invocation: %CurrentInvocation{
             parent: intent,
             request: s.invocation.request,
             provided_set: if(provided, do: elem(provided, 1))
           },
           extension_output_clock: clock,
           extension_invocations: s.extension_invocations + 1,
           extension_mcp_context: nil
       }}
    else
      {:error, :journal_capacity_insufficient} = error -> {:reply, error, s}
      _ -> {:reply, {:error, :extension_admission_refused}, s}
    end
  end

  defp record_begin(s, intent, nil), do: Session.record(s, intent)

  # The set intent is durable before the worker receives its payload, so it
  # precedes every approval, dispatch intent and send for this invocation. Both
  # records share one reservation, so a full journal refuses the invocation
  # with neither written, and feeds and observation see the parent only after
  # its set intent.
  defp record_begin(s, intent, {event, _fence}), do: Session.record_adjacent(s, [intent, event])

  # A declared provided-set command is admitted only when the host can capture
  # its complete closed source set; the worker never supplies the set facts.
  defp provided_set(descriptor, intent) do
    if ProvidedSourceSet.contract?(descriptor) do
      case ProvidedSourceSet.begin(intent, System.system_time(:millisecond)) do
        {:ok, event, fence} -> {:ok, {event, fence}}
        _ -> :error
      end
    else
      {:ok, nil}
    end
  end

  # A document Collection invocation (one holding host.collection.store) is
  # admitted only while the journal can still hold every record it may write.
  # This probe runs in the Session owner before the invocation intent, so a
  # refusal leaves no intent and starts no callback or host call. The probe is
  # released at once: the invocation's records use ordinary appends, which a
  # held reservation would charge twice.
  defp journal_capacity(s, identity) do
    case journal_bound(s, identity) do
      nil ->
        :ok

      capacity ->
        case Writer.reserve(s.journal_writer, capacity) do
          {:ok, token} ->
            case Writer.release(s.journal_writer, token) do
              :ok -> :ok
              {:error, reason} -> Session.journal_failed(s, reason)
            end

          {:error, reason}
          when reason in [:journal_reservation_unavailable, :journal_limit_reached] ->
            {:error, :journal_capacity_insufficient}

          {:error, reason} ->
            Session.journal_failed(s, reason)
        end
    end
  end

  @doc """
  Worst-case journal capacity of one document Collection invocation, or nil for
  other invocations. Every count comes from a bound enforced on the record:

    * its invocation intent (at most 65,536 bytes) and result (131,072 bytes);
    * per admitted host call, an action intent and result (65,536 bytes each),
      plus one managed receipt: a read receipt (65,536 bytes) when the identity
      also reads Collections, otherwise a fixed-size withheld-output receipt;
    * one exact-action fence attempt when a fence is installed;
    * one draft-lineage marker per intent while a draft lineage is active.

  Each line adds its newline. The host-call count is `Actions.limit/1`.
  """
  def journal_bound(s, identity) do
    if "host.collection.store" in identity["capabilities"] do
      calls = Actions.limit(identity)
      receipt = managed_receipt_bytes(identity)

      {marker_events, marker_bytes} =
        case Map.get(s, :draft_lineages, []) do
          [] ->
            {0, 0}

          lineages ->
            marker =
              Ipse.Session.DraftLineage.extension_intent(
                s.id,
                s.turn_id,
                %{"type" => "extension_invocation_intent"},
                lineages
              )

            {calls + 1, (calls + 1) * (byte_size(Jason.encode!(marker)) + 1)}
        end

      {fence_events, fence_bytes} =
        if match?(%{fence: fence} when is_map(fence), exact_action_state(s)),
          do: {1, @fence_attempt_line_bytes},
          else: {0, 0}

      %{
        events: 2 + calls * 3 + marker_events + fence_events,
        bytes:
          @intent_line_bytes + @result_line_bytes + calls * (2 * @action_line_bytes + receipt) +
            marker_bytes + fence_bytes
      }
    end
  end

  defp managed_receipt_bytes(identity) do
    if "host.collection.read" in identity["capabilities"] do
      @action_line_bytes
    else
      id = String.duplicate("0", 32)

      %{"parent_invocation_id" => id, "operation_id" => id}
      |> Ipse.Session.ManagedToolUse.action_withheld()
      |> Jason.encode!()
      |> byte_size()
      |> Kernel.+(1)
    end
  end

  # Saved output would outlive a provided-source fence, so a fenced invocation
  # opens, extends and seals none; its result must fit inline.
  def open_output(s, offer) do
    with false <- ProvidedSourceSet.active?(s),
         false <-
           get_in(s.invocation.parent || %{}, ["semantic_binding", "class"]) ===
             "nomination.select",
         true <- output_timely?(s) and s.extension_output_clock != nil,
         true <- is_nil(s.invocation.action) and not s.invocation.interrupted,
         true <- Ipse.Extension.Registry.live?(s.invocation.parent["identity"]),
         {:ok, event, source, index} <-
           ResultSource.index_open(
             s.extension_result_sources,
             s.invocation.parent,
             offer,
             output_elapsed(s)
           ),
         {:ok, final} <-
           Invocation.build_saved_result(
             s.invocation.parent,
             ResultSource.descriptor(source),
             s.invocation.results,
             120_000
           ),
         {:ok, capacity} <- ResultSource.reservation_size(source, final),
         {:ok, capacity} <- Ipse.Session.WorkerInput.output_capacity(s, source, capacity),
         true <- ResultSource.fits_reservation?(s.extension_result_sources, capacity),
         {:ok, limits} <- Ipse.Journal.normalize_limits(s.config[:journal]),
         true <- capacity.max_record_bytes <= limits["max_record_bytes"],
         {:ok, token} <-
           Writer.reserve(s.journal_writer, Map.take(capacity, [:bytes, :events])) do
      if output_timely?(s) do
        case Writer.append_reserved(s.journal_writer, token, event) do
          :ok ->
            next = %{
              s
              | extension_result_sources: index,
                extension_output: %{token: token, id: event["output_id"], last_reply: nil}
            }

            reply = if output_timely?(next), do: {:ok, event}, else: {:error, :output_expired}
            {:reply, reply, next}

          {:error, reason} ->
            Session.journal_failed(s, reason)
        end
      else
        release_output_token(s, token)
        {:reply, {:error, :output_expired}, s}
      end
    else
      _ -> {:reply, {:error, :output_admission_refused}, s}
    end
  end

  def push_output(s, output_id, reply, active) do
    with false <- ProvidedSourceSet.active?(s),
         true <- output_timely?(s),
         true <- Ipse.Extension.Registry.live?(s.invocation.parent["identity"]) do
      {:ok, current} = ResultSource.source(s.extension_result_sources, output_id)

      if ResultSource.acknowledged?(current, reply) do
        {:reply, :ok, s}
      else
        case ResultSource.index_push(s.extension_result_sources, output_id, reply) do
          {:ok, event, _source, index} ->
            record_output(s, event)

            {:reply, :ok,
             %{
               s
               | extension_result_sources: index,
                 extension_output: %{active | last_reply: reply}
             }}

          _ ->
            {:reply, {:error, :output_fragment_refused}, s}
        end
      end
    else
      _ -> {:reply, {:error, :output_fragment_refused}, s}
    end
  end

  def seal_output(s, proof, active) do
    with false <- ProvidedSourceSet.active?(s),
         true <- output_timely?(s),
         true <- Ipse.Extension.Registry.live?(s.invocation.parent["identity"]),
         {:ok, event, _source, index} <-
           ResultSource.index_accept_verified(s.extension_result_sources, active.id, proof) do
      record_output(s, event)
      {:reply, :ok, %{s | extension_result_sources: index}}
    else
      _ -> {:reply, {:error, :output_seal_refused}, s}
    end
  end

  def read_model_output(s, request) do
    if get_in(hd(s.calls), ["function", "name"]) == "saved_result_read",
      do: {:reply, readable_output(s, request, true), s},
      else: {:reply, {:error, :saved_result_read_refused}, s}
  end

  def tool_context(s, request) do
    with parent when is_map(parent) <- s.invocation.parent,
         true <- Ipse.Extension.Registry.live?(parent["identity"]),
         {:ok, _} <-
           Actions.proposal(
             %{"api_version" => 1, "kind" => "host_call", "request" => request},
             parent["identity"]
           ),
         true <- Ipse.Extension.Actions.tool?(request) do
      {:reply, {:ok, s.context_snapshot}, %{s | extension_tool_context: nil}}
    else
      _ -> {:reply, {:error, :extension_tool_context_refused}, s}
    end
  end

  def commit_tool_context(s, ref, request, old_hash, snapshot, drift) do
    with true <- old_hash == Ipse.JSON.digest([s.context_snapshot]),
         true <- Workspace.valid?(snapshot),
         true <-
           Map.take(snapshot, ~w(version cwd boundary)) ==
             Map.take(s.context_snapshot, ~w(version cwd boundary)),
         true <-
           Enum.take(snapshot["sources"], length(s.context_snapshot["sources"])) ==
             s.context_snapshot["sources"],
         :ok <- Ipse.Extension.ToolAction.validate(request) do
      if snapshot == s.context_snapshot do
        gate = %{
          request: Ipse.JSON.digest([request]),
          context: old_hash,
          job: ref,
          identity: Ipse.JSON.digest([s.invocation.parent["identity"]])
        }

        {:reply, :ok, %{s | extension_tool_context: gate, context_drift: drift}}
      else
        s =
          Session.persist_context(
            %{s | context_drift: drift, extension_tool_context: nil},
            snapshot
          )

        Session.notify(
          s,
          {:context_refreshed,
           Ipse.Session.Context.manifest(
             s.context_snapshot,
             s.context_drift,
             s.skill_drift,
             s.skills
           )}
        )

        {:reply, {:error, :review_new_workspace_instructions}, s}
      end
    else
      _ -> {:reply, {:error, :extension_tool_context_refused}, s}
    end
  end

  def prepare_mcp(s, ref, request) do
    with {:ok, limits} <- Ipse.Journal.normalize_limits(s.config[:journal]),
         true <- Ipse.Extension.EffectResult.source_record_limit() <= limits["max_record_bytes"],
         {:ok, server, tool_id} <- extension_mcp_target(s, request),
         {:ok, next, resource} <-
           Ipse.Session.ManagedToolUse.begin_discovery(s, request, server, tool_id) do
      {:reply, {:ok, server, tool_id, s.cwd, Map.put(resource, :job_ref, ref)}, next}
    else
      _ -> {:reply, {:error, :extension_mcp_refused}, s}
    end
  end

  def bind_mcp(s, ref, request, descriptor, binding) do
    with {:ok, server, tool_id} <- extension_mcp_target(s, request),
         true <- descriptor.server == server and descriptor.tool_id == tool_id,
         true <- binding == Ipse.Extension.MCPCall.binding(descriptor, request["binding"]),
         true <-
           Ipse.Extension.MCPCall.valid_binding?(
             binding,
             request,
             s.invocation.parent["identity"]
           ),
         :ok <- Ipse.MCP.validate_call(descriptor, request["arguments"]),
         {:ok, next} <- Ipse.Session.ManagedToolUse.finish_discovery(s, binding) do
      gate = %{
        request: Ipse.JSON.digest([request]),
        identity: Ipse.JSON.digest([s.invocation.parent["identity"]]),
        job: ref,
        descriptor: descriptor,
        binding: binding
      }

      {:reply, :ok, %{next | extension_mcp_context: gate}}
    else
      _ -> {:reply, {:error, :extension_mcp_refused}, %{s | extension_mcp_context: nil}}
    end
  end

  def prepare_document(s, ref, request) do
    identity = s.invocation.parent["identity"]

    with :ok <- Ipse.Extension.CollectionStore.validate(request),
         true <- output_timely?(s) and not s.invocation.interrupted,
         true <- Ipse.Extension.Registry.live?(identity),
         true <- Actions.allowed?(identity, request, s.invocation.results),
         true <- "host.collection.store" in identity["capabilities"],
         true <- Ipse.Extension.CollectionStore.operator_binding?(identity["collection_binding"]) do
      {:reply, {:ok, s.config[:home], s.cwd, identity, s.id},
       %{s | invocation: %{s.invocation | document_context: %{job: ref}}}}
    else
      _ ->
        {:reply, {:error, :document_store_refused},
         %{s | invocation: %{s.invocation | document_context: nil}}}
    end
  end

  def bind_document(s, ref, request, binding) do
    with %{job: ^ref} <- s.invocation.document_context,
         true <- Ipse.Extension.CollectionStore.Restore.allowed?(request, s.invocation.parent),
         true <- output_timely?(s) and not s.invocation.interrupted,
         true <-
           Ipse.Extension.CollectionStore.valid_binding?(
             binding,
             request,
             s.invocation.parent["identity"]
           ),
         true <- binding["session_id"] == s.id do
      gate = %{
        job: ref,
        request: Ipse.JSON.digest([request]),
        identity: Ipse.JSON.digest([s.invocation.parent["identity"]]),
        binding: binding
      }

      {:reply, :ok, %{s | invocation: %{s.invocation | document_context: gate}}}
    else
      _ ->
        {:reply, {:error, :document_store_refused},
         %{s | invocation: %{s.invocation | document_context: nil}}}
    end
  end

  def document_current(s, intent) do
    reply =
      with %{intent: ^intent} <- s.invocation.action,
           true <-
             Ipse.Extension.CollectionStore.Restore.allowed?(
               intent["request"],
               s.invocation.parent
             ),
           true <- output_timely?(s) and not s.invocation.interrupted,
           true <- Ipse.Extension.Registry.live?(s.invocation.parent["identity"]),
           true <-
             Ipse.Extension.CollectionStore.valid_binding?(
               intent["effect_binding"],
               intent["request"],
               s.invocation.parent["identity"]
             ),
           true <- intent["effect_binding"]["session_id"] == s.id,
           true <- intent["approval"] in ~w(not_required approved session_allow) do
        :ok
      else
        _ -> {:error, :document_store_refused}
      end

    {:reply, reply, s}
  end

  # Only a known, journaled cleanup completed by this live Session process can
  # authorize another step of the same partial retirement. This registry is not
  # restored on resume: an earlier owner or unknown outcome needs recovery.
  def document_retirement(s, intent) do
    with {:reply, :ok, ^s} <- document_current(s, intent) do
      request = intent["request"]["request"]
      tag = request["progress"]

      if is_map(tag) and tag["action"] === "retire" do
        key = retirement_key(intent, tag["head_id"])

        if map_size(s.document_retirements) < @document_retirement_limit or
             Map.has_key?(s.document_retirements, key) do
          {:reply, {:ok, Map.get(s.document_retirements, key)}, s}
        else
          {:reply, {:error, :document_store_refused}, s}
        end
      else
        {:reply, {:ok, nil}, s}
      end
    else
      _ -> {:reply, {:error, :document_store_refused}, s}
    end
  rescue
    _ -> {:reply, {:error, :document_store_refused}, s}
  end

  # The live registry value is read again when the Session opens the
  # controlled transfer; the digest narrows that transfer, never authorizes it.
  def document_retirement_binding?(s, caller, intent, expected) do
    with true <- s.task != nil and s.job_ref != nil,
         true <-
           caller == s.task.pid or Ipse.Session.Resources.authorized_effect?(s.task.pid, caller),
         %{"op" => "collection.store", "request" => %{"progress" => %{"action" => "retire"}}} <-
           intent["request"],
         {:reply, {:ok, authority}, ^s} <- document_retirement(s, intent),
         true <- Ipse.JSON.digest([s.invocation.parent, intent, authority]) === expected do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp retirement_key(event, head_id) do
    binding = event["effect_binding"]
    {binding["namespace"], binding["project"]["project_id"], event["identity_sha256"], head_id}
  end

  defp record_document_retirement(s, event) do
    request = get_in(event, ["request", "request"])
    tag = if is_map(request), do: request["progress"]
    progress = get_in(event, ["outcome", "value", "progress"])

    if get_in(event, ["request", "op"]) === "collection.store" and is_map(tag) and
         tag["action"] === "retire" and get_in(event, ["outcome", "status"]) === "ok" and
         is_map(progress) do
      key = retirement_key(event, tag["head_id"])

      retirements =
        case progress["status"] do
          "retiring" ->
            Map.put(s.document_retirements, key, %{
              "operation_id" => event["operation_id"],
              "invocation_id" => event["parent_invocation_id"],
              "revision" => progress["revision"],
              "epoch" => progress["retirement_epoch"]
            })

          "retired" ->
            Map.delete(s.document_retirements, key)

          _ ->
            s.document_retirements
        end

      %{s | document_retirements: retirements}
    else
      s
    end
  end

  def prepare_document_embedding(s, ref, request) do
    identity = s.invocation.parent["identity"]
    required = Ipse.Extension.CollectionStore.embedding_source_required?(identity)
    guarded = Map.has_key?(request, "source_guard")

    with :ok <- EmbeddingCall.validate(request),
         true <- output_timely?(s) and not s.invocation.interrupted,
         true <- Ipse.Extension.Registry.live?(identity),
         true <- Actions.allowed?(identity, request, s.invocation.results),
         true <- required === guarded do
      if required do
        {:reply, {:ok, s.config[:home], s.cwd, identity, s.id},
         %{s | invocation: %{s.invocation | document_embedding_context: %{job: ref}}}}
      else
        {:reply, :ordinary, %{s | invocation: %{s.invocation | document_embedding_context: nil}}}
      end
    else
      _ ->
        {:reply, {:error, :document_source_use_refused}, Ipse.Session.DocumentEmbedding.poison(s)}
    end
  end

  def bind_document_embedding(s, ref, request, binding) do
    with %{job: ^ref} <- s.invocation.document_embedding_context,
         true <- output_timely?(s) and not s.invocation.interrupted,
         true <- Ipse.Extension.Registry.live?(s.invocation.parent["identity"]),
         true <-
           Ipse.Extension.CollectionStore.valid_source_binding?(
             binding,
             request,
             s.invocation.parent["identity"]
           ),
         true <- binding["session_id"] === s.id do
      gate = %{
        job: ref,
        request: Ipse.JSON.digest([request]),
        binding: binding,
        identity: Ipse.JSON.digest([s.invocation.parent["identity"]])
      }

      {:reply, :ok, %{s | invocation: %{s.invocation | document_embedding_context: gate}}}
    else
      _ ->
        {:reply, {:error, :document_source_use_refused}, Ipse.Session.DocumentEmbedding.poison(s)}
    end
  end

  def begin_action(
        %{invocation: %{parent: %{"semantic_binding" => %{"class" => "nomination.select"}}}} = s,
        _request,
        _from,
        _phase
      ),
      do: {:reply, {:error, :nomination_effect_refused}, s}

  def begin_action(s, request, from, phase) do
    mutation = Ipse.Extension.Actions.mutating?(request)
    {:ok, captured_mode} = Ipse.Extension.Mode.capture(s.config)

    read_outer =
      get_in(s.invocation.parent || %{}, ["semantic_binding", "class"]) == "collection.read"

    mode =
      if not Actions.allowed_under_outer?(s.invocation.parent || %{}, request),
        do: :deny,
        else: Ipse.Extension.Mode.ordinary(captured_mode, mutation)

    protected =
      (Ipse.Extension.CollectionCall.operation?(request) or
         Ipse.Extension.ManagedCollectionCall.operation?(request)) and mutation and not read_outer and
        s.invocation.parent["version"] === 3 and
        get_in(s.invocation.parent, ["semantic_binding", "class"]) == "collection.publish" and
        Ipse.Extension.Mode.knowledge(captured_mode, "collection.publish") == :ok

    approval =
      if protected,
        do: "saved_consent",
        else:
          if(mutation,
            do: if(mode == :deny, do: "denied", else: "session_allow"),
            else: "not_required"
          )

    with parent when is_map(parent) <- s.invocation.parent,
         true <- output_timely?(s),
         true <- not s.invocation.interrupted,
         true <- Ipse.Extension.Registry.live?(parent["identity"]),
         true <- provided_action?(s, request),
         true <- Actions.allowed?(parent["identity"], request, s.invocation.results),
         true <-
           Actions.readable?(request, s.invocation.effect_sources, s.invocation.results),
         true <-
           not Ipse.Extension.Actions.question?(request) or Questions.enabled?(s.config),
         {:ok, context_hash} <- extension_action_context(s, request),
         {:ok, service} <- extension_service_context(s, request),
         {:ok, effect_binding} <- extension_effect_binding(s, request),
         true <-
           not EmbeddingCall.operation?(request) or
             (EmbeddingCall.valid_identity?(parent["identity"], request, effect_binding) and
                (not Map.has_key?(request, "source_guard") or
                   Ipse.Session.DocumentEmbedding.allowed?(s.invocation, request, effect_binding))),
         :ok <- extension_model_configuration(s.config, request),
         {:ok, intent} <-
           Actions.intent(
             parent,
             request,
             s.invocation.step + 1,
             approval,
             s.cwd,
             context_hash,
             service,
             effect_binding
           ),
         :ok <- extension_effect_record_capacity(s, intent),
         {:ok, s} <- exact_action_attempt(s, parent, intent) do
      cond do
        mutation and request["op"] in ["collection.call", "collection.managed"] and
            not Ipse.Session.ManagedToolUse.publication_prerequisites?(s, request, effect_binding) ->
          {:reply, {:error, :managed_effect_unavailable}, s}

        mutation and request["op"] == "collection.managed" and
            not Ipse.Extension.ManagedCollectionCall.new_capture?(request) ->
          Session.notify(
            s,
            {:error, Ipse.CLI.Errors.format(:collection_deadline_fence_unavailable)}
          )

          {:reply, {:error, :collection_deadline_fence_unavailable}, s}

        mutation and request["op"] == "collection.store" and
            Ipse.Session.ManagedToolUse.managed_invocation?(s) ->
          {:reply, {:error, :managed_effect_unavailable}, s}

        Ipse.Session.ManagedToolUse.managed_invocation?(s) and
            request["op"] in ["state.put", "state.delete", "service.call"] ->
          {:reply, {:error, :managed_effect_unavailable}, s}

        Ipse.Session.ManagedToolUse.managed_invocation?(s) and
            Ipse.Extension.Actions.question?(request) ->
          Session.notify(
            s,
            {:error,
             "Managed approval or question arguments cannot be displayed under current source ownership; no action was started."}
          )

          {:reply, {:error, :managed_argument_display_unavailable}, s}

        Ipse.Extension.Actions.question?(request) ->
          Session.record(s, intent)

          reply =
            if output_timely?(s),
              do: {:question, intent},
              else: {:error, :extension_action_expired}

          {:reply, reply,
           %{
             s
             | invocation: %{
                 s.invocation
                 | action: %{intent: intent},
                   step: s.invocation.step + 1
               }
           }}

        mutation and mode == :ask and not protected ->
          approval_ref = make_ref()

          s =
            Session.begin_wait(s, "extension_action", %{
              "turn_id" => parent["payload"]["turn_id"],
              "parent_invocation_id" => parent["invocation_id"],
              "operation_id" => intent["operation_id"]
            })

          proposed = %{
            "extension" => parent["identity"]["instance"],
            "artifact_sha256" => parent["identity"]["artifact_sha256"],
            "namespace" => intent["namespace"],
            "request" => request
          }

          proposed =
            if Ipse.Extension.Actions.inference?(request) do
              {:ok, runtime, execution} = prepare_inference(s.config, request)
              {:ok, destination} = inference_destination(runtime, request)
              proposed |> Map.put("execution", execution) |> Map.put("destination", destination)
            else
              proposed
            end

          proposed =
            if effect_binding,
              do: Map.put(proposed, "effect_binding", effect_binding),
              else: proposed

          if Ipse.Session.ManagedToolUse.managed_invocation?(s) do
            Ipse.Session.ManagedApproval.start_extension(s, intent, proposed, phase)
          else
            Session.notify(s, {:approval, approval_ref, "extension:" <> request["op"], proposed})

            {:noreply,
             %{
               s
               | phase: :extension_approval,
                 approval: {:extension, approval_ref, from, phase},
                 extension_tool_context: nil,
                 invocation: %{s.invocation | action: %{intent: intent}}
             }}
          end

        true ->
          s =
            if Ipse.Extension.SourceRead.operation?(request) or
                 Ipse.Extension.CollectionCall.operation?(request) or
                 Ipse.Extension.ManagedCollectionCall.operation?(request),
               do: Session.ensure_source_window(s),
               else: s

          {s, source} =
            cond do
              (Ipse.Extension.Actions.history?(request) or
                 Ipse.Extension.Actions.usage?(request)) and request["snapshot"] == nil ->
                {s, Session.record_source(s, intent)}

              true ->
                {Session.record_extension_action(s, intent), nil}
            end

          s = Session.managed_event(s, intent)

          context = extension_execution_context(s, intent, source)

          reply =
            cond do
              not output_timely?(s) -> {:error, :extension_action_expired}
              approval == "denied" -> {:denied, intent}
              true -> {:ok, intent, context}
            end

          if Ipse.Extension.Actions.tool?(request) and match?({:ok, _, _}, reply),
            do:
              Session.notify(
                s,
                {:tool, "extension:tool.call",
                 if(Ipse.Session.ManagedToolUse.managed_invocation?(s), do: %{}, else: request)}
              )

          {:reply, reply,
           %{
             s
             | invocation: %{
                 s.invocation
                 | action: %{
                     intent: intent,
                     usage_read: context[:usage_read],
                     child_usage: context[:child_usage],
                     source_read: context[:source_read]
                   },
                   step: s.invocation.step + 1
               },
               extension_tool_context: nil
           }}
      end
    else
      {:exact_action_refused, next} -> {:reply, {:error, :exact_action_fence_refused}, next}
      _ -> {:reply, {:error, :extension_action_refused}, s}
    end
  end

  # A fenced invocation can obtain no source beyond its captured arguments: its
  # only host call is model.complete, and only over a registered inference
  # route. This refuses before the ordinary approval prompt.
  defp provided_action?(s, request) do
    not ProvidedSourceSet.active?(s) or
      (ModelCall.operation?(request) and Session.managed_empty?(s) and
         provided_route?(s.config, request))
  end

  defp provided_inference(s, message, request) do
    cond do
      not ProvidedSourceSet.active?(s) ->
        {:ok, s}

      message == :extension_model_begin and provided_action?(s, request) ->
        ProvidedSourceSet.check(s)

      true ->
        :error
    end
  end

  defp provided_route?(config, request) do
    with {:ok, runtime, _} <- prepare_inference(config, request),
         {:ok, %{route: route}} when is_map(route) <-
           Ipse.InferenceDispatch.selection(config, runtime, request["op"], request["profile"]) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp exact_action_attempt(s, parent, intent) do
    fence = exact_action_state(s)

    if is_map(fence) and is_map(fence.fence) and
         get_in(intent, ["request", "op"]) === fence.fence["operation"] and
         get_in(parent, ["payload", "turn_id"]) !== s.turn_id do
      {:exact_action_refused, s}
    else
      exact_action_attempt_record(s, fence, parent, intent)
    end
  end

  defp exact_action_attempt_record(s, fence, parent, intent) do
    case Ipse.Session.ExactActionFence.attempt(fence, parent, intent, s.id) do
      :unrestricted ->
        {:ok, s}

      {:attempt, event} ->
        Session.record(s, event)
        next = Map.put(s, :exact_action_fence, %{fence | attempt: event})
        if event["matched"], do: {:ok, next}, else: {:exact_action_refused, next}

      _ ->
        {:exact_action_refused, s}
    end
  end

  defp exact_action_permitted?(s, intent) do
    fence = exact_action_state(s)
    parent = s.invocation.parent

    case fence do
      %{fence: nil} ->
        Ipse.Session.ExactActionFence.permitted?(fence, parent, intent)

      %{fence: restriction} when is_map(restriction) ->
        Ipse.Session.ExactActionFence.permitted?(fence, parent, intent) and
          (get_in(intent, ["request", "op"]) !== restriction["operation"] or
             get_in(parent, ["payload", "turn_id"]) === s.turn_id)

      _ ->
        false
    end
  end

  defp exact_action_state(s) do
    case Map.fetch(s, :exact_action_fence) do
      {:ok, fence} ->
        fence

      :error ->
        if get_in(s, [:config, :source_layout]) == Ipse.Session.SourceWindow.fenced_layout(),
          do: nil,
          else: %{fence: nil, attempt: nil}
    end
  end

  def bind_effect_source(s, intent, kind, data) do
    with true <- Ipse.Extension.Registry.live?(s.invocation.parent["identity"]),
         true <- not Map.has_key?(s.invocation.effect_sources, intent["operation_id"]),
         {:ok, source} <- Ipse.Extension.EffectResult.source(intent, kind, data) do
      Session.record(s, source)

      {:reply, {:ok, source},
       %{
         s
         | invocation: %{
             s.invocation
             | effect_sources:
                 Map.put(s.invocation.effect_sources, intent["operation_id"], source)
           }
       }}
    else
      _ -> {:reply, {:error, :extension_effect_source_refused}, s}
    end
  end

  def begin_inference(s, message, intent) do
    with true <- inference_begin?(message, intent["request"]),
         true <- exact_action_permitted?(s, intent),
         true <- output_timely?(s),
         true <- intent["approval"] in ~w(approved session_allow),
         true <- Ipse.Extension.Registry.live?(s.invocation.parent["identity"]),
         true <- s.steps < Map.get(s.config, :max_steps, 30),
         true <- Ipse.Usage.capacity?(s.accounting),
         {:ok, config, execution} <- prepare_inference(s.config, intent["request"]),
         {:ok, s} <- provided_inference(s, message, intent["request"]),
         true <-
           not EmbeddingCall.operation?(intent["request"]) or
             EmbeddingCall.valid_identity?(
               s.invocation.parent["identity"],
               intent["request"],
               intent["effect_binding"]
             ),
         true <-
           not Map.has_key?(intent["request"], "source_guard") or
             (Session.managed_empty?(s) and
                Ipse.Session.DocumentEmbedding.allowed?(
                  s.invocation,
                  intent["request"],
                  intent["effect_binding"]
                ) and
                match?(
                  {:ok, %{route: _}},
                  Ipse.InferenceDispatch.selection(
                    s.config,
                    config,
                    intent["request"]["op"],
                    intent["request"]["profile"]
                  )
                )),
         true <-
           Ipse.InferenceDispatch.selection(
             s.config,
             config,
             intent["request"]["op"],
             intent["request"]["profile"]
           ) != {:ok, :unregistered} or Session.managed_empty?(s),
         true <-
           not (EmbeddingCall.operation?(intent["request"]) or
                  DecisionCall.operation?(intent["request"])) or
             (intent["effect_binding"]["execution"] === execution and
                inference_destination(config, intent["request"]) ==
                  {:ok, intent["effect_binding"]["destination"]}),
         :ok <- extension_effect_record_capacity(s, intent) do
      admission =
        Ipse.Usage.admission(s.id, config, "extension", s.turn_id)
        |> Map.put("request_id", intent["operation_id"])

      source =
        case message do
          :extension_embedding_begin -> EmbeddingCall.source(intent, admission, execution)
          :extension_decision_begin -> DecisionCall.source(intent, admission, execution)
          :extension_model_begin -> ModelCall.source(intent, admission, execution)
        end

      s = Session.account(s, source)
      s = Session.account(s, admission)
      s = %{s | managed_result_seal: nil}
      s = Session.managed_event(s, admission)
      active = %{admission: admission, started: System.monotonic_time(:millisecond)}

      s = %{s | extension_model: active, steps: s.steps + 1}

      if output_timely?(s) do
        phase = intent["request"]["op"]

        reply =
          case Ipse.InferenceDispatch.selection(
                 s.config,
                 config,
                 phase,
                 intent["request"]["profile"]
               ) do
            {:ok, :unregistered} ->
              {:ok, config, admission}

            _ ->
              {:ok, ^config, input, tools, ^admission} = dispatch_view(s, phase)

              dispatch =
                Session.InferenceDispatch.prepare(s, config, input, tools, phase, admission)

              {:ok, config, admission, dispatch}
          end

        {:reply, reply, s}
      else
        code =
          case message do
            :extension_embedding_begin -> "embedding_request_failed"
            :extension_decision_begin -> "decision_request_failed"
            :extension_model_begin -> "model_request_failed"
          end

        {:reply, {:failed, %{"code" => code}}, Session.measure_request(s, :expired)}
      end
    else
      _ -> {:reply, {:error, :extension_model_refused}, s}
    end
  end

  @doc false
  def dispatch_view(
        %{invocation: %{action: %{intent: intent}}, extension_model: %{admission: admission}} = s,
        phase
      ) do
    request = intent["request"]

    with true <- request["op"] == phase,
         true <- intent["approval"] in ~w(approved session_allow),
         true <- output_timely?(s),
         true <- Ipse.Extension.Registry.live?(s.invocation.parent["identity"]),
         {:ok, runtime, execution} <- prepare_inference(s.config, request),
         true <-
           not EmbeddingCall.operation?(request) or
             EmbeddingCall.valid_identity?(
               s.invocation.parent["identity"],
               request,
               intent["effect_binding"]
             ),
         true <-
           not (EmbeddingCall.operation?(request) or DecisionCall.operation?(request)) or
             (intent["effect_binding"]["execution"] === execution and
                inference_destination(runtime, request) ==
                  {:ok, intent["effect_binding"]["destination"]}) do
      input =
        if phase == "model.complete",
          do: Ipse.Session.Context.helper_messages(request),
          else: request

      {:ok, runtime, input, [], admission}
    else
      _ -> {:error, :inference_dispatch_refused}
    end
  end

  def dispatch_view(_, _), do: {:error, :inference_dispatch_refused}

  def observe_inference(s, message, id, usage, admission) do
    entry = s.accounting.requests[id]

    if inference_usage?(message, admission) and
         Ipse.Usage.valid_usage?(usage, Ipse.Usage.operation(admission)) and
         (entry.sequence < 64 or entry.observation == usage or message == :extension_model_usage) do
      s =
        if entry.sequence < 64 and entry.observation != usage do
          event = %{
            "type" => "request_usage_observed",
            "version" => admission["version"],
            "request_id" => id,
            "attempt_id" => admission["attempt_id"],
            "sequence" => entry.sequence + 1,
            "usage" => usage
          }

          event =
            if Ipse.Usage.operation(admission) in ["embedding", "decision"],
              do: Map.put(event, "operation", Ipse.Usage.operation(admission)),
              else: event

          Session.account(s, event)
        else
          s
        end

      {:reply, :ok, s}
    else
      {:reply, {:error, :invalid_extension_usage}, s}
    end
  end

  def finish_model(s, intent, result, capture, reason, admission) do
    {result, s} = Session.InferenceDispatch.consume_result(s, intent["request"]["op"], result)
    assistant = if is_map(capture), do: capture.value

    {s, retained} =
      case ModelCall.response(admission, assistant) do
        {:ok, event} -> {Session.account(s, event), true}
        _ -> {s, false}
      end

    s = Session.measure_request(s, result)
    completion = s.accounting.requests[admission["request_id"]].completion

    outcome =
      cond do
        reason in ~w(model_cancelled model_timeout) ->
          {:failed, %{"code" => reason}}

        match?({:ok, _, _}, result) and not retained ->
          {:failed, %{"code" => "model_response"}}

        true ->
          ModelCall.value_from_completion(intent["request"], admission, completion, assistant)
      end

    {:reply, outcome, s}
  end

  def finish_embedding(s, intent, result, capture, reason, admission, started),
    do:
      finish_bounded_inference(s, intent, result, capture, reason, admission, started, :embedding)

  def finish_decision(s, intent, result, capture, reason, admission, started),
    do:
      finish_bounded_inference(s, intent, result, capture, reason, admission, started, :decision)

  defp finish_bounded_inference(s, intent, result, capture, reason, admission, started, kind) do
    {result, s} = Session.InferenceDispatch.consume_result(s, intent["request"]["op"], result)
    adapter = if kind == :embedding, do: EmbeddingCall, else: DecisionCall
    operation = Atom.to_string(kind)

    if adapter.operation?(intent["request"]) and
         Ipse.Usage.operation(admission) == operation do
      valid_capture = bounded_capture?(capture, intent, kind)
      s = if valid_capture, do: observe_bound_capture(s, admission, capture.usage), else: s
      observed = s.accounting.requests[admission["request_id"]].observation

      completion =
        Ipse.Usage.completion(
          admission,
          result,
          max(System.monotonic_time(:millisecond) - started, 0),
          observed
        )

      source =
        with true <- valid_capture,
             {:ok, payload, raw} <- result,
             true <-
               payload === capture.value and
                 Ipse.Usage.observation(admission, raw, 1)["usage"] === capture.usage,
             {:ok, source} <- adapter.response(intent, admission, completion, payload),
             do: source

      {s, source} =
        if is_map(source) do
          s = Session.account(s, source)

          {%{
             s
             | invocation: %{
                 s.invocation
                 | effect_sources:
                     Map.put(s.invocation.effect_sources, intent["operation_id"], source)
               }
           }, source}
        else
          {s, nil}
        end

      s = Session.account(s, completion)
      s = %{s | extension_model: nil}

      outcome =
        cond do
          reason in [operation <> "_cancelled", operation <> "_timeout"] ->
            {:failed, %{"code" => reason}}

          kind == :decision and
              (result == {:error, :invalid_decision_response} or
                 match?({:error, {:invalid_decision_response, _}}, result)) ->
            {:failed, %{"code" => "decision_response"}}

          match?({:ok, _, _}, result) and is_nil(source) ->
            {:failed, %{"code" => operation <> "_response"}}

          true ->
            adapter.value_from_completion(intent, admission, completion, source)
        end

      {:reply, outcome, s}
    else
      {:reply, {:error, :extension_inference_refused}, s}
    end
  end

  def commit_action(s, event, intent) do
    with true <- Actions.result_intent(event) == intent and Actions.valid_result?(event),
         true <-
           Ipse.Extension.SourceRead.bound_prepared?(
             intent["request"],
             event,
             Map.get(s.invocation.action, :source_read)
           ),
         true <-
           not Ipse.Extension.SourceRead.operation?(intent["request"]) or
             Ipse.Extension.SourceRead.bound_prepared?(
               intent["request"],
               event,
               Ipse.Extension.SourceRead.prepare(s, intent["request"]["op"], intent["request"])
             ),
         true <-
           Actions.bound_effect?(event, s.invocation.effect_sources, s.invocation.results),
         true <- Ipse.Extension.Registry.live?(s.invocation.parent["identity"]),
         true <-
           is_nil(intent["service"]) or
             Ipse.Extension.Registry.live?(intent["service"]["identity"]),
         {:ok, usage_reads} <- commit_usage_read(s, intent, event),
         {:ok, child_usage} <- commit_child_usage(s, intent, event),
         {:ok, managed_read, managed_reads} <-
           Ipse.Session.ManagedReads.bind_result(
             s.id,
             s.config,
             s.invocation.parent,
             s.invocation.action[:managed_read],
             s.invocation.managed_reads,
             event
           ),
         {:ok, contributions} <-
           Ipse.Extension.Context.apply_result(
             s.invocation.pending_contributions || s.extension_contributions,
             s.invocation.parent,
             s.invocation.results,
             event,
             if(s.reference, do: Ipse.Session.Reference.layout())
           ) do
      s =
        if managed_read do
          Session.record(s, managed_read)
          Session.managed_event(s, managed_read)
        else
          s
        end

      s = Session.record_extension_action(s, event)
      s = record_document_retirement(s, event)
      s = Session.managed_event(s, event)
      s = %{s | invocation: Ipse.Session.DocumentEmbedding.record_action(s.invocation, event)}

      lineage_available =
        match?(%Ipse.Session.ManagedLineage{unavailable: false}, s.managed_lineage)

      managed =
        not lineage_available or
          Ipse.Session.ManagedLineage.invocation_dependencies(
            s.managed_lineage,
            s.invocation.parent["invocation_id"]
          ) != {:ok, []}

      # Only execute_export drives these action continuations. Its pinned entry
      # uses the same configured predicate and independently fences the actual
      # committed result before Worker stdin; a result here is no delivery grant.
      withheld =
        intent["request"]["op"] in ~w(tool.call mcp.call collection.store) and managed and
          (not lineage_available or intent["request"]["op"] == "collection.store" or
             not Ipse.Session.WorkerInput.configured?(s.config))

      s =
        if withheld do
          refusal = Ipse.Session.ManagedToolUse.action_withheld(event)
          Session.record(s, refusal)
          Session.managed_event(s, refusal)
        else
          s
        end

      staged =
        intent["request"]["op"] == "context.publish" and
          Ipse.Session.ManagedLineage.invocation_dependencies(
            s.managed_lineage,
            s.invocation.parent["invocation_id"]
          ) != {:ok, []}

      if not withheld and Ipse.Extension.Actions.tool?(intent["request"]),
        do:
          Session.notify(
            s,
            {:tool_result, "extension:tool.call",
             if(managed,
               do: "Managed tool result withheld from terminal preview.",
               else: Jason.encode!(event["outcome"])
             )}
          )

      {:reply,
       if(withheld,
         do: {:error, :managed_action_output_unavailable},
         else: {:ok, Actions.resume(event)}
       ),
       %{
         s
         | invocation: %{
             s.invocation
             | action: nil,
               interrupted: withheld or event["outcome"]["status"] == "unknown",
               results: s.invocation.results ++ [event],
               document_embedding_context: nil,
               managed_reads: managed_reads,
               pending_contributions:
                 if(staged, do: contributions, else: s.invocation.pending_contributions)
           },
           extension_mcp_context: nil,
           usage_reads: usage_reads,
           child_usage: child_usage,
           extension_contributions:
             if(staged,
               do:
                 Map.delete(
                   s.extension_contributions,
                   s.invocation.parent["identity"]["instance"]
                 ),
               else: contributions
             )
       }}
    else
      _ -> {:reply, {:error, :invalid_extension_action}, s}
    end
  end

  def approve(s, allowed, caller, phase, action) do
    {reply, next} = approve_action(s, allowed, phase, action, false)
    GenServer.reply(caller, reply)
    {:reply, :ok, next}
  end

  @doc false
  def approve_managed(s, allowed, phase, action) do
    {reply, next} = approve_action(s, allowed, phase, action, true)
    {:reply, reply, next}
  end

  defp approve_action(s, allowed, phase, action, native) do
    intent =
      Map.put(action.intent, "approval", if(allowed == true, do: "approved", else: "denied"))

    {:ok, mode} = Ipse.Extension.Mode.capture(s.config)

    allowed =
      allowed == true and
        exact_action_permitted?(s, intent) and
        (native or not Ipse.Session.ManagedToolUse.managed_invocation?(s)) and
        Actions.allowed_under_outer?(s.invocation.parent, intent["request"]) and
        Ipse.Extension.Mode.ordinary(mode, Actions.mutating?(intent["request"])) != :deny

    intent = Map.put(intent, "approval", if(allowed, do: "approved", else: "denied"))

    if output_timely?(s) and Ipse.Extension.Registry.live?(s.invocation.parent["identity"]) do
      s = Session.record_extension_action(s, intent)
      s = Session.managed_event(s, intent)
      s = Session.finish_wait(s, if(allowed == true, do: "approved", else: "denied"))

      reply =
        cond do
          not output_timely?(s) -> {:error, :extension_action_expired}
          allowed == true -> {:ok, intent, extension_execution_context(s, intent)}
          true -> {:denied, intent}
        end

      if match?({:ok, _, _}, reply) and Ipse.Extension.Actions.tool?(intent["request"]),
        do:
          Session.notify(
            s,
            {:tool, "extension:tool.call",
             if(Ipse.Session.ManagedToolUse.managed_invocation?(s),
               do: %{},
               else: intent["request"]
             )}
          )

      {reply,
       %{
         s
         | approval: nil,
           phase: phase,
           invocation: %{s.invocation | action: %{intent: intent}, step: s.invocation.step + 1}
       }}
    else
      s = Session.finish_wait(s, "expired")

      {{:error, :extension_action_expired},
       %{s | approval: nil, phase: phase, invocation: %{s.invocation | action: nil}}}
    end
  end

  def answer(s, answers, question) do
    with {:ok, _} <- Questions.validate_answers(question.arguments, answers),
         true <- Ipse.Extension.Registry.live?(question.parent["identity"]),
         {:ok, result} <-
           Actions.result(question.action, %{
             "status" => "answered",
             "value" => %{"answers" => answers}
           }),
         {:ok, entry, _} <-
           Catalog.lookup(
             s.config,
             question.parent["descriptor"]["stage"],
             question.parent["descriptor"]["name"]
           ),
         true <- entry.identity == question.parent["identity"] do
      s = Session.enroll_feeds(s)
      results = question.results ++ [result]
      Session.record(s, result)
      Session.record(s, Actions.continuation(question.parent, result))
      s = Session.finish_wait(s, "answered")
      entry = Map.merge(entry, %{host_config: s.config, host_cwd: s.cwd})
      owner = self()
      job_ref = make_ref()

      task =
        Session.owned_task(fn ->
          Host.resume_export(entry, question.parent, result, owner, job_ref, results)
        end)

      phase = invocation_phase(question.parent)

      {:reply, :ok,
       %{
         s
         | question: nil,
           phase: phase,
           task: task,
           job_ref: job_ref,
           invocation: %{
             s.invocation
             | parent: question.parent,
               action: nil,
               step: question.action["step"],
               results: results,
               interrupted: false
           },
           tool_decision: question.parent["approval"]
       }}
    else
      _ -> {:reply, {:error, :invalid_extension_answer_or_expired}, s}
    end
  end

  @doc false
  def commit_event_job(s, event) do
    with parent when is_map(parent) <- s.invocation.parent,
         delivery when is_map(delivery) <- s.event_intent,
         true <- is_nil(s.invocation.action) and not s.invocation.interrupted,
         true <-
           Invocation.event_matches?(
             parent,
             delivery,
             s.event_received.record,
             s.event_committed.record,
             if(s.event_answer, do: s.event_answer.record)
           ),
         true <- Ipse.Extension.Registry.live?(parent["identity"]),
         {:ok, expected} <-
           Invocation.build_result(
             parent,
             %{"api_version" => 1, "kind" => "result", "value" => event["value"]},
             s.invocation.results
           ),
         true <- expected == event do
      Session.record(s, event)
      s = Session.managed_event(s, event)
      outcome = Invocation.event_outcome(s.invocation.results)
      Session.record(s, Subscriptions.result(delivery, outcome, true))

      if outcome == "failed" and not delivery["declaration"]["required"],
        do:
          Session.notify(
            s,
            {:status,
             "Optional event job had a refused or failed action; inspect its saved receipts."}
          )

      {:ok,
       %{
         s
         | invocation: %CurrentInvocation{},
           extension_mcp_context: nil,
           event_intent: nil
       }, outcome}
    else
      _ -> {:error, :event_job_result_refused}
    end
  end

  defp output_clock(entry, stage, job_ref) do
    identity = entry.identity

    if Ipse.Extension.ResultPublication.eligible?(
         identity["sdk"],
         identity["capabilities"],
         stage
       ) do
      started = System.monotonic_time(:millisecond)
      timer = Process.send_after(self(), {:extension_output_deadline, job_ref}, 120_000)
      {%{started_ms: started, timer: timer}, Map.put(entry, :output_started_ms, started)}
    else
      {nil, entry}
    end
  end

  @doc false
  def output_elapsed(%{extension_output_clock: %{started_ms: started}}),
    do: System.monotonic_time(:millisecond) - started

  @doc false
  def output_timely?(%{extension_output_clock: nil}), do: true
  @doc false
  def output_timely?(s), do: output_elapsed(s) in 0..119_999

  defp release_output_token(s, token) do
    case Writer.release(s.journal_writer, token) do
      :ok -> :ok
      {:error, reason} -> Session.journal_failed(s, reason)
    end
  end

  @doc false
  def release_output(s) do
    if s.extension_output_clock, do: Process.cancel_timer(s.extension_output_clock.timer)
    if s.extension_output, do: release_output_token(s, s.extension_output.token)
    %{s | extension_output: nil, extension_output_clock: nil}
  end

  @doc false
  def record_output(s, event, observed \\ false) do
    token = s.extension_output.token

    result =
      if observed and
           ((s.observation != nil and s.observation.policy["mode"] != "off") or
              Feeds.active?(s.feeds)),
         do: Writer.append_reserved_observed(s.journal_writer, token, event),
         else: Writer.append_reserved(s.journal_writer, token, event)

    case result do
      :ok ->
        if observed, do: release_output(s), else: s

      {:ok, source} ->
        next = release_output(s)
        Session.offer_record(next, source, event)
        next

      {:error, reason} ->
        Session.journal_failed(s, reason)
    end
  end

  @doc false
  def complete_invocation_result(s, event) do
    s = release_output(s)
    s = Session.managed_event(s, event)

    handoff =
      if s.phase == :extension_command and is_map(Map.get(s, :post_reply_capture)),
        do: Ipse.Session.ChatReviewHandoff.prepare(s, s.invocation.parent, event),
        else: :not_applicable

    s = %{
      s
      | managed_outputs:
          Map.put(s.managed_outputs, event["invocation_id"], s.invocation.managed_reads)
    }

    s = %{s | invocation: %{s.invocation | parent: nil, request: nil, provided_set: nil}}

    if s.phase == :tool do
      Turn.accept_tool_result(s, hd(s.calls), Invocation.tool_message(event))
    else
      case handoff do
        :not_applicable ->
          complete_command_result(s, event)

        result ->
          finish_chat_review(s, result)
      end
    end
  end

  @doc false
  def finish_chat_review(s, {:ok, ready}) do
    s
    |> Map.delete(:post_reply_capture)
    |> Session.ready_chat_review(ready)
    |> Turn.finish(:ok)
  end

  def finish_chat_review(s, {:error, _}) do
    Session.notify(s, {:decision_card_unavailable, :post_reply_review_unavailable})
    Turn.finish(Map.delete(s, :post_reply_capture), :ok)
  end

  defp complete_command_result(s, event) do
    display =
      Map.merge(
        %{"name" => event["descriptor"]["name"], "stage" => event["descriptor"]["stage"]},
        Invocation.delivery(event)
      )

    Session.notify(s, {:extension_result, display})
    Turn.finish(%{s | extension_result: display}, :ok)
  end

  @doc false
  def readable_output(s, request, model?) do
    with {:ok, source} <-
           ResultSource.source(
             s.extension_result_sources,
             ResultSource.request_output_id(request)
           ),
         true <- not model? or source.intent["descriptor"]["stage"] == "invoke.tool",
         delivery = ResultSource.descriptor(source),
         {:ok, source} <- ResultSource.readable_source(s.extension_result_sources, delivery) do
      {:ok, source, delivery}
    else
      _ -> {:error, :saved_result_read_refused}
    end
  end

  @doc false
  def invocation_phase(parent) do
    case parent["descriptor"]["stage"] do
      "invoke.tool" -> :tool
      "invoke.command" -> :extension_command
      "invoke.service" -> :extension_service
      "event.job" -> :extension_events
    end
  end

  defp extension_mcp_target(s, request) do
    with parent when is_map(parent) <- s.invocation.parent,
         true <-
           get_in(parent, ["semantic_binding", "class"]) not in ~w(collection.read decision.create),
         true <- not s.invocation.interrupted,
         true <- Ipse.Extension.Registry.live?(parent["identity"]),
         {:ok, ^request} <-
           Actions.proposal(
             %{"api_version" => 1, "kind" => "host_call", "request" => request},
             parent["identity"]
           ),
         true <- Actions.allowed?(parent["identity"], request, s.invocation.results) do
      Ipse.Extension.MCPCall.target(s.config, parent["identity"], request)
    else
      _ -> {:error, :extension_mcp_refused}
    end
  end

  defp extension_effect_binding(s, request) do
    cond do
      Ipse.Extension.CollectionStore.operation?(request) ->
        gate = s.invocation.document_context

        if is_map(gate) and gate.job == s.job_ref and gate.request == Ipse.JSON.digest([request]) and
             gate.identity == Ipse.JSON.digest([s.invocation.parent["identity"]]),
           do: {:ok, gate.binding},
           else: {:error, :document_store_refused}

      Ipse.Extension.ManagedCollectionCall.operation?(request) ->
        Ipse.Extension.ManagedCollectionCall.binding(s.config, s.invocation.parent, request)

      Ipse.Extension.CollectionCall.operation?(request) ->
        Ipse.Extension.CollectionCall.binding(s.config, s.invocation.parent["identity"], request)

      DecisionCall.operation?(request) ->
        DecisionCall.binding(s.config, request)

      EmbeddingCall.operation?(request) ->
        gate = s.invocation.document_embedding_context

        if Map.has_key?(request, "source_guard") do
          if is_map(gate) and gate.job == s.job_ref and
               gate.request == Ipse.JSON.digest([request]) and
               gate.identity == Ipse.JSON.digest([s.invocation.parent["identity"]]),
             do: EmbeddingCall.binding(s.config, request, gate.binding),
             else: {:error, :document_source_use_refused}
        else
          EmbeddingCall.binding(s.config, request)
        end

      EmbeddingCall.profile_request?(request) ->
        EmbeddingCall.profile_binding(
          %{"embedding_profiles" => Ipse.Config.Profiles.embedding_snapshot(s.config)},
          request
        )

      Ipse.Extension.Actions.mcp?(request) ->
        gate = s.extension_mcp_context

        if is_map(gate) and gate.job == s.job_ref and
             gate.request == Ipse.JSON.digest([request]) and
             gate.identity == Ipse.JSON.digest([s.invocation.parent["identity"]]),
           do: {:ok, gate.binding},
           else: {:error, :extension_mcp_not_bound}

      Ipse.Extension.Actions.result_read?(request) ->
        {:ok, Ipse.Extension.EffectResult.binding(request)}

      true ->
        {:ok, nil}
    end
  end

  defp extension_action_context(s, request) do
    if Ipse.Extension.Actions.workspace_context?(request) do
      checked_request =
        if Ipse.Extension.Actions.tool?(request) do
          request
        else
          {:ok, read} = Ipse.Extension.Collection.WorkspaceDocumentGuard.preflight_read(request)
          read
        end

      expected = %{
        request: Ipse.JSON.digest([checked_request]),
        context: Ipse.JSON.digest([s.context_snapshot]),
        job: s.job_ref,
        identity: Ipse.JSON.digest([s.invocation.parent["identity"]])
      }

      if s.extension_tool_context == expected,
        do: {:ok, expected.context},
        else: {:error, :tool_context_not_reviewed}
    else
      {:ok, nil}
    end
  end

  defp extension_service_context(s, request) do
    if Ipse.Extension.Actions.service?(request) do
      with {:ok, entry, context} <-
             Ipse.Extension.Services.lookup(
               s.config,
               s.invocation.parent["identity"],
               request
             ),
           true <- Ipse.Extension.Registry.live?(entry.identity) do
        {:ok, context}
      else
        _ -> {:error, :service_unavailable}
      end
    else
      {:ok, nil}
    end
  end

  defp extension_execution_context(s, intent, source \\ nil) do
    context = %{
      root: Path.join(s.context_home, "extension-state-v1"),
      cwd: s.cwd,
      sandbox: Map.get(s.config, :sandbox, :off),
      parallel_child: Map.get(s.config, :parallel_child, false),
      contributions: s.invocation.pending_contributions || s.extension_contributions,
      reference_layout: if(s.reference, do: Ipse.Session.Reference.layout()),
      identity: s.invocation.parent["identity"],
      actions: s.invocation.results
    }

    context =
      if Ipse.Extension.CollectionCall.operation?(intent["request"]) or
           Ipse.Extension.ManagedCollectionCall.operation?(intent["request"]),
         do:
           Map.merge(context, %{
             config: s.config,
             session_id: s.id,
             parent: s.invocation.parent,
             owner: self(),
             job_ref: s.job_ref,
             history_dir: s.dir,
             index_scope:
               case Ipse.Journal.Writer.source_query(s.journal_writer, :index_scope) do
                 {:ok, scope} -> scope
                 _ -> nil
               end
           }),
         else: context

    context =
      if Ipse.Extension.CollectionStore.operation?(intent["request"]),
        do:
          Map.merge(context, %{
            config: s.config,
            session_id: s.id,
            parent: s.invocation.parent,
            owner: self(),
            job_ref: s.job_ref,
            history_dir: s.dir
          }),
        else: context

    context =
      if s.extension_output_clock,
        do: Map.put(context, :output_deadline_ms, s.extension_output_clock.started_ms + 120_000),
        else: context

    context =
      if Ipse.Extension.Actions.inference?(intent["request"]),
        do: Map.merge(context, %{owner: self(), job_ref: s.job_ref}),
        else: context

    context =
      if Ipse.Extension.DecisionCall.operation?(intent["request"]),
        do:
          Map.merge(context, %{config: s.config, session_id: s.id, parent: s.invocation.parent}),
        else: context

    context =
      if Ipse.Extension.Actions.mcp?(intent["request"]),
        do:
          Map.merge(context, %{
            owner: self(),
            job_ref: s.job_ref,
            mcp_descriptor: s.extension_mcp_context.descriptor
          }),
        else: context

    context =
      if intent["request"]["op"] in ~w(tool.call mcp.call collection.store),
        do: Map.put(context, :managed_tool, %{owner: self(), job_ref: s.job_ref}),
        else: context

    context =
      if Ipse.Extension.Actions.result_read?(intent["request"]) do
        {:ok, effect_source} =
          Actions.effect_source(
            intent["request"],
            s.invocation.effect_sources,
            s.invocation.results
          )

        Map.put(context, :effect_source, effect_source)
      else
        context
      end

    context =
      if Ipse.Extension.Actions.history?(intent["request"]),
        do:
          Map.merge(context, %{
            history_dir: s.dir,
            history_session: s.id,
            history_project_drafts: s.draft_history_restricted
          }),
        else: context

    context =
      if Ipse.Extension.SourceRead.operation?(intent["request"]),
        do:
          Map.put(
            context,
            :source_read,
            Ipse.Extension.SourceRead.prepare(s, intent["request"]["op"], intent["request"])
          ),
        else: context

    context =
      if source != nil and Ipse.Extension.Actions.history?(intent["request"]),
        do: Map.put(context, :history_snapshot, Ipse.Extension.History.snapshot(source, intent)),
        else: context

    context =
      if Ipse.Extension.UsageRead.operation?(intent["request"]),
        do:
          Map.put(
            context,
            :usage_read,
            Ipse.Extension.UsageRead.prepare(
              s.accounting,
              s.usage_reads,
              intent,
              if(source, do: elem(Ipse.Journal.source_metadata(source), 1))
            )
          ),
        else: context

    context =
      if Ipse.Extension.ChildUsage.operation?(intent["request"]) do
        Map.put(
          context,
          :child_usage,
          Ipse.Extension.ChildUsage.context(
            s.child_usage,
            intent,
            s.dir,
            if(source, do: elem(Ipse.Journal.source_metadata(source), 1))
          )
        )
      else
        context
      end

    if intent["service"] do
      target = Enum.find(s.config.extensions, &(&1.identity == intent["service"]["identity"]))
      Map.merge(context, %{service_entry: target, session_id: s.id, turn_id: s.turn_id})
    else
      context
    end
  end

  defp inference_begin?(:extension_model_begin, request), do: ModelCall.operation?(request)

  defp inference_begin?(:extension_embedding_begin, request),
    do: EmbeddingCall.operation?(request)

  defp inference_begin?(:extension_decision_begin, request),
    do: DecisionCall.operation?(request)

  defp inference_usage?(:extension_model_usage, admission),
    do: Ipse.Usage.operation(admission) == "text"

  defp inference_usage?(:extension_embedding_usage, admission),
    do: Ipse.Usage.operation(admission) == "embedding"

  defp inference_usage?(:extension_decision_usage, admission),
    do: Ipse.Usage.operation(admission) == "decision"

  defp bounded_capture?(%{value: value, usage: usage}, intent, :embedding) do
    Ipse.Provider.Embedding.valid_result?(
      value,
      intent["effect_binding"]["execution"],
      intent["request"]["inputs"]
    ) and
      Ipse.Usage.valid_usage?(usage, "embedding")
  end

  defp bounded_capture?(%{value: value, usage: usage}, intent, :decision) do
    Ipse.Provider.Decision.Transport.valid_result?(
      value,
      intent["effect_binding"]["execution"],
      DecisionCall.neutral(intent["request"])
    ) and
      Ipse.Usage.valid_usage?(usage, "decision")
  end

  defp bounded_capture?(_, _, _), do: false

  defp observe_bound_capture(s, admission, usage) do
    entry = s.accounting.requests[admission["request_id"]]

    cond do
      entry.observation === usage ->
        s

      entry.sequence < 64 ->
        Session.account(s, %{
          "type" => "request_usage_observed",
          "version" => admission["version"],
          "operation" => Ipse.Usage.operation(admission),
          "request_id" => admission["request_id"],
          "attempt_id" => admission["attempt_id"],
          "sequence" => entry.sequence + 1,
          "usage" => usage
        })

      true ->
        raise "Inference observation allowance exhausted"
    end
  end

  defp prepare_inference(config, %{"op" => "embedding.create"} = request),
    do: Ipse.Config.Profiles.prepare_embedding(config, request)

  defp prepare_inference(config, %{"op" => "decision.create"} = request),
    do: Ipse.Config.Decisions.prepare(config, request)

  defp prepare_inference(config, request), do: ModelCall.prepare(config, request)

  defp inference_destination(config, %{"op" => "decision.create"}),
    do: Ipse.Provider.Decision.Transport.destination(config)

  defp inference_destination(config, _), do: Ipse.Provider.destination(config)

  defp extension_effect_record_capacity(_s, %{"approval" => "denied"}), do: :ok

  defp extension_effect_record_capacity(s, intent) do
    request = intent["request"]

    result =
      cond do
        DecisionCall.operation?(request) ->
          {:ok, %{max_record_bytes: 65_536}}

        EmbeddingCall.operation?(request) ->
          with {:ok, config, execution} <- prepare_inference(s.config, request) do
            admission =
              Ipse.Usage.admission(s.id, config, "extension", s.turn_id)
              |> Map.put("request_id", intent["operation_id"])

            Ipse.Extension.EffectResult.embedding_capacity(intent, admission, execution)
          end

        Ipse.Extension.MCPCall.operation?(request) ->
          Ipse.Extension.EffectResult.mcp_capacity(intent)

        true ->
          {:ok, %{max_record_bytes: 0}}
      end

    with {:ok, capacity} <- result,
         {:ok, limits} <- Ipse.Journal.normalize_limits(s.config[:journal]),
         true <- capacity.max_record_bytes <= limits["max_record_bytes"] do
      :ok
    else
      _ -> {:error, :effect_record_capacity}
    end
  end

  defp extension_model_configuration(config, request) do
    if Ipse.Extension.Actions.inference?(request) do
      case prepare_inference(config, request) do
        {:ok, _, _} -> :ok
        _ -> {:error, :invalid_extension_model_configuration}
      end
    else
      :ok
    end
  end

  defp commit_usage_read(s, intent, event) do
    if Ipse.Extension.UsageRead.operation?(intent["request"]),
      do:
        Ipse.Extension.UsageRead.commit(
          s.usage_reads,
          intent,
          event,
          s.invocation.action.usage_read
        ),
      else: {:ok, s.usage_reads}
  end

  defp commit_child_usage(s, intent, event) do
    if Ipse.Extension.ChildUsage.operation?(intent["request"]) do
      Ipse.Extension.ChildUsage.commit(
        s.child_usage,
        intent,
        event,
        s.invocation.action.child_usage.source
      )
    else
      {:ok, s.child_usage}
    end
  end

  @doc false
  def suspend_for_question(s, invocation_phase, action) do
    with %{intent: ^action} <- s.invocation.action,
         true <- output_timely?(s),
         true <- Questions.enabled?(s.config),
         true <- Ipse.Extension.Registry.live?(s.invocation.parent["identity"]) do
      s = release_output(s)
      parent = s.invocation.parent

      next =
        if invocation_phase == :tool,
          do:
            Turn.settle_calls(
              %{s | calls: tl(s.calls), phase: :idle},
              "Not started while extension clarification is required."
            ),
          else: s

      call = if invocation_phase == :tool, do: hd(s.calls)

      question = %{
        kind: :extension,
        id: action["operation_id"],
        arguments: action["request"]["arguments"],
        parent: parent,
        action: action,
        results: s.invocation.results,
        steps: s.steps,
        call: call
      }

      event = Actions.question_event(parent, action, s.steps)
      source = Session.record_wait_subject(next, event)
      Session.checkpoint_event_question(next, question)
      if source, do: Session.offer_record(next, source, event)
      next = Session.question_wait(next, question, source)
      Session.notify(next, {:question, question.id, question.arguments})

      {:noreply,
       %{
         next
         | question: question,
           phase: :question,
           task: nil,
           job_ref: nil,
           calls: if(call, do: [call], else: [])
       }}
    else
      _ ->
        {:noreply,
         Turn.fail(
           s,
           "Extension question could not be committed; no answer or continuation was selected."
         )}
    end
  end

  @doc false
  def complete_event_job(s, event) do
    delivery = s.event_intent

    case commit_event_job(s, event) do
      {:ok, next, outcome} ->
        if outcome == "completed" or not delivery["declaration"]["required"],
          do: {:noreply, Turn.continue_event_plan(next, delivery)},
          else:
            {:noreply,
             Turn.fail(
               next,
               "Required event job had a refused or failed action; inspect its receipts."
             )}

      _ ->
        {:noreply,
         Turn.fail(
           s,
           "Event job result was invalid or expired; inspect its saved receipts before retrying."
         )}
    end
  end

  # A fenced result is delivered inline only while its set is current and its
  # reported as-of time lies inside the fence, after a durable current release.
  # Otherwise a withheld release is recorded instead.
  defp provided_release(s, event) do
    if ProvidedSourceSet.active?(s) do
      intent = s.invocation.provided_set.intent
      now = ProvidedSourceSet.now(s)

      with {:ok, next} <- ProvidedSourceSet.check(s, now),
           true <-
             ProvidedSourceSet.result_as_of?(s.invocation.parent, intent, event["value"], now) do
        Session.record(next, ProvidedSourceSet.release(intent, "current", now, event))
        {:ok, next}
      else
        failure ->
          Session.record(s, ProvidedSourceSet.release(intent, "withheld", now, nil))

          {:withheld, s,
           if(failure == false,
             do:
               "The fenced result reported an as-of time outside its provided source set; the result was withheld and nothing was replayed.",
             else:
               "A provided source reached its observation or expiry time, or the clock moved backward, before delivery; the result was withheld and nothing was replayed."
           )}
      end
    else
      {:ok, s}
    end
  end

  @doc false
  def publish_saved_result(s, delivery) do
    with intent when is_map(intent) <- s.invocation.parent,
         # Saved pages would outlive the fence; a fenced result must fit inline.
         false <- ProvidedSourceSet.active?(s),
         true <- s.extension_output != nil and s.extension_output_clock != nil,
         true <- output_timely?(s) and is_nil(s.invocation.action),
         true <- not s.invocation.interrupted,
         true <- Ipse.Extension.Registry.live?(intent["identity"]),
         {:ok, event} <-
           Invocation.build_saved_result(
             intent,
             delivery,
             s.invocation.results,
             output_elapsed(s)
           ),
         {:ok, index} <- ResultSource.publish(s.extension_result_sources, event) do
      next =
        record_output(%{s | extension_result_sources: index}, event, true)

      {:noreply, complete_invocation_result(next, event)}
    else
      _ ->
        {:noreply, Turn.fail(s, "Saved result publication refused; inspect its source receipts.")}
    end
  end

  @doc false
  def publish_inline_result(s, event) do
    with intent when is_map(intent) <- s.invocation.parent,
         true <- output_timely?(s) and is_nil(s.extension_output),
         true <- is_nil(s.invocation.action),
         true <- not s.invocation.interrupted,
         {:ok, expected} <-
           Invocation.build_result(
             intent,
             %{
               "api_version" => 1,
               "kind" => "result",
               "value" => event["value"]
             },
             s.invocation.results
           ),
         true <- expected == event and Ipse.Extension.Registry.live?(intent["identity"]) do
      case provided_release(s, event) do
        {:ok, s} ->
          Session.record(s, event)
          s = Ipse.Session.PendingNomination.record_result(s, intent, event)
          {:noreply, complete_invocation_result(s, event)}

        {:withheld, s, message} ->
          {:noreply, Turn.fail(s, message)}
      end
    else
      _ ->
        {:noreply,
         Turn.fail(
           s,
           "Extension result was invalid or its lease expired; inspect the saved intent before retrying."
         )}
    end
  end
end
