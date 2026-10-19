defmodule Ipse.Extensions.StateTest do
  use ExUnit.Case, async: false
  alias Ipse.Extensions.State

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-state-#{Ipse.Usage.id()}")
    namespace = String.duplicate("a", 64)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, namespace: namespace}
  end

  defp execute(ctx, request), do: State.execute(ctx.root, ctx.namespace, request, Ipse.Usage.id())
  defp get(key), do: %{"op" => "state.get", "scope" => "project", "key" => key}

  defp put(key, revision, value),
    do: %{
      "op" => "state.put",
      "scope" => "project",
      "key" => key,
      "expected_revision" => revision,
      "value" => value
    }

  defp delete(key, revision),
    do: %{
      "op" => "state.delete",
      "scope" => "project",
      "key" => key,
      "expected_revision" => revision
    }

  defp list(after_key \\ nil, generation \\ nil),
    do: %{
      "op" => "state.list",
      "scope" => "project",
      "after" => after_key,
      "generation" => generation,
      "limit" => 2
    }

  test "CAS revisions and retained tombstones prevent stale ingestion resurrection", ctx do
    assert {:ok, %{"record" => %{"revision" => 0, "deleted" => true}}} = execute(ctx, get("note"))

    assert {:ok, %{"record" => %{"revision" => 1}}} =
             execute(ctx, put("note", 0, %{"text" => "old"}))

    assert {:ok, %{"record" => %{"revision" => 2, "deleted" => true}}} =
             execute(ctx, delete("note", 1))

    assert {:conflict, %{"record" => %{"revision" => 2}}} =
             execute(ctx, put("note", 1, %{"text" => "stale"}))

    assert {:conflict, _} = execute(ctx, put("note", 0, %{"text" => "stale"}))

    assert {:ok, %{"record" => %{"revision" => 2, "deleted" => true, "value" => nil}}} =
             execute(ctx, get("note"))

    assert {:ok, %{"record" => %{"revision" => 3, "value" => %{"text" => "new"}}}} =
             execute(ctx, put("note", 2, %{"text" => "new"}))
  end

  test "pagination pins generation and lists metadata without private values", ctx do
    for key <- ~w(a b c), do: assert({:ok, _} = execute(ctx, put(key, 0, %{"secret" => key})))
    assert {:ok, page} = execute(ctx, list())
    assert Enum.map(page["records"], & &1["key"]) == ~w(a b)
    assert page["next"] == "b"
    refute Enum.any?(page["records"], &Map.has_key?(&1, "value"))
    assert {:ok, final} = execute(ctx, list(page["next"], page["generation"]))
    assert Enum.map(final["records"], & &1["key"]) == ["c"]
    assert final["next"] == nil
    assert {:ok, _} = execute(ctx, delete("a", 1))
    assert {:conflict, _} = execute(ctx, list(page["next"], page["generation"]))
  end

  test "optional write deadlines are closed bounded put preconditions" do
    for deadline <- [0, 9_007_199_254_740_991] do
      assert :ok = State.validate(Map.put(put("note", 0, %{}), "write_before_ms", deadline))
    end

    for deadline <- [nil, true, "1000", 1000.0, -1, 9_007_199_254_740_992] do
      assert {:error, :invalid_extension_state_request} =
               State.validate(Map.put(put("note", 0, %{}), "write_before_ms", deadline))
    end

    for request <- [get("note"), delete("note", 0), list()] do
      assert {:error, :invalid_extension_state_request} =
               State.validate(Map.put(request, "write_before_ms", 0))
    end
  end

  test "elapsed write deadlines preserve state and produce exact known failed receipts", ctx do
    assert {:ok, original} = execute(ctx, put("note", 0, %{"text" => "original"}))
    file = Path.join([ctx.root, ctx.namespace, "state.json"])
    bytes = File.read!(file)
    request = Map.put(put("note", 1, %{"text" => "replacement"}), "write_before_ms", 0)
    operation_id = Ipse.Usage.id()

    assert {:failed, failure} = State.execute(ctx.root, ctx.namespace, request, operation_id)
    assert failure["code"] == "write_deadline_elapsed"
    assert failure["checked_at_ms"] >= request["write_before_ms"]
    assert failure["generation"] == original["generation"]
    assert failure["record"] == Map.drop(original["record"], ["value"])
    assert State.valid_outcome?(request, "failed", failure, operation_id)
    assert File.read!(file) == bytes
    assert Path.wildcard(Path.join([ctx.root, ctx.namespace, ".pending-*"])) == []

    for invalid <- [
          Map.put(failure, "code", "other"),
          Map.put(failure, "extra", true),
          Map.put(failure, "checked_at_ms", -1),
          put_in(failure, ["record", "key"], "other"),
          put_in(failure, ["record", "revision"], 0),
          put_in(failure, ["record", "operation_id"], "invalid")
        ] do
      refute State.valid_outcome?(request, "failed", invalid, operation_id)
    end

    refute State.valid_outcome?(
             Map.delete(request, "write_before_ms"),
             "failed",
             failure,
             operation_id
           )

    refute State.valid_outcome?(
             Map.put(request, "write_before_ms", failure["checked_at_ms"] + 1),
             "failed",
             failure,
             operation_id
           )

    stale = Map.put(request, "expected_revision", 0)
    assert {:conflict, conflict} = State.execute(ctx.root, ctx.namespace, stale, operation_id)
    assert State.valid_outcome?(stale, "conflict", conflict, operation_id)

    missing = Map.put(request, "key", "missing") |> Map.put("expected_revision", 0)
    assert {:failed, absent} = State.execute(ctx.root, ctx.namespace, missing, operation_id)
    assert absent["record"]["revision"] == 0
    assert State.valid_outcome?(missing, "failed", absent, operation_id)
    assert File.read!(file) == bytes

    live = Map.put(request, "write_before_ms", System.system_time(:millisecond) + 60_000)
    assert {:ok, updated} = State.execute(ctx.root, ctx.namespace, live, operation_id)
    assert updated["record"]["revision"] == 2
    assert State.valid_outcome?(live, "ok", updated, operation_id)
    assert Enum.sort(Map.keys(updated)) == ~w(generation record)
  end

  test "advisory contention never overwrites and preserves lock inode", ctx do
    assert {:ok, _} = execute(ctx, put("a", 0, %{}))
    lock_path = Path.join([ctx.root, ctx.namespace, ".lock"])
    {:ok, before} = File.stat(lock_path)
    {:ok, lock} = Ipse.Runner.lock(lock_path)

    try do
      assert {:error, _} = execute(ctx, put("a", 1, %{"lost" => true}))
    after
      Ipse.Runner.unlock(lock)
    end

    assert {:ok, %{"record" => %{"revision" => 1, "value" => %{}}}} = execute(ctx, get("a"))
    assert {:ok, _} = execute(ctx, put("a", 1, %{"committed" => true}))
    {:ok, after_unlock} = File.stat(lock_path)
    assert before.inode == after_unlock.inode
  end

  test "tombstones count against quota and larger stores retain duplicate-key validation", ctx do
    assert {:ok, _} = execute(ctx, get("a"))

    records =
      Map.new(1..256, fn n ->
        key = "key#{n}" <> String.duplicate("x", 32)

        {key,
         %{
           "key" => key,
           "revision" => 1,
           "deleted" => true,
           "value" => nil,
           "operation_id" => Ipse.Usage.id()
         }}
      end)

    state = %{
      "version" => 1,
      "namespace" => ctx.namespace,
      "generation" => 256,
      "records" => records
    }

    file = Path.join([ctx.root, ctx.namespace, "state.json"])
    File.write!(file, Jason.encode!(state))
    File.chmod!(file, 0o600)
    assert byte_size(File.read!(file)) > 32_768
    first = "key1" <> String.duplicate("x", 32)
    assert {:ok, _} = execute(ctx, get(first))
    assert {:error, :extension_state_quota} = execute(ctx, delete("new", 0))
    assert {:ok, _} = execute(ctx, put(first, 1, %{"fresh" => true}))
    bytes = File.read!(file)
    File.write!(file, String.replace(bytes, "\"version\":1", "\"version\":1,\"version\":1"))
    before = File.read!(file)
    assert {:error, _} = execute(ctx, get(first))
    assert File.read!(file) == before
  end

  test "closed requests, size limits, unsafe paths and corruption fail without repair", ctx do
    for request <- [
          put("../bad", 0, %{}),
          put("ok", -1, %{}),
          put("ok", 0, %{"text" => String.duplicate("a", 8192)}),
          Map.put(get("a"), "path", "/tmp"),
          Map.put(get("a"), "scope", "global"),
          Map.put(list(), "limit", 17)
        ] do
      assert {:error, _} = execute(ctx, request)
    end

    refute File.exists?(ctx.root)
    assert {:ok, _} = execute(ctx, put("a", 0, %{}))
    file = Path.join([ctx.root, ctx.namespace, "state.json"])

    for bytes <- ["{partial", Jason.encode!(%{"version" => 2}), String.duplicate(" ", 1_048_577)] do
      File.write!(file, bytes)
      assert {:error, _} = execute(ctx, get("a"))
      assert File.read!(file) == bytes
    end

    File.rm!(file)
    File.ln_s!("/dev/null", file)
    assert {:error, _} = execute(ctx, put("a", 0, %{}))
    assert {:ok, %{type: :symlink}} = File.lstat(file)
  end
end
