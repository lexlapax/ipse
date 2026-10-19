defmodule IpseKnowledgeExample.RecoveryPackageProof do
  @moduledoc false
  @utilities ~w(dirname basename cut sed cat grep readlink sleep uname expr awk id tr head)

  def run([archive, artifact]), do: execute(archive, artifact, :recovery)

  def run([archive, artifact, kind]) when kind in ~w(graph corpus),
    do: execute(archive, artifact, {:lifecycle, kind})

  defp execute(archive, artifact, mode) do
    archive = Path.expand(archive)
    artifact = Path.expand(artifact)
    original = digest(archive)

    root =
      Path.join(
        System.tmp_dir!(),
        "ipse-knowledge-recovery-package-#{Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)}"
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

      {proof_file, invocation} =
        case mode do
          :recovery ->
            {"recovery-proof.exs", "IpseKnowledgeExample.RecoveryProof.run(#{inspect(artifact)})"}

          {:lifecycle, kind} ->
            {"lifecycle-proof.exs",
             "IpseKnowledgeExample.LifecycleProof.run(#{inspect(artifact)}, #{inspect(kind)})"}
        end

      expression = """
      canonical = fn path -> {:ok, resolved} = Ipse.WorkspaceContext.canonical_path(path); resolved end
      bundled = #{inspect(Path.join(release, "erts-*/bin/erl"))} |> Path.wildcard() |> Enum.map(canonical)
      found = for name <- ~w(elixir erl mix rustc), path = System.find_executable(name), path != nil,
        not (name == "erl" and canonical.(path) in bundled), do: {name, path}
      unless found == [], do: raise("Unexpected system development toolchain")
      Code.require_file(#{inspect(Path.join(__DIR__, proof_file))})
      IO.puts(:json.encode(#{invocation}))
      """

      {output, status} =
        System.cmd(Path.join(release, "bin/ipse"), ["eval", expression],
          cd: release,
          env: env,
          stderr_to_stdout: true
        )

      unless status == 0, do: raise("Installed knowledge proof failed: " <> output)
      report = output |> String.split("\n", trim: true) |> List.last() |> :json.decode()

      true = valid_report?(report, mode)
      true = inventory(release) == frozen and digest(archive) == original

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

  defp valid_report?(report, :recovery),
    do:
      report["checks"] == 8 and report["graph_only"] == true and
        report["exact_abort"] == true and report["stale_abort_zero_writes"] == true and
        report["model_requests"] == 0 and report["denied_model_dispatches"] == 0 and
        report["cleanup"] == "confirmed" and report["host_loaded_domain_modules"] == false

  defp valid_report?(report, {:lifecycle, kind}),
    do:
      report["package"] == kind and report["checks"] == 7 and
        report["fixture_provider_requests"] == 7 and
        report["actual_model_inference"] == false and report["fixture_cleanup"] == "confirmed" and
        report["session_cleanup_unconfirmed_cases"] == ["owner_loss"] and
        report["host_loaded_domain_modules"] == false and
        Enum.all?(report["cases"], &(&1["idle_resume_replays"] == 0))

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

IpseKnowledgeExample.RecoveryPackageProof.run(System.argv())
