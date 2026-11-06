defmodule IpseKnowledge.CandidateAssessmentEvaluationSessionTest do
  use ExUnit.Case, async: false
  alias Ipse.JSON
  @moduletag :candidate_assessment_protocol
  @moduletag skip: System.get_env("IPSE_RUN_CANDIDATE_ASSESSMENT_PROTOCOL") != "1"

  @tag timeout: 240_000
  test "a standalone authenticated assessment freezes its first row and rejects synthetic independence" do
    root = Path.join(System.tmp_dir!(), "ipse-candidate-shadow-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)

    on_exit(fn ->
      if File.regular?(Path.join(root, "test-passed")) and
           System.get_env("IPSE_KEEP_SHADOW_FIXTURES") != "1",
         do: File.rm_rf!(root)
    end)

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
