defmodule Ipse.Extension.Collection.Migration do
  @moduledoc false
  alias Ipse.JSON
  alias Ipse.Extension.Collection.Planning
  @record_limit 8192
  @data_limit 24 * 1024 * 1024

  def request?(%{"op" => "export"} = r),
    do:
      keys?(r, ~w(op generation after limit)) and uint?(r["generation"]) and
        (is_nil(r["after"]) or key?(r["after"])) and is_integer(r["limit"]) and
        r["limit"] in 1..32

  def request?(%{"op" => "import.open"} = r),
    do:
      keys?(
        r,
        if(Map.has_key?(r, "plan"),
          do: ~w(op expected_generation descriptor plan),
          else: ~w(op expected_generation descriptor)
        )
      ) and uint?(r["expected_generation"]) and
        descriptor?(r["descriptor"]) and
        (not Map.has_key?(r, "plan") or Planning.shape?(r["plan"]))

  def request?(%{"op" => "export.plan"} = r),
    do: keys?(r, ~w(op generation)) and uint?(r["generation"])

  def request?(%{"op" => "export.operations"} = r),
    do:
      keys?(r, ~w(op generation after limit)) and uint?(r["generation"]) and
        (is_nil(r["after"]) or id?(r["after"])) and is_integer(r["limit"]) and
        r["limit"] in 1..128

  def request?(%{"op" => "import.operations"} = r) do
    keys?(r, ~w(op expected_generation migration_id after operations)) and
      uint?(r["expected_generation"]) and
      id?(r["migration_id"]) and (is_nil(r["after"]) or id?(r["after"])) and
      is_list(r["operations"]) and length(r["operations"]) in 1..128 and
      Enum.all?(r["operations"], fn row ->
        keys?(row, ~w(operation_id receipt)) and id?(row["operation_id"]) and
          receipt?(row["receipt"])
      end) and
      Enum.map(r["operations"], & &1["operation_id"]) ==
        Enum.sort(Enum.uniq(Enum.map(r["operations"], & &1["operation_id"])))
  rescue
    _ -> false
  end

  def request?(%{"op" => "import.page"} = r) do
    keys?(r, ~w(op expected_generation migration_id after records)) and
      uint?(r["expected_generation"]) and
      id?(r["migration_id"]) and (is_nil(r["after"]) or key?(r["after"])) and
      is_list(r["records"]) and length(r["records"]) in 1..32 and
      Enum.all?(r["records"], fn row ->
        keys?(row, ~w(key value)) and key?(row["key"]) and value?(row["value"])
      end) and
      Enum.map(r["records"], & &1["key"]) ==
        Enum.sort(Enum.uniq(Enum.map(r["records"], & &1["key"])))
  rescue
    _ -> false
  end

  def request?(%{"op" => op} = r) when op in ~w(import.commit import.abort),
    do:
      keys?(r, ~w(op expected_generation migration_id)) and uint?(r["expected_generation"]) and
        id?(r["migration_id"])

  def request?(%{"op" => "rollback"} = r),
    do:
      keys?(r, ~w(op expected_generation checkpoint_id)) and uint?(r["expected_generation"]) and
        id?(r["checkpoint_id"])

  def request?(%{"op" => "checkpoint.drop"} = r),
    do: keys?(r, ~w(op expected_generation)) and uint?(r["expected_generation"])

  def request?(_), do: false

  def descriptor(s) do
    %{
      "version" => 3,
      "project" => s["project"],
      "generation" => s["generation"],
      "floor" => s["floor"],
      "floor_anchor" => s["floor_anchor"],
      "floor_lineage" => s["floor_lineage"],
      "floor_lineage_sha256" => JSON.digest([s["floor_lineage"]]),
      "records" => map_size(s["records"]),
      "data_bytes" => bytes(s["records"]),
      "records_sha256" => digest(s["records"]),
      "operations" => map_size(operations(s)),
      "operations_sha256" => operation_digest(operations(s))
    }
  end

  def descriptor?(d) do
    keys?(
      d,
      ~w(version project generation floor floor_anchor floor_lineage floor_lineage_sha256 records data_bytes records_sha256 operations operations_sha256)
    ) and
      d["version"] === 3 and
      JSON.sha256?(d["project"]) and uint?(d["generation"]) and uint?(d["floor"]) and
      ((d["floor"] == 0 and is_nil(d["floor_anchor"])) or id?(d["floor_anchor"])) and
      lineage_shape?(d["floor_lineage"], d["floor_anchor"], d["floor"]) and
      JSON.sha256?(d["floor_lineage_sha256"]) and
      d["floor_lineage_sha256"] == JSON.digest([d["floor_lineage"]]) and
      is_integer(d["records"]) and d["records"] in 0..@record_limit and
      is_integer(d["data_bytes"]) and d["data_bytes"] in 0..@data_limit and
      JSON.sha256?(d["records_sha256"]) and is_integer(d["operations"]) and
      d["operations"] in 0..32_768 and
      JSON.sha256?(d["operations_sha256"])
  rescue
    _ -> false
  end

  def fenced?(s, op),
    do:
      not is_nil(s["migration"]) and
        op not in ~w(import.page import.operations import.commit import.abort)

  def prepare(s, %{"op" => "import.open", "descriptor" => d} = r, id) do
    cond do
      s["migration"] != nil ->
        {:failed, "collection_writer_fenced"}

      s["checkpoint"] != nil ->
        {:failed, "collection_checkpoint_retained"}

      d["project"] != s["project"] or d["floor"] < s["floor"] ->
        {:failed, "collection_import_floor"}

      true ->
        migration = %{
          "id" => id,
          "descriptor" => d,
          "records" => %{},
          "after" => nil,
          "imported_operations" => %{},
          "operation_after" => nil,
          "operation_count" => 0,
          "seen_required_anchor" => is_nil(s["floor_anchor"]),
          "seen_source_anchor" => is_nil(d["floor_anchor"]),
          "record_page_hashes" => nil,
          "seen_lineage_count" => 0,
          "operation_digest" => empty_operation_digest()
        }

        if Map.has_key?(r, "plan") do
          case Planning.validate(s, d, r["plan"]) do
            {:ok, plan} ->
              if Map.has_key?(plan.operations, id) do
                {:failed, "collection_operation_identity"}
              else
                migration = %{
                  migration
                  | "imported_operations" => plan.aliases,
                    "operation_count" => d["operations"],
                    "operation_digest" => d["operations_sha256"],
                    "operation_after" =>
                      plan.operations |> Map.keys() |> Enum.sort() |> List.last(),
                    "seen_required_anchor" => true,
                    "seen_source_anchor" => true,
                    "record_page_hashes" => plan.page_hashes,
                    "seen_lineage_count" => length(d["floor_lineage"])
                }

                {:ok, %{s | "migration" => migration}, %{}, %{"migration_id" => id}}
              end

            failed ->
              failed
          end
        else
          {:ok, %{s | "migration" => migration}, %{}, %{"migration_id" => id}}
        end
    end
  end

  def prepare(s, %{"op" => "import.page"} = r, id) do
    with %{"id" => migration_id} = m <- s["migration"],
         true <- migration_id == r["migration_id"] and m["after"] == r["after"],
         true <-
           length(r["records"]) == min(32, m["descriptor"]["records"] - map_size(m["records"])),
         true <- Enum.all?(r["records"], &(is_nil(r["after"]) or &1["key"] > r["after"])) do
      planned =
        is_nil(m["record_page_hashes"]) or
          Enum.at(m["record_page_hashes"], div(map_size(m["records"]), 32)) ==
            Planning.page_hash(r["records"])

      if planned do
        {records, values} =
          Enum.reduce(r["records"], {m["records"], %{}}, fn row, {records, values} ->
            encoded = encode(row["value"])
            hash = JSON.sha256(encoded)

            record = %{
              "key" => row["key"],
              "revision" => s["generation"] + 1,
              "sha256" => hash,
              "bytes" => byte_size(encoded),
              "operation_id" => id
            }

            {Map.put(records, row["key"], record), Map.put(values, hash, encoded)}
          end)

        if map_size(records) <= m["descriptor"]["records"] and
             bytes(records) <= m["descriptor"]["data_bytes"] do
          m = %{m | "records" => records, "after" => List.last(r["records"])["key"]}
          {:ok, %{s | "migration" => m}, values, %{"migration_id" => migration_id}}
        else
          {:failed, "collection_import_bounds"}
        end
      else
        {:failed, "collection_import_plan"}
      end
    else
      _ -> {:failed, "collection_import_state"}
    end
  end

  def prepare(s, %{"op" => "import.commit", "migration_id" => id}, operation_id) do
    with %{"id" => ^id} = m <- s["migration"],
         d = m["descriptor"],
         true <-
           map_size(m["records"]) == d["records"] and bytes(m["records"]) == d["data_bytes"] and
             digest(m["records"]) == d["records_sha256"] and
             m["operation_count"] == d["operations"] and
             m["operation_digest"] == d["operations_sha256"] do
      source_operations = Map.merge(operations(s), m["imported_operations"])

      if m["seen_required_anchor"] and m["seen_source_anchor"] and
           m["seen_lineage_count"] == length(d["floor_lineage"]) and
           lineage_extends?(s["floor_lineage"], d["floor_lineage"]) and
           valid_lineage?(d["floor_lineage"], d["floor_anchor"], d["floor"], source_operations) do
        floor = max(s["floor"], d["floor"])

        checkpoint =
          if floor == s["floor"],
            do: %{
              "id" => operation_id,
              "generation" => s["generation"],
              "floor" => s["floor"],
              "floor_anchor" => s["floor_anchor"],
              "floor_lineage_sha256" => JSON.digest([s["floor_lineage"]]),
              "records" => s["records"]
            }

        next = %{
          s
          | "records" => m["records"],
            "migration" => nil,
            "checkpoint" => checkpoint,
            "floor" => floor,
            "floor_anchor" =>
              if(d["floor"] > s["floor"], do: d["floor_anchor"], else: s["floor_anchor"]),
            "floor_lineage" =>
              if(d["floor"] > s["floor"], do: d["floor_lineage"], else: s["floor_lineage"]),
            "imported_operations" => Map.merge(s["imported_operations"], m["imported_operations"])
        }

        {:ok, next, %{}, %{"checkpoint_id" => if(checkpoint, do: operation_id)}}
      else
        {:failed, "collection_import_lineage"}
      end
    else
      _ -> {:failed, "collection_import_incomplete"}
    end
  end

  def prepare(s, %{"op" => "import.operations"} = r, operation_id) do
    with %{"id" => migration_id} = m <- s["migration"],
         true <- migration_id == r["migration_id"] and m["operation_after"] == r["after"],
         true <-
           length(r["operations"]) ==
             min(128, m["descriptor"]["operations"] - m["operation_count"]),
         true <-
           Enum.all?(
             r["operations"],
             &((is_nil(r["after"]) or &1["operation_id"] > r["after"]) and
                 &1["operation_id"] != operation_id)
           ) do
      existing = operations(s)

      result =
        Enum.reduce_while(
          r["operations"],
          {:ok, m["imported_operations"], m["operation_digest"]},
          fn row, {:ok, imported, digest} ->
            id = row["operation_id"]
            receipt = row["receipt"]

            case existing[id] do
              old when not is_nil(old) and old != receipt ->
                {:halt, {:failed, "collection_operation_identity"}}

              old ->
                imported = if old, do: imported, else: Map.put(imported, id, receipt)
                {:cont, {:ok, imported, operation_step(digest, id, receipt)}}
            end
          end
        )

      case result do
        {:ok, imported, digest} ->
          required =
            Enum.any?(r["operations"], fn row ->
              row["operation_id"] == s["floor_anchor"] and
                row["receipt"] == existing[s["floor_anchor"]]
            end)

          source =
            Enum.any?(r["operations"], fn row ->
              row["operation_id"] == m["descriptor"]["floor_anchor"] and
                row["receipt"]["floor"] == m["descriptor"]["floor"]
            end)

          lineage_ids = MapSet.new(m["descriptor"]["floor_lineage"])
          seen = Enum.count(r["operations"], &MapSet.member?(lineage_ids, &1["operation_id"]))

          m = %{
            m
            | "imported_operations" => imported,
              "operation_digest" => digest,
              "operation_after" => List.last(r["operations"])["operation_id"],
              "operation_count" => m["operation_count"] + length(r["operations"]),
              "seen_required_anchor" => m["seen_required_anchor"] or required,
              "seen_source_anchor" => m["seen_source_anchor"] or source,
              "seen_lineage_count" => m["seen_lineage_count"] + seen
          }

          {:ok, %{s | "migration" => m}, %{}, %{"migration_id" => migration_id}}

        failed ->
          failed
      end
    else
      _ -> {:failed, "collection_import_state"}
    end
  end

  def prepare(s, %{"op" => "import.abort", "migration_id" => id}, _) do
    case s["migration"] do
      %{"id" => ^id} = migration ->
        # Receipt inspection is irreversible even when content adoption aborts.
        # Releasing staging must not make an observed old operation executable.
        next = %{
          s
          | "migration" => nil,
            "imported_operations" =>
              Map.merge(s["imported_operations"], migration["imported_operations"])
        }

        {:ok, next, %{}, %{}}

      _ ->
        {:failed, "collection_import_state"}
    end
  end

  def prepare(%{"floor" => floor} = s, %{"op" => "rollback", "checkpoint_id" => id}, _) do
    case s["checkpoint"] do
      %{"id" => ^id, "floor" => ^floor, "records" => records} ->
        {:ok, %{s | "records" => records, "checkpoint" => nil}, %{}, %{}}

      _ ->
        {:failed, "collection_rollback_floor"}
    end
  end

  def prepare(s, %{"op" => "checkpoint.drop"}, _), do: {:ok, %{s | "checkpoint" => nil}, %{}, %{}}
  def prepare(_, _, _), do: {:failed, "collection_import_state"}

  def valid?(s, record_validator) do
    not (is_map(s["migration"]) and is_map(s["checkpoint"])) and
      migration?(s["migration"], s, record_validator) and
      checkpoint?(s["checkpoint"], s, record_validator)
  end

  defp migration?(nil, _, _), do: true

  defp migration?(m, s, valid_records) do
    keys?(
      m,
      ~w(id descriptor records after imported_operations operation_after operation_count operation_digest seen_required_anchor seen_source_anchor record_page_hashes seen_lineage_count)
    ) and id?(m["id"]) and descriptor?(m["descriptor"]) and
      m["descriptor"]["project"] == s["project"] and m["descriptor"]["floor"] >= s["floor"] and
      valid_records.(m["records"]) and map_size(m["records"]) <= m["descriptor"]["records"] and
      bytes(m["records"]) <= m["descriptor"]["data_bytes"] and
      m["after"] == m["records"] |> Map.keys() |> Enum.sort() |> List.last() and
      is_map(m["imported_operations"]) and
      Enum.all?(m["imported_operations"], fn {id, receipt} -> id?(id) and receipt?(receipt) end) and
      is_integer(m["operation_count"]) and
      m["operation_count"] in 0..m["descriptor"]["operations"] and
      JSON.sha256?(m["operation_digest"]) and
      is_boolean(m["seen_required_anchor"]) and is_boolean(m["seen_source_anchor"]) and
      is_integer(m["seen_lineage_count"]) and
      m["seen_lineage_count"] in 0..length(m["descriptor"]["floor_lineage"]) and
      (is_nil(m["record_page_hashes"]) or
         (is_list(m["record_page_hashes"]) and
            length(m["record_page_hashes"]) == div(m["descriptor"]["records"] + 31, 32) and
            Enum.all?(m["record_page_hashes"], &JSON.sha256?/1))) and
      (is_nil(m["operation_after"]) or id?(m["operation_after"]))
  rescue
    _ -> false
  end

  defp checkpoint?(nil, _, _), do: true

  defp checkpoint?(c, s, valid_records) do
    keys?(c, ~w(id generation floor floor_anchor floor_lineage_sha256 records)) and
      c["floor_anchor"] == s["floor_anchor"] and id?(c["id"]) and uint?(c["generation"]) and
      c["floor_lineage_sha256"] == JSON.digest([s["floor_lineage"]]) and
      c["generation"] <= s["generation"] and uint?(c["floor"]) and c["floor"] == s["floor"] and
      valid_records.(c["records"]) and bytes(c["records"]) <= @data_limit
  rescue
    _ -> false
  end

  def collections(s),
    do: [
      s["records"],
      get_in(s, ["migration", "records"]) || %{},
      get_in(s, ["checkpoint", "records"]) || %{}
    ]

  def encode(v), do: Jason.encode!(ordered(v))

  def operations(s), do: Map.merge(s["imported_operations"], s["operations"])

  def known_operations(s),
    do: Map.merge(operations(s), get_in(s, ["migration", "imported_operations"]) || %{})

  def lineage_extends?(current, incoming), do: Enum.take(incoming, length(current)) == current

  def valid_lineage?(lineage, anchor, floor, operations) do
    lineage_shape?(lineage, anchor, floor) and
      Enum.reduce_while(lineage, 0, fn id, previous ->
        receipt = operations[id]

        if receipt?(receipt) and receipt["floor"] > previous,
          do: {:cont, receipt["floor"]},
          else: {:halt, :invalid}
      end) === floor
  rescue
    _ -> false
  end

  defp lineage_shape?(lineage, anchor, floor) do
    is_list(lineage) and length(lineage) <= 32_768 and Enum.all?(lineage, &id?/1) and
      length(Enum.uniq(lineage)) == length(lineage) and
      if(floor == 0,
        do: lineage == [] and is_nil(anchor),
        else: lineage != [] and List.last(lineage) == anchor
      )
  end

  def reserved_operation_slots(%{"migration" => nil}), do: 0

  def reserved_operation_slots(%{"migration" => m}) do
    records = m["descriptor"]["records"] - map_size(m["records"])
    operations = m["descriptor"]["operations"] - m["operation_count"]
    # One terminal command and checkpoint removal remain possible after all pages.
    operations + div(records + 31, 32) + div(operations + 127, 128) + 2
  end

  def operation_digest(operations),
    do:
      Enum.reduce(Enum.sort(operations), empty_operation_digest(), fn {id, receipt}, digest ->
        operation_step(digest, id, receipt)
      end)

  defp empty_operation_digest, do: JSON.digest(["collection-operations", 1])
  defp operation_step(digest, id, receipt), do: JSON.digest([digest, id, receipt])

  def receipt?(r) do
    # The closed shape below is at most 241 JSON bytes, including both optional
    # IDs and maximum safe integer counters. No repeated encoding is needed to
    # establish the 512-byte receipt bound.
    keys?(Map.drop(r, ~w(migration_id checkpoint_id)), ~w(generation floor request_sha256)) and
      uint?(r["generation"]) and r["generation"] > 0 and uint?(r["floor"]) and
      JSON.sha256?(r["request_sha256"]) and
      (not Map.has_key?(r, "migration_id") or id?(r["migration_id"])) and
      (not Map.has_key?(r, "checkpoint_id") or is_nil(r["checkpoint_id"]) or
         id?(r["checkpoint_id"]))
  rescue
    _ -> false
  end

  defp ordered(v) when is_map(v),
    do: %Jason.OrderedObject{
      values: Enum.map(Enum.sort(v), fn {k, value} -> {k, ordered(value)} end)
    }

  defp ordered(v) when is_list(v), do: Enum.map(v, &ordered/1)
  defp ordered(v), do: v
  def bytes(records), do: Enum.sum(Enum.map(records, fn {_, r} -> r["bytes"] end))

  def digest(records),
    do:
      records
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {key, r} -> [key, r["sha256"], r["bytes"]] end)
      |> then(&JSON.digest([&1]))

  defp value?(v),
    do: is_map(v) and JSON.validate_object(v) == :ok and byte_size(Jason.encode!(v)) <= 6144

  defp uint?(x), do: JSON.safe_uint?(x)
  defp keys?(m, keys), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(keys)
  defp id?(x), do: is_binary(x) and Regex.match?(~r/\A[a-f0-9]{32}\z/, x)
  defp key?(x), do: is_binary(x) and Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,95}\z/, x)
end
