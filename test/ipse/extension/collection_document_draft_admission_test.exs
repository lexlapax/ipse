defmodule Ipse.Extension.Collection.DocumentDraftAdmissionTest do
  use ExUnit.Case, async: false

  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.{Collection, CollectionStore}
  alias Ipse.Extension.Collection.DocumentStage

  setup do
    parent = Path.join(System.tmp_dir!(), "ipse-draft-admission-" <> Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    on_exit(fn -> File.rm_rf!(parent) end)

    owner = %{
      "project_id" => JSON.sha256("draft admission project"),
      "session_id" => Usage.id(),
      "identity_sha256" => JSON.sha256("draft admission artifact"),
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
    initial = snapshot(c)

    opening = %{
      "op" => "maintenance.open",
      "expected_generation" => initial["generation"],
      "expected_epoch" => 0,
      "maintenance_id" => Usage.id(),
      "purpose" => "checkpoint_inspection",
      "close_operation_id" => Usage.id()
    }

    assert {:ok, _} = Collection.document_maintenance(c.root, c.ns, opening, Usage.id(), c.owner)
    active = snapshot(c)

    close = %{
      "op" => "maintenance.close",
      "expected_generation" => active["generation"],
      "expected_epoch" => 1,
      "maintenance_id" => opening["maintenance_id"]
    }

    assert {:ok, _} =
             Collection.document_maintenance(
               c.root,
               c.ns,
               close,
               opening["close_operation_id"],
               c.owner
             )
  end

  defp call(c, request, owner \\ nil, id \\ Usage.id()) do
    state = snapshot(c)

    request =
      request |> Map.put("generation", state["generation"]) |> Map.put("maintenance_epoch", 1)

    {DocumentStage.execute(c.root, c.ns, request, id, owner || c.owner), request, id}
  end

  defp inline(key) do
    body = Jason.encode!(%{"text" => key})

    %{
      "op" => "value.put_inline",
      "key" => key,
      "expected_revision" => 0,
      "byte_count" => byte_size(body),
      "sha256" => JSON.sha256(body),
      "data" => body
    }
  end

  defp start(kind, label) do
    %{
      "version" => 1,
      "action" => "start",
      "kind" => kind,
      "plan_sha256" => JSON.sha256("plan " <> label),
      "body_sha256" => JSON.sha256("body " <> label),
      "unit_limit" => 3
    }
  end

  defp tag(progress, action \\ "continue") do
    %{
      "version" => 1,
      "action" => action,
      "head_id" => progress["head_id"],
      "revision" => progress["revision"],
      "unit" => progress["unit"]
    }
  end

  defp prepared(key, slot) do
    inline(key)
    |> Map.put("op", "value.prepare_inline")
    |> Map.put("slot", slot)
    |> Map.put("epoch", Usage.id())
  end

  defp wrapped(request, id, result) do
    outer = %{"op" => "collection.store", "scope" => "project", "request" => request}

    value = %{
      "version" => 2,
      "operation_id" => id,
      "request_sha256" => JSON.digest([outer]),
      "result" => Map.delete(result, "document_progress"),
      "progress" => result["document_progress"]
    }

    assert CollectionStore.valid_outcome?(outer, "ok", value, id)
    {outer, value}
  end

  test "reserved slots and native owner, unit and revision checks remain independent", c do
    fence(c)

    {{:ok, first}, first_request, first_id} =
      call(c, Map.put(inline("fixture.first"), "progress", start("projection", "first")))

    {{:ok, second}, _, _} =
      call(c, Map.put(inline("fixture.second"), "progress", start("source", "second")))

    first_progress = first["document_progress"]
    second_progress = second["document_progress"]

    assert MapSet.disjoint?(
             MapSet.new(first_progress["slots"]),
             MapSet.new(second_progress["slots"])
           )

    assert {:ok, available} =
             DocumentStage.execute(
               c.root,
               c.ns,
               %{"op" => "stage.available"},
               Usage.id(),
               c.owner
             )

    assert Enum.all?(
             first_progress["slots"] ++ second_progress["slots"],
             &(&1 not in available["available_slots"])
           )

    assert length(available["available_slots"]) == 11

    outer = %{"op" => "collection.store", "scope" => "project", "request" => first_request}

    wrapped = %{
      "version" => 2,
      "operation_id" => first_id,
      "request_sha256" => JSON.digest([outer]),
      "result" => Map.delete(first, "document_progress"),
      "progress" => first_progress
    }

    assert CollectionStore.valid_outcome?(outer, "ok", wrapped, first_id)

    refute CollectionStore.valid_outcome?(
             outer,
             "ok",
             put_in(wrapped, ["progress", "unit"], 2),
             first_id
           )

    refute CollectionStore.valid_outcome?(
             outer,
             "ok",
             put_in(wrapped, ["result", "request_sha256"], JSON.sha256("other")),
             first_id
           )

    root = Path.join([c.root, c.ns, "root.json"])
    root_before = File.read!(root)
    claimed_slot = hd(first_progress["slots"])

    {{:failed, %{"code" => "collection_document_draft_reserved"}}, _, _} =
      call(c, prepared("fixture.legacy", claimed_slot))

    body = Jason.encode!(%{"text" => "legacy"})

    legacy_parts = %{
      "op" => "value.write_parts",
      "slot" => claimed_slot,
      "epoch" => Usage.id(),
      "key" => "fixture.legacy.parts",
      "expected_revision" => 0,
      "byte_count" => byte_size(body),
      "sha256" => JSON.sha256(body),
      "offset" => 0,
      "data" => [binary_part(body, 0, 2)],
      "publish" => true
    }

    {{:failed, %{"code" => "collection_document_draft_reserved"}}, _, _} = call(c, legacy_parts)

    wrong_head =
      prepared("fixture.wrong", claimed_slot) |> Map.put("progress", tag(second_progress))

    {{:failed, %{"code" => "collection_document_draft_reserved"}}, _, _} = call(c, wrong_head)
    assert File.read!(root) == root_before

    valid_prepare =
      prepared("fixture.prepared", claimed_slot) |> Map.put("progress", tag(first_progress))

    {{:ok, prepared}, _, _} = call(c, valid_prepare)
    current = prepared["document_progress"]
    assert current["unit"] == 2
    root_before = File.read!(root)

    request = Map.put(inline("fixture.forbidden"), "progress", tag(current))

    for owner <- [
          %{c.owner | "session_id" => Usage.id()},
          %{c.owner | "identity_sha256" => JSON.sha256("other artifact")},
          %{c.owner | "project_id" => JSON.sha256("other project")}
        ] do
      {{:error, _}, _, _} = call(c, request, owner)
    end

    {{:error, _}, _, _} = call(c, put_in(request, ["progress", "unit"], current["unit"] + 1))

    {{:error, _}, _, _} =
      call(c, put_in(request, ["progress", "revision"], current["revision"] + 1))

    finish = %{
      "op" => "commit",
      "stages" => current["prepared"],
      "progress" => tag(current, "finish")
    }

    {{:error, _}, _, _} = call(c, finish)
    assert File.read!(root) == root_before
  end

  test "the document profile keeps checkpoint removal unexposed with a live head", c do
    fence(c)

    {{:ok, _}, _, _} =
      call(c, Map.put(inline("fixture.live"), "progress", start("projection", "checkpoint")))

    before = snapshot(c)
    root = Path.join([c.root, c.ns, "root.json"])
    root_before = File.read!(root)
    request = %{"op" => "checkpoint.drop", "expected_generation" => before["generation"]}
    assert Collection.valid_request?(request)

    assert Ipse.Extension.Collection.DocumentDraft.admission_error(before, request) ===
             "collection_document_draft_fenced"

    assert {:error, :invalid_collection_request} =
             Collection.with_document_admission(c.root, c.ns, c.owner, fn _ ->
               Collection.execute_profile(
                 c.root,
                 c.ns,
                 request,
                 Usage.id(),
                 Ipse.Extension.Collection.Profile.documents()
               )
             end)

    assert File.read!(root) == root_before
    assert snapshot(c)["generation"] == before["generation"]
  end

  test "saved progress receipts bind observable epochs, stages and partial writes", c do
    fence(c)

    {{:ok, started}, start_request, start_id} =
      call(
        c,
        Map.put(inline("fixture.receipt.start"), "progress", start("projection", "receipt"))
      )

    {outer, value} = wrapped(start_request, start_id, started)

    refute CollectionStore.valid_outcome?(
             outer,
             "ok",
             put_in(value, ["progress", "maintenance_epoch"], 2),
             start_id
           )

    fake_ref = %{"slot" => hd(value["progress"]["slots"]), "epoch" => Usage.id()}

    refute CollectionStore.valid_outcome?(
             outer,
             "ok",
             put_in(value, ["progress", "prepared"], [fake_ref]),
             start_id
           )

    seed = inline("fixture.receipt.reuse")
    {{:ok, original}, _, _} = call(c, seed)

    verify = %{
      "op" => "value.verify",
      "key" => seed["key"],
      "expected_revision" => original["generation"],
      "byte_count" => seed["byte_count"],
      "sha256" => seed["sha256"],
      "progress" => start("projection", "reuse")
    }

    {{:ok, reused}, reuse_request, reuse_id} = call(c, verify)
    {outer, value} = wrapped(reuse_request, reuse_id, reused)
    fake_ref = %{"slot" => hd(value["progress"]["slots"]), "epoch" => Usage.id()}

    refute CollectionStore.valid_outcome?(
             outer,
             "ok",
             put_in(value, ["progress", "prepared"], [fake_ref]),
             reuse_id
           )

    slot = hd(started["document_progress"]["slots"])

    request =
      prepared("fixture.receipt.prepared", slot)
      |> Map.put("progress", tag(started["document_progress"]))

    {{:ok, stored}, prepare_request, prepare_id} = call(c, request)
    {outer, value} = wrapped(prepare_request, prepare_id, stored)

    refute CollectionStore.valid_outcome?(
             outer,
             "ok",
             put_in(value, ["progress", "prepared"], []),
             prepare_id
           )

    second_slot = Enum.find(stored["document_progress"]["slots"], &(&1 != slot))

    second_request =
      prepared("fixture.receipt.second", second_slot)
      |> Map.put("progress", tag(stored["document_progress"]))

    {{:ok, both_stored}, _, _} = call(c, second_request)

    assert {:ok, free} =
             DocumentStage.execute(
               c.root,
               c.ns,
               %{"op" => "stage.available"},
               Usage.id(),
               c.owner
             )

    direct_slot = hd(free["available_slots"])

    direct =
      prepared("fixture.receipt.direct", direct_slot)
      |> Map.put("progress", start("projection", "direct"))

    {{:ok, direct_stored}, direct_request, direct_id} = call(c, direct)
    {outer, value} = wrapped(direct_request, direct_id, direct_stored)
    other = Enum.find(value["progress"]["slots"], &(&1 != direct_slot))
    extra = %{"slot" => other, "epoch" => Usage.id()}
    invented = Enum.sort_by([extra | value["progress"]["prepared"]], & &1["slot"])

    refute CollectionStore.valid_outcome?(
             outer,
             "ok",
             put_in(value, ["progress", "prepared"], invented),
             direct_id
           )

    assert {:ok, available} =
             DocumentStage.execute(
               c.root,
               c.ns,
               %{"op" => "stage.available"},
               Usage.id(),
               c.owner
             )

    partial_slot = hd(available["available_slots"])
    body = Jason.encode!(%{"text" => "receipt partial"})

    partial = %{
      "op" => "value.write_parts",
      "slot" => partial_slot,
      "epoch" => Usage.id(),
      "key" => "fixture.receipt.partial",
      "expected_revision" => 0,
      "byte_count" => byte_size(body),
      "sha256" => JSON.sha256(body),
      "offset" => 0,
      "data" => [binary_part(body, 0, 2)],
      "publish" => true,
      "progress" => start("projection", "partial")
    }

    {{:ok, opened}, partial_request, partial_id} = call(c, partial)
    {outer, value} = wrapped(partial_request, partial_id, opened)

    refute CollectionStore.valid_outcome?(
             outer,
             "ok",
             put_in(value, ["progress", "active", "offset"], 3),
             partial_id
           )

    refute CollectionStore.valid_outcome?(
             outer,
             "ok",
             put_in(value, ["progress", "active", "sha256"], JSON.sha256("other")),
             partial_id
           )

    other_slot = Enum.find(opened["document_progress"]["slots"], &(&1 != partial_slot))

    refute CollectionStore.valid_outcome?(
             outer,
             "ok",
             put_in(value, ["progress", "active", "slot"], other_slot),
             partial_id
           )

    last = %{
      partial
      | "offset" => 2,
        "data" => [binary_part(body, 2, byte_size(body) - 2)],
        "progress" => tag(opened["document_progress"])
    }

    {{:ok, complete}, complete_request, complete_id} = call(c, last)
    {outer, value} = wrapped(complete_request, complete_id, complete)
    fake_active = opened["document_progress"]["active"]

    refute CollectionStore.valid_outcome?(
             outer,
             "ok",
             put_in(value, ["progress", "active"], fake_active),
             complete_id
           )

    assert {:ok, free} =
             DocumentStage.execute(
               c.root,
               c.ns,
               %{"op" => "stage.available"},
               Usage.id(),
               c.owner
             )

    sealed = %{
      "op" => "value.write_parts",
      "slot" => hd(free["available_slots"]),
      "epoch" => Usage.id(),
      "key" => "fixture.receipt.sealed",
      "expected_revision" => 0,
      "byte_count" => byte_size(body),
      "sha256" => JSON.sha256(body),
      "offset" => 0,
      "data" => [body],
      "publish" => false,
      "progress" => start("projection", "sealed")
    }

    {{:ok, sealed_result}, sealed_request, sealed_id} = call(c, sealed)
    {outer, value} = wrapped(sealed_request, sealed_id, sealed_result)

    refute CollectionStore.valid_outcome?(
             outer,
             "ok",
             put_in(value, ["progress", "prepared"], []),
             sealed_id
           )

    refute CollectionStore.valid_outcome?(
             outer,
             "ok",
             put_in(value, ["progress", "prepared", Access.at(0), "epoch"], Usage.id()),
             sealed_id
           )

    progress = both_stored["document_progress"]

    retire = %{
      "version" => 1,
      "action" => "retire",
      "head_id" => progress["head_id"],
      "revision" => progress["revision"]
    }

    ref = hd(progress["prepared"])

    {{:ok, retired}, retire_request, retire_id} =
      call(c, Map.merge(ref, %{"op" => "value.abort", "progress" => retire}))

    {outer, value} = wrapped(retire_request, retire_id, retired)

    refute CollectionStore.valid_outcome?(
             outer,
             "ok",
             put_in(value, ["progress", "retirement_epoch"], 2),
             retire_id
           )

    restored = Enum.sort_by([ref | value["progress"]["prepared"]], & &1["slot"])

    refute CollectionStore.valid_outcome?(
             outer,
             "ok",
             put_in(value, ["progress", "prepared"], restored),
             retire_id
           )
  end
end
