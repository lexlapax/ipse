defmodule MeasuredScoringVerification do
  @moduledoc "Post-execution controls for the measured CLI audit and label boundary."
  alias IpseKnowledgeExample.{EvaluationFreeze, EvaluationMeasuredExecution, EvaluationRunner}
  @log_limit 1_048_576

  def verify(run, result, repository) do
    root = Path.join(run.root, "scoring-controls")
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    for leaf <- ~w(home tmp), do: mkdir!(Path.join(root, leaf))
    {:ok, verified} = EvaluationFreeze.verify(run.seal["path"], run.seal["sha256"])
    launch = verified["manifest"]["runtime"]["launch"]
    true = verified["manifest"]["version"] == 2
    true = result["execution_complete"] and result["resource_complete"]
    prediction = Path.join(run.reports, "predictions.jsonl")
    data = verified["resolution"]["data_manifest"]

    labels =
      if run.answers do
        false = File.exists?(run.labels)
        save!(run.labels, run.answers)
        run.labels
      else
        Path.join(Path.dirname(data), verified["plan"]["data"]["queries"])
      end

    common = [
      freeze: run.seal["path"],
      freeze_sha256: run.seal["sha256"],
      audit_sha256: result["sha256"],
      data_manifest: data,
      predictions: prediction,
      prediction_sha256: result["prediction_sha256"]
    ]

    unchanged = snapshot!(run.root, root)
    packet = Path.join(root, "review")
    review_options = common ++ [output: packet] ++ if(run.answers, do: [labels: labels], else: [])
    {review, 0} = cli!(launch, repository, root, "review", :review, review_options)
    true = review["status"] == "ok"
    true = review["result"]["rows"] == result["rows"]
    true = review["result"]["reference_integrity_complete"]
    packet_manifest = Path.join(packet, "manifest.json") |> File.read!() |> JSON.decode!()
    true = packet_manifest["execution_freeze_sha256"] == run.seal["sha256"]
    true = packet_manifest["data_manifest_sha256"] == verified["plan"]["data"]["manifest_sha256"]
    template = Path.join(packet, "reviews-template.json") |> File.read!() |> JSON.decode!()
    2 = template["version"]
    true = template["review_binding_sha256"] == packet_manifest["review_binding_sha256"]

    score_options =
      common ++
        [
          labels: labels,
          reviews: Path.join(packet, "reviews-template.json"),
          output: Path.join(root, "score")
        ]

    {score, 1} = cli!(launch, repository, root, "score", :score, score_options)
    true = score["status"] == "failed"
    false = score["result"]["quality_gates_passed"]
    "unmeasured" = score["result"]["gates"]["support"]["status"]
    true = File.regular?(Path.join(root, "score/scores.json"))
    true = snapshot!(run.root, root) == unchanged

    binding_refusals =
      for {name, code, changed} <- [
            {"wrong-review-binding", "review_binding_mismatch",
             Map.put(
               template,
               "review_binding_sha256",
               different_hash(template["review_binding_sha256"])
             )},
            {"missing-review-binding", "invalid_reviews",
             Map.delete(template, "review_binding_sha256")},
            {"legacy-review", "invalid_reviews", Map.put(template, "version", 1)}
          ] do
        file = Path.join(root, name <> ".json")
        save!(file, JSON.encode!(changed) <> "\n")
        output = Path.join(root, name)
        unopened = Path.join(root, "must-not-open-binding-labels.json")

        options =
          common ++ [labels: unopened, reviews: file, output: output]

        {:error, %{"code" => actual}} = EvaluationRunner.run(:score, options)
        true = actual == code
        {:error, :enoent} = File.lstat(output)
        {:error, :enoent} = File.lstat(unopened)
        true = snapshot!(run.root, root) == unchanged
        %{"case" => name, "code" => actual}
      end

    unopened = %{
      labels: Path.join(root, "must-not-open-labels.json"),
      reviews: Path.join(root, "must-not-open-reviews.json"),
      data_manifest: Path.join(root, "must-not-open-data-manifest.json"),
      predictions: Path.join(root, "must-not-open-predictions.jsonl")
    }

    controls = [
      {"missing-audit", :measured_audit_required, &Keyword.delete(&1, :audit_sha256)},
      {"wrong-audit", :measured_audit_mismatch,
       &Keyword.put(&1, :audit_sha256, different_hash(result["sha256"]))},
      {"wrong-prediction", :measured_audit_mismatch,
       &Keyword.put(&1, :prediction_sha256, different_hash(result["prediction_sha256"]))},
      {"wrong-data-path", :measured_input_mismatch,
       &Keyword.put(&1, :data_manifest, unopened.data_manifest)},
      {"wrong-prediction-path", :measured_input_mismatch,
       &Keyword.put(&1, :predictions, unopened.predictions)}
    ]

    refused =
      for phase <- [:review, :score], {name, code, change} <- controls do
        output = Path.join(root, Atom.to_string(phase) <> "-" <> name)

        options =
          if phase == :score,
            do: common ++ [labels: unopened.labels, reviews: unopened.reviews, output: output],
            else: common ++ [output: output]

        {:error, %{"code" => actual}} = EvaluationRunner.run(phase, change.(options))
        true = actual == Atom.to_string(code)
        {:error, :enoent} = File.lstat(output)
        for path <- Map.values(unopened), do: {:error, :enoent} = File.lstat(path)
        true = snapshot!(run.root, root) == unchanged
        %{"phase" => Atom.to_string(phase), "case" => name, "code" => actual}
      end

    summary = %{
      "version" => 1,
      "synthetic" => true,
      "model_quality_measured" => false,
      "freeze_sha256" => run.seal["sha256"],
      "audit_sha256" => result["sha256"],
      "prediction_sha256" => result["prediction_sha256"],
      "review_cli" => "passed",
      "score_cli" => "unmeasured_quality_refused",
      "refusals" => refused,
      "review_binding_refusals" => binding_refusals,
      "unopened_label_and_review_inputs" => true,
      "evaluation_artifacts_and_model_request_logs_unchanged" => true,
      "new_model_work" => false,
      "answer_contract" => verified["plan"]["data"]["contract"],
      "answers_absent_through_measured_audit" => is_binary(run.answers)
    }

    save!(Path.join(root, "verification.json"), JSON.encode!(summary) <> "\n")
    summary
  end

  defp cli!(launch, repository, root, name, phase, options) do
    argv =
      ["--phase", Atom.to_string(phase)] ++
        Enum.flat_map(options, fn {key, value} ->
          ["--" <> (key |> Atom.to_string() |> String.replace("_", "-")), value]
        end)

    {executable, arguments} =
      EvaluationMeasuredExecution.command(
        launch,
        [Path.join(repository, "scripts/evaluate-knowledge.exs")],
        ":ok",
        argv
      )

    environment =
      Map.new(Map.keys(System.get_env()), &{&1, nil})
      |> Map.merge(%{
        "PATH" => Path.dirname(launch["executable"]) <> ":/usr/bin:/bin",
        "LANG" => "C.UTF-8",
        "HOME" => Path.join(root, "home"),
        "IPSE_HOME" => Path.join(root, "home/.ipse"),
        "TMPDIR" => Path.join(root, "tmp"),
        "ERL_CRASH_DUMP" => "/dev/null"
      })
      |> Map.to_list()

    {bytes, status} =
      System.cmd(executable, arguments,
        cd: repository,
        env: environment,
        stderr_to_stdout: true
      )

    log = Path.join(root, name <> ".log")
    save!(log, binary_part(bytes, 0, min(byte_size(bytes), @log_limit)))
    true = byte_size(bytes) <= @log_limit

    {:ok, message} =
      bytes |> String.split("\n", trim: true) |> List.last() |> Ipse.JSON.decode_unique()

    {message, status}
  end

  defp snapshot!(root, excluded) do
    paths = Path.wildcard(Path.join(root, "**/*"), match_dot: true)
    true = length(paths) <= 65_536

    paths
    |> Enum.reject(&(&1 == excluded or String.starts_with?(&1, excluded <> "/")))
    |> Enum.flat_map(fn path ->
      case File.lstat!(path) do
        %{type: :directory} ->
          []

        %{type: :regular, size: size} when size <= 67_108_864 ->
          digest =
            path
            |> File.stream!(1_048_576, [])
            |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
            |> :crypto.hash_final()
            |> Base.encode16(case: :lower)

          [{path, %{"bytes" => size, "sha256" => digest}}]
      end
    end)
    |> Map.new()
  end

  defp different_hash(<<first, tail::binary>>),
    do: <<if(first == ?0, do: ?1, else: ?0), tail::binary>>

  defp mkdir!(path) do
    File.mkdir!(path)
    File.chmod!(path, 0o700)
  end

  defp save!(path, bytes) do
    File.write!(path, bytes, [:exclusive, :sync])
    File.chmod!(path, 0o600)
  end
end
