# Two synthetic PTY journeys against an extracted packaged runtime.
# Source fixtures and copied precompiled ExUnit are test support, not the host.
[archive, root, expected_archive, expected_commit_label] = System.argv()
archive = Path.expand(archive)
root = Path.expand(root)
Code.require_file("../release.exs", __DIR__)

true = Regex.match?(~r/\A[0-9a-f]{64}\z/, expected_archive)
true = Regex.match?(~r/\A[0-9a-f]{40}\z/, expected_commit_label)
:ok = Ipse.Development.Release.verify_checksum!(archive)
^expected_archive = Ipse.Development.Release.checksum(archive)
{:error, :enoent} = File.lstat(root)
File.mkdir!(root)
File.chmod!(root, 0o700)

source = Path.expand("../../test/support/draft_cli_pty.exs", __DIR__)
provider_source = Path.expand("../../test/support/provider_fixture.ex", __DIR__)
driver_source = Path.expand("../../test/support/operator_cli_pty.rs", __DIR__)

inputs = [
  source,
  provider_source,
  driver_source,
  __ENV__.file,
  Path.expand("../release.exs", __DIR__)
]

fingerprint = fn paths ->
  Map.new(paths, fn path -> {path, Ipse.Development.Release.checksum(path)} end)
end

before_inputs = fingerprint.(inputs)
release = Path.join(root, "release")
File.mkdir!(release)
{"", 0} = System.cmd("tar", ["-xzf", archive, "-C", release], stderr_to_stdout: true)
exunit = Path.join(root, "ex_unit")
{:ok, _} = File.cp_r(Application.app_dir(:ex_unit), exunit)
utilities = Path.join(root, "utilities")
File.mkdir!(utilities)

for name <- ~w(dirname basename cut sed cat grep readlink sleep uname expr awk id tr head),
    do: File.ln_s!(System.find_executable(name), Path.join(utilities, name))

driver = Path.join(root, "pty")

{_, 0} =
  System.cmd("rustc", ["--edition=2021", "-D", "warnings", driver_source, "-o", driver],
    stderr_to_stdout: true
  )

home = Path.join(root, "isolated-home")
tmp = Path.join(root, "tmp")
fixture_dir = Path.join(root, "fixture")

for path <- [home, tmp, fixture_dir] do
  File.mkdir!(path)
  File.chmod!(path, 0o700)
end

File.mkdir_p!(Path.join(fixture_dir, "test/support"))
staged_provider = Path.join(fixture_dir, "test/support/provider_fixture.ex")
File.cp!(provider_source, staged_provider)
true = Ipse.Development.Release.checksum(staged_provider) == before_inputs[provider_source]

# Keep HOME unchanged and clear inherited runtime, loader and Ipse overrides.
cleared =
  System.get_env()
  |> Map.keys()
  |> Enum.filter(
    &(String.starts_with?(&1, "IPSE_") or String.starts_with?(&1, "RELEASE_") or
        &1 in ~w(ERL_AFLAGS ERL_ZFLAGS ERL_LIBS ELIXIR_ERL_OPTIONS ELIXIR_OPTS MIX_ENV MIX_HOME MIX_ARCHIVES MIX_BUILD_PATH MIX_DEPS_PATH HEX_HOME LD_PRELOAD LD_LIBRARY_PATH))
  )
  |> Map.new(&{&1, nil})

env =
  Map.merge(cleared, %{
    "PATH" => utilities,
    "IPSE_HOME" => home,
    "IPSE_TEST_DRAFT_TRANSPORT" => "ollama",
    "TMPDIR" => tmp,
    "ERL_FLAGS" => "+S 2:2",
    "RELEASE_DISTRIBUTION" => "none"
  })
  |> Map.to_list()

{identity_json, 0} =
  System.cmd(Path.join(release, "ipse"), ["version", "--json"], env: env, stderr_to_stdout: true)

identity = :json.decode(identity_json)
^expected_commit_label = identity["commit"]

inventory = fn ->
  for path <- Path.wildcard(release <> "/**/*", match_dot: true), into: %{} do
    value =
      case File.lstat!(path).type do
        :regular -> Ipse.Development.Release.checksum(path)
        :symlink -> {"symlink", File.read_link!(path)}
        :directory -> "directory"
      end

    {Path.relative_to(path, release), value}
  end
end

before_release = inventory.()

eval = """
release = #{inspect(release)}
for name <- ~w(elixir elixirc mix rustc cargo), do: nil = System.find_executable(name)
true = String.starts_with?(System.find_executable("erlc"), release <> "/erts-")
true = String.starts_with?(Application.app_dir(:ipse), release <> "/lib/")
for module <- [Ipse.Session, Ipse.Session.Draft, Ipse.Session.DraftNative, Ipse.Provider.Ollama, Ipse.Session.Saved, Ipse.CLI.Terminal, Ipse.Runner] do
  true = String.starts_with?(List.to_string(:code.which(module)), release <> "/lib/")
end
true = File.regular?(Application.app_dir(:ipse, "priv/ipse-runner"))
Code.prepend_path(#{inspect(Path.join(exunit, "ebin"))})
Code.require_file(#{inspect(source)})
"""

scenarios = [
  {"accept", "--draft-cli", [], "DRAFT_OLLAMA_TRANSPORT_PASSED", "SYNTHETIC_DRAFT_CLI_PASSED"},
  {"cancel", "--enhance-cancel", ["cancel"], "DRAFT_OLLAMA_CANCEL_PASSED",
   "SYNTHETIC_ENHANCE_CANCEL_PASSED"}
]

results =
  try do
    for {scenario, mode, extra, marker, terminal_marker} <- scenarios do
      journey = Path.join(root, scenario)
      File.mkdir!(journey)
      File.chmod!(journey, 0o700)
      args = [mode, Path.join(release, "bin/ipse"), "eval", eval] ++ extra ++ [journey]

      {output, status} =
        System.cmd(driver, args, cd: fixture_dir, env: env, stderr_to_stdout: true)

      log = Path.join(root, scenario <> ".log")
      File.write!(log, output, [:sync])
      File.chmod!(log, 0o600)

      entry = %{
        scenario: scenario,
        exit_status: status,
        marker_present: String.contains?(output, marker),
        terminal_marker_present: String.contains?(output, terminal_marker),
        draft_thinking_visible: String.contains?(output, "draft thinking canary"),
        log_sha256: Ipse.Development.Release.checksum(log)
      }

      File.write!(Path.join(root, "results.jsonl"), [:json.encode(entry), "\n"], [:append, :sync])
      File.chmod!(Path.join(root, "results.jsonl"), 0o600)

      unless status == 0 and entry.marker_present and entry.terminal_marker_present and
               not entry.draft_thinking_visible,
             do:
               raise(
                 "Installed draft scenario #{scenario} failed; preserve its private synthetic log"
               )

      IO.puts("PASS installed Ollama draft #{scenario}")
      entry
    end
  after
    true = before_release == inventory.()
    true = before_inputs == fingerprint.(inputs)
    true = Ipse.Development.Release.checksum(staged_provider) == before_inputs[provider_source]
    :ok = Ipse.Development.Release.verify_checksum!(archive)
    ^expected_archive = Ipse.Development.Release.checksum(archive)
  end

report = %{
  version: 1,
  source_commit_label: identity["commit"],
  archive_sha256: expected_archive,
  input_sha256: before_inputs,
  results: results,
  unchanged_release_inventory: true,
  synthetic_loopback_models_only: true,
  harness:
    "Existing source fixture and native PTY; packaged Ipse runtime and helper; precompiled ExUnit"
}

File.write!(Path.join(root, "report.json"), :json.encode(report))
File.chmod!(Path.join(root, "report.json"), 0o600)
IO.puts("INSTALLED_OLLAMA_DRAFT_BOTH_PASSED")
