# Reuse the exact original synthetic setup and read simulator, changing only the
# retained artifact and the terminal observation needed for a repaired refusal.
original = File.read!("docs/archive/2026-10-26-p30-p31-implementation/shared-controller-read-review/review-skipped-immutables.exs")
prefix = original |> String.split("forged = args[") |> hd()
prefix = prefix
  |> String.replace("/tested-fixture-partial-hydration-final/ebin/*.beam", "/tested-job-prerequisite-repair-beams/*.beam")
  |> String.replace("other -> raise \"unexpected result \u0023{inspect(other)}\"", "other -> {:terminal, other, reads}")
{_, bindings} = Code.eval_string(prefix)
fetch = fn key -> Keyword.fetch!(bindings, key) end
args = fetch.(:args)
s = fetch.(:s)
walk = fetch.(:walk)
profile = fetch.(:profile)
forged = args["continuation"] |> Map.put("plan_sha256", s.plan_sha) |> Map.put("unit", s.immutable)
{:terminal, {:done, {:error, :generation_prerequisite_missing, %{}}}, reads} = walk.(walk, IpseKnowledge.Store.Collection.start(profile, :generation_job, %{args | "continuation" => forged}), [])
required = Enum.take(s.units, s.immutable) |> Enum.map(& &1.key)
true = Enum.any?(reads, &(&1["op"] == "value.stat" and &1["key"] == hd(required)))
IO.inspect(%{required_immutable_values: length(required), required_immutable_values_present: 0, refusal: :generation_prerequisite_missing, proposed_effects: 0, native_operations: 0, protected_publication_demonstrated: false}, label: "SKIPPED_IMMUTABLES_REPAIR_OK")
