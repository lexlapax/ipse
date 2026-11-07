# Installed, synthetic operator-authored planning decisions; no model service.
# Run with the package-matched Elixir/OTP and ExUnit, from the repository root:
# timeout --kill-after=10s 180s elixir dev/verification/planning_decision_installed.exs \
#   ARCHIVE ABSENT_PRIVATE_ROOT ARCHIVE_SHA256 FULL_COMMIT
# The existing PTY bounds each journey to 60 seconds. Retain ROOT on any failure.
[archive, root, expected_archive, expected_commit] = System.argv()
archive = Path.expand(archive)
root = Path.expand(root)
Code.require_file("../release.exs", __DIR__)

true = Regex.match?(~r/\A[0-9a-f]{64}\z/, expected_archive)
true = Regex.match?(~r/\A[0-9a-f]{40}\z/, expected_commit)
:ok = Ipse.Development.Release.verify_checksum!(archive)
^expected_archive = Ipse.Development.Release.checksum(archive)
{:error, :enoent} = File.lstat(root)
File.mkdir!(root)
File.chmod!(root, 0o700)

write_private = fn path, bytes ->
  File.write!(path, bytes, [:exclusive, :sync])
  File.chmod!(path, 0o600)
end

fingerprint = fn paths ->
  Map.new(paths, &{&1, Ipse.Development.Release.checksum(&1)})
end

inventory = fn directory ->
  for path <- Path.wildcard(directory <> "/**/*", match_dot: true), into: %{} do
    value =
      case File.lstat!(path).type do
        :regular -> Ipse.Development.Release.checksum(path)
        :symlink -> %{"symlink" => File.read_link!(path)}
        :directory -> "directory"
      end

    {Path.relative_to(path, directory), value}
  end
end

source = Path.expand("../../test/support/planning_decision_cli.exs", __DIR__)
driver_source = Path.expand("../../test/support/operator_pty.rs", __DIR__)
inputs = [source, driver_source, __ENV__.file, Path.expand("../release.exs", __DIR__)]
before_inputs = fingerprint.(inputs)
write_private.(Path.join(root, "inputs.json"), :json.encode(before_inputs))

release = Path.join(root, "release")
File.mkdir!(release)
{"", 0} = System.cmd("tar", ["-xzf", archive, "-C", release], stderr_to_stdout: true)
before_release = inventory.(release)

exunit = Path.join(root, "ex_unit")
{:ok, _} = File.cp_r(Application.app_dir(:ex_unit), exunit)
before_exunit = inventory.(exunit)
fixture = Path.join(root, "planning_decision_cli.exs")
write_private.(fixture, File.read!(source))

driver = Path.join(root, "pty")

{compile_output, compile_status} =
  System.cmd("rustc", ["--edition=2021", "-D", "warnings", driver_source, "-o", driver],
    stderr_to_stdout: true
  )

write_private.(Path.join(root, "driver-compile.log"), compile_output)
true = compile_status == 0
driver_sha256 = Ipse.Development.Release.checksum(driver)

utilities = Path.join(root, "utilities")
home = Path.join(root, "isolated-home")
tmp = Path.join(root, "tmp")

for directory <- [utilities, home, tmp] do
  File.mkdir!(directory)
  File.chmod!(directory, 0o700)
end

for name <- ~w(dirname basename cut sed cat grep readlink sleep uname expr awk id tr head) do
  executable = System.find_executable(name)
  true = is_binary(executable)
  File.ln_s!(executable, Path.join(utilities, name))
end

# No host Elixir, compiler, inherited Ipse configuration or loader overrides in
# the installed child. ExUnit and the unchanged fixture are explicit test inputs.
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
    "HOME" => home,
    "IPSE_HOME" => home,
    "TMPDIR" => tmp,
    "ERL_FLAGS" => "+S 1:1 +A 1",
    "RELEASE_DISTRIBUTION" => "none"
  })
  |> Map.to_list()

{identity_json, 0} =
  System.cmd(Path.join(release, "ipse"), ["version", "--json"], env: env, stderr_to_stdout: true)

identity = :json.decode(identity_json)
^expected_commit = identity["commit"]

eval = """
release = #{inspect(release)}
for name <- ~w(elixir elixirc mix rustc cargo), do: nil = System.find_executable(name)
true = String.starts_with?(System.find_executable("erlc"), release <> "/erts-")
true = String.starts_with?(Application.app_dir(:ipse), release <> "/lib/")
for module <- [Ipse.Session, Ipse.Session.PlanningDecisions, Ipse.Session.PlanningTransition, Ipse.Session.Saved, Ipse.CLI.Terminal, Ipse.Extension.Consent, Ipse.Extension.Collection, Ipse.Runner] do
  {:module, ^module} = Code.ensure_loaded(module)
  true = String.starts_with?(List.to_string(:code.which(module)), release <> "/lib/")
end
true = File.regular?(Application.app_dir(:ipse, "priv/ipse-runner"))
Code.prepend_path(#{inspect(Path.join(exunit, "ebin"))})
Code.require_file(#{inspect(fixture)})
"""

# Keep the existing fixture intact: its watcher verifies no publication before
# explicit post-exit save, and revokes actual saved consent before plan_revoked.
# PlanningDecisionUnexpectedModel raises on any attempted model completion.
outcome =
  try do
    results =
      for scenario <- ~w(plan_save plan_revoked) do
        journey = Path.join(root, scenario)
        File.mkdir!(journey)
        File.chmod!(journey, 0o700)

        args = [
          "--planning-decision",
          Path.join(release, "bin/ipse"),
          "eval",
          eval,
          journey,
          scenario
        ]

        started = System.monotonic_time(:millisecond)
        {output, status} = System.cmd(driver, args, cd: release, env: env, stderr_to_stdout: true)
        elapsed = System.monotonic_time(:millisecond) - started
        log = Path.join(root, scenario <> ".log")
        write_private.(log, output)

        entry = %{
          scenario: scenario,
          exit_status: status,
          elapsed_ms: elapsed,
          fixture_marker_present: String.contains?(output, "PLANNING_DECISION_JOURNEY_PASSED"),
          log_sha256: Ipse.Development.Release.checksum(log)
        }

        write_private.(Path.join(root, scenario <> ".json"), :json.encode(entry))

        unless status == 0 and entry.fixture_marker_present,
          do: raise("Installed planning scenario #{scenario} failed; retain private evidence")

        IO.puts("PASS installed planning decision #{scenario}")
        entry
      end

    {:ok, results}
  rescue
    exception -> {:error, exception, __STACKTRACE__}
  end

posts = %{
  unchanged_release: before_release == inventory.(release),
  unchanged_sources: before_inputs == fingerprint.(inputs),
  unchanged_exunit: before_exunit == inventory.(exunit),
  unchanged_fixture: Ipse.Development.Release.checksum(fixture) == before_inputs[source],
  unchanged_driver: Ipse.Development.Release.checksum(driver) == driver_sha256,
  unchanged_archive: Ipse.Development.Release.checksum(archive) == expected_archive,
  valid_archive_sidecar:
    try do
      :ok = Ipse.Development.Release.verify_checksum!(archive)
      true
    rescue
      _ -> false
    end
}

write_private.(Path.join(root, "posts.json"), :json.encode(posts))

case outcome do
  {:error, exception, stacktrace} ->
    reraise exception, stacktrace

  {:ok, results} ->
    true = Enum.all?(posts, fn {_, unchanged} -> unchanged end)

    report = %{
      version: 1,
      source_commit_label: expected_commit,
      archive_sha256: expected_archive,
      input_sha256: before_inputs,
      exunit_inventory: before_exunit,
      driver_sha256: driver_sha256,
      results: results,
      posts: posts,
      model_calls_permitted: false,
      scope:
        "Synthetic operator-authored plan_save and plan_revoked; not assistant or human qualification"
    }

    write_private.(Path.join(root, "report.json"), :json.encode(report))
    IO.puts("INSTALLED_PLANNING_DECISION_BOTH_PASSED")
end
