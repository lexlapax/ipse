defmodule Ipse.Development.SyntheticOllama do
  @moduledoc "Loopback-only synthetic Ollama fixture for native workload evidence."
  @header_bytes 16_384
  @body_bytes 2_097_152
  @read_timeout 30_000
  @poll_ms 250

  # The runner owns the turn deadline. Idle fixture time must not end a turn
  # before protected recall reaches the provider boundary.
  def start(port, owner, first, count)
      when is_integer(port) and port in 1..65_535 and is_pid(owner) and
             is_integer(first) and first > 0 and is_integer(count) and count > 0 do
    with {:ok, listener} <-
           :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}]) do
      token = make_ref()

      task =
        Task.async(fn ->
          owner_ref = Process.monitor(owner)

          try do
            receive do
              {:synthetic_provider_start, ^token} ->
                run(listener, owner, owner_ref, first, count)

              {:DOWN, ^owner_ref, :process, ^owner, _} ->
                {:error, :owner_down}
            end
          after
            :gen_tcp.close(listener)
            Process.demonitor(owner_ref, [:flush])
          end
        end)

      Process.unlink(task.pid)

      case :gen_tcp.controlling_process(listener, task.pid) do
        :ok ->
          send(task.pid, {:synthetic_provider_start, token})
          {:ok, task}

        _ ->
          Task.shutdown(task, :brutal_kill)
          :gen_tcp.close(listener)
          {:error, :listener_transfer_failed}
      end
    end
  end

  defp run(listener, owner, owner_ref, first, count) do
    Enum.reduce_while(first..(first + count - 1), :ok, fn turn, _ ->
      outcome =
        try do
          serve(listener, owner, owner_ref, turn)
        rescue
          _ -> {:error, :fixture_failed}
        catch
          _, _ -> {:error, :fixture_failed}
        end

      case outcome do
        :ok ->
          {:cont, :ok}

        {:error, :owner_down} = error ->
          {:halt, error}

        {:error, stage} ->
          send(owner, {:synthetic_provider_failure, turn, stage})
          {:halt, {:error, {:synthetic_provider_failure, turn, stage}}}
      end
    end)
  end

  def prompt(turn), do: "Synthetic annual workload turn #{turn}: use the available references."

  defp serve(listener, owner, owner_ref, turn) do
    with {:ok, socket} <- accept(listener, owner, owner_ref) do
      try do
        with {:ok, headers, bytes} <- request(socket, owner, owner_ref),
             :ok <- validate(headers, bytes, turn),
             :ok <- ensure_owner(owner, owner_ref) do
          reference = String.contains?(bytes, "Native capacity source ")

          send(
            owner,
            {:synthetic_provider_request, turn, Ipse.JSON.sha256(bytes), byte_size(bytes),
             reference}
          )

          body =
            Jason.encode!(%{
              "model" => "synthetic",
              "message" => %{
                "role" => "assistant",
                "content" => "Synthetic workload answer #{turn}."
              },
              "done" => true,
              "prompt_eval_count" => 1,
              "eval_count" => 1
            }) <> "\n"

          case :gen_tcp.send(
                 socket,
                 "HTTP/1.1 200 Fixture\r\ncontent-type: application/x-ndjson\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                   body
               ) do
            :ok -> :ok
            _ -> {:error, :response_send_failed}
          end
        end
      rescue
        _ -> {:error, :invalid_request}
      catch
        _, _ -> {:error, :invalid_request}
      after
        :gen_tcp.close(socket)
      end
    end
  end

  defp accept(listener, owner, owner_ref) do
    if owner_alive?(owner, owner_ref) do
      case :gen_tcp.accept(listener, @poll_ms) do
        {:ok, socket} -> {:ok, socket}
        {:error, :timeout} -> accept(listener, owner, owner_ref)
        {:error, _} -> {:error, :listener_failed}
      end
    else
      {:error, :owner_down}
    end
  end

  defp request(socket, owner, owner_ref) do
    deadline = System.monotonic_time(:millisecond) + @read_timeout
    headers(socket, owner, owner_ref, deadline, <<>>)
  end

  defp headers(socket, owner, owner_ref, deadline, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [headers, initial] when byte_size(headers) <= @header_bytes ->
        with [_, length] <- Regex.run(~r/(?:^|\r\n)content-length:\s*(\d+)(?:\r\n|$)/i, headers),
             {size, ""} <- Integer.parse(length),
             true <- size in 1..@body_bytes,
             {:ok, bytes} <- body(socket, owner, owner_ref, deadline, initial, size) do
          {:ok, headers, bytes}
        else
          {:error, _} = error -> error
          _ -> {:error, :invalid_request}
        end

      [_] when byte_size(buffer) <= @header_bytes ->
        with {:ok, chunk} <- read(socket, owner, owner_ref, deadline),
             do: headers(socket, owner, owner_ref, deadline, buffer <> chunk)

      _ ->
        {:error, :invalid_request}
    end
  end

  defp body(_socket, _owner, _owner_ref, _deadline, bytes, size) when byte_size(bytes) == size,
    do: {:ok, bytes}

  defp body(socket, owner, owner_ref, deadline, bytes, size) when byte_size(bytes) < size do
    with {:ok, chunk} <- read(socket, owner, owner_ref, deadline),
         do: body(socket, owner, owner_ref, deadline, bytes <> chunk, size)
  end

  defp body(_, _, _, _, _, _), do: {:error, :invalid_request}

  defp read(socket, owner, owner_ref, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    cond do
      not owner_alive?(owner, owner_ref) ->
        {:error, :owner_down}

      remaining <= 0 ->
        {:error, :request_timeout}

      true ->
        case :gen_tcp.recv(socket, 0, min(remaining, @poll_ms)) do
          {:ok, bytes} when byte_size(bytes) > 0 -> {:ok, bytes}
          {:error, :timeout} -> read(socket, owner, owner_ref, deadline)
          _ -> {:error, :request_read_failed}
        end
    end
  end

  defp ensure_owner(owner, owner_ref),
    do: if(owner_alive?(owner, owner_ref), do: :ok, else: {:error, :owner_down})

  defp owner_alive?(owner, owner_ref) do
    receive do
      {:DOWN, ^owner_ref, :process, ^owner, _} -> false
    after
      0 -> Process.alive?(owner)
    end
  end

  defp validate(headers, bytes, turn) do
    [request_line | _] = String.split(headers, "\r\n")
    payload = Jason.decode!(bytes)

    if request_line in ["POST /api/chat HTTP/1.1", "POST /api/chat HTTP/1.0"] and
         payload["model"] == "synthetic" and is_list(payload["messages"]) and
         Enum.any?(payload["messages"], fn message ->
           message["role"] == "user" and message["content"] == prompt(turn)
         end),
       do: :ok,
       else: {:error, :invalid_request}
  end
end
