source = File.read!("test/extensions/knowledge/producer_progress_test.exs")
needle = "    assert length(full.vectors) == 11 and Enum.map(full.pages, & &1[\"ordinal\"]) == [0, 1]"
1 = length(:binary.matches(source, needle))
extra = """
    baseline = IpseKnowledge.EvidenceBaseline
    src = hd(full.bundles)[\"source\"]
    citation = hd(hd(facts(full.bundles))[\"facts\"])[\"citations\"] |> hd()
    cases = [citation, Map.put(citation, \"quote\", \"wrong\"), Map.put(citation, \"source_key\", String.duplicate(\"a\", 64)), Map.put(citation, \"end_byte\", citation[\"end_byte\"] + 4096), Map.put(citation, \"extra\", true)]
    Enum.each(cases, fn c -> assert apply(baseline, :valid_span?, [src, c]) === Evidence.valid_span?(src, c) end)
    assert Evidence.valid_spans?(src, [citation, citation])
    refute Evidence.valid_spans?(src, cases)
    IO.puts(\"V4_BATCH_SPANS_BASELINE_COMPARE valid_and_four_invalid=true\")
"""
File.write!("/tmp/ipse-v4-span-compare-test.exs", String.replace(source, needle, extra <> "\n" <> needle))
runner = File.read!("/tmp/ipse-v4-public-run.exs")
needle = "Code.require_file(\"test/extensions/knowledge/producer_progress_test.exs\")"
replacement = """
baseline = File.read!(\"docs/archive/2026-10-26-p30-p31-implementation/shared-producer-v4-pinned-read/source/extensions/knowledge/src/evidence.ex\")
baseline = String.replace(baseline, \"defmodule IpseKnowledge.Evidence do\", \"defmodule IpseKnowledge.EvidenceBaseline do\", global: false)
Code.compile_string(baseline)
Code.require_file(\"/tmp/ipse-v4-span-compare-test.exs\")
"""
1 = length(:binary.matches(runner, needle))
File.write!("/tmp/ipse-v4-span-compare-run.exs", String.replace(runner, needle, replacement))
