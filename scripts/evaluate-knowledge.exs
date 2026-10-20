Code.require_file("../examples/knowledge/evaluation_runner.exs", __DIR__)

arguments =
  case System.argv() do
    ["--" | rest] -> rest
    rest -> rest
  end

{options, rest, invalid} =
  OptionParser.parse(arguments,
    strict: [
      phase: :string,
      plan: :string,
      corpus: :string,
      queries: :string,
      output: :string,
      freeze: :string,
      freeze_sha256: :string,
      experiment: :string,
      experiment_sha256: :string,
      resolution: :string,
      data_manifest: :string,
      predictions: :string,
      prediction_sha256: :string,
      audit_sha256: :string,
      labels: :string,
      reviews: :string
    ]
  )

phases = %{
  "freeze" => :freeze,
  "declare" => :declare,
  "freeze-measured" => :freeze_measured,
  "measure" => :measure,
  "audit" => :audit,
  "predict" => :predict,
  "tune" => :tune,
  "verify" => :verify,
  "verify-frozen" => :verify_frozen,
  "review" => :review,
  "score" => :score
}

phase = phases[options[:phase]]

result =
  if rest == [] and invalid == [] and phase != nil do
    IpseKnowledgeExample.EvaluationRunner.run(phase, Keyword.delete(options, :phase))
  else
    {:error, %{"code" => "invalid_options"}}
  end

case result do
  {:ok, report} ->
    summary =
      if is_map(report),
        do:
          Map.take(
            report,
            ~w(path sha256 source_commit mode prediction_sha256 rows failed_rows execution_complete heldout_quality_complete packet_sha256 reference_integrity_complete quality_gates_passed quality_gate_scope gates contracts complete_first_grid complete_review eligible_variants disqualified_variants)
          ),
        else: %{}

    failed =
      is_map(report) and
        ((report["failed_rows"] || 0) > 0 or report["execution_complete"] == false or
           report["reference_integrity_complete"] == false or
           (phase == :score and report["quality_gates_passed"] != true))

    IO.puts(
      JSON.encode!(%{"status" => if(failed, do: "failed", else: "ok"), "result" => summary})
    )

    if failed, do: System.halt(1)

  {:error, reason} ->
    IO.puts(JSON.encode!(%{"status" => "failed", "reason" => reason}))
    System.halt(1)
end
