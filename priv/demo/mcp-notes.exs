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

  @impl true
  def handle_list_resources(_, state) do
    {:ok,
     [
       %{
         "uri" => "notes://guide",
         "name" => "Notes guide",
         "description" => "Read the example notes guide."
       }
     ], nil, state}
  end

  @impl true
  def handle_read_resource("notes://guide", state),
    do:
      {:ok, [%{"uri" => "notes://guide", "text" => "Example notes are plain UTF-8 text."}], state}

  def handle_read_resource(_, state), do: {:error, -32_002, "Unknown example resource.", state}

  @impl true
  def handle_list_prompts(_, state) do
    {:ok,
     [
       %{
         "name" => "summarize",
         "description" => "Get an example summary request.",
         "arguments" => [%{"name" => "topic", "required" => true}]
       }
     ], nil, state}
  end

  @impl true
  def handle_get_prompt("summarize", %{"topic" => topic}, state) when is_binary(topic) do
    {:ok,
     %{
       "messages" => [
         %{
           "role" => "user",
           "content" => %{"type" => "text", "text" => "Summarize this topic: " <> topic}
         }
       ]
     }, state}
  end

  def handle_get_prompt(_, _, state), do: {:error, -32_602, "Invalid example prompt.", state}
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
