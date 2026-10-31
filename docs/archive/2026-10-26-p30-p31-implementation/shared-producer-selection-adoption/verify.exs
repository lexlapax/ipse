manifest_path = "docs/archive/2026-10-26-p30-p31-implementation/shared-producer-selection-adoption/manifest.json"
sha = fn path ->
  File.stream!(path, 65536, [])
  |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
  |> :crypto.hash_final()
  |> Base.encode16(case: :lower)
end
expected = "df7c466ab04b233f7939a112487a9e46c8645c93955bb038502c97760803030f"
^expected = sha.(manifest_path)
m = Jason.decode!(File.read!(manifest_path))
rows = m["source"] ++ m["logs"] ++ m["reports"] ++ m["runtime"] ++ [m["helper"]] ++ m["ancestors"] ++ Enum.flat_map(m["artifacts"], & &1["files"])
Enum.each(rows, fn row ->
  path = row["path"]
  case row["type"] do
    "symlink" ->
      stat = File.lstat!(path)
      true = stat.type == :symlink
      true = File.read_link!(path) == row["target"]
      true = stat.mode == row["mode"]
      true = stat.uid == row["uid"]
    _ ->
      true = File.stat!(path).size == row["bytes"]
      true = sha.(path) == row["sha256"]
  end
end)
IO.puts(Jason.encode!(%{manifest_sha256: expected, checked_rows: length(rows), source: length(m["source"]), logs: length(m["logs"]), reports: length(m["reports"]), artifact_files: Enum.sum(Enum.map(m["artifacts"], &length(&1["files"]))), runtime_regular: Enum.count(m["runtime"], &(&1["type"] == "regular")), symlinks: Enum.filter(m["runtime"], &(&1["type"] == "symlink")), status: "all exact rows verified"}, pretty: true))
