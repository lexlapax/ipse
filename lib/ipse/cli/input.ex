defmodule Ipse.CLI.Input do
  @moduledoc false

  def start(session) do
    client = self()

    with {:ok, mode} <- Ipse.Runner.operator_channel() do
      start_reader(client, session, mode)
    end
  end

  defp start_reader(client, _session, :pipe) do
    reader = spawn(fn -> pipe(client, Process.monitor(client)) end)
    {:ok, reader, nil, :pipe}
  end

  defp start_reader(client, session, :native) do
    reader = spawn(fn -> initialize(client, session) end)

    case Ipse.Session.open_input_channel(session, reader) do
      {:ok, channel} ->
        send(reader, {:channel, channel})
        {:ok, reader, channel, :native}

      error ->
        Process.exit(reader, :kill)
        error
    end
  end

  defp initialize(client, session) do
    client_ref = Process.monitor(client)

    receive do
      {:channel, channel} -> wait(client, client_ref, session, channel, :native)
      {:DOWN, ^client_ref, _, _, _} -> :ok
    end
  end

  defp wait(client, client_ref, session, channel, mode) do
    receive do
      {:read, generation, request} ->
        read(client, client_ref, session, channel, mode, generation, request)

      {:DOWN, ^client_ref, _, _, _} ->
        :ok
    end
  end

  defp read(client, client_ref, session, channel, mode, generation, request) do
    # Input.await belongs to this one persistent reader. No IO.gets runs beside it.
    result = Ipse.Session.observe_channel(session, channel, request, 600_000)

    case result do
      {:ok, text, witness} ->
        send(client, {:input_mode, :native})
        send(client, {:native_input, generation, request, text, witness})
        wait(client, client_ref, session, channel, :native)

      {:error, :operator_input_busy} ->
        retry(client, client_ref, session, channel, mode, generation, request)

      {:error, :operator_input_cancelled} ->
        retry(client, client_ref, session, channel, mode, generation, request)

      {:error, :operator_input_interrupted} ->
        send(client, {:input, "/cancel"})
        retry(client, client_ref, session, channel, mode, generation, request)

      {:error, reason} when reason in [:operator_input_too_large, :operator_input_invalid_utf8] ->
        send(client, {:input_notice, reason})
        retry(client, client_ref, session, channel, mode, generation, request)

      {:error, :operator_input_eof} ->
        send(client, {:input, :eof})
        finish(client_ref)

      {:error, reason} ->
        send(client, {:input_failure, reason})
    end
  catch
    :exit, _ -> send(client, {:input_failure, :operator_input_unavailable})
  end

  defp finish(client_ref) do
    receive do
      {:DOWN, ^client_ref, _, _, _} -> :ok
      _ -> finish(client_ref)
    end
  end

  defp retry(client, client_ref, session, channel, mode, generation, request) do
    receive do
      {:read, next, next_request} ->
        read(client, client_ref, session, channel, mode, next, next_request)

      {:DOWN, ^client_ref, _, _, _} ->
        :ok
    after
      10 -> read(client, client_ref, session, channel, mode, generation, request)
    end
  end

  defp pipe(client, client_ref) do
    receive do
      {:DOWN, ^client_ref, _, _, _} -> :ok
    after
      0 ->
        case IO.gets("you> ") do
          :eof ->
            send(client, {:input, :eof})

          {:error, _} ->
            send(client, {:input, :eof})

          text ->
            text = if String.valid?(text), do: String.trim(text), else: text
            send(client, {:input, text})
            pipe(client, client_ref)
        end
    end
  end
end
