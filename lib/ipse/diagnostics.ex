defmodule Ipse.Diagnostics do
  @moduledoc "Content-free, additive encoded-context measurements and saved-session inspection."
  alias Ipse.{Journal, Session}

  @categories ~w(instructions reference_context user_text assistant_text recent_tool_results older_tool_results tool_calls native_continuation checkpoint_data tool_provenance envelope)

  def context(messages, config, system \\ nil) do
    recent =
      messages
      |> Enum.filter(&(&1["role"] == "assistant" and is_list(&1["tool_calls"])))
      |> Enum.filter(&(&1["tool_calls"] != []))
      |> Enum.take(-2)
      |> Enum.flat_map(& &1["tool_calls"])
      |> MapSet.new(& &1["id"])

    header = List.wrap(system)
    all = header ++ messages
    initial = Map.new(@categories, &{&1, 0})
    initial = Map.put(initial, "envelope", 2 + max(length(all) - 1, 0))

    categories =
      Enum.reduce(Enum.with_index(all), initial, fn {message, index}, totals ->
        totals = Map.update!(totals, "envelope", &(&1 + 2 + max(map_size(message) - 1, 0)))

        Enum.reduce(message, totals, fn {key, value}, acc ->
          bytes = byte_size(Jason.encode!(%{key => value})) - 2

          category =
            if index < length(header) and message["role"] == "user",
              do: "reference_context",
              else: category(message, key, recent)

          Map.update!(acc, category, &(&1 + bytes))
        end)
      end)

    limit = config[:context_bytes] || 400_000
    target = Ipse.Compaction.target_bytes(config, limit)

    %{
      "version" => 1,
      "scope" => if(system, do: "effective_request", else: "effective_transcript_without_system"),
      "encoded_bytes" => Enum.sum(Map.values(categories)),
      "limit_bytes" => limit,
      "target_bytes" => target,
      "message_count" => length(messages),
      "categories" => categories
    }
  end

  def saved(dir, id) do
    with {:ok, events} <- Journal.load(dir, id),
         {:ok, messages} <- Session.restore_context(events),
         :ok <- Ipse.Observability.Resources.validate(events, id),
         :ok <- Ipse.Extensions.Subscriptions.validate_sources(dir, id, events),
         {:ok, accounting} <- Ipse.Usage.restore(events, id),
         {:ok, _} <- Ipse.Research.restore(events) do
      saved_limit = get_in(hd(events), ["metadata", "configuration", "settings", "context_bytes"])
      limit = saved_limit || 400_000

      {:ok,
       %{
         "version" => 1,
         "accounting" => Ipse.Usage.snapshot(accounting),
         "event_deliveries" => Ipse.Extensions.Subscriptions.summary(events),
         "event_feeds" => Ipse.Extensions.Feeds.summary(events),
         "tool_events" => Ipse.Lifecycle.Tool.summary(events),
         "context" => context(messages, %{context_bytes: limit}),
         "limit_source" =>
           if(saved_limit, do: "saved_configuration", else: "default_not_recorded"),
         "recorded_failures" => Enum.count(events, &(&1["type"] == "compaction_failed")),
         "unknown_tool_count" => length(Ipse.Compaction.unknown_call_ids(messages)),
         "request_measurements" =>
           events
           |> Enum.filter(&valid_measurement?/1)
           |> Enum.take(-16)
           |> Enum.map(&Map.take(&1, ~w(kind outcome duration_ms)))
       }}
    end
  rescue
    _ -> {:error, :invalid_diagnostic_context}
  end

  defp valid_measurement?(event) do
    event["type"] == "request_measured" and event["kind"] in ["model", "compaction"] and
      event["outcome"] in ["completed", "failed", "cancelled"] and
      is_integer(event["duration_ms"]) and event["duration_ms"] >= 0
  end

  defp category(%{"role" => "system"}, _key, _), do: "instructions"
  defp category(_message, "provider_data", _), do: "native_continuation"
  defp category(_message, "tool_calls", _), do: "tool_calls"
  defp category(_message, "ipse_checkpoint", _), do: "checkpoint_data"

  defp category(_, key, _)
       when key in ~w(ipse_tool_outcome ipse_result_excerpt ipse_external_result ipse_extension_result),
       do: "tool_provenance"

  defp category(%{"ipse_checkpoint" => _}, "content", _), do: "checkpoint_data"
  defp category(%{"role" => "user"}, "content", _), do: "user_text"
  defp category(%{"role" => "assistant"}, "content", _), do: "assistant_text"

  defp category(%{"role" => "tool", "tool_call_id" => id}, "content", recent),
    do: if(MapSet.member?(recent, id), do: "recent_tool_results", else: "older_tool_results")

  defp category(_, _, _), do: "envelope"
end
