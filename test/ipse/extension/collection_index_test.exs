defmodule Ipse.Extension.CollectionIndexTest do
  use ExUnit.Case, async: false
  alias Ipse.Extension.{Collection, CollectionCall, SemanticAdmission}
  alias Ipse.{JSON, Usage}

  setup do
    home = Path.join(System.tmp_dir!(), "ipse-index-" <> Usage.id())
    File.mkdir!(home)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(home) end)
    namespace = JSON.sha256("synthetic metadata index")

    context = %{
      config: %{home: home},
      session_id: Usage.id(),
      index_scope: %{secret: :crypto.strong_rand_bytes(32), window: Usage.id(), generation: 1}
    }

    %{context: context, root: SemanticAdmission.collection_root(home), namespace: namespace}
  end

  defp request(cursor \\ nil, limit \\ 32, prefix \\ "note."),
    do: %{
      "op" => "collection.call",
      "request" => %{"op" => "index", "cursor" => cursor, "limit" => limit, "prefix" => prefix}
    }

  defp intent(c, request),
    do: %{
      "request" => request,
      "namespace" => c.namespace,
      "effect_binding" => %{"pin" => %{"synthetic" => true}}
    }

  defp commit(c, generation, keys) do
    Collection.execute(
      c.root,
      c.namespace,
      %{
        "op" => "commit",
        "expected_generation" => generation,
        "advance_floor" => false,
        "changes" =>
          Enum.map(
            keys,
            &%{
              "key" => &1,
              "expected_revision" => 0,
              "value" => %{"text" => "NEVER_METADATA_NOTE_VALUE"}
            }
          )
      },
      Usage.id()
    )
  end

  test "index requests close their shape and exclude private metadata prefixes" do
    assert :ok = CollectionCall.validate(request())

    for invalid <- [
          request(nil, 33),
          request(nil, 0),
          request(nil, 1, "host.validity."),
          put_in(request(), ["request", "cursor"], String.duplicate("x", 2049)),
          put_in(request(), ["request", "extra"], true)
        ] do
      assert {:error, :invalid_extension_collection_call} = CollectionCall.validate(invalid)
    end
  end

  @tag :native_storage
  test "native metadata pages contain no values, fit 4KiB and cover every public key", c do
    keys = for n <- 1..32, do: "note." <> JSON.sha256(Integer.to_string(n))
    assert {:ok, _} = commit(c, 0, keys)
    owner = self()
    handler = "index-no-values-" <> Usage.id()

    :ok =
      :telemetry.attach(
        handler,
        [:ipse, :extension, :collection, :view_index],
        fn _, measurements, _, _ -> send(owner, {:index_measurements, measurements}) end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    walk = fn walk, cursor, seen ->
      req = request(cursor)
      assert {:ok, observation} = CollectionCall.index_observation(c.context, intent(c, req))
      page = observation["value"]
      assert CollectionCall.valid_outcome?(req, "ok", page, nil)
      assert byte_size(Jason.encode!(page)) <= 4096
      assert page["count"] == 32
      assert page["coverage"] == "metadata_only"
      refute Jason.encode!(page) =~ "NEVER_METADATA_NOTE_VALUE"

      assert Enum.all?(
               page["records"],
               &(Enum.sort(Map.keys(&1)) == ~w(bytes key revision sha256))
             )

      assert_receive {:index_measurements, %{value_reads: 0}}
      next = seen ++ Enum.map(page["records"], & &1["key"])
      if page["next"], do: walk.(walk, page["next"], next), else: next
    end

    assert walk.(walk, nil, []) == Enum.sort(keys)
  end

  @tag :native_storage
  test "cursors bind the exact Session window, pin, prefix and current collection root", c do
    assert {:ok, _} = commit(c, 0, ["note.a", "note.b"])
    assert {:ok, first} = CollectionCall.index_observation(c.context, intent(c, request(nil, 1)))
    cursor = first["value"]["next"]
    assert is_binary(cursor)
    req = request(cursor, 1)
    assert {:ok, second} = CollectionCall.index_observation(c.context, intent(c, req))
    assert Enum.map(second["value"]["records"], & &1["key"]) == ["note.b"]

    for context <- [
          %{c.context | session_id: Usage.id()},
          put_in(c.context, [:index_scope, :window], Usage.id()),
          put_in(c.context, [:index_scope, :generation], 2),
          put_in(c.context, [:index_scope, :secret], :crypto.strong_rand_bytes(32))
        ] do
      assert {:error, :collection_source_refused} =
               CollectionCall.index_observation(context, intent(c, req))
    end

    changed_pin = put_in(intent(c, req), ["effect_binding", "pin"], %{"synthetic" => false})

    assert {:error, :collection_source_refused} =
             CollectionCall.index_observation(c.context, changed_pin)

    assert {:error, :collection_source_refused} =
             CollectionCall.index_observation(
               c.context,
               intent(c, request(cursor, 1, "other."))
             )

    assert {:ok, _} = commit(c, 1, ["note.c"])

    assert {:error, :collection_source_refused} =
             CollectionCall.index_observation(c.context, intent(c, req))
  end
end
