defmodule Ipse.Extension.CollectionCallTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.CollectionCall, as: Call

  defp call(inner), do: %{"op" => "collection.call", "request" => inner}

  defp commit(changes),
    do:
      call(%{
        "op" => "commit",
        "expected_generation" => 0,
        "advance_floor" => false,
        "changes" => changes
      })
      |> Map.put("proofs", [%{"handle" => "opaque", "quote" => "bounded"}])

  defp change(key, text),
    do: %{"key" => key, "expected_revision" => 0, "value" => %{"text" => text}}

  test "worker selection is limited to closed read calls and eight bounded changes" do
    for op <- ~w(status snapshot), do: assert(:ok = Call.validate(call(%{"op" => op})))
    assert :ok = Call.validate(call(%{"op" => "get", "key" => "notes.a"}))
    assert :ok = Call.validate(call(%{"op" => "inspect", "operation_id" => Ipse.Usage.id()}))

    assert :ok =
             Call.validate(
               call(%{"op" => "scan", "generation" => 0, "after" => nil, "limit" => 4})
             )

    assert :ok = Call.validate(commit(for n <- 1..8, do: change("notes.#{n}", "bounded")))
    assert {:error, _} = Call.validate(Map.delete(commit([change("notes.a", "x")]), "proofs"))
    assert {:error, _} = Call.validate(commit(for n <- 1..9, do: change("notes.#{n}", "bounded")))
    assert {:error, _} = Call.validate(commit([change("notes.a", String.duplicate("x", 6145))]))

    for bad <- [
          call(%{"op" => "scan", "generation" => 0, "after" => nil, "limit" => 5}),
          call(%{"op" => "export", "generation" => 0, "after" => nil, "limit" => 1}),
          call(%{"op" => "status", "root" => "/tmp/untrusted"}),
          Map.put(call(%{"op" => "status"}), "project", Ipse.JSON.sha256("other")),
          Map.put(call(%{"op" => "status"}), "class", "collection.publish"),
          Map.put(call(%{"op" => "status"}), "source_category", "operator"),
          call(%{
            "op" => "rollback",
            "expected_generation" => 0,
            "checkpoint_id" => Ipse.Usage.id()
          })
        ],
        do: assert({:error, _} = Call.validate(bad))

    request =
      commit([
        change("notes.a", String.duplicate("a", 4100)),
        change("notes.b", String.duplicate("b", 4100))
      ])

    assert byte_size(Jason.encode!(request)) > 8192
    assert {:error, _} = Call.validate(request)
    assert Call.mutating?(commit([change("notes.a", "x")]))
    refute Call.mutating?(call(%{"op" => "get", "key" => "notes.a"}))

    replacement = commit([%{change("notes.a", "new") | "expected_revision" => 1}])
    assert {:error, _} = Call.validate(replacement)
    assert :ok = Call.validate(put_in(replacement, ["request", "advance_floor"], true))

    deletion =
      put_in(replacement, ["request", "changes"], [
        %{"key" => "notes.a", "expected_revision" => 1, "value" => nil}
      ])

    assert {:error, _} = Call.validate(deletion)
    assert :ok = Call.validate(put_in(deletion, ["request", "advance_floor"], true))
  end

  test "scan byte paging preserves whole records and accounts the actual continuation envelope" do
    request = call(%{"op" => "scan", "generation" => 4, "after" => nil, "limit" => 4})

    intent = %{
      "parent_invocation_id" => Ipse.Usage.id(),
      "operation_id" => Ipse.Usage.id(),
      "step" => 512,
      "request" => request
    }

    records =
      for n <- 1..4 do
        %{
          "key" => "notes.#{n}",
          "revision" => 4,
          "sha256" => Ipse.JSON.sha256("#{n}"),
          "bytes" => 6000,
          "operation_id" => Ipse.Usage.id(),
          "value" => %{"text" => String.duplicate("\n", 2990)}
        }
      end

    value = %{
      "version" => 3,
      "project" => Ipse.JSON.sha256("namespace"),
      "generation" => 4,
      "floor" => 0,
      "floor_anchor" => nil,
      "records" => records,
      "next" => "notes.4"
    }

    refute Call.reply_fits?(intent, value)
    assert {:ok, first} = Call.bound_scan(intent, value)
    assert length(first["records"]) in 1..3
    assert first["records"] == Enum.take(records, length(first["records"]))
    assert first["next"] == List.last(first["records"])["key"]
    assert Call.reply_fits?(intent, first)
    rest = Enum.drop(records, length(first["records"]))
    assert {:ok, second} = Call.bound_scan(intent, %{value | "records" => rest})
    assert first["records"] ++ second["records"] == records
    assert second["next"] == "notes.4"

    oversized = put_in(hd(records), ["value", "text"], String.duplicate("x", 8193))

    assert {:failed, %{"code" => "collection_result_limit"}} =
             Call.bound_scan(intent, %{value | "records" => [oversized]})
  end

  test "an imported lineage floor can exceed the local generation without being rewritten" do
    value = %{
      "version" => 3,
      "project" => Ipse.JSON.sha256("namespace"),
      "generation" => 1,
      "floor" => 9,
      "floor_anchor" => Ipse.Usage.id()
    }

    assert Call.valid_outcome?(call(%{"op" => "snapshot"}), "ok", value, Ipse.Usage.id())

    request =
      commit([change("notes.a", "value")]) |> put_in(["request", "expected_generation"], 1)

    receipt = %{
      "generation" => 2,
      "floor" => 10,
      "request_sha256" => Ipse.JSON.digest([request["request"]])
    }

    assert Call.valid_outcome?(request, "ok", receipt, Ipse.Usage.id())

    assert Call.bound_outcome?(%{
             "request" => request,
             "outcome" => %{"status" => "ok", "value" => receipt},
             "effect_binding" => %{"request_sha256" => receipt["request_sha256"]}
           })
  end
end
