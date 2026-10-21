[recipe | arguments] = System.argv()
true = recipe in ~w(embedding-actions model-calls mcp-actions saved-results extension-lab)

{options, [], []} =
  OptionParser.parse(arguments,
    strict: [sdk: [:string, :keep], output: [:string, :keep], omit: [:string, :keep]]
  )

true = Enum.sort(Keyword.keys(options)) in [[:output, :sdk], [:omit, :output, :sdk]]
true = recipe == "mcp-actions" or not Keyword.has_key?(options, :omit)
sdk = options |> Keyword.fetch!(:sdk) |> Path.expand()
output = options |> Keyword.fetch!(:output) |> Path.expand()
true = File.regular?(Path.join(sdk, "Elixir.Ipse.Extension.beam"))

if recipe == "saved-results",
  do: true = File.regular?(Path.join(sdk, "Elixir.Ipse.Extension.ResultPublication.beam"))

Code.prepend_path(sdk)

for dependency <- ~w(jason jsonschex ex_json_pointer),
    do: Code.prepend_path(Path.expand("../../#{dependency}/ebin", sdk))

root = Path.expand("..", __DIR__)

if recipe == "extension-lab" do
  {_, []} =
    Code.with_diagnostics([log: true], fn ->
      Code.require_file("examples/extension-lab/spec.exs", root)
    end)
end

defmodule Ipse.Development.ArtifactBuilder do
  @mcp_capabilities ~w(invoke.command host.actions host.mcp host.results host.actions.mixed host.state.read host.question)

  def build(root, recipe, options, output) do
    {:error, :enoent} = File.lstat(output)
    File.mkdir_p!(Path.dirname(output))
    stage = output <> ".building-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    File.mkdir!(stage)
    compiler = Path.join(stage, "compiler")
    cwd = Path.join(compiler, "cwd")

    try do
      File.chmod!(stage, 0o700)
      File.mkdir_p!(cwd)

      for job <- jobs(recipe) do
        directory = Path.join(stage, job.directory)
        ebin = Path.join(directory, "ebin")
        File.mkdir_p!(ebin)
        source = File.read!(Path.join(root, job.source))

        source =
          cond do
            recipe == "extension-lab" ->
              String.replace(source, ~s("LAB_PACKAGE_VERSION"), inspect(job.version))

            recipe == "mcp-actions" ->
              omitted = (options[:omit] || "") |> String.split(",", trim: true)

              true =
                omitted == Enum.uniq(omitted) and Enum.all?(omitted, &(&1 in @mcp_capabilities))

              if omitted == [] do
                source
              else
                pattern = ~r/@capabilities ~w\(([^\n]+)\)/
                [[_, declared]] = Regex.scan(pattern, source)
                true = String.split(declared) == @mcp_capabilities

                String.replace(
                  source,
                  pattern,
                  "@capabilities " <> inspect(@mcp_capabilities -- omitted)
                )
              end

            true ->
              source
          end

        result =
          File.cd!(cwd, fn ->
            Code.with_diagnostics([log: true], fn ->
              Code.compile_string(source, Path.join(root, job.source))
            end)
          end)

        {module, beam} =
          case result do
            {[compiled], []} -> compiled
            _ -> raise "Artifact compilation failed or emitted warnings"
          end

        description = File.cd!(cwd, fn -> apply(module, :describe, []) end)

        entrypoint = module |> Atom.to_string() |> String.replace_prefix("Elixir.", "")

        if recipe == "extension-lab" do
          true = description == apply(IpseLab.Spec, :description, [job.kind])
          true = entrypoint == apply(IpseLab.Spec, :module, [job.kind])
        end

        File.cp!(Path.join(root, "LICENSE"), Path.join(directory, "LICENSE"))
        beam_path = "ebin/" <> Atom.to_string(module) <> ".beam"
        File.write!(Path.join(directory, beam_path), beam)

        paths =
          if recipe == "saved-results", do: ["LICENSE", beam_path], else: [beam_path, "LICENSE"]

        manifest = %{
          "format" => 1,
          "id" => job.id,
          "version" => job.version,
          "sdk" => if(recipe == "saved-results", do: 2, else: 1),
          "protocol" => 1,
          "backend" => "elixir_worker",
          "entrypoint" => entrypoint,
          "license_file" => "LICENSE",
          "capabilities" => description["capabilities"],
          "options_schema" => job.options,
          "runtime" => %{
            "elixir" => ">= 1.18.0",
            "otp" => [String.to_integer(System.otp_release())],
            "platforms" => [to_string(:erlang.system_info(:system_architecture))]
          },
          "files" =>
            Enum.map(paths, fn path ->
              bytes = File.read!(Path.join(directory, path))

              %{
                "path" => path,
                "bytes" => byte_size(bytes),
                "sha256" => Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
              }
            end)
        }

        manifest =
          Enum.reduce(~w(exports requires subscriptions), manifest, fn key, acc ->
            if Map.has_key?(description, key), do: Map.put(acc, key, description[key]), else: acc
          end)

        encoded = Jason.encode!(manifest)
        {:ok, _} = Ipse.Extensions.Manifest.decode(encoded)
        File.write!(Path.join(directory, "extension.json"), encoded)
        :code.delete(module)
        :code.purge(module)
      end

      File.rm_rf!(compiler)
      if recipe == "saved-results", do: File.rm!(Path.join(stage, "worker-loads.log"))
      File.rename!(stage, output)
      IO.puts("Built #{output}. Import, trust and enable these artifacts explicitly.")
    after
      File.rm_rf!(stage)
    end
  end

  defp jobs("extension-lab") do
    for {name, kind, version} <- [
          {"memory", :memory, "0.1.0"},
          {"memory-v2", :memory, "0.2.0"},
          {"lookup", :lookup, "0.1.0"},
          {"metadata", :metadata, "0.1.0"},
          {"observer", :observer, "0.1.0"},
          {"tool_observer", :tool_observer, "0.1.0"},
          {"text_observer", :text_observer, "0.1.0"}
        ] do
      %{
        directory: name,
        kind: kind,
        version: version,
        id: "ipse-lab/#{kind}",
        source: "examples/extension-lab/src/#{kind}.ex",
        options: apply(IpseLab.Spec, :options, [kind])
      }
    end
  end

  defp jobs(recipe) do
    {id, source} =
      case recipe do
        "embedding-actions" -> {"ipse-example/embedding-actions", "src/embed.ex"}
        "model-calls" -> {"ipse-example/model-complete", "src/complete.ex"}
        "mcp-actions" -> {"ipse-example/mcp-read", "src/read.ex"}
        "saved-results" -> {"example/saved-results", "worker.ex"}
      end

    options =
      if recipe == "saved-results" do
        %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["callback_marker"],
          "properties" => %{"callback_marker" => %{"type" => "string"}}
        }
      else
        %{"type" => "object", "additionalProperties" => false}
      end

    [
      %{
        directory: "",
        source: "examples/#{recipe}/#{source}",
        id: id,
        version: "0.1.0",
        options: options
      }
    ]
  end
end

Ipse.Development.ArtifactBuilder.build(root, recipe, options, output)
