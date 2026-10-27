defmodule Ipse.Extension.Activation do
  @moduledoc """
  Pure operator activation data for fresh Sessions and exact saved overlays.

  This is not artifact admission. The host must verify the actual installed
  reviewed bundle/sidecar, ordinary configuration, manifest capabilities and
  current protected policy before Registry prepares an identity. Resume selects
  only its saved overlay; current enable/disable cannot change its catalog.
  """
  alias Ipse.JSON

  @keys ~w(version kind artifact artifact_sha256 sidecar_sha256 instance options capabilities service_refs order lifetime allow_children)
  @error {:error, :invalid_extension_activation}

  def validate(a) do
    if valid?(a), do: :ok, else: @error
  end

  def valid?(a) do
    keys?(Map.delete(a, "main_timeout_ms"), @keys) and timeout?(a) and
      a["version"] === 1 and a["kind"] == "reviewed.bundle" and
      JSON.sha256?(a["artifact"]) and a["artifact"] == a["artifact_sha256"] and
      JSON.sha256?(a["sidecar_sha256"]) and instance?(a["instance"]) and
      is_map(a["options"]) and JSON.validate_object(a["options"]) == :ok and
      byte_size(Jason.encode!(a["options"])) <= 1024 and
      is_list(a["capabilities"]) and length(a["capabilities"]) <= 32 and
      a["capabilities"] == Enum.sort(Enum.uniq(a["capabilities"])) and
      Enum.all?(a["capabilities"], &capability?/1) and refs?(a["service_refs"]) and
      is_integer(a["order"]) and a["order"] in 0..1000 and a["lifetime"] == "session" and
      a["allow_children"] === false and byte_size(Jason.encode!(a)) <= 4096
  rescue
    _ -> false
  end

  @doc "Bind data references to their exact reviewed policy artifact, instance and disclosed routes."
  def matches_policy?(activation, policy) do
    valid?(activation) and is_map(policy) and
      activation["artifact_sha256"] == policy["artifact_sha256"] and
      activation["instance"] == get_in(policy, ["settings", "instance"]) and
      refs_match?(activation["service_refs"], get_in(policy, ["settings", "routes"]))
  rescue
    _ -> false
  end

  @doc "Derive data only. The ordinary base fingerprint/catalog is never edited or stripped."
  def derive(policy, base_catalog) do
    with true <- Ipse.Extension.SemanticConsent.policy?(policy),
         true <- get_in(policy, ["settings", "version"]) === 2,
         a when is_map(a) <- get_in(policy, ["settings", "activation"]),
         true <- matches_policy?(a, policy) do
      draft(policy["project"], a, base_catalog)
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Prepare review data before a grant exists; this creates no identity or authority."
  def draft(project_sha256, a, base_catalog) do
    with true <- JSON.sha256?(project_sha256) and valid?(a),
         true <- keys?(base_catalog, ~w(instances trust)),
         true <- is_list(base_catalog["instances"]) and length(base_catalog["instances"]) < 8,
         true <- is_list(base_catalog["trust"]) and length(base_catalog["trust"]) < 16,
         false <- Enum.any?(base_catalog["instances"], &(&1["instance"] == a["instance"])),
         false <- Enum.any?(base_catalog["trust"], &(&1["artifact"] == a["artifact"])),
         activation_sha = JSON.digest([a]),
         source = "operator-activation:" <> project_sha256 <> ":" <> activation_sha,
         instance = %{
           "instance" => a["instance"],
           "artifact" => a["artifact"],
           "enabled" => true,
           "options" => a["options"],
           "order" => a["order"],
           "lifetime" => "session",
           "scope" => "operator",
           "source" => source
         },
         ceiling = %{
           "artifact" => a["artifact"],
           "capabilities" => a["capabilities"],
           "allow_project" => false,
           "allow_children" => false
         },
         catalog = %{
           "instances" =>
             Enum.sort_by([instance | base_catalog["instances"]], &{&1["order"], &1["instance"]}),
           "trust" => Enum.sort_by([ceiling | base_catalog["trust"]], & &1["artifact"])
         } do
      result = %{catalog: catalog, source: source, activation_sha256: activation_sha}

      {:ok,
       if(Map.has_key?(a, "main_timeout_ms"),
         do: Map.put(result, :main_timeout_ms, a["main_timeout_ms"]),
         else: result
       )}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp timeout?(%{"main_timeout_ms" => value}),
    do: is_integer(value) and value in 1000..100_000

  defp timeout?(_), do: true

  defp refs?(refs) do
    is_list(refs) and length(refs) <= 8 and
      Enum.all?(refs, fn ref ->
        keys?(ref, ~w(operation service_id profile)) and
          ref["operation"] in ~w(main model.complete embedding.create decision.create) and
          identifier?(ref["service_id"]) and
          (is_nil(ref["profile"]) or identifier?(ref["profile"]))
      end) and refs == Enum.sort_by(refs, & &1["operation"]) and
      length(Enum.uniq_by(refs, & &1["operation"])) == length(refs)
  end

  defp refs_match?([], routes), do: is_list(routes)

  defp refs_match?(refs, routes) when is_list(routes),
    do:
      Enum.all?(refs, fn ref ->
        Enum.count(routes, &(Map.take(&1, ~w(operation service_id profile)) == ref)) == 1
      end)

  defp refs_match?(_, _), do: false
  defp keys?(m, keys), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(keys)
  defp instance?(v), do: is_binary(v) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, v)

  defp identifier?(v),
    do: is_binary(v) and Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,127}\z/, v)

  defp capability?(v), do: is_binary(v) and Regex.match?(~r/\A[a-z][a-z0-9_.-]{0,127}\z/, v)
end
