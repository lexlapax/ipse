defmodule Ipse.Provider.SSE do
  @moduledoc "Incremental SSE parser; chunk boundaries may split lines or UTF-8 bytes."
  defstruct buffer: "", data: [], event: nil, skip_lf: false

  def new, do: %__MODULE__{}

  def feed(state, chunk) do
    parse(%{state | buffer: state.buffer <> IO.iodata_to_binary(chunk)}, [])
  end

  # An unterminated event is intentionally not dispatched at EOF.
  def finish(state), do: {[], state}

  defp parse(%{skip_lf: true, buffer: ""} = state, events), do: {Enum.reverse(events), state}

  defp parse(%{skip_lf: true, buffer: <<"\n", rest::binary>>} = state, events),
    do: parse(%{state | skip_lf: false, buffer: rest}, events)

  defp parse(%{skip_lf: true} = state, events), do: parse(%{state | skip_lf: false}, events)

  defp parse(state, events) do
    case :binary.match(state.buffer, ["\n", "\r"]) do
      :nomatch ->
        {Enum.reverse(events), state}

      {index, 1} ->
        <<line::binary-size(index), separator, rest::binary>> = state.buffer
        {state, events} = line(%{state | buffer: rest, skip_lf: separator == ?\r}, line, events)
        parse(state, events)
    end
  end

  defp line(state, "", events) do
    events =
      if state.data == [],
        do: events,
        else: [
          %{event: state.event, data: state.data |> Enum.reverse() |> Enum.join("\n")} | events
        ]

    {%{state | data: [], event: nil}, events}
  end

  defp line(state, <<":", _::binary>>, events), do: {state, events}

  defp line(state, line, events) do
    [field | values] = :binary.split(line, ":")

    value =
      case values do
        [<<" ", value::binary>>] -> value
        [value] -> value
        [] -> ""
      end

    state =
      case field do
        "data" -> %{state | data: [value | state.data]}
        "event" -> %{state | event: value}
        _ -> state
      end

    {state, events}
  end
end
