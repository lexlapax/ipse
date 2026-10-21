Code.require_file("../dev/verification/cli.exs", __DIR__)
Ipse.Development.Verification.Runtime.load_fixture!(:knowledge)
Code.require_file("../examples/knowledge/evaluation_runner.exs", __DIR__)
Code.require_file("../priv/cost-report-demo.exs", __DIR__)

defmodule Ipse.KnowledgeEvaluationScheduleTest do
  use ExUnit.Case, async: false
  alias IpseKnowledgeExample.{EvaluationContract, EvaluationRunner}
  @variants ~w(lexical graph_explicit graph_model dense hybrid rerank research)

  defp plan do
    spec =
      JSON.decode!(File.read!("examples/knowledge/benchmark-spec.json"))
      |> Map.put("blind_seed", String.duplicate("b", 64))

    {:ok, plan} = EvaluationContract.build(spec)

    plan
    |> Map.put("version", 2)
    |> Map.put("model_origin", "http://127.0.0.1:21434")
    |> Map.put("search_port", 21435)
    |> Map.update!("profiles", &profiles/1)
    |> Map.update!("embedding_profiles", &profiles/1)
  end

  defp profiles(profiles) do
    Map.new(profiles, fn {name, profile} ->
      {name, Map.put(profile, "base_url", "http://127.0.0.1:21434")}
    end)
  end

  defp structured(plan) do
    budgets = Map.new(plan["variants"], &{&1["id"], &1["budget"]})

    spec =
      plan
      |> Map.drop(~w(variants answer))
      |> Map.put("budgets", budgets)
      |> Map.put("version", 3)
      |> Map.put("contracts", %{
        "outputs" => %{
          "answer" => "json_schema_v2",
          "extract" => "json_schema_v2",
          "rerank" => "json_schema_v2"
        },
        "selection" => "per_strategy_eligibility_v1"
      })

    {:ok, plan} = EvaluationContract.build(spec)
    plan
  end

  defp queries do
    for index <- 1..50 do
      %{"query_id" => "Q#{index}", "project" => if(index <= 47, do: "beta", else: "alpha")}
    end
  end

  test "a resolved plan binds every selected model profile to one explicit private origin" do
    plan = plan()
    assert :ok = EvaluationContract.validate(plan)

    for origin <- [
          "http://127.0.0.1:11434",
          "http://localhost:21434",
          "https://127.0.0.1:21434",
          "http://user@127.0.0.1:21434",
          "http://127.0.0.1:21434/",
          "http://127.0.0.1:21434?override=true",
          "http://127.0.0.1:021434",
          "http://127.0.0.1:0",
          "http://127.0.0.1:65536"
        ] do
      assert {:error, :model_origin} =
               EvaluationContract.validate(Map.put(plan, "model_origin", origin))
    end

    mismatched = put_in(plan, ["profiles", "p27_answer", "base_url"], "http://127.0.0.1:31434")
    assert {:error, :model_origin} = EvaluationContract.validate(mismatched)

    assert {:error, :model_origin} =
             EvaluationContract.validate(Map.put(plan, "search_port", 21434))
  end

  test "the full schedule preserves original allowances and disjoint research shares" do
    plan = plan()
    queries = queries()
    assert {:ok, schedule} = EvaluationRunner.schedule(plan, queries)
    assert schedule["original_project_count"] == 2
    assert schedule["query_count"] == 50
    assert schedule["research_call_limit"] == 550
    assert length(schedule["cells"]) == 14

    assert Enum.map(schedule["cells"], &{&1["project"], &1["variant"]}) ==
             for(project <- ["alpha", "beta"], variant <- @variants, do: {project, variant})

    assert Enum.map(schedule["cells"], & &1["ordinal"]) == Enum.to_list(0..13)
    assert length(Enum.uniq_by(schedule["cells"], & &1["id"])) == 14

    for cell <- schedule["cells"] do
      variant = Enum.find(plan["variants"], &(&1["id"] == cell["variant"]))

      expected_ids =
        queries |> Enum.filter(&(&1["project"] == cell["project"])) |> Enum.map(& &1["query_id"])

      assert cell["query_ids"] == expected_ids
      assert cell["original_project_count"] == 2

      for key <- ~w(max_requests max_input_tokens max_output_tokens) do
        assert cell["budget"][key] * 2 <= variant["budget"][key]
        assert (variant["budget"][key] - cell["budget"][key] * 2) in 0..1
      end

      assert Map.drop(cell["budget"], ~w(max_requests max_input_tokens max_output_tokens)) ==
               Map.drop(variant["budget"], ~w(max_requests max_input_tokens max_output_tokens))

      if cell["variant"] == "research",
        do: assert(cell["research_share"] == length(expected_ids) * 11),
        else: assert(cell["research_share"] == 0)
    end
  end

  test "missing projects, duplicate queries and reduced strategy sets cannot create a schedule" do
    plan = plan()
    queries = queries()
    assert {:error, :query_count} = EvaluationRunner.schedule(plan, tl(queries))

    assert {:error, :query_identity} =
             EvaluationRunner.schedule(plan, [hd(queries) | tl(tl(queries))] ++ [hd(queries)])

    assert {:error, :project_count} =
             EvaluationRunner.schedule(plan, Enum.map(queries, &Map.put(&1, "project", "alpha")))

    assert {:error, :measured_matrix} =
             EvaluationRunner.schedule(Map.update!(plan, "variants", &tl/1), queries)
  end

  test "monetary limits are partitioned without changing reservations or rate cards" do
    card = Ipse.CostReportDemo.card()

    buckets =
      for {basis, cap} <- Enum.zip(Ipse.Budget.Policy.bases(), [1001, 9000, 0]) do
        %{"basis" => basis, "limit_nanos" => cap, "reserve_nanos" => 700}
      end

    plan =
      Map.update!(plan(), "variants", fn variants ->
        Enum.map(variants, fn variant ->
          update_in(variant, ["budget"], fn budget ->
            budget |> Map.put("money", buckets) |> Map.put("rate_card", card)
          end)
        end)
      end)

    for plan <- [plan, structured(plan)] do
      assert :ok = EvaluationContract.validate(plan)
      assert {:ok, schedule} = EvaluationRunner.schedule(plan, queries())

      for variant <- @variants do
        cells = Enum.filter(schedule["cells"], &(&1["variant"] == variant))
        assert length(cells) == 2

        for cell <- cells do
          assert :ok = Ipse.Budget.Policy.validate(cell["budget"])
          assert cell["budget"]["rate_card"] == card

          assert cell["budget"]["money"] ==
                   Enum.map(buckets, &Map.update!(&1, "limit_nanos", fn cap -> div(cap, 2) end))
        end

        for bucket <- buckets do
          allocated =
            Enum.sum(
              for cell <- cells,
                  share <- cell["budget"]["money"],
                  share["basis"] == bucket["basis"],
                  do: share["limit_nanos"]
            )

          assert allocated <= bucket["limit_nanos"]
          assert (bucket["limit_nanos"] - allocated) in 0..1
        end
      end
    end
  end
end
