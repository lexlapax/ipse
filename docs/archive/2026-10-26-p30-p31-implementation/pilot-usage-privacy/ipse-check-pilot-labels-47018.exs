Path.wildcard("_build/literal-v4-ab-current2-sol-20261029/lib/*/ebin") |> Enum.each(&Code.prepend_path/1)
path = "docs/archive/2026-10-26-p30-p31-implementation/pilot-usage-privacy/development-labels.json"
data = Jason.decode!(File.read!(path))
rows = data["rows"]
candidates = Enum.flat_map(rows, & &1["candidates"])
omitted = Enum.filter(rows, &(&1["candidates"] == []))
key = fn
  nil -> "null"
  value -> to_string(value)
end
frequency = fn values, field, keys ->
  observed = Enum.frequencies_by(values, &key.(&1[field]))
  Map.new(keys, &{&1, observed[&1] || 0})
end
counts = %{
  "rows" => length(rows), "candidates" => length(candidates),
  "opportunity" => frequency.(rows, "opportunity", ~w(durable temporal none uncertain)),
  "source_entailment" => frequency.(candidates, "source_entailment", ~w(supported overclaim uncertain)),
  "useful" => frequency.(candidates, "useful", ~w(true false null)),
  "duplicate_of_prior_same_session" => frequency.(candidates, "duplicate_of_prior_same_session", ~w(true false)),
  "category_appropriate" => frequency.(candidates, "category_appropriate", ~w(true false null)),
  "intake_relation" => frequency.(candidates, "intake_relation", ~w(new replacement duplicate uncertain)),
  "row_reason_codes" => Enum.frequencies(Enum.flat_map(rows, & &1["reason_codes"])),
  "candidate_reason_codes" => Enum.frequencies(Enum.flat_map(candidates, & &1["reason_codes"])),
  "omitted_rows" => length(omitted),
  "omitted_opportunity" => frequency.(omitted, "opportunity", ~w(durable temporal none uncertain))
}
true = counts === data["aggregate_counts"]
IO.puts("PILOT_LABEL_COUNTS_RECOMPUTED_OK rows=57 candidates=39 useful=34 duplicate=3 uncertain=2")
