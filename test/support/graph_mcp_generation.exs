ExUnit.start(autorun: false, seed: 7124)

for file <- ~w(evidence profiles adapters store/state store/mcp_cas store),
    do: Code.require_file("extensions/knowledge/src/" <> file <> ".ex")

graph =
  File.read!("extensions/knowledge/src/graph.ex")
  |> String.replace(~s(@preset "state-explicit"), ~s(@preset "mcp-explicit"))

Code.compile_string(graph, "graph-mcp-test.ex")
Code.require_file("dev/fixtures/knowledge.exs")

defmodule MCPGenerationProbe do
  use ExUnit.Case, async: false
  alias IpseKnowledge.Graph
  alias Ipse.Development.Fixtures.Knowledge, as: F

  def initial do
    options = Map.new(~w(stores search fetch retrieval embedding rerank extraction), &{&1, %{}})

    options =
      options
      |> Map.put("version", 1)
      |> Map.put("stores", %{
        "notes" => %{
          "kind" => "mcp_cas",
          "binding" => "storage",
          "partition" => "notes",
          "contract" => "ipse-cas-v3"
        }
      })
      |> Map.put("extraction", %{"given" => %{"kind" => "explicit", "version" => 1}})

    {:ok, graph} = Graph.init(options)
    refute Map.has_key?(graph, :invalid)
    {graph, F.new()}
  end

  def run({:ok, %{"kind" => "host_call", "request" => request}, graph}, db) do
    {outcome, db} = F.host(db, request)
    run(Graph.handle("host.actions", %{"outcome" => outcome}, graph), db)
  end

  def run({:ok, %{"kind" => "result", "value" => value}, graph}, db), do: {value, graph, db}
  def run({:ok, %{bytes: bytes}, graph}, db), do: {JSON.decode!(bytes), graph, db}

  def until({:ok, %{"kind" => "host_call", "request" => request}, graph}, db, wanted) do
    if graph.phase === wanted,
      do: {request, graph, db},
      else:
        (
          {outcome, db} = F.host(db, request)
          until(Graph.handle("host.actions", %{"outcome" => outcome}, graph), db, wanted)
        )
  end

  def query(graph),
    do:
      Graph.handle(
        "invoke.tool",
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

  def insert(graph, db, id \\ "source-one") do
    args = %{
      "store" => "notes",
      "action" => "put",
      "args" => %{
        "source_id" => id,
        "generation" => 1,
        "expected_revision" => 0,
        "title" => "Example",
        "text" => "Cedar uses Blue.",
        "uri" => "provided:example",
        "observed_at_ms" => 1,
        "event_at_ms" => nil,
        "expires_at_ms" => nil
      }
    }

    run(Graph.handle("invoke.command", %{"id" => "source", "arguments" => args}, graph), db)
  end

  test "empty snapshot probes generation and refuses an inserted root" do
    {graph, db} = initial()
    {request, pending, db} = until(query(graph), db, :query_mcp_empty_probe)
    assert request["op"] === "mcp.call"
    assert request["arguments"]["action"] === "get_many"

    assert request["arguments"]["args"]["keys"] === [
             IpseKnowledge.Evidence.graph_identity_key("notes")
           ]

    {outcome, unchanged} = F.host(db, request)
    before = unchanged.requests

    {result, _, after_db} =
      run(Graph.handle("host.actions", %{"outcome" => outcome}, pending), unchanged)

    assert result["status"] === "abstain"

    assert result["coverage"]["store"]["effects_used"] ===
             Enum.count(after_db.requests, &(&1["op"] === "mcp.call"))

    assert result["coverage"]["store"]["reads_used"] ===
             Enum.count(after_db.requests, &(&1["op"] === "effect.result.read"))

    assert length(after_db.requests) > length(before)
    {stored, _, changed} = insert(graph, db)
    assert stored["status"] === "ok"
    {outcome, changed} = F.host(changed, request)
    {result, _, _} = run(Graph.handle("host.actions", %{"outcome" => outcome}, pending), changed)
    assert result["status"] === "conflict" and result["evidence"] === []
  end

  test "nonempty token revalidation refuses changed generation" do
    {graph, db} = initial()
    {stored, graph, db} = insert(graph, db)
    assert stored["status"] === "ok"
    previous_calls = Enum.count(db.requests, &(&1["op"] === "mcp.call"))
    {request, pending, db} = until(query(graph), db, :query_revalidate)
    before_revalidation = Enum.count(db.requests, &(&1["op"] === "mcp.call"))
    {outcome, unchanged} = F.host(db, request)

    {result, _, after_db} =
      run(Graph.handle("host.actions", %{"outcome" => outcome}, pending), unchanged)

    assert result["status"] === "abstain"
    assert Enum.count(after_db.requests, &(&1["op"] === "mcp.call")) - before_revalidation === 1

    assert result["coverage"]["store"]["effects_used"] ===
             Enum.count(after_db.requests, &(&1["op"] === "mcp.call")) - previous_calls

    {stored, _, changed} = insert(graph, db, "source-two")
    assert stored["status"] === "ok"
    {outcome, changed} = F.host(changed, request)
    {result, _, _} = run(Graph.handle("host.actions", %{"outcome" => outcome}, pending), changed)
    assert result["status"] === "conflict" and result["claims"] === []
  end

  test "empty-snapshot preflight refuses when one further effect would exceed the cap" do
    {graph, db} = initial()
    {request, pending, db} = until(query(graph), db, :query_snapshot)
    {outcome, db} = F.host(db, request)

    {:ok, %{"kind" => "host_call", "request" => read}, pending} =
      Graph.handle("host.actions", %{"outcome" => outcome}, pending)

    assert read["op"] === "effect.result.read"
    pending = put_in(pending.cont.effects, 16)
    {outcome, db} = F.host(db, read)

    {result, _, after_db} =
      run(Graph.handle("host.actions", %{"outcome" => outcome}, pending), db)

    assert result["status"] === "refused" and result["gaps"] === [%{"code" => "effect_budget"}]
    assert Enum.count(after_db.requests, &(&1["op"] === "mcp.call")) === 1
  end

  test "unknown, denied and malformed probe outcomes withhold results without another call" do
    {graph, db} = initial()
    {_request, pending, _db} = until(query(graph), db, :query_mcp_empty_probe)

    for outcome <- [
          %{"status" => "unknown"},
          %{"status" => "denied"},
          %{"status" => "ok", "value" => %{}}
        ] do
      assert {:ok, %{"kind" => "result", "value" => result}, _} =
               Graph.handle("host.actions", %{"outcome" => outcome}, pending)

      assert result["status"] === "refused"
      assert result["claims"] === [] and result["evidence"] === []
    end
  end

  test "fragmented probe accounts every page and stops before exceeding reads" do
    {graph, db} = initial()
    {request, pending, db} = until(query(graph), db, :query_mcp_empty_probe)
    {outcome, db} = F.host(db, request)

    {:ok, %{"kind" => "host_call", "request" => read}, pending} =
      Graph.handle("host.actions", %{"outcome" => outcome}, pending)

    assert read["op"] === "effect.result.read"
    {outcome, db} = F.host(db, read)
    page = outcome["value"]
    <<first::binary-size(1), _::binary>> = page["text"]
    short = page |> Map.put("text", first) |> Map.put("next", 1) |> Map.put("complete", false)

    {:ok, %{"kind" => "host_call", "request" => next}, pending} =
      Graph.handle("host.actions", %{"outcome" => Map.put(outcome, "value", short)}, pending)

    assert next["offset"] === 1
    {outcome, db} = F.host(db, next)
    {result, _, _} = run(Graph.handle("host.actions", %{"outcome" => outcome}, pending), db)
    assert result["status"] === "abstain"

    assert result["coverage"]["store"]["reads_used"] ===
             Enum.count(db.requests, &(&1["op"] === "effect.result.read"))

    pending = put_in(pending.ctx.probe_reads, 512)
    {outcome, _} = F.host(db, next)

    result =
      Graph.handle(
        "host.actions",
        %{
          "outcome" =>
            Map.put(outcome, "value", Map.put(short, "offset", 1) |> Map.put("next", 2))
        },
        pending
      )

    assert {:ok,
            %{
              "kind" => "result",
              "value" => %{"status" => "refused", "gaps" => [%{"code" => "effect_budget"}]}
            }, _} = result
  end
end

result = ExUnit.run()
passed = result.total == 5 and result.failures == 0 and result.skipped == 0 and result.excluded == 0
if passed, do: IO.puts("graph_mcp_generation=pass")
System.halt(if(passed, do: 0, else: 1))
