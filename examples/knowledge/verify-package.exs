defmodule IpseKnowledgeExample.PackageProof do
  @moduledoc false
  @utilities ~w(dirname basename cut sed cat grep readlink sleep uname expr awk id tr head)

  def run([archive, artifact]), do: run([archive, artifact, "base"])

  def run([archive, artifact, mode]) when mode in ~w(base independence complete) do
    archive = Path.expand(archive)
    artifact = Path.expand(artifact)
    original = digest(archive)
    artifact_files = inventory(artifact)

    root =
      Path.join(
        System.tmp_dir!(),
        "ipse-knowledge-package-#{Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)}"
      )

    release = Path.join(root, "release")
    utilities = Path.join(root, "utilities")
    File.mkdir_p!(release)
    File.mkdir_p!(utilities)

    try do
      {_, 0} =
        System.cmd(System.find_executable("tar"), ["-xzf", archive, "-C", release],
          stderr_to_stdout: true
        )

      Enum.each(@utilities, fn name ->
        File.ln_s!(
          System.find_executable(name) || raise("Missing declared host utility"),
          Path.join(utilities, name)
        )
      end)

      preserved = ~w(HOME LANG LC_ALL)
      env = Enum.reject(Map.keys(System.get_env()), &(&1 in preserved)) |> Map.new(&{&1, nil})

      env =
        env
        |> Map.merge(%{
          "PATH" => utilities,
          "IPSE_HOME" => Path.join(root, "home"),
          "TMPDIR" => root
        })
        |> Map.to_list()

      {_, 0} =
        System.cmd(Path.join(release, "ipse"), ["--help"],
          cd: release,
          env: env,
          stderr_to_stdout: true
        )

      frozen = inventory(release)
      proof_function = if mode == "base", do: "run", else: "independence"

      {harness, harness_files} =
        if mode == "complete" do
          directory = Path.join(root, "proof-ebin")
          File.mkdir!(directory)
          File.chmod!(root, 0o700)
          for path <- Path.wildcard(Path.join(release, "lib/*/ebin")), do: Code.prepend_path(path)

          case Kernel.ParallelCompiler.compile_to_path(
                 [Path.join(__DIR__, "complete-result-proof.exs")],
                 directory,
                 return_diagnostics: true
               ) do
            {:ok, _, []} -> :ok
            {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> :ok
            _ -> raise "Complete-result harness compilation failed or emitted warnings"
          end

          {directory, inventory(directory)}
        else
          {nil, nil}
        end

      proof =
        if mode == "complete" do
          [erl] = Path.wildcard(Path.join(release, "erts-*/bin/erl"))
          runtime_bin = Path.join(root, "runtime-bin")
          File.mkdir!(runtime_bin)
          File.ln_s!(erl, Path.join(runtime_bin, "erl"))

          """
          System.put_env("PATH", #{inspect(utilities <> ":" <> runtime_bin)})
          for name <- ~w(elixir elixirc erlc mix rustc cargo), do: nil = System.find_executable(name)
          Code.prepend_path(#{inspect(harness)})
          Code.ensure_loaded!(IpseKnowledgeExample.CompleteResultProof)
          IO.puts(:json.encode(IpseKnowledgeExample.CompleteResultProof.run(#{inspect(artifact)})))
          """
        else
          """
          Code.require_file(#{inspect(Path.join(__DIR__, "proof.exs"))})
          IO.puts(:json.encode(IpseKnowledgeExample.Proof.#{proof_function}(#{inspect(artifact)})))
          """
        end

      expression = """
      canonical = fn path -> {:ok, resolved} = Ipse.WorkspaceContext.canonical_path(path); resolved end
      bundled = #{inspect(Path.join(release, "erts-*/bin/erl"))} |> Path.wildcard() |> Enum.map(canonical)
      found = for name <- ~w(elixir erl mix rustc), path = System.find_executable(name), path != nil,
        not (name == "erl" and canonical.(path) in bundled), do: {name, path}
      unless found == [], do: raise("Unexpected system development toolchain")
      #{proof}
      """

      {output, status} =
        System.cmd(Path.join(release, "bin/ipse"), ["eval", expression],
          cd: release,
          env: env,
          stderr_to_stdout: true
        )

      unless status == 0, do: raise("Installed knowledge proof failed: " <> output)
      report = output |> String.split("\n", trim: true) |> List.last() |> :json.decode()

      case mode do
        "base" ->
          true =
            report["checks"] == 16 and report["disabled_catalogs_empty"] == true and
              report["independent_catalogs"] == true and report["model_requests"] == 0 and
              report["policy_exclusions_retained"] == true and
              report["expired_facts_excluded"] == true and
              report["incomplete_empty_is_partial"] == true and
              report["fused_graph_bound_is_partial"] == true and
              report["direct_graph_scope_matches"] == true and
              report["host_loaded_domain_modules"] == false

        "independence" ->
          true = valid_independence?(report)

        "complete" ->
          true =
            report["checks"] == 5 and report["research_evidence"] == 10 and
              report["research_bytes"] > 12_000 and report["corpus_evidence"] == 10 and
              report["corpus_bytes"] > 12_000 and report["graph_bytes"] > 12_000 and
              report["escaped_citation_bytes"] > 4096 and report["citation_crosses_fragment"] and
              report["graph_evidence"] == 1 and report["graph_claims"] == 8 and
              report["unranked_claim_bases_preserved"] and report["complete_hashes_verified"] and
              report["opposing_assertions_preserved"] and report["corpus_graph_conflict"] and
              report["historical_reads_exact"] and report["resume_inert"] and
              report["journal_unchanged"] and
              report["model_requests"] == 0 and report["host_loaded_domain_modules"] == false and
              report["cleanup"] == "confirmed" and inventory(harness) == harness_files
      end

      true =
        inventory(release) == frozen and digest(archive) == original and
          inventory(artifact) == artifact_files

      IO.puts(
        :json.encode(
          Map.merge(report, %{
            "archive_sha256" => original,
            "archive_unchanged" => true,
            "host_files_unchanged" => true,
            "system_toolchain_on_runtime_path" => false
          })
        )
      )
    after
      File.rm_rf!(root)
    end
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

  defp inventory(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard(match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Map.new(&{Path.relative_to(&1, root), digest(&1)})
  end

  defp digest(path) do
    path
    |> File.stream!(1_048_576, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end
end

IpseKnowledgeExample.PackageProof.run(System.argv())
