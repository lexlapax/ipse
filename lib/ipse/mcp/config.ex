defmodule Ipse.MCP.Config do
  @moduledoc "Loads an explicitly selected, bounded MCP server configuration."

  @file_limit 65_536
  @args_limit 16
  @arg_bytes_limit 4_096
  @args_bytes_limit 16_384
  @env_limit 16
  @env_value_limit 4_096
  @tool_limit 16
  @resource_limit 16
  @prompt_limit 16
  @allowlist_limit 16
  @resource_uri_bytes 2_048
  @id ~r/\A[a-z][a-z0-9_]{0,23}\z/
  @tool ~r/\A[A-Za-z0-9_.-]{1,32}\z/
  @prompt ~r/\A[A-Za-z0-9_.-]{1,32}\z/
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
         model_names = Enum.flat_map(parsed, &model_ids/1),
         true <- unique?(model_names),
         secrets = all_secrets(parsed),
         true <- public_manifests_clear?(parsed, secrets) do
      {:ok, Enum.map(parsed, &(&1 |> Map.put(:redactions, secrets) |> fingerprint_version(2)))}
    else
      {:error, message} when is_binary(message) -> {:error, message}
      _ -> configuration_error()
    end
  rescue
    _ -> configuration_error()
  end

  def load(_), do: configuration_error()

  defp configuration_error,
    do:
      {:error,
       "MCP configuration is invalid or unreadable (document, server identities or public-field redaction). No server was launched; see docs/operator/mcp.md#configure-a-local-stdio-server."}

  @doc "Build a tool model ID; validated server IDs and tool names keep it within 64 bytes."
  def tool_id(server_id, name), do: "mcp__#{server_id}__#{String.replace(name, ".", "_")}"

  @doc "Build a stable resource model ID with a maximum of 64 bytes."
  def resource_id(server_id, uri), do: "mcp__#{server_id}__r_#{digest(uri)}"

  @doc "Build a stable prompt model ID with a maximum of 64 bytes."
  def prompt_id(server_id, name), do: "mcp__#{server_id}__p_#{digest(name)}"

  def manifest(server) when is_map(server) do
    redactor =
      if Map.get(server, :fingerprint_version, 1) == 1,
        do: Map.delete(server, :redactions),
        else: server

    args = Enum.map(server.args, &redact(&1, redactor))

    if contains_private?(args, server),
      do: raise(ArgumentError, "MCP public arguments contain configured private values.")

    base = %{
      id: server.id,
      command: server.command,
      args: args,
      tools: Map.get(server, :tools, []),
      resources: Map.get(server, :resources, []),
      prompts: Map.get(server, :prompts, []),
      sandbox: Map.get(server, :sandbox, :off),
      env_names: server.env |> Map.keys() |> Enum.sort(),
      timeout_ms: server.timeout_ms,
      fingerprint: Map.get(server, :fingerprint)
    }

    public =
      if Map.get(server, :transport) == :http,
        do:
          base
          |> Map.drop([:command, :args])
          |> Map.merge(%{
            transport: "streamable_http",
            endpoint: server.url,
            allow_insecure_loopback: server.allow_insecure_loopback
          }),
        else: base

    if Map.get(server, :fingerprint_version, 1) == 2,
      do: Map.put(public, :fingerprint_version, 2),
      else: public
  end

  @doc "Select the stored fingerprint contract without rewriting journal records."
  def fingerprint_version(server, version) when version in [1, 2] do
    server = Map.put(server, :fingerprint_version, version)
    fingerprint_server = if version == 1, do: Map.delete(server, :redactions), else: server
    public = fingerprint_server |> manifest() |> Jason.encode!() |> Jason.decode!()
    Map.put(server, :fingerprint, public_fingerprint(public))
  end

  @doc "Admit only written journal shapes: absent legacy version or explicit version two."
  def journal_fingerprint_version(metadata) do
    case Map.fetch(metadata, "mcp_fingerprint_version") do
      :error -> {:ok, 1}
      {:ok, 2} -> {:ok, 2}
      _ -> {:error, :resume_configuration_mismatch}
    end
  end

  @doc "Hash an already validated, redacted public server manifest."
  def public_fingerprint(%{"fingerprint_version" => 2} = public),
    do:
      Ipse.JSON.digest([
        "ipse.mcp.endpoint",
        2,
        Map.drop(public, ~w(fingerprint fingerprint_version))
      ])

  def public_fingerprint(%{"transport" => "streamable_http"} = public) do
    legacy_digest(
      {:http,
       {public["id"], public["endpoint"], public["tools"], public["resources"], public["prompts"],
        List.first(public["env_names"]), public["allow_insecure_loopback"], public["timeout_ms"]}}
    )
  end

  def public_fingerprint(public) do
    base =
      {public["id"], public["command"], public["args"], public["tools"], public["env_names"],
       public["timeout_ms"]}

    sandbox = if public["sandbox"] == "native", do: :native, else: :off

    value =
      if sandbox == :off and public["resources"] == [] and public["prompts"] == [],
        do: base,
        else: {base, sandbox, public["resources"], public["prompts"]}

    legacy_digest(value)
  end

  defp legacy_digest(value),
    do: value |> :erlang.term_to_binary([:deterministic]) |> Ipse.JSON.sha256()

  def redact(text, server) when is_binary(text) and is_map(server) do
    Map.get(server, :redactions, Map.values(server.env))
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
    secrets =
      Enum.flat_map(servers, fn
        entry when is_map(entry) ->
          values = if is_map(entry["env"]), do: Map.values(entry["env"]), else: []
          bearer = entry["bearer_env"]

          key =
            if is_binary(bearer) and Regex.match?(@env_name, bearer), do: System.get_env(bearer)

          Enum.filter([key | values], &(is_binary(&1) and byte_size(&1) > 0))

        _ ->
          []
      end)

    Enum.reduce_while(Enum.with_index(servers, 1), {:ok, []}, fn {entry, index}, {:ok, acc} ->
      case parse_server(entry) do
        {:ok, server} ->
          {:cont, {:ok, [server | acc]}}

        result ->
          id = if is_map(entry), do: entry["id"]

          label =
            if is_binary(id) and Regex.match?(@id, id) and
                 not Enum.any?(secrets, &String.contains?(id, &1)),
               do: "server #{id}",
               else: "server ##{index}"

          field =
            case result do
              {:error, {:field, field}} -> field
              _ -> "record"
            end

          {:halt,
           {:error,
            "MCP #{label} has invalid #{field}. No server was launched; see docs/operator/mcp.md#configure-a-local-stdio-server."}}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      error -> error
    end
  end

  defp parse_server(%{"transport" => "http"} = entry), do: parse_http_server(entry)

  defp parse_server(entry) when is_map(entry) do
    allowed = [
      "id",
      "command",
      "args",
      "tools",
      "resources",
      "prompts",
      "env",
      "timeout_ms",
      "sandbox",
      "transport"
    ]

    with :ok <- field("fields", keys?(entry, allowed)),
         :ok <- field("transport", Map.get(entry, "transport", "stdio") == "stdio"),
         id = entry["id"],
         :ok <- field("id", is_binary(id) and Regex.match?(@id, id)),
         command = entry["command"],
         :ok <- field("command", is_binary(command)),
         :ok <- field("command", executable(command)),
         {:ok, args} <- field("args", validate_args(Map.get(entry, "args", []))),
         {:ok, tools} <- field("tools", validate_tools(Map.get(entry, "tools", []))),
         {:ok, resources} <-
           field("resources", validate_resources(Map.get(entry, "resources", []))),
         {:ok, prompts} <- field("prompts", validate_prompts(Map.get(entry, "prompts", []))),
         :ok <-
           field(
             "allowlists",
             (length(tools) + length(resources) + length(prompts)) in 1..@allowlist_limit
           ),
         {:ok, sandbox} <- field("sandbox", validate_sandbox(Map.get(entry, "sandbox", "off"))),
         {:ok, env} <- field("env", validate_env(Map.get(entry, "env", %{}))),
         :ok <-
           field(
             "public-field redaction",
             public_fields_clear?(id, command, tools, resources, prompts, env)
           ),
         timeout = Map.get(entry, "timeout_ms", 30_000),
         :ok <- field("timeout_ms", is_integer(timeout) and timeout in 1..120_000) do
      {:ok,
       fingerprint_version(
         %{
           id: id,
           command: command,
           args: args,
           tools: tools,
           resources: resources,
           prompts: prompts,
           sandbox: sandbox,
           env: env,
           timeout_ms: timeout,
           transport: :stdio
         },
         2
       )}
    else
      error -> error
    end
  end

  defp parse_server(_), do: {:error, :invalid_server}

  defp parse_http_server(entry) do
    allowed =
      ~w(id transport url tools resources prompts bearer_env allow_insecure_loopback timeout_ms)

    with :ok <- field("fields", keys?(entry, allowed)),
         id = entry["id"],
         :ok <- field("id", is_binary(id) and Regex.match?(@id, id)),
         url = entry["url"],
         :ok <- field("url", is_binary(url) and byte_size(url) <= 4096),
         insecure = Map.get(entry, "allow_insecure_loopback", false),
         :ok <- field("allow_insecure_loopback", is_boolean(insecure)),
         :ok <- field("url", valid_http_endpoint?(url, insecure)),
         {:ok, tools} <- field("tools", validate_tools(Map.get(entry, "tools", []))),
         {:ok, resources} <-
           field("resources", validate_resources(Map.get(entry, "resources", []))),
         {:ok, prompts} <- field("prompts", validate_prompts(Map.get(entry, "prompts", []))),
         :ok <-
           field(
             "allowlists",
             (length(tools) + length(resources) + length(prompts)) in 1..@allowlist_limit
           ),
         {:ok, env} <- field("headers", bearer_environment(entry["bearer_env"])),
         :ok <-
           field(
             "public-field redaction",
             public_fields_clear?(id, url, tools, resources, prompts, env)
           ),
         timeout = Map.get(entry, "timeout_ms", 30_000),
         :ok <- field("timeout_ms", is_integer(timeout) and timeout in 1..120_000) do
      {:ok,
       fingerprint_version(
         %{
           id: id,
           transport: :http,
           url: url,
           command: url,
           args: [],
           tools: tools,
           resources: resources,
           prompts: prompts,
           env: env,
           sandbox: :remote,
           allow_insecure_loopback: insecure,
           timeout_ms: timeout
         },
         2
       )}
    else
      error -> error
    end
  end

  defp field(_name, value) when value in [true, :ok], do: :ok
  defp field(_name, {:ok, _} = value), do: value
  defp field(name, _), do: {:error, {:field, name}}

  defp valid_http_endpoint?(url, insecure) do
    uri = URI.parse(url)

    String.valid?(url) and not Regex.match?(~r/[\x00-\x20\x7f]/, url) and
      is_binary(uri.host) and uri.host != "" and is_nil(uri.userinfo) and
      is_nil(uri.fragment) and is_nil(uri.query) and uri.port in 1..65535 and
      Regex.match?(~r/\A[a-zA-Z0-9.\-:\[\]]+\z/, uri.host) and
      (uri.scheme == "https" or
         (uri.scheme == "http" and insecure and uri.host in ["127.0.0.1", "::1"]))
  end

  defp bearer_environment(nil), do: {:ok, %{}}

  defp bearer_environment(name) when is_binary(name) do
    value = System.get_env(name)

    if Regex.match?(@env_name, name) and name not in @blocked_env and is_binary(value) and
         byte_size(value) in 1..4096 and Regex.match?(~r/\A[A-Za-z0-9\-._~+\/=]+\z/, value),
       do: {:ok, %{name => value}},
       else: {:error, :invalid_bearer_environment}
  end

  defp bearer_environment(_), do: {:error, :invalid_bearer_environment}

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

  defp validate_tools(tools) when is_list(tools) and length(tools) <= @tool_limit do
    if Enum.all?(tools, &(is_binary(&1) and Regex.match?(@tool, &1))) and unique?(tools),
      do: {:ok, tools},
      else: {:error, :invalid_tools}
  end

  defp validate_tools(_), do: {:error, :invalid_tools}

  defp validate_resources(resources)
       when is_list(resources) and length(resources) <= @resource_limit do
    if Enum.all?(resources, &valid_resource_uri?/1) and unique?(resources),
      do: {:ok, resources},
      else: {:error, :invalid_resources}
  end

  defp validate_resources(_), do: {:error, :invalid_resources}

  defp valid_resource_uri?(uri) when is_binary(uri) do
    if String.valid?(uri) and byte_size(uri) in 1..@resource_uri_bytes and
         not String.contains?(uri, <<0>>) and not Enum.any?(String.to_charlist(uri), &(&1 < 32)) do
      parsed = URI.parse(uri)

      is_binary(parsed.scheme) and Regex.match?(~r/\A[a-z][a-z0-9+.-]*\z/i, parsed.scheme) and
        is_nil(parsed.userinfo)
    else
      false
    end
  rescue
    _ -> false
  end

  defp valid_resource_uri?(_), do: false

  defp validate_prompts(prompts) when is_list(prompts) and length(prompts) <= @prompt_limit do
    if Enum.all?(prompts, &(is_binary(&1) and Regex.match?(@prompt, &1))) and unique?(prompts),
      do: {:ok, prompts},
      else: {:error, :invalid_prompts}
  end

  defp validate_prompts(_), do: {:error, :invalid_prompts}

  defp validate_sandbox("off"), do: {:ok, :off}
  defp validate_sandbox("native"), do: {:ok, :native}
  defp validate_sandbox(_), do: {:error, :invalid_sandbox}

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

  defp public_fields_clear?(id, command, tools, resources, prompts, env) do
    values = [id, command] ++ tools ++ resources ++ prompts ++ Map.keys(env)
    not Enum.any?(values, &contains_private?(&1, %{env: env}))
  end

  defp unique?(values), do: length(values) == length(Enum.uniq(values))

  defp all_secrets(servers) do
    servers
    |> Enum.flat_map(&Map.values(&1.env))
    |> Enum.filter(&(is_binary(&1) and byte_size(&1) > 0))
    |> Enum.uniq()
    |> Enum.sort_by(&{-byte_size(&1), &1})
  end

  defp public_manifests_clear?(servers, secrets) do
    Enum.all?(servers, fn server ->
      public = manifest(server)
      not Enum.any?(secrets, &contains_secret?(public, &1))
    end)
  end

  defp contains_secret?(value, secret) when is_binary(value),
    do: String.contains?(value, secret)

  defp contains_secret?(value, secret) when is_map(value),
    do:
      Enum.any?(value, fn {key, item} ->
        contains_secret?(key, secret) or contains_secret?(item, secret)
      end)

  defp contains_secret?(value, secret) when is_list(value),
    do: Enum.any?(value, &contains_secret?(&1, secret))

  defp contains_secret?(_, _), do: false

  defp model_ids(server) do
    Enum.map(server.tools, &tool_id(server.id, &1)) ++
      Enum.map(server.resources, &resource_id(server.id, &1)) ++
      Enum.map(server.prompts, &prompt_id(server.id, &1))
  end

  defp digest(value) do
    value
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 31)
  end

  defp keys?(map, allowed), do: Enum.all?(Map.keys(map), &(&1 in allowed))
end
