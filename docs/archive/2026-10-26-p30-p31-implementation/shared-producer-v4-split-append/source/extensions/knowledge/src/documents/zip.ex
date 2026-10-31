defmodule IpseKnowledge.Documents.Zip do
  @moduledoc false
  import Bitwise

  # OTP owns central-directory decoding. Its whole-entry zip_get allocation is
  # unsuitable for forged expansion lengths, so payloads use safeInflate instead.
  def entries(bytes, limits) do
    case :zip.list_dir(bytes) do
      {:ok, [_comment | entries]} when length(entries) <= limits.max_entries ->
        parsed = Enum.map(entries, &entry/1)
        names = Enum.map(parsed, & &1.name)
        Enum.each(parsed, &header(bytes, &1))

        cond do
          length(Enum.uniq(names)) != length(names) ->
            fail(:duplicate_zip_entry)

          Enum.sum(Enum.map(parsed, & &1.size)) > limits.max_expanded_bytes ->
            fail(:expansion_limit)

          true ->
            parsed
        end

      {:ok, _} ->
        fail(:zip_entry_limit)

      _ ->
        fail(:malformed_zip)
    end
  end

  defp entry({:zip_file, name, info, _, offset, compressed}) do
    name = List.to_string(name)
    size = elem(info, 1)
    type = elem(info, 2)

    unless String.valid?(name) and byte_size(name) <= 1024 and
             not String.contains?(name, ["\\", ":", <<0>>]) and
             not String.starts_with?(name, "/") and
             Enum.all?(
               String.split(String.trim_trailing(name, "/"), "/"),
               &(&1 not in ["", ".", ".."])
             ) and
             type in [:regular, :directory] and is_integer(size) and size >= 0 and
             is_integer(offset) and offset >= 0 and is_integer(compressed) and compressed >= 0,
           do: fail(:unsafe_zip_entry)

    %{name: name, size: size, compressed: compressed, offset: offset}
  end

  defp entry(_), do: fail(:malformed_zip)

  def read(bytes, entry, remaining) do
    {method, crc, descriptor?, data, tail} = header(bytes, entry)
    limit = min(entry.size, remaining)
    output = if method == 0, do: stored(data, limit), else: inflate(data, limit)
    if byte_size(output) != entry.size, do: fail(:inconsistent_zip_entry)
    expected = if descriptor?, do: descriptor(tail, entry), else: crc
    if :erlang.crc32(output) != expected, do: fail(:zip_checksum)
    output
  end

  defp header(bytes, entry) do
    offset = entry.offset
    compressed_size = entry.compressed
    <<_::binary-size(^offset), header::binary>> = bytes

    case header do
      <<0x04034B50::little-32, _version::little-16, flags::little-16, method::little-16,
        _time::little-16, _date::little-16, crc::little-32, compressed::little-32,
        size::little-32, name_size::little-16, extra_size::little-16, rest::binary>> ->
        if (flags &&& 1) != 0, do: fail(:encrypted_document)

        if (flags &&& bnot(0x080E)) != 0 or method not in [0, 8],
          do: fail(:unsupported_zip_method)

        <<name::binary-size(^name_size), _::binary-size(^extra_size),
          data::binary-size(^compressed_size), tail::binary>> = rest

        if name != entry.name, do: fail(:inconsistent_zip_entry)
        descriptor? = (flags &&& 8) != 0

        unless descriptor? or (compressed == entry.compressed and size == entry.size),
          do: fail(:inconsistent_zip_entry)

        {method, crc, descriptor?, data, tail}

      _ ->
        fail(:malformed_zip)
    end
  end

  defp descriptor(<<0x08074B50::little-32, rest::binary>>, entry), do: descriptor(rest, entry)

  defp descriptor(<<crc::little-32, compressed::little-32, size::little-32, _::binary>>, entry)
       when compressed == entry.compressed and size == entry.size,
       do: crc

  defp descriptor(_, _), do: fail(:inconsistent_zip_entry)

  defp stored(data, limit) do
    if byte_size(data) > limit, do: fail(:expansion_limit)
    data
  end

  defp inflate(data, limit) do
    stream = :zlib.open()

    try do
      :ok = :zlib.inflateInit(stream, -15)
      result = drain(stream, data, limit, [], 0)
      :ok = :zlib.inflateEnd(stream)
      result
    after
      :zlib.close(stream)
    end
  end

  defp drain(stream, input, limit, acc, size) do
    {status, output} = :zlib.safeInflate(stream, input)
    size = size + IO.iodata_length(output)
    if size > limit, do: fail(:expansion_limit)

    case status do
      :continue -> drain(stream, <<>>, limit, [output | acc], size)
      :finished -> acc |> then(&IO.iodata_to_binary(Enum.reverse([output | &1])))
    end
  end

  defp fail(code), do: throw({:document_error, code})
end
