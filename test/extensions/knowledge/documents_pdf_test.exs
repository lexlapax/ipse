defmodule Ipse.KnowledgeDocumentsPdfTest do
  use ExUnit.Case, async: false
  @root Path.expand("../../..", __DIR__)
  @parser System.get_env("IPSE_TEST_PDF_PARSER") || Path.join(@root, "priv/ipse-pdf")

  defp pure(body) do
    files = ~w(documents/zip documents/docx documents/pdf documents)
    args = Enum.flat_map(files, &["-r", Path.join(@root, "extensions/knowledge/src/#{&1}.ex")])

    bootstrap =
      "import ExUnit.Assertions\nalias IpseKnowledge.Documents, as: D\nparser_path=#{inspect(@parser)}\n"

    {output, status} =
      System.cmd(System.find_executable("elixir"), args ++ ["-e", bootstrap <> body],
        stderr_to_stdout: true
      )

    assert status == 0, output
    refute output =~ "warning:"
  end

  test "PDF remains disabled by default and an explicit parser requires its admitted identity" do
    pure(~S'''
    assert {:error,:pdf_experimental_unavailable}=D.extract("%PDF-1.7","a.pdf")
    for parser <- [nil,%{},%{path: "relative",sha256: "bad"},%{path: "/missing/parser",sha256: String.duplicate("0",64)}] do
      assert {:error,:pdf_parser_identity_unavailable}=D.extract_pdf("%PDF-1.7",parser)
    end
    ''')
  end

  @tag skip: not File.regular?(@parser)
  test "explicit owned parser extracts a real PDF and maps per-file failures" do
    pure(~S'''
    descriptor=%{path: parser_path,sha256: Base.encode16(:crypto.hash(:sha256,File.read!(parser_path)),case: :lower)}
    content="BT /F1 12 Tf 10 50 Td (independent extraction evidence) Tj ET"
    objects=["<< /Type /Catalog /Pages 2 0 R >>","<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 4 0 R >> >> /MediaBox [0 0 200 100] /Contents 5 0 R >>",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
      "<< /Length #{byte_size(content)} >>\nstream\n#{content}\nendstream"]
    {bytes,offsets}=Enum.with_index(objects,1)|>Enum.reduce({"%PDF-1.4\n",[0]},fn {object,n},{bytes,offsets} -> {bytes<>"#{n} 0 obj\n#{object}\nendobj\n",offsets++[byte_size(bytes)]} end)
    xref=byte_size(bytes)
    entries=Enum.map_join(tl(offsets),"",fn offset -> String.pad_leading(Integer.to_string(offset),10,"0")<>" 00000 n \n" end)
    bytes=bytes<>"xref\n0 6\n0000000000 65535 f \n"<>entries<>"trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n"
    {:ok,result}=D.extract_pdf(bytes,descriptor)
    assert result["experimental"] and result["format"]=="pdf" and result["status"]=="complete"
    assert [%{"locator"=>%{"kind"=>"page","page"=>1},"text"=>text}]=result["segments"]
    assert text=~"independent extraction evidence"
    assert result["original_sha256"]==Base.encode16(:crypto.hash(:sha256,bytes),case: :lower)
    assert result["warnings"]==[%{"code"=>"experimental_pdf_reading_order"}]
    assert {:error,:malformed_pdf}=D.extract_pdf("not PDF",descriptor)
    assert {:error,:text_limit}=D.extract_pdf(bytes,descriptor,max_text_bytes: 1)
    assert {:error,:pdf_parser_identity_unavailable}=D.extract_pdf(bytes,%{descriptor|sha256: String.duplicate("0",64)})
    ''')
  end
end
