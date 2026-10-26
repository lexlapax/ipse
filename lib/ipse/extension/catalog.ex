defmodule Ipse.Extension.Catalog do
  @moduledoc "Inert, versioned tool/command/service declarations; discovery never executes code."
  alias Ipse.JSON, as: Schema

  @groups %{
    "tools" => "invoke.tool",
    "commands" => "invoke.command",
    "services" => "invoke.service",
    "jobs" => "event.job"
  }
  @error {:error, :invalid_extension_catalog}

  def capabilities,
    do:
      ~w(transform.prompt transform.presentation invoke.tool invoke.command invoke.service invoke.result.pages host.actions host.actions.mixed host.mcp host.results host.state.read host.state.scan host.state.bound host.state.write host.question host.tools host.services host.context host.usage host.usage.scan host.usage.children host.model host.embedding host.decision stream.text stream.text.events lifecycle.record lifecycle.tools event.notify event.job event.feed event.prompt.original event.prompt.effective event.answer.original event.answer.presented event.tool.input event.tool.result observe.local observe.export) ++
        Ipse.Extension.History.capabilities()

  @doc "The initial SDK-2 contract requires the paged-result grant, and SDK-1 excludes it."
  def sdk_capabilities?(1, capabilities) when is_list(capabilities),
    do: "invoke.result.pages" not in capabilities

  def sdk_capabilities?(2, capabilities) when is_list(capabilities),
    do: "invoke.result.pages" in capabilities

  def sdk_capabilities?(_, _), do: false

  def empty,
    do: %{"version" => 1, "tools" => [], "commands" => [], "services" => []}

  def normalize(nil), do: Map.put(empty(), "jobs", [])
  def normalize(exports) when is_map(exports), do: Map.put_new(exports, "jobs", [])
  def normalize(exports), do: exports

  def validate(exports, capabilities) do
    exports = normalize(exports)

    with :ok <- Schema.validate_object(exports),
         true <-
           "invoke.result.pages" not in capabilities or
             Enum.any?(~w(invoke.tool invoke.command), &(&1 in capabilities)),
         true <- "lifecycle.tools" not in capabilities or "lifecycle.record" in capabilities,
         true <- "stream.text.events" not in capabilities or "stream.text" in capabilities,
         true <- Enum.sort(Map.keys(exports)) == ~w(commands jobs services tools version),
         true <- exports["version"] === 1,
         true <- "host.usage.scan" not in capabilities or "host.usage" in capabilities,
         true <- "host.state.scan" not in capabilities or "host.state.read" in capabilities,
         true <- "host.state.bound" not in capabilities or "host.state.read" in capabilities,
         true <- "host.usage.children" not in capabilities or "host.usage" in capabilities,
         true <-
           not Enum.any?(
             ~w(host.actions.mixed host.mcp host.results host.state.read host.state.write host.question host.tools host.services host.context host.usage host.model host.embedding host.decision) ++
               Ipse.Extension.History.capabilities(),
             &(&1 in capabilities)
           ) or
             "host.actions" in capabilities,
         true <-
           not Enum.any?(
             Ipse.Extension.History.capabilities() -- ["host.history"],
             &(&1 in capabilities)
           ) or
             "host.history" in capabilities,
         true <-
           Enum.all?(@groups, fn {group, capability} ->
             records = exports[group]

             is_list(records) and length(records) <= 8 and
               Enum.all?(records, &descriptor?/1) and unique?(Enum.map(records, & &1["id"])) and
               records != [] == capability in capabilities
           end),
         :ok <-
           Schema.validate_object(%{
             "sdk" => 1,
             "capabilities" => capabilities,
             "exports" => exports
           }) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Derive a bounded catalog from already admitted entries, without module loading."
  def snapshot(config) do
    entries =
      for entry <- Map.get(config, :extensions, []),
          {group, stage} <- Enum.sort(@groups),
          descriptor <- Map.get(entry.exports, group, []) do
        Map.merge(descriptor, %{
          "instance" => entry.identity["instance"],
          "stage" => stage,
          "name" => name(entry.identity["instance"], descriptor["id"])
        })
      end

    snapshot = %{"version" => 1, "entries" => entries}

    with true <- length(entries) <= 32,
         true <- unique?(Enum.map(entries, &{&1["stage"], &1["name"]})),
         true <- Enum.all?(entries, &(byte_size(&1["name"]) <= 64)),
         :ok <- validate_snapshot(snapshot) do
      {:ok, snapshot}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def definitions(config) do
    {:ok, catalog} = snapshot(config)

    catalog["entries"]
    |> Enum.filter(&(&1["stage"] == "invoke.tool"))
    |> Enum.map(fn descriptor ->
      %{
        "type" => "function",
        "function" => %{
          "name" => descriptor["name"],
          "description" => descriptor["description"],
          "parameters" => descriptor["arguments_schema"]
        }
      }
    end)
  end

  def validate_snapshot(%{"version" => 1, "entries" => entries} = snapshot) do
    with :ok <- Schema.validate_object(snapshot),
         true <- Enum.sort(Map.keys(snapshot)) == ~w(entries version),
         true <- is_list(entries) and length(entries) <= 32,
         true <-
           Enum.all?(entries, fn export ->
             is_map(export) and export["stage"] in Map.values(@groups) and
               is_binary(export["instance"]) and
               Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, export["instance"]) and
               descriptor?(Map.drop(export, ~w(instance stage name))) and
               export["name"] == name(export["instance"], export["id"]) and
               byte_size(export["name"]) <= 64
           end),
         true <- unique?(Enum.map(entries, &{&1["stage"], &1["name"]})) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def validate_snapshot(_), do: @error

  def from_metadata(metadata) do
    identities = Map.get(metadata, "extensions", [])
    snapshot = Map.get(metadata, "extension_catalog", %{"version" => 1, "entries" => []})

    with true <- is_list(identities) and length(identities) <= 8,
         true <- Enum.all?(identities, &Ipse.Extension.Registry.valid_identity?/1),
         true <- unique?(Enum.map(identities, & &1["instance"])),
         :ok <- validate_snapshot(snapshot),
         true <-
           Enum.all?(snapshot["entries"], fn export ->
             Enum.any?(identities, &(&1["instance"] == export["instance"]))
           end),
         true <-
           Enum.all?(identities, fn identity ->
             exports =
               Enum.reduce(@groups, empty(), fn {group, stage}, exports ->
                 records =
                   snapshot["entries"]
                   |> Enum.filter(
                     &(&1["instance"] == identity["instance"] and &1["stage"] == stage)
                   )
                   |> Enum.map(&Map.drop(&1, ~w(instance stage name)))

                 Map.put(exports, group, records)
               end)

             validate(exports, identity["capabilities"]) == :ok and
               digest(exports) == identity["exports_sha256"]
           end) do
      {:ok, snapshot}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def validate_call(descriptor, arguments) do
    with :ok <- Schema.validate_arguments(descriptor["arguments_schema"], arguments),
         :ok <-
           Schema.validate_object(%{
             "api_version" => 1,
             "invocation_id" => String.duplicate("0", 32),
             "session_id" => String.duplicate("0", 32),
             "turn_id" => String.duplicate("0", 32),
             "id" => descriptor["id"],
             "arguments" => arguments
           }) do
      :ok
    else
      _ -> {:error, :invalid_extension_arguments}
    end
  rescue
    _ -> {:error, :invalid_extension_arguments}
  end

  def validate_response(descriptor, response) do
    with :ok <- Schema.validate_object(response),
         true <- Enum.sort(Map.keys(response)) == ~w(api_version kind value),
         true <- response["api_version"] === 1 and response["kind"] == "result",
         :ok <- Schema.validate_arguments(descriptor["result_schema"], response["value"]) do
      {:ok, response["value"]}
    else
      _ -> {:error, :invalid_extension_response}
    end
  rescue
    _ -> {:error, :invalid_extension_response}
  end

  def lookup(config, stage, name) do
    with {:ok, snapshot} <- snapshot(config),
         descriptor when is_map(descriptor) <-
           Enum.find(snapshot["entries"], &(&1["stage"] == stage and &1["name"] == name)),
         entry when is_map(entry) <-
           Enum.find(
             Map.get(config, :extensions, []),
             &(&1.identity["instance"] == descriptor["instance"])
           ) do
      {:ok, entry, descriptor}
    else
      _ -> {:error, :extension_export_unavailable}
    end
  end

  def external?(name), do: is_binary(name) and String.starts_with?(name, "ext__")

  def digest(exports) do
    exports = normalize(exports)
    exports = if exports["jobs"] == [], do: Map.delete(exports, "jobs"), else: exports
    Ipse.JSON.digest([exports])
  end

  defp name(instance, id), do: "ext__" <> instance <> "__" <> id

  defp descriptor?(descriptor) when is_map(descriptor) do
    Enum.sort(Map.keys(descriptor)) == ~w(arguments_schema description id result_schema) and
      is_binary(descriptor["id"]) and
      Regex.match?(~r/\A[a-z][a-z0-9_-]{0,31}\z/, descriptor["id"]) and
      is_binary(descriptor["description"]) and String.valid?(descriptor["description"]) and
      byte_size(descriptor["description"]) in 1..1024 and
      Enum.all?(~w(arguments_schema result_schema), fn field ->
        Schema.validate_schema(descriptor[field]) == :ok and descriptor[field]["type"] == "object"
      end)
  end

  defp descriptor?(_), do: false
  defp unique?(records), do: length(records) == length(Enum.uniq(records))
end

defmodule Ipse.Extension.Services do
  @moduledoc "Inert typed service requirements, operator bindings and acyclic activation pins."
  alias Ipse.Extension.{Catalog, Registry}
  @error {:error, :invalid_extension_services}

  def empty, do: %{"version" => 1, "services" => []}
  def digest(requires), do: Ipse.JSON.digest([requires || empty()])

  def validate_requirements(requires, capabilities) do
    requires = requires || empty()

    with :ok <- Ipse.Extension.validate(requires),
         true <- keys?(requires, ~w(version services)) and requires["version"] === 1,
         requirements = requires["services"],
         true <- is_list(requirements) and length(requirements) <= 8,
         true <- Enum.all?(requirements, &requirement?/1),
         true <- unique?(Enum.map(requirements, & &1["alias"])),
         true <- requirements != [] == "host.services" in capabilities,
         true <- requirements == [] or "host.actions" in capabilities do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def validate_bindings(bindings) do
    is_list(bindings) and length(bindings) <= 64 and
      Ipse.Extension.validate(%{"bindings" => bindings}) == :ok and
      Enum.all?(bindings, fn binding ->
        keys?(binding, ~w(caller alias target artifact service)) and
          instance?(binding["caller"]) and local?(binding["alias"]) and
          instance?(binding["target"]) and local?(binding["service"]) and
          is_binary(binding["artifact"]) and
          Regex.match?(
            ~r/\A(?:[a-f0-9]{64}|builtin:[a-z][a-z0-9_-]{0,63}:[1-9][0-9]{0,3})\z/,
            binding["artifact"]
          )
      end) and unique?(Enum.map(bindings, &{&1["caller"], &1["alias"]}))
  rescue
    _ -> false
  end

  def public_bindings?(bindings) do
    is_list(bindings) and length(bindings) <= 8 and
      Enum.all?(bindings, fn binding ->
        keys?(binding, ~w(alias instance name contract target_sha256)) and
          local?(binding["alias"]) and instance?(binding["instance"]) and
          binding["contract"] === 1 and Ipse.JSON.sha256?(binding["target_sha256"]) and
          is_binary(binding["name"]) and byte_size(binding["name"]) <= 64 and
          String.starts_with?(binding["name"], "ext__")
      end) and bindings == Enum.sort_by(bindings, & &1["alias"]) and
      unique?(Enum.map(bindings, & &1["alias"]))
  rescue
    _ -> false
  end

  @doc "Resolve only reviewed data. No executable discovery, lookup, IO or initialization."
  def resolve(entries) do
    with true <- is_list(entries) and length(entries) <= 8,
         {:ok, catalog} <- Catalog.snapshot(%{extensions: entries}),
         nodes = Map.new(entries, &{&1.identity["instance"], &1}),
         true <- map_size(nodes) == length(entries),
         {:ok, edges} <- edges(nodes, catalog),
         {:ok, materialized} <- materialize(nodes, edges) do
      {:ok, Enum.map(entries, &materialized[&1.identity["instance"]])}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp edges(nodes, catalog) do
    Enum.reduce_while(nodes, {:ok, %{}}, fn {id, entry}, {:ok, edges} ->
      requires = entry.requires["services"]

      with :ok <- validate_requirements(entry.requires, entry.identity["capabilities"]),
           true <- digest(entry.requires) == entry.identity["requires_sha256"],
           true <- validate_bindings(entry.bindings),
           true <- Enum.all?(entry.bindings, &(&1["caller"] == id)),
           true <- length(requires) == length(entry.bindings),
           {:ok, resolved} <-
             Enum.reduce_while(requires, {:ok, []}, fn required, {:ok, acc} ->
               binding = Enum.find(entry.bindings, &(&1["alias"] == required["alias"]))

               with true <- is_map(binding),
                    target when is_map(target) <- nodes[binding["target"]],
                    true <- target.identity["artifact"] == binding["artifact"],
                    descriptor when is_map(descriptor) <-
                      Enum.find(catalog["entries"], fn d ->
                        d["stage"] == "invoke.service" and d["instance"] == binding["target"] and
                          d["id"] == binding["service"]
                      end),
                    true <-
                      Enum.all?(
                        ~w(arguments_schema result_schema),
                        &(required[&1] == descriptor[&1])
                      ) do
                 {:cont,
                  {:ok,
                   acc ++
                     [%{required: required, target: binding["target"], descriptor: descriptor}]}}
               else
                 _ -> {:halt, @error}
               end
             end) do
        {:cont, {:ok, Map.put(edges, id, resolved)}}
      else
        _ -> {:halt, @error}
      end
    end)
  end

  defp materialize(nodes, edges) do
    graph = :digraph.new([:acyclic, :private])

    try do
      Enum.each(Map.keys(nodes), &:digraph.add_vertex(graph, &1))

      valid =
        Enum.all?(edges, fn {id, targets} ->
          Enum.all?(targets, fn edge ->
            not match?({:error, _}, :digraph.add_edge(graph, id, edge.target))
          end)
        end)

      if valid do
        cache =
          graph
          |> :digraph_utils.topsort()
          |> Enum.reverse()
          |> Enum.reduce(%{}, fn id, cache ->
            bindings =
              Enum.map(edges[id], fn edge ->
                %{
                  "alias" => edge.required["alias"],
                  "instance" => edge.target,
                  "name" => edge.descriptor["name"],
                  "contract" => 1,
                  "target_sha256" => Ipse.JSON.digest([cache[edge.target].identity])
                }
              end)
              |> Enum.sort_by(& &1["alias"])

            entry = put_in(nodes[id], [:identity, "services"], bindings)
            Map.put(cache, id, entry)
          end)

        {:ok, cache}
      else
        @error
      end
    after
      :digraph.delete(graph)
    end
  end

  def validate_request(request) do
    with :ok <- Ipse.Extension.validate(request),
         true <- keys?(request, ~w(op alias arguments checkpoint)),
         true <- request["op"] == "service.call" and local?(request["alias"]),
         true <- is_map(request["arguments"]) and is_map(request["checkpoint"]),
         true <- byte_size(Jason.encode!(request["checkpoint"])) <= 8192 do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def validate_metadata(identities, catalog) do
    nodes = Map.new(identities, &{&1["instance"], &1})

    if Enum.all?(identities, fn identity ->
         Enum.all?(identity["services"], fn binding ->
           target = nodes[binding["instance"]]

           target != nil and Ipse.JSON.digest([target]) == binding["target_sha256"] and
             Enum.any?(catalog["entries"], fn d ->
               d["stage"] == "invoke.service" and d["instance"] == binding["instance"] and
                 d["name"] == binding["name"]
             end)
         end)
       end) do
      :ok
    else
      @error
    end
  rescue
    _ -> @error
  end

  def lookup(config, caller, request) do
    with :ok <- validate_request(request),
         binding when is_map(binding) <-
           Enum.find(caller["services"], &(&1["alias"] == request["alias"])),
         {:ok, target, descriptor} <- Catalog.lookup(config, "invoke.service", binding["name"]),
         context = %{"identity" => target.identity, "descriptor" => descriptor},
         true <- valid_binding?(caller, request, context) do
      {:ok, target, context}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def valid_binding?(caller, request, context) do
    with true <- keys?(context, ~w(identity descriptor)),
         true <- Registry.valid_identity?(context["identity"]),
         :ok <- validate_request(request),
         binding when is_map(binding) <-
           Enum.find(caller["services"], &(&1["alias"] == request["alias"])),
         true <- binding["target_sha256"] == Ipse.JSON.digest([context["identity"]]),
         descriptor = context["descriptor"],
         true <-
           descriptor["stage"] == "invoke.service" and
             descriptor["stage"] in context["identity"]["capabilities"],
         true <-
           descriptor["instance"] == binding["instance"] and descriptor["name"] == binding["name"],
         true <- descriptor["instance"] == context["identity"]["instance"],
         :ok <- Catalog.validate_snapshot(%{"version" => 1, "entries" => [descriptor]}),
         :ok <- Catalog.validate_call(descriptor, request["arguments"]),
         :ok <-
           Ipse.Extension.validate(
             payload(
               request,
               context,
               String.duplicate("0", 32),
               String.duplicate("0", 32),
               String.duplicate("0", 32),
               String.duplicate("0", 32)
             )
           ) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def payload(request, context, id, parent_id, session_id, turn_id) do
    %{
      "api_version" => 1,
      "invocation_id" => id,
      "parent_invocation_id" => parent_id,
      "session_id" => session_id,
      "turn_id" => turn_id,
      "service_contract" => 1,
      "id" => context["descriptor"]["id"],
      "arguments" => request["arguments"]
    }
  end

  def outcome(context, id, result) do
    %{
      "result" => result,
      "service" => %{
        "instance" => context["identity"]["instance"],
        "name" => context["descriptor"]["name"],
        "artifact_sha256" => context["identity"]["artifact_sha256"],
        "operation_id" => id
      }
    }
  end

  def valid_outcome?(_, "unknown", value, _), do: value == %{}

  def valid_outcome?(context, "ok", value, id) do
    keys?(value, ~w(result service)) and
      value == outcome(context, id, value["result"]) and
      match?(
        {:ok, _},
        Catalog.validate_response(
          context["descriptor"],
          %{"api_version" => 1, "kind" => "result", "value" => value["result"]}
        )
      )
  rescue
    _ -> false
  end

  def valid_outcome?(_, _, _, _), do: false

  defp requirement?(required) do
    keys?(required, ~w(alias contract arguments_schema result_schema)) and
      local?(required["alias"]) and
      required["contract"] === 1 and
      Enum.all?(~w(arguments_schema result_schema), fn key ->
        required[key]["type"] == "object" and
          Ipse.JSON.validate_schema(required[key]) == :ok
      end)
  end

  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
  defp unique?(values), do: length(values) == length(Enum.uniq(values))
  defp instance?(id), do: is_binary(id) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, id)
  defp local?(id), do: is_binary(id) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,31}\z/, id)
end
