defmodule Ipse.Extension.CollectionManagedDirectoryTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.Collection, as: C
  alias Ipse.{JSON, Session.Resources}

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-managed-directory-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)
    %{root: Path.join(parent, "collections"), project: JSON.sha256("managed directory")}
  end

  defp key(n),
    do: "p." <> String.pad_leading(String.downcase(Integer.to_string(n, 16)), 64, "0")

  defp neighbors(n \\ 0),
    do: %{
      "op" => "neighbors",
      "request" => %{
        "version" => 1,
        "prefix" => "p.",
        "fence_bytes" => 32,
        "needle" => String.slice(key(n), 2..-1//1)
      }
    }

  defp change(key, revision, value),
    do: %{"key" => key, "expected_revision" => revision, "value" => value}

  defp commit(c, generation, changes, id \\ Ipse.Usage.id()),
    do:
      C.execute(
        c.root,
        c.project,
        %{
          "op" => "commit",
          "expected_generation" => generation,
          "advance_floor" => false,
          "changes" => changes
        },
        id
      )

  defp original(generation),
    do: %{
      "op" => "commit",
      "expected_generation" => generation,
      "advance_floor" => true,
      "changes" => [change("note.a", 0, %{"text" => "original"})]
    }

  defp normalized(request),
    do: Map.update!(request, "changes", &(&1 ++ [change("host.validity.a", 0, %{})]))

  defp run(c, generation, callback),
    do:
      C.execute_managed(
        c.root,
        c.project,
        original(generation),
        Ipse.Usage.id(),
        JSON.sha256("recipe"),
        callback
      )

  defp pointer(c), do: Path.join([c.root, c.project, "root.json"])

  defp seed(c, numbers \\ [0, 10, 20, 30]) do
    id = Ipse.Usage.id()
    assert {:ok, _} = commit(c, 0, Enum.map(numbers, &change(key(&1), 0, %{"n" => &1})), id)
    id
  end

  test "actual root bytes and exact refs preserve global revisions and operation identities", c do
    first = seed(c)
    assert {:ok, _} = commit(c, 1, [change("unrelated", 0, %{})])
    updated = Ipse.Usage.id()
    assert {:ok, _} = commit(c, 2, [change(key(10), 1, %{"n" => "updated"})], updated)
    bytes = File.read!(pointer(c))
    assert {:ok, view} = C.open_view(c.root, c.project)
    assert {:ok, expected} = C.view_neighbors(view, neighbors(15)["request"])
    assert :ok = C.close_view(view)

    assert {:ok, _} =
             run(c, 3, fn witness, read ->
               assert witness["version"] === 2
               assert witness["root_state"] == "present"
               assert witness["root_bytes"] === bytes
               assert witness["root_sha256"] == JSON.sha256(bytes)
               assert witness["root"]["version"] === 3
               assert witness["root"]["generation"] === 3
               assert witness["manifest_sha256"] == Jason.decode!(bytes)["manifest"]
               assert {:ok, ^expected} = read.(neighbors(15))
               refs = expected["neighbors"]

               assert Enum.map(
                        ~w(predecessor selected successor second_successor),
                        &refs[&1]["key"]
                      ) ==
                        Enum.map([0, 10, 20, 30], &key/1)

               assert refs["selected"]["revision"] === 3
               assert refs["selected"]["operation_id"] == updated
               assert refs["predecessor"]["revision"] === 1
               assert refs["predecessor"]["operation_id"] == first
               assert {:ok, value} = read.(key(10))
               assert Map.delete(value, "value") == refs["selected"]
               assert value["value"] == %{"n" => "updated"}
               {:ok, normalized(original(3)), %{}}
             end)
  end

  test "seven neighbors plus four missing gets exhaust32 units and an ignored next lookup refuses publication",
       c do
    seed(c)
    bytes = File.read!(pointer(c))

    assert {:error, :managed_normalization_refused} =
             run(c, 1, fn _, read ->
               for _ <- 1..7, do: assert({:ok, _} = read.(neighbors(99)))
               for _ <- 1..4, do: assert({:ok, nil} = read.("missing"))
               assert {:error, :managed_read_refused} = read.(neighbors())
               assert {:error, :managed_read_refused} = read.("missing")
               {:ok, normalized(original(1)), %{}}
             end)

    assert File.read!(pointer(c)) == bytes

    assert {:ok, %{"record" => nil}} =
             C.execute(c.root, c.project, %{"op" => "get", "key" => "note.a"}, Ipse.Usage.id())
  end

  test "nil neighbor slots cost four and exact mixed exhaustion still permits publication", c do
    assert {:ok, _} =
             run(c, 0, fn witness, read ->
               assert witness["root_state"] == "absent"
               assert witness["root_bytes"] == nil
               assert witness["root_sha256"] == nil
               assert witness["manifest_sha256"] == nil

               for _ <- 1..7 do
                 assert {:ok, result} = read.(neighbors())
                 assert result["state"] == "uninitialized"
                 assert Enum.all?(Map.values(result["neighbors"]), &is_nil/1)

                 assert result["witness"] == %{
                          "version" => 2,
                          "root_state" => "absent",
                          "root" => nil,
                          "root_sha256" => nil,
                          "manifest_sha256" => nil
                        }
               end

               for _ <- 1..4, do: assert({:ok, nil} = read.("missing"))
               {:ok, normalized(original(0)), %{}}
             end)
  end

  test "closed malformed requests and cross-owner attempts debit no owner units", c do
    bad = [
      nil,
      "bad/key",
      %{"op" => "get_many", "keys" => ["missing"]},
      %{"op" => "scan", "after" => nil, "limit" => 1},
      Map.put(neighbors(), "extra", true),
      put_in(neighbors(), ["request", "version"], 1.0),
      put_in(neighbors(), ["request", "needle"], "bad"),
      put_in(neighbors(), ["request", "prefix"], "p"),
      put_in(neighbors(), ["request", "fence_bytes"], 31)
    ]

    assert {:ok, _} =
             run(c, 0, fn _, read ->
               for _ <- 1..4,
                   request <- bad,
                   do: assert({:error, :managed_read_refused} = read.(request))

               task =
                 Task.async(fn ->
                   for _ <- 1..9, do: assert({:error, :managed_read_refused} = read.(neighbors()))
                 end)

               Task.await(task)
               for _ <- 1..8, do: assert({:ok, _} = read.(neighbors()))
               {:ok, normalized(original(0)), %{}}
             end)
  end

  test "materialized empty is present and cannot acquire an uninitialized directory", c do
    assert {:ok, _} = commit(c, 0, [change("temporary", 0, %{})])

    assert {:ok, _} =
             C.execute(
               c.root,
               c.project,
               %{
                 "op" => "commit",
                 "expected_generation" => 1,
                 "advance_floor" => true,
                 "changes" => [change("temporary", 1, nil)]
               },
               Ipse.Usage.id()
             )

    bytes = File.read!(pointer(c))

    assert {:ok, _} =
             run(c, 2, fn witness, read ->
               assert witness["root_state"] == "present"
               assert witness["root_bytes"] == bytes
               assert witness["root_sha256"] == JSON.sha256(bytes)
               assert is_binary(witness["manifest_sha256"])
               assert {:error, :managed_read_refused} = read.(neighbors())
               assert {:ok, nil} = read.("missing")
               {:ok, normalized(original(2)), %{}}
             end)
  end

  test "matching prefix validation covers fences outside the selected window", c do
    seed(c)
    assert {:ok, _} = commit(c, 1, [change("p.BAD", 0, %{})])

    assert {:ok, _} =
             run(c, 2, fn _, read ->
               assert {:error, :managed_read_refused} = read.(neighbors(1))
               {:ok, normalized(original(2)), %{}}
             end)
  end

  test "neighbors read metadata only while selected value reads still rehash objects", c do
    seed(c)
    bytes = File.read!(pointer(c))

    assert {:error, :managed_normalization_refused} =
             run(c, 1, fn _, read ->
               assert {:ok, first} = read.(neighbors(15))
               selected = first["neighbors"]["selected"]
               path = Path.join([c.root, c.project, "objects", selected["sha256"] <> ".json"])
               File.write!(path, "{}")
               assert {:ok, ^first} = read.(neighbors(15))
               assert {:error, :collection_unavailable} = read.(key(10))
               {:error, :fixture_refusal}
             end)

    assert File.read!(pointer(c)) == bytes
  end

  test "same worker cannot reuse a returned closure or substitute it in a later invocation", c do
    assert :ok =
             Resources.file_effect(fn ->
               assert {:ok, _} =
                        run(c, 0, fn _, read ->
                          Process.put(:old_managed_read, read)
                          {:ok, normalized(original(0)), %{}}
                        end)

               old = Process.get(:old_managed_read)
               assert {:error, :managed_read_refused} = old.(neighbors())
               request = %{original(1) | "changes" => [change("note.b", 0, %{})]}

               assert {:ok, _} =
                        C.execute_managed(
                          c.root,
                          c.project,
                          request,
                          Ipse.Usage.id(),
                          JSON.sha256("recipe"),
                          fn _, read ->
                            for _ <- 1..9,
                                do: assert({:error, :managed_read_refused} = old.(neighbors()))

                            for _ <- 1..32, do: assert({:ok, nil} = read.("missing"))

                            normalized =
                              Map.update!(
                                request,
                                "changes",
                                &(&1 ++ [change("host.validity.b", 0, %{})])
                              )

                            {:ok, normalized, %{}}
                          end
                        )

               Process.delete(:old_managed_read)
               :ok
             end)
  end

  test "actual native owner loss refuses neighbor facts and withholds an ignored callback result",
       c do
    seed(c)
    bytes = File.read!(pointer(c))

    assert {:unknown, _} =
             run(c, 1, fn _, read ->
               cap = Process.get({C, :lock_held})
               Port.close(cap.port)
               assert {:error, :managed_read_refused} = read.(neighbors())
               {:ok, normalized(original(1)), %{}}
             end)

    assert File.read!(pointer(c)) == bytes
  end

  test "legacy roots retain binary reads and actual witnesses without implicit neighbor adoption",
       c do
    for version <- [2, 3] do
      c = %{c | root: c.root <> Integer.to_string(version)}
      seed(c)
      pointer = Jason.decode!(File.read!(pointer(c)))
      manifests = Path.join([c.root, c.project, "manifests"])

      assert {:ok, state, _} =
               C.Blocks.decode(
                 Jason.decode!(File.read!(Path.join(manifests, pointer["manifest"] <> ".json"))),
                 fn hash, _ -> File.read(Path.join(manifests, hash <> ".json")) end
               )

      encoded =
        if version == 2 do
          state
          |> Map.put("version", 2)
          |> Map.drop(~w(floor_anchor floor_lineage))
          |> Jason.encode!()
        else
          C.Encoding.encode(state)
        end

      hash = JSON.sha256(encoded)
      manifest_path = Path.join(manifests, hash <> ".json")
      File.write!(manifest_path, encoded)
      File.chmod!(manifest_path, 0o600)
      pointer = pointer |> Map.put("version", version) |> Map.put("manifest", hash)
      pointer = if version == 2, do: Map.delete(pointer, "floor_anchor"), else: pointer
      bytes = Jason.encode!(pointer)
      File.write!(pointer(c), bytes)

      assert {:ok, _} =
               run(c, 1, fn witness, read ->
                 assert witness["root_bytes"] == bytes
                 assert witness["root_sha256"] == JSON.sha256(bytes)
                 assert witness["root"]["version"] === 3
                 assert {:error, :managed_read_refused} = read.(neighbors())
                 assert {:ok, %{"value" => %{"n" => 10}}} = read.(key(10))
                 {:ok, normalized(original(1)), %{}}
               end)
    end
  end

  test "33-byte fences retain nil boundary slots and cost the same four units", c do
    zero = "wide." <> String.duplicate("0", 66)
    assert {:ok, _} = commit(c, 0, [change(zero, 0, %{})])

    request = %{
      "op" => "neighbors",
      "request" => %{
        "version" => 1,
        "prefix" => "wide.",
        "fence_bytes" => 33,
        "needle" => String.duplicate("f", 66)
      }
    }

    assert {:ok, _} =
             run(c, 1, fn _, read ->
               for _ <- 1..8 do
                 assert {:ok, result} = read.(request)
                 assert result["neighbors"]["selected"]["key"] == zero
                 assert result["neighbors"]["predecessor"] == nil
                 assert result["neighbors"]["successor"] == nil
                 assert result["neighbors"]["second_successor"] == nil
               end

               {:ok, normalized(original(1)), %{}}
             end)
  end
end
