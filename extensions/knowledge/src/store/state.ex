defmodule IpseKnowledge.Store.State do
  @moduledoc false
  @safe 9_007_199_254_740_991

  def start(profile, :snapshot, _args) do
    next(%{
      profile: profile,
      operation: :snapshot,
      records: %{},
      generation: nil,
      after: nil,
      reads: 0
    })
  end

  def start(profile, :get_many, %{"keys" => keys}) do
    next(%{
      profile: profile,
      operation: :get_many,
      keys: keys,
      records: [],
      generation: nil,
      reads: 0
    })
  end

  def start(profile, :put_immutable_many, %{"pages" => pages}) do
    next(%{profile: profile, operation: :put_immutable_many, pages: pages, records: [], reads: 0})
  end

  def start(profile, :cas_root, args) do
    request = %{
      "op" => "state.put",
      "scope" => profile["scope"],
      "key" => args["key"],
      "expected_revision" => args["expected_revision"],
      "value" => args["next_root"]
    }

    {:call, request, %{profile: profile, operation: :cas_root, request: request}}
  end

  def start(profile, :collect, %{"records" => records}) do
    next(%{profile: profile, operation: :collect, pending: records, records: [], reads: 0})
  end

  def resume(_state, %{"status" => "unknown"}), do: {:stop, :unknown_effect}
  def resume(_state, %{"status" => "conflict"}), do: error(:conflict)
  def resume(_state, %{"status" => "denied"}), do: error(:denied)
  def resume(_state, %{"status" => status}) when status != "ok", do: error(:store_refused)

  def resume(%{operation: :snapshot} = state, %{"status" => "ok", "value" => value}) do
    rows = value["records"]
    generation = value["generation"]
    cursor = value["next"]

    if keys?(value, ~w(generation records next)) and uint?(generation) and
         (state.generation == nil or state.generation == generation) and is_list(rows) and
         length(rows) in 0..16 and Enum.all?(rows, &record?/1) and
         Enum.all?(
           rows,
           &(&1["revision"] > 0 and (state.after == nil or &1["key"] > state.after))
         ) and
         Enum.map(rows, & &1["key"]) == Enum.sort(Enum.uniq(Enum.map(rows, & &1["key"]))) and
         (cursor == nil or (rows != [] and cursor == List.last(rows)["key"])) and
         Enum.all?(rows, &(not Map.has_key?(state.records, &1["key"]))) do
      records = Enum.reduce(rows, state.records, &Map.put(&2, &1["key"], &1))

      cond do
        map_size(records) > 256 ->
          error(:store_bounds)

        cursor == nil ->
          {:done,
           {:ok,
            %{
              "records" => records,
              "generation" => generation,
              "bytes" => encoded_size(records, generation),
              "reads" => state.reads + 1
            }}}

        state.reads + 1 >= 256 ->
          error(:store_bounds)

        true ->
          next(%{
            state
            | records: records,
              generation: generation,
              after: cursor,
              reads: state.reads + 1
          })
      end
    else
      error(:store_response)
    end
  rescue
    _ -> error(:store_response)
  end

  def resume(%{operation: :get_many} = state, %{"status" => "ok", "value" => value}) do
    [key | rest] = state.keys
    record = value["record"]

    if keys?(value, ~w(generation record)) and uint?(value["generation"]) and
         (state.generation == nil or state.generation == value["generation"]) and record?(record) and
         record["key"] == key do
      next(%{
        state
        | keys: rest,
          records: state.records ++ [record],
          generation: value["generation"],
          reads: state.reads + 1
      })
    else
      error(:store_response)
    end
  rescue
    _ -> error(:store_response)
  end

  def resume(%{operation: operation} = state, %{"status" => "ok", "value" => value})
      when operation in [:put_immutable_many, :cas_root, :collect] do
    record = value["record"]
    request = state.request
    expected_value = if operation == :collect, do: nil, else: request["value"]

    if keys?(value, ~w(generation record)) and uint?(value["generation"]) and record?(record) and
         record["key"] == request["key"] and
         record["revision"] == request["expected_revision"] + 1 and
         record["value"] === expected_value and record["deleted"] == (operation == :collect) do
      case operation do
        :cas_root ->
          {:done, {:ok, %{"record" => record, "generation" => value["generation"]}}}

        :put_immutable_many ->
          next(%{state | pages: tl(state.pages), records: state.records ++ [record]})

        :collect ->
          next(%{state | pending: tl(state.pending), records: state.records ++ [record]})
      end
    else
      error(:store_response)
    end
  rescue
    _ -> error(:store_response)
  end

  def resume(_, _), do: error(:store_response)

  defp next(%{operation: :snapshot} = state) do
    request = %{
      "op" => "state.scan",
      "scope" => state.profile["scope"],
      "after" => state.after,
      "generation" => state.generation,
      "limit" => 16
    }

    {:call, request, state}
  end

  defp next(%{operation: :get_many, keys: []} = state),
    do:
      {:done,
       {:ok,
        %{"records" => state.records, "generation" => state.generation, "reads" => state.reads}}}

  defp next(%{operation: :get_many, keys: [key | _]} = state),
    do: {:call, %{"op" => "state.get", "scope" => state.profile["scope"], "key" => key}, state}

  defp next(%{operation: :put_immutable_many, pages: []} = state),
    do: {:done, {:ok, %{"records" => state.records}}}

  defp next(%{operation: :put_immutable_many, pages: [page | _]} = state) do
    request = %{
      "op" => "state.put",
      "scope" => state.profile["scope"],
      "key" => page["key"],
      "expected_revision" => 0,
      "value" => page["value"]
    }

    {:call, request, Map.put(state, :request, request)}
  end

  defp next(%{operation: :collect, pending: []} = state),
    do: {:done, {:ok, %{"records" => state.records}}}

  defp next(%{operation: :collect, pending: [record | _]} = state) do
    request = %{
      "op" => "state.delete",
      "scope" => state.profile["scope"],
      "key" => record["key"],
      "expected_revision" => record["revision"]
    }

    {:call, request, Map.put(state, :request, request)}
  end

  def record?(record) do
    keys?(record, ~w(key revision deleted value operation_id)) and is_binary(record["key"]) and
      byte_size(record["key"]) in 1..64 and uint?(record["revision"]) and
      is_boolean(record["deleted"]) and
      if(record["revision"] == 0,
        do: record["deleted"] and record["value"] == nil and record["operation_id"] == nil,
        else:
          id?(record["operation_id"]) and
            if(record["deleted"], do: record["value"] == nil, else: is_map(record["value"]))
      )
  rescue
    _ -> false
  end

  defp encoded_size(records, generation),
    do:
      byte_size(
        IO.iodata_to_binary(
          JSON.encode!(%{
            "version" => 1,
            "namespace" => String.duplicate("0", 64),
            "generation" => generation,
            "records" => records
          })
        )
      )

  defp keys?(value, fields), do: is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(fields)
  defp uint?(value), do: is_integer(value) and value in 0..@safe
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
  defp error(code), do: {:done, {:error, code, %{}}}
end
