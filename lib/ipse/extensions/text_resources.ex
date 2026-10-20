defmodule Ipse.Extensions.TextResources do
  @moduledoc "Private serializable text-resource leases and inert lifecycle receipts."
  alias Ipse.Extensions.{Identity, Registry, TextConsumer}
  @types ~w(extension_text_intent extension_text_ready extension_text_closed)
  @error {:error, :invalid_extension_text_resource}
  def types, do: @types

  def frame_version(identity),
    do: if("stream.text.events" in identity["capabilities"], do: 2, else: 1)

  def count(events), do: Enum.count(events, &(&1["type"] == "extension_text_intent"))

  def entries(config),
    do:
      Enum.filter(
        Map.get(config, :extensions, []),
        &("stream.text" in &1.identity["capabilities"])
      )

  def start(entries, owner, job_ref) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      with true <- Registry.live?(entry.identity),
           {:ok, intent} <-
             GenServer.call(owner, {:extension_text_begin, job_ref, entry.identity}),
           {:ok, consumer} <- TextConsumer.start(owner, self(), entry, intent) do
        result =
          with {:ok, handle} <-
                 GenServer.call(owner, {:extension_text_register, job_ref, intent, consumer}),
               :ok <- TextConsumer.activate(consumer, handle),
               :ok <- GenServer.call(owner, {:extension_text_ready, job_ref, intent, consumer}) do
            :ok
          end

        if result == :ok do
          {:cont, :ok}
        else
          if Process.alive?(consumer), do: Process.exit(consumer, :kill)
          GenServer.call(owner, {:extension_text_abort, job_ref, intent})
          {:halt, {:error, "Extension text subscription failed before provider dispatch."}}
        end
      else
        _ -> {:halt, {:error, "Extension text subscription failed before provider dispatch."}}
      end
    end)
  catch
    :exit, _ -> {:error, "Extension text subscription was interrupted; no callback was replayed."}
  end

  def intent(identity, session_id, turn_id) do
    %{
      "type" => "extension_text_intent",
      "version" => 1,
      "resource_id" => Ipse.Usage.id(),
      "identity" => identity,
      "session_id" => session_id,
      "turn_id" => turn_id
    }
  end

  def ready(intent), do: receipt(intent, "extension_text_ready")

  def closed(intent, reason, frames \\ nil, bytes \\ nil, cleanup \\ false),
    do:
      Map.merge(
        receipt(intent, "extension_text_closed"),
        %{
          "reason" => reason,
          "acknowledged_frames" => frames,
          "acknowledged_bytes" => bytes,
          "cleanup_confirmed" => cleanup
        }
      )

  def valid_closed?(event, intent),
    do: event["type"] == "extension_text_closed" and valid_receipt?(event, intent)

  def validate_events(events, session_id \\ nil)

  def validate_events([%{"metadata" => metadata} | _] = events, session_id) do
    identities = Map.new(Map.get(metadata, "extensions", []), &{&1["instance"], &1})

    session_ids =
      events
      |> Enum.filter(&(&1["type"] in ~w(extension_text_intent request_admitted)))
      |> Enum.map(& &1["session_id"])
      |> Enum.uniq()

    true = length(session_ids) <= 1 and (session_id == nil or session_ids in [[], [session_id]])

    initial = %{resources: %{}, latest: %{}, turns: MapSet.new()}

    Enum.reduce_while(events, {:ok, initial}, fn event, {:ok, state} ->
      resources = state.resources

      case event["type"] do
        "extension_text_intent" ->
          identity = event["identity"]

          if valid_intent?(event) and identities[identity["instance"]] == identity and
               not Map.has_key?(resources, event["resource_id"]) and map_size(resources) < 10_000 do
            {:cont,
             {:ok,
              %{
                state
                | latest: Map.put(state.latest, identity["instance"], event["resource_id"]),
                  resources:
                    Map.put(resources, event["resource_id"], %{
                      intent: event,
                      phase: :intent
                    })
              }}}
          else
            {:halt, @error}
          end

        type when type in ~w(extension_text_ready extension_text_closed) ->
          with %{intent: intent, phase: phase} = resource <- resources[event["resource_id"]],
               true <- phase != :closed,
               true <- type != "extension_text_ready" or phase == :intent,
               true <- valid_receipt?(event, intent) do
            phase = if type == "extension_text_ready", do: :ready, else: :closed

            {:cont,
             {:ok,
              %{
                state
                | resources: Map.put(resources, event["resource_id"], %{resource | phase: phase})
              }}}
          else
            _ -> {:halt, @error}
          end

        "request_admitted" ->
          if event["kind"] != "model" or MapSet.member?(state.turns, event["turn_id"]) or
               ready_for_turn?(resources, state.latest, identities) do
            turns =
              if event["kind"] == "model",
                do: MapSet.put(state.turns, event["turn_id"]),
                else: state.turns

            {:cont, {:ok, %{state | turns: turns}}}
          else
            {:halt, @error}
          end

        _ ->
          {:cont, {:ok, state}}
      end
    end)
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  rescue
    _ -> @error
  end

  def validate_events(_, _), do: @error

  defp ready_for_turn?(resources, latest, identities) do
    identities
    |> Map.values()
    |> Enum.filter(&("stream.text" in &1["capabilities"]))
    |> Enum.all?(fn identity ->
      resource = resources[latest[identity["instance"]]]
      resource != nil and resource.intent["identity"] == identity and resource.phase == :ready
    end)
  end

  defp receipt(intent, type),
    do: %{
      "type" => type,
      "version" => 1,
      "resource_id" => intent["resource_id"],
      "intent_sha256" => Ipse.JSON.digest([intent])
    }

  defp valid_intent?(event) do
    keys?(event, ~w(type version resource_id identity session_id turn_id)) and
      event["version"] === 1 and Identity.valid?(event["identity"]) and
      "stream.text" in event["identity"]["capabilities"] and
      Enum.all?(~w(resource_id session_id turn_id), &id?(event[&1]))
  end

  defp valid_receipt?(%{"type" => "extension_text_ready"} = event, intent),
    do: event == ready(intent)

  defp valid_receipt?(event, intent) do
    event ==
      closed(
        intent,
        event["reason"],
        event["acknowledged_frames"],
        event["acknowledged_bytes"],
        event["cleanup_confirmed"]
      ) and
      is_boolean(event["cleanup_confirmed"]) and
      event["reason"] in ~w(cancelled consumer_failed consumer_down stream_closed startup_failed) and
      Enum.all?(~w(acknowledged_frames acknowledged_bytes), fn key ->
        is_nil(event[key]) or (is_integer(event[key]) and event[key] in 0..9_007_199_254_740_991)
      end)
  end

  defp keys?(value, keys), do: is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(keys)
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
end
