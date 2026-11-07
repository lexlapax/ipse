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

defmodule GraphIdentityDriver do
  alias CaptureDriver, as: D
  alias IpseKnowledge.{Evidence, Graph}
  alias Ipse.Development.Fixtures.Knowledge, as: F

  def seed do
    {graph, db} = D.initial()

    text =
      "Cedar uses Blue. Birch uses Green. Aspen is another name for Cedar. Cedar and Birch identify the same release group. " <>
        Enum.map_join(1..9, " ", &"Alias#{&1} names Cedar.")

    {_, graph, db} = D.source(graph, db, text)

    {_, graph, db} =
      D.invoke(
        graph,
        db,
        "capture",
        D.args([
          D.relation(),
          D.relation(%{"subject" => "Birch", "object" => "Green", "quote" => "Birch uses Green."})
        ])
      )

    {graph, db}
  end

  def alias_args(rev \\ 0),
    do: %{
      "store" => "notes",
      "action" => "alias",
      "expected_revision" => rev,
      "source_id" => "test-source",
      "generation" => 1,
      "from" => "Aspen",
      "to" => "Cedar",
      "quote" => "Aspen is another name for Cedar."
    }

  def merge_args(rev),
    do:
      alias_args(rev)
      |> Map.merge(%{
        "action" => "merge",
        "from" => "Cedar",
        "to" => "Birch",
        "quote" => "Cedar and Birch identify the same release group."
      })

  def identity(graph, db, args),
    do:
      D.run(Graph.handle("invoke.command", %{"id" => "identity", "arguments" => args}, graph), db)

  def inspect_selection(graph, db),
    do: identity(graph, db, %{"store" => "notes", "action" => "inspect"})

  def undo(graph, db, rev, operation),
    do:
      identity(graph, db, %{
        "store" => "notes",
        "action" => "undo",
        "expected_revision" => rev,
        "operation_id" => operation
      })

  def query(graph, db, entity, now \\ nil),
    do:
      D.invoke(graph, db, "query", %{
        "store" => "notes",
        "entity" => entity,
        "depth" => 1,
        "max_nodes" => 128,
        "max_edges" => 256,
        "top_k" => 10,
        "as_of_ms" => now
      })

  def key, do: Evidence.graph_identity_key("notes")
  def writes(db), do: Enum.filter(db.requests, &(&1["op"] in ~w(state.put state.delete)))

  def pending(graph, db, args),
    do:
      until(
        Graph.handle("invoke.command", %{"id" => "identity", "arguments" => args}, graph),
        db,
        &(&1["op"] === "state.put")
      )

  def until({:ok, %{"kind" => "host_call", "request" => request}, graph}, db, predicate) do
    if predicate.(request),
      do: {request, graph, db},
      else:
        (
          {outcome, db} = F.host(db, request)
          until(Graph.handle("host.actions", %{"outcome" => outcome}, graph), db, predicate)
        )
  end

  def until_phase({:ok, %{"kind" => "host_call", "request" => request}, graph}, db, phase) do
    if graph.phase === phase,
      do: {request, graph, db},
      else:
        (
          {outcome, db} = F.host(db, request)
          until_phase(Graph.handle("host.actions", %{"outcome" => outcome}, graph), db, phase)
        )
  end
end

defmodule GraphIdentityTest do
  use ExUnit.Case, async: false
  alias CaptureDriver, as: D
  alias GraphIdentityDriver, as: I
  alias IpseKnowledge.{Evidence, Graph, Store}
  alias Ipse.Development.Fixtures.Knowledge, as: F

  test "explicit alias merge and latest undo preserve original facts and citations" do
    {graph, db} = I.seed()
    original = db.records
    {before, graph, db} = I.query(graph, db, "Aspen")
    assert Enum.all?(before["claims"], &(&1["label"] === "open"))
    {aliased, graph, db} = I.identity(graph, db, I.alias_args())
    assert aliased["status"] === "ok"
    alias_op = aliased["coverage"]["identity_selection"]["operation_id"]
    {query, graph, db} = I.query(graph, db, "Aspen")
    assert [%{"subject" => "Cedar", "object" => "Blue", "basis" => [citation]}] = query["claims"]
    assert citation["quote"] === "Cedar uses Blue."
    assert query["coverage"]["identity_selection"]["revision"] === 1
    {merged, graph, db} = I.identity(graph, db, I.merge_args(1))
    merge_op = merged["coverage"]["identity_selection"]["operation_id"]
    assert merged["status"] === "ok"
    {query, graph, db} = I.query(graph, db, "Aspen")
    assert Enum.sort(Enum.map(query["claims"], & &1["subject"])) === ["Birch", "Cedar"]
    {undone, graph, db} = I.undo(graph, db, 2, merge_op)
    assert undone["status"] === "ok"
    {query, graph, db} = I.query(graph, db, "Aspen")
    assert Enum.map(query["claims"], & &1["subject"]) === ["Cedar"]
    {undone, graph, db} = I.undo(graph, db, 3, alias_op)
    assert undone["status"] === "ok"
    {query, _, db} = I.query(graph, db, "Aspen")
    assert Enum.all?(query["claims"], &(&1["label"] === "open"))
    assert Map.drop(db.records, [I.key()]) === original
    refute Enum.any?(db.requests, &(&1["op"] in ~w(model.complete decision.create mcp.call)))
  end

  test "identity is an explicit command with existing ordinary State capabilities" do
    description = Graph.describe()
    assert Enum.any?(description["exports"]["commands"], &(&1["id"] === "identity"))
    refute Enum.any?(description["exports"]["tools"], &(&1["id"] === "identity"))
    :ok = Ipse.Extension.Catalog.validate(description["exports"], description["capabilities"])
    refute "host.model" in description["capabilities"]

    schema =
      Enum.find(description["exports"]["commands"], &(&1["id"] === "identity"))[
        "arguments_schema"
      ]

    :ok = Ipse.JSON.validate_arguments(schema, I.alias_args())
  end

  test "stale revision and older undo never overwrite a newer explicit choice" do
    {graph, db} = I.seed()
    {aliased, graph, db} = I.identity(graph, db, I.alias_args())
    {_, graph, db} = I.identity(graph, db, I.merge_args(1))
    before = db.records

    for args <- [
          I.alias_args(),
          %{
            "store" => "notes",
            "action" => "undo",
            "expected_revision" => 2,
            "operation_id" => aliased["coverage"]["identity_selection"]["operation_id"]
          }
        ] do
      {refusal, _, after_db} = I.identity(graph, db, args)
      assert refusal["status"] === "refused"
      assert after_db.records === before
    end
  end

  test "namespace CAS refuses a competing publication while approval is pending" do
    {graph, db} = I.seed()
    {request, pending, db} = I.pending(graph, db, I.alias_args())
    assert request["expected_revision"] === 0 and request["expected_generation"] === db.generation
    {_, _, changed} = D.source(graph, db, "Cedar uses Orange.", 2)
    {outcome, changed} = F.host(changed, request)

    {result, _, final} =
      D.run(Graph.handle("host.actions", %{"outcome" => outcome}, pending), changed)

    assert result["status"] === "refused" and result["gaps"] === [%{"code" => "conflict"}]
    assert final.records[I.key()] === nil
  end

  test "denied and unknown writes stop once; fresh inspection observes known-applied unknown" do
    for mode <- ["denied", "unknown"] do
      {graph, db} = I.seed()
      {request, pending, db} = I.pending(graph, db, I.alias_args())
      bytes = IO.iodata_to_binary(JSON.encode!(request))
      assert byte_size(bytes) < 16_384

      {result, _, after_db} =
        D.run(
          Graph.handle(
            "host.actions",
            %{"outcome" => %{"status" => mode, "value" => %{}}},
            pending
          ),
          db
        )

      assert result["status"] === "refused" and after_db.records === db.records
      assert after_db.requests === db.requests
    end

    {graph, db} = I.seed()
    {request, pending, db} = I.pending(graph, db, I.alias_args())
    {_, applied} = F.host(db, request)

    {result, _, applied} =
      D.run(
        Graph.handle(
          "host.actions",
          %{"outcome" => %{"status" => "unknown", "value" => %{}}},
          pending
        ),
        applied
      )

    assert result["status"] === "refused"
    {inspect, graph, inspected} = I.inspect_selection(graph, applied)
    assert inspect["coverage"]["identity_selection"]["revision"] === 1
    assert I.writes(inspected) === I.writes(applied)
    [step] = inspect["coverage"]["identity_selection"]["steps"]
    {undo, _, _} = I.undo(graph, inspected, 1, step["operation_id"])
    assert undo["status"] === "ok"
  end

  test "current source replacement withdraws selection but still permits explicit undo" do
    {graph, db} = I.seed()
    {aliased, graph, db} = I.identity(graph, db, I.alias_args())
    {_, graph, db} = D.source(graph, db, "Cedar uses Orange.", 2)
    {query, graph, db} = I.query(graph, db, "Aspen")
    assert query["status"] === "refused"
    {inspect, graph, db} = I.inspect_selection(graph, db)
    assert inspect["coverage"]["identity_selection"]["current_source_authority"] === false
    {undo, _, _} = I.undo(graph, db, 1, aliased["coverage"]["identity_selection"]["operation_id"])
    assert undo["status"] === "ok"
  end

  test "expiry withdrawal and host decision deadline are explicit and unchanged" do
    {graph, db} = I.seed()
    root_key = Store.root_key("notes", Evidence.sha256("test-source"))
    expiry = System.system_time(:millisecond) + 60_000
    db = put_in(db.records[root_key]["value"]["expires_at_ms"], expiry)
    {request, _, _} = I.pending(graph, db, I.alias_args())
    assert request["write_before_ms"] === expiry
    {aliased, graph, db} = I.identity(graph, db, I.alias_args())
    {query, _, _} = I.query(graph, db, "Aspen", expiry)
    assert query["status"] === "refused"
    assert aliased["status"] === "ok"
  end

  test "current identity query refuses when its source or fact deadline passes during revalidation" do
    now = System.system_time(:millisecond)

    for {source_expiry, fact_expiry} <- [
          {now + 60_000, now + 30_000},
          {now + 30_000, now + 60_000}
        ],
        as_of <- [nil, now] do
      {graph, db} = D.initial()
      text = "Cedar uses Blue. Aspen is another name for Cedar."
      {_, graph, db} = D.source(graph, db, text, 1, source_expiry)
      relation = D.relation(%{"valid_to_ms" => fact_expiry})
      {captured, graph, db} = D.invoke(graph, db, "capture", D.args([relation]))
      assert captured["status"] === "ok"
      {aliased, graph, db} = I.identity(graph, db, I.alias_args())
      assert aliased["status"] === "ok"

      invocation =
        Graph.handle(
          "invoke.tool",
          %{
            "id" => "query",
            "arguments" => %{
              "store" => "notes",
              "entity" => "Aspen",
              "depth" => 1,
              "max_nodes" => 128,
              "max_edges" => 256,
              "top_k" => 10,
              "as_of_ms" => as_of
            }
          },
          graph
        )

      {request, pending, db} =
        I.until(invocation, db, &(&1["op"] === "state.get" and &1["key"] === I.key()))

      assert pending.phase === :query_identity_revalidate
      assert pending.ctx.next_query_transition === min(source_expiry, fact_expiry)
      {outcome, db} = F.host(db, request)
      {on_time, _, _} = D.run(Graph.handle("host.actions", %{"outcome" => outcome}, pending), db)
      assert on_time["status"] === "ok"

      # Simulate the same final callback after the already-computed deadline,
      # without an unreliable wall-clock sleep or another external effect.
      late = put_in(pending.ctx.next_query_transition, 0)
      {result, _, _} = D.run(Graph.handle("host.actions", %{"outcome" => outcome}, late), db)

      if is_nil(as_of) do
        assert result["status"] === "refused"
        assert result["claims"] === [] and result["evidence"] === []
        assert result["gaps"] === [%{"code" => "query_time_changed"}]
      else
        assert result["status"] === "ok"
      end
    end
  end

  test "source and fact expiry also withhold current queries without identity choices" do
    now = System.system_time(:millisecond)

    for field <- [:source, :fact], as_of <- [nil, now] do
      expiry = now + 60_000
      {graph, db} = D.initial()

      {_, graph, db} =
        D.source(graph, db, "Cedar uses Blue.", 1, if(field === :source, do: expiry))

      fact = D.relation(%{"valid_to_ms" => if(field === :fact, do: expiry)})
      {captured, graph, db} = D.invoke(graph, db, "capture", D.args([fact]))
      assert captured["status"] === "ok"
      original_records = db.records

      args = %{
        "store" => "notes",
        "entity" => "Cedar",
        "depth" => 1,
        "max_nodes" => 128,
        "max_edges" => 256,
        "top_k" => 10,
        "as_of_ms" => as_of
      }

      {request, pending, db} =
        I.until(
          Graph.handle("invoke.tool", %{"id" => "query", "arguments" => args}, graph),
          db,
          &(&1["op"] === "state.get" and &1["key"] === I.key())
        )

      assert pending.ctx.next_query_transition === expiry
      {outcome, db} = F.host(db, request)
      late = put_in(pending.ctx.next_query_transition, 0)

      {result, _, after_db} =
        D.run(Graph.handle("host.actions", %{"outcome" => outcome}, late), db)

      assert after_db.records === original_records

      if is_nil(as_of) do
        assert result["status"] === "refused"
        assert result["claims"] === [] and result["evidence"] === []
        assert result["gaps"] === [%{"code" => "query_time_changed"}]
      else
        assert result["status"] === "ok"
      end
    end
  end

  test "the identity-universe deadline may include an unreturned unrelated fact" do
    expiry = System.system_time(:millisecond) + 60_000
    {graph, db} = D.initial()
    text = "Cedar uses Blue. Birch uses Green. Aspen is another name for Cedar."
    {_, graph, db} = D.source(graph, db, text)

    birch =
      D.relation(%{
        "subject" => "Birch",
        "object" => "Green",
        "quote" => "Birch uses Green.",
        "valid_to_ms" => expiry
      })

    {captured, graph, db} = D.invoke(graph, db, "capture", D.args([D.relation(), birch]))
    assert captured["status"] === "ok"
    {aliased, graph, db} = I.identity(graph, db, I.alias_args())
    assert aliased["status"] === "ok"

    args = %{
      "store" => "notes",
      "entity" => "Aspen",
      "depth" => 1,
      "max_nodes" => 128,
      "max_edges" => 256,
      "top_k" => 10,
      "as_of_ms" => nil
    }

    {request, pending, db} =
      I.until(
        Graph.handle("invoke.tool", %{"id" => "query", "arguments" => args}, graph),
        db,
        &(&1["op"] === "state.get" and &1["key"] === I.key())
      )

    assert pending.ctx.next_query_transition === expiry
    {outcome, db} = F.host(db, request)
    {result, _, _} = D.run(Graph.handle("host.actions", %{"outcome" => outcome}, pending), db)
    assert Enum.map(result["claims"], & &1["subject"]) === ["Cedar"]
    late = put_in(pending.ctx.next_query_transition, 0)
    {refused, _, _} = D.run(Graph.handle("host.actions", %{"outcome" => outcome}, late), db)
    assert refused["status"] === "refused"
  end

  test "future fact activation and backward clock refuse a current query but not historical queries" do
    now = System.system_time(:millisecond)
    activation = now + 60_000
    {graph, db} = D.initial()
    text = "Cedar uses Blue. Aspen uses Gold. Aspen is another name for Cedar."
    {_, graph, db} = D.source(graph, db, text)

    future =
      D.relation(%{
        "subject" => "Aspen",
        "object" => "Gold",
        "quote" => "Aspen uses Gold.",
        "valid_from_ms" => activation
      })

    {captured, graph, db} = D.invoke(graph, db, "capture", D.args([D.relation(), future]))
    assert captured["status"] === "ok"

    for identity? <- [false, true], as_of <- [nil, now] do
      {graph, db} =
        if identity? do
          {alias_result, graph, db} = I.identity(graph, db, I.alias_args())
          assert alias_result["status"] === "ok"
          {graph, db}
        else
          {graph, db}
        end

      args = %{
        "store" => "notes",
        "entity" => if(identity?, do: "Aspen", else: "Cedar"),
        "depth" => 1,
        "max_nodes" => 128,
        "max_edges" => 256,
        "top_k" => 10,
        "as_of_ms" => as_of
      }

      {request, pending, db} =
        I.until(
          Graph.handle("invoke.tool", %{"id" => "query", "arguments" => args}, graph),
          db,
          &(&1["op"] === "state.get" and &1["key"] === I.key())
        )

      assert pending.ctx.next_query_transition === activation
      {outcome, db} = F.host(db, request)
      {on_time, _, _} = D.run(Graph.handle("host.actions", %{"outcome" => outcome}, pending), db)
      assert on_time["status"] === "ok"

      for late <- [
            put_in(pending.ctx.next_query_transition, 0),
            put_in(pending.ctx.as_of_ms, now + 120_000)
          ] do
        {result, _, _} = D.run(Graph.handle("host.actions", %{"outcome" => outcome}, late), db)

        if is_nil(as_of) do
          assert result["status"] === "refused"
          assert result["claims"] === [] and result["evidence"] === []
          assert result["gaps"] === [%{"code" => "query_time_changed"}]
        else
          assert result["status"] === "ok"
        end
      end
    end
  end

  test "a future-observed source also bounds current snapshot selection" do
    now = System.system_time(:millisecond)
    activation = now + 60_000
    {graph, db} = I.seed()

    args = %{
      "store" => "notes",
      "action" => "put",
      "args" => %{
        "source_id" => "future-source",
        "generation" => 1,
        "expected_revision" => 0,
        "title" => "Future source",
        "text" => "Future relation.",
        "uri" => "provided:future",
        "observed_at_ms" => activation,
        "event_at_ms" => nil,
        "expires_at_ms" => nil
      }
    }

    {stored, graph, db} =
      D.run(Graph.handle("invoke.command", %{"id" => "source", "arguments" => args}, graph), db)

    assert stored["status"] === "ok"

    query = %{
      "store" => "notes",
      "entity" => "Cedar",
      "depth" => 1,
      "max_nodes" => 128,
      "max_edges" => 256,
      "top_k" => 10,
      "as_of_ms" => nil
    }

    {request, pending, db} =
      I.until(
        Graph.handle("invoke.tool", %{"id" => "query", "arguments" => query}, graph),
        db,
        &(&1["op"] === "state.get" and &1["key"] === I.key())
      )

    assert pending.ctx.next_query_transition === activation
    {outcome, db} = F.host(db, request)
    late = put_in(pending.ctx.next_query_transition, 0)
    {refused, _, _} = D.run(Graph.handle("host.actions", %{"outcome" => outcome}, late), db)
    assert refused["status"] === "refused"
  end

  test "non-State final callback checks the captured-snapshot boundary" do
    activation = System.system_time(:millisecond) + 60_000
    {graph, db} = D.initial()
    {_, graph, db} = D.source(graph, db, "Cedar uses Blue. Aspen uses Gold.")

    future =
      D.relation(%{
        "subject" => "Aspen",
        "object" => "Gold",
        "quote" => "Aspen uses Gold.",
        "valid_from_ms" => activation
      })

    {captured, graph, db} = D.invoke(graph, db, "capture", D.args([D.relation(), future]))
    assert captured["status"] === "ok"

    args = %{
      "store" => "notes",
      "entity" => "Cedar",
      "depth" => 1,
      "max_nodes" => 128,
      "max_edges" => 256,
      "top_k" => 10,
      "as_of_ms" => nil
    }

    {request, pending, db} =
      I.until_phase(
        Graph.handle("invoke.tool", %{"id" => "query", "arguments" => args}, graph),
        db,
        :query_revalidate
      )

    assert pending.ctx.next_query_transition === activation
    # Simulate the non-State finish branch after the State fixture produced the
    # existing validated snapshot. This does not exercise an MCP wire adapter.
    pending = put_in(pending.ctx.profile["kind"], "mcp_cas")
    {outcome, db} = F.host(db, request)
    {on_time, _, _} = D.run(Graph.handle("host.actions", %{"outcome" => outcome}, pending), db)
    assert on_time["status"] === "ok"
    late = put_in(pending.ctx.next_query_transition, 0)
    {refused, _, _} = D.run(Graph.handle("host.actions", %{"outcome" => outcome}, late), db)
    assert refused["status"] === "refused" and refused["claims"] === []
    assert refused["gaps"] === [%{"code" => "query_time_changed"}]
  end

  test "aliases cannot shadow existing entities and merges cannot make cycles or self selections" do
    {graph, db} = I.seed()

    for args <- [
          Map.put(I.alias_args(), "from", "Birch"),
          Map.put(I.merge_args(0), "to", "Cedar"),
          Map.put(I.alias_args(), "quote", "Cedar uses Blue."),
          Map.put(I.alias_args(), "generation", 2)
        ] do
      {result, _, after_db} = I.identity(graph, db, args)
      assert result["status"] === "refused" and after_db.records === db.records
    end

    {_, graph, db} = I.identity(graph, db, I.merge_args(0))
    args = I.merge_args(1) |> Map.merge(%{"from" => "Birch", "to" => "Cedar"})
    {result, _, _} = I.identity(graph, db, args)
    assert result["status"] === "refused"
  end

  test "final exact row and namespace generation revalidation detects concurrent changes" do
    {graph, db} = I.seed()
    {_, graph, db} = I.identity(graph, db, I.alias_args())

    invocation =
      Graph.handle(
        "invoke.command",
        %{
          "id" => "query",
          "arguments" => %{
            "store" => "notes",
            "entity" => "Aspen",
            "depth" => 1,
            "max_nodes" => 128,
            "max_edges" => 256,
            "top_k" => 10,
            "as_of_ms" => nil
          }
        },
        graph
      )

    {request, pending, db} =
      I.until(invocation, db, &(&1["op"] === "state.get" and &1["key"] === I.key()))

    assert pending.phase === :query_identity_revalidate
    changed = %{db | generation: db.generation + 1}
    {outcome, changed} = F.host(changed, request)

    {result, _, _} =
      D.run(Graph.handle("host.actions", %{"outcome" => outcome}, pending), changed)

    assert result["status"] === "conflict" and result["claims"] === []

    changed =
      update_in(db.records[I.key()]["operation_id"], fn _ -> String.duplicate("f", 32) end)

    {outcome, changed} = F.host(changed, request)

    {result, _, _} =
      D.run(Graph.handle("host.actions", %{"outcome" => outcome}, pending), changed)

    assert result["status"] === "conflict"
  end

  test "strict tags, malformed citations and tombstones refuse without resurrection" do
    {graph, db} = I.seed()
    {_, graph, db} = I.identity(graph, db, I.alias_args())
    value = db.records[I.key()]["value"]

    for forged <- [
          Map.put(value, "format", 1.0),
          put_in(value, ["steps", Access.at(0), "version"], 1.0),
          put_in(value, ["steps", Access.at(0), "base_revision"], 0.0),
          put_in(value, ["steps", Access.at(0), "citation", "version"], 1.0),
          put_in(value, ["steps", Access.at(0), "citation", "quote"], "forged")
        ] do
      refute Evidence.valid_graph_identity?(forged, "notes")
      corrupt = put_in(db.records[I.key()]["value"], forged)
      {result, _, _} = I.inspect_selection(graph, corrupt)
      assert result["status"] === "refused"
    end

    tombstone =
      put_in(db.records[I.key()], %{
        "key" => I.key(),
        "revision" => 2,
        "deleted" => true,
        "value" => nil,
        "operation_id" => String.duplicate("1", 32)
      })

    {result, _, after_db} = I.identity(graph, tombstone, I.alias_args(2))
    assert result["status"] === "refused" and after_db.records === tombstone.records
  end

  test "structurally valid but foreign citation metadata cannot select current facts" do
    {graph, db} = I.seed()
    {_, graph, db} = I.identity(graph, db, I.alias_args())
    value = db.records[I.key()]["value"]
    [step] = value["steps"]

    for citation <- [
          Map.put(step["citation"], "uri", "provided:foreign"),
          put_in(step["citation"], ["origin", "store_profile"], "foreign")
        ] do
      forged =
        Map.put(value, "steps", [
          Evidence.graph_identity_step(
            step["kind"],
            step["from"],
            step["to"],
            citation,
            step["base_revision"]
          )
        ])

      assert Evidence.valid_graph_identity?(forged, "notes")
      corrupt = put_in(db.records[I.key()]["value"], forged)
      {result, _, _} = I.query(graph, corrupt, "Aspen")
      assert result["status"] === "refused" and result["claims"] === []
    end
  end

  test "bounded selection record refuses before publication rather than truncating" do
    {graph, db} = I.seed()

    {graph, db, admitted} =
      Enum.reduce(1..9, {graph, db, 0}, fn n, {graph, db, admitted} ->
        args =
          I.alias_args(admitted)
          |> Map.merge(%{"from" => "Alias#{n}", "quote" => "Alias#{n} names Cedar."})

        {result, next, after_db} = I.identity(graph, db, args)

        if result["status"] === "ok" do
          value = after_db.records[I.key()]["value"]
          assert byte_size(IO.iodata_to_binary(JSON.encode!(value))) <= 6000
          assert length(value["steps"]) === admitted + 1
          assert byte_size(IO.iodata_to_binary(JSON.encode!(hd(after_db.requests)))) < 16_384
          {next, after_db, admitted + 1}
        else
          assert after_db.records === db.records
          {graph, db, admitted}
        end
      end)

    assert admitted in 1..8
    {inspect, _, _} = I.inspect_selection(graph, db)
    assert length(inspect["coverage"]["identity_selection"]["steps"]) === admitted
  end

  test "metadata row survives collection and MCP mutation refuses before any host action" do
    {graph, db} = I.seed()
    {_, graph, db} = I.identity(graph, db, I.alias_args())
    before = db.records[I.key()]

    {_, graph, db} =
      D.invoke(graph, db, "source", %{
        "store" => "notes",
        "action" => "collect",
        "args" => %{"limit" => 12}
      })

    assert db.records[I.key()] === before

    mcp =
      put_in(graph, [:resolved, "options", "stores", "notes"], %{
        "kind" => "mcp_cas",
        "binding" => "db",
        "partition" => "notes",
        "contract" => "ipse-cas-v3"
      })

    {result, _, after_db} = I.identity(mcp, db, I.alias_args(1))
    assert result["status"] === "refused" and after_db.requests === db.requests
  end

  test "identity revalidation includes cumulative reads within the existing budget" do
    {graph, db} = I.seed()
    prior_reads = Enum.count(db.requests, &(&1["op"] in ~w(state.get state.scan)))

    invocation =
      Graph.handle(
        "invoke.command",
        %{
          "id" => "query",
          "arguments" => %{
            "store" => "notes",
            "entity" => "Cedar",
            "depth" => 1,
            "max_nodes" => 128,
            "max_edges" => 256,
            "top_k" => 10,
            "as_of_ms" => nil
          }
        },
        graph
      )

    {request, pending, db} =
      I.until(invocation, db, &(&1["op"] === "state.get" and &1["key"] === I.key()))

    {outcome, db} = F.host(db, request)
    {result, _, db} = D.run(Graph.handle("host.actions", %{"outcome" => outcome}, pending), db)

    assert result["coverage"]["store"]["reads_used"] ===
             Enum.count(db.requests, &(&1["op"] in ~w(state.get state.scan))) - prior_reads

    assert pending.ctx.checked["coverage"]["reads_used"] < 512
  end

  test "no-selection query retains one ordinary fact-validation pass" do
    {graph, db} = I.seed()
    1 = :erlang.trace_pattern({Evidence, :validate_facts, 3}, true, [:call_count])

    try do
      {result, _, _} = I.query(graph, db, "Cedar")
      assert result["status"] === "ok"
      assert {:call_count, 1} = :erlang.trace_info({Evidence, :validate_facts, 3}, :call_count)
    after
      :erlang.trace_pattern({Evidence, :validate_facts, 3}, false, [:call_count])
    end
  end

  test "maximum legal Unicode entity retains its expanded lowercase comparison form" do
    {graph, db} = D.initial()
    entity = String.duplicate("İ", 128)
    assert byte_size(entity) === 256 and byte_size(String.downcase(entity)) === 384
    fact_quote = entity <> " uses Blue."
    alias_quote = "Aspen names " <> entity <> "."
    {_, graph, db} = D.source(graph, db, fact_quote <> " " <> alias_quote)

    {captured, graph, db} =
      D.invoke(
        graph,
        db,
        "capture",
        D.args([D.relation(%{"subject" => entity, "quote" => fact_quote})])
      )

    assert captured["status"] === "ok"
    args = I.alias_args() |> Map.merge(%{"to" => entity, "quote" => alias_quote})
    {aliased, graph, db} = I.identity(graph, db, args)
    assert aliased["status"] === "ok"
    {query, _, _} = I.query(graph, db, "Aspen")
    assert query["status"] === "ok"
    assert [%{"subject" => ^entity, "basis" => [%{"quote" => ^fact_quote}]}] = query["claims"]
  end
end

defmodule GraphNamespaceRaceTest do
  use ExUnit.Case, async: false
  alias CaptureDriver, as: D
  alias GraphIdentityDriver, as: I
  alias IpseKnowledge.Graph
  alias Ipse.Development.Fixtures.Knowledge, as: F

  defp pending(graph, db) do
    args = %{
      "store" => "notes",
      "entity" => "Cedar",
      "depth" => 1,
      "max_nodes" => 128,
      "max_edges" => 256,
      "top_k" => 10,
      "as_of_ms" => nil
    }

    I.until(
      Graph.handle("invoke.tool", %{"id" => "query", "arguments" => args}, graph),
      db,
      &(&1["op"] === "state.get")
    )
  end

  test "namespace changes after selection refuse for empty, populated, and identity snapshots" do
    for kind <- [:empty, :populated, :identity] do
      {graph, db} = if kind == :empty, do: D.initial(), else: I.seed()

      {graph, db} =
        if kind == :identity do
          {res, graph, db} = I.identity(graph, db, I.alias_args())
          assert res["status"] == "ok"
          {graph, db}
        else
          {graph, db}
        end

      {request, cont, db} = pending(graph, db)
      {outcome, _} = F.host(db, request)
      {ok, _, _} = D.run(Graph.handle("host.actions", %{"outcome" => outcome}, cont), db)
      assert ok["status"] in ["ok", "abstain"]

      args = %{
        "store" => "notes",
        "action" => "put",
        "args" => %{
          "source_id" => "new-source",
          "generation" => 1,
          "expected_revision" => 0,
          "title" => "New",
          "text" => "Cedar uses Red.",
          "uri" => "provided:new",
          "observed_at_ms" => 1,
          "event_at_ms" => nil,
          "expires_at_ms" => nil
        }
      }

      {put, _, changed} =
        D.run(Graph.handle("invoke.command", %{"id" => "source", "arguments" => args}, graph), db)

      assert put["status"] == "ok"
      before = changed.records
      {outcome, changed} = F.host(changed, request)

      {result, _, after_db} =
        D.run(Graph.handle("host.actions", %{"outcome" => outcome}, cont), changed)

      assert result["status"] == "conflict"
      assert result["claims"] == [] and result["evidence"] == []
      assert after_db.records == before
    end
  end

  test "new selector or unrelated State write conflicts; unchanged snapshots still return" do
    for kind <- [:selector, :unrelated], historical <- [false, true] do
      {graph, db} = I.seed()

      args = %{
        "store" => "notes",
        "entity" => "Cedar",
        "depth" => 1,
        "max_nodes" => 128,
        "max_edges" => 256,
        "top_k" => 10,
        "as_of_ms" => if(historical, do: 1, else: nil)
      }

      {request, cont, db} =
        I.until(
          Graph.handle("invoke.tool", %{"id" => "query", "arguments" => args}, graph),
          db,
          &(&1["op"] === "state.get")
        )

      {outcome, _} = F.host(db, request)
      {ok, _, _} = D.run(Graph.handle("host.actions", %{"outcome" => outcome}, cont), db)
      assert ok["status"] in ["ok", "abstain"]

      key =
        if kind == :selector,
          do: IpseKnowledge.Store.fetch_origin_key("notes", "web", "fixture:release"),
          else: "unrelated-setting"

      digest = IpseKnowledge.Evidence.sha256("body")

      value =
        if kind == :selector do
          %{
            "format" => 1,
            "kind" => "fetch_origin",
            "partition" => "notes",
            "source_key" => key,
            "source_id" => "research.provided:" <> digest,
            "generation" => 1,
            "state" => "active",
            "content_sha256" => digest,
            "binding" => "web",
            "requested_uri" => "fixture:release",
            "observed_uri" => "fixture:release",
            "observed_at_ms" => 1,
            "capture_sha256" => digest
          }
        else
          %{"unrelated" => true}
        end

      {written, changed} =
        F.host(db, %{
          "op" => "state.put",
          "scope" => "project",
          "key" => key,
          "expected_revision" => 0,
          "value" => value
        })

      assert written["status"] == "ok"
      before = changed.records
      {outcome, changed} = F.host(changed, request)

      {result, _, final} =
        D.run(Graph.handle("host.actions", %{"outcome" => outcome}, cont), changed)

      assert result["status"] == "conflict"
      assert result["claims"] == [] and result["evidence"] == [] and final.records == before
    end
  end
end

result = ExUnit.run()
passed = result.total == 34 and result.failures == 0 and result.skipped == 0 and result.excluded == 0
if passed, do: IO.puts("graph_identity_protocol=pass")
System.halt(if(passed, do: 0, else: 1))
