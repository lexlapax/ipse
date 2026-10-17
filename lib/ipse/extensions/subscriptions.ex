defmodule Ipse.Extensions.Subscriptions do
  @moduledoc "Inert prompt/answer subscriptions and pure no-replay delivery receipts."
  alias Ipse.Journal
  alias Ipse.Extensions.{Identity, Manifest, EventJob, Catalog}
  alias Ipse.Lifecycle.{Source, Event, Answer}
  @error {:error, :invalid_extension_subscription}
  @types ~w(extension_event_intent extension_event_result)
  @views %{
    "prompt.received" => ~w(metadata prompt.original),
    "prompt.effective_committed" => ~w(metadata prompt.effective),
    "answer.committed" => ~w(metadata answer.original answer.presented)
  }
  def types, do: @types

  def summary(events) do
    outcomes =
      for %{"type" => "extension_event_result", "outcome" => outcome} <- events, do: outcome

    admitted = Enum.count(events, &(&1["type"] == "extension_event_intent"))

    Map.new(
      ~w(acknowledged completed failed unknown not_started),
      &{&1, Enum.count(outcomes, fn outcome -> outcome == &1 end)}
    )
    |> Map.merge(%{"admitted" => admitted, "incomplete" => admitted - length(outcomes)})
  end

  def digest(declarations),
    do: Ipse.Compaction.digest([Enum.sort_by(declarations || [], & &1["id"])])

  def validate(declarations, capabilities) do
    declarations = declarations || []

    with true <- is_list(declarations) and length(declarations) <= 4,
         true <- Enum.all?(declarations, &declaration?/1),
         true <- length(declarations) == length(Enum.uniq_by(declarations, & &1["id"])),
         true <-
           Enum.any?(declarations, &(&1["mode"] == "notify")) == "event.notify" in capabilities,
         true <- Enum.any?(declarations, &(&1["mode"] == "job")) == "event.job" in capabilities,
         true <- Enum.any?(declarations, &(&1["mode"] == "feed")) == "event.feed" in capabilities,
         true <-
           not Enum.any?(
             declarations,
             &(&1["mode"] == "feed" and
                 &1["event"] in ~w(tool.intent_committed tool.outcome_recorded tool.recording_stopped))
           ) or "lifecycle.tools" in capabilities,
         true <-
           not Enum.any?(
             declarations,
             &(&1["mode"] == "feed" and
                 &1["event"] in ~w(wait.started wait.finished session.recording_stopped))
           ) or "lifecycle.record" in capabilities,
         true <-
           Enum.all?(
             [
               {"prompt.original", "event.prompt.original"},
               {"prompt.effective", "event.prompt.effective"},
               {"answer.original", "event.answer.original"},
               {"answer.presented", "event.answer.presented"},
               {"tool.input", "event.tool.input"},
               {"tool.result", "event.tool.result"}
             ],
             fn {view, capability} ->
               Enum.any?(declarations, &(&1["view"] == view)) == capability in capabilities
             end
           ) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def declarations(config) do
    for schedule <- ~w(before_request after_turn),
        event <- ~w(prompt.received prompt.effective_committed answer.committed),
        entry <- Map.get(config, :extensions, []),
        declaration <- Enum.sort_by(entry.subscriptions, & &1["id"]),
        declaration["mode"] in ~w(notify job),
        declaration["event"] == event,
        EventJob.schedule(declaration) == schedule,
        do: %{instance: entry.identity["instance"], declaration: declaration}
  end

  def declarations(config, schedule),
    do: Enum.filter(declarations(config), &(EventJob.schedule(&1.declaration) == schedule))

  def all_declarations(config),
    do: declarations(config) ++ Ipse.Extensions.Feeds.declarations(config)

  def validate_handlers(declarations, exports) do
    exports = Catalog.normalize(exports)

    if Enum.all?(declarations || [], fn declaration ->
         declaration["mode"] != "job" or
           Enum.any?(exports["jobs"], &(&1["id"] == declaration["handler"]))
       end) do
      :ok
    else
      @error
    end
  rescue
    _ -> @error
  end

  def snapshot(config),
    do: %{
      "version" => 1,
      "entries" =>
        Enum.map(
          all_declarations(config),
          &%{"instance" => &1.instance, "declaration" => &1.declaration}
        )
    }

  def received(turn, text),
    do: %{
      "type" => "lifecycle_prompt_received",
      "version" => 1,
      "turn_id" => turn,
      "original" => text,
      "original_sha256" => Manifest.sha256(text)
    }

  def committed(turn, text, message, received_source),
    do: %{
      "type" => "lifecycle_prompt_committed",
      "version" => 1,
      "turn_id" => turn,
      "text" => text,
      "text_sha256" => Manifest.sha256(text),
      "message_sha256" => Ipse.Compaction.digest([message]),
      "received_source" => received_source
    }

  def valid_received?(record),
    do:
      keys?(record, ~w(type version turn_id original original_sha256)) and
        record["type"] == "lifecycle_prompt_received" and record["version"] === 1 and
        id?(record["turn_id"]) and text?(record["original"]) and
        record["original_sha256"] == Manifest.sha256(record["original"])

  def valid_committed?(record),
    do:
      keys?(record, ~w(type version turn_id text text_sha256 message_sha256 received_source)) and
        record["type"] == "lifecycle_prompt_committed" and record["version"] === 1 and
        id?(record["turn_id"]) and text?(record["text"]) and
        record["text_sha256"] == Manifest.sha256(record["text"]) and
        hash?(record["message_sha256"]) and
        Source.valid?(record["received_source"])

  def intent(identity, declaration, source, record, turn) do
    base = %{
      "type" => "extension_event_intent",
      "version" => 1,
      "delivery_id" => Ipse.Usage.id(),
      "identity" => identity,
      "declaration" => declaration,
      "source" => source,
      "turn_id" => turn
    }

    payload = payload(base, record)
    {Map.put(base, "payload_sha256", if(payload, do: Ipse.Compaction.digest([payload]))), payload}
  end

  def payload(intent, record) do
    with {:ok, event} <- Event.project(intent["source"], record, intent["declaration"]["view"]),
         true <- event["type"] == intent["declaration"]["event"],
         payload = %{
           "api_version" => 1,
           "delivery_id" => intent["delivery_id"],
           "subscription_id" => intent["declaration"]["id"],
           "turn_id" => intent["turn_id"],
           "event" => event
         },
         :ok <- Ipse.Extension.validate(payload) do
      payload
    else
      _ -> nil
    end
  end

  def result(intent, outcome, cleanup),
    do: %{
      "type" => "extension_event_result",
      "version" => 1,
      "delivery_id" => intent["delivery_id"],
      "intent_sha256" => Ipse.Compaction.digest([intent]),
      "outcome" => outcome,
      "cleanup_confirmed" => cleanup
    }

  def valid_result?(event, intent),
    do:
      event == result(intent, event["outcome"], event["cleanup_confirmed"]) and
        event["outcome"] in if(intent["declaration"]["mode"] == "job",
          do: ~w(completed failed unknown not_started),
          else: ~w(acknowledged unknown not_started)
        ) and
        is_boolean(event["cleanup_confirmed"]) and
        (event["outcome"] == "unknown" or event["cleanup_confirmed"] == true) and
        (intent["payload_sha256"] != nil or event["outcome"] == "not_started")

  def validate_sources(directory, session, events) do
    events
    |> Enum.flat_map(fn event ->
      case event["type"] do
        "extension_event_intent" ->
          [event["source"]]

        "lifecycle_prompt_committed" ->
          [event["received_source"]]

        "lifecycle_answer_committed" ->
          [event["effective_source"]]

        "lifecycle_question_sources" ->
          [event["received_source"], event["effective_source"]]

        "extension_invocation_intent" ->
          if(event["event_trigger"], do: Map.values(event["event_trigger"]["sources"]), else: [])

        _ ->
          []
      end
    end)
    |> Enum.uniq()
    |> Enum.reduce_while(:ok, fn source, :ok ->
      with true <- Source.valid?(source) and source["session_id"] == session,
           {:ok, %{records: [%{source: actual}]}} <-
             Journal.source_page(directory, session, source["byte_offset"], 1),
           true <- actual == source do
        {:cont, :ok}
      else
        _ -> {:halt, @error}
      end
    end)
    |> case do
      :ok ->
        with :ok <- Ipse.Extensions.History.validate_sources(directory, session, events),
             :ok <- Ipse.Lifecycle.Runtime.validate_sources(directory, session, events),
             :ok <- Ipse.Lifecycle.Tool.validate_sources(directory, session, events),
             do: Ipse.Extensions.Feeds.validate_sources(directory, session, events)

      error ->
        error
    end
  rescue
    _ -> @error
  end

  def validate_events([%{"metadata" => metadata} | _] = events) do
    with {:ok, declarations, identities} <- metadata(metadata) do
      initial = %{
        received: nil,
        marker: nil,
        last: nil,
        active: nil,
        seen: MapSet.new(),
        turns: MapSet.new(),
        bound: %{},
        session: nil,
        count: 0,
        job: nil,
        job_completed: false,
        job_actions: [],
        unsafe: false,
        settling: false,
        request: nil,
        presentation: nil,
        answer: nil,
        assistant_request: nil,
        previous: nil
      }

      Enum.reduce_while(events, {:ok, initial}, fn event, {:ok, state} ->
        case reduce(event, state, declarations, identities) do
          {:ok, next} -> {:cont, {:ok, %{next | previous: event}}}
          _ -> {:halt, @error}
        end
      end)
      |> case do
        {:ok, _} -> :ok
        error -> error
      end
    end
  rescue
    _ -> @error
  end

  def validate_events(_), do: @error

  def question_sources(turn, question, received, effective),
    do: %{
      "type" => "lifecycle_question_sources",
      "version" => 1,
      "turn_id" => turn,
      "question_id" => question,
      "received_source" => received,
      "effective_source" => effective
    }

  def restore_question(nil, _, _, _, _), do: {:ok, nil}
  def restore_question(_, context, _, _, _) when context != nil, do: {:ok, context}

  def restore_question(
        %{kind: :extension, parent: %{"descriptor" => %{"stage" => stage}}},
        nil,
        _,
        _,
        _
      )
      when stage != "invoke.tool" do
    {:ok, nil}
  end

  def restore_question(question, nil, directory, session, events) do
    selected =
      (get_in(hd(events), ["metadata", "extension_subscriptions", "entries"]) || [])
      |> Enum.reject(&(&1["declaration"]["mode"] == "feed"))

    if selected == [] do
      {:ok, nil}
    else
      with {_, index} <-
             events
             |> Enum.with_index()
             |> Enum.reverse()
             |> Enum.find(fn {event, _} -> question_id(event) == question.id end),
           checkpoint when is_map(checkpoint) <- Enum.at(events, index + 1),
           true <-
             checkpoint["type"] == "lifecycle_question_sources" and
               checkpoint["question_id"] == question.id,
           {:ok, received} <- resolve_fact(directory, session, checkpoint["received_source"]),
           {:ok, effective} <- resolve_fact(directory, session, checkpoint["effective_source"]),
           true <- valid_received?(received.record) and valid_committed?(effective.record),
           true <-
             effective.record["received_source"] == received.source and
               effective.record["turn_id"] == checkpoint["turn_id"] and
               received.record["turn_id"] == checkpoint["turn_id"] do
        {:ok,
         %{
           received: received,
           effective: effective,
           answer: nil,
           intent: nil,
           turn: checkpoint["turn_id"],
           schedule: "before_request"
         }}
      else
        _ -> {:error, :invalid_lifecycle_question_checkpoint}
      end
    end
  rescue
    _ -> {:error, :invalid_lifecycle_question_checkpoint}
  end

  defp resolve_fact(directory, session, source) do
    with true <- Source.valid?(source) and source["session_id"] == session,
         {:ok, %{records: [fact]}} <-
           Journal.source_page(directory, session, source["byte_offset"], 1),
         true <- fact.source == source do
      {:ok, fact}
    else
      _ -> @error
    end
  end

  defp question_id(%{"type" => "operator_question", "id" => id}), do: id
  defp question_id(%{"type" => "extension_question", "operation_id" => id}), do: id
  defp question_id(_), do: nil

  defp metadata(metadata) do
    identities = Map.new(Map.get(metadata, "extensions", []), &{&1["instance"], &1})
    snapshot = Map.get(metadata, "extension_subscriptions", %{"version" => 1, "entries" => []})

    with true <- keys?(snapshot, ~w(version entries)) and snapshot["version"] === 1,
         true <- is_list(snapshot["entries"]) and length(snapshot["entries"]) <= 8,
         true <-
           Enum.all?(snapshot["entries"], fn row ->
             keys?(row, ~w(instance declaration)) and identities[row["instance"]] != nil and
               declaration?(row["declaration"])
           end),
         true <-
           length(snapshot["entries"]) ==
             length(Enum.uniq_by(snapshot["entries"], &{&1["instance"], &1["declaration"]["id"]})),
         true <-
           snapshot["entries"] ==
             Enum.sort_by(snapshot["entries"], fn row ->
               {cond do
                  row["declaration"]["mode"] == "feed" -> 2
                  EventJob.schedule(row["declaration"]) == "before_request" -> 0
                  true -> 1
                end,
                Enum.find_index(
                  ~w(prompt.received prompt.effective_committed answer.committed),
                  &(&1 == row["declaration"]["event"])
                ), identities[row["instance"]]["order"], row["instance"],
                row["declaration"]["id"]}
             end),
         true <-
           Enum.all?(identities, fn {instance, identity} ->
             records =
               for row <- snapshot["entries"], row["instance"] == instance, do: row["declaration"]

             Identity.valid?(identity) and validate(records, identity["capabilities"]) == :ok and
               digest(records) == identity["subscriptions_sha256"]
           end),
         {:ok, catalog} <- Catalog.from_metadata(metadata),
         true <-
           Enum.all?(snapshot["entries"], fn row ->
             row["declaration"]["mode"] != "job" or
               Enum.any?(
                 catalog["entries"],
                 &(&1["stage"] == "event.job" and &1["instance"] == row["instance"] and
                     &1["id"] == row["declaration"]["handler"])
               )
           end) do
      {:ok, Enum.reject(snapshot["entries"], &(&1["declaration"]["mode"] == "feed")), identities}
    else
      _ -> @error
    end
  end

  defp reduce(%{"type" => "lifecycle_prompt_received"} = event, s, declarations, _) do
    if declarations != [] and valid_received?(event) and
         not MapSet.member?(s.turns, event["turn_id"]) do
      {:ok,
       %{
         s
         | received: event,
           marker: nil,
           active: nil,
           bound: %{},
           job: nil,
           job_completed: false,
           job_actions: [],
           unsafe: false,
           settling: false,
           request: nil,
           presentation: nil,
           answer: nil,
           assistant_request: nil,
           turns: MapSet.put(s.turns, event["turn_id"])
       }}
    else
      @error
    end
  end

  defp reduce(%{"type" => "lifecycle_prompt_committed"} = event, s, _, _) do
    if valid_committed?(event) and s.received != nil and s.marker == nil and
         event["turn_id"] == s.received["turn_id"] and
         Source.matches?(event["received_source"], s.received) and
         is_map(s.last) and s.last["role"] == "user" and s.last["content"] == event["text"] and
         Ipse.Compaction.digest([s.last]) == event["message_sha256"] do
      {:ok, %{s | marker: event, session: event["received_source"]["session_id"]}}
    else
      @error
    end
  end

  defp reduce(%{"type" => "message", "message" => message} = event, s, _, _),
    do:
      {:ok,
       %{
         s
         | last: message,
           assistant_request:
             if(message["role"] == "assistant",
               do: event["request_id"],
               else: s.assistant_request
             )
       }}

  defp reduce(%{"type" => "lifecycle_answer_committed"} = event, s, declarations, _) do
    final = s.presentation || s.last["content"]

    if Enum.any?(declarations, &(&1["declaration"]["event"] == "answer.committed")) and
         s.settling and s.answer == nil and s.active == nil and Answer.valid?(event) and
         event["turn_id"] == s.marker["turn_id"] and event["request_id"] == s.assistant_request and
         Source.matches?(event["effective_source"], s.marker) and s.last["role"] == "assistant" and
         s.last["tool_calls"] in [nil, []] and
         Answer.build(
           event["turn_id"],
           s.assistant_request,
           s.last,
           final,
           event["effective_source"]
         ) == event do
      {:ok, %{s | answer: event}}
    else
      @error
    end
  end

  defp reduce(%{"type" => "lifecycle_question_sources"} = event, s, _, _) do
    if keys?(event, ~w(type version turn_id question_id received_source effective_source)) and
         event["version"] === 1 and s.marker != nil and s.active == nil and not s.settling and
         question_id(s.previous) == event["question_id"] and is_binary(event["question_id"]) and
         byte_size(event["question_id"]) in 1..256 and String.valid?(event["question_id"]) and
         event["turn_id"] == s.marker["turn_id"] and
         event["received_source"] == s.marker["received_source"] and
         Source.matches?(event["effective_source"], s.marker) and
         event["effective_source"]["session_id"] == s.session do
      {:ok, s}
    else
      @error
    end
  end

  defp reduce(
         %{"type" => "extension_transform_result", "stage" => "transform.prompt"} = event,
         s,
         _,
         _
       ),
       do: {:ok, %{s | last: Map.put(s.last, "content", event["output"])}}

  defp reduce(%{"type" => "extension_event_intent"} = event, s, declarations, identities) do
    identity = event["identity"]
    declaration = event["declaration"]
    key = {identity["instance"], declaration["id"]}

    record =
      case declaration["event"] do
        "prompt.received" -> s.received
        "prompt.effective_committed" -> s.marker
        "answer.committed" -> s.answer
      end

    expected_payload = if record, do: payload(event, record)

    with true <-
           keys?(
             event,
             ~w(type version delivery_id identity declaration source turn_id payload_sha256)
           ),
         true <-
           event["version"] === 1 and id?(event["delivery_id"]) and s.active == nil and
             s.marker != nil and not s.unsafe,
         true <- EventJob.schedule(declaration) == "after_turn" == s.settling,
         true <- identities[identity["instance"]] == identity,
         true <-
           Enum.at(declarations, map_size(s.bound)) == %{
             "instance" => identity["instance"],
             "declaration" => declaration
           },
         true <-
           Enum.member?(declarations, %{
             "instance" => identity["instance"],
             "declaration" => declaration
           }),
         true <-
           not MapSet.member?(s.seen, event["delivery_id"]) and not Map.has_key?(s.bound, key) and
             s.count < 10_000,
         true <-
           event["turn_id"] == s.marker["turn_id"] and Source.matches?(event["source"], record),
         true <- event["source"]["session_id"] == s.session,
         true <-
           declaration["event"] != "prompt.received" or
             event["source"] == s.marker["received_source"],
         true <-
           event["payload_sha256"] ==
             if(expected_payload, do: Ipse.Compaction.digest([expected_payload])) do
      {:ok,
       %{
         s
         | active: event,
           seen: MapSet.put(s.seen, event["delivery_id"]),
           count: s.count + 1,
           job: nil,
           job_completed: false,
           job_actions: []
       }}
    else
      _ -> @error
    end
  end

  defp reduce(%{"type" => "extension_event_result"} = event, s, _, _) do
    with intent when is_map(intent) <- s.active,
         true <- valid_result?(event, intent),
         true <- event["outcome"] not in ~w(completed failed) or s.job_completed,
         true <-
           event["outcome"] not in ~w(completed failed) or
             event["outcome"] == EventJob.outcome(s.job_actions),
         true <- event["outcome"] != "not_started" or s.job == nil do
      key = {intent["identity"]["instance"], intent["declaration"]["id"]}

      {:ok,
       %{
         s
         | active: nil,
           bound: Map.put(s.bound, key, event["outcome"]),
           job: nil,
           job_completed: false,
           unsafe:
             s.unsafe or
               (intent["declaration"]["mode"] == "job" and event["outcome"] == "unknown")
       }}
    else
      _ -> @error
    end
  end

  defp reduce(%{"type" => "request_admitted", "kind" => "model"} = event, s, declarations, _) do
    if declarations == [] or
         (s.marker != nil and s.marker["turn_id"] == event["turn_id"] and
            s.session == event["session_id"] and s.active == nil and not s.unsafe and
            not s.settling and
            Enum.all?(
              Enum.filter(
                declarations,
                &(EventJob.schedule(&1["declaration"]) == "before_request")
              ),
              fn row ->
                outcome = s.bound[{row["instance"], row["declaration"]["id"]}]

                outcome != nil and
                  (not row["declaration"]["required"] or
                     outcome ==
                       if(row["declaration"]["mode"] == "job",
                         do: "completed",
                         else: "acknowledged"
                       ))
              end
            )) do
      {:ok, %{s | request: event["request_id"]}}
    else
      @error
    end
  end

  defp reduce(%{"type" => "request_finished", "request_id" => id}, %{request: id} = s, _, _),
    do: {:ok, %{s | request: nil}}

  defp reduce(
         %{
           "type" => "extension_transform_result",
           "stage" => "transform.presentation",
           "output" => output
         },
         s,
         _,
         _
       ),
       do: {:ok, %{s | presentation: output}}

  defp reduce(%{"type" => "lifecycle_turn_settling"} = event, s, _, _) do
    final = s.presentation || s.last["content"]

    if keys?(event, ~w(type version turn_id assistant_sha256 final_sha256)) and
         event["version"] === 1 and s.marker != nil and
         event["turn_id"] == s.marker["turn_id"] and s.last["role"] == "assistant" and
         s.last["tool_calls"] in [nil, []] and
         s.active == nil and not s.unsafe and s.request == nil and not s.settling and
         is_binary(final) and
         event["assistant_sha256"] == Ipse.Compaction.digest([s.last]) and
         event["final_sha256"] == Manifest.sha256(final) do
      {:ok, %{s | settling: true}}
    else
      @error
    end
  end

  defp reduce(%{"type" => "extension_invocation_intent"} = parent, %{active: intent} = s, _, _)
       when intent != nil do
    if s.job == nil and EventJob.matches?(parent, intent, s.received, s.marker, s.answer),
      do: {:ok, %{s | job: parent}},
      else: @error
  end

  defp reduce(%{"type" => "extension_invocation_result"} = result, %{job: parent} = s, _, _)
       when parent != nil do
    if Ipse.Extensions.Invocation.result_intent(result) == parent and not s.job_completed,
      do: {:ok, %{s | job_completed: true}},
      else: @error
  end

  defp reduce(%{"type" => "extension_action_result"} = result, %{job: parent} = s, _, _)
       when parent != nil do
    if result["parent_invocation_id"] == parent["invocation_id"] and length(s.job_actions) < 16,
      do: {:ok, %{s | job_actions: s.job_actions ++ [result]}},
      else: @error
  end

  defp reduce(%{"type" => "turn_finished", "status" => "ok"}, s, declarations, _) do
    if s.active == nil and not s.unsafe and
         (s.marker == nil or
            Enum.all?(declarations, fn row ->
              outcome = s.bound[{row["instance"], row["declaration"]["id"]}]

              outcome != nil and
                (not row["declaration"]["required"] or
                   outcome ==
                     if(row["declaration"]["mode"] == "job",
                       do: "completed",
                       else: "acknowledged"
                     ))
            end)) do
      {:ok, s}
    else
      @error
    end
  end

  defp reduce(%{"type" => type}, s, _, _) when type in ~w(cancelled turn_finished),
    do: {:ok, %{s | active: nil}}

  defp reduce(_, s, _, _), do: {:ok, s}

  defp declaration?(%{"mode" => "feed"} = record), do: Ipse.Extensions.Feeds.declaration?(record)

  defp declaration?(record),
    do:
      keys?(
        record,
        ~w(id event event_version view mode required) ++
          cond do
            record["mode"] == "job" -> ~w(handler schedule)
            record["event"] == "answer.committed" -> ["schedule"]
            true -> []
          end
      ) and
        text?(record["id"]) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,31}\z/, record["id"]) and
        record["event_version"] === 1 and record["mode"] in ~w(notify job) and
        (record["mode"] != "job" or
           (is_binary(record["handler"]) and
              Regex.match?(~r/\A[a-z][a-z0-9_-]{0,31}\z/, record["handler"]) and
              record["schedule"] in ~w(before_request after_turn))) and
        is_boolean(record["required"]) and
        (record["event"] != "answer.committed" or record["schedule"] == "after_turn") and
        record["view"] in Map.get(@views, record["event"], [])

  defp keys?(record, keys), do: is_map(record) and Enum.sort(Map.keys(record)) == Enum.sort(keys)
  defp text?(value), do: is_binary(value) and String.valid?(value)
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
end
