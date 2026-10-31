defmodule Ipse.Test.ProviderFixture do
  @moduledoc false

  def start(body, status \\ 200, response_headers \\ "", send_mode \\ :fragmented) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        try do
          {:ok, socket} = :gen_tcp.accept(listener, 5000)

          try do
            {headers, payload} = request(socket, "")

            response =
              "HTTP/1.1 #{status} Fixture\r\ncontent-type: text/event-stream\r\n#{response_headers}content-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n"

            :ok = :gen_tcp.send(socket, response)

            if send_mode == :whole do
              :ok = :gen_tcp.send(socket, body)
            else
              for <<byte <- body>>, do: :ok = :gen_tcp.send(socket, <<byte>>)
            end

            {headers, Jason.decode!(payload)}
          after
            :gen_tcp.close(socket)
          end
        after
          :gen_tcp.close(listener)
        end
      end)

    {"http://127.0.0.1:#{port}", task}
  end

  def request(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [headers, body] ->
        [_, size] = Regex.run(~r/content-length:\s*(\d+)/i, headers)
        {headers, rest(socket, body, String.to_integer(size))}

      [_] ->
        {:ok, chunk} = :gen_tcp.recv(socket, 0, 5000)
        request(socket, buffer <> chunk)
    end
  end

  def sequence(bodies) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        try do
          for body <- bodies do
            {:ok, socket} = :gen_tcp.accept(listener, 5000)

            try do
              {headers, payload} = request(socket, "")

              :ok =
                :gen_tcp.send(
                  socket,
                  "HTTP/1.1 200 Fixture\r\ncontent-type: text/event-stream\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                    body
                )

              {headers, Jason.decode!(payload)}
            after
              :gen_tcp.close(socket)
            end
          end
        after
          :gen_tcp.close(listener)
        end
      end)

    {"http://127.0.0.1:#{port}", task}
  end

  defp rest(_, body, size) when byte_size(body) >= size, do: body

  defp rest(socket, body, size) do
    {:ok, chunk} = :gen_tcp.recv(socket, 0, 5000)
    rest(socket, body <> chunk, size)
  end

  def sse(events) when is_list(events), do: Enum.map_join(events, &sse/1)
  def sse(event) when is_binary(event), do: "data: " <> event <> "\n\n"
  def sse(event), do: "data: " <> Jason.encode!(event) <> "\n\n"
  def ndjson(objects), do: Enum.map_join(objects, &(Jason.encode!(&1) <> "\n"))
end
