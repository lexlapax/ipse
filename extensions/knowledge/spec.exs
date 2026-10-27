defmodule IpseKnowledge.BuildSpec do
  @moduledoc false
  @presets %{
    "knowledge" => ~w(native),
    "corpus" =>
      ~w(state-lexical state-dense state-rerank state-semantic mcp-lexical mcp-dense mcp-rerank mcp-semantic),
    "research" => ~w(offline mcp mcp-model),
    "graph" => ~w(state-explicit state-model mcp-explicit mcp-model)
  }
  @modules %{
    "knowledge" => IpseKnowledge.Knowledge,
    "corpus" => IpseKnowledge.Corpus,
    "research" => IpseKnowledge.Research,
    "graph" => IpseKnowledge.Graph
  }
  @defaults %{
    "knowledge" => "native",
    "corpus" => "state-lexical",
    "research" => "offline",
    "graph" => "state-explicit"
  }
  @families ~w(stores search fetch retrieval embedding rerank extraction)

  def selection!(package, preset) do
    unless preset in Map.get(@presets, package, []),
      do: raise(ArgumentError, "Select a documented package and preset.")

    Map.fetch!(@modules, package)
  end

  def default(package), do: Map.fetch!(@defaults, package)

  def options_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["version" | @families],
      "properties" =>
        Map.new(@families, &{&1, %{"type" => "object"}})
        |> Map.put("version", %{"type" => "integer", "enum" => [1]})
    }
  end

  def digest(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

  def read_json!(path, limit) do
    %{type: :regular, size: size} = File.lstat!(path)
    unless size <= limit, do: raise(ArgumentError, "Input file exceeds its byte limit.")
    JSON.decode!(File.read!(path))
  end

  def operator(
        manifest_bytes,
        package,
        preset,
        instance,
        options,
        state_id,
        bindings,
        inference \\ %{}
      ) do
    module = selection!(package, preset)
    manifest = JSON.decode!(manifest_bytes)
    caps = IpseKnowledge.Profiles.capabilities(package, preset)

    unless manifest["sdk"] === 2 and manifest["id"] == "ipse-knowledge/" <> package and
             manifest["entrypoint"] ==
               String.replace_prefix(Atom.to_string(module), "Elixir.", "") and
             manifest["capabilities"] == caps and manifest["options_schema"] == options_schema(),
           do: raise(ArgumentError, "Artifact does not match the selected package and preset.")

    unless is_binary(instance) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, instance),
      do: raise(ArgumentError, "Invalid instance name.")

    exports = manifest["exports"]

    unless is_map(exports) and
             Enum.all?(~w(commands tools services), fn group ->
               is_list(exports[group]) and
                 Enum.all?(exports[group], fn entry ->
                   is_map(entry) and is_binary(entry["id"]) and
                     byte_size("ext__" <> instance <> "__" <> entry["id"]) <= 64
                 end)
             end),
           do: raise(ArgumentError, "Instance produces an invalid export name.")

    case IpseKnowledge.Profiles.validate(package, preset, options) do
      {:ok, _} -> :ok
      _ -> raise ArgumentError, "Options do not match the selected preset."
    end

    unless is_map(inference) and
             Enum.all?(Map.keys(inference), &(&1 in ~w(profiles embedding_profiles budget))) and
             Enum.all?(~w(profiles embedding_profiles), fn family ->
               is_map(Map.get(inference, family, %{}))
             end),
           do:
             raise(
               ArgumentError,
               "Inference input accepts only explicit profiles, embedding_profiles and budget."
             )

    references =
      Enum.map(Map.values(options["embedding"]), &{"embedding_profiles", &1["profile"]}) ++
        for family <- ~w(rerank extraction),
            profile <- Map.values(options[family]),
            profile["kind"] == "model_complete",
            do: {"profiles", profile["profile"]}

    unless Enum.all?(references, fn {registry, name} ->
             profile = get_in(inference, [registry, name])
             is_map(profile) and is_binary(profile["provider"]) and is_binary(profile["model"])
           end),
           do: raise(ArgumentError, "Supply the selected host inference profiles explicitly.")

    scopes =
      options["stores"]
      |> Map.values()
      |> Enum.filter(&(&1["kind"] == "state"))
      |> Enum.map(& &1["scope"])
      |> Enum.uniq()
      |> Enum.sort()

    aliases =
      for family <- @families,
          profile <- Map.values(options[family]),
          Map.has_key?(profile, "binding"),
          do: profile["binding"]

    aliases = Enum.sort(Enum.uniq(aliases))

    unless length(aliases) <= 8,
      do: raise(ArgumentError, "One artifact identity supports at most eight MCP aliases.")

    unless is_map(bindings) and Enum.sort(Map.keys(bindings)) == aliases and
             Enum.all?(bindings, fn {name, tool} ->
               Regex.match?(~r/\A[a-z][a-z0-9_-]{0,31}\z/, name) and is_binary(tool) and
                 byte_size(tool) <= 64 and
                 Regex.match?(
                   ~r/\Amcp__[a-z][a-z0-9_]{0,23}__(?:[A-Za-z0-9_-]{1,32}|[rp]_[0-9a-f]{31})\z/,
                   tool
                 )
             end),
           do: raise(ArgumentError, "Supply exactly the selected MCP aliases and tool IDs.")

    state_bindings =
      if scopes == [] do
        unless is_nil(state_id), do: raise(ArgumentError, "This preset has no State binding.")
        []
      else
        unless is_binary(state_id) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, state_id),
          do: raise(ArgumentError, "Supply an explicit logical State binding ID.")

        [%{"version" => 1, "instance" => instance, "id" => state_id, "scopes" => scopes}]
      end

    artifact = digest(manifest_bytes)

    trust = %{
      "artifact" => artifact,
      "capabilities" => caps,
      "allow_project" => false,
      "allow_children" => false,
      "state_bindings" => state_bindings,
      "mcp_bindings" =>
        Enum.map(Enum.sort(bindings), fn {name, tool} ->
          %{"instance" => instance, "alias" => name, "tool" => tool}
        end)
    }

    config = %{
      "version" => 1,
      "extensions" => [
        %{
          "instance" => instance,
          "artifact" => artifact,
          "enabled" => false,
          "options" => options,
          "order" => 0,
          "lifetime" => "session"
        }
      ],
      "extension_trust" => [trust]
    }

    config = Map.merge(config, inference)

    unless byte_size(IO.iodata_to_binary(JSON.encode!(config))) <= 16_384,
      do: raise(ArgumentError, "Generated operator configuration exceeds the host object limit.")

    config
  end
end
