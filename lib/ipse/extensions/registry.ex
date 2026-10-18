defmodule Ipse.Extensions.Registry do
  @moduledoc "Inert built-in metadata and explicit pinned session admission."
  alias Ipse.Extensions.{Manifest, Store}
  @error {:error, :extension_admission_refused}
  @host_capabilities Ipse.Extensions.Catalog.capabilities()
  @text %{"type" => "string", "maxLength" => 4096}
  @builtins %{
    "builtin:working-memory:1" => %{
      module: Ipse.Extensions.WorkingMemory,
      modules: [
        Ipse.Extensions.WorkingMemory,
        Ipse.Extensions.Memory,
        Ipse.Extensions.Memory.Records
      ],
      capabilities: Ipse.Extensions.Memory.capabilities(),
      exports: Ipse.Extensions.Memory.exports(),
      schema: Ipse.Extensions.Memory.options_schema(["session"])
    },
    "builtin:persistent-memory:1" => %{
      module: Ipse.Extensions.Memory,
      modules: [Ipse.Extensions.Memory, Ipse.Extensions.Memory.Records],
      capabilities: ["host.state.bound" | Ipse.Extensions.Memory.capabilities()],
      exports: Ipse.Extensions.Memory.exports(),
      schema: Ipse.Extensions.Memory.options_schema(~w(project operator))
    },
    "builtin:cost-tree:1" => %{
      module: Ipse.Extensions.Examples.CostTree,
      modules: [
        Ipse.Extensions.Examples.CostTree,
        Ipse.Extensions.CostSummary,
        Ipse.Extensions.Costs
      ],
      capabilities:
        ~w(invoke.command host.actions host.usage host.usage.scan host.usage.children),
      exports: Ipse.Extensions.Examples.CostTree.exports(),
      schema: %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["rate_card"],
        "properties" => %{"rate_card" => Ipse.Extensions.Costs.schema()}
      }
    },
    "builtin:cost-summary:1" => %{
      module: Ipse.Extensions.Examples.CostSummary,
      modules: [
        Ipse.Extensions.Examples.CostSummary,
        Ipse.Extensions.CostSummary,
        Ipse.Extensions.Costs
      ],
      capabilities: ~w(invoke.command host.actions host.usage host.usage.scan),
      exports: Ipse.Extensions.Examples.CostSummary.exports(),
      schema: %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["rate_card"],
        "properties" => %{"rate_card" => Ipse.Extensions.Costs.schema()}
      }
    },
    "builtin:cost-report:1" => %{
      module: Ipse.Extensions.Examples.CostReport,
      modules: [Ipse.Extensions.Examples.CostReport, Ipse.Extensions.Costs],
      capabilities: ~w(invoke.command host.actions host.usage),
      exports: Ipse.Extensions.Examples.CostReport.exports(),
      schema: %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["rate_card"],
        "properties" => %{"rate_card" => Ipse.Extensions.Costs.schema()}
      }
    },
    "builtin:local-trace:1" => %{
      module: Ipse.Extensions.Examples.LocalTrace,
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
      module: Ipse.Extensions.Examples.PromptAnnotation,
      capabilities: ["transform.prompt"],
      schema: %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["text"],
        "properties" => %{"text" => @text}
      }
    },
    "builtin:answer-format:1" => %{
      module: Ipse.Extensions.Examples.AnswerFormat,
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
      nil -> Store.lookup(store, reference)
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
           true <- Manifest.compatible?(artifact.manifest),
           capabilities = artifact.manifest["capabilities"],
           true <-
             Enum.all?(
               capabilities,
               &(&1 in @host_capabilities and &1 in ceiling["capabilities"])
             ),
           :ok <-
             Ipse.MCP.Schema.validate_arguments(
               artifact.manifest["options_schema"],
               instance["options"]
             ) do
        identity = %{
          "instance" => instance["instance"],
          "artifact" => instance["artifact"],
          "artifact_sha256" => artifact.digest,
          "options_sha256" => Ipse.Compaction.digest([instance["options"]]),
          "exports_sha256" => Ipse.Extensions.Catalog.digest(artifact.manifest["exports"]),
          "requires_sha256" => Ipse.Extensions.Services.digest(artifact.manifest["requires"]),
          "subscriptions_sha256" =>
            Ipse.Extensions.Subscriptions.digest(artifact.manifest["subscriptions"]),
          "services" => [],
          "scope" => instance["scope"],
          "source_sha256" => Manifest.sha256(instance["source"]),
          "sdk" => 1,
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

        binding =
          Enum.find(
            Map.get(ceiling, "state_bindings", []),
            &(&1["instance"] == instance["instance"])
          )

        identity =
          if binding,
            do: Map.put(identity, "state_binding", Map.delete(binding, "instance")),
            else: identity

        {:cont,
         {:ok,
          entries ++
            [
              %{
                identity: identity,
                options: instance["options"],
                store: store,
                exports: artifact.manifest["exports"] || Ipse.Extensions.Catalog.empty(),
                requires: artifact.manifest["requires"] || Ipse.Extensions.Services.empty(),
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
        with {:ok, entries} <- Ipse.Extensions.Services.resolve(entries),
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
      length(Ipse.Extensions.Subscriptions.all_declarations(config)) <= 8 and
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
          Ipse.Extensions.Projection.identity_valid?(entry.identity) and
          live?(entry.identity, now) and
          Enum.all?(entry.identity["capabilities"], &(&1 in @host_capabilities)) and
          Ipse.Extensions.Catalog.validate(entry.exports, entry.identity["capabilities"]) == :ok and
          Ipse.Extensions.Catalog.digest(entry.exports) == entry.identity["exports_sha256"] and
          entry.identity["runtime"] == runtime() and is_binary(entry.store) and
          Ipse.Extension.validate(entry.options) == :ok and
          entry.identity["options_sha256"] == Ipse.Compaction.digest([entry.options]) and
          Ipse.Extensions.Subscriptions.validate(
            entry.subscriptions,
            entry.identity["capabilities"]
          ) == :ok and
          Ipse.Extensions.Subscriptions.digest(entry.subscriptions) ==
            entry.identity["subscriptions_sha256"] and
          Ipse.Extensions.Subscriptions.validate_handlers(entry.subscriptions, entry.exports) ==
            :ok
      end) and
      entries == Enum.sort_by(entries, &{&1.identity["order"], &1.identity["instance"]}) and
      length(entries) == length(Enum.uniq_by(entries, & &1.identity["instance"])) and
      Ipse.Extensions.Services.resolve(entries) == {:ok, entries} and
      match?({:ok, _}, Ipse.Extensions.Catalog.snapshot(config))
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
                  true <- Manifest.compatible?(artifact.manifest),
                  true <- artifact.manifest["capabilities"] == entry.identity["capabilities"],
                  true <-
                    Ipse.Extensions.Catalog.digest(artifact.manifest["exports"]) ==
                      entry.identity["exports_sha256"],
                  true <-
                    (artifact.manifest["requires"] || Ipse.Extensions.Services.empty()) ==
                      entry.requires,
                  true <- (artifact.manifest["subscriptions"] || []) == entry.subscriptions,
                  :ok <-
                    Ipse.MCP.Schema.validate_arguments(
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

  defp runtime do
    %{
      "elixir" => System.version(),
      "otp" => System.otp_release(),
      "erts" => to_string(:erlang.system_info(:version)),
      "architecture" => to_string(:erlang.system_info(:system_architecture))
    }
  end

  defp host_digest do
    [
      Ipse.Extension,
      Ipse.Extensions.Identity,
      Ipse.Extensions.Catalog,
      Ipse.Extensions.Invocation,
      Ipse.Extensions.Actions,
      Ipse.Extensions.Operation,
      Ipse.Extensions.Services,
      Ipse.Extensions.ServiceCall,
      Ipse.Extensions.Contributions,
      Ipse.Extensions.ToolAction,
      Ipse.Extensions.ModelCall,
      Ipse.Profiles,
      Ipse.Provider.Request,
      Ipse.Provider,
      Ipse.Provider.OpenAI,
      Ipse.Provider.Anthropic,
      Ipse.Provider.Ollama,
      Ipse.Provider.HTTP,
      Ipse.HTTPProfile,
      Ipse.Auth,
      Ipse.Provider.Limits,
      Ipse.Budget,
      Ipse.Budget.Policy,
      Ipse.Budget.Store,
      Ipse.Budget.Ledger,
      Ipse.Extensions.State,
      Ipse.Extensions.History,
      Ipse.Extensions.UsageRead,
      Ipse.Extensions.ChildUsage,
      Ipse.Questions,
      Ipse.Tools,
      Ipse.Runner,
      Ipse.WorkspaceContext,
      Ipse.Skills,
      Ipse.Context,
      Ipse.Extensions.Manifest,
      Ipse.Extensions.Store,
      __MODULE__,
      Ipse.Extensions.Worker,
      Ipse.Extensions.WorkerLease,
      Ipse.Extensions.FeedChannel,
      Ipse.Extensions.Feeds,
      Ipse.Extensions.Bootstrap,
      Ipse.Extensions.Host,
      Ipse.Extensions.Projection,
      Ipse.MCP.Schema,
      Ipse.Usage,
      Ipse.Usage.Normalizer,
      Ipse.TextStream,
      Ipse.TextStream.RequiredFailure,
      Ipse.Extensions.TextResources,
      Ipse.Extensions.TextConsumer,
      Ipse.Journal,
      Ipse.Journal.Writer,
      Ipse.Journal.Reader,
      Ipse.Journal.Limits,
      Ipse.ToolCall,
      Ipse.HTTPProxy,
      Ipse.TaskResources,
      Ipse.Session.Lock,
      Ipse.FileEffect,
      Ipse.Lifecycle.Source,
      Ipse.Lifecycle.Event,
      Ipse.Lifecycle.Metadata,
      Ipse.Lifecycle.Answer,
      Ipse.Lifecycle.Runtime,
      Ipse.Lifecycle.Tool,
      Ipse.Lifecycle.Child,
      Ipse.Lifecycle.Ephemeral,
      Ipse.Observability.Config,
      Ipse.Observability.Event,
      Ipse.Observability.Channel,
      Ipse.Observability.Resources,
      Ipse.Extensions.Subscriptions,
      Ipse.Extensions.EventJob,
      Ipse.Session
    ]
    |> Enum.map(fn module ->
      %{"module" => Atom.to_string(module), "sha256" => beam_digest(module)}
    end)
    |> Ipse.Compaction.digest()
  end

  defp beam_digest(module) do
    path = :code.which(module)
    if is_list(path), do: path |> File.read!() |> Manifest.sha256(), else: raise(ArgumentError)
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
        %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Manifest.sha256(bytes)}
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

    {:ok, %{digest: Ipse.Compaction.digest([manifest]), manifest: manifest, path: root}}
  rescue
    _ -> @error
  end

  defp earliest(nil, right), do: right
  defp earliest(left, nil), do: left
  defp earliest(left, right), do: min(left, right)
end
