Code.require_file("../examples/knowledge/evaluation_inventory.exs", __DIR__)

defmodule Ipse.KnowledgeEvaluationInventoryTest do
  use ExUnit.Case, async: false
  alias Ipse.Extensions.{Manifest, State, Store}
  alias IpseKnowledgeExample.EvaluationInventory, as: Inventory

  test "audit validates actual bounded state and loads domain code only in its child" do
    root = Path.join(System.tmp_dir!(), "ipse-inventory-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    artifact = Path.join(root, "artifact")

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        [
          "extensions/knowledge/build.exs",
          "--sdk",
          Application.app_dir(:ipse, "ebin"),
          "--output",
          artifact,
          "--package",
          "corpus",
          "--preset",
          "state-lexical"
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    store = Path.join(root, "artifacts")
    assert {:ok, imported} = Store.import(artifact, store)
    namespace = String.duplicate("a", 64)
    state_root = Path.join(root, "state")
    path = Path.join([state_root, namespace, "state.json"])

    assert {:ok, absent} = Inventory.snapshot(path, store, imported.digest, "notes", root)
    assert absent["status"] == "absent" and absent["inventory"] == nil

    request = %{
      "op" => "state.put",
      "scope" => "project",
      "key" => "seed",
      "expected_revision" => 0,
      "value" => %{"private" => "synthetic private payload"}
    }

    assert {:ok, _} = State.execute(state_root, namespace, request, Ipse.Usage.id())
    original = File.read!(path)
    assert {:ok, report} = Inventory.snapshot(path, store, imported.digest, "notes", root)
    assert report["status"] == "verified"
    assert report["state_sha256"] == Manifest.sha256(original)
    assert report["state_file_bytes"] == byte_size(original)
    assert report["inventory"]["namespace_slots"] == 1
    assert report["inventory"]["other_live_records"]["records"] == 1
    assert report["inventory"]["selected_pages"]["records"] == 0
    refute JSON.encode!(report) =~ "synthetic private payload"
    assert File.read!(path) == original
    assert :code.is_loaded(IpseKnowledge.Store) == false

    altered = JSON.decode!(original) |> Map.put("generation", 2)
    File.write!(path, JSON.encode!(altered))

    assert {:error, :inventory_unavailable} =
             Inventory.snapshot(path, store, imported.digest, "notes", root)

    empty = %{"version" => 1, "namespace" => namespace, "generation" => 0.0, "records" => %{}}
    File.write!(path, JSON.encode!(empty))

    assert {:error, :inventory_unavailable} =
             Inventory.snapshot(path, store, imported.digest, "notes", root)

    File.write!(path, original)
    File.chmod!(path, 0o644)

    assert {:error, :inventory_unavailable} =
             Inventory.snapshot(path, store, imported.digest, "notes", root)
  end
end
