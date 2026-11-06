defmodule Ipse.Extension.Collection.DocumentMaintenanceTest do
  use ExUnit.Case, async: false
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.{Collection, CollectionStore}

  alias Ipse.Extension.Collection.{
    Blocks,
    DocumentMaintenance,
    DocumentStage,
    Encoding,
    Migration,
    Profile
  }

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-document-maintenance-" <> Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)

    owner = %{
      "project_id" => JSON.sha256("maintenance project"),
      "session_id" => Usage.id(),
      "identity_sha256" => JSON.sha256("maintenance artifact"),
      "invocation_id" => Usage.id()
    }

    %{
      root: Path.join(parent, "collections"),
      ns: CollectionStore.namespace(owner["project_id"]),
      owner: owner
    }
  end

  defp snapshot(c) do
    assert {:ok, snapshot} = Collection.document_snapshot(c.root, c.ns)
    snapshot
  end

  defp maintain(c, request, id \\ Usage.id()),
    do: Collection.document_maintenance(c.root, c.ns, request, id, c.owner)

  defp open_request(c) do
    s = snapshot(c)

    %{
      "op" => "maintenance.open",
      "expected_generation" => s["generation"],
      "expected_epoch" => s["document_maintenance"]["epoch"],
      "maintenance_id" => Usage.id(),
      "purpose" => "checkpoint_inspection",
      "close_operation_id" => Usage.id()
    }
  end

  defp open(c) do
    request = open_request(c)
    id = Usage.id()
    assert {:ok, receipt} = maintain(c, request, id)
    {request, id, receipt}
  end

  defp close(c, opening) do
    s = snapshot(c)

    request = %{
      "op" => "maintenance.close",
      "expected_generation" => s["generation"],
      "expected_epoch" => s["document_maintenance"]["epoch"],
      "maintenance_id" => opening["maintenance_id"]
    }

    maintain(c, request, opening["close_operation_id"])
  end

  defp call(c, request, id \\ Usage.id()) do
    request =
      if request["op"] in ~w(snapshot stage.list),
        do: request,
        else: Map.put(request, "generation", snapshot(c)["generation"])

    DocumentStage.execute(c.root, c.ns, request, id, c.owner)
  end

  defp put(c, key) do
    bytes = Jason.encode!(%{"text" => key})

    call(c, %{
      "op" => "value.put_inline",
      "key" => key,
      "expected_revision" => 0,
      "byte_count" => byte_size(bytes),
      "sha256" => JSON.sha256(bytes),
      "data" => bytes
    })
  end

  defp raw(c, request, id \\ Usage.id()),
    do: Collection.execute_profile(c.root, c.ns, request, id, Profile.documents())

  defp commit(generation, key),
    do: %{
      "op" => "commit",
      "expected_generation" => generation,
      "advance_floor" => false,
      "changes" => [%{"key" => key, "expected_revision" => 0, "value" => %{}}]
    }

  defp state(c) do
    path = Path.join(c.root, c.ns)
    pointer = File.read!(Path.join(path, "root.json")) |> Jason.decode!()

    wire =
      File.read!(Path.join([path, "manifests", pointer["manifest"] <> ".json"]))
      |> Jason.decode!()

    assert {:ok, state, _} =
             Blocks.decode(wire, fn hash, _bytes ->
               File.read(Path.join([path, "manifests", hash <> ".json"]))
             end)

    state
  end

  # Trusted disposable metadata setup, reusing the real canonical block codec.
  # This does not qualify import or represent elapsed operation endurance.
  defp install_state(c, state) do
    path = Path.join(c.root, c.ns)
    assert {:ok, bytes, blocks} = Blocks.encode(state)
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
  end

  test "metadata lifecycle preserves records, checkpoint, destructive floor and receipts", c do
    assert {:ok, _} = put(c, "unchanged")
    original = state(c)

    checkpoint = %{
      "id" => Usage.id(),
      "generation" => original["generation"],
      "floor" => original["floor"],
      "floor_anchor" => original["floor_anchor"],
      "floor_lineage_sha256" => JSON.digest([original["floor_lineage"]]),
      "records" => original["records"]
    }

    original = Map.put(original, "checkpoint", checkpoint)
    install_state(c, original)
    {request, id, receipt} = open(c)
    active = state(c)
    assert active["document_maintenance"]["epoch"] === 1
    assert active["checkpoint"] === checkpoint and active["records"] === original["records"]

    assert active["floor"] === original["floor"] and
             active["floor_lineage"] === original["floor_lineage"]

    assert {:existing, %{"operation" => ^receipt}} = maintain(c, request, id)
    assert {:ok, _} = close(c, request)
    closed = state(c)
    assert closed["document_maintenance"] === %{"version" => 1, "epoch" => 1, "status" => "idle"}
    assert closed["checkpoint"] === checkpoint and closed["records"] === original["records"]

    assert closed["floor_anchor"] === original["floor_anchor"] and
             closed["floor"] === original["floor"]

    assert closed["operations"][id] === receipt
    {next, _, _} = open(c)
    assert snapshot(c)["document_maintenance"]["epoch"] === 2
    assert {:ok, _} = close(c, next)
  end

  test "active fence and reserved close identity refuse ordinary writers and foreign close", c do
    {request, _, _} = open(c)
    generation = snapshot(c)["generation"]
    assert {:failed, %{"code" => "collection_writer_fenced"}} = put(c, "blocked")

    assert {:failed, %{"code" => "collection_operation_identity"}} =
             raw(c, commit(generation, "steal-reserved-id"), request["close_operation_id"])

    foreign = %{c | owner: Map.put(c.owner, "session_id", Usage.id())}

    assert {:failed, %{"code" => "collection_document_maintenance_owner"}} =
             close(foreign, request)

    assert snapshot(c)["generation"] === generation
    assert {:ok, _} = close(c, request)
    assert {:ok, _} = put(c, "fresh-admitted")

    assert {:failed, %{"code" => "collection_document_epoch"}} =
             raw(c, commit(snapshot(c)["generation"], "plain-after-fence"))
  end

  test "actual old host admission cannot publish after open and close with refreshed generation",
       c do
    assert {:ok, _} =
             Collection.with_document_admission(c.root, c.ns, c.owner, fn before ->
               assert before["generation"] === 0
               {request, _, _} = open(c)
               assert {:ok, _} = close(c, request)

               assert {:failed, %{"code" => "collection_document_epoch"}} =
                        raw(c, commit(snapshot(c)["generation"], "old-admission"))

               {:ok, :observed}
             end)

    assert Collection.admitted_document_epoch() === nil
    assert {:ok, _} = put(c, "new-admission")
  end

  test "same epoch admission cannot be substituted across protected roots or projects", c do
    other_root = %{c | root: c.root <> "-other"}
    other_project = %{c | owner: Map.put(c.owner, "project_id", JSON.sha256("other project"))}

    other_project = %{
      other_project
      | ns: CollectionStore.namespace(other_project.owner["project_id"])
    }

    for target <- [c, other_root, other_project] do
      {request, _, _} = open(target)
      assert {:ok, _} = close(target, request)
    end

    assert {:error, :invalid_document_admission} =
             Collection.with_document_admission(c.root, other_project.ns, c.owner, fn _ ->
               flunk("foreign namespace callback ran")
             end)

    Collection.with_document_admission(c.root, c.ns, c.owner, fn _ ->
      for target <- [other_root, other_project] do
        assert snapshot(target)["document_maintenance"]["epoch"] === 1

        assert {:failed, %{"code" => "collection_document_admission"}} =
                 raw(target, commit(snapshot(target)["generation"], "foreign-admission"))
      end
    end)

    assert {:ok, _} = put(other_root, "own-root")
    assert {:ok, _} = put(other_project, "own-project")
  end

  test "inspection admitted while active cannot become publication after close at the same epoch",
       c do
    {request, _, _} = open(c)

    Collection.with_document_admission(c.root, c.ns, c.owner, fn _ ->
      assert {:ok, _} = close(c, request)
      assert snapshot(c)["document_maintenance"]["epoch"] === 1

      assert {:failed, %{"code" => "collection_document_admission"}} =
               raw(c, commit(snapshot(c)["generation"], "active-admission"))
    end)

    assert {:ok, _} = put(c, "fresh-idle-admission")
  end

  test "old stored stage remains fenced after close; new stage metadata stays out of SDK outcomes",
       c do
    bytes = Jason.encode!(%{"text" => "staged"})
    old_epoch = Usage.id()

    prepare = %{
      "op" => "value.prepare_inline",
      "slot" => 0,
      "epoch" => old_epoch,
      "key" => "old.stage",
      "expected_revision" => 0,
      "byte_count" => byte_size(bytes),
      "sha256" => JSON.sha256(bytes),
      "data" => bytes
    }

    assert {:ok, _} = call(c, prepare)
    refute Map.has_key?(state(c)["document_maintenance"] || %{}, "epoch")
    {request, _, _} = open(c)
    assert {:ok, _} = close(c, request)

    assert {:error, :document_store_refused} =
             call(c, %{"op" => "commit", "stages" => [%{"slot" => 0, "epoch" => old_epoch}]})

    refute DocumentStage.request?(%{
             "op" => "commit",
             "generation" => snapshot(c)["generation"],
             "stages" => [%{"slot" => 0, "epoch" => old_epoch, "maintenance_epoch" => 1}]
           })

    assert {:ok, _} = call(c, %{"op" => "value.abort", "slot" => 0, "epoch" => old_epoch})
    new_prepare = %{prepare | "slot" => 1, "epoch" => Usage.id(), "key" => "new.stage"}
    id = Usage.id()
    generation = snapshot(c)["generation"]
    assert {:ok, result} = call(c, new_prepare, id)
    refute Map.has_key?(result["stage"], "maintenance_epoch")

    envelope = %{
      "op" => "collection.store",
      "scope" => "project",
      "request" => Map.put(new_prepare, "generation", generation)
    }

    assert CollectionStore.valid_outcome?(
             envelope,
             "ok",
             %{
               "version" => 1,
               "operation_id" => id,
               "request_sha256" => JSON.digest([envelope]),
               "result" => result
             },
             id
           )

    assert {:ok, %{"record" => %{"value" => %{"maintenance_epoch" => 1}}}} =
             raw(c, %{"op" => "get", "key" => "host.stage.1.header"})

    assert {:ok, _} =
             call(c, %{"op" => "commit", "stages" => [Map.take(new_prepare, ~w(slot epoch))]})
  end

  test "typed owner, epoch, ID and unexposed SDK operation checks fail closed", c do
    r = open_request(c)
    refute Collection.valid_request?(r)
    refute DocumentStage.request?(r)
    refute DocumentMaintenance.request?(Map.put(r, "expected_epoch", 0.0))
    refute DocumentMaintenance.request?(Map.put(r, "owner", c.owner))

    assert {:error, :invalid_document_maintenance_request} =
             Collection.document_maintenance(
               c.root,
               JSON.sha256("foreign namespace"),
               r,
               Usage.id(),
               c.owner
             )

    id = Usage.id()

    assert {:failed, %{"code" => "collection_operation_identity"}} =
             maintain(c, %{r | "close_operation_id" => id}, id)

    assert snapshot(c)["generation"] === 0
    {request, opened_id, _} = open(c)

    assert {:failed, %{"code" => "collection_operation_identity"}} =
             maintain(c, %{request | "maintenance_id" => Usage.id()}, opened_id)

    assert {:ok, _} = close(c, request)
  end

  test "native reload rejects a changed opening commitment and overflow never resets epoch", c do
    {_, _, _} = open(c)
    active = state(c)

    tampered =
      put_in(active, ["document_maintenance", "opening_sha256"], JSON.sha256("forged anchor"))

    refute DocumentMaintenance.valid?(tampered)
    install_state(c, tampered)
    assert {:error, :collection_unavailable} = Collection.document_snapshot(c.root, c.ns)

    idle =
      Map.put(active, "document_maintenance", %{
        "version" => 1,
        "status" => "idle",
        "epoch" => 9_007_199_254_740_991
      })

    install_state(c, idle)
    before = state(c)
    assert {:failed, %{"code" => "collection_document_epoch"}} = maintain(c, open_request(c))
    assert state(c) === before
  end

  test "exact terminal reservation fits the last two IDs and cannot consume known imported IDs",
       c do
    snapshot(c)

    base = %{
      "version" => 3,
      "project" => c.ns,
      "generation" => 32_765,
      "floor" => 0,
      "floor_anchor" => nil,
      "floor_lineage" => [],
      "records" => %{},
      "imported_operations" => %{
        Base.encode16(<<32_766::128>>, case: :lower) => %{
          "generation" => 1,
          "floor" => 0,
          "request_sha256" => JSON.sha256("known imported operation")
        }
      },
      "migration" => nil,
      "checkpoint" => nil,
      "operations" =>
        Map.new(1..32_765, fn n ->
          {Base.encode16(<<n::128>>, case: :lower),
           %{
             "generation" => n,
             "floor" => 0,
             "request_sha256" => JSON.sha256(Integer.to_string(n))
           }}
        end)
    }

    install_state(c, base)
    r = open_request(c)

    assert {:failed, %{"code" => "collection_operation_identity"}} =
             maintain(c, %{
               r
               | "close_operation_id" => Base.encode16(<<32_766::128>>, case: :lower)
             })

    {request, _, _} = open(c)
    assert {:ok, %{"reserved_operation_slots" => 1}} = raw(c, %{"op" => "status"})
    assert {:ok, _} = close(c, request)
    assert snapshot(c)["generation"] === 32_767

    assert {:ok, %{"operations" => 32_768, "reserved_operation_slots" => 0}} =
             raw(c, %{"op" => "status"})

    assert {:failed, %{"code" => "collection_capacity"}} = maintain(c, open_request(c))
  end

  test "document codecs and rollback preserve maintenance metadata", c do
    assert {:ok, _} = put(c, "codec")
    refute Map.has_key?(state(c), "document_maintenance")
    {request, _, _} = open(c)
    assert {:ok, _} = close(c, request)
    current = state(c)
    assert {:ok, decoded} = Encoding.decode(Jason.decode!(Encoding.encode(current)))
    assert decoded === current

    checkpoint = %{
      "id" => Usage.id(),
      "generation" => current["generation"],
      "floor" => current["floor"],
      "floor_anchor" => current["floor_anchor"],
      "floor_lineage_sha256" => JSON.digest([current["floor_lineage"]]),
      "records" => current["records"]
    }

    with_checkpoint = Map.put(current, "checkpoint", checkpoint)

    assert {:ok, rolled, %{}, %{}} =
             Migration.prepare(
               with_checkpoint,
               %{"op" => "rollback", "checkpoint_id" => checkpoint["id"]},
               Usage.id()
             )

    assert rolled["document_maintenance"] === current["document_maintenance"]
    assert rolled["floor"] === current["floor"]
    assert {:ok, wire, blocks} = Blocks.encode(with_checkpoint)

    assert {:ok, ^with_checkpoint, _} =
             Blocks.decode(Jason.decode!(wire), fn hash, _ -> Map.fetch(blocks, hash) end)
  end

  test "native notes writes ignore active and stale document admissions and retain their normal codec",
       c do
    notes = %{c | ns: JSON.sha256("independent notes project")}
    first_id = Usage.id()
    second_id = Usage.id()
    first_request = commit(0, "notes.active")
    second_request = commit(1, "notes.stale")

    {first, second} =
      Collection.with_document_admission(c.root, c.ns, c.owner, fn _ ->
        {opening, _, _} = open(c)

        first =
          Collection.with_document_admission(c.root, c.ns, c.owner, fn _ ->
            assert {:ok, receipt} =
                     Collection.execute(notes.root, notes.ns, first_request, first_id)

            receipt
          end)

        pointer_path = Path.join([notes.root, notes.ns, "root.json"])
        before_close = File.read!(pointer_path)
        assert {:ok, _} = close(c, opening)
        assert File.read!(pointer_path) === before_close

        assert {:ok, second} =
                 Collection.execute(notes.root, notes.ns, second_request, second_id)

        {first, second}
      end)

    expected = %{
      "version" => 3,
      "project" => notes.ns,
      "generation" => 2,
      "floor" => 0,
      "floor_anchor" => nil,
      "floor_lineage" => [],
      "records" =>
        Map.new([{"notes.active", first_id, 1}, {"notes.stale", second_id, 2}], fn {key, id,
                                                                                    revision} ->
          {key,
           %{
             "key" => key,
             "revision" => revision,
             "sha256" => JSON.sha256("{}"),
             "bytes" => 2,
             "operation_id" => id
           }}
        end),
      "operations" => %{first_id => first, second_id => second},
      "imported_operations" => %{},
      "migration" => nil,
      "checkpoint" => nil
    }

    assert first === %{
             "generation" => 1,
             "floor" => 0,
             "request_sha256" => JSON.digest([first_request])
           }

    assert second === %{
             "generation" => 2,
             "floor" => 0,
             "request_sha256" => JSON.digest([second_request])
           }

    assert state(notes) === expected
    refute Map.has_key?(state(notes), "document_maintenance")
    assert {:ok, wire, blocks} = Blocks.encode(expected)
    pointer = File.read!(Path.join([notes.root, notes.ns, "root.json"])) |> Jason.decode!()
    refute Map.has_key?(pointer, "storage_profile")
    assert pointer["manifest"] === JSON.sha256(wire)

    for {hash, bytes} <- Map.put(blocks, pointer["manifest"], wire) do
      assert File.read!(Path.join([notes.root, notes.ns, "manifests", hash <> ".json"])) === bytes
    end
  end
end
