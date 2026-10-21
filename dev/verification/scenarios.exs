defmodule Ipse.Development.Verification.Scenarios do
  @moduledoc "Finite verification entrypoints and their distinct acceptance assertions."

  @ordinary %{
    "model" =>
      {"examples/model-calls/proof.exs", IpseModelExample.Proof, [IpseModelExample.Proof]},
    "embedding" =>
      {"examples/embedding-actions/proof.exs", IpseEmbeddingExample.Proof,
       [IpseEmbeddingExample.Proof, IpseEmbeddingExample.Proof.NoModel]},
    "mcp" =>
      {"examples/mcp-actions/proof.exs", IpseMCPExample.Proof,
       [
         IpseMCPExample.Proof,
         IpseMCPExample.Proof.NoModel,
         IpseMCPExample.Fixture,
         IpseMCPExample.Fixture.HTTPLifecycle
       ]},
    "saved-results" =>
      {"examples/saved-results/proof.exs", IpseSavedResultsExample.Proof,
       [IpseSavedResultsExample.Proof, IpseSavedResultsExample.Proof.NoModel]},
    "lab" =>
      {"examples/extension-lab/proof.exs", IpseLab.Proof,
       [IpseLab.Proof, IpseLab.Proof.Model, IpseLab.Spec]},
    "memory" =>
      {"dev/experiments/memory.exs", Ipse.Development.Experiments.Memory,
       [Ipse.Development.Experiments.Memory]},
    "knowledge" =>
      {"examples/knowledge/proof.exs", IpseKnowledgeExample.Proof,
       [
         IpseKnowledgeExample.Proof,
         IpseKnowledgeExample.Proof.NoModel,
         Ipse.Development.Evaluation.Session
       ]},
    "knowledge-independence" =>
      {"examples/knowledge/proof.exs", IpseKnowledgeExample.Proof,
       [
         IpseKnowledgeExample.Proof,
         IpseKnowledgeExample.Proof.NoModel,
         Ipse.Development.Evaluation.Session
       ]},
    "knowledge-complete" =>
      {"examples/knowledge/complete-result-proof.exs", IpseKnowledgeExample.CompleteResultProof,
       [
         IpseKnowledgeExample.CompleteResultProof,
         IpseKnowledgeExample.CompleteResultProof.NoModel
       ]},
    "knowledge-evaluation" =>
      {"examples/knowledge/evaluation-proof.exs", IpseKnowledgeExample.EvaluationProof,
       [
         IpseKnowledgeExample.EvaluationProof,
         IpseKnowledgeExample.EvaluationProof.NoModel,
         Ipse.Development.Evaluation.Session
       ]},
    "knowledge-recovery" =>
      {"examples/knowledge/recovery-proof.exs", IpseKnowledgeExample.RecoveryProof,
       [
         IpseKnowledgeExample.RecoveryProof,
         IpseKnowledgeExample.RecoveryProof.NoModel,
         Ipse.Development.Evaluation.Session
       ]},
    "knowledge-graph-lifecycle" =>
      {"examples/knowledge/lifecycle-proof.exs", IpseKnowledgeExample.LifecycleProof,
       [
         IpseKnowledgeExample.LifecycleProof,
         IpseKnowledgeExample.LifecycleProof.NoMain,
         Ipse.Development.Evaluation.Session
       ]},
    "knowledge-corpus-lifecycle" =>
      {"examples/knowledge/lifecycle-proof.exs", IpseKnowledgeExample.LifecycleProof,
       [
         IpseKnowledgeExample.LifecycleProof,
         IpseKnowledgeExample.LifecycleProof.NoMain,
         Ipse.Development.Evaluation.Session
       ]},
    "knowledge-selection" =>
      {"examples/knowledge/lifecycle-proof.exs", IpseKnowledgeExample.LifecycleProof,
       [
         IpseKnowledgeExample.LifecycleProof,
         IpseKnowledgeExample.LifecycleProof.NoMain,
         Ipse.Development.Evaluation.Session
       ]},
    "knowledge-mcp" =>
      {["dev/fixtures/knowledge.exs", "examples/knowledge/mcp-proof.exs"],
       IpseKnowledgeExample.MCPProof,
       [
         Ipse.Development.Fixtures.Knowledge,
         Ipse.Development.Fixtures.Knowledge.Backend,
         Ipse.Development.Evaluation.Session,
         IpseKnowledgeExample.MCPProof,
         IpseKnowledgeExample.MCPProof.NoModel
       ]},
    "knowledge-research" =>
      {["dev/fixtures/knowledge.exs", "examples/knowledge/research-proof.exs"],
       IpseKnowledgeExample.ResearchProof,
       [
         Ipse.Development.Fixtures.Knowledge,
         Ipse.Development.Fixtures.Knowledge.Backend,
         Ipse.Development.Evaluation.Session,
         IpseKnowledgeExample.ResearchProof,
         IpseKnowledgeExample.ResearchProof.NoModel
       ]}
  }

  @measured ~w(measured-knowledge measured-authority)
  def names, do: Enum.sort(["package", "model-service"] ++ @measured ++ Map.keys(@ordinary))

  def evaluator do
    %{
      native_environment: :base,
      source: "dev/evaluation/cli.exs",
      sources: [
        "extensions/knowledge/src/evidence.ex",
        "dev/evaluation/author.exs",
        "dev/fixtures/knowledge.exs",
        "dev/evaluation/cli.exs"
      ],
      module: Ipse.Development.Evaluation.MeasuredExecution,
      modules: [
        Ipse.Development.Evaluation.Contract,
        Ipse.Development.Evaluation.Dataset,
        Ipse.Development.Evaluation.Freeze,
        Ipse.Development.Evaluation.Session,
        Ipse.Development.Evaluation.Answer,
        Ipse.Development.Evaluation.Resources,
        Ipse.Development.Evaluation.Inventory,
        Ipse.Development.Evaluation.Gateway,
        Ipse.Development.Evaluation.Score,
        Ipse.Development.Evaluation.Review,
        Ipse.Development.Evaluation.ModelService,
        Ipse.Development.Evaluation.MeasuredExecution,
        Ipse.Development.Evaluation.MeasuredExecution.Environment,
        Ipse.Development.Evaluation.Metrics,
        Ipse.Development.Evaluation.Runner,
        Ipse.Development.Evaluation.Runner.NoMain,
        Ipse.Development.Fixtures.Knowledge,
        Ipse.Development.Fixtures.Knowledge.Backend,
        Ipse.Development.Evaluation.Author,
        IpseKnowledge.Evidence,
        Ipse.Development.Evaluation.CLI
      ]
    }
  end

  def fixture!(:mcp) do
    %{
      source: "examples/mcp-actions/fixture.exs",
      module: IpseMCPExample.Fixture,
      modules: [IpseMCPExample.Fixture, IpseMCPExample.Fixture.HTTPLifecycle]
    }
  end

  def fixture!(:knowledge) do
    %{
      source: "dev/fixtures/knowledge.exs",
      module: Ipse.Development.Fixtures.Knowledge,
      modules: [Ipse.Development.Fixtures.Knowledge, Ipse.Development.Fixtures.Knowledge.Backend]
    }
  end

  def fixture!(:model_service) do
    %{
      source: "dev/fixtures/model_service.exs",
      module: Ipse.Development.Fixtures.ModelService,
      modules: [
        Ipse.Development.Fixtures.ModelService,
        Ipse.Development.Fixtures.ModelService.Daemon
      ]
    }
  end

  def fetch!("package"), do: Map.put(fetch!("memory"), :name, "package")

  def fetch!(name) when name in @measured do
    evaluator = evaluator()
    authority = name == "measured-authority"

    source =
      if authority,
        do: "dev/verification/measured_authority.exs",
        else: "dev/verification/measured_knowledge.exs"

    module =
      if authority,
        do: Ipse.Development.Verification.MeasuredAuthority,
        else: Ipse.Development.Verification.MeasuredKnowledge

    %{
      name: name,
      source: source,
      module: module,
      sources:
        evaluator.sources ++
          [
            "dev/fixtures/model_service.exs",
            "dev/verification/scenarios.exs",
            "dev/verification/runtime.exs",
            "dev/verification/measured_knowledge.exs"
          ] ++
          if(authority, do: [source], else: []),
      modules:
        evaluator.modules ++
          fixture!(:model_service).modules ++
          [
            __MODULE__,
            Ipse.Development.Verification.Runtime,
            Ipse.Development.Verification.MeasuredKnowledge,
            Ipse.Development.Verification.MeasuredKnowledge.Scoring
          ] ++ if(authority, do: [module], else: []),
      native_environment: :manager,
      utilities: ["kill"],
      retained: true,
      linux_only: true,
      artifact_input: true
    }
  end

  def fetch!("model-service") do
    %{
      name: "model-service",
      source: "dev/verification/model_service.exs",
      sources: [
        "dev/evaluation/model_service.exs",
        "dev/verification/model_service.exs"
      ],
      module: Ipse.Development.Verification.ModelService,
      modules: [
        Ipse.Development.Evaluation.ModelService,
        Ipse.Development.Verification.ModelService
      ],
      utilities: ["kill"]
    }
  end

  def fetch!(name) do
    {source, module, modules} = Map.fetch!(@ordinary, name)
    sources = List.wrap(source)
    spec = %{name: name, source: List.last(sources), module: module, modules: modules}
    if length(sources) == 1, do: spec, else: Map.put(spec, :sources, sources)
  end

  def expression(spec, input, selection, mode, context \\ %{})

  def expression(%{name: "measured-knowledge"}, input, selection, _mode, context),
    do:
      "Ipse.Development.Verification.MeasuredKnowledge.run(#{inspect(context.repository)}, #{inspect(input)}, #{inspect(context.output)}, #{inspect(selection)})"

  def expression(%{name: "measured-authority"}, input, "default", _mode, context),
    do:
      "Ipse.Development.Verification.MeasuredAuthority.run(#{inspect(context.repository)}, #{inspect(input)}, #{inspect(context.output)})"

  def expression(%{name: "model-service"}, input, "default", _mode, context),
    do:
      "Ipse.Development.Verification.ModelService.run(#{inspect(input)}, #{inspect(context.output)})"

  def expression(%{name: "lab"}, input, "default", :installed, _context),
    do: "IpseLab.Proof.run_installed(#{inspect(input)})"

  def expression(%{name: "model"}, input, selection, _mode, _context) do
    {thinking, output} = model_selection(selection)
    "IpseModelExample.Proof.run(#{inspect(input)}, #{inspect(thinking)}, #{inspect(output)})"
  end

  def expression(%{name: "knowledge-independence"}, input, "default", _mode, _context),
    do: "IpseKnowledgeExample.Proof.independence(#{inspect(input)})"

  def expression(%{name: "knowledge-graph-lifecycle"}, input, "default", _mode, _context),
    do: "IpseKnowledgeExample.LifecycleProof.run(#{inspect(input)}, \"graph\")"

  def expression(%{name: "knowledge-corpus-lifecycle"}, input, "default", _mode, _context),
    do: "IpseKnowledgeExample.LifecycleProof.run(#{inspect(input)}, \"corpus\")"

  def expression(%{name: "knowledge-selection"}, input, "default", _mode, _context),
    do: "IpseKnowledgeExample.LifecycleProof.selection(#{inspect(input)})"

  def expression(%{module: module}, input, "default", _mode, _context),
    do: "#{inspect(module)}.run(#{inspect(input)})"

  def selection!("model", selection) do
    model_selection(selection)
    :ok
  end

  def selection!("package", "default"), do: :ok
  def selection!("model-service", "default"), do: :ok
  def selection!("measured-authority", "default"), do: :ok

  def selection!("measured-knowledge", selection)
      when selection in ~w(default sealed structured sealed-structured sealed-long-answers sealed-gpu-answers) do
    :ok
  end

  def selection!(name, "default") when is_map_key(@ordinary, name), do: :ok

  def output_required?(name), do: name == "model-service" or name in @measured
  def repository_required?(name), do: name in @measured

  def validate!(%{name: "measured-knowledge"}, report, _selection) do
    true = report["synthetic"] and report["model_quality_measured"] == false
    350 = report["result"]["rows"]
    true = report["result"]["execution_complete"] and report["result"]["resource_complete"]
    "passed" = report["scoring"]["review_cli"]
    "unmeasured_quality_refused" = report["scoring"]["score_cli"]
    true = report["scoring"]["unopened_label_and_review_inputs"]
    false = report["scoring"]["new_model_work"]
    :ok
  end

  def validate!(%{name: "measured-authority"}, report, "default") do
    5 = report["checks"]
    true = report["cleanup_confirmed"] and report["fresh_attempt_per_control"]
    false = report["quality_measured"]
    :ok
  end

  def validate!(%{name: "model-service"}, report, "default") do
    true = report["synthetic"]

    if :os.type() == {:unix, :linux} do
      rows = report["cases"]
      26 = length(rows)
      true = MapSet.size(MapSet.new(rows, & &1["case"])) == length(rows)
      for row <- rows, do: true = row["synthetic"] and row["status"] == "passed"
    else
      true = report["unsupported_before_effects"]
    end

    :ok
  end

  def validate!(%{name: "model"}, report, selection) do
    {thinking, output} = model_selection(selection)
    true = report["thinking_selection"] == (thinking || "default")

    true =
      report["output_contract"] ==
        case output do
          :text -> "text_v1"
          :json_schema -> "json_schema_v2"
          :json_schema_long -> "json_schema_v3"
        end

    checks!(report, 9)
  end

  def validate!(%{name: name}, report, "default") when name in ~w(embedding mcp),
    do: checks!(report, 12)

  def validate!(%{name: name}, report, "default")
      when name in ~w(knowledge-mcp knowledge-research) do
    expected = if name == "knowledge-mcp", do: 9, else: 17
    knowledge!(report, expected)
  end

  def validate!(%{name: "knowledge"}, report, "default") do
    knowledge!(report, 16)

    all_true!(
      report,
      ~w(disabled_catalogs_empty independent_catalogs policy_exclusions_retained
      expired_facts_excluded incomplete_empty_is_partial fused_graph_bound_is_partial direct_graph_scope_matches)
    )
  end

  def validate!(%{name: "knowledge-independence"}, report, "default") do
    true = valid_independence?(report)
    :ok
  end

  def validate!(%{name: "knowledge-complete"}, report, "default") do
    knowledge!(report, 5)
    10 = report["research_evidence"]
    10 = report["corpus_evidence"]
    1 = report["graph_evidence"]
    8 = report["graph_claims"]

    true =
      report["research_bytes"] > 12_000 and report["corpus_bytes"] > 12_000 and
        report["graph_bytes"] > 12_000

    true = report["escaped_citation_bytes"] > 4096

    all_true!(
      report,
      ~w(citation_crosses_fragment unranked_claim_bases_preserved complete_hashes_verified
      opposing_assertions_preserved corpus_graph_conflict historical_reads_exact resume_inert journal_unchanged)
    )

    "confirmed" = report["cleanup"]
    :ok
  end

  def validate!(%{name: "knowledge-evaluation"}, report, "default") do
    5 = report["checks"]
    0 = report["model_requests"]
    true = report["paged_ingest"]
    "dotted" = report["profile_names"]
    true = is_integer(report["durable_receipts"]) and report["durable_receipts"] > 0
    :ok
  end

  def validate!(%{name: "knowledge-recovery"}, report, "default") do
    knowledge!(report, 8)
    all_true!(report, ~w(graph_only exact_abort stale_abort_zero_writes explicit_new_draft))
    0 = report["denied_model_dispatches"]
    "confirmed" = report["cleanup"]
    :ok
  end

  def validate!(%{name: name}, report, "default")
      when name in ~w(knowledge-graph-lifecycle knowledge-corpus-lifecycle) do
    kind = if name == "knowledge-graph-lifecycle", do: "graph", else: "corpus"
    ^kind = report["package"]
    7 = report["checks"]
    7 = report["fixture_provider_requests"]
    false = report["actual_model_inference"]
    false = report["host_loaded_domain_modules"]
    "confirmed" = report["fixture_cleanup"]
    ["owner_loss"] = report["session_cleanup_unconfirmed_cases"]
    expected = ~w(forget cancel owner_loss timeout quota malformed unavailable) |> Enum.sort()
    ^expected = report["cases"] |> Enum.map(& &1["case"]) |> Enum.sort()

    for row <- report["cases"] do
      0 = row["idle_resume_replays"]
      cleanup = if row["case"] == "owner_loss", do: "unconfirmed_owner_loss", else: "confirmed"
      ^cleanup = row["session_cleanup"]
    end

    :ok
  end

  def validate!(%{name: "knowledge-selection"}, report, "default") do
    10 = report["checks"]
    10 = report["fixture_provider_requests"]
    false = report["actual_model_inference"]
    false = report["host_loaded_domain_modules"]
    "confirmed" = report["cleanup"]
    0 = report["idle_resume_replays"]

    all_true!(
      report,
      ~w(changed_endpoint_refused explicit_fallback_partial explicit_reindex_succeeded
      timeout_only_reused changed_reported_model_reindexed reported_model_change_preserved_selection)
    )
  end

  def validate!(%{name: "saved-results"}, report, "default") do
    4_194_304 = report["byte_count"]
    1024 = report["fragment_count"]
    for key <- ~w(historical_reads_exact resume_inert journal_unchanged), do: true = report[key]
    1 = report["worker_loads"]
    1 = report["callbacks"]
    0 = report["model_requests"]
    false = report["host_loaded_domain_modules"]
    "confirmed" = report["cleanup"]
    :ok
  end

  def validate!(%{name: "lab"}, report, "default") do
    checks!(report, 41)
    false = report["safe_to_continue"]
    "unconfirmed" = report["expected_terminal_cleanup"]
    :ok
  end

  def validate!(%{name: "memory"}, report, "default") do
    true = report["passed"]
    100 = report["records"]
    100 = report["questions"]
    2 = report["projects"]
    6 = report["sessions"]
    0 = report["model_calls"]
    1.0 = report["recall_at_5"]
    1.0 = report["exact_span_precision"]
    :ok
  end

  defp knowledge!(report, count) do
    ^count = report["checks"]
    0 = report["model_requests"]
    false = report["host_loaded_domain_modules"]
    :ok
  end

  defp all_true!(report, fields) do
    for field <- fields, do: true = report[field]
    :ok
  end

  @counter_fields ~w(embedding_operations extension_worker_starts mcp_operations state_operations text_operations)
  defp zero_counts?(counts),
    do:
      is_map(counts) and Enum.sort(Map.keys(counts)) == @counter_fields and
        Enum.all?(Map.values(counts), &(&1 === 0))

  defp valid_independence?(report) do
    expected =
      for {memory, scope} <- [
            {"working", "session"},
            {"persistent", "project"},
            {"persistent", "operator"}
          ],
          package <- ~w(corpus graph research),
          do: {memory, scope, package}

    rows = report["cases"]

    report["checks"] === 10 and report["catalog_bound_refused"] === true and
      report["model_requests"] === 0 and report["payloads_traced"] === false and
      report["host_loaded_domain_modules"] === false and report["cleanup"] == "confirmed" and
      zero_counts?(report["catalog_refusal_calls"]) and is_list(rows) and
      Enum.sort(Enum.map(rows, &{&1["memory"], &1["scope"], &1["package"]})) ==
        Enum.sort(expected) and
      Enum.all?(rows, fn row ->
        row["note_isolation"] === true and row["forget_isolation"] === true and
          row["state_files"] === if(row["package"] == "research", do: 1, else: 2) and
          row["retained_knowledge_store"] === (row["package"] != "research") and
          Enum.all?(~w(disabled_calls idle_calls resume_calls), &zero_counts?(row[&1])) and
          Enum.all?(~w(operation_calls forget_calls), fn phase ->
            counts = row[phase]

            is_map(counts) and Enum.sort(Map.keys(counts)) == @counter_fields and
              counts["extension_worker_starts"] > 0 and counts["state_operations"] > 0 and
              Enum.all?(
                ~w(mcp_operations embedding_operations text_operations),
                &(counts[&1] === 0)
              )
          end)
      end)
  end

  defp checks!(report, count) do
    ^count = map_size(report["checks"])
    true = Enum.all?(report["checks"], fn {_, passed} -> passed == true end)
    :ok
  end

  defp model_selection("default"), do: {nil, :text}
  defp model_selection("none"), do: {"none", :text}
  defp model_selection("json"), do: {nil, :json_schema}
  defp model_selection("json-none"), do: {"none", :json_schema}
  defp model_selection("json-long"), do: {nil, :json_schema_long}
end
