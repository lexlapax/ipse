defmodule Ipse.Extension.CollectionPlanningTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.Collection.{Migration, Planning}

  defp id(n), do: n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")

  defp receipt(n, floor),
    do: %{
      "generation" => n,
      "floor" => floor,
      "request_sha256" => Ipse.JSON.sha256("independent plan request #{n}")
    }

  defp state do
    %{
      "version" => 3,
      "project" => Ipse.JSON.sha256("independent plan project"),
      "generation" => 1,
      "floor" => 0,
      "floor_anchor" => nil,
      "floor_lineage" => [],
      "operations" => %{id(1) => receipt(1, 0)},
      "imported_operations" => %{},
      "records" =>
        Map.new(~w(a b), fn key ->
          {key,
           %{
             "key" => key,
             "sha256" => Ipse.JSON.sha256("value"),
             "bytes" => 42,
             "revision" => 1,
             "operation_id" => id(1)
           }}
        end),
      "migration" => nil,
      "checkpoint" => nil
    }
  end

  test "a typed complete metadata plan binds both digests and calculates actual new aliases" do
    source = state()
    descriptor = Migration.descriptor(source)
    plan = Planning.export(source)
    assert Planning.shape?(plan)

    assert {:ok, %{aliases: aliases, page_hashes: [_]}} =
             Planning.validate(source, descriptor, plan)

    assert aliases == %{}
    empty = %{source | "operations" => %{}, "generation" => 0, "records" => %{}}
    assert {:ok, %{aliases: new}} = Planning.validate(empty, descriptor, plan)
    assert new == source["operations"]
    changed = put_in(plan, ["records", Access.at(0), Access.at(1)], Ipse.JSON.sha256("changed"))
    assert {:failed, "collection_import_plan"} = Planning.validate(source, descriptor, changed)
  end

  test "duplicate unordered float oversized and open metadata shapes are refused" do
    plan = Planning.export(state())
    [first, second] = plan["records"]
    refute Planning.shape?(%{plan | "records" => [second, first]})
    refute Planning.shape?(%{plan | "records" => [first, first]})
    refute Planning.shape?(put_in(plan, ["records", Access.at(0), Access.at(2)], 42.0))
    refute Planning.shape?(Map.put(plan, "path", "/untrusted"))

    refute Planning.shape?(
             put_in(
               plan,
               ["operations", Access.at(0), Access.at(0)],
               String.duplicate("A", 100_000)
             )
           )

    receipt = hd(plan["operations"])
    refute Planning.shape?(%{plan | "operations" => [receipt, receipt]})
  end

  test "plans reject rewritten immutable identities before a writer fence exists" do
    target = state()

    source =
      put_in(target, ["operations", id(1), "request_sha256"], Ipse.JSON.sha256("different"))

    assert {:failed, "collection_operation_identity"} =
             Planning.validate(target, Migration.descriptor(source), Planning.export(source))
  end

  test "inspected aliases do not substitute for the applied lineage prefix" do
    target =
      state()
      |> Map.put("generation", 2)
      |> Map.put("floor", 2)
      |> Map.put("floor_anchor", id(2))
      |> Map.put("floor_lineage", [id(2)])
      |> put_in(["operations", id(2)], receipt(2, 2))

    source =
      target
      |> Map.put("generation", 3)
      |> Map.put("floor", 3)
      |> Map.put("floor_anchor", id(3))
      |> Map.put("floor_lineage", [id(3)])
      |> put_in(["operations", id(3)], receipt(3, 3))

    assert {:failed, "collection_import_lineage"} =
             Planning.validate(target, Migration.descriptor(source), Planning.export(source))
  end
end
