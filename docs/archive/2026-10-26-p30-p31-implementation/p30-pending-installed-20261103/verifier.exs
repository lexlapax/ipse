# Synthetic installed-runtime verifier. The source fixture and native PTY driver
# are test support; all Ipse host and bundled worker code comes from the release.
[archive, root] = System.argv()
archive = Path.expand(archive)
root = Path.expand(root)
Code.require_file("../release.exs", __DIR__)

expected_archive = "678b446a8351a9eed9a3ac6ce738064ce9981767842d7cf27dfef9fa60d0667d"
expected_commit_label = "e0daa8119c5da949c886f1c36715eaace04e0455"
:ok = Ipse.Development.Release.verify_checksum!(archive)
^expected_archive = Ipse.Development.Release.checksum(archive)
{:error, :enoent} = File.lstat(root)
File.mkdir!(root)
File.chmod!(root, 0o700)

source = Path.expand("../../test/support/shadow_pending_candidate_cli.exs", __DIR__)
provider_source = Path.expand("../../test/support/provider_fixture.ex", __DIR__)
driver_source = Path.expand("../../test/support/operator_pty.rs", __DIR__)
inputs = [source, provider_source, driver_source, __ENV__.file, Path.expand("../release.exs", __DIR__)]
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
{_, 0} = System.cmd("rustc", ["--edition=2021", "-D", "warnings", driver_source, "-o", driver], stderr_to_stdout: true)
home = Path.join(root, "isolated-home")
tmp = Path.join(root, "tmp")
for path <- [home, tmp] do
  File.mkdir!(path)
  File.chmod!(path, 0o700)
end

# Keep the operator's HOME unchanged, and clear inherited Ipse and VM overrides.
cleared =
  System.get_env()
  |> Map.keys()
  |> Enum.filter(&(String.starts_with?(&1, "IPSE_") or String.starts_with?(&1, "RELEASE_") or &1 in ~w(ERL_AFLAGS ERL_ZFLAGS ERL_LIBS ELIXIR_ERL_OPTIONS ELIXIR_OPTS MIX_ENV MIX_HOME MIX_ARCHIVES MIX_BUILD_PATH MIX_DEPS_PATH HEX_HOME LD_PRELOAD LD_LIBRARY_PATH)))
  |> Map.new(&{&1, nil})

env =
  Map.merge(cleared, %{
    "PATH" => utilities,
    "IPSE_HOME" => home,
    "TMPDIR" => tmp,
    "ERL_FLAGS" => "+S 2:2",
    "RELEASE_DISTRIBUTION" => "none"
  })
  |> Map.to_list()

{identity_json, 0} = System.cmd(Path.join(release, "ipse"), ["version", "--json"], env: env, stderr_to_stdout: true)
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
for module <- [Ipse.CLI, Ipse.Session, Ipse.Session.ManagedUse, Ipse.Extension.DecisionExperiment, Ipse.Extension.Bundles] do
  true = String.starts_with?(List.to_string(:code.which(module)), release <> "/lib/")
end
Code.prepend_path(#{inspect(Path.join(exunit, "ebin"))})
{:ok, entries} = Ipse.Extension.Bundles.inventory()
~w(corpus-collection-documents corpus-state-documents knowledge knowledge-decision-shadow) = Enum.map(entries, & &1.id)
Code.require_file(#{inspect(source)})
"""

scenarios = ~w(save_managed_approval_root_shadow save_managed_approval_deny save_managed_approval_input_source_lost save_managed_approval_output_source_lost save_managed_approval_unknown)
results =
  try do
  for scenario <- scenarios do
    journey = Path.join(root, scenario)
    File.mkdir!(journey)
    File.chmod!(journey, 0o700)
    {output, status} =
      System.cmd(driver, ["--assertion", Path.join(release, "bin/ipse"), "eval", eval, journey, scenario],
        cd: release, env: env, stderr_to_stdout: true)
    log = Path.join(root, scenario <> ".log")
    File.write!(log, output)
    File.chmod!(log, 0o600)
    entry = %{scenario: scenario, exit_status: status, marker_present: String.contains?(output, "SHADOW_EXPERIMENT_SESSION_PASSED"), log_sha256: Ipse.Development.Release.checksum(log)}
    File.write!(Path.join(root, "results.jsonl"), [IO.iodata_to_binary(:json.encode(entry)), "\n"], [:append, :sync])
    File.chmod!(Path.join(root, "results.jsonl"), 0o600)
    unless status == 0 and String.contains?(output, "SHADOW_EXPERIMENT_SESSION_PASSED"),
      do: raise("Installed pending assessment failed in #{scenario}; see private synthetic log")
    IO.puts("PASS installed pending assessment: #{scenario}")
    entry
  end

  after
true = before_release == inventory.()
true = before_inputs == fingerprint.(inputs)
:ok = Ipse.Development.Release.verify_checksum!(archive)
^expected_archive = Ipse.Development.Release.checksum(archive)
  end
report = %{
  version: 1,
  source_commit_label: identity["commit"],
  build_identity: identity,
  archive_sha256: expected_archive,
  input_sha256: before_inputs,
  results: results,
  unchanged_release_inventory: true,
  system_toolchain_on_runtime_path: false,
  synthetic_loopback_models_only: true,
  harness: "Existing source fixture and precompiled ExUnit; packaged Ipse runtime and bundled workers; native PTY compiled separately"
}
File.write!(Path.join(root, "report.json"), :json.encode(report))
File.chmod!(Path.join(root, "report.json"), 0o600)
IO.puts("INSTALLED_PENDING_SHADOW_ALL_FIVE_PASSED")
