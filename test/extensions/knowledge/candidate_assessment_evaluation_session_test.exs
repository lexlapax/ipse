defmodule IpseKnowledge.CandidateAssessmentEvaluationSessionTest do
  use ExUnit.Case, async: false
  alias Ipse.{JSON, Journal, Session}
  alias Ipse.Extension.Actions
  @moduletag :candidate_assessment_protocol
  @moduletag skip: System.get_env("IPSE_RUN_CANDIDATE_ASSESSMENT_PROTOCOL") != "1"

  @tag timeout: 240_000
  test "a standalone authenticated assessment freezes its first row and rejects synthetic independence" do
    root = Path.join(System.tmp_dir!(), "ipse-candidate-shadow-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)

    # The PTY, Session and worker may outlive an interrupted test. Retain this
    # entire fresh root until a separate process/effect audit confirms closure.

    driver = Path.join(root, "pty")

    assert {"", 0} =
             System.cmd(
               "rustc",
               ["--edition=2021", "-D", "warnings", "test/support/operator_pty.rs", "-o", driver],
               stderr_to_stdout: true
             )

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 === "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    seed = Path.expand("../../support/shadow_pending_candidate_cli.exs", __DIR__)

    {seed_output, seed_status} =
      System.cmd(
        driver,
        ["--assertion", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [seed, root, "save_managed_approval_candidate_evaluation_seed"],
        stderr_to_stdout: true
      )

    File.write!(Path.join(root, "seed-private.log"), seed_output, [:exclusive, :sync])
    File.chmod!(Path.join(root, "seed-private.log"), 0o600)
    assert seed_status === 0, "Synthetic fixture root: #{root}; seed status #{seed_status}"
    assert seed_output =~ "CANDIDATE_ASSESSMENT_SEED_FROZEN"
    recipe_path = Path.join(root, "recipe.json")
    recipe = Jason.decode!(File.read!(recipe_path))
    case_output = Path.join([root, "cases", recipe["case_id"]])
    entry = Path.expand("../../support/candidate_assessment_evaluation_cli.exs", __DIR__)

    {output, status} =
      System.cmd(
        driver,
        ["--assertion", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [entry, recipe_path, case_output, "save_managed_approval_candidate_evaluation"],
        stderr_to_stdout: true
      )

    File.write!(Path.join(root, "assessment-private.log"), output, [:exclusive, :sync])
    File.chmod!(Path.join(root, "assessment-private.log"), 0o600)
    assert status === 0, "Synthetic fixture root: #{root}; assessment status #{status}"
    assert output =~ "CANDIDATE_ASSESSMENT_PROTOCOL_PASSED"
    negative = Jason.decode!(File.read!(Path.join(root, "rubric-refusal.json")))
    assert negative["scope"] === "pre_session_preflight"
    assert negative["declaration_sha256"] !== recipe["declaration_sha256"]
    assert negative["error"] === "candidate_fence_unavailable"
    assert negative["selected_loopback_connections_after_refusal"] === 0
    assert negative["session_files_unchanged"] === true and negative["policy_unchanged"] === true

    terminal = Jason.decode!(File.read!(Path.join(case_output, "terminal.json")))
    session_id = terminal["session_id"]
    assert {:ok, events} = Journal.load(Path.join(root, "sessions"), session_id)
    assert {:ok, _} = Session.Saved.restore(events, session_id)
    metadata = hd(events)["metadata"]
    assert metadata["source_layout"] === Session.ExactActionFence.layout()
    fence = metadata["exact_action_fence"]
    assert Session.ExactActionFence.valid?(fence)
    assert fence["operation"] === "decision.create"

    assert [attempt] = Enum.filter(events, &(&1["type"] === "exact_action_fence_attempt"))
    assert attempt["matched"] === true
    assert attempt["fence_sha256"] === JSON.digest([fence])
    assert attempt["session_id"] === session_id

    assert [parent] =
             Enum.filter(events, fn event ->
               event["type"] === "extension_invocation_intent" and
                 event["invocation_id"] === attempt["parent_invocation_id"]
             end)

    assert parent["identity"]["instance"] === "knowledge"
    declaration = Jason.decode!(File.read!(Path.join(root, "declaration.json")))
    assert parent["identity"]["artifact_sha256"] === declaration["spec"]["artifact_sha256"]
    assert parent["descriptor"]["id"] === "assess"
    assert parent["descriptor"]["stage"] === "invoke.tool"
    assert parent["payload"]["arguments"] === %{"key" => recipe["key"]}
    assert fence["identity_sha256"] === JSON.digest([parent["identity"]])
    assert fence["descriptor_sha256"] === JSON.digest([parent["descriptor"]])
    assert fence["arguments_sha256"] === JSON.digest([parent["payload"]["arguments"]])

    assert [action] =
             Enum.filter(events, fn event ->
               event["type"] === "extension_action_intent" and
                 event["operation_id"] === attempt["operation_id"]
             end)

    assert action["request"]["op"] === "decision.create"
    assert action["approval"] === "approved"
    assert [question] = action["request"]["questions"]

    assert JSON.sha256(question["instructions"]) ===
             declaration["spec"]["decision_route"]["rubric_sha256"]

    assert action["parent_invocation_id"] === parent["invocation_id"]
    assert action["request_sha256"] === JSON.digest([action["request"]])
    assert fence["request_sha256"] === action["request_sha256"]
    assert attempt["request_sha256"] === action["request_sha256"]

    assert [action_result] =
             Enum.filter(events, fn event ->
               event["type"] === "extension_action_result" and
                 event["operation_id"] === action["operation_id"]
             end)

    assert Actions.valid_result?(action_result)
    assert Actions.result_intent(action_result) === action
    assert action_result["outcome"]["status"] === "ok"

    result = Jason.decode!(File.read!(Path.join(root, "protocol-result.json")))
    assert result["materialized_row_status"] === "ok"
    assert result["synthetic_labels_rejected"] === true
    assert result["labels_loader_invoked"] === true
    assert result["quality"] === "unverified" and result["qualified_default"] === false
    assert result["main_requests"] === 2 and result["decision_requests"] === 1
    assert result["total_main_requests"] === 7 and result["seed_main_requests"] === 5
    assert result["known_settled_decision_calls"] === 1
    assert is_nil(result["matched_elapsed_ms"]) and is_nil(result["whole_cost_nanos"])
    first = Jason.decode!(File.read!(Path.join(root, "first-rows.json")))
    assert result["first_rows_sha256"] === JSON.digest([first])
    assert result["declaration_sha256"] === recipe["declaration_sha256"]
    File.write!(Path.join(root, "test-passed"), "passed\n", [:exclusive, :sync])
    File.chmod!(Path.join(root, "test-passed"), 0o600)
  end
end
