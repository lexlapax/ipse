defmodule Ipse.Extension.Collection.DocumentDraftNativeCapacityTest do
  use ExUnit.Case, async: false
  @moduletag :native_storage

  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.{Collection, CollectionStore}
  alias Ipse.Extension.Collection.{Blocks, DocumentDraft, DocumentStage, Profile}

  defp id(n), do: n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-draft-native-capacity-" <> Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)

    owner = %{
      "project_id" => JSON.sha256("draft capacity native project"),
      "session_id" => Usage.id(),
      "identity_sha256" => JSON.sha256("draft capacity native artifact"),
      "invocation_id" => Usage.id()
    }

    %{
      root: Path.join(parent, "collections"),
      ns: CollectionStore.namespace(owner["project_id"]),
      owner: owner
    }
  end

  defp snapshot(c) do
    assert {:ok, state} = Collection.document_snapshot(c.root, c.ns)
    state
  end

  defp prepare_epoch(c) do
    initial = snapshot(c)

    opening = %{
      "op" => "maintenance.open",
      "expected_generation" => initial["generation"],
      "expected_epoch" => 0,
      "maintenance_id" => Usage.id(),
      "purpose" => "checkpoint_inspection",
      "close_operation_id" => Usage.id()
    }

    assert {:ok, _} = Collection.document_maintenance(c.root, c.ns, opening, Usage.id(), c.owner)
    active = snapshot(c)

    close = %{
      "op" => "maintenance.close",
      "expected_generation" => active["generation"],
      "expected_epoch" => 1,
      "maintenance_id" => opening["maintenance_id"]
    }

    assert {:ok, _} =
             Collection.document_maintenance(
               c.root,
               c.ns,
               close,
               opening["close_operation_id"],
               c.owner
             )
  end

  defp read_state(c) do
    path = Path.join(c.root, c.ns)
    pointer = File.read!(Path.join(path, "root.json")) |> Jason.decode!()

    wire =
      File.read!(Path.join([path, "manifests", pointer["manifest"] <> ".json"]))
      |> Jason.decode!()

    assert {:ok, state, _} =
             Blocks.decode(wire, fn hash, _ ->
               File.read(Path.join([path, "manifests", hash <> ".json"]))
             end)

    state
  end

  defp object(c, key, value, operation_id) do
    bytes = Jason.encode!(value)
    hash = JSON.sha256(bytes)
    file = Path.join([c.root, c.ns, "objects", hash <> ".json"])
    File.write!(file, bytes)
    File.chmod!(file, 0o600)

    {key,
     %{
       "key" => key,
       "revision" => 1,
       "operation_id" => operation_id,
       "sha256" => hash,
       "bytes" => byte_size(bytes)
     }}
  end

  defp packed(body) do
    %{
      "version" => 1,
      "kind" => "document_value",
      "sha256" => JSON.sha256(body),
      "byte_count" => byte_size(body),
      "parts" => [body]
    }
  end

  defp public_key(n),
    do: "fixture.public." <> String.pad_leading(Integer.to_string(n), 5, "0")

  defp fits?(state) do
    with {:ok, bytes, blocks} <- Blocks.encode(state),
         {:ok, _} <- DocumentDraft.cleanup_reserve(state, bytes, blocks) do
      true
    else
      _ -> false
    end
  end

  defp last_fitting(low, high, _fits) when high - low == 1, do: low

  defp last_fitting(low, high, fits) do
    midpoint = div(low + high, 2)

    if fits.(midpoint),
      do: last_fitting(midpoint, high, fits),
      else: last_fitting(low, midpoint, fits)
  end

  defp install(c, state) do
    path = Path.join(c.root, c.ns)
    assert {:ok, bytes, blocks} = Blocks.encode(state)
    hash = JSON.sha256(bytes)

    for {digest, body} <- Map.put(blocks, hash, bytes) do
      file = Path.join([path, "manifests", digest <> ".json"])
      File.write!(file, body)
      File.chmod!(file, 0o600)
    end

    pointer =
      state
      |> Map.take(~w(version project generation floor floor_anchor))
      |> Map.put("version", Blocks.version(state))
      |> Map.put("manifest", hash)

    pointer = Profile.run(Profile.documents(), fn -> Profile.fence(pointer) end)
    File.write!(Path.join(path, "root.json"), Jason.encode!(pointer))
    File.chmod!(Path.join(path, "root.json"), 0o600)
    {bytes, blocks}
  end

  # Trusted disposable metadata construction: no 8,000-operation run or
  # claimed population benchmark. All referenced value objects are real files.
  defp seed_geometry(c) do
    state = read_state(c)
    base_generation = state["generation"]

    operations =
      Enum.reduce(1..6, state["operations"], fn i, rows ->
        generation = base_generation + i

        Map.put(rows, id(900_000 + i), %{
          "generation" => generation,
          "floor" => 0,
          "request_sha256" => JSON.sha256("synthetic ledger #{i}")
        })
      end)

    generation = base_generation + 6

    ids =
      operations
      |> Enum.sort_by(fn {_, receipt} -> receipt["generation"] end)
      |> Enum.map(&elem(&1, 0))

    first_id = hd(ids)
    body = Jason.encode!(%{"text" => String.duplicate("x", 30)})
    packed = packed(body)
    {_, public_record} = object(c, "fixture.public.1", packed, first_id)

    public =
      Map.new(1..8_000, fn n ->
        key = public_key(n)
        {key, %{public_record | "key" => key}}
      end)

    {heads, stage_records} =
      Enum.reduce(0..7, {%{}, %{}}, fn index, {heads, records} ->
        slot = index * 2
        active_epoch = id(100_000 + slot)
        sealed_epoch = id(100_001 + slot)
        active_key = "fixture.active.#{index}"
        sealed_key = "fixture.sealed.#{index}"

        active = %{
          "slot" => slot,
          "epoch" => active_epoch,
          "key" => active_key,
          "expected_revision" => 0,
          "byte_count" => byte_size(body),
          "sha256" => JSON.sha256(body),
          "offset" => 10,
          "publish" => true
        }

        prepared = %{"slot" => slot + 1, "epoch" => sealed_epoch}
        head_id = Enum.at(ids, index)

        head = %{
          "id" => head_id,
          "kind" => "projection",
          "owner" => Map.delete(c.owner, "invocation_id"),
          "plan_sha256" => JSON.sha256("plan #{index}"),
          "body_sha256" => JSON.sha256("body #{index}"),
          "maintenance_epoch" => 1,
          "retirement_epoch" => nil,
          "unit_limit" => 3,
          "unit" => 1,
          "revision" => generation,
          "slots" => [slot, slot + 1],
          "active" => active,
          "prepared" => [prepared]
        }

        # Model a collection opened across an upgrade: half the heads were
        # admitted before receipt reservation, and half use the new format.
        head = if rem(index, 2) == 1, do: Map.put(head, "retirement_operation", nil), else: head

        expiry = System.system_time(:millisecond) + 3_600_000

        common = %{
          "version" => 1,
          "owner" => c.owner,
          "expected_revision" => 0,
          "byte_count" => byte_size(body),
          "sha256" => JSON.sha256(body),
          "expires_at_ms" => expiry,
          "maintenance_epoch" => 1
        }

        active_header =
          Map.merge(common, %{
            "epoch" => active_epoch,
            "key" => active_key,
            "offset" => 10,
            "parts" => 10,
            "state" => "open",
            "write_publish" => true
          })

        sealed_header =
          Map.merge(common, %{
            "epoch" => sealed_epoch,
            "key" => sealed_key,
            "offset" => byte_size(body),
            "parts" => 0,
            "state" => "sealed"
          })

        rows =
          [
            object(c, "host.stage.#{slot}.header", active_header, first_id),
            object(c, "host.stage.#{slot + 1}.header", sealed_header, first_id),
            object(c, "host.stage.#{slot + 1}.ready", packed, first_id)
          ] ++
            Enum.map(0..9, fn part ->
              object(
                c,
                "host.stage.#{slot}.part.#{part}",
                %{
                  "epoch" => active_epoch,
                  "offset" => part,
                  "data" => binary_part(body, part, 1)
                },
                first_id
              )
            end)

        {Map.put(heads, head_id, head), Map.merge(records, Map.new(rows))}
      end)

    template =
      state
      |> Map.put("generation", generation)
      |> Map.put("operations", operations)
      |> Map.put("document_drafts", heads)

    geometry = fn count ->
      keys = Enum.map(1..count, &public_key/1)
      Map.put(template, "records", Map.merge(Map.take(public, keys), stage_records))
    end

    fits = fn count -> fits?(geometry.(count)) end
    assert fits.(1_000)
    refute fits.(8_000)
    count = last_fitting(1_000, 8_000, fits)
    seeded = geometry.(count)
    assert_record_ledger(seeded)
    assert fits?(seeded)
    refute fits.(count + 1)

    # The extra native write uses this same body and next prefix key. Its
    # operation identity and generation are included in the post-state model.
    write_id = id(999_999)
    key = public_key(count + 1)

    next_record =
      Map.merge(public[key], %{"revision" => generation + 1, "operation_id" => write_id})

    candidate =
      seeded
      |> put_in(["records", key], next_record)
      |> Map.put("generation", generation + 1)
      |> update_in(
        ["operations"],
        &Map.put(&1, write_id, %{
          "generation" => generation + 1,
          "floor" => 0,
          "request_sha256" => JSON.sha256("candidate native receipt")
        })
      )

    refute fits?(candidate)
    {seeded, install(c, seeded), count, body, key, write_id}
  end

  test "cleanup remains available after a real capacity refusal leaves the root unchanged", c do
    prepare_epoch(c)
    {seeded, {manifest, blocks}, count, body, new_key, write_id} = seed_geometry(c)
    assert {:ok, reserved} = DocumentDraft.cleanup_reserve(seeded, manifest, blocks)
    assert count in 1_000..7_999
    before = snapshot(c)
    assert before["generation"] == seeded["generation"]
    key = "fixture.public.00001"

    assert {:ok, %{"record" => %{"revision" => 1}}} =
             DocumentStage.execute(
               c.root,
               c.ns,
               %{"op" => "value.stat", "key" => key, "generation" => before["generation"]},
               Usage.id(),
               c.owner
             )

    root = Path.join([c.root, c.ns, "root.json"])
    root_before = File.read!(root)

    write = %{
      "op" => "value.put_inline",
      "key" => new_key,
      "expected_revision" => 0,
      "byte_count" => byte_size(body),
      "sha256" => JSON.sha256(body),
      "data" => body,
      "generation" => before["generation"],
      "maintenance_epoch" => 1
    }

    assert {:failed, %{"code" => "collection_capacity"}} =
             DocumentStage.execute(c.root, c.ns, write, write_id, c.owner)

    assert File.read!(root) == root_before
    assert snapshot(c)["generation"] == before["generation"]

    head = seeded["document_drafts"] |> Map.values() |> Enum.find(&(&1["active"]["slot"] == 2))
    active = head["active"]

    tag = %{
      "version" => 1,
      "action" => "retire",
      "head_id" => head["id"],
      "revision" => head["revision"]
    }

    abort = %{
      "op" => "value.abort",
      "slot" => active["slot"],
      "epoch" => active["epoch"],
      "generation" => before["generation"],
      "maintenance_epoch" => 1,
      "progress" => tag
    }

    marked_id = Usage.id()

    assert {:ok, %{"document_progress" => %{"status" => "retiring", "retirement_epoch" => 1}}} =
             DocumentStage.execute(c.root, c.ns, abort, marked_id, c.owner)

    after_marked = snapshot(c)
    marked_head = after_marked["document_drafts"][head["id"]]
    assert after_marked["generation"] == before["generation"] + 1

    assert marked_head["retirement_operation"] === %{
             "operation_id" => marked_id,
             "invocation_id" => c.owner["invocation_id"]
           }

    assert length(marked_head["prepared"]) == 1

    assert {:ok, %{"operation" => %{"generation" => revision}}} =
             Collection.execute_profile(
               c.root,
               c.ns,
               %{"op" => "inspect", "operation_id" => marked_id},
               Usage.id(),
               Profile.documents()
             )

    assert revision == marked_head["revision"]

    legacy =
      after_marked["document_drafts"]
      |> Map.values()
      |> Enum.find(&(&1["active"]["slot"] == 0))

    legacy_abort = %{
      "op" => "value.abort",
      "slot" => legacy["active"]["slot"],
      "epoch" => legacy["active"]["epoch"],
      "generation" => after_marked["generation"],
      "maintenance_epoch" => 1,
      "progress" => %{
        "version" => 1,
        "action" => "retire",
        "head_id" => legacy["id"],
        "revision" => legacy["revision"]
      }
    }

    legacy_root_before = File.read!(root)

    refute match?(
             {:ok, _},
             DocumentStage.execute(c.root, c.ns, legacy_abort, Usage.id(), c.owner)
           )

    after_legacy = snapshot(c)
    assert after_legacy === after_marked
    assert File.read!(root) === legacy_root_before
    refute Map.has_key?(after_legacy["document_drafts"][legacy["id"]], "retirement_operation")

    heads = Map.values(seeded["document_drafts"])

    marker = %{
      "version" => 1,
      "public_record_count" => count,
      "head_count" => length(heads),
      "reserved_slot_count" => length(DocumentDraft.reserved_slots(seeded)),
      "active_stage_count" => Enum.count(heads, &(not is_nil(&1["active"]))),
      "prepared_stage_count" => Enum.sum(Enum.map(heads, &length(&1["prepared"]))),
      "stage_record_count" =>
        Enum.count(Map.keys(seeded["records"]), &String.starts_with?(&1, "host.stage.")),
      "known_operation_count" =>
        map_size(seeded["operations"]) + map_size(seeded["imported_operations"]),
      "generation" => seeded["generation"],
      "base_block_count" => map_size(blocks),
      "base_block_body_bytes" =>
        Enum.sum(Enum.map(blocks, fn {_, bytes} -> byte_size(bytes) end)),
      "reserved_file_count" => length(reserved),
      "reserved_file_bytes" => Enum.sum(reserved),
      "adjacent_native_write_refused" => true,
      "root_and_generation_unchanged" => true,
      "marked_cleanup_first" => true,
      "owned_cleanup_confirmed" => true
    }

    IO.puts("DRAFT_CAPACITY " <> Jason.encode!(marker))
  end

  # Every record names the ledger operation that wrote it at its revision; the
  # loader rejects a root whose record revision differs from that operation's
  # generation.
  defp assert_record_ledger(state) do
    generations = Map.new(state["operations"], fn {id, r} -> {id, r["generation"]} end)
    assert state["generation"] === map_size(state["operations"])

    assert Enum.all?(state["records"], fn {_, r} ->
             generations[r["operation_id"]] === r["revision"]
           end)
  end

  # One unfinished single-stage head fills the 8,192-record live map with its
  # header and ten parts. Published values share one real object file. All
  # records are attributed to the generation-one operation, matching their
  # revision 1.
  defp seed_full_live_map(c) do
    state = read_state(c)
    generation = state["generation"] + 1
    head_id = id(910_001)

    {first_id, _} = Enum.find(state["operations"], fn {_, r} -> r["generation"] === 1 end)

    operations =
      Map.put(state["operations"], head_id, %{
        "generation" => generation,
        "floor" => 0,
        "request_sha256" => JSON.sha256("synthetic head admission")
      })

    body = Jason.encode!(%{"text" => String.duplicate("x", 30)})
    {_, public_record} = object(c, "fixture.public.1", packed(body), first_id)
    epoch = id(110_000)
    expiry = System.system_time(:millisecond) + 3_600_000

    header = %{
      "version" => 1,
      "owner" => c.owner,
      "expected_revision" => 0,
      "byte_count" => byte_size(body),
      "sha256" => JSON.sha256(body),
      "expires_at_ms" => expiry,
      "maintenance_epoch" => 1,
      "epoch" => epoch,
      "key" => "fixture.active.0",
      "offset" => 10,
      "parts" => 10,
      "state" => "open",
      "write_publish" => true
    }

    stage_records =
      Map.new(
        [object(c, "host.stage.0.header", header, first_id)] ++
          Enum.map(0..9, fn part ->
            object(
              c,
              "host.stage.0.part.#{part}",
              %{"epoch" => epoch, "offset" => part, "data" => binary_part(body, part, 1)},
              first_id
            )
          end)
      )

    head = %{
      "id" => head_id,
      "kind" => "projection",
      "owner" => Map.delete(c.owner, "invocation_id"),
      "plan_sha256" => JSON.sha256("full live map plan"),
      "body_sha256" => JSON.sha256("full live map body"),
      "maintenance_epoch" => 1,
      "retirement_epoch" => nil,
      "retirement_operation" => nil,
      "unit_limit" => 3,
      "unit" => 1,
      "revision" => generation,
      "slots" => [0, 1],
      "active" => %{
        "slot" => 0,
        "epoch" => epoch,
        "key" => "fixture.active.0",
        "expected_revision" => 0,
        "byte_count" => byte_size(body),
        "sha256" => JSON.sha256(body),
        "offset" => 10,
        "publish" => true
      },
      "prepared" => []
    }

    limit = Profile.run(Profile.documents(), fn -> Profile.limit(:records) end)
    count = limit - map_size(stage_records) - map_size(state["records"])

    public =
      Map.new(1..count, fn n ->
        key = public_key(n)
        {key, %{public_record | "key" => key}}
      end)

    seeded =
      state
      |> Map.put("generation", generation)
      |> Map.put("operations", operations)
      |> Map.put("document_drafts", %{head_id => head})
      |> Map.update!("records", &(&1 |> Map.merge(public) |> Map.merge(stage_records)))

    assert map_size(seeded["records"]) === 8_192
    assert_record_ledger(seeded)
    assert DocumentDraft.valid?(seeded)
    assert fits?(seeded)
    install(c, seeded)
    {seeded, head, body, public_key(count + 1)}
  end

  test "retiring an unfinished head frees its stage records but no published value", c do
    prepare_epoch(c)
    {seeded, head, body, new_key} = seed_full_live_map(c)
    before = snapshot(c)
    root = Path.join([c.root, c.ns, "root.json"])
    root_before = File.read!(root)

    write = fn generation ->
      %{
        "op" => "value.put_inline",
        "key" => new_key,
        "expected_revision" => 0,
        "byte_count" => byte_size(body),
        "sha256" => JSON.sha256(body),
        "data" => body,
        "generation" => generation,
        "maintenance_epoch" => 1
      }
    end

    # A full live map refuses one more published value without changing the root.
    assert {:failed, %{"code" => "collection_capacity"}} =
             DocumentStage.execute(
               c.root,
               c.ns,
               write.(before["generation"]),
               Usage.id(),
               c.owner
             )

    assert File.read!(root) == root_before

    retire = %{
      "op" => "value.abort",
      "slot" => 0,
      "epoch" => head["active"]["epoch"],
      "generation" => before["generation"],
      "maintenance_epoch" => 1,
      "progress" => %{
        "version" => 1,
        "action" => "retire",
        "head_id" => head["id"],
        "revision" => head["revision"]
      }
    }

    assert {:ok, %{"document_progress" => %{"status" => "retired"}}} =
             DocumentStage.execute(c.root, c.ns, retire, Usage.id(), c.owner)

    retired = read_state(c)
    refute Map.has_key?(retired["document_drafts"] || %{}, head["id"])
    assert map_size(retired["records"]) === 8_192 - 11
    refute Enum.any?(Map.keys(retired["records"]), &String.starts_with?(&1, "host.stage."))

    # Published values are retained exactly; the retirement spends, rather than
    # refunds, permanent operation history.
    published =
      Map.reject(seeded["records"], fn {key, _} -> String.starts_with?(key, "host.") end)

    assert Map.take(retired["records"], Map.keys(published)) === published
    assert map_size(retired["operations"]) === map_size(seeded["operations"]) + 1

    assert {:ok, _} =
             DocumentStage.execute(
               c.root,
               c.ns,
               write.(snapshot(c)["generation"]),
               Usage.id(),
               c.owner
             )

    assert map_size(read_state(c)["records"]) === 8_192 - 10
  end

  for kept <- [:active, :prepared] do
    test "a single #{kept} stage on an unretired legacy head finishes atomically", c do
      prepare_epoch(c)
      {seeded, _, _, _, _, _} = seed_geometry(c)

      legacy =
        seeded["document_drafts"]
        |> Map.values()
        |> Enum.find(&(&1["active"]["slot"] == 0))

      refute Map.has_key?(legacy, "retirement_operation")
      [prepared] = legacy["prepared"]
      active = legacy["active"]

      {head, removed_slot, retained_ref} =
        case unquote(kept) do
          :active ->
            {%{legacy | "prepared" => []}, prepared["slot"], Map.take(active, ~w(slot epoch))}

          :prepared ->
            {%{legacy | "active" => nil}, active["slot"], prepared}
        end

      prefix = "host.stage.#{removed_slot}."

      records =
        seeded["records"]
        |> Enum.reject(fn {key, _} -> String.starts_with?(key, prefix) end)
        |> Map.new()

      narrowed =
        seeded |> Map.put("records", records) |> put_in(["document_drafts", head["id"]], head)

      assert DocumentDraft.valid?(narrowed)
      install(c, narrowed)
      before = snapshot(c)

      request =
        Map.merge(retained_ref, %{
          "op" => "value.abort",
          "generation" => before["generation"],
          "maintenance_epoch" => 1,
          "progress" => %{
            "version" => 1,
            "action" => "retire",
            "head_id" => head["id"],
            "revision" => head["revision"]
          }
        })

      assert {:ok, %{"document_progress" => %{"status" => "retired"}}} =
               DocumentStage.execute(c.root, c.ns, request, Usage.id(), c.owner)

      after_abort = snapshot(c)
      assert after_abort["generation"] === before["generation"] + 1
      refute Map.has_key?(after_abort["document_drafts"], head["id"])
      assert Enum.all?(head["slots"], &(&1 in after_abort["document_available_slots"]))

      assert Map.take(read_state(c)["records"], ["fixture.public.00001"]) ===
               Map.take(narrowed["records"], ["fixture.public.00001"])
    end
  end
end
