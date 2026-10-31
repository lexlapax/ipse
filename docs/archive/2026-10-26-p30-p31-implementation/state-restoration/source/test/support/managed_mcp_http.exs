defmodule Ipse.Test.ManagedMCPHTTP do
  @moduledoc false

  def start(root) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    task = Task.async(fn -> accept(listener, root) end)
    {"http://127.0.0.1:#{port}/mcp", task, listener}
  end

  defp accept(listener, root) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        try do
          File.write!(Path.join(root, "managed-mcp-connections.log"), "accepted\n", [:append])
          {method, body} = read_request(socket, "")
          rpc = if body == "", do: %{}, else: Jason.decode!(body)

          if rpc["method"] == "tools/list" and File.exists?(Path.join(root, "managed-mcp-gate")) do
            File.write!(Path.join(root, "managed-mcp-list-ready"), "ready")
            wait_for_release(root)
          end

          if rpc["method"] == "initialize" and
               File.exists?(Path.join(root, "managed-mcp-drop-start")) do
            File.write!(Path.join(root, "managed-mcp-start-received"), "received")
          else
            result = result(rpc, root)
            status = if method == "DELETE" or is_nil(rpc["id"]), do: 202, else: 200

            body =
              if status == 202,
                do: "",
                else: Jason.encode!(%{"jsonrpc" => "2.0", "id" => rpc["id"], "result" => result})

            response =
              "HTTP/1.1 #{status} #{if status == 200, do: "OK", else: "Accepted"}\r\ncontent-type: application/json\r\nmcp-session-id: fixture-session\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                body

            if rpc["method"] == "tools/call" and
                 File.exists?(Path.join(root, "managed-mcp-hold-call")) do
              File.write!(Path.join(root, "managed-mcp-call-held"), "held")
              closed = :gen_tcp.recv(socket, 0, 5000)
              File.write!(Path.join(root, "managed-mcp-call-closed"), inspect(closed))
            else
              :gen_tcp.send(socket, response)
            end
          end
        after
          :gen_tcp.close(socket)
        end

        accept(listener, root)

      _ ->
        :ok
    end
  end

  defp read_request(socket, bytes) do
    case String.split(bytes, "\r\n\r\n", parts: 2) do
      [headers, body] ->
        [method | _] = String.split(headers, " ", parts: 2)

        length =
          case Regex.run(~r/(?:^|\r\n)content-length:\s*(\d+)/i, headers) do
            [_, value] -> String.to_integer(value)
            _ -> 0
          end

        if byte_size(body) >= length,
          do: {method, binary_part(body, 0, length)},
          else: read_more(socket, bytes)

      _ ->
        read_more(socket, bytes)
    end
  end

  defp read_more(socket, bytes) when byte_size(bytes) <= 65_536 do
    {:ok, chunk} = :gen_tcp.recv(socket, 0, 5000)
    read_request(socket, bytes <> chunk)
  end

  defp wait_for_release(root) do
    unless File.exists?(Path.join(root, "managed-mcp-list-release")) do
      Process.sleep(2)
      wait_for_release(root)
    end
  end

  defp result(%{"method" => "initialize"}, _) do
    %{
      "protocolVersion" => "2025-11-25",
      "capabilities" => %{"tools" => %{}},
      "serverInfo" => %{"name" => "fixture", "version" => "1"}
    }
  end

  defp result(%{"method" => "tools/list"}, _) do
    %{
      "tools" => [
        %{
          "name" => "write_note",
          "description" => "Synthetic managed HTTP write",
          "inputSchema" => %{
            "type" => "object",
            "properties" => %{"path" => %{"type" => "string"}, "content" => %{"type" => "string"}},
            "required" => ["path", "content"],
            "additionalProperties" => false
          }
        }
      ]
    }
  end

  defp result(
         %{
           "method" => "tools/call",
           "params" => %{"name" => "write_note", "arguments" => arguments}
         },
         root
       ) do
    File.write!(Path.join(root, "calls.log"), "write_note\n", [:append])
    File.write!(Path.join(root, arguments["path"]), arguments["content"])

    %{
      "isError" => false,
      "content" => [%{"type" => "text", "text" => "Synthetic managed HTTP result"}]
    }
  end

  defp result(_, _), do: %{}
end
