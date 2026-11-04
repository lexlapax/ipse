defmodule Ipse.Test.WordCapacityFixture do
  @moduledoc false

  # Synthetic geometry, not independent Word rendering or semantic quality.
  # An inert PNG thumbnail exercises original-byte geometry without expanding
  # the main XML. Its unexamined relationship must remain a partial warning.
  def build(kind) when kind in [:at_bound, :text_over, :original_over] do
    text_bytes = if kind === :text_over, do: 65_537, else: 65_536
    original_bytes = if kind === :original_over, do: 1_048_577, else: 1_048_576

    paragraphs =
      Enum.map(1..32, fn ordinal ->
        needle =
          case ordinal do
            1 -> "firstcapacityneedle"
            16 -> "middlecapacityneedle"
            32 -> "lastcapacityneedle"
            _ -> "capacityparagraph#{ordinal}"
          end

        prefix = "#{needle} preserves résumé 雪 evidence. "
        target = if ordinal === 32, do: text_bytes - 31 - 31 * 2047, else: 2047
        remaining = target - byte_size(prefix)
        filler = String.duplicate("detail ", div(remaining, 7) + 1)
        prefix <> binary_part(filler, 0, remaining - 1) <> "x"
      end)

    text = Enum.join(paragraphs, "\n")
    ^text_bytes = byte_size(text)
    body = Enum.map_join(paragraphs, &"<w:p><w:r><w:t>#{&1}</w:t></w:r></w:p>")
    initial = package(body, 0)
    padding = original_bytes - byte_size(initial)
    true = padding >= 0
    bytes = package(body, padding)
    ^original_bytes = byte_size(bytes)

    %{
      bytes: bytes,
      text: text,
      paragraphs: paragraphs,
      original_bytes: original_bytes,
      text_bytes: text_bytes,
      chunks: 32,
      needles: [
        {1, "firstcapacityneedle"},
        {16, "middlecapacityneedle"},
        {32, "lastcapacityneedle"}
      ]
    }
  end

  defp package(body, padding) do
    word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    relationship = "http://schemas.openxmlformats.org/package/2006/relationships"

    {:ok, {_, bytes}} =
      :zip.create(
        ~c"source.docx",
        [
          {~c"_rels/.rels",
           "<Relationships xmlns=\"#{relationship}\"><Relationship Id=\"main\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/><Relationship Id=\"thumbnail\" Type=\"#{relationship}/metadata/thumbnail\" Target=\"docProps/thumbnail.png\"/></Relationships>"},
          {~c"[Content_Types].xml",
           "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"png\" ContentType=\"image/png\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>"},
          {~c"word/document.xml",
           "<w:document xmlns:w=\"#{word}\"><w:body>#{body}</w:body></w:document>"},
          {~c"docProps/thumbnail.png", thumbnail(padding)}
        ],
        [:memory, {:compress, []}]
      )

    bytes
  end

  defp thumbnail(padding) do
    chunks = [
      {"IHDR", <<1::32, 1::32, 8, 6, 0, 0, 0>>},
      {"npAD", String.duplicate("p", padding)},
      {"IDAT", :zlib.compress(<<0, 0, 0, 0, 0>>)},
      {"IEND", <<>>}
    ]

    <<137, 80, 78, 71, 13, 10, 26, 10>> <>
      Enum.map_join(chunks, fn {type, data} ->
        <<byte_size(data)::32, type::binary, data::binary, :erlang.crc32(type <> data)::32>>
      end)
  end
end
