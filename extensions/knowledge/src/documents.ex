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
  def version("docx"), do: "ipse-documents-v3"
  def version(format) when format in ~w(text markdown pdf), do: version()

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
