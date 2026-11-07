defmodule Ipse.Extension.Collection.DocumentDraftNativeTest do
  use ExUnit.Case, async: false

  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.{Collection, CollectionStore}
  alias Ipse.Extension.Collection.DocumentStage

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-document-draft-" <> Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)

    owner = %{
      "project_id" => JSON.sha256("draft native project"),
      "session_id" => Usage.id(),
      "identity_sha256" => JSON.sha256("draft native artifact"),
      "invocation_id" => Usage.id()
    }

    %{
      root: Path.join(parent, "collections"),
      ns: CollectionStore.namespace(owner["project_id"]),
      owner: owner
    }
  end

  defp snapshot(c) do
    assert {:ok, state} = Collection.document_snapshot(c.root, c.ns)
    state
  end

  defp fence(c) do
    state = snapshot(c)

    open = %{
      "op" => "maintenance.open",
      "expected_generation" => state["generation"],
      "expected_epoch" => state["document_maintenance"]["epoch"],
      "maintenance_id" => Usage.id(),
      "purpose" => "checkpoint_inspection",
      "close_operation_id" => Usage.id()
    }

    assert {:ok, _} = Collection.document_maintenance(c.root, c.ns, open, Usage.id(), c.owner)
    state = snapshot(c)

    close = %{
      "op" => "maintenance.close",
      "expected_generation" => state["generation"],
      "expected_epoch" => state["document_maintenance"]["epoch"],
      "maintenance_id" => open["maintenance_id"]
    }

    assert {:ok, _} =
             Collection.document_maintenance(
               c.root,
               c.ns,
               close,
               open["close_operation_id"],
               c.owner
             )
  end

  defp call(c, request, id \\ Usage.id()) do
    state = snapshot(c)
    request = Map.put(request, "generation", state["generation"])
    epoch = state["document_maintenance"]["epoch"]
    request = if epoch > 0, do: Map.put(request, "maintenance_epoch", epoch), else: request
    {DocumentStage.execute(c.root, c.ns, request, id, c.owner), request, id}
  end

  defp inline(key, bytes) do
    %{
      "op" => "value.put_inline",
      "key" => key,
      "expected_revision" => 0,
      "byte_count" => byte_size(bytes),
      "sha256" => JSON.sha256(bytes),
      "data" => bytes
    }
  end

  defp start(limit) do
    %{
      "version" => 1,
      "action" => "start",
      "kind" => "projection",
      "plan_sha256" => JSON.sha256("fixed plan"),
      "body_sha256" => JSON.sha256("fixed body"),
      "unit_limit" => limit
    }
  end

  defp continuation(progress, action \\ "continue") do
    %{
      "version" => 1,
      "action" => action,
      "head_id" => progress["head_id"],
      "revision" => progress["revision"],
      "unit" => progress["unit"]
    }
  end

  test "verified first reuse and stage changes atomically advance the real head", c do
    original = Jason.encode!(%{"text" => "original"})
    {{:ok, seeded}, _, _} = call(c, inline("document.original", original))
    fence(c)
    before = snapshot(c)

    verify = %{
      "op" => "value.verify",
      "key" => "document.original",
      "expected_revision" => seeded["generation"],
      "byte_count" => byte_size(original),
      "sha256" => JSON.sha256(original),
      "progress" => start(3)
    }

    {{:ok, verified}, actual, id} = call(c, verify)
    assert verified["generation"] == before["generation"] + 1

    assert verified["request_sha256"] ==
             JSON.digest([
               %{"op" => "collection.store", "scope" => "project", "request" => actual}
             ])

    progress = verified["document_progress"]
    assert progress["head_id"] == id
    assert progress["unit"] == 1
    assert length(progress["slots"]) == 2

    slot = hd(progress["slots"])
    body = Jason.encode!(%{"text" => "two parts"})
    split = div(byte_size(body), 2)

    request = %{
      "op" => "value.write_parts",
      "slot" => slot,
      "epoch" => Usage.id(),
      "key" => "document.next",
      "expected_revision" => 0,
      "byte_count" => byte_size(body),
      "sha256" => JSON.sha256(body),
      "offset" => 0,
      "data" => [binary_part(body, 0, split)],
      "publish" => true,
      "progress" => continuation(progress)
    }

    {{:ok, partial}, _, _} = call(c, request)
    assert partial["document_progress"]["unit"] == 1
    assert partial["document_progress"]["revision"] > progress["revision"]

    {{:ok, _}, _, _} = call(c, inline("document.competing", Jason.encode!(%{"x" => 1})))

    stale = %{
      request
      | "offset" => split,
        "data" => [binary_part(body, split, byte_size(body) - split)]
    }

    {{:error, _}, _, _} = call(c, stale)
    last = %{stale | "progress" => continuation(partial["document_progress"])}
    {{:ok, complete}, _, _} = call(c, last)
    assert complete["document_progress"]["unit"] == 2

    assert complete["document_progress"]["revision"] >
             partial["document_progress"]["revision"] + 1

    metadata = Jason.encode!(%{"metadata" => true})

    prepare =
      inline("document.metadata", metadata)
      |> Map.put("op", "value.prepare_inline")
      |> Map.put("slot", slot)
      |> Map.put("epoch", Usage.id())
      |> Map.put("progress", continuation(complete["document_progress"]))

    {{:ok, prepared}, _, _} = call(c, prepare)
    progress = prepared["document_progress"]
    assert progress["unit"] == 3
    assert length(progress["prepared"]) == 1

    finish = %{
      "op" => "commit",
      "stages" => progress["prepared"],
      "progress" => continuation(progress, "finish")
    }

    {{:ok, finished}, _, _} = call(c, finish)
    assert finished["document_progress"]["status"] == "finished"
    assert snapshot(c)["document_drafts"] === %{}
  end

  test "retirement preserves the observed cleanup epoch across a second fence", c do
    fence(c)
    bytes = Jason.encode!(%{"x" => 1})

    first =
      inline("document.first", bytes)
      |> Map.put("op", "value.prepare_inline")
      |> Map.put("slot", 0)
      |> Map.put("epoch", Usage.id())
      |> Map.put("progress", start(3))

    {{:ok, one}, _, _} = call(c, first)
    p1 = one["document_progress"]

    second =
      inline("document.second", bytes)
      |> Map.put("op", "value.prepare_inline")
      |> Map.put("slot", Enum.at(p1["slots"], 1))
      |> Map.put("epoch", Usage.id())
      |> Map.put("progress", continuation(p1))

    {{:ok, two}, _, _} = call(c, second)
    p2 = two["document_progress"]
    fence(c)

    retire = fn progress ->
      %{
        "version" => 1,
        "action" => "retire",
        "head_id" => progress["head_id"],
        "revision" => progress["revision"]
      }
    end

    [first_ref, second_ref] = p2["prepared"]

    {{:ok, one_removed}, retirement_request, retirement_id} =
      call(c, Map.merge(first_ref, %{"op" => "value.abort", "progress" => retire.(p2)}))

    retiring = one_removed["document_progress"]
    assert retiring["status"] == "retiring"
    assert retiring["retirement_epoch"] == 2
    retired_state = snapshot(c)
    head = retired_state["document_drafts"][p2["head_id"]]

    assert head["retirement_operation"] === %{
             "operation_id" => retirement_id,
             "invocation_id" => c.owner["invocation_id"]
           }

    assert {:ok, %{"operation" => operation}} =
             Collection.execute_profile(
               c.root,
               c.ns,
               %{"op" => "inspect", "operation_id" => retirement_id},
               Usage.id(),
               Ipse.Extension.Collection.Profile.documents()
             )

    assert operation["generation"] == head["revision"]

    assert operation["request_sha256"] ===
             JSON.digest([
               %{
                 "op" => "collection.store",
                 "scope" => "project",
                 "request" => retirement_request
               }
             ])

    fence(c)

    {{:error, _}, _, _} =
      call(c, Map.merge(second_ref, %{"op" => "value.abort", "progress" => retire.(retiring)}))

    assert Map.has_key?(snapshot(c)["document_drafts"], p2["head_id"])
  end

  test "wrong immutable body or revision cannot allocate a head", c do
    bytes = Jason.encode!(%{"x" => 1})
    {{:ok, seeded}, _, _} = call(c, inline("document.original", bytes))
    fence(c)
    before = snapshot(c)

    verify = %{
      "op" => "value.verify",
      "key" => "document.original",
      "expected_revision" => seeded["generation"],
      "byte_count" => byte_size(bytes),
      "sha256" => JSON.sha256("different"),
      "progress" => start(1)
    }

    {{:failed, _}, _, _} = call(c, verify)
    assert snapshot(c)["generation"] == before["generation"]
    assert snapshot(c)["document_drafts"] === %{}

    {{:failed, _}, _, _} =
      call(c, %{
        verify
        | "sha256" => JSON.sha256(bytes),
          "expected_revision" => seeded["generation"] + 1
      })

    assert snapshot(c)["generation"] == before["generation"]
  end
end
