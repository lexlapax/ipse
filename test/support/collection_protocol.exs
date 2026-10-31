defmodule IpseTest.CollectionProtocol do
  @moduledoc "Pure client/closed-host-envelope model; no Core or native effect dispatch."
  import ExUnit.Assertions
  alias IpseKnowledge.Store.Collection, as: C
  alias IpseKnowledge.Store.Collection.Paged
  alias Ipse.JSON, as: J
  alias Ipse.Extension
  alias Ipse.Extension.CollectionStore

  def new(records, generation) do
    %{
      records:
        Map.new(records, fn {key, value} ->
          {key, %{value: value, revision: generation - 1000}}
        end),
      stages: %{},
      generation: generation,
      reads: 0,
      effects: 0,
      frames: [],
      requests: [],
      part_counts: [],
      outcomes: []
    }
  end

  def reset(model),
    do: %{model | reads: 0, effects: 0, frames: [], requests: [], part_counts: [], outcomes: []}

  def packed_bytes(value) do
    bytes = json(value)

    parts =
      Stream.unfold(bytes, fn
        "" ->
          nil

        rest ->
          part = utf8(rest, min(byte_size(rest), 6144))
          {part, binary_part(rest, byte_size(part), byte_size(rest) - byte_size(part))}
      end)
      |> Enum.to_list()

    byte_size(
      json(%{
        "version" => 1,
        "kind" => "document_value",
        "sha256" => J.sha256(bytes),
        "byte_count" => byte_size(bytes),
        "parts" => parts
      })
    )
  end

  def run(result, model, hook \\ fn _, _ -> :continue end)

  def run({:call, request, continuation}, model, hook) do
    assert CollectionStore.validate(request) == :ok
    frame = %{"api_version" => 1, "kind" => "host_call", "request" => request}
    assert Extension.validate(frame) == :ok
    read = C.read_request?(request)

    model = %{
      model
      | reads: model.reads + if(read, do: 1, else: 0),
        effects: model.effects + if(read, do: 0, else: 1),
        frames: model.frames ++ [byte_size(json(frame))],
        requests: model.requests ++ [request]
    }

    assert model.reads <= 512 and model.effects <= 16

    case hook.(request, model) do
      :stop ->
        {{:call, request, continuation}, model}

      :unknown ->
        {C.resume(continuation, %{"status" => "unknown"}), model}

      :continue ->
        {value, model} = execute(request["request"], model)
        id = length(model.requests) |> Integer.to_string(16) |> String.pad_leading(32, "0")

        wrapped = %{
          "version" => 1,
          "operation_id" => id,
          "request_sha256" => J.digest([request]),
          "result" => value
        }

        assert CollectionStore.valid_outcome?(request, "ok", wrapped, id),
               inspect({request, value}, limit: :infinity)

        outcome = %{"status" => "ok", "value" => wrapped}
        assert Extension.validate(outcome) == :ok

        run(
          C.resume(continuation, outcome),
          %{model | outcomes: model.outcomes ++ [outcome]},
          hook
        )
    end
  end

  def run(terminal, model, _), do: {terminal, model}

  defp execute(%{"op" => "snapshot"}, m),
    do:
      {Map.put(summary(m), "document_store", %{
         "version" => 2,
         "inline_bytes" => 8192,
         "write_parts" => 2
       }), m}

  defp execute(%{"op" => "value.stat"} = r, m) do
    assert r["generation"] == m.generation
    {Map.merge(summary(m), %{"key" => r["key"], "record" => descriptor(m.records[r["key"]])}), m}
  end

  defp execute(%{"op" => "value.read"} = r, m) do
    assert r["generation"] == m.generation
    row = Map.fetch!(m.records, r["key"])
    bytes = json(row.value)
    data = slice(binary_part(bytes, r["offset"], byte_size(bytes) - r["offset"]))
    next = r["offset"] + byte_size(data)

    value =
      Map.merge(summary(m), descriptor(row))
      |> Map.merge(%{
        "key" => r["key"],
        "offset" => r["offset"],
        "data" => data,
        "next" => if(next < byte_size(bytes), do: next)
      })

    {value, m}
  end

  defp execute(%{"op" => "stage.list"}, m),
    do:
      {Map.put(
         summary(m),
         "stages",
         m.stages
         |> Map.values()
         |> Enum.map(&Map.take(&1, ~w(slot epoch state byte_count offset expires_at_ms)))
       ), m}

  defp execute(%{"op" => "stage.inspect"} = r, m) do
    assert r["generation"] == m.generation
    stage = Map.fetch!(m.stages, {r["slot"], r["epoch"]})

    {Map.put(
       summary(m),
       "stage",
       Map.take(
         stage,
         ~w(slot epoch key expected_revision byte_count sha256 state offset expires_at_ms write_publish)
       )
     ), m}
  end

  defp execute(%{"op" => "value.prepare_inline"} = r, m) do
    assert r["generation"] == m.generation
    false = Map.has_key?(m.stages, {r["slot"], r["epoch"]})
    value = Jason.decode!(r["data"])
    assert Paged.native_value?(value)
    assert J.sha256(r["data"]) === r["sha256"] and byte_size(r["data"]) === r["byte_count"]

    stage =
      Map.take(r, ~w(slot epoch key expected_revision byte_count sha256))
      |> Map.merge(%{
        "state" => "sealed",
        "offset" => r["byte_count"],
        "expires_at_ms" => 2_000_000_000_000,
        "value" => value,
        "parts" => [r["data"]]
      })

    m = %{
      m
      | generation: m.generation + 1,
        stages: Map.put(m.stages, {r["slot"], r["epoch"]}, stage),
        part_counts: m.part_counts ++ [div(r["byte_count"] + 6143, 6144)]
    }

    {Map.put(
       mutation(m, r),
       "stage",
       Map.take(
         stage,
         ~w(slot epoch key expected_revision byte_count sha256 state offset expires_at_ms)
       )
       |> Map.put("version", 1)
     ), m}
  end

  defp execute(%{"op" => "value.write_parts"} = r, m) do
    assert r["generation"] == m.generation
    ref = {r["slot"], r["epoch"]}
    previous = Map.get(m.stages, ref, %{"parts" => [], "offset" => 0})
    assert previous["offset"] == r["offset"]
    parts = previous["parts"] ++ r["data"]
    assert length(parts) <= 10
    bytes = IO.iodata_to_binary(parts)
    complete = byte_size(bytes) == r["byte_count"]

    stage =
      Map.take(r, ~w(slot epoch key expected_revision byte_count sha256))
      |> Map.merge(%{
        "state" => if(complete, do: "sealed", else: "open"),
        "offset" => byte_size(bytes),
        "expires_at_ms" => 2_000_000_000_000,
        "write_publish" => r["publish"],
        "parts" => parts
      })

    stage =
      if complete do
        assert J.sha256(bytes) == r["sha256"]
        value = Jason.decode!(bytes)
        assert Paged.native_value?(value)
        Map.put(stage, "value", value)
      else
        stage
      end

    m = %{
      m
      | generation: m.generation + 1,
        stages: Map.put(m.stages, ref, stage),
        part_counts: m.part_counts ++ [length(parts)]
    }

    write =
      Map.take(
        stage,
        ~w(slot epoch key expected_revision byte_count sha256 offset state expires_at_ms)
      )
      |> Map.merge(%{"publish" => r["publish"], "revision" => 0})

    assert r["publish"] == false
    {Map.put(mutation(m, r), "write", write), m}
  end

  defp execute(%{"op" => "commit"} = r, m) do
    assert r["generation"] == m.generation
    next = m.generation + 1

    {records, stages} =
      Enum.reduce(r["stages"], {m.records, m.stages}, fn ref, {records, stages} ->
        stage = Map.fetch!(stages, {ref["slot"], ref["epoch"]})
        assert stage["state"] == "sealed"
        assert (records[stage["key"]] || %{revision: 0}).revision == stage["expected_revision"]
        assert Paged.native_value?(stage["value"])

        {Map.put(records, stage["key"], %{value: stage["value"], revision: next}),
         Map.delete(stages, {ref["slot"], ref["epoch"]})}
      end)

    m = %{m | records: records, stages: stages, generation: next}
    {mutation(m, r), m}
  end

  defp descriptor(nil), do: nil

  defp descriptor(row),
    do: %{
      "revision" => row.revision,
      "sha256" => J.sha256(json(row.value)),
      "byte_count" => byte_size(json(row.value))
    }

  defp summary(m),
    do: %{
      "version" => 3,
      "project" => String.duplicate("a", 64),
      "generation" => m.generation,
      "floor" => m.generation - 1000,
      "floor_anchor" => nil
    }

  defp mutation(m, r),
    do: %{
      "generation" => m.generation,
      "floor" => m.generation - 1000,
      "request_sha256" => J.digest([r])
    }

  defp json(value), do: IO.iodata_to_binary(JSON.encode!(value))
  defp slice(bytes), do: prefix(bytes, 0, min(byte_size(bytes), 6144))
  defp prefix(bytes, low, high) when low == high, do: utf8(bytes, low)

  defp prefix(bytes, low, high) do
    mid = div(low + high + 1, 2)

    if byte_size(json(utf8(bytes, mid))) <= 8192,
      do: prefix(bytes, mid, high),
      else: prefix(bytes, low, mid - 1)
  end

  defp utf8(bytes, n) do
    value = binary_part(bytes, 0, n)
    if String.valid?(value), do: value, else: utf8(bytes, n - 1)
  end
end
