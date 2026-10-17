defmodule Ipse.Extensions.CatalogTest do
  use ExUnit.Case, async: true
  alias Ipse.Extensions.Catalog

  defp descriptor(id \\ "echo") do
    %{
      "id" => id,
      "description" => "Synthetic extension operation",
      "arguments_schema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{"text" => %{"type" => "string", "maxLength" => 1024}},
        "required" => ["text"]
      },
      "result_schema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{"text" => %{"type" => "string"}},
        "required" => ["text"]
      }
    }
  end

  defp exports(records \\ [descriptor()]), do: Map.put(Catalog.empty(), "tools", records)
  defp entry(instance, exports), do: %{identity: %{"instance" => instance}, exports: exports}

  test "closed inert descriptors match their negotiated capabilities" do
    assert :ok = Catalog.validate(nil, ["transform.prompt"])
    assert :ok = Catalog.validate(exports(), ["invoke.tool"])
    assert {:error, _} = Catalog.validate(nil, ["invoke.tool"])
    assert {:error, _} = Catalog.validate(exports(), [])
    assert {:error, _} = Catalog.validate(exports(), ["invoke.command"])
    assert {:error, _} = Catalog.validate(Map.put(exports(), "version", 1.0), ["invoke.tool"])
    assert {:error, _} = Catalog.validate(Map.put(exports(), "extra", true), ["invoke.tool"])
    assert {:error, _} = Catalog.validate(Map.delete(exports(), "commands"), ["invoke.tool"])
  end

  test "IDs, descriptions, JSON-only schemas and repeated exports are independently bounded" do
    for d <- [
          Map.put(descriptor(), "id", "../read"),
          Map.put(descriptor(), "id", String.duplicate("a", 33)),
          Map.put(descriptor(), "description", String.duplicate("é", 513)),
          Map.put(descriptor(), "extra", true),
          Map.put(descriptor(), "result_schema", %{"type" => "string"}),
          Map.put(descriptor(), "arguments_schema", %{
            "type" => "object",
            "$ref" => "https://example.invalid/schema"
          }),
          Map.put(descriptor(), "result_schema", %{type: "object"}),
          self()
        ] do
      assert {:error, _} = Catalog.validate(exports([d]), ["invoke.tool"])
    end

    assert {:error, _} = Catalog.validate(exports([descriptor(), descriptor()]), ["invoke.tool"])

    assert {:error, _} =
             Catalog.validate(exports(for n <- 1..9, do: descriptor("echo#{n}")), ["invoke.tool"])
  end

  test "qualified names cannot shadow builtins and delimiter collisions are refused" do
    config = %{extensions: [entry("one", exports())]}
    assert {:ok, %{"entries" => [export]}} = Catalog.snapshot(config)
    assert export["name"] == "ext__one__echo"
    refute export["name"] in ~w(read write edit shell ask_operator)

    assert {:error, _} =
             Catalog.snapshot(%{
               extensions: [
                 entry("a__b", exports([descriptor("c")])),
                 entry("a", exports([descriptor("b__c")]))
               ]
             })

    assert {:error, _} =
             Catalog.snapshot(%{extensions: [entry(String.duplicate("a", 64), exports())]})
  end

  test "global registration count and encoded catalog bytes have fixed ceilings" do
    all =
      Catalog.empty()
      |> Map.put("tools", for(n <- 1..3, do: descriptor("tool#{n}")))
      |> Map.put("commands", for(n <- 1..3, do: descriptor("cmd#{n}")))
      |> Map.put("services", for(n <- 1..3, do: descriptor("svc#{n}")))

    assert :ok = Catalog.validate(all, ~w(invoke.tool invoke.command invoke.service))
    assert {:error, _} = Catalog.snapshot(%{extensions: for(n <- 1..4, do: entry("i#{n}", all))})

    records =
      for n <- 1..8, do: Map.put(descriptor("op#{n}"), "description", String.duplicate("a", 1024))

    assert :ok = Catalog.validate(exports(records), ["invoke.tool"])

    assert {:error, _} =
             Catalog.snapshot(%{
               extensions: [entry("a", exports(records)), entry("b", exports(records))]
             })
  end

  test "only declared tools enter provider definitions; stage lookup is exact" do
    declarations =
      exports() |> Map.put("commands", [descriptor()]) |> Map.put("services", [descriptor()])

    config = %{extensions: [entry("one", declarations)]}

    assert [%{"function" => %{"name" => "ext__one__echo", "parameters" => schema}}] =
             Catalog.definitions(config)

    assert schema == descriptor()["arguments_schema"]

    for stage <- ~w(invoke.tool invoke.command invoke.service) do
      assert {:ok, _, %{"stage" => ^stage}} = Catalog.lookup(config, stage, "ext__one__echo")
    end

    assert {:error, _} = Catalog.lookup(config, "invoke.tool", "read")
    assert {:error, _} = Catalog.lookup(config, "invoke.unsupported", "ext__one__echo")
    assert Catalog.external?("ext__missing__tool")
    refute Catalog.external?(nil)
    assert Catalog.digest(nil) == Catalog.digest(Catalog.empty())
  end

  test "typed reply envelopes leave action-looking values inert and reject host proposals" do
    descriptor = Map.put(descriptor(), "result_schema", %{"type" => "object"})
    value = %{"actions" => [%{"kind" => "shell", "command" => "inert text"}]}

    assert {:ok, ^value} =
             Catalog.validate_response(
               descriptor,
               %{"api_version" => 1, "kind" => "result", "value" => value}
             )

    assert {:error, _} =
             Catalog.validate_response(
               descriptor,
               %{"api_version" => 1, "kind" => "actions", "value" => value}
             )

    assert {:error, _} =
             Catalog.validate_response(
               descriptor,
               %{"api_version" => 1.0, "kind" => "result", "value" => value}
             )
  end
end
