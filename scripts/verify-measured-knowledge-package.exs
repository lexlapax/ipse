arguments =
  case System.argv() do
    ["--" | rest] -> rest
    rest -> rest
  end

{paths, contract} =
  case arguments do
    [archive, repository, artifact_file, output] ->
      {[archive, repository, artifact_file, output], nil}

    [archive, repository, artifact_file, output, "--sealed-answers"] ->
      {[archive, repository, artifact_file, output], "sealed_answers_v1"}
  end

[archive, repository, artifact_file, output] = Enum.map(paths, &Path.expand/1)

unless :os.type() == {:unix, :linux},
  do: raise("complete installed measured verification requires Linux")

archive_sha = Base.encode16(:crypto.hash(:sha256, File.read!(archive)), case: :lower)
File.mkdir!(output)
File.chmod!(output, 0o700)
release = Path.join(output, "release")
utilities = Path.join(output, "utilities")
home = Path.join(output, "home")

for path <- [release, utilities, home] do
  File.mkdir!(path)
  File.chmod!(path, 0o700)
end

{log, 0} = System.cmd("tar", ["-xzf", archive, "-C", release], stderr_to_stdout: true)
File.write!(Path.join(output, "extract.log"), log)

for name <-
      ~w(dirname basename cut sed cat grep readlink sleep uname expr awk id tr head kill git systemd-run systemctl) do
  File.ln_s!(
    System.find_executable(name) || raise("missing declared utility " <> name),
    Path.join(utilities, name)
  )
end

current = System.get_env()

environment =
  Map.new(Map.keys(current), &{&1, nil})
  |> Map.merge(%{
    "PATH" => utilities,
    "HOME" => home,
    "IPSE_HOME" => Path.join(home, ".ipse"),
    "TMPDIR" => output,
    "LANG" => "C.UTF-8"
  })
  |> Map.merge(Map.take(current, ~w(XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS)))
  |> Map.to_list()

expression = """
for name <- ~w(elixir elixirc mix rustc cargo), do: nil = System.find_executable(name)
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file(#{inspect(Path.join(repository, "examples/knowledge/evaluation_runner.exs"))})
Code.require_file(#{inspect(Path.join(repository, "test/support/measured_model_fixture.exs"))})
Code.require_file(#{inspect(Path.join(repository, "test/support/measured_knowledge_verification.exs"))})
Code.require_file(#{inspect(Path.join(repository, "test/support/measured_scoring_verification.exs"))})
artifacts = JSON.decode!(File.read!(#{inspect(artifact_file)}))
run = MeasuredKnowledgeVerification.prepare(#{inspect(Path.join(output, "installed"))}, #{inspect(repository)}, artifacts, nil, #{inspect(contract)})
result = MeasuredKnowledgeVerification.verify(run)
scoring = MeasuredScoringVerification.verify(run, result, #{inspect(repository)})
IO.puts(JSON.encode!(%{"synthetic" => true, "installed" => true, "model_quality_measured" => false, "result" => result, "scoring" => scoring}))
"""

{log, code} =
  System.cmd(Path.join(release, "bin/ipse"), ["eval", expression],
    cd: repository,
    env: environment,
    stderr_to_stdout: true
  )

File.write!(Path.join(output, "installed.log"), log)
File.chmod!(Path.join(output, "installed.log"), 0o600)
true = Base.encode16(:crypto.hash(:sha256, File.read!(archive)), case: :lower) == archive_sha

unless code == 0,
  do:
    raise(
      "installed measured verification failed; inspect " <> Path.join(output, "installed.log")
    )

IO.write(log)
