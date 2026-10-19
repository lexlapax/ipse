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
      data_manifest: :string,
      predictions: :string,
      prediction_sha256: :string,
      labels: :string,
      reviews: :string
    ]
  )

phases = %{
  "freeze" => :freeze,
  "predict" => :predict,
  "tune" => :tune,
  "verify" => :verify,
  "verify-frozen" => :verify_frozen,
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
            ~w(path sha256 source_commit mode prediction_sha256 rows failed_rows execution_complete heldout_quality_complete)
          ),
        else: %{}

    failed =
      is_map(report) and
        ((report["failed_rows"] || 0) > 0 or report["execution_complete"] == false)

    IO.puts(
      JSON.encode!(%{"status" => if(failed, do: "failed", else: "ok"), "result" => summary})
    )

    if failed, do: System.halt(1)

  {:error, reason} ->
    IO.puts(JSON.encode!(%{"status" => "failed", "reason" => reason}))
    System.halt(1)
end
