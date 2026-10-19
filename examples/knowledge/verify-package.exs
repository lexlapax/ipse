defmodule IpseKnowledgeExample.PackageProof do
  @moduledoc false
  @utilities ~w(dirname basename cut sed cat grep readlink sleep uname expr awk id tr head)

  def run([archive, artifact]) do
    archive = Path.expand(archive)
    artifact = Path.expand(artifact)
    original = digest(archive)

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

      expression = """
      canonical = fn path -> {:ok, resolved} = Ipse.WorkspaceContext.canonical_path(path); resolved end
      bundled = #{inspect(Path.join(release, "erts-*/bin/erl"))} |> Path.wildcard() |> Enum.map(canonical)
      found = for name <- ~w(elixir erl mix rustc), path = System.find_executable(name), path != nil,
        not (name == "erl" and canonical.(path) in bundled), do: {name, path}
      unless found == [], do: raise("Unexpected system development toolchain")
      Code.require_file(#{inspect(Path.join(__DIR__, "proof.exs"))})
      IO.puts(:json.encode(IpseKnowledgeExample.Proof.run(#{inspect(artifact)})))
      """

      {output, status} =
        System.cmd(Path.join(release, "bin/ipse"), ["eval", expression],
          cd: release,
          env: env,
          stderr_to_stdout: true
        )

      unless status == 0, do: raise("Installed knowledge proof failed: " <> output)
      report = output |> String.split("\n", trim: true) |> List.last() |> :json.decode()

      true =
        report["checks"] == 11 and report["disabled_catalogs_empty"] == true and
          report["independent_catalogs"] == true and report["model_requests"] == 0 and
          report["host_loaded_domain_modules"] == false

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
