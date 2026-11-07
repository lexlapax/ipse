defmodule Ipse.Extension.Collection.DocumentDraftSchemaTest do
  use ExUnit.Case, async: true

  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.Collection.{DocumentDraft, DocumentMaintenance}
  alias Ipse.Extension.CollectionStore

  defp state do
    id = Usage.id()
    project = JSON.sha256("document draft test project")

    owner = %{
      "project_id" => project,
      "session_id" => Usage.id(),
      "identity_sha256" => JSON.sha256("artifact identity")
    }

    head = %{
      "id" => id,
      "kind" => "source",
      "owner" => owner,
      "plan_sha256" => JSON.sha256("plan"),
      "body_sha256" => JSON.sha256("body"),
      "maintenance_epoch" => 1,
      "retirement_epoch" => nil,
      "unit_limit" => 3,
      "unit" => 0,
      "revision" => 1,
      "slots" => [0, 1, 2],
      "active" => nil,
      "prepared" => []
    }

    %{
      "project" => CollectionStore.namespace(project),
      "generation" => 1,
      "operations" => %{
        id => %{"generation" => 1, "floor" => 0, "request_sha256" => JSON.sha256("request")}
      },
      "imported_operations" => %{},
      "records" => %{},
      "migration" => nil,
      "document_maintenance" => %{"version" => 1, "epoch" => 1, "status" => "idle"},
      "document_drafts" => %{id => head}
    }
  end

  test "closed heads bind their native owner, opening receipt and distinct reserved slots" do
    state = state()
    [{id, head}] = Map.to_list(state["document_drafts"])
    assert DocumentMaintenance.metadata(state)["epoch"] == 1
    assert DocumentDraft.valid?(state)
    assert DocumentDraft.reserved_slots(state) == [0, 1, 2]
    assert DocumentDraft.reserved_operations(state) == 1
    refute DocumentDraft.valid?(put_in(state, ["document_drafts", id, "unit"], 4))
    refute DocumentDraft.valid?(put_in(state, ["document_drafts", id, "revision"], 2))
    refute DocumentDraft.valid?(put_in(state, ["document_drafts", id, "slots"], [0, 0, 2]))

    refute DocumentDraft.valid?(
             put_in(state, ["document_drafts", id, "owner", "project_id"], JSON.sha256("other"))
           )

    refute DocumentDraft.valid?(put_in(state, ["document_drafts", id, "maintenance_epoch"], 2))

    refute DocumentDraft.valid?(
             put_in(state, ["document_drafts", id], Map.put(head, "extra", true))
           )

    refute DocumentDraft.valid?(put_in(state, ["operations"], %{}))
    assert DocumentDraft.valid_absent_or_present?(Map.delete(state, "document_drafts"))
    refute DocumentDraft.valid?(Map.put(state, "document_drafts", %{}))
  end

  test "cleanup operation reservations follow the actual owned stages" do
    state = state()
    [{id, _}] = Map.to_list(state["document_drafts"])
    ref = %{"slot" => 0, "epoch" => Usage.id()}

    active = %{
      "slot" => 1,
      "epoch" => Usage.id(),
      "key" => "documents.example",
      "expected_revision" => 0,
      "byte_count" => 20,
      "sha256" => JSON.sha256("partial value"),
      "offset" => 3,
      "publish" => false
    }

    state = put_in(state, ["document_drafts", id, "prepared"], [ref])
    state = put_in(state, ["document_drafts", id, "active"], active)
    assert DocumentDraft.valid?(state)
    assert DocumentDraft.reserved_operations(state) == 2
    refute DocumentDraft.valid?(put_in(state, ["document_drafts", id, "active", "slot"], 0))
  end

  test "partial retirement joins the exact ledger generation and rejects tampering" do
    state = state()
    [{head_id, head}] = Map.to_list(state["document_drafts"])
    operation_id = Usage.id()
    invocation_id = Usage.id()

    assert {:ok, joined} =
             head
             |> Map.put("retirement_operation", nil)
             |> Map.put("retirement_epoch", 1)
             |> Map.put("revision", 2)
             |> DocumentDraft.bind_retirement(operation_id, invocation_id)

    receipt = %{"generation" => 2, "floor" => 0, "request_sha256" => JSON.sha256("cleanup")}

    state =
      state
      |> Map.put("generation", 2)
      |> put_in(["operations", operation_id], receipt)
      |> put_in(["document_drafts", head_id], joined)

    assert DocumentDraft.valid?(state)

    imported_only =
      state
      |> update_in(["operations"], &Map.delete(&1, operation_id))
      |> put_in(["imported_operations", operation_id], receipt)

    refute DocumentDraft.valid?(imported_only)
    refute DocumentDraft.valid?(put_in(state, ["operations", operation_id, "generation"], 1))
    refute DocumentDraft.valid?(put_in(state, ["document_drafts", head_id, "revision"], 1))

    refute DocumentDraft.valid?(
             put_in(state, ["document_drafts", head_id, "retirement_epoch"], nil)
           )

    refute DocumentDraft.valid?(
             put_in(
               state,
               ["document_drafts", head_id, "retirement_operation", "operation_id"],
               Usage.id()
             )
           )

    refute DocumentDraft.valid?(
             put_in(
               state,
               ["document_drafts", head_id, "retirement_operation", "invocation_id"],
               "invalid"
             )
           )

    # Existing heads remain readable; their missing join grants no new recovery authority.
    assert DocumentDraft.valid?(
             update_in(
               state,
               ["document_drafts", head_id],
               &Map.delete(&1, "retirement_operation")
             )
           )

    assert {:ok, legacy} =
             head
             |> Map.put("retirement_epoch", 1)
             |> Map.put("revision", 2)
             |> DocumentDraft.bind_retirement(operation_id, invocation_id)

    refute Map.has_key?(legacy, "retirement_operation")
  end

  test "the operation ledger retains the head's reducing cleanup capacity" do
    state = state()

    operations =
      Map.new(1..32_767, fn number ->
        {number |> Integer.to_string(16) |> String.pad_leading(32, "0"), %{}}
      end)

    state = %{state | "operations" => operations}
    assert DocumentDraft.operation_budget?(state)
    full = Map.put(operations, String.duplicate("f", 32), %{})
    refute DocumentDraft.operation_budget?(%{state | "operations" => full})
  end

  test "progress tags have closed action-specific shapes" do
    start = %{
      "version" => 1,
      "action" => "start",
      "kind" => "source",
      "plan_sha256" => JSON.sha256("plan"),
      "body_sha256" => JSON.sha256("body"),
      "unit_limit" => 3
    }

    continuation = %{
      "version" => 1,
      "action" => "continue",
      "head_id" => Usage.id(),
      "revision" => 1,
      "unit" => 0
    }

    assert DocumentDraft.tag?(start)
    assert DocumentDraft.tag?(continuation)
    assert DocumentDraft.tag?(%{continuation | "action" => "finish"})

    assert DocumentDraft.tag?(%{
             "version" => 1,
             "action" => "retire",
             "head_id" => continuation["head_id"],
             "revision" => 1
           })

    refute DocumentDraft.tag?(Map.put(start, "unit", 1))
    refute DocumentDraft.tag?(Map.put(continuation, "next_unit", 1))
    refute DocumentDraft.tag?(%{continuation | "revision" => 0})
    refute DocumentDraft.tag?(%{continuation | "unit" => -1})
    refute DocumentDraft.tag?(%{start | "unit_limit" => 32_769})
  end

  test "first head uses the host operation and excludes reserved or occupied slots" do
    state = state()
    [{_, existing}] = Map.to_list(state["document_drafts"])
    owner = Map.put(existing["owner"], "invocation_id", Usage.id())
    id = Usage.id()

    tag = %{
      "version" => 1,
      "action" => "start",
      "kind" => "projection",
      "plan_sha256" => JSON.sha256("another plan"),
      "body_sha256" => JSON.sha256("another body"),
      "unit_limit" => 4
    }

    state = put_in(state, ["records", "host.stage.3.part.0"], %{})
    assert {:ok, head} = DocumentDraft.first_head(state, tag, id, owner)
    assert head["id"] == id
    assert head["unit"] == 0
    assert head["revision"] == 2
    assert head["slots"] == [4, 5]
    assert head["owner"] == existing["owner"]
    assert {:error, _} = DocumentDraft.first_head(state, tag, existing["id"], owner)
    assert {:error, _} = DocumentDraft.first_head(state, Map.put(tag, "unit", 2), id, owner)
  end

  test "continuation joins the stored epoch, owner, revision and unit" do
    state = state()
    [{id, head}] = Map.to_list(state["document_drafts"])
    owner = Map.put(head["owner"], "invocation_id", Usage.id())
    tag = %{"version" => 1, "action" => "continue", "head_id" => id, "revision" => 1, "unit" => 0}

    assert {:ok, ^head} = DocumentDraft.authorize(state, tag, owner)
    assert {:error, _} = DocumentDraft.authorize(state, %{tag | "action" => "finish"}, owner)
    assert {:error, _} = DocumentDraft.authorize(state, %{tag | "unit" => 1}, owner)
    assert {:error, _} = DocumentDraft.authorize(state, %{tag | "revision" => 2}, owner)

    assert {:error, _} =
             DocumentDraft.authorize(state, tag, %{owner | "session_id" => Usage.id()})

    fenced = put_in(state, ["document_maintenance", "epoch"], 2)
    assert {:error, _} = DocumentDraft.authorize(fenced, tag, owner)

    retire = %{"version" => 1, "action" => "retire", "head_id" => id, "revision" => 1}
    assert {:ok, ^head} = DocumentDraft.authorize(fenced, retire, owner)
    retiring = put_in(fenced, ["document_drafts", id, "retirement_epoch"], 2)
    assert {:ok, _} = DocumentDraft.authorize(retiring, retire, owner)
    refute match?({:ok, _}, DocumentDraft.authorize(retiring, tag, owner))

    assert {:error, _} =
             DocumentDraft.authorize(
               put_in(retiring, ["document_maintenance", "epoch"], 3),
               retire,
               owner
             )
  end

  test "partial writes change revision but advance only after the actual complete effect" do
    state = state()
    [{id, head}] = Map.to_list(state["document_drafts"])

    tag = %{
      "version" => 1,
      "action" => "start",
      "kind" => "source",
      "plan_sha256" => head["plan_sha256"],
      "body_sha256" => head["body_sha256"],
      "unit_limit" => 3
    }

    request = %{
      "op" => "value.write_parts",
      "slot" => 0,
      "epoch" => Usage.id(),
      "key" => "documents.example",
      "expected_revision" => 0,
      "byte_count" => 4,
      "sha256" => JSON.sha256("abcd"),
      "offset" => 0,
      "data" => ["ab"],
      "publish" => true
    }

    changes = [%{"key" => "host.stage.0.header", "value" => %{}}]
    assert {:ok, partial} = DocumentDraft.step(head, tag, request, changes, 1)
    assert partial["unit"] == 0
    assert partial["active"]["offset"] == 2

    continuation = %{
      "version" => 1,
      "action" => "continue",
      "head_id" => id,
      "revision" => 1,
      "unit" => 0
    }

    last = %{request | "offset" => 2, "data" => ["cd"]}
    published = [%{"key" => "documents.example", "value" => %{}}]
    assert {:ok, complete} = DocumentDraft.step(partial, continuation, last, published, 2)
    assert complete["unit"] == 1
    assert complete["revision"] == 2
    assert complete["active"] == nil

    assert {:error, _} =
             DocumentDraft.step(partial, continuation, %{last | "key" => "other"}, published, 2)

    assert {:error, _} = DocumentDraft.step(partial, continuation, last, [], 2)
  end

  test "retirement removes only a named owned stage and keeps its first cleanup epoch" do
    state = state()
    [{id, head}] = Map.to_list(state["document_drafts"])
    first = %{"slot" => 0, "epoch" => Usage.id()}
    last = %{"slot" => 1, "epoch" => Usage.id()}
    head = %{head | "prepared" => [first, last]}
    tag = %{"version" => 1, "action" => "retire", "head_id" => id, "revision" => 1}
    request = Map.put(first, "op", "value.abort")

    changes = [
      %{"key" => "host.stage.0.header", "value" => nil},
      %{"key" => "host.stage.0.ready", "value" => nil}
    ]

    assert {:ok, retiring} = DocumentDraft.retire(head, tag, request, changes, 2, 2)
    assert retiring["retirement_epoch"] == 2
    assert retiring["prepared"] == [last]
    later = %{tag | "revision" => 2}
    last_request = Map.put(last, "op", "value.abort")

    last_changes = [
      %{"key" => "host.stage.1.header", "value" => nil},
      %{"key" => "host.stage.1.ready", "value" => nil}
    ]

    assert {:error, _} = DocumentDraft.retire(retiring, later, last_request, last_changes, 3, 3)
    assert {:error, _} = DocumentDraft.retire(retiring, later, request, changes, 3, 2)
    assert {:ok, nil} = DocumentDraft.retire(retiring, later, last_request, last_changes, 3, 2)
  end
end
