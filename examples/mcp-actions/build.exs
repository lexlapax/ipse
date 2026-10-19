{options, [], []} =
  OptionParser.parse(System.argv(), strict: [sdk: :string, output: :string, omit: :string])

sdk = Path.expand(Keyword.fetch!(options, :sdk))
output = Path.expand(Keyword.fetch!(options, :output))
true = File.regular?(Path.join(sdk, "Elixir.Ipse.Extension.beam"))
Code.prepend_path(sdk)
File.mkdir_p!(Path.join(output, "ebin"))
omitted = (options[:omit] || "") |> String.split(",", trim: true)
source = File.read!(Path.join(__DIR__, "src/read.ex"))

source =
  if omitted == [] do
    source
  else
    capabilities =
      ~w(invoke.command host.actions host.mcp host.results host.actions.mixed host.state.read host.question) --
        omitted

    String.replace(
      source,
      ~r/@capabilities ~w\([^\n]+\)/,
      "@capabilities " <> inspect(capabilities)
    )
  end

[{module, beam}] = Code.compile_string(source, "mcp-actions/read.ex")
description = module.describe()
beam_path = "ebin/" <> Atom.to_string(module) <> ".beam"
File.write!(Path.join(output, beam_path), beam)
File.cp!(Path.expand("../../LICENSE", __DIR__), Path.join(output, "LICENSE"))

manifest = %{
  "format" => 1,
  "id" => "ipse-example/mcp-read",
  "version" => "0.1.0",
  "sdk" => 1,
  "protocol" => 1,
  "backend" => "elixir_worker",
  "entrypoint" => module |> Atom.to_string() |> String.replace_prefix("Elixir.", ""),
  "license_file" => "LICENSE",
  "options_schema" => %{"type" => "object", "additionalProperties" => false},
  "capabilities" => description["capabilities"],
  "exports" => description["exports"],
  "runtime" => %{
    "elixir" => ">= 1.18.0",
    "otp" => [String.to_integer(System.otp_release())],
    "platforms" => [to_string(:erlang.system_info(:system_architecture))]
  },
  "files" =>
    for path <- [beam_path, "LICENSE"], bytes = File.read!(Path.join(output, path)) do
      %{
        "path" => path,
        "bytes" => byte_size(bytes),
        "sha256" => Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
      }
    end
}

File.write!(Path.join(output, "extension.json"), :json.encode(manifest))
IO.puts("Built an inert MCP result-reader artifact; import, trust and binding remain explicit.")
