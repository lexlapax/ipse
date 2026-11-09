defmodule Ipse.Extension.CollectionReviewGateTest do
  use ExUnit.Case, async: true
  @moduletag :native_storage
  alias Ipse.Extension.Collection
  alias Ipse.JSON

  # These trusted callbacks exercise the storage fence only. Genuine input,
  # one-use Review and signed normalization belong to the management journey.
  test "retention and supersession remain fenced without advancing the root or operation ledger" do
    parent = Path.join(System.tmp_dir!(), "ipse-review-fence-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)
    root = Path.join(parent, "collections")
    namespace = JSON.sha256("synthetic retained review fences")

    request = %{
      "op" => "commit",
      "expected_generation" => 0,
      "advance_floor" => true,
      "changes" => [
        %{"key" => "note.a", "expected_revision" => 0, "value" => %{"text" => "fixture"}}
      ]
    }

    normalized =
      Map.update!(request, "changes", fn changes ->
        changes ++
          [
            %{
              "key" => "host.validity.a",
              "expected_revision" => 0,
              "value" => %{"anchor" => 0}
            }
          ]
      end)

    for kind <- ~w(native_literal_retention native_literal_supersession native_pending_correction) do
      operation = Ipse.Usage.id()

      assert {:error, :native_review_publication_fence_unavailable} =
               Collection.execute_managed(
                 root,
                 namespace,
                 request,
                 operation,
                 JSON.sha256("fixture recipe"),
                 fn _, _ -> {:ok, normalized, %{"version" => 3, "kind" => kind}} end
               )

      assert {:ok, %{"generation" => 0, "floor" => 0}} =
               Collection.execute(root, namespace, %{"op" => "snapshot"}, Ipse.Usage.id())

      assert {:ok, %{"operation" => nil}} =
               Collection.execute(
                 root,
                 namespace,
                 %{"op" => "inspect", "operation_id" => operation},
                 Ipse.Usage.id()
               )

      refute File.exists?(Path.join([root, namespace, "root.json"]))
    end
  end
end
