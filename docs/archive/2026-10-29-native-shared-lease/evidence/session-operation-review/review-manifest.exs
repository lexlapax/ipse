root = "docs/archive/2026-10-29-native-shared-lease/evidence/session-operation-barrier"
graph = "_build/session-operation-barrier-sol-20261029/lib"
sha = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
parse = fn path ->
  path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(fn row ->
    [hash, file] = String.split(row, "  ", parts: 2)
    {file, hash}
  end)
end
true = sha.(File.read!(root <> "/manifest.sha256")) == "d96e5fdabb6cc67bd74d94fc2ef405941844f1a031bef43084a733fa090efaa2"
entries = parse.(root <> "/manifest.sha256")
Enum.each(entries, fn {path, hash} -> true = sha.(File.read!(Path.join(root, path))) == hash end)
rows = parse.(root <> "/runtime.sha256")
Enum.each(rows, fn {path, hash} -> true = sha.(File.read!(Path.join(graph, path))) == hash end)
{:ok, sources} = :erl_tar.extract(String.to_charlist(root <> "/source.tar"), [:memory])
true = length(sources) == 4
helper_sha = sha.(File.read!(Path.join(graph, "ipse/priv/ipse-runner")))
true = helper_sha == "a64c58bb32864d217501f750c0e5fa25abf4562bfda53fab6c4f2573115f4995"
for file <- ["Elixir.Ipse.Session.Lock.beam", "Elixir.Ipse.Runner.beam"] do
  true = File.read!(Path.join(graph, "ipse/ebin/" <> file)) == File.read!("_build/session-share-candidate-v4-sol-20261029/lib/ipse/ebin/" <> file)
end
IO.inspect(%{manifest_entries: length(entries), source_files: length(sources), runtime_files: length(rows), helper_unchanged: true, lock_and_runner_inherited: true}, label: "SESSION_OPERATION_MANIFEST_OK")
