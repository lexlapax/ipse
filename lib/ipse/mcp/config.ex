defmodule Ipse.MCP.Config do
  @moduledoc "Loads an explicitly selected, bounded MCP server configuration."

  @file_limit 65_536
  @args_limit 16
  @arg_bytes_limit 4_096
  @args_bytes_limit 16_384
  @env_limit 16
  @env_value_limit 4_096
  @tool_limit 16
  @id ~r/\A[a-z][a-z0-9_]{0,23}\z/
  @tool ~r/\A[A-Za-z0-9_.-]{1,32}\z/
  @env_name ~r/\A[A-Z_][A-Z0-9_]{0,63}\z/
  @blocked_env ~w(OPENAI_API_KEY ANTHROPIC_API_KEY IPSE_CHATGPT_ACCESS_TOKEN)

  def load(nil), do: {:ok, []}

  def load(path) when is_binary(path) do
    with {:ok, bytes} <- read_bounded(path),
         {:ok, decoded} <- Jason.decode(bytes),
         %{"servers" => servers} = document when is_list(servers) <- decoded,
         true <- keys?(document, ["servers"]),
         true <- length(servers) <= 4,
         {:ok, parsed} <- parse_servers(servers),
         true <- unique?(Enum.map(parsed, & &1.id)),
         model_names =
           for(server <- parsed, tool <- server.tools, do: tool_id(server.id, tool)),
         true <- unique?(model_names) do
      {:ok, parsed}
    else
      {:error, _} -> {:error, "MCP configuration is invalid or unreadable."}
      _ -> {:error, "MCP configuration is invalid or unreadable."}
    end
  rescue
    _ -> {:error, "MCP configuration is invalid or unreadable."}
  end

  def load(_), do: {:error, "MCP configuration is invalid or unreadable."}

  def tool_id(server_id, name), do: "mcp__#{server_id}__#{String.replace(name, ".", "_")}"

  def manifest(server) when is_map(server) do
    %{
      id: server.id,
      command: server.command,
      args: Enum.map(server.args, &redact(&1, server)),
      tools: server.tools,
      env_names: server.env |> Map.keys() |> Enum.sort(),
      timeout_ms: server.timeout_ms,
      fingerprint: server.fingerprint
    }
  end

  def redact(text, server) when is_binary(text) and is_map(server) do
    server.env
    |> Map.values()
    |> Enum.filter(&(is_binary(&1) and byte_size(&1) > 0))
    |> Enum.uniq()
    |> Enum.sort_by(&byte_size/1, :desc)
    |> Enum.reduce(text, fn secret, acc ->
      String.replace(acc, secret, fn _ -> "[redacted]" end)
    end)
  end

  def contains_private?(value, server) when is_binary(value), do: redact(value, server) != value

  def contains_private?(value, server) when is_map(value),
    do:
      Enum.any?(value, fn {key, item} ->
        contains_private?(key, server) or contains_private?(item, server)
      end)

  def contains_private?(value, server) when is_list(value),
    do: Enum.any?(value, &contains_private?(&1, server))

  def contains_private?(_, _), do: false

  defp read_bounded(path) do
    with {:ok, stat} <- File.lstat(path),
         true <- stat.type == :regular,
         {:ok, io} <- File.open(path, [:read, :binary]) do
      try do
        case IO.binread(io, @file_limit + 1) do
          data when is_binary(data) and byte_size(data) <= @file_limit ->
            if String.valid?(data), do: {:ok, data}, else: {:error, :invalid_utf8}

          _ ->
            {:error, :oversize}
        end
      after
        File.close(io)
      end
    end
  end

  defp parse_servers(servers) do
    Enum.reduce_while(servers, {:ok, []}, fn entry, {:ok, acc} ->
      case parse_server(entry) do
        {:ok, server} -> {:cont, {:ok, [server | acc]}}
        _ -> {:halt, {:error, :invalid_server}}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      error -> error
    end
  end

  defp parse_server(entry) when is_map(entry) do
    allowed = ["id", "command", "args", "tools", "env", "timeout_ms"]

    with true <- keys?(entry, allowed),
         id when is_binary(id) <- entry["id"],
         true <- Regex.match?(@id, id),
         command when is_binary(command) <- entry["command"],
         :ok <- executable(command),
         {:ok, args} <- validate_args(Map.get(entry, "args", [])),
         {:ok, tools} <- validate_tools(entry["tools"]),
         {:ok, env} <- validate_env(Map.get(entry, "env", %{})),
         timeout when is_integer(timeout) and timeout in 1..120_000 <-
           Map.get(entry, "timeout_ms", 30_000) do
      fingerprint = fingerprint(id, command, args, tools, env, timeout)

      {:ok,
       %{
         id: id,
         command: command,
         args: args,
         tools: tools,
         env: env,
         timeout_ms: timeout,
         fingerprint: fingerprint
       }}
    else
      _ -> {:error, :invalid_server}
    end
  end

  defp parse_server(_), do: {:error, :invalid_server}

  defp executable(path) do
    if Path.type(path) == :absolute and String.valid?(path) and
         not String.contains?(path, <<0>>) and byte_size(path) <= @arg_bytes_limit do
      case File.stat(path) do
        {:ok, %{type: :regular, mode: mode}} when Bitwise.band(mode, 0o111) != 0 -> :ok
        _ -> {:error, :invalid_command}
      end
    else
      {:error, :invalid_command}
    end
  end

  defp validate_args(args) when is_list(args) and length(args) <= @args_limit do
    if Enum.all?(
         args,
         &(is_binary(&1) and String.valid?(&1) and
             not String.contains?(&1, <<0>>) and
             byte_size(&1) <= @arg_bytes_limit)
       ) do
      bytes = Enum.reduce(args, 0, &(byte_size(&1) + &2))
      if bytes <= @args_bytes_limit, do: {:ok, args}, else: {:error, :args_too_large}
    else
      {:error, :invalid_args}
    end
  end

  defp validate_args(_), do: {:error, :invalid_args}

  defp validate_tools(tools) when is_list(tools) and length(tools) in 1..@tool_limit do
    if Enum.all?(tools, &(is_binary(&1) and Regex.match?(@tool, &1))) and unique?(tools),
      do: {:ok, tools},
      else: {:error, :invalid_tools}
  end

  defp validate_tools(_), do: {:error, :invalid_tools}

  defp validate_env(env) when is_map(env) and map_size(env) <= @env_limit do
    valid =
      Enum.all?(env, fn {key, value} ->
        is_binary(key) and Regex.match?(@env_name, key) and key not in @blocked_env and
          is_binary(value) and String.valid?(value) and
          not String.contains?(value, <<0>>) and byte_size(value) <= @env_value_limit
      end)

    if valid, do: {:ok, env}, else: {:error, :invalid_env}
  end

  defp validate_env(_), do: {:error, :invalid_env}

  defp fingerprint(id, command, args, tools, env, timeout) do
    public_args = Enum.map(args, &redact(&1, %{env: env}))

    {id, command, public_args, tools, Enum.sort(Map.keys(env)), timeout}
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp unique?(values), do: length(values) == length(Enum.uniq(values))

  defp keys?(map, allowed), do: Enum.all?(Map.keys(map), &(&1 in allowed))
end
