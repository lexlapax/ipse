defmodule Ipse.Extension.Config do
  @moduledoc "Data-only extension selection with an operator trust ceiling and scoped instances."
  alias Ipse.JSON, as: Schema
  @error {:error, "Invalid extension configuration or operator trust policy."}
  @identifier %{"type" => "string", "minLength" => 1, "maxLength" => 128}

  def schema do
    %{
      "extensions" => %{"type" => "array", "maxItems" => 8, "items" => instance_schema()},
      "extension_trust" => %{"type" => "array", "maxItems" => 16, "items" => trust_schema()}
    }
  end

  def validate(data) do
    with :ok <- Schema.validate_arguments(%{"type" => "object", "properties" => schema()}, data),
         instances = Map.get(data, "extensions", []),
         trust = Map.get(data, "extension_trust", []),
         true <- unique?(Enum.map(instances, & &1["instance"])),
         true <- unique?(Enum.map(trust, & &1["artifact"])),
         true <- Enum.all?(instances, &valid_instance?/1),
         true <- Enum.all?(trust, &valid_trust?/1) do
      :ok
    else
      _ -> @error
    end
  end

  @doc "Resolve reviewed configuration only; never inspect, load or run extension code."
  def resolve(sources, opts) do
    with true <- Enum.all?(sources, &(validate(&1.data) == :ok)),
         true <-
           Enum.all?(
             sources,
             &(&1.scope == "operator" or not Map.has_key?(&1.data, "extension_trust"))
           ),
         {:ok, policy} <- merge_sources(sources),
         {:ok, instances} <- select(policy.instances, opts),
         true <- Enum.all?(instances, &admitted?(&1, policy.trust)) do
      {:ok, %{"instances" => sort(instances), "trust" => sort_trust(policy.trust)}}
    else
      _ -> @error
    end
  end

  @doc "Inspect identity and options digests without printing extension option contents."
  def inspect_config(config) do
    Map.update!(config, "instances", fn instances ->
      Enum.map(instances, fn instance ->
        instance
        |> Map.delete("options")
        |> Map.put("options_sha256", Ipse.JSON.digest([instance["options"]]))
      end)
    end)
  end

  defp instance_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ~w(instance artifact enabled options order lifetime),
      "properties" => %{
        "instance" => @identifier,
        "artifact" => @identifier,
        "enabled" => %{"type" => "boolean"},
        "options" => %{"type" => "object"},
        "order" => %{"type" => "integer", "minimum" => 0, "maximum" => 1000},
        "lifetime" => %{"type" => "string", "enum" => ~w(session persistent)},
        "expires_at" => %{"type" => "integer", "minimum" => 0}
      }
    }
  end

  defp trust_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ~w(artifact capabilities allow_project allow_children),
      "properties" => %{
        "artifact" => @identifier,
        "capabilities" => %{"type" => "array", "maxItems" => 32, "items" => @identifier},
        "allow_project" => %{"type" => "boolean"},
        "allow_children" => %{"type" => "boolean"},
        "text_required" => %{"type" => "boolean"},
        "mcp_bindings" => %{
          "type" => "array",
          "maxItems" => 64,
          "items" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ~w(instance alias tool),
            "properties" => Map.new(~w(instance alias tool), &{&1, @identifier})
          }
        },
        "state_bindings" => %{
          "type" => "array",
          "maxItems" => 8,
          "items" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ~w(version instance id scopes),
            "properties" => %{
              "version" => %{"type" => "integer", "enum" => [1]},
              "instance" => @identifier,
              "id" => @identifier,
              "scopes" => %{
                "type" => "array",
                "minItems" => 1,
                "maxItems" => 3,
                "items" => %{"type" => "string", "enum" => ~w(operator project session)}
              }
            }
          }
        },
        "service_bindings" => %{
          "type" => "array",
          "maxItems" => 64,
          "items" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ~w(caller alias target artifact service),
            "properties" => Map.new(~w(caller alias target artifact service), &{&1, @identifier})
          }
        },
        "expires_at" => %{"type" => "integer", "minimum" => 0}
      }
    }
  end

  defp merge_sources(sources) do
    Enum.reduce_while(sources, {:ok, %{instances: %{}, trust: %{}}}, fn source, {:ok, acc} ->
      trust = Map.new(Map.get(source.data, "extension_trust", []), &{&1["artifact"], &1})

      instances =
        Map.new(Map.get(source.data, "extensions", []), fn instance ->
          {instance["instance"],
           Map.merge(instance, %{"scope" => source.scope, "source" => source.path})}
        end)

      next = %{instances: Map.merge(acc.instances, instances), trust: Map.merge(acc.trust, trust)}

      if map_size(next.instances) <= 8 and map_size(next.trust) <= 16,
        do: {:cont, {:ok, next}},
        else: {:halt, @error}
    end)
  end

  defp select(instances, opts) do
    selected = Keyword.get_values(opts, :extension)

    cond do
      not unique?(selected) or not Enum.all?(selected, &Map.has_key?(instances, &1)) ->
        @error

      selected != [] and opts[:extensions] == false ->
        @error

      true ->
        {:ok,
         Enum.map(instances, fn {id, instance} ->
           cond do
             opts[:extensions] == false -> Map.put(instance, "enabled", false)
             id in selected -> Map.merge(instance, %{"enabled" => true, "lifetime" => "session"})
             true -> instance
           end
         end)}
    end
  end

  defp admitted?(%{"enabled" => false}, _trust), do: true

  defp admitted?(instance, trust) do
    case trust[instance["artifact"]] do
      nil ->
        false

      ceiling ->
        instance["scope"] == "operator" or
          (ceiling["allow_project"] and
             not Enum.any?(
               Map.get(ceiling, "state_bindings", []),
               &(&1["instance"] == instance["instance"])
             ) and
             not Enum.any?(
               Map.get(ceiling, "mcp_bindings", []),
               &(&1["instance"] == instance["instance"])
             ))
    end
  end

  defp valid_instance?(instance) do
    Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, instance["instance"]) and
      artifact?(instance["artifact"]) and is_integer(instance["order"]) and
      (not Map.has_key?(instance, "expires_at") or is_integer(instance["expires_at"]))
  end

  defp valid_trust?(trust) do
    artifact?(trust["artifact"]) and unique?(trust["capabilities"]) and
      (trust["text_required"] != true or "stream.text" in trust["capabilities"]) and
      valid_state_bindings?(Map.get(trust, "state_bindings", [])) and
      Ipse.Extension.MCPCall.trust_bindings?(Map.get(trust, "mcp_bindings", [])) and
      Ipse.Extension.Services.validate_bindings(Map.get(trust, "service_bindings", [])) and
      Enum.all?(trust["capabilities"], &Regex.match?(~r/\A[a-z][a-z0-9_.-]{0,127}\z/, &1)) and
      (not Map.has_key?(trust, "expires_at") or is_integer(trust["expires_at"]))
  end

  defp valid_state_bindings?(bindings) do
    unique?(Enum.map(bindings, & &1["instance"])) and
      Enum.all?(bindings, fn binding ->
        Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, binding["instance"]) and
          Ipse.Extension.State.valid_binding?(Map.delete(binding, "instance"))
      end)
  end

  defp artifact?(id),
    do: Regex.match?(~r/\A(?:[a-f0-9]{64}|builtin:[a-z][a-z0-9_-]{0,63}:[1-9][0-9]{0,3})\z/, id)

  defp unique?(values), do: length(values) == length(Enum.uniq(values))
  defp sort(instances), do: Enum.sort_by(instances, &{&1["order"], &1["instance"]})
  defp sort_trust(trust), do: trust |> Map.values() |> Enum.sort_by(& &1["artifact"])
end

defmodule Ipse.Extension.Registry do
  @moduledoc "Inert built-in metadata and explicit pinned session admission."
  alias Ipse.Extension.Artifact
  @error {:error, :extension_admission_refused}
  @host_capabilities Ipse.Extension.Catalog.capabilities()
  @text %{"type" => "string", "maxLength" => 4096}
  @builtins %{
    "builtin:working-memory:1" => %{
      module: Ipse.Builtins.WorkingMemory,
      modules: [
        Ipse.Builtins.WorkingMemory,
        Ipse.Builtins.Memory,
        Ipse.Builtins.Memory.Records
      ],
      capabilities: Ipse.Builtins.Memory.capabilities(),
      state_scope_option: "scope",
      exports: Ipse.Builtins.Memory.exports(),
      schema: Ipse.Builtins.Memory.options_schema(["session"])
    },
    "builtin:persistent-memory:1" => %{
      module: Ipse.Builtins.Memory,
      modules: [Ipse.Builtins.Memory, Ipse.Builtins.Memory.Records],
      capabilities: ["host.state.bound" | Ipse.Builtins.Memory.capabilities()],
      state_scope_option: "scope",
      exports: Ipse.Builtins.Memory.exports(),
      schema: Ipse.Builtins.Memory.options_schema(~w(project operator))
    },
    "builtin:cost-tree:1" => %{
      module: Ipse.Builtins.CostTree,
      modules: [Ipse.Builtins.CostTree, Ipse.Usage.Costs],
      capabilities:
        ~w(invoke.command host.actions host.usage host.usage.scan host.usage.children),
      exports: Ipse.Builtins.CostTree.exports(),
      schema: %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["rate_card"],
        "properties" => %{"rate_card" => Ipse.Usage.Costs.schema()}
      }
    },
    "builtin:cost-summary:1" => %{
      module: Ipse.Builtins.CostSummary,
      modules: [Ipse.Builtins.CostSummary, Ipse.Usage.Costs],
      capabilities: ~w(invoke.command host.actions host.usage host.usage.scan),
      exports: Ipse.Builtins.CostSummary.exports(),
      schema: %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["rate_card"],
        "properties" => %{"rate_card" => Ipse.Usage.Costs.schema()}
      }
    },
    "builtin:cost-report:1" => %{
      module: Ipse.Builtins.CostReport,
      modules: [Ipse.Builtins.CostReport, Ipse.Usage.Costs],
      capabilities: ~w(invoke.command host.actions host.usage),
      exports: Ipse.Builtins.CostReport.exports(),
      schema: %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["rate_card"],
        "properties" => %{"rate_card" => Ipse.Usage.Costs.schema()}
      }
    },
    "builtin:local-trace:1" => %{
      module: Ipse.Builtins.LocalTrace,
      capabilities: ["observe.local"],
      schema: %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["directory"],
        "properties" => %{
          "directory" => %{"type" => "string", "minLength" => 1, "maxLength" => 1024},
          "retained_leases" => %{"type" => "integer", "minimum" => 1, "maximum" => 32}
        }
      }
    },
    "builtin:prompt-annotation:1" => %{
      module: Ipse.Builtins.PromptAnnotation,
      capabilities: ["transform.prompt"],
      schema: %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["text"],
        "properties" => %{"text" => @text}
      }
    },
    "builtin:answer-format:1" => %{
      module: Ipse.Builtins.AnswerFormat,
      capabilities: ["transform.presentation"],
      schema: %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["prefix", "suffix"],
        "properties" => %{"prefix" => @text, "suffix" => @text}
      }
    }
  }

  @doc "Static descriptors only; discovery never invokes extension functions."
  def builtins do
    Enum.map(@builtins, fn {id, metadata} ->
      %{
        "artifact" => id,
        "sdk" => 1,
        "capabilities" => metadata.capabilities,
        "options_schema" => metadata.schema
      }
    end)
    |> Enum.sort_by(& &1["artifact"])
  end

  @doc "Lookup a compiled built-in or verify an independently installed artifact."
  def lookup(store, reference) when is_binary(reference) do
    case @builtins[reference] do
      nil -> Artifact.lookup(store, reference)
      metadata -> builtin(reference, metadata)
    end
  end

  def lookup(_, _), do: @error

  @doc "Prepare exact ordered identities outside the Session process; no code executes."
  def prepare(catalog, home, child? \\ false, now \\ System.system_time(:second)) do
    trust = Map.new(catalog["trust"], &{&1["artifact"], &1})
    store = Path.join(home, "extensions/artifacts")

    catalog["instances"]
    |> Enum.filter(& &1["enabled"])
    |> Enum.reduce_while({:ok, []}, fn instance, {:ok, entries} ->
      ceiling = trust[instance["artifact"]]

      with true <- is_map(ceiling),
           true <- instance["scope"] == "operator" or ceiling["allow_project"] == true,
           true <- not child? or ceiling["allow_children"] == true,
           true <- live?(instance, now) and live?(ceiling, now),
           {:ok, artifact} <- lookup(store, instance["artifact"]),
           true <- Artifact.compatible?(artifact.manifest),
           capabilities = artifact.manifest["capabilities"],
           binding =
             Enum.find(
               Map.get(ceiling, "state_bindings", []),
               &(&1["instance"] == instance["instance"])
             ),
           true <- selected_state_scope?(instance["artifact"], instance["options"], binding),
           true <-
             Enum.all?(
               capabilities,
               &(&1 in @host_capabilities and &1 in ceiling["capabilities"])
             ),
           :ok <-
             Ipse.JSON.validate_arguments(
               artifact.manifest["options_schema"],
               instance["options"]
             ) do
        identity = %{
          "instance" => instance["instance"],
          "artifact" => instance["artifact"],
          "artifact_sha256" => artifact.digest,
          "options_sha256" => Ipse.JSON.digest([instance["options"]]),
          "exports_sha256" => Ipse.Extension.Catalog.digest(artifact.manifest["exports"]),
          "requires_sha256" => Ipse.Extension.Services.digest(artifact.manifest["requires"]),
          "subscriptions_sha256" =>
            Ipse.Extension.Subscriptions.digest(artifact.manifest["subscriptions"]),
          "services" => [],
          "scope" => instance["scope"],
          "source_sha256" => Ipse.JSON.sha256(instance["source"]),
          "sdk" => artifact.manifest["sdk"],
          "protocol" => 1,
          "capabilities" => capabilities,
          "order" => instance["order"],
          "lifetime" => instance["lifetime"],
          "allow_children" => ceiling["allow_children"],
          "expires_at" => earliest(instance["expires_at"], ceiling["expires_at"]),
          "runtime" => runtime(),
          "host_sha256" => host_digest(),
          "generation" => 1
        }

        identity =
          if ceiling["text_required"] == true,
            do: Map.put(identity, "text_required", true),
            else: identity

        identity =
          if binding,
            do: Map.put(identity, "state_binding", Map.delete(binding, "instance")),
            else: identity

        mcp_bindings = Ipse.Extension.MCPCall.bindings(ceiling, instance["instance"])

        identity =
          if mcp_bindings == [],
            do: identity,
            else: Map.put(identity, "mcp_bindings", mcp_bindings)

        {:cont,
         {:ok,
          entries ++
            [
              %{
                identity: identity,
                options: instance["options"],
                store: store,
                exports: artifact.manifest["exports"] || Ipse.Extension.Catalog.empty(),
                requires: artifact.manifest["requires"] || Ipse.Extension.Services.empty(),
                subscriptions: artifact.manifest["subscriptions"] || [],
                bindings:
                  Enum.filter(
                    Map.get(ceiling, "service_bindings", []),
                    &(&1["caller"] == instance["instance"])
                  )
              }
            ]}}
      else
        _ -> {:halt, @error}
      end
    end)
    |> case do
      {:ok, entries} ->
        with {:ok, entries} <- Ipse.Extension.Services.resolve(entries),
             true <- valid_entries?(%{extensions: entries}, now) do
          {:ok, entries}
        else
          _ -> @error
        end

      _ ->
        @error
    end
  rescue
    _ -> @error
  end

  def manifests(config), do: Enum.map(Map.get(config, :extensions, []), & &1.identity)

  def child_entries(config),
    do: Enum.filter(Map.get(config, :extensions, []), & &1.identity["allow_children"])

  def valid_entries?(config, now \\ System.system_time(:second)) do
    entries = Map.get(config, :extensions, [])

    is_list(entries) and length(entries) <= 8 and
      length(Ipse.Extension.Subscriptions.all_declarations(config)) <= 8 and
      Enum.count(entries, &("stream.text" in &1.identity["capabilities"])) <= 4 and
      Enum.all?(entries, fn entry ->
        is_map(entry) and
          Enum.sort(Map.keys(entry)) == [
            :bindings,
            :exports,
            :identity,
            :options,
            :requires,
            :store,
            :subscriptions
          ] and
          Ipse.Extension.Projection.identity_valid?(entry.identity) and
          live?(entry.identity, now) and
          Enum.all?(entry.identity["capabilities"], &(&1 in @host_capabilities)) and
          Ipse.Extension.Catalog.validate(entry.exports, entry.identity["capabilities"]) == :ok and
          Ipse.Extension.Catalog.digest(entry.exports) == entry.identity["exports_sha256"] and
          entry.identity["runtime"] == runtime() and is_binary(entry.store) and
          Ipse.Extension.validate(entry.options) == :ok and
          selected_state_scope?(
            entry.identity["artifact"],
            entry.options,
            entry.identity["state_binding"]
          ) and
          entry.identity["options_sha256"] == Ipse.JSON.digest([entry.options]) and
          Ipse.Extension.Subscriptions.validate(
            entry.subscriptions,
            entry.identity["capabilities"]
          ) == :ok and
          Ipse.Extension.Subscriptions.digest(entry.subscriptions) ==
            entry.identity["subscriptions_sha256"] and
          Ipse.Extension.Subscriptions.validate_handlers(entry.subscriptions, entry.exports) ==
            :ok
      end) and
      entries == Enum.sort_by(entries, &{&1.identity["order"], &1.identity["instance"]}) and
      length(entries) == length(Enum.uniq_by(entries, & &1.identity["instance"])) and
      Ipse.Extension.Services.resolve(entries) == {:ok, entries} and
      match?({:ok, _}, Ipse.Extension.Catalog.snapshot(config))
  rescue
    _ -> false
  end

  @doc "Recheck required code and schemas before opening a fresh or resumed session."
  def revalidate(config) do
    with true <- valid_entries?(config),
         host = host_digest(),
         true <-
           Enum.all?(Map.get(config, :extensions, []), fn entry ->
             with {:ok, artifact} <- lookup(entry.store, entry.identity["artifact"]),
                  true <- artifact.digest == entry.identity["artifact_sha256"],
                  true <- entry.identity["host_sha256"] == host,
                  true <- Artifact.compatible?(artifact.manifest),
                  true <- artifact.manifest["sdk"] === entry.identity["sdk"],
                  true <- artifact.manifest["capabilities"] == entry.identity["capabilities"],
                  true <-
                    Ipse.Extension.Catalog.digest(artifact.manifest["exports"]) ==
                      entry.identity["exports_sha256"],
                  true <-
                    (artifact.manifest["requires"] || Ipse.Extension.Services.empty()) ==
                      entry.requires,
                  true <- (artifact.manifest["subscriptions"] || []) == entry.subscriptions,
                  :ok <-
                    Ipse.JSON.validate_arguments(
                      artifact.manifest["options_schema"],
                      entry.options
                    ) do
               true
             else
               _ -> false
             end
           end) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def live?(identity, now \\ System.system_time(:second)),
    do: is_nil(identity["expires_at"]) or identity["expires_at"] > now

  defp selected_state_scope?(artifact, options, binding) do
    case get_in(@builtins, [artifact, :state_scope_option]) do
      nil -> true
      _option when is_nil(binding) -> true
      option -> is_map(binding) and options[option] in binding["scopes"]
    end
  end

  defp runtime do
    %{
      "elixir" => System.version(),
      "otp" => System.otp_release(),
      "erts" => to_string(:erlang.system_info(:version)),
      "architecture" => to_string(:erlang.system_info(:system_architecture))
    }
  end

  defp host_digest do
    case Application.load(:ipse) do
      :ok -> :ok
      {:error, {:already_loaded, :ipse}} -> :ok
      _ -> raise ArgumentError, "Ipse application inventory is unavailable"
    end

    modules = Application.spec(:ipse, :modules)

    unless is_list(modules) and Enum.all?(modules, &is_atom/1) and
             length(modules) == length(Enum.uniq(modules)) and
             Enum.all?([Ipse.Session, Ipse.Extension, __MODULE__], &(&1 in modules)) do
      raise ArgumentError, "Ipse application inventory is invalid"
    end

    modules
    |> Enum.reject(&String.starts_with?(Atom.to_string(&1), "Elixir.Ipse.Builtins."))
    |> Enum.sort_by(&Atom.to_string/1)
    |> Enum.map(fn module ->
      %{"module" => Atom.to_string(module), "sha256" => beam_digest(module)}
    end)
    |> Ipse.JSON.digest()
  end

  defp beam_digest(module) do
    path = :code.which(module)
    if is_list(path), do: path |> File.read!() |> Ipse.JSON.sha256(), else: raise(ArgumentError)
  end

  defp builtin(reference, metadata) do
    root = Application.app_dir(:ipse)
    module = Atom.to_string(metadata.module)

    paths =
      Enum.map(
        Map.get(metadata, :modules, [metadata.module]),
        &("ebin/" <> Atom.to_string(&1) <> ".beam")
      ) ++ ["priv/extensions/LICENSE"]

    files =
      Enum.map(paths, fn path ->
        bytes = File.read!(Path.join(root, path))
        %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
      end)

    manifest = %{
      "format" => 1,
      "id" => reference,
      "version" => "1.0.0",
      "sdk" => 1,
      "protocol" => 1,
      "backend" => "builtin",
      "entrypoint" => String.replace_prefix(module, "Elixir.", ""),
      "files" => files,
      "license_file" => "priv/extensions/LICENSE",
      "options_schema" => metadata.schema,
      "capabilities" => metadata.capabilities,
      "runtime" => %{
        "elixir" => "== " <> System.version(),
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      }
    }

    manifest =
      if metadata[:exports], do: Map.put(manifest, "exports", metadata.exports), else: manifest

    {:ok, %{digest: Ipse.JSON.digest([manifest]), manifest: manifest, path: root}}
  rescue
    _ -> @error
  end

  defp earliest(nil, right), do: right
  defp earliest(left, nil), do: left
  defp earliest(left, right), do: min(left, right)

  @identity_keys ~w(instance artifact artifact_sha256 options_sha256 exports_sha256 requires_sha256 subscriptions_sha256 services scope source_sha256 sdk protocol capabilities order lifetime expires_at runtime host_sha256 generation allow_children)
  @identity_optional ~w(text_required state_binding mcp_bindings)

  def valid_identity?(identity) when is_map(identity) do
    Enum.sort(Map.keys(Map.drop(identity, @identity_optional))) == Enum.sort(@identity_keys) and
      (not Map.has_key?(identity, "text_required") or
         (is_boolean(identity["text_required"]) and "stream.text" in identity["capabilities"])) and
      (not Map.has_key?(identity, "state_binding") or
         (identity["scope"] == "operator" and
            Ipse.Extension.State.valid_binding?(identity["state_binding"]))) and
      (not Map.has_key?(identity, "mcp_bindings") or
         (identity["scope"] == "operator" and "host.mcp" in identity["capabilities"] and
            Ipse.Extension.MCPCall.public_bindings?(identity["mcp_bindings"]))) and
      Ipse.Extension.validate(identity) == :ok and
      is_binary(identity["instance"]) and
      Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, identity["instance"]) and
      is_binary(identity["artifact"]) and
      Regex.match?(
        ~r/\A(?:[a-f0-9]{64}|builtin:[a-z][a-z0-9_-]{0,63}:[1-9][0-9]{0,3})\z/,
        identity["artifact"]
      ) and
      Enum.all?(
        ~w(artifact_sha256 options_sha256 exports_sha256 requires_sha256 subscriptions_sha256 source_sha256 host_sha256),
        &hash?(identity[&1])
      ) and
      Ipse.Extension.Services.public_bindings?(identity["services"]) and
      identity["scope"] in ~w(operator project) and
      Ipse.Extension.Catalog.sdk_capabilities?(identity["sdk"], identity["capabilities"]) and
      identity["protocol"] === 1 and identity["generation"] === 1 and
      is_list(identity["capabilities"]) and
      ("host.state.bound" not in identity["capabilities"] or
         Map.has_key?(identity, "state_binding")) and
      Enum.all?(identity["capabilities"], &(&1 in Ipse.Extension.Catalog.capabilities())) and
      length(identity["capabilities"]) == length(Enum.uniq(identity["capabilities"])) and
      is_integer(identity["order"]) and identity["order"] in 0..1000 and
      identity["lifetime"] in ~w(session persistent) and is_boolean(identity["allow_children"]) and
      (is_nil(identity["expires_at"]) or
         (is_integer(identity["expires_at"]) and identity["expires_at"] >= 0)) and
      runtime?(identity["runtime"])
  rescue
    _ -> false
  end

  def valid_identity?(_), do: false
  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[a-f0-9]{64}\z/, value)

  defp runtime?(runtime) when is_map(runtime) do
    Enum.sort(Map.keys(runtime)) == ~w(architecture elixir erts otp) and
      Enum.all?(Map.values(runtime), &(is_binary(&1) and byte_size(&1) in 1..256))
  end

  defp runtime?(_), do: false
end
