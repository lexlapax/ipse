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
          ~w(artifact_modules text_unicode docx_revision pdf_default_off pdf_explicit_extraction dependency_notices),
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
