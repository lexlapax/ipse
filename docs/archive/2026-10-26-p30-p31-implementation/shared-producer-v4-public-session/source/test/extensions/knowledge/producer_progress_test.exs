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
    id = Integer.to_string(d.calls + 1, 16) |> String.pad_leading(32, "0")
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
    case invoke(Progress.append(resolved, @profile, args, facts, token), d) do
      {{:done, {:continue, value}}, d} -> append(resolved, args, facts, value["continuation"], d)
      terminal -> terminal
    end
  end
end
