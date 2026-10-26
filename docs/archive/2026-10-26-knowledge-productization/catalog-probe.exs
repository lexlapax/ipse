# Historical descriptor measurement, 2026-10-26; see index.md for scope and results.
# Run from the repository root with built Ipse/Jason code paths. No application starts.
Code.compiler_options(ignore_module_conflict: true)

source_paths =
  ["lib/ipse/json.ex", "lib/ipse/extension/catalog.ex", "extensions/bundled/memory.ex"] ++
    Enum.map(~w(evidence profiles corpus graph research), fn name ->
      "extensions/knowledge/src/#{name}.ex"
    end)

Enum.each(source_paths, &Code.require_file/1)

groups = %{
  "tools" => "invoke.tool",
  "commands" => "invoke.command",
  "services" => "invoke.service",
  "jobs" => "event.job"
}

packages = [
  {"notes", Ipse.Builtins.Memory.exports()},
  {"corpus", IpseKnowledge.Corpus.describe()["exports"]},
  {"graph", IpseKnowledge.Graph.describe()["exports"]},
  {"research", IpseKnowledge.Research.describe()["exports"]}
]

entries =
  for {name, exports} <- packages,
      {group, stage} <- Enum.sort(groups),
      descriptor <- Map.get(exports, group, []) do
    Map.merge(descriptor, %{
      "instance" => name,
      "stage" => stage,
      "name" => "ext__#{name}__#{descriptor["id"]}"
    })
  end

snapshot = %{"version" => 1, "entries" => entries}

validation =
  case Ipse.Extension.Catalog.validate_snapshot(snapshot) do
    :ok -> "ok"
    {:error, reason} -> Atom.to_string(reason)
  end

controls =
  Map.new(packages, fn {name, _} ->
    selected = Map.put(snapshot, "entries", Enum.filter(entries, &(&1["instance"] == name)))
    :ok = Ipse.Extension.Catalog.validate_snapshot(selected)
    {name, "ok"}
  end)

{revision, 0} = System.cmd("git", ["rev-parse", "HEAD"])

IO.puts(
  JSON.encode!(%{
    "revision" => String.trim(revision),
    "elixir" => System.version(),
    "otp" => List.to_string(:erlang.system_info(:otp_release)),
    "entries" => length(entries),
    "encoded_bytes" => byte_size(Jason.encode!(snapshot)),
    "count_by_instance" => Enum.frequencies_by(entries, & &1["instance"]),
    "validation" => validation,
    "individual_catalog_controls" => controls,
    "source_sha256" =>
      Map.new(source_paths, fn path ->
        {path, :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)}
      end)
  })
)
