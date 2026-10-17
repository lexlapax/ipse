defmodule Ipse.Extensions.History do
  @moduledoc "Explicit, own-session history pages over a fixed journal boundary; no replay authority."
  alias Ipse.{Journal, Lifecycle.Source, Lifecycle.Event}

  @views %{
    "metadata" => {"host.history", []},
    "prompt.original" => {"host.history.prompt.original", ["prompt.received"]},
    "prompt.expanded" => {"host.history.prompt.expanded", ["prompt.expanded_committed"]},
    "prompt.effective" => {"host.history.prompt.effective", ["prompt.effective_committed"]},
    "answer.original" => {"host.history.answer.original", ["answer.committed"]},
    "answer.presented" => {"host.history.answer.presented", ["answer.committed"]},
    "tool.input" => {"host.history.tool.input", ["tool.intent_committed"]},
    "tool.result" => {"host.history.tool.result", ["tool.outcome_recorded"]}
  }
  @page_bytes 12_288
  @errors ~w(history_snapshot history_cursor history_source history_timeout)
  @source_keys ~w(version session_id byte_offset event_id)
  @snapshot_keys ~w(byte_offset event_id operation_id session_id version view)

  def capabilities, do: @views |> Map.values() |> Enum.map(&elem(&1, 0)) |> Enum.sort()
  def operation?(request), do: is_map(request) and request["op"] == "history.read"
  def capability(request), do: @views |> Map.get(request["view"], {nil, []}) |> elem(0)

  def validate(request) do
    with true <- keys?(request, ~w(op view cursor snapshot limit)),
         true <- operation?(request) and is_map_key(@views, request["view"]),
         true <-
           uint?(request["cursor"]) and is_integer(request["limit"]) and request["limit"] in 1..8,
         true <-
           is_nil(request["snapshot"]) or
             (snapshot?(request["snapshot"]) and request["snapshot"]["view"] == request["view"]),
         :ok <- Ipse.Extension.validate(request) do
      :ok
    else
      _ -> {:error, :invalid_extension_history_request}
    end
  rescue
    _ -> {:error, :invalid_extension_history_request}
  end

  def snapshot(source, intent) do
    {:ok, reference} = Source.metadata(source)

    Map.merge(reference, %{
      "operation_id" => intent["operation_id"],
      "view" => intent["request"]["view"]
    })
  end

  def snapshot?(value) do
    keys?(value, @snapshot_keys) and Source.valid_metadata?(Map.take(value, @source_keys)) and
      id?(value["operation_id"]) and is_map_key(@views, value["view"])
  rescue
    _ -> false
  end

  @doc "Only the owned host task supplies the directory, identity and fresh boundary."
  def execute(context, intent) do
    request = intent["request"]
    snapshot = request["snapshot"] || context[:history_snapshot]

    with :ok <- validate(request),
         true <-
           snapshot?(snapshot) and snapshot["session_id"] == context.history_session and
             intent["namespace"] == context.history_session and
             snapshot["view"] == request["view"],
         {:ok, %{records: [%{source: source, record: anchor}]}} <-
           Journal.source_page(
             context.history_dir,
             context.history_session,
             snapshot["byte_offset"],
             1
           ),
         true <- Map.take(source, @source_keys) == Map.take(snapshot, @source_keys),
         true <- anchor?(anchor, snapshot, Ipse.Compaction.digest([context.identity])) do
      read_page(context, request, snapshot)
    else
      _ -> failed("history_snapshot")
    end
  rescue
    _ -> failed("history_source")
  end

  defp anchor?(record, snapshot, identity_sha256) do
    record["type"] == "extension_action_intent" and record["version"] === 1 and
      record["operation_id"] == snapshot["operation_id"] and
      record["namespace"] == snapshot["session_id"] and
      record["identity_sha256"] == identity_sha256 and
      record["approval"] == "not_required" and operation?(record["request"]) and
      record["request"]["snapshot"] == nil and record["request"]["view"] == snapshot["view"] and
      validate(record["request"]) == :ok
  end

  defp read_page(context, request, snapshot) do
    upper = snapshot["byte_offset"]
    cursor = request["cursor"]

    if cursor > upper do
      failed("history_cursor")
    else
      case Journal.source_page(
             context.history_dir,
             context.history_session,
             cursor,
             request["limit"],
             upper
           ) do
        {:ok, page} -> {:ok, collect(page, request, snapshot)}
        _ -> failed("history_source")
      end
    end
  end

  defp collect(page, request, snapshot) do
    offsets =
      Enum.map(Enum.drop(page.records, 1), & &1.source["byte_offset"]) ++
        [page.next || snapshot["byte_offset"]]

    initial = page(snapshot, request["cursor"], page.next, [])

    Enum.zip(page.records, offsets)
    |> Enum.reduce_while(initial, fn {%{source: source, record: record}, next}, value ->
      next = if next == snapshot["byte_offset"], do: nil, else: next
      row = project(source, record, request["view"])
      candidate = page(snapshot, request["cursor"], next, value["records"] ++ [row])

      cond do
        fits?(candidate) ->
          {:cont, candidate}

        value["records"] == [] ->
          {:cont, page(snapshot, request["cursor"], next, [gap(source, "page_budget")])}

        true ->
          {:halt, page(snapshot, request["cursor"], source["byte_offset"], value["records"])}
      end
    end)
  end

  defp page(snapshot, cursor, next, records),
    do: %{
      "version" => 1,
      "coverage" => "recorded_views_only",
      "snapshot" => snapshot,
      "cursor" => cursor,
      "next" => next,
      "scanned" => length(records),
      "records" => records
    }

  defp project(source, record, view) do
    case Event.project(source, record, "metadata") do
      {:ok, metadata} ->
        cond do
          view == "metadata" ->
            %{"kind" => "event", "event" => metadata}

          metadata["type"] in elem(@views[view], 1) ->
            case Event.project(source, record, view) do
              {:ok, event} -> %{"kind" => "event", "event" => event}
              _ -> gap(source, "view_unavailable")
            end

          true ->
            {:ok, reference} = Source.metadata(source)
            %{"kind" => "skipped", "source" => reference, "reason" => "other_view"}
        end

      _ ->
        gap(source, "unsupported_record")
    end
  end

  defp gap(source, reason) do
    {:ok, reference} = Source.metadata(source)
    %{"kind" => "gap", "source" => reference, "reason" => reason}
  end

  def valid_outcome?(_request, "unknown", value, _), do: value == %{}

  def valid_outcome?(_request, "failed", value, _),
    do: keys?(value, ["code"]) and value["code"] in @errors

  def valid_outcome?(request, "ok", value, operation) do
    snapshot = value["snapshot"]
    rows = value["records"]

    validate(request) == :ok and
      keys?(value, ~w(version coverage snapshot cursor next scanned records)) and
      value["version"] === 1 and value["coverage"] == "recorded_views_only" and
      snapshot?(snapshot) and snapshot["view"] == request["view"] and
      (request["snapshot"] == snapshot or
         (request["snapshot"] == nil and snapshot["operation_id"] == operation)) and
      value["cursor"] === request["cursor"] and value["cursor"] <= snapshot["byte_offset"] and
      (value["next"] == nil or
         (uint?(value["next"]) and value["next"] > value["cursor"] and
            value["next"] < snapshot["byte_offset"])) and
      is_list(rows) and length(rows) <= request["limit"] and value["scanned"] === length(rows) and
      (rows != [] or (value["next"] == nil and value["cursor"] == snapshot["byte_offset"])) and
      rows?(
        rows,
        request["view"],
        snapshot,
        value["cursor"],
        value["next"] || snapshot["byte_offset"]
      ) and
      fits?(value)
  rescue
    _ -> false
  end

  def valid_outcome?(_, _, _, _), do: false

  def bound_outcome?(event),
    do:
      event["outcome"]["status"] != "ok" or
        event["outcome"]["value"]["snapshot"]["session_id"] == event["namespace"]

  @doc "Resolve cached source/anchor references without repeating a history operation or changing its saved page."
  def validate_sources(directory, session, events) do
    events
    |> Enum.filter(
      &(operation?(&1["request"]) and &1["type"] == "extension_action_result" and
          &1["outcome"]["status"] == "ok")
    )
    |> Enum.reduce_while({:ok, MapSet.new()}, fn event, {:ok, seen} ->
      value = event["outcome"]["value"]
      snapshot = value["snapshot"]
      anchor_key = {:anchor, snapshot, event["identity_sha256"]}

      with true <- Ipse.Extensions.Actions.valid_result?(event) and event["namespace"] == session,
           {:ok, seen} <-
             verify_once(seen, anchor_key, fn ->
               with {:ok, %{records: [%{source: source, record: record}]}} <-
                      Journal.source_page(directory, session, snapshot["byte_offset"], 1) do
                 Map.take(source, @source_keys) == Map.take(snapshot, @source_keys) and
                   anchor?(record, snapshot, event["identity_sha256"])
               else
                 _ -> false
               end
             end),
           {:ok, seen} <- verify_rows(directory, session, value, event["request"]["view"], seen) do
        {:cont, {:ok, seen}}
      else
        _ -> {:halt, {:error, :invalid_extension_history_source}}
      end
    end)
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  rescue
    _ -> {:error, :invalid_extension_history_source}
  end

  defp verify_rows(directory, session, value, view, seen) do
    Enum.with_index(value["records"])
    |> Enum.reduce_while({:ok, seen}, fn {row, index}, {:ok, seen} ->
      budget = row["kind"] == "gap" and row["reason"] == "page_budget"
      following = Enum.at(value["records"], index + 1)

      finish =
        if following,
          do: row_source(following)["byte_offset"],
          else: value["next"] || value["snapshot"]["byte_offset"]

      key =
        {:row, view, Ipse.Compaction.digest([row]), finish,
         if(budget, do: {value["snapshot"], value["cursor"], index})}

      result =
        verify_once(seen, key, fn ->
          source = row_source(row)

          with {:ok, %{records: [%{source: actual, record: record}], next: next}} <-
                 Journal.source_page(
                   directory,
                   session,
                   source["byte_offset"],
                   1,
                   value["snapshot"]["byte_offset"]
                 ),
               true <- Map.take(actual, @source_keys) == Map.take(source, @source_keys),
               true <- (next || value["snapshot"]["byte_offset"]) == finish do
            expected = project(actual, record, view)

            row == expected or
              (budget and index == 0 and source["byte_offset"] == value["cursor"] and
                 not fits?(page(value["snapshot"], value["cursor"], next, [expected])))
          else
            _ -> false
          end
        end)

      case result do
        {:ok, seen} -> {:cont, {:ok, seen}}
        error -> {:halt, error}
      end
    end)
  end

  defp verify_once(seen, key, check) do
    if MapSet.member?(seen, key) or check.(),
      do: {:ok, MapSet.put(seen, key)},
      else: {:error, :invalid_extension_history_source}
  end

  defp rows?(rows, view, snapshot, cursor, finish) do
    Enum.with_index(rows)
    |> Enum.reduce_while(cursor - 1, fn {row, index}, previous ->
      source = row_source(row)
      reference = Map.take(source, @source_keys)

      if Source.valid_metadata?(reference) and reference["session_id"] == snapshot["session_id"] and
           reference["byte_offset"] >= cursor and
           (index != 0 or reference["byte_offset"] == cursor) and
           reference["byte_offset"] > previous and
           reference["byte_offset"] < finish and row?(row, view) do
        {:cont, reference["byte_offset"]}
      else
        {:halt, false}
      end
    end) != false
  end

  defp row_source(%{"kind" => "event", "event" => event}), do: event["source"]
  defp row_source(row), do: row["source"]

  defp row?(%{"kind" => "event", "event" => event} = row, "metadata"),
    do: keys?(row, ~w(kind event)) and Event.valid_metadata?(event)

  defp row?(%{"kind" => "event", "event" => event} = row, view) do
    source = event["source"]
    data = event["data"]

    with true <- keys?(row, ~w(kind event)),
         true <-
           Source.valid?(source) and event["view"] == view and
             event["type"] in elem(@views[view], 1),
         {:ok, reference} <- Source.metadata(source),
         true <-
           if(view in ~w(tool.input tool.result),
             do: Ipse.Lifecycle.Tool.private_data?(view, data),
             else:
               keys?(data, ["text"]) and is_binary(data["text"]) and String.valid?(data["text"]) and
                 byte_size(data["text"]) <= 8192
           ) do
      Event.valid_metadata?(%{event | "view" => "metadata", "source" => reference, "data" => %{}})
    else
      _ -> false
    end
  end

  defp row?(%{"kind" => "gap", "reason" => reason} = row, _),
    do:
      keys?(row, ~w(kind source reason)) and Source.valid_metadata?(row["source"]) and
        reason in ~w(unsupported_record view_unavailable page_budget)

  defp row?(%{"kind" => "skipped", "reason" => "other_view"} = row, view),
    do:
      view != "metadata" and keys?(row, ~w(kind source reason)) and
        Source.valid_metadata?(row["source"])

  defp row?(_, _), do: false

  defp fits?(value) do
    byte_size(Jason.encode!(value)) <= @page_bytes and
      Ipse.Extension.validate(%{
        "api_version" => 1,
        "invocation_id" => String.duplicate("0", 32),
        "operation_id" => String.duplicate("0", 32),
        "step" => 16,
        "outcome" => %{"status" => "ok", "value" => value}
      }) == :ok
  end

  defp failed(code), do: {:failed, %{"code" => code}}
  defp keys?(value, keys), do: is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(keys)
  defp uint?(value), do: is_integer(value) and value in 0..9_007_199_254_740_991
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
end
