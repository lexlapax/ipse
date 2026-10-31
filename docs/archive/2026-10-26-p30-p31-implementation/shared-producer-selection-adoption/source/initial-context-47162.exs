ExUnit.start()

Code.require_file("dev/knowledge/collection_recipe_model.ex")

corpus =
  File.read!("extensions/knowledge/src/corpus.ex")
  |> String.replace(~s(@preset "state-lexical"), ~s(@preset "collection-dense"), global: false)

Code.compile_string(corpus, "extensions/knowledge/src/corpus.ex")

defmodule Ipse.SharedProducerTest do
  use ExUnit.Case, async: false
  alias Ipse.CollectionRecipeModel, as: M
  alias IpseKnowledge.{Adapters, Evidence, Profiles}
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
    source = %{
      "source_id" => "fixture:producer",
      "partition" => "notes",
      "generation" => 1,
      "title" => "Producer fixture",
      "text" => String.duplicate("alpha beta ", 4_000),
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

    put = %{"source" => source, "expected_revision" => 0, "continuation" => nil}
    model = put_loop(put, M.new(%{}, 1000))

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
    assert d.model.records["genproducer.notes"].value["status"] == "pending"
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

  test "public page production refuses before any claim, host call or inference" do
    {resolved, args, d} = initial()
    {:ok, state} = IpseKnowledge.Corpus.init(resolved["options"])
    before = d.model.records

    assert {:ok, %{"kind" => "result", "value" => result}, _} =
             IpseKnowledge.Corpus.handle(
               "invoke.command",
               %{"id" => "generation_produce", "arguments" => Map.put(args, "store", "local")},
               state
             )

    assert result["status"] == "refused"
    assert result["gaps"] == [%{"code" => "shared_producer_source_dispatch_unavailable"}]
    assert d.calls == 0 and d.requests == [] and d.model.records === before
    refute Map.has_key?(d.model.records, "genproducer.notes")
  end

  defp configured_selection do
    config = %{
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

  test "read-only domain selection setup preserves configured identity and never invents reported model" do
    {resolved, _, _} = initial()
    {_, value} = configured_selection()
    assert {:call, request, cont} = Producer.selection(resolved, "learned")
    assert request == %{"op" => "embedding.profile", "version" => 1, "profile" => "encoder"}
    assert {:done, {:ok, setup}} = Producer.resume(cont, %{"status" => "ok", "value" => value})
    assert setup["configured_profile"] === value["profile"]
    assert setup["selection_sha256"] === value["selection_sha256"]
    assert setup["reported_model"] == nil and setup["coverage"]["effects_used"] == 0
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
      assert {:done, {:error, :invalid_adapter_input}} =
               Adapters.start(
                 resolved,
                 :embed,
                 Map.put(args, "expected_selection_sha256", malformed)
               )
    end
  end

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

  test "bootstrap aliases malformed versions and post-response pin mismatches refuse" do
    {resolved, _, _} = initial()
    {_, value} = configured_selection()
    {:call, _, state} = Adapters.start(resolved, :embedding_profile, %{"profile" => "learned"})

    assert {:done, {:error, :invalid_embedding_profile}} =
             Adapters.resume(state, %{
               "status" => "ok",
               "value" => put_in(value, ["profile", "id"], "foreign")
             })

    assert {:done, {:error, :invalid_embedding_profile}} =
             Adapters.resume(state, %{"status" => "ok", "value" => Map.put(value, "version", 1.0)})

    assert {:done, {:error, :invalid_profile}} =
             Adapters.start(resolved, :embedding_profile, %{"profile" => "missing"})

    {:call, _, embedding} =
      Adapters.start(resolved, :embed, %{
        "profile" => "learned",
        "inputs" => [%{"chunk_id" => Evidence.sha256("input"), "text" => "Exact input"}],
        "expected_selection_sha256" => value["selection_sha256"]
      })

    assert {:done, {:error, :invalid_embedding_result}} =
             Adapters.resume(embedding, %{
               "status" => "ok",
               "value" => %{
                 "version" => 2,
                 "selection_sha256" => String.duplicate("b", 64),
                 "result" => nil
               }
             })
  end
end
