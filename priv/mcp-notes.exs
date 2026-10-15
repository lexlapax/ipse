# Credential-free example server. Launch with the compiled SDK/Jason code paths.
defmodule Ipse.Examples.MCPNotes do
  @behaviour MCP.Server.Handler
  @impl true
  def init(_), do: {:ok, %{}}

  @impl true
  def handle_list_tools(_cursor, state) do
    tool = %{
      "name" => "write_note",
      "description" => "Write the scratch file mcp-note.txt.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "content" => %{"type" => "string", "maxLength" => 8192}
        },
        "required" => ["content"],
        "additionalProperties" => false
      }
    }

    {:ok, [tool], nil, state}
  end

  @impl true
  def handle_call_tool("write_note", %{"content" => text}, state)
      when is_binary(text) and byte_size(text) <= 8192 do
    case File.write("mcp-note.txt", text) do
      :ok -> {:ok, [%{"type" => "text", "text" => "Wrote mcp-note.txt."}], state}
      _ -> {:error, -32_000, "Could not write the scratch note.", state}
    end
  end

  def handle_call_tool(_, _, state),
    do: {:error, -32_602, "Invalid example tool arguments.", state}
end

{:ok, _} = Application.ensure_all_started(:mcp_elixir_sdk)

{:ok, server} =
  MCP.Server.start_link(
    transport: {MCP.Transport.Stdio, mode: :server},
    handler: {Ipse.Examples.MCPNotes, []},
    server_info: %{name: "ipse-notes-example", version: "1"}
  )

ref = Process.monitor(server)

receive do
  {:DOWN, ^ref, :process, ^server, _} -> :ok
end
