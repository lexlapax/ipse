source = File.read!("test/extensions/knowledge/producer_progress_test.exs")
needle = "    assert length(full.vectors) == 11 and Enum.map(full.pages, & &1[\"ordinal\"]) == [0, 1]"
1 = length(:binary.matches(source, needle))
extra = """
    baseline = IpseKnowledge.Store.Collection.GenerationBaseline
    current = IpseKnowledge.Store.Collection.Generation
    Enum.with_index(full.pages) |> Enum.each(fn {page, ordinal} ->
      vectors = Enum.slice(full.vectors, ordinal * 8, 8)
      old = apply(baseline, :vector_page, [\"notes\", 0, full.bundles, vectors, @selection, ordinal * 8])
      new = apply(current, :vector_page, [\"notes\", 0, full.bundles, vectors, @selection, ordinal * 8])
      assert old === new and elem(new, 1).value === page
    end)
    for values <- [full.pages, Enum.reverse(full.pages), [hd(full.pages)]] do
      old = apply(baseline, :unpack_vector_pages, [\"notes\", 0, full.bundles, values, @selection])
      new = apply(current, :unpack_vector_pages, [\"notes\", 0, full.bundles, values, @selection])
      assert old === new
    end
    IO.puts(\"V4_CODEC_BASELINE_COMPARE identical=true pages=2 negative_shapes=2\")
"""
File.write!("/tmp/ipse-v4-codec-compare-test.exs", String.replace(source, needle, extra <> "\n" <> needle))
runner = File.read!("/tmp/ipse-v4-public-run.exs")
needle = "Code.require_file(\"test/extensions/knowledge/producer_progress_test.exs\")"
replacement = """
baseline = File.read!(\"docs/archive/2026-10-26-p30-p31-implementation/shared-producer-v4-pinned-read/source/extensions/knowledge/src/store/collection/generation.ex\")
baseline = String.replace(baseline, \"defmodule IpseKnowledge.Store.Collection.Generation do\", \"defmodule IpseKnowledge.Store.Collection.GenerationBaseline do\", global: false)
Code.compile_string(baseline)
Code.require_file(\"/tmp/ipse-v4-codec-compare-test.exs\")
"""
1 = length(:binary.matches(runner, needle))
File.write!("/tmp/ipse-v4-codec-compare-run.exs", String.replace(runner, needle, replacement))
