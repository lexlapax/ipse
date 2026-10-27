defmodule IpseKnowledge.Documents.Docx do
  @moduledoc false
  alias IpseKnowledge.Documents.Zip
  @word ~c"http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  @strict ~c"http://purl.oclc.org/ooxml/wordprocessingml/main"
  @parts ~w(word/document.xml word/footnotes.xml word/endnotes.xml word/comments.xml)
  @structural ~w(document body footnotes endnotes comments footnote endnote comment p pPr r rPr t delText tbl tblPr tblGrid gridCol tr trPr tc tcPr ins moveTo del moveFrom hyperlink bookmarkStart bookmarkEnd commentRangeStart commentRangeEnd commentReference footnoteReference endnoteReference proofErr permStart permEnd sectPr lastRenderedPageBreak pStyle rStyle)

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

    {authority, authority_bytes} =
      Enum.reduce(["_rels/.rels", "[Content_Types].xml"], {%{}, 0}, fn name, {data, expanded} ->
        entry =
          Enum.find(entries, &(&1.name == name)) || fail(:unsupported_docx_package_authority)

        xml = Zip.read(bytes, entry, limits.max_expanded_bytes - expanded)
        {Map.put(data, name, xml), expanded + byte_size(xml)}
      end)

    root_relationships =
      IpseKnowledge.Documents.Docx.Styles.relationships(authority["_rels/.rels"], names, :root)

    IpseKnowledge.Documents.Docx.Styles.content_types(authority["[Content_Types].xml"], names)

    selected =
      Enum.filter(entries, &(&1.name in @parts))
      |> Enum.sort_by(&Enum.find_index(@parts, fn name -> name == &1.name end))

    {relationships, relationship_bytes} =
      case Enum.find(entries, &(&1.name == "word/_rels/document.xml.rels")) do
        nil ->
          {%{parts: %{}, external?: false, unexamined?: false}, 0}

        entry ->
          xml = Zip.read(bytes, entry, limits.max_expanded_bytes - authority_bytes)
          {IpseKnowledge.Documents.Docx.Styles.relationships(xml, names), byte_size(xml)}
      end

    for name <- ["word/styles.xml" | tl(@parts)], name in names do
      unless Map.has_key?(relationships.parts, name),
        do: fail(:unsupported_docx_part_relationship)
    end

    {styles, style_bytes} =
      case Enum.find(entries, &(&1.name == "word/styles.xml")) do
        nil ->
          {IpseKnowledge.Documents.Docx.Styles.empty(), 0}

        entry ->
          xml =
            Zip.read(
              bytes,
              entry,
              limits.max_expanded_bytes - authority_bytes - relationship_bytes
            )

          {IpseKnowledge.Documents.Docx.Styles.parse(xml), byte_size(xml)}
      end

    {segments, warnings, _expanded, _text} =
      Enum.reduce(
        selected,
        {[], [], authority_bytes + style_bytes + relationship_bytes, 0},
        fn entry, {segments, warnings, expanded, text} ->
          xml = Zip.read(bytes, entry, limits.max_expanded_bytes - expanded)
          state = parse(xml, entry.name, limits, length(segments), text, styles)

          {segments ++ Enum.reverse(state.segments), warnings ++ state.warnings,
           expanded + byte_size(xml), state.text_bytes}
        end
      )

    omissions =
      for name <- names,
          String.starts_with?(name, "word/") and String.ends_with?(name, ".xml") and
            name not in ["word/styles.xml" | @parts],
          do: %{"code" => "part_not_extracted", "part" => name}

    relationship_warnings =
      Enum.flat_map(
        [{"_rels/.rels", root_relationships}, {"word/_rels/document.xml.rels", relationships}],
        fn {name, observation} ->
          external =
            if observation.external?,
              do: [%{"code" => "external_relationship_not_followed", "part" => name}],
              else: []

          unexamined =
            if observation.unexamined?,
              do: [%{"code" => "internal_relationship_not_examined", "part" => name}],
              else: []

          external ++ unexamined
        end
      )

    unexamined =
      if Enum.any?(names, fn name ->
           String.ends_with?(name, ".rels") and
             name not in ["_rels/.rels", "word/_rels/document.xml.rels"]
         end),
         do: [%{"code" => "relationship_part_not_examined"}],
         else: []

    warnings = Enum.uniq(warnings ++ omissions ++ relationship_warnings ++ unexamined)

    {:ok,
     %{
       "format" => "docx",
       "status" => if(warnings == [], do: "complete", else: "partial"),
       "revision_policy" => "insertions_included_deletions_excluded",
       "visibility_policy" => "bounded_style_and_direct_hidden_excluded",
       "segments" => segments,
       "warnings" => warnings
     }}
  end

  defp parse(xml, part, limits, count, text, styles) do
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
      runs: [],
      styles: styles,
      segments: [],
      count: count,
      text_bytes: text,
      warnings: [],
      warned: MapSet.new()
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

    state =
      if not word?,
        do: warning(state, "unsupported_namespace_content"),
        else: state

    cond do
      element in ~w(del moveFrom) ->
        %{state | excluded: state.excluded + 1}

      element == "r" ->
        if state.runs != [], do: fail(:unsupported_nested_run)

        %{
          state
          | runs: [
              %{
                hidden: false,
                style: nil,
                style_seen: false,
                visibility_seen: false,
                content_started: false
              }
            ]
        }

      element == "vanish" ->
        hidden_property(state, attrs)

      element in ~w(webHidden specVanish) ->
        if state.excluded > 0 or "rPrChange" in state.stack,
          do: warning(state, "unsupported_visibility_property", element),
          else: fail(:unsupported_docx_style_visibility)

      element in ~w(headerReference footerReference) ->
        warning(state, "referenced_part_not_extracted", element)

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
        if not match?(["pStyle", "pPr", "p" | _], state.stack) or
             state.current.style_seen or state.current.content_started,
           do: fail(:unsupported_docx_style_visibility)

        style = attr(attrs, "val")
        IpseKnowledge.Documents.Docx.Styles.check(state.styles, style, "paragraph")
        %{state | current: %{state.current | style: style, style_seen: true}}

      element == "rStyle" ->
        case {state.stack, state.runs} do
          {["rStyle", "rPr", "r" | _], [run]} ->
            if run.style_seen or run.content_started, do: fail(:unsupported_docx_style_visibility)
            style = attr(attrs, "val")
            IpseKnowledge.Documents.Docx.Styles.check(state.styles, style, "character")
            %{state | runs: [%{run | style: style, style_seen: true}]}

          _ ->
            fail(:unsupported_docx_style_visibility)
        end

      element in ~w(tblStyle numPr) ->
        fail(:unsupported_docx_style_visibility)

      element in ~w(tab br cr) ->
        append(state, if(element == "tab", do: "\t", else: "\n"))

      element == "noBreakHyphen" ->
        append(state, "\u2011")

      element == "softHyphen" ->
        append(state, "\u00ad")

      element in ~w(fldSimple fldChar instrText) ->
        warning(state, "fields_not_recalculated")

      element in ~w(drawing pict object altChunk subDoc txbxContent sym ptab) ->
        warning(state, "unsupported_content", element)

      true ->
        if word? and element not in @structural,
          do: warning(state, "unsupported_word_content"),
          else: state
    end
  end

  defp event({:endElement, _, _, _}, _, %{stack: [element | rest]} = state) do
    state =
      cond do
        element in ~w(del moveFrom) -> %{state | excluded: state.excluded - 1}
        element == "p" -> finish_paragraph(state)
        element == "r" -> %{state | runs: tl(state.runs)}
        element == "tbl" -> %{state | tables: tl(state.tables)}
        element in ~w(footnote endnote comment) -> %{state | note: nil}
        true -> state
      end

    %{state | depth: state.depth - 1, stack: rest}
  end

  defp event({:characters, characters}, _, %{stack: ["t" | _]} = state),
    do: append(state, :unicode.characters_to_binary(characters))

  defp event({:characters, _}, _, %{excluded: excluded} = state) when excluded > 0,
    do: state

  defp event({:characters, characters}, _, state) do
    if characters |> :unicode.characters_to_binary() |> String.trim() == "",
      do: state,
      else: warning(state, "unsupported_text_content")
  end

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

    %{
      state
      | paragraph: number,
        current: %{
          text: [],
          style: nil,
          style_seen: false,
          content_started: false,
          locator: locator
        }
    }
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

  defp append(%{excluded: excluded} = state, _) when excluded > 0, do: state
  defp append(%{current: nil} = state, ""), do: state
  defp append(%{current: nil} = state, _), do: warning(state, "unsupported_text_location")

  defp append(state, bytes) do
    state =
      case state.runs do
        [run] -> %{state | runs: [%{run | content_started: true}]}
        [] -> state
      end

    hidden =
      case state.runs do
        [run] ->
          inherited =
            IpseKnowledge.Documents.Docx.Styles.hidden?(
              state.styles,
              state.current.style,
              run.style
            )

          if run.visibility_seen, do: run.hidden, else: inherited

        [] ->
          IpseKnowledge.Documents.Docx.Styles.hidden?(state.styles, state.current.style, nil)
      end

    state = %{state | current: %{state.current | content_started: true}}

    if hidden do
      state
    else
      size = state.text_bytes + byte_size(bytes)
      if size > state.limits.max_text_bytes, do: fail(:text_limit)
      %{state | text_bytes: size, current: %{state.current | text: [bytes | state.current.text]}}
    end
  end

  defp hidden_property(%{stack: ["vanish", "rPr", "r" | _], runs: [run]} = state, attrs) do
    if run.content_started or run.visibility_seen, do: fail(:unsupported_docx_run_properties)

    hidden =
      case attr(attrs, "val") do
        value when value in [nil, "1", "true", "on"] -> true
        value when value in ["0", "false", "off"] -> false
        _ -> fail(:unsupported_docx_run_properties)
      end

    %{state | runs: [%{run | hidden: hidden, visibility_seen: true}]}
  end

  defp hidden_property(state, _), do: warning(state, "unsupported_visibility_property", "vanish")

  defp warning(state, code, element \\ nil) do
    key = {code, element}

    if MapSet.member?(state.warned, key) do
      state
    else
      warning = %{"code" => code, "part" => state.part}
      warning = if element, do: Map.put(warning, "element", element), else: warning

      %{state | warnings: [warning | state.warnings], warned: MapSet.put(state.warned, key)}
    end
  end

  defp attr(attrs, name) do
    Enum.find_value(attrs, fn {uri, _, local, value} ->
      if uri in [@word, @strict] and List.to_string(local) == name, do: List.to_string(value)
    end)
  end

  defp fail(code), do: throw({:document_error, code})
end

defmodule IpseKnowledge.Documents.Docx.Styles do
  @moduledoc false
  @word ~c"http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  @strict ~c"http://purl.oclc.org/ooxml/wordprocessingml/main"

  def empty, do: %{styles: %{}, default: nil, defaults: nil}

  @part_types %{
    "word/document.xml" => "document.main",
    "word/styles.xml" => "styles",
    "word/footnotes.xml" => "footnotes",
    "word/endnotes.xml" => "endnotes",
    "word/comments.xml" => "comments"
  }

  def content_types(xml, names) do
    safe_xml!(xml)

    options = [
      :disallow_entities,
      {:external_entities, :none},
      {:fail_undeclared_ref, true},
      {:event_state, %{depth: 0, seen: MapSet.new(), overrides: %{}}},
      {:event_fun, &content_event/3}
    ]

    case :xmerl_sax_parser.stream(xml, options) do
      {:ok, %{depth: 0, overrides: types}, rest} when rest in ["", []] ->
        Enum.each(@part_types, fn {name, kind} ->
          if name in names and
               types["/" <> name] !=
                 "application/vnd.openxmlformats-officedocument.wordprocessingml.#{kind}+xml",
             do: fail(:unsupported_docx_content_types)
        end)

        :ok

      {:document_error, _, code, _, _} when is_atom(code) ->
        fail(code)

      _ ->
        fail(:malformed_xml)
    end
  end

  def relationships(xml, names, mode \\ :document) do
    safe_xml!(xml)

    state = %{
      depth: 0,
      count: 0,
      parts: %{},
      external?: false,
      unexamined?: false,
      ids: MapSet.new(),
      names: names,
      mode: mode,
      error:
        if(mode == :root,
          do: :unsupported_docx_package_authority,
          else: :unsupported_docx_style_relationship
        )
    }

    options = [
      :disallow_entities,
      {:external_entities, :none},
      {:fail_undeclared_ref, true},
      {:event_state, state},
      {:event_fun, &relationship_event/3}
    ]

    case :xmerl_sax_parser.stream(xml, options) do
      {:ok, %{depth: 0} = result, rest} when rest in ["", []] ->
        if mode == :root and not Map.has_key?(result.parts, "word/document.xml"),
          do: fail(result.error)

        %{parts: result.parts, external?: result.external?, unexamined?: result.unexamined?}

      {:document_error, _, code, _, _} when is_atom(code) ->
        fail(code)

      _ ->
        fail(:malformed_xml)
    end
  end

  def parse(xml) do
    safe_xml!(xml)

    state =
      Map.merge(empty(), %{
        stack: [],
        current: nil,
        root: false,
        seen: MapSet.new(),
        default_types: MapSet.new(),
        default_character: nil
      })

    options = [
      :disallow_entities,
      {:external_entities, :none},
      {:fail_undeclared_ref, true},
      {:event_state, state},
      {:event_fun, &event/3}
    ]

    case :xmerl_sax_parser.stream(xml, options) do
      {:ok, %{stack: [], root: true} = result, rest} when rest in ["", []] ->
        # Validate the inheritance graph, including unused definitions. An invalid
        # graph cannot acquire different meaning through a later style reference.
        Enum.each(result.styles, fn {id, style} ->
          chain(result, id, style.type, MapSet.new(), false)
        end)

        # The character-style/rStyle rule and generic default-for-type rule do
        # not establish a qualified Word visibility policy for this case. Keep
        # a visibility-bearing default character style outside our subset.
        if result.default_character do
          flags = chain(result, result.default_character, "character", MapSet.new())
          if Enum.any?(flags, &(not is_nil(&1))), do: fail(:unsupported_docx_style_visibility)
        end

        Map.take(result, [:styles, :default, :defaults])

      {:document_error, _, code, _, _} when is_atom(code) ->
        fail(code)

      _ ->
        fail(:malformed_xml)
    end
  end

  def check(styles, id, type) when is_binary(id) and byte_size(id) in 1..256 do
    chain(styles, id, type, MapSet.new())
    :ok
  end

  def check(_, _, _), do: fail(:unsupported_docx_style_visibility)

  def hidden?(styles, paragraph, character) do
    paragraph = paragraph || styles.default
    p = if paragraph, do: chain(styles, paragraph, "paragraph", MapSet.new()), else: []
    c = if character, do: chain(styles, character, "character", MapSet.new()), else: []
    # Word and ISO differ for multi-level toggle interactions. This supported
    # subset accepts only a single effective inherited declaration; direct run
    # overrides remain absolute, but never make an invalid style graph valid.
    flags = Enum.reject([styles.defaults | p ++ c], &is_nil/1)

    case flags do
      [] ->
        false

      [value] ->
        value

      values ->
        if Enum.all?(values, &(&1 == false)),
          do: false,
          else: fail(:unsupported_docx_style_visibility)
    end
  end

  defp chain(state, id, type, seen, selected? \\ true) do
    if MapSet.size(seen) >= 64 or MapSet.member?(seen, id),
      do: fail(:unsupported_docx_style_visibility)

    case Map.fetch(state.styles, id) do
      {:ok, %{type: ^type} = style} ->
        if selected? and style.link != nil, do: fail(:unsupported_docx_style_visibility)

        parent =
          if style.parent,
            do: chain(state, style.parent, type, MapSet.put(seen, id), selected?),
            else: []

        parent ++ [style.hidden]

      _ ->
        fail(:unsupported_docx_style_visibility)
    end
  end

  defp event({:startDTD, _, _, _}, _, _), do: fail(:xml_entities_unsupported)
  defp event({:processingInstruction, _, _}, _, _), do: fail(:xml_processing_instruction)

  defp event({:startElement, uri, local, _, attrs}, _, state) do
    if length(state.stack) >= 64 or length(attrs) > 64 or
         Enum.any?(attrs, fn {_, _, _, value} -> length(value) > 4096 end),
       do: fail(:xml_structure_limit)

    unless uri in [@word, @strict], do: fail(:unsupported_docx_style_visibility)
    element = List.to_string(local)
    if state.stack == [] and element != "styles", do: fail(:invalid_word_namespace)
    state = %{state | stack: [element | state.stack], root: true}

    cond do
      state.stack == ["style", "styles"] ->
        if map_size(state.styles) >= 512 or state.current != nil,
          do: fail(:unsupported_docx_style_visibility)

        id = attr(attrs, "styleId")
        type = attr(attrs, "type")

        unless is_binary(id) and byte_size(id) in 1..256 and
                 type in ~w(paragraph character table numbering) and
                 not Map.has_key?(state.styles, id),
               do: fail(:unsupported_docx_style_visibility)

        default = flag(attr(attrs, "default"), false)

        if default and MapSet.member?(state.default_types, type),
          do: fail(:unsupported_docx_style_visibility)

        state =
          if default,
            do: %{state | default_types: MapSet.put(state.default_types, type)},
            else: state

        state = if default and type == "paragraph", do: %{state | default: id}, else: state

        state =
          if default and type == "character", do: %{state | default_character: id}, else: state

        %{
          state
          | current: %{
              id: id,
              type: type,
              parent: nil,
              link: nil,
              hidden: nil,
              seen: MapSet.new()
            }
        }

      element == "style" ->
        fail(:unsupported_docx_style_visibility)

      state.stack in [
        ["docDefaults", "styles"],
        ["rPrDefault", "docDefaults", "styles"],
        ["rPr", "rPrDefault", "docDefaults", "styles"]
      ] ->
        unique(state, List.to_tuple(state.stack))

      element in ~w(basedOn link) and state.current != nil ->
        unless state.stack == [element, "style", "styles"],
          do: fail(:unsupported_docx_style_visibility)

        value = attr(attrs, "val")

        unless is_binary(value) and byte_size(value) in 1..256,
          do: fail(:unsupported_docx_style_visibility)

        state = unique_style(state, element)
        key = if element == "basedOn", do: :parent, else: :link
        %{state | current: Map.put(state.current, key, value)}

      element == "vanish" ->
        value = flag(attr(attrs, "val"), true)

        cond do
          state.stack == ["vanish", "rPr", "rPrDefault", "docDefaults", "styles"] ->
            state = unique(state, :default_vanish)
            %{state | defaults: value}

          state.stack == ["vanish", "rPr", "style", "styles"] and state.current != nil ->
            state = unique_style(state, :vanish)

            if state.current.type not in ~w(paragraph character),
              do: fail(:unsupported_docx_style_visibility)

            %{state | current: %{state.current | hidden: value}}

          true ->
            fail(:unsupported_docx_style_visibility)
        end

      element in ~w(webHidden specVanish tblStyle numPr rStyle pStyle rPrChange) ->
        fail(:unsupported_docx_style_visibility)

      true ->
        state
    end
  end

  defp event({:endElement, _, _, _}, _, %{stack: [element | rest]} = state) do
    state =
      if element == "style" do
        style = state.current

        %{
          state
          | styles: Map.put(state.styles, style.id, Map.drop(style, [:id, :seen])),
            current: nil
        }
      else
        state
      end

    %{state | stack: rest}
  end

  defp event({:characters, chars}, _, state) do
    unless chars |> :unicode.characters_to_binary() |> String.trim() == "",
      do: fail(:unsupported_docx_style_visibility)

    state
  end

  defp event(_, _, state), do: state

  defp unique(state, key) do
    if MapSet.member?(state.seen, key), do: fail(:unsupported_docx_style_visibility)
    %{state | seen: MapSet.put(state.seen, key)}
  end

  defp unique_style(state, key) do
    if MapSet.member?(state.current.seen, key), do: fail(:unsupported_docx_style_visibility)
    %{state | current: %{state.current | seen: MapSet.put(state.current.seen, key)}}
  end

  defp flag(nil, default), do: default
  defp flag(value, _) when value in ["1", "true", "on"], do: true
  defp flag(value, _) when value in ["0", "false", "off"], do: false
  defp flag(_, _), do: fail(:unsupported_docx_style_visibility)

  defp attr(attrs, name),
    do:
      Enum.find_value(attrs, fn {uri, _, local, value} ->
        if uri in [@word, @strict] and List.to_string(local) == name, do: List.to_string(value)
      end)

  defp fail(code), do: throw({:document_error, code})

  defp safe_xml!(xml) do
    unless String.valid?(xml) and not String.contains?(xml, <<0>>),
      do: fail(:unsupported_xml_encoding)

    if String.contains?(xml, ["<!DOCTYPE", "<!ENTITY"]), do: fail(:xml_entities_unsupported)
  end

  defp relationship_event({:startDTD, _, _, _}, _, _), do: fail(:xml_entities_unsupported)

  defp relationship_event({:processingInstruction, _, _}, _, _),
    do: fail(:xml_processing_instruction)

  defp relationship_event({:startElement, uri, local, _, attrs}, _, state) do
    unless uri == ~c"http://schemas.openxmlformats.org/package/2006/relationships" and
             ((state.depth == 0 and local == ~c"Relationships") or
                (state.depth == 1 and local == ~c"Relationship")) and length(attrs) <= 16 and
             Enum.all?(attrs, fn {_, _, _, value} -> length(value) <= 4096 end),
           do: fail(state.error)

    if state.count >= 1024, do: fail(state.error)

    if state.depth == 0 do
      %{state | depth: 1}
    else
      attribute = fn name ->
        Enum.find_value(attrs, fn {namespace, _, key, value} ->
          if namespace in [[], ~c""] and List.to_string(key) == name, do: List.to_string(value)
        end)
      end

      id = attribute.("Id")

      unless is_binary(id) and byte_size(id) in 1..256 and not MapSet.member?(state.ids, id),
        do: fail(state.error)

      type = attribute.("Type")
      mode = attribute.("TargetMode")
      target = attribute.("Target")

      unless is_binary(type) and type != "" and is_binary(target) and target != "" and
               mode in [nil, "Internal", "External"] and
               (mode == "External" or
                  (not String.starts_with?(target, "//") and
                     not Regex.match?(~r/\A[A-Za-z][A-Za-z0-9+.-]*:/, target))),
             do: fail(state.error)

      if is_binary(type) and String.ends_with?(type, "/stylesWithEffects"),
        do: fail(state.error)

      part =
        Enum.find_value(
          [
            "http://schemas.openxmlformats.org/officeDocument/2006/relationships/",
            "http://purl.oclc.org/ooxml/officeDocument/relationships/"
          ],
          fn prefix ->
            if is_binary(type) and String.starts_with?(type, prefix) do
              kind = String.replace_prefix(type, prefix, "")

              case {state.mode, kind} do
                {:root, "officeDocument"} ->
                  "word/document.xml"

                {:document, kind} when kind in ~w(styles footnotes endnotes comments) ->
                  "word/#{kind}.xml"

                _ ->
                  nil
              end
            end
          end
        )

      if part do
        targets =
          if state.mode == :root,
            do: [part, "/" <> part],
            else: [Path.basename(part), "/" <> part]

        if Map.has_key?(state.parts, part) or attribute.("Target") not in targets or
             attribute.("TargetMode") not in [nil, "Internal"] or part not in state.names,
           do: fail(state.error)
      end

      %{
        state
        | depth: 2,
          count: state.count + 1,
          parts: if(part, do: Map.put(state.parts, part, id), else: state.parts),
          external?: state.external? or mode == "External",
          unexamined?: state.unexamined? or (is_nil(part) and mode != "External"),
          ids: MapSet.put(state.ids, id)
      }
    end
  end

  defp relationship_event({:endElement, _, _, _}, _, state), do: %{state | depth: state.depth - 1}

  defp relationship_event({:characters, chars}, _, state) do
    unless chars |> :unicode.characters_to_binary() |> String.trim() == "",
      do: fail(state.error)

    state
  end

  defp relationship_event(_, _, state), do: state

  defp content_event({:startDTD, _, _, _}, _, _), do: fail(:xml_entities_unsupported)
  defp content_event({:processingInstruction, _, _}, _, _), do: fail(:xml_processing_instruction)

  defp content_event({:startElement, uri, local, _, attrs}, _, state) do
    element = List.to_string(local)

    unless uri == ~c"http://schemas.openxmlformats.org/package/2006/content-types" and
             ((state.depth == 0 and element == "Types") or
                (state.depth == 1 and element in ["Default", "Override"])) and length(attrs) <= 16 and
             Enum.all?(attrs, fn {_, _, _, value} -> length(value) <= 4096 end) and
             MapSet.size(state.seen) < 1024,
           do: fail(:unsupported_docx_content_types)

    if state.depth == 0 do
      %{state | depth: 1}
    else
      attribute = fn name ->
        Enum.find_value(attrs, fn {namespace, _, key, value} ->
          if namespace == [] and List.to_string(key) == name, do: List.to_string(value)
        end)
      end

      name = attribute.(if(element == "Default", do: "Extension", else: "PartName"))
      value = attribute.("ContentType")
      key = {element, name}

      unless is_binary(name) and byte_size(name) in 1..1024 and is_binary(value) and
               byte_size(value) in 1..256 and
               not MapSet.member?(state.seen, key),
             do: fail(:unsupported_docx_content_types)

      %{
        state
        | depth: 2,
          seen: MapSet.put(state.seen, key),
          overrides:
            if(element == "Override",
              do: Map.put(state.overrides, name, value),
              else: state.overrides
            )
      }
    end
  end

  defp content_event({:endElement, _, _, _}, _, state), do: %{state | depth: state.depth - 1}

  defp content_event({:characters, chars}, _, state) do
    unless chars |> :unicode.characters_to_binary() |> String.trim() == "",
      do: fail(:unsupported_docx_content_types)

    state
  end

  defp content_event(_, _, state), do: state
end
