defmodule Ipse.MCP.Planning do
  @moduledoc "Operator-only planning read declarations; data checks grant no dispatch authority."
  alias Ipse.{JSON, MCP.Config}
  @error {:error, :invalid_planning_mcp_reads}

  def schema, do: %{"type" => "object"}

  def validate(reads) when is_map(reads) and map_size(reads) <= 64 do
    if Enum.all?(reads, fn {id, entry} ->
         is_map(entry) and
           Enum.sort(Map.keys(entry)) ==
             ~w(descriptor_sha256 endpoint_sha256 server_id tool version) and
           entry["version"] === 1 and valid_server?(entry["server_id"]) and
           valid_tool?(entry["tool"]) and id === Config.tool_id(entry["server_id"], entry["tool"]) and
           JSON.sha256?(entry["endpoint_sha256"]) and JSON.sha256?(entry["descriptor_sha256"])
       end),
       do: :ok,
       else: @error
  rescue
    _ -> @error
  end

  def validate(_), do: @error

  def resolve(sources) when is_list(sources) do
    Enum.reduce_while(sources, {:ok, %{}}, fn source, {:ok, acc} ->
      entries = Map.get(source.data, "planning_mcp_reads", %{})

      cond do
        Map.has_key?(source.data, "planning_mcp_reads") and source.scope != "operator" ->
          {:halt, {:error, :planning_mcp_reads_operator_only}}

        validate(entries) != :ok or validate(Map.merge(acc, entries)) != :ok ->
          {:halt, @error}

        true ->
          {:cont, {:ok, Map.merge(acc, entries)}}
      end
    end)
  rescue
    _ -> @error
  end

  def resolve(_), do: @error

  @doc false
  def runtime_configuration(config) when is_map(config) do
    reads = Map.get(config, :planning_mcp_reads, %{})

    with :ok <- validate(reads),
         {:ok, recorded} <- manifest_reads(config[:configuration]),
         true <- recorded === reads do
      :ok
    else
      _ -> {:error, :invalid_planning_mcp_configuration}
    end
  end

  def runtime_configuration(_), do: {:error, :invalid_planning_mcp_configuration}

  @doc false
  def saved_configuration?(saved, config) when is_map(config) do
    with :ok <- runtime_configuration(config),
         {:ok, recorded} <- manifest_reads(saved),
         true <- recorded === Map.get(config, :planning_mcp_reads, %{}) do
      true
    else
      _ -> false
    end
  end

  def saved_configuration?(_, _), do: false

  defp manifest_reads(nil), do: {:ok, %{}}

  defp manifest_reads(manifest) when is_map(manifest) do
    case {Map.fetch(manifest, :planning_mcp_reads), Map.fetch(manifest, "planning_mcp_reads")} do
      {:error, :error} -> {:ok, %{}}
      {{:ok, reads}, :error} -> if(validate(reads) == :ok, do: {:ok, reads}, else: @error)
      {:error, {:ok, reads}} -> if(validate(reads) == :ok, do: {:ok, reads}, else: @error)
      _ -> @error
    end
  end

  defp manifest_reads(_), do: @error

  # The descriptor must come from the Session's actual discovery, not worker
  # data. Matching still requires ordinary approval, current revalidation,
  # durable intent/result and replay before dispatch can use it.
  def declared?(%{server: server, name: name, tool_id: id, digest: digest} = descriptor, reads)
      when is_map(server) and is_binary(name) and is_binary(id) do
    validate(reads) == :ok and Map.get(descriptor, :kind, :tool) == :tool and
      server[:fingerprint_version] === 2 and
      server[:fingerprint] === Config.fingerprint_version(server, 2).fingerprint and
      id === Config.tool_id(server.id, name) and name in server.tools and
      reads[id] === %{
        "version" => 1,
        "server_id" => server.id,
        "tool" => name,
        "endpoint_sha256" => server.fingerprint,
        "descriptor_sha256" => digest
      }
  rescue
    _ -> false
  end

  def declared?(_, _), do: false
  defp valid_server?(id), do: is_binary(id) and Regex.match?(~r/\A[a-z][a-z0-9_]{0,23}\z/, id)
  defp valid_tool?(name), do: is_binary(name) and Regex.match?(~r/\A[A-Za-z0-9_.-]{1,32}\z/, name)
end
