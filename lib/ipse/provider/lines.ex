defmodule Ipse.Provider.Lines do
  @moduledoc false
  alias Ipse.Provider.Fragments
  defstruct pending: %Fragments{}, lines: 0, skip_lf: false, mode: :sse

  def new(mode \\ :sse), do: %__MODULE__{mode: mode}

  def feed(state, bytes) when is_binary(bytes) do
    with {:ok, state, lines} <-
           reduce(state, bytes, [], fn line, lines -> {:ok, [line | lines]} end),
         do: {:ok, Enum.reverse(lines), state}
  end

  def reduce(state, bytes, acc, fun) when is_binary(bytes) and is_function(fun, 2),
    do: split(state, bytes, acc, fun)

  def tail(state), do: Fragments.value(state.pending)

  def finish(%{pending: %Fragments{bytes: 0}} = state), do: {:ok, nil, state}

  def finish(%{lines: count} = state) when count < 131_072,
    do: {:ok, tail(state), %{state | lines: count + 1, pending: Fragments.new()}}

  def finish(_), do: Fragments.error()

  defp split(state, "", acc, _), do: {:ok, state, acc}

  defp split(%{skip_lf: true} = state, <<"\n", rest::binary>>, acc, fun),
    do: split(%{state | skip_lf: false}, rest, acc, fun)

  defp split(%{skip_lf: true} = state, bytes, acc, fun),
    do: split(%{state | skip_lf: false}, bytes, acc, fun)

  defp split(state, bytes, acc, fun) do
    separators = if state.mode == :sse, do: ["\n", "\r"], else: "\n"

    case :binary.match(bytes, separators) do
      :nomatch ->
        with {:ok, pending} <- Fragments.append(state.pending, bytes),
             do: {:ok, %{state | pending: pending}, acc}

      {index, 1} when state.lines < 131_072 ->
        <<line::binary-size(^index), separator, rest::binary>> = bytes

        with {:ok, pending} <- Fragments.append(state.pending, line) do
          next = %{
            state
            | pending: Fragments.new(),
              lines: state.lines + 1,
              skip_lf: state.mode == :sse and separator == ?\r
          }

          with {:ok, acc} <- fun.(Fragments.value(pending), acc),
               do: split(next, rest, acc, fun)
        end

      _ ->
        Fragments.error()
    end
  end
end
