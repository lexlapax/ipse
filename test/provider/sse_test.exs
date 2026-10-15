defmodule Ipse.Provider.SSETest do
  use ExUnit.Case, async: true
  alias Ipse.Provider.SSE

  test "arbitrary byte boundaries preserve UTF-8, CRLF, comments and multiline data" do
    wire = ": ping\r\nevent: message\r\ndata: héllo\r\ndata: second\r\n\r\ndata: last\n\n"
    expected = [%{event: "message", data: "héllo\nsecond"}, %{event: nil, data: "last"}]

    for size <- 1..byte_size(wire) do
      chunks = chunks(wire, size)

      {events, _} =
        Enum.reduce(chunks, {[], SSE.new()}, fn chunk, {events, state} ->
          {new, state} = SSE.feed(state, chunk)
          {events ++ new, state}
        end)

      assert events == expected
    end
  end

  test "CR-only delimiters dispatch; EOF does not invent an event" do
    assert {[%{event: nil, data: "yes"}], _} = SSE.feed(SSE.new(), "data: yes\r\r")
    {[], state} = SSE.feed(SSE.new(), "data: truncated")
    assert {[], ^state} = SSE.finish(state)
  end

  defp chunks("", _), do: []
  defp chunks(binary, size) when byte_size(binary) <= size, do: [binary]

  defp chunks(binary, size) do
    <<head::binary-size(size), rest::binary>> = binary
    [head | chunks(rest, size)]
  end
end
