defmodule Ipse.MCPHTTPDemo do
  @moduledoc false

  def run do
    root = Path.join(System.tmp_dir!(), "ipse-http-demo-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    {:ok, supervisor} = Task.Supervisor.start_link()
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    Task.Supervisor.start_child(supervisor, fn -> accept(listener, supervisor) end)

    try do
      config = Path.join(root, "mcp.json")

      File.write!(
        config,
        Jason.encode!(%{
          "servers" => [
            %{
              "id" => "httpdemo",
              "transport" => "http",
              "url" => "http://127.0.0.1:#{port}/mcp",
              "allow_insecure_loopback" => true,
              "tools" => ["echo"],
              "timeout_ms" => 5000
            }
          ]
        })
      )

      {:ok, [server]} = Ipse.MCP.Config.load(config)
      {:ok, [tool]} = Ipse.MCP.discover_server(server, root)

      {:ok, "synthetic HTTP MCP verified"} =
        Ipse.MCP.call(tool, %{"text" => "synthetic HTTP MCP verified"}, root)

      :ok
    after
      :gen_tcp.close(listener)
      Supervisor.stop(supervisor)
      File.rm_rf!(root)
    end
  end

  defp accept(listener, supervisor) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        {:ok, handler} =
          Task.Supervisor.start_child(supervisor, fn ->
            receive do
              :serve -> serve(socket)
            end
          end)

        :ok = :gen_tcp.controlling_process(socket, handler)
        send(handler, :serve)
        accept(listener, supervisor)

      _ ->
        :ok
    end
  end

  defp serve(socket) do
    try do
      {headers, body} = request(socket, "")
      size = headers |> Map.get("content-length", "0") |> String.to_integer()
      body = body(socket, body, size)
      rpc = Jason.decode!(body)

      result =
        case rpc["method"] do
          "initialize" ->
            %{
              "protocolVersion" => "2025-11-25",
              "capabilities" => %{"tools" => %{}},
              "serverInfo" => %{"name" => "synthetic-http", "version" => "1"}
            }

          "tools/list" ->
            %{
              "tools" => [
                %{
                  "name" => "echo",
                  "description" => "Return synthetic text",
                  "inputSchema" => %{
                    "type" => "object",
                    "properties" => %{"text" => %{"type" => "string"}},
                    "required" => ["text"]
                  }
                }
              ]
            }

          "tools/call" ->
            %{"content" => [%{"type" => "text", "text" => rpc["params"]["arguments"]["text"]}]}

          _ ->
            %{}
        end

      {status, response} =
        if is_nil(rpc["id"]),
          do: {202, ""},
          else: {200, Jason.encode!(%{"jsonrpc" => "2.0", "id" => rpc["id"], "result" => result})}

      :gen_tcp.send(
        socket,
        "HTTP/1.1 #{status} OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(response)}\r\nconnection: close\r\n\r\n" <>
          response
      )
    after
      :gen_tcp.close(socket)
    end
  end

  defp request(socket, buffer) do
    case :binary.split(buffer, "\r\n\r\n") do
      [raw, body] ->
        [_first | lines] = String.split(raw, "\r\n")

        headers =
          Map.new(lines, fn line ->
            [key, value] = String.split(line, ":", parts: 2)
            {String.downcase(key), String.trim(value)}
          end)

        {headers, body}

      [_] ->
        {:ok, bytes} = :gen_tcp.recv(socket, 0, 5000)
        request(socket, buffer <> bytes)
    end
  end

  defp body(_, bytes, size) when byte_size(bytes) >= size, do: bytes

  defp body(socket, bytes, size) do
    {:ok, more} = :gen_tcp.recv(socket, 0, 5000)
    body(socket, bytes <> more, size)
  end
end
