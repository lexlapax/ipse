defmodule Ipse.Extensions.Services do
  @moduledoc "Inert typed service requirements, operator bindings and acyclic activation pins."
  alias Ipse.Extensions.{Catalog, Identity}
  @error {:error, :invalid_extension_services}

  def empty, do: %{"version" => 1, "services" => []}
  def digest(requires), do: Ipse.Compaction.digest([requires || empty()])

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
          binding["contract"] === 1 and hash?(binding["target_sha256"]) and
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
                  "target_sha256" => Ipse.Compaction.digest([cache[edge.target].identity])
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

           target != nil and Ipse.Compaction.digest([target]) == binding["target_sha256"] and
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
         true <- Identity.valid?(context["identity"]),
         :ok <- validate_request(request),
         binding when is_map(binding) <-
           Enum.find(caller["services"], &(&1["alias"] == request["alias"])),
         true <- binding["target_sha256"] == Ipse.Compaction.digest([context["identity"]]),
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
          Ipse.MCP.Schema.validate_schema(required[key]) == :ok
      end)
  end

  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
  defp unique?(values), do: length(values) == length(Enum.uniq(values))
  defp instance?(id), do: is_binary(id) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, id)
  defp local?(id), do: is_binary(id) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,31}\z/, id)
  defp hash?(hash), do: is_binary(hash) and Regex.match?(~r/\A[a-f0-9]{64}\z/, hash)
end
