{options, [], []} =
  OptionParser.parse(System.argv(),
    strict: [output: :string, notices: :string, target_dir: :string]
  )

output = options |> Keyword.fetch!(:output) |> Path.expand()
notices = options |> Keyword.fetch!(:notices) |> Path.expand()

target =
  options
  |> Keyword.get(
    :target_dir,
    System.get_env("CARGO_TARGET_DIR") || Path.expand("../../_build/ipse-pdf", __DIR__)
  )
  |> Path.expand()

manifest = Path.join(__DIR__, "Cargo.toml")
inventory = __DIR__ |> Path.join("dependency-inventory.json") |> File.read!() |> JSON.decode!()

command = fn arguments ->
  {text, status} =
    System.cmd("cargo", arguments ++ ["--manifest-path", manifest],
      env: [{"CARGO_TARGET_DIR", target}],
      stderr_to_stdout: true
    )

  unless status == 0, do: raise("PDF parser Cargo operation failed: " <> text)
  text
end

metadata = command.(["metadata", "--format-version", "1", "--locked"]) |> JSON.decode!()

packages =
  metadata["packages"] |> Enum.reject(&(&1["name"] == "ipse-pdf")) |> Enum.sort_by(& &1["name"])

reviewed = Enum.map(inventory["packages"], &Map.take(&1, ~w(name version license)))

unless Enum.map(packages, &Map.take(&1, ~w(name version license))) == reviewed,
  do: raise("PDF parser dependencies differ from the reviewed inventory")

command.(["build", "--release", "--locked"])

File.mkdir_p!(Path.dirname(output))
File.cp!(Path.join(target, "release/ipse-pdf"), output)
File.chmod!(output, 0o755)
File.mkdir_p!(notices)

for package <- packages do
  source = Path.dirname(package["manifest_path"])
  destination = Path.join(notices, package["name"] <> "-" <> package["version"])
  File.mkdir_p!(destination)

  files =
    File.ls!(source)
    |> Enum.filter(&Regex.match?(~r/\A(?:LICENSE|COPYING|COPYRIGHT|NOTICE|AUTHORS)/i, &1))

  if files == [] do
    if package["name"] == "alloc-stdlib" and package["version"] == "0.2.4" do
      # This crate is a subdirectory of rust-alloc-no-stdlib and omits the
      # repository-root LICENSE from its package. The reviewed copy retains the
      # exact repository-root notice from its .cargo_vcs_info commit.
      File.cp!(
        Path.join(__DIR__, "notices/alloc-stdlib-LICENSE"),
        Path.join(destination, "LICENSE")
      )
    else
      raise("Dependency has no retained license/notice file: " <> package["name"])
    end
  end

  for file <- files,
      File.regular?(Path.join(source, file)),
      do: File.cp!(Path.join(source, file), Path.join(destination, file))
end

for name <- ~w(DEPENDENCIES.md dependency-inventory.json Cargo.lock),
    do: File.cp!(Path.join(__DIR__, name), Path.join(notices, name))

File.cp_r!(Path.join(__DIR__, "notices"), Path.join(notices, "notices"))

File.cp!(Path.expand("../../LICENSE", __DIR__), Path.join(notices, "IPSE-LICENSE"))
IO.puts("Built optional experimental PDF parser and retained dependency notices.")
