ExUnit.start()

Code.require_file("dev/knowledge/collection_recipe_model.ex")

corpus =
  File.read!("extensions/knowledge/src/corpus.ex")
  |> String.replace(~s(@preset "state-lexical"), ~s(@preset "collection-dense"), global: false)

Code.compile_string(corpus, "extensions/knowledge/src/corpus.ex")

defmodule Ipse.SharedProducerTest do
  use ExUnit.Case, async: false
  alias Ipse.CollectionRecipeModel, as: M
  alias IpseKnowledge.{Adapters, Documents, Evidence, Profiles}
  alias IpseKnowledge.Store.Collection, as: C
  alias IpseKnowledge.Store.Collection.{Generation, Producer}
  @profile %{"kind" => "collection", "scope" => "project", "partition" => "notes"}
  @selection %{
    "profile" => "encoder",
    "model" => "fixture-model",
    "dimensions" => 1024,
    "encoding" => "float32le",
    "selection_sha256" => String.duplicate("a", 64)
  }
  @facts %{"kind" => "explicit", "profile" => nil, "version" => 1}

  defp initial(opts \\ []) do
    model =
      Enum.reduce(Keyword.get(opts, :sources, [source_attrs(opts)]), M.new(%{}, 1000), fn source,
                                                                                          model ->
        put_loop(%{"source" => source, "expected_revision" => 0, "continuation" => nil}, model)
      end)

    initial_job(model)
  end

  defp source_attrs(opts) do
    %{
      "source_id" => "fixture:producer",
      "partition" => "notes",
      "generation" => 1,
      "title" => "Producer fixture",
      "text" => Keyword.get(opts, :text, String.duplicate("alpha beta ", 4_000)),
      "uri" => "provided:producer",
      "observed_at_ms" => Keyword.get(opts, :observed_at_ms, 10),
      "event_at_ms" => nil,
      "expires_at_ms" => Keyword.get(opts, :expires_at_ms),
      "origin" => %{
        "kind" => "provided",
        "store_profile" => "local",
        "partition_or_scope" => "notes",
        "receipt" => nil,
        "historical" => Keyword.get(opts, :historical, false)
      }
    }
  end

  defp initial_job(model) do
    args = %{
      "action" => "begin",
      "vector_selection" => @selection,
      "fact_selection" => @facts,
      "continuation" => nil,
      "group" => nil
    }

    {{:done, {:ok, _}}, model} = M.run(C.start(@profile, :generation_job, args), M.reset(model))
    job = model.records["genjob.notes"]

    options =
      Map.new(~w(stores search fetch retrieval embedding rerank extraction), &{&1, %{}})
      |> Map.merge(%{
        "version" => 1,
        "stores" => %{"local" => @profile},
        "retrieval" => %{"words" => %{"kind" => "bm25", "version" => 1}},
        "embedding" => %{"learned" => %{"kind" => "embedding", "profile" => "encoder"}}
      })

    {:ok, resolved} = Profiles.validate("corpus", "collection-dense", options)

    args = %{
      "version" => 1,
      "action" => "page",
      "embedding" => "learned",
      "job_id" => job.value["id"],
      "job_revision" => job.revision,
      "vector_selection" => @selection,
      "fact_selection" => @facts
    }

    {resolved, args, %{model: M.reset(model), calls: 0, pages: %{}, requests: [], fault: nil}}
  end

  defp put_loop(args, model) do
    case M.run(C.start(@profile, :put, args), M.reset(model)) do
      {{:done, {:continue, next}}, model} ->
        put_loop(%{args | "continuation" => next["continuation"]}, model)

      {{:done, {:ok, %{"status" => "stored"}}}, model} ->
        model
    end
  end

  defp drive({:call, request, cont}, d) do
    assert Ipse.Extension.validate(%{
             "api_version" => 1,
             "kind" => "host_call",
             "request" => request
           }) == :ok

    d = %{d | requests: d.requests ++ [request]}
    {outcome, d} = host(request, d)
    drive(Producer.resume(cont, outcome), d)
  end

  defp drive(terminal, d), do: {terminal, d}

  defp host(%{"op" => "collection.store"} = r, d) do
    {outcome, model} = M.host(r, d.model)
    d = %{d | model: model}

    if d.fault == :commit_unknown and d.calls > 0 and r["request"]["op"] == "commit",
      do: {%{"status" => "unknown"}, d},
      else: {outcome, d}
  end

  defp host(%{"op" => "embedding.create"} = r, d) do
    assert r["expected_selection_sha256"] === @selection["selection_sha256"]
    claim = d.model.records["genproducer.notes"].value
    assert claim["status"] == "pending"
    assert claim["version"] === 3
    assert Producer.valid_record?(claim)

    assert r["source_guard"] === %{
             "version" => 1,
             "claim_key" => "genproducer.notes",
             "claim_revision" => d.model.records["genproducer.notes"].revision,
             "claim_sha256" => Evidence.sha256(IO.iodata_to_binary(JSON.encode!(claim))),
             "batch_index" => d.calls
           }

    claim["inputs"]
    |> Enum.slice(d.calls * 2, length(r["inputs"]))
    |> Enum.zip(r["inputs"])
    |> Enum.each(fn {[si, _ci, _chunk, canonical, raw, start, finish], text} ->
      source_key = Enum.at(claim["source_bindings"], si)["source_key"]
      source = source_text(d.model, source_key)
      assert text === binary_part(source, start, finish - start)
      assert Evidence.sha256(text) === raw
      assert {:ok, ^canonical} = Ipse.Extension.canonical_digest([text])
    end)

    assert map_size(d.model.stages) == 0
    calls = d.calls + 1
    id = calls |> Integer.to_string(16) |> String.pad_leading(32, "0")
    source = Evidence.sha256("fixture-response:#{calls}")
    bytes = for _ <- 1..1024, into: <<>>, do: <<1.0::float-little-32>>

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
      "selection_sha256" =>
        if(d.fault == :selection,
          do: String.duplicate("b", 64),
          else: @selection["selection_sha256"]
        ),
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

    d = %{d | calls: calls, pages: Map.merge(d.pages, pages)}

    d =
      if d.fault in [:catalog, :source, :root] do
        {key, previous, value} =
          case d.fault do
            :catalog ->
              row = d.model.records["catalog.notes"]
              {"catalog.notes", row, Map.update!(row.value, "generation", &(&1 + 1))}

            :source ->
              source_key = hd(d.model.records["catalog.notes.0"].value["rows"])["source_key"]
              key = "source.notes." <> source_key
              row = d.model.records[key]
              {key, row, Map.update!(row.value, "revision", &(&1 + 1))}

            :root ->
              {"generation.notes", nil,
               %{"version" => 1, "fixture" => "foreign root replacement"}}
          end

        bytes = IO.iodata_to_binary(JSON.encode!(value))

        foreign = %{
          "op" => "collection.store",
          "scope" => "project",
          "request" => %{
            "op" => "value.put_inline",
            "key" => key,
            "generation" => d.model.generation,
            "expected_revision" => if(previous, do: previous.revision, else: 0),
            "data" => bytes,
            "byte_count" => byte_size(bytes),
            "sha256" => Evidence.sha256(bytes)
          }
        }

        {%{"status" => "ok"}, model} = M.host(foreign, d.model)
        %{d | model: model, fault: :anchor_changed}
      else
        d
      end

    if d.fault == :expire do
      expires =
        d.model.records["genproducer.notes"].value["source_bindings"]
        |> hd()
        |> Map.fetch!("expires_at_ms")

      Process.sleep(max(expires - System.system_time(:millisecond) + 1, 0))
    end

    if d.fault == :inference_unknown,
      do: {%{"status" => "unknown"}, d},
      else: {%{"status" => "ok", "value" => value}, d}
  end

  defp host(%{"op" => "effect.result.read"} = r, d) do
    p = Map.fetch!(d.pages, {r["operation_id"], r["vector_index"]})
    count = min(r["limit"], 1024 - r["offset"])
    data = binary_part(p.bytes, r["offset"] * 4, count * 4)
    last = count + r["offset"] == 1024

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
      "values" => Base.encode64(data)
    }

    {%{"status" => "ok", "value" => page}, d}
  end

  test "claim precedes four receipt flows and publishes exactly the canonical shared first page" do
    {resolved, args, d} = initial(expires_at_ms: System.system_time(:millisecond) + 60_000)
    job = d.model.records["genjob.notes"]
    {{:done, {:ok, result}}, d} = drive(Producer.start(resolved, @profile, args), d)
    assert result["status"] == "page_ready"
    assert result["coverage"]["validated_inference_receipt_flow"]
    refute result["coverage"]["model_receipt_provenance"]
    assert d.calls == 4
    assert d.model.records["genjob.notes"] === job
    refute Map.has_key?(d.model.records, "generation.notes")
    assert map_size(d.model.stages) == 0
    ready = d.model.records["genproducer.notes"].value
    assert Producer.valid_record?(ready)
    assert length(ready["receipts"]) == 4
    page = d.model.records[result["page"]["key"]].value
    assert page["kind"] == "shared_vectors"
    assert length(page["rows"]) == 8
    assert Enum.all?(Map.keys(d.model.records), &(not String.starts_with?(&1, "vectors.")))

    {{:done, {:ok, read}}, _} =
      M.run(
        C.start(@profile, :source_bundles, %{
          "source_keys" => page_source_keys(d.model),
          "as_of_ms" => 0
        }),
        M.reset(d.model)
      )

    bundles = read["bundles"]

    supplied =
      for b <- bundles do
        {:ok, chunks} = Evidence.chunks(b["source"])

        vectors =
          for c <- chunks do
            {:ok, input} = Ipse.Extension.canonical_digest([c["text"]])

            {:ok, v} =
              Evidence.vector(
                Map.drop(@selection, ["encoding"])
                |> Map.merge(%{
                  "chunk_id" => c["chunk_id"],
                  "input_sha256" => input,
                  "values" => List.duplicate(1.0, 1024)
                })
              )

            v
          end

        [chunk | _] = chunks
        {:ok, citation} = Evidence.citation(b["source"], chunk, 0, 1)

        {:ok, fact} =
          Evidence.fact(%{
            "subject" => "A",
            "predicate" => "mentions",
            "object" => "B",
            "polarity" => "positive",
            "inferred" => false,
            "valid_from_ms" => nil,
            "valid_to_ms" => nil,
            "extraction" => @facts,
            "citations" => [citation]
          })

        %{
          "source_key" => b["source"]["source_key"],
          "source_bundle_sha256" =>
            Evidence.sha256(IO.iodata_to_binary(JSON.encode!(b["source"]))),
          "vectors" => vectors,
          "facts" => [fact]
        }
      end

    assert {:ok, plan} = Generation.pack_group("notes", 0, bundles, supplied, @selection, @facts)
    assert Enum.find(plan.values, &(&1.value["kind"] == "shared_vectors")).value === page

    IO.inspect(%{
      producer_reads: result["coverage"]["reads_used"],
      effects: result["coverage"]["effects_used"],
      inference_calls: d.calls,
      max_host_frame:
        Enum.max(
          Enum.map(
            d.requests,
            &byte_size(
              IO.iodata_to_binary(
                JSON.encode!(%{"api_version" => 1, "kind" => "host_call", "request" => &1})
              )
            )
          )
        ),
      ready_bytes: byte_size(IO.iodata_to_binary(JSON.encode!(ready))),
      page_bytes: result["page"]["byte_count"]
    })
  end

  defp page_source_keys(model),
    do: model.records["catalog.notes.0"].value["rows"] |> Enum.map(& &1["source_key"])

  defp source_text(model, source_key) do
    head = model.records["source.notes." <> source_key].value

    bytes =
      Enum.map_join(head["blocks"], fn ref ->
        model.records[ref["key"]].value["pieces"] |> Enum.join()
      end)

    Ipse.JSON.decode_unique(bytes) |> elem(1) |> Map.fetch!("text")
  end

  defp before_inference({:call, %{"op" => "embedding.create"} = request, _}, d),
    do: {request, d}

  defp before_inference({:call, request, cont}, d) do
    {outcome, d} = host(request, d)
    action = %{"request" => request, "outcome" => outcome}
    d = Map.update(d, :before_inference_actions, [action], &(&1 ++ [action]))
    before_inference(Producer.resume(cont, outcome), d)
  end

  @tag :host_seed
  test "preserve a pending v3 logical model relation before its first inference" do
    {resolved, args, d} = initial()
    {request, d} = before_inference(Producer.start(resolved, @profile, args), d)
    seed_fixture(request, d, System.get_env("IPSE_PRODUCER_HOST_SEED_PATH"))
  end

  defp seed_fixture(request, d, path, extra \\ %{}) do
    claim = d.model.records["genproducer.notes"]
    assert Producer.valid_record?(claim.value)
    assert claim.value["status"] === "pending"
    assert d.calls == 0 and map_size(d.model.stages) == 0

    commit =
      Enum.find(d.before_inference_actions, fn action ->
        action["request"]["request"]["op"] == "commit" and
          action["outcome"]["value"]["result"]["generation"] === claim.revision
      end)

    assert commit["outcome"]["status"] === "ok"
    claim_operation_id = commit["outcome"]["value"]["operation_id"]

    records =
      Map.new(d.model.records, fn {key, row} ->
        bytes = IO.iodata_to_binary(JSON.encode!(row.value))

        {key,
         %{
           "key" => key,
           "value" => row.value,
           "revision" => row.revision,
           "sha256" => Evidence.sha256(bytes),
           "byte_count" => byte_size(bytes),
           "operation_id" => if(key == "genproducer.notes", do: claim_operation_id, else: nil)
         }}
      end)

    guard = %{
      "version" => 1,
      "claim_key" => "genproducer.notes",
      "claim_revision" => claim.revision,
      "claim_sha256" => records["genproducer.notes"]["sha256"],
      "batch_index" => 0
    }

    fixture =
      Map.merge(
        %{
          "kind" => "closed_model_pending_v3_no_native_history_or_inference",
          "generation" => d.model.generation,
          "profile" => @profile,
          "records" => records,
          "guard" => guard,
          "selection" => @selection,
          "inputs" => request["inputs"],
          "embedding_request" => request,
          "claim_commit_action" => commit,
          "source_policy" => %{
            "observed_at_ms" => 10,
            "expires_at_ms" => nil,
            "historical" => false
          }
        },
        extra
      )

    if path do
      File.write!(
        path,
        inspect(fixture, pretty: true, limit: :infinity, printable_limit: :infinity) <> "\n",
        [:exclusive]
      )
    end

    IO.inspect(%{
      host_seed: path,
      records: map_size(records),
      generation: d.model.generation,
      claim_operation_id: claim_operation_id,
      inference_calls: d.calls,
      active_stages: map_size(d.model.stages)
    })

    fixture
  end

  defp extra_seed_path(name) do
    case System.get_env("IPSE_PRODUCER_HOST_SEED_DIRECTORY") do
      nil -> nil
      directory -> Path.join(directory, name <> ".exs")
    end
  end

  @tag :host_relation_seeds
  test "pending v3 preserves reversed insertion ordinals within sorted catalog rows" do
    inserted =
      ["fixture:reverse-one", "fixture:reverse-two"]
      |> Enum.sort_by(&Evidence.sha256/1, :desc)
      |> Enum.map(fn id ->
        source_attrs(text: "reverse insertion source #{id}") |> Map.put("source_id", id)
      end)

    {resolved, args, d} = initial(sources: inserted)
    {request, d} = before_inference(Producer.start(resolved, @profile, args), d)
    bindings = d.model.records["genproducer.notes"].value["source_bindings"]

    ordinals =
      Enum.map(bindings, &d.model.records["source.notes." <> &1["source_key"]].value["ordinal"])

    assert ordinals === [1, 0]

    assert Enum.map(bindings, & &1["source_key"]) ===
             Enum.sort(Enum.map(bindings, & &1["source_key"]))

    assert length(request["inputs"]) == 2

    seed_fixture(request, d, extra_seed_path("pending-v3-reverse-order"), %{
      "fixture_case" => "reverse_insertion_sorted_catalog",
      "head_ordinals_in_claim_order" => ordinals,
      "inserted_source_ids" => Enum.map(inserted, & &1["source_id"])
    })
  end

  @tag :host_relation_seeds
  test "pending v3 uses actual extracted DOCX segment spans rather than whole-text splitting" do
    paragraphs = ["First paragraph", "保持 exact second paragraph", "Third paragraph"]
    word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    rel = "http://schemas.openxmlformats.org/package/2006/relationships"
    body = Enum.map_join(paragraphs, &("<w:p><w:r><w:t>" <> &1 <> "</w:t></w:r></w:p>"))

    root =
      "<Relationships xmlns=\"#{rel}\"><Relationship Id=\"main\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>"

    types =
      "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>"

    entries = [
      {~c"_rels/.rels", root},
      {~c"[Content_Types].xml", types},
      {~c"word/document.xml",
       "<w:document xmlns:w=\"#{word}\"><w:body>#{body}</w:body></w:document>"}
    ]

    fixed_time = {{2026, 1, 1}, {0, 0, 0}}

    entries =
      Enum.map(entries, fn {name, data} ->
        info = %File.Stat{
          size: byte_size(data),
          type: :regular,
          access: :read_write,
          atime: fixed_time,
          mtime: fixed_time,
          ctime: fixed_time,
          mode: 0o100644,
          links: 1,
          major_device: 0,
          minor_device: 0,
          inode: 0,
          uid: 0,
          gid: 0
        }

        {name, data, File.Stat.to_record(info)}
      end)

    {:ok, {_, bytes}} = :zip.create(~c"segments.docx", entries, [:memory])
    assert {:ok, document} = Documents.extract(bytes, "segments.docx")
    assert Enum.map(document["segments"], & &1["text"]) === paragraphs
    assert {:ok, payload} = Documents.source_payload(document, 65_536, 2)
    receipt = Evidence.document_storage_receipt!(payload["document"])

    attrs =
      source_attrs(text: payload["text"])
      |> Map.put("source_id", "fixture:segmented-docx")
      |> Map.put("origin", Map.put(source_attrs([])["origin"], "receipt", receipt))

    attrs =
      if receipt["version"] == 4, do: Map.put(attrs, "document", payload["document"]), else: attrs

    assert {:ok, source} = Evidence.collection_source(attrs)
    assert Evidence.valid_source?(source)
    assert {:ok, chunks} = Evidence.chunks(source)
    assert length(chunks) == 3
    assert Enum.map(chunks, & &1["text"]) === paragraphs
    assert hd(tl(chunks))["start_byte"] > hd(chunks)["end_byte"]
    {resolved, args, d} = initial(sources: [source])
    {request, d} = before_inference(Producer.start(resolved, @profile, args), d)
    assert request["inputs"] === Enum.take(paragraphs, 2)
    refs = d.model.records["genproducer.notes"].value["inputs"]

    assert Enum.map(refs, &Enum.slice(&1, 5, 2)) ===
             Enum.map(chunks, &[&1["start_byte"], &1["end_byte"]])

    seed_fixture(request, d, extra_seed_path("pending-v3-segmented-document"), %{
      "fixture_case" => "extracted_docx_short_paragraphs",
      "original_docx_base64" => Base.encode64(bytes),
      "document_sha256" => Evidence.sha256(bytes),
      "paragraphs" => paragraphs,
      "document_metadata" => payload["document"]
    })
  end

  @tag :range_claim
  test "v3 ranges bind exact multibyte raw slices through receipts and canonical shared page" do
    text = String.duplicate("α β\tγ\r\n", 4_000)
    {resolved, args, d} = initial(text: text)
    {{:done, {:ok, result}}, d} = drive(Producer.start(resolved, @profile, args), d)
    ready = d.model.records["genproducer.notes"].value
    assert ready["version"] === 3
    assert ready["recipe"] === "ipse.evidence.shared_producer.first_page.v3"
    assert Producer.valid_record?(ready)
    assert Enum.all?(ready["inputs"], &(length(&1) == 7))
    assert d.calls == 4
    assert result["coverage"]["effects_used"] <= 16
    assert result["coverage"]["reads_used"] <= 512
    assert map_size(d.model.stages) == 0

    assert Enum.all?(d.requests, fn request ->
             byte_size(
               IO.iodata_to_binary(
                 JSON.encode!(%{"api_version" => 1, "kind" => "host_call", "request" => request})
               )
             ) <= 16_384
           end)

    Enum.each(ready["inputs"], fn [_, _, _, canonical, raw, start, finish] ->
      slice = binary_part(text, start, finish - start)
      assert String.valid?(slice)
      assert raw === Evidence.sha256(slice)
      assert {:ok, ^canonical} = Ipse.Extension.canonical_digest([slice])
    end)

    page = d.model.records[result["page"]["key"]].value
    assert page["kind"] == "shared_vectors" and length(page["rows"]) == 8

    IO.inspect(%{
      range_claim_bytes: byte_size(IO.iodata_to_binary(JSON.encode!(ready))),
      reads: result["coverage"]["reads_used"],
      effects: result["coverage"]["effects_used"],
      page_bytes: result["page"]["byte_count"]
    })
  end

  @tag :range_claim
  test "v3 rejects malformed foreign overlapping reordered or absent ranges" do
    {resolved, args, d} = initial()
    {_, d} = before_inference(Producer.start(resolved, @profile, args), d)
    claim = d.model.records["genproducer.notes"].value
    assert Producer.valid_record?(claim)
    [first, second | rest] = claim["inputs"]

    for input <- [
          Enum.take(first, 5),
          List.replace_at(first, 0, 1),
          List.replace_at(first, 0, 0.0),
          List.replace_at(first, 5, -1),
          List.replace_at(first, 5, 0.0),
          List.replace_at(first, 6, 65_537),
          List.replace_at(first, 6, Enum.at(first, 5)),
          List.replace_at(first, 6, Enum.at(first, 5) + 4097)
        ] do
      refute Producer.valid_record?(%{claim | "inputs" => [input, second | rest]})
    end

    refute Producer.valid_record?(%{claim | "inputs" => [second, first | rest]})
    refute Producer.valid_record?(%{claim | "inputs" => [first, first | rest]})
    overlapping = List.replace_at(second, 5, Enum.at(first, 6) - 1)
    refute Producer.valid_record?(%{claim | "inputs" => [first, overlapping | rest]})
    refute Producer.valid_record?(%{claim | "version" => 3.0})

    refute Producer.valid_record?(%{
             claim
             | "recipe" => "ipse.evidence.shared_producer.first_page.v2"
           })

    assert d.calls == 0
  end

  @tag :range_claim
  test "legacy v2 pending records remain inspectable but never become an inference continuation" do
    {resolved, args, d} = initial()
    {_, d} = before_inference(Producer.start(resolved, @profile, args), d)
    row = d.model.records["genproducer.notes"]

    legacy =
      row.value
      |> Map.put("version", 2)
      |> Map.put("recipe", "ipse.evidence.shared_producer.first_page.v2")
      |> Map.update!("inputs", &Enum.map(&1, fn input -> Enum.take(input, 5) end))

    assert Producer.valid_record?(legacy)
    refute Producer.valid_record?(%{legacy | "version" => 3})
    bytes = IO.iodata_to_binary(JSON.encode!(legacy))

    request = %{
      "op" => "collection.store",
      "scope" => "project",
      "request" => %{
        "op" => "value.put_inline",
        "key" => "genproducer.notes",
        "generation" => d.model.generation,
        "expected_revision" => row.revision,
        "data" => bytes,
        "byte_count" => byte_size(bytes),
        "sha256" => Evidence.sha256(bytes)
      }
    }

    {%{"status" => "ok"}, model} = M.host(request, d.model)
    d = %{d | model: M.reset(model)}

    {{:done, {:ok, inspected}}, d} =
      drive(Producer.start(resolved, @profile, %{args | "action" => "inspect"}), d)

    assert inspected["status"] === "pending_unknown"
    assert inspected["coverage"]["recipe"] === legacy["recipe"]
    assert inspected["continuation"] == nil

    {{:done, {:error, :shared_producer_pending_unknown, _}}, d} =
      drive(Producer.start(resolved, @profile, args), %{d | model: M.reset(d.model)})

    assert d.calls == 0
    assert map_size(d.model.stages) == 0
  end

  test "unknown inference or changed result selection leaves an inspectable non-replayable claim" do
    for {fault, expected} <- [{:inference_unknown, :unknown}, {:selection, :mismatch}] do
      {resolved, args, d} = initial()
      {outcome, d} = drive(Producer.start(resolved, @profile, args), %{d | fault: fault})

      if expected == :unknown,
        do: assert(outcome == {:stop, :unknown_effect}),
        else: assert(match?({:done, {:error, _, _}}, outcome))

      assert d.calls == 1
      assert d.model.records["genproducer.notes"].value["status"] == "pending"
      d = %{d | model: M.reset(d.model), fault: nil, requests: []}

      {{:done, {:error, :shared_producer_pending_unknown, _}}, again} =
        drive(Producer.start(resolved, @profile, args), d)

      assert again.calls == 1

      {{:done, {:ok, inspected}}, _} =
        drive(Producer.start(resolved, @profile, %{args | "action" => "inspect"}), d)

      assert inspected["status"] == "pending_unknown" and inspected["continuation"] == nil
      refute inspected["coverage"]["retry_available"]
    end
  end

  test "a committed final page with unknown acknowledgement never offers replay" do
    {resolved, args, d} = initial()

    {{:stop, :unknown_effect}, d} =
      drive(Producer.start(resolved, @profile, args), %{d | fault: :commit_unknown})

    assert d.model.records["genproducer.notes"].value["status"] == "ready"
    assert map_size(d.model.stages) == 0
    d = %{d | model: M.reset(d.model), fault: nil}

    {{:done, {:error, :shared_producer_page_already_completed, _}}, after_read} =
      drive(Producer.start(resolved, @profile, args), d)

    assert after_read.calls == d.calls
  end

  test "catalog changes during inference cannot select staged output or rebase the final CAS" do
    {resolved, args, d} = initial()
    job = d.model.records["genjob.notes"]

    {{:done, {:error, :shared_producer_changed, _}}, d} =
      drive(Producer.start(resolved, @profile, args), %{d | fault: :catalog})

    assert d.calls == 1
    assert d.model.records["genjob.notes"] === job
    assert d.model.records["genproducer.notes"].value["status"] == "pending"
    refute Enum.any?(Map.keys(d.model.records), &String.starts_with?(&1, "genvec."))
    refute Map.has_key?(d.model.records, "generation.notes")
  end

  test "opt-in grants and malformed producer bindings refuse without widening the old preset" do
    old = Profiles.capabilities("corpus", "collection-documents")
    new = Profiles.capabilities("corpus", "collection-dense")
    assert new -- old == ~w(host.embedding host.results)
    refute "host.model" in new
    {resolved, args, _} = initial()

    for bad <- [
          Map.put(args, "version", 1.0),
          Map.put(args, "continuation", %{}),
          put_in(args, ["vector_selection", "dimensions"], 1),
          Map.put(args, "embedding", "missing")
        ] do
      assert {:done, {:error, :invalid_shared_producer_request, _}} =
               Producer.start(resolved, @profile, bad)
    end
  end

  @tag :worker_policy
  test "expired historical and future-observed sources refuse before claim and inference" do
    now = System.system_time(:millisecond)

    for opts <- [[expires_at_ms: now - 1], [historical: true], [observed_at_ms: now + 60_000]] do
      {resolved, args, d} = initial(opts)
      {outcome, d} = drive(Producer.start(resolved, @profile, args), d)
      IO.inspect(%{source_policy_case: opts, inference_calls: d.calls, outcome: outcome})
      assert match?({:done, {:error, :shared_producer_ineligible, _}}, outcome)
      assert d.calls == 0
      refute Map.has_key?(d.model.records, "genproducer.notes")
    end
  end

  @tag :worker_policy
  test "expiry during a preceding batch stops before another inference and keeps pending uncertainty" do
    {resolved, args, d} = initial(expires_at_ms: System.system_time(:millisecond) + 1_000)
    {outcome, d} = drive(Producer.start(resolved, @profile, args), %{d | fault: :expire})
    assert match?({:done, {:error, :shared_producer_ineligible, _}}, outcome)
    assert d.calls == 1
    assert d.model.records["genproducer.notes"].value["status"] == "pending"
    refute Enum.any?(Map.keys(d.model.records), &String.starts_with?(&1, "genvec."))
  end

  @tag :worker_policy
  test "source and root mutations before the next batch stop without a retry or new inference" do
    for fault <- [:source, :root] do
      {resolved, args, d} = initial()
      {outcome, d} = drive(Producer.start(resolved, @profile, args), %{d | fault: fault})
      assert match?({:done, {:error, :shared_producer_changed, _}}, outcome)
      assert d.calls == 1
      assert d.model.records["genproducer.notes"].value["status"] == "pending"
      refute Enum.any?(Map.keys(d.model.records), &String.starts_with?(&1, "genvec."))
    end
  end

  @tag :public_entry
  test "public page delegates to the exact guarded producer and malformed input has no effect" do
    {resolved, args, d} = initial()
    {:ok, state} = IpseKnowledge.Corpus.init(resolved["options"])
    before = d.model.records

    assert {:call, request, continuation} = Producer.start(resolved, @profile, args)

    assert {:ok, %{"kind" => "host_call", "request" => ^request}, public_state} =
             IpseKnowledge.Corpus.handle(
               "invoke.command",
               %{"id" => "generation_produce", "arguments" => Map.put(args, "store", "local")},
               state
             )

    assert public_state.cont === continuation
    assert public_state.phase == :collection_producer and public_state.pending == :producer

    assert Ipse.Extension.validate(%{
             "api_version" => 1,
             "kind" => "host_call",
             "request" => request
           }) == :ok

    assert {:ok, %{"kind" => "result", "value" => result}, _} =
             IpseKnowledge.Corpus.handle(
               "invoke.command",
               %{
                 "id" => "generation_produce",
                 "arguments" => args |> Map.put("store", "local") |> Map.put("source_guard", %{})
               },
               state
             )

    assert result["status"] == "refused"
    assert result["gaps"] == [%{"code" => "invalid_shared_producer_request"}]
    assert d.calls == 0 and d.requests == [] and d.model.records === before
    refute Map.has_key?(d.model.records, "genproducer.notes")

    {_, value} = configured_selection()
    {:call, _, selection} = Producer.selection(resolved, "learned")

    assert {:done, {:ok, setup}} =
             Producer.resume(selection, %{"status" => "ok", "value" => value})

    refute Map.has_key?(setup["coverage"], "source_dispatch_available")
    assert setup["reported_model"] == nil
    assert setup["coverage"]["reads_used"] == 1 and setup["coverage"]["effects_used"] == 0
  end

  defp configured_selection do
    config = %{
      extensions: [%{identity: %{"capabilities" => ~w(host.actions host.embedding)}}],
      embedding_profiles: %{
        "encoder" => %{
          "operation" => "embedding",
          "provider" => "ollama",
          "model" => "configured-model",
          "dimensions" => 1024,
          "dimension_mode" => "native",
          "base_url" => "http://127.0.0.1:9",
          "timeout_ms" => 5000
        }
      }
    }

    scope = %{"embedding_profiles" => Ipse.Config.Profiles.embedding_snapshot(config)}
    request = %{"op" => "embedding.profile", "version" => 1, "profile" => "encoder"}
    {:ok, binding} = Ipse.Extension.EmbeddingCall.profile_binding(scope, request)
    {config, Ipse.Extension.EmbeddingCall.profile_value(binding)}
  end

  @tag :selection_api
  test "read-only domain selection setup preserves configured identity and never invents reported model" do
    {resolved, _, _} = initial()
    {_, value} = configured_selection()
    assert {:call, request, cont} = Producer.selection(resolved, "learned")
    assert request == %{"op" => "embedding.profile", "version" => 1, "profile" => "encoder"}
    assert {:done, {:ok, setup}} = Producer.resume(cont, %{"status" => "ok", "value" => value})
    assert setup["configured_profile"] === value["profile"]
    assert setup["selection_sha256"] === value["selection_sha256"]
    assert setup["reported_model"] == nil and setup["coverage"]["effects_used"] == 0
    refute Map.has_key?(setup["coverage"], "source_dispatch_available")
    assert setup["coverage"]["reads_used"] == 1
    assert {:ok, state} = IpseKnowledge.Corpus.init(resolved["options"])

    args = %{
      "store" => "local",
      "version" => 1,
      "action" => "selection",
      "embedding" => "learned"
    }

    assert {:ok, %{"kind" => "host_call", "request" => ^request}, state} =
             IpseKnowledge.Corpus.handle(
               "invoke.command",
               %{"id" => "generation_produce", "arguments" => args},
               state
             )

    assert {:ok, %{"kind" => "result", "value" => public}, _} =
             IpseKnowledge.Corpus.handle(
               "host.actions",
               %{"outcome" => %{"status" => "ok", "value" => value}},
               state
             )

    assert public["coverage"] === setup
    assert public["continuation"] == nil
  end

  @tag :selection_api
  test "legacy embedding shape is unchanged while exact optional pin reaches Host binding" do
    {resolved, _, _} = initial()
    {config, value} = configured_selection()
    inputs = [%{"chunk_id" => Evidence.sha256("fixture-input"), "text" => "Exact source bytes"}]
    args = %{"profile" => "learned", "inputs" => inputs}
    assert {:call, old, _} = Adapters.start(resolved, :embed, args)

    assert old === %{
             "op" => "embedding.create",
             "version" => 2,
             "profile" => "encoder",
             "inputs" => ["Exact source bytes"],
             "timeout_ms" => 120_000
           }

    assert {:call, pinned, _} =
             Adapters.start(
               resolved,
               :embed,
               Map.put(args, "expected_selection_sha256", value["selection_sha256"])
             )

    assert Map.delete(pinned, "expected_selection_sha256") === old
    assert pinned["expected_selection_sha256"] === value["selection_sha256"]
    assert {:ok, _} = Ipse.Extension.EmbeddingCall.binding(config, pinned)

    changed =
      put_in(config, [:embedding_profiles, "encoder", "model"], "changed-configured-model")

    assert {:error, _} = Ipse.Extension.EmbeddingCall.binding(changed, pinned)
    assert {:ok, _} = Ipse.Extension.EmbeddingCall.binding(changed, old)

    for malformed <- [nil, "bad"] do
      assert {:done, {:error, :invalid_adapter_input, _}} =
               Adapters.start(
                 resolved,
                 :embed,
                 Map.put(args, "expected_selection_sha256", malformed)
               )
    end
  end

  @tag :selection_api
  test "mismatched pin refuses before the closed host inference continuation" do
    {resolved, _, _} = initial()
    {config, value} = configured_selection()

    args = %{
      "profile" => "learned",
      "inputs" => [%{"chunk_id" => Evidence.sha256("input"), "text" => "Exact input"}],
      "expected_selection_sha256" => value["selection_sha256"]
    }

    {:call, request, _} = Adapters.start(resolved, :embed, args)
    changed = put_in(config, [:embedding_profiles, "encoder", "dimensions"], 768)
    inference = fn -> flunk("mismatched selection reached inference") end

    refused =
      case Ipse.Extension.EmbeddingCall.binding(changed, request) do
        {:ok, _} -> inference.()
        refused -> refused
      end

    assert {:error, _} = refused
  end

  @tag :selection_api
  test "bootstrap aliases malformed versions and post-response pin mismatches refuse" do
    {resolved, _, _} = initial()
    {_, value} = configured_selection()
    {:call, _, state} = Adapters.start(resolved, :embedding_profile, %{"profile" => "learned"})

    assert {:done, {:error, :invalid_embedding_profile, _}} =
             Adapters.resume(state, %{
               "status" => "ok",
               "value" => put_in(value, ["profile", "id"], "foreign")
             })

    assert {:done, {:error, :invalid_embedding_profile, _}} =
             Adapters.resume(state, %{"status" => "ok", "value" => Map.put(value, "version", 1.0)})

    assert {:done, {:error, :invalid_profile, _}} =
             Adapters.start(resolved, :embedding_profile, %{"profile" => "missing"})

    {:call, _, embedding} =
      Adapters.start(resolved, :embed, %{
        "profile" => "learned",
        "inputs" => [%{"chunk_id" => Evidence.sha256("input"), "text" => "Exact input"}],
        "expected_selection_sha256" => value["selection_sha256"]
      })

    assert {:done, {:error, :invalid_embedding_result, _}} =
             Adapters.resume(embedding, %{
               "status" => "ok",
               "value" => %{
                 "version" => 2,
                 "selection_sha256" => String.duplicate("b", 64),
                 "result" => nil
               }
             })
  end

  defp guard_wire_args(resolved) do
    args = %{
      "profile" => "learned",
      "inputs" => [
        %{"chunk_id" => Evidence.sha256("guard-input"), "text" => "Exact guarded bytes"}
      ]
    }

    pin = @selection["selection_sha256"]

    guard = %{
      "version" => 1,
      "claim_key" => "genproducer.notes",
      "claim_revision" => 1,
      "claim_sha256" => Evidence.sha256("pending claim bytes"),
      "batch_index" => 0
    }

    {:call, old, _} = Adapters.start(resolved, :embed, args)
    {args, pin, guard, old}
  end

  @tag :guard_adapter
  test "optional source guard preserves exact legacy and pinned embedding wire and v2 results" do
    {resolved, _, _} = initial()
    {args, pin, guard, old} = guard_wire_args(resolved)

    assert old === %{
             "op" => "embedding.create",
             "version" => 2,
             "profile" => "encoder",
             "inputs" => ["Exact guarded bytes"],
             "timeout_ms" => 120_000
           }

    pinned_args = Map.put(args, "expected_selection_sha256", pin)
    assert {:call, pinned, _} = Adapters.start(resolved, :embed, pinned_args)
    assert Map.delete(pinned, "expected_selection_sha256") === old

    for index <- 0..3 do
      exact_guard = Map.put(guard, "batch_index", index)

      assert {:call, guarded, state} =
               Adapters.start(resolved, :embed, Map.put(pinned_args, "source_guard", exact_guard))

      assert guarded === Map.put(pinned, "source_guard", exact_guard)
      assert state.expected_selection_sha256 === pin
      assert guarded["version"] === 2

      assert byte_size(
               IO.iodata_to_binary(
                 JSON.encode!(%{"api_version" => 1, "kind" => "host_call", "request" => guarded})
               )
             ) <= 16_384

      assert {:stop, :unknown_effect} = Adapters.resume(state, %{"status" => "unknown"})

      assert {:done, {:error, :invalid_embedding_result, _}} =
               Adapters.resume(state, %{
                 "status" => "ok",
                 "value" => %{
                   "version" => 2,
                   "selection_sha256" => Evidence.sha256("foreign"),
                   "result" => nil
                 }
               })
    end
  end

  @tag :guard_adapter
  test "malformed source guard or absent pin refuses before emitting any embedding request" do
    {resolved, _, _} = initial()
    {args, pin, guard, _} = guard_wire_args(resolved)

    for bad <- [
          nil,
          %{},
          Map.put(guard, "version", 1.0),
          Map.put(guard, "claim_key", "host.stage.0"),
          Map.put(guard, "claim_key", "genproducer.notes/foreign"),
          Map.put(guard, "claim_revision", 0),
          Map.put(guard, "claim_revision", 1.0),
          Map.put(guard, "claim_revision", Evidence.safe_integer_max() + 1),
          Map.put(guard, "claim_sha256", "bad"),
          Map.put(guard, "batch_index", 4),
          Map.put(guard, "batch_index", 0.0),
          Map.put(guard, "claim_operation_id", String.duplicate("0", 32))
        ] do
      candidate = Map.merge(args, %{"expected_selection_sha256" => pin, "source_guard" => bad})

      assert {:done, {:error, :invalid_adapter_input, _}} =
               Adapters.start(resolved, :embed, candidate)
    end

    for candidate <- [
          Map.put(args, "source_guard", guard),
          Map.merge(args, %{"expected_selection_sha256" => nil, "source_guard" => guard}),
          Map.merge(args, %{"expected_selection_sha256" => "bad", "source_guard" => guard})
        ] do
      assert {:done, {:error, :invalid_adapter_input, _}} =
               Adapters.start(resolved, :embed, candidate)
    end
  end

  @tag :guard_flow
  test "private v3 batches carry one confirmed claim identity and advance only after known receipts" do
    {resolved, args, d} = initial()
    {_, d} = drive(Producer.start(resolved, @profile, args), d)
    requests = Enum.filter(d.requests, &(&1["op"] == "embedding.create"))
    assert length(requests) == 4
    assert Enum.map(requests, & &1["source_guard"]["batch_index"]) === [0, 1, 2, 3]

    assert length(Enum.uniq(Enum.map(requests, &Map.drop(&1["source_guard"], ["batch_index"])))) ==
             1

    assert Enum.all?(
             requests,
             &(&1["expected_selection_sha256"] === @selection["selection_sha256"])
           )

    assert map_size(d.model.stages) == 0
    {resolved, args, d} = initial()

    assert {{:stop, :unknown_effect}, d} =
             drive(Producer.start(resolved, @profile, args), %{d | fault: :inference_unknown})

    assert d.calls == 1
    assert d.model.records["genproducer.notes"].value["status"] === "pending"

    {{:done, {:error, :shared_producer_pending_unknown, _}}, after_read} =
      drive(Producer.start(resolved, @profile, args), %{d | model: M.reset(d.model), fault: nil})

    assert after_read.calls == 1

    IO.inspect(%{
      guarded_batches: 4,
      unknown_batches: d.calls,
      max_frame:
        Enum.max(
          Enum.map(
            requests,
            &byte_size(
              IO.iodata_to_binary(
                JSON.encode!(%{"api_version" => 1, "kind" => "host_call", "request" => &1})
              )
            )
          )
        )
    })
  end
end
