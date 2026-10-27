defmodule Ipse.Extension.CollectionTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.Collection, as: C

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-collection-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)

    %{
      parent: parent,
      root: Path.join(parent, "collections"),
      project: Ipse.JSON.sha256("project")
    }
  end

  defp run(c, r, id \\ Ipse.Usage.id()), do: C.execute(c.root, c.project, r, id)
  defp change(key, rev, value), do: %{"key" => key, "expected_revision" => rev, "value" => value}

  defp commit(generation, changes, floor \\ false),
    do: %{
      "op" => "commit",
      "expected_generation" => generation,
      "changes" => changes,
      "advance_floor" => floor
    }

  test "immutable IDs resolve committed effects after receipt loss and cannot execute again", c do
    id = Ipse.Usage.id()
    r = commit(0, [change("a", 0, %{"text" => "original"})])
    assert {:ok, receipt} = run(c, r, id)
    assert receipt["generation"] == 1
    assert {:existing, %{"operation" => ^receipt}} = run(c, r, id)
    assert {:existing, _} = run(c, commit(1, [change("b", 0, %{})]), id)
    assert {:ok, %{"operation" => ^receipt}} = run(c, %{"op" => "inspect", "operation_id" => id})
    assert {:ok, %{"record" => nil}} = run(c, %{"op" => "get", "key" => "b"})
    assert {:conflict, %{"generation" => 1}} = run(c, commit(0, [change("b", 0, %{})]))
    assert {:conflict, _} = run(c, commit(1, [change("a", 0, %{})]))
    assert {:ok, _} = run(c, commit(1, [change("a", 1, %{"text" => "replacement"})]))
    path = Path.join(c.root, c.project)
    assert_only_reachable_manifests(path)
    assert length(Path.wildcard(Path.join([path, "objects", "*.json"]))) == 1

    assert {:ok, %{"record" => %{"revision" => 2, "value" => %{"text" => "replacement"}}}} =
             run(c, %{"op" => "get", "key" => "a"})
  end

  test "unshipped v2 manifests upgrade atomically while preserving semantic receipts", c do
    operation = Ipse.Usage.id()
    assert {:ok, receipt} = run(c, commit(0, [change("a", 0, %{"text" => "legacy"})]), operation)
    directory = Path.join(c.root, c.project)
    pointer_path = Path.join(directory, "root.json")
    pointer = Jason.decode!(File.read!(pointer_path))
    manifest_path = Path.join([directory, "manifests", pointer["manifest"] <> ".json"])

    decoded = decode_manifest(manifest_path)

    bytes = Jason.encode!(decoded |> Map.put("version", 2) |> Map.delete("floor_anchor"))
    hash = Ipse.JSON.sha256(bytes)
    legacy_path = Path.join([directory, "manifests", hash <> ".json"])
    File.write!(legacy_path, bytes)
    File.chmod!(legacy_path, 0o600)

    File.write!(
      pointer_path,
      Jason.encode!(
        pointer
        |> Map.put("version", 2)
        |> Map.put("manifest", hash)
        |> Map.delete("floor_anchor")
      )
    )

    assert {:ok, %{"operation" => ^receipt}} =
             run(c, %{"op" => "inspect", "operation_id" => operation})

    assert Jason.decode!(File.read!(pointer_path))["version"] == 2
    assert {:ok, _} = run(c, commit(1, [change("b", 0, %{"text" => "new"})]))
    assert Jason.decode!(File.read!(pointer_path))["version"] == 4

    assert {:existing, %{"operation" => ^receipt}} =
             run(c, commit(2, [change("c", 0, %{})]), operation)

    refute File.exists?(legacy_path)
  end

  test "nonzero legacy floors without applied ancestry are refused without rewriting their root",
       c do
    assert {:ok, _} = run(c, commit(0, [change("a", 0, %{"text" => "legacy support"})], true))
    directory = Path.join(c.root, c.project)
    pointer_path = Path.join(directory, "root.json")
    pointer = Jason.decode!(File.read!(pointer_path))
    manifest_path = Path.join([directory, "manifests", pointer["manifest"] <> ".json"])

    decoded = decode_manifest(manifest_path)

    legacy = decoded |> Map.put("version", 2) |> Map.drop(~w(floor_anchor floor_lineage))
    bytes = Jason.encode!(legacy)
    manifest = Ipse.JSON.sha256(bytes)
    file = Path.join([directory, "manifests", manifest <> ".json"])
    File.write!(file, bytes)
    File.chmod!(file, 0o600)

    root =
      pointer
      |> Map.put("version", 2)
      |> Map.put("manifest", manifest)
      |> Map.delete("floor_anchor")
      |> Jason.encode!()

    File.write!(pointer_path, root)
    assert {:error, :collection_unavailable} = run(c, %{"op" => "get", "key" => "a"})
    assert File.read!(pointer_path) == root
    assert File.read!(file) == bytes
  end

  test "known logical lock helper loss before publication returns unknown without exposing staging",
       c do
    assert {:ok, _} = run(c, commit(0, [change("retained", 0, %{"text" => "original"})]))
    handler = "collection-lock-loss-" <> Ipse.Usage.id()
    owner = self()

    task =
      Task.async(fn ->
        Ipse.Session.Resources.file_effect(fn ->
          send(owner, {:collection_effect, self()})

          receive do
            :publish -> run(c, commit(1, [change("staged", 0, %{"text" => "unpublished"})]))
          end
        end)
      end)

    assert_receive {:collection_effect, worker}

    :ok =
      :telemetry.attach(
        handler,
        [:ipse, :extension, :collection, :staged],
        &__MODULE__.lose_lock/4,
        worker
      )

    try do
      send(worker, :publish)
      assert {:unknown, :collection_lock_lost} = Task.await(task, 10_000)
    after
      :telemetry.detach(handler)
    end

    await(fn -> match?({:ok, %{"generation" => 1}}, run(c, %{"op" => "snapshot"})) end)

    assert {:ok, %{"generation" => 1, "record" => nil}} =
             run(c, %{"op" => "get", "key" => "staged"})

    assert {:ok, %{"record" => %{"value" => %{"text" => "original"}}}} =
             run(c, %{"op" => "get", "key" => "retained"})
  end

  def lose_lock(_, _, _, expected) do
    if self() == expected, do: Port.close(Process.get({C, :lock_held}).port)
  end

  test "a live Collection transaction refuses reentry and reverse control acquisitions before worker creation",
       c do
    owner = self()

    task =
      Task.async(fn ->
        Ipse.Session.Resources.file_effect(fn ->
          send(owner, {:collection_effect, self()})

          receive do
            :publish -> run(c, commit(0, [change("admitted", 0, %{})]))
          end
        end)
      end)

    assert_receive {:collection_effect, worker}
    handler = "collection-order-" <> Ipse.Usage.id()

    :ok =
      :telemetry.attach(
        handler,
        [:ipse, :extension, :collection, :staged],
        &__MODULE__.reverse_acquisitions/4,
        {worker, owner, c}
      )

    try do
      send(worker, :publish)
      assert {:ok, _} = Task.await(task, 10_000)

      assert_receive {:reverse_acquisitions, :ok, {:error, :collection_lock_order},
                      {:error, :consent_unavailable}, {:error, :project_identity_lock_order}}
    after
      :telemetry.detach(handler)
    end
  end

  def reverse_acquisitions(_, _, _, {expected, owner, context}) do
    if self() == expected do
      live = Ipse.Runner.Transaction.check(Process.get({C, :lock_held}))
      collection = run(context, %{"op" => "snapshot"})
      consent = Ipse.Extension.Consent.snapshot(context.root, context.project)
      identity = Ipse.Extension.ProjectIdentity.assert_order()
      send(owner, {:reverse_acquisitions, live, collection, consent, identity})
    end
  end

  test "forget floors block pre-forget imports after physical reclamation", c do
    assert {:ok, _} = run(c, commit(0, [change("note", 0, %{"text" => "forgotten"})]))
    assert {:ok, backup} = run(c, %{"op" => "snapshot"})
    assert {:ok, %{"floor" => 2}} = run(c, commit(1, [change("note", 1, nil)], true))
    assert {:ok, %{"record" => nil}} = run(c, %{"op" => "get", "key" => "note"})

    request =
      commit(2, [change("note", 0, %{"text" => "forgotten"})])
      |> Map.merge(%{"op" => "import", "project" => c.project, "floor" => backup["floor"]})

    assert {:failed, %{"code" => "collection_import_floor"}} = run(c, request)
    assert Path.wildcard(Path.join([c.root, c.project, "objects", "*.json"])) == []
    assert {:ok, %{"floor" => 2}} = run(c, %{request | "floor" => 2})
  end

  test "complete 2000-note maximum values fit without raising legacy State limits", c do
    # The whole JSON value is exactly 6144 bytes, including the evidence label.
    base = %{"text" => "", "evidence" => "bounded admitted support"}
    value = Map.put(base, "text", String.duplicate("x", 6144 - byte_size(Jason.encode!(base))))
    assert byte_size(Jason.encode!(value)) == 6144

    generation =
      Enum.reduce(Enum.chunk_every(1..2000, 128), 0, fn chunk, generation ->
        changes = Enum.map(chunk, &change("note#{&1}", 0, value))
        assert {:ok, %{"generation" => next}} = run(c, commit(generation, changes))
        next
      end)

    assert {:ok, status} = run(c, %{"op" => "status"})
    assert status["records"] == 2000
    assert status["data_bytes"] == 2000 * 6144
    assert status["accounted_total_bytes"] < 64 * 1024 * 1024
    assert status["limits"]["control_reserved_bytes"] == 22 * 1024 * 1024

    assert {:ok, page} =
             run(c, %{"op" => "scan", "generation" => generation, "after" => nil, "limit" => 32})

    assert length(page["records"]) == 32
    assert page["next"] == List.last(page["records"])["key"]
    assert {:ok, _} = run(c, commit(generation, [change("later", 0, %{})]))

    assert {:conflict, _} =
             run(c, %{
               "op" => "scan",
               "generation" => generation,
               "after" => page["next"],
               "limit" => 32
             })
  end

  test "staged crash objects and manifests cannot become visible and are reclaimed", c do
    assert {:ok, _} = run(c, commit(0, [change("a", 0, %{"text" => "visible"})]))
    dir = Path.join(c.root, c.project)
    staged = Path.join([dir, "objects", Ipse.JSON.sha256("torn") <> ".json"])
    File.write!(staged, "{partial")
    File.chmod!(staged, 0o600)
    pending = Path.join([dir, "manifests", ".pending-" <> Ipse.Usage.id()])
    File.write!(pending, "{partial")
    File.chmod!(pending, 0o600)
    assert {:ok, %{"generation" => 1}} = run(c, %{"op" => "snapshot"})
    assert {:ok, _} = run(c, commit(1, [change("b", 0, %{})]))
    refute File.exists?(staged)
    refute File.exists?(pending)

    assert {:ok, %{"record" => %{"value" => %{"text" => "visible"}}}} =
             run(c, %{"op" => "get", "key" => "a"})
  end

  test "an unreadable authoritative metadata block refuses before orphan reclamation or publication",
       c do
    assert {:ok, _} = run(c, commit(0, [change("retained", 0, %{"text" => "support"})]))
    path = Path.join(c.root, c.project)
    pointer = Path.join(path, "root.json") |> File.read!()
    root = Jason.decode!(pointer)

    wire =
      Path.join([path, "manifests", root["manifest"] <> ".json"])
      |> File.read!()
      |> Jason.decode!()

    block = Path.join([path, "manifests", hd(wire["operations"])["sha256"] <> ".json"])
    orphan = Path.join([path, "manifests", Ipse.JSON.sha256("orphan") <> ".json"])
    File.write!(orphan, "{}")
    File.chmod!(orphan, 0o600)
    File.chmod!(block, 0o644)
    assert {:error, :collection_unavailable} = run(c, commit(1, [change("unpublished", 0, %{})]))
    assert File.read!(Path.join(path, "root.json")) == pointer
    assert File.exists?(orphan)
    File.chmod!(block, 0o600)

    assert {:ok, %{"record" => %{"value" => %{"text" => "support"}}}} =
             run(c, %{"op" => "get", "key" => "retained"})
  end

  test "record byte capacity warns and refuses a new observation without evicting existing records",
       c do
    value = %{"text" => String.duplicate("x", 6133)}
    assert byte_size(Jason.encode!(value)) == 6144

    generation =
      Enum.reduce(Enum.chunk_every(1..4096, 128), 0, fn chunk, generation ->
        assert {:ok, receipt} =
                 run(c, commit(generation, Enum.map(chunk, &change("note#{&1}", 0, value))))

        receipt["generation"]
      end)

    assert {:ok, %{"notice" => "capacity_80_percent", "records" => 4096}} =
             run(c, %{"op" => "status"})

    assert {:failed, %{"code" => "collection_capacity", "generation" => ^generation}} =
             run(c, commit(generation, [change("new", 0, value)]))

    assert {:ok, %{"record" => %{"value" => ^value}}} = run(c, %{"op" => "get", "key" => "note1"})
  end

  test "a symlinked or noncanonical selected root cannot become a collection", c do
    actual = Path.join(c.parent, "actual")
    File.mkdir!(actual)
    File.chmod!(actual, 0o700)
    File.ln_s!(actual, c.root)
    assert {:error, :collection_unavailable} = run(c, %{"op" => "snapshot"})
    File.rm!(c.root)

    assert {:error, :collection_unavailable} =
             C.execute(
               c.parent <> "/actual/../collections",
               c.project,
               %{"op" => "snapshot"},
               Ipse.Usage.id()
             )
  end

  test "closed requests and unsafe single-link, mode, canonical and hash paths fail closed", c do
    for r <- [
          commit(0, [change("../bad", 0, %{})]),
          commit(0, [change("a", 0, nil)]),
          commit(0, [change("a", 0, %{"text" => String.duplicate("x", 6144)})]),
          Map.put(%{"op" => "snapshot"}, "path", "/tmp")
        ] do
      assert {:error, :invalid_collection_request} = run(c, r)
    end

    refute File.exists?(c.root)
    assert {:ok, _} = run(c, commit(0, [change("a", 0, %{"text" => "data"})]))
    dir = Path.join(c.root, c.project)
    [object] = Path.wildcard(Path.join([dir, "objects", "*.json"]))
    File.chmod!(object, 0o644)
    assert {:error, :collection_unavailable} = run(c, %{"op" => "get", "key" => "a"})
    File.chmod!(object, 0o600)
    File.ln!(object, Path.join(c.parent, "hardlink"))
    assert {:error, :collection_unavailable} = run(c, %{"op" => "get", "key" => "a"})
    File.rm!(Path.join(c.parent, "hardlink"))
    File.write!(object, "{}")
    assert {:error, :collection_unavailable} = run(c, %{"op" => "get", "key" => "a"})
    pointer = Path.join(dir, "root.json")
    bytes = File.read!(pointer)
    File.write!(pointer, String.replace(bytes, "\"version\":4", "\"version\":4,\"version\":4"))
    assert {:error, :collection_unavailable} = run(c, %{"op" => "snapshot"})
  end

  test "retained lock inode survives contention and separate VM CAS prevents two publications",
       c do
    assert {:ok, _} = run(c, %{"op" => "snapshot"})
    lock_path = Path.join([c.root, c.project, ".lock"])
    inode = File.stat!(lock_path).inode
    {:ok, lock} = Ipse.Runner.lock(lock_path)

    try do
      assert {:error, :collection_unavailable} = run(c, commit(0, [change("a", 0, %{})]))
    after
      Ipse.Runner.unlock(lock)
    end

    code = ~S'''
    [root,project,key] = System.argv()
    {:ok,_} = Application.ensure_all_started(:ipse)
    r = %{"op"=>"commit","expected_generation"=>0,"advance_floor"=>false,
      "changes"=>[%{"key"=>key,"expected_revision"=>0,"value"=>%{"owner"=>key}}]}
    result = Ipse.Extension.Collection.execute(root,project,r,Ipse.Usage.id())
    IO.puts(inspect(elem(result,0)))
    '''

    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    tasks =
      for key <- ~w(first second) do
        Task.async(fn ->
          System.cmd(
            System.find_executable("elixir"),
            paths ++ ["-e", code, "--", c.root, c.project, key],
            stderr_to_stdout: true,
            env: [{"ERL_FLAGS", "+S 2:2"}]
          )
        end)
      end

    results =
      Enum.map(tasks, fn task ->
        {output, status} = Task.await(task, 30_000)
        assert status == 0, output
        String.trim(output)
      end)

    assert Enum.count(results, &(&1 == ":ok")) == 1
    assert Enum.all?(results, &(&1 in [":ok", ":conflict", ":error"]))
    assert {:ok, %{"generation" => 1}} = run(c, %{"op" => "snapshot"})
    assert File.stat!(lock_path).inode == inode
  end

  @tag timeout: 30_000
  test "killing a publishing OS VM exposes only a complete generation and permits reclamation",
       c do
    assert {:ok, _} = run(c, commit(0, [change("original", 0, %{"text" => "retained"})]))
    barrier = Path.join(c.parent, "crash-barrier")
    objects = Path.join([c.root, c.project, "objects"])

    code = ~S'''
    [root,project,barrier] = System.argv()
    {:ok,_} = Application.ensure_all_started(:ipse)
    File.write!(barrier<>".pid",:os.getpid())
    wait = fn wait -> unless File.exists?(barrier), do: (Process.sleep(1); wait.(wait)) end
    wait.(wait)
    changes = for n <- 1..128, do: %{"key"=>"staged#{n}","expected_revision"=>0,
      "value"=>%{"text"=>String.duplicate("x",6000),"source"=>n}}
    r = %{"op"=>"commit","expected_generation"=>1,"advance_floor"=>false,"changes"=>changes}
    result = Ipse.Extension.Collection.execute(root,project,r,Ipse.Usage.id())
    IO.puts(inspect(result))
    '''

    paths = Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)])

    task =
      Task.async(fn ->
        System.cmd(
          System.find_executable("elixir"),
          paths ++ ["-e", code, "--", c.root, c.project, barrier],
          stderr_to_stdout: true,
          env: [{"ERL_FLAGS", "+S 2:2"}]
        )
      end)

    await(fn -> File.exists?(barrier <> ".pid") end)
    pid = File.read!(barrier <> ".pid")
    assert Regex.match?(~r/\A[0-9]+\z/, pid)
    File.write!(barrier, "release")
    await(fn -> Enum.count(File.ls!(objects), &(&1 != ".writer.lock")) > 1 end)
    {_, 0} = System.cmd("kill", ["-KILL", pid], stderr_to_stdout: true)
    {_, status} = Task.await(task, 10_000)
    assert status != 0
    await(fn -> match?({:ok, _}, run(c, %{"op" => "snapshot"})) end)
    assert {:ok, snapshot} = run(c, %{"op" => "snapshot"})
    assert snapshot["generation"] in [1, 2]
    rows = all_rows(c, snapshot["generation"], nil, [])
    assert length(rows) == if(snapshot["generation"] == 1, do: 1, else: 129)
    assert Enum.find(rows, &(&1["key"] == "original"))["value"] == %{"text" => "retained"}
    assert {:ok, _} = run(c, commit(snapshot["generation"], [change("after-crash", 0, %{})]))
    assert Enum.count(File.ls!(objects), &(&1 != ".writer.lock")) == length(rows) + 1
  end

  defp await(fun, remaining \\ 10_000)

  defp await(fun, remaining) when remaining > 0 do
    unless fun.() do
      Process.sleep(1)
      await(fun, remaining - 1)
    end
  end

  defp await(_, _), do: flunk("storage process barrier timed out")

  defp decode_manifest(path) do
    stored = path |> File.read!() |> Jason.decode!()

    assert {:ok, decoded, _} =
             Ipse.Extension.Collection.Blocks.decode(stored, fn hash, _ ->
               File.read(Path.join(Path.dirname(path), hash <> ".json"))
             end)

    decoded
  end

  defp assert_only_reachable_manifests(path) do
    pointer = Path.join(path, "root.json") |> File.read!() |> Jason.decode!()
    manifest = Path.join([path, "manifests", pointer["manifest"] <> ".json"])
    stored = manifest |> File.read!() |> Jason.decode!()

    assert {:ok, _, reachable} =
             Ipse.Extension.Collection.Blocks.decode(stored, fn hash, _ ->
               File.read(Path.join(Path.dirname(manifest), hash <> ".json"))
             end)

    actual =
      Path.wildcard(Path.join([path, "manifests", "*.json"]))
      |> Enum.map(&Path.basename(&1, ".json"))
      |> MapSet.new()

    assert actual == MapSet.put(reachable, pointer["manifest"])
  end

  defp all_rows(c, generation, after_key, rows) do
    assert {:ok, page} =
             run(c, %{
               "op" => "scan",
               "generation" => generation,
               "after" => after_key,
               "limit" => 32
             })

    if page["next"],
      do: all_rows(c, generation, page["next"], rows ++ page["records"]),
      else: rows ++ page["records"]
  end
end
