ExUnit.start(autorun: false)
Code.require_file("dev/fixtures/knowledge.exs", Path.expand("../..", __DIR__))
Code.require_file("extensions/knowledge/src/corpus.ex", Path.expand("../..", __DIR__))

defmodule ResearchTransferTest do
  use ExUnit.Case, async: false
  alias IpseKnowledge.{Research, Corpus, Store, Evidence, Profiles}
  alias Ipse.Development.Fixtures.Knowledge, as: F
  @root Path.expand("../..", __DIR__)
  defp opts do
    JSON.decode!(
      File.read!(Path.join(@root, "extensions/knowledge/options/research-state-retained.json"))
    )
  end

  defp source do
    %{
      "source_id" => "supplied:one",
      "title" => "Release",
      "text" => "Résumé 雪: Ada owns release after audit.",
      "uri" => "https://example.invalid/provided",
      "observed_at_ms" => 10,
      "event_at_ms" => nil,
      "expires_at_ms" => nil
    }
  end

  defp args(source \\ source()),
    do: %{"store" => "notes", "source" => source, "quote" => "Ada owns release after audit."}

  defp start(module) do
    options =
      if module == Corpus,
        do: opts() |> Map.put("search", %{}) |> Map.put("fetch", %{}),
        else: opts()

    {:ok, state} = module.init(options)
    refute Map.has_key?(state, :invalid)
    state
  end

  defp value(%Ipse.Extension.ResultPublication.Output{bytes: bytes}), do: JSON.decode!(bytes)
  defp value(%{"kind" => "result", "value" => value}), do: value

  defp run(module, {:ok, %{"kind" => "host_call", "request" => request}, state}, db) do
    {outcome, db} = F.host(db, request)
    run(module, module.handle("host.actions", %{"outcome" => outcome}, state), db)
  end

  defp run(_, {:ok, result, _}, db), do: {value(result), db}
  defp run(_, {:stop, :unknown_effect}, db), do: {:unknown, db}

  defp call(module, id, args, db),
    do:
      run(
        module,
        module.handle("invoke.command", %{"id" => id, "arguments" => args}, start(module)),
        db
      )

  defp store_run({:call, request, cont}, db) do
    {outcome, db} = F.host(db, request)
    store_run(Store.resume(cont, outcome), db)
  end

  defp store_run(result, db), do: {result, db}

  defp snapshot(db) do
    {result, db} = store_run(Store.start("notes", opts()["stores"]["notes"], :snapshot, %{}), db)
    assert {:done, {:ok, snapshot}} = result
    {snapshot, db}
  end

  defp forged_put do
    s = source()
    [{offset, len}] = :binary.matches(s["text"], args()["quote"])

    s
    |> Map.put("source_id", Store.provided_transfer_id(s["text"]))
    |> Map.merge(%{
      "generation" => 1,
      "expected_revision" => 0,
      "provided_transfer" => %{
        "version" => 1,
        "kind" => "research.provided_transfer",
        "source_id" => s["source_id"],
        "uri" => s["uri"],
        "body_sha256" => Evidence.sha256(s["text"]),
        "quote" => args()["quote"],
        "start_byte" => offset,
        "end_byte" => offset + len
      }
    })
  end

  test "explicit provided transfer is queried with attribution and exact UTF8 derivation" do
    {retained, db} = call(Research, "retain", args(), F.new("research-notes"))
    assert retained["status"] == "ok"
    {snapshot, db} = snapshot(db)
    assert [source] = snapshot["sources"]
    assert source["text"] == source()["text"]
    assert source["origin"]["kind"] == "provided"
    assert source["origin"]["historical"] == false
    receipt = source["origin"]["receipt"]
    assert receipt == retained["coverage"]["derivation"]
    assert receipt["start_byte"] == byte_size("Résumé 雪: ")
    assert receipt["end_byte"] == byte_size(source["text"])
    assert receipt["body_sha256"] == Evidence.sha256(source["text"])

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

    assert query["status"] == "ok"
    assert [candidate] = query["evidence"]
    assert candidate["citation"]["origin"] == source["origin"]
    assert String.contains?(candidate["citation"]["quote"], "Ada owns release")
    assert Enum.all?(F.requests(db), &String.starts_with?(&1["op"], "state."))
  end

  test "Corpus forget blocks aliases, new worker states and changed selected quote in the same body" do
    {retained, db} = call(Research, "retain", args(), F.new("research-notes"))
    id = retained["coverage"]["source_id"]

    {inspected, db} =
      call(
        Corpus,
        "source",
        %{"store" => "notes", "action" => "inspect", "args" => %{"source_id" => id}},
        db
      )

    revision = inspected["coverage"]["revision"]
    assert is_integer(revision)

    {forgotten, db} =
      call(
        Corpus,
        "source",
        %{
          "store" => "notes",
          "action" => "forget",
          "args" => %{"source_id" => id, "expected_revision" => revision}
        },
        db
      )

    assert forgotten["status"] == "ok"
    records = F.records(db)

    for alias <- [%{}, %{"source_id" => "renamed"}, %{"uri" => "https://other.invalid/alias"}] do
      supplied = Map.merge(source(), alias)

      for quote <- [args()["quote"], "Résumé 雪"] do
        {refused, after_db} =
          call(Research, "retain", Map.put(args(supplied), "quote", quote), db)

        assert refused["status"] == "refused"
        assert F.records(after_db) == records
      end
    end

    {snapshot, _} = snapshot(db)
    assert snapshot["sources"] == []
  end

  test "same body cannot silently rewrite attribution" do
    {_, db} = call(Research, "retain", args(), F.new("research-notes"))

    {refused, after_db} =
      call(Research, "retain", args(Map.put(source(), "uri", "provided:other")), db)

    assert refused["status"] == "refused"
    assert F.records(after_db) == F.records(db)
  end

  test "Store independently rejects changed hash, offsets, quote ambiguity, identity and authority metadata before IO" do
    put = forged_put()

    invalid = [
      put_in(put, ["provided_transfer", "body_sha256"], String.duplicate("0", 64)),
      put_in(put, ["provided_transfer", "start_byte"], 0),
      put_in(put, ["provided_transfer", "end_byte"], 0),
      put_in(put, ["provided_transfer", "quote"], "missing"),
      Map.put(put, "source_id", "caller-selected"),
      Map.put(put, "generation", 2),
      Map.put(put, "expected_revision", 1),
      Map.put(put, "historical_import", %{}),
      Map.put(put, "origin", %{"kind" => "fetched"}),
      put_in(put, ["provided_transfer", "kind"], "fetch-v1"),
      put_in(put, ["provided_transfer", "receipt"], %{}),
      Map.put(put, "document", %{})
    ]

    for args <- invalid do
      assert {:done, {:error, :invalid_store_arguments, _}} =
               Store.start("notes", opts()["stores"]["notes"], :put, args)
    end

    text = "repeat repeat"

    ambiguous =
      put
      |> Map.put("text", text)
      |> Map.put("source_id", Store.provided_transfer_id(text))
      |> put_in(["provided_transfer", "body_sha256"], Evidence.sha256(text))
      |> put_in(["provided_transfer", "quote"], "repeat")
      |> put_in(["provided_transfer", "start_byte"], 0)
      |> put_in(["provided_transfer", "end_byte"], 6)

    assert {:done, {:error, :invalid_store_arguments, _}} =
             Store.start("notes", opts()["stores"]["notes"], :put, ambiguous)
  end

  test "Research closed input and ordinary Corpus put reject forwarded authority fields" do
    for extra <- [
          %{"source_id" => "target"},
          %{"generation" => 2},
          %{"expected_revision" => 9},
          %{"origin" => %{"kind" => "fetched"}},
          %{"receipt" => %{}},
          %{"historical_import" => %{}}
        ] do
      {refused, db} = call(Research, "retain", Map.merge(args(), extra), F.new("research-notes"))
      assert refused["status"] == "refused"
      assert F.requests(db) == []

      nested =
        if Map.has_key?(extra, "source_id"), do: %{"target_source_id" => "target"}, else: extra

      {refused, db} =
        call(Research, "retain", args(Map.merge(source(), nested)), F.new("research-notes"))

      assert refused["status"] == "refused"
      assert F.requests(db) == []
    end

    {refused, db} =
      call(
        Corpus,
        "source",
        %{"store" => "notes", "action" => "put", "args" => forged_put()},
        F.new("research-notes")
      )

    assert refused["status"] == "refused"
    assert F.requests(db) == []
  end

  test "overlapping quote matches are ambiguous" do
    assert {:error, :ambiguous_quote} = Store.provided_quote_range("aaa", "aa")

    {result, db} =
      call(
        Research,
        "retain",
        args(Map.put(source(), "text", "aaa")) |> Map.put("quote", "aa"),
        F.new("research-notes")
      )

    assert result["status"] == "refused"
    assert F.requests(db) == []
  end

  test "preset keeps provided-only profiles and exposes only the existing State capabilities" do
    assert Profiles.capabilities("research", "state-retained") ==
             Profiles.capabilities("corpus", "state-lexical")

    assert {:error, _} = Profiles.validate("research", "offline", opts())

    assert {:error, _} =
             Profiles.validate(
               "research",
               "state-retained",
               put_in(opts(), ["fetch", "given"], %{
                 "kind" => "mcp",
                 "binding" => "web",
                 "contract" => "fetch-v1"
               })
             )

    assert {:error, _} =
             Profiles.validate("research", "state-retained", Map.put(opts(), "stores", %{}))
  end

  test "an uncertain mutation remains unknown and is not retried" do
    state = start(Research)

    assert {:ok, %{"kind" => "host_call"}, _} =
             Research.handle("invoke.command", %{"id" => "retain", "arguments" => args()}, state)

    mutating = fn recur, result, db ->
      {:ok, %{"kind" => "host_call", "request" => request}, state} = result

      if request["op"] == "state.put" do
        assert {:stop, :unknown_effect} =
                 Research.handle(
                   "host.actions",
                   %{"outcome" => %{"status" => "unknown", "value" => %{}}},
                   state
                 )

        db
      else
        {outcome, db} = F.host(db, request)
        recur.(recur, Research.handle("host.actions", %{"outcome" => outcome}, state), db)
      end
    end

    db =
      mutating.(
        mutating,
        Research.handle("invoke.command", %{"id" => "retain", "arguments" => args()}, state),
        F.new("research-notes")
      )

    assert F.records(db) == %{}
  end
end

result = ExUnit.run()
System.halt(if result.failures == 0, do: 0, else: 1)
