defmodule Ipse.Session.DocumentEmbedding do
  @moduledoc false
  alias Ipse.Session
  alias Ipse.Extension.{CollectionStore, EmbeddingCall, Registry}
  alias Ipse.Extension.Collection.{DocumentSourceUse, DocumentStage}
  @error {:error, :document_source_use_refused}

  # This state is populated only by live, durably committed action results.
  # Saved result lists and pending Collection records never reconstruct it.
  def record_action(invocation, event) do
    identity = invocation.parent["identity"]

    if CollectionStore.embedding_source_required?(identity) do
      state = invocation.document_producer || initial()
      state = record(state, event, identity, invocation.parent["invocation_id"])
      %{invocation | document_producer: state}
    else
      invocation
    end
  end

  def allowed?(invocation, request, binding) do
    state = invocation.document_producer
    source = binding["source_binding"]
    guard = request["source_guard"]
    claim = state && state.claim

    is_map(claim) and state.status === :ready and state.next === guard["batch_index"] and
      claim.key === guard["claim_key"] and claim.revision === guard["claim_revision"] and
      claim.sha256 === guard["claim_sha256"] and claim.namespace === source["namespace"] and
      claim.project === source["project"] and
      claim.identity_sha256 === source["identity_sha256"] and
      claim.parent === invocation.parent["invocation_id"] and
      Map.get(claim, :guard_version, 1) === guard["version"]
  rescue
    _ -> false
  end

  def admit(s, facts) do
    intent = s.invocation.action.intent
    binding = intent["effect_binding"]
    state = s.invocation.document_producer

    with true <- Session.Invocation.output_timely?(s) and not s.invocation.interrupted,
         true <- Registry.live?(s.invocation.parent["identity"]),
         true <-
           EmbeddingCall.valid_identity?(
             s.invocation.parent["identity"],
             intent["request"],
             binding
           ),
         true <- binding["source_binding"]["session_id"] === s.id,
         true <- allowed?(s.invocation, intent["request"], binding),
         true <- facts.claim_operation_id === state.claim.operation_id,
         true <-
           facts.claim_revision === state.claim.revision and
             facts.claim_sha256 === state.claim.sha256,
         true <- facts.claim_key === state.claim.key and facts.batch_index === state.next,
         true <- facts.selection_sha256 === intent["request"]["expected_selection_sha256"],
         true <-
           facts.batch_count in 1..4 and
             (is_nil(state.count) or state.count === facts.batch_count) do
      next = %{
        state
        | status: :inflight,
          inflight: intent["operation_id"],
          count: facts.batch_count
      }

      {:reply, :ok, %{s | invocation: %{s.invocation | document_producer: next}}}
    else
      _ -> {:reply, @error, poison(s)}
    end
  rescue
    _ -> {:reply, @error, poison(s)}
  end

  def poison(s) do
    state = s.invocation.document_producer || initial()
    %{s | invocation: %{s.invocation | document_producer: %{state | status: :poisoned}}}
  end

  # This runs in the actual admitted file effect, after approval. The native
  # read authenticates the old phase; the unchanged generation on the following
  # inline CAS closes the gap after releasing this short read lease.
  def observe_inline(read, witness, request) do
    with {:ok, body} <- pending_inline(request),
         true <- witness["root"]["generation"] === request["generation"],
         {:ok, old} <- DocumentStage.read_value(read, request["key"]),
         true <- prior_inline?(old, request) do
      {:ok,
       %{
         generation: request["generation"],
         revision: request["expected_revision"],
         sha256: if(old, do: old["sha256"]),
         body_sha256: Ipse.JSON.sha256(request["data"]),
         vector_cursor: body["vector_cursor"]
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def pending_inline(request) do
    with %{"op" => "value.put_inline", "key" => key, "data" => data} <- request,
         true <- is_binary(key) and String.starts_with?(key, "genproducer4."),
         {:ok, body} <- Ipse.JSON.decode_unique(data),
         true <- body["status"] === "pending",
         true <- DocumentStage.request?(request) and DocumentSourceUse.pending?(body, key) do
      {:ok, body}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def inline_claim?(request) do
    request["op"] == "value.put_inline" and is_binary(request["key"]) and
      String.starts_with?(request["key"], "genproducer4.") and
      match?({:ok, %{"status" => "pending"}}, Ipse.JSON.decode_unique(request["data"]))
  rescue
    _ -> false
  end

  def prepare_inline(s, intent, observation) do
    binding = intent["effect_binding"]
    request = intent["request"]["request"]
    identity = s.invocation.parent["identity"]
    state = s.invocation.document_producer || initial()

    with %{intent: ^intent} <- s.invocation.action,
         true <- Session.Invocation.output_timely?(s) and not s.invocation.interrupted,
         true <-
           CollectionStore.embedding_source_required?(identity) and Registry.live?(identity),
         true <- CollectionStore.valid_binding?(binding, intent["request"], identity),
         true <- binding["session_id"] === s.id,
         true <- intent["parent_invocation_id"] === s.invocation.parent["invocation_id"],
         true <- intent["approval"] in ~w(not_required approved session_allow),
         true <- state.status === :ready and is_nil(state.claim) and is_nil(state.prepare),
         true <- is_nil(state.inline),
         {:ok, body} <- pending_inline(request),
         true <- is_map(observation) and map_size(observation) === 5,
         true <- observation.generation === request["generation"],
         true <- observation.revision === request["expected_revision"],
         true <- observation.body_sha256 === request["sha256"],
         true <- observation.vector_cursor === body["vector_cursor"],
         true <-
           if(request["expected_revision"] === 0,
             do: is_nil(observation.sha256),
             else: Ipse.JSON.sha256?(observation.sha256)
           ) do
      inline = %{
        operation_id: intent["operation_id"],
        request_sha256: Ipse.JSON.digest([intent["request"]]),
        key: request["key"],
        sha256: request["sha256"],
        namespace: binding["namespace"],
        project: binding["project"],
        identity_sha256: binding["identity_sha256"],
        parent: intent["parent_invocation_id"],
        generation: request["generation"],
        guard_version: 2
      }

      {:reply, :ok,
       %{s | invocation: %{s.invocation | document_producer: %{state | inline: inline}}}}
    else
      _ -> {:reply, @error, poison(s)}
    end
  rescue
    _ -> {:reply, @error, poison(s)}
  end

  defp prior_inline?(nil, request), do: request["expected_revision"] === 0

  defp prior_inline?(row, request) do
    request["expected_revision"] > 0 and row["revision"] === request["expected_revision"] and
      Ipse.JSON.sha256?(row["sha256"]) and
      DocumentSourceUse.ready?(row["value"], request["key"])
  end

  @doc false
  def before_dispatch(data, wire_facts) do
    source = data.document_source.binding["source_binding"]
    request = data.document_source.request
    marker = make_ref()

    result =
      Session.Resources.file_effect(fn ->
        Ipse.Extension.ProjectIdentity.with_existing_binding(
          data.config[:home],
          data.cwd,
          source["project"],
          fn _ ->
            Ipse.Extension.Collection.with_document_read(
              CollectionStore.root(data.config[:home]),
              source["namespace"],
              fn _, read ->
                with true <- data.phase == "embedding.create" and is_map(data.wire),
                     {:ok, facts} <-
                       DocumentSourceUse.authenticate(
                         read,
                         request["source_guard"],
                         request["inputs"],
                         data.document_source.selection
                       ),
                     :ok <-
                       GenServer.call(
                         data.owner,
                         {:document_embedding_admit, data.job_ref, data.phase, data.admission,
                          data.expected, wire_facts, facts},
                         5_000
                       ),
                     # All blocking validation and the one-use spend precede UTC.
                     now = System.system_time(:millisecond),
                     true <- DocumentSourceUse.current?(facts, now),
                     true <- Registry.live?(data.document_source.identity, div(now, 1000)) do
                  {:ok, marker}
                else
                  _ -> @error
                end
              end
            )
          end
        )
      end)

    case result do
      {:ok, ^marker} -> :ok
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  def dispatch_data(s) do
    intent = s.invocation.action.intent
    request = intent["request"]
    binding = intent["effect_binding"]
    execution = binding["execution"]

    %{
      request: request,
      binding: binding,
      identity: s.invocation.parent["identity"],
      deadline_ms:
        if(s.extension_output_clock, do: s.extension_output_clock.started_ms + 120_000),
      selection: %{
        "profile" => execution["id"],
        "model" => execution["model"],
        "dimensions" => execution["dimensions"],
        "encoding" => "float32le",
        "selection_sha256" => request["expected_selection_sha256"]
      }
    }
  end

  defp record(state, %{"request" => %{"op" => "embedding.create"}} = event, _, _) do
    if state.status === :inflight and state.inflight === event["operation_id"] and
         event["outcome"]["status"] == "ok" do
      next = state.next + 1

      %{
        state
        | next: next,
          inflight: nil,
          status: if(next == state.count, do: :done, else: :ready)
      }
    else
      %{state | status: :poisoned}
    end
  end

  defp record(state, event, identity, parent) do
    request = event["request"]
    binding = event["effect_binding"]

    if CollectionStore.operation?(request) and
         event["parent_invocation_id"] === parent and
         CollectionStore.valid_binding?(binding, request, identity) do
      cond do
        not is_nil(state.inline) -> record_inline(state, event, binding, parent)
        event["outcome"]["status"] == "ok" -> record_store(state, event, binding, parent)
        true -> state
      end
    else
      state
    end
  end

  defp record_inline(state, event, binding, parent) do
    inline = state.inline
    result = event["outcome"]["value"]["result"]

    if state.status === :ready and is_nil(state.claim) and
         event["outcome"]["status"] === "ok" and
         event["operation_id"] === inline.operation_id and
         Ipse.JSON.digest([event["request"]]) === inline.request_sha256 and
         binding["namespace"] === inline.namespace and binding["project"] === inline.project and
         binding["identity_sha256"] === inline.identity_sha256 and parent === inline.parent and
         result["generation"] === inline.generation + 1 and
         result["record"]["revision"] === result["generation"] and
         result["record"]["sha256"] === inline.sha256 do
      claim =
        inline
        |> Map.drop([:request_sha256, :generation])
        |> Map.put(:revision, result["generation"])

      %{state | inline: nil, claim: claim}
    else
      %{state | inline: nil, status: :poisoned}
    end
  end

  defp record_store(%{claim: nil} = state, event, binding, parent) do
    request = event["request"]["request"]
    result = event["outcome"]["value"]["result"]

    cond do
      state.status !== :ready ->
        state

      request["op"] == "value.prepare_inline" and request["expected_revision"] === 0 and
        is_binary(request["key"]) and String.starts_with?(request["key"], "genproducer.") ->
        prepare = %{
          ref: Map.take(result["stage"], ~w(slot epoch)),
          key: request["key"],
          sha256: request["sha256"],
          namespace: binding["namespace"],
          project: binding["project"],
          identity_sha256: binding["identity_sha256"],
          parent: parent
        }

        if is_nil(state.prepare),
          do: %{state | prepare: prepare},
          else: %{state | status: :poisoned}

      request["op"] == "commit" and not is_nil(state.prepare) ->
        p = state.prepare

        if request["stages"] === [p.ref] and binding["namespace"] === p.namespace and
             binding["project"] === p.project and binding["identity_sha256"] === p.identity_sha256 do
          %{
            state
            | claim:
                p
                |> Map.delete(:ref)
                |> Map.merge(%{
                  operation_id: event["operation_id"],
                  revision: result["generation"]
                }),
              prepare: nil
          }
        else
          %{state | status: :poisoned}
        end

      true ->
        state
    end
  end

  defp record_store(state, _, _, _), do: state

  defp initial,
    do: %{
      prepare: nil,
      inline: nil,
      claim: nil,
      status: :ready,
      next: 0,
      count: nil,
      inflight: nil
    }
end
