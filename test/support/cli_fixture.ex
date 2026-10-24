defmodule Ipse.CLITest.IOFixture do
  use GenServer

  def start_link(owner), do: GenServer.start_link(__MODULE__, owner)
  def feed(pid, line), do: GenServer.call(pid, {:feed, line})
  def output(pid), do: GenServer.call(pid, :output)
  def pending?(pid), do: GenServer.call(pid, :pending?)

  @impl true
  def init(owner), do: {:ok, %{owner: owner, output: [], lines: [], pending: nil}}

  @impl true
  def handle_call({:feed, line}, _from, %{pending: {reader, reply_as}} = state) do
    send(reader, {:io_reply, reply_as, line_reply(line)})
    send(state.owner, {:io_line_fed, self(), line})
    {:reply, :ok, %{state | pending: nil}}
  end

  def handle_call({:feed, line}, _from, state) do
    send(state.owner, {:io_line_fed, self(), line})
    {:reply, :ok, %{state | lines: state.lines ++ [line]}}
  end

  def handle_call(:output, _from, state),
    do: {:reply, IO.iodata_to_binary(Enum.reverse(state.output)), state}

  def handle_call(:pending?, _from, state), do: {:reply, state.pending != nil, state}

  @impl true
  def handle_info({:io_request, from, reply_as, {:get_line, _encoding, prompt}}, state) do
    send(state.owner, {:io_waiting, self(), prompt})
    state = append(state, prompt)

    case state.lines do
      [line | rest] ->
        send(from, {:io_reply, reply_as, line_reply(line)})
        {:noreply, %{state | lines: rest}}

      [] ->
        {:noreply, %{state | pending: {from, reply_as}}}
    end
  end

  def handle_info({:io_request, from, reply_as, {:put_chars, _encoding, chars}}, state) do
    send(from, {:io_reply, reply_as, :ok})
    {:noreply, append(state, chars)}
  end

  def handle_info(
        {:io_request, from, reply_as, {:put_chars, _encoding, module, function, args}},
        state
      ) do
    send(from, {:io_reply, reply_as, :ok})
    {:noreply, append(state, apply(module, function, args))}
  end

  def handle_info({:io_request, from, reply_as, {:get_geometry, :columns}}, state) do
    send(from, {:io_reply, reply_as, 80})
    {:noreply, state}
  end

  def handle_info({:io_request, from, reply_as, request}, state) do
    send(from, {:io_reply, reply_as, {:error, {:unsupported_io_request, request}}})
    {:noreply, state}
  end

  defp append(state, chars) do
    text = IO.iodata_to_binary(chars)
    send(state.owner, {:io_output, self(), text})
    %{state | output: [text | state.output]}
  end

  defp line_reply(:eof), do: :eof
  defp line_reply(text) when is_binary(text), do: text <> "\n"
end
