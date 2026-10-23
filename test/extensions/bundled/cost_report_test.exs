Code.require_file("../../../priv/demo/usage.exs", __DIR__)

defmodule Ipse.Extension.CostReportTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Usage}
  alias Ipse.Builtins.CostReport

  test "the shipped cost report works through actual Session callbacks with synthetic accounting" do
    assert :ok = Ipse.UsageDemo.run_costs()
  end

  defp record(provider, id, raw) do
    a = Usage.admission(id, %{provider: provider, model: "cost-fixture"}, "model", Usage.id())
    finished = Usage.completion(a, {:ok, %{}, raw}, 1, nil)
    {:ok, ledger} = Usage.restore([%{"metadata" => %{"usage_version" => 1}}, a, finished])
    Usage.request_record(ledger.requests[a["request_id"]])
  end

  test "reports keep API estimates and subscription equivalents in separate groups" do
    card = Ipse.UsageDemo.card()
    [row] = card["rows"]

    card =
      Map.put(card, "rows", [
        row,
        %{
          row
          | "id" => "subscription",
            "provider" => "chatgpt",
            "billing_mode" => "subscription",
            "basis" => "api_equivalent"
        }
      ])

    id = Usage.id()

    requests =
      for provider <- [:openai, :chatgpt],
          do: record(provider, id, %{"input_tokens" => 100, "output_tokens" => 20})

    assert {:ok, report} =
             CostReport.report(card, %{
               "requests" => requests,
               "cursor" => 0,
               "next" => nil,
               "snapshot" => %{}
             })

    assert length(report["groups"]) == 2
    assert Enum.sort(Enum.map(report["groups"], & &1["basis"])) == ~w(api_equivalent api_estimate)
    assert Enum.all?(report["groups"], &(&1["amount_nanos"] == 400_000))
    assert report["coverage"] == "page"
  end

  test "missing rates and partial work never produce a complete group total" do
    id = Usage.id()
    r = record(:openai, id, %{})

    assert {:ok, report} =
             CostReport.report(Ipse.UsageDemo.card(), %{
               "requests" => [r],
               "cursor" => 0,
               "next" => nil,
               "snapshot" => %{}
             })

    assert [%{"amount_nanos" => nil, "known_amount_nanos" => nil, "unknown_cost_count" => 1}] =
             report["groups"]

    r =
      record(:openai, id, %{"input_tokens" => 100, "output_tokens" => 20})
      |> Map.merge(%{"outcome" => "cancelled", "finality" => "partial"})

    assert {:ok, report} =
             CostReport.report(Ipse.UsageDemo.card(), %{
               "requests" => [r],
               "cursor" => 0,
               "next" => nil,
               "snapshot" => %{}
             })

    assert [%{"amount_nanos" => nil, "known_amount_nanos" => 400_000, "unknown_cost_count" => 1}] =
             report["groups"]
  end

  test "overflow in a sum remains explicit even when individual estimates fit" do
    card = Ipse.UsageDemo.card()
    [row] = card["rows"]
    card = Map.put(card, "rows", [%{row | "rates" => %{"input" => "999999999", "output" => "0"}}])
    id = Usage.id()

    requests =
      for _ <- 1..2, do: record(:openai, id, %{"input_tokens" => 5000, "output_tokens" => 0})

    assert {:ok, report} =
             CostReport.report(card, %{
               "requests" => requests,
               "cursor" => 0,
               "next" => nil,
               "snapshot" => %{}
             })

    assert [%{"overflow" => true, "amount_nanos" => nil, "known_amount_nanos" => nil}] =
             report["groups"]

    assert Enum.all?(report["requests"], &is_integer(&1["estimate"]["amount_nanos"]))
  end

  test "invalid semantic rate cards produce a known operator result", do: assert_invalid_card()

  defp assert_invalid_card do
    root = Path.join(System.tmp_dir!(), "ipse-invalid-cost-card-#{Usage.id()}")
    File.mkdir_p!(root)

    try do
      card = Map.put(Ipse.UsageDemo.card(), "published_on", "not-a-date")
      cfg = Ipse.UsageDemo.config(Path.join(root, "home"), true, card)

      {:ok, pid} =
        DynamicSupervisor.start_child(
          Ipse.Sessions,
          {Session,
           config: cfg,
           cwd: root,
           state_dir: Path.join(root, "sessions"),
           subscriber: self(),
           owner: self()}
        )

      :ok = Session.invoke_export(pid, :command, "ext__costs__report", %{})
      assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
      assert Session.info(pid).extension_result["value"]["status"] == "invalid_rate_card"
      :ok = Session.close(pid)
    after
      File.rm_rf!(root)
    end
  end
end
