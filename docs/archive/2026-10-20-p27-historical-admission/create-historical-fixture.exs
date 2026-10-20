# Synthetic creation only. Invoke after the active CPU comparison is terminal.
# Use the built original914 SDK and a fresh output directory. Never pass a real
# experiment: prepare/3 constructs fixture data and fake model services itself.
defmodule P27CreateHistoricalFixture do
  @predictor "914bc0ad7fd1794e0c9855a20d4548b961c309f4"

  def main([source, requested]) do
    try do
      true = :os.type() == {:unix, :linux}
      true = Path.type(source) == :absolute and File.cwd!() == source
      true = Path.type(requested) == :absolute
      true = :code.is_loaded(IpseKnowledgeExample.EvaluationMeasuredExecution) == false
      {head, 0} = System.cmd("git", ["--no-optional-locks", "-C", source, "rev-parse", "HEAD"])
      @predictor = String.trim(head)

      {"", 0} =
        System.cmd("git", [
          "--no-optional-locks",
          "-C",
          source,
          "status",
          "--porcelain=v1",
          "--untracked-files=all"
        ])

      Code.require_file(Path.join(source, "examples/knowledge/evaluation_plan.exs"))
      Code.require_file(Path.join(source, "test/support/measured_model_fixture.exs"))
      Code.require_file(Path.join(source, "test/support/measured_knowledge_verification.exs"))
      {:ok, launch} = IpseKnowledgeExample.EvaluationFreeze.runtime_launch()
      {:ok, output} = Ipse.WorkspaceContext.canonical_path(requested)
      %{type: :directory} = File.lstat!(Path.dirname(output))

      for protected <- [source, launch["root"] | launch["code_paths"]] do
        {:ok, protected} = Ipse.WorkspaceContext.canonical_path(protected)

        false =
          output == protected or String.starts_with?(output, protected <> "/") or
            String.starts_with?(protected, output <> "/")
      end

      {:error, :enoent} = File.lstat(output)
      File.mkdir!(output)
      File.chmod!(output, 0o700)

      for leaf <- ~w(home tmp) do
        dir = Path.join(output, leaf)
        File.mkdir!(dir)
        File.chmod!(dir, 0o700)
      end

      System.put_env(%{
        "HOME" => Path.join(output, "home"),
        "IPSE_HOME" => Path.join(output, "home/.ipse"),
        "TMPDIR" => Path.join(output, "tmp"),
        "ERL_CRASH_DUMP" => "/dev/null"
      })

      {:ok, _} = Application.ensure_all_started(:ipse)

      artifacts =
        MeasuredKnowledgeVerification.build_artifacts(Path.join(output, "artifacts"), source)

      save!(Path.join(output, "artifacts.json"), artifacts)
      run = MeasuredKnowledgeVerification.prepare(Path.join(output, "run"), source, artifacts)

      {:ok, before} =
        IpseKnowledgeExample.EvaluationFreeze.verify(run.seal["path"], run.seal["sha256"])

      "fixture" = before["plan"]["mode"]
      # Exactly one execution call. A partial/failed attempt is retained and never
      # retried here; postprocessing uses the separate read-only verification file.
      {:ok, result} =
        IpseKnowledgeExample.EvaluationMeasuredExecution.run(
          freeze: run.seal["path"],
          freeze_sha256: run.seal["sha256"]
        )

      true = result["execution_complete"] and result["resource_complete"]
      350 = result["rows"]

      {:ok, ^result} =
        IpseKnowledgeExample.EvaluationMeasuredExecution.audit(
          run.seal["path"],
          run.seal["sha256"]
        )

      {:ok, ^before} =
        IpseKnowledgeExample.EvaluationFreeze.verify(run.seal["path"], run.seal["sha256"])

      save!(Path.join(output, "initial-audit.json"), result)

      receipt = %{
        "version" => 1,
        "status" => "completed",
        "synthetic" => true,
        "predictor_commit" => @predictor,
        "source" => source,
        "freeze" => run.seal["path"],
        "freeze_sha256" => run.seal["sha256"],
        "fixture" => run.root,
        "reports" => run.reports,
        "original_audit_sha256" => result["sha256"],
        "prediction_sha256" => result["prediction_sha256"],
        "rows" => result["rows"],
        "new_measure_calls" => 1,
        "synthetic_model_service" => true,
        "real_inference" => false,
        "model_quality_measured" => false
      }

      save!(Path.join(output, "fixture-receipt.json"), receipt)
      IO.puts(JSON.encode!(receipt))
    rescue
      error ->
        IO.puts(
          JSON.encode!(%{
            "status" => "failed",
            "class" => inspect(error.__struct__),
            "model_quality_measured" => false
          })
        )

        System.halt(1)
    end
  end

  defp save!(path, value) do
    File.write!(path, JSON.encode!(value) <> "\n", [:exclusive, :sync])
    File.chmod!(path, 0o600)
  end
end
