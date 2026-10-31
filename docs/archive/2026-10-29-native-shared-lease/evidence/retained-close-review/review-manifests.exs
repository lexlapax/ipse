root = "docs/archive/2026-10-29-native-shared-lease/evidence"
sha = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
for {dir, expected} <- [{"retained-close", "d7ce31a5eafa7e562564f1bad0a2009718f006cb359143bc307de89f5171ec85"}, {"retained-close-v4", "7a8ab790c6524db89fce2687662a9bb6a306b84e0a8c1d2e207b95a51ce274a0"}] do
  manifest = Path.join([root, dir, "manifest.sha256"])
  true = sha.(File.read!(manifest)) == expected
  rows = manifest |> File.read!() |> String.split("\n", trim: true)
  Enum.each(rows, fn row ->
    [digest, p] = String.split(row, "  ", parts: 2)
    true = sha.(File.read!(Path.join([root, dir, p]))) == digest
  end)
  IO.inspect(%{cohort: dir, entries: length(rows)}, label: "RETAINED_CLOSE_MANIFEST_OK")
end
