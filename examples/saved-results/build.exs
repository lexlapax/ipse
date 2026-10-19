{options, [], []} = OptionParser.parse(System.argv(), strict: [sdk: :string, output: :string])
sdk = options |> Keyword.fetch!(:sdk) |> Path.expand()
output = options |> Keyword.fetch!(:output) |> Path.expand()
true = File.regular?(Path.join(sdk, "Elixir.Ipse.Extension.ResultPublication.beam"))
false = File.exists?(output)
Code.prepend_path(sdk)

for dependency <- ~w(jason jsonschex ex_json_pointer),
    do: Code.prepend_path(Path.expand("../../#{dependency}/ebin", sdk))

File.mkdir_p!(Path.dirname(output))
stage = output <> ".building-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
File.mkdir_p!(Path.join(stage, "ebin"))
compiler_cwd = Path.join(stage, "compiler/cwd")
File.mkdir_p!(compiler_cwd)

try do
  # Compilation loads the module in this separate builder VM. Keep its load marker
  # inside staging, away from both the source checkout and the final artifact.
  result =
    File.cd!(compiler_cwd, fn ->
      Kernel.ParallelCompiler.compile_to_path(
        [Path.join(__DIR__, "worker.ex")],
        Path.join(stage, "ebin"),
        return_diagnostics: true
      )
    end)

  case result do
    {:ok, _, []} -> :ok
    {:ok, _, %{compile_warnings: [], runtime_warnings: []}} -> :ok
    _ -> raise "Saved-result artifact compilation failed or emitted warnings"
  end

  description =
    File.cd!(compiler_cwd, fn ->
      Code.prepend_path(Path.join(stage, "ebin"))
      Code.ensure_loaded!(IpseSavedResultsExample.Worker)
      IpseSavedResultsExample.Worker.describe()
    end)

  File.rm_rf!(Path.join(stage, "compiler"))
  File.rm!(Path.join(stage, "worker-loads.log"))
  File.cp!(Path.expand("../../LICENSE", __DIR__), Path.join(stage, "LICENSE"))

  manifest = %{
    "format" => 1,
    "id" => "example/saved-results",
    "version" => "0.1.0",
    "sdk" => 2,
    "protocol" => 1,
    "backend" => "elixir_worker",
    "entrypoint" => "IpseSavedResultsExample.Worker",
    "license_file" => "LICENSE",
    "capabilities" => description["capabilities"],
    "exports" => description["exports"],
    "options_schema" => %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["callback_marker"],
      "properties" => %{"callback_marker" => %{"type" => "string"}}
    },
    "runtime" => %{
      "elixir" => ">= 1.18.0",
      "otp" => [String.to_integer(System.otp_release())],
      "platforms" => [to_string(:erlang.system_info(:system_architecture))]
    },
    "files" =>
      for path <- ["LICENSE", "ebin/Elixir.IpseSavedResultsExample.Worker.beam"] do
        bytes = File.read!(Path.join(stage, path))

        %{
          "path" => path,
          "bytes" => byte_size(bytes),
          "sha256" => Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
        }
      end
  }

  encoded = Jason.encode!(manifest)
  {:ok, _} = Ipse.Extensions.Manifest.decode(encoded)
  File.write!(Path.join(stage, "extension.json"), encoded)
  File.rename!(stage, output)
  IO.puts("Built #{output}. Import, trust and enable this artifact explicitly.")
after
  File.rm_rf!(stage)
end
