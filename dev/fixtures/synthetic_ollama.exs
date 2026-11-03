defmodule Ipse.Development.SyntheticOllama do
  @moduledoc "Loopback-only synthetic Ollama fixture for native workload evidence."
  @header_bytes 16_384
  @body_bytes 2_097_152
  @timeout 30_000

  def start(port, owner, first, count)
      when is_integer(port) and port in 1..65_535 and is_pid(owner) and
             is_integer(first) and first > 0 and is_integer(count) and count > 0 do
    with {:ok, listener} <-
           :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}]) do
      task =
        Task.async(fn ->
          try do
            for turn <- first..(first + count - 1) do
              {:ok, socket} = :gen_tcp.accept(listener, @timeout)

              try do
                {headers, bytes} = request(socket, <<>>)
                [request_line | _] = String.split(headers, "\r\n")
                true = request_line in ["POST /api/chat HTTP/1.1", "POST /api/chat HTTP/1.0"]
                payload = Jason.decode!(bytes)
                prompt = prompt(turn)
                true = payload["model"] == "synthetic" and is_list(payload["messages"])

                true =
                  Enum.any?(payload["messages"], fn message ->
                    message["role"] == "user" and message["content"] == prompt
                  end)

                # All source text is synthetic; do not copy the request into a receipt.
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

                :ok =
                  :gen_tcp.send(
                    socket,
                    "HTTP/1.1 200 Fixture\r\ncontent-type: application/x-ndjson\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                      body
                  )
              after
                :gen_tcp.close(socket)
              end
            end
          after
            :gen_tcp.close(listener)
          end

          :ok
        end)

      {:ok, task}
    end
  end

  def prompt(turn), do: "Synthetic annual workload turn #{turn}: use the available references."

  defp request(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [headers, initial] ->
        true = byte_size(headers) <= @header_bytes
        [_, length] = Regex.run(~r/(?:^|\r\n)content-length:\s*(\d+)(?:\r\n|$)/i, headers)
        size = String.to_integer(length)
        true = size in 1..@body_bytes
        {headers, body(socket, initial, size)}

      [_] when byte_size(buffer) <= @header_bytes ->
        {:ok, chunk} = :gen_tcp.recv(socket, 0, @timeout)
        request(socket, buffer <> chunk)

      _ ->
        raise "synthetic provider request headers exceeded the fixture bound"
    end
  end

  defp body(_socket, bytes, size) when byte_size(bytes) == size, do: bytes

  defp body(socket, bytes, size) when byte_size(bytes) < size do
    {:ok, chunk} = :gen_tcp.recv(socket, 0, @timeout)
    body(socket, bytes <> chunk, size)
  end

  defp body(_, _, _), do: raise("synthetic provider request exceeded its declared length")
end
