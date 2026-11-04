defmodule Ipse.Session.PendingNomination do
  @moduledoc """
  Host binding for a successful same-turn Knowledge nomination.

  A nomination is not a source proof, a display, a review permit, or authority
  to publish. The live Session must establish those separately.
  """
  alias Ipse.{JSON, Session}
  alias Ipse.Extension.{Catalog, Invocation, Mode}

  @error {:error, :nomination_unavailable}
  @categories ~w(ordinary preference current)

  @doc false
  def record_result(s, intent, result) do
    if s.phase == :tool and intent["descriptor"]["id"] == "nominate" and
         intent["identity"]["instance"] == "knowledge" and
         s.pending_acceptance_layout == Session.PendingAcceptance.layout() do
      record_new_result(s, intent, result)
    else
      s
    end
  end

  defp record_new_result(s, intent, result) do
    case from_result(intent, result, s.config, s.id, s.turn_id) do
      {:ok, nomination} ->
        Session.record(s, nomination)

        if Map.get(s, :pending_nomination) == nil do
          Map.put(s, :pending_nomination, %{
            event: nomination,
            arguments: intent["payload"]["arguments"]
          })
        else
          Map.put(s, :pending_nomination, :conflicted)
        end

      _ ->
        Map.put(s, :pending_nomination, :unavailable)
    end
  end

  @doc false
  def from_result(intent, result, config, session, turn) do
    admission = config[:semantic_admission]

    with true <- Ipse.Extension.SemanticAdmission.valid?(admission, session),
         {:ok, scope} <- Session.OperatorAssertion.scope(admission),
         true <- admission["instance"] == "knowledge",
         %{"kind" => "reviewed.bundle", "artifact_sha256" => digest} <-
           get_in(admission, ["policy", "settings", "activation"]),
         true <- digest == scope["artifact_sha256"],
         {:ok, mode} <- Mode.capture(config),
         false <- mode["headless"],
         :ok <- Mode.knowledge(mode, "collection.publish"),
         {:ok, entry, descriptor} <-
           Catalog.lookup(config, "invoke.tool", "ext__knowledge__nominate"),
         true <- entry.identity === intent["identity"],
         true <- admission["pin"]["identity_sha256"] == JSON.digest([entry.identity]),
         true <- entry.identity["artifact_sha256"] == digest,
         true <- descriptor === intent["descriptor"],
         {:ok, event} <- bind(intent, result, scope, mode, session, turn) do
      {:ok, event}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp bind(intent, result, scope, mode, session, turn) do
    with true <- intent["descriptor"]["id"] == "nominate",
         true <- intent["descriptor"]["stage"] == "invoke.tool",
         true <- intent["descriptor"]["instance"] == "knowledge",
         true <- intent["identity"]["instance"] == "knowledge",
         true <- intent["identity"]["artifact_sha256"] == scope["artifact_sha256"],
         false <- mode["headless"],
         :ok <- Mode.knowledge(mode, "collection.publish"),
         true <- intent["payload"]["session_id"] === session,
         true <- intent["payload"]["turn_id"] === turn,
         true <- id?(intent["invocation_id"]) and id?(session) and id?(turn),
         true <- Ipse.Tools.valid_call_id?(intent["parent_call_id"]),
         true <- id?(intent["parent_request_id"]),
         true <- arguments?(intent["payload"]["arguments"]),
         {:ok, ^result} <-
           Invocation.build_result(intent, %{
             "api_version" => 1,
             "kind" => "result",
             "value" => %{"status" => "nominated"}
           }) do
      {:ok,
       %{
         "type" => "pending_proposal_nominated",
         "version" => 1,
         "session_id" => session,
         "turn_id" => turn,
         "invocation_id" => intent["invocation_id"],
         "parent_call_id" => intent["parent_call_id"],
         "parent_request_id" => intent["parent_request_id"],
         "intent_sha256" => JSON.digest([intent]),
         "result_sha256" => JSON.digest([result]),
         "scope_sha256" => JSON.digest([scope]),
         "mode" => mode
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc false
  def validate_events(events, session) when is_list(events) do
    with :ok <- validate_nominations(events, session),
         {:ok, _attempts} <- capture_attempts(events, session) do
      :ok
    end
  end

  def validate_events(_, _), do: @error

  defp validate_nominations(events, session) do
    if Enum.any?(events, &(&1["type"] == "pending_proposal_nominated")) do
      [%{"metadata" => metadata} | _] = events
      admission = metadata["semantic_admission"]
      session = session || get_in(admission || %{}, ["pin", "session_id"])

      with true <- Ipse.Extension.SemanticAdmission.valid?(admission, session),
           true <- metadata["pending_acceptance_layout"] == Session.PendingAcceptance.layout(),
           {:ok, scope} <- Session.OperatorAssertion.scope(admission),
           true <- admission["instance"] == "knowledge",
           %{"kind" => "reviewed.bundle", "artifact_sha256" => digest} <-
             get_in(admission, ["policy", "settings", "activation"]),
           true <- digest == scope["artifact_sha256"],
           {:ok, catalog} <- Catalog.from_metadata(metadata),
           [identity] <- Enum.filter(metadata["extensions"], &(&1["instance"] == "knowledge")),
           true <- admission["pin"]["identity_sha256"] == JSON.digest([identity]),
           [descriptor] <-
             Enum.filter(catalog["entries"], fn entry ->
               entry["stage"] == "invoke.tool" and entry["name"] == "ext__knowledge__nominate"
             end) do
        validate_history(events, session, scope, identity, descriptor)
      else
        _ -> @error
      end
    else
      :ok
    end
  rescue
    _ -> @error
  end

  @doc false
  def capture_attempt(session, turn, request, nomination, proof) do
    with true <- id?(session) and id?(turn) and id?(request),
         true <- nomination["type"] === "pending_proposal_nominated",
         true <- nomination["session_id"] === session and nomination["turn_id"] === turn,
         {:ok, _} <- Ipse.Extension.ManagedRecipe.source_identity(proof),
         true <- proof["session_id"] === session and proof["kind"] === "answer.original",
         true <- proof["origin"] === "assistant_proposal" do
      binding = %{
        "type" => "pending_chat_capture_started",
        "version" => 2,
        "session_id" => session,
        "turn_id" => turn,
        "request_id" => request,
        "nomination_sha256" => JSON.digest([nomination]),
        "source_proof" => proof
      }

      {:ok, Map.put(binding, "capture_attempt_id", binary_part(JSON.digest([binding]), 0, 32))}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Restore spent answer identities only; interrupted captures are never restarted."
  def capture_attempts(events, session) when is_list(events) do
    if Enum.any?(events, &(&1["type"] === "pending_chat_capture_started")) do
      [%{"metadata" => metadata} | _] = events
      session = session || get_in(metadata, ["semantic_admission", "pin", "session_id"])
      {:ok, origin} = Ipse.Journal.SourceOrigin.recorded(metadata, session)

      initial = %{
        turn: nil,
        nomination: nil,
        intents: %{},
        answer: nil,
        closed: true,
        attempts: %{}
      }

      origin = if origin, do: JSON.digest([origin])

      Enum.reduce_while(events, {:ok, initial}, fn event, {:ok, state} ->
        case attempt_record(state, event, session, origin) do
          {:ok, next} -> {:cont, {:ok, next}}
          _ -> {:halt, @error}
        end
      end)
      |> case do
        {:ok, state} -> {:ok, state.attempts}
        _ -> @error
      end
    else
      {:ok, %{}}
    end
  rescue
    _ -> @error
  end

  def capture_attempts(_, _), do: @error

  defp attempt_record(state, %{"type" => "input_received"} = event, session, _origin) do
    if event["session_id"] === session and id?(event["turn_id"]),
      do:
        {:ok,
         %{
           state
           | turn: event["turn_id"],
             nomination: nil,
             intents: %{},
             answer: nil,
             closed: false
         }},
      else: @error
  end

  defp attempt_record(
         state,
         %{"type" => "extension_invocation_intent"} = event,
         _session,
         _origin
       ),
       do: {:ok, %{state | intents: Map.put(state.intents, event["invocation_id"], event)}}

  defp attempt_record(state, %{"type" => "pending_proposal_nominated"} = event, session, _origin) do
    with true <-
           not state.closed and event["session_id"] === session and
             event["turn_id"] === state.turn,
         intent when is_map(intent) <- state.intents[event["invocation_id"]],
         true <- event["intent_sha256"] === JSON.digest([intent]),
         arguments = intent["payload"]["arguments"],
         true <- arguments?(arguments) do
      nomination =
        if is_nil(state.nomination), do: %{event: event, arguments: arguments}, else: :conflicted

      {:ok, %{state | nomination: nomination}}
    else
      _ -> @error
    end
  end

  defp attempt_record(
         state,
         %{"type" => "source_answer_committed", "version" => 1, "answer" => answer},
         session,
         origin
       ),
       do: attempt_record(state, answer, session, origin)

  defp attempt_record(
         state,
         %{"type" => "lifecycle_answer_committed"} = answer,
         _session,
         _origin
       ) do
    if not state.closed and is_nil(state.answer) and answer["turn_id"] === state.turn and
         Session.Lifecycle.valid_answer?(answer),
       do: {:ok, %{state | answer: answer}},
       else: @error
  end

  defp attempt_record(state, %{"type" => "pending_chat_capture_started"} = event, session, origin) do
    with false <- state.closed,
         %{event: nomination, arguments: arguments} <- state.nomination,
         answer when is_map(answer) <- state.answer,
         {:ok, index} <- Session.SourceIndex.new(session, 1, origin),
         {:ok, index} <- Session.SourceIndex.admit_answer(index, answer),
         {:ok, proof} <-
           attempt_proof(index, event, state.turn, answer["request_id"], arguments["text"]),
         {:ok, expected} <-
           capture_attempt(session, state.turn, answer["request_id"], nomination, proof),
         true <- capture_record?(event, expected),
         key = {state.turn, answer["request_id"]},
         false <- Map.has_key?(state.attempts, key),
         true <- map_size(state.attempts) < Invocation.limit() do
      {:ok, %{state | attempts: Map.put(state.attempts, key, expected["capture_attempt_id"])}}
    else
      _ -> @error
    end
  end

  defp attempt_record(state, %{"type" => type}, _session, _origin)
       when type in ~w(turn_finished cancelled),
       do: {:ok, %{state | closed: true}}

  defp attempt_record(state, _, _, _), do: {:ok, state}

  defp capture_record?(%{"version" => 1} = event, expected) do
    event ===
      expected |> Map.take(~w(type session_id turn_id nomination_sha256)) |> Map.put("version", 1)
  end

  defp capture_record?(%{"version" => 2} = event, expected), do: event === expected
  defp capture_record?(_, _), do: false

  defp attempt_proof(index, %{"version" => 2, "source_proof" => proof}, _turn, _request, text) do
    with true <- proof["quote"] === text,
         {:ok, %{"proof" => ^proof}} <- Session.SourceIndex.revalidate_stored(index, proof),
         do: {:ok, proof},
         else: (_ -> @error)
  end

  # Legacy started records stored no proof or handle. Derive only their stable
  # proof identity from the already committed original, never a live capability.
  defp attempt_proof(index, %{"version" => 1}, turn, request_id, text) do
    with {:ok, request} <- Session.SourceIndex.answer_request(index, turn, request_id, text),
         {:ok, %{"proof" => proof}} <- Session.SourceIndex.resolve_proof(index, request),
         do: {:ok, proof},
         else: (_ -> @error)
  end

  defp attempt_proof(_, _, _, _, _), do: @error

  defp validate_history(events, session, scope, identity, descriptor) do
    Enum.reduce_while(events, {:ok, [], %{}, %{}, MapSet.new()}, fn event,
                                                                    {:ok, prefix, intents,
                                                                     results, seen} ->
      id = event["invocation_id"]

      case event["type"] do
        "extension_invocation_intent" ->
          {:cont, {:ok, [event | prefix], Map.put(intents, id, event), results, seen}}

        "extension_invocation_result" ->
          {:cont, {:ok, [event | prefix], intents, Map.put(results, id, event), seen}}

        "pending_proposal_nominated" ->
          with false <- MapSet.member?(seen, id),
               intent when is_map(intent) <- Map.get(intents, id),
               result when is_map(result) <- Map.get(results, id),
               true <- intent["identity"] === identity and intent["descriptor"] === descriptor,
               true <- follows_result?(prefix, intent, result, session, event["turn_id"]),
               %{"type" => "input_received", "turn_id" => turn} <-
                 Enum.find(prefix, &(&1["type"] in ~w(input_received turn_finished))),
               true <- turn === event["turn_id"],
               {:ok, mode, _} <-
                 Session.PlanningTransition.reconstruct(Enum.reverse(prefix), session),
               {:ok, ^event} <- bind(intent, result, scope, mode, session, event["turn_id"]) do
            {:cont, {:ok, [event | prefix], intents, results, MapSet.put(seen, id)}}
          else
            _ -> {:halt, @error}
          end

        _ ->
          {:cont, {:ok, [event | prefix], intents, results, seen}}
      end
    end)
    |> case do
      {:ok, _, _, _, _} -> :ok
      _ -> @error
    end
  end

  # Offering an observed result to feeds may append bounded feed-delivery
  # intents synchronously. Any other intervening record breaks the live order.
  defp follows_result?(prefix, intent, result, session, turn) do
    follows_inline_result?(prefix, result, session, turn) or
      follows_managed_result?(prefix, intent, result, session, turn)
  end

  defp follows_inline_result?(prefix, result, session, turn) do
    {between, rest} =
      Enum.split_while(prefix, fn event ->
        event["type"] in ~w(extension_feed_delivery_intent draft_extension_intent)
      end)

    feeds = Enum.filter(between, &(&1["type"] == "extension_feed_delivery_intent"))

    length(feeds) <= 8 and
      length(Enum.uniq(Enum.map(feeds, & &1["source"]))) <= 1 and
      Enum.all?(feeds, fn feed ->
        get_in(feed, ["source", "session_id"]) === session and
          Ipse.Journal.source_matches?(feed["source"], result)
      end) and
      feed_pairs?(Enum.reverse(between), session, turn) and match?([^result | _], rest)
  end

  # Managed publication records the raw inline result before its owned current
  # release. Only the exact confirmed chain can nominate; a raw worker result or
  # a withheld/historical projection cannot substitute for current delivery.
  defp follows_managed_result?([cleanup | prefix], intent, result, session, turn) do
    {outcome, prefix} =
      case prefix do
        [%{"type" => "lifecycle_tool_outcome"} = outcome | rest] -> {outcome, rest}
        _ -> {nil, prefix}
      end

    with [message, admission, ^result, release | prior] <- prefix,
         true <-
           Ipse.Session.ManagedOutput.valid_intent?(
             release,
             session,
             intent,
             result["actions_sha256"]
           ),
         true <- Ipse.Session.ManagedOutput.bound_result?(release, result),
         true <- admission["decision"] === "current",
         true <- Ipse.Session.ManagedOutput.valid_admission?(admission, release, result, []),
         true <- message === %{"type" => "message", "message" => Invocation.tool_message(result)},
         true <- cleanup["status"] === "confirmed",
         true <- Ipse.Session.ManagedOutput.valid_cleanup?(cleanup, release, admission),
         true <- lifecycle_result?(outcome, message, intent, session, turn, prior) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp follows_managed_result?(_, _, _, _, _), do: false

  defp lifecycle_result?(nil, _, _, _, _, _), do: true

  defp lifecycle_result?(outcome, message, intent, session, turn, prior) do
    with true <- Session.ToolLifecycle.valid?(outcome),
         true <- outcome["session_id"] === session and outcome["turn_id"] === turn,
         true <- outcome["request_id"] === intent["parent_request_id"],
         true <-
           outcome["status"] === "result_recorded" and outcome["approval"] === "saved_consent",
         true <- outcome["semantic_binding"] === intent["semantic_binding"],
         true <- Ipse.Journal.source_matches?(outcome["result_source"], message),
         [start] <-
           Enum.filter(prior, fn record ->
             record["type"] === "lifecycle_tool_intent" and
               record["tool_id"] === outcome["tool_id"]
           end),
         true <- Session.ToolLifecycle.valid?(start),
         true <- start["session_id"] === session and start["turn_id"] === turn,
         true <- start["request_id"] === intent["parent_request_id"],
         true <- start["semantic_binding"] === intent["semantic_binding"],
         true <- Ipse.Journal.source_matches?(outcome["tool_source"], start) do
      true
    else
      _ -> false
    end
  end

  defp feed_pairs?([], _, _), do: true

  defp feed_pairs?([%{"type" => "draft_extension_intent"} = marker, feed | rest], session, turn) do
    feed["type"] == "extension_feed_delivery_intent" and
      marker ===
        Session.DraftLineage.extension_intent(
          session,
          turn,
          feed,
          marker["possible_source_lineages"]
        ) and feed_pairs?(rest, session, turn)
  end

  defp feed_pairs?([%{"type" => "extension_feed_delivery_intent"} | rest], session, turn),
    do: feed_pairs?(rest, session, turn)

  defp feed_pairs?(_, _, _), do: false

  @doc false
  def arguments?(args) when is_map(args) do
    Enum.sort(Map.keys(args)) == ~w(category reason references text) and
      text?(args["text"], 1024) and text?(args["reason"], 256) and
      args["category"] in @categories and args["references"] === []
  end

  def arguments?(_), do: false

  defp text?(value, max),
    do: is_binary(value) and String.valid?(value) and byte_size(value) in 1..max

  defp id?(value),
    do: is_binary(value) and Regex.match?(~r/\A[a-f0-9]{32}\z/, value)
end
