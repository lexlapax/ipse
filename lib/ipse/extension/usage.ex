defmodule Ipse.Extension.UsageRead do
  @moduledoc "Caller-bound own-session accounting pages; no content read, inference or budget authority."
  alias Ipse.{Usage, Journal}
  alias Ipse.Journal
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
    keys?(s, @snapshot_keys) and is_integer(s["version"]) and s["version"] in [1, 2] and
      Journal.valid_source_metadata?(s["source"]) and id?(s["operation_id"]) and
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

      snapshot["request_count"] > length(Usage.order(ledger)) ->
        failed("usage_snapshot")

      true ->
        page(ledger, request, snapshot)
    end
  rescue
    _ -> failed("usage_snapshot")
  end

  defp fresh(ledger, intent, source) do
    %{
      "version" => Usage.snapshot(ledger)["version"],
      "source" => source,
      "operation_id" => intent["operation_id"],
      "identity_sha256" => intent["identity_sha256"],
      "request_count" => length(Usage.order(ledger)),
      "legacy_unmetered" => ledger.legacy_unmetered
    }
  end

  defp page(ledger, request, snapshot) do
    cursor = request["cursor"]

    rows =
      Usage.order(ledger)
      |> Enum.drop(cursor)
      |> Enum.take(min(request["limit"], snapshot["request_count"] - cursor))
      |> Enum.map(&Usage.request_record(ledger.requests[&1]))

    value = %{
      "version" => snapshot["version"],
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
      value["version"] === s["version"] and value["scope"] == "session" and
      value["coverage"] == "canonical_requests" and snapshot?(s) and
      (request["snapshot"] == s or (request["snapshot"] == nil and s["operation_id"] == operation)) and
      value["cursor"] === request["cursor"] and value["cursor"] <= s["request_count"] and
      is_list(rows) and
      length(rows) == min(request["limit"], s["request_count"] - value["cursor"]) and
      Enum.all?(
        rows,
        &(Usage.valid_request_record?(&1) and &1["session_id"] == s["source"]["session_id"] and
            (value["version"] == 2 or &1["version"] === 1))
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
        with {:ok, ledger} <- Usage.apply_event(state.ledger, event),
             {:ok, next} <- apply_saved(event, %{state | ledger: ledger}) do
          {:cont, {:ok, next}}
        else
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
      true = Ipse.Extension.Actions.result_intent(event) == intent
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

  defp apply_saved(_event, state), do: {:ok, state}

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
           {:ok, metadata} <- Journal.source_metadata(actual),
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

defmodule Ipse.Extension.ChildUsage do
  @moduledoc "Explicit parent-bound discovery and frozen reads of registered child accounting."
  alias Ipse.Usage
  alias Ipse.Journal
  alias Ipse.Runner
  alias Ipse.Workspace
  @limit 10_000
  @bytes 16_777_216
  @error {:error, :invalid_extension_child_usage}
  @snapshot ~w(version source operation_id identity_sha256)
  @errors ~w(usage_child_missing usage_child_busy usage_child_invalid usage_child_bounds usage_child_snapshot usage_child_timeout usage_children_limit usage_children_cursor usage_children_snapshot usage_children_bounds)

  def operation?(r), do: is_map(r) and r["op"] in ~w(usage.children usage.child.read)
  def new, do: %{index: %{}, order: [], overflow: false, request: nil, reads: %{}}

  @doc false
  def read_for_budget(directory, parent, child),
    do: read_child(directory, parent, child, nil, true)

  def apply_parent(state, %{"type" => "request_admitted", "kind" => "model"} = e),
    do: %{state | request: e}

  def apply_parent(state, %{"type" => "delegation_started"} = e) do
    if length(state.order) >= @limit do
      %{state | overflow: true}
    else
      child = %{
        "child_id" => e["child_id"],
        "parent_request_id" => state.request && state.request["request_id"],
        "parent_turn_id" => state.request && state.request["turn_id"],
        "origin_call_id" => e["origin_call_id"],
        "status" => "unfinished",
        "cleanup_confirmed" => false
      }

      %{
        state
        | index: Map.put(state.index, e["child_id"], child),
          order: state.order ++ [e["child_id"]]
      }
    end
  end

  def apply_parent(state, %{"type" => "delegation_finished", "child_id" => id} = e) do
    if Map.has_key?(state.index, id) do
      update_in(state, [:index, id], &Map.merge(&1, Map.take(e, ~w(status cleanup_confirmed))))
    else
      state
    end
  end

  def apply_parent(state, _), do: state

  def validate(r) do
    extra = if r["op"] == "usage.child.read", do: ["child_id"], else: []

    if operation?(r) and keys?(r, ~w(op cursor limit snapshot) ++ extra) and
         is_integer(r["cursor"]) and r["cursor"] in 0..@limit and r["limit"] in 1..4 and
         is_integer(r["limit"]) and
         (extra == [] or id?(r["child_id"])) and
         (r["snapshot"] == nil or snapshot?(r["snapshot"])) and Ipse.Extension.validate(r) == :ok,
       do: :ok,
       else: @error
  rescue
    _ -> @error
  end

  def snapshot?(s) do
    extra =
      if s["version"] == 2,
        do: ~w(child_count),
        else: ~w(child_id request_count legacy_unmetered bytes sha256)

    keys?(s, @snapshot ++ extra) and is_integer(s["version"]) and s["version"] in [2, 3, 4] and
      Journal.valid_source_metadata?(s["source"]) and id?(s["operation_id"]) and
      hash?(s["identity_sha256"]) and
      if(s["version"] == 2,
        do: count?(s["child_count"]),
        else:
          id?(s["child_id"]) and count?(s["request_count"]) and is_boolean(s["legacy_unmetered"]) and
            is_integer(s["bytes"]) and s["bytes"] in 1..@bytes and hash?(s["sha256"])
      )
  rescue
    _ -> false
  end

  def context(state, intent, directory, source) do
    %{state: state, intent: intent, directory: directory, source: source}
  end

  def execute(c) do
    r = c.intent["request"]

    with :ok <- validate(r),
         true <- not (c.state.overflow and r["op"] == "usage.children" and r["snapshot"] == nil),
         true <- r["snapshot"] != nil or map_size(c.state.reads) < @limit,
         {:ok, snapshot} <- admitted_snapshot(c) do
      if r["op"] == "usage.children" do
        discovery(c, snapshot)
      else
        with child when is_map(child) <- c.state.index[r["child_id"]],
             {:ok, ledger, bytes, digest} <-
               read_child(c.directory, c.intent["namespace"], child, snapshot),
             snapshot =
               snapshot ||
                 Map.merge(base(c, if(Usage.snapshot(ledger)["version"] == 2, do: 4, else: 3)), %{
                   "child_id" => r["child_id"],
                   "request_count" => length(Usage.order(ledger)),
                   "legacy_unmetered" => ledger.legacy_unmetered,
                   "bytes" => bytes,
                   "sha256" => digest
                 }),
             true <-
               snapshot["request_count"] == length(Usage.order(ledger)) and
                 snapshot["legacy_unmetered"] == ledger.legacy_unmetered do
          page(
            r,
            snapshot,
            Enum.map(Usage.order(ledger), &Usage.request_record(ledger.requests[&1]))
          )
        else
          nil ->
            failed(if(c.state.overflow, do: "usage_children_limit", else: "usage_child_missing"))

          {:failed, _} = error ->
            error

          _ ->
            failed("usage_child_invalid")
        end
      end
    else
      false -> failed("usage_children_limit")
      {:failed, _} = error -> error
      _ -> failed("usage_child_snapshot")
    end
  rescue
    _ -> failed("usage_child_invalid")
  end

  defp admitted_snapshot(c) do
    r = c.intent["request"]
    s = r["snapshot"]
    versions = if r["op"] == "usage.children", do: [2], else: [3, 4]

    cond do
      s == nil ->
        {:ok, nil}

      s["version"] not in versions or not bound?(s, c.intent) ->
        failed("usage_child_snapshot")

      c.state.reads[s["operation_id"]] != s ->
        failed("usage_child_snapshot")

      r["op"] == "usage.child.read" and s["child_id"] != r["child_id"] ->
        failed("usage_child_snapshot")

      true ->
        {:ok, s}
    end
  end

  defp base(c, version),
    do: %{
      "version" => version,
      "source" => c.source,
      "operation_id" => c.intent["operation_id"],
      "identity_sha256" => c.intent["identity_sha256"]
    }

  defp discovery(c, snapshot) do
    snapshot = snapshot || Map.put(base(c, 2), "child_count", length(c.state.order))

    rows =
      c.state.order
      |> Enum.take(snapshot["child_count"])
      |> Enum.map(&public_child(c.state.index[&1]))

    page(c.intent["request"], snapshot, rows)
  end

  defp public_child(child),
    do:
      child
      |> Map.drop(["origin_call_id"])
      |> Map.put("origin_recorded", is_binary(child["origin_call_id"]))

  defp page(r, snapshot, rows) do
    if r["cursor"] > length(rows) do
      failed("usage_children_cursor")
    else
      selected = rows |> Enum.drop(r["cursor"]) |> Enum.take(r["limit"])
      child = r["op"] == "usage.child.read"

      value = %{
        "version" => if(child and snapshot["version"] == 4, do: 2, else: 1),
        "scope" => if(child, do: "child", else: "children"),
        "coverage" => if(child, do: "canonical_requests", else: "registered_children"),
        "snapshot" => snapshot,
        "cursor" => r["cursor"],
        "next" =>
          if(r["cursor"] + length(selected) < length(rows), do: r["cursor"] + length(selected))
      }

      value = Map.put(value, if(child, do: "requests", else: "children"), selected)
      if fits?(value), do: {:ok, value}, else: failed("usage_children_bounds")
    end
  end

  def valid_outcome?(_, "unknown", value, _), do: value == %{}

  def valid_outcome?(_, "failed", value, _),
    do: keys?(value, ["code"]) and value["code"] in @errors

  def valid_outcome?(r, "ok", value, operation) do
    child = r["op"] == "usage.child.read"
    key = if child, do: "requests", else: "children"
    snapshot = value["snapshot"]
    rows = value[key]
    count = snapshot[if(child, do: "request_count", else: "child_count")]

    validate(r) == :ok and keys?(value, ~w(version scope coverage snapshot cursor next) ++ [key]) and
      value["version"] === if(child and snapshot["version"] == 4, do: 2, else: 1) and
      value["scope"] == if(child, do: "child", else: "children") and
      value["coverage"] == if(child, do: "canonical_requests", else: "registered_children") and
      snapshot?(snapshot) and snapshot["version"] in if(child, do: [3, 4], else: [2]) and
      (snapshot == r["snapshot"] or
         (r["snapshot"] == nil and snapshot["operation_id"] == operation)) and
      (not child or snapshot["child_id"] == r["child_id"]) and
      value["cursor"] === r["cursor"] and r["cursor"] <= count and is_list(rows) and
      length(rows) == min(r["limit"], count - r["cursor"]) and
      value["next"] === if(r["cursor"] + length(rows) < count, do: r["cursor"] + length(rows)) and
      Enum.all?(rows, fn row ->
        if child do
          Usage.valid_request_record?(row) and row["session_id"] == r["child_id"] and
            row["parent_session_id"] == snapshot["source"]["session_id"] and
            (value["version"] == 2 or row["version"] === 1)
        else
          keys?(
            row,
            ~w(child_id parent_request_id parent_turn_id status cleanup_confirmed origin_recorded)
          ) and
            id?(row["child_id"]) and
            (is_nil(row["parent_request_id"]) or id?(row["parent_request_id"])) and
            (is_nil(row["parent_turn_id"]) or id?(row["parent_turn_id"])) and
            is_boolean(row["origin_recorded"]) and
            row["status"] in ~w(unfinished result_recorded unknown) and
            is_boolean(row["cleanup_confirmed"])
        end
      end) and fits?(value)
  rescue
    _ -> false
  end

  def valid_outcome?(_, _, _, _), do: false

  def commit(state, intent, event, source) do
    outcome = event["outcome"]
    value = outcome["value"]
    r = intent["request"]
    c = context(state, intent, nil, source)

    with true <- valid_outcome?(r, outcome["status"], value, intent["operation_id"]),
         true <- outcome["status"] != "ok" or match?({:ok, _}, admitted_snapshot(c)),
         true <- outcome["status"] != "ok" or bound?(value["snapshot"], intent),
         true <-
           outcome["status"] != "ok" or r["snapshot"] != nil or map_size(state.reads) < @limit,
         true <- outcome["status"] != "ok" or commit_page?(c, value) do
      if outcome["status"] == "ok" and r["snapshot"] == nil,
        do: {:ok, put_in(state, [:reads, intent["operation_id"]], value["snapshot"])},
        else: {:ok, state}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp commit_page?(c, value) do
    snapshot = value["snapshot"]

    if c.intent["request"]["op"] == "usage.children" do
      (not c.state.overflow or c.intent["request"]["snapshot"] != nil) and
        (c.intent["request"]["snapshot"] != nil or
           snapshot["child_count"] == length(c.state.order)) and
        {:ok, value} == discovery(c, snapshot)
    else
      child = c.state.index[c.intent["request"]["child_id"]]

      is_map(child) and is_binary(child["origin_call_id"]) and
        Enum.all?(value["requests"], &(&1["parent_request_id"] == child["parent_request_id"]))
    end and (c.intent["request"]["snapshot"] != nil or snapshot["source"] == c.source)
  end

  def restore(events) do
    Enum.reduce_while(events, {:ok, new(), nil}, fn e, {:ok, state, pending} ->
      cond do
        e["type"] == "extension_action_intent" and operation?(e["request"]) ->
          {:cont, {:ok, state, e}}

        e["type"] == "extension_action_result" and operation?(e["request"]) ->
          source =
            if e["outcome"]["status"] == "ok", do: e["outcome"]["value"]["snapshot"]["source"]

          if pending == Ipse.Extension.Actions.result_intent(e) do
            case commit(state, pending, e, source) do
              {:ok, next} -> {:cont, {:ok, next, nil}}
              _ -> {:halt, @error}
            end
          else
            {:halt, @error}
          end

        true ->
          {:cont, {:ok, apply_parent(state, e), pending}}
      end
    end)
    |> case do
      {:ok, state, _} -> {:ok, state}
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def validate_sources(directory, session, events) do
    with {:ok, state} <- restore(events) do
      intents =
        Map.new(
          for %{"type" => "extension_action_intent"} = e <- events,
              operation?(e["request"]),
              do: {e["operation_id"], e}
        )

      pages =
        events
        |> Enum.filter(
          &(&1["type"] == "extension_action_result" and operation?(&1["request"]) and
              &1["outcome"]["status"] == "ok" and &1["request"]["op"] == "usage.child.read")
        )
        |> Enum.group_by(& &1["outcome"]["value"]["snapshot"]["operation_id"])

      Enum.reduce_while(state.reads, :ok, fn {operation, snapshot}, :ok ->
        source = snapshot["source"]

        result =
          with true <- source["session_id"] == session,
               {:ok, %{records: [%{source: actual, record: record}]}} <-
                 Journal.source_page(directory, session, source["byte_offset"], 1),
               {:ok, metadata} <- Journal.source_metadata(actual),
               true <- metadata == source and record == intents[operation] do
            if snapshot["version"] in [3, 4] do
              with {:ok, ledger, _, _} <-
                     read_child(directory, session, state.index[snapshot["child_id"]], snapshot) do
                rows = Enum.map(Usage.order(ledger), &Usage.request_record(ledger.requests[&1]))

                length(Usage.order(ledger)) == snapshot["request_count"] and
                  ledger.legacy_unmetered == snapshot["legacy_unmetered"] and
                  Enum.all?(pages[operation], fn e ->
                    page(e["request"], snapshot, rows) == {:ok, e["outcome"]["value"]}
                  end)
              else
                _ -> false
              end
            else
              true
            end
          else
            _ -> false
          end

        if result == true, do: {:cont, :ok}, else: {:halt, @error}
      end)
    end
  rescue
    _ -> @error
  end

  defp read_child(directory, parent, child, snapshot, accounting_events \\ false) do
    with true <- is_map(child) and id?(child["child_id"]) and id?(parent),
         {:ok, root} <- Workspace.canonical_path(directory),
         :ok <- private(root, :directory),
         path = Path.join([root, "subagents", parent]),
         :ok <- private_directory(Path.join(root, "subagents")),
         :ok <- private_directory(path),
         {:ok, ^path} <- Workspace.canonical_path(path),
         file = Path.join(path, child["child_id"] <> ".jsonl"),
         lockfile = Path.join(path, child["child_id"] <> ".lock"),
         :ok <- private_file(file),
         :ok <- private_file(lockfile) do
      case Runner.lock(lockfile) do
        {:ok, lock} ->
          try do
            load_child(file, parent, child, snapshot, accounting_events)
          after
            Runner.unlock(lock)
          end

        _ ->
          failed("usage_child_busy")
      end
    else
      _ -> failed("usage_child_missing")
    end
  rescue
    _ -> failed("usage_child_invalid")
  end

  defp load_child(file, parent, child, snapshot, accounting_events) do
    with {:ok, stat} <- File.stat(file),
         bytes = if(snapshot, do: snapshot["bytes"], else: stat.size),
         true <- bytes in 1..@bytes and bytes <= stat.size,
         {:ok, io} <- :file.open(String.to_charlist(file), [:raw, :read, :binary]) do
      try do
        with {:ok, contents} <- :file.pread(io, 0, bytes),
             true <- byte_size(contents) == bytes and String.ends_with?(contents, "\n"),
             {:ok, events} <- decode(contents),
             [%{"metadata" => metadata} | _] <- events,
             true <-
               metadata["delegation_origin"] == %{
                 "parent_session_id" => parent,
                 "parent_request_id" => child["parent_request_id"],
                 "call_id" => child["origin_call_id"]
               },
             true <- is_binary(child["origin_call_id"]),
             {:ok, ledger} <- Usage.restore(events, child["child_id"]),
             :ok <- validate_model_actions(events),
             true <-
               Enum.all?(ledger.requests, fn {_, r} ->
                 r.admission["parent_session_id"] == parent and
                   r.admission["parent_request_id"] == child["parent_request_id"]
               end),
             digest =
               Ipse.JSON.digest([
                 Enum.map(Usage.order(ledger), &Usage.request_record(ledger.requests[&1]))
               ]),
             true <- snapshot == nil or snapshot["sha256"] == digest do
          if accounting_events do
            facts =
              Enum.filter(
                events,
                &(&1["type"] in ~w(request_admitted request_usage_observed request_finished))
              )

            {:ok, ledger, bytes, digest, facts}
          else
            {:ok, ledger, bytes, digest}
          end
        else
          _ -> failed("usage_child_invalid")
        end
      after
        :file.close(io)
      end
    else
      false -> failed("usage_child_bounds")
      _ -> failed("usage_child_invalid")
    end
  end

  defp decode(contents) do
    contents
    |> String.split("\n")
    |> Enum.drop(-1)
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, rows} ->
      case Ipse.JSON.decode_bounded(line, Journal.source_record_bytes()) do
        {:ok, row} when is_map(row) -> {:cont, {:ok, [row | rows]}}
        _ -> {:halt, @error}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  defp private_directory(path) do
    case File.lstat(path) do
      {:ok, %{type: :directory, mode: mode}} when Bitwise.band(mode, 0o022) == 0 -> :ok
      _ -> @error
    end
  end

  defp private_file(path), do: private(path, :regular)

  defp validate_model_actions(events) do
    if Enum.any?(
         events,
         &(Ipse.Extension.ModelCall.operation?(&1["request"]) or
             Ipse.Extension.EmbeddingCall.operation?(&1["request"]))
       ),
       do: Ipse.Extension.Actions.validate_events(events),
       else: :ok
  end

  defp private(path, type) do
    case File.lstat(path) do
      {:ok, %{type: ^type, mode: mode}} when Bitwise.band(mode, 0o077) == 0 -> :ok
      _ -> @error
    end
  end

  defp bound?(s, intent),
    do:
      s["source"]["session_id"] == intent["namespace"] and
        s["identity_sha256"] == intent["identity_sha256"]

  defp fits?(v), do: Ipse.Extension.validate(v) == :ok and byte_size(Jason.encode!(v)) <= 12_288
  defp failed(code), do: {:failed, %{"code" => code}}
  defp count?(v), do: is_integer(v) and v in 0..@limit
  defp keys?(v, fields), do: is_map(v) and Enum.sort(Map.keys(v)) == Enum.sort(fields)
  defp id?(v), do: is_binary(v) and Regex.match?(~r/\A[0-9a-f]{32}\z/, v)
  defp hash?(v), do: is_binary(v) and Regex.match?(~r/\A[0-9a-f]{64}\z/, v)
end
