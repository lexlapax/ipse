defmodule Ipse.Development.Verification.Documents do
  @moduledoc false

  def run(artifact) do
    {:ok, _} = Application.ensure_all_started(:ipse)
    {:ok, _} = Application.ensure_all_started(:xmerl)
    manifest = JSON.decode!(File.read!(Path.join(artifact, "extension.json")))

    for file <- manifest["files"] do
      bytes = File.read!(Path.join(artifact, file["path"]))
      true = byte_size(bytes) == file["bytes"] and digest(bytes) == file["sha256"]
    end

    modules = [
      IpseKnowledge.Evidence,
      IpseKnowledge.Documents,
      IpseKnowledge.Documents.Zip,
      IpseKnowledge.Documents.Docx,
      IpseKnowledge.Documents.Pdf,
      IpseKnowledge.Documents.ParserStage
    ]

    Code.prepend_path(Path.join(artifact, "ebin"))

    for module <- modules do
      Code.ensure_loaded!(module)
      true = Path.dirname(to_string(:code.which(module))) == Path.join(artifact, "ebin")
    end

    extract = fn bytes, name -> apply(IpseKnowledge.Documents, :extract, [bytes, name]) end

    {:ok, %{"format" => "markdown", "segments" => [%{"text" => "# Café 好"}]}} =
      extract.("# Café 好", "fixture.md")

    xml =
      "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:p><w:r><w:t>visible </w:t></w:r><w:del><w:r><w:delText>removed</w:delText></w:r></w:del><w:ins><w:r><w:t>inserted</w:t></w:r></w:ins></w:p></w:body></w:document>"

    root_relationship =
      "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"main\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>"

    content_types =
      "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>"

    {:ok, {_, docx}} =
      :zip.create(
        ~c"development.docx",
        [
          {~c"word/document.xml", xml},
          {~c"_rels/.rels", root_relationship},
          {~c"[Content_Types].xml", content_types}
        ],
        [:memory]
      )

    {:ok, %{"segments" => [%{"text" => "visible inserted"}]}} = extract.(docx, "development.docx")

    styles =
      "<w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"/></w:styles>"

    style_links =
      "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"s\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/><Relationship Id=\"e\" Type=\"http://schemas.microsoft.com/office/2007/relationships/stylesWithEffects\" Target=\"stylesWithEffects.xml\"/></Relationships>"

    style_types =
      String.replace(
        content_types,
        "</Types>",
        "<Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/><Override PartName=\"/word/stylesWithEffects.xml\" ContentType=\"application/vnd.ms-word.stylesWithEffects+xml\"/></Types>"
      )

    styled_document = fn alternate ->
      {:ok, {_, bytes}} =
        :zip.create(
          ~c"styles.docx",
          [
            {~c"word/document.xml", xml},
            {~c"_rels/.rels", root_relationship},
            {~c"[Content_Types].xml", style_types},
            {~c"word/_rels/document.xml.rels", style_links},
            {~c"word/styles.xml", styles},
            {~c"word/stylesWithEffects.xml", alternate}
          ],
          [:memory]
        )

      bytes
    end

    {:ok,
     %{
       "extraction_version" => "ipse-documents-v15",
       "status" => "complete",
       "segments" => [%{"text" => "visible inserted"}]
     }} = extract.(styled_document.(styles), "styles.docx")

    {:error, :unsupported_docx_style_visibility} =
      extract.(styled_document.(String.replace(styles, "Normal", "Other")), "mismatch.docx")

    for {part, item, reference} <- [
          {"footnotes", "footnote", "footnoteReference"},
          {"endnotes", "endnote", "endnoteReference"},
          {"comments", "comment", "commentReference"}
        ] do
      annotation =
        "<w:#{part} xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:#{item} w:id=\"+07\"><w:p><w:r><w:t>linked café</w:t></w:r></w:p></w:#{item}></w:#{part}>"

      types =
        String.replace(
          content_types,
          "</Types>",
          "<Override PartName=\"/word/#{part}.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.#{part}+xml\"/></Types>"
        )

      links =
        "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"annotation\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/#{part}\" Target=\"#{part}.xml\"/></Relationships>"

      for linked <- [true, false] do
        body =
          if linked,
            do: String.replace(xml, "</w:p>", "<w:r><w:#{reference} w:id=\"7\"/></w:r></w:p>"),
            else: xml

        {:ok, {_, bytes}} =
          :zip.create(
            ~c"annotations.docx",
            [
              {~c"word/document.xml", body},
              {~c"_rels/.rels", root_relationship},
              {~c"[Content_Types].xml", types},
              {~c"word/_rels/document.xml.rels", links},
              {String.to_charlist("word/#{part}.xml"), annotation}
            ],
            [:memory]
          )

        {:ok, result} = extract.(bytes, "annotations.docx")
        [_, %{"text" => "linked café", "locator" => locator}] = result["segments"]
        "+07" = locator["annotation_id"]

        if linked do
          "complete" = result["status"]
          [] = result["warnings"]

          %{"byte_offset" => 16, "paragraph" => 1, "part" => "word/document.xml"} =
            locator["reference_site"]
        else
          "partial" = result["status"]
          false = Map.has_key?(locator, "reference_site")
          true = Enum.any?(result["warnings"], &(&1["code"] == "annotation_anchors_unresolved"))
        end
      end
    end

    evidence = IpseKnowledge.Evidence

    many_xml =
      String.replace(xml, "<w:p>", "<w:tbl><w:tr><w:tc><w:p>")
      |> String.replace("</w:p>", "</w:p></w:tc></w:tr></w:tbl>")

    [prefix, body] = String.split(many_xml, "<w:body>")
    [cell, suffix] = String.split(body, "</w:body>")

    {:ok, {_, many_bytes}} =
      :zip.create(
        ~c"many.docx",
        [
          {~c"word/document.xml",
           prefix <> "<w:body>" <> String.duplicate(cell, 329) <> "</w:body>" <> suffix},
          {~c"_rels/.rels", root_relationship},
          {~c"[Content_Types].xml", content_types}
        ],
        [:memory]
      )

    {:ok, many} = extract.(many_bytes, "many.docx")
    329 = length(many["segments"])
    {:ok, payload} = apply(IpseKnowledge.Documents, :source_payload, [many, 65536, 2])
    true = length(payload["document"]["segments"]) <= 32
    receipt = apply(evidence, :document_storage_receipt!, [payload["document"]])

    {:ok, source} =
      apply(evidence, :collection_source, [
        %{
          "source_id" => "provided:many",
          "partition" => "notes",
          "generation" => 1,
          "title" => "Many-cell control",
          "text" => payload["text"],
          "document" => payload["document"],
          "uri" => "provided:many.docx",
          "observed_at_ms" => 10,
          "event_at_ms" => nil,
          "expires_at_ms" => nil,
          "origin" => %{
            "kind" => "provided",
            "store_profile" => "notes",
            "partition_or_scope" => "notes",
            "receipt" => receipt,
            "historical" => false
          }
        }
      ])

    {:ok, [first | _] = chunks} = apply(evidence, :chunks, [source])
    true = length(chunks) <= 32
    {:ok, cited} = apply(evidence, :citation, [source, first, 0, 80])
    2 = cited["document"]["version"]
    true = apply(evidence, :valid_span?, [source, cited])

    false =
      apply(evidence, :valid_span?, [source, put_in(cited, ["document", "span_fields"], [])])

    {:error, :pdf_experimental_unavailable} = extract.(pdf(), "fixture.pdf")
    {:error, :legacy_word_unsupported} = extract.("legacy fixture", "fixture.doc")

    home = System.fetch_env!("IPSE_HOME")
    File.mkdir_p!(home)
    File.chmod!(home, 0o700)
    {:ok, descriptor} = Ipse.DocumentParser.descriptor(home, System.tmp_dir!())

    backend =
      case apply(IpseKnowledge.Documents, :extract_pdf, [pdf(), descriptor]) do
        {:ok, result} ->
          true = result["experimental"] and result["status"] == "complete"
          [%{"text" => text, "locator" => %{"kind" => "page", "page" => 1}}] = result["segments"]
          true = String.contains?(text, "independent parser fixture")
          "available"

        {:error, :pdf_resource_backend_unavailable} ->
          {:unix, :darwin} = :os.type()
          "unavailable_fail_closed"
      end

    notices = Path.join(Path.dirname(descriptor.path), "ipse-pdf-notices")
    inventory = JSON.decode!(File.read!(Path.join(notices, "dependency-inventory.json")))
    60 = length(inventory["packages"])

    for package <- inventory["packages"] do
      directory = Path.join(notices, package["name"] <> "-" <> package["version"])
      true = File.dir?(directory) and File.ls!(directory) != []
    end

    %{
      "synthetic" => true,
      "live_inference" => false,
      "pdf_resource_backend" => backend,
      "checks" =>
        Map.new(
          ~w(artifact_modules text_unicode docx_revision docx_matching_style_effects docx_block_packing docx_annotation_links pdf_default_off pdf_explicit_extraction dependency_notices),
          &{&1, true}
        )
    }
  end

  def pdf do
    content = "BT /F1 12 Tf 10 50 Td (independent parser fixture) Tj ET"

    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 4 0 R >> >> /MediaBox [0 0 200 100] /Contents 5 0 R >>",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
      "<< /Length #{byte_size(content)} >>\nstream\n#{content}\nendstream"
    ]

    {bytes, offsets} =
      Enum.with_index(objects, 1)
      |> Enum.reduce({"%PDF-1.4\n", []}, fn {object, number}, {bytes, offsets} ->
        {bytes <> "#{number} 0 obj\n#{object}\nendobj\n", offsets ++ [byte_size(bytes)]}
      end)

    entries =
      Enum.map_join(
        offsets,
        "",
        &(String.pad_leading(Integer.to_string(&1), 10, "0") <> " 00000 n \n")
      )

    bytes <>
      "xref\n0 6\n0000000000 65535 f \n" <>
      entries <>
      "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n#{byte_size(bytes)}\n%%EOF\n"
  end

  defp digest(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
end
