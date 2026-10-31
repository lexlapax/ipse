defmodule Ipse.Extension.CollectionDocumentHeldValueTest do
  use ExUnit.Case, async: false
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.Collection
  alias Ipse.Extension.Collection.{DocumentStage, Profile}

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-document-held-value-" <> Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)
    %{root: parent <> "/collections", namespace: JSON.sha256("held logical fixture")}
  end

  defp packed(body) do
    pieces =
      Stream.unfold(body, fn
        "" ->
          nil

        rest ->
          n = min(byte_size(rest), 6144)
          {binary_part(rest, 0, n), binary_part(rest, n, byte_size(rest) - n)}
      end)
      |> Enum.to_list()

    %{
      "version" => 1,
      "kind" => "document_value",
      "parts" => pieces,
      "sha256" => JSON.sha256(body),
      "byte_count" => byte_size(body)
    }
  end

  test "complete logical read retains actual native operation and logical rather than physical hash",
       c do
    owner = %{
      "project_id" => JSON.sha256("fixture project"),
      "session_id" => Usage.id(),
      "identity_sha256" => JSON.sha256("fixture identity"),
      "invocation_id" => Usage.id()
    }

    body = Jason.encode!(%{"text" => "synthetic whole logical value"})
    operation = Usage.id()

    assert {:ok, %{"generation" => 1}} =
             DocumentStage.execute(
               c.root,
               c.namespace,
               %{
                 "op" => "value.put_inline",
                 "key" => "source.fixture",
                 "expected_revision" => 0,
                 "byte_count" => byte_size(body),
                 "sha256" => JSON.sha256(body),
                 "data" => body,
                 "generation" => 0
               },
               operation,
               owner
             )

    assert {:ok, read} =
             Collection.with_document_read(c.root, c.namespace, fn _, read ->
               assert {:ok, row} = DocumentStage.read_value(read, "source.fixture")
               assert row["key"] == "source.fixture"
               assert row["revision"] == 1 and row["operation_id"] == operation
               assert row["sha256"] == JSON.sha256(body) and row["byte_count"] == byte_size(body)
               assert row["value"] == Jason.decode!(body)
               assert {:ok, physical} = read.("source.fixture")
               refute physical["sha256"] == row["sha256"]
               assert {:ok, nil} = DocumentStage.read_value(read, "absent")
               {:ok, read}
             end)

    assert {:error, :document_store_refused} = DocumentStage.read_value(read, "source.fixture")
  end

  test "large complete packed objects decode but bad hashes and duplicate bodies refuse", c do
    logical = %{"pieces" => List.duplicate(String.duplicate("x", 4096), 10)}
    good = packed(Jason.encode!(logical))

    values = [
      {"data.good", good},
      {"data.hash", %{good | "sha256" => String.duplicate("0", 64)}},
      {"data.duplicate", packed(~s({"text":"first","text":"second"}))},
      {"data.extra", Map.put(good, "untrusted", true)}
    ]

    assert {:ok, _} =
             Collection.execute_profile(
               c.root,
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" =>
                   Enum.map(values, fn {key, value} ->
                     %{"key" => key, "expected_revision" => 0, "value" => value}
                   end)
               },
               Usage.id(),
               Profile.documents()
             )

    assert {:ok, :checked} =
             Collection.with_document_read(c.root, c.namespace, fn _, read ->
               assert {:ok, row} = DocumentStage.read_value(read, "data.good")
               assert row["value"] == logical
               assert row["byte_count"] > 16_384

               for key <- ~w(data.hash data.duplicate data.extra),
                   do:
                     assert(
                       {:error, :document_store_refused} = DocumentStage.read_value(read, key)
                     )

               {:ok, :checked}
             end)
  end
end
