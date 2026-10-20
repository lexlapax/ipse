defmodule IpseKnowledge.Store.MCPCAS do
  @moduledoc false
  @safe 9_007_199_254_740_991

  def start(profile, :snapshot, _args),
    do:
      dispatch(
        %{profile: profile, operation: :snapshot, stage: :directory, records: %{}, calls: 0},
        "snapshot",
        %{}
      )

  def start(profile, :get_many, %{"keys" => keys} = args),
    do:
      get_next(%{
        profile: profile,
        operation: :get_many,
        calls: 0,
        groups: Enum.chunk_every(keys, 8),
        records: [],
        generation: Map.get(args, "generation")
      })

  def start(profile, :put_immutable_many, %{"pages" => pages}),
    do:
      write_next(%{
        profile: profile,
        operation: :put_immutable_many,
        pages: pages,
        records: [],
        calls: 0
      })

  def start(profile, :cas_root, args) do
    case root_arguments(profile, args) do
      {:ok, args} ->
        dispatch(
          %{profile: profile, operation: :cas_root, expected: args, calls: 0},
          "cas_root",
          args
        )

      {:error, code} ->
        error(code)
    end
  end

  def start(profile, :collect, %{"records" => records, "snapshot_generation" => generation}),
    do:
      dispatch(
        %{profile: profile, operation: :collect, expected: records, calls: 0},
        "collect",
        %{"keys" => Enum.map(records, & &1["key"]), "snapshot_generation" => generation}
      )

  def resume(_, %{"status" => "unknown"}), do: {:stop, :unknown_effect}
  def resume(_, %{"status" => "denied"}), do: error(:denied)
  def resume(_, %{"status" => status}) when status != "ok", do: error(:store_refused)

  def resume(%{phase: :call} = state, %{"status" => "ok", "value" => descriptor}) do
    if keys?(descriptor, ~w(version operation_id kind source_sha256 byte_count)) and
         descriptor["version"] === 1 and descriptor["kind"] == "mcp.text" and
         id?(descriptor["operation_id"]) and hash?(descriptor["source_sha256"]) and
         is_integer(descriptor["byte_count"]) and descriptor["byte_count"] in 1..60_000,
       do:
         read(
           %{state | phase: :read}
           |> Map.merge(%{descriptor: descriptor, text: "", offset: 0})
         ),
       else: error(:store_response)
  end

  def resume(%{phase: :read} = state, %{"status" => "ok", "value" => page}) do
    descriptor = state.descriptor

    if keys?(page, ~w(version operation_id kind source_sha256 offset next complete text)) and
         page["version"] === 1 and page["kind"] == "mcp.text" and
         page["operation_id"] == descriptor["operation_id"] and
         page["source_sha256"] == descriptor["source_sha256"] and
         page["offset"] === state.offset and is_binary(page["text"]) and
         String.valid?(page["text"]) and
         byte_size(page["text"]) <= 4096 and is_boolean(page["complete"]) do
      text = state.text <> page["text"]
      next = byte_size(text)

      cond do
        next > descriptor["byte_count"] ->
          error(:store_response)

        page["complete"] and page["next"] == nil and next == descriptor["byte_count"] ->
          consume(state, JSON.decode!(text))

        not page["complete"] and page["next"] === next and next > state.offset ->
          read(%{state | text: text, offset: next})

        true ->
          error(:store_response)
      end
    else
      error(:store_response)
    end
  rescue
    _ -> error(:store_response)
  end

  def resume(_, _), do: error(:store_response)

  defp root_arguments(profile, args) do
    fields =
      ~w(key expected_revision expected_source_generation expected_content_sha256 draft_id next_root)

    case profile["contract"] do
      "ipse-cas-v1" ->
        legacy = Map.delete(args, "expected_generation")

        if args["expected_generation"] == nil and keys?(legacy, fields) and
             uint?(args["expected_revision"]) and
             args["expected_revision"] > 0,
           do: {:ok, legacy},
           else: {:error, :atomic_admission_unavailable}

      "ipse-cas-v2" ->
        args = Map.put_new(args, "expected_generation", nil)

        if keys?(args, ["expected_generation" | fields]) and
             uint?(args["expected_revision"]) and
             (uint?(args["expected_generation"]) or
                (args["expected_generation"] == nil and args["expected_revision"] > 0)),
           do: {:ok, args},
           else: {:error, :atomic_admission_unavailable}

      _ ->
        {:error, :store_response}
    end
  end

  defp envelope(profile, action, args, request_id),
    do: %{
      "version" => if(profile["contract"] == "ipse-cas-v2", do: 2, else: 1),
      "contract" => profile["contract"],
      "partition" => profile["partition"],
      "request_id" => request_id,
      "action" => action,
      "args" => args
    }

  defp dispatch(state, action, args) do
    id = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    envelope = envelope(state.profile, action, args, id)

    request = %{
      "op" => "mcp.call",
      "version" => 1,
      "binding" => state.profile["binding"],
      "arguments" => envelope,
      "timeout_ms" => 30_000
    }

    if state.profile["contract"] in ~w(ipse-cas-v1 ipse-cas-v2) and
         bounded_request?(request) and state.calls < 16 do
      {:call, request,
       Map.merge(state, %{phase: :call, envelope: envelope, calls: state.calls + 1})}
    else
      error(:effect_limit)
    end
  end

  defp read(state) do
    {:call,
     %{
       "op" => "effect.result.read",
       "version" => 1,
       "operation_id" => state.descriptor["operation_id"],
       "source_sha256" => state.descriptor["source_sha256"],
       "offset" => state.offset,
       "limit" => 4096
     }, state}
  end

  defp consume(state, envelope) do
    if keys?(envelope, ~w(version contract partition request_id action status generation value)) and
         Enum.all?(~w(version contract partition request_id action), fn field ->
           envelope[field] === state.envelope[field]
         end) and
         envelope["status"] in ~w(ok conflict refused) and uint?(envelope["generation"]) and
         is_map(envelope["value"]) do
      case envelope["status"] do
        "ok" -> accept(state, envelope["value"], envelope["generation"])
        "conflict" -> conflict(state, envelope["value"], envelope["generation"])
        _ -> error(:store_refused)
      end
    else
      error(:store_response)
    end
  end

  defp conflict(
         %{operation: :cas_root, profile: %{"contract" => "ipse-cas-v2"}} = state,
         value,
         generation
       ) do
    summary = value["record"]
    expected = state.expected

    if keys?(value, ["record"]) and conflict_record?(summary, generation) and
         summary["key"] == expected["key"] and
         (summary["revision"] !== expected["expected_revision"] or
            (expected["expected_generation"] != nil and
               generation !== expected["expected_generation"]) or
            summary["source_generation"] !== expected["expected_source_generation"] or
            summary["content_sha256"] !== expected["expected_content_sha256"] or
            summary["draft_id"] !== expected["draft_id"]),
       do: error(:conflict),
       else: error(:store_response)
  end

  defp conflict(_, _, _), do: error(:conflict)

  defp conflict_record?(record, generation) do
    keys?(record, ~w(key revision deleted source_generation content_sha256 draft_id)) and
      hash?(record["key"]) and uint?(record["revision"]) and
      record["revision"] <= generation and is_boolean(record["deleted"]) and
      if record["deleted"] do
        Enum.all?(~w(source_generation content_sha256 draft_id), &(record[&1] == nil))
      else
        record["revision"] > 0 and uint?(record["source_generation"]) and
          record["source_generation"] > 0 and
          ((record["content_sha256"] == nil and record["draft_id"] == nil) or
             (hash?(record["content_sha256"]) and
                (record["draft_id"] == nil or id?(record["draft_id"]))))
      end
  end

  defp accept(%{operation: :snapshot, stage: :directory} = state, value, generation) do
    rows = value["records"]

    if keys?(value, ~w(records count bytes complete)) and value["complete"] === true and
         is_list(rows) and length(rows) <= 256 and value["count"] === length(rows) and
         uint?(value["bytes"]) and value["bytes"] <= 1_048_576 and
         Enum.all?(rows, &(metadata?(&1) and valid_record_generation?(state, &1, generation))) and
         length(Enum.uniq_by(rows, & &1["key"])) == length(rows) do
      groups = rows |> Enum.map(& &1["key"]) |> Enum.chunk_every(8)

      if length(groups) + 1 > 12 do
        error(:remote_snapshot_limit)
      else
        snapshot_next(
          Map.merge(state, %{
            stage: :records,
            groups: groups,
            directory: rows,
            generation: generation,
            bytes: value["bytes"]
          })
        )
      end
    else
      error(:store_response)
    end
  end

  defp accept(%{operation: :snapshot, stage: :records} = state, value, generation) do
    [keys | rest] = state.groups

    with true <- generation == state.generation,
         {:ok, records} <- rows(value, keys),
         true <-
           Enum.all?(records, fn row ->
             metadata = Enum.find(state.directory, &(&1["key"] == row["key"]))

             Map.take(row, ~w(key revision deleted)) ==
               Map.take(metadata, ~w(key revision deleted))
           end) do
      all = Enum.reduce(records, state.records, &Map.put(&2, &1["key"], &1))
      snapshot_next(%{state | groups: rest, records: all})
    else
      _ -> error(:store_response)
    end
  end

  defp accept(%{operation: :get_many} = state, value, generation) do
    with true <- state.generation == nil or state.generation == generation,
         {:ok, records} <- rows(value, state.envelope["args"]["keys"]),
         true <- Enum.all?(records, &valid_record_generation?(state, &1, generation)) do
      get_next(%{
        state
        | groups: tl(state.groups),
          records: state.records ++ records,
          generation: generation
      })
    else
      _ -> error(:snapshot_changed)
    end
  end

  defp accept(%{operation: :put_immutable_many} = state, value, generation) do
    count = length(state.envelope["args"]["pages"])
    expected = Enum.take(state.pages, count)

    with true <- keys?(value, ["records"]),
         true <- is_list(value["records"]) and length(value["records"]) == count,
         true <-
           Enum.zip(value["records"], expected)
           |> Enum.all?(fn {actual, page} ->
             record?(actual) and actual["key"] == page["key"] and actual["revision"] == 1 and
               valid_record_generation?(state, actual, generation) and
               actual["deleted"] == false and actual["value"] === page["value"]
           end) do
      write_next(%{
        state
        | pages: Enum.drop(state.pages, count),
          records: state.records ++ value["records"]
      })
    else
      _ -> error(:store_response)
    end
  end

  defp accept(%{operation: :cas_root} = state, value, generation) do
    record = value["record"]

    if keys?(value, ["record"]) and record?(record) and
         valid_record_generation?(state, record, generation) and
         record["key"] == state.expected["key"] and
         record["revision"] == state.expected["expected_revision"] + 1 and
         record["deleted"] == false and record["value"] === state.expected["next_root"] and
         (state.expected["expected_generation"] == nil or
            generation === state.expected["expected_generation"] + 1),
       do: {:done, {:ok, %{"record" => record, "generation" => generation}}},
       else: error(:store_response)
  end

  defp accept(%{operation: :collect} = state, value, generation) do
    records = value["records"]

    if keys?(value, ["records"]) and is_list(records) and
         (state.profile["contract"] == "ipse-cas-v1" or
            generation == state.envelope["args"]["snapshot_generation"] + 1) and
         length(records) == length(state.expected) and
         Enum.zip(records, state.expected)
         |> Enum.all?(fn {record, old} ->
           record?(record) and record["key"] == old["key"] and
             valid_record_generation?(state, record, generation) and
             record["revision"] == old["revision"] + 1 and record["deleted"] and
             record["value"] == nil
         end),
       do: {:done, {:ok, %{"records" => records, "generation" => generation}}},
       else: error(:store_response)
  end

  defp valid_record_generation?(state, record, generation),
    do:
      state.profile["contract"] == "ipse-cas-v1" or
        (record["revision"] <= generation and
           (record["revision"] > 0 or record["deleted"]))

  defp snapshot_next(%{groups: []} = state),
    do:
      {:done,
       {:ok,
        %{
          "records" => state.records,
          "generation" => state.generation,
          "bytes" => state.bytes,
          "reads" => state.calls
        }}}

  defp snapshot_next(%{groups: [keys | _]} = state),
    do: dispatch(state, "get_many", %{"keys" => keys})

  defp get_next(%{groups: []} = state),
    do:
      {:done,
       {:ok,
        %{"records" => state.records, "generation" => state.generation, "reads" => state.calls}}}

  defp get_next(%{groups: [keys | _]} = state), do: dispatch(state, "get_many", %{"keys" => keys})

  defp write_next(%{pages: []} = state), do: {:done, {:ok, %{"records" => state.records}}}

  defp write_next(state) do
    pair = Enum.take(state.pages, 2)
    args = %{"pages" => Enum.map(pair, &Map.put(&1, "expected_revision", 0))}

    pair_request = %{
      "op" => "mcp.call",
      "version" => 1,
      "binding" => state.profile["binding"],
      "timeout_ms" => 30_000,
      "arguments" =>
        envelope(state.profile, "put_immutable_many", args, String.duplicate("0", 32))
    }

    pages = if bounded_request?(pair_request), do: pair, else: Enum.take(pair, 1)

    dispatch(state, "put_immutable_many", %{
      "pages" => Enum.map(pages, &Map.put(&1, "expected_revision", 0))
    })
  end

  defp rows(value, keys) do
    records = value["records"]

    if keys?(value, ~w(records complete)) and value["complete"] === true and is_list(records) and
         Enum.map(records, & &1["key"]) == keys and Enum.all?(records, &record?/1),
       do: {:ok, records},
       else: :error
  end

  def record?(record),
    do:
      keys?(record, ~w(key revision deleted value)) and hash?(record["key"]) and
        uint?(record["revision"]) and is_boolean(record["deleted"]) and
        if(record["deleted"], do: record["value"] == nil, else: is_map(record["value"]))

  defp metadata?(record),
    do:
      keys?(record, ~w(key revision deleted kind)) and hash?(record["key"]) and
        uint?(record["revision"]) and record["revision"] > 0 and is_boolean(record["deleted"]) and
        record["kind"] in ~w(root page tombstone)

  defp bounded_request?(request),
    do:
      Ipse.Extension.validate(request) == :ok and
        byte_size(IO.iodata_to_binary(JSON.encode!(request))) <= 15_000 and
        pretty_bound(request, 0) <= 32_768

  defp pretty_bound(map, depth) when is_map(map),
    do:
      2 +
        Enum.sum(
          for {key, value} <- map,
              do:
                byte_size(IO.iodata_to_binary(JSON.encode!(key))) + pretty_bound(value, depth + 1) +
                  depth * 2 + 6
        )

  defp pretty_bound(list, depth) when is_list(list),
    do: 2 + Enum.sum(for value <- list, do: pretty_bound(value, depth + 1) + depth * 2 + 4)

  defp pretty_bound(value, _), do: byte_size(IO.iodata_to_binary(JSON.encode!(value)))
  defp keys?(value, fields), do: is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(fields)
  defp uint?(value), do: is_integer(value) and value in 0..@safe
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
  defp error(code), do: {:done, {:error, code, %{}}}
end
