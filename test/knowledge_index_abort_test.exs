defmodule Ipse.KnowledgeIndexAbortTest do
  use ExUnit.Case, async: false

  @root Path.expand("..", __DIR__)

  test "Corpus reports committed abort generation and stale requests cannot mutate a draft" do
    bootstrap = ~S'''
    import ExUnit.Assertions
    alias IpseKnowledge.{Corpus, Evidence, Store}
    alias IpseKnowledge.Test.CASFixture, as: Fixture

    defmodule AbortDriver do
      def store({:call, request, continuation}, db) do
        {outcome, db} = IpseKnowledge.Test.CASFixture.host(db, request)
        store(IpseKnowledge.Store.resume(continuation, outcome), db)
      end

      def store(result, db), do: {result, db}

      def corpus({:ok, %{"kind" => "host_call", "request" => request}, state}, db) do
        {outcome, db} = IpseKnowledge.Test.CASFixture.host(db, request)
        reply = IpseKnowledge.Corpus.handle("host.actions", %{"outcome" => outcome}, state)
        corpus(reply, db)
      end

      def corpus({:ok, %{"kind" => "result", "value" => value}, _}, db), do: {value, db}

      def mutations(db) do
        Enum.count(IpseKnowledge.Test.CASFixture.requests(db), fn request ->
          request["op"] in ~w(state.put state.delete) or
            (request["op"] == "mcp.call" and
               get_in(request, ["arguments", "action"]) in
                 ~w(cas_root put_immutable_many collect))
        end)
      end
    end

    state_profile = %{"kind" => "state", "scope" => "project", "partition" => "notes"}
    remote_profile = %{"kind" => "mcp_cas", "binding" => "storage", "partition" => "notes",
      "contract" => "ipse-cas-v3"}
    embedding = %{"kind" => "embedding", "profile" => "encoder"}
    source = %{"source_id" => "manual:one", "generation" => 7, "expected_revision" => 0,
      "title" => "A manual", "text" => "Release requires quiescence.", "uri" => "local:manual",
      "observed_at_ms" => 10, "event_at_ms" => nil, "expires_at_ms" => nil}

    for profile <- [state_profile, remote_profile] do
      invoke = fn db, operation, args ->
        AbortDriver.store(Store.start("notes", profile, operation, args), db)
      end
      {{:done, {:ok, _}}, db} = invoke.(Fixture.new(), :put, source)
      {{:done, {:ok, snapshot}}, db} = invoke.(db, :snapshot, %{})
      {:ok, [chunk]} = Evidence.chunks(hd(snapshot["sources"]))
      open = %{"source_id" => source["source_id"], "generation" => 7,
        "projection_kind" => "vectors", "profile" => embedding, "chunks" => [chunk["chunk_id"]]}
      {{:done, {:ok, opened}}, db} = invoke.(db, :projection_open, open)

      options = Map.new(~w(stores search fetch retrieval embedding rerank extraction), &{&1, %{}})
        |> Map.put("version", 1)
        |> Map.put("stores", %{"notes" => profile})
        |> Map.put("retrieval", %{"words" => %{"kind" => "bm25", "version" => 1}})
        |> Map.put("embedding", %{"vectors" => embedding,
          "other" => %{"kind" => "embedding", "profile" => "other_encoder"}})
      preset = if profile["kind"] == "state", do: "state-dense", else: "mcp-dense"
      {:ok, resolved} = IpseKnowledge.Profiles.validate("corpus", preset, options)
      initial = %{resolved: resolved, phase: :idle, ctx: nil, cont: nil, pending: nil}
      args = %{"store" => "notes", "embedding" => "vectors", "source_id" => source["source_id"],
        "generation" => 7, "action" => "abort", "chunks" => [chunk["chunk_id"]]}
      abort = fn db, arguments ->
        Corpus.handle("invoke.command", %{"id" => "index", "arguments" => arguments}, initial)
        |> AbortDriver.corpus(db)
      end

      for stale <- [Map.put(args, "generation", 6), Map.put(args, "embedding", "other"),
                    Map.put(args, "chunks", [Evidence.sha256("another chunk")])] do
        {refused, unchanged} = abort.(db, stale)
        assert refused["status"] == "refused"
        assert refused["gaps"] == [%{"code" => "stale_draft"}]
        assert unchanged.records == db.records
        assert unchanged.generation == db.generation
        assert AbortDriver.mutations(unchanged) == AbortDriver.mutations(db)
      end

      {result, after_abort} = abort.(db, args)
      assert result["status"] == "ok"
      assert result["gaps"] == []
      assert result["coverage"] == %{"status" => "aborted", "generation" => 7,
        "revision" => opened["draft"]["revision"] + 1}
      assert AbortDriver.mutations(after_abort) == AbortDriver.mutations(db) + 1
      {{:done, {:ok, inspected}}, after_abort} =
        invoke.(after_abort, :inspect, %{"source_id" => source["source_id"]})
      assert inspected["draft"] == nil
      assert inspected["generation"] == 7
      assert inspected["revision"] == result["coverage"]["revision"]

      {refused, unchanged} = abort.(after_abort, args)
      assert refused["status"] == "refused"
      assert refused["gaps"] == [%{"code" => "stale_draft"}]
      assert unchanged.records == after_abort.records
      assert unchanged.generation == after_abort.generation
      assert AbortDriver.mutations(unchanged) == AbortDriver.mutations(after_abort)

      {{:done, {:ok, next}}, next_db} = invoke.(after_abort, :projection_open, open)
      {{:done, {:error, :stale_draft, %{}}}, unchanged} =
        invoke.(next_db, :projection_abort, %{"draft" => opened["draft"]})
      assert unchanged.records == next_db.records
      assert unchanged.generation == next_db.generation
      assert AbortDriver.mutations(unchanged) == AbortDriver.mutations(next_db)
      {{:done, {:ok, aborted}}, next_db} =
        invoke.(next_db, :projection_abort, %{"draft" => next["draft"]})
      assert aborted["generation"] == 7

      replacement = source |> Map.delete("text") |> Map.merge(%{"generation" => 8,
        "expected_revision" => aborted["revision"], "byte_count" => 20,
        "content_sha256" => Evidence.sha256("a future replacement")})
      {{:done, {:ok, draft}}, next_db} = invoke.(next_db, :open, replacement)
      assert draft["generation"] == 8
      {{:done, {:ok, aborted}}, _} = invoke.(next_db, :abort,
        %{"source_id" => source["source_id"], "draft_id" => draft["draft_id"],
          "expected_revision" => draft["revision"]})
      assert aborted["generation"] == 7
    end
    '''

    paths =
      ~w(evidence.ex profiles.ex adapters.ex store/state.ex store/mcp_cas.ex store.ex corpus.ex)

    args =
      Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)]) ++
        Enum.flat_map(paths, &["-r", Path.join(@root, "extensions/knowledge/src/" <> &1)]) ++
        ["-r", Path.join(@root, "test/support/knowledge_mcp_fixture.exs"), "-e", bootstrap]

    {output, status} =
      System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)

    assert status == 0, output

    for module <- [
          IpseKnowledge.Corpus,
          IpseKnowledge.Store,
          IpseKnowledge.Store.State,
          IpseKnowledge.Store.MCPCAS,
          IpseKnowledge.Evidence,
          IpseKnowledge.Profiles,
          IpseKnowledge.Adapters
        ] do
      refute Code.ensure_loaded?(module)
    end
  end
end
