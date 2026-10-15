defmodule Ipse.MCP do
  @moduledoc "Explicit local MCP tools behind the session's existing approval and journal boundary."
  alias Ipse.MCP.{Client, Config, Schema}

  def fingerprints(config) do
    config |> Map.get(:mcp_servers, []) |> Enum.map(& &1.fingerprint)
  end

  def discover(servers, cwd, resource \\ nil) do
    Enum.reduce_while(servers, {:ok, []}, fn server, {:ok, acc} ->
      case Client.discover(server, cwd, resource) do
        {:ok, tools} ->
          all = acc ++ tools
          public = all |> Enum.map(&Client.definition/1) |> Jason.encode!()

          definitions = Enum.map(all, &Client.definition/1)

          if byte_size(public) <= 131_072 and not Config.contains_private?(definitions, server),
            do: {:cont, {:ok, all}},
            else:
              {:halt, {:error, "MCP catalog is oversized or contains configured private values."}}

        {:error, _} = error ->
          {:halt, error}

        {:unknown, message} ->
          {:halt, {:error, message}}
      end
    end)
  end

  def external?(name), do: is_binary(name) and String.starts_with?(name, "mcp__")
  def tool(tools, name), do: Enum.find(tools, &(&1.tool_id == name))
  def definitions(tools), do: Enum.map(tools, &Client.definition/1)
  def manifests(tools), do: Enum.map(tools, &Client.manifest/1)

  def validate_call(nil, _),
    do: {:error, "MCP tool is not explicitly enabled; no call dispatched."}

  def validate_call(tool, args) do
    with :ok <- Schema.validate_arguments(tool.input_schema, args),
         encoded <- Jason.encode!(args, pretty: true),
         true <- byte_size(encoded) <= 32_768,
         true <- not Config.contains_private?(args, tool.server) do
      :ok
    else
      _ ->
        {:error,
         "MCP arguments are invalid, oversized, or contain configured private values; no call dispatched."}
    end
  end
end
