defmodule Ipse.Observability do
  @moduledoc "Operator-only capture policy, independent of sink selection and recovery facts."
  alias Ipse.JSON, as: Schema

  @groups ~w(session prompt context model stream tool approval question child compaction extension turn error)
  @defaults %{
    "mode" => "off",
    "groups" => @groups,
    "level" => "info",
    "sample_every" => 1,
    "queue_events" => 256,
    "event_bytes" => 16_384,
    "file_bytes" => 10_485_760,
    "retained_files" => 2
  }
  @error {:error, :invalid_observability_policy}
  def defaults, do: @defaults
  def groups, do: @groups

  def schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{
        "mode" => %{"type" => "string", "enum" => ~w(off local export)},
        "groups" => %{
          "type" => "array",
          "maxItems" => length(@groups),
          "items" => %{"type" => "string", "enum" => @groups}
        },
        "level" => %{"type" => "string", "enum" => ~w(info debug)},
        "sample_every" => integer(1, 1000),
        "queue_events" => integer(1, 256),
        "event_bytes" => integer(1024, 16_384),
        "file_bytes" => integer(16_384, 10_485_760),
        "retained_files" => integer(1, 2)
      }
    }
  end

  def validate_policy(policy) do
    with :ok <- Schema.validate_arguments(schema(), policy),
         groups = Map.get(policy, "groups", @groups),
         true <- length(groups) == length(Enum.uniq(groups)) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def resolve(sources, options, environment) do
    with true <-
           Enum.all?(
             sources,
             &(&1.scope == "operator" or not Map.has_key?(&1.data, "observability"))
           ),
         operator = Enum.find(sources, &Map.has_key?(&1.data, "observability")),
         values = if(operator, do: operator.data["observability"], else: %{}),
         :ok <- validate_policy(values),
         policy = Map.merge(@defaults, values),
         policy =
           if(environment["IPSE_OBSERVABILITY"],
             do: Map.put(policy, "mode", environment["IPSE_OBSERVABILITY"]),
             else: policy
           ),
         policy =
           if(options[:observability],
             do: Map.put(policy, "mode", options[:observability]),
             else: policy
           ),
         :ok <- validate_policy(policy) do
      source =
        cond do
          options[:observability] -> "CLI"
          environment["IPSE_OBSERVABILITY"] -> "environment"
          operator -> operator.path
          true -> "built-in"
        end

      {:ok, %{policy: policy, mode_source: source}}
    else
      _ -> @error
    end
  end

  def policy(config), do: Map.get(config, :observability, @defaults)

  def runtime(config) do
    policy = policy(config)
    entries = Enum.filter(Map.get(config, :extensions, []), &sink?/1)

    with :ok <- validate_policy(policy),
         true <- Enum.sort(Map.keys(policy)) == Enum.sort(Map.keys(@defaults)),
         true <- length(entries) <= 4,
         true <-
           Enum.all?(entries, fn entry ->
             Enum.count(~w(observe.local observe.export), &(&1 in entry.identity["capabilities"])) ==
               1
           end),
         true <- policy["mode"] == "off" or Enum.all?(entries, &permitted?(&1, policy)) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def sink?(entry),
    do: Enum.any?(~w(observe.local observe.export), &(&1 in entry.identity["capabilities"]))

  def stage(entry),
    do:
      if("observe.export" in entry.identity["capabilities"],
        do: "observe.export",
        else: "observe.local"
      )

  defp permitted?(entry, %{"mode" => "local"}), do: stage(entry) == "observe.local"

  defp permitted?(entry, %{"mode" => "export"}),
    do: stage(entry) == "observe.local" or entry.identity["scope"] == "operator"

  defp integer(low, high), do: %{"type" => "integer", "minimum" => low, "maximum" => high}
  alias Ipse.Observability.Channel
  @types ~w(diagnostic_sink_intent diagnostic_sink_ready diagnostic_sink_closed)
  def types, do: @types

  def intent(entry, session, policy) do
    %{
      "type" => "diagnostic_sink_intent",
      "version" => 1,
      "resource_id" => Ipse.Usage.id(),
      "session_id" => session,
      "identity" => entry.identity,
      "stage" => stage(entry),
      "policy" => policy
    }
  end

  def receipt(intent, kind, cleanup \\ nil) do
    %{
      "type" => "diagnostic_sink_" <> kind,
      "version" => 1,
      "resource_id" => intent["resource_id"],
      "intent_sha256" => Ipse.JSON.digest([intent]),
      "cleanup_confirmed" => cleanup
    }
  end

  def prepare(owner, config, session, record, prior_count \\ 0) do
    policy = policy(config)

    capture = %{
      policy: policy,
      counters: :atomics.new(3, signed: false),
      started: System.monotonic_time(:millisecond),
      resources: %{}
    }

    if policy["mode"] == "off" do
      capture
    else
      entries = config |> Map.get(:extensions, []) |> Enum.filter(&sink?/1)
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

      case build_event(source, record, sequence, elapsed) do
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
            "stage" => stage(resource.entry),
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

  def validate_events(events, session \\ nil) do
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
      Ipse.Extension.Registry.valid_identity?(event["identity"]) and
      event["stage"] in ~w(observe.local observe.export) and
      event["stage"] in event["identity"]["capabilities"] and
      runtime(%{
        observability: event["policy"],
        extensions: [%{identity: event["identity"]}]
      }) == :ok and
      event["policy"]["mode"] in ~w(local export)
  end

  def build_event(source, record, sequence, elapsed) do
    with {:ok, event} <- Ipse.Session.Lifecycle.project(source, record, "metadata"),
         group = event["type"] |> String.split(".") |> hd(),
         group =
           (cond do
              String.contains?(event["type"], ".compaction_") -> "compaction"
              group in ["assistant", "answer"] -> "stream"
              group == "wait" -> "session"
              true -> group
            end),
         true <- group in groups() do
      {:ok,
       %{
         "version" => 1,
         "sequence" => sequence,
         "elapsed_ms" => elapsed,
         "group" => group,
         "level" => level(event),
         "event" => event
       }}
    else
      _ -> {:error, :unsupported_observation}
    end
  end

  def valid_event?(value) do
    is_map(value) and
      Enum.sort(Map.keys(value)) == ~w(elapsed_ms event group level sequence version) and
      value["version"] === 1 and Ipse.JSON.safe_uint?(value["sequence"]) and value["sequence"] > 0 and
      Ipse.JSON.safe_uint?(value["elapsed_ms"]) and value["group"] in groups() and
      value["level"] in ~w(info error debug) and
      Ipse.Session.Lifecycle.valid_metadata?(value["event"]) and
      Ipse.Extension.validate(value) == :ok
  rescue
    _ -> false
  end

  defp level(event) do
    cond do
      event["data"]["outcome"] in ~w(failed unknown) or
        event["data"]["status"] in ~w(error failed unknown) or
          String.ends_with?(event["type"], ".compaction_failed") ->
        "error"

      event["type"] == "model.usage_observed" ->
        "debug"

      true ->
        "info"
    end
  end
end
