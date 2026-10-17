defmodule Ipse.Extensions.ChildUsage do
  @moduledoc "Explicit parent-bound discovery and frozen reads of registered child accounting."
  alias Ipse.{Usage, Journal, Runner, WorkspaceContext}
  alias Ipse.Extensions.Manifest
  alias Ipse.Lifecycle.Source
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

    keys?(s, @snapshot ++ extra) and s["version"] in [2, 3] and
      Source.valid_metadata?(s["source"]) and id?(s["operation_id"]) and
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
                 Map.merge(base(c, 3), %{
                   "child_id" => r["child_id"],
                   "request_count" => length(ledger.order),
                   "legacy_unmetered" => ledger.legacy_unmetered,
                   "bytes" => bytes,
                   "sha256" => digest
                 }),
             true <-
               snapshot["request_count"] == length(ledger.order) and
                 snapshot["legacy_unmetered"] == ledger.legacy_unmetered do
          page(r, snapshot, Enum.map(ledger.order, &Usage.request_record(ledger.requests[&1])))
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
    version = if r["op"] == "usage.children", do: 2, else: 3

    cond do
      s == nil -> {:ok, nil}
      s["version"] != version or not bound?(s, c.intent) -> failed("usage_child_snapshot")
      c.state.reads[s["operation_id"]] != s -> failed("usage_child_snapshot")
      version == 3 and s["child_id"] != r["child_id"] -> failed("usage_child_snapshot")
      true -> {:ok, s}
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
        "version" => 1,
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
      value["version"] === 1 and value["scope"] == if(child, do: "child", else: "children") and
      value["coverage"] == if(child, do: "canonical_requests", else: "registered_children") and
      snapshot?(snapshot) and snapshot["version"] == if(child, do: 3, else: 2) and
      (snapshot == r["snapshot"] or
         (r["snapshot"] == nil and snapshot["operation_id"] == operation)) and
      (not child or snapshot["child_id"] == r["child_id"]) and
      value["cursor"] === r["cursor"] and r["cursor"] <= count and is_list(rows) and
      length(rows) == min(r["limit"], count - r["cursor"]) and
      value["next"] === if(r["cursor"] + length(rows) < count, do: r["cursor"] + length(rows)) and
      Enum.all?(rows, fn row ->
        if child do
          Usage.valid_request_record?(row) and row["session_id"] == r["child_id"] and
            row["parent_session_id"] == snapshot["source"]["session_id"]
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

          if pending == Ipse.Extensions.Actions.result_intent(e) do
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
               {:ok, metadata} <- Source.metadata(actual),
               true <- metadata == source and record == intents[operation] do
            if snapshot["version"] == 3 do
              with {:ok, ledger, _, _} <-
                     read_child(directory, session, state.index[snapshot["child_id"]], snapshot) do
                rows = Enum.map(ledger.order, &Usage.request_record(ledger.requests[&1]))

                length(ledger.order) == snapshot["request_count"] and
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
         {:ok, root} <- WorkspaceContext.canonical_path(directory),
         :ok <- private(root, :directory),
         path = Path.join([root, "subagents", parent]),
         :ok <- private_directory(Path.join(root, "subagents")),
         :ok <- private_directory(path),
         {:ok, ^path} <- WorkspaceContext.canonical_path(path),
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
             true <-
               Enum.all?(ledger.requests, fn {_, r} ->
                 r.admission["parent_session_id"] == parent and
                   r.admission["parent_request_id"] == child["parent_request_id"]
               end),
             digest =
               Ipse.Compaction.digest([
                 Enum.map(ledger.order, &Usage.request_record(ledger.requests[&1]))
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
      case Manifest.decode_json(line, Source.record_bytes()) do
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
