defmodule IpseKnowledge.Documents.Docx do
  @moduledoc false
  alias IpseKnowledge.Documents.Zip
  @word ~c"http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  @strict ~c"http://purl.oclc.org/ooxml/wordprocessingml/main"
  @parts ~w(word/document.xml word/footnotes.xml word/endnotes.xml word/comments.xml)

  def extract(bytes, limits) do
    entries = Zip.entries(bytes, limits)
    names = Enum.map(entries, & &1.name)

    cond do
      "EncryptedPackage" in names or "EncryptionInfo" in names ->
        fail(:encrypted_document)

      Enum.any?(
        names,
        &(String.starts_with?(&1, "word/embeddings/") or
              String.ends_with?(String.downcase(&1), "vbaproject.bin"))
      ) ->
        fail(:embedded_objects_unsupported)

      "word/document.xml" not in names ->
        fail(:not_word_document)

      true ->
        :ok
    end

    selected =
      Enum.filter(entries, &(&1.name in @parts))
      |> Enum.sort_by(&Enum.find_index(@parts, fn name -> name == &1.name end))

    {segments, warnings, _expanded, _text} =
      Enum.reduce(selected, {[], [], 0, 0}, fn entry, {segments, warnings, expanded, text} ->
        xml = Zip.read(bytes, entry, limits.max_expanded_bytes - expanded)
        state = parse(xml, entry.name, limits, length(segments), text)

        {segments ++ Enum.reverse(state.segments), warnings ++ state.warnings,
         expanded + byte_size(xml), state.text_bytes}
      end)

    omissions =
      for name <- names,
          String.match?(name, ~r/\Aword\/(?:header|footer)\d+\.xml\z/),
          do: %{"code" => "part_not_extracted", "part" => name}

    warnings = Enum.uniq(warnings ++ omissions)

    {:ok,
     %{
       "format" => "docx",
       "status" => if(warnings == [], do: "complete", else: "partial"),
       "revision_policy" => "final_visible_insertions_included_deletions_excluded",
       "segments" => segments,
       "warnings" => warnings
     }}
  end

  defp parse(xml, part, limits, count, text) do
    # Refuse DTD syntax before the parser can invoke an entity resolver. DOCX XML
    # is UTF-8 in this version; UTF-16 is explicitly refused instead of bypassing
    # the independent declaration check with interleaved NULs.
    unless String.valid?(xml) and not String.contains?(xml, <<0>>),
      do: fail(:unsupported_xml_encoding)

    if String.contains?(xml, ["<!DOCTYPE", "<!ENTITY"]), do: fail(:xml_entities_unsupported)

    state = %{
      part: part,
      limits: limits,
      depth: 0,
      stack: [],
      root: false,
      paragraph: 0,
      current: nil,
      table_count: 0,
      tables: [],
      note: nil,
      excluded: 0,
      segments: [],
      count: count,
      text_bytes: text,
      warnings: []
    }

    options = [
      :disallow_entities,
      {:external_entities, :none},
      {:fail_undeclared_ref, true},
      {:event_state, state},
      {:event_fun, &event/3}
    ]

    case :xmerl_sax_parser.stream(xml, options) do
      {:ok, %{depth: 0, root: true} = result, rest} when rest in ["", []] -> result
      {:document_error, _, code, _, _} when is_atom(code) -> fail(code)
      _ -> fail(:malformed_xml)
    end
  end

  defp event({:startDTD, _, _, _}, _, _), do: fail(:xml_entities_unsupported)
  defp event({:processingInstruction, _, _}, _, _), do: fail(:xml_processing_instruction)

  defp event({:startElement, uri, name, _, attrs}, _, state) do
    if state.depth >= 64 or length(attrs) > 64, do: fail(:xml_structure_limit)

    if Enum.any?(attrs, fn {_, _, _, value} -> length(value) > 4096 end),
      do: fail(:xml_structure_limit)

    if uri == ~c"http://schemas.openxmlformats.org/markup-compatibility/2006" and
         name == ~c"AlternateContent",
       do: fail(:unsupported_docx_alternate_content)

    word? = uri in [@word, @strict]
    element = if word?, do: List.to_string(name), else: :other

    state =
      if state.depth == 0 do
        expected =
          case state.part do
            "word/document.xml" -> "document"
            "word/footnotes.xml" -> "footnotes"
            "word/endnotes.xml" -> "endnotes"
            "word/comments.xml" -> "comments"
          end

        if element != expected, do: fail(:invalid_word_namespace)
        %{state | root: true}
      else
        state
      end

    state = %{state | depth: state.depth + 1, stack: [element | state.stack]}

    cond do
      element in ~w(del moveFrom) ->
        %{state | excluded: state.excluded + 1}

      element == "tbl" ->
        index = state.table_count + 1
        %{state | table_count: index, tables: [%{table: index, row: 0, cell: 0} | state.tables]}

      element == "tr" and state.tables != [] ->
        [table | rest] = state.tables
        %{state | tables: [%{table | row: table.row + 1, cell: 0} | rest]}

      element == "tc" and state.tables != [] ->
        [table | rest] = state.tables
        %{state | tables: [%{table | cell: table.cell + 1} | rest]}

      element in ~w(footnote endnote comment) ->
        %{state | note: attr(attrs, "id")}

      element == "p" ->
        start_paragraph(state)

      element == "pStyle" and state.current != nil ->
        put_in(state.current.style, attr(attrs, "val"))

      element in ~w(tab br cr) ->
        append(state, if(element == "tab", do: "\t", else: "\n"))

      element in ~w(drawing pict object altChunk subDoc txbxContent) ->
        %{
          state
          | warnings: [
              %{"code" => "unsupported_content", "part" => state.part, "element" => element}
              | state.warnings
            ]
        }

      true ->
        state
    end
  end

  defp event({:endElement, _, _, _}, _, %{stack: [element | rest]} = state) do
    state =
      cond do
        element in ~w(del moveFrom) -> %{state | excluded: state.excluded - 1}
        element == "p" -> finish_paragraph(state)
        element == "tbl" -> %{state | tables: tl(state.tables)}
        element in ~w(footnote endnote comment) -> %{state | note: nil}
        true -> state
      end

    %{state | depth: state.depth - 1, stack: rest}
  end

  defp event({:characters, characters}, _, %{stack: ["t" | _]} = state),
    do: append(state, :unicode.characters_to_binary(characters))

  defp event(_, _, state), do: state

  defp start_paragraph(%{current: current}) when current != nil,
    do: fail(:unsupported_nested_paragraph)

  defp start_paragraph(state) do
    number = state.paragraph + 1
    locator = %{"kind" => "paragraph", "part" => state.part, "paragraph" => number}

    locator =
      if state.note == nil, do: locator, else: Map.put(locator, "annotation_id", state.note)

    locator =
      case state.tables do
        [table | _] ->
          Map.merge(locator, %{
            "kind" => "table_cell",
            "table" => table.table,
            "row" => table.row,
            "cell" => table.cell
          })

        [] ->
          locator
      end

    %{state | paragraph: number, current: %{text: [], style: nil, locator: locator}}
  end

  defp finish_paragraph(%{current: nil} = state), do: state

  defp finish_paragraph(state) do
    text = state.current.text |> Enum.reverse() |> IO.iodata_to_binary()

    if text == "" do
      %{state | current: nil}
    else
      if state.count >= state.limits.max_segments, do: fail(:segment_limit)
      segment = %{"text" => text, "locator" => state.current.locator}

      segment =
        if state.current.style, do: Map.put(segment, "style", state.current.style), else: segment

      %{state | current: nil, count: state.count + 1, segments: [segment | state.segments]}
    end
  end

  defp append(%{current: nil} = state, _), do: state
  defp append(%{excluded: excluded} = state, _) when excluded > 0, do: state

  defp append(state, bytes) do
    size = state.text_bytes + byte_size(bytes)
    if size > state.limits.max_text_bytes, do: fail(:text_limit)
    %{state | text_bytes: size, current: %{state.current | text: [bytes | state.current.text]}}
  end

  defp attr(attrs, name) do
    Enum.find_value(attrs, fn {uri, _, local, value} ->
      if uri in [@word, @strict] and List.to_string(local) == name, do: List.to_string(value)
    end)
  end

  defp fail(code), do: throw({:document_error, code})
end
