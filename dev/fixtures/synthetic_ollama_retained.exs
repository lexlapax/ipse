defmodule Ipse.Development.SyntheticOllamaRetained do
  @moduledoc false
  @header_limit 16_384
  @body_limit 2_097_152
  @accept_timeout 180_000
  @body_timeout 30_000
  @prompt "Synthetic retained-cohort diagnostic: use the available references for this distinct turn."

  def prompt, do: @prompt

  def start(port, owner) when is_integer(port) and port in 1..65_535 and is_pid(owner) do
    with {:ok, listener} <-
           :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}]) do
      task =
        Task.async(fn ->
          try do
            {:ok, socket} = :gen_tcp.accept(listener, @accept_timeout)

            try do
              {headers, bytes} = request(socket, <<>>)
              [line | _] = String.split(headers, "\r\n")
              true = line in ["POST /api/chat HTTP/1.1", "POST /api/chat HTTP/1.0"]
              payload = Jason.decode!(bytes)
              true = payload["model"] == "synthetic" and is_list(payload["messages"])

              true =
                Enum.any?(
                  payload["messages"],
                  &(&1["role"] == "user" and &1["content"] == @prompt)
                )

              send(
                owner,
                {:retained_request, Ipse.JSON.sha256(bytes), byte_size(bytes),
                 String.contains?(bytes, "Native capacity source ")}
              )

              body =
                Jason.encode!(%{
                  "model" => "synthetic",
                  "message" => %{
                    "role" => "assistant",
                    "content" => "Synthetic diagnostic response."
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
          after
            :gen_tcp.close(listener)
          end
        end)

      {:ok, task}
    end
  end

  defp request(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [headers, initial] ->
        true = byte_size(headers) <= @header_limit
        [_, length] = Regex.run(~r/(?:^|\r\n)content-length:\s*(\d+)(?:\r\n|$)/i, headers)
        size = String.to_integer(length)
        true = size in 1..@body_limit
        {headers, body(socket, initial, size)}

      [_] when byte_size(buffer) <= @header_limit ->
        {:ok, chunk} = :gen_tcp.recv(socket, 0, @body_timeout)
        request(socket, buffer <> chunk)

      _ ->
        raise "diagnostic request headers exceeded bound"
    end
  end

  defp body(_, bytes, size) when byte_size(bytes) == size, do: bytes

  defp body(socket, bytes, size) when byte_size(bytes) < size do
    {:ok, chunk} = :gen_tcp.recv(socket, 0, @body_timeout)
    body(socket, bytes <> chunk, size)
  end

  defp body(_, _, _), do: raise("diagnostic request body exceeded declared size")
end
