[root, evidence, sdk_baseline] = System.argv()
root = Path.expand(root)
evidence = Path.expand(evidence)
{:error, :enoent} = File.lstat(evidence)
File.mkdir_p!(evidence)
File.chmod!(evidence, 0o700)
File.cd!(root)
sha = &Base.encode16(:crypto.hash(:sha256, &1), case: :lower)
Process.put(:steps, [])
run = fn name, command, args ->
  IO.puts(JSON.encode!(%{"step" => name, "state" => "running"}))
  executable = if String.starts_with?(command, "."), do: Path.expand(command), else: command
  start = System.monotonic_time(:millisecond)
  {output, status} = System.cmd(executable, args, stderr_to_stdout: true,
    env: [{"ERL_FLAGS", "+S 4:4 +A 2"}])
  path = Path.join(evidence, name <> ".log")
  File.write!(path, output, [:exclusive, :sync])
  row = %{"step" => name, "exit" => status, "milliseconds" => System.monotonic_time(:millisecond) - start,
    "bytes" => byte_size(output), "sha256" => sha.(output)}
  steps = Process.get(:steps) ++ [row]
  Process.put(:steps, steps)
  File.write!(Path.join(evidence, "steps.json"), JSON.encode!(steps) <> "\n", [:sync])
  IO.puts(JSON.encode!(row))
  if status != 0, do: raise("Failed step #{name}; see #{path}")
  if name in ~w(tests native-tests) do
    summary = output |> String.split("\n", trim: true) |> List.last()
    true = Regex.match?(~r/^(?:Result: .*passed|\d+ tests, 0 failures)/, summary)
    false = Regex.match?(~r/\b[1-9][0-9]* failed\b/, summary)
    false = String.contains?(output, "SIGTERM received - shutting down")
  end
  output
end
report = fn output -> output |> String.split("\n", trim: true) |> List.last() |> JSON.decode!() end
check = fn subject, kind, installed ->
  case kind do
    "saved-results" ->
      4_194_304 = subject["byte_count"]
      1024 = subject["fragment_count"]
      for key <- ~w(historical_reads_exact resume_inert journal_unchanged), do: true = subject[key]
      1 = subject["worker_loads"]
      1 = subject["callbacks"]
      0 = subject["model_requests"]
      false = subject["host_loaded_domain_modules"]
      "confirmed" = subject["cleanup"]
    _ ->
      count = map_size(subject["checks"])
      true = if kind == "extension-lab", do: count >= 41, else: count == if(kind == "model-calls", do: 9, else: 12)
      true = Enum.all?(subject["checks"], fn {_, value} -> value == true end)
  end
  if kind == "extension-lab" do
    false = subject["safe_to_continue"]
    "unconfirmed" = subject["expected_terminal_cleanup"]
    if installed, do: true = subject["temporary_cli_selection"]
  end
  if installed do
    true = subject["archive_unchanged"]
    false = subject["system_toolchain_on_runtime_path"]
  end
  subject
end
run.("inventory-before", "elixir", ["/tmp/ipse-p27-r1-source-inventory.exs", evidence <> "/source-before.json"])
for {name, command, args} <- [
  {"build", "./scripts/build.sh", []},
  {"format", "mix", ["format", "--check-formatted"]},
  {"compile", "mix", ["compile", "--warnings-as-errors"]},
  {"docs", "elixir", ["scripts/check-docs.exs"]},
  {"ci-policy", "elixir", ["scripts/check-ci-policy.exs"]},
  {"tests", "mix", if(:os.type() == {:unix, :linux}, do: ["test", "--include", "native_sandbox"], else: ["test"])},
  {"demo", "./bin/ipse", ["demo"]}
], do: run.(name, command, args)
if :os.type() == {:unix, :darwin} do
  run.("native-tests", "mix", ["test", "test/macos_sandbox_test.exs", "test/stdio_runner_test.exs", "test/macos_filesystem_test.exs", "--include", "macos_sandbox", "--include", "macos_filesystem"])
end
artifacts = evidence <> "/artifacts"
sdk = root <> "/_build/dev/lib/ipse/ebin"
recipes = ~w(embedding-actions model-calls mcp-actions saved-results extension-lab)
for recipe <- recipes do
  run.("build-" <> recipe, "elixir", ["scripts/build-artifact.exs", recipe, "--sdk", sdk, "--output", artifacts <> "/" <> recipe])
end
# Compare catalogs and ordered inventories with the actual deleted builders. The
# two compilers use different source paths, so executable-byte identity is not a
# compatibility requirement. Runtime invocation below verifies the new bytes.
old_root = evidence <> "/old-builder-source"
File.mkdir!(old_root)
File.cp!("LICENSE", old_root <> "/LICENSE")
{paths, 0} = System.cmd("git", ["ls-tree", "-r", "--name-only", "c9c4999", "--" | Enum.map(recipes, &("examples/" <> &1))])
for relative <- String.split(paths, "\n", trim: true), Path.extname(relative) in ~w(.ex .exs) do
  {bytes, 0} = System.cmd("git", ["show", "c9c4999:" <> relative])
  path = old_root <> "/" <> relative
  File.mkdir_p!(Path.dirname(path))
  File.write!(path, bytes)
end
for recipe <- recipes do
  output = evidence <> "/old-artifacts/" <> recipe
  run.("old-build-" <> recipe, "elixir", [old_root <> "/examples/" <> recipe <> "/build.exs", "--sdk", sdk, "--output", output])
  leaves = if recipe == "extension-lab", do: ~w(memory memory-v2 lookup metadata observer tool_observer text_observer), else: [""]
  for leaf <- leaves do
    old = Path.join([output, leaf, "extension.json"]) |> File.read!() |> JSON.decode!()
    new = Path.join([artifacts, recipe, leaf, "extension.json"]) |> File.read!() |> JSON.decode!()
    true = Map.drop(old, ["files"]) == Map.drop(new, ["files"])
    true = Enum.map(old["files"], & &1["path"]) == Enum.map(new["files"], & &1["path"])
  end
end
subjects = for recipe <- recipes, reduce: %{} do
  acc ->
    artifact = artifacts <> "/" <> recipe
    modes = if recipe == "model-calls", do: [[], ["none"], ["json"], ["json", "none"]], else: [[]]
    Enum.with_index(modes) |> Enum.reduce(acc, fn {mode, index}, selected ->
      name = "source-" <> recipe <> "-" <> to_string(index)
      value = run.(name, "mix", ["run", "--no-compile", "examples/" <> recipe <> "/verify.exs", artifact | mode]) |> report.() |> check.(recipe, false)
      Map.put(selected, name, value)
    end)
end
run.("manual-exercise", "mix", ["run", "--no-compile", "/tmp/ipse-p27-builder-manual-exercise.exs", artifacts <> "/extension-lab/lookup"])
run.("package", "./scripts/package.sh", [])
[archive] = Path.wildcard(root <> "/dist/ipse-*.tar.gz")
run.("package-installed", "elixir", ["scripts/verify-package.exs", archive])
subjects = for recipe <- recipes, reduce: subjects do
  acc ->
    artifact = artifacts <> "/" <> recipe
    modes = if recipe == "model-calls", do: [[], ["none"], ["json"], ["json-none"]], else: [[]]
    Enum.with_index(modes) |> Enum.reduce(acc, fn {mode, index}, selected ->
      name = "installed-" <> recipe <> "-" <> to_string(index)
      value = run.(name, "elixir", ["examples/" <> recipe <> "/verify-package.exs", archive, artifact | mode]) |> report.() |> check.(recipe, true)
      Map.put(selected, name, value)
    end)
end
inventory = fn base ->
  Path.wildcard(base <> "/**/*", match_dot: true) |> Enum.filter(&File.regular?/1)
  |> Map.new(&{Path.relative_to(&1, base), sha.(File.read!(&1))})
end
baseline_before = inventory.(sdk_baseline)
for {recipe, leaf} <- [{"model-calls", "sdk1-model"}, {"saved-results", "sdk2-results"}], installed <- [false, true] do
  name = "baseline-" <> leaf <> if(installed, do: "-installed", else: "-source")
  {command, args} = if installed,
    do: {"elixir", ["examples/" <> recipe <> "/verify-package.exs", archive, sdk_baseline <> "/" <> leaf]},
    else: {"mix", ["run", "--no-compile", "examples/" <> recipe <> "/verify.exs", sdk_baseline <> "/" <> leaf]}
  run.(name, command, args) |> report.() |> check.(recipe, installed)
end
true = baseline_before == inventory.(sdk_baseline)
if :os.type() == {:unix, :linux} do
  run.("measured-source", "mix", ["run", "scripts/verify-measured-knowledge.exs", "--", root, evidence <> "/measured-source", "--sealed-answers", "--structured"])
  run.("measured-installed", "elixir", ["scripts/verify-measured-knowledge-package.exs", archive, root, evidence <> "/measured-source/artifacts.json", evidence <> "/measured-installed", "--sealed-answers", "--structured"])
end
run.("inventory-after", "elixir", ["/tmp/ipse-p27-r1-source-inventory.exs", evidence <> "/source-after.json"])
true = File.read!(evidence <> "/source-before.json") == File.read!(evidence <> "/source-after.json")
summary = %{"version" => 1, "source_inventory_sha256" => sha.(File.read!(evidence <> "/source-before.json")),
  "steps" => Process.get(:steps), "subjects" => subjects, "catalogs_compared" => 11,
  "sdk_baseline_unchanged" => true, "baseline_inventory" => baseline_before,
  "archive" => %{"file" => Path.basename(archive), "sha256" => sha.(File.read!(archive)), "bytes" => File.stat!(archive).size},
  "limits" => ["Synthetic model/protocol fixtures; no private held-out data or real quality/resource comparison.", "Installed harness isolation is unchanged; common precompiled isolation remains S05.", "Lab deliberately ends with expected unconfirmed cleanup after a required-service crash."]}
File.write!(evidence <> "/summary.json", JSON.encode!(summary) <> "\n", [:exclusive, :sync])
IO.puts("S04 builder source and installed verification completed")
