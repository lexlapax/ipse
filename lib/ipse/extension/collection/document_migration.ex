defmodule Ipse.Extension.Collection.DocumentMigration do
  @moduledoc false
  alias Ipse.JSON

  alias Ipse.Extension.Collection.{
    DocumentDraft,
    DocumentMaintenance,
    Encoding,
    Migration,
    Profile
  }

  @reads ~w(backup.describe backup.metadata backup.plan backup.page)
  @migration_fields ~w(version id descriptor records after imported_operations operation_after operation_count operation_digest seen_required_anchor seen_source_anchor record_page_hashes seen_lineage_count owner epoch opening_epoch opening_generation opening_sha256 plan_records page_counts next_page source_ids data_inputs data_bindings dependency_union_sha256 plan_binding_sha256)

  def read?(r), do: r["op"] in @reads
  def input?(r), do: r["op"] in ~w(restore.open restore.page)
  def sdk_request?(r), do: request?(r) and r["op"] not in ~w(backup.plan backup.page)

  def request?(r) when is_map(r) do
    fields =
      case r["op"] do
        op when op in ~w(backup.describe backup.plan) ->
          ~w(op generation)

        "backup.page" ->
          ~w(op generation after limit)

        "backup.metadata" ->
          ~w(op generation section offset limit)

        "restore.open" ->
          ~w(op expected_generation expected_epoch input_sha256 plan_binding_sha256 dependency_union_sha256)

        "restore.page" ->
          ~w(op expected_generation expected_epoch migration_id ordinal input_sha256 data_binding_sha256 plan_binding_sha256 dependency_union_sha256)

        op when op in ~w(restore.commit restore.abort) ->
          ~w(op expected_generation expected_epoch migration_id plan_binding_sha256 dependency_union_sha256)

        op when op in ~w(restore.rollback restore.checkpoint_drop) ->
          ~w(op expected_generation expected_epoch checkpoint_id plan_binding_sha256 dependency_union_sha256)

        _ ->
          []
      end

    fields != [] and exact?(r, fields) and
      if(read?(r),
        do: uint?(r["generation"]),
        else: uint?(r["expected_generation"]) and uint?(r["expected_epoch"])
      ) and
      (not input?(r) or JSON.sha256?(r["input_sha256"])) and
      (read?(r) or
         (JSON.sha256?(r["plan_binding_sha256"]) and JSON.sha256?(r["dependency_union_sha256"]))) and
      (r["op"] !== "restore.page" or JSON.sha256?(r["data_binding_sha256"])) and
      (r["op"] != "backup.page" or
         ((is_nil(r["after"]) or key?(r["after"])) and is_integer(r["limit"]) and
            r["limit"] in 1..8)) and
      (r["op"] !== "backup.metadata" or
         (r["section"] in ~w(records operations lineage) and
            uint?(r["offset"]) and r["offset"] <= 32_768 and is_integer(r["limit"]) and
            r["limit"] in 1..8)) and
      (not Map.has_key?(r, "migration_id") or id?(r["migration_id"])) and
      (not Map.has_key?(r, "checkpoint_id") or id?(r["checkpoint_id"])) and
      (r["op"] != "restore.page" or uint?(r["ordinal"]))
  rescue
    _ -> false
  end

  def request?(_), do: false

  def descriptor(s) do
    Migration.descriptor(s)
    |> Map.merge(%{
      "version" => 4,
      "profile" => Profile.documents(),
      "maintenance_epoch" => DocumentMaintenance.metadata(s)["epoch"],
      "envelopes_sha256" => JSON.digest([rows(s["records"])])
    })
  end

  def compact_descriptor(s),
    do:
      descriptor(s)
      |> Map.delete("floor_lineage")
      |> Map.put("floor_lineage_count", length(s["floor_lineage"]))

  def metadata(s, r) do
    all =
      case r["section"] do
        "records" ->
          rows(s["records"])

        "operations" ->
          Migration.operations(s)
          |> Enum.sort()
          |> Enum.map(fn {id, receipt} -> [id, receipt] end)

        "lineage" ->
          s["floor_lineage"]
      end

    selected = Enum.slice(all, r["offset"], r["limit"])

    %{
      "version" => 1,
      "generation" => s["generation"],
      "section" => r["section"],
      "offset" => r["offset"],
      "next" =>
        if(r["offset"] + length(selected) < length(all), do: r["offset"] + length(selected)),
      "descriptor" => compact_descriptor(s),
      "rows" => selected
    }
  end

  def valid_result?(r, status, value, operation_id, owner) do
    request?(r) and Ipse.Extension.Collection.DocumentStage.owner?(owner) and
      Ipse.Extension.validate(value) === :ok and
      case {r["op"], status} do
        {"backup.describe", "ok"} ->
          exact?(value, ~w(descriptor)) and compact_descriptor?(value["descriptor"], r, owner)

        {"backup.metadata", "ok"} ->
          metadata_result?(r, value, owner)

        {op, "ok"} when op not in @reads ->
          receipt_result?(r, value, owner, operation_id)

        {op, "existing"} when op not in @reads ->
          exact?(value, ~w(version project generation floor floor_anchor operation)) and
            summary?(value, owner) and receipt_result?(r, value["operation"], owner, operation_id)

        {_, "conflict"} ->
          exact?(value, ~w(version project generation floor floor_anchor)) and
            summary?(value, owner)

        {_, "failed"} ->
          exact?(value, ~w(version project generation floor floor_anchor code)) and
            summary?(value, owner) and
            value["code"] in ~w(collection_operation_identity collection_document_epoch collection_import_state collection_import_plan collection_import_incomplete collection_import_lineage collection_rollback_floor collection_capacity collection_writer_fenced)

        _ ->
          false
      end
  rescue
    _ -> false
  end

  defp receipt_result?(r, receipt, owner, operation_id) do
    Migration.receipt?(receipt) and receipt["generation"] === r["expected_generation"] + 1 and
      receipt["request_sha256"] === JSON.digest([r, DocumentDraft.owner(owner)]) and
      case r["op"] do
        "restore.open" ->
          exact?(receipt, ~w(generation floor request_sha256 migration_id)) and
            receipt["migration_id"] === operation_id

        "restore.page" ->
          exact?(receipt, ~w(generation floor request_sha256 migration_id)) and
            receipt["migration_id"] === r["migration_id"]

        "restore.commit" ->
          exact?(receipt, ~w(generation floor request_sha256 checkpoint_id)) and
            (is_nil(receipt["checkpoint_id"]) or receipt["checkpoint_id"] === operation_id)

        _ ->
          exact?(receipt, ~w(generation floor request_sha256))
      end
  end

  defp metadata_result?(r, v, owner) do
    total =
      v["descriptor"][
        case r["section"] do
          "lineage" -> "floor_lineage_count"
          section -> section
        end
      ]

    exact?(v, ~w(version generation section offset next descriptor rows)) and v["version"] === 1 and
      v["generation"] === r["generation"] and v["section"] === r["section"] and
      v["offset"] === r["offset"] and
      compact_descriptor?(v["descriptor"], r, owner) and is_list(v["rows"]) and
      length(v["rows"]) <= r["limit"] and
      r["offset"] <= total and length(v["rows"]) === min(r["limit"], total - r["offset"]) and
      v["next"] ===
        if(r["offset"] + length(v["rows"]) < total, do: r["offset"] + length(v["rows"])) and
      case r["section"] do
        "records" ->
          Enum.all?(v["rows"], &row?/1) and ordered_unique?(Enum.map(v["rows"], &hd/1))

        "operations" ->
          Enum.all?(v["rows"], fn
            [id, receipt] -> id?(id) and Migration.receipt?(receipt)
            _ -> false
          end) and ordered_unique?(Enum.map(v["rows"], &hd/1))

        "lineage" ->
          Enum.all?(v["rows"], &id?/1) and length(Enum.uniq(v["rows"])) === length(v["rows"])
      end
  end

  defp compact_descriptor?(d, r, owner) do
    keys =
      ~w(version profile project generation maintenance_epoch floor floor_anchor floor_lineage_count floor_lineage_sha256 records data_bytes records_sha256 operations operations_sha256 envelopes_sha256)

    exact?(d, keys) and d["version"] === 4 and d["profile"] === Profile.documents() and
      d["project"] === Ipse.Extension.CollectionStore.namespace(owner["project_id"]) and
      d["generation"] === r["generation"] and
      uint?(d["maintenance_epoch"]) and
      uint?(d["floor"]) and is_integer(d["floor_lineage_count"]) and
      d["floor_lineage_count"] in 0..32_768 and
      ((d["floor"] === 0 and d["floor_anchor"] === nil and d["floor_lineage_count"] === 0) or
         (d["floor"] > 0 and id?(d["floor_anchor"]) and d["floor_lineage_count"] > 0)) and
      Enum.all?(
        ~w(floor_lineage_sha256 records_sha256 operations_sha256 envelopes_sha256),
        &JSON.sha256?(d[&1])
      ) and
      is_integer(d["records"]) and d["records"] in 0..8192 and is_integer(d["operations"]) and
      d["operations"] in 0..32_768 and
      is_integer(d["data_bytes"]) and d["data_bytes"] in 0..(160 * 1024 * 1024)
  end

  defp summary?(v, owner),
    do:
      v["version"] === 3 and
        v["project"] === Ipse.Extension.CollectionStore.namespace(owner["project_id"]) and
        uint?(v["generation"]) and uint?(v["floor"]) and
        ((v["floor"] === 0 and is_nil(v["floor_anchor"])) or id?(v["floor_anchor"]))

  defp ordered_unique?(keys), do: keys === Enum.sort(Enum.uniq(keys))

  def export_plan(s) do
    %{
      "descriptor" => descriptor(s),
      "plan" => %{
        "version" => 2,
        "records" => rows(s["records"]),
        "operations" => Encoding.pack_receipts(Migration.operations(s)),
        "page_counts" => s["records"] |> map_size() |> counts(),
        "data_inputs" => nil,
        "data_bindings" => nil,
        "dependency_union_sha256" => nil
      }
    }
  end

  def descriptor?(d) do
    is_map(d) and
      exact?(
        d,
        ~w(version profile project generation maintenance_epoch floor floor_anchor floor_lineage floor_lineage_sha256 records data_bytes records_sha256 operations operations_sha256 envelopes_sha256)
      ) and
      d["version"] === 4 and d["profile"] === Profile.documents() and
      JSON.sha256?(d["envelopes_sha256"]) and
      JSON.sha256?(d["project"]) and uint?(d["generation"]) and uint?(d["maintenance_epoch"]) and
      uint?(d["floor"]) and
      is_list(d["floor_lineage"]) and length(d["floor_lineage"]) <= 32_768 and
      Enum.all?(d["floor_lineage"], &id?/1) and
      length(Enum.uniq(d["floor_lineage"])) == length(d["floor_lineage"]) and
      ((d["floor"] === 0 and d["floor_anchor"] === nil and d["floor_lineage"] === []) or
         (id?(d["floor_anchor"]) and List.last(d["floor_lineage"]) === d["floor_anchor"])) and
      d["floor_lineage_sha256"] === JSON.digest([d["floor_lineage"]]) and
      is_integer(d["records"]) and d["records"] in 0..8192 and
      is_integer(d["data_bytes"]) and d["data_bytes"] in 0..(160 * 1024 * 1024) and
      is_integer(d["operations"]) and d["operations"] in 0..32_768 and
      JSON.sha256?(d["records_sha256"]) and JSON.sha256?(d["operations_sha256"])
  rescue
    _ -> false
  end

  def plan(s, input) do
    with true <- exact?(input, ~w(descriptor plan)) and descriptor?(input["descriptor"]),
         d = input["descriptor"],
         p = input["plan"],
         true <-
           exact?(
             p,
             ~w(version records operations page_counts data_inputs data_bindings dependency_union_sha256)
           ) and p["version"] === 2,
         true <- byte_size(Migration.encode(input)) <= 8 * 1024 * 1024,
         list when is_list(list) and length(list) <= 8192 <- p["records"],
         true <- Enum.all?(list, &row?/1),
         keys = Enum.map(list, &hd/1),
         true <- keys === Enum.sort(Enum.uniq(keys)),
         {:ok, operations} <- Encoding.unpack_receipts(p["operations"]),
         true <- Encoding.pack_receipts(operations) === p["operations"],
         records = records(list),
         true <-
           map_size(records) === d["records"] and Migration.bytes(records) === d["data_bytes"] and
             Migration.digest(records) === d["records_sha256"] and
             JSON.digest([list]) === d["envelopes_sha256"] and
             map_size(operations) === d["operations"] and
             Migration.operation_digest(operations) === d["operations_sha256"],
         true <-
           Enum.all?(records, fn {_, r} ->
             r["revision"] <= d["generation"] and
               get_in(operations, [r["operation_id"], "generation"]) === r["revision"]
           end),
         true <- counts?(p["page_counts"], d["records"]),
         true <-
           is_list(p["data_inputs"]) and length(p["data_inputs"]) === length(p["page_counts"]) and
             Enum.all?(p["data_inputs"], &selected_input?/1),
         true <-
           p["data_bindings"] === Enum.map(p["data_inputs"], &JSON.digest([&1])) and
             JSON.sha256?(p["dependency_union_sha256"]),
         true <-
           d["project"] === s["project"] and d["floor"] >= s["floor"] and
             Migration.lineage_extends?(s["floor_lineage"], d["floor_lineage"]) and
             Migration.valid_lineage?(
               d["floor_lineage"],
               d["floor_anchor"],
               d["floor"],
               operations
             ),
         known = Migration.known_operations(s),
         true <-
           Enum.all?(operations, fn {id, receipt} ->
             is_nil(known[id]) or known[id] === receipt
           end),
         true <-
           is_nil(s["floor_anchor"]) or operations[s["floor_anchor"]] === known[s["floor_anchor"]] do
      {:ok,
       %{
         descriptor: d,
         records: records,
         aliases: Map.drop(operations, Map.keys(known)),
         operations: operations,
         counts: p["page_counts"],
         hashes: page_hashes(records, p["page_counts"])
       }}
    else
      _ -> {:failed, "collection_import_plan"}
    end
  rescue
    _ -> {:failed, "collection_import_plan"}
  end

  def quiescent?(s),
    do:
      map_size(DocumentDraft.heads(s)) === 0 and
        Enum.all?(Map.keys(s["records"]), &(not String.starts_with?(&1, "host.")))

  def prepare(s, %{"op" => "restore.open"} = r, id, owner, input) do
    m = DocumentMaintenance.metadata(s)

    with true <-
           m["status"] === "idle" and is_nil(s["migration"]) and is_nil(s["checkpoint"]) and
             quiescent?(s),
         {:ok, p} <- plan(s, input),
         epoch = max(m["epoch"], p.descriptor["maintenance_epoch"]) + 1,
         true <- uint?(epoch),
         true <-
           not Map.has_key?(p.operations, id) and
             r["dependency_union_sha256"] === input["plan"]["dependency_union_sha256"],
         :ok <-
           if(
             map_size(Migration.known_operations(s)) + map_size(p.aliases) + length(p.counts) + 3 <=
               32_768,
             do: :ok,
             else: {:failed, "collection_capacity"}
           ) do
      migration = %{
        "version" => 1,
        "id" => id,
        "descriptor" => p.descriptor,
        "records" => %{},
        "after" => nil,
        "imported_operations" => p.aliases,
        "operation_after" => p.operations |> Map.keys() |> Enum.sort() |> List.last(),
        "operation_count" => p.descriptor["operations"],
        "operation_digest" => p.descriptor["operations_sha256"],
        "seen_required_anchor" => true,
        "seen_source_anchor" => true,
        "record_page_hashes" => p.hashes,
        "seen_lineage_count" => length(p.descriptor["floor_lineage"]),
        "owner" => DocumentDraft.owner(owner),
        "epoch" => epoch,
        "opening_epoch" => m["epoch"],
        "opening_generation" => s["generation"] + 1,
        "opening_sha256" => JSON.digest([descriptor(s), r, DocumentDraft.owner(owner)]),
        "plan_records" => p.records,
        "page_counts" => p.counts,
        "next_page" => 0,
        "source_ids" => p.operations |> Map.keys() |> Enum.sort(),
        "data_inputs" => input["plan"]["data_inputs"],
        "data_bindings" => input["plan"]["data_bindings"],
        "dependency_union_sha256" => r["dependency_union_sha256"],
        "plan_binding_sha256" => r["plan_binding_sha256"]
      }

      active = %{
        "version" => 2,
        "status" => "active",
        "purpose" => "document_import",
        "epoch" => epoch,
        "maintenance_id" => id,
        "owner" => migration["owner"],
        "opening_generation" => migration["opening_generation"],
        "opening_sha256" => migration["opening_sha256"]
      }

      {:ok, s |> Map.put("migration", migration) |> Map.put("document_maintenance", active), %{},
       %{"migration_id" => id}}
    else
      {:failed, _} = failed -> failed
      _ -> {:failed, "collection_import_state"}
    end
  end

  def prepare(s, %{"op" => "restore.page"} = r, id, owner, input) do
    with m when is_map(m) <- s["migration"],
         true <- owned?(m, r, owner),
         true <- r["ordinal"] === m["next_page"],
         true <- r["data_binding_sha256"] === Enum.at(m["data_bindings"], m["next_page"]),
         true <-
           exact?(input, ~w(descriptor records next)) and input["descriptor"] === m["descriptor"] and
             is_list(input["records"]),
         true <- length(input["records"]) === Enum.at(m["page_counts"], m["next_page"]),
         true <-
           Enum.all?(input["records"], fn row ->
             exact?(row, ~w(key value revision operation_id sha256 bytes)) and
               m["plan_records"][row["key"]] === Map.delete(row, "value") and
               packed?(row["value"])
           end),
         true <-
           input["next"] ===
             if(m["next_page"] + 1 === length(m["page_counts"]),
               do: nil,
               else: List.last(input["records"])["key"]
             ),
         rows =
           Enum.map(input["records"], fn row ->
             bytes = Migration.encode(row["value"])
             [row["key"], JSON.sha256(bytes), byte_size(bytes)]
           end),
         true <- JSON.digest([rows]) === Enum.at(m["record_page_hashes"], m["next_page"]) do
      {records, values} =
        Enum.reduce(input["records"], {m["records"], %{}}, fn row, {records, values} ->
          bytes = Migration.encode(row["value"])
          hash = JSON.sha256(bytes)

          record = %{
            "key" => row["key"],
            "revision" => s["generation"] + 1,
            "sha256" => hash,
            "bytes" => byte_size(bytes),
            "operation_id" => id
          }

          {Map.put(records, row["key"], record), Map.put(values, hash, bytes)}
        end)

      m = %{
        m
        | "records" => records,
          "after" => List.last(input["records"])["key"],
          "next_page" => m["next_page"] + 1
      }

      {:ok, %{s | "migration" => m}, values, %{"migration_id" => m["id"]}}
    else
      _ -> {:failed, "collection_import_state"}
    end
  end

  def prepare(s, %{"op" => op} = r, id, owner, _) when op in ~w(restore.commit restore.abort) do
    with m when is_map(m) <- s["migration"],
         true <- owned?(m, r, owner),
         true <- op !== "restore.commit" or m["next_page"] === length(m["page_counts"]),
         {:ok, next, values, extra} <-
           Migration.prepare(
             s,
             %{
               "op" => String.replace(op, "restore.", "import."),
               "migration_id" => r["migration_id"]
             },
             id
           ) do
      checkpoint =
        if next["checkpoint"],
          do:
            next["checkpoint"]
            |> Map.put("document_owner", m["owner"])
            |> Map.put("document_epoch", m["epoch"])
            |> Map.put("migration_id", m["id"])
            |> Map.put("dependency_union_sha256", m["dependency_union_sha256"])
            |> Map.put("plan_binding_sha256", m["plan_binding_sha256"]),
          else: nil

      {:ok,
       next
       |> Map.put("checkpoint", checkpoint)
       |> Map.put("document_maintenance", idle(m["epoch"])), values, extra}
    else
      {:failed, _} = failed -> failed
      _ -> {:failed, "collection_import_state"}
    end
  end

  def prepare(s, %{"op" => op} = r, id, owner, _)
      when op in ~w(restore.rollback restore.checkpoint_drop) do
    m = DocumentMaintenance.metadata(s)
    c = s["checkpoint"]

    with true <- m["status"] === "idle" and quiescent?(s) and is_nil(s["migration"]),
         true <-
           is_map(c) and c["id"] === r["checkpoint_id"] and
             c["document_owner"] === DocumentDraft.owner(owner) and
             c["dependency_union_sha256"] === r["dependency_union_sha256"] and
             c["plan_binding_sha256"] === r["plan_binding_sha256"],
         true <- c["floor"] === s["floor"] and uint?(m["epoch"] + 1),
         internal = %{
           "op" => if(op === "restore.rollback", do: "rollback", else: "checkpoint.drop"),
           "checkpoint_id" => r["checkpoint_id"]
         },
         {:ok, next, values, extra} <- Migration.prepare(s, internal, id) do
      epoch = if op === "restore.rollback", do: m["epoch"] + 1, else: m["epoch"]
      {:ok, Map.put(next, "document_maintenance", idle(epoch)), values, extra}
    else
      _ -> {:failed, "collection_rollback_floor"}
    end
  end

  def prepare(_, _, _, _, _), do: {:failed, "collection_import_state"}

  def active?(s), do: match?(%{"version" => 1}, s["migration"])

  def reserved_slots(s) do
    if active?(s),
      do: length(s["migration"]["page_counts"]) - s["migration"]["next_page"] + 2,
      else: 0
  end

  def valid?(s, valid_records) do
    m = s["migration"]

    with true <- exact?(m, @migration_fields) and m["version"] === 1 and id?(m["id"]),
         true <- valid_records.(m["records"]) and descriptor?(m["descriptor"]),
         true <-
           is_map(m["plan_records"]) and
             JSON.digest([rows(m["plan_records"])]) === m["descriptor"]["envelopes_sha256"],
         true <- counts?(m["page_counts"], map_size(m["plan_records"])),
         true <- uint?(m["next_page"]) and m["next_page"] <= length(m["page_counts"]),
         true <- m["record_page_hashes"] === page_hashes(m["plan_records"], m["page_counts"]),
         true <- prefix?(m),
         true <- maintenance_valid?(s),
         known = Migration.known_operations(s),
         {:ok, verified} <- plan(s, plan_input(m, known)),
         true <- verified.records === m["plan_records"] do
      m["operation_count"] === m["descriptor"]["operations"] and
        m["operation_digest"] === m["descriptor"]["operations_sha256"] and
        m["imported_operations"] ===
          Map.drop(Map.take(known, m["source_ids"]), Map.keys(Migration.operations(s))) and
        m["source_ids"] === Enum.sort(Enum.uniq(m["source_ids"])) and
        length(m["source_ids"]) === m["operation_count"] and
        m["operation_after"] === List.last(m["source_ids"]) and
        m["seen_required_anchor"] === true and m["seen_source_anchor"] === true and
        m["seen_lineage_count"] === length(m["descriptor"]["floor_lineage"])
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def maintenance_valid?(s) do
    m = s["migration"]
    a = DocumentMaintenance.metadata(s)
    known = Migration.known_operations(s)

    request = %{
      "op" => "restore.open",
      "expected_generation" => m["opening_generation"] - 1,
      "expected_epoch" => m["opening_epoch"],
      "input_sha256" => JSON.sha256(Migration.encode(plan_input(m, known))),
      "dependency_union_sha256" => m["dependency_union_sha256"],
      "plan_binding_sha256" => m["plan_binding_sha256"]
    }

    before =
      Map.put(
        %{
          s
          | "generation" => m["opening_generation"] - 1,
            "operations" =>
              Map.reject(s["operations"], fn {_, r} ->
                r["generation"] >= m["opening_generation"]
              end)
        },
        "document_maintenance",
        idle(m["opening_epoch"])
      )

    is_map(m) and active?(s) and
      a === %{
        "version" => 2,
        "status" => "active",
        "purpose" => "document_import",
        "epoch" => m["epoch"],
        "maintenance_id" => m["id"],
        "owner" => m["owner"],
        "opening_generation" => m["opening_generation"],
        "opening_sha256" => m["opening_sha256"]
      } and
      uint?(m["epoch"]) and m["epoch"] > 0 and JSON.sha256?(m["opening_sha256"]) and
      uint?(m["opening_epoch"]) and
      m["epoch"] === max(m["opening_epoch"], m["descriptor"]["maintenance_epoch"]) + 1 and
      JSON.sha256?(m["plan_binding_sha256"]) and JSON.sha256?(m["dependency_union_sha256"]) and
      m["opening_generation"] in 1..s["generation"] and
      get_in(s, ["operations", m["id"], "generation"]) === m["opening_generation"] and
      get_in(s, ["operations", m["id"], "request_sha256"]) === JSON.digest([request, m["owner"]]) and
      m["opening_sha256"] === JSON.digest([descriptor(before), request, m["owner"]]) and
      owner?(m["owner"], s["project"])
  rescue
    _ -> false
  end

  def checkpoint?(c, s, valid_records) do
    receipt = Migration.known_operations(s)[c["id"]]

    request = %{
      "op" => "restore.commit",
      "expected_generation" => c["generation"],
      "expected_epoch" => c["document_epoch"],
      "migration_id" => c["migration_id"],
      "plan_binding_sha256" => c["plan_binding_sha256"],
      "dependency_union_sha256" => c["dependency_union_sha256"]
    }

    exact?(
      c,
      ~w(id generation floor floor_anchor floor_lineage_sha256 records document_owner document_epoch migration_id dependency_union_sha256 plan_binding_sha256)
    ) and
      id?(c["id"]) and uint?(c["generation"]) and c["generation"] <= s["generation"] and
      id?(c["migration_id"]) and is_map(receipt) and receipt["checkpoint_id"] === c["id"] and
      receipt["generation"] === c["generation"] + 1 and receipt["floor"] === c["floor"] and
      receipt["request_sha256"] === JSON.digest([request, c["document_owner"]]) and
      c["floor"] === s["floor"] and c["floor_anchor"] === s["floor_anchor"] and
      c["floor_lineage_sha256"] === JSON.digest([s["floor_lineage"]]) and
      valid_records.(c["records"]) and Migration.bytes(c["records"]) <= 160 * 1024 * 1024 and
      owner?(c["document_owner"], s["project"]) and JSON.sha256?(c["dependency_union_sha256"]) and
      JSON.sha256?(c["plan_binding_sha256"]) and uint?(c["document_epoch"]) and
      c["document_epoch"] > 0 and
      c["document_epoch"] <= DocumentMaintenance.metadata(s)["epoch"]
  rescue
    _ -> false
  end

  def forecast(s) do
    m = s["migration"]
    remaining = length(m["page_counts"]) - m["next_page"]
    known = Migration.known_operations(s)

    ids =
      Enum.map(
        0..32_768,
        &(Integer.to_string(&1, 16) |> String.downcase() |> String.pad_leading(32, "0"))
      )
      |> Enum.reject(&Map.has_key?(known, &1))
      |> Enum.take(remaining)

    true = length(ids) === remaining

    future =
      Enum.reduce(ids, s, fn id, state ->
        receipt = %{
          "generation" => state["generation"] + 1,
          "floor" => state["floor"],
          "request_sha256" => String.duplicate("f", 64),
          "migration_id" => m["id"]
        }

        %{
          state
          | "generation" => receipt["generation"],
            "operations" => Map.put(state["operations"], id, receipt)
        }
      end)

    records =
      Map.new(m["plan_records"], fn {k, r} ->
        {k,
         %{r | "revision" => future["generation"], "operation_id" => List.last(ids) || m["id"]}}
      end)

    future
    |> put_in(["migration", "records"], records)
    |> put_in(["migration", "after"], records |> Map.keys() |> Enum.sort() |> List.last())
    |> put_in(["migration", "next_page"], length(m["page_counts"]))
  end

  defp plan_input(m, known),
    do: %{
      "descriptor" => m["descriptor"],
      "plan" => %{
        "version" => 2,
        "records" => rows(m["plan_records"]),
        "operations" => Encoding.pack_receipts(Map.take(known, m["source_ids"])),
        "page_counts" => m["page_counts"],
        "data_inputs" => m["data_inputs"],
        "data_bindings" => m["data_bindings"],
        "dependency_union_sha256" => m["dependency_union_sha256"]
      }
    }

  def packed?(value) do
    with true <-
           exact?(value, ~w(version kind sha256 byte_count parts)) and value["version"] === 1 and
             value["kind"] === "document_value",
         true <-
           JSON.sha256?(value["sha256"]) and is_integer(value["byte_count"]) and
             value["byte_count"] in 2..61_440,
         parts when is_list(parts) and length(parts) in 1..10 <- value["parts"],
         true <-
           Enum.all?(parts, &(is_binary(&1) and String.valid?(&1) and byte_size(&1) in 1..6144)),
         bytes = IO.iodata_to_binary(parts),
         true <-
           byte_size(bytes) === value["byte_count"] and JSON.sha256(bytes) === value["sha256"],
         {:ok, _} <- Ipse.Extension.ResultDocument.decode(bytes, %{"type" => "object"}),
         true <- byte_size(Migration.encode(value)) <= 65_536 do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp prefix?(m) do
    count = m["page_counts"] |> Enum.take(m["next_page"]) |> Enum.sum()
    keys = m["plan_records"] |> Map.keys() |> Enum.sort() |> Enum.take(count)

    Enum.sort(Map.keys(m["records"])) === keys and m["after"] === List.last(keys) and
      Enum.all?(m["records"], fn {k, r} ->
        p = m["plan_records"][k]
        r["sha256"] === p["sha256"] and r["bytes"] === p["bytes"]
      end)
  end

  defp owned?(m, r, owner),
    do:
      m["version"] === 1 and m["id"] === r["migration_id"] and
        m["owner"] === DocumentDraft.owner(owner) and m["epoch"] === r["expected_epoch"] and
        m["plan_binding_sha256"] === r["plan_binding_sha256"] and
        m["dependency_union_sha256"] === r["dependency_union_sha256"]

  defp idle(epoch), do: %{"version" => 1, "status" => "idle", "epoch" => epoch}

  defp owner?(o, namespace),
    do:
      exact?(o, ~w(project_id session_id identity_sha256)) and
        JSON.sha256?(o["project_id"]) and JSON.sha256?(o["identity_sha256"]) and
        id?(o["session_id"]) and
        Ipse.Extension.CollectionStore.namespace(o["project_id"]) === namespace

  defp rows(records),
    do:
      records
      |> Enum.sort()
      |> Enum.map(fn {k, r} -> [k, r["revision"], r["operation_id"], r["sha256"], r["bytes"]] end)

  defp records(rows),
    do:
      Map.new(rows, fn [k, r, id, h, b] ->
        {k, %{"key" => k, "revision" => r, "operation_id" => id, "sha256" => h, "bytes" => b}}
      end)

  defp row?([k, r, id, h, b]),
    do:
      key?(k) and uint?(r) and r > 0 and id?(id) and JSON.sha256?(h) and is_integer(b) and
        b in 2..65_536

  defp row?(_), do: false

  defp page_hashes(records, counts) do
    {hashes, []} =
      Enum.map_reduce(counts, Enum.sort(records), fn n, rows ->
        {part, rest} = Enum.split(rows, n)
        {JSON.digest([Enum.map(part, fn {k, r} -> [k, r["sha256"], r["bytes"]] end)]), rest}
      end)

    hashes
  end

  defp counts(0), do: []
  defp counts(n), do: [min(8, n) | counts(max(n - 8, 0))]

  defp counts?(list, n),
    do:
      is_list(list) and length(list) <= 8192 and Enum.all?(list, &(is_integer(&1) and &1 in 1..8)) and
        Enum.sum(list) === n

  defp uint?(n), do: JSON.safe_uint?(n)

  defp selected_input?(ref),
    do:
      exact?(ref, ~w(version session_id delivery)) and ref["version"] === 1 and
        id?(ref["session_id"]) and Ipse.Extension.ResultSource.valid_descriptor?(ref["delivery"])

  defp id?(s), do: is_binary(s) and Regex.match?(~r/\A[a-f0-9]{32}\z/, s)

  defp key?(s),
    do:
      is_binary(s) and Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,95}\z/, s) and
        not String.starts_with?(s, "host.")

  defp exact?(m, fields), do: is_map(m) and Enum.sort(Map.keys(m)) === Enum.sort(fields)
end
