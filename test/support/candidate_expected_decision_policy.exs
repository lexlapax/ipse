ExUnit.start(autorun: false)
Code.require_file("dev/evaluation/candidate_assessment_session.exs")
Code.require_file("extensions/knowledge/src/knowledge/decision_policy.ex")

defmodule CandidateExpectedDecisionPolicyTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.Evaluation.CandidateAssessmentSession, as: Owner
  alias IpseKnowledge.Knowledge.DecisionPolicy

  test "host-built request matches the bundled policy for both assessment inputs" do
    rubric =
      "Choose keep_baseline or defer_candidate for this already proposed candidate. Defer only when ambiguity, conflict or low durability warrants omitting this capture. Advice cannot change evidence, origin, text, category, retention or permission."

    for input <- [
          %{
            "candidate_id" => "abc",
            "text" => "A quotation: \"yes\"",
            "assigned_category" => "ordinary",
            "reason" => "fixture"
          },
          %{"id" => "note", "text" => "Καλημέρα", "generation" => 4, "sources" => ["one", "two"]}
        ] do
      candidate = %{"id" => "candidate", "input" => IO.iodata_to_binary(JSON.encode!(input))}

      facts = %{
        "version" => 1,
        "availability" => "available",
        "budget_available" => true,
        "candidates" => [candidate],
        "alternatives" => ~w(keep_baseline defer_candidate)
      }

      policy =
        DecisionPolicy.default("notes.assess")
        |> Map.merge(%{"strategy" => "decision", "profile" => "advice"})

      assert {:ok, plan} = DecisionPolicy.plan(policy, facts, :development_experiment)
      assert {:ok, request} = Owner.expected_decision_request(input, Ipse.JSON.sha256(rubric))
      assert request === plan.request
    end
  end

  test "encoded candidate size boundary agrees with the bundled policy" do
    rubric =
      "Choose keep_baseline or defer_candidate for this already proposed candidate. Defer only when ambiguity, conflict or low durability warrants omitting this capture. Advice cannot change evidence, origin, text, category, retention or permission."

    empty_bytes = byte_size(IO.iodata_to_binary(JSON.encode!(%{"text" => ""})))

    policy =
      DecisionPolicy.default("notes.assess")
      |> Map.merge(%{"strategy" => "decision", "profile" => "advice"})

    for {size, expected} <- [{6144, :ok}, {6145, :error}] do
      input = %{"text" => String.duplicate("x", size - empty_bytes)}
      candidate = %{"id" => "candidate", "input" => IO.iodata_to_binary(JSON.encode!(input))}
      assert byte_size(candidate["input"]) == size

      facts = %{
        "version" => 1,
        "availability" => "available",
        "budget_available" => true,
        "candidates" => [candidate],
        "alternatives" => ~w(keep_baseline defer_candidate)
      }

      result = DecisionPolicy.plan(policy, facts, :development_experiment)
      host = Owner.expected_decision_request(input, Ipse.JSON.sha256(rubric))

      if expected == :ok do
        assert {:ok, plan} = result
        assert {:ok, request} = host
        assert request === plan.request
      else
        assert {:error, _} = result
        assert {:error, :candidate_request_unavailable} = host
      end
    end
  end
end

result = ExUnit.run()
System.halt(if(result.failures == 0 and result.total == 2, do: 0, else: 1))
