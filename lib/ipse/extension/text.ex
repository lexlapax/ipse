defmodule Ipse.Extension.TextResources do
  @moduledoc "Private serializable text-resource leases and inert lifecycle receipts."
  alias Ipse.Extension.{Registry, TextConsumer}
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
      event["version"] === 1 and Registry.valid_identity?(event["identity"]) and
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

defmodule Ipse.Extension.TextConsumer do
  @moduledoc "Owned worker adapter for acknowledged private visible-text frames."
  use GenServer
  alias Ipse.Extension.{Registry, Worker}

  def start(owner, coordinator, entry, intent),
    do: GenServer.start(__MODULE__, {owner, coordinator, entry, intent})

  def activate(pid, handle), do: GenServer.call(pid, {:activate, handle}, :infinity)

  def close(%{pid: pid, worker: worker}) do
    result = if is_pid(worker), do: Worker.close(worker), else: {:error, :cleanup_unconfirmed}
    monitor = Process.monitor(pid)
    if Process.alive?(pid), do: Process.exit(pid, :kill)

    receive do
      {:DOWN, ^monitor, :process, ^pid, _} -> result
    after
      1_000 -> {:error, :cleanup_unconfirmed}
    end
  end

  @impl true
  def init({owner, coordinator, entry, intent}) do
    consumer = self()

    spawn(fn ->
      owner_ref = Process.monitor(owner)
      consumer_ref = Process.monitor(consumer)

      receive do
        {:DOWN, ^owner_ref, :process, _, _} -> Process.exit(consumer, :kill)
        {:DOWN, ^consumer_ref, :process, _, _} -> :ok
      end
    end)

    {:ok,
     %{
       owner: owner,
       owner_ref: Process.monitor(owner),
       coordinator: coordinator,
       entry: entry,
       intent: intent,
       worker: nil,
       handle: nil,
       broker_ref: nil,
       sequence: 0,
       frames: 0,
       bytes: 0,
       close_reason: "startup_failed"
     }}
  end

  @impl true
  def handle_call({:activate, handle}, {caller, _}, %{coordinator: caller, handle: nil} = s) do
    entry = s.entry

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
      s = %{s | worker: worker, handle: handle, broker_ref: Process.monitor(handle.server)}

      try do
        with :ok <-
               GenServer.call(s.owner, {:extension_text_worker, s.intent["resource_id"], worker}),
             {:ok, _} <- Worker.call(worker, "initialize", entry.options),
             true <- Registry.live?(entry.identity) do
          {:reply, :ok, %{s | close_reason: "consumer_down"}}
        else
          _ -> {:stop, :normal, {:error, :text_consumer_unavailable}, s}
        end
      catch
        :exit, _ -> {:stop, :normal, {:error, :text_consumer_unavailable}, s}
      end
    else
      _ -> {:stop, :normal, {:error, :text_consumer_unavailable}, s}
    end
  end

  def handle_call(_, _, s), do: {:reply, {:error, :text_consumer_refused}, s}

  @impl true
  def handle_info({:ipse_text, broker, frame}, %{handle: %{server: broker}} = s) do
    sequence = Map.get(frame, "sequence", 0)
    payload = %{"api_version" => 1, "handle" => s.intent["resource_id"], "frame" => frame}

    with true <- frame["subscription_id"] == s.handle.subscription_id,
         true <-
           frame["version"] === Ipse.Extension.TextResources.frame_version(s.intent["identity"]),
         true <- frame["version"] == 1 or Ipse.Session.TextStream.valid_frame?(frame),
         true <- frame["session_id"] == s.intent["session_id"],
         true <- frame["kind"] == "closed" or sequence == s.sequence + 1,
         true <- Registry.live?(s.entry.identity),
         {:ok, reply} <- Worker.call(s.worker, "stream.text", payload),
         true <-
           reply == %{
             "api_version" => 1,
             "handle" => s.intent["resource_id"],
             "kind" => "ack",
             "sequence" => sequence
           },
         true <- Registry.live?(s.entry.identity),
         :ok <- acknowledge(s.handle, frame) do
      next = %{
        s
        | sequence: sequence,
          frames: s.frames + 1,
          bytes: s.bytes + byte_size(Map.get(frame, "text", ""))
      }

      if frame["kind"] == "closed" do
        {:stop, :normal, %{next | close_reason: "stream_closed"}}
      else
        {:noreply, next}
      end
    else
      _ ->
        {:stop, :normal, %{s | close_reason: "consumer_failed"}}
    end
  catch
    :exit, _ ->
      {:stop, :normal, %{s | close_reason: "consumer_failed"}}
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{owner_ref: ref} = s),
    do: {:stop, :normal, s}

  def handle_info({:DOWN, ref, :process, _, _}, %{broker_ref: ref} = s) do
    {:stop, :normal, %{s | close_reason: "stream_closed"}}
  end

  def handle_info(_, s), do: {:noreply, s}

  @impl true
  def terminate(_, s) do
    cleanup = if is_pid(s.worker), do: Worker.close(s.worker), else: :ok

    send(
      s.owner,
      {:extension_text_closed, self(), s.intent["resource_id"], s.close_reason, s.frames, s.bytes,
       cleanup == :ok}
    )

    :ok
  end

  @impl true
  def format_status(status) do
    Map.new(status, fn
      {key, _} when key in [:state, :message, :reason, :log] -> {key, :private_text_consumer}
      item -> item
    end)
  end

  defp acknowledge(_, %{"kind" => "closed"}), do: :ok
  defp acknowledge(handle, frame), do: Ipse.Session.TextStream.ack(handle, frame["sequence"])
end
