# Post-execution proof only. No measure/run/provider entry is called here.
# Run main/1 in a fresh VM under the original fixture's selected runtime.
defmodule P27HistoricalVerification do
  alias IpseKnowledgeExample.{EvaluationFreeze, EvaluationMeasuredExecution, EvaluationResources}
  alias Ipse.Extensions.Manifest
  @predictor "914bc0ad7fd1794e0c9855a20d4548b961c309f4"
  @adapter "af62ee1731c8d0be7d0caa90347937498ea97083cb5749e5bfbcef0052e1358c"

  def main(argv) do
    try do
      result = verify!(argv)
      IO.puts(JSON.encode!(result))
    rescue
      error ->
        IO.puts(JSON.encode!(%{"status" => "failed", "class" => inspect(error.__struct__)}))
        System.halt(1)
    catch
      _, _ ->
        IO.puts(JSON.encode!(%{"status" => "failed", "code" => "verification_refused"}))
        System.halt(1)
    end
  end

  defp verify!([source, freeze, freeze_sha, checker, checker_commit, adapter, output]) do
    for path <- [source, freeze, checker, adapter, output],
        do: true = Path.type(path) == :absolute

    true = Regex.match?(~r/\A[0-9a-f]{64}\z/, freeze_sha)
    true = Regex.match?(~r/\A[0-9a-f]{40}\z/, checker_commit)
    @adapter = sha(read!(adapter, 1_048_576))
    true = :code.is_loaded(EvaluationMeasuredExecution) == false
    true = :code.is_loaded(IpseKnowledgeExample.EvaluationRunner) == false
    true = File.cwd!() == source
    Code.require_file(Path.join(source, "examples/knowledge/evaluation_plan.exs"))
    {:ok, verified} = EvaluationFreeze.verify(freeze, freeze_sha)
    @predictor = verified["manifest"]["source"]["commit"]
    ^source = verified["manifest"]["source"]["root"]
    2 = verified["manifest"]["version"]
    "fixture" = verified["plan"]["mode"]

    true =
      Enum.all?(verified["plan"]["profiles"], fn {_, profile} ->
        profile["model"] == "fixture-text:latest"
      end)

    true =
      Enum.all?(verified["plan"]["embedding_profiles"], fn {_, profile} ->
        profile["model"] == "fixture-embedding:latest"
      end)

    for {module, name} <- [
          {EvaluationMeasuredExecution, "evaluation_measured_execution.exs"},
          {IpseKnowledgeExample.EvaluationRunner, "evaluation_runner.exs"}
        ] do
      true =
        canonical!(to_string(module.module_info(:compile)[:source])) ==
          Path.join(source, "examples/knowledge/" <> name)
    end

    {:ok, original} = EvaluationMeasuredExecution.audit(freeze, freeze_sha)
    true = original["execution_complete"] and original["resource_complete"]
    350 = original["rows"]
    original_paths = :code.get_path()
    fixture = freeze |> Path.dirname() |> Path.dirname()
    reports = verified["resolution"]["reports"]
    true = reports == Path.join(fixture, "reports")
    data = Path.dirname(verified["resolution"]["data_manifest"])
    true = data == Path.join(fixture, "data")

    # One input set owns both output exclusion and final byte/identity closure.
    # Model inputs and original artifact directories may be outside the fixture.
    protected = protected_inputs!(verified, checker, fixture, adapter, __ENV__.file)

    output = new_output!(output, protected)
    mkdir!(output)
    for name <- ~w(calls inputs logs home tmp), do: mkdir!(Path.join(output, name))
    save!(Path.join(output, "verifier-source.exs"), read!(__ENV__.file, 1_048_576))
    save!(Path.join(output, "adapter-source.exs"), read!(adapter, 1_048_576))
    save!(Path.join(output, "original-audit.json"), encode(original))
    initial = snapshot!(fixture)
    initial_inputs = snapshot_roots!(protected)

    context = %{
      source: source,
      freeze: freeze,
      freeze_sha: freeze_sha,
      checker: checker,
      checker_commit: checker_commit,
      adapter: adapter,
      output: output,
      verified: verified,
      fixture: fixture,
      original: original
    }

    {positive, 0, packet_root} = invoke!(context, "positive-review", :review)
    true = positive["reference_integrity_complete"] and positive["rows"] == 350
    packet = Path.join(packet_root, "packet")
    manifest = json!(read!(Path.join(packet, "manifest.json"), 1_048_576))
    ^freeze_sha = manifest["execution_freeze_sha256"]
    true = manifest["data_manifest_sha256"] == verified["plan"]["data"]["manifest_sha256"]

    for {name, hash} <- manifest["files"],
        do: true = sha(read!(Path.join(packet, name), 33_554_432)) == hash

    template = json!(read!(Path.join(packet, "reviews-template.json"), 33_554_432))
    2 = template["version"]
    true = template["review_binding_sha256"] == manifest["review_binding_sha256"]

    for secret <-
          Enum.map(verified["plan"]["variants"], & &1["id"]) ++ [verified["plan"]["blind_seed"]] do
      for path <- Path.wildcard(Path.join(packet, "*")) do
        false = String.contains?(read!(path, 33_554_432), JSON.encode!(secret))
      end
    end

    template_file = Path.join(output, "inputs/template.json")
    save!(template_file, encode(template))
    {unmeasured, 1, score_root} = invoke!(context, "unmeasured-score", :score, template_file)
    false = unmeasured["quality_measured"]
    false = unmeasured["quality_gates_passed"]
    "unmeasured" = unmeasured["gates"]["support"]["status"]
    true = File.regular?(Path.join(score_root, "scores.json"))
    true = initial == snapshot!(fixture)

    # Every negative child still runs the actual private entry in a fresh VM.
    native_files = [
      Path.join(Path.dirname(freeze), "native-authority.bin"),
      Path.join(Path.dirname(freeze), "bootstrap.bin"),
      Path.join(Path.dirname(freeze), "launch/protocol.bin"),
      Path.join(Path.dirname(freeze), "native-root/sequence/stage-001.protocol"),
      Path.join(Path.dirname(freeze), "native-root/sequence/stage-001.receipt-identity"),
      Path.join(Path.dirname(freeze), "native-root/sequence/stage-001.status"),
      Path.join(Path.dirname(freeze), "native-root/prepared/population.json"),
      Path.join(reports, "cells/cell-000/model-service/receipt.json"),
      Path.join(reports, "cells/cell-000/domain/usage.jsonl")
    ]

    native_cases =
      for {path, index} <- Enum.with_index(native_files) do
        mutate!(fixture, [{path, read!(path, 67_108_864) <> " "}], fn ->
          {:error, _} = EvaluationMeasuredExecution.audit(freeze, freeze_sha)
          {failed, 1, child_output} = invoke!(context, "native-#{index}", :review)
          "failed" = failed["status"]
          false = File.exists?(Path.join(child_output, "packet"))
          false = File.exists?(Path.join(child_output, "evidence/resource-supplement.json"))
        end)

        Path.relative_to(path, fixture)
      end

    merged_cases =
      for {name, index} <-
            Enum.with_index(
              ~w(predictions.jsonl execution.jsonl usage.jsonl request-resources.jsonl resources.jsonl timings.jsonl)
            ) do
        path = Path.join(reports, name)

        mutate!(fixture, [{path, read!(path, 67_108_864) <> " "}], fn ->
          {failed, 1, child_output} = invoke!(context, "merged-#{index}", :review)
          "failed" = failed["status"]
          false = File.exists?(Path.join(child_output, "packet"))
          false = File.exists?(Path.join(child_output, "evidence/resource-supplement.json"))
        end)

        name
      end

    coherent_cases =
      for name <- ~w(timings.jsonl request-resources.jsonl) do
        path = Path.join(reports, name)
        original_stream = read!(path, 67_108_864)

        changed =
          if name == "timings.jsonl",
            do:
              original_stream
              |> jsonl!()
              |> Enum.map(&Map.put(&1, "elapsed_us", 0))
              |> Enum.map_join("", &encode/1),
            else: ""

        true = changed != original_stream
        summary_path = Path.join(reports, "resource-summary.json")
        original_summary = read!(summary_path, 67_108_864)
        # Recompute before mutation from one coherent map, never from mixed rereads.
        streams =
          Map.new(
            ~w(predictions.jsonl timings.jsonl request-resources.jsonl usage.jsonl resources.jsonl),
            fn file ->
              {file,
               if(file == name, do: changed, else: read!(Path.join(reports, file), 67_108_864))}
            end
          )

        summary =
          EvaluationResources.summary(
            jsonl!(streams["predictions.jsonl"]),
            jsonl!(streams["timings.jsonl"]),
            jsonl!(streams["request-resources.jsonl"]),
            Enum.filter(jsonl!(streams["usage.jsonl"]), &Map.has_key?(&1, "budget")),
            jsonl!(streams["resources.jsonl"])
          )

        true = summary["complete"] and summary["storage_reachability_complete"]
        true = summary != json!(original_summary)

        mutate!(fixture, [{path, changed}, {summary_path, encode(summary)}], fn ->
          {:ok, old_acceptance} = EvaluationMeasuredExecution.audit(freeze, freeze_sha)
          true = old_acceptance["execution_complete"] and old_acceptance["resource_complete"]
          {failed, 1, child_output} = invoke!(context, "coherent-" <> name, :review)
          "merged_stream_changed" = failed["code"]
          true = File.regular?(Path.join(child_output, "evidence/original-audit.json"))
          false = File.exists?(Path.join(child_output, "evidence/resource-supplement.json"))
          false = File.exists?(Path.join(child_output, "packet"))
        end)

        name
      end

    # Move only synthetic query bytes out of the fixture. Old audit must still
    # pass; a binding-valid score must fail labels while invalid binding refuses
    # earlier with its exact code. Restore the original inode and bytes afterward.
    query = Path.join(data, verified["plan"]["data"]["queries"])
    retained = Path.join(output, "inputs/temporarily-retained-queries.json")
    query_before = snapshot!(fixture)
    File.rename!(query, retained)

    binding_cases =
      try do
        {:ok, _} = EvaluationMeasuredExecution.audit(freeze, freeze_sha)
        absent_snapshot = snapshot!(fixture)

        cases =
          for {name, code, review} <- [
                {"wrong", "review_binding_mismatch",
                 Map.put(
                   template,
                   "review_binding_sha256",
                   different_hash(template["review_binding_sha256"])
                 )},
                {"missing", "invalid_reviews", Map.delete(template, "review_binding_sha256")},
                {"legacy", "invalid_reviews", Map.put(template, "version", 1)},
                {"extra", "invalid_reviews", Map.put(template, "extra", true)}
              ] do
            file = Path.join(output, "inputs/review-" <> name <> ".json")
            save!(file, encode(review))
            {failed, 1, child_output} = invoke!(context, "binding-" <> name, :score, file)
            ^code = failed["code"]
            false = File.exists?(Path.join(child_output, "scores.json"))
            true = absent_snapshot == snapshot!(fixture)
            %{"case" => name, "code" => code}
          end

        {failed, 1, child_output} =
          invoke!(context, "binding-valid-missing-labels", :score, template_file)

        "labels_failed" = failed["code"]
        false = File.exists?(Path.join(child_output, "scores.json"))
        true = absent_snapshot == snapshot!(fixture)
        cases
      after
        File.rename!(retained, query)
      end

    true = query_before == snapshot!(fixture)

    {failed, 1, bad_checker_output} =
      invoke!(context, "wrong-checker-identity", :review, nil,
        checker_commit: different_hash(checker_commit)
      )

    "failed" = failed["status"]
    false = File.exists?(bad_checker_output)
    true = initial == snapshot!(fixture)
    # Repeat the read-only positive after all exact restores, never measurement.
    {restored, 0, restored_root} = invoke!(context, "restored-positive", :review)
    true = restored["packet_sha256"] == positive["packet_sha256"]
    true = File.regular?(Path.join(restored_root, "packet/manifest.json"))
    true = initial == snapshot!(fixture)
    {:ok, ^verified} = EvaluationFreeze.verify(freeze, freeze_sha)
    {:ok, ^original} = EvaluationMeasuredExecution.audit(freeze, freeze_sha)
    true = :code.get_path() == original_paths
    @adapter = sha(read!(adapter, 1_048_576))
    true = initial_inputs == snapshot_roots!(protected)
    save!(Path.join(output, "protected-fixture-snapshot.json"), encode(initial))
    save!(Path.join(output, "protected-inputs-snapshot.json"), encode(initial_inputs))

    receipt = %{
      "version" => 1,
      "status" => "passed",
      "synthetic" => true,
      "model_quality_measured" => false,
      "predictor_commit" => @predictor,
      "checker_commit" => checker_commit,
      "adapter_sha256" => @adapter,
      "freeze_sha256" => freeze_sha,
      "original_audit_sha256" => original["sha256"],
      "prediction_sha256" => original["prediction_sha256"],
      "rows" => 350,
      "packet_sha256" => positive["packet_sha256"],
      "native_corruptions" => native_cases,
      "merged_stream_corruptions" => merged_cases,
      "coherent_rewrites" => coherent_cases,
      "binding_refusals_before_absent_labels" => binding_cases,
      "valid_binding_missing_labels_refused" => true,
      "wrong_checker_identity_refused" => true,
      "original_verification_and_ordered_paths_unchanged" => true,
      "protected_fixture_and_request_claim_files_unchanged" => true,
      "protected_input_roots" => protected,
      "protected_input_files_and_identities_unchanged" => true,
      "restored_positive_packet_identical" => true,
      "new_measure_or_provider_calls" => 0
    }

    save!(Path.join(output, "verification.json"), encode(receipt))
    receipt
  end

  defp invoke!(context, name, phase, reviews \\ nil, overrides \\ []) do
    target = Path.join(context.output, "calls/" <> name)

    argv = [
      Atom.to_string(phase),
      "--sealed-source",
      context.source,
      "--freeze",
      context.freeze,
      "--freeze-sha256",
      context.freeze_sha,
      "--checker-root",
      context.checker,
      "--checker-commit",
      Keyword.get(overrides, :checker_commit, context.checker_commit),
      "--output",
      target
    ]

    argv = if phase == :score, do: argv ++ ["--reviews", reviews], else: argv
    @adapter = sha(read!(context.adapter, 1_048_576))

    {executable, args} =
      EvaluationMeasuredExecution.command(
        context.verified["manifest"]["runtime"]["launch"],
        [context.adapter],
        "P27HistoricalJudgment.main(System.argv())",
        argv
      )

    environment =
      Map.new(Map.keys(System.get_env()), &{&1, nil})
      |> Map.merge(%{
        "PATH" => Path.dirname(executable) <> ":/usr/bin:/bin",
        "LANG" => "C.UTF-8",
        "HOME" => Path.join(context.output, "home"),
        "IPSE_HOME" => Path.join(context.output, "home/.ipse"),
        "TMPDIR" => Path.join(context.output, "tmp"),
        "ERL_CRASH_DUMP" => "/dev/null"
      })
      |> Map.to_list()

    {raw, status} =
      System.cmd(executable, args, cd: context.source, env: environment, stderr_to_stdout: true)

    true = byte_size(raw) <= 1_048_576
    save!(Path.join(context.output, "logs/" <> name <> ".log"), raw)
    message = raw |> String.split("\n", trim: true) |> List.last() |> json!()
    @adapter = sha(read!(context.adapter, 1_048_576))
    {message, status, target}
  end

  defp mutate!(fixture, replacements, action) do
    before = snapshot!(fixture)

    originals =
      Enum.map(replacements, fn {path, _} ->
        true = String.starts_with?(canonical!(path), fixture <> "/")
        {path, read!(path, 67_108_864)}
      end)

    try do
      for {path, raw} <- replacements, do: File.write!(path, raw)
      changed = snapshot!(fixture)
      action.()
      true = changed == snapshot!(fixture)
    after
      for {path, raw} <- originals, do: File.write!(path, raw)
    end

    true = before == snapshot!(fixture)
  end

  defp protected_inputs!(verified, checker, fixture, adapter, verifier) do
    resolution = verified["resolution"]
    runtime = verified["manifest"]["runtime"]["launch"]
    service = resolution["model_service"]

    roots =
      [
        verified["manifest"]["source"]["root"],
        checker,
        fixture,
        runtime["root"],
        service["cache_source"],
        adapter,
        verifier
      ] ++
        runtime["code_paths"] ++
        Map.values(resolution["artifacts"]) ++
        Enum.map(service["runtime"]["files"], & &1["source"])

    roots = roots |> Enum.map(&canonical!/1) |> Enum.uniq() |> Enum.sort()
    true = length(roots) in 1..128

    Enum.reject(roots, fn root ->
      Enum.any?(roots, fn parent ->
        parent != root and String.starts_with?(root, parent <> "/")
      end)
    end)
  end

  defp snapshot!(root), do: snapshot_roots!([root])

  defp snapshot_roots!(roots) do
    paths =
      Enum.flat_map(roots, fn root ->
        case File.lstat!(root) do
          %{type: :directory} -> [root | Path.wildcard(Path.join(root, "**/*"), match_dot: true)]
          _ -> [root]
        end
      end)
      |> Enum.uniq()
      |> Enum.sort()

    true = length(paths) <= 65_536

    total =
      Enum.reduce(paths, 0, fn path, bytes ->
        case File.lstat!(path) do
          %{type: :regular, size: size} -> bytes + size
          _ -> bytes
        end
      end)

    true = total <= 1_073_741_824

    Map.new(paths, fn path ->
      stat = File.lstat!(path)
      identity = Map.take(stat, [:type, :major_device, :inode, :uid, :gid, :mode])

      record =
        case stat.type do
          :regular ->
            true = stat.size <= 67_108_864

            hash =
              File.stream!(path, 1_048_576, [])
              |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
              |> :crypto.hash_final()
              |> Base.encode16(case: :lower)

            Map.merge(identity, %{bytes: stat.size, sha256: hash})

          :symlink ->
            Map.put(identity, :target, File.read_link!(path))

          _ ->
            identity
        end

      {path, record}
    end)
  end

  defp new_output!(requested, protected) do
    target = canonical!(requested)
    %{type: :directory} = File.lstat!(Path.dirname(target))

    for root <- protected do
      root = canonical!(root)

      false =
        target == root or String.starts_with?(target, root <> "/") or
          String.starts_with?(root, target <> "/")
    end

    {:error, :enoent} = File.lstat(target)
    target
  end

  defp canonical!(path) do
    {:ok, result} = Ipse.WorkspaceContext.canonical_path(path)
    result
  end

  defp read!(path, limit) do
    %{type: :regular, size: size} = File.lstat!(path)
    true = size <= limit
    {:ok, bytes} = File.open(path, [:read, :binary], &IO.binread(&1, limit + 1))
    bytes = if bytes == :eof, do: "", else: bytes
    true = is_binary(bytes) and byte_size(bytes) == size and size <= limit
    bytes
  end

  defp mkdir!(path) do
    File.mkdir!(path)
    File.chmod!(path, 0o700)
  end

  defp save!(path, bytes) do
    File.write!(path, bytes, [:exclusive, :sync])
    File.chmod!(path, 0o600)
  end

  defp json!(raw) do
    {:ok, value} = Ipse.JSON.decode_unique(raw)
    value
  end

  defp jsonl!(raw), do: raw |> String.split("\n", trim: true) |> Enum.map(&json!/1)
  defp encode(value), do: JSON.encode!(value) <> "\n"
  defp sha(raw), do: Manifest.sha256(raw)

  defp different_hash(<<first, tail::binary>>),
    do: <<if(first == ?0, do: ?1, else: ?0), tail::binary>>
end
