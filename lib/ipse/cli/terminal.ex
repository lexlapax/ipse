defmodule Ipse.CLI.Terminal do
  @moduledoc "Plain terminal rendering that leaves source values unchanged."

  @controls ~r/[\x{0000}-\x{0008}\x{000b}-\x{001f}\x{007f}-\x{009f}\x{034f}\p{Cf}\p{Zl}\p{Zp}]/u

  def puts(text), do: puts(:stdio, text)
  def puts(device, text), do: output(device, [escape(text), "\n"])
  def write(text), do: write(:stdio, text)
  def write(device, text), do: output(device, escape(text))

  def escape(text) when is_binary(text), do: escaped(text, []) |> IO.iodata_to_binary()

  defp output(device, bytes) do
    device =
      case device do
        :stdio -> :standard_io
        :stderr -> :standard_error
        _ -> device
      end

    case :io.getopts(device) do
      options when is_list(options) ->
        if options[:encoding] == :latin1,
          do: IO.binwrite(device, bytes),
          else: IO.write(device, bytes)

      _ ->
        IO.write(device, bytes)
    end
  end

  defp escaped(text, acc) do
    case :unicode.characters_to_binary(text) do
      valid when is_binary(valid) ->
        Enum.reverse([escape_valid(valid) | acc])

      {_status, valid, <<byte, rest::binary>>} ->
        escaped(rest, [[escape_valid(valid), "\\x", hex(byte, 2)] | acc])
    end
  end

  defp escape_valid(text) do
    Regex.replace(@controls, text, fn <<codepoint::utf8>> -> unicode_escape(codepoint) end)
  end

  defp unicode_escape(codepoint) when codepoint <= 0xFFFF,
    do: "\\u" <> hex(codepoint, 4)

  defp unicode_escape(codepoint) do
    offset = codepoint - 0x10000
    unicode_escape(0xD800 + div(offset, 1024)) <> unicode_escape(0xDC00 + rem(offset, 1024))
  end

  defp hex(value, width),
    do: value |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(width, "0")
end
