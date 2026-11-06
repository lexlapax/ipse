defmodule Ipse.Extension.Collection.DocumentInventoryTest do
  use ExUnit.Case, async: false
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.{Collection, CollectionStore}
  alias Ipse.Extension.Collection.{Directory, DocumentStage, Profile}

  @tag :document_inventory_pure
  test "closed inventory pages retain complete physical descriptors and deterministic bounded cursors" do
    keys = for n <- 0..39, do: String.pad_leading(Integer.to_string(n), 96, "a")

    records =
      Map.new(keys, fn key ->
        {key,
         %{
           "key" => key,
           "revision" => 9_007_199_254_740_991,
           "sha256" => JSON.sha256(key),
           "bytes" => 65_536
         }}
      end)

    records = Map.put(records, "host.stage.0.header", %{"private" => true})

    summary = %{
      "version" => 3,
      "project" => JSON.sha256("inventory"),
      "generation" => 9_007_199_254_740_991,
      "floor" => 9_007_199_254_740_991,
      "floor_anchor" => Usage.id()
    }

    walk = fn walk, after_key, seen ->
      request = %{
        "op" => "value.index",
        "generation" => summary["generation"],
        "after" => after_key,
        "limit" => 16
      }

      assert DocumentStage.request?(request)
      refute DocumentStage.mutating?(request)
      assert {:ok, page} = Directory.document_index(records, summary, request)
      assert page["count"] == 40 and page["coverage"] == "public_document_records"
      assert byte_size(Jason.encode!(page)) <= 4096

      assert CollectionStore.valid_outcome?(
               %{"op" => "collection.store", "scope" => "project", "request" => request},
               "ok",
               %{
                 "version" => 1,
                 "operation_id" => String.duplicate("a", 32),
                 "request_sha256" =>
                   JSON.digest([
                     %{"op" => "collection.store", "scope" => "project", "request" => request}
                   ]),
                 "result" => page
               },
               String.duplicate("a", 32)
             )

      next = seen ++ Enum.map(page["records"], & &1["key"])
      if page["next"], do: walk.(walk, page["next"], next), else: next
    end

    assert walk.(walk, nil, []) == Enum.sort(keys)

    request = %{"op" => "value.index", "generation" => 0, "after" => nil, "limit" => 16}

    for invalid <- [
          Map.put(request, "generation", 0.0),
          Map.put(request, "limit", 17),
          Map.put(request, "limit", 1.0),
          Map.put(request, "after", "host.stage.0.header"),
          Map.put(request, "after", "host.other"),
          Map.put(request, "after", "../foreign"),
          Map.put(request, "namespace", JSON.sha256("foreign")),
          Map.put(request, "profile", "notes-v1")
        ] do
      refute DocumentStage.request?(invalid)
    end
  end

  @tag :document_inventory_native
  test "native inventory uses only checked metadata, hides private keys and leaves storage unchanged" do
    dir = Path.join(System.tmp_dir!(), "ipse-document-inventory-" <> Usage.id())
    File.mkdir!(dir)
    File.chmod!(dir, 0o700)
    on_exit(fn -> File.rm_rf!(dir) end)
    root = Path.join(dir, "collections")
    namespace = CollectionStore.namespace(JSON.sha256("project"))
    keys = for n <- 0..39, do: "data." <> String.pad_leading(Integer.to_string(n), 91, "a")

    private =
      ~w(host.stage.0.header host.stage.0.ready host.stage.0.part.0 host.other host.validity.secret)

    body = "{\"text\":\"BODY_MUST_NOT_BE_READ\"}"

    packed = %{
      "version" => 1,
      "kind" => "document_value",
      "sha256" => JSON.sha256(body),
      "byte_count" => byte_size(body),
      "parts" => [body]
    }

    changes =
      Enum.map(keys ++ private, &%{"key" => &1, "expected_revision" => 0, "value" => packed})

    assert {:ok, _} =
             Collection.execute_profile(
               root,
               namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" => changes
               },
               Usage.id(),
               Profile.documents()
             )

    physical = Ipse.Extension.Collection.Migration.encode(packed)
    objects = Path.wildcard(Path.join([root, namespace, "objects", "*.json"]))
    assert objects != []
    Enum.each(objects, &File.write!(&1, "CORRUPTED_VALUE_OBJECT"))

    files = fn ->
      Path.wildcard(Path.join([root, namespace, "**", "*"]), match_dot: true)
      |> Enum.filter(&File.regular?/1)
      |> Map.new(&{&1, File.read!(&1)})
    end

    before = files.()

    owner = %{
      "project_id" => JSON.sha256("project"),
      "session_id" => Usage.id(),
      "identity_sha256" => JSON.sha256("identity"),
      "invocation_id" => Usage.id()
    }

    observed = self()
    handler = "document-inventory-" <> Usage.id()

    :ok =
      :telemetry.attach(
        handler,
        [:ipse, :extension, :collection, :document_index],
        fn _, measurements, _, _ -> send(observed, {:index, measurements}) end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    walk = fn walk, after_key, seen ->
      request = %{"op" => "value.index", "generation" => 1, "after" => after_key, "limit" => 16}
      assert {:ok, page} = DocumentStage.execute(root, namespace, request, Usage.id(), owner)
      assert page["count"] == 40

      assert Enum.all?(
               page["records"],
               &(&1["record_sha256"] == JSON.sha256(physical) and
                   &1["record_bytes"] == byte_size(physical))
             )

      assert_receive {:index, %{value_reads: 0}}
      next = seen ++ Enum.map(page["records"], & &1["key"])
      if page["next"], do: walk.(walk, page["next"], next), else: next
    end

    assert walk.(walk, nil, []) == Enum.sort(keys)

    assert {:conflict, _} =
             Collection.document_index(root, namespace, %{
               "op" => "value.index",
               "generation" => 0,
               "after" => nil,
               "limit" => 16
             })

    assert {:error, :document_store_refused} =
             DocumentStage.execute(
               root,
               namespace,
               %{
                 "op" => "value.index",
                 "generation" => 1,
                 "after" => "host.stage.0.header",
                 "limit" => 16
               },
               Usage.id(),
               owner
             )

    assert {:ok, empty} =
             Collection.document_index(root, JSON.sha256("empty"), %{
               "op" => "value.index",
               "generation" => 0,
               "after" => nil,
               "limit" => 16
             })

    assert empty["records"] == [] and empty["count"] == 0 and empty["next"] == nil

    notes = JSON.sha256("notes profile")

    assert {:ok, _} =
             Collection.execute(
               root,
               notes,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" => [
                   %{
                     "key" => "note.private",
                     "expected_revision" => 0,
                     "value" => %{"text" => "NOT_DOCUMENTS"}
                   }
                 ]
               },
               Usage.id()
             )

    assert {:error, _} =
             Collection.document_index(root, notes, %{
               "op" => "value.index",
               "generation" => 1,
               "after" => nil,
               "limit" => 16
             })

    assert files.() == before
  end
end
