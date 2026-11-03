[archive, root] = System.argv()
archive = Path.expand(archive)
root = Path.expand(root)
Code.require_file("../release.exs", __DIR__)
:ok = Ipse.Development.Release.verify_checksum!(archive)
source = Path.expand("../../test/support/documents_setup.exs", __DIR__)
driver_source = Path.expand("../../test/support/operator_pty.rs", __DIR__)
false = File.exists?(root)
File.mkdir!(root)
File.chmod!(root, 0o700)
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
File.mkdir!(home)
File.chmod!(home, 0o700)

{identity, 0} =
  System.cmd(Path.join(release, "ipse"), ["version", "--json"],
    env: [{"PATH", utilities}, {"IPSE_HOME", home}, {"ERL_FLAGS", "+S 2:2"}],
    stderr_to_stdout: true
  )

identity = :json.decode(identity)

inventory = fn ->
  for path <- Path.wildcard(release <> "/**/*", match_dot: true), into: %{} do
    value =
      case File.lstat!(path).type do
        :regular -> :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)
        :symlink -> {"symlink", File.read_link!(path)}
        :directory -> "directory"
      end

    {Path.relative_to(path, release), value}
  end
end

before = inventory.()

eval = """
release = #{inspect(release)}
for name <- ~w(elixir elixirc mix rustc cargo), do: nil = System.find_executable(name)
true = String.starts_with?(System.find_executable("erlc"), release <> "/erts-")
true = String.starts_with?(Application.app_dir(:ipse), release <> "/lib/")
for module <- [Ipse.CLI, Ipse.CLI.Documents, Ipse.Extension.Bundles] do
  true = String.starts_with?(List.to_string(:code.which(module)), release <> "/lib/")
end
Code.prepend_path(#{inspect(Path.join(exunit, "ebin"))})
{:ok, entries} = Ipse.Extension.Bundles.inventory()
~w(corpus-collection-documents corpus-state-documents knowledge knowledge-decision-shadow) =
  Enum.map(entries, & &1.id)
Code.require_file(#{inspect(source)})
false = :code.is_loaded(IpseKnowledge.Corpus)
"""

results =
  for {scenario, mode} <- [
        {"state", "--knowledge"},
        {"collection", "--knowledge"},
        {"cancel", "--knowledge-cancel"},
        {"stale", "--knowledge-stale"},
        {"race", "--knowledge-config"},
        {"pipe", nil}
      ] do
    journey = Path.join(root, scenario)
    File.mkdir!(journey)
    File.chmod!(journey, 0o700)
    executable = Path.join(release, "bin/ipse")
    args = ["eval", eval, journey, scenario]

    {executable, args} =
      if mode, do: {driver, [mode, executable | args]}, else: {executable, args}

    {output, status} =
      System.cmd(executable, args,
        cd: release,
        stderr_to_stdout: true,
        env: [
          {"PATH", utilities},
          {"IPSE_HOME", home},
          {"ERL_FLAGS", "+S 2:2"},
          {"RELEASE_DISTRIBUTION", "none"}
        ]
      )

    File.write!(Path.join(root, scenario <> ".log"), output)

    marker =
      if scenario in ~w(state collection),
        do: "DOCUMENT_SETUP_JOURNEY_PASSED",
        else: "DOCUMENT_SETUP_REFUSAL_PASSED"

    unless status == 0 and String.contains?(output, marker),
      do: raise("Installed setup failed in #{scenario}; see private fixture log")

    IO.puts("PASS installed document setup: #{scenario}")

    %{
      scenario: scenario,
      exit_status: status,
      log_sha256: :crypto.hash(:sha256, output) |> Base.encode16(case: :lower)
    }
  end

true = before == inventory.()

report = %{
  version: 1,
  source_commit: identity["commit"],
  build_identity: identity,
  archive_sha256: :crypto.hash(:sha256, File.read!(archive)) |> Base.encode16(case: :lower),
  fixture_sha256: :crypto.hash(:sha256, File.read!(source)) |> Base.encode16(case: :lower),
  results: results,
  unchanged_release_inventory: true,
  system_toolchain_on_runtime_path: false,
  bundled_erlc_visible: true,
  harness:
    "Existing ExUnit fixture source plus copied precompiled ex_unit; bundled runtime code only for Ipse; synthetic Rust PTY compiled before runtime launch",
  model_calls: 0
}

File.write!(Path.join(root, "report.json"), :json.encode(report))
IO.puts("INSTALLED_DOCUMENT_SETUP_ALL_SIX_PASSED")
