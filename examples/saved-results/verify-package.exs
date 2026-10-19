defmodule IpseSavedResultsExample.PackageProof do
  @moduledoc false
  @utilities ~w(dirname basename cut sed cat grep readlink sleep uname expr awk id tr head)

  def run([archive, artifact]) do
    archive = Path.expand(archive)
    artifact = Path.expand(artifact)
    archive_sha = digest(archive)
    artifact_files = inventory(artifact)

    root =
      Path.join(
        System.tmp_dir!(),
        "ipse-saved-package-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      )

    release = Path.join(root, "release")
    utilities = Path.join(root, "utilities")
    runtime_bin = Path.join(root, "runtime-bin")
    proof_ebin = Path.join(root, "proof-ebin")
    for path <- [release, utilities, runtime_bin, proof_ebin], do: File.mkdir_p!(path)
    File.chmod!(root, 0o700)

    try do
      {_, 0} =
        System.cmd(
          System.find_executable("tar") || raise("tar is required"),
          ["-xzf", archive, "-C", release],
          stderr_to_stdout: true
        )

      host_utilities =
        Map.new(@utilities, fn name ->
          path = System.find_executable(name) || raise("Missing declared utility: " <> name)
          File.ln_s!(path, Path.join(utilities, name))
          {path, digest(path)}
        end)

      [bundled_erl] = Path.wildcard(Path.join(release, "erts-*/bin/erl"))
      File.ln_s!(bundled_erl, Path.join(runtime_bin, "erl"))

      # Compile the trusted proof harness here, before the release runs. The
      # artifact was built separately; the bundled runtime performs no builds.
      for path <- Path.wildcard(Path.join(release, "lib/*/ebin")), do: Code.prepend_path(path)

      result =
        Kernel.ParallelCompiler.compile_to_path([Path.join(__DIR__, "proof.exs")], proof_ebin,
          return_diagnostics: true
        )

      case result do
        {:ok, _, []} -> :ok
        {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> :ok
        _ -> raise "Proof harness compilation failed or emitted warnings"
      end

      env = System.get_env() |> Map.keys() |> Map.new(&{&1, nil})

      env =
        Map.merge(env, %{
          "PATH" => utilities,
          "HOME" => Path.join(root, "home"),
          "IPSE_HOME" => Path.join(root, "home"),
          "LANG" => "C.UTF-8",
          "TMPDIR" => root
        })
        |> Map.to_list()

      {_, 0} =
        System.cmd(Path.join(release, "ipse"), ["--help"],
          cd: release,
          env: env,
          stderr_to_stdout: true
        )

      host_files = inventory(release)
      harness_files = inventory(proof_ebin)

      expression = """
      System.put_env("PATH", #{inspect(utilities <> ":" <> runtime_bin)})
      canonical = fn path -> {:ok, resolved} = Ipse.WorkspaceContext.canonical_path(path); resolved end
      bundled = #{inspect(Path.join(release, "erts-*/bin/erl"))} |> Path.wildcard() |> Enum.map(canonical)
      found = for name <- ~w(elixir elixirc erl erlc mix rustc cargo),
        path = System.find_executable(name), path != nil,
        not (name == "erl" and canonical.(path) in bundled), do: {name, path}
      unless found == [], do: raise("Unexpected system toolchain on runtime PATH")
      Code.prepend_path(#{inspect(proof_ebin)})
      Code.ensure_loaded!(IpseSavedResultsExample.Proof)
      IO.puts(Jason.encode!(IpseSavedResultsExample.Proof.run(#{inspect(artifact)})))
      """

      {output, status} =
        System.cmd(Path.join(release, "bin/ipse"), ["eval", expression],
          cd: release,
          env: env,
          stderr_to_stdout: true
        )

      unless status == 0, do: raise("Installed saved-result proof failed: " <> output)
      report = output |> String.split("\n", trim: true) |> List.last() |> :json.decode()

      true =
        report["byte_count"] == 4_194_304 and report["fragment_count"] == 1024 and
          report["historical_reads_exact"] and report["resume_inert"] and
          report["journal_unchanged"] and
          report["worker_loads"] == 1 and report["callbacks"] == 1 and
          report["model_requests"] == 0 and
          report["host_loaded_domain_modules"] == false and report["cleanup"] == "confirmed"

      true =
        digest(archive) == archive_sha and inventory(artifact) == artifact_files and
          inventory(release) == host_files and inventory(proof_ebin) == harness_files and
          Enum.all?(host_utilities, fn {path, hash} -> digest(path) == hash end)

      IO.puts(
        :json.encode(
          Map.merge(report, %{
            "archive_sha256" => archive_sha,
            "archive_unchanged" => true,
            "artifact_unchanged" => true,
            "host_files_unchanged" => true,
            "proof_harness_unchanged" => true,
            "system_toolchain_on_runtime_path" => false,
            "artifact_and_harness_prebuilt" => true
          })
        )
      )
    after
      File.rm_rf!(root)
    end
  end

  def run(_),
    do: raise("usage: elixir examples/saved-results/verify-package.exs ARCHIVE PREBUILT_ARTIFACT")

  defp inventory(root),
    do:
      root
      |> Path.join("**/*")
      |> Path.wildcard(match_dot: true)
      |> Enum.filter(&File.regular?/1)
      |> Map.new(&{Path.relative_to(&1, root), digest(&1)})

  defp digest(path),
    do:
      path
      |> File.stream!(1_048_576, [])
      |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)
end

IpseSavedResultsExample.PackageProof.run(System.argv())
