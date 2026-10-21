base = "/var/tmp/ipse-p27-builder-20261020-c1/evidence"
output = "/var/tmp/ipse-p27-builder-20261020-c1/receipts"
File.mkdir!(output)
File.chmod!(output, 0o700)
read = &(File.read!(&1) |> JSON.decode!())
sha = &Base.encode16(:crypto.hash(:sha256, &1), case: :lower)
last = fn path -> path |> File.read!() |> String.split("\n", trim: true) |> List.last() |> JSON.decode!() end
true = File.read!(base <> "/source-before.json") == File.read!(base <> "/source-after.json")
builder = read.(base <> "/summary.json")
true = builder["sdk_baseline_unchanged"]
11 = builder["catalogs_compared"]
true = Enum.all?(builder["steps"], &(&1["exit"] == 0))
subjects = for name <- ~w(source installed), into: %{} do
  summary = last.(base <> "/measured-" <> name <> ".log")
  true = summary["synthetic"] and not summary["model_quality_measured"]
  audit = summary["result"]
  350 = audit["rows"]
  true = audit["execution_complete"] and audit["resource_complete"]
  16 = length(audit["report"]["stages"])
  true = audit["report"]["whole_lifetime"]["complete"]
  true = audit["report"]["whole_lifetime"]["cleanup_confirmed"]
  run = if name == "source", do: base <> "/measured-source/source", else: base <> "/measured-installed/installed"
  plan = read.(run <> "/freeze/plan.json")
  3 = plan["version"]
  score = read.(run <> "/scoring-controls/score/scores.json")
  2 = score["version"]
  3 = score["declarations"]["version"]
  true = score["contracts"] == plan["contracts"]
  "per_strategy_eligibility_v1" = score["quality_gate_scope"]
  true = score["complete_first_grid"]
  false = score["complete_review"]
  false = score["quality_gates_passed"]
  [] = score["eligible_variants"]
  7 = length(score["disqualified_variants"])
  350 = Enum.sum(Enum.map(score["variants"], &length(&1["rows"])))
  counts = for row <- File.read!(run <> "/reports/execution.jsonl") |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1), row["phase"] == "answer_context" do
    true = Regex.match?(~r/\A[0-9a-f]{64}\z/, row["request_sha256"])
    row
  end
  350 = length(counts)
  scoring = summary["scoring"]
  true = scoring["answers_absent_through_measured_audit"]
  true = scoring["unopened_label_and_review_inputs"]
  true = scoring["evaluation_artifacts_and_model_request_logs_unchanged"]
  10 = length(scoring["refusals"])
  3 = length(scoring["review_binding_refusals"])
  {name, %{"plan_version" => 3, "contracts" => plan["contracts"],
    "audit" => Map.take(audit, ~w(sha256 rows prediction_sha256 execution_complete resource_complete)),
    "complete_stages" => 16, "answer_context_request_hashes" => 350,
    "whole_lifetime_complete_and_cleanup_confirmed" => true,
    "score" => Map.take(score, ~w(version quality_gate_scope complete_first_grid complete_review eligible_variants quality_gates_passed)),
    "scoring_controls" => scoring}}
end
record = %{"version" => 1, "subjects" => subjects, "source_inventory_sha256" => sha.(File.read!(base <> "/source-before.json"))}
File.write!(output <> "/measured-summary.json", JSON.encode!(record) <> "\n", [:exclusive])
for path <- Path.wildcard(base <> "/*.log") ++ Enum.map(~w(source-before.json source-after.json steps.json summary.json), &(base <> "/" <> &1)) do
  File.cp!(path, Path.join(output, Path.basename(path)))
end
IO.puts(JSON.encode!(%{"bounded_receipts" => length(Path.wildcard(output <> "/*")), "source" => record["source_inventory_sha256"], "synthetic_rows_per_subject" => 350}))
