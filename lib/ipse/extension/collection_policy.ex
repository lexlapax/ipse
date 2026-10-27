defmodule Ipse.Extension.CollectionPolicy do
  @moduledoc """
  Reviewed declarative constraints for a collection publication mapping.

  This pure check grants no authority. The owning host must resolve every proof
  against its current source window and recheck consent and suppression under
  the publication lock. Worker labels, schemas and proof-shaped JSON do not
  establish origin. Constraints come only from the pinned reviewed policy.
  """
  alias Ipse.JSON
  @keys ~w(version key_prefix value_schema evidence_path source_categories allow_delete)
  @origins ~w(interactive_operator native_operator_answer unattended_input assistant_proposal typed_host_outcome attributed_reference legacy_unverified)
  @error {:error, :collection_policy_refused}

  def valid_constraints?(c) do
    is_map(c) and Enum.sort(Map.keys(c)) == Enum.sort(@keys) and c["version"] === 1 and
      is_binary(c["key_prefix"]) and
      Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,31}\z/, c["key_prefix"]) and
      is_boolean(c["allow_delete"]) and path?(c["evidence_path"]) and
      categories?(c["source_categories"]) and
      JSON.validate_schema(c["value_schema"]) == :ok and
      c["value_schema"]["type"] == "object" and closed_schema?(c["value_schema"]) and
      byte_size(Jason.encode!(c)) <= 10_240
  rescue
    _ -> false
  end

  @doc "Check all changes against reviewed constraints and already authenticated stable proof receipts."
  def check(request, constraints, verified_proofs) do
    with true <- valid_constraints?(constraints),
         true <- Ipse.Extension.Collection.valid_request?(request),
         true <- request["op"] == "commit",
         true <- proofs?(verified_proofs, constraints["source_categories"]),
         true <- Enum.all?(request["changes"], &change?(&1, constraints, verified_proofs)) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp change?(change, constraints, proofs) do
    String.starts_with?(change["key"], constraints["key_prefix"]) and
      case change["value"] do
        nil ->
          constraints["allow_delete"]

        value ->
          JSON.validate_arguments(constraints["value_schema"], value) == :ok and
            supported?(field(value, constraints["evidence_path"]), proofs)
      end
  end

  defp supported?(selected, proofs) when is_list(selected) and selected != [] do
    length(selected) <= length(proofs) and length(Enum.uniq(selected)) == length(selected) and
      Enum.all?(selected, &(&1 in proofs))
  end

  defp supported?(_, _), do: false

  defp proofs?(proofs, categories) when is_list(proofs) and length(proofs) in 1..8 do
    length(Enum.uniq(proofs)) == length(proofs) and
      Enum.all?(proofs, fn proof ->
        is_map(proof) and proof["origin"] in categories and
          JSON.validate_object(proof) == :ok
      end) and byte_size(Jason.encode!(proofs)) <= 8192
  end

  defp proofs?(_, _), do: false

  defp field(value, []), do: value
  defp field(value, [key | rest]) when is_map(value), do: field(value[key], rest)
  defp field(_, _), do: nil

  defp path?(path) when is_list(path) and length(path) in 1..8,
    do: Enum.all?(path, &(is_binary(&1) and Regex.match?(~r/\A[a-zA-Z0-9_]{1,64}\z/, &1)))

  defp path?(_), do: false

  defp categories?(values) when is_list(values) and values != [],
    do: values == Enum.sort(Enum.uniq(values)) and Enum.all?(values, &(&1 in @origins))

  defp categories?(_), do: false

  defp closed_schema?(schema) do
    object? = schema["type"] == "object" or "object" in List.wrap(schema["type"])

    (not object? or schema["additionalProperties"] === false) and
      Enum.all?(Map.get(schema, "properties", %{}), fn {_, child} -> closed_schema?(child) end) and
      (not is_map(schema["items"]) or closed_schema?(schema["items"]))
  end
end
