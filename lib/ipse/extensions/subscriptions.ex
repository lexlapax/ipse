defmodule Ipse.Extensions.Subscriptions do
  @moduledoc "Inert prompt subscriptions and pure no-replay delivery receipts."
  alias Ipse.Journal
  alias Ipse.Extensions.{Identity, Manifest}
  alias Ipse.Lifecycle.{Source, Event}
  @error {:error, :invalid_extension_subscription}
  @types ~w(extension_event_intent extension_event_result)
  @views %{
    "prompt.received" => ~w(metadata prompt.original),
    "prompt.effective_committed" => ~w(metadata prompt.effective)
  }
  def types, do: @types

  def digest(declarations),
    do: Ipse.Compaction.digest([Enum.sort_by(declarations || [], & &1["id"])])

  def validate(declarations, capabilities) do
    declarations = declarations || []

    with true <- is_list(declarations) and length(declarations) <= 4,
         true <- Enum.all?(declarations, &declaration?/1),
         true <- length(declarations) == length(Enum.uniq_by(declarations, & &1["id"])),
         true <- declarations != [] == "event.notify" in capabilities,
         true <-
           Enum.all?(
             [
               {"prompt.original", "event.prompt.original"},
               {"prompt.effective", "event.prompt.effective"}
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
    for event <- ~w(prompt.received prompt.effective_committed),
        entry <- Map.get(config, :extensions, []),
        declaration <- Enum.sort_by(entry.subscriptions, & &1["id"]),
        declaration["event"] == event,
        do: %{instance: entry.identity["instance"], declaration: declaration}
  end

  def snapshot(config),
    do: %{
      "version" => 1,
      "entries" =>
        Enum.map(
          declarations(config),
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
        event["outcome"] in ~w(acknowledged unknown not_started) and
        is_boolean(event["cleanup_confirmed"]) and
        (event["outcome"] == "unknown" or event["cleanup_confirmed"] == true) and
        (intent["payload_sha256"] != nil or event["outcome"] == "not_started")

  def validate_sources(directory, session, events) do
    events
    |> Enum.filter(
      &(&1["type"] == "extension_event_intent" or &1["type"] == "lifecycle_prompt_committed")
    )
    |> Enum.map(fn event ->
      if event["type"] == "extension_event_intent",
        do: event["source"],
        else: event["received_source"]
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
        count: 0
      }

      Enum.reduce_while(events, {:ok, initial}, fn event, {:ok, state} ->
        case reduce(event, state, declarations, identities) do
          {:ok, next} -> {:cont, {:ok, next}}
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
               {if(row["declaration"]["event"] == "prompt.received", do: 0, else: 1),
                identities[row["instance"]]["order"], row["instance"], row["declaration"]["id"]}
             end),
         true <-
           Enum.all?(identities, fn {instance, identity} ->
             records =
               for row <- snapshot["entries"], row["instance"] == instance, do: row["declaration"]

             Identity.valid?(identity) and validate(records, identity["capabilities"]) == :ok and
               digest(records) == identity["subscriptions_sha256"]
           end) do
      {:ok, snapshot["entries"], identities}
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

  defp reduce(%{"type" => "message", "message" => message}, s, _, _),
    do: {:ok, %{s | last: message}}

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
    record = if declaration["event"] == "prompt.received", do: s.received, else: s.marker
    expected_payload = if record, do: payload(event, record)

    with true <-
           keys?(
             event,
             ~w(type version delivery_id identity declaration source turn_id payload_sha256)
           ),
         true <-
           event["version"] === 1 and id?(event["delivery_id"]) and s.active == nil and
             s.marker != nil,
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
       %{s | active: event, seen: MapSet.put(s.seen, event["delivery_id"]), count: s.count + 1}}
    else
      _ -> @error
    end
  end

  defp reduce(%{"type" => "extension_event_result"} = event, s, _, _) do
    with intent when is_map(intent) <- s.active, true <- valid_result?(event, intent) do
      key = {intent["identity"]["instance"], intent["declaration"]["id"]}
      {:ok, %{s | active: nil, bound: Map.put(s.bound, key, event["outcome"])}}
    else
      _ -> @error
    end
  end

  defp reduce(%{"type" => "request_admitted", "kind" => "model"} = event, s, declarations, _) do
    if declarations == [] or
         (s.marker != nil and s.marker["turn_id"] == event["turn_id"] and
            s.session == event["session_id"] and s.active == nil and
            Enum.all?(declarations, fn row ->
              outcome = s.bound[{row["instance"], row["declaration"]["id"]}]
              outcome != nil and (not row["declaration"]["required"] or outcome == "acknowledged")
            end)) do
      {:ok, s}
    else
      @error
    end
  end

  defp reduce(%{"type" => type}, s, _, _) when type in ~w(cancelled turn_finished),
    do: {:ok, %{s | active: nil}}

  defp reduce(_, s, _, _), do: {:ok, s}

  defp declaration?(record),
    do:
      keys?(record, ~w(id event event_version view mode required)) and
        text?(record["id"]) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,31}\z/, record["id"]) and
        record["event_version"] === 1 and record["mode"] == "notify" and
        is_boolean(record["required"]) and
        record["view"] in Map.get(@views, record["event"], [])

  defp keys?(record, keys), do: is_map(record) and Enum.sort(Map.keys(record)) == Enum.sort(keys)
  defp text?(value), do: is_binary(value) and String.valid?(value)
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
end
