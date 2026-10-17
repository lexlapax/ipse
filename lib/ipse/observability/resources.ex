defmodule Ipse.Observability.Resources do
  @moduledoc "Separate default-off diagnostic leases and no-replay recovery facts."
  alias Ipse.Observability.{Config, Channel}
  @types ~w(diagnostic_sink_intent diagnostic_sink_ready diagnostic_sink_closed)
  def types, do: @types

  def intent(entry, session, policy) do
    %{
      "type" => "diagnostic_sink_intent",
      "version" => 1,
      "resource_id" => Ipse.Usage.id(),
      "session_id" => session,
      "identity" => entry.identity,
      "stage" => Config.stage(entry),
      "policy" => policy
    }
  end

  def receipt(intent, kind, cleanup \\ nil) do
    %{
      "type" => "diagnostic_sink_" <> kind,
      "version" => 1,
      "resource_id" => intent["resource_id"],
      "intent_sha256" => Ipse.Compaction.digest([intent]),
      "cleanup_confirmed" => cleanup
    }
  end

  def prepare(owner, config, session, record, prior_count \\ 0) do
    policy = Config.policy(config)

    capture = %{
      policy: policy,
      counters: :atomics.new(3, signed: false),
      started: System.monotonic_time(:millisecond),
      resources: %{}
    }

    if policy["mode"] == "off" do
      capture
    else
      entries = config |> Map.get(:extensions, []) |> Enum.filter(&Config.sink?/1)
      :atomics.add(capture.counters, 3, max(length(entries) - max(10_000 - prior_count, 0), 0))

      entries
      |> Enum.take(max(10_000 - prior_count, 0))
      |> Enum.reduce(capture, fn entry, acc ->
        intent = intent(entry, session, policy)
        record.(intent)

        case Channel.start(owner, entry, policy, intent) do
          {:ok, resource} ->
            put_in(acc, [:resources, intent["resource_id"]], resource)

          _ ->
            record.(receipt(intent, "closed", false))
            :atomics.add(acc.counters, 3, 1)
            acc
        end
      end)
    end
  end

  def offer(capture, source, record) do
    if capture.policy["mode"] != "off" do
      sequence = :atomics.add_get(capture.counters, 1, 1)
      elapsed = max(System.monotonic_time(:millisecond) - capture.started, 0)

      case Ipse.Observability.Event.build(source, record, sequence, elapsed) do
        {:ok, event} ->
          Enum.each(capture.resources, fn {_, resource} ->
            Channel.offer(resource, event, capture.policy)
          end)

        _ ->
          :atomics.add(capture.counters, 2, 1)
      end
    end

    :ok
  end

  def snapshot(capture) do
    %{
      "mode" => capture.policy["mode"],
      "policy" => capture.policy,
      "offered" => :atomics.get(capture.counters, 1),
      "unsupported" => :atomics.get(capture.counters, 2),
      "startup_failures" => :atomics.get(capture.counters, 3),
      "sinks" =>
        Enum.map(capture.resources, fn {id, resource} ->
          Map.merge(Channel.snapshot(resource), %{
            "resource_id" => id,
            "stage" => Config.stage(resource.entry),
            "ready" => resource.ready,
            "closed" => resource.closed
          })
        end)
    }
  end

  def stop(capture) do
    if capture.policy["mode"] != "off",
      do:
        Enum.each(capture.resources, fn {_, resource} ->
          Channel.revoke(resource)
          Channel.stop(resource)
        end)

    %{capture | policy: Map.put(capture.policy, "mode", "off")}
  end

  def close(capture, record) do
    resources = Enum.reject(capture.resources, fn {_, resource} -> resource.closed end)
    Enum.each(resources, fn {_, resource} -> Channel.revoke(resource) end)

    results =
      Task.async_stream(
        resources,
        fn {id, resource} ->
          {id, Channel.close(resource)}
        end,
        timeout: 4_000,
        on_timeout: :kill_task,
        max_concurrency: 4
      )
      |> Enum.zip(resources)
      |> Enum.map(fn
        {{:ok, {_, result}}, {_, resource}} ->
          record.(receipt(resource.intent, "closed", result == :ok))
          result

        {_, {_, resource}} ->
          Process.exit(resource.pid, :kill)
          record.(receipt(resource.intent, "closed", false))
          {:error, :cleanup_unconfirmed}
      end)

    prior =
      Enum.any?(capture.resources, fn {_, resource} ->
        resource.closed and not resource.cleanup
      end)

    if prior, do: [{:error, :cleanup_unconfirmed} | results], else: results
  end

  def validate(events, session \\ nil) do
    identities = get_in(List.first(events) || %{}, ["metadata", "extensions"]) || []

    Enum.reduce_while(events, {:ok, %{}}, fn event, {:ok, active} ->
      case event["type"] do
        "diagnostic_sink_intent" ->
          id = event["resource_id"]

          if is_nil(active[id]) and map_size(active) < 10_000 and intent?(event, session) and
               event["identity"] in identities,
             do:
               {:cont, {:ok, Map.put(active, id, %{intent: event, ready: false, closed: false})}},
             else: {:halt, {:error, :invalid_diagnostic_receipts}}

        type when type in ~w(diagnostic_sink_ready diagnostic_sink_closed) ->
          id = event["resource_id"]
          prior = active[id]
          closed = type == "diagnostic_sink_closed"
          cleanup = event["cleanup_confirmed"]

          if prior && not prior.closed && (closed or not prior.ready) &&
               event == receipt(prior.intent, if(closed, do: "closed", else: "ready"), cleanup) &&
               if(closed, do: is_boolean(cleanup), else: is_nil(cleanup)) do
            next = if closed, do: %{prior | closed: true}, else: %{prior | ready: true}
            {:cont, {:ok, Map.put(active, id, next)}}
          else
            {:halt, {:error, :invalid_diagnostic_receipts}}
          end

        _ ->
          {:cont, {:ok, active}}
      end
    end)
    |> case do
      {:ok, _} -> :ok
      _ -> {:error, :invalid_diagnostic_receipts}
    end
  rescue
    _ -> {:error, :invalid_diagnostic_receipts}
  end

  defp intent?(event, session) do
    Enum.sort(Map.keys(event)) == ~w(identity policy resource_id session_id stage type version) and
      event["version"] === 1 and
      (is_nil(session) or event["session_id"] == session) and is_binary(event["session_id"]) and
      Regex.match?(~r/\A[0-9a-f]{32}\z/, event["session_id"]) and is_binary(event["resource_id"]) and
      Regex.match?(~r/\A[0-9a-f]{32}\z/, event["resource_id"]) and
      Ipse.Extensions.Identity.valid?(event["identity"]) and
      event["stage"] in ~w(observe.local observe.export) and
      event["stage"] in event["identity"]["capabilities"] and
      Config.runtime(%{
        observability: event["policy"],
        extensions: [%{identity: event["identity"]}]
      }) == :ok and
      event["policy"]["mode"] in ~w(local export)
  end
end
