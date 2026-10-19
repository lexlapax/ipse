defmodule Ipse.Extensions.MCPCall do
  @moduledoc "Operator-bound MCP calls using the existing owned transports and exact approval."
  alias Ipse.MCP.{Client, Config, Schema}
  alias Ipse.Extensions.EffectResult

  @error {:error, :invalid_extension_mcp_call}
  @refused {:failed, %{"code" => "mcp_refused"}}
  @unknown {:unknown, %{}}

  def operation?(request), do: is_map(request) and request["op"] == "mcp.call"

  def validate(request) do
    if keys?(request, ~w(op version binding arguments timeout_ms)) and operation?(request) and
         request["version"] === 1 and alias?(request["binding"]) and
         is_map(request["arguments"]) and is_integer(request["timeout_ms"]) and
         request["timeout_ms"] in 1..30_000 and Ipse.Extension.validate(request) == :ok,
       do: :ok,
       else: @error
  rescue
    _ -> @error
  end

  def trust_bindings?(bindings) do
    is_list(bindings) and length(bindings) <= 64 and
      Enum.all?(bindings, fn binding ->
        keys?(binding, ~w(instance alias tool)) and instance?(binding["instance"]) and
          alias?(binding["alias"]) and tool_id?(binding["tool"])
      end) and unique?(Enum.map(bindings, &{&1["instance"], &1["alias"]}))
  rescue
    _ -> false
  end

  def public_bindings?(bindings) do
    is_list(bindings) and length(bindings) <= 8 and
      Enum.all?(bindings, fn binding ->
        keys?(binding, ~w(alias tool)) and alias?(binding["alias"]) and tool_id?(binding["tool"])
      end) and unique?(Enum.map(bindings, & &1["alias"])) and
      bindings == Enum.sort_by(bindings, & &1["alias"])
  rescue
    _ -> false
  end

  def bindings(trust, instance) do
    entries = Map.get(trust, "mcp_bindings", [])

    if trust_bindings?(entries) and instance?(instance) do
      entries
      |> Enum.filter(&(&1["instance"] == instance))
      |> Enum.map(&Map.drop(&1, ["instance"]))
      |> Enum.sort_by(& &1["alias"])
    else
      []
    end
  rescue
    _ -> []
  end

  def target(config, identity, request) do
    with :ok <- validate(request),
         true <- is_nil(config[:delegation_origin]) and config[:parallel_child] != true,
         true <- authorized_identity?(identity),
         selected when is_map(selected) <-
           Enum.find(identity["mcp_bindings"], &(&1["alias"] == request["binding"])),
         servers when is_list(servers) <- config[:mcp_servers] || [],
         matches = Enum.filter(servers, &(selected["tool"] in configured_ids(&1))),
         [server] <- matches do
      {:ok, server, selected["tool"]}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def discover(server, tool_id, request, cwd, resource) do
    with :ok <- validate(request),
         true <- tool_id?(tool_id) and tool_id in configured_ids(server),
         true <- is_binary(cwd) and resource?(resource),
         {:ok, descriptors} <-
           bounded(fn -> Client.discover(server, cwd, resource) end, request["timeout_ms"]),
         descriptor when is_map(descriptor) <-
           Enum.find(descriptors, &(&1.tool_id == tool_id)),
         true <- descriptor.server === server,
         :ok <- Ipse.MCP.validate_call(descriptor, request["arguments"]),
         public = binding(descriptor, request["binding"]),
         true <- not Config.contains_private?(public, server) do
      {:ok, descriptor, public}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  def binding(descriptor, name) do
    %{
      "kind" => "mcp",
      "version" => 1,
      "alias" => name,
      "manifest" => json(Client.manifest(descriptor)),
      "server" => json(Config.manifest(descriptor.server)),
      "schema" => descriptor.input_schema
    }
  end

  def valid_binding?(binding, request, identity, metadata \\ nil) do
    with :ok <- validate(request),
         true <- authorized_identity?(identity),
         true <- keys?(binding, ~w(kind version alias manifest server schema)),
         true <- binding["kind"] == "mcp" and binding["version"] === 1,
         true <- binding["alias"] == request["binding"],
         selected when is_map(selected) <-
           Enum.find(identity["mcp_bindings"], &(&1["alias"] == request["binding"])),
         manifest = binding["manifest"],
         server = binding["server"],
         true <- public_server?(server),
         true <- public_manifest?(manifest, server),
         true <- manifest["tool_id"] == selected["tool"],
         :ok <- Schema.validate_arguments(binding["schema"], request["arguments"]),
         true <- binding["schema"]["type"] == "object",
         true <- byte_size(Jason.encode!(request["arguments"], pretty: true)) <= 32_768,
         true <- metadata?(metadata, server["fingerprint"]) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def execute(context, intent) do
    request = intent["request"]
    descriptor = context[:mcp_descriptor]
    resource = %{owner: context[:owner], job_ref: context[:job_ref]}

    with :ok <- validate(request),
         true <- is_map(descriptor) and resource?(resource),
         true <- binding(descriptor, request["binding"]) === intent["effect_binding"],
         :ok <- Ipse.MCP.validate_call(descriptor, request["arguments"]) do
      case bounded(
             fn -> Client.call(descriptor, request["arguments"], context.cwd, resource) end,
             request["timeout_ms"]
           ) do
        {:ok, text} when is_binary(text) -> persist_source(context, intent, text)
        {:error, _} -> @refused
        _ -> @unknown
      end
    else
      _ -> @refused
    end
  rescue
    _ -> @unknown
  catch
    _, _ -> @unknown
  end

  def valid_outcome?(_request, status, value, _) when status in ~w(unknown denied),
    do: value == %{}

  def valid_outcome?(_request, "failed", value, _), do: value === elem(@refused, 1)

  def valid_outcome?(request, "ok", value, operation_id),
    do: validate(request) == :ok and EffectResult.descriptor?(value, operation_id)

  def valid_outcome?(_, _, _, _), do: false

  defp persist_source(context, intent, text) do
    if String.valid?(text) and byte_size(text) <= 65_536 and
         not Config.contains_private?(text, context.mcp_descriptor.server) do
      case GenServer.call(
             context.owner,
             {:extension_effect_source, context.job_ref, intent, "mcp.text", %{"text" => text}},
             :infinity
           ) do
        {:ok, source} ->
          if EffectResult.valid_source?(source, intent),
            do: {:ok, EffectResult.descriptor(source)},
            else: @unknown

        _ ->
          @unknown
      end
    else
      @unknown
    end
  end

  defp bounded(fun, timeout) do
    task =
      Ipse.TaskResources.async(fn ->
        try do
          fun.()
        rescue
          _ -> @unknown
        catch
          _, _ -> @unknown
        end
      end)

    case Task.yield(task, timeout) do
      {:ok, result} ->
        result

      _ ->
        Task.shutdown(task, :brutal_kill)
        @unknown
    end
  end

  defp authorized_identity?(identity) do
    is_map(identity) and identity["scope"] == "operator" and
      is_list(identity["capabilities"]) and "host.mcp" in identity["capabilities"] and
      "host.actions" in identity["capabilities"] and
      public_bindings?(identity["mcp_bindings"])
  end

  defp configured_ids(server) do
    Enum.map(server.tools, &Config.tool_id(server.id, &1)) ++
      Enum.map(Map.get(server, :resources, []), &Config.resource_id(server.id, &1)) ++
      Enum.map(Map.get(server, :prompts, []), &Config.prompt_id(server.id, &1))
  end

  defp public_manifest?(manifest, server) do
    base = ~w(schema_version tool_id server_id name origin descriptor_sha256 risk)
    kind = if is_map(manifest), do: Map.get(manifest, "kind", "tool")
    keys = if kind == "tool", do: base, else: base ++ ~w(kind source)

    keys?(manifest, keys) and manifest["schema_version"] === 1 and
      manifest["server_id"] == server["id"] and hash?(manifest["descriptor_sha256"]) and
      manifest["risk"] == "external_requires_approval" and
      keys?(manifest["origin"], ~w(transport configured_endpoint_fingerprint sandbox_requested)) and
      manifest["origin"]["transport"] == Map.get(server, "transport", "stdio") and
      manifest["origin"]["sandbox_requested"] == server["sandbox"] and
      manifest["origin"]["configured_endpoint_fingerprint"] == server["fingerprint"] and
      manifest_target?(kind, manifest, server)
  end

  defp manifest_target?("tool", manifest, server) do
    manifest["name"] in server["tools"] and
      manifest["tool_id"] == Config.tool_id(server["id"], manifest["name"])
  end

  defp manifest_target?("resource", manifest, server) do
    manifest["source"] in server["resources"] and manifest["name"] == manifest["source"] and
      manifest["tool_id"] == Config.resource_id(server["id"], manifest["source"])
  end

  defp manifest_target?("prompt", manifest, server) do
    manifest["source"] in server["prompts"] and manifest["name"] == manifest["source"] and
      manifest["tool_id"] == Config.prompt_id(server["id"], manifest["source"])
  end

  defp manifest_target?(_, _, _), do: false

  defp public_server?(server) do
    base = ~w(id tools resources prompts sandbox env_names timeout_ms fingerprint)
    http = is_map(server) and server["transport"] == "streamable_http"

    keys =
      if http,
        do: base ++ ~w(transport endpoint allow_insecure_loopback),
        else: base ++ ~w(command args)

    keys?(server, keys) and server_id?(server["id"]) and hash?(server["fingerprint"]) and
      is_integer(server["timeout_ms"]) and server["timeout_ms"] in 1..120_000 and
      names?(server["tools"], 16, &tool_name?/1) and
      names?(server["prompts"], 16, &tool_name?/1) and
      names?(server["resources"], 16, &resource_uri?/1) and
      (length(server["tools"]) + length(server["prompts"]) + length(server["resources"])) in 1..16 and
      names?(server["env_names"], 16, &env_name?/1) and
      server["env_names"] == Enum.sort(server["env_names"]) and
      server_transport?(server, http) and fingerprint_matches?(server, http)
  end

  defp server_transport?(server, true) do
    server["sandbox"] == "remote" and length(server["env_names"]) <= 1 and
      is_boolean(server["allow_insecure_loopback"]) and
      endpoint?(server["endpoint"], server["allow_insecure_loopback"])
  end

  defp server_transport?(server, false) do
    server["sandbox"] in ~w(off native) and text?(server["command"], 4096) and
      Path.type(server["command"]) == :absolute and
      not String.contains?(server["command"], <<0>>) and
      is_list(server["args"]) and length(server["args"]) <= 16 and
      Enum.all?(server["args"], &(text?(&1, 4096) and not String.contains?(&1, <<0>>))) and
      Enum.reduce(server["args"], 0, &(byte_size(&1) + &2)) <= 16_384
  end

  defp fingerprint_matches?(server, http),
    do: server["fingerprint"] == server_fingerprint(server, http)

  defp server_fingerprint(server, true) do
    term_digest(
      {:http,
       {server["id"], server["endpoint"], server["tools"], server["resources"], server["prompts"],
        List.first(server["env_names"]), server["allow_insecure_loopback"], server["timeout_ms"]}}
    )
  end

  defp server_fingerprint(server, false) do
    base =
      {server["id"], server["command"], server["args"], server["tools"], server["env_names"],
       server["timeout_ms"]}

    sandbox = if server["sandbox"] == "native", do: :native, else: :off

    value =
      if sandbox == :off and server["resources"] == [] and server["prompts"] == [],
        do: base,
        else: {base, sandbox, server["resources"], server["prompts"]}

    term_digest(value)
  end

  defp endpoint?(value, insecure) do
    if text?(value, 4096) and not Regex.match?(~r/[\x00-\x20\x7f]/, value) do
      uri = URI.parse(value)

      is_binary(uri.host) and uri.host != "" and is_nil(uri.userinfo) and
        is_nil(uri.fragment) and is_nil(uri.query) and uri.port in 1..65535 and
        Regex.match?(~r/\A[a-zA-Z0-9.\-:\[\]]+\z/, uri.host) and
        (uri.scheme == "https" or
           (uri.scheme == "http" and insecure and uri.host in ["127.0.0.1", "::1"]))
    else
      false
    end
  end

  defp metadata?(nil, _), do: true

  defp metadata?(metadata, fingerprint),
    do:
      is_map(metadata) and is_list(metadata["mcp_servers"]) and
        fingerprint in metadata["mcp_servers"]

  defp resource?(value),
    do: is_map(value) and is_pid(value[:owner]) and is_reference(value[:job_ref])

  defp names?(values, limit, predicate),
    do:
      is_list(values) and length(values) <= limit and unique?(values) and
        Enum.all?(values, predicate)

  defp unique?(values), do: length(values) == length(Enum.uniq(values))
  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
  defp alias?(value), do: is_binary(value) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,31}\z/, value)

  defp instance?(value),
    do: is_binary(value) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, value)

  defp tool_id?(value),
    do:
      is_binary(value) and byte_size(value) <= 64 and
        Regex.match?(
          ~r/\Amcp__[a-z][a-z0-9_]{0,23}__(?:[A-Za-z0-9_-]{1,32}|[rp]_[0-9a-f]{31})\z/,
          value
        )

  defp server_id?(value),
    do: is_binary(value) and Regex.match?(~r/\A[a-z][a-z0-9_]{0,23}\z/, value)

  defp tool_name?(value),
    do: is_binary(value) and Regex.match?(~r/\A[A-Za-z0-9_.-]{1,32}\z/, value)

  defp env_name?(value),
    do:
      is_binary(value) and Regex.match?(~r/\A[A-Z_][A-Z0-9_]{0,63}\z/, value) and
        value not in ~w(OPENAI_API_KEY ANTHROPIC_API_KEY IPSE_CHATGPT_ACCESS_TOKEN)

  defp resource_uri?(value),
    do:
      text?(value, 2048) and byte_size(value) > 0 and
        not Enum.any?(String.to_charlist(value), &(&1 < 32)) and
        is_binary(URI.parse(value).scheme) and
        Regex.match?(~r/\A[a-z][a-z0-9+.-]*\z/i, URI.parse(value).scheme) and
        is_nil(URI.parse(value).userinfo)

  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)

  defp text?(value, limit),
    do: is_binary(value) and String.valid?(value) and byte_size(value) <= limit

  defp json(value), do: value |> Jason.encode!() |> Jason.decode!()

  defp term_digest(value),
    do:
      value
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
end
