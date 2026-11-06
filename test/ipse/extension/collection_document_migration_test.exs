defmodule Ipse.Extension.CollectionDocumentMigrationTest do
  use ExUnit.Case, async: true
  alias Ipse.JSON

  alias Ipse.Extension.Collection.{
    Blocks,
    DocumentDraft,
    DocumentMaintenance,
    DocumentMigration,
    Migration,
    Profile
  }

  defp id(n), do: n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")

  defp owner do
    %{
      "project_id" => JSON.sha256("document migration synthetic project"),
      "session_id" => id(80),
      "identity_sha256" => JSON.sha256("synthetic artifact"),
      "invocation_id" => id(81)
    }
  end

  defp packed(text) do
    body = Migration.encode(%{"text" => text, "revision" => 7})

    %{
      "version" => 1,
      "kind" => "document_value",
      "sha256" => JSON.sha256(body),
      "byte_count" => byte_size(body),
      "parts" => [body]
    }
  end

  defp state(entries) do
    {records, operations} =
      entries
      |> Enum.with_index(1)
      |> Enum.reduce({%{}, %{}}, fn {{key, n, value}, g}, {records, ops} ->
        bytes = Migration.encode(value)

        {Map.put(records, key, %{
           "key" => key,
           "revision" => g,
           "operation_id" => id(n),
           "sha256" => JSON.sha256(bytes),
           "bytes" => byte_size(bytes)
         }),
         Map.put(ops, id(n), %{
           "generation" => g,
           "floor" => 0,
           "request_sha256" => JSON.sha256(bytes)
         })}
      end)

    %{
      "version" => 3,
      "project" => Ipse.Extension.CollectionStore.namespace(owner()["project_id"]),
      "generation" => map_size(operations),
      "floor" => 0,
      "floor_anchor" => nil,
      "floor_lineage" => [],
      "records" => records,
      "operations" => operations,
      "imported_operations" => %{},
      "migration" => nil,
      "checkpoint" => nil
    }
  end

  defp fixtures do
    values = %{"a" => packed("é exact source"), "b" => packed("second")}
    source = state([{"a", 1, values["a"]}, {"b", 2, values["b"]}])
    target = state([{"prior", 9, packed("target checkpoint")}])
    {source, target, values}
  end

  defp request(s, op, args, input \\ nil) do
    frozen = s["migration"] || s["checkpoint"] || %{}

    r =
      Map.merge(
        %{
          "op" => op,
          "expected_generation" => s["generation"],
          "expected_epoch" => DocumentMaintenance.metadata(s)["epoch"],
          "plan_binding_sha256" => frozen["plan_binding_sha256"] || JSON.sha256("plan binding"),
          "dependency_union_sha256" => frozen["dependency_union_sha256"] || JSON.digest([[]])
        },
        args
      )

    r =
      if op === "restore.page",
        do: Map.put(r, "data_binding_sha256", Enum.at(frozen["data_bindings"], args["ordinal"])),
        else: r

    if is_nil(input),
      do: r,
      else: Map.put(r, "input_sha256", JSON.sha256(Migration.encode(input)))
  end

  defp sealed_plan(source) do
    input = DocumentMigration.export_plan(source)

    refs =
      Enum.with_index(input["plan"]["page_counts"], fn _, i ->
        %{
          "version" => 1,
          "session_id" => id(100 + i),
          "delivery" => %{
            "version" => 1,
            "kind" => "saved.result",
            "output_id" => JSON.sha256("page #{i}"),
            "sha256" => JSON.sha256("bytes #{i}"),
            "byte_count" => 1,
            "historical_receipt" => true
          }
        }
      end)

    update_in(
      input,
      ["plan"],
      &Map.merge(&1, %{
        "data_inputs" => refs,
        "data_bindings" => Enum.map(refs, fn r -> JSON.digest([r]) end),
        "dependency_union_sha256" => JSON.digest([[]])
      })
    )
  end

  defp publish(s, r, n, input \\ nil, actual_owner \\ owner()) do
    {:ok, next, values, extra} = DocumentMigration.prepare(s, r, id(n), actual_owner, input)

    receipt =
      Map.merge(
        %{
          "generation" => s["generation"] + 1,
          "floor" => next["floor"],
          "request_sha256" => JSON.digest([r, DocumentDraft.owner(actual_owner)])
        },
        extra
      )

    next = %{
      next
      | "generation" => receipt["generation"],
        "operations" => Map.put(s["operations"], id(n), receipt)
    }

    {next, values}
  end

  defp input(source, values) do
    rows =
      source["records"]
      |> Enum.sort()
      |> Enum.map(fn {k, row} -> Map.put(row, "value", values[k]) end)

    %{"descriptor" => DocumentMigration.descriptor(source), "records" => rows, "next" => nil}
  end

  defp open(source, target) do
    input = sealed_plan(source)
    publish(target, request(target, "restore.open", %{}, input), 10, input) |> elem(0)
  end

  test "closed request shapes never accept authority or filesystem fields" do
    r = %{"op" => "backup.page", "generation" => 0, "after" => nil, "limit" => 8}
    assert DocumentMigration.request?(r)
    refute DocumentMigration.request?(Map.put(r, "root", "/tmp/arbitrary"))
    refute DocumentMigration.request?(%{r | "limit" => 9})
    refute DocumentMigration.request?(%{"op" => "import.open", "expected_generation" => 0})
  end

  test "planned restore preserves exact packed bytes and receipts while rebasing native envelopes" do
    {source, target, values} = fixtures()
    opened = open(source, target)
    page = input(source, values)

    {paged, actual_values} =
      publish(
        opened,
        request(opened, "restore.page", %{"migration_id" => id(10), "ordinal" => 0}, page),
        11,
        page
      )

    assert actual_values ===
             Map.new(values, fn {_, v} ->
               b = Migration.encode(v)
               {JSON.sha256(b), b}
             end)

    {committed, %{}} =
      publish(paged, request(paged, "restore.commit", %{"migration_id" => id(10)}), 12)

    assert committed["records"]["b"]["revision"] === 3
    assert committed["records"]["b"]["operation_id"] === id(11)
    assert committed["imported_operations"] === source["operations"]
    assert committed["checkpoint"]["records"] === target["records"]
    assert Migration.reserved_operation_slots(committed) === 1
    assert DocumentMigration.checkpoint?(committed["checkpoint"], committed, &is_map/1)

    refute DocumentMigration.checkpoint?(
             %{committed["checkpoint"] | "id" => id(11)},
             committed,
             &is_map/1
           )

    assert {:failed, "collection_checkpoint_retained"} =
             DocumentMaintenance.prepare(
               committed,
               %{
                 "op" => "maintenance.open",
                 "expected_generation" => committed["generation"],
                 "expected_epoch" => 1,
                 "maintenance_id" => id(60),
                 "purpose" => "checkpoint_inspection",
                 "close_operation_id" => id(61),
                 "owner" => owner()
               },
               id(62),
               32_768
             )

    assert DocumentMaintenance.metadata(committed) === %{
             "version" => 1,
             "epoch" => 1,
             "status" => "idle"
           }

    {rolled, %{}} =
      publish(committed, request(committed, "restore.rollback", %{"checkpoint_id" => id(12)}), 13)

    assert rolled["records"] === target["records"]
    assert rolled["generation"] === 5
    assert rolled["imported_operations"] === source["operations"]
    assert DocumentMaintenance.metadata(rolled)["epoch"] === 2
    assert rolled["checkpoint"] === nil
    assert Migration.reserved_operation_slots(rolled) === 0
  end

  test "abort retains inspected identities and closes only the import epoch" do
    {source, target, _} = fixtures()
    opened = open(source, target)

    {aborted, %{}} =
      publish(opened, request(opened, "restore.abort", %{"migration_id" => id(10)}), 11)

    assert aborted["records"] === target["records"]
    assert aborted["imported_operations"] === source["operations"]
    assert aborted["migration"] === nil
    assert DocumentMaintenance.metadata(aborted)["epoch"] === 1
  end

  test "pending plan survives real block codec round trip and rejects opening tamper" do
    {source, target, _} = fixtures()
    opened = open(source, target)

    Profile.run(Profile.documents(), fn ->
      assert DocumentMigration.valid?(opened, &is_map/1)
      assert DocumentMaintenance.valid?(opened)
      assert {:ok, bytes, blocks} = Blocks.encode(opened)
      assert {:ok, wire} = JSON.decode_unique(bytes)

      assert {:ok, decoded, _} =
               Blocks.decode(wire, fn hash, _ -> {:ok, Map.fetch!(blocks, hash)} end)

      assert decoded === opened
      assert DocumentMigration.valid?(decoded, &is_map/1)

      refute DocumentMaintenance.valid?(
               put_in(opened, ["migration", "opening_sha256"], JSON.sha256("forged"))
             )
    end)
  end

  test "page substitution, reorder, duplicate and wrong ordinal refuse before a record is accepted" do
    {source, target, values} = fixtures()
    opened = open(source, target)
    page = input(source, values)
    r = request(opened, "restore.page", %{"migration_id" => id(10), "ordinal" => 0}, page)

    for changed <- [
          %{page | "records" => Enum.reverse(page["records"])},
          put_in(page, ["records", Access.at(0), "revision"], 99),
          %{page | "next" => "b"},
          %{page | "records" => [hd(page["records"]), hd(page["records"])]}
        ] do
      assert {:failed, _} = DocumentMigration.prepare(opened, r, id(11), owner(), changed)
    end

    assert {:failed, _} =
             DocumentMigration.prepare(opened, %{r | "ordinal" => 1}, id(11), owner(), page)

    assert opened["migration"]["records"] === %{}
  end

  test "another Session, artifact or epoch cannot accept or terminate the import" do
    {source, target, values} = fixtures()
    opened = open(source, target)
    page = input(source, values)
    r = request(opened, "restore.page", %{"migration_id" => id(10), "ordinal" => 0}, page)

    for other <- [
          %{owner() | "session_id" => id(82)},
          %{owner() | "identity_sha256" => JSON.sha256("other")}
        ] do
      assert {:failed, _} = DocumentMigration.prepare(opened, r, id(11), other, page)

      assert {:failed, _} =
               DocumentMigration.prepare(
                 opened,
                 request(opened, "restore.abort", %{"migration_id" => id(10)}),
                 id(11),
                 other,
                 nil
               )
    end

    assert {:failed, _} =
             DocumentMigration.prepare(
               opened,
               %{r | "expected_epoch" => 0},
               id(11),
               owner(),
               page
             )
  end

  test "complete incoming identities reject receipt collision and preserve exact overlap" do
    {source, _, _} = fixtures()
    plan = sealed_plan(source)
    assert {:ok, %{aliases: aliases}} = DocumentMigration.plan(source, plan)
    assert aliases === %{}
    changed = put_in(source, ["operations", id(1), "request_sha256"], JSON.sha256("collision"))
    assert {:failed, _} = DocumentMigration.plan(changed, plan)
    changed_plan = put_in(plan, ["plan", "records", Access.at(0), Access.at(1)], 2)
    assert {:failed, _} = DocumentMigration.plan(source, changed_plan)
  end

  test "packed part boundaries are preserved and malformed bodies refuse" do
    packed = packed("exact")
    assert DocumentMigration.packed?(packed)
    body = IO.iodata_to_binary(packed["parts"])
    <<first::binary-size(4), rest::binary>> = body
    assert DocumentMigration.packed?(%{packed | "parts" => [first, rest]})
    refute DocumentMigration.packed?(%{packed | "sha256" => JSON.sha256("other")})
    refute DocumentMigration.packed?(%{packed | "parts" => ["{\"x\":1,\"x\":2}"]})
  end

  test "inspection-only maintenance is not repurposed as import authority" do
    {source, target, _} = fixtures()

    active =
      Map.put(target, "document_maintenance", %{
        "version" => 1,
        "epoch" => 1,
        "status" => "active"
      })

    p = sealed_plan(source)

    assert {:failed, _} =
             DocumentMigration.prepare(
               active,
               request(active, "restore.open", %{}, p),
               id(10),
               owner(),
               p
             )

    refute DocumentMaintenance.request?(%{
             "op" => "maintenance.open",
             "expected_generation" => 0,
             "expected_epoch" => 0,
             "maintenance_id" => id(90),
             "purpose" => "document_import",
             "close_operation_id" => id(91)
           })
  end

  test "raw result references and complete union are sealed independently from canonical page bytes" do
    {source, target, values} = fixtures()
    unsealed = DocumentMigration.export_plan(source)
    assert {:failed, _} = DocumentMigration.plan(target, unsealed)
    sealed = sealed_plan(source)

    changed_ref =
      put_in(
        sealed,
        ["plan", "data_inputs", Access.at(0), "delivery", "sha256"],
        JSON.sha256("different raw delivery")
      )

    assert {:failed, _} = DocumentMigration.plan(target, changed_ref)
    opened = open(source, target)
    page = input(source, values)
    r = request(opened, "restore.page", %{"migration_id" => id(10), "ordinal" => 0}, page)

    assert {:failed, _} =
             DocumentMigration.prepare(
               opened,
               %{r | "data_binding_sha256" => JSON.sha256("different selected source")},
               id(11),
               owner(),
               page
             )

    assert {:failed, _} =
             DocumentMigration.prepare(
               opened,
               %{r | "dependency_union_sha256" => JSON.sha256("changed union")},
               id(11),
               owner(),
               page
             )

    abort = request(opened, "restore.abort", %{"migration_id" => id(10)})

    assert {:failed, _} =
             DocumentMigration.prepare(
               opened,
               %{abort | "plan_binding_sha256" => JSON.sha256("different plan")},
               id(11),
               owner(),
               nil
             )
  end

  test "open accounts for incoming aliases, every remaining page and both terminal liabilities" do
    {source, target, _} = fixtures()

    operations =
      Map.new(1..32_765, fn n ->
        {id(100_000 + n),
         %{"generation" => n, "floor" => 0, "request_sha256" => JSON.sha256("capacity")}}
      end)

    target = %{
      target
      | "records" => %{},
        "generation" => map_size(operations),
        "operations" => operations
    }

    plan = sealed_plan(source)

    assert {:failed, _} =
             DocumentMigration.prepare(
               target,
               request(target, "restore.open", %{}, plan),
               id(10),
               owner(),
               plan
             )

    assert source["generation"] === 2
  end

  test "bounded metadata pages retain the actual source generation and cannot silently truncate" do
    source = state(for n <- 1..10, do: {"key#{n}", n, packed("row #{n}")})

    r = %{
      "op" => "backup.metadata",
      "generation" => source["generation"],
      "section" => "operations",
      "offset" => 0,
      "limit" => 8
    }

    result = DocumentMigration.metadata(source, r)
    assert length(result["rows"]) === 8
    assert result["next"] === 8
    assert DocumentMigration.valid_result?(r, "ok", result, id(50), owner())
    refute DocumentMigration.valid_result?(r, "ok", %{result | "next" => nil}, id(50), owner())

    refute DocumentMigration.valid_result?(
             r,
             "ok",
             %{result | "rows" => Enum.take(result["rows"], 7)},
             id(50),
             owner()
           )

    assert byte_size(Jason.encode!(result)) < 12_000
  end

  test "compact successful receipts bind exact operation identity, owner and request" do
    {source, target, _} = fixtures()
    plan = sealed_plan(source)
    r = request(target, "restore.open", %{}, plan)
    {opened, _} = publish(target, r, 10, plan)
    receipt = opened["operations"][id(10)]
    assert DocumentMigration.valid_result?(r, "ok", receipt, id(10), owner())

    refute DocumentMigration.valid_result?(
             r,
             "ok",
             %{receipt | "migration_id" => id(12)},
             id(10),
             owner()
           )

    refute DocumentMigration.valid_result?(r, "ok", receipt, id(10), %{
             owner()
             | "identity_sha256" => JSON.sha256("other")
           })

    assert {:failed, _} =
             DocumentMigration.prepare(
               opened,
               request(opened, "restore.commit", %{"migration_id" => id(10)}),
               id(11),
               owner(),
               nil
             )
  end

  test "checkpoint disposition retains operation history and is same-owner bound" do
    {source, target, values} = fixtures()
    opened = open(source, target)
    page = input(source, values)

    {paged, _} =
      publish(
        opened,
        request(opened, "restore.page", %{"migration_id" => id(10), "ordinal" => 0}, page),
        11,
        page
      )

    {committed, _} =
      publish(paged, request(paged, "restore.commit", %{"migration_id" => id(10)}), 12)

    r = request(committed, "restore.checkpoint_drop", %{"checkpoint_id" => id(12)})

    assert {:failed, _} =
             DocumentMigration.prepare(
               committed,
               r,
               id(13),
               %{owner() | "session_id" => id(90)},
               nil
             )

    {dropped, _} = publish(committed, r, 13)
    assert dropped["records"] === committed["records"]
    assert dropped["checkpoint"] === nil
    assert dropped["imported_operations"] === source["operations"]
    assert dropped["generation"] === committed["generation"] + 1
    assert DocumentMaintenance.metadata(dropped)["epoch"] === 1
  end

  test "an imported higher floor retains its exact source anchor and prevents rollback" do
    {source, target, values} = fixtures()

    source =
      source
      |> Map.put("floor", 1)
      |> Map.put("floor_anchor", id(1))
      |> Map.put("floor_lineage", [id(1)])
      |> put_in(["operations", id(1), "floor"], 1)

    opened = open(source, target)
    page = input(source, values)

    {paged, _} =
      publish(
        opened,
        request(opened, "restore.page", %{"migration_id" => id(10), "ordinal" => 0}, page),
        11,
        page
      )

    {committed, _} =
      publish(paged, request(paged, "restore.commit", %{"migration_id" => id(10)}), 12)

    assert committed["checkpoint"] === nil
    assert committed["floor"] === 1
    assert committed["floor_anchor"] === id(1)
    assert committed["floor_lineage"] === [id(1)]
    assert committed["imported_operations"][id(1)] === source["operations"][id(1)]

    assert {:failed, _} =
             DocumentMigration.prepare(
               committed,
               request(committed, "restore.rollback", %{"checkpoint_id" => id(12)}),
               id(13),
               owner(),
               nil
             )
  end

  test "checkpoint byte reserve survives a head and stage while real disposition remains fenced" do
    {source, target, values} = fixtures()
    opened = open(source, target)
    page = input(source, values)

    {paged, _} =
      publish(
        opened,
        request(opened, "restore.page", %{"migration_id" => id(10), "ordinal" => 0}, page),
        11,
        page
      )

    {committed, _} =
      publish(paged, request(paged, "restore.commit", %{"migration_id" => id(10)}), 12)

    tag = %{
      "version" => 1,
      "action" => "start",
      "kind" => "source",
      "plan_sha256" => JSON.sha256("plan"),
      "body_sha256" => JSON.sha256("body"),
      "unit_limit" => 2
    }

    assert {:ok, head} = DocumentDraft.first_head(committed, tag, id(70), owner())

    active = %{
      "slot" => 0,
      "epoch" => id(71),
      "key" => "future",
      "expected_revision" => 0,
      "byte_count" => 20,
      "sha256" => JSON.sha256("body"),
      "offset" => 0,
      "publish" => false
    }

    g = committed["generation"] + 1
    receipt = %{"generation" => g, "floor" => 0, "request_sha256" => JSON.sha256("stage setup")}

    stage_record = %{
      "key" => "host.stage.0.header",
      "revision" => g,
      "operation_id" => id(70),
      "sha256" => JSON.sha256("{}"),
      "bytes" => 2
    }

    busy =
      committed
      |> Map.put("generation", g)
      |> put_in(["operations", id(70)], receipt)
      |> Map.put("document_drafts", %{id(70) => Map.put(head, "active", active)})
      |> put_in(["records", "host.stage.0.header"], stage_record)

    assert DocumentDraft.valid?(busy)
    refute DocumentMigration.quiescent?(busy)

    assert {:failed, _} =
             DocumentMigration.prepare(
               busy,
               request(busy, "restore.checkpoint_drop", %{"checkpoint_id" => id(12)}),
               id(72),
               owner(),
               nil
             )

    assert {:ok, manifest, blocks} = Blocks.encode(busy)
    assert {:ok, cleanup} = DocumentDraft.cleanup_reserve(busy, manifest, blocks)
    assert {:ok, ^cleanup, terminal} = DocumentDraft.cleanup_reserve(busy, manifest, blocks, 1)
    assert length(terminal) === 4
    assert Enum.sum(terminal) > 2 * 65_536
    assert Migration.reserved_operation_slots(busy) === 1
  end

  test "restore epoch is strictly newer than source and target while opening proof keeps actual prior epoch" do
    {source, target, _} = fixtures()

    source =
      Map.put(source, "document_maintenance", %{"version" => 1, "status" => "idle", "epoch" => 5})

    target =
      Map.put(target, "document_maintenance", %{"version" => 1, "status" => "idle", "epoch" => 2})

    assert DocumentMigration.descriptor(source)["maintenance_epoch"] === 5
    assert DocumentMigration.compact_descriptor(source)["maintenance_epoch"] === 5
    opened = open(source, target)
    assert opened["migration"]["opening_epoch"] === 2
    assert opened["migration"]["epoch"] === 6
    assert DocumentMaintenance.valid?(opened)
    assert DocumentMigration.valid?(opened, &is_map/1)
    assert {:ok, bytes, blocks} = Blocks.encode(opened)
    assert {:ok, wire} = JSON.decode_unique(bytes)
    assert {:ok, decoded, _} = Blocks.decode(wire, fn h, _ -> {:ok, Map.fetch!(blocks, h)} end)
    assert decoded === opened
    refute DocumentMaintenance.valid?(put_in(opened, ["migration", "opening_epoch"], 5))
    target = put_in(target, ["document_maintenance", "epoch"], 8)
    assert open(source, target)["migration"]["epoch"] === 9
  end

  test "source epoch is an exact finite descriptor field and overflow refuses without changing data" do
    {source, target, _} = fixtures()
    descriptor = DocumentMigration.descriptor(source)
    refute DocumentMigration.descriptor?(Map.delete(descriptor, "maintenance_epoch"))

    for bad <- [1.0, -1, "1", 9_007_199_254_740_992] do
      refute DocumentMigration.descriptor?(Map.put(descriptor, "maintenance_epoch", bad))
    end

    r = %{"op" => "backup.describe", "generation" => source["generation"]}
    value = %{"descriptor" => DocumentMigration.compact_descriptor(source)}
    assert DocumentMigration.valid_result?(r, "ok", value, id(90), owner())

    refute DocumentMigration.valid_result?(
             r,
             "ok",
             update_in(value["descriptor"], &Map.delete(&1, "maintenance_epoch")),
             id(90),
             owner()
           )

    max = 9_007_199_254_740_991

    for {source_epoch, target_epoch} <- [{max, 0}, {0, max}] do
      source =
        Map.put(source, "document_maintenance", %{
          "version" => 1,
          "status" => "idle",
          "epoch" => source_epoch
        })

      target =
        Map.put(target, "document_maintenance", %{
          "version" => 1,
          "status" => "idle",
          "epoch" => target_epoch
        })

      input = sealed_plan(source)

      assert {:failed, _} =
               DocumentMigration.prepare(
                 target,
                 request(target, "restore.open", %{}, input),
                 id(10),
                 owner(),
                 input
               )

      assert target["migration"] === nil
      assert target["records"] !== %{}
    end
  end
end
