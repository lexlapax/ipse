defmodule Ipse.Extension.Collection.DocumentDraft do
  @moduledoc """
  Closed native metadata for bounded document progress.

  These helpers grant no authority and do not publish a transition. The native
  collection owner must validate and update a head with its associated effect.
  """
  alias Ipse.JSON

  alias Ipse.Extension.Collection.{
    Directory,
    DocumentMaintenance,
    DocumentStage,
    Encoding,
    Migration
  }

  alias Ipse.Extension.CollectionStore

  @key "document_drafts"
  @heads 8
  @slots 16
  @head_bytes 4096
  @block_bytes 64 * 1024
  @manifest_bytes 8 * 1024 * 1024
  @max_uint 9_007_199_254_740_991
  @head_fields ~w(id kind owner plan_sha256 body_sha256 maintenance_epoch retirement_epoch unit_limit unit revision slots active prepared)
  @owner_fields ~w(project_id session_id identity_sha256)
  @active_fields ~w(slot epoch key expected_revision byte_count sha256 offset publish)
  @receipt_fields ~w(version status head_id revision unit maintenance_epoch retirement_epoch slots active prepared plan_sha256 body_sha256 unit_limit kind)

  def present?(state), do: Map.has_key?(state, @key)
  def heads(state), do: Map.get(state, @key, %{})

  def tag?(%{"version" => 1, "action" => "start"} = tag) do
    exact?(tag, ~w(version action kind plan_sha256 body_sha256 unit_limit)) and
      tag["kind"] in ~w(source projection) and JSON.sha256?(tag["plan_sha256"]) and
      JSON.sha256?(tag["body_sha256"]) and is_integer(tag["unit_limit"]) and
      tag["unit_limit"] in 1..32_768
  end

  def tag?(%{"version" => 1, "action" => action} = tag)
      when action in ~w(continue finish) do
    exact?(tag, ~w(version action head_id revision unit)) and id?(tag["head_id"]) and
      JSON.safe_uint?(tag["revision"]) and tag["revision"] > 0 and JSON.safe_uint?(tag["unit"])
  end

  def tag?(%{"version" => 1, "action" => "retire"} = tag) do
    exact?(tag, ~w(version action head_id revision)) and id?(tag["head_id"]) and
      JSON.safe_uint?(tag["revision"]) and tag["revision"] > 0
  end

  def tag?(_), do: false

  def valid?(state) do
    heads = heads(state)
    maintenance = DocumentMaintenance.metadata(state)

    is_map(heads) and map_size(heads) in 1..@heads and
      is_nil(state["migration"]) and
      JSON.safe_uint?(maintenance["epoch"]) and maintenance["epoch"] > 0 and
      Enum.all?(heads, fn {id, head} -> valid_head?(id, head, state, maintenance) end) and
      unique_slots?(heads)
  rescue
    _ -> false
  end

  def valid_absent_or_present?(state), do: not present?(state) or valid?(state)

  def reserved_slots(state) do
    state |> heads() |> Map.values() |> Enum.flat_map(& &1["slots"]) |> Enum.sort()
  end

  @doc "One cleanup CAS per extant owned stage, or one to retire an empty head."
  def reserved_operations(state) do
    state
    |> heads()
    |> Map.values()
    |> Enum.reduce(0, fn head, total ->
      owned = length(head["prepared"]) + if(is_nil(head["active"]), do: 0, else: 1)
      total + max(owned, 1)
    end)
  end

  @doc "Check the combined native operation ledger, including reducing cleanup."
  def operation_budget?(state) do
    map_size(Migration.known_operations(state)) + Migration.reserved_operation_slots(state) +
      DocumentMaintenance.reserved_slots(state) + reserved_operations(state) <= 32_768
  rescue
    _ -> false
  end

  @doc "A conservative complete file vector for all currently owed cleanups."
  def cleanup_reserve(state, manifest_bytes, blocks)
      when is_binary(manifest_bytes) and is_map(blocks) do
    with {:ok, cleanup, []} <- cleanup_reserve(state, manifest_bytes, blocks, 0),
         do: {:ok, cleanup}
  end

  @doc false
  # A checkpoint disposition remains owed while heads/stages must be retired
  # first. Account for that extra publication without admitting it or discarding
  # any current metadata from the conservative cleanup bound.
  def cleanup_reserve(state, manifest_bytes, blocks, additional_terminal_steps)
      when is_binary(manifest_bytes) and is_map(blocks) and additional_terminal_steps in 0..1 do
    cleanup_refs = if map_size(heads(state)) == 0, do: [], else: cleanup_refs(state)
    additional_refs = List.duplicate(nil, additional_terminal_steps)
    refs = cleanup_refs ++ additional_refs

    if refs == [] do
      {:ok, [], []}
    else
      with {:ok, wire} <- JSON.decode_unique(manifest_bytes),
           true <-
             is_map(wire) and is_list(wire["operations"]) and is_list(wire["floor_lineage"]),
           true <- length(refs) in 1..25,
           bound = cleanup_manifest_bound(wire),
           true <- bound in 1..@manifest_bytes,
           true <- cleanup_flat_bound(state, length(refs)) <= @manifest_bytes,
           future_blocks =
             Enum.sum(
               Enum.map(refs, fn ref ->
                 if(is_nil(ref), do: 0, else: stage_record_count(state, ref)) + 2
               end)
             ),
           true <- map_size(blocks) + future_blocks <= 1024,
           true <-
             Enum.sum(Enum.map(blocks, fn {_, bytes} -> byte_size(bytes) end)) +
               future_blocks * @block_bytes <= 9 * 1024 * 1024,
           true <- wire_reference_count(wire) + 2 <= 1024 do
        sizes = fn selected ->
          Enum.flat_map(selected, fn ref ->
            count = if is_nil(ref), do: 0, else: stage_record_count(state, ref)
            List.duplicate(@block_bytes, count + 2) ++ [bound, pointer_bound(state)]
          end)
        end

        {:ok, sizes.(cleanup_refs), sizes.(additional_refs)}
      else
        _ -> {:error, :document_draft_capacity}
      end
    end
  rescue
    _ -> {:error, :document_draft_capacity}
  end

  defp wire_reference_count(wire) do
    base =
      length(wire["operations"]) + length(wire["imported_operations"]) +
        length(wire["records"]) + length(wire["floor_lineage"])

    checkpoint = if is_map(wire["checkpoint"]), do: length(wire["checkpoint"]["records"]), else: 0
    base + checkpoint
  end

  defp cleanup_refs(state) do
    refs =
      Enum.flat_map(heads(state), fn {_, head} ->
        active = if is_nil(head["active"]), do: [], else: [head["active"]]

        case active ++ head["prepared"] do
          [] -> [nil]
          refs -> refs
        end
      end)

    if DocumentMaintenance.metadata(state)["status"] === "active", do: [nil | refs], else: refs
  end

  defp stage_record_count(state, ref) do
    prefix = "host.stage.#{ref["slot"]}."
    Enum.count(Map.keys(state["records"]), &String.starts_with?(&1, prefix))
  end

  defp cleanup_manifest_bound(wire) do
    local = %{
      "kind" => "local",
      "count" => 256,
      "sha256" => String.duplicate("f", 64),
      "bytes" => @block_bytes,
      "start" => @max_uint
    }

    lineage = %{
      "kind" => "lineage",
      "count" => 512,
      "sha256" => String.duplicate("f", 64),
      "bytes" => @block_bytes,
      "start" => @max_uint
    }

    wire
    |> reserve_retirement_receipts()
    |> Map.update!("operations", &(&1 ++ [local]))
    |> Map.update!("floor_lineage", &(&1 ++ [lineage]))
    |> inflate_bound()
    |> Migration.encode()
    |> byte_size()
  end

  defp cleanup_flat_bound(state, count) do
    {:ok, flat} = state |> Encoding.encode() |> JSON.decode_unique()
    operation = [String.duplicate("A", 22), String.duplicate("A", 43), @max_uint]
    lineage_id = String.duplicate("f", 32)

    flat
    |> reserve_retirement_receipts()
    |> Map.update!("operations", &(&1 ++ List.duplicate(operation, count)))
    |> Map.update!("floor_lineage", &(&1 ++ List.duplicate(lineage_id, count)))
    |> inflate_bound()
    |> Migration.encode()
    |> byte_size()
  end

  # A new head reserves room for the full native-owned join before admission.
  # Legacy heads do not gain this field or need unreserved cleanup space.
  defp reserve_retirement_receipts(state) do
    if is_map(state["document_drafts"]) do
      update_in(state, ["document_drafts"], fn heads ->
        Map.new(heads, fn {id, head} ->
          if Map.has_key?(head, "retirement_operation") do
            {id,
             Map.put(head, "retirement_operation", %{
               "operation_id" => String.duplicate("f", 32),
               "invocation_id" => String.duplicate("f", 32)
             })}
          else
            {id, head}
          end
        end)
      end)
    else
      state
    end
  end

  defp pointer_bound(state) do
    %{
      "version" => @max_uint,
      "project" => state["project"],
      "generation" => @max_uint,
      "floor" => @max_uint,
      "floor_anchor" => String.duplicate("f", 32),
      "manifest" => String.duplicate("f", 64),
      "storage_profile" => "document_graph_v1"
    }
    |> Migration.encode()
    |> byte_size()
  end

  defp inflate_bound(map) when is_map(map) do
    Map.new(map, fn
      {"prefix", _} -> {"prefix", String.duplicate("1", 256)}
      {"retirement_epoch", nil} -> {"retirement_epoch", @max_uint}
      {"floor_anchor", nil} -> {"floor_anchor", String.duplicate("f", 32)}
      {key, value} -> {key, inflate_bound(value)}
    end)
  end

  defp inflate_bound(list) when is_list(list), do: Enum.map(list, &inflate_bound/1)
  defp inflate_bound(value) when is_integer(value), do: @max_uint
  defp inflate_bound(value) when value in ~w(idle active), do: "retiring"
  defp inflate_bound(value), do: value

  @doc "Refuse administrative rewrites and competing writes to reserved stage slots."
  def admission_error(state, request, allowed_slots \\ []) do
    reserved = reserved_slots(state) -- allowed_slots

    cond do
      map_size(heads(state)) == 0 ->
        nil

      request["op"] not in ~w(commit progress.verify progress.retire maintenance.open maintenance.close) ->
        "collection_document_draft_fenced"

      request["op"] === "commit" and
          Enum.any?(request["changes"], fn change ->
            Enum.any?(reserved, &String.starts_with?(change["key"], "host.stage.#{&1}."))
          end) ->
        "collection_document_draft_reserved"

      true ->
        nil
    end
  rescue
    _ -> "collection_document_draft_fenced"
  end

  def owner(owner), do: Map.take(owner, @owner_fields)

  @doc "Build a bounded response from the actual post-publication head."
  def receipt(previous, next, action, generation, current_epoch) do
    terminal? = is_nil(next)
    head = next || previous

    status =
      cond do
        terminal? and action === "retire" -> "retired"
        terminal? -> "finished"
        not is_nil(head["retirement_epoch"]) -> "retiring"
        true -> "active"
      end

    head
    |> Map.take(
      ~w(kind plan_sha256 body_sha256 unit_limit unit maintenance_epoch retirement_epoch slots active prepared)
    )
    |> Map.merge(%{
      "version" => 1,
      "status" => status,
      "head_id" => previous["id"],
      "revision" => generation
    })
    |> then(fn value ->
      if terminal? do
        value
        |> Map.put("slots", [])
        |> Map.put("active", nil)
        |> Map.put("prepared", [])
        |> Map.put("retirement_epoch", if(action === "retire", do: current_epoch, else: nil))
      else
        value
      end
    end)
  end

  def receipt?(receipt) do
    exact?(receipt, @receipt_fields) and receipt["version"] === 1 and
      receipt["status"] in ~w(active retiring finished retired) and id?(receipt["head_id"]) and
      JSON.safe_uint?(receipt["revision"]) and receipt["revision"] > 0 and
      JSON.safe_uint?(receipt["maintenance_epoch"]) and receipt["maintenance_epoch"] > 0 and
      (is_nil(receipt["retirement_epoch"]) or
         (JSON.safe_uint?(receipt["retirement_epoch"]) and
            receipt["retirement_epoch"] >= receipt["maintenance_epoch"])) and
      receipt["kind"] in ~w(source projection) and JSON.sha256?(receipt["plan_sha256"]) and
      JSON.sha256?(receipt["body_sha256"]) and is_integer(receipt["unit_limit"]) and
      receipt["unit_limit"] in 1..32_768 and JSON.safe_uint?(receipt["unit"]) and
      receipt["unit"] <= receipt["unit_limit"] and receipt_shape?(receipt)
  rescue
    _ -> false
  end

  defp receipt_shape?(%{"status" => status} = r) when status in ~w(active retiring) do
    slots?(r["slots"], r["kind"]) and active?(r["active"], r["slots"]) and
      prepared?(r["prepared"], r["slots"], r["active"]) and
      (status !== "active" or is_nil(r["retirement_epoch"])) and
      (status !== "retiring" or not is_nil(r["retirement_epoch"]))
  end

  defp receipt_shape?(%{"status" => status} = r) when status in ~w(finished retired) do
    r["slots"] === [] and is_nil(r["active"]) and r["prepared"] === [] and
      (status !== "finished" or
         (r["unit"] === r["unit_limit"] and is_nil(r["retirement_epoch"]))) and
      (status !== "retired" or not is_nil(r["retirement_epoch"]))
  end

  @doc "Recheck a copied continuation against the actual native head and owner."
  def authorize(state, tag, actual_owner) do
    maintenance = DocumentMaintenance.metadata(state)

    with true <- tag?(tag) and tag["action"] in ~w(continue finish retire),
         true <- DocumentStage.owner?(actual_owner) and valid?(state),
         head when is_map(head) <- heads(state)[tag["head_id"]],
         true <- owner(actual_owner) === head["owner"],
         true <- tag["revision"] === head["revision"],
         true <- maintenance["status"] === "idle",
         true <- permitted_epoch?(head, tag, maintenance["epoch"], actual_owner),
         true <- tag["action"] === "retire" or tag["unit"] === head["unit"],
         true <-
           tag["action"] !== "finish" or
             (head["unit"] === head["unit_limit"] and is_nil(head["active"])) do
      {:ok, head}
    else
      _ -> {:error, :document_draft_refused}
    end
  rescue
    _ -> {:error, :document_draft_refused}
  end

  defp permitted_epoch?(head, %{"action" => "retire"}, current, owner) do
    head["maintenance_epoch"] <= current and
      ((is_nil(head["retirement_epoch"]) and first_retirement_safe?(head)) or
         (head["retirement_epoch"] === current and retirement_authorized?(head, owner)))
  end

  defp permitted_epoch?(head, _, current, _owner) do
    head["maintenance_epoch"] === current and is_nil(head["retirement_epoch"])
  end

  # Legacy heads can finish in one cleanup, but cannot record the operation
  # join needed to authorize a subsequent cleanup under the same live owner.
  defp first_retirement_safe?(head) do
    Map.has_key?(head, "retirement_operation") or
      length(head["prepared"]) + if(is_nil(head["active"]), do: 0, else: 1) <= 1
  end

  defp retirement_authorized?(head, owner) do
    case {head["retirement_operation"], owner["retirement_authority"]} do
      {%{"operation_id" => operation, "invocation_id" => invocation},
       %{
         "operation_id" => approved_operation,
         "invocation_id" => approved_invocation,
         "revision" => revision,
         "epoch" => epoch
       }} ->
        operation === approved_operation and invocation === approved_invocation and
          revision === head["revision"] and epoch === head["retirement_epoch"]

      _ ->
        false
    end
  end

  @doc "Construct a first head from the actual locked state and host operation identity."
  def first_head(state, tag, operation_id, actual_owner, selected_slot \\ nil) do
    maintenance = DocumentMaintenance.metadata(state)
    existing = heads(state)

    with true <- tag?(tag) and tag["action"] === "start",
         true <-
           id?(operation_id) and not Map.has_key?(Migration.known_operations(state), operation_id),
         true <- DocumentStage.owner?(actual_owner),
         true <- CollectionStore.namespace(actual_owner["project_id"]) === state["project"],
         true <- valid_absent_or_present?(state),
         true <- maintenance["status"] === "idle" and maintenance["epoch"] > 0,
         true <- is_nil(state["migration"]) and map_size(existing) < @heads,
         true <- JSON.safe_uint?(state["generation"] + 1),
         available = available_slots(state),
         count = if(tag["kind"] === "source", do: 3, else: 2),
         true <- length(available) >= count,
         true <- is_nil(selected_slot) or selected_slot in available,
         slots =
           if(is_nil(selected_slot),
             do: Enum.take(available, count),
             else:
               Enum.sort([
                 selected_slot | Enum.take(List.delete(available, selected_slot), count - 1)
               ])
           ) do
      {:ok,
       %{
         "id" => operation_id,
         "kind" => tag["kind"],
         "owner" => owner(actual_owner),
         "plan_sha256" => tag["plan_sha256"],
         "body_sha256" => tag["body_sha256"],
         "maintenance_epoch" => maintenance["epoch"],
         "retirement_epoch" => nil,
         "retirement_operation" => nil,
         "unit_limit" => tag["unit_limit"],
         "unit" => 0,
         "revision" => state["generation"] + 1,
         "slots" => slots,
         "active" => nil,
         "prepared" => []
       }}
    else
      _ -> {:error, :document_draft_refused}
    end
  rescue
    _ -> {:error, :document_draft_refused}
  end

  @doc "The locked state, not a worker's slot list, decides availability."
  def available_slots(state) do
    reserved = MapSet.new(reserved_slots(state))
    records = state["records"]

    Enum.filter(0..(@slots - 1), fn slot ->
      prefix = "host.stage.#{slot}."

      not MapSet.member?(reserved, slot) and
        not Enum.any?(Map.keys(records), &String.starts_with?(&1, prefix))
    end)
  end

  @doc "Check native stage headers and sealed bodies against each retained head."
  def physical?(state, read) when is_function(read, 1) do
    Enum.all?(heads(state), fn {_, head} ->
      active_physical?(head, head["active"], read) and
        Enum.all?(head["prepared"], &prepared_physical?(head, &1, read))
    end)
  rescue
    _ -> false
  end

  defp active_physical?(_, nil, _), do: true

  defp active_physical?(head, active, read) do
    with {:ok, %{"value" => header}} <- read.(stage_key(active, "header")),
         true <- common_header?(head, active, header),
         true <- header["state"] === "open" and header["write_publish"] === active["publish"],
         true <-
           Map.take(header, ~w(key expected_revision byte_count sha256 offset)) ===
             Map.take(active, ~w(key expected_revision byte_count sha256 offset)),
         {:ok, nil} <- read.(stage_key(active, "ready")) do
      true
    else
      _ -> false
    end
  end

  defp prepared_physical?(head, ref, read) do
    with {:ok, %{"value" => header}} <- read.(stage_key(ref, "header")),
         true <- common_header?(head, ref, header),
         true <- header["state"] === "sealed" and header["offset"] === header["byte_count"],
         {:ok, %{"value" => packed}} <- read.(stage_key(ref, "ready")),
         true <- packed["sha256"] === header["sha256"],
         true <- packed["byte_count"] === header["byte_count"],
         {:ok, _} <- DocumentStage.decode_packed(packed) do
      true
    else
      _ -> false
    end
  end

  defp common_header?(head, ref, header) do
    is_map(header) and header["version"] === 1 and header["epoch"] === ref["epoch"] and
      header["maintenance_epoch"] === head["maintenance_epoch"] and
      DocumentStage.owner?(header["owner"]) and owner(header["owner"]) === head["owner"]
  end

  @doc "Derive a head after authorization and validation of the stage request and native changes."
  def step(head, tag, request, changes, generation) do
    with true <- is_map(head) and tag?(tag) and is_map(request) and is_list(changes),
         true <-
           tag["action"] === "start" or
             (tag["head_id"] === head["id"] and tag["revision"] === head["revision"] and
                tag["unit"] === head["unit"]),
         true <-
           JSON.safe_uint?(generation) and
             if(tag["action"] === "start",
               do: generation === head["revision"],
               else: generation > head["revision"]
             ),
         {:ok, next} <- stage_step(head, tag, request, changes) do
      {:ok, if(is_nil(next), do: nil, else: Map.put(next, "revision", generation))}
    else
      _ -> {:error, :document_draft_refused}
    end
  rescue
    _ -> {:error, :document_draft_refused}
  end

  @doc "Advance only after the caller verifies the actual immutable value under the lock."
  def verified_reuse(head, tag, generation) do
    with true <- tag?(tag) and tag["action"] in ~w(start continue),
         true <-
           tag["action"] === "start" or
             (tag["head_id"] === head["id"] and tag["revision"] === head["revision"] and
                tag["unit"] === head["unit"]),
         true <- is_nil(head["active"]),
         true <- JSON.safe_uint?(generation),
         true <-
           if(tag["action"] === "start",
             do: generation === head["revision"],
             else: generation > head["revision"]
           ),
         {:ok, next} <- advance(head) do
      {:ok, Map.put(next, "revision", generation)}
    else
      _ -> {:error, :document_draft_refused}
    end
  rescue
    _ -> {:error, :document_draft_refused}
  end

  @doc "Derive a cleanup after authorization; the caller supplies the actual idle epoch."
  def retire(head, tag, request, changes, generation, current_epoch) do
    with true <- tag?(tag) and tag["action"] === "retire",
         true <- tag["head_id"] === head["id"] and tag["revision"] === head["revision"],
         true <- JSON.safe_uint?(generation) and generation > head["revision"],
         true <- JSON.safe_uint?(current_epoch) and current_epoch >= head["maintenance_epoch"],
         true <- is_nil(head["retirement_epoch"]) or head["retirement_epoch"] === current_epoch,
         {:ok, reduced} <- retire_stage(head, request, changes) do
      if is_nil(reduced) do
        {:ok, nil}
      else
        {:ok,
         reduced
         |> Map.put("retirement_epoch", current_epoch)
         |> Map.put("revision", generation)}
      end
    else
      _ -> {:error, :document_draft_refused}
    end
  rescue
    _ -> {:error, :document_draft_refused}
  end

  @doc "Bind a partial retirement to its actual native operation and Session invocation."
  def bind_retirement(nil, _, _), do: {:ok, nil}

  def bind_retirement(head, operation_id, invocation_id) do
    if is_map(head) and not is_nil(head["retirement_epoch"]) and id?(operation_id) and
         id?(invocation_id) do
      if Map.has_key?(head, "retirement_operation") do
        {:ok,
         Map.put(head, "retirement_operation", %{
           "operation_id" => operation_id,
           "invocation_id" => invocation_id
         })}
      else
        {:ok, head}
      end
    else
      {:error, :document_draft_refused}
    end
  end

  defp retire_stage(head, %{"op" => "progress.retire"}, []) do
    if is_nil(head["active"]) and head["prepared"] === [],
      do: {:ok, nil},
      else: {:error, :document_draft_refused}
  end

  defp retire_stage(head, %{"op" => "value.abort"} = r, changes) do
    ref = Map.take(r, ~w(slot epoch))
    active = head["active"]
    active_match = is_map(active) and Map.take(active, ~w(slot epoch)) === ref
    prepared_match = ref in head["prepared"]

    with true <- active_match or prepared_match,
         true <- changed_key?(changes, stage_key(ref, "header"), true),
         true <- not prepared_match or changed_key?(changes, stage_key(ref, "ready"), true) do
      reduced = %{
        head
        | "active" => if(active_match, do: nil, else: active),
          "prepared" => List.delete(head["prepared"], ref)
      }

      if is_nil(reduced["active"]) and reduced["prepared"] === [],
        do: {:ok, nil},
        else: {:ok, reduced}
    else
      _ -> {:error, :document_draft_refused}
    end
  end

  defp retire_stage(_, _, _), do: {:error, :document_draft_refused}

  defp stage_step(head, %{"action" => action}, %{"op" => "value.put_inline"} = r, changes)
       when action in ~w(start continue) do
    with true <- is_nil(head["active"]),
         true <- changed_key?(changes, r["key"], false),
         {:ok, next} <- advance(head),
         do: {:ok, next}
  end

  defp stage_step(head, %{"action" => action}, %{"op" => "value.prepare_inline"} = r, changes)
       when action in ~w(start continue) do
    ref = Map.take(r, ~w(slot epoch))

    with true <- is_nil(head["active"]) and available_for_head?(head, ref),
         true <- changed_key?(changes, stage_key(ref, "header"), false),
         true <- changed_key?(changes, stage_key(ref, "ready"), false),
         {:ok, next} <- advance(head),
         do: {:ok, add_prepared(next, ref)}
  end

  defp stage_step(head, %{"action" => action}, %{"op" => "value.write_parts"} = r, changes)
       when action in ~w(start continue) do
    ref = Map.take(r, ~w(slot epoch))
    active = head["active"]
    identity = Map.take(r, ~w(slot epoch key expected_revision byte_count sha256 publish))
    count = Enum.sum(Enum.map(r["data"], &byte_size/1))
    next_offset = r["offset"] + count

    with true <-
           if(is_nil(active),
             do: r["offset"] === 0 and available_for_head?(head, ref),
             else: Map.drop(active, ["offset"]) === identity and active["offset"] === r["offset"]
           ),
         true <- next_offset <= r["byte_count"] do
      if next_offset < r["byte_count"] do
        with true <- changed_key?(changes, stage_key(ref, "header"), false),
             do: {:ok, Map.put(head, "active", Map.put(identity, "offset", next_offset))}
      else
        with true <-
               if(r["publish"],
                 do: changed_key?(changes, r["key"], false),
                 else:
                   changed_key?(changes, stage_key(ref, "header"), false) and
                     changed_key?(changes, stage_key(ref, "ready"), false)
               ),
             {:ok, next} <- advance(Map.put(head, "active", nil)) do
          {:ok, if(r["publish"], do: next, else: add_prepared(next, ref))}
        end
      end
    end
  end

  defp stage_step(head, %{"action" => "finish"}, %{"op" => "commit"} = r, changes) do
    refs = Enum.sort_by(r["stages"], & &1["slot"])

    if head["unit"] === head["unit_limit"] and is_nil(head["active"]) and
         refs !== [] and refs === head["prepared"] and
         Enum.all?(refs, fn ref ->
           changed_key?(changes, stage_key(ref, "header"), true) and
             changed_key?(changes, stage_key(ref, "ready"), true)
         end),
       do: {:ok, nil},
       else: {:error, :document_draft_refused}
  end

  defp stage_step(_, _, _, _), do: {:error, :document_draft_refused}

  defp advance(head) do
    if head["unit"] < head["unit_limit"],
      do: {:ok, Map.update!(head, "unit", &(&1 + 1))},
      else: {:error, :document_draft_refused}
  end

  defp available_for_head?(head, ref) do
    ref["slot"] in head["slots"] and id?(ref["epoch"]) and
      Enum.all?(head["prepared"], &(&1["slot"] !== ref["slot"]))
  end

  defp add_prepared(head, ref),
    do: Map.update!(head, "prepared", &Enum.sort_by([ref | &1], fn item -> item["slot"] end))

  defp stage_key(ref, part), do: "host.stage.#{ref["slot"]}.#{part}"

  defp changed_key?(changes, key, deleted?) do
    Enum.any?(changes, fn change ->
      change["key"] === key and is_nil(change["value"]) === deleted?
    end)
  end

  defp valid_head?(id, h, state, maintenance) do
    known = Migration.known_operations(state)
    initial = known[id]

    (exact?(h, @head_fields) or exact?(h, @head_fields ++ ~w(retirement_operation))) and
      byte_size(Jason.encode!(h)) <= @head_bytes and
      id?(id) and h["id"] === id and
      h["kind"] in ~w(source projection) and owner?(h["owner"], state["project"]) and
      JSON.sha256?(h["plan_sha256"]) and JSON.sha256?(h["body_sha256"]) and
      JSON.safe_uint?(h["maintenance_epoch"]) and
      h["maintenance_epoch"] in 1..maintenance["epoch"] and
      (is_nil(h["retirement_epoch"]) or
         (JSON.safe_uint?(h["retirement_epoch"]) and
            h["retirement_epoch"] in h["maintenance_epoch"]..maintenance["epoch"])) and
      is_integer(h["unit_limit"]) and h["unit_limit"] in 1..32_768 and
      JSON.safe_uint?(h["unit"]) and h["unit"] <= h["unit_limit"] and
      JSON.safe_uint?(h["revision"]) and h["revision"] in 1..state["generation"] and
      is_map(initial) and initial["generation"] <= h["revision"] and
      retirement_operation?(h, state["operations"]) and
      slots?(h["slots"], h["kind"]) and active?(h["active"], h["slots"]) and
      prepared?(h["prepared"], h["slots"], h["active"])
  end

  defp retirement_operation?(head, known) do
    case Map.fetch(head, "retirement_operation") do
      :error ->
        true

      {:ok, nil} ->
        is_nil(head["retirement_epoch"])

      {:ok, operation} ->
        is_map(operation) and exact?(operation, ~w(operation_id invocation_id)) and
          not is_nil(head["retirement_epoch"]) and id?(operation["operation_id"]) and
          id?(operation["invocation_id"]) and
          match?(%{"generation" => _}, known[operation["operation_id"]]) and
          known[operation["operation_id"]]["generation"] === head["revision"]
    end
  end

  defp owner?(owner, namespace) do
    exact?(owner, @owner_fields) and JSON.sha256?(owner["project_id"]) and
      id?(owner["session_id"]) and JSON.sha256?(owner["identity_sha256"]) and
      CollectionStore.namespace(owner["project_id"]) === namespace
  end

  defp slots?(slots, kind) do
    count = if kind === "source", do: 3, else: 2

    is_list(slots) and length(slots) == count and
      Enum.all?(slots, &(is_integer(&1) and &1 in 0..(@slots - 1))) and
      slots === Enum.sort(Enum.uniq(slots))
  end

  defp active?(nil, _), do: true

  defp active?(active, slots) do
    exact?(active, @active_fields) and active["slot"] in slots and id?(active["epoch"]) and
      Directory.key?(active["key"]) and not String.starts_with?(active["key"], "host.") and
      JSON.safe_uint?(active["expected_revision"]) and
      is_integer(active["byte_count"]) and active["byte_count"] in 2..61_440 and
      JSON.sha256?(active["sha256"]) and JSON.safe_uint?(active["offset"]) and
      active["offset"] < active["byte_count"] and is_boolean(active["publish"])
  end

  defp prepared?(prepared, slots, active) do
    is_list(prepared) and length(prepared) <= length(slots) and
      Enum.all?(prepared, fn ref ->
        exact?(ref, ~w(slot epoch)) and ref["slot"] in slots and id?(ref["epoch"])
      end) and
      length(Enum.uniq_by(prepared, & &1["slot"])) === length(prepared) and
      prepared === Enum.sort_by(prepared, & &1["slot"]) and
      (is_nil(active) or Enum.all?(prepared, &(&1["slot"] !== active["slot"])))
  end

  defp unique_slots?(heads) do
    slots = heads |> Map.values() |> Enum.flat_map(& &1["slots"])
    length(Enum.uniq(slots)) === length(slots)
  end

  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)
  defp exact?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) === Enum.sort(keys)
end
