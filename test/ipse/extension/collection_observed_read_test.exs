defmodule Ipse.Extension.CollectionObservedReadTest do
  use ExUnit.Case, async: false

  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.Collection
  alias Ipse.Extension.Collection.{ObservedRead, ReadView}

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-observed-read-" <> Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    owner = self()

    on_exit(fn ->
      case Registry.lookup(Ipse.Registry, {ReadView, owner}) do
        [{server, _}] ->
          monitor = Process.monitor(server)

          receive do
            {:DOWN, ^monitor, :process, ^server, _} -> :ok
          after
            5_000 -> flunk("read view did not terminate")
          end

        [] ->
          :ok
      end

      File.rm_rf!(parent)
    end)

    %{root: Path.join(parent, "collections"), namespace: JSON.sha256("observed")}
  end

  defp execute(c, request), do: Collection.execute(c.root, c.namespace, request, Usage.id())

  defp commit(c, generation, key, revision, value) do
    execute(c, %{
      "op" => "commit",
      "expected_generation" => generation,
      "advance_floor" => revision != 0,
      "changes" => [%{"key" => key, "expected_revision" => revision, "value" => value}]
    })
  end

  test "get and snapshot return generic results and an exact root witness", c do
    assert {:ok, _} = commit(c, 0, "note.one", 0, %{"text" => "synthetic"})

    for request <- [
          %{"op" => "snapshot"},
          %{"op" => "get", "key" => "note.one"},
          %{"op" => "get", "key" => "missing"}
        ] do
      assert {:ok, expected} = execute(c, request)
      assert {:ok, observation} = ObservedRead.read(c.root, c.namespace, request)
      assert observation["value"] === expected
      assert observation["request_sha256"] == JSON.digest([request])
      assert observation["result_sha256"] == JSON.digest([expected])
      pointer = File.read!(Path.join([c.root, c.namespace, "root.json"]))
      assert observation["witness"]["root"] == Jason.decode!(pointer)
      assert observation["witness"]["root_sha256"] == JSON.sha256(pointer)
      assert observation["witness"]["manifest_sha256"] == Jason.decode!(pointer)["manifest"]
      assert [] == Registry.lookup(Ipse.Registry, {ReadView, self()})
    end
  end

  test "absent and materialized empty roots produce distinct observations", c do
    request = %{"op" => "get", "key" => "missing"}
    assert {:ok, absent} = ObservedRead.read(c.root, c.namespace, request)
    assert absent["value"]["record"] == nil
    assert absent["witness"]["root_state"] == "absent"
    assert absent["witness"]["root_sha256"] == nil
    assert {:ok, _} = commit(c, 0, "note.one", 0, %{})
    assert {:ok, _} = commit(c, 1, "note.one", 1, nil)
    assert {:ok, present} = ObservedRead.read(c.root, c.namespace, request)
    assert present["value"]["record"] == nil
    assert present["witness"]["root_state"] == "present"
    assert JSON.sha256?(present["witness"]["root_sha256"])
    assert present["value"]["generation"] == 2
  end

  test "a later root produces a distinct observation even when a record is unchanged", c do
    assert {:ok, _} = commit(c, 0, "note.one", 0, %{"text" => "synthetic"})
    request = %{"op" => "get", "key" => "note.one"}
    assert {:ok, first} = ObservedRead.read(c.root, c.namespace, request)
    assert {:ok, _} = commit(c, 1, "note.two", 0, %{"text" => "other"})
    assert {:ok, second} = ObservedRead.read(c.root, c.namespace, request)
    assert first["value"]["record"] == second["value"]["record"]
    assert first["witness"]["root_sha256"] != second["witness"]["root_sha256"]
    assert first["result_sha256"] != second["result_sha256"]
  end

  test "legacy v3 roots refuse observation while generic get remains available", c do
    assert {:ok, _} = commit(c, 0, "note.one", 0, %{"text" => "synthetic"})
    directory = Path.join(c.root, c.namespace)
    pointer_path = Path.join(directory, "root.json")
    pointer = Jason.decode!(File.read!(pointer_path))
    manifest = Path.join([directory, "manifests", pointer["manifest"] <> ".json"])

    assert {:ok, state, _} =
             Collection.Blocks.decode(Jason.decode!(File.read!(manifest)), fn hash, _ ->
               File.read(Path.join([directory, "manifests", hash <> ".json"]))
             end)

    bytes = Collection.Encoding.encode(state)
    hash = JSON.sha256(bytes)
    legacy = Path.join([directory, "manifests", hash <> ".json"])
    File.write!(legacy, bytes)
    File.chmod!(legacy, 0o600)

    File.write!(
      pointer_path,
      Jason.encode!(pointer |> Map.put("version", 3) |> Map.put("manifest", hash))
    )

    request = %{"op" => "get", "key" => "note.one"}
    assert {:ok, %{"record" => %{"value" => %{"text" => "synthetic"}}}} = execute(c, request)

    assert {:error, :collection_observation_refused} =
             ObservedRead.read(c.root, c.namespace, request)
  end

  test "snapshot refuses an unreadable probe value even when generic snapshot succeeds", c do
    assert {:ok, _} = commit(c, 0, "ipse.observation", 0, %{"text" => "synthetic"})

    assert {:ok, %{"record" => record}} =
             execute(c, %{"op" => "get", "key" => "ipse.observation"})

    object = Path.join([c.root, c.namespace, "objects", record["sha256"] <> ".json"])
    File.write!(object, "corrupt")
    assert {:ok, %{"generation" => 1}} = execute(c, %{"op" => "snapshot"})

    assert {:error, :collection_observation_refused} =
             ObservedRead.read(c.root, c.namespace, %{"op" => "snapshot"})
  end

  test "a stored reserved sidecar is never returned by an observation", c do
    request = %{
      "op" => "commit",
      "expected_generation" => 0,
      "advance_floor" => true,
      "changes" => [%{"key" => "note.one", "expected_revision" => 0, "value" => %{}}]
    }

    normalized =
      Map.update!(request, "changes", fn changes ->
        changes ++
          [
            %{
              "key" => "host.validity.a",
              "expected_revision" => 0,
              "value" => %{"secret" => true}
            }
          ]
      end)

    assert {:ok, _} =
             Collection.execute_managed(
               c.root,
               c.namespace,
               request,
               Usage.id(),
               JSON.sha256("recipe"),
               fn _, _ -> {:ok, normalized, %{"version" => 1}} end
             )

    assert {:error, :collection_observation_refused} =
             ObservedRead.read(c.root, c.namespace, %{"op" => "get", "key" => "host.validity.a"})

    assert {:ok, result} = ObservedRead.read(c.root, c.namespace, %{"op" => "snapshot"})
    refute Jason.encode!(result) =~ "secret"

    assert {:ok, %{"record" => sidecar}} =
             execute(c, %{"op" => "get", "key" => "host.validity.a"})

    File.write!(
      Path.join([c.root, c.namespace, "objects", sidecar["sha256"] <> ".json"]),
      "corrupt"
    )

    scan = %{"op" => "scan", "after" => nil, "generation" => 1, "limit" => 4}
    assert {:ok, expected} = Collection.scan_visible(c.root, c.namespace, scan, Usage.id())
    assert {:ok, observed} = ObservedRead.read(c.root, c.namespace, scan)
    assert observed["value"] === expected
    refute Jason.encode!(observed) =~ "secret"
  end

  test "private keys and operations without an exact public translation fail closed", c do
    for request <- [
          %{"op" => "get", "key" => "host.validity.format"},
          %{"op" => "get", "key" => "host.validity.a"},
          %{"op" => "get", "key" => "missing", "extra" => true},
          %{"op" => "snapshot", "extra" => true},
          %{"op" => "status"},
          %{"op" => "inspect", "operation_id" => Usage.id()},
          %{"op" => "scan", "after" => nil, "generation" => 0, "limit" => 5},
          %{"op" => "scan", "after" => "host.validity.a", "generation" => 0, "limit" => 4},
          %{"op" => "commit"}
        ] do
      assert {:error, :collection_observation_refused} =
               ObservedRead.read(c.root, c.namespace, request)
    end

    refute File.exists?(c.root)
  end

  test "visible scan matches pagination at the witnessed generation and refuses stale generations",
       c do
    assert {:ok, _} = commit(c, 0, "note.a", 0, %{"n" => 1})
    assert {:ok, _} = commit(c, 1, "note.b", 0, %{"n" => 2})
    assert {:ok, _} = commit(c, 2, "note.c", 0, %{"n" => 3})

    for cursor <- [nil, "note.a", "note.b", "note.c"] do
      request = %{"op" => "scan", "after" => cursor, "generation" => 3, "limit" => 1}
      assert {:ok, expected} = Collection.scan_visible(c.root, c.namespace, request, Usage.id())
      assert {:ok, observed} = ObservedRead.read(c.root, c.namespace, request)
      assert observed["value"] === expected
      assert observed["request_sha256"] == JSON.digest([request])
      assert observed["result_sha256"] == JSON.digest([expected])
    end

    stale = %{"op" => "scan", "after" => nil, "generation" => 2, "limit" => 4}
    assert {:conflict, _} = Collection.scan_visible(c.root, c.namespace, stale, Usage.id())

    assert {:error, :collection_observation_refused} =
             ObservedRead.read(c.root, c.namespace, stale)

    assert {:ok, %{"record" => record}} = execute(c, %{"op" => "get", "key" => "note.a"})

    File.write!(
      Path.join([c.root, c.namespace, "objects", record["sha256"] <> ".json"]),
      "corrupt"
    )

    assert {:ok, view} = Collection.open_view(c.root, c.namespace)

    assert {:error, :collection_view_stale} =
             Collection.view_read(view, %{
               "op" => "visible_scan",
               "after" => nil,
               "generation" => 2,
               "limit" => 4
             })

    assert {:error, _} = Collection.close_view(view)
  end

  test "visible scan refuses a changed root between pages", c do
    assert {:ok, _} = commit(c, 0, "note.a", 0, %{"n" => 1})
    assert {:ok, _} = commit(c, 1, "note.b", 0, %{"n" => 2})
    first = %{"op" => "scan", "after" => nil, "generation" => 2, "limit" => 1}
    assert {:ok, observed} = ObservedRead.read(c.root, c.namespace, first)
    assert observed["value"]["next"] == "note.a"
    assert {:ok, _} = commit(c, 2, "note.c", 0, %{"n" => 3})

    assert {:error, :collection_observation_refused} =
             ObservedRead.read(c.root, c.namespace, %{first | "after" => "note.a"})
  end

  test "lost native owner while scanning cannot publish an observation", c do
    assert {:ok, _} = commit(c, 0, "note.a", 0, %{"n" => 1})
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:ipse, :extension, :collection, :view_read],
        &__MODULE__.fence/4,
        self()
      )

    try do
      assert {:error, :collection_observation_refused} =
               ObservedRead.read(c.root, c.namespace, %{
                 "op" => "scan",
                 "after" => nil,
                 "generation" => 1,
                 "limit" => 4
               })

      assert_receive {:fenced, true}
    after
      :telemetry.detach(handler)
    end
  end

  test "a lost native view owner cannot publish an observation", c do
    assert {:ok, _} = commit(c, 0, "note.one", 0, %{"text" => "synthetic"})
    owner = self()
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:ipse, :extension, :collection, :view_read],
        &__MODULE__.fence/4,
        owner
      )

    try do
      assert {:error, :collection_observation_refused} =
               ObservedRead.read(c.root, c.namespace, %{"op" => "get", "key" => "note.one"})

      assert_receive {:fenced, true}
      assert [] == Registry.lookup(Ipse.Registry, {ReadView, self()})
    after
      :telemetry.detach(handler)
    end
  end

  def fence(_, _, _, owner) do
    case Process.get({Collection, :lock_held}) do
      %{port: port} -> send(owner, {:fenced, Port.close(port)})
      _ -> send(owner, {:fenced, false})
    end
  end
end
