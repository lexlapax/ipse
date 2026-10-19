Code.require_file("src/profiles.ex", __DIR__)
Code.require_file("spec.exs", __DIR__)

{opts, [], []} =
  OptionParser.parse(System.argv(),
    strict: [
      artifact: :string,
      package: :string,
      preset: :string,
      instance: :string,
      options: :string,
      output: :string,
      state_binding: :string,
      mcp_bindings: :string,
      inference_config: :string
    ]
  )

artifact = Path.expand(Keyword.fetch!(opts, :artifact))
manifest_path = Path.join(artifact, "extension.json")
%{type: :regular, size: size} = File.lstat!(manifest_path)
true = size <= 16_384
manifest = File.read!(manifest_path)
options = IpseKnowledge.BuildSpec.read_json!(Keyword.fetch!(opts, :options), 16_384)

bindings =
  if opts[:mcp_bindings],
    do: IpseKnowledge.BuildSpec.read_json!(opts[:mcp_bindings], 8192),
    else: %{}

inference =
  if opts[:inference_config],
    do: IpseKnowledge.BuildSpec.read_json!(opts[:inference_config], 16_384),
    else: %{}

config =
  IpseKnowledge.BuildSpec.operator(
    manifest,
    Keyword.fetch!(opts, :package),
    Keyword.fetch!(opts, :preset),
    Keyword.fetch!(opts, :instance),
    options,
    opts[:state_binding],
    bindings,
    inference
  )

output = Path.expand(Keyword.fetch!(opts, :output))
{:ok, file} = File.open(output, [:write, :binary, :exclusive])

try do
  File.chmod!(output, 0o600)
  IO.binwrite(file, JSON.encode!(config))
after
  File.close(file)
end

IO.puts("Wrote disabled instance and exact trust selection. Review before enabling.")
