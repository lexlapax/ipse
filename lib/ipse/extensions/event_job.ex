defmodule Ipse.Extensions.EventJob do
  @moduledoc "Source-bound event invocation admission and inert question recovery."
  alias Ipse.Extensions.{Catalog, Invocation, Subscriptions}
  alias Ipse.Lifecycle.Source

  def schedule(declaration), do: Map.get(declaration, "schedule", "before_request")

  def outcome(actions),
    do:
      if(Enum.all?(actions, &(&1["outcome"]["status"] in ~w(ok answered))),
        do: "completed",
        else: "failed"
      )

  def prepare(config, entry, delivery, payload, facts, session, turn) do
    name = "ext__" <> entry.identity["instance"] <> "__" <> delivery["declaration"]["handler"]

    with true <- payload != nil,
         {:ok, ^entry, descriptor} <- Catalog.lookup(config, "event.job", name),
         arguments = %{"event" => payload},
         :ok <- Catalog.validate_call(descriptor, arguments),
         trigger = %{
           "version" => 1,
           "delivery_id" => delivery["delivery_id"],
           "intent_sha256" => Ipse.Compaction.digest([delivery]),
           "event_id" => delivery["source"]["event_id"],
           "schedule" => schedule(delivery["declaration"]),
           "sources" => %{
             "received" => facts.received.source,
             "effective" => facts.effective.source
           }
         },
         parent =
           Invocation.intent(
             entry.identity,
             descriptor,
             arguments,
             session,
             turn,
             nil,
             nil,
             "event_trigger"
           ),
         public_payload = Map.put(parent["payload"], "trigger", public_trigger(trigger)),
         parent =
           parent
           |> Map.put("event_trigger", trigger)
           |> Map.put("payload", public_payload)
           |> Map.put("payload_sha256", Ipse.Compaction.digest([public_payload])),
         :ok <- Invocation.validate_intent(parent),
         true <- matches?(parent, delivery, facts.received.record, facts.effective.record) do
      {:ok, parent}
    else
      _ -> {:error, :event_job_refused}
    end
  end

  def public_trigger(trigger),
    do: %{
      "kind" => "event",
      "delivery_id" => trigger["delivery_id"],
      "event_id" => trigger["event_id"],
      "schedule" => trigger["schedule"]
    }

  def valid_trigger?(trigger) do
    is_map(trigger) and
      Enum.sort(Map.keys(trigger)) ==
        ~w(delivery_id event_id intent_sha256 schedule sources version) and
      trigger["version"] === 1 and id?(trigger["delivery_id"]) and id?(trigger["event_id"]) and
      is_binary(trigger["intent_sha256"]) and
      Regex.match?(~r/\A[0-9a-f]{64}\z/, trigger["intent_sha256"]) and
      trigger["schedule"] in ~w(before_request after_turn) and
      is_map(trigger["sources"]) and
      Enum.sort(Map.keys(trigger["sources"])) == ~w(effective received) and
      Enum.all?(trigger["sources"], fn {_, source} -> Source.valid?(source) end) and
      trigger["sources"]["received"]["session_id"] ==
        trigger["sources"]["effective"]["session_id"]
  rescue
    _ -> false
  end

  def matches?(parent, delivery, received, effective) do
    trigger = parent["event_trigger"]

    record =
      if delivery["declaration"]["event"] == "prompt.received", do: received, else: effective

    valid_trigger?(trigger) and delivery["declaration"]["mode"] == "job" and
      parent["descriptor"]["stage"] == "event.job" and parent["identity"] == delivery["identity"] and
      parent["descriptor"]["id"] == delivery["declaration"]["handler"] and
      parent["payload"]["turn_id"] == delivery["turn_id"] and
      parent["payload"]["session_id"] == delivery["source"]["session_id"] and
      trigger["delivery_id"] == delivery["delivery_id"] and
      trigger["event_id"] == delivery["source"]["event_id"] and
      trigger["intent_sha256"] == Ipse.Compaction.digest([delivery]) and
      trigger["schedule"] == schedule(delivery["declaration"]) and
      trigger["sources"]["received"] == effective["received_source"] and
      Source.matches?(trigger["sources"]["received"], received) and
      Source.matches?(trigger["sources"]["effective"], effective) and
      parent["payload"]["trigger"] == public_trigger(trigger) and
      parent["payload"]["arguments"] == %{"event" => Subscriptions.payload(delivery, record)}
  rescue
    _ -> false
  end

  def restore_question(nil, _, _, _), do: {:ok, nil}

  def restore_question(
        %{kind: :extension, parent: %{"event_trigger" => trigger} = parent},
        directory,
        session,
        events
      ) do
    with true <- valid_trigger?(trigger),
         delivery when is_map(delivery) <-
           Enum.find(
             events,
             &(&1["type"] == "extension_event_intent" and
                 &1["delivery_id"] == trigger["delivery_id"])
           ),
         {:ok, %{records: [received]}} <-
           Ipse.Journal.source_page(
             directory,
             session,
             trigger["sources"]["received"]["byte_offset"],
             1
           ),
         {:ok, %{records: [effective]}} <-
           Ipse.Journal.source_page(
             directory,
             session,
             trigger["sources"]["effective"]["byte_offset"],
             1
           ),
         true <-
           received.source == trigger["sources"]["received"] and
             effective.source == trigger["sources"]["effective"],
         true <- matches?(parent, delivery, received.record, effective.record) do
      {:ok,
       %{
         received: received,
         effective: effective,
         intent: delivery,
         turn: delivery["turn_id"],
         schedule: trigger["schedule"]
       }}
    else
      _ -> {:error, :invalid_event_job_question}
    end
  end

  def restore_question(_, _, _, _), do: {:ok, nil}
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
end
