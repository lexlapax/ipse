defmodule Ipse.Extension.Collection.WorkspaceDocumentGuardTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.Collection.WorkspaceDocumentGuard, as: Guard

  defp guard do
    %{
      "path" => "source.docx",
      "original_sha256" => String.duplicate("a", 64),
      "opening_operation_id" => String.duplicate("b", 32),
      "source_id" => "workspace:source",
      "generation" => 1,
      "bundle_sha256" => String.duplicate("c", 64)
    }
  end

  defp request(inner),
    do: %{
      "op" => "collection.store",
      "scope" => "project",
      "request" => inner,
      "workspace_guard" => guard()
    }

  test "each publication form requires one exact source binding for workspace preflight" do
    for inner <- [
          %{"op" => "commit"},
          %{"op" => "value.put_inline"},
          %{"op" => "value.write_parts", "publish" => true}
        ] do
      request = request(inner)
      assert Guard.guarded_request?(request)
      assert {:ok, read} = Guard.preflight_read(request)
      assert read["arguments"]["path"] == "source.docx"
      assert read["arguments"]["expected_sha256"] == String.duplicate("a", 64)
      refute Guard.guarded_request?(Map.delete(request, "workspace_guard"))

      refute Guard.guarded_request?(
               put_in(request, ["workspace_guard", "opening_operation_id"], "forged")
             )

      refute Guard.guarded_request?(
               put_in(request, ["workspace_guard", "original_sha256"], "wrong")
             )
    end

    refute Guard.guarded_request?(request(%{"op" => "value.write_parts", "publish" => false}))
  end

  test "shipped bundle selection uses the exact host catalog digest" do
    shipped = String.duplicate("a", 64)
    other = String.duplicate("b", 64)
    bundles = [%{id: "corpus-collection-documents", digest: shipped}]
    assert Guard.selected_bundle?(%{"artifact_sha256" => shipped}, bundles)
    refute Guard.selected_bundle?(%{"artifact_sha256" => other}, bundles)

    refute Guard.selected_bundle?(%{"artifact_sha256" => shipped}, [
             %{id: "other", digest: shipped}
           ])
  end

  test "a Corpus source cannot fall back to generic behavior without the shipped catalog entry" do
    sha = String.duplicate("a", 64)
    identity = %{"artifact_sha256" => sha}

    assert {:error, :document_guard_unconfirmed} =
             Guard.bundle_selection(identity, "ipse-knowledge/corpus", {:error, :unavailable})

    assert {:error, :document_guard_unconfirmed} =
             Guard.bundle_selection(identity, "ipse-knowledge/corpus", {:ok, []})

    entry = %{id: "corpus-collection-documents", digest: sha}
    assert {:ok, true} = Guard.bundle_selection(identity, "ipse-knowledge/corpus", {:ok, [entry]})

    assert {:ok, false} =
             Guard.bundle_selection(
               %{"artifact_sha256" => String.duplicate("b", 64)},
               "ipse-knowledge/corpus",
               {:ok, [entry]}
             )

    assert {:ok, false} =
             Guard.bundle_selection(identity, "another-extension", {:error, :unavailable})
  end

  test "workspace and supplied-document invocations cannot relabel a source as ordinary" do
    session = fn action, args ->
      %{
        invocation: %{
          parent: %{
            "descriptor" => %{"id" => "source"},
            "payload" => %{"arguments" => %{"action" => action, "args" => args}}
          }
        }
      }
    end

    for action <- ~w(read_document continue_collection_document put_document) do
      assert {:error, :document_store_refused} =
               Guard.authorize(
                 session.(action, %{}),
                 %{"request" => %{}},
                 :not_workspace_document
               )
    end

    assert {:error, :document_store_refused} =
             Guard.authorize(
               session.("continue_collection_source", %{"input_action" => "put_document"}),
               %{"request" => %{}},
               :not_workspace_document
             )

    assert {:ok, :other_source} =
             Guard.authorize(session.("put", %{}), %{"request" => %{}}, :not_workspace_document)
  end

  test "a non-head source value is inspected and cannot bypass a workspace document invocation" do
    bytes = Jason.encode!(%{"kind" => "not_a_source_head"})

    packed = %{
      "version" => 1,
      "kind" => "document_value",
      "byte_count" => byte_size(bytes),
      "sha256" => Ipse.JSON.sha256(bytes),
      "parts" => [bytes]
    }

    change = %{
      "key" => "source.notes." <> String.duplicate("a", 64),
      "expected_revision" => 0,
      "value" => packed
    }

    assert {:ok, [:not_workspace_document]} =
             Guard.inspect_changes([change], fn _ -> {:ok, nil} end, String.duplicate("b", 32))

    session = %{
      invocation: %{
        parent: %{
          "descriptor" => %{"id" => "source"},
          "payload" => %{"arguments" => %{"action" => "read_document", "args" => %{}}}
        }
      }
    }

    assert {:error, :document_store_refused} =
             Guard.authorize(session, %{"request" => %{}}, :not_workspace_document)
  end
end
