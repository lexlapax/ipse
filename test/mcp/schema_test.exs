defmodule Ipse.MCP.SchemaTest do
  use ExUnit.Case, async: true

  alias Ipse.MCP.Schema

  test "validates nested objects, required fields, arrays, scalar types, enums and bounds" do
    schema = %{
      "type" => "object",
      "properties" => %{
        "name" => %{"type" => "string", "minLength" => 1, "maxLength" => 20},
        "count" => %{"type" => "integer", "minimum" => 0, "maximum" => 10},
        "enabled" => %{"type" => "boolean", "enum" => [true]},
        "tags" => %{
          "type" => "array",
          "minItems" => 1,
          "maxItems" => 3,
          "items" => %{"type" => "string", "enum" => ["safe", "local"]}
        },
        "nested" => %{
          "type" => "object",
          "properties" => %{"value" => %{"type" => "number", "minimum" => 0.5}},
          "required" => ["value"],
          "additionalProperties" => false
        }
      },
      "required" => ["name", "count", "enabled", "tags", "nested"],
      "additionalProperties" => false,
      "description" => "A bounded fixture"
    }

    arguments = %{
      "name" => "fixture",
      "count" => 3,
      "enabled" => true,
      "tags" => ["safe", "local"],
      "nested" => %{"value" => 0.75}
    }

    assert :ok = Schema.validate_schema(schema)
    assert :ok = Schema.validate_arguments(schema, arguments)
    assert {:error, _} = Schema.validate_arguments(schema, Map.put(arguments, "count", 3.5))
    assert {:error, _} = Schema.validate_arguments(schema, Map.put(arguments, "unexpected", "x"))
    assert {:error, _} = Schema.validate_arguments(schema, Map.put(arguments, "tags", ["unsafe"]))
  end

  test "uses JSON Schema numeric equivalence for integers and enums" do
    integer_schema = %{"type" => "object", "properties" => %{"count" => %{"type" => "integer"}}}
    assert :ok = Schema.validate_arguments(integer_schema, %{"count" => 1})
    assert :ok = Schema.validate_arguments(integer_schema, %{"count" => 1.0})

    enum_schema = %{
      "type" => "object",
      "properties" => %{"amount" => %{"type" => "number", "enum" => [1]}}
    }

    assert :ok = Schema.validate_arguments(enum_schema, %{"amount" => 1})
    assert :ok = Schema.validate_arguments(enum_schema, %{"amount" => 1.0})
  end

  test "adapts only the identical draft-07 keyword subset without loading a remote dialect" do
    schema = %{
      "$schema" => "http://json-schema.org/draft-07/schema#",
      "type" => "object",
      "properties" => %{
        "query" => %{"type" => "string", "minLength" => 1},
        "count" => %{"type" => "number", "minimum" => 1, "maximum" => 3},
        "urls" => %{"type" => "array", "items" => %{"type" => "string"}, "maxItems" => 2}
      },
      "required" => ["query"],
      "additionalProperties" => false
    }

    assert :ok = Schema.validate_schema(schema)

    assert :ok =
             Schema.validate_arguments(schema, %{
               "query" => "public sources",
               "count" => 2,
               "urls" => ["https://example.com"]
             })

    for args <- [
          %{},
          %{"query" => ""},
          %{"query" => "x", "count" => 4},
          %{"query" => "x", "unexpected" => true}
        ] do
      assert {:error, _} = Schema.validate_arguments(schema, args)
    end

    assert {:error, _} =
             Schema.validate_schema(Map.put(schema, "$ref", "https://example.com/private"))

    assert {:error, _} = Schema.validate_schema(Map.put(schema, "dependencies", %{}))

    assert {:error, _} =
             Schema.validate_schema(%{
               "$schema" => "http://json-schema.org/draft-07/schema#",
               "type" => "array",
               "items" => [%{"type" => "string"}]
             })

    assert {:error, _} =
             Schema.validate_schema(
               Map.put(schema, "$schema", "http://json-schema.org/draft-04/schema#")
             )
  end

  test "accepts only the canonical root dialect and bounded inert defaults" do
    schema = %{
      "$schema" => "https://json-schema.org/draft/2020-12/schema",
      "type" => "object",
      "properties" => %{
        "name" => %{
          "type" => "string",
          "default" => "not inserted",
          "description" => "An inert schema annotation"
        }
      }
    }

    assert :ok = Schema.validate_schema(schema)
    assert :ok = Schema.validate_arguments(schema, %{})

    assert {:error, _} =
             Schema.validate_schema(%{schema | "$schema" => "http://example.test/schema"})

    assert {:error, _} =
             Schema.validate_schema(%{
               "type" => "object",
               "properties" => %{
                 "x" => %{
                   "type" => "string",
                   "$schema" => "https://json-schema.org/draft/2020-12/schema"
                 }
               }
             })

    assert {:error, _} =
             Schema.validate_schema(%{
               "type" => "string",
               "default" => String.duplicate("x", 8 * 1024 + 1)
             })
  end

  test "supports only narrow nullable type pairs with base-type constraints" do
    schema = %{
      "type" => "object",
      "properties" => %{
        "label" => %{
          "type" => ["string", "null"],
          "minLength" => 2,
          "enum" => ["ok", nil]
        },
        "count" => %{"type" => ["null", "integer"], "minimum" => 0}
      }
    }

    assert :ok = Schema.validate_schema(schema)
    assert :ok = Schema.validate_arguments(schema, %{"label" => nil, "count" => 1})
    assert :ok = Schema.validate_arguments(schema, %{"label" => "ok", "count" => nil})
    assert {:error, _} = Schema.validate_arguments(schema, %{"label" => "x"})
    assert {:error, _} = Schema.validate_arguments(schema, %{"label" => false})

    invalid_types = [
      ["string"],
      ["string", "integer"],
      ["null", "null"],
      ["mystery", "null"],
      ["string", "null", "integer"]
    ]

    for types <- invalid_types do
      assert {:error, _} =
               Schema.validate_schema(%{
                 "type" => "object",
                 "properties" => %{"x" => %{"type" => types}}
               })
    end

    assert {:error, _} =
             Schema.validate_schema(%{
               "type" => "object",
               "properties" => %{"x" => %{"type" => ["number", "null"], "minLength" => 1}}
             })
  end

  test "rejects unknown keywords, unsupported constructs, invalid shapes and conflicting bounds" do
    invalid = [
      %{"type" => "object", "$ref" => "#/definitions/x"},
      %{"type" => "object", "oneOf" => []},
      %{"type" => "object", "properties" => %{"x" => %{"type" => "string", "pattern" => ".*"}}},
      %{"type" => "object", "properties" => %{"x" => %{"type" => "string", "format" => "uri"}}},
      %{"type" => "mystery"},
      %{"type" => "array"},
      %{
        "type" => "object",
        "properties" => %{"x" => %{"type" => "integer", "minimum" => 4, "maximum" => 3}}
      },
      %{"type" => "object", "required" => ["missing"]},
      %{
        "type" => "object",
        "required" => ["x", "x"],
        "properties" => %{"x" => %{"type" => "null"}}
      },
      %{"type" => "object", "properties" => %{"x" => %{"type" => "number", "enum" => ["wrong"]}}},
      %{"type" => "object", "properties" => %{"x" => %{"type" => "string", "minItems" => 1}}}
    ]

    for schema <- invalid do
      assert {:error, "Invalid or unsupported tool schema."} = Schema.validate_schema(schema)
    end
  end

  test "enforces schema byte, nesting, and node limits with safe errors" do
    oversized = %{"type" => "object", "description" => String.duplicate("x", 33 * 1024)}
    assert {:error, _} = Schema.validate_schema(oversized)

    deep =
      Enum.reduce(1..9, %{"type" => "string"}, fn _, inner ->
        %{"type" => "array", "items" => inner}
      end)

    assert {:error, _} = Schema.validate_schema(deep)

    many_properties =
      Map.new(1..260, fn n -> {"p#{n}", %{"type" => "null"}} end)

    assert {:error, _} =
             Schema.validate_schema(%{"type" => "object", "properties" => many_properties})
  end

  test "bounds argument bytes, depth, strings and collections independently" do
    object_schema = %{"type" => "object", "additionalProperties" => true}
    assert :ok = Schema.validate_arguments(object_schema, %{"ok" => "yes"})

    assert {:error, _} =
             Schema.validate_arguments(object_schema, %{
               "large" => String.duplicate("x", 8 * 1024 + 1)
             })

    deep_value = Enum.reduce(1..12, "leaf", fn _, inner -> [inner] end)
    assert {:error, _} = Schema.validate_arguments(object_schema, %{"deep" => deep_value})

    too_many = Map.new(1..129, fn n -> {"k#{n}", n} end)
    assert {:error, _} = Schema.validate_arguments(object_schema, too_many)

    oversized = %{
      "first" => String.duplicate("y", 6_000),
      "second" => String.duplicate("z", 6_000),
      "third" => String.duplicate("q", 6_000)
    }

    assert {:error, _} = Schema.validate_arguments(object_schema, oversized)

    array_schema = %{
      "type" => "object",
      "properties" => %{"items" => %{"type" => "array", "items" => %{"type" => "integer"}}},
      "required" => ["items"]
    }

    assert {:error, _} =
             Schema.validate_arguments(array_schema, %{"items" => Enum.to_list(1..129)})
  end
end
