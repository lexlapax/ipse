defmodule Ipse.MCP.Schema do
  @moduledoc "Bounded validator for the initial MCP tool-schema subset."

  @schema_limit 32 * 1024
  @argument_limit 16 * 1024
  @schema_depth 8
  @schema_nodes 256
  @argument_depth 12
  @string_bytes 8 * 1024
  @collection_size 128

  @schema_error "Invalid or unsupported tool schema."
  @argument_error "Tool arguments do not match the declared schema."
  @schema_keys ~w($schema type properties required additionalProperties items enum minLength maxLength minItems maxItems minimum maximum title description default)
  @types ~w(object string integer number boolean null array)
  @dialect "https://json-schema.org/draft/2020-12/schema"
  @draft7 "http://json-schema.org/draft-07/schema#"

  @doc "Validate one bounded schema from the documented JSON Schema subset."
  def validate_schema(schema) when is_map(schema) do
    with {:ok, count} <- schema_node(schema, 1, 0),
         true <- count <= @schema_nodes,
         {:ok, encoded} <- encode(schema),
         true <- byte_size(encoded) <= @schema_limit do
      :ok
    else
      _ -> {:error, @schema_error}
    end
  end

  def validate_schema(_), do: {:error, @schema_error}

  @doc "Validate JSON arguments against a schema, enforcing independent input bounds."
  def validate_arguments(schema, arguments) when is_map(schema) and is_map(arguments) do
    with :ok <- validate_schema(schema),
         :ok <- validate_object(arguments),
         {:ok, compiled} <- compile(schema),
         :ok <- JSONSchex.validate(compiled, arguments) do
      :ok
    else
      _ -> {:error, @argument_error}
    end
  rescue
    _ -> {:error, @argument_error}
  end

  def validate_arguments(_, _), do: {:error, @argument_error}

  @doc "Validate a bounded plain JSON object without compiling an application schema."
  def validate_object(arguments) when is_map(arguments) do
    with :ok <- json_value(arguments, 1),
         {:ok, encoded} <- encode(arguments),
         true <- byte_size(encoded) <= @argument_limit do
      :ok
    else
      _ -> {:error, @argument_error}
    end
  rescue
    _ -> {:error, @argument_error}
  end

  def validate_object(_), do: {:error, @argument_error}

  defp compile(schema) do
    # No loader is supplied: external references cannot trigger network or file access.
    # The admitted draft-07 keywords have identical validation semantics in our
    # subset: no refs, tuple items, dependencies, formats or other draft-specific
    # constructs pass schema_node. Compile that checked subset with JSONSchex's
    # supported dialect while retaining the original descriptor/digest on wire.
    schema =
      if schema["$schema"] == @draft7, do: Map.put(schema, "$schema", @dialect), else: schema

    JSONSchex.compile(schema, loader: nil)
  rescue
    _ -> {:error, :invalid}
  end

  defp schema_node(schema, depth, count)
       when is_map(schema) and depth <= @schema_depth and count < @schema_nodes do
    count = count + 1

    with true <- string_keyed?(schema),
         true <- Enum.all?(Map.keys(schema), &(&1 in @schema_keys)),
         :ok <- dialect(schema, depth),
         {:ok, type, nullable} <- type_spec(Map.get(schema, "type")),
         :ok <- metadata(schema),
         :ok <- properties(schema, type),
         :ok <- required(schema, type),
         :ok <- additional_properties(schema, type),
         :ok <- items(schema, type),
         :ok <- enum(schema, type, nullable),
         :ok <- constraints(schema, type) do
      schema_children(schema, type, depth + 1, count)
    else
      _ -> {:error, :invalid}
    end
  end

  defp schema_node(_, _, _), do: {:error, :invalid}

  defp schema_children(schema, "object", depth, count) do
    schema |> Map.get("properties", %{}) |> Map.values() |> count_schemas(depth, count)
  end

  defp schema_children(schema, "array", depth, count),
    do: count_schemas([schema["items"]], depth, count)

  defp schema_children(_schema, _type, _depth, count), do: {:ok, count}

  defp count_schemas(schemas, depth, count) do
    Enum.reduce_while(schemas, {:ok, count}, fn schema, {:ok, current} ->
      case schema_node(schema, depth, current) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  end

  defp properties(schema, "object") do
    case Map.get(schema, "properties", %{}) do
      props when is_map(props) ->
        if string_keyed?(props) and Enum.all?(Map.values(props), &is_map/1),
          do: :ok,
          else: {:error, :invalid}

      _ ->
        {:error, :invalid}
    end
  end

  defp properties(schema, _type), do: absent?(schema, "properties")

  defp required(schema, "object") do
    case Map.get(schema, "required", []) do
      fields when is_list(fields) ->
        props = Map.get(schema, "properties", %{})

        if Enum.all?(fields, &is_binary/1) and length(fields) == length(Enum.uniq(fields)) and
             Enum.all?(fields, &Map.has_key?(props, &1)),
           do: :ok,
           else: {:error, :invalid}

      _ ->
        {:error, :invalid}
    end
  end

  defp required(schema, _type), do: absent?(schema, "required")

  defp additional_properties(schema, "object") do
    case Map.get(schema, "additionalProperties", true) do
      value when is_boolean(value) -> :ok
      _ -> {:error, :invalid}
    end
  end

  defp additional_properties(schema, _type), do: absent?(schema, "additionalProperties")

  defp items(schema, "array"), do: if(is_map(schema["items"]), do: :ok, else: {:error, :invalid})
  defp items(schema, _type), do: absent?(schema, "items")

  defp enum(schema, type, nullable) do
    case Map.fetch(schema, "enum") do
      :error ->
        :ok

      {:ok, values} when is_list(values) and values != [] ->
        if Enum.all?(values, fn value ->
             scalar?(value) and
               (value_matches_type?(type, value) or (nullable and is_nil(value)))
           end) and
             length(values) == length(Enum.uniq(values)),
           do: :ok,
           else: {:error, :invalid}

      _ ->
        {:error, :invalid}
    end
  end

  defp constraints(schema, type) do
    allowed = constraint_keys(type)

    with true <- Enum.all?(~w(minLength maxLength), &allowed_or_absent?(schema, &1, allowed)),
         true <- Enum.all?(~w(minItems maxItems), &allowed_or_absent?(schema, &1, allowed)),
         true <- Enum.all?(~w(minimum maximum), &allowed_or_absent?(schema, &1, allowed)),
         :ok <- integer_bounds(schema, "minLength", "maxLength"),
         :ok <- integer_bounds(schema, "minItems", "maxItems"),
         :ok <- number_bounds(schema, "minimum", "maximum") do
      :ok
    else
      _ -> {:error, :invalid}
    end
  end

  defp constraint_keys("string"), do: ~w(minLength maxLength)
  defp constraint_keys("array"), do: ~w(minItems maxItems)
  defp constraint_keys(type) when type in ["integer", "number"], do: ~w(minimum maximum)
  defp constraint_keys(_), do: []

  defp allowed_or_absent?(schema, key, allowed),
    do: not Map.has_key?(schema, key) or key in allowed

  defp integer_bounds(schema, min_key, max_key) do
    min = Map.get(schema, min_key)
    max = Map.get(schema, max_key)

    valid? =
      (not Map.has_key?(schema, min_key) or (is_integer(min) and min >= 0)) and
        (not Map.has_key?(schema, max_key) or (is_integer(max) and max >= 0))

    if valid? and (is_nil(min) or is_nil(max) or min <= max), do: :ok, else: {:error, :invalid}
  end

  defp number_bounds(schema, min_key, max_key) do
    min = Map.get(schema, min_key)
    max = Map.get(schema, max_key)

    valid? =
      (not Map.has_key?(schema, min_key) or finite_number?(min)) and
        (not Map.has_key?(schema, max_key) or finite_number?(max))

    if valid? and (is_nil(min) or is_nil(max) or min <= max), do: :ok, else: {:error, :invalid}
  end

  defp metadata(schema) do
    valid? =
      Enum.all?(~w(title description), &(not Map.has_key?(schema, &1) or is_binary(schema[&1]))) and
        (not Map.has_key?(schema, "default") or json_value(schema["default"], 1) == :ok)

    if valid?, do: :ok, else: {:error, :invalid}
  end

  defp dialect(schema, 1) do
    case Map.fetch(schema, "$schema") do
      :error -> :ok
      {:ok, @dialect} -> :ok
      {:ok, @draft7} -> :ok
      _ -> {:error, :unsupported_dialect}
    end
  end

  defp dialect(schema, _depth), do: absent?(schema, "$schema")

  defp type_spec(type) when is_binary(type) and type in @types,
    do: {:ok, type, false}

  defp type_spec([first, second] = types) when length(types) == 2 do
    cond do
      first == "null" and second in @types and second != "null" -> {:ok, second, true}
      second == "null" and first in @types and first != "null" -> {:ok, first, true}
      true -> {:error, :invalid_type}
    end
  end

  defp type_spec(_), do: {:error, :invalid_type}

  defp absent?(schema, key), do: if(Map.has_key?(schema, key), do: {:error, :invalid}, else: :ok)

  defp value_matches_type?("object", value), do: is_map(value)
  defp value_matches_type?("array", value), do: is_list(value)
  defp value_matches_type?("string", value), do: is_binary(value) and String.valid?(value)
  defp value_matches_type?("integer", value), do: is_integer(value)
  defp value_matches_type?("number", value), do: finite_number?(value)
  defp value_matches_type?("boolean", value), do: is_boolean(value)
  defp value_matches_type?("null", value), do: is_nil(value)

  defp scalar?(value),
    do:
      is_nil(value) or is_binary(value) or is_boolean(value) or is_integer(value) or
        finite_number?(value)

  defp finite_number?(value) when is_integer(value), do: true
  defp finite_number?(value) when is_float(value), do: value == value and abs(value) < 1.0e308
  defp finite_number?(_), do: false

  defp json_value(_value, depth) when depth > @argument_depth, do: {:error, :invalid}

  defp json_value(value, _depth) when is_binary(value),
    do:
      if(String.valid?(value) and byte_size(value) <= @string_bytes,
        do: :ok,
        else: {:error, :invalid}
      )

  defp json_value(value, _depth) when is_boolean(value) or is_nil(value) or is_integer(value),
    do: :ok

  defp json_value(value, _depth) when is_float(value),
    do: if(finite_number?(value), do: :ok, else: {:error, :invalid})

  defp json_value(value, depth) when is_map(value) and map_size(value) <= @collection_size do
    if string_keyed?(value) do
      Enum.reduce_while(value, :ok, fn {key, item}, :ok ->
        with true <- String.valid?(key) and byte_size(key) <= @string_bytes,
             :ok <- json_value(item, depth + 1) do
          {:cont, :ok}
        else
          _ -> {:halt, {:error, :invalid}}
        end
      end)
    else
      {:error, :invalid}
    end
  end

  defp json_value(value, depth) when is_list(value) and length(value) <= @collection_size do
    Enum.reduce_while(value, :ok, fn item, :ok ->
      case json_value(item, depth + 1) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp json_value(_, _), do: {:error, :invalid}

  defp string_keyed?(map), do: Enum.all?(Map.keys(map), &is_binary/1)

  defp encode(value) do
    case Jason.encode(value) do
      {:ok, encoded} -> {:ok, encoded}
      _ -> {:error, :invalid}
    end
  rescue
    _ -> {:error, :invalid}
  end
end
