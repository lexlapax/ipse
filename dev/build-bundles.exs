sdk = Application.app_dir(:ipse, "ebin")
root = Path.expand("../priv/extension-bundles", __DIR__)
staging = root <> ".building-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
false = File.exists?(staging)
File.mkdir_p!(staging)

try do
  entries =
    for {id, package, preset} <- [
          {"corpus-collection-documents", "corpus", "collection-documents"},
          {"corpus-state-documents", "corpus", "state-documents"},
          {"knowledge", "knowledge", "native"}
        ] do
      output = Path.join(staging, id)

      args = [
        "extensions/knowledge/build.exs",
        "--sdk",
        sdk,
        "--output",
        output,
        "--package",
        package,
        "--preset",
        preset
      ]

      {text, 0} = System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)

      IO.write(text)
      bytes = File.read!(Path.join(output, "extension.json"))
      :ok = Ipse.Extension.Artifact.decode(bytes) |> then(fn {:ok, _} -> :ok end)
      %{"id" => id, "path" => id, "manifest_sha256" => Ipse.JSON.sha256(bytes)}
    end

  catalog = %{
    "version" => 1,
    "artifacts" => entries
  }

  File.write!(Path.join(staging, "catalog.json"), Jason.encode!(catalog, pretty: true) <> "\n")
  {:ok, artifacts} = Ipse.Extension.Bundles.inventory(staging)
  true = Enum.map(artifacts, & &1.id) == Enum.map(entries, & &1["id"])

  case File.lstat(root) do
    {:error, :enoent} -> :ok
    {:ok, %{type: :directory}} -> File.rm_rf!(root)
  end

  File.rename!(staging, root)
  IO.puts("Built inert extension bundle catalog; artifacts remain disabled until operator setup.")
after
  File.rm_rf!(staging)
end
