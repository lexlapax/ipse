defmodule IpseKnowledge.FactGroupAssemblyCases do
  use ExUnit.Case, async: false
  alias IpseKnowledge.Corpus
  alias IpseKnowledge.Evidence, as: E
  alias Ipse.Extension.ResultPublication.Output

  defp state do
    profile = %{"kind" => "collection", "scope" => "project", "partition" => "docs"}

    %{
      resolved: %{
        "preset" => "collection-dense",
        "options" => %{"stores" => %{"docs" => profile}}
      },
      phase: :idle,
      ctx: nil,
      cont: nil,
      pending: nil
    }
  end

  defp row(n),
    do: %{
      "subject" => "subject-#{n}-" <> String.duplicate("x", 100),
      "predicate" => "supports",
      "object" => "release",
      "polarity" => "positive",
      "inferred" => false,
      "valid_from_ms" => nil,
      "valid_to_ms" => nil,
      "spans" => [[0, 0, 1]]
    }

  defp group(entries),
    do: %{"version" => 1, "kind" => "explicit_fact_group", "sources" => entries}

  defp entry(key, facts), do: %{"source_key" => E.sha256(key), "facts" => facts}

  defp publish(value),
    do: %{
      "id" => "source",
      "arguments" => %{
        "store" => "docs",
        "action" => "fact_input",
        "args" => %{"input" => %{"version" => 1, "mode" => "publish", "value" => value}}
      }
    }

  defp assemble(refs),
    do: %{
      "id" => "source",
      "arguments" => %{
        "store" => "docs",
        "action" => "fact_input",
        "args" => %{"input" => %{"version" => 1, "mode" => "assemble"}},
        "data_inputs" => refs
      }
    }

  defp reference(bytes, number) do
    delivery = %{
      "version" => 1,
      "kind" => "saved.result",
      "output_id" => E.sha256("output-#{number}"),
      "byte_count" => byte_size(bytes),
      "sha256" => E.sha256(bytes),
      "historical_receipt" => true
    }

    %{
      "version" => 1,
      "session_id" => String.pad_leading(Integer.to_string(number, 16), 32, "0"),
      "delivery" => delivery
    }
  end

  defp owner,
    do: %{
      "project_id" => E.sha256("project"),
      "session_id" => String.duplicate("f", 32),
      "identity_sha256" => E.sha256("identity"),
      "invocation_id" => String.duplicate("e", 32)
    }

  defp emit(value, n) do
    request = publish(value)
    assert byte_size(IO.iodata_to_binary(JSON.encode!(request))) < 16_384
    assert {:ok, %Output{} = output, _} = Corpus.handle("invoke.command", request, state())
    {reference(output.bytes, n), output.bytes}
  end

  defp drive(response, inputs, count \\ 0, owner_fn \\ fn _, _ -> owner() end, chunk_size \\ 6144)

  defp drive(
         {:ok, %{"kind" => "host_call", "request" => request}, state},
         inputs,
         count,
         owner_fn,
         chunk_size
       ) do
    ref = request["result_input"]
    body = Map.fetch!(inputs, ref)
    offset = request["request"]["offset"]
    size = min(chunk_size, byte_size(body) - offset)
    chunk = binary_part(body, offset, size)
    next = if offset + size == byte_size(body), do: nil, else: offset + size
    {:ok, hash} = Ipse.Extension.canonical_digest([request])

    reply = %{
      "status" => "ok",
      "value" => %{
        "version" => 3,
        "owner" => owner_fn.(ref, offset),
        "operation_id" => String.duplicate("d", 32),
        "request_sha256" => hash,
        "result" => %{
          "delivery" => ref["delivery"],
          "offset" => offset,
          "next" => next,
          "data_base64" => Base.encode64(chunk),
          "sha256" => E.sha256(chunk),
          "origin" => nil
        }
      }
    }

    drive(
      Corpus.handle("host.actions", %{"outcome" => reply}, state),
      inputs,
      count + 1,
      owner_fn,
      chunk_size
    )
  end

  defp drive({:ok, %Output{} = output, _}, _, count, _, _) do
    Process.put(:assembled_bytes, output.bytes)
    {:ok, JSON.decode!(output.bytes), byte_size(output.bytes), count}
  end

  defp drive(
         {:ok, %{"kind" => "result", "value" => %{"status" => "refused"}}, _},
         _,
         count,
         _,
         _
       ),
       do: {:refused, count}

  test "eight separately framed sources assemble all 160 rows into a paged result" do
    entries = for n <- 1..8, do: entry("source-#{n}", Enum.map(1..20, &row(n * 100 + &1)))

    pairs =
      entries |> Enum.with_index(1) |> Enum.map(fn {source, n} -> emit(group([source]), n) end)

    refs = Enum.map(pairs, &elem(&1, 0))

    assert {:ok, result, size, 8} =
             drive(Corpus.handle("invoke.command", assemble(refs), state()), Map.new(pairs))

    assert result === group(entries)
    assert size > 16_384
    assert Enum.sum(Enum.map(result["sources"], &length(&1["facts"]))) == 160

    IO.puts(
      "ASSEMBLY_GEOMETRY " <>
        IO.iodata_to_binary(
          JSON.encode!(%{"sources" => 8, "rows" => 160, "bytes" => size, "reads" => 8})
        )
    )

    flattened = Process.get(:assembled_bytes)
    flattened_ref = reference(flattened, 9)

    assert {:ok, ^result, ^size, _} =
             drive(Corpus.handle("invoke.command", assemble([flattened_ref]), state()), %{
               flattened_ref => flattened
             })
  end

  test "same-source fragments merge in order and exact duplicate rows refuse" do
    a = row(1)
    b = row(2)

    pairs = [
      emit(group([entry("one", [a])]), 1),
      emit(group([entry("one", []), entry("two", [b])]), 2),
      emit(group([entry("one", [b])]), 3)
    ]

    assert {:ok, merged, _, 3} =
             drive(
               Corpus.handle("invoke.command", assemble(Enum.map(pairs, &elem(&1, 0))), state()),
               Map.new(pairs)
             )

    assert merged === group([entry("one", [a, b]), entry("two", [b])])
    duplicate = [hd(pairs), emit(group([entry("one", [a])]), 4)]

    assert {:refused, 2} =
             drive(
               Corpus.handle(
                 "invoke.command",
                 assemble(Enum.map(duplicate, &elem(&1, 0))),
                 state()
               ),
               Map.new(duplicate)
             )
  end

  test "duplicate references and impossible descriptor lower bounds refuse before reads" do
    {ref, body} = emit(group([entry("one", [])]), 1)

    assert {:refused, 0} =
             drive(Corpus.handle("invoke.command", assemble([ref, ref]), state()), %{ref => body})

    large =
      for n <- 1..8 do
        ref
        |> put_in(["session_id"], String.pad_leading(Integer.to_string(n, 16), 32, "0"))
        |> put_in(["delivery", "byte_count"], 4 * 1024 * 1024)
      end

    assert {:refused, 0} = drive(Corpus.handle("invoke.command", assemble(large), state()), %{})

    assert {:refused, 0} =
             drive(
               Corpus.handle("invoke.command", assemble(List.duplicate(ref, 9)), state()),
               %{}
             )

    assert {:refused, 0} =
             drive(
               Corpus.handle("invoke.command", assemble([Map.put(ref, "extra", true)]), state()),
               %{}
             )

    backup = %{
      "id" => "source",
      "arguments" => %{
        "store" => "docs",
        "action" => "backup_plan",
        "args" => %{"backup" => %{"generation" => 1}},
        "data_inputs" => Enum.take(large, 5)
      }
    }

    assert {:ok, %{"kind" => "result", "value" => %{"status" => "refused"}}, _} =
             Corpus.handle("invoke.command", backup, state())
  end

  test "merged per-source limits, malformed bodies and different input owners refuse" do
    first = emit(group([entry("one", Enum.map(1..17, &row/1))]), 1)
    second = emit(group([entry("one", Enum.map(18..33, &row/1))]), 2)
    pairs = [first, second]
    refs = Enum.map(pairs, &elem(&1, 0))

    assert {:refused, 2} =
             drive(Corpus.handle("invoke.command", assemble(refs), state()), Map.new(pairs))

    wide1 = emit(group(for n <- 1..5, do: entry("wide-#{n}", [])), 4)
    wide2 = emit(group(for n <- 6..10, do: entry("wide-#{n}", [])), 5)
    wide = [wide1, wide2]

    assert {:refused, 2} =
             drive(
               Corpus.handle("invoke.command", assemble(Enum.map(wide, &elem(&1, 0))), state()),
               Map.new(wide)
             )

    malformed = group([entry("one", [row(1)])]) |> Map.put("extra", true)
    bytes = IO.iodata_to_binary(JSON.encode!(malformed))
    ref = reference(bytes, 3)

    assert {:refused, 1} =
             drive(Corpus.handle("invoke.command", assemble([ref]), state()), %{ref => bytes})

    [r1, r2] = refs

    changed = fn ref, _ ->
      if ref === r1, do: owner(), else: Map.put(owner(), "project_id", E.sha256("other project"))
    end

    assert {:refused, 2} =
             drive(
               Corpus.handle("invoke.command", assemble([r1, r2]), state()),
               Map.new(pairs),
               0,
               changed
             )

    broken = put_in(ref, ["delivery", "sha256"], E.sha256("different bytes"))

    assert {:refused, 1} =
             drive(Corpus.handle("invoke.command", assemble([broken]), state()), %{
               broken => bytes
             })
  end

  test "owner changes and short-chunk attempts cannot reset the shared 512 read limit" do
    {ref, body} = emit(group([entry("one", [row(1)])]), 1)

    changed = fn _, offset ->
      if offset == 0, do: owner(), else: Map.put(owner(), "identity_sha256", E.sha256("other"))
    end

    assert {:refused, 2} =
             drive(
               Corpus.handle("invoke.command", assemble([ref]), state()),
               %{ref => body},
               0,
               changed,
               1
             )

    long = fn key, n ->
      group([entry(key, [Map.put(row(n), "subject", String.duplicate("x", 200))])])
    end

    {ref2, body2} = emit(long.("two", 2), 2)
    {ref3, body3} = emit(long.("three", 3), 3)
    assert byte_size(body2) < 512 and byte_size(body2) + byte_size(body3) > 512

    assert {:refused, 512} =
             drive(
               Corpus.handle("invoke.command", assemble([ref2, ref3]), state()),
               %{ref2 => body2, ref3 => body3},
               0,
               fn _, _ -> owner() end,
               1
             )
  end
end
