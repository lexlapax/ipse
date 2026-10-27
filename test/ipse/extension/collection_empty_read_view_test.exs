defmodule Ipse.Extension.CollectionEmptyReadViewTest do
  use ExUnit.Case, async: false
  alias Ipse.Extension.Collection, as: C
  alias Ipse.Extension.Collection.ReadView
  alias Ipse.JSON

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-empty-view-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    owner = self()

    on_exit(fn ->
      case Registry.lookup(Ipse.Registry, {ReadView, owner}) do
        [{server, _}] -> await_dead(server)
        [] -> :ok
      end

      File.rm_rf!(parent)
    end)

    %{parent: parent, root: Path.join(parent, "collections"), project: JSON.sha256("empty")}
  end

  test "an absent root is rechecked on every read and cannot survive first publication", c do
    assert {:ok, view} = C.open_view(c.root, c.project)
    assert {:ok, first} = get(view)
    assert first["version"] === 2
    assert first["records"] === [nil]
    assert first["witness"]["root_state"] === "absent"
    refute File.exists?(pointer(c))
    assert {:ok, %{"keys" => [], "records" => [], "next" => nil}} = scan(view)
    refute File.exists?(pointer(c))
    assert {:ok, _} = publish(c)
    assert {:error, :collection_view_stale} = get(view)
    await_dead(view.server)
    assert {:error, :collection_view_unavailable} = get(view)
    assert {:ok, fresh} = C.open_view(c.root, c.project)
    assert {:ok, result} = get(fresh)
    assert result["records"] |> hd() |> Map.fetch!("value") == %{"text" => "first"}
    assert result["witness"]["root_state"] === "present"
    assert JSON.sha256?(result["witness"]["manifest_sha256"])
    assert :ok = C.close_view(fresh)
  end

  test "a previously materialized root becoming absent is stale rather than an empty result", c do
    assert {:ok, _} = publish(c)
    assert {:ok, view} = C.open_view(c.root, c.project)
    original = File.read!(pointer(c))
    File.rm!(pointer(c))
    assert {:error, :collection_view_stale} = get(view)
    await_dead(view.server)
    File.write!(pointer(c), original)
    File.chmod!(pointer(c), 0o600)
    assert {:ok, fresh} = C.open_view(c.root, c.project)
    assert {:ok, %{"records" => [%{"value" => %{"text" => "first"}}]}} = get(fresh)
    assert :ok = C.close_view(fresh)
  end

  test "unsafe or malformed selected roots refuse opening without following or rewriting them",
       c do
    assert {:ok, seed} = C.open_view(c.root, c.project)
    assert :ok = C.close_view(seed)
    outside = Path.join(c.parent, "outside.json")
    File.write!(outside, "secret fixture")
    File.chmod!(outside, 0o600)

    for kind <- [:symlink, :hardlink, :directory, :mode, :malformed, :fifo] do
      case kind do
        :symlink -> File.ln_s!(outside, pointer(c))
        :hardlink -> File.ln!(outside, pointer(c))
        :directory -> File.mkdir!(pointer(c))
        :mode -> File.write!(pointer(c), "{}")
        :malformed -> File.write!(pointer(c), "not JSON")
        :fifo -> Ipse.Test.FileEffectProbe.fifo!(pointer(c))
      end

      if kind in [:mode, :malformed],
        do: File.chmod!(pointer(c), if(kind == :mode, do: 0o640, else: 0o600))

      before = retained_object(pointer(c))
      assert {:error, :collection_unavailable} = C.open_view(c.root, c.project)
      assert retained_object(pointer(c)) == before
      assert File.read!(outside) == "secret fixture"
      assert Registry.lookup(Ipse.Registry, {ReadView, self()}) == []
      if kind == :directory, do: File.rmdir!(pointer(c)), else: File.rm!(pointer(c))
    end
  end

  test "a newly appearing unsafe root cannot be interpreted as continued absence", c do
    for kind <- [:symlink, :directory, :malformed] do
      assert {:ok, view} = C.open_view(c.root, c.project)

      case kind do
        :symlink ->
          File.ln_s!(Path.join(c.parent, "missing"), pointer(c))

        :directory ->
          File.mkdir!(pointer(c))

        :malformed ->
          File.write!(pointer(c), "{}")
          File.chmod!(pointer(c), 0o600)
      end

      refute match?({:ok, _}, get(view))
      await_dead(view.server)
      if kind == :directory, do: File.rmdir!(pointer(c)), else: File.rm!(pointer(c))
    end
  end

  test "closed absent-cache shape admits no fabricated hash, record, floor or old version", c do
    assert {:ok, view} = C.open_view(c.root, c.project)
    cache = :sys.get_state(view.server).cache
    assert :ok = C.close_view(view)

    for mutate <- [
          &Map.put(&1, "root_bytes", "{}"),
          &Map.put(&1, "root_sha256", JSON.sha256("{}")),
          &Map.put(&1, "manifest_sha256", JSON.sha256("manifest")),
          &Map.put(&1, "root_state", "present"),
          &Map.put(&1, "version", 1),
          &put_in(&1, ["summary", "generation"], 1),
          &put_in(&1, ["summary", "floor"], 1),
          &put_in(&1, ["summary", "floor_anchor"], Ipse.Usage.id()),
          &put_in(&1, ["records", "a"], %{"value" => %{}})
        ] do
      assert {:ok, handle} = ReadView.begin()
      assert {:error, :collection_view_capacity} = ReadView.install(handle, mutate.(cache))
      await_dead(handle.server)
    end
  end

  test "actual native owner loss withholds an otherwise valid absent result", c do
    assert {:ok, view} = C.open_view(c.root, c.project)
    handler = "empty-view-native-loss-" <> Ipse.Usage.id()

    assert :ok =
             :telemetry.attach(
               handler,
               [:ipse, :extension, :collection, :view_read],
               fn _, _, _, _ ->
                 cap = Process.get({C, :lock_held})
                 Port.close(cap.port)
               end,
               nil
             )

    on_exit(fn -> :telemetry.detach(handler) end)
    assert {:unknown, :collection_lock_lost} = get(view)
    await_dead(view.server)
    :telemetry.detach(handler)
    assert {:ok, fresh} = C.open_view(c.root, c.project)
    assert {:ok, %{"records" => [nil]}} = get(fresh)
    assert :ok = C.close_view(fresh)
    refute File.exists?(pointer(c))
  end

  test "a complete imported floor can exceed local generation without becoming absence", c do
    source = Path.join(c.parent, "source")

    for n <- 1..20 do
      assert {:ok, _} =
               C.execute(
                 source,
                 c.project,
                 %{
                   "op" => "commit",
                   "expected_generation" => n - 1,
                   "advance_floor" => true,
                   "changes" => [
                     %{
                       "key" => "a",
                       "expected_revision" => n - 1,
                       "value" => %{"text" => "source-#{n}"}
                     }
                   ]
                 },
                 Ipse.Usage.id()
               )
    end

    assert {:ok, page} =
             C.execute(
               source,
               c.project,
               %{"op" => "export", "generation" => 20, "after" => nil, "limit" => 1},
               Ipse.Usage.id()
             )

    assert {:ok, operations} =
             C.execute(
               source,
               c.project,
               %{"op" => "export.operations", "generation" => 20, "after" => nil, "limit" => 128},
               Ipse.Usage.id()
             )

    migration = Ipse.Usage.id()

    assert {:ok, %{"generation" => 1}} =
             C.execute(
               c.root,
               c.project,
               %{
                 "op" => "import.open",
                 "expected_generation" => 0,
                 "descriptor" => page["descriptor"]
               },
               migration
             )

    assert {:ok, %{"generation" => 2}} =
             C.execute(
               c.root,
               c.project,
               %{
                 "op" => "import.page",
                 "expected_generation" => 1,
                 "migration_id" => migration,
                 "after" => nil,
                 "records" => Enum.map(page["records"], &Map.take(&1, ~w(key value)))
               },
               Ipse.Usage.id()
             )

    assert {:ok, %{"generation" => 3}} =
             C.execute(
               c.root,
               c.project,
               %{
                 "op" => "import.operations",
                 "expected_generation" => 2,
                 "migration_id" => migration,
                 "after" => nil,
                 "operations" => operations["operations"]
               },
               Ipse.Usage.id()
             )

    assert {:ok, %{"generation" => 4, "floor" => 20}} =
             C.execute(
               c.root,
               c.project,
               %{
                 "op" => "import.commit",
                 "expected_generation" => 3,
                 "migration_id" => migration
               },
               Ipse.Usage.id()
             )

    assert {:ok, view} = C.open_view(c.root, c.project)
    assert {:ok, result} = get(view)
    assert result["summary"]["floor"] == 20
    assert result["summary"]["generation"] == 4
    assert result["witness"]["root_state"] == "present"
    assert [%{"value" => %{"text" => "source-20"}}] = result["records"]
    assert :ok = C.close_view(view)
  end

  defp pointer(c), do: Path.join([c.root, c.project, "root.json"])

  defp retained_object(path),
    do: File.lstat!(path) |> Map.take([:type, :mode, :uid, :inode, :links, :size, :mtime, :ctime])

  defp get(view), do: C.view_read(view, %{"op" => "get_many", "keys" => ["a"]})
  defp scan(view), do: C.view_read(view, %{"op" => "scan", "after" => nil, "limit" => 8})

  defp publish(c),
    do:
      C.execute(
        c.root,
        c.project,
        %{
          "op" => "commit",
          "expected_generation" => 0,
          "advance_floor" => true,
          "changes" => [
            %{"key" => "a", "expected_revision" => 0, "value" => %{"text" => "first"}}
          ]
        },
        Ipse.Usage.id()
      )

  defp await_dead(pid) do
    monitor = Process.monitor(pid)

    receive do
      {:DOWN, ^monitor, :process, ^pid, _} -> :ok
    after
      5_000 -> flunk("cache or owner did not terminate")
    end
  end
end
