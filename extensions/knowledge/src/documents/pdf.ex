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
    9 => :embedded_objects_unsupported
  }

  def extract(bytes, %{path: path, sha256: digest}, limits)
      when is_binary(path) and is_binary(digest) do
    with true <- Path.type(path) == :absolute and Path.expand(path) == path,
         {:ok, %{type: :regular, links: 1, mode: mode, size: size}} <- File.lstat(path),
         true <-
           size <= 32 * 1024 * 1024 and Bitwise.band(mode, 0o022) == 0 and
             Bitwise.band(mode, 0o111) != 0,
         {:ok, executable} <-
           File.open(path, [:read, :binary], &IO.binread(&1, 32 * 1024 * 1024 + 1)),
         true <- is_binary(executable) and byte_size(executable) <= 32 * 1024 * 1024,
         true <- Base.encode16(:crypto.hash(:sha256, executable), case: :lower) == digest do
      port =
        Port.open({:spawn_executable, String.to_charlist(path)}, [
          :binary,
          :exit_status,
          :use_stdio,
          :stderr_to_stdout,
          :hide,
          args: []
        ])

      try do
        request =
          <<"IPDF0001", limits.max_pages::big-32, limits.max_expanded_bytes::big-32,
            limits.max_text_bytes::big-32, byte_size(bytes)::big-32, bytes::binary>>

        true = Port.command(port, request)

        receive_output(
          port,
          <<>>,
          limits,
          System.monotonic_time(:millisecond) + limits.timeout_ms
        )
      after
        if Port.info(port), do: Port.close(port)
      end
    else
      _ -> {:error, :pdf_parser_identity_unavailable}
    end
  rescue
    _ -> {:error, :pdf_parser_unavailable}
  end

  def extract(_, _, _), do: {:error, :pdf_parser_identity_unavailable}

  defp receive_output(port, bytes, limits, deadline) do
    receive do
      {^port, {:data, data}}
      when byte_size(bytes) + byte_size(data) <= limits.max_text_bytes + limits.max_pages * 9 + 13 ->
        receive_output(port, bytes <> data, limits, deadline)

      {^port, {:data, _}} ->
        {:error, :pdf_output_limit}

      {^port, {:exit_status, 0}} ->
        decode(bytes, limits)

      {^port, {:exit_status, _}} ->
        {:error, :pdf_resource_limit}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> {:error, :extraction_timeout}
    end
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
