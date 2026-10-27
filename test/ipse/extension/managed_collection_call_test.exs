Code.require_file("../../support/managed_policy.exs", __DIR__)

defmodule Ipse.Extension.ManagedCollectionCallTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.{Collection, CollectionCall, ManagedCollectionCall}
  alias Ipse.JSON

  test "SDK1 and SDK2 need the separate declared capability with host actions" do
    request = request()
    response = %{"api_version" => 1, "kind" => "host_call", "request" => request}
    old = Ipse.Test.ManagedPolicy.identity()
    assert {:error, _} = Ipse.Extension.Actions.proposal(response, old)

    for sdk <- [1, 2] do
      capabilities = ["host.collection.managed" | old["capabilities"]]

      capabilities =
        if sdk == 1, do: List.delete(capabilities, "invoke.result.pages"), else: capabilities

      identity = Map.merge(old, %{"sdk" => sdk, "capabilities" => capabilities})
      assert {:ok, ^request} = Ipse.Extension.Actions.proposal(response, identity)

      assert {:error, _} =
               Ipse.Extension.Catalog.validate(
                 Ipse.Extension.Catalog.empty(),
                 List.delete(capabilities, "host.actions")
               )
    end
  end

  defp request do
    %{
      "op" => "collection.managed",
      "recipe_sha256" => JSON.sha256("recipe"),
      "request" => %{
        "op" => "commit",
        "expected_generation" => 0,
        "advance_floor" => true,
        "changes" => [
          %{"key" => "pending.a", "expected_revision" => 0, "value" => %{"text" => "observation"}}
        ]
      },
      "proofs" => [%{"handle" => "opaque", "quote" => "observation"}]
    }
  end

  test "managed selection is explicit, bounded and cannot expose or overwrite host metadata" do
    r = request()
    assert :ok = ManagedCollectionCall.validate(r)
    assert ManagedCollectionCall.capability(r) == "host.collection.managed"

    for changed <- [
          Map.delete(r, "proofs"),
          Map.delete(r, "recipe_sha256"),
          Map.put(r, "origin", "interactive_operator"),
          Map.put(r, "actual", %{"input_bytes" => 0}),
          Map.put(r, "cost", 0),
          put_in(r, ["request", "advance_floor"], false),
          put_in(r, ["request", "changes", Access.at(0), "key"], "host.validity.live.000.0"),
          Map.put(r, "recipe_sha256", "unreviewed"),
          Map.put(r, "proofs", [])
        ] do
      assert {:error, _} = ManagedCollectionCall.validate(changed)
    end

    for inner <- [
          %{"op" => "get", "key" => "host.validity.anchor.00.0"},
          %{
            "op" => "scan",
            "generation" => 0,
            "limit" => 4,
            "after" => "host.validity.live.000.0"
          },
          put_in(r["request"], ["changes", Access.at(0), "key"], "host.validity.a")
        ] do
      call = %{"op" => "collection.call", "request" => inner}
      call = if inner["op"] == "commit", do: Map.put(call, "proofs", r["proofs"]), else: call
      assert {:error, _} = CollectionCall.validate(call)
    end

    assert :ok =
             CollectionCall.validate(%{
               "op" => "collection.call",
               "request" => %{"op" => "get", "key" => "pending.public"}
             })

    assert :ok =
             CollectionCall.validate(%{
               "op" => "collection.call",
               "request" => %{
                 "op" => "scan",
                 "generation" => 0,
                 "after" => "pending.public",
                 "limit" => 4
               }
             })
  end

  test "reservation includes maximum escaped sidecars, safe integer revisions and exact envelopes" do
    r = request()
    charge = ManagedCollectionCall.reservation(r)
    value = %{"text" => String.duplicate(<<0>>, 1022)}
    assert byte_size(Jason.encode!(value)) <= 6144
    # Fill the value to exactly the admitted 6144 encoded bytes without changing its escaping.
    value =
      Map.put(
        value,
        "text",
        value["text"] <> String.duplicate("x", 6144 - byte_size(Jason.encode!(value)))
      )

    assert byte_size(Jason.encode!(value)) == 6144

    changes =
      for n <- 1..2,
          do: %{
            "key" => String.duplicate("k", 95) <> Integer.to_string(n),
            "expected_revision" => 9_007_199_254_740_991,
            "value" => value
          }

    normalized = Map.update!(r["request"], "changes", &(&1 ++ changes))
    measured = byte_size(Jason.encode!(normalized)) + 2048
    assert measured <= charge["input_bytes"]

    assert charge["input_bytes"] ==
             byte_size(Jason.encode!(r)) +
               2 * (6144 + byte_size(Jason.encode!(hd(changes))) - 6144 + 1) + 2048

    assert charge["operations"] == 1 and charge["output_bytes"] == 16_384
    assert Collection.valid_request?(normalized)
  end

  test "private scan excludes metadata before selection and preserves exact public continuation" do
    parent = Path.join(System.tmp_dir!(), "ipse-sdk-visible-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)
    root = Path.join(parent, "collections")
    namespace = JSON.sha256("visible fixture")

    changes =
      for key <- ["a", "host.validity.anchor.00.0", "host.validity.live.000.0", "z"],
          do: %{"key" => key, "expected_revision" => 0, "value" => %{"text" => key}}

    commit = %{
      "op" => "commit",
      "expected_generation" => 0,
      "advance_floor" => false,
      "changes" => changes
    }

    assert {:ok, _} = Collection.execute(root, namespace, commit, Ipse.Usage.id())
    scan = %{"op" => "scan", "generation" => 1, "after" => nil, "limit" => 1}
    assert {:ok, first} = Collection.scan_visible(root, namespace, scan, Ipse.Usage.id())
    assert Enum.map(first["records"], & &1["key"]) == ["a"]
    assert first["next"] == "a"

    assert {:ok, last} =
             Collection.scan_visible(root, namespace, %{scan | "after" => "a"}, Ipse.Usage.id())

    assert Enum.map(last["records"], & &1["key"]) == ["z"]
    assert last["next"] == nil

    assert {:error, _} =
             Collection.scan_visible(
               root,
               namespace,
               %{scan | "after" => "host.validity.a"},
               Ipse.Usage.id()
             )

    # An operator/raw collection read remains available and is deliberately separate from SDK visibility.
    assert {:ok, %{"record" => %{"key" => "host.validity.anchor.00.0"}}} =
             Collection.execute(
               root,
               namespace,
               %{"op" => "get", "key" => "host.validity.anchor.00.0"},
               Ipse.Usage.id()
             )

    hidden = JSON.sha256("only metadata")

    assert {:ok, _} =
             Collection.execute(
               root,
               hidden,
               %{commit | "changes" => [Enum.at(changes, 1)]},
               Ipse.Usage.id()
             )

    assert {:ok, empty} = Collection.scan_visible(root, hidden, scan, Ipse.Usage.id())
    assert empty["records"] == [] and empty["next"] == nil
  end

  test "status controls disclose bounded identities and digests without reserved plan keys" do
    request = %{"op" => "collection.call", "request" => %{"op" => "status"}}

    intent = %{
      "request" => request,
      "parent_invocation_id" => Ipse.Usage.id(),
      "operation_id" => Ipse.Usage.id(),
      "step" => 1
    }

    migration = %{
      "id" => Ipse.Usage.id(),
      "after" => "host.validity.live.000.0",
      "plan" => List.duplicate("host.validity.anchor.00.0", 8192)
    }

    assert {:ok, projected} =
             CollectionCall.bound_status(intent, %{"migration" => migration, "checkpoint" => nil})

    assert projected["migration"] == %{
             "id" => migration["id"],
             "sha256" => JSON.digest([migration])
           }

    refute Jason.encode!(projected) =~ "host.validity."
    assert byte_size(Jason.encode!(projected)) < 256
  end
end
