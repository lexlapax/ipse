defmodule Ipse.Extensions.Config do
  @moduledoc "Data-only extension selection with an operator trust ceiling and scoped instances."
  alias Ipse.MCP.Schema
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
        |> Map.put("options_sha256", Ipse.Compaction.digest([instance["options"]]))
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
      Ipse.Extensions.Services.validate_bindings(Map.get(trust, "service_bindings", [])) and
      Enum.all?(trust["capabilities"], &Regex.match?(~r/\A[a-z][a-z0-9_.-]{0,127}\z/, &1)) and
      (not Map.has_key?(trust, "expires_at") or is_integer(trust["expires_at"]))
  end

  defp valid_state_bindings?(bindings) do
    unique?(Enum.map(bindings, & &1["instance"])) and
      Enum.all?(bindings, fn binding ->
        Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, binding["instance"]) and
          Ipse.Extensions.State.valid_binding?(Map.delete(binding, "instance"))
      end)
  end

  defp artifact?(id),
    do: Regex.match?(~r/\A(?:[a-f0-9]{64}|builtin:[a-z][a-z0-9_-]{0,63}:[1-9][0-9]{0,3})\z/, id)

  defp unique?(values), do: length(values) == length(Enum.uniq(values))
  defp sort(instances), do: Enum.sort_by(instances, &{&1["order"], &1["instance"]})
  defp sort_trust(trust), do: trust |> Map.values() |> Enum.sort_by(& &1["artifact"])
end
