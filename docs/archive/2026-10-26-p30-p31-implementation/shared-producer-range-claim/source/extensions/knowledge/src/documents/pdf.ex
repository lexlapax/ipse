defmodule IpseKnowledge.Documents.Pdf do
  @moduledoc false
  @errors %{
    2 => :image_only_or_empty_pdf,
    3 => :encrypted_document,
    4 => :malformed_pdf,
    5 => :pdf_resource_limit,
    6 => :pdf_protocol_error,
    7 => :page_limit,
    8 => :text_limit,
    9 => :embedded_objects_unsupported,
    10 => :pdf_resource_backend_unavailable
  }

  def extract(bytes, descriptor, limits) do
    case IpseKnowledge.Documents.ParserStage.run(bytes, descriptor, limits) do
      {:ok, output} -> decode(output, limits)
      error -> error
    end
  rescue
    _ -> {:error, :pdf_parser_unavailable}
  end

  defp decode(<<"IPDO0001", status, count::big-32, rest::binary>>, limits)
       when status in [0, 1] and count > 0 and count <= limits.max_pages do
    case pages(rest, count, 1, [], [], 0, limits) do
      {:ok, segments, warnings} ->
        partial? = warnings != []

        if status == 1 == partial? and segments != [] do
          {:ok,
           %{
             "format" => "pdf",
             "experimental" => true,
             "status" => if(partial?, do: "partial", else: "complete"),
             "segments" => segments,
             "warnings" => [%{"code" => "experimental_pdf_reading_order"} | warnings]
           }}
        else
          {:error, :pdf_protocol_error}
        end

      error ->
        error
    end
  end

  defp decode(<<"IPDO0001", status, 0::big-32>>, _),
    do: {:error, Map.get(@errors, status, :pdf_protocol_error)}

  defp decode(_, _), do: {:error, :pdf_protocol_error}

  defp pages(<<>>, 0, _, segments, warnings, _, _),
    do: {:ok, Enum.reverse(segments), Enum.reverse(warnings)}

  defp pages(
         <<number::big-32, status, size::big-32, rest::binary>>,
         remaining,
         number,
         segments,
         warnings,
         text_size,
         limits
       )
       when remaining > 0 and status in [0, 1, 2] and size <= byte_size(rest) do
    <<text::binary-size(^size), rest::binary>> = rest
    total = text_size + size

    cond do
      total > limits.max_text_bytes ->
        {:error, :text_limit}

      status == 0 and length(segments) >= limits.max_segments ->
        {:error, :segment_limit}

      status == 0 and size > 0 and String.valid?(text) ->
        segment = %{"text" => text, "locator" => %{"kind" => "page", "page" => number}}
        pages(rest, remaining - 1, number + 1, [segment | segments], warnings, total, limits)

      status in [1, 2] and size == 0 ->
        warning = %{
          "code" => if(status == 1, do: "page_has_no_text", else: "page_extraction_failed"),
          "page" => number
        }

        pages(rest, remaining - 1, number + 1, segments, [warning | warnings], total, limits)

      true ->
        {:error, :pdf_protocol_error}
    end
  end

  defp pages(_, _, _, _, _, _, _), do: {:error, :pdf_protocol_error}
end
