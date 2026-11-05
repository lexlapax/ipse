defmodule CheckFrozenWordOracle do
  @base "_build/verification/word-independent-oracle-20261105-01"
  @author @base <> "/author"
  @body "/w:document[1]/w:body[1]"
  @word "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  @parts ~w([Content_Types].xml _rels/.rels word/document.xml word/footnotes.xml word/comments.xml word/_rels/document.xml.rels)

  def run do
    oracle = pinned_json("expected-oracle.json", "890fc96281f60bb73eee4d6a71d044edc2250bf5a30b147e8d585b2eb5f858ed")
    index = pinned_json("raw-package-index.json", "bc86e870b7f8de6151ae66936f0a6839e493b842518896517c97bb2a371d56ee")
    true = sha(File.read!(@author <> "/author_oracle.exs")) == "3f5f217db9db20556bc2dcaba098c29d1c402ba7e9590b31eadf2a202601e9ee"
    pins = @base <> "/checker/input-pins.json" |> File.read!() |> :json.decode()
    ids = Enum.map(21..30, &"D0#{&1}") ++ ["V003-v1", "V003-v2"]
    for rows <- [pins["sources"], index["sources"], oracle["sources"]], do: true = Enum.map(rows, & &1["id"]) == ids
    true = oracle["source_count"] == 12 and oracle["historical_question_denominator"] == 62
    results = Enum.zip([pins["sources"], index["sources"], oracle["sources"]]) |> Enum.map(&check_source/1)
    report = %{
      "scope" => "independent fixed-input source/oracle byte and coordinate check; no candidate or gold",
      "oracle_sha256" => sha(File.read!(@author <> "/expected-oracle.json")),
      "sources" => results, "source_count" => length(results),
      "included_blocks" => Enum.sum(Enum.map(results, & &1["blocks"])),
      "included_text_nodes" => Enum.sum(Enum.map(results, & &1["included_text_nodes"])),
      "excluded_text_nodes" => Enum.sum(Enum.map(results, & &1["excluded_text_nodes"])),
      "style_string_nil_diagnostic" => Enum.sum(Enum.map(results, & &1["style_string_nil_diagnostic"])),
      "candidate_evaluated" => false, "gold_read" => false, "historical_full_locators_unchanged_unverified" => 62,
      "revision_kind_id_product_fields" => "unrepresented/unverified", "installed_answer_qualification" => false
    }
    File.write!(@base <> "/checker/pure-check-receipt.json", [:json.encode(report), "\n"], [:exclusive])
    IO.puts("CHECKED 12 original archives; 144 blocks; 204 text-node dispositions; style string-nil diagnostic 36; no candidate qualification")
  end

  defp check_source({pin, indexed, expected}) do
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
    trees = Map.new(indexed["parts"], fn part ->
      name = part["part"]
      raw = Map.fetch!(actual, name)
      true = byte_size(raw) == part["bytes"] and sha(raw) == part["sha256"]
      true = File.read!(part["raw_path"]) == raw
      true = String.valid?(raw) and byte_size(raw) < 65536
      false = String.contains?(raw, ["<!DOCTYPE", "<!ENTITY"])
      tree = part["nodes_path"] |> File.read!() |> :json.decode()
      # These exact frozen originals have plain literal character content: no entities/CDATA.
      literal = Regex.scan(~r/<w:(t|delText)(?:\s[^>]*)?>([^<]*)<\/w:\1>/u, raw) |> Enum.map(&List.last/1)
      false = Enum.any?(literal, &String.contains?(&1, "&"))
      decoded = flatten(tree) |> Enum.filter(&Map.has_key?(&1, "text")) |> Enum.map(& &1["text"])
      true = literal == decoded
      {name, tree}
    end)
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
    true = diagnostic == 3
    %{"id" => id, "original_sha256" => pin["sha256"], "blocks" => 12, "included_text_nodes" => 14, "excluded_text_nodes" => 3,
      "source_text_bytes" => byte_size(text), "source_text_sha256" => sha(text), "independent_raw_paragraph_crosswalk" => crosswalk,
      "style_string_nil_diagnostic" => diagnostic}
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

CheckFrozenWordOracle.run()
