defmodule Ipse.Development.SyntheticOllamaRetained do
  @moduledoc false
  @header_limit 16_384
  @body_limit 2_097_152
  @accept_timeout 180_000
  @body_timeout 30_000
  @prompt "Synthetic fresh 2000-note recall probe: use the available references for this distinct turn."

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

              reference_texts =
                for %{"role" => "user", "content" => text} <- payload["messages"],
                    is_binary(text),
                    {:ok, %{"extensions" => extensions}} <-
                      [Ipse.Session.Reference.selected_publishers(%{"content" => text})],
                    is_binary(extensions),
                    do: extensions

              assert_prompt_uncontaminated!()
              number = find_seeded_reference(reference_texts)
              true = is_integer(number) and number in 1..2000
              send(owner, {:retained_request, Ipse.JSON.sha256(bytes), byte_size(bytes), number})

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

  defp assert_prompt_uncontaminated! do
    false = String.contains?(@prompt, "Native capacity source ")
    false = String.contains?("Synthetic diagnostic response.", "Native capacity source ")
    :ok
  end

  defp find_seeded_reference(texts) do
    Enum.find_value(texts, fn text ->
      Regex.scan(~r/Native capacity source ([1-9][0-9]{0,3}): /, text, capture: :all_but_first)
      |> Enum.find_value(fn [number] ->
        number = String.to_integer(number)
        if number in 1..2000 and String.contains?(text, seed_text(number)), do: number
      end)
    end)
  end

  defp seed_text(number) do
    prefix = "Native capacity source #{number}: "
    body = Enum.map_join(1..17, " ", &Ipse.JSON.sha256("native capacity #{number}:#{&1}"))
    prefix <> binary_part(body, 0, 1024 - byte_size(prefix))
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
