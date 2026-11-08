ExUnit.start(autorun: false, seed: 1701)

for file <- ~w(evidence profiles adapters store/state store/mcp_cas store),
    do: Code.require_file("extensions/knowledge/src/" <> file <> ".ex")

Code.require_file("extensions/knowledge/src/graph.ex")
Code.require_file("dev/fixtures/knowledge.exs")

defmodule GraphWallClock do
  def now do
    case Process.get(:graph_wall) do
      [value | rest] ->
        Process.put(:graph_wall, rest)
        value

      [] ->
        raise "graph wall clock exhausted"
    end
  end
end

File.read!("extensions/knowledge/src/graph.ex")
|> String.replace("defmodule IpseKnowledge.Graph do", "defmodule WallTimedGraph do")
|> String.replace("System.system_time(:millisecond)", "GraphWallClock.now()")
|> Code.compile_string("graph-wall-clock-test.ex")

mcp_source =
  File.read!("extensions/knowledge/src/graph.ex")
  |> String.replace(~s(@preset "state-explicit"), ~s(@preset "mcp-explicit"))

mcp_source
|> String.replace("defmodule IpseKnowledge.Graph do", "defmodule FakeMCPGraph do")
|> Code.compile_string("graph-fake-mcp-test.ex")

mcp_source
|> String.replace("defmodule IpseKnowledge.Graph do", "defmodule WallTimedMCPGraph do")
|> String.replace("System.system_time(:millisecond)", "GraphWallClock.now()")
|> Code.compile_string("graph-fake-mcp-clock-test.ex")

defmodule GraphResultTimeTest do
  use ExUnit.Case, async: false
  alias IpseKnowledge.{Evidence, Graph}
  alias Ipse.Development.Fixtures.Knowledge, as: F

  defp run({:ok, %{"kind" => "host_call", "request" => request}, graph}, db) do
    {outcome, db} = F.host(db, request)
    run(Graph.handle("host.actions", %{"outcome" => outcome}, graph), db)
  end

  defp run({:ok, %{"kind" => "result", "value" => value}, graph}, db),
    do: {value, graph, db}

  defp until_identity({:ok, %{"kind" => "host_call", "request" => request}, graph}, db) do
    if graph.phase === :query_identity_revalidate do
      {outcome, db} = F.host(db, request)
      {graph, outcome, db}
    else
      {outcome, db} = F.host(db, request)
      until_identity(Graph.handle("host.actions", %{"outcome" => outcome}, graph), db)
    end
  end

  defp fixture(count, expires, extra_relations \\ []) do
    options = Map.new(~w(stores search fetch retrieval embedding rerank extraction), &{&1, %{}})

    options =
      options
      |> Map.put("version", 1)
      |> Map.put("stores", %{
        "notes" => %{"kind" => "state", "scope" => "project", "partition" => "notes"}
      })
      |> Map.put("extraction", %{"given" => %{"kind" => "explicit", "version" => 1}})

    {:ok, graph} = Graph.init(options)
    quote = "Cedar uses Blue " <> String.duplicate("x", 980) <> "."
    quotes = List.duplicate(quote, count)
    text = quote

    source = %{
      "store" => "notes",
      "action" => "put",
      "args" => %{
        "source_id" => "fixture",
        "generation" => 1,
        "expected_revision" => 0,
        "title" => "Evidence",
        "text" => text,
        "uri" => "provided:fixture",
        "observed_at_ms" => 1,
        "event_at_ms" => nil,
        "expires_at_ms" => expires
      }
    }

    {saved, graph, db} =
      run(
        Graph.handle("invoke.command", %{"id" => "source", "arguments" => source}, graph),
        F.new()
      )

    assert saved["status"] === "ok"

    relations =
      Enum.with_index(quotes, 1)
      |> Enum.map(fn {quote, n} ->
        %{
          "subject" => "Cedar",
          "predicate" => "uses",
          "object" => "item#{n}",
          "polarity" => "positive",
          "inferred" => false,
          "valid_from_ms" => nil,
          "valid_to_ms" => nil,
          "quote" => quote
        }
      end)

    args = %{
      "store" => "notes",
      "extraction" => "given",
      "source_id" => "fixture",
      "generation" => 1,
      "relations" => relations ++ extra_relations
    }

    {captured, graph, db} =
      run(Graph.handle("invoke.tool", %{"id" => "capture", "arguments" => args}, graph), db)

    assert captured["status"] === "ok", inspect(captured)
    {graph, db}
  end

  defp add_never_current(graph, db, observed, expires, historical) do
    args = %{
      "store" => "notes",
      "action" => "put",
      "args" => %{
        "source_id" => "never",
        "generation" => 1,
        "expected_revision" => 0,
        "title" => "Never current",
        "text" => "Other evidence.",
        "uri" => "provided:never",
        "observed_at_ms" => observed,
        "event_at_ms" => nil,
        "expires_at_ms" => expires
      }
    }

    {saved, graph, db} =
      run(Graph.handle("invoke.command", %{"id" => "source", "arguments" => args}, graph), db)

    assert saved["status"] === "ok"
    key = IpseKnowledge.Store.root_key("notes", Evidence.sha256("never"))

    db =
      if historical, do: put_in(db.records[key]["value"]["origin"]["historical"], true), else: db

    {graph, db}
  end

  defp pending(graph, db, as_of) do
    args = %{
      "store" => "notes",
      "entity" => "Cedar",
      "depth" => 1,
      "max_nodes" => 128,
      "max_edges" => 256,
      "top_k" => 10,
      "as_of_ms" => as_of
    }

    until_identity(
      Graph.handle("invoke.tool", %{"id" => "query", "arguments" => args}, graph),
      db
    )
  end

  defp mcp_run({:ok, %{"kind" => "host_call", "request" => request}, graph}, db) do
    {outcome, db} = F.host(db, request)
    mcp_run(FakeMCPGraph.handle("host.actions", %{"outcome" => outcome}, graph), db)
  end

  defp mcp_run({:ok, %{"kind" => "result", "value" => value}, graph}, db),
    do: {value, graph, db}

  defp mcp_until_revalidation({:ok, %{"kind" => "host_call", "request" => request}, graph}, db) do
    if graph.phase === :query_revalidate do
      {request, graph, db}
    else
      {outcome, db} = F.host(db, request)

      mcp_until_revalidation(
        FakeMCPGraph.handle("host.actions", %{"outcome" => outcome}, graph),
        db
      )
    end
  end

  defp mcp_clock_run({:ok, %{"kind" => "host_call", "request" => request}, graph}, db) do
    {outcome, db} = F.host(db, request)
    mcp_clock_run(WallTimedMCPGraph.handle("host.actions", %{"outcome" => outcome}, graph), db)
  end

  defp mcp_clock_run({:ok, %{"kind" => "result", "value" => value}, graph}, db),
    do: {value, graph, db}

  test "current result is withheld when expiry crosses during preparation" do
    expiry = System.system_time(:millisecond) + 60_000
    {graph, db} = fixture(1, expiry)
    {pending, outcome, _} = pending(graph, db, nil)
    assert pending.ctx.next_query_transition === expiry
    Process.put(:graph_wall, [expiry - 1, expiry])

    assert {:ok, %{"kind" => "result", "value" => refusal}, after_state} =
             WallTimedGraph.handle("host.actions", %{"outcome" => outcome}, pending)

    assert refusal["status"] === "refused"
    assert refusal["gaps"] === [%{"code" => "query_time_changed"}]
    assert refusal["evidence"] === [] and refusal["claims"] === []
    assert after_state.phase === :idle and Process.get(:graph_wall) === []

    Process.put(:graph_wall, [expiry - 1, expiry - 1])

    assert {:ok, %{"value" => result}, _} =
             WallTimedGraph.handle("host.actions", %{"outcome" => outcome}, pending)

    assert result["status"] === "ok" and result["claims"] != []

    Process.put(:graph_wall, [expiry - 1, pending.ctx.as_of_ms - 1])

    assert {:ok, %{"value" => rollback}, _} =
             WallTimedGraph.handle("host.actions", %{"outcome" => outcome}, pending)

    assert rollback["gaps"] === [%{"code" => "query_time_changed"}]
    assert rollback["evidence"] === [] and rollback["claims"] === []

    Process.put(:graph_wall, [expiry - 1, expiry - 2])

    assert {:ok, %{"value" => sampled_rollback}, _} =
             WallTimedGraph.handle("host.actions", %{"outcome" => outcome}, pending)

    assert sampled_rollback["gaps"] === [%{"code" => "query_time_changed"}]
    assert sampled_rollback["evidence"] === [] and sampled_rollback["claims"] === []

    Process.put(:graph_wall, [expiry])

    assert {:ok, %{"value" => already_expired}, _} =
             WallTimedGraph.handle("host.actions", %{"outcome" => outcome}, pending)

    assert already_expired["gaps"] === [%{"code" => "query_time_changed"}]
    assert Process.get(:graph_wall) === []
  end

  test "a previously excluded fact activating during preparation withholds the result" do
    activation = System.system_time(:millisecond) + 60_000
    quote = "Cedar uses Blue " <> String.duplicate("x", 980) <> "."

    future_fact = %{
      "subject" => "Cedar",
      "predicate" => "uses",
      "object" => "Future",
      "polarity" => "positive",
      "inferred" => false,
      "valid_from_ms" => activation,
      "valid_to_ms" => nil,
      "quote" => quote
    }

    {graph, db} = fixture(1, nil, [future_fact])
    {pending, outcome, _} = pending(graph, db, nil)
    assert pending.ctx.next_query_transition === activation
    Process.put(:graph_wall, [activation - 1, activation])

    assert {:ok, %{"value" => refusal}, _} =
             WallTimedGraph.handle("host.actions", %{"outcome" => outcome}, pending)

    assert refusal["gaps"] === [%{"code" => "query_time_changed"}]
    assert refusal["evidence"] === [] and refusal["claims"] === []
  end

  test "a current fact expiry during preparation withholds the result" do
    expiry = System.system_time(:millisecond) + 60_000
    quote = "Cedar uses Blue " <> String.duplicate("x", 980) <> "."

    expiring_fact = %{
      "subject" => "Cedar",
      "predicate" => "uses",
      "object" => "Expiring",
      "polarity" => "positive",
      "inferred" => false,
      "valid_from_ms" => nil,
      "valid_to_ms" => expiry,
      "quote" => quote
    }

    {graph, db} = fixture(1, nil, [expiring_fact])
    {pending, outcome, _} = pending(graph, db, nil)
    assert pending.ctx.next_query_transition === expiry
    Process.put(:graph_wall, [expiry - 1, expiry])

    assert {:ok, %{"value" => refusal}, _} =
             WallTimedGraph.handle("host.actions", %{"outcome" => outcome}, pending)

    assert refusal["gaps"] === [%{"code" => "query_time_changed"}]
    assert refusal["evidence"] === [] and refusal["claims"] === []
  end

  test "a previously excluded source activating during preparation withholds the result" do
    activation = System.system_time(:millisecond) + 60_000
    {graph, db} = fixture(1, nil)
    {graph, db} = add_never_current(graph, db, activation, nil, false)
    {pending, outcome, _} = pending(graph, db, nil)
    assert pending.ctx.next_query_transition === activation
    Process.put(:graph_wall, [activation - 1, activation])

    assert {:ok, %{"value" => refusal}, _} =
             WallTimedGraph.handle("host.actions", %{"outcome" => outcome}, pending)

    assert refusal["gaps"] === [%{"code" => "query_time_changed"}]
    assert refusal["evidence"] === [] and refusal["claims"] === []
  end

  test "explicit historical time keeps its selection after wall-clock expiry" do
    expiry = System.system_time(:millisecond) + 60_000
    {graph, db} = fixture(1, expiry)
    {pending, outcome, _} = pending(graph, db, expiry - 1)
    Process.put(:graph_wall, [])

    assert {:ok, %{"value" => result}, _} =
             WallTimedGraph.handle("host.actions", %{"outcome" => outcome}, pending)

    assert result["status"] === "ok" and result["claims"] != []
    assert Process.get(:graph_wall) === []
  end

  test "never-current sources and empty fact intervals do not create false deadlines" do
    now = System.system_time(:millisecond)
    expiry = now + 60_000
    quote = "Cedar uses Blue " <> String.duplicate("x", 980) <> "."

    empty_fact = %{
      "subject" => "Birch",
      "predicate" => "uses",
      "object" => "Gold",
      "polarity" => "positive",
      "inferred" => false,
      "valid_from_ms" => now + 10_000,
      "valid_to_ms" => now + 10_000,
      "quote" => quote
    }

    for {observed, expires, historical} <- [
          {now + 20_000, now + 10_000, false},
          {now + 20_000, now + 20_000, false},
          {now + 20_000, nil, true}
        ] do
      {graph, db} = fixture(1, expiry, [empty_fact])
      {graph, db} = add_never_current(graph, db, observed, expires, historical)
      {pending, outcome, _} = pending(graph, db, nil)
      assert pending.ctx.next_query_transition === expiry
      Process.put(:graph_wall, [now + 30_000, now + 30_000])

      assert {:ok, %{"value" => result}, _} =
               WallTimedGraph.handle("host.actions", %{"outcome" => outcome}, pending)

      assert result["status"] === "ok" and result["claims"] != []
    end
  end

  test "a prepared paged result is discarded after an expiry" do
    expiry = System.system_time(:millisecond) + 60_000
    {graph, db} = fixture(8, expiry)
    {pending, outcome, _} = pending(graph, db, nil)
    Process.put(:graph_wall, [expiry - 1, expiry - 1])

    assert {:ok, %Ipse.Extension.ResultPublication.Output{} = paged, _} =
             WallTimedGraph.handle("host.actions", %{"outcome" => outcome}, pending)

    assert paged.byte_count > 12_000
    assert length(JSON.decode!(paged.bytes)["claims"]) === 8
    Process.put(:graph_wall, [expiry - 1, expiry])

    assert {:ok, %{"kind" => "result", "value" => refusal}, _} =
             WallTimedGraph.handle("host.actions", %{"outcome" => outcome}, pending)

    assert refusal["status"] === "refused"
    assert refusal["gaps"] === [%{"code" => "query_time_changed"}]
    assert refusal["evidence"] === [] and refusal["claims"] === []
  end

  test "fake MCP revalidation withholds an expiry crossed during result preparation" do
    expiry = System.system_time(:millisecond) + 60_000
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

    {:ok, graph} = FakeMCPGraph.init(options)

    source = %{
      "store" => "notes",
      "action" => "put",
      "args" => %{
        "source_id" => "mcp-source",
        "generation" => 1,
        "expected_revision" => 0,
        "title" => "Evidence",
        "text" => "Cedar uses Blue.",
        "uri" => "provided:fixture",
        "observed_at_ms" => 1,
        "event_at_ms" => nil,
        "expires_at_ms" => expiry
      }
    }

    {saved, graph, db} =
      mcp_run(
        FakeMCPGraph.handle("invoke.command", %{"id" => "source", "arguments" => source}, graph),
        F.new()
      )

    assert saved["status"] === "ok"

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
      mcp_until_revalidation(
        FakeMCPGraph.handle("invoke.tool", %{"id" => "query", "arguments" => query}, graph),
        db
      )

    assert pending.ctx.next_query_transition === expiry
    {outcome, db} = F.host(db, request)
    Process.put(:graph_wall, [expiry - 1, expiry])

    {refusal, after_state, _} =
      mcp_clock_run(
        WallTimedMCPGraph.handle("host.actions", %{"outcome" => outcome}, pending),
        db
      )

    assert refusal["status"] === "refused" and
             refusal["gaps"] === [%{"code" => "query_time_changed"}]

    assert refusal["evidence"] === [] and refusal["claims"] === []
    assert after_state.phase === :idle and Process.get(:graph_wall) === []
  end
end

result = ExUnit.run()

if result.total == 8 and result.failures == 0 and result.skipped == 0 and result.excluded == 0,
  do: IO.puts("graph_result_time=pass")

System.halt(
  if(result.total == 8 and result.failures == 0 and result.skipped == 0 and result.excluded == 0,
    do: 0,
    else: 1
  )
)
