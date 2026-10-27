defmodule Ipse.Config.Semantics do
  @moduledoc "Operator-only semantic selections; references never substitute for protected grants."
  alias Ipse.{JSON, Extension.SemanticConsent}
  @error {:error, :invalid_semantic_configuration}

  # Dynamic keyed registries use the existing bounded JSON object subset;
  # validate/1 supplies the closed entry schema and registry cardinality.
  def schema, do: %{"type" => "object"}

  def validate(registry) do
    if is_map(registry) and map_size(registry) <= 8 and
         Enum.all?(registry, fn {instance, entry} ->
           is_binary(instance) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, instance) and
             is_map(entry) and
             Enum.sort(Map.keys(entry)) == ~w(enabled policy_sha256 project version) and
             entry["version"] === 1 and is_boolean(entry["enabled"]) and
             JSON.sha256?(entry["project"]) and JSON.sha256?(entry["policy_sha256"])
         end) do
      :ok
    else
      @error
    end
  rescue
    _ -> @error
  end

  @doc "Resolve only operator references, including when project configuration is trusted."
  def resolve(sources) when is_list(sources) do
    Enum.reduce_while(sources, {:ok, %{}}, fn source, {:ok, acc} ->
      entries = Map.get(source.data, "semantic_selections", %{})

      cond do
        Map.has_key?(source.data, "semantic_selections") and source.scope != "operator" ->
          {:halt, {:error, :semantic_configuration_operator_only}}

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

  @doc "Explicit shared inference service identities; address aliases are operator-owned."
  def validate_services(registry) do
    with true <- is_map(registry) and map_size(registry) <= 8,
         true <-
           Enum.all?(registry, fn {id, entry} ->
             is_binary(id) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, id) and
               is_map(entry) and Enum.sort(Map.keys(entry)) == ~w(origins version) and
               entry["version"] === 1 and is_list(entry["origins"]) and
               length(entry["origins"]) in 1..8 and
               entry["origins"] === Enum.sort(Enum.uniq(entry["origins"])) and
               Enum.all?(entry["origins"], fn origin ->
                 Ipse.Provider.valid_destination?(%{
                   "origin" => origin,
                   "target_sha256" => String.duplicate("0", 64)
                 })
               end)
           end),
         origins = Enum.flat_map(registry, fn {_, entry} -> entry["origins"] end),
         true <- length(origins) == length(Enum.uniq(origins)) do
      :ok
    else
      _ -> {:error, :invalid_inference_services}
    end
  rescue
    _ -> {:error, :invalid_inference_services}
  end

  def resolve_services(sources) when is_list(sources) do
    Enum.reduce_while(sources, {:ok, %{}}, fn source, {:ok, acc} ->
      entries = Map.get(source.data, "inference_services", %{})

      cond do
        Map.has_key?(source.data, "inference_services") and source.scope != "operator" ->
          {:halt, {:error, :inference_services_operator_only}}

        validate_services(entries) != :ok or validate_services(Map.merge(acc, entries)) != :ok ->
          {:halt, {:error, :invalid_inference_services}}

        true ->
          {:cont, {:ok, Map.merge(acc, entries)}}
      end
    end)
  rescue
    _ -> {:error, :invalid_inference_services}
  end

  def resolve_services(_), do: {:error, :invalid_inference_services}

  @doc "Prepare the data reference saved after explicit operator review and Consent.replace."
  def selection(policy) do
    if SemanticConsent.policy?(policy),
      do:
        {:ok,
         %{
           policy["settings"]["instance"] => %{
             "version" => 1,
             "project" => policy["project"],
             "policy_sha256" => JSON.digest([policy]),
             "enabled" => true
           }
         }},
      else: @error
  end

  @doc "Match selected data against an independently loaded current protected policy."
  def selected?(registry, instance, policy) do
    validate(registry) == :ok and SemanticConsent.policy?(policy) and
      registry[instance] === %{
        "version" => 1,
        "project" => policy["project"],
        "policy_sha256" => JSON.digest([policy]),
        "enabled" => true
      } and policy["settings"]["instance"] == instance
  rescue
    _ -> false
  end

  @doc "Fresh-Session admission requires both the operator selection and protected grant."
  def admit(registry, snapshot, context, now) do
    with :ok <- validate(registry),
         true <- SemanticConsent.context?(context),
         true <- is_map(snapshot) and JSON.safe_uint?(snapshot["epoch"]) do
      if selected?(registry, context["identity"]["instance"], snapshot["policy"]),
        do: SemanticConsent.admit(snapshot, context, now),
        else: {:ok, nil}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end
end
