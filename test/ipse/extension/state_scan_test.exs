defmodule Ipse.Extension.StateScanTest do
  use ExUnit.Case, async: false
  alias Ipse.Extension.{Actions, Catalog, State}

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-state-scan-" <> Ipse.Usage.id())
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, namespace: String.duplicate("a", 64)}
  end

  defp scan(after_key \\ nil, generation \\ nil),
    do: %{
      "op" => "state.scan",
      "scope" => "project",
      "after" => after_key,
      "generation" => generation,
      "limit" => 16
    }

  defp run(ctx, request) do
    id = Ipse.Usage.id()
    {status, value} = State.execute(ctx.root, ctx.namespace, request, id)
    assert State.valid_outcome?(request, to_string(status), value, id)
    {status, value}
  end

  test "value pages fit callback bounds, pin a generation and retain tombstones", ctx do
    for n <- 1..3 do
      run(ctx, %{
        "op" => "state.put",
        "scope" => "project",
        "key" => "key#{n}",
        "expected_revision" => 0,
        "value" => %{"text" => String.duplicate("x", 7900)}
      })
    end

    assert {:ok, page} = run(ctx, scan())
    assert length(page["records"]) == 1
    assert page["next"] == "key1"
    assert byte_size(Jason.encode!(page)) < 12_500
    assert Ipse.Extension.validate(%{"outcome" => %{"status" => "ok", "value" => page}}) == :ok
    assert {:ok, second} = run(ctx, scan(page["next"], page["generation"]))
    assert second["next"] == "key2"

    run(ctx, %{
      "op" => "state.delete",
      "scope" => "project",
      "key" => "key3",
      "expected_revision" => 1
    })

    assert {:conflict, _} = run(ctx, scan(second["next"], second["generation"]))
    assert {:ok, final} = run(ctx, scan("key2"))
    assert [%{"deleted" => true, "value" => nil}] = final["records"]
    assert final["next"] == nil
    refute State.valid_outcome?(scan(), "ok", %{page | "next" => "other"}, Ipse.Usage.id())
    [record] = page["records"]

    refute State.valid_outcome?(
             scan(),
             "ok",
             %{page | "records" => [Map.delete(record, "value")]},
             Ipse.Usage.id()
           )

    refute State.valid_outcome?(
             scan(),
             "ok",
             %{page | "records" => [Map.put(record, "extra", true)]},
             Ipse.Usage.id()
           )

    refute State.valid_outcome?(
             scan(),
             "ok",
             %{page | "records" => [], "next" => "key1"},
             Ipse.Usage.id()
           )
  end

  test "extended read work is separately granted and never extends effectful action steps" do
    identity = %{
      "capabilities" => ~w(host.actions host.state.read host.state.scan host.state.write)
    }

    assert Actions.limit(identity) == 512
    assert Actions.limit(identity, scan()) == 512
    assert Actions.limit(identity, %{"op" => "state.get"}) == 512
    assert Actions.limit(identity, %{"op" => "state.put"}) == 16
    assert Actions.limit(identity, %{"op" => "model.complete"}) == 16
    assert Actions.limit(identity, %{"op" => "usage.read"}) == 16
    assert Catalog.validate(Catalog.empty(), ~w(host.actions host.state.scan)) != :ok

    assert Catalog.validate(Catalog.empty(), ~w(host.actions host.state.read host.state.scan)) ==
             :ok

    assert State.validate(Map.put(scan(), "limit", 17)) != :ok
    assert State.validate(Map.put(scan(), "path", "/tmp")) != :ok
    assert State.capability(scan()) == "host.state.scan"
  end
end
