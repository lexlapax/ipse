corpus =
  File.read!("extensions/knowledge/src/corpus.ex")
  |> String.replace(
    "defmodule IpseKnowledge.Corpus do",
    "defmodule IpseKnowledge.CollectionTimeCorpus do",
    global: false
  )
  |> String.replace(~s(@preset "state-lexical"), ~s(@preset "collection-documents"),
    global: false
  )

Code.compile_string(corpus, "private-collection-corpus.ex")

defmodule CollectionCorpusBoundaryTest do
  use ExUnit.Case, async: false
  alias IpseKnowledge.CollectionCompletedBackupCases, as: Fixture
  alias IpseKnowledge.CollectionTimeCorpus, as: Corpus
  alias IpseTest.CollectionProtocol, as: P

  def run({:ok, %{"kind" => "host_call", "request" => request}, state}, model, wait) do
    if wait, do: wait.()
    {result, model} = P.execute(request["request"], model)

    outcome = %{
      "status" => "ok",
      "value" => %{
        "version" => 1,
        "operation_id" => String.duplicate("a", 32),
        "request_sha256" => Ipse.JSON.digest([request]),
        "result" => result
      }
    }

    run(Corpus.handle("host.actions", %{"outcome" => outcome}, state), model, nil)
  end

  def run({:ok, %{"kind" => "result", "value" => value}, state}, model, _),
    do: {value, state, model}

  def run({:ok, %{bytes: bytes}, state}, model, _), do: {JSON.decode!(bytes), state, model}

  test "real Collection query paths refuse crossed source deadline and retain explicit history" do
    for route <- [:namespace, :selected], mode <- [:stable, :expired, :historical] do
      now = System.system_time(:millisecond)
      deadline = now + 1200
      Process.put(:observed, 10)
      Process.put(:expires, deadline)
      c = Fixture.temporal_fixture()

      options =
        JSON.decode!(File.read!("extensions/knowledge/options/corpus-lexical.json"))
        |> put_in(["stores", "notes"], %{
          "kind" => "collection",
          "scope" => "project",
          "partition" => "docs"
        })

      {:ok, state} = Corpus.init(options)
      refute Map.has_key?(state, :invalid)

      args = %{
        "store" => "notes",
        "retrieval" => "words",
        "query" => "Ada",
        "top_k" => 1,
        "as_of_ms" => if(mode == :historical, do: now, else: nil)
      }

      {id, args} =
        if route == :namespace,
          do: {"query", Map.put(args, "rerank", nil)},
          else: {"query_selected", Map.put(args, "source_ids", ["backup:one"])}

      model = P.new(c.values, 1010)

      wait =
        if mode == :stable,
          do: nil,
          else: fn -> Process.sleep(max(deadline - System.system_time(:millisecond) + 5, 0)) end

      {value, _, after_model} =
        run(
          Corpus.handle("invoke.command", %{"id" => id, "arguments" => args}, state),
          model,
          wait
        )

      assert after_model.records == model.records

      if mode == :expired do
        assert value["status"] == "refused" and
                 value["gaps"] == [%{"code" => "query_time_changed"}]

        assert value["evidence"] == [] and value["claims"] == []
      else
        assert value["status"] == "ok"
      end
    end
  end
end

defmodule CollectionSemanticStoreDouble do
  def start(_, :generation_selected, _), do: {:done, {:ok, Process.get(:selected)}}
  def start(profile, op, args), do: IpseKnowledge.Store.Collection.start(profile, op, args)
  def resume(:terminal, _), do: {:done, {:ok, Process.get(:checked)}}
  def resume(cont, outcome), do: IpseKnowledge.Store.Collection.resume(cont, outcome)
  def read_request?(request), do: IpseKnowledge.Store.Collection.read_request?(request)
  def snapshot_epoch(value), do: IpseKnowledge.Store.Collection.snapshot_epoch(value)
end

defmodule CollectionSemanticAdaptersDouble do
  def start(_, :embedding_profile, _), do: {:call, %{"op" => "embedding.profile"}, %{}}
  def start(_, :embed, _), do: {:call, %{"op" => "embedding.create"}, %{}}
  def start(resolved, op, args), do: IpseKnowledge.Adapters.start(resolved, op, args)

  def resume(_, _),
    do:
      {:done,
       {:ok,
        %{
          "selection_sha256" => Process.get(:selection)["selection_sha256"],
          "profile" => %{"id" => "encoder"}
        }}}
end

semantic_source =
  File.read!("extensions/knowledge/src/corpus.ex")
  |> String.replace(
    "defmodule IpseKnowledge.Corpus do",
    "defmodule IpseKnowledge.CollectionSemanticTimeCorpus do",
    global: false
  )
  |> String.replace(
    "alias IpseKnowledge.{Adapters, Documents, Evidence, Profiles, Store}",
    "alias IpseKnowledge.{Documents, Evidence, Profiles, Store}\n  alias CollectionSemanticAdaptersDouble, as: Adapters",
    global: false
  )
  |> String.replace(
    "alias IpseKnowledge.Store.Collection, as: CollectionStore",
    "alias CollectionSemanticStoreDouble, as: CollectionStore",
    global: false
  )
  |> String.replace(~s(@preset "state-lexical"), ~s(@preset "collection-dense"), global: false)

Code.compile_string(semantic_source, "private-collection-semantic-corpus.ex")

defmodule CollectionSemanticBoundaryTest do
  use ExUnit.Case, async: false
  alias IpseKnowledge.CollectionCompletedBackupCases, as: Fixture
  alias IpseKnowledge.CollectionSemanticTimeCorpus, as: Corpus

  test "selected fact transitions prevent pre-embedding proposal with fail-closed context" do
    for transition <- [:start, :end],
        mode <- [:crossed, :historical, :stable, :missing, :wrong] do
      now = System.system_time(:millisecond)
      deadline = now + 60_000
      Process.put(:observed, 10)
      Process.put(:expires, nil)
      source = Fixture.temporal_fixture().source

      fact = %{
        "valid_from_ms" => if(transition == :start, do: deadline),
        "valid_to_ms" => if(transition == :end, do: deadline)
      }

      Process.put(:selected, %{
        "selected" => [%{"source" => source, "vectors" => [], "facts" => [fact]}],
        "native_generation" => 1,
        "generation" => 1,
        "catalog_sha256" => "fixture",
        "coverage" => %{"reads_used" => 0}
      })

      selection = %{
        "selection_sha256" => IpseKnowledge.Evidence.sha256("selection"),
        "profile" => "encoder",
        "model" => "fixture",
        "dimensions" => 1,
        "encoding" => "float32le"
      }

      Process.put(:selection, selection)

      options =
        JSON.decode!(File.read!("extensions/knowledge/options/corpus-lexical.json"))
        |> put_in(["stores", "notes"], %{
          "kind" => "collection",
          "scope" => "project",
          "partition" => "docs"
        })
        |> put_in(["retrieval", "dense"], %{
          "kind" => "dense",
          "version" => 1,
          "embedding" => "vectors"
        })
        |> put_in(["embedding", "vectors"], %{"kind" => "embedding", "profile" => "encoder"})

      {:ok, state} = Corpus.init(options)
      refute Map.has_key?(state, :invalid)

      args = %{
        "store" => "notes",
        "retrieval" => "dense",
        "query" => "Ada",
        "top_k" => 1,
        "as_of_ms" => if(mode == :historical, do: now, else: nil),
        "source_ids" => ["backup:one"],
        "vector_selection" => selection,
        "fact_selection" => %{"kind" => "explicit", "profile" => nil, "version" => 1}
      }

      assert {:ok, %{"kind" => "host_call", "request" => %{"op" => "embedding.profile"}}, pending} =
               Corpus.handle(
                 "invoke.command",
                 %{"id" => "query_selected", "arguments" => args},
                 state
               )

      assert pending.ctx.query_time_transition == deadline
      assert pending.collection_query == true

      ctx =
        case mode do
          :crossed ->
            pending.ctx
            |> Map.put(:as_of_ms, now - 120_000)
            |> Map.put(:query_time_transition, now - 60_000)

          :historical ->
            pending.ctx
            |> Map.put(:as_of_ms, now - 120_000)
            |> Map.put(:query_time_transition, now - 60_000)
            |> put_in([:args, "as_of_ms"], now - 120_000)

          :missing ->
            Map.delete(pending.ctx, :query_time_transition)

          :wrong ->
            Map.put(pending.ctx, :query_time_scope, :wrong)

          :stable ->
            pending.ctx
        end

      result =
        Corpus.handle("host.actions", %{"outcome" => %{"status" => "ok"}}, %{pending | ctx: ctx})

      if mode in [:crossed, :missing, :wrong] do
        assert {:ok, %{"kind" => "result", "value" => value}, _} = result

        assert value["status"] == "refused" and
                 value["gaps"] == [%{"code" => "query_time_changed"}]

        assert value["evidence"] == [] and value["claims"] == []
      else
        assert {:ok, %{"kind" => "host_call", "request" => %{"op" => "embedding.create"}}, _} =
                 result
      end

      if mode in [:crossed, :historical, :stable] do
        Process.put(:checked, %{
          "native_generation" => 1,
          "record" => %{"sha256" => "fixture"},
          "coverage" => %{"reads_used" => 1}
        })

        rank = %{
          "status" => "abstain",
          "evidence" => [],
          "claims" => [],
          "gaps" => [],
          "coverage" => %{"complete" => true}
        }

        final_ctx = ctx |> Map.put(:rank, rank) |> Map.put(:embedding_result_reads, 0)

        final_state = %{
          pending
          | phase: :collection_semantic_revalidate,
            pending: :collection,
            cont: :terminal,
            ctx: final_ctx
        }

        assert {:ok, %{"kind" => "result", "value" => final}, _} =
                 Corpus.handle("host.actions", %{"outcome" => %{"status" => "ok"}}, final_state)

        if mode == :crossed do
          assert final["status"] == "refused" and
                   final["gaps"] == [%{"code" => "query_time_changed"}]
        else
          assert final["status"] == "abstain"
        end

        assert final["evidence"] == []

        if mode == :crossed do
          assert final["claims"] == []
        else
          assert [%{"label" => "open", "evidence_indexes" => []}] = final["claims"]
        end
      end
    end
  end
end

for {suffix, mutation} <- [
      {"MissingTransition",
       fn src ->
         String.replace(src, "Map.get(rank, \"query_time_transition\", :missing)", ":missing",
           global: false
         )
       end},
      {"WrongScope",
       fn src ->
         String.replace(
           src,
           "Map.put(:query_time_scope, :collection)",
           "Map.put(:query_time_scope, :wrong)",
           global: false
         )
       end}
    ] do
  source =
    File.read!("extensions/knowledge/src/corpus.ex")
    |> String.replace(
      "defmodule IpseKnowledge.Corpus do",
      "defmodule IpseKnowledge.Collection#{suffix}Corpus do",
      global: false
    )
    |> String.replace(~s(@preset "state-lexical"), ~s(@preset "collection-documents"),
      global: false
    )
    |> mutation.()

  Code.compile_string(source, "private-collection-#{suffix}.ex")
end

defmodule CollectionFaultBoundaryTest do
  use ExUnit.Case, async: false
  alias IpseKnowledge.CollectionCompletedBackupCases, as: Fixture
  alias IpseTest.CollectionProtocol, as: P

  test "namespace output refuses missing transition and incorrect scope" do
    for module <- [
          IpseKnowledge.CollectionMissingTransitionCorpus,
          IpseKnowledge.CollectionWrongScopeCorpus
        ] do
      Process.put(:observed, 10)
      Process.put(:expires, nil)
      c = Fixture.temporal_fixture()

      opts =
        JSON.decode!(File.read!("extensions/knowledge/options/corpus-lexical.json"))
        |> put_in(["stores", "notes"], %{
          "kind" => "collection",
          "scope" => "project",
          "partition" => "docs"
        })

      {:ok, state} = module.init(opts)

      args = %{
        "store" => "notes",
        "retrieval" => "words",
        "rerank" => nil,
        "query" => "Ada",
        "top_k" => 1,
        "as_of_ms" => nil
      }

      {value, _, _} =
        run(
          module,
          module.handle("invoke.command", %{"id" => "query", "arguments" => args}, state),
          P.new(c.values, 1010)
        )

      assert value["status"] == "refused" and value["gaps"] == [%{"code" => "query_time_changed"}]
      assert value["evidence"] == [] and value["claims"] == []
    end
  end

  defp run(module, {:ok, %{"kind" => "host_call", "request" => request}, state}, model) do
    {result, model} = P.execute(request["request"], model)

    outcome = %{
      "status" => "ok",
      "value" => %{
        "version" => 1,
        "operation_id" => String.duplicate("a", 32),
        "request_sha256" => Ipse.JSON.digest([request]),
        "result" => result
      }
    }

    run(module, module.handle("host.actions", %{"outcome" => outcome}, state), model)
  end

  defp run(_, {:ok, %{"kind" => "result", "value" => value}, state}, model),
    do: {value, state, model}

  defp run(_, {:ok, %{bytes: bytes}, state}, model), do: {JSON.decode!(bytes), state, model}

  test "actual Index derives boundaries from eligible and ineligible source summaries" do
    for {observed, expires, selected, expected} <- [
          {10, 200, 100, 200},
          {200, nil, 100, 200},
          {10, 90, 100, nil},
          {10, nil, 100, nil},
          {10, 200, 200, nil}
        ] do
      Process.put(:observed, observed)
      Process.put(:expires, expires)
      c = Fixture.temporal_fixture()

      {result, _} =
        P.run(
          IpseKnowledge.Store.Collection.start(
            %{"kind" => "collection", "scope" => "project", "partition" => "docs"},
            :lexical_query,
            %{"query" => "Ada", "top_k" => 1, "as_of_ms" => selected}
          ),
          P.new(c.values, 1010)
        )

      assert {:done, {:ok, rank}} = result

      assert Map.has_key?(rank, "query_time_transition") and
               rank["query_time_transition"] == expected

      assert rank["coverage"]["namespace_complete"] == true
    end
  end

  test "empty namespace refuses when an unreturned source becomes eligible" do
    for mode <- [:crossed, :historical, :stable] do
      now = System.system_time(:millisecond)
      deadline = now + 1200
      Process.put(:observed, deadline)
      Process.put(:expires, nil)
      c = Fixture.temporal_fixture()

      opts =
        JSON.decode!(File.read!("extensions/knowledge/options/corpus-lexical.json"))
        |> put_in(["stores", "notes"], %{
          "kind" => "collection",
          "scope" => "project",
          "partition" => "docs"
        })

      {:ok, state} = IpseKnowledge.CollectionTimeCorpus.init(opts)

      args = %{
        "store" => "notes",
        "retrieval" => "words",
        "rerank" => nil,
        "query" => "Ada",
        "top_k" => 1,
        "as_of_ms" => if(mode == :historical, do: now, else: nil)
      }

      wait =
        if mode == :stable,
          do: nil,
          else: fn -> Process.sleep(max(deadline - System.system_time(:millisecond) + 5, 0)) end

      {value, _, _} =
        CollectionCorpusBoundaryTest.run(
          IpseKnowledge.CollectionTimeCorpus.handle(
            "invoke.command",
            %{"id" => "query", "arguments" => args},
            state
          ),
          P.new(c.values, 1010),
          wait
        )

      if mode == :crossed do
        assert value["status"] == "refused" and
                 value["gaps"] == [%{"code" => "query_time_changed"}]
      else
        assert value["status"] == "abstain"
      end

      assert value["evidence"] == [] and value["claims"] == []
    end
  end
end

defmodule CollectionWorkspaceBoundaryTest do
  use ExUnit.Case, async: false
  alias IpseKnowledge.CollectionCompletedBackupCases, as: Fixture
  alias IpseKnowledge.CollectionTimeCorpus, as: Corpus
  alias IpseKnowledge.Evidence, as: E
  alias IpseTest.CollectionProtocol, as: P

  defp receipt(text, original) do
    %{
      "kind" => "document_extraction",
      "version" => 2,
      "format" => "docx",
      "original_sha256" => E.sha256(original),
      "original_bytes" => byte_size(original),
      "extraction_version" => "ipse-documents-v14",
      "status" => "complete",
      "warnings" => [],
      "segments" => [
        %{
          "start_byte" => 0,
          "end_byte" => byte_size(text),
          "text_sha256" => E.sha256(text),
          "locator" => %{"kind" => "paragraph", "part" => "word/document.xml", "paragraph" => 1}
        }
      ],
      "acquisition" => %{
        "kind" => "workspace.read",
        "path" => "source.docx",
        "operation_id" => String.duplicate("2", 32)
      }
    }
  end

  defp until_workspace(
         {:ok, %{"kind" => "host_call", "request" => req}, %{phase: :document_use_check} = state},
         model
       ),
       do: {req, state, model}

  defp until_workspace({:ok, %{"kind" => "host_call", "request" => request}, state}, model) do
    {value, model} = P.execute(request["request"], model)

    outcome = %{
      "status" => "ok",
      "value" => %{
        "version" => 1,
        "operation_id" => String.duplicate("a", 32),
        "request_sha256" => Ipse.JSON.digest([request]),
        "result" => value
      }
    }

    until_workspace(Corpus.handle("host.actions", %{"outcome" => outcome}, state), model)
  end

  defp page(original) do
    first = binary_part(original, 0, 1)

    value = %{
      "version" => 2,
      "encoding" => "base64",
      "path" => "source.docx",
      "byte_count" => byte_size(original),
      "sha256" => E.sha256(original),
      "data" => Base.encode64(first),
      "offset" => 0,
      "page_sha256" => E.sha256(first),
      "next" => 1
    }

    %{
      "operation_id" => String.duplicate("3", 32),
      "outcome" => %{
        "status" => "ok",
        "value" => %{"text" => IO.iodata_to_binary(JSON.encode!(value))}
      }
    }
  end

  test "Collection rechecks time after simulated workspace callback" do
    for mode <- [:crossed_actual, :crossed_simulated, :historical, :stable] do
      now = System.system_time(:millisecond)
      deadline = now + if(mode == :crossed_actual, do: 1200, else: 60_000)
      Process.put(:observed, 10)
      Process.put(:expires, deadline)
      original = "synthetic original"
      doc = receipt("Ada knows Bea. Café evidence.", original)
      assert E.valid_document?(doc, "Ada knows Bea. Café evidence.")
      c = Fixture.temporal_fixture(doc)

      opts =
        JSON.decode!(File.read!("extensions/knowledge/options/corpus-lexical.json"))
        |> put_in(["stores", "notes"], %{
          "kind" => "collection",
          "scope" => "project",
          "partition" => "docs"
        })

      {:ok, state} = Corpus.init(opts)

      args = %{
        "store" => "notes",
        "retrieval" => "words",
        "rerank" => nil,
        "query" => "Ada",
        "top_k" => 1,
        "as_of_ms" => if(mode == :historical, do: now, else: nil)
      }

      {request, pending, model} =
        until_workspace(
          Corpus.handle("invoke.command", %{"id" => "query", "arguments" => args}, state),
          P.new(c.values, 1010)
        )

      assert request["op"] == "tool.call" and pending.ctx.query_time_transition == deadline

      assert {:ok, %{"kind" => "host_call", "request" => read}, fence} =
               Corpus.handle("host.actions", page(original), pending)

      assert fence.phase == :document_use_collection

      if mode == :crossed_actual,
        do: Process.sleep(max(deadline - System.system_time(:millisecond) + 5, 0))

      fence =
        if mode == :crossed_simulated do
          ctx =
            fence.ctx
            |> Map.put(:as_of_ms, now - 120_000)
            |> Map.put(:query_time_transition, now - 60_000)

          %{fence | ctx: ctx}
        else
          fence
        end

      {value, model} = P.execute(read["request"], model)

      outcome = %{
        "status" => "ok",
        "value" => %{
          "version" => 1,
          "operation_id" => String.duplicate("a", 32),
          "request_sha256" => Ipse.JSON.digest([read]),
          "result" => value
        }
      }

      {result, _, _} =
        CollectionCorpusBoundaryTest.run(
          Corpus.handle("host.actions", %{"outcome" => outcome}, fence),
          model,
          nil
        )

      if mode == :crossed_simulated do
        assert result["status"] == "refused" and
                 result["gaps"] == [%{"code" => "query_time_changed"}]

        assert result["evidence"] == [] and result["claims"] == []
      else
        if mode == :crossed_actual do
          assert result["status"] == "conflict" and
                   result["gaps"] == [%{"code" => "snapshot_changed"}]

          assert result["evidence"] == [] and result["claims"] == []
        else
          assert result["status"] == "ok"
        end
      end
    end
  end
end
