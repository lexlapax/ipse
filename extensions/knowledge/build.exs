[{IpseKnowledge.Profiles, profiles_beam}] =
  Code.compile_file(Path.join(__DIR__, "src/profiles.ex"))

Code.require_file("spec.exs", __DIR__)

{opts, [], []} =
  OptionParser.parse(System.argv(),
    strict: [sdk: :string, output: :string, package: :string, preset: :string]
  )

package = Keyword.fetch!(opts, :package)
preset = Keyword.fetch!(opts, :preset)
module = IpseKnowledge.BuildSpec.selection!(package, preset)
sdk = Path.expand(Keyword.fetch!(opts, :sdk))
output = Path.expand(Keyword.fetch!(opts, :output))
true = File.regular?(Path.join(sdk, "Elixir.Ipse.Extension.beam"))
false = File.exists?(output)
Code.prepend_path(sdk)
File.mkdir_p!(Path.dirname(output))
temporary = output <> ".building-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
File.mkdir_p!(Path.join(temporary, "ebin"))

try do
  File.write!(Path.join(temporary, "ebin/Elixir.IpseKnowledge.Profiles.beam"), profiles_beam)
  entry = File.read!(Path.join([__DIR__, "src", package <> ".ex"]))
  literal = "@preset " <> inspect(IpseKnowledge.BuildSpec.default(package))
  1 = length(:binary.matches(entry, literal))
  transformed = String.replace(entry, literal, "@preset " <> inspect(preset), global: false)
  entry_path = Path.join(temporary, package <> ".ex")
  File.write!(entry_path, transformed)

  helpers =
    for path <- ~w(evidence store store/state store/mcp_cas adapters),
        do: Path.join([__DIR__, "src", path <> ".ex"])

  result =
    Kernel.ParallelCompiler.compile_to_path(
      helpers ++ [entry_path],
      Path.join(temporary, "ebin"),
      return_diagnostics: true
    )

  case result do
    {:ok, _, warnings} when warnings == [] -> :ok
    {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> :ok
    _ -> raise "Artifact compilation failed or emitted diagnostics."
  end

  description = module.describe()
  true = description["sdk"] === 2
  true = description["capabilities"] == IpseKnowledge.Profiles.capabilities(package, preset)
  File.rm!(entry_path)
  File.cp!(Path.expand("../../LICENSE", __DIR__), Path.join(temporary, "LICENSE"))

  files =
    [
      "LICENSE"
      | Enum.map(
          Path.wildcard(Path.join(temporary, "ebin/*.beam")),
          &Path.relative_to(&1, temporary)
        )
    ]
    |> Enum.sort()

  manifest = %{
    "format" => 1,
    "id" => "ipse-knowledge/" <> package,
    "version" => "0.1.0",
    "sdk" => 2,
    "protocol" => 1,
    "backend" => "elixir_worker",
    "entrypoint" => module |> Atom.to_string() |> String.replace_prefix("Elixir.", ""),
    "license_file" => "LICENSE",
    "options_schema" => IpseKnowledge.BuildSpec.options_schema(),
    "capabilities" => description["capabilities"],
    "exports" => description["exports"],
    "runtime" => %{
      "elixir" => ">= 1.18.0",
      "otp" => [String.to_integer(System.otp_release())],
      "platforms" => [to_string(:erlang.system_info(:system_architecture))]
    },
    "files" =>
      Enum.map(files, fn path ->
        bytes = File.read!(Path.join(temporary, path))

        %{
          "path" => path,
          "bytes" => byte_size(bytes),
          "sha256" => IpseKnowledge.BuildSpec.digest(bytes)
        }
      end)
  }

  manifest_bytes = IO.iodata_to_binary(JSON.encode!(manifest))
  true = byte_size(manifest_bytes) <= 16_384
  File.write!(Path.join(temporary, "extension.json"), manifest_bytes)
  File.rename!(temporary, output)
  IO.puts("Built #{package}/#{preset}. Import, trust and enable it explicitly.")
after
  File.rm_rf!(temporary)
end
