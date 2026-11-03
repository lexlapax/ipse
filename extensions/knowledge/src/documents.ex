defmodule IpseKnowledge.Documents do
  @moduledoc """
  Bounded extraction of already acquired document bytes. This module never opens
  document paths, follows relationships, runs content, or grants fetch authority.
  DOCX includes insertions and excludes deletions and hidden runs using bounded
  style inheritance and direct properties. Ambiguous visibility is refused;
  unsupported rendering is marked as partial.
  Locators refer to this extraction version and the original binary hash.
  """
  alias IpseKnowledge.Documents.{Docx, Pdf}

  @limits %{
    max_input_bytes: 16 * 1024 * 1024,
    max_expanded_bytes: 32 * 1024 * 1024,
    max_text_bytes: 1024 * 1024,
    max_entries: 1024,
    max_segments: 10_000,
    max_pages: 256,
    timeout_ms: 5000
  }
  @text [
    ""
    | ~w(.txt .md .markdown .ex .exs .erl .hrl .rs .c .h .cpp .hpp .java .kt .kts .swift .js .jsx .ts .tsx .py .rb .go .r .jl .lua .pl .pm .sh .bash .zsh .fish .ps1 .json .jsonl .yaml .yml .toml .xml .html .htm .css .scss .vue .svelte .sql .csv .tsv .log .ini .cfg .conf .lock .cmake .gradle)
  ]

  def limits, do: @limits
  @doc "Legacy shared recipe version, retained for text, Markdown and PDF."
  def version, do: "ipse-documents-v2"

  @doc "Return the immutable extraction recipe selected for a result format."
  def version("docx"), do: "ipse-documents-v16"
  def version(format) when format in ~w(text markdown pdf), do: version()

  @doc "Project an extracted DOCX into the bounded explicit source-put contract."
  def source_payload(document), do: source_payload(document, 8192)
  def source_payload(document, maximum), do: source_payload(document, maximum, 1)

  @doc "Build a bounded source, packing short paragraph runs with exact original byte maps."
  def source_payload(%{"format" => "docx", "segments" => segments} = document, maximum, chunking)
      when maximum in [8192, 65_536] and
             chunking in [1, 2] and
             is_list(segments) and length(segments) in 1..10_000 do
    chunk_bytes = if chunking == 2, do: 4096, else: 2048

    segments =
      if length(segments) > 32 and
           document["extraction_version"] in [
             "ipse-documents-v14",
             "ipse-documents-v15",
             version("docx")
           ],
         do: pack_blocks(segments, chunk_bytes, document["extraction_version"]),
         else: segments

    if length(segments) > 32 do
      {:error, :document_source_limit}
    else
      {parts, spans, _offset} =
        Enum.reduce(segments, {[], [], 0}, fn segment, {parts, spans, offset} ->
          text = segment["text"]
          start = offset + if(parts == [], do: 0, else: 1)

          span = %{
            "start_byte" => start,
            "end_byte" => start + byte_size(text),
            "text_sha256" => digest(text),
            "locator" => segment["locator"]
          }

          {parts ++ [text], spans ++ [span], start + byte_size(text)}
        end)

      text = Enum.join(parts, "\n")

      receipt = %{
        "kind" => "document_extraction",
        "version" => 1,
        "format" => "docx",
        "original_sha256" => document["original_sha256"],
        "original_bytes" => document["original_bytes"],
        "extraction_version" => document["extraction_version"],
        "status" => document["status"],
        "warnings" => document["warnings"],
        "segments" => spans
      }

      chunks = Enum.sum(Enum.map(parts, &source_chunk_count(&1, chunk_bytes)))

      if text != "" and byte_size(text) <= maximum and length(segments) <= 32 and chunks <= 32 and
           byte_size(IO.iodata_to_binary(JSON.encode!(receipt))) <= 16_384 do
        {:ok, %{"text" => text, "document" => receipt}}
      else
        {:error, :document_source_limit}
      end
    end
  rescue
    _ -> {:error, :invalid_document_extraction}
  end

  def source_payload(%{"format" => "docx"}, _, _), do: {:error, :document_source_limit}
  def source_payload(_, _, _), do: {:error, :document_format_unsupported}

  defp pack_blocks(segments, maximum, recipe) do
    {groups, pending} =
      Enum.reduce(segments, {[], nil}, fn segment, {groups, pending} ->
        locator = segment["locator"]
        base = if is_map(locator), do: Map.delete(locator, "numbering"), else: nil

        plain =
          is_map(base) and
            (not Map.has_key?(locator, "numbering") or recipe == "ipse-documents-v16") and
            ((Enum.sort(Map.keys(base)) == ~w(kind paragraph part) and
                base["kind"] == "paragraph") or
               (Enum.sort(Map.keys(base)) == ~w(cell kind paragraph part row table) and
                  base["kind"] == "table_cell"))

        row =
          [locator["paragraph"], byte_size(segment["text"])] ++
            if(locator["kind"] == "table_cell",
              do: Enum.map(~w(table row cell), &locator[&1]),
              else: []
            ) ++ if(Map.has_key?(locator, "numbering"), do: [locator["numbering"]], else: [])

        fits =
          plain and pending != nil and pending.part == locator["part"] and
            locator["paragraph"] > pending.last and length(pending.rows) < 64 and
            pending.bytes + 1 + byte_size(segment["text"]) <= maximum

        if fits do
          {groups,
           %{
             pending
             | texts: [segment["text"] | pending.texts],
               rows: [row | pending.rows],
               bytes: pending.bytes + 1 + byte_size(segment["text"]),
               last: locator["paragraph"]
           }}
        else
          groups = flush_blocks(groups, pending)

          if plain do
            {groups,
             %{
               part: locator["part"],
               last: locator["paragraph"],
               rows: [row],
               texts: [segment["text"]],
               bytes: byte_size(segment["text"]),
               original: segment
             }}
          else
            {[segment | groups], nil}
          end
        end
      end)

    flush_blocks(groups, pending) |> Enum.reverse()
  end

  defp flush_blocks(groups, nil), do: groups
  defp flush_blocks(groups, %{rows: [_], original: original}), do: [original | groups]

  defp flush_blocks(groups, pending) do
    [
      %{
        "text" => pending.texts |> Enum.reverse() |> Enum.join("\n"),
        "locator" => %{
          "kind" => "block_group",
          "part" => pending.part,
          "blocks" => Enum.reverse(pending.rows)
        }
      }
      | groups
    ]
  end

  defp source_chunk_count(text, maximum) do
    Stream.unfold(text, fn
      "" ->
        nil

      rest ->
        prefix = binary_part(rest, 0, min(byte_size(rest), maximum))

        bytes =
          case :unicode.characters_to_binary(prefix, :utf8, :utf8) do
            binary when is_binary(binary) -> byte_size(binary)
            {:incomplete, binary, _} -> byte_size(binary)
            _ -> raise ArgumentError, "Invalid source text"
          end

        {1, binary_part(rest, bytes, byte_size(rest) - bytes)}
    end)
    |> Enum.take(33)
    |> Enum.sum()
  end

  defp digest(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  @doc """
  Explicit experimental PDF selection. The host must admit the parser's absolute
  path and SHA-256 from protected configuration, outside untrusted workspaces.
  Ordinary `extract/3` keeps PDF disabled even when a parser is installed.
  """
  def extract_pdf(bytes, parser, options \\ []) do
    with true <- is_binary(bytes) and is_list(options),
         {:ok, limits} <- admitted_limits(options),
         true <- byte_size(bytes) <= limits.max_input_bytes do
      owned(
        fn ->
          case Pdf.extract(bytes, parser, limits) do
            {:ok, document} -> {:ok, metadata(document, bytes)}
            error -> error
          end
        end,
        limits.timeout_ms
      )
    else
      false -> {:error, :invalid_or_oversized_input}
      error -> error
    end
  end

  @doc "Options may lower, but never raise, the published resource ceilings."
  def extract(bytes, filename, options \\ []) do
    with true <- is_binary(bytes) and is_binary(filename) and is_list(options),
         {:ok, limits} <- admitted_limits(options),
         true <- byte_size(bytes) <= limits.max_input_bytes do
      owned(fn -> extract_bytes(bytes, filename, limits) end, limits.timeout_ms)
    else
      false -> {:error, :invalid_or_oversized_input}
      error -> error
    end
  end

  defp admitted_limits(options) do
    if Keyword.keyword?(options) and length(options) == map_size(Map.new(options)) and
         Enum.all?(options, fn {key, value} ->
           is_integer(value) and value > 0 and value <= Map.get(@limits, key, 0)
         end) do
      {:ok, Map.merge(@limits, Map.new(options))}
    else
      {:error, :invalid_limits}
    end
  end

  defp extract_bytes(bytes, filename, limits) do
    format = filename |> Path.extname() |> String.downcase()

    result =
      cond do
        format in @text ->
          text(bytes, format, limits)

        format == ".docx" and
            String.starts_with?(bytes, <<0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1>>) ->
          {:error, :compound_word_container_unsupported}

        format == ".docx" ->
          Docx.extract(bytes, limits)

        format == ".pdf" ->
          {:error, :pdf_experimental_unavailable}

        format == ".doc" ->
          {:error, :legacy_word_unsupported}

        true ->
          {:error, :unsupported_format}
      end

    case result do
      {:ok, document} ->
        {:ok, metadata(document, bytes)}

      error ->
        error
    end
  end

  defp metadata(document, bytes) do
    Map.merge(document, %{
      "original_sha256" => Base.encode16(:crypto.hash(:sha256, bytes), case: :lower),
      "original_bytes" => byte_size(bytes),
      "extraction_version" => version(document["format"])
    })
  end

  defp text(bytes, extension, limits) do
    cond do
      not String.valid?(bytes) ->
        {:error, :invalid_utf8}

      binary_text?(bytes) ->
        {:error, :binary_input}

      String.starts_with?(bytes, "%PDF-") ->
        {:error, :format_mismatch}

      byte_size(bytes) > limits.max_text_bytes ->
        {:error, :text_limit}

      true ->
        lines = String.split(bytes, "\n")

        if length(lines) <= limits.max_segments do
          {segments, _offset} =
            lines
            |> Enum.with_index(1)
            |> Enum.map_reduce(0, fn {line, number}, offset ->
              {%{
                 "text" => line,
                 "locator" => %{
                   "kind" => "line",
                   "line" => number,
                   "start_byte" => offset,
                   "end_byte" => offset + byte_size(line)
                 }
               }, offset + byte_size(line) + 1}
            end)

          {:ok,
           %{
             "format" => if(extension in ~w(.md .markdown), do: "markdown", else: "text"),
             "status" => "complete",
             "segments" => segments,
             "warnings" => []
           }}
        else
          {:error, :segment_limit}
        end
    end
  end

  defp binary_text?(bytes) do
    Regex.match?(~r/[\x00-\x08\x0e-\x1f\x7f]/, bytes)
  end

  defp owned(function, timeout) do
    owner = self()
    reference = make_ref()

    {worker, monitor} =
      :erlang.spawn_opt(
        fn ->
          :proc_lib.set_label({__MODULE__, :worker})

          result =
            try do
              function.()
            rescue
              _ -> {:error, :malformed_document}
            catch
              {:document_error, code} -> {:error, code}
              _, _ -> {:error, :malformed_document}
            end

          send(owner, {reference, result})
        end,
        [:monitor, {:max_heap_size, %{size: 8_000_000, kill: true, error_logger: false}}]
      )

    # A separate monitor remains responsive while the parser performs CPU work.
    spawn(fn ->
      :proc_lib.set_label({__MODULE__, :guardian})
      owner_monitor = Process.monitor(owner)
      worker_monitor = Process.monitor(worker)

      receive do
        {:DOWN, ^owner_monitor, :process, _, _} -> Process.exit(worker, :kill)
        {:DOWN, ^worker_monitor, :process, _, _} -> :ok
      end
    end)

    receive do
      {^reference, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, ^worker, _} ->
        {:error, :extraction_resource_limit}
    after
      timeout ->
        Process.exit(worker, :kill)

        receive do
          {:DOWN, ^monitor, :process, ^worker, _} -> :ok
        end

        receive do
          {^reference, _} -> :ok
        after
          0 -> :ok
        end

        {:error, :extraction_timeout}
    end
  end
end
