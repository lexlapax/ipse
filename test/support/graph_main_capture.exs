ExUnit.start(autorun: false)

for file <- ~w(evidence profiles adapters store/state store/mcp_cas store),
    do: Code.require_file("extensions/knowledge/src/" <> file <> ".ex")

Code.require_file(List.first(System.argv()) || "extensions/knowledge/src/graph.ex")
Code.require_file("dev/fixtures/knowledge.exs")

defmodule CaptureDriver do
  import ExUnit.Assertions
  alias IpseKnowledge.Graph
  alias Ipse.Development.Fixtures.Knowledge, as: F

  def initial do
    options = Map.new(~w(stores search fetch retrieval embedding rerank extraction), &{&1, %{}})

    options =
      options
      |> Map.put("version", 1)
      |> Map.put("stores", %{
        "notes" => %{"kind" => "state", "scope" => "project", "partition" => "notes"}
      })
      |> Map.put("extraction", %{"given" => %{"kind" => "explicit", "version" => 1}})

    {:ok, graph} = Graph.init(options)
    refute Map.has_key?(graph, :invalid)
    {graph, F.new()}
  end

  def invoke(graph, db, id, args),
    do: run(Graph.handle("invoke.tool", %{"id" => id, "arguments" => args}, graph), db)

  def run({:ok, %{"kind" => "host_call", "request" => request}, graph}, db) do
    {outcome, db} = F.host(db, request)
    run(Graph.handle("host.actions", %{"outcome" => outcome}, graph), db)
  end

  def run({:ok, %{bytes: bytes}, graph}, db), do: {JSON.decode!(bytes), graph, db}
  def run({:ok, %{"kind" => "result", "value" => value}, graph}, db), do: {value, graph, db}

  def source(graph, db, text, gen \\ 1, expires \\ nil) do
    key = IpseKnowledge.Store.root_key("notes", IpseKnowledge.Evidence.sha256("test-source"))
    revision = if db.records[key], do: db.records[key]["revision"], else: 0

    args = %{
      "store" => "notes",
      "action" => "put",
      "args" => %{
        "source_id" => "test-source",
        "generation" => gen,
        "expected_revision" => revision,
        "title" => "Relationship evidence",
        "text" => text,
        "uri" => "provided:test",
        "observed_at_ms" => 1,
        "event_at_ms" => nil,
        "expires_at_ms" => expires
      }
    }

    run(Graph.handle("invoke.command", %{"id" => "source", "arguments" => args}, graph), db)
  end

  def relation(extra \\ %{}),
    do:
      Map.merge(
        %{
          "subject" => "Cedar",
          "predicate" => "uses",
          "object" => "Blue",
          "polarity" => "positive",
          "inferred" => false,
          "valid_from_ms" => nil,
          "valid_to_ms" => nil,
          "quote" => "Cedar uses Blue."
        },
        extra
      )

  def args(relations \\ nil),
    do: %{
      "store" => "notes",
      "extraction" => "given",
      "source_id" => "test-source",
      "generation" => 1,
      "relations" => relations || [relation()]
    }

  def query(graph, db, now \\ nil),
    do:
      invoke(graph, db, "query", %{
        "store" => "notes",
        "entity" => "Cedar",
        "depth" => 1,
        "max_nodes" => 128,
        "max_edges" => 256,
        "top_k" => 10,
        "as_of_ms" => now
      })

  def mutations(db), do: Enum.count(db.requests, &(&1["op"] in ~w(state.put state.delete)))
end

defmodule CaptureTest do
  use ExUnit.Case, async: false
  alias CaptureDriver, as: D
  alias IpseKnowledge.{Graph, Evidence, Store}
  alias Ipse.Development.Fixtures.Knowledge, as: F

  test "main-model descriptor uses ordinary State effects and no secondary model capability" do
    description = Graph.describe()
    assert Enum.any?(description["exports"]["tools"], &(&1["id"] == "capture"))
    refute "host.model" in description["capabilities"]

    assert :ok =
             Ipse.Extension.Catalog.validate(description["exports"], description["capabilities"])

    capture = Enum.find(description["exports"]["tools"], &(&1["id"] == "capture"))
    assert :ok = Ipse.JSON.validate_arguments(capture["arguments_schema"], D.args())

    assert {:error, _} =
             Ipse.JSON.validate_arguments(
               capture["arguments_schema"],
               put_in(D.args(), ["relations", Access.at(0), "citations"], [])
             )
  end

  test "tool derives exact source generation/chunk/span and queries the committed relationship" do
    {graph, db} = D.initial()
    {source, graph, db} = D.source(graph, db, "Cedar uses Blue.")
    assert source["status"] == "ok"
    {result, graph, db} = D.invoke(graph, db, "capture", D.args())
    assert result["status"] == "ok", inspect(result)
    {result, _, db} = D.query(graph, db)

    assert [
             %{
               "subject" => "Cedar",
               "object" => "Blue",
               "label" => "supported",
               "basis" => [citation]
             }
           ] = result["claims"]

    assert citation["quote"] == "Cedar uses Blue." and citation["generation"] == 1
    assert citation["start_byte"] == 0 and citation["end_byte"] == 16
    assert citation["content_sha256"] == Evidence.sha256("Cedar uses Blue.")

    refute Enum.any?(
             db.requests,
             &(&1["op"] in ~w(model.complete decision.create embedding.create))
           )
  end

  test "all invalid supports and generation mismatches refuse before a mutation" do
    for {text, args} <- [
          {"Cedar uses Blue.", D.args([D.relation(%{"quote" => "Cedar uses Red."})])},
          {"Cedar uses Blue. Cedar uses Blue.", D.args()},
          {"Cedar uses Blue.", Map.put(D.args(), "generation", 2)},
          {"Cedar uses Blue.", D.args([D.relation(%{"polarity" => "maybe"})])},
          {"Cedar uses Blue.",
           D.args([D.relation(%{"valid_from_ms" => 10, "valid_to_ms" => 5})])},
          {"Cedar uses Blue.", D.args([D.relation(%{"citations" => []})])},
          {"Cedar uses Blue.", Map.put(D.args(), "extraction", "not-enabled")}
        ] do
      {graph, db} = D.initial()
      {_, graph, db} = D.source(graph, db, text)
      records = db.records
      before = D.mutations(db)
      {result, _, db} = D.invoke(graph, db, "capture", args)
      assert result["status"] == "refused"
      assert db.records == records and D.mutations(db) == before
    end
  end

  test "expired sources refuse before writes and generation changes between snapshot and open refuse" do
    {graph, db} = D.initial()
    {_, graph, db} = D.source(graph, db, "Cedar uses Blue.", 1, 2)
    before = D.mutations(db)
    {result, _, after_db} = D.invoke(graph, db, "capture", D.args())
    assert result["status"] == "refused" and D.mutations(after_db) == before

    {graph, db} = D.initial()
    {_, graph, db} = D.source(graph, db, "Cedar uses Blue.")

    {:ok, %{"kind" => "host_call", "request" => request}, pending} =
      Graph.handle("invoke.tool", %{"id" => "capture", "arguments" => D.args()}, graph)

    {snapshot, db} = F.host(db, request)
    {_, graph, db} = D.source(graph, db, "Cedar uses Green.", 2)
    before = D.mutations(db)
    {result, _, db} = D.run(Graph.handle("host.actions", %{"outcome" => snapshot}, pending), db)
    assert result["status"] == "refused" and D.mutations(db) == before
    {query, _, _} = D.query(graph, db)

    assert query["claims"] == [
             %{
               "label" => "open",
               "uncertainty" => "semantic_support_unassessed",
               "evidence_indexes" => []
             }
           ]
  end

  test "polarity, uncertainty and temporal facts remain explicit and conflicts are preserved" do
    {graph, db} = D.initial()
    {_, graph, db} = D.source(graph, db, "Cedar uses Blue.")

    relations = [
      D.relation(),
      D.relation(%{"polarity" => "negative"}),
      D.relation(%{
        "object" => "Green",
        "inferred" => true,
        "valid_from_ms" => 10,
        "valid_to_ms" => 20
      })
    ]

    {result, graph, db} = D.invoke(graph, db, "capture", D.args(relations))
    assert result["status"] == "ok"
    {query, _, _} = D.query(graph, db, 15)
    assert Enum.count(query["claims"], &(&1["label"] == "conflict")) == 2
    assert Enum.any?(query["claims"], &(&1["object"] == "Green" and &1["label"] == "inference"))
    {later, _, _} = D.query(graph, db, 20)
    refute Enum.any?(later["claims"], &(&1["object"] == "Green"))
  end

  test "source replacement and forgetting invalidate captured facts" do
    {graph, db} = D.initial()
    {_, graph, db} = D.source(graph, db, "Cedar uses Blue.")
    {_, graph, db} = D.invoke(graph, db, "capture", D.args())
    {_, graph, db} = D.source(graph, db, "Cedar uses Green.", 2)
    {query, graph, db} = D.query(graph, db)

    assert query["claims"] == [
             %{
               "label" => "open",
               "uncertainty" => "semantic_support_unassessed",
               "evidence_indexes" => []
             }
           ]

    key = Store.root_key("notes", Evidence.sha256("test-source"))

    args = %{
      "store" => "notes",
      "action" => "forget",
      "args" => %{
        "source_id" => "test-source",
        "expected_revision" => db.records[key]["revision"]
      }
    }

    {forgotten, graph, db} =
      D.run(Graph.handle("invoke.command", %{"id" => "source", "arguments" => args}, graph), db)

    assert forgotten["status"] == "ok"
    before = D.mutations(db)
    {refused, _, db} = D.invoke(graph, db, "capture", Map.put(D.args(), "generation", 2))
    assert refused["status"] == "refused" and D.mutations(db) == before
  end

  test "unknown first mutation stops the invocation without replay" do
    {graph, db} = D.initial()
    {_, graph, db} = D.source(graph, db, "Cedar uses Blue.")
    result = Graph.handle("invoke.tool", %{"id" => "capture", "arguments" => D.args()}, graph)
    {request, pending} = until_mutation(result, db)
    assert request["op"] == "state.put"

    {:ok, reply, state} =
      Graph.handle(
        "host.actions",
        %{"outcome" => %{"status" => "unknown", "value" => %{}}},
        pending
      )

    assert state.phase == :idle
    refute reply["kind"] == "host_call"
    value = if reply[:bytes], do: JSON.decode!(reply.bytes), else: reply["value"]
    assert value["status"] == "refused" and value["gaps"] == [%{"code" => "unknown_effect"}]
  end

  test "later batches retain prior facts, deduplicate unchanged facts and preserve distinct identities" do
    {graph, db} = D.initial()
    {_, graph, db} = D.source(graph, db, "Cedar uses Blue.")
    {_, graph, db} = D.invoke(graph, db, "capture", D.args())
    relation = D.relation(%{"subject" => "Different Cedar", "object" => "Green"})
    {result, graph, db} = D.invoke(graph, db, "capture", D.args([D.relation(), relation]))
    assert result["status"] == "ok"
    {query, _, _} = D.query(graph, db)
    assert Enum.count(query["claims"], &(&1["subject"] == "Cedar")) == 1
    refute Enum.any?(query["claims"], &(&1["subject"] == "Different Cedar"))
  end

  test "nonexplicit profiles and oversized batches refuse without requesting effects" do
    {graph, db} = D.initial()
    state = put_in(graph, [:resolved, "options", "extraction", "given", "kind"], "model_complete")

    for {state, args} <- [
          {state, D.args()},
          {graph, D.args([])},
          {graph, D.args(List.duplicate(D.relation(), 9))}
        ] do
      {result, _, after_db} = D.invoke(state, db, "capture", args)
      assert result["status"] == "refused"
      assert after_db.requests == db.requests
    end
  end

  test "denied projection claim stops without requesting another mutation" do
    {graph, db} = D.initial()
    {_, graph, db} = D.source(graph, db, "Cedar uses Blue.")
    result = Graph.handle("invoke.tool", %{"id" => "capture", "arguments" => D.args()}, graph)
    {_, pending} = until_mutation(result, db)

    {:ok, reply, state} =
      Graph.handle(
        "host.actions",
        %{"outcome" => %{"status" => "denied", "value" => %{}}},
        pending
      )

    assert state.phase == :idle
    refute reply["kind"] == "host_call"
    value = if reply[:bytes], do: JSON.decode!(reply.bytes), else: reply["value"]
    assert value["status"] == "refused" and value["gaps"] == [%{"code" => "denied"}]
  end

  defp until_mutation({:ok, %{"kind" => "host_call", "request" => request}, graph}, db) do
    if request["op"] == "state.put",
      do: {request, graph},
      else:
        (
          {outcome, db} = F.host(db, request)
          until_mutation(Graph.handle("host.actions", %{"outcome" => outcome}, graph), db)
        )
  end
end

result = ExUnit.run()
System.halt(if(result.failures == 0, do: 0, else: 1))
