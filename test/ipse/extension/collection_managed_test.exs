defmodule Ipse.Extension.CollectionManagedTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.Collection, as: C
  alias Ipse.JSON

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-collection-managed-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)
    %{root: Path.join(parent, "collections"), project: JSON.sha256("managed fixture")}
  end

  defp change(key, revision, value),
    do: %{"key" => key, "expected_revision" => revision, "value" => value}

  defp original(generation \\ 0),
    do: %{
      "op" => "commit",
      "expected_generation" => generation,
      "advance_floor" => false,
      "changes" => [change("note.a", 0, %{"text" => "original"})]
    }

  defp normalized(request),
    do: Map.update!(request, "changes", &(&1 ++ [change("host.validity.a", 0, %{"anchor" => 0})]))

  defp run(c, request, fun, id \\ Ipse.Usage.id()),
    do: C.execute_managed(c.root, c.project, request, id, JSON.sha256("recipe"), fun)

  defp read(c, key),
    do: C.execute(c.root, c.project, %{"op" => "get", "key" => key}, Ipse.Usage.id())

  test "one commit binds original, normalized and host receipt and survives reopen", c do
    request = original()
    expected = normalized(request)
    id = Ipse.Usage.id()
    caller = self()

    assert {:ok, result} =
             run(
               c,
               request,
               fn witness, get ->
                 assert witness["root"]["generation"] == 0
                 assert witness["manifest_sha256"] == nil
                 assert {:ok, nil} = get.("host.validity.a")
                 send(caller, {:read_closure, get})
                 {:ok, expected, %{"version" => 1, "anchor" => 0}}
               end,
               id
             )

    assert result["binding"]["original_request_sha256"] == JSON.digest([request])
    assert result["binding"]["recipe_sha256"] == JSON.sha256("recipe")
    assert result["binding"]["normalization_sha256"] == JSON.digest([result["normalization"]])
    assert result["receipt"]["request_sha256"] == JSON.digest([expected])
    assert result["receipt"]["managed_binding_sha256"] == JSON.digest([result["binding"]])
    assert result["receipt"]["generation"] == 1
    assert_receive {:read_closure, get}
    assert {:error, :managed_read_refused} = get.("note.a")

    assert {:ok, %{"record" => %{"value" => %{"text" => "original"}, "revision" => 1}}} =
             read(c, "note.a")

    assert {:ok, %{"record" => %{"value" => %{"anchor" => 0}, "revision" => 1}}} =
             read(c, "host.validity.a")

    assert Jason.decode!(File.read!(Path.join([c.root, c.project, "root.json"])))["version"] == 5

    receipt = result["receipt"]

    assert {:ok, %{"operation" => ^receipt}} =
             C.execute(
               c.root,
               c.project,
               %{"op" => "inspect", "operation_id" => id},
               Ipse.Usage.id()
             )

    assert {:existing, %{"operation" => ^receipt}} =
             run(c, request, fn _, _ -> flunk("duplicate entered normalizer") end, id)
  end

  test "original CAS conflicts and reserved original keys refuse before normalization", c do
    assert {:conflict, %{"generation" => 0}} =
             run(c, original(1), fn _, _ -> flunk("stale entered normalizer") end)

    reserved = put_in(original(), ["changes", Access.at(0), "key"], "host.validity.forged")

    assert {:error, :invalid_managed_collection_request} =
             run(c, reserved, fn _, _ -> flunk("reserved input entered normalizer") end)

    assert {:ok, %{"record" => nil}} = read(c, "note.a")
  end

  test "normalization cannot change original values, generation, floor or write nonreserved keys",
       c do
    request = original()

    for damaged <- [
          put_in(normalized(request), ["changes", Access.at(0), "value", "text"], "changed"),
          Map.put(normalized(request), "expected_generation", 1),
          Map.put(normalized(request), "advance_floor", true),
          put_in(normalized(request), ["changes", Access.at(1), "key"], "other.a"),
          put_in(normalized(request), ["changes", Access.at(1), "value"], nil),
          request,
          Map.update!(
            request,
            "changes",
            &(&1 ++ for(n <- 1..17, do: change("host.validity.#{n}", 0, %{})))
          )
        ] do
      assert {:error, :managed_normalization_refused} =
               run(c, request, fn _, _ -> {:ok, damaged, %{}} end)

      assert {:ok, %{"record" => nil}} = read(c, "note.a")
    end
  end

  test "read capability cannot cross process, outlive callback or exceed32 reads", c do
    request = original()

    assert {:ok, _} =
             run(c, request, fn _, get ->
               task = Task.async(fn -> get.("note.a") end)
               assert {:error, :managed_read_refused} = Task.await(task)
               for _ <- 1..32, do: assert({:ok, nil} = get.("note.a"))
               assert {:error, :managed_read_refused} = get.("note.a")
               {:ok, normalized(request), %{}}
             end)
  end

  test "normalizer refusal, nonobject receipt and overlarge receipt publish nothing", c do
    request = original()

    for response <- [
          {:error, :ineligible},
          {:ok, normalized(request), []},
          {:ok, normalized(request), %{"text" => String.duplicate("x", 2049)}}
        ] do
      assert {:error, :managed_normalization_refused} = run(c, request, fn _, _ -> response end)
      assert {:ok, %{"record" => nil}} = read(c, "note.a")
    end
  end

  test "actual native owner loss prevents publication and reports unknown", c do
    request = original()

    assert {:unknown, _} =
             run(c, request, fn _, _ ->
               cap = Process.get({C, :lock_held})
               Port.close(cap.port)
               {:ok, normalized(request), %{}}
             end)

    assert {:ok, %{"record" => nil}} = read(c, "note.a")
    assert {:ok, %{"record" => nil}} = read(c, "host.validity.a")
  end
end
