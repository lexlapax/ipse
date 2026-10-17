Code.require_file("spec.exs", __DIR__)

defmodule IpseLab.PackageProof do
  @moduledoc false
  @utilities ~w(dirname basename cut sed cat grep readlink sleep uname expr awk id tr head)

  def run([archive, artifacts]) do
    archive = Path.expand(archive)
    artifacts = Path.expand(artifacts)
    original = digest(archive)

    root =
      Path.join(
        System.tmp_dir!(),
        "ipse-extension-package-#{Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)}"
      )

    release = Path.join(root, "release")
    tools = Path.join(root, "utilities")
    File.mkdir_p!(release)
    File.mkdir_p!(tools)
    File.mkdir_p!(Path.join(root, "home"))

    try do
      {_, 0} =
        System.cmd(System.find_executable("tar"), ["-xzf", archive, "-C", release],
          stderr_to_stdout: true
        )

      Enum.each(@utilities, fn name ->
        File.ln_s!(
          System.find_executable(name) || raise("Missing declared host utility"),
          Path.join(tools, name)
        )
      end)

      preserved = ~w(HOME LANG LC_ALL)
      env = Enum.reject(Map.keys(System.get_env()), &(&1 in preserved)) |> Map.new(&{&1, nil})

      env =
        env
        |> Map.merge(%{"PATH" => tools, "IPSE_HOME" => Path.join(root, "home"), "TMPDIR" => root})
        |> Map.to_list()

      wrapper = Path.join(release, "ipse")

      for name <- ~w(memory lookup),
          do: run!(wrapper, ["extension", "import", Path.join(artifacts, name)], release, env)

      operator = Path.join(root, "operator.json")
      File.write!(operator, :json.encode(IpseLab.Spec.operator(artifacts)))
      File.chmod!(operator, 0o600)

      fixture = %{
        "version" => 1,
        "cases" => [
          %{
            "id" => "temporary-tool",
            "kind" => "tool",
            "name" => "ext__memory__remember",
            "arguments" => %{"text" => "entity: Temporary"},
            "expect" => %{"status" => "ok", "requests" => 2, "context_contains" => "supervisors"}
          },
          %{
            "id" => "project-export",
            "kind" => "command",
            "name" => "ext__memory__export",
            "arguments" => %{},
            "expect" => %{"status" => "ok", "requests" => 0}
          }
        ]
      }

      fixture_path = Path.join(root, "scenarios.json")
      File.write!(fixture_path, :json.encode(fixture))

      cli =
        run!(
          wrapper,
          [
            "extension",
            "check",
            "--config",
            operator,
            "--fixture",
            fixture_path,
            "--extension",
            "memory",
            "--extension",
            "lookup",
            "--no-project-config",
            "--yes"
          ],
          release,
          env
        )
        |> cli_report()

      true = cli["passed"] and cli["safe_to_continue"] and cli["case_count"] == 2

      expression =
        """
        canonical = fn path ->
          {:ok, resolved} = Ipse.WorkspaceContext.canonical_path(path)
          resolved
        end
        bundled = #{inspect(Path.join(release, "erts-*/bin/erl"))} |> Path.wildcard() |> Enum.map(canonical)
        found = for name <- ~w(elixir erl mix rustc),
                    path = System.find_executable(name), path != nil,
                    not (name == "erl" and canonical.(path) in bundled), do: {name, path}
        unless found == [], do: raise("Unexpected system toolchain executables: " <> inspect(found))
        Code.require_file(#{inspect(Path.join(__DIR__, "proof.exs"))})
        IO.puts(:json.encode(IpseLab.Proof.run(#{inspect(artifacts)})))
        """

      {output, status} =
        System.cmd(Path.join(release, "bin/ipse"), ["eval", expression],
          cd: release,
          env: env,
          stderr_to_stdout: true
        )

      unless status == 0, do: raise("Installed extension proof failed: " <> output)
      report = output |> String.split("\n", trim: true) |> List.last() |> :json.decode()
      true = Enum.all?(report["checks"], fn {_, passed} -> passed == true end)
      true = digest(archive) == original

      IO.puts(
        :json.encode(
          Map.merge(report, %{
            "archive_sha256" => original,
            "archive_unchanged" => true,
            "temporary_cli_selection" => true,
            "system_toolchain_on_runtime_path" => false
          })
        )
      )
    after
      File.rm_rf!(root)
    end
  end

  defp run!(command, arguments, cwd, env) do
    case System.cmd(command, arguments, cd: cwd, env: env, stderr_to_stdout: true) do
      {output, 0} -> output
      {output, _} -> raise "Extension lab CLI fixture failed: " <> output
    end
  end

  defp cli_report(output) do
    lines = String.split(output, "\n")
    start = Enum.find_index(lines, &(&1 == "{")) || raise("CLI conformance report missing")
    lines |> Enum.drop(start) |> Enum.join("\n") |> :json.decode()
  end

  defp digest(path) do
    path
    |> File.stream!(1_048_576, [])
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end
end

IpseLab.PackageProof.run(System.argv())
