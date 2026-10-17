defmodule Ipse.Extensions.UsageRead do
  @moduledoc "Caller-bound own-session accounting pages; no content read, inference or budget authority."
  alias Ipse.{Usage, Journal}
  alias Ipse.Lifecycle.Source
  @error {:error, :invalid_extension_usage_read}
  @snapshot_keys ~w(version source operation_id identity_sha256 request_count legacy_unmetered)
  @limit 10_000

  def operation?(request), do: is_map(request) and request["op"] == "usage.read"
  def limit, do: @limit

  def validate(request) do
    if keys?(request, ~w(op cursor limit snapshot)) and operation?(request) and
         uint?(request["cursor"]) and request["cursor"] <= @limit and
         is_integer(request["limit"]) and request["limit"] in 1..4 and
         (is_nil(request["snapshot"]) or snapshot?(request["snapshot"])) and
         Ipse.Extension.validate(request) == :ok do
      :ok
    else
      @error
    end
  rescue
    _ -> @error
  end

  def snapshot?(s) do
    keys?(s, @snapshot_keys) and s["version"] === 1 and
      Source.valid_metadata?(s["source"]) and id?(s["operation_id"]) and
      hash?(s["identity_sha256"]) and uint?(s["request_count"]) and s["request_count"] <= @limit and
      is_boolean(s["legacy_unmetered"])
  rescue
    _ -> false
  end

  def prepare(ledger, snapshots, intent, source \\ nil) do
    request = intent["request"]
    snapshot = request["snapshot"] || fresh(ledger, intent, source)
    initial = request["snapshot"] == nil

    cond do
      validate(request) != :ok ->
        failed("usage_snapshot")

      initial and map_size(snapshots) >= @limit ->
        failed("usage_limit")

      not snapshot?(snapshot) ->
        failed("usage_snapshot")

      snapshot["identity_sha256"] != intent["identity_sha256"] or
          snapshot["source"]["session_id"] != intent["namespace"] ->
        failed("usage_snapshot")

      not initial and snapshots[snapshot["operation_id"]] != snapshot ->
        failed("usage_snapshot")

      request["cursor"] > snapshot["request_count"] ->
        failed("usage_cursor")

      snapshot["request_count"] > length(ledger.order) ->
        failed("usage_snapshot")

      true ->
        page(ledger, request, snapshot)
    end
  rescue
    _ -> failed("usage_snapshot")
  end

  defp fresh(ledger, intent, source) do
    %{
      "version" => 1,
      "source" => source,
      "operation_id" => intent["operation_id"],
      "identity_sha256" => intent["identity_sha256"],
      "request_count" => length(ledger.order),
      "legacy_unmetered" => ledger.legacy_unmetered
    }
  end

  defp page(ledger, request, snapshot) do
    cursor = request["cursor"]

    rows =
      ledger.order
      |> Enum.drop(cursor)
      |> Enum.take(min(request["limit"], snapshot["request_count"] - cursor))
      |> Enum.map(&Usage.request_record(ledger.requests[&1]))

    value = %{
      "version" => 1,
      "scope" => "session",
      "coverage" => "canonical_requests",
      "snapshot" => snapshot,
      "cursor" => cursor,
      "next" => if(cursor + length(rows) < snapshot["request_count"], do: cursor + length(rows)),
      "requests" => rows
    }

    if fits?(value), do: {:ok, value}, else: failed("usage_bounds")
  end

  def valid_outcome?(_, "unknown", value, _), do: value == %{}

  def valid_outcome?(_, "failed", value, _),
    do:
      keys?(value, ["code"]) and
        value["code"] in ~w(usage_snapshot usage_cursor usage_bounds usage_limit)

  def valid_outcome?(request, "ok", value, operation) do
    s = value["snapshot"]
    rows = value["requests"]

    next =
      if value["cursor"] + length(rows) < s["request_count"], do: value["cursor"] + length(rows)

    validate(request) == :ok and
      keys?(value, ~w(version scope coverage snapshot cursor next requests)) and
      value["version"] === 1 and value["scope"] == "session" and
      value["coverage"] == "canonical_requests" and snapshot?(s) and
      (request["snapshot"] == s or (request["snapshot"] == nil and s["operation_id"] == operation)) and
      value["cursor"] === request["cursor"] and value["cursor"] <= s["request_count"] and
      is_list(rows) and
      length(rows) == min(request["limit"], s["request_count"] - value["cursor"]) and
      Enum.all?(
        rows,
        &(Usage.valid_request_record?(&1) and &1["session_id"] == s["source"]["session_id"])
      ) and
      value["next"] === next and fits?(value)
  rescue
    _ -> false
  end

  def valid_outcome?(_, _, _, _), do: false

  def commit(snapshots, intent, event, expected) do
    outcome = event["outcome"]

    if outcome == outcome(expected) and
         valid_outcome?(
           intent["request"],
           outcome["status"],
           outcome["value"],
           intent["operation_id"]
         ) do
      {:ok, save(snapshots, intent, outcome)}
    else
      @error
    end
  end

  defp save(snapshots, intent, %{"status" => "ok", "value" => value}) do
    if intent["request"]["snapshot"] == nil,
      do: Map.put(snapshots, intent["operation_id"], value["snapshot"]),
      else: snapshots
  end

  defp save(snapshots, _, _), do: snapshots
  def outcome({:ok, value}), do: %{"status" => "ok", "value" => value}
  def outcome({:failed, value}), do: %{"status" => "failed", "value" => value}

  @doc "Validate cached pages against accounting at their original read, never retrieving a fresh balance on resume."
  def restore([header | _] = events) do
    if Enum.any?(events, &operation?(&1["request"])) do
      {:ok, ledger} = Usage.restore([header])

      Enum.reduce_while(events, {:ok, %{ledger: ledger, snapshots: %{}, pending: nil}}, fn event,
                                                                                           {:ok,
                                                                                            state} ->
        case apply_saved(event, state) do
          {:ok, next} -> {:cont, {:ok, next}}
          _ -> {:halt, @error}
        end
      end)
      |> case do
        {:ok, state} -> {:ok, state.snapshots}
        _ -> @error
      end
    else
      {:ok, %{}}
    end
  rescue
    _ -> @error
  end

  def restore(_), do: @error

  defp apply_saved(%{"type" => "extension_action_intent", "request" => request} = intent, state) do
    if operation?(request),
      do: {:ok, %{state | pending: {intent, state.ledger}}},
      else: {:ok, %{state | pending: nil}}
  end

  defp apply_saved(%{"type" => "extension_action_result", "request" => request} = event, state) do
    if operation?(request) do
      {intent, ledger} = state.pending
      true = Ipse.Extensions.Actions.result_intent(event) == intent
      value = event["outcome"]["value"]
      source = if event["outcome"]["status"] == "ok", do: value["snapshot"]["source"]
      expected = prepare(ledger, state.snapshots, intent, source)

      if event["outcome"]["status"] == "unknown" and value == %{} do
        {:ok, %{state | pending: nil}}
      else
        with {:ok, saved} <- commit(state.snapshots, intent, event, expected),
             do: {:ok, %{state | snapshots: saved, pending: nil}}
      end
    else
      {:ok, state}
    end
  end

  defp apply_saved(event, state) do
    with {:ok, ledger} <- Usage.apply_event(state.ledger, event),
         do: {:ok, %{state | ledger: ledger}}
  end

  @doc "Resolve each initial read intent once; no raw transcript or later damaged tail is scanned."
  def validate_sources(directory, session, events) do
    {:ok, snapshots} = restore(events)

    intents =
      Map.new(
        for %{"type" => "extension_action_intent"} = e <- events,
            operation?(e["request"]),
            do: {e["operation_id"], e}
      )

    Enum.reduce_while(snapshots, :ok, fn {operation, snapshot}, :ok ->
      ref = snapshot["source"]

      with true <- ref["session_id"] == session,
           {:ok, %{records: [%{source: actual, record: record}]}} <-
             Journal.source_page(directory, session, ref["byte_offset"], 1),
           {:ok, metadata} <- Source.metadata(actual),
           true <- metadata == ref,
           true <- record == intents[operation] do
        {:cont, :ok}
      else
        _ -> {:halt, @error}
      end
    end)
  rescue
    _ -> @error
  end

  defp fits?(value),
    do: Ipse.Extension.validate(value) == :ok and byte_size(Jason.encode!(value)) <= 12_288

  defp failed(code), do: {:failed, %{"code" => code}}
  defp keys?(v, keys), do: is_map(v) and Enum.sort(Map.keys(v)) == Enum.sort(keys)
  defp uint?(v), do: is_integer(v) and v in 0..9_007_199_254_740_991
  defp id?(v), do: is_binary(v) and Regex.match?(~r/\A[0-9a-f]{32}\z/, v)
  defp hash?(v), do: is_binary(v) and Regex.match?(~r/\A[0-9a-f]{64}\z/, v)
end
