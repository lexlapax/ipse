# Private historical bridge. Define only; launch main/1 in a fresh original VM.
# The former standalone supplemental reader remains an unaccepted draft.
defmodule P27HistoricalJudgment do
  alias IpseKnowledgeExample.{
    EvaluationFreeze,
    EvaluationMeasuredExecution,
    EvaluationRunner,
    EvaluationResources,
    EvaluationInput,
    EvaluationReview
  }

  alias IpseKnowledge.EvaluationScore
  alias Ipse.Extensions.Manifest
  @predictor_commit "914bc0ad7fd1794e0c9855a20d4548b961c309f4"
  @score_limit 536_870_912
  @module_files %{
    IpseKnowledgeExample.EvaluationRunner => "evaluation_runner.exs",
    IpseKnowledgeExample.EvaluationFreeze => "evaluation_freeze.exs",
    IpseKnowledgeExample.EvaluationMeasuredExecution => "evaluation_measured_execution.exs",
    IpseKnowledgeExample.EvaluationResources => "evaluation_resources.exs",
    IpseKnowledgeExample.EvaluationInput => "evaluation_input.exs",
    IpseKnowledgeExample.EvaluationReview => "evaluation_review.exs",
    IpseKnowledge.EvaluationScore => "evaluation_score.exs",
    IpseKnowledge.Metrics => "metrics.exs"
  }

  defmodule Request do
    @enforce_keys [
      :phase,
      :sealed_source,
      :freeze,
      :freeze_sha256,
      :checker_root,
      :checker_commit,
      :output
    ]
    defstruct @enforce_keys ++ [reviews: nil]
  end

  defmodule References do
    @enforce_keys [
      :manifest_path,
      :manifest_sha256,
      :members,
      :corpus_member,
      :queries_member,
      :split,
      :as_of_ms
    ]
    defstruct @enforce_keys
  end

  defmodule Admission do
    @enforce_keys [
      :declaration,
      :prediction_bytes,
      :binding_sha256,
      :references,
      :blind_seed,
      :provenance,
      :protected,
      :output
    ]
    defstruct @enforce_keys
  end

  def main(argv) do
    result =
      try do
        request = parse!(argv)
        admission = admit!(request)
        judge!(admission, request)
      rescue
        error ->
          IO.puts(JSON.encode!(%{"status" => "failed", "class" => inspect(error.__struct__)}))
          1
      catch
        {owner, code}
        when owner in [:historical_judgment, :evaluation_runner] and is_atom(code) ->
          IO.puts(JSON.encode!(%{"status" => "failed", "code" => Atom.to_string(code)}))
          1

        _, _ ->
          IO.puts(JSON.encode!(%{"status" => "failed", "code" => "unexpected_failure"}))
          1
      end

    System.halt(result)
  end

  defp parse!([phase | argv]) when phase in ["review", "score"] do
    require!(
      length(argv) <= 16 and Enum.all?(argv, &(is_binary(&1) and byte_size(&1) <= 8192)),
      :arguments
    )

    {options, [], []} =
      OptionParser.parse(argv,
        strict: [
          sealed_source: :string,
          freeze: :string,
          freeze_sha256: :string,
          checker_root: :string,
          checker_commit: :string,
          output: :string,
          reviews: :string
        ]
      )

    keys =
      ~w(sealed_source freeze freeze_sha256 checker_root checker_commit output)a ++
        if(phase == "score", do: [:reviews], else: [])

    require!(length(argv) == 2 * length(keys), :arguments)
    require!(Enum.sort(Keyword.keys(options)) == Enum.sort(keys), :arguments)

    for key <-
          ~w(sealed_source freeze checker_root output)a ++
            if(phase == "score", do: [:reviews], else: []),
        do: require!(Path.type(options[key]) == :absolute, :absolute_path_required)

    require!(Regex.match?(~r/\A[0-9a-f]{64}\z/, options[:freeze_sha256]), :freeze_hash)
    require!(Regex.match?(~r/\A[0-9a-f]{40}\z/, options[:checker_commit]), :checker_commit)
    struct!(Request, options ++ [phase: String.to_existing_atom(phase)])
  end

  defp parse!(_), do: fail!(:arguments)

  defp admit!(request) do
    Enum.each(Map.keys(@module_files) ++ [IpseKnowledgeExample.EvaluationPlan], fn module ->
      require!(:code.is_loaded(module) == false, :fresh_vm_required)
    end)

    [sealed_source, freeze_path, freeze_sha, checker_root, checker_commit, output] =
      [
        request.sealed_source,
        request.freeze,
        request.freeze_sha256,
        request.checker_root,
        request.checker_commit,
        request.output
      ]

    for path <- [sealed_source, freeze_path, checker_root, output],
        do: true = Path.type(path) == :absolute

    for digest <- [freeze_sha, checker_commit],
        do: true = Regex.match?(~r/\A[0-9a-f]{40}(?:[0-9a-f]{24})?\z/, digest)

    true = byte_size(freeze_sha) == 64
    true = byte_size(checker_commit) == 40
    true = File.cwd!() == sealed_source

    Code.require_file(Path.join(sealed_source, "examples/knowledge/evaluation_plan.exs"))

    read = fn path, limit ->
      %{type: :regular, size: size} = File.lstat!(path)
      true = size <= limit
      {:ok, bytes} = File.open(path, [:read, :binary], &IO.binread(&1, limit + 1))
      bytes = if bytes == :eof, do: "", else: bytes
      true = is_binary(bytes) and byte_size(bytes) == size and size <= limit
      bytes
    end

    json = fn bytes ->
      {:ok, value} = Ipse.JSON.decode_unique(bytes)
      value
    end

    jsonl = fn bytes -> bytes |> String.split("\n", trim: true) |> Enum.map(json) end
    encode = fn value -> JSON.encode!(value) <> "\n" end
    sha = &Manifest.sha256/1

    save = fn path, bytes ->
      File.write!(path, bytes, [:exclusive, :sync])
      File.chmod!(path, 0o600)
    end

    {:ok, verified} = EvaluationFreeze.verify(freeze_path, freeze_sha)
    2 = verified["manifest"]["version"]
    @predictor_commit = verified["manifest"]["source"]["commit"]
    ^sealed_source = verified["manifest"]["source"]["root"]
    reports = verified["resolution"]["reports"]
    freeze_root = Path.dirname(freeze_path)

    # The caller owns a stable private parent. Resolve aliases before checking or
    # writing; this is not a retained-directory guarantee against hostile renames.
    canonical_output = fn requested, protected_paths ->
      canonical = fn path ->
        true = is_binary(path) and Path.type(path) == :absolute
        {:ok, resolved} = Ipse.WorkspaceContext.canonical_path(path)
        resolved
      end

      target = canonical.(requested)
      %{type: :directory} = File.lstat!(Path.dirname(target))

      for path <- protected_paths do
        protected = canonical.(path)

        false =
          target == protected or String.starts_with?(target, protected <> "/") or
            String.starts_with?(protected, target <> "/")
      end

      {:error, :enoent} = File.lstat(target)
      target
    end

    protected =
      [
        sealed_source,
        checker_root,
        freeze_root,
        reports,
        Path.dirname(verified["resolution"]["data_manifest"]),
        verified["resolution"]["model_service"]["cache_source"],
        verified["manifest"]["runtime"]["launch"]["root"]
      ] ++ verified["manifest"]["runtime"]["launch"]["code_paths"]

    output = canonical_output.(output, protected)
    {:ok, checker_root} = Ipse.WorkspaceContext.canonical_path(checker_root)

    # This is the original immutable audit, before any corrective module is loaded.
    {:ok, original} = EvaluationMeasuredExecution.audit(freeze_path, freeze_sha)
    true = original["execution_complete"] and original["resource_complete"]
    ^freeze_sha = original["report"]["freeze_sha256"]
    true = sha.(encode.(original["report"])) == original["sha256"]
    original_paths = :code.get_path()

    # Retain exact checker identity before executing its trusted repository modules.
    git = fn args ->
      {bytes, 0} = System.cmd("git", ["--no-optional-locks", "-C", checker_root | args])
      String.trim(bytes)
    end

    ^checker_commit = git.(["rev-parse", "HEAD"])
    "" = git.(["status", "--porcelain=v1", "--untracked-files=all"])

    {listed, 0} =
      System.cmd("git", ["--no-optional-locks", "-C", checker_root, "ls-files", "-z", "--cached"])

    files = String.split(listed, <<0>>, trim: true) |> Enum.sort()
    true = length(files) in 1..4096

    checker_files =
      Enum.map(files, fn relative ->
        true =
          Path.type(relative) == :relative and
            Enum.all?(Path.split(relative), &(&1 not in ["", ".", ".."]))

        bytes = read.(Path.join(checker_root, relative), 67_108_864)
        %{"path" => relative, "bytes" => byte_size(bytes), "sha256" => sha.(bytes)}
      end)

    checker = %{
      "commit" => checker_commit,
      "tree" => git.(["rev-parse", "HEAD^{tree}"]),
      "files" => checker_files
    }

    self = read.(__ENV__.file, 1_048_576)
    File.mkdir!(output)
    File.chmod!(output, 0o700)
    evidence = Path.join(output, "evidence")
    File.mkdir!(evidence)
    File.chmod!(evidence, 0o700)
    save.(Path.join(evidence, "original-audit.json"), encode.(original))
    save.(Path.join(evidence, "checker-source.json"), encode.(checker))
    save.(Path.join(evidence, "adapter-source.exs"), self)

    try do
      # Current Runner provides only its read-only join/domain helpers here. Its
      # current Measured module may be loaded transitively but is never invoked.
      Code.require_file(Path.join(checker_root, "examples/knowledge/evaluation_runner.exs"))
      module_origins!(checker_root)
      true = :code.get_path() == original_paths
      {:ok, ^verified} = EvaluationFreeze.verify(freeze_path, freeze_sha)
      native = Path.join(freeze_root, "native-root")
      population_bytes = read.(Path.join(native, "prepared/population.json"), 67_108_864)
      true = sha.(population_bytes) == original["report"]["prepared_sha256"]
      population = json.(population_bytes)
      ^freeze_sha = population["freeze_sha256"]
      true = population["original_plan"] == verified["plan"]
      {:ok, schedule} = EvaluationRunner.schedule(verified["plan"], population["queries"])
      ^schedule = population["schedule"]
      14 = length(schedule["cells"])
      stages = Map.new(original["report"]["stages"], &{&1["name"], &1})

      cells =
        Enum.map(schedule["cells"], fn cell ->
          cell_root = Path.join(reports, "cells/" <> cell["id"])
          result_bytes = read.(Path.join(cell_root, "cell-result.json"), 67_108_864)
          result = json.(result_bytes)
          true = sha.(encode.(result)) == stages[cell["id"]]["domain_sha256"]
          true = result["complete"]
          domain_root = Path.join(cell_root, "domain")
          domain = read.(Path.join(domain_root, "domain-result.json"), 67_108_864) |> json.()
          true = result["domain"] == domain
          :ok = EvaluationRunner.audit_cell(domain_root, domain)

          %{
            path: domain_root,
            identity: %{
              "cell" => cell["id"],
              "domain_sha256" => sha.(encode.(domain)),
              "outcome_sha256" => sha.(encode.(result)),
              "files" => domain["files"]
            }
          }
        end)

      streams = EvaluationRunner.audit_merged_files(Enum.map(cells, & &1.path), reports)
      predictions = Map.fetch!(streams, "predictions.jsonl")
      true = sha.(predictions) == original["prediction_sha256"]
      rows = jsonl.(predictions)
      true = length(rows) == original["rows"] and original["rows"] == 350

      summary =
        EvaluationResources.summary(
          rows,
          jsonl.(streams["timings.jsonl"]),
          jsonl.(streams["request-resources.jsonl"]),
          Enum.filter(jsonl.(streams["usage.jsonl"]), &Map.has_key?(&1, "budget")),
          jsonl.(streams["resources.jsonl"])
        )

      true = summary == json.(read.(Path.join(reports, "resource-summary.json"), 67_108_864))
      true = summary["complete"] and summary["storage_reachability_complete"]

      receipt = %{
        "version" => 1,
        "kind" => "supplemental_closed_cell_resource_join",
        "execution_id" => original["report"]["execution_id"],
        "freeze_sha256" => freeze_sha,
        "predictor_commit" => verified["manifest"]["source"]["commit"],
        "original_audit_sha256" => original["sha256"],
        "checker_commit" => checker_commit,
        "checker_source_sha256" => sha.(encode.(checker)),
        "reader_sha256" => sha.(self),
        "prepared_sha256" => sha.(population_bytes),
        "cells" => Enum.map(cells, & &1.identity),
        "merged_files" =>
          Map.new(streams, fn {name, bytes} ->
            {name, %{"bytes" => byte_size(bytes), "sha256" => sha.(bytes)}}
          end),
        "resource_summary_sha256" => sha.(encode.(summary)),
        "rows" => length(rows),
        "resource_join_complete" => true,
        "quality_measured" => false,
        "original_evidence_modified" => false,
        "new_model_requests" => 0
      }

      bytes = encode.(receipt)
      save.(Path.join(evidence, "resource-supplement.json"), bytes)

      subject!(
        request,
        verified,
        original,
        population,
        streams,
        checker,
        receipt,
        self,
        protected,
        output
      )
    rescue
      error ->
        save.(
          Path.join(output, "failure.json"),
          encode.(%{
            "status" => "failed",
            "class" => inspect(error.__struct__),
            "quality_measured" => false
          })
        )

        reraise error, __STACKTRACE__
    catch
      kind, reason ->
        save.(
          Path.join(output, "failure.json"),
          encode.(%{"status" => "failed", "class" => inspect(kind), "quality_measured" => false})
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp module_origins!(checker_root) do
    Enum.each(@module_files, fn {module, relative} ->
      source = module.module_info(:compile) |> Keyword.fetch!(:source) |> to_string()

      require!(
        canonical!(source) == Path.join([checker_root, "examples/knowledge", relative]),
        :module_origin
      )
    end)
  end

  defp subject!(
         request,
         verified,
         original,
         population,
         streams,
         checker,
         receipt,
         self,
         protected,
         output
       ) do
    plan = verified["plan"]
    :ok = EvaluationRunner.validate(plan)
    bytes = Map.fetch!(streams, "predictions.jsonl")

    saved =
      read!(Path.join(verified["resolution"]["reports"], "finalized.json"), 67_108_864) |> json!()

    variants = Enum.map(plan["variants"], & &1["id"])
    queries = Enum.map(population["queries"], &Map.take(&1, ~w(query_id project)))
    require!(saved["variants"] == variants and saved["queries"] == queries, :scoring_grid)

    require!(
      saved["prediction_sha256"] == sha(bytes) and original["prediction_sha256"] == sha(bytes),
      :prediction_identity
    )

    require!(
      saved["freeze_sha256"] == request.freeze_sha256 and
        saved["data_manifest_sha256"] == plan["data"]["manifest_sha256"],
      :prediction_context
    )

    require!(length(variants) == 7 and length(queries) == 50, :historical_grid)

    declaration = %{
      "version" => 2,
      "context_sha256" => request.freeze_sha256,
      "metric_version" => 1,
      "variants" => variants,
      "baseline" => "lexical",
      "queries" => queries,
      "files" => [%{"id" => "predictions", "sha256" => sha(bytes)}],
      "classification_map" => Map.new(~w(answer conflict open abstain), &{&1, &1})
    }

    binding = full_grid!(declaration, bytes)
    manifest = population["data_manifest"]
    require!(manifest["sha256"] == plan["data"]["manifest_sha256"], :data_manifest_identity)
    members = manifest["members"]
    require!(is_list(members) and length(members) in 1..4096, :data_members)
    require!(length(members) == length(Enum.uniq_by(members, & &1["path"])), :data_members)

    for member <- members do
      require!(is_map(member) and Enum.sort(Map.keys(member)) == ~w(path sha256), :data_member)
      require!(relative?(member["path"]) and hash?(member["sha256"]), :data_member)
    end

    for key <- ~w(corpus queries),
        do: require!(Enum.count(members, &(&1["path"] == plan["data"][key])) == 1, :data_member)

    at = if plan["as_of_ms"] == "manifest", do: manifest["as_of_ms"], else: plan["as_of_ms"]

    require!(
      is_integer(at) and at >= 0 and population["effective_as_of_ms"] == at,
      :effective_time
    )

    references = %References{
      manifest_path: verified["resolution"]["data_manifest"],
      manifest_sha256: manifest["sha256"],
      members: members,
      corpus_member: plan["data"]["corpus"],
      queries_member: plan["data"]["queries"],
      split: plan["data"]["split"],
      as_of_ms: at
    }

    provenance = %{
      "version" => 1,
      "predictor_commit" => @predictor_commit,
      "checker_commit" => checker["commit"],
      "checker_source_sha256" => sha(encode(checker)),
      "original_audit_sha256" => original["sha256"],
      "supplement_sha256" => sha(encode(receipt)),
      "adapter_sha256" => sha(self),
      "execution_freeze_sha256" => request.freeze_sha256,
      "data_manifest_sha256" => references.manifest_sha256,
      "review_binding_sha256" => binding,
      "prediction_sha256" => sha(bytes),
      "new_model_requests" => 0,
      "original_evidence_modified" => false
    }

    %Admission{
      declaration: declaration,
      prediction_bytes: bytes,
      binding_sha256: binding,
      references: references,
      blind_seed: plan["blind_seed"],
      provenance: provenance,
      protected: protected,
      output: output
    }
  end

  defp full_grid!(declaration, bytes) do
    {:ok, checked} =
      checked(EvaluationScore.verified_predictions(declaration, %{"predictions" => bytes}))

    expected =
      for variant <- declaration["variants"],
          query <- declaration["queries"],
          do: {variant, query["query_id"]}

    actual = Enum.map(checked["rows"], &{&1["variant"], &1["query_id"]})
    require!(Enum.sort(expected) == Enum.sort(actual), :incomplete_prediction_grid)
    checked["review_binding_sha256"]
  end

  defp reference_bytes!(references, purpose) do
    manifest = canonical!(references.manifest_path)
    require!(manifest == references.manifest_path, :reference_alias)
    require!(sha(read!(manifest, 1_048_576)) == references.manifest_sha256, :data_manifest_hash)

    names =
      if purpose == :review,
        do: [references.corpus_member, references.queries_member],
        else: [references.queries_member]

    bytes =
      Map.new(names, fn name ->
        [member] = Enum.filter(references.members, &(&1["path"] == name))
        require!(relative?(name), :reference_member)
        target = Path.join(Path.dirname(manifest), name)
        require!(canonical!(target) == target, :reference_alias)
        raw = read!(target, 1_048_576)
        require!(sha(raw) == member["sha256"], :reference_member_hash)
        {name, raw}
      end)

    if purpose == :review do
      %{
        "as_of_ms" => references.as_of_ms,
        "corpus" => bytes[references.corpus_member],
        "queries" => bytes[references.queries_member],
        "split" => references.split
      }
    else
      bytes[references.queries_member]
    end
  end

  defp judge!(admission, request) do
    try do
      require!(
        full_grid!(admission.declaration, admission.prediction_bytes) == admission.binding_sha256,
        :subject_binding
      )

      blobs = %{"predictions" => admission.prediction_bytes}

      {outcome, provenance, exit_code} =
        case request.phase do
          :review ->
            {:ok, packet} =
              checked(
                EvaluationReview.prepare(
                  admission.declaration,
                  blobs,
                  fn -> {:ok, reference_bytes!(admission.references, :review)} end,
                  admission.blind_seed
                )
              )

            summary =
              packet["summary"]
              |> Map.merge(
                Map.take(
                  admission.provenance,
                  ~w(execution_freeze_sha256 data_manifest_sha256 supplement_sha256)
                )
              )

            files = Map.put(packet["files"], "manifest.json", encode(summary))
            target = Path.join(admission.output, "packet")
            File.mkdir!(target)
            File.chmod!(target, 0o700)
            for {name, raw} <- files, do: save!(Path.join(target, name), raw, 33_554_432)
            packet_sha = sha(files["manifest.json"])

            {%{
               "phase" => "review",
               "packet_sha256" => packet_sha,
               "rows" => summary["rows"],
               "reference_integrity_complete" => summary["reference_integrity_complete"],
               "semantic_support" => "unmeasured"
             }, Map.put(admission.provenance, "packet_sha256", packet_sha),
             if(summary["reference_integrity_complete"], do: 0, else: 1)}

          :score ->
            reviews_path = canonical!(request.reviews)
            disjoint!(reviews_path, admission.protected)
            raw_review = read!(reviews_path, 33_554_432)

            {:ok, report} =
              checked(
                EvaluationScore.score(
                  admission.declaration,
                  blobs,
                  fn ->
                    EvaluationInput.labels(
                      reference_bytes!(admission.references, :labels),
                      admission.references.split
                    )
                  end,
                  fn -> {:ok, json!(raw_review)} end
                )
              )

            raw_report = encode(report)
            save!(Path.join(admission.output, "scores.json"), raw_report, @score_limit)

            {%{
               "phase" => "score",
               "scores_sha256" => sha(raw_report),
               "quality_measured" =>
                 report["semantic"]["review_complete"] and report["literal_review_complete"],
               "quality_gates_passed" => report["quality_gates_passed"],
               "gates" => report["gates"]
             },
             Map.merge(admission.provenance, %{
               "reviews_sha256" => sha(raw_review),
               "scores_sha256" => sha(raw_report)
             }), if(report["quality_gates_passed"], do: 0, else: 1)}
        end

      save!(
        Path.join(admission.output, "evidence/judgment-provenance.json"),
        encode(provenance),
        1_048_576
      )

      final =
        Map.merge(outcome, %{
          "version" => 1,
          "status" => "completed",
          "exit_code" => exit_code,
          "quality_measured" => Map.get(outcome, "quality_measured", false)
        })

      save!(Path.join(admission.output, "outcome.json"), encode(final), 1_048_576)
      IO.puts(JSON.encode!(final))
      exit_code
    rescue
      error ->
        save_failure!(admission.output, %{"class" => inspect(error.__struct__)})
        reraise error, __STACKTRACE__
    catch
      {:historical_judgment, code} ->
        save_failure!(admission.output, %{"code" => Atom.to_string(code)})
        fail!(code)
    end
  end

  defp save_failure!(output, detail) do
    save!(
      Path.join(output, "failure.json"),
      encode(
        Map.merge(
          %{"status" => "failed", "quality_measured" => false},
          detail
        )
      ),
      1_048_576
    )
  end

  defp canonical!(path) do
    require!(is_binary(path) and Path.type(path) == :absolute, :absolute_path_required)
    {:ok, resolved} = Ipse.WorkspaceContext.canonical_path(path)
    resolved
  end

  defp disjoint!(target, paths) do
    for path <- paths do
      protected = canonical!(path)

      require!(
        target != protected and not String.starts_with?(target, protected <> "/") and
          not String.starts_with?(protected, target <> "/"),
        :protected_overlap
      )
    end

    :ok
  end

  defp read!(path, limit) do
    %{type: :regular, size: size} = File.lstat!(path)
    require!(size <= limit, :input_size)
    {:ok, raw} = File.open(path, [:read, :binary], &IO.binread(&1, limit + 1))
    raw = if raw == :eof, do: "", else: raw
    require!(is_binary(raw) and byte_size(raw) == size and size <= limit, :input_size)
    raw
  end

  defp save!(path, raw, limit) do
    require!(is_binary(raw) and byte_size(raw) <= limit, :output_size)
    File.write!(path, raw, [:exclusive, :sync])
    File.chmod!(path, 0o600)
  end

  defp json!(raw) do
    {:ok, value} = Ipse.JSON.decode_unique(raw)
    value
  end

  defp encode(value), do: JSON.encode!(value) <> "\n"
  defp sha(raw), do: Manifest.sha256(raw)
  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)

  defp relative?(value),
    do:
      is_binary(value) and byte_size(value) in 1..4096 and Path.type(value) == :relative and
        Enum.all?(Path.split(value), &(&1 not in ["", ".", ".."]))

  defp checked({:ok, _} = result), do: result
  defp checked({:error, code}) when is_atom(code), do: fail!(code)
  defp checked({:error, _}), do: fail!(:judgment_failed)
  defp require!(true, _), do: :ok
  defp require!(_, code), do: fail!(code)
  defp fail!(code), do: throw({:historical_judgment, code})
end
