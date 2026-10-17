Code.require_file("spec.exs", __DIR__)
{options, [], []} = OptionParser.parse(System.argv(), strict: [sdk: :string, output: :string])
sdk = Path.expand(Keyword.fetch!(options, :sdk))
output = Path.expand(Keyword.fetch!(options, :output))
true = File.regular?(Path.join(sdk, "Elixir.Ipse.Extension.beam"))
Code.prepend_path(sdk)
File.mkdir_p!(output)

for {name, kind, version} <- [
      {"memory", :memory, "0.1.0"},
      {"memory-v2", :memory, "0.2.0"},
      {"lookup", :lookup, "0.1.0"},
      {"metadata", :metadata, "0.1.0"},
      {"observer", :observer, "0.1.0"},
      {"tool_observer", :tool_observer, "0.1.0"},
      {"text_observer", :text_observer, "0.1.0"}
    ] do
  directory = Path.join(output, name)
  File.mkdir_p!(Path.join(directory, "ebin"))

  source =
    File.read!(Path.join([__DIR__, "src", "#{kind}.ex"]))
    |> String.replace(~s("LAB_PACKAGE_VERSION"), inspect(version))

  [{module, beam}] = Code.compile_string(source, "extension-lab/#{kind}.ex")
  beam_path = "ebin/" <> Atom.to_string(module) <> ".beam"
  File.write!(Path.join(directory, beam_path), beam)
  File.cp!(Path.expand("../../LICENSE", __DIR__), Path.join(directory, "LICENSE"))
  description = IpseLab.Spec.description(kind)

  manifest = %{
    "format" => 1,
    "id" => "ipse-lab/#{kind}",
    "version" => version,
    "sdk" => 1,
    "protocol" => 1,
    "backend" => "elixir_worker",
    "entrypoint" => IpseLab.Spec.module(kind),
    "license_file" => "LICENSE",
    "capabilities" => description["capabilities"],
    "options_schema" => IpseLab.Spec.options(kind),
    "runtime" => %{
      "elixir" => ">= 1.18.0",
      "otp" => [String.to_integer(System.otp_release())],
      "platforms" => [to_string(:erlang.system_info(:system_architecture))]
    },
    "files" =>
      for(
        path <- [beam_path, "LICENSE"],
        bytes = File.read!(Path.join(directory, path)),
        do: %{
          "path" => path,
          "bytes" => byte_size(bytes),
          "sha256" => Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
        }
      )
  }

  manifest =
    Enum.reduce(~w(exports requires subscriptions), manifest, fn key, m ->
      if Map.has_key?(description, key), do: Map.put(m, key, description[key]), else: m
    end)

  File.write!(Path.join(directory, "extension.json"), :json.encode(manifest))
  :code.delete(module)
  :code.purge(module)
end

IO.puts(
  "Built seven inert local artifacts; import and execution require separate operator actions."
)
