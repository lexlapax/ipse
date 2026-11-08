defmodule Ipse.Runner.TerminalInput do
  @moduledoc """
  Keeps the VM's own standard-input reader off a terminal owned by native helpers.

  Native operator helpers inherit the VM's descriptors 0 and 1 and read the
  terminal directly. The OTP 27 `-noshell` standard-input reader (the registered
  `user_drv_reader` process) reads eagerly: whenever the terminal becomes
  readable it starts a blocking read on a dirty IO scheduler and keeps any bytes
  for a later `IO.gets`. If a helper wins the bytes first, that read stays
  blocked in the kernel and takes the next line, or part of it, that the operator
  types for a later helper. OTP releases whose reader runs only on request do not
  register that name and need no action.

  `claim/0` must succeed before a helper that reads the terminal is started. The
  first claim asks the reader to pause through the same request that OTP's
  external-editor path uses and waits for its acknowledgement; that
  acknowledgement means the reader is idle in its receive loop rather than inside
  a read. The pause is never lifted: resuming would rearm a read that blocks again
  on the shared terminal. A VM whose terminal belongs to native helpers therefore
  never reads that terminal through `IO.gets` again, which matches the
  interactive client's single-reader rule. A reader that cannot acknowledge in
  time is already blocked in a read, so the claim refuses instead of displaying a
  prompt whose answer it could take. Its acknowledgement can still arrive later
  and completes the pause for the next claim.

  Pipes and other nonterminal input, VMs with a shell, and runtimes without the
  eager reader keep their ordinary standard-input behavior.
  """
  use GenServer

  @ack_ms 500

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "Pause any eager VM reader of the inherited terminal; `:ok` once none competes."
  def claim do
    GenServer.call(__MODULE__, :claim, @ack_ms + 5_000)
  catch
    :exit, _ -> {:error, :terminal_input_contended}
  end

  @impl true
  def init(_), do: {:ok, %{reader: nil, ref: nil, paused: false}}

  @impl true
  def handle_call(:claim, _from, s) do
    case eager_reader() do
      nil ->
        {:reply, :ok, s}

      reader ->
        s = if s.reader == reader, do: s, else: request_pause(reset(s), reader)
        s = if s.paused, do: s, else: await_ack(s)

        cond do
          s.paused -> {:reply, :ok, s}
          s.reader == nil -> {:reply, :ok, s}
          true -> {:reply, {:error, :terminal_input_contended}, s}
        end
    end
  end

  @impl true
  def handle_info({ref, :ok}, %{ref: ref} = s) when is_reference(ref),
    do: {:noreply, %{s | paused: true}}

  def handle_info({:DOWN, ref, :process, _, _}, %{ref: ref} = s), do: {:noreply, reset(s)}
  def handle_info(_, s), do: {:noreply, s}

  # Only a noshell VM reading an actual terminal on both standard descriptors
  # can hand that terminal to a native helper.
  defp eager_reader do
    with {:ok, _} <- :init.get_argument(:noshell),
         reader when is_pid(reader) <- Process.whereis(:user_drv_reader),
         options when is_list(options) <- :io.getopts(:user),
         true <- options[:stdin] == true and options[:stdout] == true do
      reader
    else
      _ -> nil
    end
  end

  # The monitor reference doubles as the reply alias; it stays active so a late
  # acknowledgement still records the pause.
  defp request_pause(s, reader) do
    ref = Process.monitor(reader, alias: :explicit_unalias)
    send(reader, {ref, :disable})
    %{s | reader: reader, ref: ref, paused: false}
  end

  defp await_ack(%{ref: ref} = s) do
    receive do
      {^ref, :ok} -> %{s | paused: true}
      {:DOWN, ^ref, :process, _, _} -> reset(s)
    after
      @ack_ms -> s
    end
  end

  defp reset(%{ref: nil} = s), do: s

  defp reset(%{ref: ref} = s) do
    Process.demonitor(ref, [:flush])
    Process.unalias(ref)
    %{s | reader: nil, ref: nil, paused: false}
  end
end
