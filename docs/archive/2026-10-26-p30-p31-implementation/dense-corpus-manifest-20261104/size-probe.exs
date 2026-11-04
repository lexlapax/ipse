packet = Path.expand("_build/verification/ipse-dense-build-diagnostic-20261104-01")
sdk = Path.expand("_build/test/lib/ipse/ebin")
inputs =
  (["LICENSE", "extensions/knowledge/build.exs", "extensions/knowledge/spec.exs"] ++
     Path.wildcard("extensions/knowledge/src/**/*.ex") ++
     Path.wildcard("_build/test/lib/*/ebin/*"))
  |> Enum.filter(&File.regular?/1)
  |> Enum.sort()

fingerprint = fn ->
  Enum.map_join(inputs, "", fn path ->
    Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower) <> "  " <> path <> "\n"
  end)
end

before = fingerprint.()
File.write!(Path.join(packet, "size-inputs-before.sha256"), before)
output = Path.join(packet, "corpus-dense")
System.argv(["--sdk", sdk, "--output", output, "--package", "corpus", "--preset", "collection-dense"])

try do
  path = Path.expand("extensions/knowledge/build.exs")
  source = File.read!(path)
  assertion = "true = byte_size(manifest_bytes) <= 16_384"
  1 = length(:binary.matches(source, assertion))
  observation = ~S|IO.puts("manifest_bytes=" <> to_string(byte_size(manifest_bytes))); IO.puts("file_count=" <> to_string(length(manifest["files"]))); Enum.each(Enum.sort(Map.keys(manifest)), fn key -> IO.puts("section_bytes_" <> key <> "=" <> to_string(byte_size(IO.iodata_to_binary(JSON.encode!(manifest[key]))))) end); |
  derived = String.replace(source, assertion, observation <> assertion)
  Code.eval_string(derived, [], file: path)
  IO.puts("build_result=success")
rescue
  error ->
    IO.puts("build_exception=" <> inspect(error.__struct__))

    for {_module, function, _arity, location} <- __STACKTRACE__,
        String.ends_with?(to_string(location[:file]), "extensions/knowledge/build.exs") do
      IO.puts("build_frame=" <> to_string(location[:file]) <> ":" <> to_string(location[:line]) <> ":" <> to_string(function))
    end

    description = apply(IpseKnowledge.Corpus, :describe, [])
    encoded = apply(JSON, :encode!, [description["exports"]]) |> IO.iodata_to_binary()
    IO.puts("exports_bytes=" <> Integer.to_string(byte_size(encoded)))
    IO.puts("catalog=" <> inspect(apply(Ipse.Extension.Catalog, :validate, [description["exports"], description["capabilities"]])))
    IO.puts("commands=" <> Integer.to_string(length(description["exports"]["commands"])))
    IO.puts("tools=" <> Integer.to_string(length(description["exports"]["tools"])))
end

after_inputs = fingerprint.()
File.write!(Path.join(packet, "size-inputs-after.sha256"), after_inputs)
IO.puts("inputs_unchanged=" <> to_string(before == after_inputs))
IO.puts("published_output=" <> to_string(File.exists?(output)))
IO.puts("remaining_build_stages=" <> to_string(length(Path.wildcard(output <> ".building-*"))))
