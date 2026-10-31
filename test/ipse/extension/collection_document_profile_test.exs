defmodule Ipse.Extension.Collection.DocumentProfileTest do
  use ExUnit.Case, async: false
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.Collection
  alias Ipse.Extension.Collection.Profile

  setup do
    directory = Path.join(System.tmp_dir!(), "ipse-document-profile-" <> Usage.id())
    File.mkdir!(directory)
    File.chmod!(directory, 0o700)
    on_exit(fn -> File.rm_rf!(directory) end)

    %{
      directory: directory,
      root: Path.join(directory, "collections"),
      project: JSON.sha256("document fixture")
    }
  end

  defp commit(value) do
    %{
      "op" => "commit",
      "expected_generation" => 0,
      "advance_floor" => false,
      "changes" => [%{"key" => "packed.block", "expected_revision" => 0, "value" => value}]
    }
  end

  test "legacy notes roots cannot be reinterpreted under the document profile", c do
    assert {:ok, _} =
             Collection.execute(c.root, c.project, commit(%{"text" => "legacy"}), Usage.id())

    path = Path.join([c.root, c.project, "root.json"])
    before = File.read!(path)

    assert {:error, _} =
             Collection.execute_profile(
               c.root,
               c.project,
               %{"op" => "status"},
               Usage.id(),
               Profile.documents()
             )

    assert File.read!(path) == before

    assert {:ok, %{"records" => 1}} =
             Collection.execute(c.root, c.project, %{"op" => "status"}, Usage.id())
  end

  test "document root profile is hashed and large blocks remain bounded selected reads", c do
    value = %{"parts" => for(n <- 1..10, do: "#{n}:" <> String.duplicate("x", 4096))}
    assert byte_size(Jason.encode!(value)) > 16_384

    assert {:ok, _} =
             Collection.execute_profile(
               c.root,
               c.project,
               commit(value),
               Usage.id(),
               Profile.documents()
             )

    pointer = Jason.decode!(File.read!(Path.join([c.root, c.project, "root.json"])))
    assert pointer["storage_profile"] == Profile.documents()
    assert {:error, _} = Collection.execute(c.root, c.project, %{"op" => "status"}, Usage.id())

    assert {:ok, status} =
             Collection.execute_profile(
               c.root,
               c.project,
               %{"op" => "status"},
               Usage.id(),
               Profile.documents()
             )

    assert status["limits"]["notes_reserved_bytes"] == 64 * 1024 * 1024
    assert status["accounted_allocated_bytes"] == status["allocated_bytes"] + 64 * 1024 * 1024
    assert {:ok, view} = Collection.open_view_profile(c.root, c.project, Profile.documents())

    try do
      assert {:ok, read} =
               Collection.view_read(view, %{"op" => "get_many", "keys" => ["packed.block"]})

      assert [record] = read["records"]
      assert record["value"] == value

      assert read["witness"]["root_sha256"] ==
               JSON.sha256(File.read!(Path.join([c.root, c.project, "root.json"])))
    after
      assert :ok = Collection.close_view(view)
    end

    assert Collection.limits()["total_bytes"] == 64 * 1024 * 1024
  end

  test "profile selection does not raise SDK strings or accept caller budget fields", c do
    assert {:error, :invalid_collection_request} =
             Collection.execute_profile(
               c.root,
               c.project,
               commit(%{"text" => String.duplicate("x", 8193)}),
               Usage.id(),
               Profile.documents()
             )

    request = Map.put(commit(%{"text" => "bounded"}), "quota", 999_999_999)

    assert {:error, :invalid_collection_request} =
             Collection.execute_profile(
               c.root,
               c.project,
               request,
               Usage.id(),
               Profile.documents()
             )

    assert {:error, :unknown_collection_profile} =
             Collection.execute_profile(
               c.root,
               c.project,
               %{"op" => "status"},
               Usage.id(),
               "custom"
             )

    assert {:error, :invalid_transaction_request} =
             Ipse.Runner.Transaction.quota(nil, :collection, 192 * 1024 * 1024 + 1)
  end
end
