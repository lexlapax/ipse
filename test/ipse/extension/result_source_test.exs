defmodule Ipse.Extension.ResultSourceTest do
  use ExUnit.Case, async: true

  alias Ipse.Extension.{Registry, Invocation, ResultDocument, ResultSource}
  alias ResultSource.{Index, Sealed}

  @schema %{"type" => "object", "additionalProperties" => true}

  test "binds output identity to the original intent, total bytes and exact digest" do
    intent = intent()
    bytes = Jason.encode!(%{"quote" => "a complete quotation"})
    assert {:ok, begin, source} = ResultSource.open(intent, offer(bytes), 10)
    assert begin["intent_sha256"] == Ipse.JSON.digest([intent])
    assert begin["schema_sha256"] == Ipse.JSON.digest([@schema])

    assert begin["output_id"] ==
             Ipse.JSON.digest([
               %{
                 "intent_sha256" => Ipse.JSON.digest([intent]),
                 "byte_count" => byte_size(bytes),
                 "sha256" => Ipse.JSON.sha256(bytes)
               }
             ])

    assert ResultSource.valid_descriptor?(ResultSource.descriptor(source))
    refute ResultSource.valid_descriptor?(Map.put(ResultSource.descriptor(source), "extra", true))
    assert {:ok, request} = ResultSource.request(source)
    assert request["offset"] == 0 and request["limit"] == 4096
    assert request["output_id"] == begin["output_id"]

    tool =
      intent
      |> put_in(["descriptor", "stage"], "invoke.tool")
      |> update_in(["identity", "capabilities"], &["invoke.tool" | &1])
      |> Map.merge(%{
        "parent_call_id" => "source-call",
        "parent_request_id" => Ipse.Usage.id(),
        "approval" => "approved"
      })

    assert :ok = Invocation.validate_intent(tool)
    assert {:ok, _, _} = ResultSource.open(tool, offer(bytes), 10)
  end

  test "rejects missing SDK grant, unsupported original stage and malformed offers" do
    original = intent()

    legacy =
      original
      |> put_in(["identity", "sdk"], 1)
      |> update_in(["identity", "capabilities"], &List.delete(&1, "invoke.result.pages"))

    assert :ok = Invocation.validate_intent(legacy)

    service =
      original
      |> put_in(["descriptor", "stage"], "invoke.service")
      |> update_in(["identity", "capabilities"], &["invoke.service" | &1])

    assert :ok = Invocation.validate_intent(service)

    for rejected <- [legacy, service],
        do: assert({:error, _} = ResultSource.open(rejected, offer("{}"), 0))

    for bad <- [
          Map.put(offer("{}"), "extra", true),
          put_in(offer("{}"), ["output", "byte_count"], 0),
          put_in(offer("{}"), ["output", "byte_count"], 4_194_305),
          put_in(offer("{}"), ["output", "sha256"], "bad")
        ] do
      assert {:error, _} = ResultSource.open(original, bad, 0)
    end

    for elapsed <- [-1, 120_001, 1.0],
        do: assert({:error, _} = ResultSource.open(original, offer("{}"), elapsed))
  end

  test "accepts fixed pages with UTF8 and JSON tokens split across byte fragments" do
    value = %{"text" => String.duplicate("é🙂", 1300)}
    assert {:ok, bytes} = ResultDocument.encode(value, @schema)
    {intent, begin, chunks, source} = drain(bytes)
    assert length(chunks) == 2
    refute String.valid?(Base.decode64!(hd(chunks)["data_base64"]))
    assert {:error, _} = ResultSource.request(source)
    assert {:ok, proof, sealed} = ResultSource.seal(source, 20)
    assert proof.event["chunks_sha256"] == Ipse.JSON.digest(chunks)
    assert proof.event["chunk_count"] == 2
    assert {:ok, same_event, accepted} = ResultSource.accept_verified(source, proof)
    assert same_event == proof.event
    assert accepted.phase == sealed.phase
    final = final(intent, sealed, 21)
    assert {:ok, index} = ResultSource.restore([intent, begin] ++ chunks ++ [proof.event, final])
    assert ResultSource.published?(index, final)
    refute ResultSource.published?(index, Map.put(final, "elapsed_ms", 22))

    assert {:ok, %{bytes: ^bytes, value: ^value, provenance: "historical_receipt"}} =
             ResultSource.materialize(index, final["delivery"])
  end

  test "does not publish offers, chunks or a valid seal without the final receipt" do
    {intent, begin, chunks, source} = drain(Jason.encode!(%{"items" => Enum.to_list(1..256)}))
    assert {:ok, proof, _} = ResultSource.seal(source, 20)

    for prefix <- [
          [intent],
          [intent, begin],
          [intent, begin] ++ chunks,
          [intent, begin] ++ chunks ++ [proof.event]
        ] do
      assert {:ok, index} = ResultSource.restore(prefix)
      assert map_size(index.committed) == 0
      assert {:error, _} = ResultSource.readable_source(index, ResultSource.descriptor(source))
      assert {:error, _} = ResultSource.materialize(index, ResultSource.descriptor(source))
    end
  end

  test "complete invalid JSON, schema violations and a wrong total hash stay legal unsealed prefixes" do
    schema = %{
      "type" => "object",
      "required" => ["required"],
      "properties" => %{"required" => %{"type" => "boolean"}},
      "additionalProperties" => false
    }

    for {bytes, custom_intent} <- [
          {"{malformed}", intent()},
          {"{\"extra\":true}", intent(schema)}
        ] do
      {intent, begin, chunks, source} = drain(bytes, custom_intent)
      assert {:error, _} = ResultSource.seal(source, 20)
      assert {:ok, index} = ResultSource.restore([intent, begin] ++ chunks)
      assert map_size(index.committed) == 0
      forged_seal = unsafe_seal(source, chunks, 20)
      assert {:error, _} = ResultSource.restore([intent, begin] ++ chunks ++ [forged_seal])
    end

    {intent, begin, chunks, source} = drain("{}", intent(), String.duplicate("f", 64))
    assert {:ok, _} = ResultSource.restore([intent, begin] ++ chunks)
    assert {:error, _} = ResultSource.seal(source, 20)
  end

  test "refuses incomplete, short, repeated, out-of-order, foreign and corrupted fragments" do
    bytes = Jason.encode!(%{"quote" => String.duplicate("a", 8192)})
    {:ok, _, source} = ResultSource.open(intent(), offer(bytes), 10)
    valid = reply(source, bytes)

    for bad <- [
          put_in(valid, ["output", "offset"], 1),
          put_in(valid, ["output", "next"], 4095),
          put_in(valid, ["output", "complete"], true),
          put_in(valid, ["output", "output_id"], String.duplicate("b", 64)),
          put_in(valid, ["output", "sha256"], String.duplicate("b", 64)),
          put_in(valid, ["output", "data_base64"], "bad"),
          Map.put(valid, "extra", 1)
        ] do
      assert {:error, _} = ResultSource.push(source, bad)
    end

    assert {:error, _} = ResultSource.seal(source, 20)
    assert {:ok, _, advanced} = ResultSource.push(source, valid)
    assert {:error, _} = ResultSource.push(advanced, valid)
    assert {:error, _} = ResultSource.push(source, reply(advanced, bytes))
  end

  test "acknowledges exact earlier internal replies without accepting another durable chunk" do
    bytes = Jason.encode!(%{"quote" => String.duplicate("a", 8192)})
    {:ok, _, source} = ResultSource.open(intent(), offer(bytes), 10)
    first = reply(source, bytes)
    refute ResultSource.acknowledged?(source, first)
    {:ok, _, one} = ResultSource.push(source, first)
    second = reply(one, bytes)
    {:ok, _, two} = ResultSource.push(one, second)
    assert ResultSource.acknowledged?(two, first)
    assert ResultSource.acknowledged?(two, second)
    refute ResultSource.acknowledged?(two, reply(two, bytes))
    assert {:error, _} = ResultSource.push(two, first)

    for altered <- [
          put_in(first, ["output", "output_id"], String.duplicate("f", 64)),
          put_in(first, ["output", "sha256"], String.duplicate("f", 64)),
          put_in(first, ["output", "data_base64"], Base.encode64("changed")),
          put_in(first, ["output", "complete"], true),
          put_in(first, ["output", "next"], 4095),
          Map.put(first, "extra", true)
        ] do
      refute ResultSource.acknowledged?(two, altered)
    end
  end

  test "rejects tampered source envelopes, closure commitments and final receipts" do
    {intent, begin, chunks, source} = drain(Jason.encode!(%{"ok" => true}))
    {:ok, proof, sealed} = ResultSource.seal(source, 20)
    final = final(intent, sealed, 21)
    valid = [intent, begin] ++ chunks ++ [proof.event, final]

    for field <-
          ~w(output_id invocation_id intent_sha256 schema_sha256 sha256 byte_count version elapsed_ms) do
      bad_begin = Map.put(begin, field, "tampered")
      assert {:error, _} = ResultSource.restore([intent, bad_begin] ++ chunks)
    end

    assert {:error, _} = ResultSource.restore([intent, Map.put(begin, "extra", 1)] ++ chunks)

    for field <-
          ~w(output_id invocation_id byte_count chunk_count sha256 chunks_sha256 elapsed_ms version) do
      bad_seal = Map.put(proof.event, field, "tampered")
      assert {:error, _} = ResultSource.restore([intent, begin] ++ chunks ++ [bad_seal, final])
    end

    for bad_final <- [
          Map.put(final, "value", %{}),
          Map.put(final, "extra", 1),
          Map.put(final, "elapsed_ms", 19),
          Map.put(final, "text", "{}"),
          put_in(final, ["delivery", "sha256"], String.duplicate("f", 64)),
          put_in(final, ["identity", "options_sha256"], String.duplicate("f", 64))
        ] do
      assert {:error, _} = ResultSource.restore(Enum.drop(valid, -1) ++ [bad_final])
    end

    assert {:error, _} = ResultSource.restore([intent, final])
    assert {:error, _} = ResultSource.restore(valid ++ [final])
    assert {:error, _} = ResultSource.restore([intent, begin, begin])
    assert {:error, _} = ResultSource.restore([intent, begin] ++ chunks ++ chunks)

    for field <- ~w(output_id invocation_id offset next byte_count sha256 data_base64 version) do
      [first | rest] = chunks

      assert {:error, _} =
               ResultSource.restore([intent, begin, Map.put(first, field, "tampered")] ++ rest)
    end

    assert {:error, _} =
             ResultSource.restore(
               [intent, begin] ++ chunks ++ [Map.put(proof.event, "elapsed_ms", 9)]
             )

    assert {:error, _} =
             ResultSource.restore(Enum.drop(valid, -1) ++ [Map.put(final, "elapsed_ms", 120_001)])
  end

  test "refuses source advancement after cancellation, a user turn, a new lease or question recovery" do
    {intent, begin, chunks, _} = drain("{}")

    for boundary <- [
          %{"type" => "cancelled"},
          %{"type" => "turn_finished"},
          %{"type" => "message", "message" => %{"role" => "user", "content" => "new task"}}
        ] do
      assert {:ok, _} = ResultSource.restore([intent, begin, boundary])
      assert {:error, _} = ResultSource.restore([intent, begin, boundary] ++ chunks)
    end

    next = intent()
    assert {:error, _} = ResultSource.restore([intent, begin, next])

    assert {:error, _} =
             ResultSource.restore([intent, begin, %{"type" => "cancelled"}, next] ++ chunks)

    for type <-
          ~w(extension_question extension_continuation_intent extension_action_intent extension_action_result) do
      event = %{"type" => type, "parent_invocation_id" => intent["invocation_id"]}
      assert {:error, _} = ResultSource.restore([intent, begin, event])

      if type in ~w(extension_question extension_continuation_intent) do
        assert {:error, _} = ResultSource.restore([intent, event, begin])
      end
    end
  end

  test "legacy inline results cannot replace an already begun source" do
    {intent, begin, _, _} = drain("{}")

    assert {:ok, inline} =
             Invocation.build_result(intent, %{
               "api_version" => 1,
               "kind" => "result",
               "value" => %{}
             })

    assert {:ok, _} = ResultSource.restore([intent, inline])
    assert {:error, _} = ResultSource.restore([intent, begin, inline])
    assert {:error, _} = ResultSource.restore([%{"type" => "extension_output_unknown"}])
  end

  test "trusted online proofs must match independently accumulated source metadata" do
    {_, _, _, source} = drain("{}")
    {:ok, proof, _} = ResultSource.seal(source, 20)

    assert {:error, _} =
             ResultSource.accept_verified(source, %Sealed{
               proof
               | begin_sha256: String.duplicate("f", 64)
             })

    assert {:error, _} =
             ResultSource.accept_verified(source, %Sealed{
               proof
               | event: Map.put(proof.event, "chunks_sha256", String.duplicate("f", 64))
             })

    assert {:error, _} =
             ResultSource.accept_verified(source, %Sealed{
               proof
               | event: Map.put(proof.event, "elapsed_ms", 9)
             })

    assert {:error, _} = ResultSource.accept_verified(source, Map.from_struct(proof))
    assert {:ok, _, _} = ResultSource.accept_verified(source, proof)
  end

  test "live index and offline restore agree on quota, closure and materialization" do
    intent = intent()
    bytes = Jason.encode!(%{"quote" => String.duplicate("x", 8192)})
    {:ok, begin, _, index} = ResultSource.index_open(%Index{}, intent, offer(bytes), 10)
    {index, chunks} = index_drain(index, begin["output_id"], bytes)
    {:ok, source} = ResultSource.source(index, begin["output_id"])
    {:ok, proof, _} = ResultSource.seal(source, 20)

    {:ok, seal, sealed, index} =
      ResultSource.index_accept_verified(index, begin["output_id"], proof)

    final = final(intent, sealed, 21)
    {:ok, index} = ResultSource.publish(index, final)
    assert ResultSource.published?(index, final)
    {:ok, restored} = ResultSource.restore([intent, begin] ++ chunks ++ [seal, final])
    assert ResultSource.quota(index) == ResultSource.quota(restored)

    assert ResultSource.materialize(index, final["delivery"]) ==
             ResultSource.materialize(restored, final["delivery"])

    assert {:ok, committed_source} = ResultSource.readable_source(index, final["delivery"])
    assert committed_source.phase == :committed

    assert ResultSource.materialize(committed_source, final["delivery"]) ==
             ResultSource.materialize(index, final["delivery"])

    foreign = Map.put(final["delivery"], "output_id", String.duplicate("f", 64))
    assert {:error, _} = ResultSource.readable_source(index, foreign)
    assert {:error, _} = ResultSource.materialize(committed_source, foreign)
    assert {:error, _} = ResultSource.materialize(sealed, final["delivery"])

    assert {:error, _} = ResultSource.index_open(index, intent, offer(bytes), 22)
    assert {:error, _} = ResultSource.publish(index, final)
  end

  test "charges all begun attempts, including unreadable orphan prefixes" do
    events =
      Enum.flat_map(1..64, fn _ ->
        intent = intent()
        {:ok, begin, _} = ResultSource.open(intent, offer("{}"), 0)
        [intent, begin, %{"type" => "cancelled"}]
      end)

    assert {:ok, index} = ResultSource.restore(events)
    assert index.begun_count == 64
    assert map_size(index.committed) == 0
    assert {:error, _} = ResultSource.index_open(index, intent(), offer("{}"), 0)
    extra = intent()
    {:ok, begin, _} = ResultSource.open(extra, offer("{}"), 0)
    assert {:error, _} = ResultSource.restore(events ++ [extra, begin])

    near_byte_limit = %Index{source_bytes: 67_108_864 - 1}
    assert {:error, _} = ResultSource.index_open(near_byte_limit, intent(), offer("{}"), 0)
  end

  test "checks the full source reservation against the old finite index before begin" do
    assert ResultSource.fits_reservation?(%Index{}, %{source_bytes: 67_108_864})
    refute ResultSource.fits_reservation?(%Index{}, %{source_bytes: 67_108_865})
    old = %Index{begun_count: 63, source_bytes: 67_108_863}
    assert ResultSource.fits_reservation?(old, %{source_bytes: 1})
    refute ResultSource.fits_reservation?(old, %{source_bytes: 2})
    refute ResultSource.fits_reservation?(%Index{old | begun_count: 64}, %{source_bytes: 1})

    for capacity <- [
          %{},
          %{source_bytes: 0},
          %{source_bytes: -1},
          %{source_bytes: 1.0},
          %{"source_bytes" => 1},
          nil
        ] do
      refute ResultSource.fits_reservation?(old, capacity)
    end
  end

  test "reservation upper bound covers actual near-cap records, maximum elapsed width and fixed pages" do
    value = sized_document(4_194_304)
    {:ok, bytes} = ResultDocument.encode(value, @schema)
    intent = intent()
    {:ok, begin, initial} = ResultSource.open(intent, offer(bytes), 0)
    template = final(intent, initial, 0)
    {:ok, estimate} = ResultSource.reservation_size(initial, template)
    {_, _, chunks, source} = drain(bytes, intent)
    assert length(chunks) == 1024
    {:ok, proof, sealed} = ResultSource.seal(source, 120_000)
    assert proof.event["chunks_sha256"] == Ipse.JSON.digest(chunks)
    final = final(intent, sealed, 120_000)
    records = [begin] ++ chunks ++ [proof.event, final]
    assert estimate.bytes == Enum.sum(Enum.map(records, &record_bytes/1))
    assert estimate.events == 1027
    assert estimate.source_bytes == Enum.sum(Enum.map(Enum.drop(records, -1), &record_bytes/1))
    assert estimate.max_record_bytes == Enum.max(Enum.map(records, &(record_bytes(&1) - 1)))
    assert {:ok, index} = ResultSource.restore([intent | records])

    assert {:ok, %{bytes: ^bytes, value: ^value}} =
             ResultSource.materialize(index, final["delivery"])
  end

  defp intent(schema \\ @schema) do
    hash = String.duplicate("a", 64)

    identity = %{
      "instance" => "fixture",
      "artifact" => hash,
      "artifact_sha256" => hash,
      "options_sha256" => hash,
      "exports_sha256" => hash,
      "requires_sha256" => hash,
      "subscriptions_sha256" => hash,
      "services" => [],
      "scope" => "operator",
      "source_sha256" => hash,
      "sdk" => 2,
      "protocol" => 1,
      "capabilities" => ~w(invoke.command invoke.result.pages),
      "order" => 1,
      "lifetime" => "session",
      "expires_at" => nil,
      "runtime" => %{
        "architecture" => "fixture",
        "elixir" => "1.18.5",
        "erts" => "15",
        "otp" => "27"
      },
      "host_sha256" => hash,
      "generation" => 1,
      "allow_children" => false
    }

    assert Registry.valid_identity?(identity)

    descriptor = %{
      "id" => "query",
      "description" => "Synthetic complete result",
      "arguments_schema" => %{"type" => "object", "additionalProperties" => false},
      "result_schema" => schema,
      "instance" => "fixture",
      "stage" => "invoke.command",
      "name" => "ext__fixture__query"
    }

    event =
      Invocation.intent(
        identity,
        descriptor,
        %{},
        Ipse.Usage.id(),
        Ipse.Usage.id(),
        nil,
        nil,
        "operator_request"
      )

    assert :ok = Invocation.validate_intent(event)
    event
  end

  defp offer(bytes),
    do: %{
      "api_version" => 1,
      "kind" => "result_producer",
      "output" => %{
        "version" => 1,
        "byte_count" => byte_size(bytes),
        "sha256" => Ipse.JSON.sha256(bytes)
      }
    }

  defp reply(source, bytes) do
    count = min(4096, byte_size(bytes) - source.offset)
    fragment = binary_part(bytes, source.offset, count)

    %{
      "api_version" => 1,
      "kind" => "result_chunk",
      "output" => %{
        "version" => 1,
        "output_id" => source.begin["output_id"],
        "offset" => source.offset,
        "next" => source.offset + count,
        "complete" => source.offset + count == byte_size(bytes),
        "data_base64" => Base.encode64(fragment),
        "sha256" => Ipse.JSON.sha256(fragment)
      }
    }
  end

  defp drain(bytes, intent \\ intent(), declared_hash \\ nil) do
    offered =
      if declared_hash,
        do: put_in(offer(bytes), ["output", "sha256"], declared_hash),
        else: offer(bytes)

    {:ok, begin, source} = ResultSource.open(intent, offered, 10)
    {chunks, source} = do_drain(source, bytes, [])
    {intent, begin, Enum.reverse(chunks), source}
  end

  defp do_drain(source, bytes, acc) do
    if source.offset == byte_size(bytes) do
      {acc, source}
    else
      {:ok, event, next} = ResultSource.push(source, reply(source, bytes))
      do_drain(next, bytes, [event | acc])
    end
  end

  defp index_drain(index, id, bytes, acc \\ []) do
    {:ok, source} = ResultSource.source(index, id)

    if source.offset == byte_size(bytes) do
      {index, Enum.reverse(acc)}
    else
      {:ok, event, _, next} = ResultSource.index_push(index, id, reply(source, bytes))
      index_drain(next, id, bytes, [event | acc])
    end
  end

  defp final(intent, source, elapsed) do
    delivery = ResultSource.descriptor(source)

    Map.merge(intent, %{
      "type" => "extension_invocation_result",
      "version" => 2,
      "delivery" => delivery,
      "text" => Jason.encode!(delivery),
      "text_sha256" => Ipse.JSON.sha256(Jason.encode!(delivery)),
      "action_count" => 0,
      "actions_sha256" => Ipse.JSON.digest([]),
      "elapsed_ms" => elapsed
    })
  end

  defp unsafe_seal(source, chunks, elapsed),
    do: %{
      "type" => "extension_output_seal",
      "version" => 1,
      "invocation_id" => source.intent["invocation_id"],
      "output_id" => source.begin["output_id"],
      "byte_count" => source.offset,
      "chunk_count" => length(chunks),
      "sha256" => source.begin["sha256"],
      "chunks_sha256" => Ipse.JSON.digest(chunks),
      "elapsed_ms" => elapsed
    }

  defp record_bytes(event), do: byte_size(Jason.encode!(event)) + 1

  defp sized_document(target) do
    base = %{"items" => List.duplicate(String.duplicate("x", 8192), 511), "pad" => ""}
    Map.put(base, "pad", String.duplicate("x", target - byte_size(Jason.encode!(base))))
  end
end
