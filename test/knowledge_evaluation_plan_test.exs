Code.require_file("../examples/knowledge/evaluation_plan.exs", __DIR__)

defmodule Ipse.KnowledgeEvaluationPlanTest do
  use ExUnit.Case, async: false
  alias IpseKnowledgeExample.{EvaluationPlan, EvaluationRunner}
  @variants ~w(lexical graph_explicit graph_model dense hybrid rerank research)

  defp spec do
    JSON.decode!(File.read!("examples/knowledge/benchmark-spec.json"))
    |> Map.put("blind_seed", String.duplicate("b", 64))
  end

  test "the complete declaration is valid without opening dataset members or artifacts" do
    declared = spec()
    assert {:ok, plan} = EvaluationPlan.build(declared)
    assert :ok = EvaluationRunner.validate(plan)
    assert plan["answer"] and Enum.map(plan["variants"], & &1["id"]) == @variants
    assert plan["data"] == declared["data"] and plan["models"] == declared["models"]
    assert Enum.all?(plan["variants"], &(&1["budget"] == declared["budgets"][&1["id"]]))
    assert Enum.all?(plan["variants"], &Map.has_key?(&1["bindings"], "answer"))
    research = List.last(plan["variants"])
    assert research["query_options"]["limits"]["max_sources"] == 10
    assert :code.is_loaded(IpseKnowledge.Corpus) == false

    for mutated <- [
          Map.put(declared, "labels", "PRIVATE_LABELS"),
          Map.delete(declared, "budgets"),
          update_in(declared, ["artifacts"], &Map.delete(&1, "answer")),
          put_in(declared, ["profiles", "p27_answer", "credential"], "unreviewed")
        ] do
      assert {:error, _} = EvaluationPlan.build(mutated)
    end
  end

  test "CLI normalizes declared paths and creates one private plan without reading inputs" do
    root = Path.join(System.tmp_dir!(), "ipse-plan-cli-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    input = Path.join(root, "spec.json")
    declared = spec() |> Map.put("blind_seed", nil)
    File.write!(input, JSON.encode!(declared))
    paths = Path.wildcard(Path.join([Path.dirname(Application.app_dir(:ipse)), "*", "ebin"]))
    code = Enum.flat_map(paths, &["-pa", &1])
    script = Path.expand("scripts/prepare-knowledge-evaluation.exs")

    for name <- ~w(first second) do
      output = Path.join(root, name <> ".json")

      {message, status} =
        System.cmd(
          System.find_executable("elixir"),
          code ++ [script, "--spec", input, "--output", output, "--new-blind-seed"],
          stderr_to_stdout: true
        )

      assert status == 0, message
      result = JSON.decode!(String.trim(message))
      assert result["status"] == "ok" and result["result"]["variants"] == 7
      assert result["result"]["sha256"] == Ipse.Extensions.Manifest.sha256(File.read!(output))
      plan = JSON.decode!(File.read!(output))
      refute message =~ plan["blind_seed"]
      assert :ok = EvaluationRunner.validate(plan)
      assert plan["artifacts"]["lexical"] == Path.join(root, "artifacts/lexical")
      assert Bitwise.band(File.stat!(output).mode, 0o777) == 0o600
    end

    first = File.read!(Path.join(root, "first.json"))
    second = File.read!(Path.join(root, "second.json"))
    refute JSON.decode!(first)["blind_seed"] == JSON.decode!(second)["blind_seed"]

    {message, status} =
      System.cmd(
        System.find_executable("elixir"),
        code ++
          [script, "--spec", input, "--output", Path.join(root, "first.json"), "--new-blind-seed"],
        stderr_to_stdout: true
      )

    assert status == 1 and JSON.decode!(String.trim(message))["status"] == "failed"
    assert File.read!(Path.join(root, "first.json")) == first
    refute File.exists?(Path.join(root, "artifacts"))
    refute File.exists?(Path.join(root, "corpus.json"))
    refute File.exists?(Path.join(root, "heldout.json"))
  end

  test "baseline budgets cover every project distribution of fifty answer requests" do
    declared = spec()

    for id <- ~w(lexical graph_explicit research), projects <- 1..50 do
      budget = declared["budgets"][id]
      largest_project = 51 - projects
      assert div(budget["max_requests"], projects) >= largest_project

      assert div(budget["max_input_tokens"], projects) >=
               largest_project * budget["reserve_input_tokens"]

      assert div(budget["max_output_tokens"], projects) >=
               largest_project * budget["reserve_output_tokens"]
    end
  end

  test "public Session and driver return all ten offline Research citations" do
    root = Path.join(System.tmp_dir!(), "ipse-research-capacity-" <> Ipse.Usage.id())
    artifact = Path.join(root, "artifact")
    on_exit(fn -> File.rm_rf!(root) end)

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        [
          "extensions/knowledge/build.exs",
          "--sdk",
          Application.app_dir(:ipse, "ebin"),
          "--output",
          artifact,
          "--package",
          "research",
          "--preset",
          "offline"
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    bytes = File.read!(Path.join(artifact, "extension.json"))
    manifest = JSON.decode!(bytes)
    digest = Ipse.Extensions.Manifest.sha256(bytes)
    options = JSON.decode!(File.read!("extensions/knowledge/options/research-offline.json"))

    selection = %{
      root: root,
      project: "synthetic",
      variant: "research",
      artifacts: [
        %{
          instance: "research",
          path: artifact,
          digest: digest,
          options: options,
          order: 0,
          trust: %{
            "artifact" => digest,
            "capabilities" => manifest["capabilities"],
            "allow_project" => false,
            "allow_children" => false
          }
        }
      ],
      runtime: %{
        provider: :demo,
        model: "unused",
        compact: false,
        budget: %{"version" => 1, "max_requests" => 1}
      },
      bindings: %{"research" => %{"instance" => "research", "id" => "investigate"}},
      required_verbs: ["research"],
      timeout_ms: 30_000,
      approval_validator: fn _ -> flunk("offline Research proposed a host action") end
    }

    alias IpseKnowledgeExample.EvaluationSession, as: Session
    assert {:ok, run} = Session.open(selection)

    try do
      sources =
        Enum.map(1..10, fn n ->
          %{
            "source_id" => "s#{n}",
            "generation" => 1,
            "title" => "Locks",
            "text" => "Lock files preserve inode identity.",
            "uri" => "local:s#{n}",
            "observed_at_ms" => 1,
            "event_at_ms" => nil,
            "expires_at_ms" => nil
          }
        end)

      args = %{
        "search" => "given",
        "fetch" => "given",
        "retrieval" => "words",
        "rerank" => nil,
        "query" => "lock files",
        "as_of_ms" => 20,
        "limits" => %{"max_sources" => 10, "max_body_bytes" => 1024, "timeout_ms" => 5000},
        "sources" => sources
      }

      assert {:ok, receipt, next} = Session.invoke(run, "research", args)
      result = receipt["value"]
      assert result["status"] == "ok" and length(result["evidence"]) == 10
      assert hd(result["claims"])["evidence_indexes"] == Enum.to_list(0..9)
      assert {:ok, snapshot} = Session.snapshot(next)
      assert snapshot["accounting"]["request_count"] == 0
      assert length(next.receipts) == 1
      assert is_binary(hd(next.receipts)["result_sha256"])
      assert :code.is_loaded(IpseKnowledge.Research) == false
    after
      assert {:ok, %{"cleanup" => "confirmed"}} = Session.close(run)
    end
  end
end
