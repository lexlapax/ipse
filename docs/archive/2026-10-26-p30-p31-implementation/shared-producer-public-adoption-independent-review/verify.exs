base = "docs/archive/2026-10-26-p30-p31-implementation/shared-producer-public-adoption"
hash = fn b -> Base.encode16(:crypto.hash(:sha256, b), case: :lower) end
bytes = File.read!(base <> "/manifest.json")
"2b503a998c9eaa03dd3b3a878fd2c2a9dbdcd33e40d35209e05ca896ad16c098" = hash.(bytes)
m = :json.decode(bytes)

walk = fn recur, v ->
  cond do
    is_map(v) and is_binary(v["path"]) and is_binary(v["sha256"]) -> [v]
    is_map(v) -> Enum.flat_map(Map.values(v), &recur.(recur, &1))
    is_list(v) -> Enum.flat_map(v, &recur.(recur, &1))
    true -> []
  end
end

rows = walk.(walk, m)

Enum.each(rows, fn r ->
  true = File.stat!(r["path"]).size === r["bytes"]
  true = hash.(File.read!(r["path"])) === r["sha256"]
end)

for a <- m["artifacts"] do
  {files, 0} = System.cmd("rg", ["--files", "--hidden", "--no-ignore", a["root"]])

  true =
    MapSet.new(String.split(files, "\n", trim: true)) ===
      MapSet.new(Enum.map(a["rows"], & &1["path"]))
end

native =
  "docs/archive/2026-10-26-p30-p31-implementation/shared-producer-guard-session/private-package"

ast = fn s ->
  Code.string_to_quoted!(s)
  |> Macro.prewalk(fn
    {a, m, b} when is_list(m) -> {a, [], b}
    x -> x
  end)
end

source = base <> "/source/extensions/knowledge"

true =
  ast.(File.read!(source <> "/src/corpus.ex")) === ast.(File.read!(native <> "/src/corpus.ex"))

true = File.read!(source <> "/src/adapters.ex") === File.read!(native <> "/src/adapters.ex")

true =
  File.read!(source <> "/src/store/collection/producer.ex") ===
    String.replace(
      File.read!(native <> "/src/store/collection/producer.ex"),
      "          \"source_dispatch_available\" => false,\n",
      "", global: false)

canonical = Enum.at(m["artifacts"], 1)["root"]
manifest = File.read!(canonical <> "/extension.json")
"a7eba4d0daf79bcd6ec2d268a22b12e41b16bdae55d839f17284372218b8a5e6" = hash.(manifest)

native_manifest =
  :json.decode(
    File.read!("_build/shared-producer-guard-session-20261029/artifact/extension.json")
  )

keys = ~w(sdk id entrypoint capabilities exports options_schema)
true = Map.take(:json.decode(manifest), keys) === Map.take(native_manifest, keys)
config = :json.decode(File.read!(base <> "/operator.json"))
inference = :json.decode(File.read!(base <> "/inference.json"))
true = config["inference_services"] === inference["inference_services"]
[instance] = config["extensions"]
false = instance["enabled"]
[trust] = config["extension_trust"]
[%{"version" => 2, "source_use" => "shared_producer_v1"}] = trust["collection_bindings"]
IO.puts("#{length(rows)} exact manifest rows; two exact26-file artifact trees")

IO.puts(
  "Canonical Corpus AST/private equality, Adapters byte equality, sole Producer selection-coverage removal and descriptor shapes verified; generated disabled v2/service map retained; canonical manifest a7eb... distinct from native8de1"
)
