defmodule Ipse.Provider.Stream do
  @moduledoc "Bounded fragments, line framing and SSE events across arbitrary byte chunks."
  @bytes 8_388_608
  @fragments 32_768
  defstruct parts: [], bytes: 0, count: 0

  defmodule LineState do
    @moduledoc false
    defstruct pending: %Ipse.Provider.Stream{}, lines: 0, skip_lf: false, mode: :sse
  end

  defmodule EventState do
    @moduledoc false
    defstruct lines: %Ipse.Provider.Stream.LineState{},
              data: [],
              event: nil,
              data_bytes: 0,
              data_count: 0,
              events: 0
  end

  def new_buffer, do: %__MODULE__{}
  def error, do: {:error, "Provider stream limit exceeded; the response is incomplete."}

  def append_buffer(%__MODULE__{} = state, ""), do: {:ok, state}

  def append_buffer(%__MODULE__{} = state, bytes) when is_binary(bytes) do
    if state.bytes + byte_size(bytes) <= @bytes and state.count < @fragments do
      {:ok,
       %{
         state
         | parts: [bytes | state.parts],
           bytes: state.bytes + byte_size(bytes),
           count: state.count + 1
       }}
    else
      error()
    end
  end

  def append_buffer(_, _), do: error()

  def buffer_value(%__MODULE__{parts: parts}),
    do: parts |> Enum.reverse() |> IO.iodata_to_binary()

  def update_field(fields, key, value) when is_map(fields) do
    with {:ok, previous} <- coerce_buffer(Map.get(fields, key, "")),
         {:ok, next} <- append_buffer(previous, value) do
      {:ok, Map.put(fields, key, next)}
    end
  end

  def materialize_fields(fields) do
    Map.new(fields, fn
      {key, %__MODULE__{} = value} -> {key, buffer_value(value)}
      pair -> pair
    end)
  end

  def tick(state) do
    count = Map.get(state, :stream_events, 0)

    with :ok <- check_deadline(state) do
      if count < 65_536, do: {:ok, Map.put(state, :stream_events, count + 1)}, else: error()
    end
  end

  def check_deadline(%{stream_deadline: deadline}) when is_integer(deadline) do
    if System.monotonic_time(:millisecond) < deadline,
      do: :ok,
      else: {:error, "Provider request timed out."}
  end

  def check_deadline(_), do: :ok

  def index?(index), do: is_integer(index) and index in 0..255

  def items?(items, call_type) when is_list(items) do
    bounded = Enum.take(items, 257)

    length(bounded) <= 256 and Enum.all?(bounded, &is_map/1) and
      Enum.count(bounded, &(&1["type"] == call_type)) <= 32
  end

  def items?(_, _), do: false

  defp coerce_buffer(%__MODULE__{} = state), do: {:ok, state}
  defp coerce_buffer(value) when is_binary(value), do: append_buffer(new_buffer(), value)
  defp coerce_buffer(_), do: error()

  def new_lines(mode \\ :sse), do: %Ipse.Provider.Stream.LineState{mode: mode}

  def reduce_lines(state, bytes, acc, fun) when is_binary(bytes) and is_function(fun, 2),
    do: split_lines(state, bytes, acc, fun)

  def line_tail(state), do: buffer_value(state.pending)

  def finish_lines(%{pending: %__MODULE__{bytes: 0}} = state), do: {:ok, nil, state}

  def finish_lines(%{lines: count} = state) when count < 131_072,
    do: {:ok, line_tail(state), %{state | lines: count + 1, pending: new_buffer()}}

  def finish_lines(_), do: error()

  defp split_lines(state, "", acc, _), do: {:ok, state, acc}

  defp split_lines(%{skip_lf: true} = state, <<"\n", rest::binary>>, acc, fun),
    do: split_lines(%{state | skip_lf: false}, rest, acc, fun)

  defp split_lines(%{skip_lf: true} = state, bytes, acc, fun),
    do: split_lines(%{state | skip_lf: false}, bytes, acc, fun)

  defp split_lines(state, bytes, acc, fun) do
    separators = if state.mode == :sse, do: ["\n", "\r"], else: "\n"

    case :binary.match(bytes, separators) do
      :nomatch ->
        with {:ok, pending} <- append_buffer(state.pending, bytes),
             do: {:ok, %{state | pending: pending}, acc}

      {index, 1} when state.lines < 131_072 ->
        <<line::binary-size(^index), separator, rest::binary>> = bytes

        with {:ok, pending} <- append_buffer(state.pending, line) do
          next = %{
            state
            | pending: new_buffer(),
              lines: state.lines + 1,
              skip_lf: state.mode == :sse and separator == ?\r
          }

          with {:ok, acc} <- fun.(buffer_value(pending), acc),
               do: split_lines(next, rest, acc, fun)
        end

      _ ->
        error()
    end
  end

  def new_sse, do: %Ipse.Provider.Stream.EventState{}

  def feed_sse(state, chunk) do
    with {:ok, events, state} <-
           reduce_sse(state, chunk, [], fn event, events -> {:ok, [event | events]} end),
         do: {Enum.reverse(events), state}
  end

  @doc "Processes each framed event before parsing later input; preserves callback observations on failure."
  def reduce_sse(state, chunk, acc, fun) do
    handler = fn bytes, {state, acc} ->
      with :ok <- check_deadline(acc),
           {:ok, state, events} <- sse_line(state, bytes, []) do
        case events do
          [] ->
            {:ok, {state, acc}}

          [event] ->
            with {:ok, acc} <- fun.(event, acc),
                 :ok <- check_deadline(acc),
                 do: {:ok, {state, acc}}
        end
      end
    end

    with :ok <- check_deadline(acc),
         {:ok, parser, {state, acc}} <-
           reduce_lines(state.lines, IO.iodata_to_binary(chunk), {state, acc}, handler),
         do: {:ok, acc, %{state | lines: parser}}
  end

  # An unterminated event is intentionally not dispatched at EOF.
  def finish_sse(state), do: {[], state}

  defp sse_line(state, "", events) do
    cond do
      state.data == [] ->
        {:ok, %{state | event: nil}, events}

      state.events >= 65_536 ->
        error()

      true ->
        event = %{event: state.event, data: state.data |> Enum.reverse() |> Enum.join("\n")}

        {:ok,
         %{state | data: [], event: nil, data_bytes: 0, data_count: 0, events: state.events + 1},
         [event | events]}
    end
  end

  defp sse_line(state, <<":", _::binary>>, events), do: {:ok, state, events}

  defp sse_line(state, line, events) do
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
        error()

      "event" ->
        {:ok, %{state | event: value}, events}

      _ ->
        {:ok, state, events}
    end
  end
end
