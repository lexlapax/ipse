[archive, fixture, output] = System.argv()
archive = Path.expand(archive)
fixture = Path.expand(fixture)
output = Path.expand(output)
File.mkdir!(output)
File.chmod!(output, 0o700)
release = Path.join(output, "release")
utilities = Path.join(output, "utilities")
File.mkdir!(release)
File.mkdir!(utilities)
original = :crypto.hash(:sha256, File.read!(archive))
{_, 0} = System.cmd("tar", ["-xzf", archive, "-C", release], stderr_to_stdout: true)

for name <- ~w(dirname basename cut sed cat grep readlink sleep uname expr awk id tr head kill) do
  File.ln_s!(
    System.find_executable(name) || raise("missing declared utility #{name}"),
    Path.join(utilities, name)
  )
end

env =
  Map.new(Map.keys(System.get_env()), &{&1, nil})
  |> Map.merge(%{
    "PATH" => utilities,
    "HOME" => Path.join(output, "home"),
    "IPSE_HOME" => Path.join(output, "home/.ipse"),
    "TMPDIR" => output,
    "LANG" => "C.UTF-8"
  })
  |> Map.to_list()

module = Path.expand("../examples/knowledge/evaluation_model_service.exs", __DIR__)
verification = Path.expand("../test/support/model_service_verification.exs", __DIR__)

expression = """
for name <- ~w(elixir elixirc mix rustc cargo), do: nil = System.find_executable(name)
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file(#{inspect(module)})
Code.require_file(#{inspect(verification)})
root = #{inspect(Path.join(output, "evidence"))}
File.mkdir!(root)
File.chmod!(root, 0o700)
if :os.type() == {:unix, :linux} do
  results = Enum.map(ModelServiceVerification.cases(), &ModelServiceVerification.verify_case(&1, #{inspect(fixture)}, Path.join(root, &1)))
  IO.puts(JSON.encode!(%{"synthetic" => true, "installed" => true, "cases" => results}))
else
  config = ModelServiceVerification.configuration(#{inspect(fixture)}, root)
  selected = Path.join(root, "unsupported-output")
  result = IpseKnowledgeExample.EvaluationModelService.run(config, selected, fn -> raise "unexpected callback" end)
  :not_started = result.work
  false = File.exists?(selected)
  IO.puts(JSON.encode!(%{"synthetic" => true, "installed" => true, "unsupported_before_effects" => true}))
end
"""

{log, status} =
  System.cmd(Path.join(release, "bin/ipse"), ["eval", expression],
    cd: release,
    env: env,
    stderr_to_stdout: true
  )

File.write!(Path.join(output, "installed.log"), log)
unless status == 0, do: raise("installed model-service verification failed: " <> log)
true = :crypto.hash(:sha256, File.read!(archive)) == original
IO.write(log)
