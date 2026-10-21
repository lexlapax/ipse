defmodule Ipse.Development.Verification.MeasuredKnowledge do
  @moduledoc false
  alias Ipse.Development.Evaluation.{
    Freeze,
    Contract,
    MeasuredExecution
  }

  @variants ~w(lexical graph_explicit graph_model dense hybrid rerank research)

  def run(repository, artifact_file, output, selection) do
    {:ok, _} = Application.ensure_all_started(:ipse)
    artifacts = JSON.decode!(File.read!(artifact_file))

    {contract, generation} =
      case selection do
        "default" -> {nil, 2}
        "sealed" -> {"sealed_answers_v1", 2}
        "structured" -> {nil, 3}
        "sealed-structured" -> {"sealed_answers_v1", 3}
        "sealed-long-answers" -> {"sealed_answers_v1", 3}
        "sealed-gpu-answers" -> {"sealed_answers_v1", 3}
      end

    run =
      prepare(Path.join(output, "run"), repository, artifacts,
        data_contract: contract,
        generation: generation,
        long_answers: selection in ~w(sealed-long-answers sealed-gpu-answers),
        gpu: selection == "sealed-gpu-answers"
      )

    result = verify(run)

    scoring =
      Ipse.Development.Verification.MeasuredKnowledge.Scoring.verify(run, result, repository)

    %{
      "synthetic" => true,
      "model_quality_measured" => false,
      "result" => result,
      "scoring" => scoring,
      "evidence" => output
    }
  end

  def prepare(root, repository, artifacts, options \\ []) do
    true =
      Keyword.keyword?(options) and
        Enum.all?(
          Keyword.keys(options),
          &(&1 in [:fault, :data_contract, :generation, :long_answers, :gpu])
        )

    fault = Keyword.get(options, :fault)
    contract = Keyword.get(options, :data_contract)
    generation = Keyword.get(options, :generation, 2)
    long_answers = Keyword.get(options, :long_answers, false)
    gpu = Keyword.get(options, :gpu, false)
    true = is_boolean(gpu)
    true = is_boolean(long_answers) and (not long_answers or generation == 3)
    true = contract in [nil, "sealed_answers_v1"]
    true = generation in [2, 3]
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    {:ok, launch} = Freeze.runtime_launch()
    origin = "http://127.0.0.1:#{free_port()}"
    search_port = free_port()
    true = search_port != URI.parse(origin).port

    service =
      Ipse.Development.Fixtures.ModelService.configuration(root, launch, origin, fault, true, gpu)

    data_root = Path.join(root, "data")
    File.mkdir!(data_root)
    File.chmod!(data_root, 0o700)

    documents =
      for project <- ~w(alpha beta),
          {id, state, text} <- [
            {"release", "current", "Release requires quiescence."},
            {"forgotten", "forgotten", "PRIVATE_FORGOTTEN requires silence."},
            {"expired", "expired", "PRIVATE_EXPIRED requires silence."}
          ] do
        %{
          "document_id" => project <> "-" <> id,
          "project" => project,
          "source_id" => "fixture:" <> project <> ":" <> id,
          "generation" => 1,
          "version" => 1,
          "title" => id,
          "text" => text,
          "created_at" => "2026-01-01T00:00:00Z",
          "observed_at" => "2026-03-01T00:00:00Z",
          "state" => state,
          "sha256" => Ipse.JSON.sha256(text),
          "byte_length" => byte_size(text),
          "media_type" => "text/plain"
        }
      end

    queries =
      for index <- 1..50 do
        %{
          "query_id" => "Q#{index}",
          "project" => if(index <= 25, do: "alpha", else: "beta"),
          "split" => "fixture",
          "query" => if(rem(index, 2) == 1, do: "Release", else: "absent mineral"),
          "expected_class" => if(rem(index, 2) == 1, do: "answer", else: "abstain"),
          "relevance" => [],
          "expected_answer" => "NEVER_PROVIDER_INPUT"
        }
      end

    corpus = JSON.encode!(%{"schema_version" => 1, "documents" => documents})

    answers =
      if contract do
        JSON.encode!(%{
          "contract" => contract,
          "split" => "heldout",
          "commitment_nonce" => Ipse.Usage.id() <> Ipse.Usage.id(),
          "answers" =>
            Enum.map(queries, fn q ->
              q
              |> Map.drop(~w(split query))
              |> Map.put("expected_refusal", q["expected_class"] == "abstain")
            end)
        })
      end

    query_bytes =
      if contract do
        JSON.encode!(%{
          "contract" => contract,
          "split" => "heldout",
          "queries" => Enum.map(queries, &Map.take(&1, ~w(query_id project query)))
        })
      else
        JSON.encode!(%{"schema_version" => 1, "queries" => queries})
      end

    save!(Path.join(data_root, "corpus.json"), corpus)
    save!(Path.join(data_root, "queries.json"), query_bytes)

    data =
      if contract do
        JSON.encode!(%{
          "contract" => contract,
          "as_of_ms" => 1_800_000_000_000,
          "inputs" => %{
            "corpus" => %{"path" => "corpus.json", "sha256" => Ipse.JSON.sha256(corpus)},
            "queries" => %{"path" => "queries.json", "sha256" => Ipse.JSON.sha256(query_bytes)}
          },
          "answers_sha256" => Ipse.JSON.sha256(answers)
        })
      else
        JSON.encode!(%{
          "as_of_ms" => 1_800_000_000_000,
          "files" => [
            %{"path" => "corpus.json", "sha256" => Ipse.JSON.sha256(corpus)},
            %{"path" => "queries.json", "sha256" => Ipse.JSON.sha256(query_bytes)}
          ]
        })
      end

    data_path = Path.join(data_root, "manifest.json")
    save!(data_path, data)

    spec =
      JSON.decode!(File.read!(Path.join(repository, "examples/knowledge/benchmark-spec.json")))

    spec =
      spec
      |> Map.put("mode", "fixture")
      |> Map.put("as_of_ms", 1_800_000_000_000)
      |> Map.put("blind_seed", String.duplicate("b", 64))
      |> Map.put("artifacts", artifacts)
      |> Map.put("search_port", search_port)
      |> Map.put("models", %{})
      |> Map.put("data", %{
        "corpus" => "corpus.json",
        "queries" => "queries.json",
        "split" => "fixture",
        "expected_queries" => 50,
        "manifest_sha256" => Ipse.JSON.sha256(data)
      })
      |> Map.update!("profiles", fn profiles ->
        Map.new(profiles, fn {id, profile} ->
          {id, profile |> Map.put("model", "fixture-text:latest") |> Map.put("base_url", origin)}
        end)
      end)
      |> Map.update!("embedding_profiles", fn profiles ->
        Map.new(profiles, fn {id, profile} ->
          {id,
           profile
           |> Map.put("model", "fixture-embedding:latest")
           |> Map.put("base_url", origin)
           |> Map.put("dimensions", 2)}
        end)
      end)

    spec =
      spec
      |> Map.put("version", generation)
      |> Map.put("model_origin", origin)
      |> Map.put("models", service["models"])

    spec =
      if generation == 3,
        do:
          Map.put(spec, "contracts", %{
            "outputs" => %{
              "answer" => "json_schema_v2",
              "extract" => "json_schema_v2",
              "rerank" => "json_schema_v2"
            },
            "selection" => "per_strategy_eligibility_v1"
          }),
        else: spec

    spec =
      if contract,
        do:
          spec |> put_in(["data", "contract"], contract) |> put_in(["data", "split"], "heldout"),
        else: spec

    spec =
      if long_answers do
        spec
        |> put_in(["contracts", "outputs", "answer"], "json_schema_v3")
        |> update_in(["profiles", "p27_answer"], fn profile ->
          profile
          |> Map.delete("reasoning_effort")
          |> Map.put("max_output_tokens", 8192)
          |> Map.put("model_call_timeout_ms", 480_000)
        end)
        |> Map.update!(
          "budgets",
          &Map.new(&1, fn {id, budget} ->
            {id,
             budget
             |> Map.put("reserve_output_tokens", 8192)
             |> Map.put("max_output_tokens", budget["max_requests"] * 8192)}
          end)
        )
      else
        spec
      end

    {:ok, plan} = Contract.build(spec)

    :ok = Contract.validate(plan)

    resolution = %{
      "artifacts" => artifacts,
      "model_origin" => origin,
      "search_port" => search_port,
      "reports" => Path.join(root, "reports"),
      "data_manifest" => data_path,
      "model_service" => service
    }

    {:ok, experiment} = Freeze.declare(repository, JSON.encode!(plan), artifacts, resolution)

    {:ok, seal} =
      Freeze.create_v2(
        repository,
        experiment["bytes"],
        resolution,
        Path.join(root, "freeze")
      )

    save!(Path.join(root, "seal-receipt.json"), JSON.encode!(seal))
    save!(Path.join(root, "experiment.json"), experiment["bytes"])

    %{
      seal: seal,
      reports: resolution["reports"],
      root: root,
      answers: answers,
      labels: Path.join(root, "released-answers.json")
    }
  end

  def verify(run) do
    if run.answers, do: false = File.exists?(run.labels)

    {:ok, result} =
      MeasuredExecution.run(freeze: run.seal["path"], freeze_sha256: run.seal["sha256"])

    true = result["execution_complete"] and result["resource_complete"]
    350 = result["rows"]
    predictions = Path.join(run.reports, "predictions.jsonl")
    bytes = File.read!(predictions)
    true = Ipse.JSON.sha256(bytes) == result["prediction_sha256"]
    rows = bytes |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
    true = Enum.all?(rows, &(&1["status"] == "ok"))
    350 = MapSet.size(MapSet.new(rows, &{&1["variant"], &1["query_id"]}))
    true = Enum.sort(Enum.uniq(Enum.map(rows, & &1["variant"]))) == Enum.sort(@variants)
    true = Enum.sort(Enum.uniq(Enum.map(rows, & &1["project"]))) == ~w(alpha beta)
    verify_provider_logs!(run)
    before = snapshot(run.root)
    {:ok, ^result} = MeasuredExecution.audit(run.seal["path"], run.seal["sha256"])
    if run.answers, do: false = File.exists?(run.labels)
    true = snapshot(run.root) == before
    save!(Path.join(run.root, "verified-audit.json"), JSON.encode!(result))
    before = snapshot(run.root)

    {:error, _} =
      MeasuredExecution.run(freeze: run.seal["path"], freeze_sha256: run.seal["sha256"])

    true = snapshot(run.root) == before
    verify_tamper_controls!(run)
    result
  end

  defp verify_tamper_controls!(run) do
    freeze = Path.dirname(run.seal["path"])

    for path <- [
          Path.join(run.reports, "predictions.jsonl"),
          Path.join(run.reports, "execution.jsonl"),
          Path.join(run.reports, "usage.jsonl"),
          Path.join(run.reports, "request-resources.jsonl"),
          Path.join(run.reports, "resources.jsonl"),
          Path.join(run.reports, "timings.jsonl"),
          Path.join(run.reports, "cells/cell-000/domain/usage.jsonl"),
          Path.join(run.reports, "cells/cell-000/model-service/receipt.json"),
          Path.join(freeze, "native-root/prepared/population.json"),
          Path.join(freeze, "native-root/sequence/stage-001.receipt")
        ] do
      original = File.read!(path)
      before = snapshot(run.root)

      try do
        File.write!(path, original <> " ")
        changed = snapshot(run.root)
        {:error, _} = MeasuredExecution.audit(run.seal["path"], run.seal["sha256"])
        true = snapshot(run.root) == changed
      after
        File.write!(path, original)
      end

      true = snapshot(run.root) == before
    end

    for name <- ~w(timings.jsonl request-resources.jsonl) do
      path = Path.join(run.reports, name)
      summary_path = Path.join(run.reports, "resource-summary.json")
      original = File.read!(path)
      original_summary = File.read!(summary_path)
      before = snapshot(run.root)

      try do
        changed =
          if name == "timings.jsonl" do
            original
            |> jsonl()
            |> Enum.map(&Map.put(&1, "elapsed_us", 0))
            |> Enum.map_join("", &(JSON.encode!(&1) <> "\n"))
          else
            ""
          end

        true = changed != original
        File.write!(path, changed)

        read_rows = fn file -> File.read!(Path.join(run.reports, file)) |> jsonl() end

        summary =
          Ipse.Development.Evaluation.Resources.summary(
            read_rows.("predictions.jsonl"),
            read_rows.("timings.jsonl"),
            read_rows.("request-resources.jsonl"),
            Enum.filter(read_rows.("usage.jsonl"), &Map.has_key?(&1, "budget")),
            read_rows.("resources.jsonl")
          )

        true = summary["complete"] and summary["storage_reachability_complete"]
        true = summary != JSON.decode!(original_summary)
        File.write!(summary_path, JSON.encode!(summary) <> "\n")
        changed_snapshot = snapshot(run.root)
        {:error, error} = MeasuredExecution.audit(run.seal["path"], run.seal["sha256"])
        "merged_stream_changed" = error["code"]
        true = snapshot(run.root) == changed_snapshot
      after
        File.write!(path, original)
        File.write!(summary_path, original_summary)
      end

      true = snapshot(run.root) == before
    end

    for directory <- [run.reports, Path.join(freeze, "attempts")] do
      retained = directory <> "-retained-control"
      before = snapshot(run.root)
      File.rename!(directory, retained)
      File.mkdir!(directory)
      File.chmod!(directory, 0o700)

      try do
        changed = snapshot(run.root)

        {:error, _} =
          MeasuredExecution.run(
            freeze: run.seal["path"],
            freeze_sha256: run.seal["sha256"]
          )

        {:error, _} = MeasuredExecution.audit(run.seal["path"], run.seal["sha256"])
        true = snapshot(run.root) == changed
      after
        File.rmdir!(directory)
        File.rename!(retained, directory)
      end

      true = snapshot(run.root) == before
    end

    {:ok, _} = MeasuredExecution.audit(run.seal["path"], run.seal["sha256"])

    save!(
      Path.join(run.root, "tamper-controls.json"),
      JSON.encode!(%{
        "modified_files_refused" => 10,
        "self_consistent_resource_rewrites_refused" => 2,
        "replaced_directories_refused" => 2,
        "read_only_audit" => true,
        "reentry_refused" => true,
        "original_evidence_restored" => true
      })
    )
  end

  defp verify_provider_logs!(run) do
    {:ok, verified} = Freeze.verify(run.seal["path"], run.seal["sha256"])
    models = verified["plan"]["models"]

    for ordinal <- 0..13 do
      id = "cell-" <> String.pad_leading(Integer.to_string(ordinal), 3, "0")
      cell = Path.join(run.reports, "cells/" <> id)
      home = Path.join(cell, "model-service/home")
      bytes = File.read!(Path.join(home, "fixture-requests.jsonl"))
      true = byte_size(bytes) <= 16_777_216

      for forbidden <- ~w(PRIVATE_FORGOTTEN PRIVATE_EXPIRED NEVER_PROVIDER_INPUT),
          do: false = String.contains?(bytes, forbidden)

      requests = jsonl(bytes)
      summary = JSON.decode!(File.read!(Path.join(home, "fixture-requests-summary.json")))
      true = summary["synthetic"] and not summary["model_inference"]
      true = summary["requests"] == length(requests) and length(requests) <= 4096
      true = summary["log_bytes"] == byte_size(bytes)
      true = summary["operations"] == Enum.frequencies_by(requests, & &1["operation"])
      service = JSON.decode!(File.read!(Path.join(cell, "model-service/receipt.json")))

      pid =
        File.read!(Path.join(home, "fixture-daemon.pid")) |> String.trim() |> String.to_integer()

      true = service["listener"]["pid"] == pid
      false = File.exists?("/proc/#{pid}")
      wire = Enum.filter(requests, &(&1["operation"] in ~w(answer extraction embedding rerank)))
      metadata = Enum.reject(requests, &(&1 in wire))
      true = service["metadata_requests"] == length(metadata)
      true = Enum.all?(wire, &Map.has_key?(models, &1["model"]))

      usage = File.read!(Path.join(cell, "domain/usage.jsonl")) |> jsonl()
      [budget] = for row <- usage, row["budget"], do: row["budget"]
      true = budget["request_count"] == length(wire)
      variant = Enum.at(@variants, rem(ordinal, 7))

      required =
        case variant do
          "graph_model" -> ~w(answer extraction)
          "rerank" -> ~w(answer embedding rerank)
          value when value in ~w(dense hybrid) -> ~w(answer embedding)
          _ -> ~w(answer)
        end

      for operation <- required, do: true = Enum.any?(wire, &(&1["operation"] == operation))

      if verified["plan"]["version"] == 3 do
        for request <- wire, request["operation"] in ~w(answer extraction rerank) do
          body = request["request"]
          %{"type" => "object"} = schema = body["format"]
          false = schema["additionalProperties"]

          if Contract.long_answers?(verified["plan"]) and request["operation"] == "answer" do
            false = Map.has_key?(body, "think")
            8192 = body["options"]["num_predict"]
          else
            false = body["think"]
            4096 = body["options"]["num_predict"]
          end

          input =
            body["messages"]
            |> List.last()
            |> Map.fetch!("content")
            |> String.split("\n", parts: 2)
            |> List.last()
            |> JSON.decode!()
            |> Map.fetch!("input")
            |> JSON.decode!()

          case request["operation"] do
            "extraction" ->
              ["facts"] = schema["required"]
              true = schema["properties"]["facts"]["maxItems"] == input["max_facts"]

              true =
                get_in(schema, ~w(properties facts items properties chunk enum)) ==
                  Enum.map(input["chunks"], & &1["id"])

            "rerank" ->
              ["order"] = schema["required"]
              true = get_in(schema, ~w(properties order minItems)) == input["required_count"]
              true = get_in(schema, ~w(properties order maxItems)) == input["required_count"]
              ids = Enum.map(input["candidates"], & &1["id"])

              true =
                get_in(schema, ~w(properties order items enum)) ==
                  if(ids == [], do: nil, else: ids)

            "answer" ->
              ~w(classification claims) = schema["required"]
              ids = Enum.map(input["candidates"], & &1["id"])

              true =
                get_in(schema, ~w(properties claims maxItems)) == if(ids == [], do: 0, else: 8)

              true =
                get_in(schema, ~w(properties claims items properties citations items enum)) ==
                  if(ids == [], do: nil, else: ids)
          end
        end
      end
    end
  end

  defp jsonl(bytes), do: bytes |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)

  def save!(path, bytes) do
    File.write!(path, bytes, [:exclusive, :sync])
    File.chmod!(path, 0o600)
    {:ok, :ok} = File.open(Path.dirname(path), [:read, :raw, :directory], &:file.sync/1)
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)
    if port == 11434, do: free_port(), else: port
  end

  defp snapshot(root) do
    Path.wildcard(Path.join(root, "**/*"))
    |> Enum.filter(&File.regular?/1)
    |> Map.new(fn path -> {path, Ipse.JSON.sha256(File.read!(path))} end)
  end
end

defmodule Ipse.Development.Verification.MeasuredKnowledge.Scoring do
  @moduledoc "Post-execution controls for the measured CLI audit and label boundary."
  alias Ipse.Development.Evaluation.{Freeze, MeasuredExecution, Runner}
  @log_limit 1_048_576

  def verify(run, result, repository) do
    root = Path.join(run.root, "scoring-controls")
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    for leaf <- ~w(home tmp), do: mkdir!(Path.join(root, leaf))
    {:ok, verified} = Freeze.verify(run.seal["path"], run.seal["sha256"])
    execution = MeasuredExecution.execution_context!(verified)
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
    {review, 0} = cli!(execution, repository, root, "review", :review, review_options)
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

    {score, 1} = cli!(execution, repository, root, "score", :score, score_options)
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

        {:error, %{"code" => actual}} = Runner.run(:score, options)
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

        {:error, %{"code" => actual}} = Runner.run(phase, change.(options))
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

  defp cli!(execution, repository, root, name, phase, options) do
    argv =
      ["--phase", Atom.to_string(phase)] ++
        Enum.flat_map(options, fn {key, value} ->
          ["--" <> (key |> Atom.to_string() |> String.replace("_", "-")), value]
        end)

    {executable, arguments} =
      case execution do
        {:source, launch} ->
          MeasuredExecution.command(
            launch,
            [Path.join(repository, "scripts/evaluate-knowledge.exs")],
            ":ok",
            argv
          )

        {:precompiled, _} ->
          MeasuredExecution.precompiled_command(
            execution,
            :cli,
            "Ipse.Development.Evaluation.CLI.main(System.argv())",
            argv
          )
      end

    launch =
      case execution do
        {:source, launch} -> launch
        {:precompiled, runtime} -> runtime["launch"]
      end

    selected =
      case execution do
        {:precompiled, _} ->
          MeasuredExecution.verification_environment(
            execution,
            Path.join(root, "home"),
            Path.join(root, "tmp")
          )

        {:source, _} ->
          %{
            "PATH" => Path.dirname(launch["executable"]) <> ":/usr/bin:/bin",
            "LANG" => "C.UTF-8",
            "HOME" => Path.join(root, "home"),
            "IPSE_HOME" => Path.join(root, "home/.ipse"),
            "TMPDIR" => Path.join(root, "tmp")
          }
      end

    environment =
      Map.new(Map.keys(System.get_env()), &{&1, nil})
      |> Map.merge(selected)
      |> Map.put("ERL_CRASH_DUMP", "/dev/null")
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
