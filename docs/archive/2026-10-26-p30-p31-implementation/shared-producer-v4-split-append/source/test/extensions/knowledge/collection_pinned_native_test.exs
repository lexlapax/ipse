defmodule Ipse.CollectionPinnedNativeTest do
  use ExUnit.Case, async: false
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.Collection
  alias Ipse.Extension.Collection.DocumentStage
  alias IpseKnowledge.Store.Collection, as: C

  @tag :pinned_native_stale
  @tag timeout: 120_000
  test "pinned anchor and multipart reads refuse an intervening native commit" do
    parent = Path.join(System.tmp_dir!(), "ipse-pinned-read-" <> Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    root = Path.join(parent, "collections")
    namespace = JSON.sha256("synthetic pinned native read")

    owner = %{
      "project_id" => JSON.sha256("synthetic pinned project"),
      "identity_sha256" => JSON.sha256("synthetic pinned identity"),
      "session_id" => Usage.id(),
      "invocation_id" => Usage.id()
    }

    profile = %{"kind" => "collection", "scope" => "project", "partition" => "notes"}
    bytes = IO.iodata_to_binary(Elixir.JSON.encode!(%{"text" => String.duplicate("x", 7000)}))
    key = "synthetic.anchor"

    assert {:ok, %{"generation" => 1}} =
             DocumentStage.execute(root, namespace, put(key, bytes, 0), Usage.id(), owner)

    {:call, stat, continuation} =
      C.start(profile, :value_read_at, %{"key" => key, "generation" => 1})

    assert stat["request"]["op"] == "value.stat"

    {:ok, stat_result} =
      DocumentStage.execute(root, namespace, stat["request"], Usage.id(), owner)

    {:call, read, continuation} = C.resume(continuation, wrapped(stat, stat_result))
    assert read["request"]["generation"] == 1

    assert {:ok, %{"generation" => 2}} =
             DocumentStage.execute(
               root,
               namespace,
               put("synthetic.noise1", "{}", 1),
               Usage.id(),
               owner
             )

    assert {:error, :document_store_refused} =
             DocumentStage.execute(root, namespace, read["request"], Usage.id(), owner)

    assert {:done, {:error, :collection_refused, _}} =
             C.resume(continuation, %{
               "status" => "failed",
               "value" => %{"code" => "document_store_refused"}
             })

    {:call, stale_ref, stale_cont} =
      C.start(profile, :value_read_ref_at, %{
        "key" => key,
        "sha256" => JSON.sha256(bytes),
        "generation" => 1
      })

    assert {:error, :document_store_refused} =
             DocumentStage.execute(root, namespace, stale_ref["request"], Usage.id(), owner)

    assert {:done, {:error, :collection_refused, _}} =
             C.resume(stale_cont, %{
               "status" => "failed",
               "value" => %{"code" => "document_store_refused"}
             })

    {:call, wrong_ref, wrong_cont} =
      C.start(profile, :value_read_ref_at, %{
        "key" => key,
        "sha256" => String.duplicate("a", 64),
        "generation" => 2
      })

    assert {:ok, wrong_result} =
             DocumentStage.execute(root, namespace, wrong_ref["request"], Usage.id(), owner)

    assert {:done, {:error, :collection_response, _}} =
             C.resume(wrong_cont, wrapped(wrong_ref, wrong_result))

    ref = %{
      "key" => key,
      "sha256" => JSON.sha256(bytes),
      "byte_count" => byte_size(bytes),
      "generation" => 2,
      "revision" => 1
    }

    {:call, first, continuation} = C.start(profile, :object_read, ref)

    {:ok, first_result} =
      DocumentStage.execute(root, namespace, first["request"], Usage.id(), owner)

    assert is_integer(first_result["next"])
    {:call, second, continuation} = C.resume(continuation, wrapped(first, first_result))
    assert second["request"]["generation"] == 2

    assert {:ok, %{"generation" => 3}} =
             DocumentStage.execute(
               root,
               namespace,
               put("synthetic.noise2", "{}", 2),
               Usage.id(),
               owner
             )

    assert {:error, :document_store_refused} =
             DocumentStage.execute(root, namespace, second["request"], Usage.id(), owner)

    assert {:done, {:error, :collection_refused, _}} =
             C.resume(continuation, %{
               "status" => "failed",
               "value" => %{"code" => "document_store_refused"}
             })

    assert {:ok, :verified} =
             Collection.with_document_read(root, namespace, fn witness, read ->
               assert witness["root"]["generation"] == 3

               assert {:ok, %{"value" => %{"text" => text}, "revision" => 1}} =
                        DocumentStage.read_value(read, key)

               assert byte_size(text) == 7000
               {:ok, :verified}
             end)

    IO.puts("Retained synthetic pinned-read native store: " <> parent)
  end

  defp put(key, data, generation),
    do: %{
      "op" => "value.put_inline",
      "key" => key,
      "expected_revision" => 0,
      "generation" => generation,
      "data" => data,
      "sha256" => JSON.sha256(data),
      "byte_count" => byte_size(data)
    }

  defp wrapped(request, result),
    do: %{
      "status" => "ok",
      "value" => %{
        "version" => 1,
        "operation_id" => Usage.id(),
        "request_sha256" => JSON.digest([request]),
        "result" => result
      }
    }
end
