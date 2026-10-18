defmodule Ipse.Extensions.Feeds do
  @moduledoc "Declared scoped feeds, bounded admission and source-bound no-replay receipts."
  alias Ipse.Extensions.{FeedChannel, Identity}
  alias Ipse.Lifecycle.{Source, Event}

  @types ~w(extension_feed_intent extension_feed_ready extension_feed_delivery_intent extension_feed_delivery_result extension_feed_closed)
  @reasons ~w(consumer_down stopped cancelled session_close capacity source_unavailable payload_limit session_limit startup_failed callback_failed view_unavailable cleanup_failure)
  @limit 10_000
  @error {:error, :invalid_extension_feed}
  def record_types, do: @types
  def limit, do: @limit

  def summary(events) do
    {:ok, saved} = validate(events)
    acknowledged = Enum.count(events, &(&1["type"] == "extension_feed_delivery_result"))

    %{
      "leases" => map_size(saved.resources),
      "open_leases" => Enum.count(saved.resources, fn {_, r} -> not r.closed end),
      "admitted" => saved.deliveries,
      "acknowledged" => acknowledged,
      "unacknowledged" => saved.deliveries - acknowledged,
      "unconfirmed_cleanup" =>
        Enum.count(
          events,
          &(&1["type"] == "extension_feed_closed" and &1["cleanup_confirmed"] == false)
        )
    }
  end

  def reason_code(reason), do: Enum.find_index(@reasons, &(&1 == reason)) + 1
  def reason(resource), do: Enum.at(@reasons, max(:atomics.get(resource.counters, 10) - 1, 0))

  def types do
    Event.metadata_types() --
      ~w(session.created session.started session.resumed session.close_committed prompt.received prompt.expanded_committed prompt.projection_committed prompt.effective_committed answer.committed)
  end

  def declaration?(d) do
    keys?(d, ~w(id event event_version view mode queue_events)) and
      is_binary(d["id"]) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,31}\z/, d["id"]) and
      d["event_version"] === 1 and d["view"] in views(d["event"]) and d["mode"] == "feed" and
      d["event"] in types() and is_integer(d["queue_events"]) and d["queue_events"] in 1..32
  rescue
    _ -> false
  end

  defp views("tool.intent_committed"), do: ~w(metadata tool.input)
  defp views("tool.outcome_recorded"), do: ~w(metadata tool.result)
  defp views(_), do: ["metadata"]

  def declarations(config),
    do:
      for(
        entry <- Map.get(config, :extensions, []),
        d <- Enum.sort_by(entry.subscriptions, & &1["id"]),
        d["mode"] == "feed",
        do: %{instance: entry.identity["instance"], declaration: d}
      )

  def new(events, session) do
    budget = :atomics.new(1, signed: false)
    :atomics.put(budget, 1, Enum.count(events, &(&1["type"] == "extension_feed_delivery_intent")))

    %{
      session: session,
      enrolled: false,
      resources: %{},
      budget: budget,
      refused: 0,
      prior: Enum.count(events, &(&1["type"] == "extension_feed_intent"))
    }
  end

  def enroll(%{enrolled: true} = feeds, _, _, _), do: feeds

  def enroll(feeds, config, owner, record_source) do
    plans = declarations(config)
    permitted = max(@limit - feeds.prior, 0)

    plans
    |> Enum.take(permitted)
    |> Enum.reduce(%{feeds | enrolled: true, refused: max(length(plans) - permitted, 0)}, fn plan,
                                                                                             acc ->
      entry = Enum.find(config.extensions, &(&1.identity["instance"] == plan.instance))

      intent = %{
        "type" => "extension_feed_intent",
        "version" => 1,
        "resource_id" => Ipse.Usage.id(),
        "session_id" => feeds.session,
        "identity" => entry.identity,
        "declaration" => plan.declaration
      }

      source = record_source.(intent)

      case FeedChannel.start(owner, entry, intent, source) do
        {:ok, resource} ->
          put_in(acc, [:resources, intent["resource_id"]], resource)

        _ ->
          # There was no executable admission; retain a known failed lease.
          closed = %{
            "type" => "extension_feed_closed",
            "version" => 1,
            "resource_id" => intent["resource_id"],
            "intent_sha256" => digest(intent),
            "reason" => "startup_failed",
            "admitted" => 0,
            "acknowledged" => 0,
            "gap_source" => nil,
            "cleanup_confirmed" => true
          }

          record_source.(closed)
          %{acc | refused: acc.refused + 1}
      end
    end)
  end

  def active?(nil), do: false
  def active?(feeds), do: Enum.any?(feeds.resources, fn {_, r} -> FeedChannel.active?(r) end)

  def offer(nil, _, _, _), do: :ok
  def offer(%{resources: resources}, _, _, _) when map_size(resources) == 0, do: :ok

  def offer(feeds, nil, _, _) do
    Enum.each(feeds.resources, fn {_, r} ->
      if FeedChannel.active?(r), do: FeedChannel.stop(r, "source_unavailable")
    end)
  end

  def offer(feeds, source, record, append) do
    case Event.project(source, record, "metadata") do
      {:ok, event} ->
        Enum.each(feeds.resources, fn {id, r} ->
          cond do
            not FeedChannel.active?(r) ->
              :ok

            event["type"] == "tool.recording_stopped" and
                r.intent["declaration"]["event"] in ~w(tool.intent_committed tool.outcome_recorded) ->
              FeedChannel.stop(r, "source_unavailable")

            r.intent["declaration"]["event"] == event["type"] ->
              case Event.project(source, record, r.intent["declaration"]["view"]) do
                {:ok, selected} ->
                  admit(feeds, id, r, source, selected, append)

                _ ->
                  :ets.insert(r.pending, {:gap, source})
                  FeedChannel.stop(r, "view_unavailable")
              end

            true ->
              :ok
          end
        end)

      _ ->
        :ok
    end
  end

  defp admit(feeds, id, r, source, event, append) do
    slots = :atomics.add_get(r.counters, 1, 1)

    cond do
      slots > r.intent["declaration"]["queue_events"] ->
        FeedChannel.release(r.counters)
        :ets.insert(r.pending, {:gap, source})
        FeedChannel.stop(r, "capacity")

      :atomics.get(feeds.budget, 1) >= @limit ->
        FeedChannel.release(r.counters)
        :ets.insert(r.pending, {:gap, source})
        FeedChannel.stop(r, "session_limit")

      true ->
        sequence = :atomics.get(r.counters, 2) + 1
        payload = payload(r.intent, r.source, sequence, event)

        if Ipse.Extension.validate(payload) == :ok do
          intent = %{
            "type" => "extension_feed_delivery_intent",
            "version" => 1,
            "resource_id" => id,
            "sequence" => sequence,
            "source" => source,
            "after_source" => r.source,
            "payload_sha256" => digest(payload)
          }

          append.(intent)
          :atomics.add(feeds.budget, 1, 1)
          :atomics.add(r.counters, 2, 1)
          :ets.insert(r.pending, {sequence, intent})
          send(r.pid, {:delivery, intent, payload})
        else
          FeedChannel.release(r.counters)
          :ets.insert(r.pending, {:gap, source})
          FeedChannel.stop(r, "payload_limit")
        end
    end
  end

  def payload(intent, anchor, sequence, event) do
    {:ok, after_source} = Source.metadata(anchor)

    %{
      "api_version" => 1,
      "handle" => intent["resource_id"],
      "subscription_id" => intent["declaration"]["id"],
      "sequence" => sequence,
      "after" => after_source,
      "event" => event
    }
  end

  def ack(payload),
    do: %{
      "api_version" => 1,
      "kind" => "ack",
      "handle" => payload["handle"],
      "sequence" => payload["sequence"],
      "event_id" => payload["event"]["event_id"]
    }

  def ready(intent), do: receipt(intent, "extension_feed_ready")

  def result(intent),
    do: %{
      "type" => "extension_feed_delivery_result",
      "version" => 1,
      "resource_id" => intent["resource_id"],
      "sequence" => intent["sequence"],
      "intent_sha256" => digest(intent),
      "outcome" => "acknowledged"
    }

  def closed(r, cleanup) do
    gap =
      case :ets.lookup(r.pending, :gap) do
        [{:gap, source}] -> source
        _ -> nil
      end

    receipt(r.intent, "extension_feed_closed")
    |> Map.merge(%{
      "reason" => reason(r),
      "admitted" => :atomics.get(r.counters, 2),
      "acknowledged" => :atomics.get(r.counters, 4),
      "gap_source" => gap,
      "cleanup_confirmed" => cleanup
    })
  end

  defp receipt(intent, type),
    do: %{
      "type" => type,
      "version" => 1,
      "resource_id" => intent["resource_id"],
      "intent_sha256" => digest(intent)
    }

  def close(feeds, reason, append) do
    active = Enum.reject(feeds.resources, fn {_, r} -> r.closed end)
    Enum.each(active, fn {_, r} -> FeedChannel.stop(r, reason) end)

    results =
      Task.async_stream(active, fn {id, r} -> {id, FeedChannel.close(r, reason)} end,
        timeout: 4_000,
        on_timeout: :kill_task,
        max_concurrency: 8
      )
      |> Enum.to_list()

    resources =
      Enum.zip(active, results)
      |> Enum.reduce(feeds.resources, fn {{id, r}, result}, acc ->
        cleanup = match?({:ok, {^id, :ok}}, result)
        if Process.alive?(r.pid), do: Process.exit(r.pid, :kill)
        append.(closed(r, cleanup))
        :ets.delete_all_objects(r.pending)
        Map.put(acc, id, %{r | closed: true, cleanup: cleanup})
      end)

    all = %{feeds | resources: resources, enrolled: true}

    outcomes =
      for {_, r} <- resources, do: if(r.cleanup, do: :ok, else: {:error, :cleanup_unconfirmed})

    {outcomes, all}
  end

  def snapshot(feeds),
    do: %{
      "enrolled" => feeds.enrolled,
      "refused" => feeds.refused,
      "admitted" => :atomics.get(feeds.budget, 1),
      "feeds" =>
        Enum.map(feeds.resources, fn {id, r} ->
          %{
            "resource_id" => id,
            "event" => r.intent["declaration"]["event"],
            "queue_events" => r.intent["declaration"]["queue_events"],
            "active" => FeedChannel.active?(r),
            "ready" => r.ready,
            "closed" => r.closed,
            "cleanup_confirmed" => r.cleanup,
            "admitted" => :atomics.get(r.counters, 2),
            "acknowledged" => :atomics.get(r.counters, 4),
            "pending" => if(r.closed, do: 0, else: :atomics.get(r.counters, 1)),
            "reason" => if(FeedChannel.active?(r), do: nil, else: reason(r))
          }
        end)
    }

  def validate(events, session \\ nil) do
    identities =
      Map.new(get_in(hd(events), ["metadata", "extensions"]) || [], &{&1["instance"], &1})

    declarations = get_in(hd(events), ["metadata", "extension_subscriptions", "entries"]) || []
    initial = %{resources: %{}, deliveries: 0, session: session}

    Enum.reduce_while(events, {:ok, initial}, fn event, {:ok, s} ->
      case validate_record(event, s, identities, declarations) do
        {:ok, next} -> {:cont, {:ok, next}}
        _ -> {:halt, @error}
      end
    end)
  rescue
    _ -> @error
  end

  def valid_record?(%{"type" => "extension_feed_intent"} = e) do
    keys?(e, ~w(type version resource_id session_id identity declaration)) and common?(e) and
      id?(e["session_id"]) and Identity.valid?(e["identity"]) and declaration?(e["declaration"]) and
      "event.feed" in e["identity"]["capabilities"]
  end

  def valid_record?(%{"type" => "extension_feed_ready"} = e),
    do:
      keys?(e, ~w(type version resource_id intent_sha256)) and common?(e) and
        hash?(e["intent_sha256"])

  def valid_record?(%{"type" => "extension_feed_delivery_intent"} = e),
    do:
      keys?(e, ~w(type version resource_id sequence source after_source payload_sha256)) and
        common?(e) and
        uint?(e["sequence"]) and e["sequence"] in 1..@limit and Source.valid?(e["source"]) and
        Source.valid?(e["after_source"]) and hash?(e["payload_sha256"])

  def valid_record?(%{"type" => "extension_feed_delivery_result"} = e),
    do:
      keys?(e, ~w(type version resource_id sequence intent_sha256 outcome)) and common?(e) and
        uint?(e["sequence"]) and e["sequence"] in 1..@limit and hash?(e["intent_sha256"]) and
        e["outcome"] == "acknowledged"

  def valid_record?(%{"type" => "extension_feed_closed"} = e),
    do:
      keys?(
        e,
        ~w(type version resource_id intent_sha256 reason admitted acknowledged gap_source cleanup_confirmed)
      ) and common?(e) and
        hash?(e["intent_sha256"]) and e["reason"] in @reasons and
        is_boolean(e["cleanup_confirmed"]) and
        uint?(e["admitted"]) and e["admitted"] <= @limit and uint?(e["acknowledged"]) and
        e["acknowledged"] <= e["admitted"] and
        (e["gap_source"] == nil or Source.valid?(e["gap_source"])) and
        (e["reason"] not in ~w(capacity payload_limit session_limit view_unavailable) or
           e["gap_source"] != nil)

  def valid_record?(_), do: false

  defp validate_record(%{"type" => type} = e, s, identities, declarations) when type in @types do
    with true <- valid_record?(e) do
      case type do
        "extension_feed_intent" ->
          with true <- s.session in [nil, e["session_id"]] and map_size(s.resources) < @limit,
               true <- not Map.has_key?(s.resources, e["resource_id"]),
               true <- identities[e["identity"]["instance"]] == e["identity"],
               true <-
                 %{"instance" => e["identity"]["instance"], "declaration" => e["declaration"]} in declarations do
            r = %{
              intent: e,
              ready: false,
              closed: false,
              admitted: 0,
              ack: 0,
              pending: %{},
              last_offset: nil
            }

            {:ok,
             %{s | session: e["session_id"], resources: Map.put(s.resources, e["resource_id"], r)}}
          else
            _ -> @error
          end

        _ ->
          with %{closed: false} = r <- s.resources[e["resource_id"]],
               {:ok, next} <- step(e, r, s) do
            {:ok,
             %{
               s
               | resources: Map.put(s.resources, e["resource_id"], next),
                 deliveries:
                   s.deliveries + if(type == "extension_feed_delivery_intent", do: 1, else: 0)
             }}
          else
            _ -> @error
          end
      end
    else
      _ -> @error
    end
  end

  defp validate_record(_, s, _, _), do: {:ok, s}

  defp step(%{"type" => "extension_feed_ready"} = e, r, _) do
    if not r.ready and e == ready(r.intent), do: {:ok, %{r | ready: true}}, else: @error
  end

  defp step(%{"type" => "extension_feed_delivery_intent"} = e, r, s) do
    if s.deliveries < @limit and e["sequence"] == r.admitted + 1 and
         e["source"]["session_id"] == s.session and
         e["after_source"]["session_id"] == s.session and
         e["after_source"]["byte_offset"] < e["source"]["byte_offset"] and
         (r.last_offset == nil or e["source"]["byte_offset"] > r.last_offset) and
         map_size(r.pending) < r.intent["declaration"]["queue_events"] do
      {:ok,
       %{
         r
         | admitted: e["sequence"],
           last_offset: e["source"]["byte_offset"],
           pending: Map.put(r.pending, e["sequence"], e)
       }}
    else
      @error
    end
  end

  defp step(%{"type" => "extension_feed_delivery_result"} = e, r, _) do
    with true <- r.ready and e["sequence"] == r.ack + 1,
         intent when is_map(intent) <- r.pending[e["sequence"]],
         true <- e == result(intent) do
      {:ok, %{r | ack: e["sequence"], pending: Map.delete(r.pending, e["sequence"])}}
    else
      _ -> @error
    end
  end

  defp step(%{"type" => "extension_feed_closed"} = e, r, s) do
    if e["intent_sha256"] == digest(r.intent) and e["admitted"] == r.admitted and
         e["acknowledged"] == r.ack and
         (e["gap_source"] == nil or
            (e["gap_source"]["session_id"] == s.session and
               (r.last_offset == nil or e["gap_source"]["byte_offset"] > r.last_offset))) do
      {:ok, %{r | closed: true, pending: %{}}}
    else
      @error
    end
  end

  def validate_sources(directory, session, events) do
    with {:ok, _} <- validate(events, session) do
      events
      |> Enum.reduce_while({:ok, %{}}, fn e, {:ok, resources} ->
        case e["type"] do
          "extension_feed_intent" ->
            {:cont, {:ok, Map.put(resources, e["resource_id"], %{intent: e, anchor: nil})}}

          "extension_feed_delivery_intent" ->
            resource = resources[e["resource_id"]]
            intent = resource.intent

            with {:ok, anchor} <- resolve_anchor(directory, session, resource, e["after_source"]),
                 {:ok, %{records: [%{source: source, record: record}]}} <-
                   Ipse.Journal.source_page(directory, session, e["source"]["byte_offset"], 1),
                 true <- source == e["source"],
                 :ok <- delivery_position(directory, session, e, source["byte_offset"], 10),
                 {:ok, event} <- Event.project(source, record, intent["declaration"]["view"]),
                 true <- event["type"] == intent["declaration"]["event"],
                 true <-
                   digest(payload(intent, anchor, e["sequence"], event)) == e["payload_sha256"] do
              {:cont, {:ok, put_in(resources, [e["resource_id"], :anchor], anchor)}}
            else
              _ -> {:halt, @error}
            end

          "extension_feed_closed" when :erlang.map_get("gap_source", e) != nil ->
            source = e["gap_source"]

            with {:ok, %{records: [%{source: actual}]}} <-
                   Ipse.Journal.source_page(directory, session, source["byte_offset"], 1),
                 true <- actual == source do
              {:cont, {:ok, resources}}
            else
              _ -> {:halt, @error}
            end

          _ ->
            {:cont, {:ok, resources}}
        end
      end)
      |> case do
        {:ok, _} -> :ok
        _ -> @error
      end
    end
  rescue
    _ -> @error
  end

  defp resolve_anchor(_, _, %{anchor: anchor}, anchor) when anchor != nil, do: {:ok, anchor}

  defp resolve_anchor(directory, session, %{anchor: nil, intent: intent}, source) do
    with {:ok, %{records: [%{source: actual, record: ^intent}]}} <-
           Ipse.Journal.source_page(directory, session, source["byte_offset"], 1),
         true <- actual == source,
         do: {:ok, actual},
         else: (_ -> @error)
  end

  defp resolve_anchor(_, _, _, _), do: @error

  # Source + at most eight feed intents + the existing adjacent question checkpoint.
  # Stop at this intent rather than parsing a later oversized or torn tail.
  defp delivery_position(_, _, _, _, 0), do: @error

  defp delivery_position(directory, session, intent, cursor, remaining) do
    with {:ok, %{records: [%{record: record}], next: next}} <-
           Ipse.Journal.source_page(directory, session, cursor, 1) do
      cond do
        record == intent -> :ok
        next != nil -> delivery_position(directory, session, intent, next, remaining - 1)
        true -> @error
      end
    end
  end

  defp digest(value), do: Ipse.Compaction.digest([value])
  defp common?(e), do: e["version"] === 1 and id?(e["resource_id"])
  defp keys?(e, keys), do: is_map(e) and Enum.sort(Map.keys(e)) == Enum.sort(keys)
  defp id?(v), do: is_binary(v) and Regex.match?(~r/\A[0-9a-f]{32}\z/, v)
  defp hash?(v), do: is_binary(v) and Regex.match?(~r/\A[0-9a-f]{64}\z/, v)
  defp uint?(v), do: is_integer(v) and v in 0..9_007_199_254_740_991
end
