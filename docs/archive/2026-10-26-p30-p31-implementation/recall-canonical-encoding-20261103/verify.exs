Code.prepend_paths(Path.wildcard("/home/lexlapax/projects/lexlapax/ipse/_build/test/lib/*/ebin"))
{:ok, _} = Application.ensure_all_started(:crypto)
archive = "/home/lexlapax/projects/lexlapax/ipse/docs/archive/2026-10-26-p30-p31-implementation"
roots = [
 {"/dev/shm/ipse-source-phase-controls-f44-20261103-01/single/ipse-native-recall-4b7ee1d5ffe3255896fde1cc3100a8fe", archive <> "/source-owner-phase-20261103/single/phase-before.json"},
 {"/dev/shm/ipse-native-recall-fa547f3ae898e4bd50df06a2afe015dd", archive <> "/egress-diagnostic-dcbb-20261103/strict-source-before.json"}
]
sources = for {root, manifest} <- roots, row <- Jason.decode!(File.read!(manifest)) do
 path = Path.join([root, "home", "sessions", row["id"] <> ".jsonl"])
 bytes = File.read!(path)
 unless Ipse.JSON.sha256(bytes) == row["journal_sha256"], do: raise("source hash mismatch")
 {path, row["journal_sha256"], bytes |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)}
end
scalars = [nil, true, false, 0, -1, 9_007_199_254_740_991, 0.0, -0.0, 1.0e-100, 1.0e100, "", "é 🐚", "\u0000\n\r\t\b\f\"\\/", "\u2028\u2029", :ordinary, :null]
values = for {a, i} <- Enum.with_index(scalars), {b, j} <- Enum.with_index(scalars), do: [%{"z" => [a, b], "a" => %{nested: [b, %{"é" => a}], zero: 0}, "i" => i, "j" => j}]
values = values ++ [[%{"alpha" => 2, alpha: 1}], [%{}], [[]], []]
invalid = [[{:not, :json}], [<<255>>], [%{{:bad, :key} => 1}], [self()], [make_ref()]]
classify = fn value ->
 try do
  {:ok, Ipse.JSON.digest(value)}
 rescue
  e -> {:error, e.__struct__}
 end
end
before = Enum.map(values ++ invalid, classify)
history_before = for {_, _, events} <- sources, do: {Ipse.JSON.digest(events), Enum.map(events, &Ipse.JSON.digest([&1]))}
Code.compiler_options(ignore_module_conflict: true, warnings_as_errors: true)
Code.compile_file("/dev/shm/ipse-populated-cache-phase-a0XYcKFw/json-candidate.ex")
unless before == Enum.map(values ++ invalid, classify), do: raise("canonical digest/error contract changed")
history_after = for {_, _, events} <- sources, do: {Ipse.JSON.digest(events), Enum.map(events, &Ipse.JSON.digest([&1]))}
unless history_before == history_after, do: raise("historical event digest changed")
for {path, sha, _} <- sources, do: if(Ipse.JSON.sha256(File.read!(path)) != sha, do: raise("source changed"))
IO.puts(inspect(%{corpus_cases: length(values), invalid_cases: length(invalid), retained_sources: length(sources), retained_events: Enum.sum(Enum.map(sources, &(length(elem(&1, 2))))), historical_digest_manifest: Ipse.JSON.digest([history_after |> Enum.map(fn {history, events} -> [history, events] end)])}))
ExUnit.start()
Code.require_file("/home/lexlapax/projects/lexlapax/ipse/test/ipse/json_test.exs")
IO.puts("CANONICAL_DIGEST_EQUIVALENCE_PASSED")
