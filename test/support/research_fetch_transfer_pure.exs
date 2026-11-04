ExUnit.start(autorun: false, max_cases: 1)
Code.require_file("dev/fixtures/knowledge.exs", Path.expand("../..", __DIR__))
Code.require_file("extensions/knowledge/src/corpus.ex", Path.expand("../..", __DIR__))

defmodule ResearchFetchTransferTest do
  use ExUnit.Case, async: false
  alias IpseKnowledge.{Research, Corpus, Store, Evidence}
  alias Ipse.Development.Fixtures.Knowledge, as: F
  @root Path.expand("../..", __DIR__)
  @body "Résumé 雪: Ada owns release after audit."
  @quote "Ada owns release after audit."
  @uri "fixture:release"

  defp opts,
    do:
      JSON.decode!(
        File.read!(Path.join(@root, "extensions/knowledge/options/research-state-fetched.json"))
      )

  defp args,
    do: %{
      "store" => "notes",
      "fetch" => "web",
      "uri" => @uri,
      "title" => "Release",
      "quote" => @quote,
      "timeout_ms" => 3000
    }

  defp db(text \\ @body) do
    page = %{
      "text" => text,
      "observed_uri" => "fixture:observed-release",
      "media_type" => "text/plain",
      "observed_at_ms" => 10
    }

    {:ok, db} =
      F.configure_web(F.new("research-notes"), %{
        "searches" => %{},
        "pages" => %{@uri => page, "fixture:alias" => page}
      })

    db
  end

  defp start(module) do
    options = if module == Corpus, do: opts() |> Map.put("fetch", %{}), else: opts()
    {:ok, state} = module.init(options)
    refute Map.has_key?(state, :invalid)
    state
  end

  defp value(%Ipse.Extension.ResultPublication.Output{bytes: bytes}), do: JSON.decode!(bytes)
  defp value(%{"kind" => "result", "value" => value}), do: value

  defp run(module, {:ok, %{"kind" => "host_call", "request" => request}, state}, db, stop) do
    case {request["op"], stop} do
      {"state.put", :denied} ->
        run(
          module,
          module.handle(
            "host.actions",
            %{"outcome" => %{"status" => "denied", "value" => %{}}},
            state
          ),
          db,
          :none
        )

      {"state.put", :unknown_after} ->
        {_outcome, db} = F.host(db, request)

        run(
          module,
          module.handle(
            "host.actions",
            %{"outcome" => %{"status" => "unknown", "value" => %{}}},
            state
          ),
          db,
          :none
        )

      _ ->
        {outcome, db} = F.host(db, request)
        run(module, module.handle("host.actions", %{"outcome" => outcome}, state), db, stop)
    end
  end

  defp run(_, {:ok, result, _}, db, _), do: {value(result), db}
  defp run(_, {:stop, :unknown_effect}, db, _), do: {:unknown, db}

  defp call(module, id, args, db, stop \\ :none),
    do:
      run(
        module,
        module.handle("invoke.command", %{"id" => id, "arguments" => args}, start(module)),
        db,
        stop
      )

  defp store_run({:call, request, cont}, db) do
    {outcome, db} = F.host(db, request)
    store_run(Store.resume(cont, outcome), db)
  end

  defp store_run(result, db), do: {result, db}

  test "actual fetch protocol precedes the attributed canonical Store write and Corpus query" do
    {result, db} = call(Research, "fetch_retain", args(), db())
    assert result["status"] == "ok"
    assert result["coverage"]["native_receipt"] == false
    assert result["coverage"]["source_id"] == Store.provided_transfer_id(@body)
    requests = F.requests(db)
    assert hd(requests)["op"] == "mcp.call"

    assert Enum.find_index(requests, &(&1["op"] == "effect.result.read")) <
             Enum.find_index(requests, &(&1["op"] == "state.put"))

    {query, _} =
      call(
        Corpus,
        "query",
        %{
          "store" => "notes",
          "retrieval" => "words",
          "rerank" => nil,
          "query" => "release",
          "top_k" => 3,
          "as_of_ms" => 20
        },
        db
      )

    assert [evidence] = query["evidence"]
    citation = evidence["citation"]
    assert citation["quote"] == @body
    assert citation["content_sha256"] == Evidence.sha256(@body)
    assert citation["origin"]["kind"] == "fetch"
    receipt = citation["origin"]["receipt"]
    assert receipt == result["coverage"]["derivation"]
    assert receipt["body_sha256"] == Evidence.sha256(@body)

    assert receipt["requested_uri"] == @uri and
             receipt["observed_uri"] == "fixture:observed-release"

    assert receipt["quote"] == @quote and receipt["start_byte"] == byte_size("Résumé 雪: ")
    assert receipt["end_byte"] == byte_size(@body)
    assert receipt["descriptor"]["kind"] == "mcp.text"
  end

  test "forget blocks same-body URI and quote aliases in fresh Research states" do
    {retained, db} = call(Research, "fetch_retain", args(), db())
    id = retained["coverage"]["source_id"]

    {inspected, db} =
      call(
        Corpus,
        "source",
        %{"store" => "notes", "action" => "inspect", "args" => %{"source_id" => id}},
        db
      )

    {forgotten, db} =
      call(
        Corpus,
        "source",
        %{
          "store" => "notes",
          "action" => "forget",
          "args" => %{"source_id" => id, "expected_revision" => inspected["coverage"]["revision"]}
        },
        db
      )

    assert forgotten["status"] == "ok"
    records = F.records(db)

    for uri <- [@uri, "fixture:alias"], quote <- [@quote, "Résumé 雪"] do
      {refused, after_db} =
        call(
          Research,
          "fetch_retain",
          args() |> Map.put("uri", uri) |> Map.put("quote", quote),
          db
        )

      assert refused["status"] == "refused"
      assert F.records(after_db) == records
    end
  end

  test "malformed and denied fetches never reach State mutation" do
    for mode <- [
          :fetch_partial,
          :fetch_changed_body,
          :fetch_forged_hash,
          :fetch_forged_receipt,
          :fetch_wrong_uri,
          :denied
        ] do
      {refused, db} = call(Research, "fetch_retain", args(), F.barrier(db(), "fetch", mode))
      assert refused["status"] == "refused"
      refute Enum.any?(F.requests(db), &(&1["op"] == "state.put"))
      assert F.records(db) == %{}
    end

    {refused, db} =
      call(Research, "fetch_retain", Map.put(args(), "uri", "fixture:missing"), db())

    assert refused["status"] == "refused" and F.records(db) == %{}
  end

  test "quote and body constraints refuse before any write" do
    for {text, quote} <- [
          {@body, "missing"},
          {"aaa", "aa"},
          {"x" <> String.duplicate("z", 4096), "x"}
        ] do
      {refused, db} = call(Research, "fetch_retain", Map.put(args(), "quote", quote), db(text))
      assert refused["status"] == "refused" and F.records(db) == %{}
      refute Enum.any?(F.requests(db), &(&1["op"] == "state.put"))
    end
  end

  test "caller cannot supply bytes, fetch receipt, destination identity or historical authority" do
    for extra <- [
          %{"text" => @body},
          %{"source" => %{}},
          %{"receipt" => %{}},
          %{"source_id" => "fake"},
          %{"generation" => 2},
          %{"expected_revision" => 9},
          %{"origin" => %{"kind" => "fetch"}},
          %{"historical_import" => %{}}
        ] do
      {refused, db} = call(Research, "fetch_retain", Map.merge(args(), extra), db())
      assert refused["status"] == "refused" and F.requests(db) == []

      assert {:done, {:error, :invalid_fetch_transfer, _}} =
               Store.start_fetch_transfer(
                 "notes",
                 opts()["stores"]["notes"],
                 opts()["fetch"]["web"],
                 Map.merge(Map.take(args(), ~w(uri title quote timeout_ms)), extra)
               )
    end
  end

  test "State denial changes no records and interrupted writes stop unknown" do
    {refused, denied} = call(Research, "fetch_retain", args(), db(), :denied)
    assert refused["status"] == "refused" and F.records(denied) == %{}
    assert {:unknown, after_db} = call(Research, "fetch_retain", args(), db(), :unknown_after)
    assert map_size(F.records(after_db)) == 1
  end

  test "same body cannot silently rewrite fetch attribution" do
    {retained, db} = call(Research, "fetch_retain", args(), db())
    {refused, same} = call(Research, "fetch_retain", Map.put(args(), "uri", "fixture:alias"), db)
    assert retained["status"] == "ok" and refused["status"] == "refused"
    assert F.records(same) == F.records(db)
  end

  test "a provided-body tombstone also blocks re-fetching those bytes" do
    put = %{
      "source_id" => Store.provided_transfer_id(@body),
      "generation" => 1,
      "expected_revision" => 0,
      "title" => "Provided",
      "text" => @body,
      "uri" => "provided:release",
      "observed_at_ms" => 10,
      "event_at_ms" => nil,
      "expires_at_ms" => nil
    }

    assert {{:done, {:ok, stored}}, db} =
             store_run(Store.start("notes", opts()["stores"]["notes"], :put, put), db())

    id = stored["source_id"]

    {forgotten, db} =
      call(
        Corpus,
        "source",
        %{
          "store" => "notes",
          "action" => "forget",
          "args" => %{"source_id" => id, "expected_revision" => stored["revision"]}
        },
        db
      )

    assert forgotten["status"] == "ok"

    {refused, after_db} =
      call(Research, "fetch_retain", Map.put(args(), "uri", "fixture:alias"), db)

    assert refused["status"] == "refused" and F.records(after_db) == F.records(db)
  end

  test "ordinary Store and Corpus put cannot forward a fabricated fetched capture" do
    put = %{
      "source_id" => "provided:ordinary",
      "generation" => 1,
      "expected_revision" => 0,
      "title" => "Provided",
      "text" => @body,
      "uri" => @uri,
      "observed_at_ms" => 10,
      "event_at_ms" => nil,
      "expires_at_ms" => nil,
      "fetched_capture" => %{"descriptor" => %{"operation_id" => String.duplicate("0", 32)}}
    }

    assert {:done, {:error, :invalid_store_arguments, _}} =
             Store.start("notes", opts()["stores"]["notes"], :put, put)

    {refused, unchanged} =
      call(Corpus, "source", %{"store" => "notes", "action" => "put", "args" => put}, db())

    assert refused["status"] == "refused" and F.records(unchanged) == %{}
  end

  test "an uncertain actual fetch stops without State IO" do
    assert {:unknown, unchanged} =
             call(Research, "fetch_retain", args(), F.barrier(db(), "fetch", :unknown))

    refute Enum.any?(F.requests(unchanged), &(&1["op"] in ~w(state.put state.scan state.get)))
  end
end

result = ExUnit.run()
System.halt(if result.failures == 0, do: 0, else: 1)
