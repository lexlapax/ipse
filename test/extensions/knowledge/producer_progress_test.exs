if System.get_env("IPSE_PRODUCER_PROGRESS_CHILD") == "1" do
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

      {_, model} = run_job(job_args("begin", nil), model)

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
        {{:done, {:continue, next}}, m} ->
          put(%{args | "continuation" => next["continuation"]}, m)

        {{:done, {:ok, %{"status" => "stored"}}}, m} ->
          m
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

    defp public_fact_invoke(resolved, args, d) do
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

      outcome =
        if d.fault == :advanced_maintenance and inner["op"] == "snapshot" do
          put_in(outcome, ["value", "result", "document_store"], %{
            "version" => 3,
            "inline_bytes" => 8192,
            "write_parts" => 2,
            "maintenance_epoch" => 1,
            "maintenance_status" => "idle"
          })
        else
          outcome
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

      if Process.get(:check_wide_source_guard) == true and d.calls == 0 do
        reader = fn key ->
          case d.model.records[key] do
            nil ->
              {:ok, nil}

            row ->
              bytes = IO.iodata_to_binary(JSON.encode!(row.value))

              packed = %{
                "version" => 1,
                "kind" => "document_value",
                "parts" => packed_parts(bytes),
                "sha256" => Evidence.sha256(bytes),
                "byte_count" => byte_size(bytes)
              }

              {:ok,
               %{
                 "revision" => row.revision,
                 "operation_id" => String.duplicate("1", 32),
                 "value" => packed
               }}
          end
        end

        {micros, result} =
          :timer.tc(fn ->
            Ipse.Extension.Collection.DocumentSourceUse.authenticate(
              reader,
              guard,
              r["inputs"],
              @selection,
              %{"version" => 1, "epoch" => 0, "status" => "idle"}
            )
          end)

        assert {:ok, facts} = result
        assert length(facts.sources) == 8 and facts.reads <= 269

        claim_value = claim.value

        group_sources =
          Enum.map(claim_value["source_bindings"], fn binding ->
            head = d.model.records["source.notes." <> binding["source_key"]].value

            head
            |> Map.take(~w(source_key ordinal text_bytes chunks bundle_sha256))
            |> Map.put("head_sha256", binding["head_sha256"])
          end)

        group = %{
          "partition" => "notes",
          "catalog_sha256" => claim_value["catalog_sha256"],
          "cursor" => claim_value["cursor"],
          "sources" => group_sources
        }

        assert {:ok, group_facts} =
                 Ipse.Extension.Collection.DocumentSourceUse.authenticate_group_sources(
                   reader,
                   group
                 )

        assert length(group_facts.sources) == 8 and group_facts.reads <= 269
        assert group_facts.bundle_bytes == facts.bundle_bytes

        assert {:ok, catalog_facts} =
                 Ipse.Extension.Collection.DocumentSourceUse.authenticate_catalog_group(
                   reader,
                   "notes",
                   claim_value["catalog_sha256"],
                   claim_value["cursor"]
                 )

        assert catalog_facts.sources === group_facts.sources and catalog_facts.reads <= 279
        assert catalog_facts.bundle_bytes == facts.bundle_bytes

        Process.put(:wide_source_guard_measurement, %{
          microseconds: micros,
          reads: facts.reads,
          bytes: facts.bundle_bytes,
          group_reads: group_facts.reads,
          group_bytes: group_facts.bundle_bytes,
          catalog_reads: catalog_facts.reads
        })
      end

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

    defp packed_parts(""), do: []

    defp packed_parts(bytes) do
      {part, rest} = Evidence.utf8_prefix(bytes, 6144)
      [part | packed_parts(rest)]
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

      assert Progress.ready?(
               d.model.records["genproducer4.notes.0"].value,
               "genproducer4.notes.0"
             )

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

      assert Map.keys(d.model.records) |> Enum.count(&String.starts_with?(&1, "genproducer4.")) ==
               2

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

    @tag :v4_wide_source_guard
    @tag timeout: 120_000
    test "source guard accepts the first batch of eight wide segmented documents" do
      Process.put(:check_wide_source_guard, true)
      {resolved, args, d} = initial_sources(segmented_sources())
      {{:done, {:ok, page}}, _} = invoke(Producer.start(resolved, @profile, args), d)
      assert page["status"] == "page_ready"
      measurement = Process.get(:wide_source_guard_measurement)
      assert measurement.reads <= 269 and measurement.bytes > 500_000
      IO.puts("WIDE_SOURCE_GUARD " <> Jason.encode!(measurement))
    after
      Process.delete(:check_wide_source_guard)
      Process.delete(:wide_source_guard_measurement)
    end

    defp segmented_sources do
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
      assert receipt["version"] == 4

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
    end

    @tag :v4_maintenance_epoch
    test "both producer versions refuse an old Job after a maintenance fence before writes or inference" do
      {resolved, args, d} = initial()
      old = %{d | fault: :advanced_maintenance}
      legacy_args = args |> Map.drop(~w(vector_cursor previous_ready)) |> Map.put("version", 1)

      for request <- [legacy_args, args] do
        assert {{:done, {:error, :shared_producer_changed, _}}, stopped} =
                 invoke(Producer.start(resolved, @profile, request), old)

        assert stopped.calls === 0

        refute Enum.any?(
                 stopped.requests,
                 &(&1["op"] == "embedding.create" or not C.read_request?(&1))
               )
      end
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
      {resolved, args, d} =
        initial(Enum.map(1..8, &"Source #{&1} supports a synthetic relation."))

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

      {{:done, {:ok, _}}, d} =
        invoke(Producer.start(resolved, @profile, first["continuation"]), d)

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

      assert Map.keys(d.model.records) |> Enum.count(&String.starts_with?(&1, "genproducer4.")) ==
               1

      refute Map.has_key?(d.model.records, "generation.notes")
      assert map_size(d.model.stages) == 0
    end

    @tag :v4_empty_facts
    test "explicit empty and mixed fact sets survive group validation and directory selection" do
      for {action, mixed} <- [
            {"finalize_paged", false},
            {"finalize", false},
            {"finalize_paged", true}
          ] do
        {resolved, args, d} = initial(["First synthetic source.", "Second synthetic source."])
        {{:done, {:ok, _}}, d} = invoke(Producer.start(resolved, @profile, args), d)
        {{:done, {:ok, full}}, d} = invoke(Progress.assemble(resolved, @profile, args), d)
        supplied = facts(full.bundles)

        supplied =
          Enum.with_index(supplied)
          |> Enum.map(fn {row, i} ->
            if mixed and i == 1, do: row, else: %{row | "facts" => []}
          end)

        if not mixed do
          packed =
            Enum.zip([full.bundles, supplied, full.vectors])
            |> Enum.map(fn {bundle, entry, vector} ->
              %{
                "source_key" => entry["source_key"],
                "source_bundle_sha256" =>
                  Evidence.sha256(IO.iodata_to_binary(JSON.encode!(bundle["source"]))),
                "vectors" => [vector],
                "facts" => []
              }
            end)

          model_selection = %{
            "kind" => "model_complete",
            "profile" => "extractor",
            "version" => 1
          }

          assert {:error, _} =
                   IpseKnowledge.Store.Collection.Generation.pack_group(
                     "notes",
                     0,
                     full.bundles,
                     packed,
                     @selection,
                     model_selection
                   )
        end

        {{:done, {:error, _, _}}, refused} =
          invoke(Progress.append(resolved, @profile, args, tl(supplied), nil), d)

        assert refused.model.effects == 0

        {{:done, {:ok, appended}}, d} = append(resolved, args, supplied, nil, d)
        {selected, model} = finalize(job_args(action, appended["continuation"]), d.model)
        assert selected["status"] == "selected"
        root = model.records["generation.notes"].value
        assert root["facts"] == if(mixed, do: 1, else: 0)
        assert root["entity_pages"] == [] == !mixed

        expected =
          Map.take(
            root,
            ~w(generation catalog_sha256 catalog_generation floor vector_selection fact_selection)
          )
          |> Map.put("root_sha256", Evidence.sha256(IO.iodata_to_binary(JSON.encode!(root))))

        values = Map.new(model.records, fn {key, record} -> {key, record.value} end)

        assert {:ok, rows} =
                 IpseKnowledge.Store.Collection.Directory.entity_rows(root, values, expected)

        assert rows == [] == !mixed

        request = %{
          "source_ids" => Enum.map(full.bundles, & &1["source"]["source_id"]),
          "vector_selection" => @selection,
          "fact_selection" => @facts,
          "as_of_ms" => 1000
        }

        assert {{:done, {:ok, snapshot}}, _} =
                 M.run(C.start(@profile, :generation_selected, request), M.reset(model))

        assert Enum.sum(Enum.map(snapshot["selected"], &length(&1["facts"]))) == root["facts"]
        refute snapshot["coverage"]["model_receipt_provenance"]
      end
    end

    @tag :v4_empty_facts_multigroup
    test "an empty group and a nonempty group merge into one selected directory" do
      {resolved, args, d} = initial(Enum.map(1..9, &"Synthetic source #{&1}."))
      {{:done, {:ok, _}}, d} = invoke(Producer.start(resolved, @profile, args), d)
      {{:done, {:ok, first}}, d} = invoke(Progress.assemble(resolved, @profile, args), d)
      empty = Enum.map(facts(first.bundles), &%{&1 | "facts" => []})
      {{:done, {:ok, _}}, d} = append(resolved, args, empty, nil, d)
      next = %{args | "job_revision" => d.model.records["genjob.notes"].revision}
      {{:done, {:ok, _}}, d} = invoke(Producer.start(resolved, @profile, next), d)
      {{:done, {:ok, second}}, d} = invoke(Progress.assemble(resolved, @profile, next), d)
      {{:done, {:ok, appended}}, d} = append(resolved, next, facts(second.bundles), nil, d)
      {selected, model} = finalize(job_args("finalize_paged", appended["continuation"]), d.model)
      assert selected["status"] == "selected"
      assert model.records["generation.notes"].value["facts"] == 1

      ids = Enum.map([hd(first.bundles), hd(second.bundles)], & &1["source"]["source_id"])

      request = %{
        "source_ids" => ids,
        "vector_selection" => @selection,
        "fact_selection" => @facts,
        "as_of_ms" => 1000
      }

      assert {{:done, {:ok, snapshot}}, _} =
               M.run(C.start(@profile, :generation_selected, request), M.reset(model))

      assert Enum.sort(Enum.map(snapshot["selected"], &length(&1["facts"]))) == [0, 1]
    end

    @tag :v4_public_fact_stage
    test "public compact facts stage through explicit continuations with source-local citations" do
      {resolved, _, d} = initial(["Synthetic source supports a reviewed relation."])
      source_id = "fixture:progress:0"

      rows =
        for n <- 1..32 do
          %{
            "subject" => "Subject #{n}",
            "predicate" => "supports",
            "object" => "Relation",
            "polarity" => "positive",
            "inferred" => false,
            "valid_from_ms" => nil,
            "valid_to_ms" => nil,
            "spans" => List.duplicate([0, 0, 9], 8)
          }
        end

      args = %{
        "store" => "local",
        "source_id" => source_id,
        "version" => 2,
        "action" => "facts",
        "expected_revision" => 0,
        "facts" => rows,
        "continuation" => nil
      }

      bad = put_in(args, ["facts", Access.at(31), "spans", Access.at(0)], [1, 0, 1])
      {refused, invalid} = public_fact_invoke(resolved, bad, d)
      assert refused["status"] == "refused" and invalid.model.effects == 0

      wide =
        Enum.take(rows, 18)
        |> Enum.map(fn row ->
          row
          |> Map.put("subject", String.duplicate("S", 256))
          |> Map.put("predicate", String.duplicate("P", 128))
          |> Map.put("object", String.duplicate("O", 256))
        end)

      oversized = %{args | "facts" => wide}
      assert byte_size(JSON.encode!(oversized)) > 12_000

      assert :ok =
               Ipse.Extension.validate(%{"id" => "generation_produce", "arguments" => oversized})

      {refused, invalid} = public_fact_invoke(resolved, oversized, d)

      assert refused["status"] == "refused" and invalid.model.effects == 0 and
               invalid.requests == []

      {result, staged} = public_fact_finish(resolved, args, d)
      assert result["status"] == "ok" and result["coverage"]["facts"] == 32
      request = %{"source_id" => source_id, "selection" => @facts, "as_of_ms" => 1000}

      assert {{:done, {:ok, snapshot}}, _} =
               M.run(C.start(@profile, :fact_selected, request), M.reset(staged.model))

      assert length(snapshot["facts"]) == 32
      assert Enum.all?(snapshot["facts"], &(length(&1["citations"]) == 8))
    end

    defp public_fact_finish(resolved, args, d) do
      case public_fact_invoke(resolved, args, d) do
        {%{
           "status" => "draft",
           "continuation" => %{"id" => "generation_produce", "arguments" => next}
         }, d} ->
          public_fact_finish(resolved, next, d)

        result ->
          result
      end
    end

    @tag :v4_selected_empty_facts
    test "durable explicit empty and nonempty facts survive shared selection" do
      {resolved, args, d} = initial(["First synthetic source.", "Second synthetic source."])
      {{:done, {:ok, _}}, d} = invoke(Producer.start(resolved, @profile, args), d)
      {{:done, {:ok, full}}, d} = invoke(Progress.assemble(resolved, @profile, args), d)
      [first, second] = full.bundles
      [_, second_facts] = facts(full.bundles)

      model = stage_fact_projection(first["source"], [], nil, d.model)
      model = stage_fact_projection(second["source"], second_facts["facts"], nil, model)

      requests = Enum.map(model.requests, & &1["request"])
      assert %{"op" => "commit", "generation" => generation} = List.last(requests)
      assert %{"op" => "stage.inspect", "generation" => ^generation} = Enum.at(requests, -2)

      {{:done, {:ok, selected}}, _} =
        M.run(
          C.start(@profile, :fact_selected, %{
            "source_id" => first["source"]["source_id"],
            "selection" => @facts,
            "as_of_ms" => 1000
          }),
          M.reset(model)
        )

      assert selected["facts"] == []

      projection = IpseKnowledge.Store.Collection.Projection
      key = "facts.notes." <> Evidence.sha256(first["source"]["source_id"])
      root = model.records[key].value
      catalog = model.records["catalog.notes"]

      catalog = %{
        "value" => catalog.value,
        "sha256" => Evidence.sha256(IO.iodata_to_binary(JSON.encode!(catalog.value)))
      }

      assert projection.selected_fact_root?(root, @profile, first["source"], @facts, catalog)

      for forged <- [
            Map.put(root, "entities", [String.duplicate("0", 64)]),
            Map.put(root, "facts", 1),
            Map.put(root, "selection", %{
              "kind" => "model_complete",
              "profile" => "model",
              "version" => 1
            })
          ] do
        refute projection.selected_fact_root?(forged, @profile, first["source"], @facts, catalog)
      end

      {{:done, {:ok, appended}}, d} = append_selected(resolved, args, nil, %{d | model: model})
      {selected, model} = finalize(job_args("finalize_paged", appended["continuation"]), d.model)
      assert selected["status"] == "selected"
      assert model.records["generation.notes"].value["facts"] == 1

      selection = %{"kind" => "model_complete", "profile" => "model", "version" => 1}

      assert {:error, :invalid_fact_projection} =
               projection.pack_facts(first["source"], [], selection)

      assert {:error, :fact_projection_corrupt} =
               projection.unpack_facts(first["source"], [], selection)

      assert {:done, {:error, :invalid_vector_projection, _}} =
               C.start(@profile, :fact_store, %{
                 "source_id" => first["source"]["source_id"],
                 "selection" => selection,
                 "facts" => [],
                 "expected_revision" => 0,
                 "as_of_ms" => 1000,
                 "continuation" => nil
               })
    end

    @tag :v4_selected_facts
    test "durable explicit projections feed group append and are rechecked on continuation" do
      {resolved, args, d} = initial(["First synthetic source.", "Second synthetic source."])
      {{:done, {:ok, _}}, d} = invoke(Producer.start(resolved, @profile, args), d)
      {{:done, {:ok, full}}, d} = invoke(Progress.assemble(resolved, @profile, args), d)

      model =
        Enum.zip(full.bundles, facts(full.bundles))
        |> Enum.reduce(d.model, fn {bundle, row}, model ->
          stage_fact_projection(bundle["source"], row["facts"], nil, model)
        end)

      d = %{d | model: model}

      source = hd(full.bundles)["source"]
      key = "facts.notes." <> Evidence.sha256(source["source_id"])
      root = model.records[key]

      corrupt = %{
        root
        | value: Map.put(root.value, "source_bundle_sha256", String.duplicate("0", 64))
      }

      corrupt_model = %{model | records: Map.put(model.records, key, corrupt)}

      assert {{:done, {:error, _, _}}, refused} =
               invoke(Progress.append_selected(resolved, @profile, args, nil), %{
                 d
                 | model: corrupt_model
               })

      assert refused.model.effects == 0

      {{:done, {:continue, first}}, d} =
        invoke(Progress.append_selected(resolved, @profile, args, nil), d)

      assert is_map(first["continuation"])
      [first_bundle | _] = full.bundles
      [first_fact] = hd(facts(full.bundles))["facts"]

      {:ok, changed} =
        first_fact
        |> Map.drop(~w(version fact_id))
        |> Map.put("subject", "Changed")
        |> Evidence.fact()

      changed_model = stage_fact_projection(first_bundle["source"], [changed], nil, d.model, 1)

      assert {{:done, {:error, _, _}}, refused} =
               invoke(
                 Progress.append_selected(resolved, @profile, args, first["continuation"]),
                 %{d | model: changed_model}
               )

      assert refused.model.effects == 0

      {{:done, {:ok, appended}}, d} = append_selected(resolved, args, first["continuation"], d)
      {selected, model} = finalize(job_args("finalize_paged", appended["continuation"]), d.model)
      assert selected["status"] == "selected"
      assert model.records["generation.notes"].value["facts"] == 2

      assert {:done, {:error, :invalid_shared_producer_request, _}} =
               Progress.append_selected(
                 resolved,
                 @profile,
                 %{
                   args
                   | "fact_selection" => %{
                       "kind" => "model_complete",
                       "profile" => "model",
                       "version" => 1
                     }
                 },
                 nil
               )
    end

    defp stage_fact_projection(source, facts, token, model, revision \\ 0) do
      args = %{
        "source_id" => source["source_id"],
        "selection" => @facts,
        "facts" => facts,
        "expected_revision" => revision,
        "as_of_ms" => 1000,
        "continuation" => token
      }

      case M.run(C.start(@profile, :fact_store, args), M.reset(model)) do
        {{:done, {:continue, next}}, model} ->
          stage_fact_projection(source, facts, next["continuation"], model, revision)

        {{:done, {:ok, _}}, model} ->
          model
      end
    end

    defp append_selected(resolved, args, token, d) do
      case invoke(Progress.append_selected(resolved, @profile, args, token), d) do
        {{:done, {:continue, next}}, d} ->
          append_selected(resolved, args, next["continuation"], d)

        result ->
          result
      end
    end

    @tag :v4_staged_change
    test "a changed catalog refuses a resumed metadata stage without another effect" do
      {resolved, args, d} = initial(["A synthetic source supports a staged relation."])
      {{:done, {:ok, _}}, d} = invoke(Producer.start(resolved, @profile, args), d)
      {{:done, {:ok, full}}, d} = invoke(Progress.assemble(resolved, @profile, args), d)
      facts = facts(full.bundles)
      {token, staged} = first_metadata_stage(resolved, args, facts, nil, d)
      assert length(token["stages"]) == 1 and map_size(staged.model.stages) == 1

      generation = staged.model.generation + 1
      catalog = staged.model.records["catalog.notes"]

      changed = %{
        catalog
        | value: Map.update!(catalog.value, "floor", &(&1 + 1)),
          revision: generation
      }

      model = %{
        staged.model
        | generation: generation,
          records: Map.put(staged.model.records, "catalog.notes", changed)
      }

      assert {{:done, {:error, _, _}}, refused} =
               invoke(Progress.append(resolved, @profile, args, facts, token), %{
                 staged
                 | model: model
               })

      assert refused.model.effects == 0 and refused.model.stages === model.stages
      assert refused.calls == staged.calls
    end

    defp first_metadata_stage(resolved, args, facts, token, d) do
      {{:done, {:continue, value}}, d} =
        invoke(Progress.append(resolved, @profile, args, facts, token), d)

      next = value["continuation"]

      if next["stages"] == [],
        do: first_metadata_stage(resolved, args, facts, next, d),
        else: {next, d}
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

    @tag :v4_fact_batch
    test "compact facts regenerate all citations and reject altered spans" do
      {resolved, args, d} = initial(["Synthetic source supports a reviewed relation."])
      {{:done, {:ok, _}}, d} = invoke(Producer.start(resolved, @profile, args), d)
      {{:done, {:ok, full}}, _} = invoke(Progress.assemble(resolved, @profile, args), d)
      [bundle] = full.bundles
      [row] = facts(full.bundles)
      [original] = row["facts"]
      citation = hd(original["citations"])

      many =
        for n <- 1..32 do
          attrs =
            original
            |> Map.drop(~w(version fact_id))
            |> Map.put("subject", "Synthetic #{n}")
            |> Map.put("citations", List.duplicate(citation, 8))

          assert {:ok, fact} = Evidence.fact(attrs)
          fact
        end

      projection = IpseKnowledge.Store.Collection.Projection

      compact =
        Enum.map(many, fn fact ->
          fact
          |> Map.drop(~w(version fact_id extraction citations))
          |> Map.put(
            "spans",
            List.duplicate([0, citation["start_byte"], citation["end_byte"]], 8)
          )
        end)

      assert {:ok, ^many} = projection.facts_from_spans(bundle["source"], compact)
      assert {:ok, []} = projection.facts_from_spans(bundle["source"], [])

      for bad <- [
            put_in(compact, [Access.at(31), "spans", Access.at(0)], [1, 0, 1]),
            put_in(compact, [Access.at(31), "spans", Access.at(0)], [0, -1, 2]),
            put_in(compact, [Access.at(31), "spans"], []),
            List.replace_at(compact, 31, hd(compact))
          ] do
        assert {:error, :invalid_explicit_fact_spans} =
                 projection.facts_from_spans(bundle["source"], bad)
      end

      assert {:ok, pages} = projection.pack_facts(bundle["source"], many, @facts)
      assert {:ok, ^many} = projection.unpack_facts(bundle["source"], pages, @facts)

      supplied = %{
        "source_key" => bundle["source"]["source_key"],
        "source_bundle_sha256" =>
          Evidence.sha256(IO.iodata_to_binary(JSON.encode!(bundle["source"]))),
        "vectors" => full.vectors,
        "facts" => many
      }

      generation = IpseKnowledge.Store.Collection.Generation

      assert {:ok, _} =
               generation.pack_group("notes", 0, [bundle], [supplied], @selection, @facts)

      forged_citation = Map.put(citation, "source_id", "forged:source")

      assert {:ok, forged_fact} =
               original
               |> Map.drop(~w(version fact_id))
               |> Map.put("citations", [forged_citation])
               |> Evidence.fact()

      forged_facts = List.replace_at(many, 31, forged_fact)

      assert {:error, _} =
               generation.pack_group(
                 "notes",
                 0,
                 [bundle],
                 [%{supplied | "facts" => forged_facts}],
                 @selection,
                 @facts
               )

      [page | rest] = pages
      [first | rows] = page["rows"]
      [span | spans] = first["citations"]
      forged = List.replace_at(span, 3, String.duplicate("0", 64))
      bad = [%{page | "rows" => [%{first | "citations" => [forged | spans]} | rows]} | rest]

      assert {:error, :fact_projection_corrupt} =
               projection.unpack_facts(bundle["source"], bad, @facts)

      assert {:error, :fact_projection_corrupt} =
               projection.unpack_facts(bundle["source"], pages, %{
                 "kind" => "explicit",
                 "profile" => "other",
                 "version" => 1
               })
    end

    @tag :v4_fact_input_pages
    test "maximum-width escaped compact facts form bounded canonical pages and reject altered sets" do
      {resolved, args, d} = initial(["Synthetic source supports a reviewed relation."])
      {{:done, {:ok, _}}, d} = invoke(Producer.start(resolved, @profile, args), d)
      {{:done, {:ok, full}}, _} = invoke(Progress.assemble(resolved, @profile, args), d)
      original = hd(full.bundles)["source"]

      {:ok, source} =
        original
        |> Map.drop(~w(version source_key content_sha256 chunking))
        |> Map.put("text", String.duplicate("x", 65_536))
        |> Evidence.collection_source()

      rows =
        for n <- 1..32 do
          %{
            "subject" =>
              String.duplicate("\\\"", 126) <> String.pad_leading(Integer.to_string(n), 2, "0"),
            "predicate" => String.duplicate("\\\"", 64),
            "object" => String.duplicate("\\\"", 128),
            "polarity" => "positive",
            "inferred" => false,
            "valid_from_ms" => Evidence.safe_integer_max(),
            "valid_to_ms" => Evidence.safe_integer_max(),
            "spans" => List.duplicate([15, 61_440, 61_441], 8)
          }
        end

      p = IpseKnowledge.Store.Collection.Projection
      assert {:ok, %{pages: pages, manifest: manifest}} = p.fact_input_pages(source, rows)
      assert length(pages) in 2..8

      IO.puts(
        "FACT_INPUT_PAGE_GEOMETRY " <>
          Jason.encode!(%{
            pages: length(pages),
            bytes:
              Enum.map(pages, fn page -> byte_size(IO.iodata_to_binary(JSON.encode!(page))) end),
            manifest_bytes: byte_size(Jason.encode!(manifest)),
            facts: length(rows)
          })
      )

      assert Enum.all?(pages, &(byte_size(IO.iodata_to_binary(JSON.encode!(&1))) <= 7_000))

      for page <- pages do
        slot = %{
          "version" => 1,
          "kind" => "explicit_fact_input_slot",
          "draft_id" => String.duplicate("a", 32),
          "source_key" => source["source_key"],
          "page" => page,
          "manifest" => manifest
        }

        bytes = IO.iodata_to_binary(JSON.encode!(slot))
        assert byte_size(bytes) <= 8_192

        request = %{
          "op" => "collection.store",
          "scope" => "project",
          "request" => %{
            "op" => "value.put_inline",
            "key" => "factdraft.notes.#{page["ordinal"]}",
            "expected_revision" => 0,
            "byte_count" => byte_size(bytes),
            "sha256" => Evidence.sha256(bytes),
            "data" => bytes,
            "generation" => 1
          }
        }

        assert :ok = Ipse.Extension.CollectionStore.validate(request)

        assert :ok =
                 Ipse.Extension.validate(%{
                   "api_version" => 1,
                   "kind" => "host_call",
                   "request" => request
                 })
      end

      assert {:ok, %{rows: ^rows, facts: facts}} = p.fact_input_rows(source, pages, manifest)
      assert length(facts) == 32 and Enum.all?(facts, &(length(&1["citations"]) == 8))
      assert {:ok, fact_pages} = p.pack_facts(source, facts, @facts)
      assert length(fact_pages) >= 2
      assert Enum.all?(fact_pages, &IpseKnowledge.Store.Collection.Paged.native_value?/1)
      assert {:ok, ^facts} = p.unpack_facts(source, fact_pages, @facts)
      assert {:ok, %{pages: [], manifest: empty_manifest}} = p.fact_input_pages(source, [])
      assert {:ok, %{rows: [], facts: []}} = p.fact_input_rows(source, [], empty_manifest)

      [first | rest] = pages

      for bad <- [
            Enum.reverse(pages),
            rest,
            Enum.drop(pages, -1),
            [Map.put(first, "ordinal", 1) | rest],
            [Map.put(first, "source_bundle_sha256", String.duplicate("0", 64)) | rest]
          ] do
        assert {:error, :invalid_fact_input_pages} = p.fact_input_rows(source, bad, manifest)
      end

      forged = Map.update!(manifest, "row_count", &(&1 - 1))
      assert {:error, :invalid_fact_input_pages} = p.fact_input_rows(source, pages, forged)
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
else
  defmodule Ipse.ProducerProgressTest do
    use ExUnit.Case, async: false

    setup_all do
      root = Path.join(System.tmp_dir!(), "ipse-producer-progress-artifact-" <> Ipse.Usage.id())
      File.mkdir_p!(root)
      on_exit(fn -> File.rm_rf!(root) end)
      artifact = Path.join(root, "corpus")

      {output, status} =
        System.cmd(
          System.find_executable("elixir"),
          [
            "extensions/knowledge/build.exs",
            "--sdk",
            Application.app_dir(:ipse, "ebin"),
            "--output",
            artifact,
            "--package",
            "corpus",
            "--preset",
            "collection-dense"
          ],
          stderr_to_stdout: true
        )

      assert status == 0, output
      %{artifact: artifact}
    end

    for tag <- ~w(v4_pages v4_public_continuation v4_wide_geometry v4_segmented_geometry
                v4_wide_source_guard v4_unknown v4_source_integrity v4_span_batch
                v4_object_revision v4_anchor_reserve v4_packed_fact_pages v4_corruption
                v4_append v4_empty_facts v4_empty_facts_multigroup v4_staged_change
                v4_selected_reuse v4_fact_batch v4_selected_facts v4_selected_empty_facts
                v4_public_fact_stage v4_fact_input_pages v4_maintenance_epoch)a do
      @tag tag
      @tag timeout: 600_000
      test "isolated producer progress control #{tag}", %{artifact: artifact} do
        tag = unquote(tag)

        paths =
          :code.get_path()
          |> Enum.map(&List.to_string/1)
          |> Enum.filter(&(Path.basename(&1) == "ebin"))
          |> Enum.flat_map(&["-pa", &1])

        script =
          "ExUnit.start(autorun: false, exclude: [:test], include: [{#{inspect(tag)}, true}]); " <>
            "{:ok, _} = Application.ensure_all_started(:ipse); " <>
            "Code.require_file(#{inspect(Path.expand(__ENV__.file))}); " <>
            "result = ExUnit.run(); " <>
            "if Map.take(result, [:total, :failures, :excluded, :skipped]) != " <>
            "%{total: 23, failures: 0, excluded: 22, skipped: 0}, do: System.halt(1); " <>
            "IO.puts(\"PRODUCER_PROGRESS_CONTROL_PASS #{tag}\")"

        {output, status} =
          System.cmd(
            System.find_executable("elixir"),
            ["--erl", "+S 2:2"] ++ paths ++ ["-pa", Path.join(artifact, "ebin"), "-e", script],
            stderr_to_stdout: true,
            env: [
              {"IPSE_PRODUCER_PROGRESS_CHILD", "1"},
              {"ERL_LIBS", Path.dirname(Application.app_dir(:ipse))}
            ]
          )

        assert status == 0, output

        assert Enum.count(
                 String.split(output, "\n"),
                 &(&1 == "PRODUCER_PROGRESS_CONTROL_PASS #{tag}")
               ) == 1

        IO.write(output)
      end
    end
  end
end
