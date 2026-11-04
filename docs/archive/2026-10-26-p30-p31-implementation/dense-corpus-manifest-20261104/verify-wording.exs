repo = File.cwd!()
packet = Path.join(repo, "_build/verification/ipse-dense-build-diagnostic-20261104-01")
candidate = Path.join(packet, "candidate")
output = Path.join(packet, "corpus-dense-wording")
cache = Path.join(packet, "artifact-cache")
sdk = Path.join(repo, "_build/test/lib/ipse/ebin")
helper = Path.join(repo, "priv/ipse-runner")
true = File.regular?(helper)
false = File.exists?(candidate)
false = File.exists?(output)
false = File.exists?(cache)

source_files =
  ["LICENSE", "extensions/knowledge/build.exs", "extensions/knowledge/spec.exs"] ++
    Path.wildcard("extensions/knowledge/src/**/*.ex")

inputs =
  (source_files ++ ["priv/ipse-runner"] ++ Path.wildcard("_build/test/lib/*/ebin/*"))
  |> Enum.filter(&File.regular?/1)
  |> Enum.sort()

fingerprint = fn ->
  Enum.map_join(inputs, "", fn path ->
    Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower) <> "  " <> path <> "\n"
  end)
end

before = fingerprint.()
File.write!(Path.join(packet, "wording-inputs-before.sha256"), before)

for path <- source_files do
  target = Path.join(candidate, path)
  File.mkdir_p!(Path.dirname(target))
  File.cp!(path, target)
end

File.cp!(Path.join(packet, "corpus-wording.ex"), Path.join(candidate, "extensions/knowledge/src/corpus.ex"))
true = File.read!(Path.join(candidate, "extensions/knowledge/build.exs")) == File.read!("extensions/knowledge/build.exs")
File.chmod!(packet, 0o700)
File.chmod!(Path.join(packet, "home"), 0o700)
System.put_env("IPSE_RUNNER_PATH", helper)

{build, status} =
  System.cmd(System.find_executable("elixir"), [
    "--erl", "+S 1:1 +A 1", "extensions/knowledge/build.exs",
    "--sdk", sdk, "--output", output, "--package", "corpus", "--preset", "collection-dense"
  ], cd: candidate, env: [{"HOME", Path.join(packet, "home")}, {"IPSE_RUNNER_PATH", helper}], stderr_to_stdout: true)

File.write!(Path.join(packet, "wording-build.log"), build)
IO.puts("build_exit=#{status}")
0 = status
"Built corpus/collection-dense. Import, trust and enable it explicitly.\n" = build

for path <- Path.wildcard(Path.join(repo, "_build/test/lib/*/ebin")), do: Code.prepend_path(path)
^sdk = List.to_string(:filename.dirname(:code.which(Ipse.Extension)))
priv = List.to_string(:code.priv_dir(:ipse)) |> Path.expand()
true = File.read!(Path.join(priv, "ipse-runner")) == File.read!(helper)
IO.puts("full_sdk_and_helper_preflight=pass")

bytes = File.read!(Path.join(output, "extension.json"))
{:ok, manifest} = apply(Ipse.Extension.Artifact, :decode, [bytes])
IO.puts("manifest_bytes=#{byte_size(bytes)}")
IO.puts("headroom=#{16_384 - byte_size(bytes)}")
IO.puts("file_count=#{length(manifest["files"])}")
IO.puts("artifact_decode=pass")

{:error, :invalid_extension_manifest} = apply(Ipse.Extension.Artifact, :decode, [bytes <> String.duplicate(" ", 16_385 - byte_size(bytes))])
{:error, :invalid_extension_value} = apply(Ipse.Extension, :validate, [%{"a" => String.duplicate("a", 8192), "b" => String.duplicate("b", 8192)}])
IO.puts("manifest_oversize_and_sdk_16k_guards=pass")

ports_before = Port.list() |> MapSet.new()
{:ok, imported} = apply(Ipse.Extension.Artifact, :import, [output, cache])
{:ok, ^imported} = apply(Ipse.Extension.Artifact, :lookup, [cache, imported.digest])
true = imported.manifest == manifest
true = imported.digest == Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
true = MapSet.subset?(Port.list() |> MapSet.new(), ports_before)
IO.puts("artifact_import_lookup=pass")
IO.puts("artifact_digest=" <> imported.digest)
IO.puts("native_lock_cleanup=pass")

after_inputs = fingerprint.()
File.write!(Path.join(packet, "wording-inputs-after.sha256"), after_inputs)
true = before == after_inputs
IO.puts("main_inputs_unchanged=true")
IO.puts("remaining_build_stages=#{length(Path.wildcard(output <> ".building-*"))}")
