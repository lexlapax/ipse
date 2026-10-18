defmodule Ipse.Provider.Lines do
  @moduledoc false
  alias Ipse.Provider.Fragments
  defstruct pending: %Fragments{}, lines: 0, skip_lf: false, mode: :sse

  def new(mode \\ :sse), do: %__MODULE__{mode: mode}

  def feed(state, bytes) when is_binary(bytes), do: split(state, bytes, [])
  def tail(state), do: Fragments.value(state.pending)

  defp split(state, "", lines), do: {:ok, Enum.reverse(lines), state}

  defp split(%{skip_lf: true} = state, <<"\n", rest::binary>>, lines),
    do: split(%{state | skip_lf: false}, rest, lines)

  defp split(%{skip_lf: true} = state, bytes, lines),
    do: split(%{state | skip_lf: false}, bytes, lines)

  defp split(state, bytes, lines) do
    separators = if state.mode == :sse, do: ["\n", "\r"], else: "\n"

    case :binary.match(bytes, separators) do
      :nomatch ->
        with {:ok, pending} <- Fragments.append(state.pending, bytes),
             do: {:ok, Enum.reverse(lines), %{state | pending: pending}}

      {index, 1} when state.lines < 131_072 ->
        <<line::binary-size(^index), separator, rest::binary>> = bytes

        with {:ok, pending} <- Fragments.append(state.pending, line) do
          next = %{
            state
            | pending: Fragments.new(),
              lines: state.lines + 1,
              skip_lf: state.mode == :sse and separator == ?\r
          }

          split(next, rest, [Fragments.value(pending) | lines])
        end

      _ ->
        Fragments.error()
    end
  end
end
