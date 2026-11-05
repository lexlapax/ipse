defmodule CheckFrozenWordOracleV2 do
  @base "_build/verification/word-independent-oracle-20261105-01"
  @author @base <> "/author"
  @body "/w:document[1]/w:body[1]"
  @word "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  @parts ~w([Content_Types].xml _rels/.rels word/document.xml word/footnotes.xml word/comments.xml word/_rels/document.xml.rels)

  def run do
    old = pinned_json("expected-oracle.json", "890fc96281f60bb73eee4d6a71d044edc2250bf5a30b147e8d585b2eb5f858ed")
    oracle = pinned_json("expected-oracle-v2.json", "e2af13b29bacd36da26490053f1f2b86b6ab37f0c418d43f553537ceb7851a47")
    true = sha(File.read!(@author <> "/author_oracle_v2.exs")) == "37061b96da1ba15bb262a759928c1aa28bcfb937574eba2a358ad7f6add30cf8"
    {normalized_old, changes} = normalize_old_metadata(old)
    true = changes == 36 and normalized_old === oracle
    index = pinned_json("raw-package-index.json", "bc86e870b7f8de6151ae66936f0a6839e493b842518896517c97bb2a371d56ee")
    true = sha(File.read!(@author <> "/author_oracle.exs")) == "3f5f217db9db20556bc2dcaba098c29d1c402ba7e9590b31eadf2a202601e9ee"
    node_pin_bytes = File.read!(@base <> "/checker/v2-raw-node-preimages.sha256")
    true = sha(node_pin_bytes) == "0f1e25c54ac15b84c24d759128145da06d39732a1d970b355bdc4746d10f2d29"
    node_pins = node_pin_bytes |> String.split("\n", trim: true) |> Map.new(fn line ->
      [digest, path] = String.split(line, "  ", parts: 2)
      true = String.starts_with?(path, @author <> "/raw/") and String.ends_with?(path, ".nodes.json")
      {path, digest}
    end)
    true = map_size(node_pins) == 72
    pins = @base <> "/checker/input-pins.json" |> File.read!() |> :json.decode()
    ids = Enum.map(21..30, &"D0#{&1}") ++ ["V003-v1", "V003-v2"]
    for rows <- [pins["sources"], index["sources"], oracle["sources"]], do: true = Enum.map(rows, & &1["id"]) == ids
    true = oracle["source_count"] == 12 and oracle["historical_question_denominator"] == 62
    results = Enum.zip([pins["sources"], index["sources"], oracle["sources"]]) |> Enum.map(&check_source(&1, node_pins))
    actual_node_reads = Enum.flat_map(results, & &1["actual_raw_nodefiles_read"])
    true = length(actual_node_reads) == 72 and Map.new(actual_node_reads, &{&1["path"], &1["sha256"]}) == node_pins
    report = %{
      "scope" => "independent fixed-input source/oracle byte and coordinate check; no candidate or gold",
      "oracle_sha256" => sha(File.read!(@author <> "/expected-oracle-v2.json")),
      "retained_v1_oracle_sha256" => sha(File.read!(@author <> "/expected-oracle.json")),
      "strict_v1_to_v2_heading_style_string_to_null_changes" => changes,
      "all_other_v1_v2_data_strictly_identical" => true,
      "raw_node_preimages_sha256" => sha(node_pin_bytes), "actual_raw_nodefiles_read" => actual_node_reads,
      "sources" => results, "source_count" => length(results),
      "included_blocks" => Enum.sum(Enum.map(results, & &1["blocks"])),
      "included_text_nodes" => Enum.sum(Enum.map(results, & &1["included_text_nodes"])),
      "excluded_text_nodes" => Enum.sum(Enum.map(results, & &1["excluded_text_nodes"])),
      "style_string_nil_diagnostic" => Enum.sum(Enum.map(results, & &1["style_string_nil_diagnostic"])),
      "style_absence_null_count" => Enum.sum(Enum.map(results, & &1["style_absence_null_count"])),
      "candidate_evaluated" => false, "gold_read" => false, "historical_full_locators_unchanged_unverified" => 62,
      "revision_kind_id_product_fields" => "unrepresented/unverified", "installed_answer_qualification" => false
    }
    File.write!(@base <> "/checker/pure-check-receipt-v2.json", [:json.encode(report), "\n"], [:exclusive])
    IO.puts("CHECKED v2: 12 originals; 144 blocks; 204 text-node dispositions; exactly 36 metadata-only null fixes; 72 pinned raw nodefiles; no candidate qualification")
  end

  defp check_source({pin, indexed, expected}, node_pins) do
    id = pin["id"]
    true = pin["path"] == "dev/fixtures/knowledge-qualification/documents/sources/#{id}.docx"
    original = File.read!(pin["path"])
    true = byte_size(original) == pin["bytes"] and sha(original) == pin["sha256"]
    true = expected["original_sha256"] == pin["sha256"] and expected["original_bytes"] == pin["bytes"] and expected["original_path"] == pin["path"]
    true = Map.take(indexed, ~w(id path bytes sha256)) == pin
    true = expected["raw_parts"] == indexed["parts"]
    {:ok, extracted} = :zip.extract(original, [:memory])
    actual = Map.new(extracted, fn {name, bytes} -> {List.to_string(name), bytes} end)
    true = map_size(actual) == 6 and Enum.sort(Map.keys(actual)) == Enum.sort(@parts)
    {tree_entries, node_reads} = Enum.map_reduce(indexed["parts"], [], fn part, reads ->
      name = part["part"]
      raw = Map.fetch!(actual, name)
      true = byte_size(raw) == part["bytes"] and sha(raw) == part["sha256"]
      true = File.read!(part["raw_path"]) == raw
      true = String.valid?(raw) and byte_size(raw) < 65536
      false = String.contains?(raw, ["<!DOCTYPE", "<!ENTITY"])
      node_bytes = File.read!(part["nodes_path"])
      node_digest = sha(node_bytes)
      true = Map.fetch!(node_pins, part["nodes_path"]) == node_digest
      tree = :json.decode(node_bytes)
      # These exact frozen originals have plain literal character content: no entities/CDATA.
      literal = Regex.scan(~r/<w:(t|delText)(?:\s[^>]*)?>([^<]*)<\/w:\1>/u, raw) |> Enum.map(&List.last/1)
      false = Enum.any?(literal, &String.contains?(&1, "&"))
      decoded = flatten(tree) |> Enum.filter(&Map.has_key?(&1, "text")) |> Enum.map(& &1["text"])
      true = literal == decoded
      {{name, tree}, reads ++ [%{"path" => part["nodes_path"], "sha256" => node_digest}]}
    end)
    trees = Map.new(tree_entries)
    true = Enum.all?(~w(word/document.xml word/footnotes.xml word/comments.xml), fn part ->
      attrs = attributes(trees[part]); attrs["xmlns:w"] == @word
    end)
    document_nodes = flatten(trees["word/document.xml"])
    false = Enum.any?(document_nodes, &(&1["name"] in ~w(w:rPr w:vanish w:webHidden w:specVanish w:rStyle w:tab w:br w:cr w:numPr w:moveTo w:moveFrom)))
    all_raw_text = Enum.flat_map(trees, fn {part, tree} ->
      flatten(tree) |> Enum.filter(&Map.has_key?(&1, "text")) |> Enum.map(&{part, &1["node"], &1["text"]})
    end)
    included = Enum.flat_map(expected["blocks"], fn block -> Enum.map(block["fragments"], &{block["part"], &1["node"], &1["text"]}) end)
    excluded = Enum.map(expected["excluded_fragments"], &{&1["part"], &1["node"], &1["text"]})
    true = length(all_raw_text) == 17 and length(included) == 14 and length(excluded) == 3
    true = length(Enum.uniq(included ++ excluded)) == 17 and Enum.sort(included ++ excluded) == Enum.sort(all_raw_text)
    true = length(expected["blocks"]) == 12
    {_, _, crosswalk} = Enum.reduce(expected["blocks"], {0, %{}, []}, fn block, {offset, stories, rows} ->
      paragraphs = flatten(trees[block["part"]]) |> Enum.filter(&(&1["name"] == "w:p")) |> Enum.map(& &1["node"])
      ordinal = Enum.find_index(paragraphs, &(&1 == block["paragraph_node"])) + 1
      true = block["locator_basis"]["part_paragraph"] == ordinal
      true = Enum.map_join(block["fragments"], & &1["text"]) == block["text"]
      Enum.reduce(block["fragments"], 0, fn fragment, local ->
        finish = local + byte_size(fragment["text"])
        true = fragment["block_span"] == [local, finish]
        true = String.starts_with?(fragment["node"], block["paragraph_node"] <> "/")
        finish
      end)
      finish = offset + byte_size(block["text"])
      true = block["document_span"] == [offset, finish]
      story_offset = Map.get(stories, block["story"], 0)
      true = block["story_span"] == [story_offset, story_offset + byte_size(block["text"])]
      basis = block["locator_basis"]
      if Map.has_key?(basis, "table") do
        [_, t, r, c, p] = Regex.run(~r{/w:tbl\[(\d+)\]/w:tr\[(\d+)\]/w:tc\[(\d+)\]/w:p\[(\d+)\]$}, block["paragraph_node"])
        true = Enum.map([t, r, c, p], &String.to_integer/1) == Enum.map(~w(table row cell cell_paragraph), &basis[&1])
      end
      if Map.has_key?(basis, "body_paragraph"), do: true = block["paragraph_node"] == @body <> "/w:p[#{basis["body_paragraph"]}]"
      row = %{"part" => block["part"], "node" => block["paragraph_node"], "part_paragraph" => ordinal, "locator_basis" => basis}
      {finish + 1, Map.put(stories, block["story"], story_offset + byte_size(block["text"]) + 1), rows ++ [row]}
    end)
    text = Enum.map_join(expected["blocks"], "\n", & &1["text"])
    true = expected["text"] == text and expected["text_bytes"] == byte_size(text) and expected["text_sha256"] == sha(text)
    for {name, value} <- [{"w:del", "11"}, {"w:ins", "12"}] do
      [revision] = Enum.filter(document_nodes, &(&1["name"] == name))
      true = attributes(revision)["w:id"] == value
    end
    true = excluded |> Enum.count(fn {part, path, _} -> part == "word/document.xml" and String.contains?(path, "/w:del[1]/") end) == 1
    for {position, type, note_id} <- [{1, "separator", "-1"}, {2, "continuationSeparator", "0"}] do
      node = Enum.find(flatten(trees["word/footnotes.xml"]), &(&1["node"] == "/w:footnotes[1]/w:footnote[#{position}]"))
      true = attributes(node)["w:type"] == type and attributes(node)["w:id"] == note_id
    end
    diagnostic = Enum.count(expected["blocks"], &(&1["locator_basis"]["heading_style"] == "nil"))
    null_styles = Enum.count(expected["blocks"], fn block ->
      Map.has_key?(block["locator_basis"], "heading_style") and block["locator_basis"]["heading_style"] === :null
    end)
    true = diagnostic == 0 and null_styles == 3
    [heading] = Enum.filter(expected["blocks"], &(&1["locator_basis"]["heading_style"] == "Heading1"))
    true = heading["paragraph_node"] == @body <> "/w:p[2]"
    %{"id" => id, "original_sha256" => pin["sha256"], "blocks" => 12, "included_text_nodes" => 14, "excluded_text_nodes" => 3,
      "source_text_bytes" => byte_size(text), "source_text_sha256" => sha(text), "independent_raw_paragraph_crosswalk" => crosswalk,
      "style_string_nil_diagnostic" => diagnostic, "style_absence_null_count" => null_styles, "actual_raw_nodefiles_read" => node_reads}
  end

  # Correct only the 36 known absent-style metadata fields; strict whole-value
  # equality above rejects every other changed value, key, row, type or order.
  defp normalize_old_metadata(old) do
    {sources, count} = Enum.map_reduce(old["sources"], 0, fn source, total ->
      {blocks, changed} = Enum.map_reduce(source["blocks"], 0, fn block, subtotal ->
        basis = block["locator_basis"]
        if basis["heading_style"] === "nil" do
          true = block["part"] == "word/document.xml" and basis["body_paragraph"] in [1, 3, 4]
          {Map.put(block, "locator_basis", Map.put(basis, "heading_style", :null)), subtotal + 1}
        else
          {block, subtotal}
        end
      end)
      true = changed == 3
      {Map.put(source, "blocks", blocks), total + changed}
    end)
    {Map.put(old, "sources", sources), count}
  end

  defp pinned_json(name, digest) do
    bytes = File.read!(@author <> "/" <> name)
    true = sha(bytes) == digest
    :json.decode(bytes)
  end
  defp flatten(node), do: [node | Enum.flat_map(Map.get(node, "children", []), &flatten/1)]
  defp attributes(node), do: Map.new(Map.get(node, "attributes", []), &{&1["name"], &1["value"]})
  defp sha(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end

CheckFrozenWordOracleV2.run()
