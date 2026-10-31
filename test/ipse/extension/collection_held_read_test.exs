defmodule Ipse.Extension.CollectionHeldReadTest do
  use ExUnit.Case, async: false
  alias Ipse.Extension.Collection
  alias Ipse.JSON

  @moduletag :collection_held_read

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-collection-held-read-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)
    c = %{root: Path.join(parent, "collections"), project: JSON.sha256("held read")}
    assert {:ok, _} = commit(c, 0, 0, "original")
    Map.put(c, :root_file, Path.join([c.root, c.project, "root.json"]))
  end

  defp commit(c, generation, revision, text) do
    Collection.execute(
      c.root,
      c.project,
      %{
        "op" => "commit",
        "expected_generation" => generation,
        "advance_floor" => false,
        "changes" => [
          %{"key" => "selected", "expected_revision" => revision, "value" => %{"text" => text}}
        ]
      },
      Ipse.Usage.id()
    )
  end

  test "the actual Collection owner stays locked across every observation and callback", c do
    before = File.read!(c.root_file)
    parent = self()

    task =
      Task.async(fn ->
        Collection.with_managed_read(c.root, c.project, fn witness, read ->
          assert {:ok, record} = read.("selected")
          assert record["revision"] == 1
          assert record["value"] == %{"text" => "original"}
          assert witness["root"]["generation"] == 1
          assert witness["root_bytes"] == before
          assert witness["root_sha256"] == JSON.sha256(before)
          refute Map.has_key?(witness, "operation_id")
          send(parent, {:held, self()})
          receive do: (:continue -> :ok)
          assert {:ok, ^record} = read.("selected")
          {:ok, record}
        end)
      end)

    assert_receive {:held, callback}, 5000
    assert {:error, _} = commit(c, 1, 1, "contender")
    assert File.read!(c.root_file) == before
    send(callback, :continue)
    assert {:ok, %{"value" => %{"text" => "original"}}} = Task.await(task, 5000)
    assert File.read!(c.root_file) == before
    assert {:ok, _} = commit(c, 1, 1, "later explicit change")
  end

  test "read closures refuse cross-process use, escape and nested writes", c do
    assert {:ok, read} =
             Collection.with_managed_read(c.root, c.project, fn _, read ->
               assert {:error, :managed_read_refused} =
                        Task.async(fn -> read.("selected") end) |> Task.await()

               assert {:error, :collection_lock_order} = commit(c, 1, 1, "nested")

               assert {:error, :collection_lock_order} =
                        Collection.with_managed_read(c.root, c.project, fn _, _ ->
                          flunk("reentry")
                        end)

               assert {:ok, %{"value" => %{"text" => "original"}}} = read.("selected")
               {:ok, read}
             end)

    assert {:error, :managed_read_refused} = read.("selected")

    assert {:ok, %{"record" => %{"value" => %{"text" => "original"}}}} =
             Collection.execute(
               c.root,
               c.project,
               %{"op" => "get", "key" => "selected"},
               Ipse.Usage.id()
             )
  end

  test "the shared 32-unit read allowance is sticky and invalidates a nominal success", c do
    before = File.read!(c.root_file)

    assert {:error, :managed_read_refused} =
             Collection.with_managed_read(c.root, c.project, fn _, read ->
               for _ <- 1..32, do: assert({:ok, _} = read.("selected"))
               assert {:error, :managed_read_refused} = read.("selected")
               assert {:error, :managed_read_refused} = read.("missing")
               {:ok, :must_not_escape}
             end)

    assert File.read!(c.root_file) == before
  end

  test "the lease check follows owner and read-budget lifetime without consuming reads", c do
    assert {:ok, alive} =
             Collection.with_managed_read(c.root, c.project, fn _, read, alive ->
               for _ <- 1..40, do: assert(:ok = alive.())
               assert {:error, :managed_read_refused} = Task.async(alive) |> Task.await()
               for _ <- 1..32, do: assert({:ok, _} = read.("selected"))
               assert :ok = alive.()
               {:ok, alive}
             end)

    assert {:error, :managed_read_refused} = alive.()

    assert {:error, :managed_read_refused} =
             Collection.with_managed_read(c.root, c.project, fn _, read, alive ->
               for _ <- 1..33, do: read.("selected")
               assert {:error, :managed_read_refused} = alive.()
               {:ok, :must_not_escape}
             end)
  end

  test "native owner death allows a fresh owner but prevents the old callback succeeding", c do
    parent = self()

    task =
      Task.async(fn ->
        Collection.with_managed_read(c.root, c.project, fn _, read ->
          assert {:ok, _} = read.("selected")
          cap = Process.get({Collection, :lock_held})
          {:os_pid, native} = Port.info(cap.port, :os_pid)
          send(parent, {:native, self(), native})
          receive do: (:continue -> :ok)
          assert {:error, :managed_read_refused} = read.("selected")
          {:ok, :old_snapshot}
        end)
      end)

    assert_receive {:native, callback, native}, 5000
    assert {_, 0} = System.cmd("kill", ["-KILL", Integer.to_string(native)])
    assert {:ok, _} = commit(c, 1, 1, "new owner")
    send(callback, :continue)
    assert {:unknown, :collection_lock_lost} = Task.await(task, 5000)
  end

  test "unknown callback outcomes stay typed and malformed callback outcomes refuse", c do
    before = File.read!(c.root_file)

    assert {:unknown, :synthetic_unconfirmed} =
             Collection.with_managed_read(c.root, c.project, fn _, _ ->
               {:unknown, :synthetic_unconfirmed}
             end)

    assert {:error, :managed_read_refused} =
             Collection.with_managed_read(c.root, c.project, fn _, _ -> :ok end)

    assert {:error, :invalid_collection_request} =
             Collection.with_managed_read(c.root, c.project, nil)

    assert File.read!(c.root_file) == before
  end

  for used <- [0, 32] do
    test "publication closes a callback after #{used} reads without reclassifying a selected root",
         c do
      handler = {__MODULE__, make_ref()}
      caller = self()
      id = Ipse.Usage.id()

      original = %{
        "op" => "commit",
        "expected_generation" => 1,
        "advance_floor" => true,
        "changes" => [
          %{"key" => "note.a", "expected_revision" => 0, "value" => %{"text" => "selected"}}
        ]
      }

      normalized =
        Map.update!(
          original,
          "changes",
          &(&1 ++ [%{"key" => "host.validity.a", "expected_revision" => 0, "value" => %{}}])
        )

      try do
        assert {:ok, result} =
                 Collection.execute_managed(
                   c.root,
                   c.project,
                   original,
                   id,
                   JSON.sha256("synthetic recipe"),
                   fn _, read ->
                     for _ <- List.duplicate(:read, unquote(used)),
                         do: assert({:ok, nil} = read.("missing"))

                     assert :ok =
                              :telemetry.attach(
                                handler,
                                [:ipse, :extension, :collection, :staged],
                                &__MODULE__.after_normalizer/4,
                                {read, caller}
                              )

                     {:ok, normalized, %{}}
                   end
                 )

        assert result["receipt"]["generation"] == 2
        assert_receive {:after_normalizer, %{generation: 2}, true}, 5000

        assert {:ok, %{"record" => %{"revision" => 2, "value" => %{"text" => "selected"}}}} =
                 Collection.execute(
                   c.root,
                   c.project,
                   %{"op" => "get", "key" => "note.a"},
                   Ipse.Usage.id()
                 )

        assert {:ok, %{"operation" => %{"generation" => 2}}} =
                 Collection.execute(
                   c.root,
                   c.project,
                   %{"op" => "inspect", "operation_id" => id},
                   Ipse.Usage.id()
                 )
      after
        :telemetry.detach(handler)
      end
    end
  end

  def after_normalizer(_, _, metadata, {read, caller}) do
    refused = Enum.all?(1..33, fn _ -> read.("missing") == {:error, :managed_read_refused} end)
    send(caller, {:after_normalizer, metadata, refused})
  end
end
