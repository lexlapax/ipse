defmodule Ipse.Extension.CollectionNeighborsTest do
  use ExUnit.Case, async: false
  alias Ipse.Extension.Collection, as: C
  alias Ipse.{JSON, Session.Resources}

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-neighbors-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    owner = self()

    on_exit(fn ->
      case Registry.lookup(Ipse.Registry, {C.ReadView, owner}) do
        [{server, _}] -> await_dead(server)
        [] -> :ok
      end

      File.rm_rf!(parent)
    end)

    %{parent: parent, root: Path.join(parent, "collections"), project: JSON.sha256("neighbors")}
  end

  defp key(n), do: "p." <> String.pad_leading(String.downcase(Integer.to_string(n, 16)), 64, "0")

  defp request(n \\ 0),
    do: %{
      "version" => 1,
      "prefix" => "p.",
      "fence_bytes" => 32,
      "needle" => String.slice(key(n), 2..-1//1)
    }

  defp change(key, revision, value),
    do: %{"key" => key, "expected_revision" => revision, "value" => value}

  defp commit(c, generation, changes, floor \\ false),
    do:
      C.execute(
        c.root,
        c.project,
        %{
          "op" => "commit",
          "expected_generation" => generation,
          "advance_floor" => floor,
          "changes" => changes
        },
        Ipse.Usage.id()
      )

  defp seed(c) do
    assert {:ok, _} =
             commit(
               c,
               0,
               Enum.map([0, 10, 20, 30, 40], &change(key(&1), 0, %{"text" => "page #{&1}"}))
             )

    assert {:ok, view} = C.open_view(c.root, c.project)
    view
  end

  defp directory(c), do: Path.join(c.root, c.project)
  defp pointer(c), do: Path.join(directory(c), "root.json")
  defp get(view, key), do: C.view_read(view, %{"op" => "get_many", "keys" => [key]})

  defp await_dead(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    after
      5_000 -> flunk("resource remained alive")
    end
  end

  defp attach(event, callback) do
    id = "neighbors-" <> Ipse.Usage.id()
    assert :ok = :telemetry.attach(id, [:ipse, :extension, :collection, event], callback, nil)
    on_exit(fn -> :telemetry.detach(id) end)
    id
  end

  test "actual root witness surrounds exact refs without value reads or ledger mutation", c do
    view = seed(c)
    before = File.read!(pointer(c))
    parent = self()

    event =
      attach(:view_neighbors, fn _, measurements, _, _ ->
        send(parent, {:observed, measurements})
      end)

    assert {:ok, result} = C.view_neighbors(view, request(15))
    assert result["state"] == "initialized"
    assert result["directory"] == request(15)
    assert result["witness"]["root_sha256"] == JSON.sha256(before)
    assert result["witness"]["root"] == Jason.decode!(before)

    assert Enum.map(
             ~w(predecessor selected successor second_successor),
             &result["neighbors"][&1]["key"]
           ) == Enum.map([0, 10, 20, 30], &key/1)

    assert Enum.all?(
             Map.values(result["neighbors"]),
             &(Map.keys(&1) |> Enum.sort() ==
                 Enum.sort(~w(key revision sha256 bytes operation_id)))
           )

    assert_receive {:observed, %{refs: 4, value_reads: 0}}
    assert File.read!(pointer(c)) == before
    assert :sys.get_state(view.server).reads == 1
    assert :sys.get_state(view.server).observations == 4
    :telemetry.detach(event)
    assert :ok = C.close_view(view)
  end

  test "selected and unrelated broken object bytes are untouched until an actual value read", c do
    view = seed(c)
    records = :sys.get_state(view.server).cache["records"]

    for selected <- [key(10), key(40)] do
      path = Path.join([directory(c), "objects", records[selected]["sha256"] <> ".json"])
      File.write!(path, "{}")
    end

    assert {:ok, result} = C.view_neighbors(view, request(15))
    assert result["neighbors"]["selected"]["key"] == key(10)
    assert {:error, :collection_unavailable} = get(view, key(10))
    await_dead(view.server)
  end

  test "real absence has no fabricated root while materialized empty lacks a required sentinel",
       c do
    assert {:ok, view} = C.open_view(c.root, c.project)
    assert {:ok, result} = C.view_neighbors(view, request())
    assert result["state"] == "uninitialized"

    assert result["witness"] == %{
             "version" => 2,
             "root_state" => "absent",
             "root" => nil,
             "root_sha256" => nil,
             "manifest_sha256" => nil
           }

    assert Enum.all?(Map.values(result["neighbors"]), &is_nil/1)
    assert :sys.get_state(view.server).observations == 4
    refute File.exists?(pointer(c))
    assert :ok = C.close_view(view)
    assert {:ok, _} = commit(c, 0, [change("ordinary", 0, %{})])
    assert {:ok, _} = commit(c, 1, [change("ordinary", 1, nil)], true)
    assert {:ok, present} = C.open_view(c.root, c.project)
    assert {:error, :collection_view_corrupt} = C.view_neighbors(present, request())
    await_dead(present.server)
    assert File.exists?(pointer(c))
  end

  test "missing and malformed matching fences refuse even outside the selected window", c do
    for {poison, generation} <- Enum.with_index([key(1), "p.BAD"], 0) do
      if generation == 0 do
        assert {:ok, _} = commit(c, 0, [change(poison, 0, %{})])
      else
        assert {:ok, _} = commit(c, 1, [change(key(0), 0, %{}), change(poison, 0, %{})])
      end

      assert {:ok, view} = C.open_view(c.root, c.project)
      assert {:error, :collection_view_corrupt} = C.view_neighbors(view, request())
      await_dead(view.server)
    end
  end

  test "invalid descriptors refuse before borrowing or native IO", c do
    view = seed(c)

    for r <- [
          Map.put(request(), "version", 1.0),
          Map.put(request(), "needle", "bad"),
          Map.put(request(), "extra", true)
        ] do
      assert {:error, :invalid_collection_view_request} = C.view_neighbors(view, r)
    end

    assert :sys.get_state(view.server).reads == 0
    assert :sys.get_state(view.server).observations == 0
    assert :ok = C.close_view(view)
  end

  test "mixed observation costs cannot evade the512-unit cap by batching or short directories",
       c do
    view = seed(c)
    :sys.replace_state(view.server, &%{&1 | observations: 500})

    assert {:ok, _} =
             C.view_read(view, %{"op" => "get_many", "keys" => Enum.map([0, 10, 20, 30], &key/1)})

    assert {:ok, _} = C.view_read(view, %{"op" => "scan", "after" => key(40), "limit" => 4})
    assert {:ok, _} = C.view_neighbors(view, request(99))
    assert :sys.get_state(view.server).observations == 512
    assert :sys.get_state(view.server).reads == 3
    assert {:error, :collection_view_capacity} = get(view, key(0))
    await_dead(view.server)
  end

  test "remaining units are checked before native borrowing and no count resets on copied handles",
       c do
    view = seed(c)
    parent = self()
    id = attach(:view_neighbors, fn _, _, _, _ -> send(parent, :native_started) end)
    :sys.replace_state(view.server, &%{&1 | observations: 509})

    assert {:error, :collection_view_capacity} =
             C.view_neighbors(%{view | ref: view.ref}, request())

    refute_receive :native_started
    await_dead(view.server)
    :telemetry.detach(id)
  end

  test "complete directory key and matching ref seals detect private cache tampering", c do
    for mutate <- [
          fn s -> %{s | index: :gb_trees.delete(key(20), s.index)} end,
          fn s -> update_in(s, [:cache, "records"], &Map.delete(&1, key(40))) end,
          fn s -> put_in(s, [:cache, "records", key(40), "operation_id"], Ipse.Usage.id()) end
        ] do
      view =
        if File.exists?(pointer(c)), do: elem(C.open_view(c.root, c.project), 1), else: seed(c)

      :sys.replace_state(view.server, mutate)
      assert {:error, :collection_view_corrupt} = C.view_neighbors(view, request())
      await_dead(view.server)
    end
  end

  test "changed or newly materialized root invalidates every cached ref", c do
    assert {:ok, empty} = C.open_view(c.root, c.project)
    assert {:ok, _} = commit(c, 0, [change(key(0), 0, %{})])
    assert {:error, :collection_view_stale} = C.view_neighbors(empty, request())
    await_dead(empty.server)
    assert {:ok, view} = C.open_view(c.root, c.project)
    assert {:ok, _} = commit(c, 1, [change(key(10), 0, %{})])
    assert {:error, :collection_view_stale} = C.view_neighbors(view, request())
    await_dead(view.server)
  end

  test "actual native owner loss withholds metadata and permits explicit later reacquisition",
       c do
    view = seed(c)

    id =
      attach(:view_neighbors, fn _, _, _, _ -> Port.close(Process.get({C, :lock_held}).port) end)

    assert {:unknown, :collection_lock_lost} = C.view_neighbors(view, request())
    await_dead(view.server)
    :telemetry.detach(id)
    assert {:ok, fresh} = C.open_view(c.root, c.project)
    assert {:ok, _} = C.view_neighbors(fresh, request())
    assert :ok = C.close_view(fresh)
  end

  test "expiry after native root check discards refs despite otherwise successful IO", c do
    view = seed(c)

    id =
      attach(:view_neighbors, fn _, _, _, _ ->
        monitor = Process.monitor(view.server)
        send(view.server, :expire)

        receive do
          {:DOWN, ^monitor, :process, _, _} -> :ok
        after
          2_000 -> raise "expiry missing"
        end
      end)

    assert {:error, :collection_view_unavailable} = C.view_neighbors(view, request())
    await_dead(view.server)
    :telemetry.detach(id)
  end

  test "original owner death fences native ref selection while paused borrower remains alive",
       c do
    parent = self()

    id =
      attach(:view_neighbors, fn _, _, _, _ ->
        cap = Process.get({C, :lock_held})
        send(parent, {:paused, self(), cap.controller})

        receive do
          :continue -> :ok
        after
          5_000 -> raise "release missing"
        end
      end)

    owner =
      spawn(fn ->
        view = seed(c)
        send(parent, {:owned, view})

        Resources.file_effect(fn ->
          send(parent, {:completed, C.view_neighbors(view, request())})
        end)
      end)

    assert_receive {:owned, view}, 5_000
    assert_receive {:paused, borrower, controller}, 5_000
    Process.exit(owner, :kill)
    await_dead(view.server)
    await_dead(controller)
    assert Process.alive?(borrower)

    assert :ok =
             Resources.file_effect(fn ->
               assert {:ok, cap} =
                        Ipse.Runner.Transaction.acquire(Path.join(directory(c), ".lock"),
                          cwd: c.parent
                        )

               Ipse.Runner.Transaction.release(cap)
             end)

    send(borrower, :continue)
    assert_receive {:completed, result}, 5_000
    refute match?({:ok, _}, result)
    :telemetry.detach(id)
  end
end
