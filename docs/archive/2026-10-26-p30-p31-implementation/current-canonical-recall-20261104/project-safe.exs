root = "/dev/shm/ipse-recall33-current-frozen-20261104-01/tmp/ipse-native-recall-3cf874f622daf58b2342974e47070911"
runtime = "/home/lexlapax/projects/lexlapax/ipse/_build/verification/regression-groups-frozen-20261104-02/serial/source"
hash = fn path -> :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower) end
sessions = for path <- Path.wildcard(Path.join(root, "home/sessions/*.jsonl")) do
  rows = path |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
  %{ "journal_sha256" => hash.(path), "counts" => Enum.frequencies_by(rows, & &1["type"]),
     "assertions" => Enum.count(rows, &(&1["type"] == "operator_assertion")),
     "successful_gets" => Enum.count(rows, &(&1["type"] == "extension_action_result" and get_in(&1,["request","op"]) == "collection.call" and get_in(&1,["request","request","op"]) == "get" and get_in(&1,["outcome","status"]) == "ok")) }
end
catalog_path = Path.join(runtime, "priv/extension-bundles/catalog.json")
catalog = Jason.decode!(File.read!(catalog_path))
value = %{"kind" => "fresh_current_canonical_first33_positive", "sessions" => sessions,
 "seed_assertions" => Enum.sum(Enum.map(sessions, & &1["assertions"])),
 "catalog_sha256" => hash.(catalog_path), "bundles" => Enum.map(catalog["artifacts"], &Map.take(&1, ~w(id manifest_sha256 path))),
 "native_helper_sha256" => hash.(Path.join(runtime,"priv/ipse-runner")),
 "app_spec_sha256" => hash.(Path.join(runtime,"_build/test/lib/ipse/ebin/ipse.app")),
 "canonical_helper_sha256" => hash.(Path.join(runtime,"test/support/native_note_recall_many.exs")),
 "selected_case" => "first33_positive", "sparse_or_reappear_run" => false,
 "canonical_assertions" => ["33 natively reviewed short statements", "all33 full marker texts in actual provider request", "33 successful get results", "coverage complete and included33", "successful provider completion", "strict Saved restore", "confirmed consumer close"],
 "no_claims" => ["retained2000 qualification", "sparse/reappearing source case", "arbitrary note sizes", "installed package or human interaction", "provider request retained on disk"]}
33 = value["seed_assertions"]
File.write!(Path.join(__DIR__,"safe-projection.json"), Jason.encode!(value,pretty: true)<>"\n", [:exclusive])
