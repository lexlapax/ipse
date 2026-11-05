defmodule WordIndependentExpected do
  @base "_build/verification/word-independent-oracle-20261105-01/author"
  @body "/w:document[1]/w:body[1]"
  @foot "Footnote: values are local pilot observations, not population estimates."
  @comment "Comment: this reviewer has not approved publication."

  # These literal texts and node assignments were manually authored from the raw XML.
  # This script computes byte spans and checks the assignments, never extracts answers.
  def rows do
    [
      ["D021", "Glacier field protocol", "Sample chain", "Team Moraine seals each ice core with a tamper-evident cobalt band.", "A broken band triggers quarantine; it does not establish who handled the core.", "Storage temperature", "−18 °C", "handover room 23", "handover room 30"],
      ["D022", "Chamber choir score note", "Breath marks", "The alto section breathes after the word lumière in bar 42.", "The tenor pencilled comma in bar 40 is a rehearsal suggestion, not the conductor's mark.", "Concert pitch", "A = 442 Hz", "handover room 24", "handover room 31"],
      ["D023", "Harbor sensor memo", "Calibration check", "Buoy Sølv reports salinity only after a two-point calibration.", "A flat reading may indicate a fouled probe; the cause remains uncertain until inspection.", "Calibration lot", "S-031", "handover room 25", "handover room 32"],
      ["D024", "School garden minutes", "Compost rotation", "Bed Élan receives leaf compost in October and rests through November.", "The committee cancelled the proposed manure delivery; no manure was applied under this plan.", "Leaf compost", "0.7 m³", "handover room 26", "handover room 33"],
      ["D025", "Canoe repair card", "Seam inspection", "The stern seam is inspected after every fifth outing.", "A superficial paint scratch alone does not authorize replacement of the hull.", "Sealant batch", "N-55", "handover room 27", "handover room 34"],
      ["D026", "Sculpture loan schedule", "Packing direction", "The basalt owl travels upright in a foam-lined crate.", "The sketch showing a horizontal orientation is superseded by the signed packing direction.", "Crate mass", "86 kg", "handover room 28", "handover room 35"],
      ["D027", "Rural mesh field book", "Relay schedule", "Relay Cedar sleeps for 12 minutes between status broadcasts.", "A silent relay is not necessarily offline; its scheduled sleep must be considered.", "Antenna height", "6.2 m", "handover room 29", "handover room 36"],
      ["D028", "Museum tactile guide", "Replica handling", "The bronze bell replica may be handled with clean dry hands.", "The original bell remains behind glass; replica handling permission does not cover it.", "Replica diameter", "18 cm", "handover room 30", "handover room 37"],
      ["D029", "Cooperative bakery log", "Starter rotation", "Starter Brisa is refreshed at a ratio of 1:3:3 by mass.", "A sour aroma alone is not recorded as spoilage; a pink surface requires disposal.", "Bench rest", "45 min", "handover room 31", "handover room 38"],
      ["D030", "Cave mapping fieldbook", "Survey tie", "Traverse Q connects to the entrance datum by station Q0.", "The dashed branch beyond Q7 is conjectural and must not be reported as a surveyed passage.", "Instrument precision", "±0.3°", "handover room 32", "handover room 39"],
      ["V003-v1", "Apiary inspection threshold", "Limits", "Effective 2026-03-01, Intervention threshold is 9 mites.", "This edition remains valid until a signed replacement takes effect.", "Intervention threshold", "9 mites", "east desk", "west desk"],
      ["V003-v2", "Apiary inspection threshold", "Limits", "Effective 2026-09-01, Intervention threshold is 6 mites.", "This signed replacement supersedes v1 from its effective date; earlier events retain the old rule.", "Intervention threshold", "6 mites", "east desk", "west desk"]
    ]
  end

  def run do
    false = File.exists?(Path.join(@base, "expected-oracle-v2.json"))
    raw = @base |> Path.join("raw-package-index.json") |> File.read!() |> :json.decode()
    expected = Enum.zip(rows(), raw["sources"]) |> Enum.map(fn {row, pin} -> source(row, pin) end)
    result = %{"schema" => "word-independent-logical-oracle-v1", "recipe" => "manual-raw-ooxml-visible-revisions-1", "cohort" => "exposed-historical-remediation", "source_count" => 12, "historical_question_denominator" => 62,
      "selected_revision_policy" => "include w:ins; exclude w:del/w:delText", "span_unit" => "UTF-8 bytes, zero-based half-open",
      "serialization" => "body blocks in raw order, then referenced footnote story, then comment story; newline between blocks, no trailing newline; no synthetic markers or separators",
      "product_locator_mapping" => "pending independent checker; locator_basis is raw author evidence, not asserted product fields", "sources" => expected}
    File.write!(Path.join(@base, "expected-oracle-v2.json"), [:json.encode(result), "\n"], [:exclusive])
    IO.puts("Authored #{length(expected)} sources; #{Enum.sum(Enum.map(expected, &length(&1["blocks"])))} blocks; 168 included text nodes; 36 excluded text nodes; complete 204-node accounting")
  end

  defp source([id, title, heading, positive, limit, label, value, deleted, inserted], pin) do
    true = id == pin["id"]
    ordinary = [title, heading, positive, limit] |> Enum.with_index(1) |> Enum.map(fn {txt, i} ->
      block("body", @body <> "/w:p[#{i}]", %{"body_paragraph" => i, "part_paragraph" => i, "heading_style" => if(i == 2, do: "Heading1", else: :null)}, [fragment("/w:r[1]/w:t[1]/text()[1]", txt, "ordinary body text")])
    end)
    cells = [{1, 1, "Measure", 5}, {1, 2, "Value", 6}, {2, 1, label, 7}, {2, 2, value, 8}] |> Enum.map(fn {r, c, txt, p} ->
      block("body", @body <> "/w:tbl[1]/w:tr[#{r}]/w:tc[#{c}]/w:p[1]", %{"table" => 1, "row" => r, "cell" => c, "cell_paragraph" => 1, "part_paragraph" => p}, [fragment("/w:r[1]/w:t[1]/text()[1]", txt, "ordinary table-cell text")])
    end)
    revision = block("body", @body <> "/w:p[5]", %{"body_paragraph" => 5, "part_paragraph" => 9}, [fragment("/w:r[1]/w:t[1]/text()[1]", "Current handover: ", "ordinary body prefix; retain its trailing space"), fragment("/w:ins[1]/w:r[1]/w:t[1]/text()[1]", inserted, "insertion included under selected final-text revision policy")])
    annotation = block("body", @body <> "/w:p[6]", %{"body_paragraph" => 6, "part_paragraph" => 10}, [fragment("/w:r[1]/w:t[1]/text()[1]", "Annotation anchor", "ordinary annotation anchor text"), fragment("/w:r[3]/w:t[1]/text()[1]", "; review marker", "ordinary text inside comment range; markup adds no characters")])
    foot = block("footnote:2", "/w:footnotes[1]/w:footnote[3]/w:p[1]", %{"note_id" => "2", "note_paragraph" => 1, "part_paragraph" => 3}, [fragment("/w:r[1]/w:t[1]/text()[1]", @foot, "referenced ordinary footnote; include its content as a separate story")], "word/footnotes.xml")
    comment = block("comment:3", "/w:comments[1]/w:comment[1]/w:p[1]", %{"comment_id" => "3", "comment_paragraph" => 1, "part_paragraph" => 1}, [fragment("/w:r[1]/w:t[1]/text()[1]", @comment, "referenced comment evidence; include as separate comment story, not body assertion")], "word/comments.xml")
    blocks = ordinary ++ cells ++ [revision, annotation, foot, comment]
    {blocks, _} = Enum.map_reduce(blocks, 0, fn b, offset ->
      size = byte_size(b["text"])
      {Map.put(b, "document_span", [offset, offset + size]), offset + size + 1}
    end)
    {blocks, _} = Enum.map_reduce(blocks, %{}, fn b, offsets ->
      offset = Map.get(offsets, b["story"], 0)
      size = byte_size(b["text"])
      {Map.put(b, "story_span", [offset, offset + size]), Map.put(offsets, b["story"], offset + size + 1)}
    end)
    exclusions = [
      %{"part" => "word/document.xml", "node" => @body <> "/w:p[5]/w:del[1]/w:r[1]/w:delText[1]/text()[1]", "text" => deleted, "reason" => "tracked deletion excluded by selected final-text revision policy", "raw_revision_id" => "11"},
      %{"part" => "word/footnotes.xml", "node" => "/w:footnotes[1]/w:footnote[1]/w:p[1]/w:r[1]/w:t[1]/text()[1]", "text" => "—", "reason" => "w:type=separator, w:id=-1 is footnote layout control, not ordinary note evidence"},
      %{"part" => "word/footnotes.xml", "node" => "/w:footnotes[1]/w:footnote[2]/w:p[1]/w:r[1]/w:t[1]/text()[1]", "text" => "—", "reason" => "w:type=continuationSeparator, w:id=0 is footnote layout control, not ordinary note evidence"}
    ]
    all_expected = Enum.flat_map(blocks, fn b -> Enum.map(b["fragments"], &{b["part"], &1["node"], &1["text"]}) end) ++ Enum.map(exclusions, &{&1["part"], &1["node"], &1["text"]})
    all_raw = Enum.flat_map(pin["parts"], fn part ->
      tree = part["nodes_path"] |> File.read!() |> :json.decode()
      Enum.map(raw_text(tree), &{part["part"], &1["node"], &1["text"]})
    end)
    true = length(all_expected) == 17
    true = Enum.sort(all_expected) == Enum.sort(all_raw)
    text = Enum.map_join(blocks, "\n", & &1["text"])
    %{"id" => id, "original_path" => pin["path"], "original_bytes" => pin["bytes"], "original_sha256" => pin["sha256"], "raw_parts" => pin["parts"], "text" => text, "text_bytes" => byte_size(text), "text_sha256" => :crypto.hash(:sha256, text) |> Base.encode16(case: :lower), "blocks" => blocks, "excluded_fragments" => exclusions,
      "raw_revision_metadata" => [%{"node" => @body <> "/w:p[5]/w:del[1]", "kind" => "deletion", "w:id" => "11", "w:author" => "Editor", "w:date" => "2026-09-02T00:00:00Z"}, %{"node" => @body <> "/w:p[5]/w:ins[1]", "kind" => "insertion", "w:id" => "12", "w:author" => "Editor", "w:date" => "2026-09-03T00:00:00Z"}],
      "nontext_nodes" => [%{"node" => @body <> "/w:p[6]/w:r[2]/w:footnoteReference[1]", "reason" => "reference ID2, no literal marker characters"}, %{"node" => @body <> "/w:p[6]/w:commentRangeStart[1]", "reason" => "comment range starts, ID3; no characters"}, %{"node" => @body <> "/w:p[6]/w:commentRangeEnd[1]", "reason" => "comment range ends, ID3; no characters"}, %{"node" => @body <> "/w:p[6]/w:r[4]/w:commentReference[1]", "reason" => "comment reference ID3; no literal marker characters"}],
      "coverage" => %{"raw_text_nodes" => 17, "included_text_nodes" => 14, "excluded_text_nodes" => 3, "body_paragraphs" => 6, "table_cells" => 4, "footnote_stories" => 1, "comment_stories" => 1, "header_footer_endnote_parts" => 0, "tabs_breaks" => 0, "unassigned_text_nodes" => 0}}
  end

  defp fragment(suffix, text, reason), do: %{"suffix" => suffix, "text" => text, "reason" => reason}

  defp block(story, node, locator, fragments, part \\ "word/document.xml") do
    {fragments, _} = Enum.map_reduce(fragments, 0, fn f, offset ->
      size = byte_size(f["text"])
      mapped = f |> Map.delete("suffix") |> Map.put("node", node <> f["suffix"]) |> Map.put("block_span", [offset, offset + size])
      {mapped, offset + size}
    end)
    %{"story" => story, "part" => part, "paragraph_node" => node, "locator_basis" => locator, "fragments" => fragments, "text" => Enum.map_join(fragments, & &1["text"])}
  end

  defp raw_text(%{"text" => _} = node), do: [node]
  defp raw_text(node), do: Enum.flat_map(Map.get(node, "children", []), &raw_text/1)
end

WordIndependentExpected.run()
