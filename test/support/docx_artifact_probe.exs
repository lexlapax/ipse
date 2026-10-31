alias IpseKnowledge.Documents, as: D
word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
rels = "http://schemas.openxmlformats.org/package/2006/relationships"
prefix = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"

root =
  "<Relationships xmlns=\"#{rels}\"><Relationship Id=\"main\" Type=\"#{prefix}officeDocument\" Target=\"word/document.xml\"/></Relationships>"

types =
  "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>"

make = fn body ->
  document = "<w:document xmlns:w=\"#{word}\"><w:body>#{body}</w:body></w:document>"

  {:ok, {_, bytes}} =
    :zip.create(
      ~c"probe.docx",
      [
        {~c"_rels/.rels", root},
        {~c"[Content_Types].xml", types},
        {~c"word/document.xml", document}
      ],
      [:memory]
    )

  bytes
end

run = fn text -> "<w:r><w:t>#{text}</w:t></w:r>" end
"ipse-documents-v12" = D.version("docx")

{:error, :unsupported_docx_text_structure} =
  D.extract(
    make.("<w:p><w:pPr>" <> run.("metadata") <> "</w:pPr>" <> run.("visible") <> "</w:p>"),
    "test.docx"
  )

{:error, :unsupported_docx_annotation} =
  D.extract(
    make.("<w:footnote w:id=\"1\"><w:p>" <> run.("wrong part") <> "</w:p></w:footnote>"),
    "test.docx"
  )

{:ok,
 %{
   "extraction_version" => "ipse-documents-v12",
   "segments" => [%{"text" => "visible"}],
   "status" => "complete"
 }} = D.extract(make.("<w:p>" <> run.("visible") <> "</w:p>"), "test.docx")

document =
  "<w:document xmlns:w=\"#{word}\"><w:body><w:p>" <>
    run.("λ") <> "<w:r><w:footnoteReference w:id=\"7\"/></w:r></w:p></w:body></w:document>"

notes =
  "<w:footnotes xmlns:w=\"#{word}\"><w:footnote w:id=\"7\"><w:p>" <>
    run.("footnote") <> "</w:p></w:footnote></w:footnotes>"

links =
  "<Relationships xmlns=\"#{rels}\"><Relationship Id=\"notes\" Type=\"#{prefix}footnotes\" Target=\"footnotes.xml\"/></Relationships>"

note_types =
  String.replace(
    types,
    "</Types>",
    "<Override PartName=\"/word/footnotes.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml\"/></Types>"
  )

{:ok, {_, linked}} =
  :zip.create(
    ~c"linked.docx",
    [
      {~c"_rels/.rels", root},
      {~c"[Content_Types].xml", note_types},
      {~c"word/document.xml", document},
      {~c"word/_rels/document.xml.rels", links},
      {~c"word/footnotes.xml", notes}
    ],
    [:memory]
  )

{:ok, %{"status" => "partial", "segments" => [_, %{"locator" => locator}]}} =
  D.extract(linked, "linked.docx")

%{"part" => "word/document.xml", "paragraph" => 1, "byte_offset" => 2} =
  locator["reference_site"]

comment_document =
  "<w:document xmlns:w=\"#{word}\"><w:body><w:p>" <>
    run.("λ") <>
    "<w:commentRangeStart w:id=\"7\"/>" <>
    run.("text") <>
    "<w:commentRangeEnd w:id=\"7\"/><w:r><w:commentReference w:id=\"7\"/></w:r></w:p></w:body></w:document>"

comments =
  "<w:comments xmlns:w=\"#{word}\"><w:comment w:id=\"7\"><w:p>" <>
    run.("comment") <> "</w:p></w:comment></w:comments>"

comment_types = String.replace(note_types, "footnotes", "comments")
comment_links = String.replace(links, "footnotes", "comments")

{:ok, {_, ranged}} =
  :zip.create(
    ~c"ranged.docx",
    [
      {~c"_rels/.rels", root},
      {~c"[Content_Types].xml", comment_types},
      {~c"word/document.xml", comment_document},
      {~c"word/_rels/document.xml.rels", comment_links},
      {~c"word/comments.xml", comments}
    ],
    [:memory]
  )

{:ok, %{"status" => "partial", "segments" => [_, %{"locator" => range_locator}]}} =
  D.extract(ranged, "ranged.docx")

%{"part" => "word/document.xml", "paragraph" => 1, "start_byte" => 2, "end_byte" => 6} =
  range_locator["reference_range"]

table_document =
  "<w:document xmlns:w=\"#{word}\"><w:body><w:tbl><w:tblPr><w:tblStyle w:val=\"grid\"/></w:tblPr>" <>
    "<w:tr><w:tc><w:p>" <> run.("café 雪") <> "</w:p></w:tc></w:tr></w:tbl></w:body></w:document>"

table_styles =
  "<w:styles xmlns:w=\"#{word}\"><w:style w:type=\"table\" w:styleId=\"base\"/>" <>
    "<w:style w:type=\"table\" w:styleId=\"grid\"><w:basedOn w:val=\"base\"/></w:style></w:styles>"

table_links = String.replace(links, "footnotes", "styles")
table_types = String.replace(note_types, "footnotes", "styles")

make_table = fn styles ->
  {:ok, {_, bytes}} =
    :zip.create(
      ~c"table.docx",
      [
        {~c"_rels/.rels", root},
        {~c"[Content_Types].xml", table_types},
        {~c"word/document.xml", table_document},
        {~c"word/_rels/document.xml.rels", table_links},
        {~c"word/styles.xml", styles}
      ],
      [:memory]
    )

  bytes
end

{:ok, %{"status" => "complete", "segments" => [%{"text" => "café 雪", "locator" => cell}]}} =
  D.extract(make_table.(table_styles), "table.docx")

%{"kind" => "table_cell", "table" => 1, "row" => 1, "cell" => 1} = cell

hidden_table_styles =
  String.replace(table_styles, "<w:basedOn", "<w:rPr><w:vanish/></w:rPr><w:basedOn")

{:error, :unsupported_docx_style_visibility} =
  D.extract(make_table.(hidden_table_styles), "hidden-table.docx")

IO.puts("ARTIFACT_DOCX_PROBE_PASSED #{:code.which(D)}")
