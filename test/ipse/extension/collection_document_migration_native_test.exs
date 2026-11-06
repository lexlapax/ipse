defmodule Ipse.Extension.CollectionDocumentMigrationNativeTest do
  use ExUnit.Case, async: false
  @moduletag :document_migration_native
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.{Collection, CollectionStore}

  alias Ipse.Extension.Collection.{
    Blocks,
    DocumentDraft,
    DocumentMigration,
    DocumentStage,
    Migration,
    Profile
  }

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-document-migration-" <> Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)

    owner = %{
      "project_id" => JSON.sha256("native migration synthetic project"),
      "session_id" => Usage.id(),
      "identity_sha256" => JSON.sha256("native migration fixture"),
      "invocation_id" => Usage.id()
    }

    %{
      source: %{
        root: Path.join(parent, "source"),
        ns: CollectionStore.namespace(owner["project_id"]),
        owner: owner
      },
      target: %{
        root: Path.join(parent, "target"),
        ns: CollectionStore.namespace(owner["project_id"]),
        owner: owner
      }
    }
  end

  defp snapshot(c) do
    assert {:ok, result} = Collection.document_snapshot(c.root, c.ns)
    result
  end

  defp native_state(c) do
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

  # Trusted metadata setup in a fresh disposable namespace. This exercises the
  # real native admission at the history boundary, not 32,768 elapsed writes.
  defp install_history_boundary(c, state) do
    target_local = 32_766 - map_size(state["imported_operations"])
    known = Migration.known_operations(state)

    ids =
      1..32_768
      |> Enum.map(
        &(Integer.to_string(&1, 16)
          |> String.downcase()
          |> String.pad_leading(31, "0")
          |> then(fn id -> "e" <> id end))
      )
      |> Enum.reject(&Map.has_key?(known, &1))
      |> Enum.take(target_local - state["generation"])

    operations =
      ids
      |> Enum.with_index(state["generation"] + 1)
      |> Enum.reduce(state["operations"], fn {id, g}, ops ->
        Map.put(ops, id, %{
          "generation" => g,
          "floor" => 0,
          "request_sha256" => JSON.sha256("synthetic native history boundary")
        })
      end)

    state = %{state | "generation" => map_size(operations), "operations" => operations}
    assert DocumentDraft.operation_budget?(state)
    assert {:ok, bytes, blocks} = Blocks.encode(state)
    path = Path.join(c.root, c.ns)
    hash = JSON.sha256(bytes)

    for {digest, body} <- Map.put(blocks, hash, bytes) do
      file = Path.join([path, "manifests", digest <> ".json"])
      File.write!(file, body)
      File.chmod!(file, 0o600)
    end

    pointer =
      Map.take(state, ~w(version project generation floor floor_anchor))
      |> Map.put("version", Blocks.version(state))
      |> Map.put("manifest", hash)

    pointer = Profile.run(Profile.documents(), fn -> Profile.fence(pointer) end)
    File.write!(Path.join(path, "root.json"), Jason.encode!(pointer))
    File.chmod!(Path.join(path, "root.json"), 0o600)
    {state, bytes, blocks}
  end

  defp seed(c, key, text) do
    put_data(c, key, %{"text" => text, "revision" => 17})
  end

  defp put_data(c, key, value) do
    s = snapshot(c)
    body = Migration.encode(value)

    request = %{
      "op" => "value.put_inline",
      "key" => key,
      "expected_revision" => 0,
      "generation" => s["generation"],
      "byte_count" => byte_size(body),
      "sha256" => JSON.sha256(body),
      "data" => body
    }

    request =
      if s["document_maintenance"]["epoch"] > 0,
        do: Map.put(request, "maintenance_epoch", s["document_maintenance"]["epoch"]),
        else: request

    assert {:ok, result} = DocumentStage.execute(c.root, c.ns, request, Usage.id(), c.owner)
    result
  end

  defp read(c, request),
    do: Collection.document_migration(c.root, c.ns, request, Usage.id(), c.owner)

  # These Core tests supply an explicit synthetic Host callback. They do not
  # qualify approval, historical result selection or protected-source permission.
  defp backup(c) do
    g = snapshot(c)["generation"]
    assert {:ok, plan} = read(c, %{"op" => "backup.plan", "generation" => g})

    assert {:ok, page} =
             read(c, %{"op" => "backup.page", "generation" => g, "after" => nil, "limit" => 8})

    delivery = %{
      "version" => 1,
      "kind" => "saved.result",
      "output_id" => JSON.sha256("synthetic output"),
      "byte_count" => byte_size(Migration.encode(page)),
      "sha256" => JSON.sha256(Migration.encode(page)),
      "historical_receipt" => true
    }

    selected = %{"version" => 1, "session_id" => Usage.id(), "delivery" => delivery}

    sealed =
      update_in(
        plan,
        ["plan"],
        &Map.merge(&1, %{
          "data_inputs" => [selected],
          "data_bindings" => [JSON.digest([selected])],
          "dependency_union_sha256" => JSON.digest([[]])
        })
      )

    %{
      plan: sealed,
      page: page,
      plan_binding: JSON.sha256("synthetic selected plan"),
      data_binding: JSON.digest([selected]),
      union: JSON.digest([[]])
    }
  end

  defp request(c, b, op, args, input \\ nil) do
    s = snapshot(c)

    r =
      Map.merge(
        %{
          "op" => op,
          "expected_generation" => s["generation"],
          "expected_epoch" => s["document_maintenance"]["epoch"],
          "plan_binding_sha256" => b.plan_binding,
          "dependency_union_sha256" => b.union
        },
        args
      )

    r = if op === "restore.page", do: Map.put(r, "data_binding_sha256", b.data_binding), else: r

    if is_nil(input),
      do: r,
      else: Map.put(r, "input_sha256", JSON.sha256(Migration.encode(input)))
  end

  defp execute(c, b, r, input \\ nil, overrides \\ []) do
    opts = [
      publication_guard: fn -> :ok end,
      plan_binding_sha256: b.plan_binding,
      dependency_union_sha256: b.union
    ]

    opts =
      if DocumentMigration.input?(r),
        do:
          opts ++
            [
              with_input: fn accept -> accept.(input) end,
              input_binding_sha256:
                if(r["op"] === "restore.open", do: b.plan_binding, else: b.data_binding)
            ],
        else: opts

    id = Usage.id()

    result =
      Collection.document_migration(c.root, c.ns, r, id, c.owner, Keyword.merge(opts, overrides))

    {result, id}
  end

  defp opened(source, target) do
    seed(source, "source_a", "source body α")
    seed(source, "source_b", "second body")
    seed(target, "prior", "old target")
    b = backup(source)
    r = request(target, b, "restore.open", %{}, b.plan)
    assert {{:ok, receipt}, id} = execute(target, b, r, b.plan)
    assert receipt["migration_id"] === id
    assert DocumentMigration.valid_result?(r, "ok", receipt, id, target.owner)
    {b, id}
  end

  test "native planned import commits exact packed objects and rollback restores the old target",
       c do
    {b, migration} = opened(c.source, c.target)
    before_source = snapshot(c.source)

    r =
      request(c.target, b, "restore.page", %{"migration_id" => migration, "ordinal" => 0}, b.page)

    assert {{:ok, page_receipt}, _} = execute(c.target, b, r, b.page)
    r = request(c.target, b, "restore.commit", %{"migration_id" => migration})
    assert {{:ok, receipt}, commit_id} = execute(c.target, b, r)
    s = snapshot(c.target)
    assert s["document_maintenance"] === %{"version" => 1, "epoch" => 1, "status" => "idle"}

    for row <- b.page["records"] do
      assert {:ok, stat} =
               DocumentStage.execute(
                 c.target.root,
                 c.target.ns,
                 %{"op" => "value.layout", "generation" => s["generation"], "key" => row["key"]},
                 Usage.id(),
                 c.target.owner
               )

      assert stat["layout"]["record_sha256"] === row["sha256"]
      assert stat["layout"]["revision"] === page_receipt["generation"]
    end

    assert snapshot(c.source) === before_source
    r = request(c.target, b, "restore.rollback", %{"checkpoint_id" => commit_id})
    assert {{:ok, _}, _} = execute(c.target, b, r)
    after_rollback = snapshot(c.target)

    assert {:ok, %{"descriptor" => %{"records" => 1}}} =
             read(c.target, %{
               "op" => "backup.describe",
               "generation" => after_rollback["generation"]
             })

    assert after_rollback["document_maintenance"]["epoch"] === 2

    assert {:ok, _} =
             DocumentStage.execute(
               c.target.root,
               c.target.ns,
               %{
                 "op" => "value.read",
                 "generation" => after_rollback["generation"],
                 "key" => "prior",
                 "offset" => 0
               },
               Usage.id(),
               c.target.owner
             )

    assert receipt["checkpoint_id"] === commit_id
    seed(c.target, "after_rollback", "fresh epoch update")
  end

  test "same owner is required through pages and native abort retains observed source IDs", c do
    {b, migration} = opened(c.source, c.target)
    initial = snapshot(c.target)

    r =
      request(c.target, b, "restore.page", %{"migration_id" => migration, "ordinal" => 0}, b.page)

    other = %{c.target | owner: %{c.target.owner | "session_id" => Usage.id()}}
    assert {{:failed, %{"code" => "collection_import_state"}}, _} = execute(other, b, r, b.page)
    assert snapshot(c.target) === initial
    r = request(c.target, b, "restore.abort", %{"migration_id" => migration})
    assert {{:ok, _}, _} = execute(c.target, b, r)
    final = snapshot(c.target)

    assert {:ok, %{"descriptor" => %{"records" => 1}}} =
             read(c.target, %{"op" => "backup.describe", "generation" => final["generation"]})

    assert final["document_maintenance"]["status"] === "idle"
    assert final["document_maintenance"]["epoch"] === 1

    assert {:ok, source_receipts} =
             Ipse.Extension.Collection.Encoding.unpack_receipts(b.plan["plan"]["operations"])

    assert {:ok, metadata} =
             read(c.target, %{
               "op" => "backup.metadata",
               "generation" => final["generation"],
               "section" => "operations",
               "offset" => 0,
               "limit" => 8
             })

    actual = Map.new(metadata["rows"], fn [id, receipt] -> {id, receipt} end)

    for {source_id, receipt} <- source_receipts do
      assert actual[source_id] === receipt
    end
  end

  test "actual final publication guard refuses without switching the target and stays unknown",
       c do
    seed(c.source, "source_a", "source")
    b = backup(c.source)
    r = request(c.target, b, "restore.open", %{}, b.plan)

    guard = fn ->
      key = {__MODULE__, :guard_calls}
      n = Process.get(key, 0) + 1
      Process.put(key, n)
      if n === 1, do: :ok, else: {:error, :synthetic_source_lost}
    end

    assert {{:unknown, :collection_publication_unconfirmed}, _} =
             execute(c.target, b, r, b.plan, publication_guard: guard)

    assert snapshot(c.target)["generation"] === 0
  end

  test "a callback cannot forge a native result without consuming its selected input", c do
    seed(c.source, "source_a", "source")
    b = backup(c.source)
    r = request(c.target, b, "restore.open", %{}, b.plan)

    assert {{:error, :document_migration_input_not_consumed}, _} =
             execute(c.target, b, r, b.plan, with_input: fn _ -> {:ok, %{}} end)

    assert snapshot(c.target)["generation"] === 0

    assert {{:error, :invalid_document_migration_request}, _} =
             execute(c.target, b, r, b.plan,
               input_binding_sha256: JSON.sha256("other selected source")
             )

    assert snapshot(c.target)["generation"] === 0
  end

  @tag :checkpoint_reserve_boundary
  test "a fresh native target reserves checkpoint through stage cleanup and floor invalidation",
       c do
    seed(c.source, "source_a", "fresh target source")
    b = backup(c.source)
    r = request(c.target, b, "restore.open", %{}, b.plan)
    assert {{:ok, _}, migration} = execute(c.target, b, r, b.plan)

    r =
      request(c.target, b, "restore.page", %{"migration_id" => migration, "ordinal" => 0}, b.page)

    assert {{:ok, _}, _} = execute(c.target, b, r, b.page)
    r = request(c.target, b, "restore.commit", %{"migration_id" => migration})
    assert {{:ok, _}, checkpoint} = execute(c.target, b, r)

    current = snapshot(c.target)
    body = Migration.encode(%{"text" => "pending stage"})

    stage = %{
      "op" => "value.write_parts",
      "slot" => 0,
      "epoch" => Usage.id(),
      "key" => "pending",
      "expected_revision" => 0,
      "byte_count" => byte_size(body),
      "sha256" => JSON.sha256(body),
      "offset" => 0,
      "data" => [binary_part(body, 0, 4)],
      "publish" => false,
      "generation" => current["generation"],
      "maintenance_epoch" => 1,
      "progress" => %{
        "version" => 1,
        "action" => "start",
        "kind" => "source",
        "plan_sha256" => JSON.sha256("stage plan"),
        "body_sha256" => JSON.sha256(body),
        "unit_limit" => 2
      }
    }

    assert {:ok, staged} =
             DocumentStage.execute(c.target.root, c.target.ns, stage, Usage.id(), c.target.owner)

    {boundary, manifest, blocks} = install_history_boundary(c.target, native_state(c.target))
    assert {:ok, original_cleanup} = DocumentDraft.cleanup_reserve(boundary, manifest, blocks)

    assert {:ok, ^original_cleanup, checkpoint_reserve} =
             DocumentDraft.cleanup_reserve(boundary, manifest, blocks, 1)

    assert length(checkpoint_reserve) === 4
    assert Enum.sum(checkpoint_reserve) > 2 * 65_536
    before = File.read!(Path.join([c.target.root, c.target.ns, "root.json"]))
    s = snapshot(c.target)
    write_body = Migration.encode(%{"text" => "must not spend terminal identity"})

    write = %{
      "op" => "value.put_inline",
      "key" => "competing",
      "expected_revision" => 0,
      "generation" => s["generation"],
      "maintenance_epoch" => 1,
      "byte_count" => byte_size(write_body),
      "sha256" => JSON.sha256(write_body),
      "data" => write_body
    }

    assert {:failed, %{"code" => "collection_capacity"}} =
             DocumentStage.execute(c.target.root, c.target.ns, write, Usage.id(), c.target.owner)

    assert File.read!(Path.join([c.target.root, c.target.ns, "root.json"])) === before
    blocked = request(c.target, b, "restore.checkpoint_drop", %{"checkpoint_id" => checkpoint})
    assert {{:failed, _}, _} = execute(c.target, b, blocked)
    assert File.read!(Path.join([c.target.root, c.target.ns, "root.json"])) === before

    progress = staged["document_progress"]

    abort = %{
      "op" => "value.abort",
      "slot" => stage["slot"],
      "epoch" => stage["epoch"],
      "generation" => s["generation"],
      "maintenance_epoch" => 1,
      "progress" => %{
        "version" => 1,
        "action" => "retire",
        "head_id" => progress["head_id"],
        "revision" => progress["revision"]
      }
    }

    assert {:ok, _} =
             DocumentStage.execute(c.target.root, c.target.ns, abort, Usage.id(), c.target.owner)

    s = snapshot(c.target)
    assert s["document_maintenance"]["status"] === "idle"
    assert s["floor"] > boundary["floor"]
    retired = native_state(c.target)
    assert retired["checkpoint"] === nil
    assert DocumentDraft.heads(retired) === %{}
    assert Migration.reserved_operation_slots(retired) === 0
    assert map_size(Migration.known_operations(retired)) === 32_767
    assert s["document_available_slots"] === Enum.to_list(0..15)
    root_after_retirement = File.read!(Path.join([c.target.root, c.target.ns, "root.json"]))

    for op <- ~w(restore.checkpoint_drop restore.rollback) do
      r = request(c.target, b, op, %{"checkpoint_id" => checkpoint})
      assert {{:failed, %{"code" => "collection_rollback_floor"}}, _} = execute(c.target, b, r)

      assert File.read!(Path.join([c.target.root, c.target.ns, "root.json"])) ===
               root_after_retirement
    end

    assert {:ok, %{"descriptor" => %{"records" => 1}}} =
             read(c.target, %{"op" => "backup.describe", "generation" => s["generation"]})
  end

  test "loss of the selected-input callback after native publication stays unknown", c do
    seed(c.source, "source_a", "source")
    b = backup(c.source)
    r = request(c.target, b, "restore.open", %{}, b.plan)

    callback = fn accept ->
      assert {:ok, _} = accept.(b.plan)
      {:error, :synthetic_original_lease_lost}
    end

    assert {{:unknown, :collection_publication_unconfirmed}, _} =
             execute(c.target, b, r, b.plan, with_input: callback)

    s = snapshot(c.target)
    assert s["generation"] === 1
    assert s["document_maintenance"]["status"] === "active"
    assert s["document_maintenance"]["epoch"] === 1
  end

  test "an already expired trusted deadline cannot consume selected input or publish", c do
    seed(c.source, "source_a", "source")
    b = backup(c.source)
    r = request(c.target, b, "restore.open", %{}, b.plan)
    test = self()

    assert {{:error, :collection_use_expired}, _} =
             execute(c.target, b, r, b.plan,
               publish_before_ms: System.system_time(:millisecond) - 1,
               with_input: fn accept ->
                 send(test, :unexpected_input_read)
                 accept.(b.plan)
               end
             )

    refute_received :unexpected_input_read
    assert snapshot(c.target)["generation"] === 0
  end

  @tag :restore_source_epoch
  test "actual source epoch cannot alias a fresh target restore even when row stamps alias", c do
    initial = snapshot(c.source)
    close_id = Usage.id()

    opening = %{
      "op" => "maintenance.open",
      "expected_generation" => initial["generation"],
      "expected_epoch" => initial["document_maintenance"]["epoch"],
      "maintenance_id" => Usage.id(),
      "purpose" => "checkpoint_inspection",
      "close_operation_id" => close_id
    }

    assert {:ok, _} =
             Collection.document_maintenance(
               c.source.root,
               c.source.ns,
               opening,
               Usage.id(),
               c.source.owner
             )

    active = snapshot(c.source)

    close = %{
      "op" => "maintenance.close",
      "expected_generation" => active["generation"],
      "expected_epoch" => active["document_maintenance"]["epoch"],
      "maintenance_id" => opening["maintenance_id"]
    }

    assert {:ok, _} =
             Collection.document_maintenance(
               c.source.root,
               c.source.ns,
               close,
               close_id,
               c.source.owner
             )

    actual_source = snapshot(c.source)
    source_epoch = actual_source["document_maintenance"]["epoch"]
    assert source_epoch === 1

    token = %{
      "maintenance_epoch" => source_epoch,
      "job_revision" => actual_source["generation"] + 1
    }

    job = %{
      "kind" => "completed_job_epoch_fixture",
      "status" => "selected",
      "maintenance_epoch" => source_epoch,
      "token" => token
    }

    put_data(c.source, "completed_job", job)
    seed(c.target, "prior", "fresh unfenced target")
    assert snapshot(c.target)["document_maintenance"]["epoch"] === 0
    b = backup(c.source)
    assert b.plan["descriptor"]["maintenance_epoch"] === source_epoch
    assert b.page["descriptor"]["maintenance_epoch"] === source_epoch
    r = request(c.target, b, "restore.open", %{}, b.plan)
    assert {{:ok, _}, migration} = execute(c.target, b, r, b.plan)
    assert snapshot(c.target)["document_maintenance"]["epoch"] === source_epoch + 1

    r =
      request(c.target, b, "restore.page", %{"migration_id" => migration, "ordinal" => 0}, b.page)

    assert {{:ok, _}, _} = execute(c.target, b, r, b.page)
    r = request(c.target, b, "restore.commit", %{"migration_id" => migration})
    assert {{:ok, _}, _} = execute(c.target, b, r)
    restored = native_state(c.target)
    assert restored["records"]["completed_job"]["revision"] === token["job_revision"]
    assert restored["document_maintenance"]["epoch"] > token["maintenance_epoch"]

    assert {:ok, expected_receipts} =
             Ipse.Extension.Collection.Encoding.unpack_receipts(b.plan["plan"]["operations"])

    assert restored["imported_operations"] === expected_receipts
    s = snapshot(c.target)

    assert {:ok, read_back} =
             DocumentStage.execute(
               c.target.root,
               c.target.ns,
               %{
                 "op" => "value.read",
                 "key" => "completed_job",
                 "offset" => 0,
                 "generation" => s["generation"]
               },
               Usage.id(),
               c.target.owner
             )

    assert read_back["data"] === Migration.encode(job)
    before = File.read!(Path.join([c.target.root, c.target.ns, "root.json"]))
    stale_body = Migration.encode(%{"text" => "must refuse old source epoch"})

    stale = %{
      "op" => "value.put_inline",
      "key" => "stale",
      "expected_revision" => 0,
      "generation" => s["generation"],
      "maintenance_epoch" => token["maintenance_epoch"],
      "byte_count" => byte_size(stale_body),
      "sha256" => JSON.sha256(stale_body),
      "data" => stale_body
    }

    assert {:error, :document_store_refused} =
             DocumentStage.execute(c.target.root, c.target.ns, stale, Usage.id(), c.target.owner)

    assert File.read!(Path.join([c.target.root, c.target.ns, "root.json"])) === before
  end
end
