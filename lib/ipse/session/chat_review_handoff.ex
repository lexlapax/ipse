defmodule Ipse.Session.ChatReviewHandoff do
  @moduledoc "One-use host handoff from a settled chat to protected native review."

  alias Ipse.{JSON, Session}
  alias Ipse.Extension.{Catalog, Invocation, Registry, SemanticAdmission}
  alias Ipse.Journal.Writer
  @slot {__MODULE__, :handoff}
  @error {:error, :chat_review_unavailable}
  @fields ~w(type version handoff_id session_id turn_id request_id client_id client_generation nomination_sha256 capture_intent_sha256 capture_result_sha256 pending_key text category reason source_proof pin)
  @reoffer_fields ~w(type version review_id session_id origin_sha256 origin_source client_id client_generation focus_id render_revision mode)

  defmodule Handle do
    @moduledoc false
    @enforce_keys [:owner, :ref]
    defstruct @enforce_keys

    defimpl Inspect do
      def inspect(_, _), do: "#ChatReviewHandoff<private>"
    end
  end

  # Worker output selects a pending key only. Management must authenticate the
  # signed current value and original source before showing its native card.
  @doc false
  def prepare(s, intent, result) do
    with %{proof: proof} <- Map.get(s, :post_reply_capture),
         %{event: nomination, arguments: arguments} <- Map.get(s, :pending_nomination),
         true <- Session.PendingNomination.arguments?(arguments),
         true <-
           s.phase === :extension_command and s.invocation.parent === intent and
             not s.invocation.interrupted,
         {:ok, entry, descriptor} <-
           Catalog.lookup(s.config, "invoke.command", "ext__knowledge__capture"),
         true <- entry.identity === intent["identity"] and descriptor === intent["descriptor"],
         true <- Registry.live?(entry.identity),
         admission = s.config[:semantic_admission],
         true <- SemanticAdmission.valid?(admission, s.id),
         true <- admission["pin"]["identity_sha256"] === JSON.digest([entry.identity]),
         capture = get_in(intent, ["payload", "arguments"]),
         true <-
           capture["text"] === arguments["text"] and
             capture["category"] === arguments["category"] and
             capture["reason"] === arguments["reason"] and capture["event_at_ms"] === nil,
         {:ok, ^result} <-
           Invocation.build_result(
             intent,
             %{"api_version" => 1, "kind" => "result", "value" => result["value"]},
             s.invocation.results
           ),
         %{"status" => status, "key" => "pending." <> key} <- result["value"],
         true <- status in ["saved", "existing"] and JSON.sha256?(key),
         {:ok, %{"proof" => ^proof}} <-
           Writer.source_query(s.journal_writer, {:stored_proof, proof}),
         %{client: client, reader: reader, id: channel, generation: generation} <-
           s.operator_channel,
         true <- Process.alive?(client) and Process.alive?(reader) do
      event = %{
        "type" => "pending_chat_review_handoff",
        "version" => 1,
        "handoff_id" => Ipse.Usage.id(),
        "session_id" => s.id,
        "turn_id" => s.turn_id,
        "request_id" => s.last_request_id,
        "client_id" => channel,
        "client_generation" => generation,
        "nomination_sha256" => JSON.digest([nomination]),
        "capture_intent_sha256" => JSON.digest([intent]),
        "capture_result_sha256" => JSON.digest([result]),
        "pending_key" => "pending." <> key,
        "text" => arguments["text"],
        "category" => arguments["category"],
        "reason" => arguments["reason"],
        "source_proof" => proof,
        "pin" => admission["pin"]
      }

      if valid_event?(event), do: {:ok, event}, else: @error
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc false
  def valid_event?(event) do
    is_map(event) and Enum.sort(Map.keys(event)) === Enum.sort(@fields) and
      event["type"] === "pending_chat_review_handoff" and event["version"] === 1 and
      Enum.all?(
        ~w(handoff_id session_id turn_id request_id client_id client_generation),
        fn key ->
          is_binary(event[key]) and byte_size(event[key]) == 32 and
            match?({:ok, _}, Base.decode16(event[key], case: :lower))
        end
      ) and
      Enum.all?(
        ~w(nomination_sha256 capture_intent_sha256 capture_result_sha256),
        &JSON.sha256?(event[&1])
      ) and
      match?("pending." <> _, event["pending_key"]) and
      JSON.sha256?(String.replace_prefix(event["pending_key"], "pending.", "")) and
      Session.PendingNomination.arguments?(
        Map.put(Map.take(event, ~w(text category reason)), "references", [])
      ) and
      match?({:ok, _}, Ipse.Extension.ManagedRecipe.source_identity(event["source_proof"])) and
      Ipse.Extension.SemanticConsent.pin?(event["pin"]) and
      event["pin"]["session_id"] === event["session_id"] and
      event["source_proof"]["session_id"] === event["session_id"] and
      event["source_proof"]["quote"] === event["text"] and
      event["source_proof"]["kind"] === "answer.original" and
      event["source_proof"]["origin"] === "assistant_proposal"
  rescue
    _ -> false
  end

  @doc false
  def valid?(%{"event" => event, "source" => source} = binding) do
    valid_event?(event) and
      Ipse.Journal.valid_source?(source) and source["session_id"] === event["session_id"] and
      source["record_sha256"] === JSON.digest([event]) and
      case Enum.sort(Map.keys(binding)) do
        ~w(event source) ->
          true

        ~w(event review review_source source version) ->
          binding["version"] === 2 and valid_reoffer?(binding["review"], origin(binding)) and
            get_in(binding, ["review_source", "session_id"]) === event["session_id"] and
            get_in(binding, ["review_source", "byte_offset"]) > source["byte_offset"] and
            Ipse.Journal.source_matches?(binding["review_source"], binding["review"])

        _ ->
          false
      end
  rescue
    _ -> false
  end

  def valid?(_), do: false

  @doc false
  def origin(binding), do: Map.take(binding, ~w(event source))

  @doc false
  def client_id(binding),
    do:
      if(binding["version"] === 2,
        do: binding["review"]["client_id"],
        else: binding["event"]["client_id"]
      )

  @doc false
  def client_generation(binding),
    do:
      if(binding["version"] === 2,
        do: binding["review"]["client_generation"],
        else: binding["event"]["client_generation"]
      )

  @doc false
  def reoffer_choices(records) do
    for %{"type" => "pending_chat_review_handoff"} = event <- records,
        valid_event?(event),
        do: %{key: event["pending_key"], sha256: JSON.digest([event])}
  end

  @doc false
  def render_revision(binding),
    do: if(binding["version"] === 2, do: binding["review"]["render_revision"], else: 1)

  @doc false
  def reoffer(binding, client, generation, focus, revision, mode) do
    original = origin(binding)

    event = %{
      "type" => "pending_chat_review_reoffered",
      "version" => 1,
      "review_id" => Ipse.Usage.id(),
      "session_id" => original["event"]["session_id"],
      "origin_sha256" => JSON.digest([original]),
      "origin_source" => original["source"],
      "client_id" => client,
      "client_generation" => generation,
      "focus_id" => focus,
      "render_revision" => revision,
      "mode" => mode
    }

    if valid_reoffer?(event, original), do: {:ok, event}, else: @error
  rescue
    _ -> @error
  end

  @doc false
  def valid_reoffer?(event, original) do
    valid?(original) and Enum.sort(Map.keys(original)) === ~w(event source) and
      is_map(event) and Enum.sort(Map.keys(event)) === Enum.sort(@reoffer_fields) and
      event["type"] === "pending_chat_review_reoffered" and event["version"] === 1 and
      event["session_id"] === original["event"]["session_id"] and
      event["origin_sha256"] === JSON.digest([original]) and
      event["origin_source"] === original["source"] and
      Enum.all?(~w(review_id client_id client_generation focus_id), &id?(event[&1])) and
      event["client_id"] !== original["event"]["client_id"] and
      event["client_generation"] !== original["event"]["client_generation"] and
      JSON.safe_uint?(event["render_revision"]) and event["render_revision"] >= 2 and
      Ipse.Extension.Mode.nomination(event["mode"]) === :ok
  rescue
    _ -> false
  end

  @doc false
  def wrap_reoffer(original, event, source) do
    binding =
      Map.merge(origin(original), %{"version" => 2, "review" => event, "review_source" => source})

    if valid?(binding), do: {:ok, binding}, else: @error
  end

  defp id?(value),
    do:
      is_binary(value) and byte_size(value) === 32 and
        match?({:ok, _}, Base.decode16(value, case: :lower))

  @doc false
  def operation_id(event), do: binary_part(JSON.digest([event]), 0, 32)

  @doc false
  def matches_facts?(binding, facts) do
    event = binding["event"]

    valid?(binding) and facts["operation_id"] === operation_id(binding) and
      facts["client_id"] === client_id(binding) and facts["session_id"] === nil and
      facts["render_revision"] === render_revision(binding) and
      facts["pending_key"] === event["pending_key"] and facts["text"] === event["text"] and
      facts["assigned_category"] === event["category"] and facts["reason"] === event["reason"] and
      facts["source_proof"] === event["source_proof"] and
      facts["project_id"] === event["pin"]["project_id"] and
      facts["namespace"] === event["pin"]["namespace"] and
      facts["binding_sha256"] === event["pin"]["binding_sha256"] and
      facts["policy_sha256"] === event["pin"]["policy_sha256"] and
      facts["capture_epoch"] === event["pin"]["epoch"]
  rescue
    _ -> false
  end

  @doc false
  def verify_history(binding, records) do
    event = binding["event"]
    id = event["session_id"]

    with true <- valid?(binding),
         {:ok, _saved} <- Session.Saved.restore(records, id),
         true <- get_in(hd(records), ["metadata", "semantic_admission", "pin"]) === event["pin"],
         [{^event, handoff_at}] <-
           Enum.filter(Enum.with_index(records), fn {record, _} ->
             record["type"] === "pending_chat_review_handoff" and
               record["handoff_id"] === event["handoff_id"]
           end),
         [{nomination, nomination_at}] <- by_digest(records, event["nomination_sha256"]),
         true <-
           nomination["type"] === "pending_proposal_nominated" and
             nomination["turn_id"] === event["turn_id"],
         [{intent, intent_at}] <- by_digest(records, event["capture_intent_sha256"]),
         [{result, result_at}] <- by_digest(records, event["capture_result_sha256"]),
         true <- nomination_at < intent_at and intent_at < result_at and result_at < handoff_at,
         true <-
           intent["type"] === "extension_invocation_intent" and
             intent["descriptor"]["name"] === "ext__knowledge__capture" and
             intent["payload"]["session_id"] === id and
             intent["payload"]["turn_id"] === event["turn_id"] and
             result["type"] === "extension_invocation_result" and
             result["invocation_id"] === intent["invocation_id"],
         [nomination_intent] <-
           Enum.filter(records, fn record ->
             record["type"] === "extension_invocation_intent" and
               record["invocation_id"] === nomination["invocation_id"]
           end),
         true <-
           nomination_intent["payload"]["arguments"] === %{
             "text" => event["text"],
             "category" => event["category"],
             "reason" => event["reason"],
             "references" => []
           },
         true <-
           result["value"]["status"] in ["saved", "existing"] and
             result["value"]["key"] === event["pending_key"],
         {:ok, historical} <- Session.SourceWindow.restore(Enum.take(records, intent_at), id),
         request = intent["payload"]["arguments"]["source"],
         true <- request["quote"] === event["text"],
         {:ok, [selected]} <-
           Session.SourceIndex.saved_query_provenances(
             historical.index,
             "source.quote",
             request,
             historical.historical_window
           ),
         {:ok, %{"proof" => proof}} <-
           Session.SourceIndex.revalidate_stored(historical.index, event["source_proof"]),
         true <- proof === event["source_proof"],
         item when is_map(item) <- historical.index.entries[proof["occurrence_id"]],
         true <-
           selected === %{
             "occurrence_id" => proof["occurrence_id"],
             "version_id" => proof["version_id"],
             "kind" => "answer.original",
             "origin" => "assistant_proposal",
             "provenance" => item.provenance
           },
         true <-
           item.provenance["turn_id"] === event["turn_id"] and
             item.provenance["request_id"] === event["request_id"] and
             item.provenance["receipt_sha256"] === proof["receipt_sha256"],
         true <-
           intent["payload"]["arguments"] === %{
             "text" => event["text"],
             "category" => event["category"],
             "reason" => event["reason"],
             "event_at_ms" => nil,
             "source" => request
           },
         %{"type" => "turn_finished", "status" => "ok"} <-
           Enum.find(Enum.drop(records, handoff_at + 1), fn record ->
             record["type"] in ~w(turn_finished input_received)
           end),
         :ok <- verify_reoffer_history(binding, records) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp by_digest(records, digest),
    do:
      Enum.filter(Enum.with_index(records), fn {record, _} -> JSON.digest([record]) === digest end)

  @doc false
  def validate_reoffers(records, session \\ nil) do
    if Enum.any?(records, &(&1["type"] === "pending_chat_review_reoffered")) do
      session =
        session || get_in(hd(records), ["metadata", "semantic_admission", "pin", "session_id"])

      with {:ok, timeline} <- Session.PlanningTransition.mode_timeline(records, session) do
        initial = %{
          origins: %{},
          revisions: %{},
          ids: MapSet.new(),
          clients: MapSet.new(),
          focuses: MapSet.new(),
          idle: true
        }

        Enum.reduce_while(records, {:ok, initial, timeline, 0}, fn event,
                                                                   {:ok, state, timeline,
                                                                    position} ->
          {mode, timeline} = Session.PlanningTransition.mode_at(timeline, position)

          case reoffer_record(state, event, session, mode) do
            {:ok, next} -> {:cont, {:ok, next, timeline, position + 1}}
            _ -> {:halt, @error}
          end
        end)
        |> case do
          {:ok, _, _, _} -> :ok
          _ -> @error
        end
      end
    else
      :ok
    end
  rescue
    _ -> @error
  end

  defp reoffer_record(state, %{"type" => "pending_chat_review_handoff"} = event, session, _) do
    if valid_event?(event) and event["session_id"] === session and
         not Map.has_key?(state.origins, JSON.digest([event])) and
         map_size(state.origins) < Invocation.limit(),
       do: {:ok, %{state | origins: Map.put(state.origins, JSON.digest([event]), event)}},
       else: @error
  end

  defp reoffer_record(state, %{"type" => "input_received"}, _, _),
    do: {:ok, %{state | idle: false}}

  defp reoffer_record(state, %{"type" => type}, _, _) when type in ~w(turn_finished cancelled),
    do: {:ok, %{state | idle: true}}

  defp reoffer_record(state, %{"type" => "pending_chat_review_reoffered"} = event, session, mode) do
    with true <- state.idle and event["session_id"] === session,
         original when is_map(original) <-
           state.origins[get_in(event, ["origin_source", "record_sha256"])],
         binding = %{"event" => original, "source" => event["origin_source"]},
         true <- valid_reoffer?(event, binding),
         true <- event["mode"] === mode,
         true <- MapSet.size(state.ids) < Invocation.limit(),
         true <-
           event["render_revision"] === Map.get(state.revisions, event["origin_sha256"], 1) + 1,
         false <- MapSet.member?(state.ids, event["review_id"]),
         false <- MapSet.member?(state.clients, {event["client_id"], event["client_generation"]}),
         false <- MapSet.member?(state.focuses, event["focus_id"]) do
      {:ok,
       %{
         state
         | revisions: Map.put(state.revisions, event["origin_sha256"], event["render_revision"]),
           ids: MapSet.put(state.ids, event["review_id"]),
           clients: MapSet.put(state.clients, {event["client_id"], event["client_generation"]}),
           focuses: MapSet.put(state.focuses, event["focus_id"])
       }}
    else
      _ -> @error
    end
  end

  defp reoffer_record(state, _, _, _), do: {:ok, state}

  defp verify_reoffer_history(%{"version" => 2, "review" => review} = binding, records) do
    with :ok <- validate_reoffers(records, binding["event"]["session_id"]),
         [^review] <-
           Enum.filter(
             records,
             &(&1["type"] === "pending_chat_review_reoffered" and
                 &1["review_id"] === review["review_id"])
           ) do
      :ok
    else
      _ -> @error
    end
  end

  defp verify_reoffer_history(_, _), do: :ok

  @doc false
  def current_review?(binding, records) do
    selected = if binding["version"] === 2, do: binding["review"], else: binding["event"]

    with true <- valid?(binding),
         [position] <-
           Enum.flat_map(Enum.with_index(records), fn {record, index} ->
             if record === selected, do: [index], else: []
           end) do
      not Enum.any?(Enum.drop(records, position + 1), fn record ->
        record["type"] in ~w(input_received cancelled source_window_opened execution_mode_resumed planning_entry_observed planning_exited) or
          (record["type"] === "pending_chat_review_reoffered" and
             record["origin_sha256"] === JSON.digest([origin(binding)]))
      end)
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc false
  def load_reoffer_history(directory, session, policy \\ nil) do
    with {:ok, records} <- Ipse.Journal.load(directory, session, policy),
         {:ok, _} <- Session.Saved.restore(records, session),
         {:ok, rows} <- history_rows(directory, session, 0, length(records), []),
         true <- Enum.map(rows, & &1.record) === records do
      originals =
        for %{record: %{"type" => "pending_chat_review_handoff"} = event, source: source} <- rows,
            do: %{"event" => event, "source" => source}

      originals_by_sha = Map.new(originals, &{JSON.digest([&1]), &1})

      reviews =
        Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, found} ->
          if row.record["type"] === "pending_chat_review_reoffered" do
            with original when is_map(original) <- originals_by_sha[row.record["origin_sha256"]],
                 {:ok, wrapper} <- wrap_reoffer(original, row.record, row.source) do
              {:cont, {:ok, [wrapper | found]}}
            else
              _ -> {:halt, @error}
            end
          else
            {:cont, {:ok, found}}
          end
        end)

      with true <- Enum.all?(originals, &valid?/1),
           {:ok, reviews} <- reviews,
           :ok <- Session.SourceWindow.validate_sources(directory, session, records) do
        {:ok, %{records: records, originals: originals, reviews: Enum.reverse(reviews)}}
      else
        _ -> @error
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp history_rows(_directory, _session, nil, 0, rows), do: {:ok, Enum.reverse(rows)}

  defp history_rows(directory, session, cursor, 0, rows) when is_integer(cursor) do
    case Ipse.Journal.source_page(directory, session, cursor, 1) do
      {:ok, %{records: [], next: nil}} -> {:ok, Enum.reverse(rows)}
      _ -> @error
    end
  end

  defp history_rows(directory, session, cursor, remaining, rows)
       when is_integer(cursor) and remaining > 0 do
    with {:ok, page} <- Ipse.Journal.source_page(directory, session, cursor, min(remaining, 64)),
         true <- page.records !== [] and length(page.records) <= remaining do
      history_rows(
        directory,
        session,
        page.next,
        remaining - length(page.records),
        Enum.reduce(page.records, rows, &[&1 | &2])
      )
    else
      _ -> @error
    end
  end

  defp history_rows(_, _, _, _, _), do: @error

  @doc false
  def verify_source(binding, directory, records \\ nil) do
    with true <- valid?(binding),
         %{"event" => event, "source" => source} <- binding,
         {:ok, %{records: [%{source: ^source, record: ^event}]}} <-
           Ipse.Journal.source_page(directory, event["session_id"], source["byte_offset"], 1),
         {:ok, records} <-
           if(is_list(records),
             do: {:ok, records},
             else: Ipse.Journal.load(directory, event["session_id"])
           ),
         :ok <- verify_history(binding, records),
         :ok <- verify_review_source(binding, directory),
         :ok <- Session.SourceWindow.validate_sources(directory, event["session_id"], records) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp verify_review_source(
         %{"version" => 2, "review" => review, "review_source" => source},
         directory
       ) do
    case Ipse.Journal.source_page(directory, review["session_id"], source["byte_offset"], 1) do
      {:ok, %{records: [%{source: ^source, record: ^review}]}} -> :ok
      _ -> @error
    end
  end

  defp verify_review_source(_, _), do: :ok

  @doc false
  def verify_originals(context, id, records \\ nil) do
    context
    |> Map.get(:chat_review_handoffs, [])
    |> Enum.filter(&(get_in(&1, ["event", "session_id"]) === id))
    |> Enum.reduce_while(:ok, fn binding, :ok ->
      case verify_source(binding, context.history_dir, records) do
        :ok -> {:cont, :ok}
        _ -> {:halt, @error}
      end
    end)
  end

  @doc false
  def validate_management(records) do
    case get_in(List.first(records) || %{}, ["metadata", "chat_review_handoff"]) do
      nil ->
        :ok

      event ->
        accepted = Enum.filter(records, &(&1["type"] === "pending_proposal_accepted"))

        if valid?(event) and Enum.all?(accepted, &matches_facts?(event, &1["facts"])),
          do: :ok,
          else: @error
    end
  rescue
    _ -> @error
  end

  @doc false
  def take(session, token) when is_pid(session) and is_reference(token) do
    with nil <- Process.get(@slot),
         {:ok, event, mode} <- Session.claim_chat_review(session, token),
         true <- valid?(event),
         :ok <- Ipse.Extension.Mode.nomination(mode) do
      ref = make_ref()
      Process.put(@slot, %{ref: ref, session: session, event: event, mode: mode, state: :claimed})
      {:ok, %Handle{owner: self(), ref: ref}}
    else
      _ -> @error
    end
  catch
    :exit, _ -> {:unknown, :chat_review_unconfirmed}
  end

  def take(_, _), do: @error

  @doc false
  def runtime_config(%Handle{owner: owner, ref: ref}, config) when owner == self() do
    with %{ref: ^ref, mode: mode, state: state} <- Process.get(@slot),
         true <- state in [:claimed, :closed] do
      project_config(config, mode)
    else
      _ -> @error
    end
  end

  def runtime_config(_, _), do: @error

  defp project_config(config, mode) when is_map(config) do
    with :ok <- Ipse.Extension.Mode.nomination(mode),
         values = Ipse.Extension.Mode.config(mode),
         projected =
           config
           |> Map.merge(%{values | approval: String.to_existing_atom(values.approval)})
           |> Map.put(:accept_edits, false)
           |> Map.put(:planning_cli_start, false),
         {:ok, ^mode} <- Ipse.Extension.Mode.capture(projected) do
      {:ok, projected}
    else
      _ -> @error
    end
  end

  defp project_config(_, _), do: @error

  @doc false
  def claim_management_attempt(event) do
    case Process.get(@slot) do
      %{state: :attempted, event: ^event} = state ->
        Process.put(@slot, %{state | state: :management_spent})
        :ok

      _ ->
        @error
    end
  end

  @doc false
  def close(%Handle{owner: owner, ref: ref}) when owner == self() do
    with %{ref: ^ref, session: session, state: :claimed} = state <- Process.get(@slot) do
      Process.put(@slot, %{state | state: :close_attempted})

      case Session.close_confirmed(session) do
        :ok ->
          Process.put(@slot, %{state | state: :closed})
          :ok

        _ ->
          {:unknown, :chat_review_close_unconfirmed}
      end
    else
      _ -> @error
    end
  catch
    :exit, _ -> {:unknown, :chat_review_close_unconfirmed}
  end

  def close(_), do: @error

  @doc false
  def review(%Handle{owner: owner, ref: ref}, config, cwd, history_dir) when owner == self() do
    with %{ref: ^ref, event: event, mode: mode, state: :closed} = state <- Process.get(@slot),
         {:ok, config} <- project_config(config, mode) do
      Process.put(@slot, %{state | state: :attempted})
      Ipse.CLI.Knowledge.Management.accept_chat_candidate(config, cwd, history_dir, event)
    else
      _ -> @error
    end
  rescue
    _ -> {:unknown, :chat_review_unconfirmed}
  catch
    _, _ -> {:unknown, :chat_review_unconfirmed}
  after
    case Process.get(@slot) do
      %{ref: ^ref} -> Process.delete(@slot)
      _ -> :ok
    end
  end

  def review(_, _, _, _), do: @error
end
