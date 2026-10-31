Code.require_file("dev/knowledge/collection_recipe_model.ex")

defmodule Ipse.ProducerProgressTest do
  use ExUnit.Case, async: false
  alias Ipse.CollectionRecipeModel, as: M
  alias IpseKnowledge.{Evidence, Profiles}
  alias IpseKnowledge.Store.Collection, as: C
  alias IpseKnowledge.Store.Collection.Producer
  alias IpseKnowledge.Store.Collection.Producer.Progress
  @profile %{"kind" => "collection", "scope" => "project", "partition" => "notes"}
  @selection %{
    "profile" => "encoder",
    "model" => "fixture-model",
    "dimensions" => 1024,
    "encoding" => "float32le",
    "selection_sha256" => String.duplicate("a", 64)
  }
  @facts %{"kind" => "explicit", "profile" => nil, "version" => 1}

  defp initial(texts \\ [String.duplicate("x", 4096 * 10 + 700)]) do
    sources =
      Enum.with_index(texts)
      |> Enum.map(fn {text, i} ->
        %{
          "source_id" => "fixture:progress:#{i}",
          "partition" => "notes",
          "generation" => 1,
          "title" => "Synthetic progress #{i}",
          "text" => text,
          "uri" => "provided:progress:#{i}",
          "observed_at_ms" => 10,
          "event_at_ms" => nil,
          "expires_at_ms" => nil,
          "origin" => %{
            "kind" => "provided",
            "store_profile" => "local",
            "partition_or_scope" => "notes",
            "receipt" => nil,
            "historical" => false
          }
        }
      end)

    initial_sources(sources)
  end

  defp initial_sources(sources) do
    model =
      Enum.reduce(sources, M.new(%{}, 1000), fn source, m ->
        put(%{"source" => source, "expected_revision" => 0, "continuation" => nil}, m)
      end)

    {{:done, {:ok, _}}, model} =
      M.run(C.start(@profile, :generation_job, job_args("begin", nil)), M.reset(model))

    options =
      Map.new(~w(stores search fetch retrieval embedding rerank extraction), &{&1, %{}})
      |> Map.merge(%{
        "version" => 1,
        "stores" => %{"local" => @profile},
        "retrieval" => %{"words" => %{"kind" => "bm25", "version" => 1}},
        "embedding" => %{"learned" => %{"kind" => "embedding", "profile" => "encoder"}}
      })

    {:ok, resolved} = Profiles.validate("corpus", "collection-dense", options)
    job = model.records["genjob.notes"]

    args = %{
      "version" => 2,
      "action" => "page",
      "embedding" => "learned",
      "job_id" => job.value["id"],
      "job_revision" => job.revision,
      "vector_selection" => @selection,
      "fact_selection" => @facts,
      "vector_cursor" => 0,
      "previous_ready" => nil
    }

    d = %{
      model: M.reset(model),
      calls: 0,
      batch: 0,
      pages: %{},
      requests: [],
      fault: nil,
      texts: Map.new(sources, &{Evidence.sha256(&1["source_id"]), &1["text"]})
    }

    {resolved, args, d}
  end

  defp put(args, m) do
    case M.run(C.start(@profile, :put, args), M.reset(m)) do
      {{:done, {:continue, next}}, m} -> put(%{args | "continuation" => next["continuation"]}, m)
      {{:done, {:ok, %{"status" => "stored"}}}, m} -> m
    end
  end

  defp job_args(action, token),
    do: %{
      "action" => action,
      "vector_selection" => @selection,
      "fact_selection" => @facts,
      "continuation" => token,
      "group" => nil
    }

  defp drive({:call, r, c}, d) do
    assert Ipse.Extension.validate(%{"api_version" => 1, "kind" => "host_call", "request" => r}) ==
             :ok

    {outcome, d} = host(r, %{d | requests: d.requests ++ [r]})
    drive(Producer.resume(c, outcome), d)
  end

  defp drive(result, d), do: {result, d}
  defp invoke(result, d), do: drive(result, %{d | model: M.reset(d.model), requests: []})

  defp public_drive({:ok, %{"kind" => "host_call", "request" => request}, state}, d) do
    {outcome, d} = host(request, %{d | requests: d.requests ++ [request]})
    public_drive(IpseKnowledge.Corpus.handle("host.actions", %{"outcome" => outcome}, state), d)
  end

  defp public_drive({:ok, %{"kind" => "result", "value" => value}, _state}, d), do: {value, d}

  defp public_invoke(resolved, args, d) do
    state = %{resolved: resolved, phase: :idle, ctx: nil, cont: nil, pending: nil}
    payload = %{"id" => "generation_produce", "arguments" => args}

    public_drive(IpseKnowledge.Corpus.handle("invoke.command", payload, state), %{
      d
      | model: M.reset(d.model),
        requests: []
    })
  end

  defp host(%{"op" => "collection.store"} = r, d) do
    inner = r["request"]

    {outcome, model} =
      if inner["op"] == "value.read" and not Map.has_key?(d.model.records, inner["key"]) do
        assert Ipse.Extension.CollectionStore.validate(r) == :ok
        {%{"status" => "failed", "value" => %{"code" => "document_store_refused"}}, d.model}
      else
        M.host(r, d.model)
      end

    value = if inner["op"] == "value.put_inline", do: JSON.decode!(inner["data"])
    d = %{d | model: model}
    d = if is_map(value) and value["status"] == "pending", do: %{d | batch: 0}, else: d

    unknown =
      (d.fault == :claim_unknown and is_map(value) and value["status"] == "pending") or
        (d.fault == :ready_unknown and is_map(value) and value["status"] == "ready") or
        (d.fault == :page_unknown and inner["op"] == "value.write_parts" and
           inner["offset"] + Enum.sum(Enum.map(inner["data"], &byte_size/1)) ==
             inner["byte_count"])

    {if(unknown, do: %{"status" => "unknown"}, else: outcome), d}
  end

  defp host(%{"op" => "embedding.create"} = r, d) do
    guard = r["source_guard"]
    claim = d.model.records[guard["claim_key"]]

    assert guard === %{
             "version" => 2,
             "claim_key" => guard["claim_key"],
             "claim_revision" => claim.revision,
             "claim_sha256" => Evidence.sha256(IO.iodata_to_binary(JSON.encode!(claim.value))),
             "batch_index" => d.batch
           }

    assert Progress.pending?(claim.value, guard["claim_key"])
    assert Ipse.Extension.Collection.DocumentSourceUse.pending?(claim.value, guard["claim_key"])
    assert r["expected_selection_sha256"] === @selection["selection_sha256"]
    refs = Enum.slice(claim.value["inputs"], d.batch * 2, 2)

    Enum.zip(refs, r["inputs"])
    |> Enum.each(fn {[si, _, _, canonical, raw, start, finish], text} ->
      source_key = Enum.at(claim.value["source_bindings"], si)["source_key"]
      assert text === binary_part(d.texts[source_key], start, finish - start)
      assert Evidence.sha256(text) === raw
      assert {:ok, ^canonical} = Ipse.Extension.canonical_digest([text])
    end)

    assert map_size(d.model.stages) == 0
    id = Integer.to_string(d.calls + 1, 16) |> String.downcase() |> String.pad_leading(32, "0")
    bytes = for _ <- 1..1024, into: <<>>, do: <<1.0::float-little-32>>
    source = Evidence.sha256("progress-response:#{id}")

    pages =
      Enum.with_index(r["inputs"])
      |> Map.new(fn {text, index} ->
        {:ok, canonical} = Ipse.Extension.canonical_digest([text])
        {{id, index}, %{bytes: bytes, input: canonical, source: source}}
      end)

    value = %{
      "version" => 2,
      "request_id" => id,
      "attempt_id" => id,
      "profile" => r["profile"],
      "reported_model" => "fixture-model",
      "selection_sha256" => @selection["selection_sha256"],
      "usage" => nil,
      "result" => %{
        "version" => 2,
        "operation_id" => id,
        "source_sha256" => source,
        "kind" => "embedding.f32le",
        "encoding" => "float32le.base64",
        "dimensions" => 1024,
        "vector_count" => length(r["inputs"])
      }
    }

    outcome =
      if d.fault == :inference_unknown,
        do: %{"status" => "unknown"},
        else: %{"status" => "ok", "value" => value}

    {outcome, %{d | calls: d.calls + 1, batch: d.batch + 1, pages: Map.merge(d.pages, pages)}}
  end

  defp host(%{"op" => "effect.result.read"} = r, d) do
    p = d.pages[{r["operation_id"], r["vector_index"]}]
    count = min(r["limit"], 1024 - r["offset"])
    last = r["offset"] + count == 1024

    page = %{
      "version" => 2,
      "operation_id" => r["operation_id"],
      "source_sha256" => p.source,
      "kind" => "embedding.f32le",
      "encoding" => "float32le.base64",
      "vector_index" => r["vector_index"],
      "dimensions" => 1024,
      "offset" => r["offset"],
      "complete" => last,
      "next" => if(last, do: nil, else: r["offset"] + count),
      "input_sha256" => p.input,
      "vector_sha256" => Evidence.sha256(p.bytes),
      "values" => Base.encode64(binary_part(p.bytes, r["offset"] * 4, count * 4))
    }

    {%{"status" => "ok", "value" => page}, d}
  end

  @tag :v4_pages
  test "eleven chunks progress through two known pages and complete canonical assembly without truncation" do
    {resolved, args, d} = initial()
    job = d.model.records["genjob.notes"]
    {{:done, {:ok, first}}, d} = invoke(Producer.start(resolved, @profile, args), d)
    assert first["status"] == "page_ready" and first["continuation"]["vector_cursor"] == 8
    assert d.calls == 4 and d.model.effects == 6 and map_size(d.model.stages) == 0
    assert Enum.count(d.requests, &(&1["request"]["op"] == "value.write_parts")) == 4
    assert d.model.records["genjob.notes"] === job
    first_frames = d.model.frames
    assert Progress.ready?(d.model.records["genproducer4.notes.0"].value, "genproducer4.notes.0")

    assert Ipse.Extension.Collection.DocumentSourceUse.ready?(
             d.model.records["genproducer4.notes.0"].value,
             "genproducer4.notes.0"
           )

    {{:done, {:ok, last}}, d} =
      invoke(Producer.start(resolved, @profile, first["continuation"]), d)

    assert last["continuation"] == nil and last["coverage"]["all_pages_ready"]
    refute last["coverage"]["group_complete"]
    assert d.calls == 6 and d.model.effects == 4
    second_frames = d.model.frames
    {{:done, {:ok, full}}, d} = invoke(Progress.assemble(resolved, @profile, args), d)
    assert length(full.vectors) == 11 and Enum.map(full.pages, & &1["ordinal"]) == [0, 1]
    assert Enum.map(full.pages, &length(&1["rows"])) == [8, 3]
    assert full.coverage["reads_used"] <= 512 and full.coverage["effects_used"] == 0
    assert Map.keys(d.model.records) |> Enum.count(&String.starts_with?(&1, "genproducer4.")) == 2
    refute Map.has_key?(d.model.records, "generation.notes")

    IO.puts(
      "V4_TWO_PAGES " <>
        Jason.encode!(%{
          vectors: 11,
          pages: 2,
          embedding_calls: 6,
          maximum_store_frame: Enum.max(first_frames ++ second_frames ++ d.model.frames),
          hydrate_reads: full.coverage["reads_used"],
          native_operations: 0
        })
    )
  end

  @tag :v4_public_continuation
  test "public v2 continuation carries the store and resumes the next page" do
    {resolved, args, d} = initial()
    {first, d} = public_invoke(resolved, Map.put(args, "store", "local"), d)
    assert first["status"] == "ok"
    assert first["coverage"]["status"] == "page_ready"
    refute Map.has_key?(first["coverage"], "continuation")
    assert %{"id" => "generation_produce", "arguments" => next} = first["continuation"]
    assert next["store"] == "local" and next["vector_cursor"] == 8
    assert next["previous_ready"] == first["coverage"]["ready"]
    {last, d} = public_invoke(resolved, next, d)
    assert last["status"] == "ok" and last["continuation"] == nil
    assert last["coverage"]["coverage"]["all_pages_ready"]
    assert d.calls == 6
  end

  @tag :v4_wide_geometry
  test "eight maximum-size plain sources preserve every vector page within the per-call budget" do
    {resolved, args, d} = initial(List.duplicate(String.duplicate("x", 65_536), 8))
    {pages, d} = produce_pages(resolved, args, d, 0)
    assert pages == 16 and d.calls == 64
    {{:done, {:ok, full}}, d} = invoke(Progress.assemble(resolved, @profile, args), d)
    assert length(full.vectors) == 128
    assert full.coverage["reads_used"] <= 512
    assert full.coverage["effects_used"] == 0

    IO.puts(
      "V4_WIDE_GEOMETRY " <>
        Jason.encode!(%{
          sources: 8,
          chunks: 128,
          pages: pages,
          hydrate_reads: full.coverage["reads_used"],
          hydrate_maximum_store_frame: Enum.max(d.model.frames)
        })
    )
  end

  defp produce_pages(resolved, args, d, count) do
    {{:done, {:ok, result}}, d} = invoke(Producer.start(resolved, @profile, args), d)

    if next = result["continuation"],
      do: produce_pages(resolved, next, d, count + 1),
      else: {count + 1, d}
  end

  @tag :v4_segmented_geometry
  @tag timeout: 600_000
  test "eight segmented documents preserve all 256 chunks within the per-call budget" do
    word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    rel = "http://schemas.openxmlformats.org/package/2006/relationships"

    root =
      "<Relationships xmlns=\"#{rel}\"><Relationship Id=\"main\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>"

    types =
      "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>"

    body =
      Enum.map_join(1..32, fn n ->
        "<w:p><w:r><w:t>#{n}:" <> String.duplicate("x", 2040) <> "</w:t></w:r></w:p>"
      end)

    {:ok, {_, bytes}} =
      :zip.create(
        ~c"segments.docx",
        [
          {~c"_rels/.rels", root},
          {~c"[Content_Types].xml", types},
          {~c"word/document.xml",
           "<w:document xmlns:w=\"#{word}\"><w:body>#{body}</w:body></w:document>"}
        ],
        [:memory]
      )

    {:ok, document} = IpseKnowledge.Documents.extract(bytes, "segments.docx")
    {:ok, payload} = IpseKnowledge.Documents.source_payload(document, 65_536, 2)
    receipt = Evidence.document_storage_receipt!(payload["document"])

    sources =
      Enum.map(1..8, fn n ->
        attrs = %{
          "source_id" => "fixture:segments:#{n}",
          "partition" => "notes",
          "generation" => 1,
          "title" => "Segmented #{n}",
          "text" => payload["text"],
          "uri" => "provided:segments:#{n}",
          "observed_at_ms" => 10,
          "event_at_ms" => nil,
          "expires_at_ms" => nil,
          "origin" => %{
            "kind" => "provided",
            "store_profile" => "local",
            "partition_or_scope" => "notes",
            "receipt" => receipt,
            "historical" => false
          }
        }

        attrs =
          if receipt["version"] == 4,
            do: Map.put(attrs, "document", payload["document"]),
            else: attrs

        {:ok, source} = Evidence.collection_source(attrs)
        {:ok, chunks} = Evidence.chunks(source)
        assert length(chunks) == 32
        source
      end)

    {resolved, args, d} = initial_sources(sources)
    {pages, d} = produce_pages(resolved, args, d, 0)
    assert pages == 32 and d.calls == 128
    {{:done, {:ok, full}}, d} = invoke(Progress.assemble(resolved, @profile, args), d)
    assert length(full.vectors) == 256 and full.coverage["reads_used"] <= 512

    wide_facts =
      Enum.map(facts(full.bundles), fn entry ->
        [original] = entry["facts"]

        generated =
          Enum.map(1..32, fn n ->
            attrs =
              original |> Map.drop(~w(version fact_id)) |> Map.put("subject", "Synthetic #{n}")

            attrs =
              if System.get_env("IPSE_V4_ESCAPED_FACTS") == "1" do
                attrs
                |> Map.put("subject", "#{n}:" <> String.duplicate("\"", 252))
                |> Map.put("predicate", String.duplicate("\\", 128))
              else
                attrs
              end

            {:ok, fact} = Evidence.fact(attrs)
            fact
          end)

        %{entry | "facts" => generated}
      end)

    Process.put(:v4_append_max_reads, 0)
    Process.put(:v4_append_invocations, 0)
    {{:done, {:ok, completed}}, result} = append(resolved, args, wide_facts, nil, d)
    assert completed["job"]["cursor"] == 8
    assert completed["job"]["facts"] == 256 and map_size(result.model.stages) == 0

    IO.puts(
      "V4_SEGMENTED_GEOMETRY " <>
        Jason.encode!(%{
          sources: 8,
          chunks: 256,
          pages: pages,
          facts: 256,
          hydrate_reads: full.coverage["reads_used"],
          append_max_reads: Process.get(:v4_append_max_reads),
          append_invocations: Process.get(:v4_append_invocations)
        })
    )
  end

  @tag :v4_unknown
  test "unknown claim inference page and ready never return an adoption or retry continuation" do
    for fault <- [:claim_unknown, :inference_unknown, :page_unknown, :ready_unknown] do
      {resolved, args, d} = initial()

      assert {{:stop, :unknown_effect}, d} =
               invoke(Producer.start(resolved, @profile, args), %{d | fault: fault})

      calls = d.calls

      assert {{:done, {:error, code, _}}, d} =
               invoke(Producer.start(resolved, @profile, args), %{d | fault: nil})

      assert code in [:shared_producer_pending_unknown, :shared_producer_page_already_completed]
      assert d.calls == calls and d.requests != []

      refute Enum.any?(
               d.requests,
               &(&1["op"] == "embedding.create" or C.read_request?(&1) == false)
             )
    end
  end

  @tag :v4_source_integrity
  test "catalog-bound source heads and immutable blocks refuse changed bytes before effects" do
    {resolved, args, d} = initial(["A synthetic source has an authenticated head and block."])
    keys = Map.keys(d.model.records)
    head = Enum.find(keys, &String.starts_with?(&1, "source.notes."))
    assert is_binary(head)
    block = hd(d.model.records[head].value["blocks"])["key"]
    assert is_binary(block)

    for key <- [head, block] do
      altered = %{
        d.model
        | records:
            Map.update!(d.model.records, key, fn row ->
              %{row | value: Map.put(row.value, "unexpected", true)}
            end)
      }

      assert {{:done, {:error, _, _}}, rejected} =
               invoke(Producer.start(resolved, @profile, args), %{d | model: altered})

      assert rejected.model.effects == 0 and rejected.calls == 0
      refute Map.has_key?(rejected.model.records, "genproducer4.notes.0")
    end
  end

  @tag :v4_span_batch
  test "batched citation validation rejects any altered citation" do
    {resolved, args, d} = initial(["A source has a specific supporting sentence."])
    {{:done, {:ok, _}}, d} = invoke(Producer.start(resolved, @profile, args), d)
    {{:done, {:ok, full}}, _} = invoke(Progress.assemble(resolved, @profile, args), d)
    source = hd(full.bundles)["source"]
    citation = hd(hd(facts(full.bundles))["facts"])["citations"] |> hd()
    assert Evidence.valid_spans?(source, [citation, citation])

    for invalid <- [
          Map.put(citation, "quote", "altered"),
          Map.put(citation, "source_key", String.duplicate("a", 64)),
          Map.put(citation, "end_byte", citation["end_byte"] + 4096),
          Map.put(citation, "extra", true)
        ] do
      refute Evidence.valid_span?(source, invalid)
      refute Evidence.valid_spans?(source, [citation, invalid])
    end
  end

  @tag :v4_object_revision
  test "fixed-generation object reads enforce an optional exact physical revision" do
    {_, _, d} = initial(["A synthetic immutable block."])
    head = Enum.find(Map.keys(d.model.records), &String.starts_with?(&1, "source.notes."))
    key = hd(d.model.records[head].value["blocks"])["key"]
    row = d.model.records[key]
    bytes = IO.iodata_to_binary(JSON.encode!(row.value))

    ref = %{
      "key" => key,
      "sha256" => Evidence.sha256(bytes),
      "byte_count" => byte_size(bytes),
      "generation" => d.model.generation
    }

    assert {{:done, {:ok, %{"value" => value}}}, _} =
             M.run(C.start(@profile, :object_read, ref), M.reset(d.model))

    assert value === row.value

    assert {{:done, {:ok, _}}, _} =
             M.run(
               C.start(@profile, :object_read, Map.put(ref, "revision", row.revision)),
               M.reset(d.model)
             )

    assert row.revision + 1 <= d.model.generation

    assert {{:done, {:error, :collection_object_corrupt, _}}, _} =
             M.run(
               C.start(@profile, :object_read, Map.put(ref, "revision", row.revision + 1)),
               M.reset(d.model)
             )
  end

  @tag :v4_anchor_reserve
  test "anchor reservation counts escaped and multibyte read pages" do
    for value <- [
          %{"text" => "short"},
          %{"text" => String.duplicate("\"\\", 3000) <> "好"},
          %{"text" => String.duplicate(<<1>>, 4000)}
        ] do
      model = M.new(%{"fixture.anchor" => value}, 1001)

      {{:done, {:ok, %{"record" => %{"value" => ^value}}}}, read} =
        M.run(C.start(@profile, :value_read, %{"key" => "fixture.anchor"}), model)

      extra = read.reads - 3
      assert Progress.anchor_read_extra([%{"value" => value}, nil], false) == extra
      assert Progress.anchor_read_extra([%{"value" => value}, nil], true) == extra * 2
    end
  end

  @tag :v4_packed_fact_pages
  test "escaped fact pages split before exceeding the native packed-value bound" do
    {resolved, args, d} = initial(Enum.map(1..8, &"Source #{&1} supports a synthetic relation."))
    {{:done, {:ok, _}}, d} = invoke(Producer.start(resolved, @profile, args), d)
    {{:done, {:ok, full}}, _} = invoke(Progress.assemble(resolved, @profile, args), d)

    wide_facts =
      Enum.map(facts(full.bundles), fn entry ->
        [original] = entry["facts"]

        generated =
          Enum.map(1..32, fn n ->
            attrs =
              original
              |> Map.drop(~w(version fact_id))
              |> Map.put("subject", "#{n}:" <> String.duplicate("\"", 252))
              |> Map.put("predicate", String.duplicate("\\", 128))

            {:ok, fact} = Evidence.fact(attrs)
            fact
          end)

        %{entry | "facts" => generated}
      end)

    supplied =
      Enum.zip([full.bundles, wide_facts, full.vectors])
      |> Enum.map(fn {bundle, entry, vector} ->
        %{
          "source_key" => entry["source_key"],
          "source_bundle_sha256" =>
            Evidence.sha256(IO.iodata_to_binary(JSON.encode!(bundle["source"]))),
          "vectors" => [vector],
          "facts" => entry["facts"]
        }
      end)

    alias IpseKnowledge.Store.Collection.{Generation, Paged}

    assert {:ok, plan} =
             Generation.pack_group("notes", 0, full.bundles, supplied, @selection, @facts)

    assert length(plan.header["fact_pages"]) > 1
    assert Paged.native_value?(plan.header)
    assert Enum.all?(plan.values, &Paged.native_value?(&1.value))
    values = Map.new(plan.values, &{&1.key, &1.value})

    assert {:ok, ^supplied} =
             Generation.unpack_group("notes", plan.header, values, full.bundles, %{
               "cursor" => 0,
               "vector_selection" => @selection,
               "fact_selection" => @facts
             })
  end

  @tag :v4_corruption
  test "missing reordered and altered page or ready chains cannot claim complete chunk coverage" do
    {resolved, args, d} = initial()
    {{:done, {:ok, first}}, d} = invoke(Producer.start(resolved, @profile, args), d)
    {{:done, {:ok, _}}, d} = invoke(Producer.start(resolved, @profile, first["continuation"]), d)
    ready = d.model.records["genproducer4.notes.0"]

    for model <- [
          %{d.model | records: Map.delete(d.model.records, ready.value["page"]["key"])},
          %{
            d.model
            | records:
                Map.update!(d.model.records, "genproducer4.notes.0", fn row ->
                  %{row | revision: row.revision + 1}
                end)
          },
          %{
            d.model
            | records:
                Map.update!(d.model.records, "genproducer4.notes.1", fn row ->
                  %{row | value: Map.put(row.value, "previous_ready", nil)}
                end)
          },
          %{
            d.model
            | records:
                Map.update!(d.model.records, ready.value["page"]["key"], fn row ->
                  %{row | value: Map.update!(row.value, "rows", &Enum.reverse/1)}
                end)
          }
        ] do
      assert {{:done, {:error, _, _}}, failed} =
               invoke(Progress.assemble(resolved, @profile, args), %{d | model: model})

      assert failed.calls == d.calls and failed.model.effects == 0
    end
  end

  @tag :v4_append
  test "explicit valid facts enable canonical Job append and only terminal group proof permits slot reuse" do
    {resolved, args, d} = initial(Enum.map(1..9, &"Source #{&1} supports audit."))
    {{:done, {:ok, page}}, d} = invoke(Producer.start(resolved, @profile, args), d)
    assert page["coverage"]["all_pages_ready"]
    {{:done, {:ok, full}}, d} = invoke(Progress.assemble(resolved, @profile, args), d)
    facts = facts(full.bundles)
    {{:done, {:ok, complete}}, d} = append(resolved, args, facts, nil, d)
    assert complete["job"]["cursor"] == 8 and complete["status"] == "groups"
    old = d.model.records["genproducer4.notes.0"]
    next = %{args | "job_revision" => d.model.records["genjob.notes"].revision}
    {{:done, {:ok, _}}, d} = invoke(Producer.start(resolved, @profile, next), d)
    assert d.model.records["genproducer4.notes.0"].revision > old.revision
    assert d.model.records["genproducer4.notes.0"].value["cursor"] == 8
    assert Map.keys(d.model.records) |> Enum.count(&String.starts_with?(&1, "genproducer4.")) == 1
    refute Map.has_key?(d.model.records, "generation.notes")
    assert map_size(d.model.stages) == 0
  end

  @tag :v4_selected_reuse
  test "selected prior group authorizes reuse only for a page actually in that group" do
    {resolved, args, d} = initial(["Synthetic source supports a reviewed relation."])
    {{:done, {:ok, page}}, d} = invoke(Producer.start(resolved, @profile, args), d)
    assert page["coverage"]["all_pages_ready"]
    {{:done, {:ok, full}}, d} = invoke(Progress.assemble(resolved, @profile, args), d)
    {{:done, {:ok, appended}}, d} = append(resolved, args, facts(full.bundles), nil, d)
    {selected, model} = finalize(job_args("finalize_paged", appended["continuation"]), d.model)
    assert selected["status"] == "selected"
    assert model.records["generation.notes"].value["version"] === 2
    {begun, model} = run_job(job_args("begin", nil), model)
    assert begun["status"] == "groups"
    old = model.records["genproducer4.notes.0"]

    next = %{
      args
      | "job_id" => begun["job"]["id"],
        "job_revision" => model.records["genjob.notes"].revision
    }

    bogus_sha = String.duplicate("a", 64)

    bogus_page = %{
      "key" => "genvec.notes." <> bogus_sha,
      "sha256" => bogus_sha,
      "byte_count" => 2
    }

    forged = put_in(model.records["genproducer4.notes.0"].value["page"], bogus_page)

    {{:done, {:error, _, _}}, rejected} =
      invoke(Producer.start(resolved, @profile, next), %{d | model: forged})

    assert rejected.model.effects == 0 and rejected.calls == d.calls
    assert rejected.model.records["genproducer4.notes.0"].value["page"] === bogus_page

    {{:done, {:ok, ready}}, accepted} =
      invoke(Producer.start(resolved, @profile, next), %{d | model: model})

    assert ready["status"] == "page_ready"
    assert accepted.model.records["genproducer4.notes.0"].revision > old.revision
    assert accepted.model.records["generation.notes"] === model.records["generation.notes"]
    refute Enum.any?(accepted.requests, &(&1["request"]["op"] == "value.write_parts"))
  end

  defp run_job(args, model) do
    case M.run(C.start(@profile, :generation_job, args), M.reset(model)) do
      {{:done, {:continue, value}}, model} ->
        run_job(%{args | "continuation" => value["continuation"]}, model)

      {{:done, {:ok, value}}, model} ->
        {value, model}
    end
  end

  defp finalize(args, model) do
    {result, model} = run_job(args, model)

    if result["status"] == "selected",
      do: {result, model},
      else: finalize(%{args | "continuation" => result["continuation"]}, model)
  end

  defp facts(bundles) do
    Enum.map(bundles, fn b ->
      source = b["source"]
      {:ok, [chunk | _]} = Evidence.chunks(source)

      {:ok, citation} =
        Evidence.citation(
          source,
          chunk,
          chunk["start_byte"],
          min(chunk["end_byte"], chunk["start_byte"] + 20)
        )

      {:ok, fact} =
        Evidence.fact(%{
          "subject" => "Audit",
          "predicate" => "has source",
          "object" => source["source_id"],
          "polarity" => "positive",
          "inferred" => false,
          "valid_from_ms" => nil,
          "valid_to_ms" => nil,
          "extraction" => @facts,
          "citations" => [citation]
        })

      %{"source_key" => source["source_key"], "facts" => [fact]}
    end)
  end

  defp append(resolved, args, facts, token, d) do
    result = invoke(Progress.append(resolved, @profile, args, facts, token), d)

    if is_integer(Process.get(:v4_append_max_reads)) do
      {_, measured} = result

      Process.put(
        :v4_append_max_reads,
        max(Process.get(:v4_append_max_reads), measured.model.reads)
      )

      Process.put(:v4_append_invocations, Process.get(:v4_append_invocations) + 1)
    end

    case result do
      {{:done, {:continue, value}}, d} ->
        append(resolved, args, facts, value["continuation"], d)

      {{:done, {:error, code, _}}, d} = failed ->
        IO.puts(
          "V4_APPEND_FAILURE " <>
            Jason.encode!(%{
              code: code,
              reads: d.model.reads,
              effects: d.model.effects,
              stages: map_size(d.model.stages),
              token: token,
              requests:
                Enum.frequencies(
                  Enum.map(d.requests, fn r -> get_in(r, ["request", "op"]) || r["op"] end)
                )
            })
        )

        failed

      terminal ->
        terminal
    end
  end
end
