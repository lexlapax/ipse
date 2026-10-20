defmodule MeasuredKnowledgeVerification do
  @moduledoc false
  alias IpseKnowledgeExample.{
    EvaluationFreeze,
    EvaluationPlan,
    EvaluationRunner,
    EvaluationMeasuredExecution
  }

  @variants ~w(lexical graph_explicit graph_model dense hybrid rerank research)

  def build_artifacts(root, repository) do
    {:ok, launch} = EvaluationFreeze.runtime_launch()
    File.mkdir!(root)
    File.chmod!(root, 0o700)

    Map.new(
      [
        {"lexical", "corpus", "state-lexical"},
        {"dense", "corpus", "state-dense"},
        {"semantic", "corpus", "state-semantic"},
        {"explicit", "graph", "state-explicit"},
        {"model", "graph", "state-model"},
        {"research", "research", "mcp"},
        {"answer", nil, nil}
      ],
      fn {name, package, preset} ->
        output = Path.join(root, name)

        script =
          if package, do: "extensions/knowledge/build.exs", else: "examples/model-calls/build.exs"

        argv = ["--sdk", Application.app_dir(:ipse, "ebin"), "--output", output]
        argv = if package, do: argv ++ ["--package", package, "--preset", preset], else: argv

        {executable, args} =
          EvaluationMeasuredExecution.command(
            launch,
            [Path.join(repository, script)],
            ":ok",
            argv
          )

        {log, code} =
          System.cmd(executable, args,
            cd: repository,
            env: [{"ERL_CRASH_DUMP", "/dev/null"}],
            stderr_to_stdout: true
          )

        save!(Path.join(root, name <> ".build.log"), log)
        unless code == 0, do: raise("synthetic artifact build failed: " <> name)
        {name, output}
      end
    )
  end

  def prepare(root, repository, artifacts, fault \\ nil, contract \\ nil) do
    true = contract in [nil, "sealed_answers_v1"]
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    {:ok, launch} = EvaluationFreeze.runtime_launch()
    origin = "http://127.0.0.1:#{free_port()}"
    search_port = free_port()
    true = search_port != URI.parse(origin).port
    service = MeasuredModelFixture.configuration(root, launch, origin, fault)
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
      |> Map.put("version", 2)
      |> Map.put("model_origin", origin)
      |> Map.put("models", service["models"])

    spec =
      if contract,
        do:
          spec |> put_in(["data", "contract"], contract) |> put_in(["data", "split"], "heldout"),
        else: spec

    {:ok, plan} = EvaluationPlan.build(spec)

    :ok = EvaluationRunner.validate(plan)
    {:ok, experiment} = EvaluationFreeze.declare(repository, JSON.encode!(plan), artifacts)

    resolution = %{
      "artifacts" => artifacts,
      "model_origin" => origin,
      "search_port" => search_port,
      "reports" => Path.join(root, "reports"),
      "data_manifest" => data_path,
      "model_service" => service
    }

    {:ok, seal} =
      EvaluationFreeze.create_v2(
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
      EvaluationMeasuredExecution.run(freeze: run.seal["path"], freeze_sha256: run.seal["sha256"])

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
    {:ok, ^result} = EvaluationMeasuredExecution.audit(run.seal["path"], run.seal["sha256"])
    if run.answers, do: false = File.exists?(run.labels)
    true = snapshot(run.root) == before
    save!(Path.join(run.root, "verified-audit.json"), JSON.encode!(result))
    before = snapshot(run.root)

    {:error, _} =
      EvaluationMeasuredExecution.run(freeze: run.seal["path"], freeze_sha256: run.seal["sha256"])

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
        {:error, _} = EvaluationMeasuredExecution.audit(run.seal["path"], run.seal["sha256"])
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
          IpseKnowledgeExample.EvaluationResources.summary(
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
        {:error, error} = EvaluationMeasuredExecution.audit(run.seal["path"], run.seal["sha256"])
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
          EvaluationMeasuredExecution.run(
            freeze: run.seal["path"],
            freeze_sha256: run.seal["sha256"]
          )

        {:error, _} = EvaluationMeasuredExecution.audit(run.seal["path"], run.seal["sha256"])
        true = snapshot(run.root) == changed
      after
        File.rmdir!(directory)
        File.rename!(retained, directory)
      end

      true = snapshot(run.root) == before
    end

    {:ok, _} = EvaluationMeasuredExecution.audit(run.seal["path"], run.seal["sha256"])

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
    {:ok, verified} = EvaluationFreeze.verify(run.seal["path"], run.seal["sha256"])
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
