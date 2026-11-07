ExUnit.start(autorun: false, max_cases: 1, seed: 1306)
Code.require_file("extensions/knowledge/src/store.ex")
Code.require_file("extensions/knowledge/src/corpus.ex")

mcp =
  File.read!("extensions/knowledge/src/corpus.ex")
  |> String.replace("defmodule IpseKnowledge.Corpus do", "defmodule IpseKnowledge.CorpusMCP do",
    global: false
  )
  |> String.replace(~s(@preset "state-lexical"), ~s(@preset "mcp-lexical"), global: false)

Code.compile_string(mcp, "private-corpus-mcp.ex")
Code.require_file("dev/fixtures/knowledge.exs")

defmodule FenceControls do
  use ExUnit.Case, async: false
  alias IpseKnowledge.{Store, Evidence}
  alias Ipse.Development.Fixtures.Knowledge, as: F

  def options(kind) do
    opts = JSON.decode!(File.read!("extensions/knowledge/options/corpus-lexical.json"))

    if kind == :state,
      do: opts,
      else:
        put_in(opts, ["stores", "notes"], %{
          "kind" => "mcp_cas",
          "binding" => "storage",
          "partition" => "manual",
          "contract" => "ipse-cas-v3"
        })
  end

  def init(kind) do
    module = if kind == :state, do: IpseKnowledge.Corpus, else: IpseKnowledge.CorpusMCP
    opts = options(kind)
    {:ok, s} = module.init(opts)
    refute Map.has_key?(s, :invalid)
    {module, s, F.new("manual"), opts["stores"]["notes"]}
  end

  def run(module, {:ok, %{"kind" => "host_call", "request" => req}, s}, db) do
    {out, db} = F.host(db, req)
    run(module, module.handle("host.actions", %{"outcome" => out}, s), db)
  end

  def run(_, {:ok, %{bytes: bytes}, s}, db), do: {JSON.decode!(bytes), s, db}
  def run(_, {:ok, %{"kind" => "result", "value" => value}, s}, db), do: {value, s, db}

  def hold(
        module,
        {:ok, %{"kind" => "host_call", "request" => req}, %{phase: :query_revalidate} = s},
        db
      ),
      do: {module, req, s, db}

  def hold(module, {:ok, %{"kind" => "host_call", "request" => req}, s}, db) do
    {out, db} = F.host(db, req)
    hold(module, module.handle("host.actions", %{"outcome" => out}, s), db)
  end

  def source(module, state, db, id) do
    args = %{
      "store" => "notes",
      "action" => "put",
      "args" => %{
        "source_id" => id,
        "generation" => 1,
        "expected_revision" => 0,
        "title" => id,
        "text" => "Release requires audit.",
        "uri" => "provided:" <> id,
        "observed_at_ms" => 1,
        "event_at_ms" => nil,
        "expires_at_ms" => nil
      }
    }

    run(
      module,
      module.handle("invoke.command", %{"id" => "source", "arguments" => args}, state),
      db
    )
  end

  def query(module, state, as_of) do
    args = %{
      "store" => "notes",
      "retrieval" => "words",
      "rerank" => nil,
      "query" => "release audit",
      "top_k" => 10,
      "as_of_ms" => as_of
    }

    module.handle("invoke.command", %{"id" => "query", "arguments" => args}, state)
  end

  def step_store({:call, req, c}, db) do
    {out, db} = F.host(db, req)
    {Store.resume(c, out), db}
  end

  def run_store({:call, _, _} = value, db) do
    {value, db} = step_store(value, db)
    run_store(value, db)
  end

  def run_store(value, db), do: {value, db}

  test "State and MCP query fence changed and stable namespaces" do
    for kind <- [:state, :mcp], as_of <- [nil, 10] do
      {module, state, db, _} = init(kind)
      {first, state, db} = source(module, state, db, "first")
      assert first["status"] == "ok"
      {_, req, pending, db} = hold(module, query(module, state, as_of), db)
      {out, stable} = F.host(db, req)

      {ok, _, _} =
        run(module, module.handle("host.actions", %{"outcome" => out}, pending), stable)

      assert ok["status"] == "ok" and length(ok["evidence"]) == 1
      {added, _, changed} = source(module, state, db, "second")
      assert added["status"] == "ok"
      {out, changed} = F.host(changed, req)

      {conflict, _, _} =
        run(module, module.handle("host.actions", %{"outcome" => out}, pending), changed)

      assert conflict["status"] == "conflict"
      assert conflict["evidence"] == [] and conflict["claims"] == []
    end
  end

  test "old empty Store APIs remain immediate; fenced State/MCP checks empty query" do
    for kind <- [:state, :mcp] do
      {module, state, db, profile} = init(kind)
      assert {:done, {:ok, old}} = Store.start("notes", profile, :revalidate, %{"tokens" => []})
      assert {:done, {:ok, ^old}} = Store.start_revalidation("notes", profile, %{"tokens" => []})
      refute Map.has_key?(old, "store_generation")
      assert {:call, _, _} = Store.start_fenced_revalidation("notes", profile, %{"tokens" => []})
      {_, req, pending, db} = hold(module, query(module, state, nil), db)
      {out, stable} = F.host(db, req)

      {ok, _, _} =
        run(module, module.handle("host.actions", %{"outcome" => out}, pending), stable)

      assert ok["status"] == "abstain"
      {added, _, changed} = source(module, state, db, "first")
      assert added["status"] == "ok"
      {out, changed} = F.host(changed, req)

      {result, _, _} =
        run(module, module.handle("host.actions", %{"outcome" => out}, pending), changed)

      assert result["status"] == "conflict" and result["evidence"] == []
    end
  end

  test "33 tokens preserve old caller and expose stable generation; later drift refuses" do
    {_, _, db, profile} = init(:state)

    {tokens, db} =
      Enum.map_reduce(1..33, db, fn n, db ->
        key = Evidence.sha256("root-#{n}")

        val = %{
          "partition" => "manual",
          "source_key" => Evidence.sha256("source-#{n}"),
          "generation" => 1,
          "content_sha256" => nil,
          "state" => "staging"
        }

        row = %{
          "key" => key,
          "revision" => 1,
          "deleted" => false,
          "value" => val,
          "operation_id" => String.duplicate("a", 32)
        }

        token = val |> Map.put("key", key) |> Map.put("revision", 1)
        {token, %{db | records: Map.put(db.records, key, row), generation: 33}}
      end)

    {{:done, {:ok, checked}}, _} =
      run_store(Store.start_revalidation("notes", profile, %{"tokens" => tokens}), db)

    assert checked["valid"] and checked["store_generation"] == 33 and
             checked["coverage"]["reads_used"] == 33

    {cont, db} =
      Enum.reduce(
        1..32,
        {Store.start_revalidation("notes", profile, %{"tokens" => tokens}), db},
        fn _, {continuation, acc} -> step_store(continuation, acc) end
      )

    assert {{:done, {:error, :snapshot_changed, _}}, _} = run_store(cont, %{db | generation: 34})
  end

  test "empty probe budget, unknown and denied stop without mutation" do
    for kind <- [:state, :mcp] do
      {module, state, db, profile} = init(kind)
      args = %{"tokens" => [], "reads_used" => 512, "effects_used" => 0}

      assert {:done, {:error, :effect_limit, _}} =
               Store.start_fenced_revalidation("notes", profile, args)

      {_, _, pending, held_db} = hold(module, query(module, state, nil), db)
      records_before = held_db.records
      requests_before = held_db.requests

      for status <- ["unknown", "denied"] do
        assert {:ok, %{"kind" => "result", "value" => result}, finished} =
                 module.handle("host.actions", %{"outcome" => %{"status" => status}}, pending)

        assert result["status"] == "refused" and result["evidence"] == []
        assert result["claims"] == [] and finished.phase == :idle
        assert held_db.records === records_before and held_db.requests === requests_before
      end
    end
  end

  test "remote-selected MCP empty and nonempty refs fence storage generation" do
    for populated <- [false, true] do
      {module, _, db, _} = init(:mcp)

      opts =
        options(:mcp)
        |> put_in(["retrieval", "words"], %{
          "kind" => "mcp_query",
          "binding" => "query_service",
          "partition" => "manual",
          "contract" => "query-v1"
        })

      {:ok, state} = module.init(opts)
      refute Map.has_key?(state, :invalid)

      {state, db} =
        if populated do
          {stored, state, db} = source(module, state, db, "first")
          assert stored["status"] == "ok"
          {state, db}
        else
          {state, db}
        end

      before_requests = length(db.requests)
      {_, req, pending, db} = hold(module, query(module, state, 10), db)
      assert req["op"] == "mcp.call" and req["binding"] == "storage"
      assert get_in(req, ["arguments", "action"]) == "get_many"
      assert length(get_in(req, ["arguments", "args", "keys"])) == 1

      assert Enum.any?(
               db.requests,
               &(&1["op"] == "mcp.call" and &1["binding"] == "query_service")
             )

      {outcome, unchanged} = F.host(db, req)

      {ok, _, observed} =
        run(module, module.handle("host.actions", %{"outcome" => outcome}, pending), unchanged)

      assert ok["status"] == if(populated, do: "ok", else: "abstain")
      assert get_in(ok, ["coverage", "store", "namespace_complete"]) == false
      new_requests = Enum.take(observed.requests, length(observed.requests) - before_requests)

      assert get_in(ok, ["coverage", "final_validation", "effects_used"]) ==
               Enum.count(new_requests, &(&1["op"] == "mcp.call"))

      assert get_in(ok, ["coverage", "final_validation", "reads_used"]) ==
               Enum.count(new_requests, &(&1["op"] == "effect.result.read"))

      {added, _, changed} = source(module, state, db, if(populated, do: "second", else: "first"))
      assert added["status"] == "ok"
      {outcome, changed} = F.host(changed, req)

      {result, _, _} =
        run(module, module.handle("host.actions", %{"outcome" => outcome}, pending), changed)

      assert result["status"] == "conflict" and result["evidence"] == []
    end
  end
end

doc_corpus =
  File.read!("extensions/knowledge/src/corpus.ex")
  |> String.replace(
    "defmodule IpseKnowledge.Corpus do",
    "defmodule IpseKnowledge.CorpusDocuments do",
    global: false
  )
  |> String.replace(~s(@preset "state-lexical"), ~s(@preset "state-documents"), global: false)

Code.compile_string(doc_corpus, "private-corpus-documents.ex")

rerank_corpus =
  File.read!("extensions/knowledge/src/corpus.ex")
  |> String.replace(
    "defmodule IpseKnowledge.Corpus do",
    "defmodule IpseKnowledge.CorpusRerank do",
    global: false
  )
  |> String.replace(~s(@preset "state-lexical"), ~s(@preset "state-rerank"), global: false)

Code.compile_string(rerank_corpus, "private-corpus-rerank.ex")

defmodule CorpusTimeFenceControls do
  use ExUnit.Case, async: false
  alias FenceControls, as: D
  alias Ipse.Development.Fixtures.Knowledge, as: F

  def await_deadline(deadline),
    do: await_deadline(deadline, System.monotonic_time(:millisecond) + 5_000)

  defp await_deadline(deadline, until) do
    if System.system_time(:millisecond) < deadline do
      assert System.monotonic_time(:millisecond) < until
      Process.sleep(10)
      await_deadline(deadline, until)
    end
  end

  # Simulate crossing after verifying the real snapshot's computed boundary.
  # This is a continuation-state control, not a wall-clock observation.
  defp crossed(pending, historical) do
    now = System.system_time(:millisecond)
    selected = now - 120_000

    ctx =
      pending.ctx |> Map.put(:as_of_ms, selected) |> Map.put(:query_time_transition, now - 60_000)

    ctx = if historical, do: put_in(ctx.args["as_of_ms"], selected), else: ctx
    %{pending | ctx: ctx}
  end

  defp add_timed(module, state, db, observed, expiry) do
    args = %{
      "store" => "notes",
      "action" => "put",
      "args" => %{
        "source_id" => "timed",
        "generation" => 1,
        "expected_revision" => 0,
        "title" => "timed",
        "text" => "Release requires audit.",
        "uri" => "provided:timed",
        "observed_at_ms" => observed,
        "event_at_ms" => nil,
        "expires_at_ms" => expiry
      }
    }

    {result, state, db} =
      D.run(
        module,
        module.handle("invoke.command", %{"id" => "source", "arguments" => args}, state),
        db
      )

    assert result["status"] == "ok"
    {state, db}
  end

  test "full snapshot expiry and future observation distinguish current and historical queries" do
    for transition <- [:expiry, :activation], historical <- [false, true] do
      {module, state, db, _} = D.init(:state)
      now = System.system_time(:millisecond)
      deadline = now + 60_000
      {observed, expiry} = if transition == :expiry, do: {1, deadline}, else: {deadline, nil}
      {state, db} = add_timed(module, state, db, observed, expiry)

      {_, req, pending, db} =
        D.hold(module, D.query(module, state, if(historical, do: now, else: nil)), db)

      assert pending.ctx.query_time_transition == deadline
      pending = crossed(pending, historical)
      before = db.records
      {outcome, db} = F.host(db, req)

      {result, _, db} =
        D.run(module, module.handle("host.actions", %{"outcome" => outcome}, pending), db)

      assert db.records == before

      if historical do
        assert result["status"] == if(transition == :expiry, do: "ok", else: "abstain")
      else
        assert result["status"] == "refused" and
                 result["gaps"] == [%{"code" => "query_time_changed"}]

        assert result["evidence"] == [] and result["claims"] == []
      end
    end
  end

  test "clock rollback at final fence is refused for a current query" do
    {module, state, db, _} = D.init(:state)
    {_, req, pending, db} = D.hold(module, D.query(module, state, nil), db)
    pending = put_in(pending.ctx.as_of_ms, System.system_time(:millisecond) + 60_000)
    {outcome, db} = F.host(db, req)

    {result, _, _} =
      D.run(module, module.handle("host.actions", %{"outcome" => outcome}, pending), db)

    assert result["status"] == "refused" and result["gaps"] == [%{"code" => "query_time_changed"}]
  end

  test "missing or malformed full snapshot temporal context refuses" do
    {module, state, db, _} = D.init(:state)
    {_, req, pending, db} = D.hold(module, D.query(module, state, nil), db)

    for ctx <- [
          Map.delete(pending.ctx, :query_time_scope),
          Map.delete(pending.ctx, :query_time_transition),
          Map.put(pending.ctx, :query_time_transition, "bad")
        ] do
      {outcome, next_db} = F.host(db, req)

      {result, _, _} =
        D.run(
          module,
          module.handle("host.actions", %{"outcome" => outcome}, %{pending | ctx: ctx}),
          next_db
        )

      assert result["status"] == "refused" and
               result["gaps"] == [%{"code" => "query_time_changed"}]
    end
  end

  test "captured fact activation and expiry distinguish current from historical full snapshots" do
    for transition <- [:valid_from_ms, :valid_to_ms], historical <- [false, true] do
      {module, corpus, db, _} = D.init(:state)
      opts = JSON.decode!(File.read!("extensions/knowledge/options/graph-explicit.json"))
      {:ok, graph} = IpseKnowledge.Graph.init(opts)
      {stored, graph, db} = D.source(IpseKnowledge.Graph, graph, db, "timed-fact")
      assert stored["status"] == "ok"
      now = System.system_time(:millisecond)
      deadline = now + 60_000

      relation = %{
        "subject" => "Release",
        "predicate" => "requires",
        "object" => "audit",
        "polarity" => "positive",
        "inferred" => false,
        "valid_from_ms" => if(transition == :valid_from_ms, do: deadline, else: nil),
        "valid_to_ms" => if(transition == :valid_to_ms, do: deadline, else: nil),
        "quote" => "Release requires audit."
      }

      args = %{
        "store" => "notes",
        "extraction" => "asserted",
        "source_id" => "timed-fact",
        "generation" => 1,
        "relations" => [relation]
      }

      {captured, _, db} =
        D.run(
          IpseKnowledge.Graph,
          IpseKnowledge.Graph.handle(
            "invoke.tool",
            %{"id" => "capture", "arguments" => args},
            graph
          ),
          db
        )

      assert captured["status"] == "ok"

      {_, req, pending, db} =
        D.hold(module, D.query(module, corpus, if(historical, do: now, else: nil)), db)

      [fact] = pending.ctx.snapshot["projections"] |> Map.values() |> Enum.flat_map(& &1["facts"])
      assert fact[Atom.to_string(transition)] == deadline
      assert pending.ctx.query_time_transition == deadline
      pending = crossed(pending, historical)
      before = db.records
      {outcome, db} = F.host(db, req)

      {result, _, db} =
        D.run(module, module.handle("host.actions", %{"outcome" => outcome}, pending), db)

      assert db.records == before

      if historical do
        assert result["status"] == "ok"
      else
        assert result["status"] == "refused" and
                 result["gaps"] == [%{"code" => "query_time_changed"}]

        assert result["evidence"] == [] and result["claims"] == []
      end
    end
  end
end

defmodule CorpusRerankTimeControls do
  use ExUnit.Case, async: false
  alias IpseKnowledge.CorpusRerank, as: Corpus
  alias Ipse.Development.Fixtures.Knowledge, as: F
  alias FenceControls, as: D

  defp hold_snapshot(
         {:ok, %{"kind" => "host_call", "request" => req}, %{phase: :query_snapshot} = state},
         db
       ),
       do: {req, state, db}

  defp hold_snapshot({:ok, %{"kind" => "host_call", "request" => req}, state}, db) do
    {outcome, db} = F.host(db, req)
    hold_snapshot(Corpus.handle("host.actions", %{"outcome" => outcome}, state), db)
  end

  defp decision(
         {:ok, %{"kind" => "host_call", "request" => %{"op" => "model.complete"} = req}, _},
         db
       ),
       do: {:model, req, db}

  defp decision({:ok, %{"kind" => "host_call", "request" => req}, state}, db) do
    {outcome, db} = F.host(db, req)
    decision(Corpus.handle("host.actions", %{"outcome" => outcome}, state), db)
  end

  defp decision({:ok, %{"kind" => "result", "value" => value}, _}, db), do: {:result, value, db}

  test "source expiry before reranking refuses before model dispatch while stable and historical proceed" do
    for mode <- [:current_expired, :historical, :current_stable] do
      options =
        D.options(:state)
        |> put_in(["rerank", "model"], %{
          "kind" => "model_complete",
          "profile" => "fixture",
          "max_candidates" => 16,
          "quote_bytes" => 128
        })

      {:ok, state} = Corpus.init(options)
      refute Map.has_key?(state, :invalid)
      now = System.system_time(:millisecond)
      deadline = now + 2000

      args = %{
        "store" => "notes",
        "action" => "put",
        "args" => %{
          "source_id" => "egress",
          "generation" => 1,
          "expected_revision" => 0,
          "title" => "egress",
          "text" => "Release requires audit.",
          "uri" => "provided:egress",
          "observed_at_ms" => 1,
          "event_at_ms" => nil,
          "expires_at_ms" => deadline
        }
      }

      {stored, state, db} =
        D.run(
          Corpus,
          Corpus.handle("invoke.command", %{"id" => "source", "arguments" => args}, state),
          F.new("manual")
        )

      assert stored["status"] == "ok"

      query = %{
        "store" => "notes",
        "retrieval" => "words",
        "rerank" => "model",
        "query" => "release audit",
        "top_k" => 10,
        "as_of_ms" => if(mode == :historical, do: now, else: nil)
      }

      {req, pending, db} =
        hold_snapshot(
          Corpus.handle("invoke.command", %{"id" => "query", "arguments" => query}, state),
          db
        )

      if mode != :current_stable, do: CorpusTimeFenceControls.await_deadline(deadline)
      {outcome, db} = F.host(db, req)
      result = decision(Corpus.handle("host.actions", %{"outcome" => outcome}, pending), db)

      if mode == :current_expired do
        assert {:result, %{"status" => "refused", "gaps" => [%{"code" => "query_time_changed"}]},
                _} = result
      else
        assert {:model, %{"op" => "model.complete"}, _} = result
      end
    end
  end
end

defmodule CorpusDocumentFenceControls do
  use ExUnit.Case, async: false
  alias IpseKnowledge.{CorpusDocuments, Evidence, Store}
  alias Ipse.Development.Fixtures.Knowledge, as: F
  alias FenceControls, as: D

  defp seed_document(expires \\ nil) do
    opts = D.options(:state)
    {:ok, state} = CorpusDocuments.init(opts)
    refute Map.has_key?(state, :invalid)
    text = "Release requires audit."
    original = "synthetic original"

    receipt = %{
      "kind" => "document_extraction",
      "version" => 2,
      "format" => "docx",
      "original_sha256" => Evidence.sha256(original),
      "original_bytes" => byte_size(original),
      "extraction_version" => "ipse-documents-v14",
      "status" => "complete",
      "warnings" => [],
      "segments" => [
        %{
          "start_byte" => 0,
          "end_byte" => byte_size(text),
          "text_sha256" => Evidence.sha256(text),
          "locator" => %{"kind" => "paragraph", "part" => "word/document.xml", "paragraph" => 1}
        }
      ],
      "acquisition" => %{
        "kind" => "workspace.read",
        "path" => "source.docx",
        "operation_id" => String.duplicate("2", 32)
      }
    }

    assert Evidence.valid_document?(receipt, text)

    args = %{
      "source_id" => "document-one",
      "generation" => 1,
      "expected_revision" => 0,
      "title" => "document",
      "text" => text,
      "uri" => "workspace:source.docx",
      "observed_at_ms" => 1,
      "event_at_ms" => nil,
      "expires_at_ms" => expires,
      "document" => receipt
    }

    {{:done, {:ok, stored}}, db} =
      D.run_store(Store.start("notes", opts["stores"]["notes"], :put, args), F.new("manual"))

    assert stored["status"] == "stored"
    {state, db, original}
  end

  defp until_document(
         {:ok, %{"kind" => "host_call", "request" => req}, %{phase: :document_use_check} = state},
         db
       ),
       do: {req, state, db}

  defp until_document({:ok, %{"kind" => "host_call", "request" => req}, state}, db) do
    {outcome, db} = F.host(db, req)
    until_document(CorpusDocuments.handle("host.actions", %{"outcome" => outcome}, state), db)
  end

  defp verified_page(original) do
    first = binary_part(original, 0, 1)

    page = %{
      "version" => 2,
      "encoding" => "base64",
      "path" => "source.docx",
      "byte_count" => byte_size(original),
      "sha256" => Evidence.sha256(original),
      "data" => Base.encode64(first),
      "offset" => 0,
      "page_sha256" => Evidence.sha256(first),
      "next" => 1
    }

    %{
      "operation_id" => String.duplicate("3", 32),
      "outcome" => %{
        "status" => "ok",
        "value" => %{"text" => IO.iodata_to_binary(JSON.encode!(page))}
      }
    }
  end

  test "document current-use performs a second generation fence after workspace check" do
    {state, db, original} = seed_document()
    {request, pending, db} = until_document(D.query(CorpusDocuments, state, 10), db)
    assert request["op"] == "tool.call" and pending.phase == :document_use_check
    assert pending.document_budget.guarded

    assert {:ok, %{"kind" => "host_call", "request" => read}, fence} =
             CorpusDocuments.handle("host.actions", verified_page(original), pending)

    assert fence.phase == :document_use_store and read["op"] == "state.get"
    {outcome, unchanged} = F.host(db, read)

    {ok, _, _} =
      D.run(
        CorpusDocuments,
        CorpusDocuments.handle("host.actions", %{"outcome" => outcome}, fence),
        unchanged
      )

    assert ok["status"] == "ok" and length(ok["evidence"]) == 1
    assert ok["coverage"]["workspace_invocation_reads"] == fence.document_budget.reads
    assert ok["coverage"]["workspace_invocation_effects"] == fence.document_budget.effects
    {added, _, changed} = D.source(CorpusDocuments, state, db, "concurrent")
    assert added["status"] == "ok"
    before = changed.records
    {outcome, changed} = F.host(changed, read)

    {result, _, final} =
      D.run(
        CorpusDocuments,
        CorpusDocuments.handle("host.actions", %{"outcome" => outcome}, fence),
        changed
      )

    assert result["status"] == "conflict" and result["evidence"] == [] and result["claims"] == []
    assert final.records == before
  end

  test "document second fence refuses before another read when cumulative budget is exhausted" do
    {state, db, original} = seed_document()
    {_, pending, db} = until_document(D.query(CorpusDocuments, state, 10), db)
    pending = put_in(pending.document_budget.reads, 512)
    before = db.records

    assert {:ok, %{"kind" => "result", "value" => result}, finished} =
             CorpusDocuments.handle("host.actions", verified_page(original), pending)

    assert result["status"] == "refused" and result["evidence"] == [] and result["claims"] == []
    assert finished.phase == :idle and db.records == before
  end

  test "document expiry during workspace check refuses at the second fence" do
    deadline = System.system_time(:millisecond) + 2000
    {state, db, original} = seed_document(deadline)
    {_, pending, db} = until_document(D.query(CorpusDocuments, state, nil), db)
    assert pending.ctx.query_time_transition == deadline

    assert {:ok, %{"kind" => "host_call", "request" => read}, fence} =
             CorpusDocuments.handle("host.actions", verified_page(original), pending)

    CorpusTimeFenceControls.await_deadline(deadline)
    {outcome, db} = F.host(db, read)

    {result, _, _} =
      D.run(
        CorpusDocuments,
        CorpusDocuments.handle("host.actions", %{"outcome" => outcome}, fence),
        db
      )

    assert result["status"] == "refused" and result["gaps"] == [%{"code" => "query_time_changed"}]
    assert result["evidence"] == [] and result["claims"] == []
  end
end

defmodule Corpus64TokenFenceControls do
  use ExUnit.Case, async: false
  alias IpseKnowledge.{Evidence, Store}
  alias FenceControls, as: D

  test "64 synthetic source and selector tokens keep shared helper compatibility and fence drift" do
    {_, _, db, profile} = D.init(:state)

    {tokens, db} =
      Enum.map_reduce(1..64, db, fn n, db ->
        kind = if n <= 32, do: "root", else: "fetch_origin"
        key = Evidence.sha256("#{kind}-#{n}")

        val = %{
          "kind" => kind,
          "partition" => "manual",
          "source_key" => Evidence.sha256("source-#{n}"),
          "generation" => 1,
          "content_sha256" => nil,
          "state" => "staging"
        }

        row = %{
          "key" => key,
          "revision" => 1,
          "deleted" => false,
          "value" => val,
          "operation_id" => String.duplicate("a", 32)
        }

        token =
          Map.take(val, ~w(partition source_key generation content_sha256 state))
          |> Map.put("key", key)
          |> Map.put("revision", 1)

        {token, %{db | records: Map.put(db.records, key, row), generation: 64}}
      end)

    assert length(Enum.uniq_by(tokens, & &1["key"])) == 64

    {{:done, {:ok, checked}}, _} =
      D.run_store(Store.start_revalidation("notes", profile, %{"tokens" => tokens}), db)

    assert checked["valid"] and checked["store_generation"] == 64 and
             checked["coverage"]["reads_used"] == 64

    {cont, db} =
      Enum.reduce(
        1..32,
        {Store.start_revalidation("notes", profile, %{"tokens" => tokens}), db},
        fn _, {c, db} -> D.step_store(c, db) end
      )

    assert {{:done, {:error, :snapshot_changed, _}}, _} =
             D.run_store(cont, %{db | generation: 65})
  end
end

remote_rerank_corpus =
  File.read!("extensions/knowledge/src/corpus.ex")
  |> String.replace(
    "defmodule IpseKnowledge.Corpus do",
    "defmodule IpseKnowledge.CorpusMCPRerank do",
    global: false
  )
  |> String.replace(~s(@preset "state-lexical"), ~s(@preset "mcp-rerank"), global: false)

Code.compile_string(remote_rerank_corpus, "private-corpus-mcp-rerank.ex")

defmodule CorpusRemoteTimeControls do
  use ExUnit.Case, async: false
  alias FenceControls, as: D
  alias Ipse.Development.Fixtures.Knowledge, as: F

  defp init(rerank \\ false) do
    module = if rerank, do: IpseKnowledge.CorpusMCPRerank, else: IpseKnowledge.CorpusMCP

    opts =
      D.options(:mcp)
      |> put_in(["retrieval", "words"], %{
        "kind" => "mcp_query",
        "binding" => "query_service",
        "partition" => "manual",
        "contract" => "query-v1"
      })

    opts =
      if rerank,
        do:
          put_in(opts, ["rerank", "model"], %{
            "kind" => "model_complete",
            "profile" => "fixture",
            "max_candidates" => 16,
            "quote_bytes" => 128
          }),
        else: opts

    {:ok, state} = module.init(opts)
    refute Map.has_key?(state, :invalid)
    {module, state, F.new("manual")}
  end

  defp seed(module, state, db, expires) do
    args = %{
      "store" => "notes",
      "action" => "put",
      "args" => %{
        "source_id" => "remote-timed",
        "generation" => 1,
        "expected_revision" => 0,
        "title" => "remote-timed",
        "text" => "Release requires audit.",
        "uri" => "provided:remote-timed",
        "observed_at_ms" => 1,
        "event_at_ms" => nil,
        "expires_at_ms" => expires
      }
    }

    {stored, state, db} =
      D.run(
        module,
        module.handle("invoke.command", %{"id" => "source", "arguments" => args}, state),
        db
      )

    assert stored["status"] == "ok"
    {state, db}
  end

  test "selected expiry guards current final fence, while historical and empty selected remain usable" do
    for mode <- [:current_expired, :historical, :empty, :current_stable] do
      {module, state, db} = init()
      now = System.system_time(:millisecond)
      deadline = now + 60_000
      {state, db} = if mode == :empty, do: {state, db}, else: seed(module, state, db, deadline)

      {_, req, pending, db} =
        D.hold(module, D.query(module, state, if(mode == :historical, do: now, else: nil)), db)

      assert pending.ctx.query_time_scope == :remote_selected
      assert pending.ctx.query_time_transition == if(mode == :empty, do: nil, else: deadline)

      pending =
        if mode in [:current_expired, :historical] do
          selected = now - 120_000

          ctx =
            pending.ctx
            |> Map.put(:as_of_ms, selected)
            |> Map.put(:query_time_transition, now - 60_000)

          ctx = if mode == :historical, do: put_in(ctx.args["as_of_ms"], selected), else: ctx
          %{pending | ctx: ctx}
        else
          pending
        end

      records = db.records
      {outcome, db} = F.host(db, req)

      {result, _, db} =
        D.run(module, module.handle("host.actions", %{"outcome" => outcome}, pending), db)

      assert records == db.records

      if mode == :current_expired do
        assert result["status"] == "refused" and
                 result["gaps"] == [%{"code" => "query_time_changed"}]

        assert result["evidence"] == [] and result["claims"] == []
      else
        assert result["status"] == if(mode == :empty, do: "abstain", else: "ok")
        assert get_in(result, ["coverage", "store", "namespace_complete"]) == false

        if mode == :empty do
          assert result["evidence"] == []

          assert result["claims"] == [
                   %{
                     "label" => "open",
                     "evidence_indexes" => [],
                     "uncertainty" => "semantic_support_unassessed"
                   }
                 ]
        end
      end
    end
  end

  defp hold_selected(
         _module,
         {:ok, %{"kind" => "host_call", "request" => req},
          %{phase: :query_selected_snapshot} = state},
         db
       ),
       do: {req, state, db}

  defp hold_selected(module, {:ok, %{"kind" => "host_call", "request" => req}, state}, db) do
    {outcome, db} = F.host(db, req)
    hold_selected(module, module.handle("host.actions", %{"outcome" => outcome}, state), db)
  end

  defp until_decision(
         _module,
         {:ok, %{"kind" => "host_call", "request" => %{"op" => "model.complete"} = req}, _},
         db
       ),
       do: {:model, req, db}

  defp until_decision(module, {:ok, %{"kind" => "host_call", "request" => req}, state}, db) do
    {outcome, db} = F.host(db, req)
    until_decision(module, module.handle("host.actions", %{"outcome" => outcome}, state), db)
  end

  defp until_decision(_, {:ok, %{"kind" => "result", "value" => value}, _}, db),
    do: {:result, value, db}

  test "selected source expiry before rerank prevents proposing model call" do
    for mode <- [:current_expired, :historical, :current_stable] do
      {module, state, db} = init(true)
      now = System.system_time(:millisecond)
      deadline = now + 2_000
      {state, db} = seed(module, state, db, deadline)

      args = %{
        "store" => "notes",
        "retrieval" => "words",
        "rerank" => "model",
        "query" => "release audit",
        "top_k" => 10,
        "as_of_ms" => if(mode == :historical, do: now, else: nil)
      }

      {req, pending, db} =
        hold_selected(
          module,
          module.handle("invoke.command", %{"id" => "query", "arguments" => args}, state),
          db
        )

      if mode != :current_stable, do: CorpusTimeFenceControls.await_deadline(deadline)
      {outcome, db} = F.host(db, req)

      decision =
        until_decision(
          module,
          module.handle("host.actions", %{"outcome" => outcome}, pending),
          db
        )

      if mode == :current_expired do
        assert {:result,
                %{
                  "status" => "refused",
                  "gaps" => [%{"code" => "query_time_changed"}],
                  "evidence" => [],
                  "claims" => []
                }, _} = decision
      else
        assert {:model, %{"op" => "model.complete"}, _} = decision
      end
    end
  end
end

result = ExUnit.run()

passed =
  result.total == 16 and result.failures == 0 and result.skipped == 0 and result.excluded == 0

if passed, do: IO.puts("corpus_time_controls=pass")
System.halt(if(passed, do: 0, else: 1))
