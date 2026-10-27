defmodule Ipse.Extension.CollectionReadViewTest do
  use ExUnit.Case, async: false
  alias Ipse.Extension.Collection, as: C
  alias Ipse.Extension.Collection.ReadView
  alias Ipse.{JSON, Session.Resources}

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-read-view-" <> Ipse.Usage.id())
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

    %{parent: parent, root: Path.join(parent, "collections"), project: JSON.sha256("view")}
  end

  defp change(key, revision, value),
    do: %{"key" => key, "expected_revision" => revision, "value" => value}

  defp commit(c, generation, changes, floor \\ false) do
    C.execute(
      c.root,
      c.project,
      %{
        "op" => "commit",
        "expected_generation" => generation,
        "changes" => changes,
        "advance_floor" => floor
      },
      Ipse.Usage.id()
    )
  end

  defp seed(c) do
    assert {:ok, _} =
             commit(c, 0, [
               change("a", 0, %{"text" => "alpha"}),
               change("b", 0, %{"text" => "beta"}),
               change("c", 0, %{"text" => "gamma"})
             ])

    assert {:ok, view} = C.open_view(c.root, c.project)
    view
  end

  defp get(view, keys), do: C.view_read(view, %{"op" => "get_many", "keys" => keys})
  defp pointer(c), do: Path.join([c.root, c.project, "root.json"])
  defp directory(c), do: Path.join(c.root, c.project)

  test "root-bound batches and cursor pages read in caller order without durable operations", c do
    view = seed(c)
    before = files(c)
    bytes = File.read!(pointer(c))
    assert {:ok, result} = get(view, ["b", "missing", "a"])
    assert result["keys"] == ["b", "missing", "a"]
    assert Enum.map(result["records"], &(&1 && &1["value"]["text"])) == ["beta", nil, "alpha"]
    assert result["witness"]["root"] == Jason.decode!(bytes)
    assert result["witness"]["root_sha256"] == JSON.sha256(bytes)
    assert result["witness"]["manifest_sha256"] == Jason.decode!(bytes)["manifest"]

    assert {:ok, %{"keys" => ["a", "b"], "next" => "b"}} =
             C.view_read(view, %{"op" => "scan", "after" => nil, "limit" => 2})

    assert {:ok, %{"keys" => ["c"], "next" => nil}} =
             C.view_read(view, %{"op" => "scan", "after" => "b", "limit" => 2})

    assert files(c) == before
    assert :sys.get_state(view.server).reads == 3
    assert :sys.get_state(view.server).observations == 7
    assert {:error, :collection_view_exists} = C.open_view(c.root, c.project)
    assert :ok = C.close_view(view)
    refute Process.alive?(view.server)
    assert {:ok, replacement} = C.open_view(c.root, c.project)
    assert :ok = C.close_view(replacement)
  end

  test "managed v5 views expose selected storage records without minting eligibility", c do
    request = %{
      "op" => "commit",
      "expected_generation" => 0,
      "advance_floor" => true,
      "changes" => [change("note.a", 0, %{"text" => "value"})]
    }

    normalized =
      Map.update!(request, "changes", &(&1 ++ [change("host.validity.a", 0, %{"anchor" => 0})]))

    assert {:ok, _} =
             C.execute_managed(
               c.root,
               c.project,
               request,
               Ipse.Usage.id(),
               JSON.sha256("recipe"),
               fn _, _ -> {:ok, normalized, %{"version" => 1}} end
             )

    assert {:ok, view} = C.open_view(c.root, c.project)
    assert {:ok, result} = get(view, ["note.a", "host.validity.a"])
    assert result["witness"]["root"]["version"] == 5
    assert Enum.map(result["records"], & &1["value"]) == [%{"text" => "value"}, %{"anchor" => 0}]
    refute Map.has_key?(result, "eligible")
    assert :ok = C.close_view(view)
  end

  test "an outer protected caller retains its stack while opening and reading a view", c do
    view = seed(c)
    assert :ok = C.close_view(view)
    owner = self()

    retained =
      Resources.file_effect(fn ->
        assert Resources.file_effect_owner() == owner

        assert {:ok, outer} =
                 Ipse.Runner.Transaction.acquire(Path.join(c.parent, ".lock"), cwd: c.parent)

        assert {:ok, inner} = C.open_view(c.root, c.project)
        assert inner.owner == owner
        assert {:ok, _} = get(inner, ["a"])
        assert :ok = Ipse.Runner.Transaction.check(outer)
        assert :ok = Ipse.Runner.Transaction.release(outer)
        inner
      end)

    assert {:ok, _} = get(retained, ["b"])
    assert :ok = C.close_view(retained)
  end

  test "unmaterialized and anchored materialized empty stores have distinct witnesses", c do
    assert {:ok, empty} = C.open_view(c.root, c.project)
    assert {:ok, absent} = get(empty, ["a"])

    assert absent["witness"] == %{
             "version" => 2,
             "root_state" => "absent",
             "root" => nil,
             "root_sha256" => nil,
             "manifest_sha256" => nil
           }

    assert absent["records"] == [nil]
    assert :ok = C.close_view(empty)
    refute File.exists?(pointer(c))
    assert {:ok, _} = commit(c, 0, [change("a", 0, %{})])
    assert {:ok, _} = commit(c, 1, [change("a", 1, nil)], true)
    assert {:ok, view} = C.open_view(c.root, c.project)
    assert {:ok, present} = get(view, ["a"])
    assert present["witness"]["root_state"] == "present"
    assert JSON.sha256?(present["witness"]["manifest_sha256"])

    assert {:ok, %{"records" => [nil], "summary" => %{"generation" => 2, "floor" => 2}}} =
             get(view, ["a"])

    assert {:ok, %{"keys" => [], "next" => nil}} =
             C.view_read(view, %{"op" => "scan", "after" => nil, "limit" => 8})

    assert :ok = C.close_view(view)
  end

  test "legacy manifests refuse without implicit adoption or changed files", c do
    view = seed(c)
    assert :ok = C.close_view(view)
    pointer = Jason.decode!(File.read!(pointer(c)))
    manifest_path = Path.join([directory(c), "manifests", pointer["manifest"] <> ".json"])

    assert {:ok, state, _} =
             C.Blocks.decode(Jason.decode!(File.read!(manifest_path)), fn hash, _ ->
               File.read(Path.join([directory(c), "manifests", hash <> ".json"]))
             end)

    bytes = C.Encoding.encode(state)
    hash = JSON.sha256(bytes)
    path = Path.join([directory(c), "manifests", hash <> ".json"])
    File.write!(path, bytes)
    File.chmod!(path, 0o600)

    File.write!(
      pointer(c),
      Jason.encode!(pointer |> Map.put("version", 3) |> Map.put("manifest", hash))
    )

    before = files(c)
    assert {:error, :collection_view_unsupported} = C.open_view(c.root, c.project)
    assert files(c) == before

    assert {:ok, %{"record" => %{"value" => %{"text" => "alpha"}}}} =
             C.execute(c.root, c.project, %{"op" => "get", "key" => "a"}, Ipse.Usage.id())
  end

  test "root replacement makes the entire view stale and explicit reopen observes it", c do
    view = seed(c)
    assert {:ok, _} = commit(c, 1, [change("b", 1, %{"text" => "replacement"})])
    assert {:error, :collection_view_stale} = get(view, ["a"])
    await_dead(view.server)
    assert {:error, :collection_view_unavailable} = get(view, ["b"])
    assert {:ok, fresh} = C.open_view(c.root, c.project)
    assert {:ok, %{"records" => [%{"value" => %{"text" => "replacement"}}]}} = get(fresh, ["b"])
    assert :ok = C.close_view(fresh)
  end

  test "selected objects are rehashed while unchanged-root unrelated manifest blocks stay cached",
       c do
    view = seed(c)
    state = :sys.get_state(view.server)
    root = Jason.decode!(state.cache["root_bytes"])
    manifest_path = Path.join([directory(c), "manifests", root["manifest"] <> ".json"])
    File.write!(manifest_path, "broken manifest")
    assert {:ok, %{"records" => [%{"value" => %{"text" => "alpha"}}]}} = get(view, ["a"])
    ref = state.cache["records"]["b"]
    File.write!(Path.join([directory(c), "objects", ref["sha256"] <> ".json"]), "{}")
    assert {:error, :collection_unavailable} = get(view, ["b"])
    await_dead(view.server)
    assert {:error, :collection_unavailable} = C.open_view(c.root, c.project)
  end

  test "copied, forged and cross-task handles cannot grant caller authority", c do
    view = seed(c)
    assert inspect(view) == "#Collection.ReadView<private>"
    assert {:error, :collection_view_unavailable} = get(%{view | ref: make_ref()}, ["a"])
    assert {:error, :collection_view_unavailable} = get(Map.from_struct(view), ["a"])

    assert {:error, :collection_view_unavailable} =
             Task.async(fn -> get(view, ["a"]) end) |> Task.await()

    assert {:error, :collection_view_unavailable} =
             Task.async(fn ->
               GenServer.call(
                 view.server,
                 {view.ref, {:borrow, %{"op" => "get_many", "keys" => ["a"]}}}
               )
             end)
             |> Task.await()

    owner = self()

    assert {:error, :collection_view_unavailable} =
             Task.async(fn ->
               :ok = Resources.bind_effect_owner(owner)
               get(view, ["a"])
             end)
             |> Task.await()

    assert {:ok, _} = Resources.file_effect(fn -> get(view, ["a"]) end)
    assert :ok = C.close_view(view)
  end

  test "closed request schemas refuse without consuming reads", c do
    view = seed(c)

    for request <- [
          %{"op" => "get_many", "keys" => []},
          %{"op" => "get_many", "keys" => List.duplicate("a", 9)},
          %{"op" => "get_many", "keys" => ["a", "a"]},
          %{"op" => "get_many", "keys" => ["../a"]},
          %{"op" => "scan", "after" => nil, "limit" => 1.0},
          %{"op" => "scan", "after" => nil, "limit" => 9},
          %{"op" => "get_many", "keys" => ["a"], "owner" => "forged"}
        ] do
      assert {:error, :invalid_collection_view_request} = C.view_read(view, request)
    end

    assert :sys.get_state(view.server).reads == 0
    assert :ok = C.close_view(view)
  end

  test "private cache corruption of headers, selected refs or scan index fails closed", c do
    for mutate <- [
          fn s -> put_in(s, [:cache, "summary", "generation"], 2) end,
          fn s -> put_in(s, [:cache, "records", "a", "sha256"], JSON.sha256("forged")) end,
          fn s -> %{s | index: :gb_trees.empty()} end
        ] do
      view =
        if File.exists?(pointer(c)), do: elem(C.open_view(c.root, c.project), 1), else: seed(c)

      :sys.replace_state(view.server, mutate)

      assert {:error, :collection_view_corrupt} =
               C.view_read(view, %{"op" => "scan", "after" => nil, "limit" => 8})

      await_dead(view.server)
    end
  end

  test "absolute expiry and copied-handle read cap cannot be renewed", c do
    view = seed(c)
    :sys.replace_state(view.server, &%{&1 | reads: 511})
    assert {:ok, _} = get(%{view | ref: view.ref}, ["a"])
    assert {:error, :collection_view_capacity} = get(view, ["a"])
    await_dead(view.server)
    assert {:ok, expiring} = C.open_view(c.root, c.project)

    :sys.replace_state(
      expiring.server,
      &%{&1 | deadline: System.monotonic_time(:millisecond) - 1}
    )

    assert {:error, :collection_view_expired} = get(expiring, ["a"])
    await_dead(expiring.server)
  end

  test "encoded cache and ref-count capacity are enforced before reads", c do
    view = seed(c)
    cache = :sys.get_state(view.server).cache
    assert :ok = C.close_view(view)

    records =
      Map.new(1..8192, fn n ->
        key = "k" <> String.pad_leading(Integer.to_string(n), 95, "0")
        {key, %{cache["records"]["a"] | "key" => key}}
      end)

    assert {:ok, oversized} = ReadView.begin()

    assert {:error, :collection_view_capacity} =
             ReadView.install(oversized, %{cache | "records" => records})

    await_dead(oversized.server)
    assert {:ok, too_many} = ReadView.begin()
    records = Map.put(records, "extra", %{cache["records"]["a"] | "key" => "extra"})

    assert {:error, :collection_view_capacity} =
             ReadView.install(too_many, %{cache | "records" => records})

    await_dead(too_many.server)
  end

  test "one finite global slot per original owner and owner death closes metadata", _c do
    parent = self()

    owners =
      Enum.map(1..16, fn _ ->
        spawn(fn ->
          result = ReadView.begin()
          send(parent, {self(), result})

          receive do
            :stop -> :ok
          end
        end)
      end)

    on_exit(fn -> Enum.each(owners, &Process.exit(&1, :kill)) end)

    servers =
      Enum.map(owners, fn owner ->
        assert_receive {^owner, {:ok, view}}, 2_000
        view.server
      end)

    assert {:error, :collection_view_capacity} = ReadView.begin()
    Enum.each(owners, &Process.exit(&1, :kill))
    Enum.each(servers, &await_dead/1)
    assert {:ok, view} = ReadView.begin()
    assert :ok = C.close_view(view)
  end

  test "8192 short-key refs fit while a forged summary or encoded overhead does not", c do
    view = seed(c)
    cache = :sys.get_state(view.server).cache
    assert :ok = C.close_view(view)

    records =
      Map.new(1..8192, fn n ->
        key = "k#{n}"
        {key, %{cache["records"]["a"] | "key" => key}}
      end)

    assert {:ok, bounded} = ReadView.begin()
    assert :ok = ReadView.install(bounded, %{cache | "records" => records})
    assert :ok = C.close_view(bounded)
    assert {:ok, forged} = ReadView.begin()

    assert {:error, :collection_view_capacity} =
             ReadView.install(forged, put_in(cache, ["summary", "generation"], 1.0))

    await_dead(forged.server)
  end

  test "original owner death fences actual native work even with paused borrower alive", c do
    handler = "read-view-owner-loss-" <> Ipse.Usage.id()
    parent = self()

    assert :ok =
             :telemetry.attach(
               handler,
               [:ipse, :extension, :collection, :view_read],
               fn _, _, _, _ ->
                 cap = Process.get({C, :lock_held})
                 send(parent, {:borrower, self(), cap.controller})

                 receive do
                   :continue -> :ok
                 after
                   5_000 -> raise "fixture release missing"
                 end
               end,
               nil
             )

    on_exit(fn -> :telemetry.detach(handler) end)

    owner =
      spawn(fn ->
        view = seed(c)
        send(parent, {:view, view})
        Resources.file_effect(fn -> send(parent, {:completed, get(view, ["a"])}) end)
      end)

    assert_receive {:view, view}, 5_000
    assert_receive {:borrower, borrower, controller}, 5_000
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
    :telemetry.detach(handler)
  end

  test "actual native owner loss yields unknown without selected data", c do
    view = seed(c)
    handler = "read-view-loss-" <> Ipse.Usage.id()
    parent = self()

    assert :ok =
             :telemetry.attach(
               handler,
               [:ipse, :extension, :collection, :view_read],
               fn _, _, _, _ ->
                 cap = Process.get({C, :lock_held})
                 send(parent, {:lost_native, cap.controller})
                 Port.close(cap.port)
               end,
               nil
             )

    on_exit(fn -> :telemetry.detach(handler) end)
    assert {:unknown, :collection_lock_lost} = get(view, ["a"])
    assert_receive {:lost_native, _}
    await_dead(view.server)
    :telemetry.detach(handler)
    assert {:ok, fresh} = C.open_view(c.root, c.project)
    assert {:ok, _} = get(fresh, ["a"])
    assert :ok = C.close_view(fresh)
  end

  test "expiry during an actual native read discards its otherwise valid data", c do
    view = seed(c)
    handler = "read-view-expiry-" <> Ipse.Usage.id()

    assert :ok =
             :telemetry.attach(
               handler,
               [:ipse, :extension, :collection, :view_read],
               fn _, _, _, _ ->
                 monitor = Process.monitor(view.server)
                 send(view.server, :expire)

                 receive do
                   {:DOWN, ^monitor, :process, _, _} -> :ok
                 after
                   2_000 -> raise "expiry fixture did not close cache"
                 end
               end,
               nil
             )

    on_exit(fn -> :telemetry.detach(handler) end)
    assert {:error, :collection_view_unavailable} = get(view, ["a"])
    refute Process.alive?(view.server)
    :telemetry.detach(handler)
  end

  test "a lost borrowed file-effect worker invalidates its cache", c do
    view = seed(c)

    assert catch_exit(
             Resources.file_effect(fn ->
               assert {:ok, _, _} = ReadView.borrow(view, %{"op" => "get_many", "keys" => ["a"]})
               exit(:synthetic_borrower_loss)
             end)
           ) == :synthetic_borrower_loss

    await_dead(view.server)
    assert {:error, :collection_view_unavailable} = get(view, ["a"])
  end

  test "another VM shares the actual lock then invalidates the old root witness", c do
    view = seed(c)
    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    request = %{
      "op" => "commit",
      "expected_generation" => 1,
      "advance_floor" => false,
      "changes" => [change("a", 1, %{"text" => "other VM"})]
    }

    program = """
    {:ok, _} = Application.ensure_all_started(:ipse)
    result = Ipse.Extension.Collection.execute(#{inspect(c.root)}, #{inspect(c.project)},
      #{inspect(request)}, #{inspect(Ipse.Usage.id())})
    case result do
      {:ok, _} -> IO.puts("PUBLISHED")
      {:error, :collection_unavailable} -> IO.puts("BUSY")
      _ -> System.halt(2)
    end
    """

    invoke = fn ->
      System.cmd("elixir", ["--erl", "+S 2:2"] ++ paths ++ ["-e", program],
        stderr_to_stdout: true
      )
    end

    Resources.file_effect(fn ->
      assert {:ok, cap} =
               Ipse.Runner.Transaction.acquire(Path.join(directory(c), ".lock"), cwd: c.parent)

      assert {"BUSY\n", 0} = invoke.()
      assert :ok = Ipse.Runner.Transaction.release(cap)
    end)

    assert {:ok, _} = get(view, ["a"])
    assert {"PUBLISHED\n", 0} = invoke.()
    assert {:error, :collection_view_stale} = get(view, ["a"])
    await_dead(view.server)
  end

  defp files(c) do
    Path.wildcard(Path.join(directory(c), "**/*"), match_dot: true)
    |> Enum.filter(&File.regular?/1)
    |> Map.new(&{Path.relative_to(&1, directory(c)), JSON.sha256(File.read!(&1))})
  end

  defp await_dead(pid) do
    monitor = Process.monitor(pid)

    receive do
      {:DOWN, ^monitor, :process, ^pid, _} -> :ok
    after
      5_000 -> flunk("cache did not terminate")
    end
  end
end
