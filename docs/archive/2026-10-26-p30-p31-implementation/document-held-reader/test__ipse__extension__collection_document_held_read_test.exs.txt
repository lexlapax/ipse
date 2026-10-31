defmodule Ipse.Extension.CollectionDocumentHeldReadTest do
  use ExUnit.Case, async: false
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.Collection
  alias Ipse.Extension.Collection.Profile

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-document-held-read-" <> Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)
    c = %{root: Path.join(parent, "collections"), project: JSON.sha256("document read fixture")}
    value = %{"parts" => List.duplicate(String.duplicate("x", 4096), 10)}
    assert {:ok, _} = commit(c, 0, 0, value)
    Map.merge(c, %{value: value, pointer: Path.join([c.root, c.project, "root.json"])})
  end

  defp commit(c, generation, revision, value) do
    Collection.execute_profile(
      c.root,
      c.project,
      %{
        "op" => "commit",
        "expected_generation" => generation,
        "advance_floor" => false,
        "changes" => [
          %{"key" => "packed.source", "expected_revision" => revision, "value" => value}
        ]
      },
      Usage.id(),
      Profile.documents()
    )
  end

  test "document owner retains exact profile/root and large records while excluding a writer",
       c do
    before = File.read!(c.pointer)
    parent = self()

    task =
      Task.async(fn ->
        Collection.with_document_read(c.root, c.project, fn witness, read ->
          assert witness["root_bytes"] == before
          assert witness["root_sha256"] == JSON.sha256(before)
          assert witness["root"]["generation"] == 1
          assert Jason.decode!(before)["storage_profile"] == Profile.documents()
          assert {:ok, record} = read.("packed.source")
          assert record["value"] == c.value
          assert record["revision"] == 1
          assert byte_size(Jason.encode!(record["value"])) > 16_384

          assert {:error, :managed_read_refused} =
                   Task.async(fn -> read.("packed.source") end) |> Task.await()

          assert {:error, :collection_lock_order} = commit(c, 1, 1, %{})

          assert {:error, :collection_lock_order} =
                   Collection.with_document_read(c.root, c.project, fn _, _ -> flunk("nested") end)

          send(parent, {:held, self()})
          receive do: (:continue -> :ok)
          assert {:ok, ^record} = read.("packed.source")
          {:ok, read}
        end)
      end)

    assert_receive {:held, owner}, 5000
    assert {:error, _} = commit(c, 1, 1, %{"text" => "contender"})
    assert File.read!(c.pointer) == before
    send(owner, :continue)
    assert {:ok, escaped} = Task.await(task, 5000)
    assert {:error, :managed_read_refused} = escaped.("packed.source")
    assert {:ok, _} = commit(c, 1, 1, %{"text" => "after release"})
    assert Collection.limits()["value_bytes"] == 6144

    assert {:error, _} =
             Collection.with_managed_read(c.root, c.project, fn _, _ -> flunk("wrong profile") end)
  end

  test "512 document reads succeed and a sticky 513th refusal prevents nominal success", c do
    before = File.read!(c.pointer)

    assert {:ok, 512} =
             Collection.with_document_read(c.root, c.project, fn _, read ->
               for _ <- 1..512, do: assert({:ok, %{"revision" => 1}} = read.("packed.source"))
               {:ok, 512}
             end)

    assert {:error, :managed_read_refused} =
             Collection.with_document_read(c.root, c.project, fn _, read ->
               for _ <- 1..512, do: assert({:ok, nil} = read.("absent"))
               assert {:error, :managed_read_refused} = read.("packed.source")
               assert {:error, :managed_read_refused} = read.("absent")
               {:ok, :must_not_escape}
             end)

    assert File.read!(c.pointer) == before
  end

  test "document reader loss permits a successor but old callback cannot report known success",
       c do
    parent = self()

    task =
      Task.async(fn ->
        Collection.with_document_read(c.root, c.project, fn _, read ->
          assert {:ok, _} = read.("packed.source")
          cap = Process.get({Collection, :lock_held})
          {:os_pid, native} = Port.info(cap.port, :os_pid)
          send(parent, {:native, self(), native})
          receive do: (:continue -> :ok)
          assert {:error, :managed_read_refused} = read.("packed.source")
          {:ok, :stale}
        end)
      end)

    assert_receive {:native, owner, native}, 5000
    assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(native)])
    assert {:ok, _} = commit(c, 1, 1, %{"text" => "successor"})
    send(owner, :continue)
    assert {:unknown, :collection_lock_lost} = Task.await(task, 5000)
  end

  test "typed unknown and invalid callbacks preserve original root without publication", c do
    before = File.read!(c.pointer)

    assert {:unknown, :synthetic_unconfirmed} =
             Collection.with_document_read(c.root, c.project, fn _, _ ->
               {:unknown, :synthetic_unconfirmed}
             end)

    assert {:error, :managed_read_refused} =
             Collection.with_document_read(c.root, c.project, fn _, read ->
               assert {:error, :managed_read_refused} = read.(%{"op" => "pending_summary"})
               :invalid
             end)

    assert {:error, :invalid_collection_request} =
             Collection.with_document_read(c.root, c.project, nil)

    assert File.read!(c.pointer) == before
  end
end
