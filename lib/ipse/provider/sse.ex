defmodule Ipse.Provider.SSE do
  @moduledoc "Incremental SSE parser; chunk boundaries may split lines or UTF-8 bytes."
  alias Ipse.Provider.{Fragments, Lines}
  defstruct lines: %Lines{}, data: [], event: nil, data_bytes: 0, data_count: 0, events: 0

  def new, do: %__MODULE__{}

  def feed(state, chunk) do
    with {:ok, events, state} <-
           reduce(state, chunk, [], fn event, events -> {:ok, [event | events]} end),
         do: {Enum.reverse(events), state}
  end

  @doc "Processes each framed event before parsing later input; preserves callback observations on failure."
  def reduce(state, chunk, acc, fun) do
    handler = fn bytes, {state, acc} ->
      with :ok <- Fragments.check_deadline(acc),
           {:ok, state, events} <- line(state, bytes, []) do
        case events do
          [] ->
            {:ok, {state, acc}}

          [event] ->
            with {:ok, acc} <- fun.(event, acc),
                 :ok <- Fragments.check_deadline(acc),
                 do: {:ok, {state, acc}}
        end
      end
    end

    with :ok <- Fragments.check_deadline(acc),
         {:ok, parser, {state, acc}} <-
           Lines.reduce(state.lines, IO.iodata_to_binary(chunk), {state, acc}, handler),
         do: {:ok, acc, %{state | lines: parser}}
  end

  # An unterminated event is intentionally not dispatched at EOF.
  def finish(state), do: {[], state}

  defp line(state, "", events) do
    cond do
      state.data == [] ->
        {:ok, %{state | event: nil}, events}

      state.events >= 65_536 ->
        Fragments.error()

      true ->
        event = %{event: state.event, data: state.data |> Enum.reverse() |> Enum.join("\n")}

        {:ok,
         %{state | data: [], event: nil, data_bytes: 0, data_count: 0, events: state.events + 1},
         [event | events]}
    end
  end

  defp line(state, <<":", _::binary>>, events), do: {:ok, state, events}

  defp line(state, line, events) do
    [field | values] = :binary.split(line, ":")

    value =
      case values do
        [<<" ", value::binary>>] -> value
        [value] -> value
        [] -> ""
      end

    bytes = state.data_bytes + byte_size(value) + if(state.data_count > 0, do: 1, else: 0)

    case field do
      "data" when bytes <= 8_388_608 and state.data_count < 32_768 ->
        {:ok,
         %{
           state
           | data: [value | state.data],
             data_bytes: bytes,
             data_count: state.data_count + 1
         }, events}

      "data" ->
        Fragments.error()

      "event" ->
        {:ok, %{state | event: value}, events}

      _ ->
        {:ok, state, events}
    end
  end
end
