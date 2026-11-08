defmodule Ipse.Development.Evaluation.CandidateExpectedDecisionPolicyTest do
  use ExUnit.Case, async: false
  @root Path.expand("../../..", __DIR__)

  test "assessment request construction matches the bundled policy" do
    parent_policy = :code.is_loaded(IpseKnowledge.Knowledge.DecisionPolicy)

    paths =
      for module <- [Ipse.Extension, Jason, JSONSchex, ExJSONPointer],
          path = module |> :code.which() |> to_string() |> Path.dirname(),
          do: ["-pa", path]

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        List.flatten(paths) ++
          [Path.join(@root, "test/support/candidate_expected_decision_policy.exs")],
        cd: @root,
        stderr_to_stdout: true,
        env: [{"ERL_FLAGS", "+S 1:1 +A 1"}]
      )

    assert status == 0, output
    assert :code.is_loaded(IpseKnowledge.Knowledge.DecisionPolicy) == parent_policy
  end
end
