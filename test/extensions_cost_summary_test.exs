Code.require_file("../priv/cost-report-demo.exs", __DIR__)

defmodule Ipse.Usage.CostSummaryTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Usage, Journal}
  alias Ipse.Usage.CostSummary
  alias Ipse.Extensions.Actions
  alias Ipse.Extensions.Catalog
  alias Ipse.Extensions.Invocation

  defp record(
         session,
         provider \\ :openai,
         raw \\ %{"input_tokens" => 100, "output_tokens" => 20}
       ) do
    admission =
      Usage.admission(session, %{provider: provider, model: "cost-fixture"}, "model", Usage.id())

    finished = Usage.completion(admission, {:ok, %{}, raw}, 1, nil)
    {:ok, ledger} = Usage.restore([%{"metadata" => %{"usage_version" => 1}}, admission, finished])
    Usage.request_record(ledger.requests[admission["request_id"]])
  end

  defp summarize(records, card \\ Ipse.CostReportDemo.card(), legacy \\ false) do
    {:ok, accumulator} = CostSummary.new(card)

    accumulator =
      Enum.reduce(records, accumulator, fn r, acc ->
        {:ok, next} = CostSummary.put(acc, r)
        next
      end)

    count = length(Enum.uniq_by(records, &{&1["session_id"], &1["request_id"], &1["attempt_id"]}))
    session = if records == [], do: Usage.id(), else: hd(records)["session_id"]

    snapshot = %{
      "request_count" => count,
      "legacy_unmetered" => legacy,
      "source" => %{"session_id" => session}
    }

    {CostSummary.report(accumulator, snapshot, true), accumulator, snapshot}
  end

  test "canonical replacements and repeated pages do not double-count cumulative records" do
    first =
      record(Usage.id())
      |> Map.merge(%{"outcome" => "unknown", "finality" => "partial", "duration_ms" => nil})

    latest = %{first | "outcome" => "completed", "finality" => "final", "duration_ms" => 1}

    latest =
      put_in(
        latest,
        ["usage"],
        Ipse.Usage.Normalizer.normalize(:openai, %{"input_tokens" => 100, "output_tokens" => 40})
      )

    {report, acc, _} = summarize([first, latest, latest])
    assert report["request_count"] == 1
    assert report["enumeration_complete"] and report["cost_estimate_complete"]
    assert [%{"amount_nanos" => 600_000, "counts" => counts}] = report["groups"]
    assert counts["input_tokens"]["total"] == 100
    assert counts["output_tokens"]["total"] == 40
    assert counts["total_tokens"]["total"] == 140

    assert {:error, :invalid_summary_request} =
             CostSummary.put(acc, %{latest | "model" => "changed-admission"})
  end

  test "partial and unmetered scopes retain known subtotals without claiming complete costs" do
    session = Usage.id()
    final = record(session)

    partial =
      record(session)
      |> Map.merge(%{"outcome" => "unknown", "finality" => "partial", "duration_ms" => nil})

    missing = record(session, :openai, %{})
    {report, _, _} = summarize([final, partial, missing])
    refute report["cost_estimate_complete"]

    assert [
             %{
               "amount_nanos" => nil,
               "known_amount_nanos" => 800_000,
               "counts" => counts,
               "unknown_outcome_count" => 1,
               "unknown_cost_count" => 2
             }
           ] = report["groups"]

    assert counts["input_tokens"] == %{
             "total" => nil,
             "known_subtotal" => 200,
             "unknown_count" => 1,
             "overflow" => false
           }

    {legacy, _, _} = summarize([final], Ipse.CostReportDemo.card(), true)
    assert legacy["enumeration_complete"]
    refute legacy["cost_estimate_complete"]
  end

  test "separate billing bases and missing rates do not become one monetary total" do
    session = Usage.id()

    {report, _, _} =
      summarize([record(session), record(session, :chatgpt), record(session, :ollama)])

    assert length(report["groups"]) == 3
    refute report["cost_estimate_complete"]
    refute Map.has_key?(report, "amount_nanos")
    assert Enum.count(report["groups"], &is_nil(&1["amount_nanos"])) == 2
  end

  test "integer overflow is explicit in costs and independent token dimensions" do
    card = Ipse.CostReportDemo.card()
    [row] = card["rows"]

    expensive = %{
      card
      | "rows" => [%{row | "rates" => %{"input" => "999999999", "output" => "0"}}]
    }

    session = Usage.id()

    {report, _, _} =
      summarize(
        for(
          _ <- 1..2,
          do: record(session, :openai, %{"input_tokens" => 5000, "output_tokens" => 0})
        ),
        expensive
      )

    assert [%{"overflow" => true, "amount_nanos" => nil, "known_amount_nanos" => nil}] =
             report["groups"]

    {single, _, _} =
      summarize(
        [record(session, :openai, %{"input_tokens" => 1_000_000, "output_tokens" => 0})],
        expensive
      )

    assert [%{"overflow" => true, "amount_nanos" => nil}] = single["groups"]

    records =
      for _ <- 1..9010,
          do: record(session, :openai, %{"input_tokens" => 999_999_999_999, "output_tokens" => 0})

    {report, _, _} = summarize(records, %{card | "rows" => []})
    assert [%{"counts" => counts}] = report["groups"]
    assert counts["input_tokens"]["overflow"]
    assert counts["input_tokens"]["total"] == nil
    assert counts["input_tokens"]["known_subtotal"] == nil
    assert counts["output_tokens"]["total"] == 0
  end

  test "missing pages and foreign sessions cannot produce a complete own-session scope" do
    {_, accumulator, snapshot} = summarize([record(Usage.id())])

    refute CostSummary.report(accumulator, %{snapshot | "request_count" => 2}, true)[
             "enumeration_complete"
           ]

    refute CostSummary.report(accumulator, snapshot, false)["cost_estimate_complete"]

    refute CostSummary.report(
             accumulator,
             put_in(snapshot, ["source", "session_id"], Usage.id()),
             true
           )["enumeration_complete"]

    {empty, _, _} = summarize([])
    assert empty["request_count"] == 0 and empty["groups"] == []
  end

  @tag timeout: 90_000
  test "actual worker summarizes beyond 16 pages and idle resume uses cached receipts" do
    root = Path.join(System.tmp_dir!(), "ipse-cost-summary-#{Usage.id()}")
    File.mkdir_p!(root)

    config =
      Ipse.CostReportDemo.config(
        Path.join(root, "home"),
        true,
        Ipse.CostReportDemo.card(),
        :summary
      )

    dir = Path.join(root, "sessions")
    opts = [config: config, cwd: root, state_dir: dir, subscriber: self(), owner: self()]

    try do
      disabled =
        Ipse.CostReportDemo.config(
          Path.join(root, "disabled"),
          false,
          Ipse.CostReportDemo.card(),
          :summary
        )

      assert disabled.extensions == []

      {:ok, inactive} =
        DynamicSupervisor.start_child(
          Ipse.Sessions,
          {Session, Keyword.put(opts, :config, disabled)}
        )

      assert Session.exports(inactive)["entries"] == []
      :ok = Session.close(inactive)
      refute File.exists?(Path.join(root, "disabled"))
      {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts})

      for n <- 1..70 do
        :ok = Session.prompt(pid, "Synthetic summary request #{n}")
        assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
      end

      :ok = Session.invoke_export(pid, :command, "ext__costs__summary", %{})
      assert_receive {:ipse, ^pid, {:done, :ok}}, 30_000
      value = Session.info(pid).extension_result["value"]
      assert value["status"] == "summarized"
      assert value["request_count"] == 70 and value["enumeration_complete"]
      assert [%{"amount_nanos" => 28_000_000, "counts" => counts}] = value["groups"]
      assert counts["input_tokens"]["total"] == 7000
      assert counts["output_tokens"]["total"] == 1400
      assert value["cost_estimate_complete"]
      id = Session.info(pid).id
      :ok = Session.close(pid)
      {:ok, events} = Journal.load(dir, id)
      reads = Enum.filter(events, &(&1["type"] == "extension_action_result"))
      assert length(reads) == 18
      assert Enum.all?(reads, &(&1["request"]["op"] == "usage.read"))
      assert {:ok, _} = Actions.restore(events)
      path = Path.join(dir, id <> ".jsonl")
      before = File.read!(path)

      {:ok, resumed} =
        DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts ++ [id: id]})

      assert Session.info(resumed).extension_result["value"] == value
      assert File.read!(path) == before
      :ok = Session.close(resumed)
    after
      File.rm_rf!(root)
    end
  end

  test "bulk read capability preserves ordinary action bounds and requires its parent grants" do
    config =
      Ipse.CostReportDemo.config("/synthetic/home", true, Ipse.CostReportDemo.card(), :summary)

    [entry] = config.extensions
    {:ok, snapshot} = Catalog.snapshot(config)
    descriptor = hd(snapshot["entries"])

    parent =
      Invocation.intent(
        entry.identity,
        descriptor,
        %{},
        Usage.id(),
        Usage.id(),
        nil,
        nil,
        "operator_request"
      )

    read = %{"op" => "usage.read", "cursor" => 0, "limit" => 4, "snapshot" => nil}
    assert {:ok, _} = Actions.intent(parent, read, 17, "not_required", "/synthetic")
    assert {:ok, _} = Actions.intent(parent, read, 10_000, "not_required", "/synthetic")
    assert {:error, _} = Actions.intent(parent, read, 10_001, "not_required", "/synthetic")

    writer = update_in(parent, ["identity", "capabilities"], &(&1 ++ ["host.state.write"]))

    write = %{
      "op" => "state.put",
      "scope" => "session",
      "key" => "fact",
      "expected_revision" => 0,
      "value" => %{}
    }

    assert {:ok, _} = Actions.intent(writer, write, 16, "approved", "/synthetic")
    assert {:error, _} = Actions.intent(writer, write, 17, "approved", "/synthetic")

    ordinary =
      update_in(parent, ["identity", "capabilities"], &List.delete(&1, "host.usage.scan"))

    assert {:error, :invalid_extension_action} =
             Actions.intent(ordinary, read, 17, "not_required", "/synthetic")

    assert {:error, _} =
             Catalog.validate(Catalog.empty(), ~w(invoke.command host.actions host.usage.scan))

    assert {:error, _} =
             Catalog.validate(Catalog.empty(), ~w(invoke.command host.usage host.usage.scan))
  end
end
