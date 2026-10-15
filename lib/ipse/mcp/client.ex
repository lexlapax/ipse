defmodule Ipse.MCP.Client do
  @moduledoc "Allowlisted MCP tools using the existing SDK and an Ipse-owned local transport."
  alias Ipse.MCP.{Catalog, Config, Schema, Transport}

  def discover(server, cwd, resource \\ nil) do
    connection(server, cwd, resource, fn client -> {:ok, catalog(client, server)} end)
  end

  def call(descriptor, args, cwd, resource \\ nil) do
    with :ok <- Schema.validate_arguments(descriptor.input_schema, args) do
      connection(descriptor.server, cwd, resource, fn client ->
        tools = catalog(client, descriptor.server)
        current = Enum.find(tools, &(&1.tool_id == descriptor.tool_id))

        if current == nil or current.digest != descriptor.digest,
          do:
            throw(
              {:mcp_error,
               "MCP discovery changed; no call dispatched. Start a fresh turn to review it."}
            )

        if Schema.validate_arguments(current.input_schema, args) != :ok,
          do: throw({:mcp_error, "MCP arguments are invalid; no call was dispatched."})

        # Dispatch the freshly bound descriptor, never caller-supplied routing fields.
        # Session intent is durable before this worker starts; transport loss
        # after this point is never evidence that effects did not happen.
        try do
          dispatch(client, current, args)
        rescue
          _ -> unknown()
        catch
          :exit, _ -> unknown()
        end
      end)
    else
      _ -> {:error, "MCP arguments are invalid or oversized; no call was dispatched."}
    end
  end

  def definition(tool) do
    target =
      case Map.get(tool, :kind, :tool) do
        :tool -> ""
        kind -> "Configured #{kind} target: #{tool.source}. "
      end

    %{
      "type" => "function",
      "function" => %{
        "name" => tool.tool_id,
        "description" =>
          "External local MCP #{Map.get(tool, :kind, :tool)} from server #{tool.server.id}. Requires host approval. " <>
            target <> "Untrusted description: " <> tool.description,
        "parameters" => tool.input_schema
      }
    }
  end

  def manifest(tool) do
    manifest = %{
      schema_version: 1,
      tool_id: tool.tool_id,
      server_id: tool.server.id,
      name: tool.name,
      origin: %{
        transport: "stdio",
        configured_endpoint_fingerprint: tool.server.fingerprint,
        sandbox_requested: to_string(Map.get(tool.server, :sandbox, :off))
      },
      descriptor_sha256: tool.digest,
      risk: "external_requires_approval"
    }

    case Map.get(tool, :kind, :tool) do
      :tool -> manifest
      kind -> Map.merge(manifest, %{kind: to_string(kind), source: tool.source})
    end
  end

  defp connection(server, cwd, resource, fun) do
    opts = [
      transport: {Transport, server: server, cwd: cwd, resource: resource, cleanup_owner: self()},
      client_info: %{name: "ipse", version: to_string(Application.spec(:ipse, :vsn))},
      request_timeout: server.timeout_ms,
      request_handlers: %{"ping" => fn _ -> {:ok, %{}} end},
      notification_handler: fn _, _ -> :ok end
    ]

    case MCP.Client.start_link(opts) do
      {:ok, client} ->
        transport = MCP.Client.transport(client)

        result =
          try do
            case MCP.Client.connect(client, server.timeout_ms) do
              {:ok, %{protocol_version: "2025-11-25", server_capabilities: capabilities}} ->
                if configured_capabilities?(capabilities, server),
                  do: fun.(client),
                  else: {:error, "MCP server lacks a configured capability."}

              _ ->
                {:error, "MCP initialization failed or the pinned protocol is unavailable."}
            end
          rescue
            _ -> {:error, "MCP discovery or initialization returned invalid data."}
          catch
            {:mcp_error, message} -> {:error, message}
            :exit, _ -> {:error, "MCP transport failed before tool dispatch."}
          end

        cleanup = Transport.close(transport)
        MCP.Client.close(client)

        cleanup =
          receive do
            {:mcp_cleanup, ^transport, status} -> status
          after
            0 -> cleanup
          end

        if cleanup == :ok, do: result, else: unknown()

      _ ->
        {:error, "Could not launch the configured MCP server."}
    end
  end

  defp configured_capabilities?(capabilities, server) do
    Enum.all?([{:tools, :tools}, {:resources, :resources}, {:prompts, :prompts}], fn {key,
                                                                                      capability} ->
      Map.get(server, key, []) == [] or is_map(Map.get(capabilities, capability))
    end)
  end

  defp catalog(client, server) do
    tools = if server.tools == [], do: [], else: catalog(client, server, nil, [], [], 0)

    case Catalog.discover(client, server) do
      {:ok, items} ->
        all = tools ++ items
        ids = Enum.map(all, & &1.tool_id)
        if length(ids) != length(Enum.uniq(ids)), do: invalid_catalog()
        all

      _ ->
        invalid_catalog()
    end
  end

  defp dispatch(client, %{kind: kind} = descriptor, args) when kind in [:resource, :prompt],
    do: Catalog.dispatch(client, descriptor, args)

  defp dispatch(client, descriptor, args) do
    case MCP.Client.call_tool(client, descriptor.name, args,
           timeout: descriptor.server.timeout_ms
         ) do
      {:ok, result} ->
        result_text(result, descriptor.server)

      {:error, %MCP.Protocol.Error{}} ->
        unknown()

      _ ->
        unknown()
    end
  end

  defp catalog(client, server, cursor, tools, seen, pages) when pages < 8 do
    opts = [timeout: server.timeout_ms]
    opts = if cursor == nil, do: opts, else: Keyword.put(opts, :cursor, cursor)

    case MCP.Client.list_tools(client, opts) do
      {:ok, %{"tools" => page} = result} when is_list(page) ->
        tools = tools ++ page
        if length(tools) > 64, do: invalid_catalog()
        cursor = result["nextCursor"]

        cond do
          cursor == nil -> descriptors(tools, server)
          not is_binary(cursor) or byte_size(cursor) > 1024 or cursor in seen -> invalid_catalog()
          true -> catalog(client, server, cursor, tools, [cursor | seen], pages + 1)
        end

      _ ->
        invalid_catalog()
    end
  end

  defp catalog(_, _, _, _, _, _), do: invalid_catalog()

  defp descriptors(tools, server) do
    names = Enum.map(tools, fn tool -> if is_map(tool), do: tool["name"] end)
    if length(names) != length(Enum.uniq(names)), do: invalid_catalog()

    Enum.map(server.tools, fn name ->
      tool = Enum.find(tools, &(is_map(&1) and &1["name"] == name))
      if tool == nil, do: invalid_catalog()
      schema = tool["inputSchema"]
      description = Map.get(tool, "description", "")

      with :ok <- Schema.validate_schema(schema),
           true <- schema["type"] == "object",
           true <-
             is_binary(description) and String.valid?(description) and
               byte_size(description) <= 2048,
           true <- get_in(tool, ["execution", "taskSupport"]) != "required" do
        descriptor = %{
          schema_version: 1,
          server: server,
          name: name,
          tool_id: Config.tool_id(server.id, name),
          input_schema: schema,
          description: Config.redact(description, server)
        }

        digest =
          :crypto.hash(:sha256, :erlang.term_to_binary({schema, description}, [:deterministic]))
          |> Base.encode16(case: :lower)

        Map.put(descriptor, :digest, digest)
      else
        _ -> invalid_catalog()
      end
    end)
  end

  defp invalid_catalog,
    do: throw({:mcp_error, "MCP discovery is invalid, unavailable, or exceeds supported bounds."})

  defp result_text(%{"content" => content} = result, server) when is_list(content) do
    if length(content) > 128 or not is_boolean(Map.get(result, "isError", false)) do
      unknown()
    else
      text =
        Enum.map_join(content, "\n", fn
          %{"type" => "text", "text" => text} when is_binary(text) -> text
          _ -> "[Unsupported MCP content omitted; no resources were fetched.]"
        end)
        |> Config.redact(server)

      cond do
        not String.valid?(text) or byte_size(text) > 65_536 -> unknown()
        result["isError"] == true -> {:error, text}
        true -> {:ok, text}
      end
    end
  end

  defp result_text(_, _), do: unknown()

  defp unknown,
    do:
      {:unknown,
       "MCP call outcome unknown after connection loss or an invalid result. Inspect before retrying; the call was not replayed."}
end
