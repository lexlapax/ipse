defmodule Ipse.Extension.CollectionUnmanagedTest do
  use ExUnit.Case, async: false
  alias Ipse.Extension.Collection

  test "the legacy operation and managed-marker refusal share the current native transaction" do
    parent = Path.join(System.tmp_dir!(), "ipse-unmanaged-boundary-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)
    root = Path.join(parent, "collections")
    project = Ipse.JSON.sha256("unmanaged-boundary")
    call = fn request -> Collection.execute_unmanaged(root, project, request, Ipse.Usage.id()) end
    change = fn key, value -> %{"key" => key, "expected_revision" => 0, "value" => value} end

    commit = fn generation, changes ->
      %{
        "op" => "commit",
        "expected_generation" => generation,
        "advance_floor" => false,
        "changes" => changes
      }
    end

    assert {:ok, _} = call.(commit.(0, [change.("legacy", %{"text" => "legacy"})]))

    assert {:ok, %{"record" => %{"value" => %{"text" => "legacy"}}}} =
             call.(%{"op" => "get", "key" => "legacy"})

    assert {:ok, _} =
             Collection.execute(
               root,
               project,
               commit.(1, [change.("host.validity.format", %{"format" => "reserved"})]),
               Ipse.Usage.id()
             )

    for request <- [
          %{"op" => "get", "key" => "legacy"},
          %{"op" => "scan", "generation" => 2, "after" => nil, "limit" => 4},
          %{"op" => "snapshot"},
          commit.(2, [change.("later", %{"text" => "must not write"})])
        ] do
      assert {:error, :collection_managed_namespace} = call.(request)
    end

    assert {:ok, %{"record" => nil}} =
             Collection.execute(
               root,
               project,
               %{"op" => "get", "key" => "later"},
               Ipse.Usage.id()
             )
  end
end
