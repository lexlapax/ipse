defmodule Ipse.Provider.Fragments do
  @moduledoc false
  @bytes 8_388_608
  @fragments 32_768
  defstruct parts: [], bytes: 0, count: 0

  def new, do: %__MODULE__{}
  def error, do: {:error, "Provider stream limit exceeded; the response is incomplete."}

  def append(%__MODULE__{} = state, ""), do: {:ok, state}

  def append(%__MODULE__{} = state, bytes) when is_binary(bytes) do
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

  def append(_, _), do: error()
  def value(%__MODULE__{parts: parts}), do: parts |> Enum.reverse() |> IO.iodata_to_binary()

  def update(fields, key, value) when is_map(fields) do
    with {:ok, previous} <- buffer(Map.get(fields, key, "")),
         {:ok, next} <- append(previous, value) do
      {:ok, Map.put(fields, key, next)}
    end
  end

  def materialize(fields) do
    Map.new(fields, fn
      {key, %__MODULE__{} = value} -> {key, value(value)}
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

  defp buffer(%__MODULE__{} = state), do: {:ok, state}
  defp buffer(value) when is_binary(value), do: append(new(), value)
  defp buffer(_), do: error()
end
