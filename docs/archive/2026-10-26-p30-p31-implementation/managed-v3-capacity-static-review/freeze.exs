root = File.cwd!()
out = Path.join(root, "_build/verification-preparation/managed-v3-capacity-20261027")
paths = [
  "dev/knowledge/managed_v3_capacity.exs",
  "lib/ipse/application.ex",
  "lib/ipse/json.ex",
  "lib/ipse/extension.ex",
  "lib/ipse/extension/collection.ex",
  "lib/ipse/extension/collection/normalizer_v3.ex",
  "lib/ipse/extension/collection/managed_pages.ex",
  "lib/ipse/extension/collection/managed_pages/planner.ex",
  "lib/ipse/extension/collection/migration.ex",
  "lib/ipse/extension/project_identity.ex",
  "lib/ipse/extension/project_identity/domain_auth.ex",
  "test/support/managed_policy.exs",
  "test/ipse/extension/collection_normalizer_v3_test.exs",
  "test/ipse/extension/collection_normalizer_v3_integration_test.exs",
  "extensions/knowledge/src/notes.ex",
  "extensions/knowledge/src/knowledge/records.ex",
  "extensions/knowledge/src/knowledge/contracts.ex",
  "dev/knowledge/storage_annual.exs",
  "dev/knowledge/storage_workload.ex"
]
hash = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
snapshots = Map.new(paths, &{&1, File.read!(Path.join(root, &1))})
Enum.each(snapshots, fn {path, bytes} ->
  {:ok, _} = Code.string_to_quoted(bytes, file: path)
  target = Path.join([out, "sources", path])
  File.mkdir_p!(Path.dirname(target))
  Enum.reduce(Path.split(Path.dirname(target)) |> Enum.drop(length(Path.split(out))), out, fn part, acc ->
    dir = Path.join(acc, part)
    File.chmod!(dir, 0o700)
    dir
  end)
  {:ok, io} = :file.open(String.to_charlist(target), [:write, :binary, :exclusive])
  :ok = :file.write(io, bytes)
  :ok = :file.sync(io)
  :ok = :file.close(io)
  File.chmod!(target, 0o600)
  true = File.read!(Path.join(root, path)) == bytes
end)
manifest = Map.new(snapshots, fn {path, bytes} -> {path, %{bytes: byte_size(bytes), sha256: hash.(bytes)}} end)
manifest = %{version: 1, kind: "static_source_preparation_only", native_executions: 0,
  publications: 0, runtime_qualified: false, sources: manifest,
  driver_sha256: manifest["dev/knowledge/managed_v3_capacity.exs"].sha256,
  review_sha256: hash.(File.read!(out <> "/REVIEW.md"))}
bytes = JSON.encode!(manifest) <> "\n"
File.write!(out <> "/manifest.json", bytes, [:exclusive])
File.chmod!(out <> "/manifest.json", 0o600)
IO.puts("static source freeze #{map_size(snapshots)} files; manifest SHA256 #{hash.(bytes)}; native executions 0")
