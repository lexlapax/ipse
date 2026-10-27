defmodule Ipse.Extension.Collection do
  @moduledoc """
  Internal bounded immutable collection storage. This API grants no authority.

  The host selects the protected root and admitted project identity. Callers must
  journal intent and hold the project control lock before a publication requiring
  consent. Storage never calls back into consent or performs inference. Readers
  take the same retained OS lock as writers, so reclamation cannot race a read.

  Values are content addressed; only the bounded manifest is rewritten. Successful
  operation IDs remain inspectable and cannot execute twice. Exhaustion refuses
  publication; the operation ledger is never silently reset. Export pages carry
  a floor advanced by destructive operations. Typed staged import fences ordinary
  writers and replaces records atomically after every page and digest validates.
  It retains inspected source IDs, including across abort and rollback, and
  cannot import below the current floor. The small `import` operation remains a
  separate bounded merge; complete migration uses `import.open/page/operations/commit`.

  This is an internal storage component, not a shipped knowledge host call.
  Domain policy belongs to the extension; protected consent and project identity
  admission belong to the host. The native quota profile currently accepts only
  explicitly reviewed Linux filesystems and fails closed on unsupported hosts.
  """
  alias Ipse.JSON
  alias Ipse.Runner.Transaction
  alias Ipse.Extension.Collection.{Encoding, Migration, Planning}
  import Bitwise, only: [band: 2]
  @value_bytes 6 * 1024
  @data_bytes 24 * 1024 * 1024
  @total_bytes 64 * 1024 * 1024
  # Consent's active/staged ledger allowance is 18 MiB; shared project identity
  # adds 4 MiB. Both owners independently enforce their protected native budgets.
  @control_bytes 22 * 1024 * 1024
  @manifest_bytes 8 * 1024 * 1024
  @records 8192
  @operations 32_768
  @lock_key {__MODULE__, :lock_held}
  @error {:error, :collection_unavailable}

  def limits do
    %{
      "value_bytes" => @value_bytes,
      "data_bytes" => @data_bytes,
      "total_bytes" => @total_bytes,
      "control_reserved_bytes" => @control_bytes,
      "records" => @records,
      "operations" => @operations
    }
  end

  def execute(root, project, request, operation_id) do
    if Process.get(@lock_key) do
      {:error, :collection_lock_order}
    else
      with true <- valid_request?(request) and id?(operation_id) do
        Ipse.Session.Resources.file_effect(fn -> locked(root, project, request, operation_id) end)
      else
        _ -> {:error, :invalid_collection_request}
      end
    end
  rescue
    _ -> @error
  end

  def valid_request?(%{"op" => op} = r) when op in ~w(status snapshot), do: keys?(r, ["op"])
  def valid_request?(%{"op" => "get"} = r), do: keys?(r, ~w(op key)) and key?(r["key"])

  def valid_request?(%{"op" => "inspect"} = r),
    do: keys?(r, ~w(op operation_id)) and id?(r["operation_id"])

  def valid_request?(%{"op" => "scan"} = r) do
    keys?(r, ~w(op after generation limit)) and
      (is_nil(r["after"]) or key?(r["after"])) and uint?(r["generation"]) and
      is_integer(r["limit"]) and r["limit"] in 1..32
  end

  def valid_request?(%{"op" => op} = r) when op in ~w(commit import) do
    fields = ~w(op expected_generation changes advance_floor)
    fields = if op == "import", do: fields ++ ~w(project floor), else: fields

    keys?(r, fields) and uint?(r["expected_generation"]) and is_boolean(r["advance_floor"]) and
      (op != "import" or (JSON.sha256?(r["project"]) and uint?(r["floor"]))) and
      is_list(r["changes"]) and length(r["changes"]) in 1..128 and
      Enum.all?(r["changes"], &change?/1) and
      length(Enum.uniq_by(r["changes"], & &1["key"])) == length(r["changes"]) and
      (r["advance_floor"] or Enum.all?(r["changes"], &(not is_nil(&1["value"]))))
  rescue
    _ -> false
  end

  def valid_request?(request), do: Migration.request?(request)

  defp change?(c) do
    keys?(c, ~w(key expected_revision value)) and key?(c["key"]) and
      uint?(c["expected_revision"]) and (is_nil(c["value"]) or value?(c["value"]))
  end

  defp value?(v) do
    is_map(v) and :ok == JSON.validate_object(v) and
      byte_size(Jason.encode!(v)) <= @value_bytes
  end

  defp locked(root, project, request, operation_id) do
    with true <- is_binary(root) and Path.type(root) == :absolute and JSON.sha256?(project),
         {:ok, uid} <- Ipse.Runner.protected_current_uid(),
         :ok <- directory(Path.dirname(root), uid, false),
         :ok <- directory(root, uid, true),
         path = Path.join(root, project),
         :ok <- directory(path, uid, true),
         :ok <- directory(Path.join(path, "objects"), uid, true),
         :ok <- directory(Path.join(path, "manifests"), uid, true),
         :ok <- safe_lock(Path.join(path, ".lock"), uid),
         {:ok, cap} <- Transaction.acquire(Path.join(path, ".lock"), cwd: Path.dirname(root)) do
      Process.put(@lock_key, cap)

      result =
        try do
          with :ok <- safe_lock(Path.join(path, ".lock"), uid),
               {:ok, state, manifest} <- load(path, project, uid),
               :ok <- Transaction.check(cap),
               :ok <- Transaction.quota(cap, :collection, @total_bytes - @control_bytes) do
            apply_request(path, uid, state, manifest, request, operation_id)
          else
            {:error, :transaction_filesystem_unsupported} ->
              {:error, :collection_filesystem_unsupported}

            {:error, :transaction_capacity} ->
              {:failed, %{"code" => "collection_capacity"}}

            _ ->
              @error
          end
        rescue
          _ -> {:unknown, :collection_transaction_unconfirmed}
        catch
          _, _ -> {:unknown, :collection_transaction_unconfirmed}
        after
          Process.delete(@lock_key)
        end

      checked = Transaction.check(cap)
      released = Transaction.release(cap)

      if checked == :ok and released == :ok,
        do: result,
        else: {:unknown, :collection_lock_lost}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp apply_request(path, uid, s, _, %{"op" => "status"}, _) do
    status(path, uid, s)
  end

  defp apply_request(_, _, s, _, %{"op" => "snapshot"}, _), do: {:ok, summary(s)}

  defp apply_request(_, _, s, _, %{"op" => "inspect", "operation_id" => id}, _),
    do: {:ok, Map.put(summary(s), "operation", Migration.known_operations(s)[id])}

  defp apply_request(path, uid, s, _, %{"op" => "get", "key" => key}, _) do
    with {:ok, record} <- read_record(path, uid, s, key),
         do: {:ok, Map.put(summary(s), "record", record)}
  end

  defp apply_request(path, uid, s, _, %{"op" => "scan"} = r, _) do
    if r["generation"] == s["generation"] do
      keys =
        s["records"]
        |> Map.keys()
        |> Enum.sort()
        |> Enum.filter(&(is_nil(r["after"]) or &1 > r["after"]))

      selected = Enum.take(keys, r["limit"])

      with {:ok, records} <- read_records(path, uid, s, selected) do
        {:ok,
         Map.merge(summary(s), %{
           "records" => records,
           "next" => if(length(keys) > length(selected), do: List.last(selected))
         })}
      end
    else
      {:conflict, summary(s)}
    end
  end

  defp apply_request(path, uid, s, manifest, %{"op" => "export"} = r, id) do
    case apply_request(path, uid, s, manifest, %{r | "op" => "scan"}, id) do
      {:ok, page} -> {:ok, Map.put(page, "descriptor", Migration.descriptor(s))}
      other -> other
    end
  end

  defp apply_request(_, _, s, _, %{"op" => "export.plan", "generation" => generation}, _) do
    if generation == s["generation"],
      do:
        {:ok,
         Map.merge(summary(s), %{
           "descriptor" => Migration.descriptor(s),
           "plan" => Planning.export(s)
         })},
      else: {:conflict, summary(s)}
  end

  defp apply_request(_, _, s, _, %{"op" => "export.operations"} = r, _) do
    if r["generation"] == s["generation"] do
      keys =
        s
        |> Migration.operations()
        |> Map.keys()
        |> Enum.sort()
        |> Enum.filter(&(is_nil(r["after"]) or &1 > r["after"]))

      selected = Enum.take(keys, r["limit"])
      operations = Migration.operations(s)

      {:ok,
       Map.merge(summary(s), %{
         "descriptor" => Migration.descriptor(s),
         "operations" =>
           Enum.map(selected, &%{"operation_id" => &1, "receipt" => operations[&1]}),
         "next" => if(length(keys) > length(selected), do: List.last(selected))
       })}
    else
      {:conflict, summary(s)}
    end
  end

  defp apply_request(path, uid, s, manifest, r, id) do
    known = Migration.known_operations(s)

    cond do
      Map.has_key?(known, id) ->
        {:existing, Map.put(summary(s), "operation", known[id])}

      r["expected_generation"] != s["generation"] or
          Enum.any?(r["changes"] || [], &(revision(s, &1["key"]) != &1["expected_revision"])) ->
        {:conflict, summary(s)}

      Migration.fenced?(s, r["op"]) ->
        {:failed, Map.put(summary(s), "code", "collection_writer_fenced")}

      r["op"] == "import" and (r["project"] != s["project"] or r["floor"] != s["floor"]) ->
        {:failed, Map.put(summary(s), "code", "collection_import_floor")}

      map_size(known) >= @operations or not uint?(s["generation"] + 1) ->
        capacity(s)

      r["op"] == "import.open" and not Map.has_key?(r, "plan") and
          not import_fits?(path, uid, s, r["descriptor"]) ->
        capacity(s)

      true ->
        case prepare(s, r, id) do
          {:ok, next, values, extra} ->
            receipt =
              Map.merge(
                %{
                  "generation" => s["generation"] + 1,
                  "floor" => next["floor"],
                  "request_sha256" => JSON.digest([r])
                },
                extra
              )

            next = %{
              next
              | "generation" => receipt["generation"],
                "operations" => Map.put(s["operations"], id, receipt)
            }

            next =
              if r["advance_floor"] == true,
                do: Map.update!(next, "floor_lineage", &(&1 ++ [id])),
                else: next

            publish(path, uid, s, next, manifest, values, receipt, r)

          {:failed, code} ->
            {:failed, Map.put(summary(s), "code", code)}
        end
    end
  end

  defp import_fits?(path, uid, s, descriptor) do
    import_fits_quiescent?(path, uid, s, descriptor)
  end

  defp import_fits_quiescent?(path, uid, s, descriptor) do
    # Staging additionally checks exact allocation before every publication.
    extra_manifest =
      descriptor["records"] * 512 + div(descriptor["records"] + 31, 32) * 256 + 4096 +
        descriptor["operations"] * 384

    manifest_bound = byte_size(Encoding.encode(s)) + extra_manifest

    with true <- manifest_bound <= @manifest_bytes,
         {:ok, disk} <- disk_bytes(path, uid),
         {:ok, allocation} <- allocation() do
      disk + descriptor["data_bytes"] + 2 * manifest_bound + @control_bytes <= @total_bytes and
        allocation["allocated_bytes"] + descriptor["data_bytes"] + 2 * manifest_bound +
          @control_bytes <= @total_bytes
    else
      _ -> false
    end
  end

  defp prepare(s, %{"op" => op} = r, id) when op in ~w(commit import) do
    {records, values} = changed_records(s, r["changes"], id)
    floor = if r["advance_floor"], do: max(s["generation"] + 1, s["floor"] + 1), else: s["floor"]

    next = %{
      s
      | "records" => records,
        "floor" => floor,
        "floor_anchor" => if(r["advance_floor"], do: id, else: s["floor_anchor"]),
        "checkpoint" => if(r["advance_floor"], do: nil, else: s["checkpoint"])
    }

    {:ok, next, values, %{}}
  end

  defp prepare(s, %{"op" => "import.open"} = r, id) do
    with {:ok, next, values, extra} <- Migration.prepare(s, r, id),
         true <-
           map_size(Migration.known_operations(next)) + Migration.reserved_operation_slots(next) +
             1 <= @operations do
      {:ok, next, values, extra}
    else
      false -> {:failed, "collection_capacity"}
      failed -> failed
    end
  end

  defp prepare(s, r, id), do: Migration.prepare(s, r, id)

  defp status(path, uid, s) do
    with {:ok, disk} <- disk_bytes(path, uid),
         {:ok, allocation} <- allocation() do
      {:ok,
       Map.merge(summary(s), %{
         "records" => map_size(s["records"]),
         "migration" => if(s["migration"], do: Map.drop(s["migration"], ["records"])),
         "checkpoint" => if(s["checkpoint"], do: Map.drop(s["checkpoint"], ["records"])),
         "staged_records" => map_size(get_in(s, ["migration", "records"]) || %{}),
         "staged_data_bytes" => Migration.bytes(get_in(s, ["migration", "records"]) || %{}),
         "checkpoint_records" => map_size(get_in(s, ["checkpoint", "records"]) || %{}),
         "checkpoint_data_bytes" => Migration.bytes(get_in(s, ["checkpoint", "records"]) || %{}),
         "operations" => map_size(Migration.operations(s)),
         "reserved_operation_slots" => Migration.reserved_operation_slots(s),
         "data_bytes" => data_bytes(s),
         "envelope_data_bytes" => envelope_bytes(s),
         "disk_bytes" => disk,
         "accounted_total_bytes" => disk + @control_bytes,
         "allocated_bytes" => allocation["allocated_bytes"],
         "accounted_allocated_bytes" => allocation["allocated_bytes"] + @control_bytes,
         "notice" =>
           if(
             envelope_bytes(s) >= div(@data_bytes * 4, 5) or
               disk + @control_bytes >= div(@total_bytes * 4, 5) or
               allocation["allocated_bytes"] + @control_bytes >= div(@total_bytes * 4, 5) or
               map_size(s["records"]) >= div(@records * 4, 5) or
               map_size(Migration.operations(s)) >= div(@operations * 4, 5),
             do: "capacity_80_percent"
           ),
         "limits" => limits()
       })}
    end
  end

  defp changed_records(s, changes, id) do
    Enum.reduce(changes, {s["records"], %{}}, fn c, {records, values} ->
      if is_nil(c["value"]) do
        {Map.delete(records, c["key"]), values}
      else
        bytes = Migration.encode(c["value"])
        hash = JSON.sha256(bytes)

        record = %{
          "key" => c["key"],
          "revision" => s["generation"] + 1,
          "sha256" => hash,
          "bytes" => byte_size(bytes),
          "operation_id" => id
        }

        {Map.put(records, c["key"], record), Map.put(values, hash, bytes)}
      end
    end)
  end

  defp publish(path, uid, old, next, manifest, values, receipt, request) do
    bytes = Encoding.encode(next)
    terminal = terminal_reserve(next)

    cond do
      not valid_state?(next, next["project"]) or
        map_size(next["records"]) > @records or data_bytes(next) > @data_bytes or
        byte_size(bytes) > @manifest_bytes or Enum.any?(terminal, &(&1 > @manifest_bytes)) ->
        capacity(old)

      true ->
        hash = JSON.sha256(bytes)
        pointer = Jason.encode!(Map.put(summary(next), "manifest", hash))

        with :ok <- collect(path, uid, old, manifest),
             {:ok, planned} <- full_import_plan(path, uid, old, next, request),
             {:ok, pending} <- prepare_values(path, uid, values),
             {:ok, disk} <- disk_bytes(path, uid),
             true <-
               disk + @control_bytes + byte_size(bytes) +
                 Enum.sum(Enum.map(pending, fn {_, _, v} -> byte_size(v) end)) +
                 byte_size(pointer) + Enum.sum(terminal) <= @total_bytes,
             :ok <-
               Transaction.preflight(
                 publication_cap(),
                 planned ++
                   terminal ++
                   [
                     byte_size(bytes),
                     byte_size(pointer)
                     | Enum.map(pending, fn {_, _, value} -> byte_size(value) end)
                   ]
               ) do
          # Every failure after staging is an inspected unknown outcome. In
          # particular a failed final directory sync cannot justify replay.
          with :ok <- write_values(pending),
               :ok <- immutable(Path.join(path, "manifests"), hash, bytes, uid),
               :ok <- publish_pointer(path, uid, pointer, next) do
            collect(path, uid, next, hash)
            {:ok, receipt}
          else
            _ -> {:unknown, :collection_publication_unconfirmed}
          end
        else
          false ->
            capacity(old)

          {:error, :transaction_capacity} ->
            capacity(old)

          {:error, :transaction_filesystem_unsupported} ->
            {:error, :collection_filesystem_unsupported}

          _ ->
            @error
        end
    end
  end

  defp publish_pointer(_path, _uid, bytes, state) do
    temporary = ".pending-" <> Ipse.Usage.id()

    with :ok <- Transaction.stage(publication_cap(), ".", [{temporary, bytes}]),
         {:ok, allocation} <- allocation(),
         :ok <- report_allocation(state, allocation),
         true <- allocation["allocated_bytes"] + @control_bytes <= @total_bytes,
         :ok <- Transaction.switch(publication_cap(), temporary, "root.json"),
         do: :ok
  end

  defp allocation do
    case Transaction.allocation(publication_cap()) do
      {:ok, %{logical: logical, allocated: allocated, entries: entries}} ->
        {:ok, %{"logical_bytes" => logical, "allocated_bytes" => allocated, "entries" => entries}}

      error ->
        error
    end
  end

  defp report_allocation(state, allocation) do
    :telemetry.execute(
      [:ipse, :extension, :collection, :staged],
      %{
        allocated_bytes: allocation["allocated_bytes"],
        accounted_allocated_bytes: allocation["allocated_bytes"] + @control_bytes,
        root_publication_reserved_bytes: 0
      },
      %{generation: state["generation"]}
    )

    :ok
  end

  defp prepare_values(path, uid, values) do
    dir = Path.join(path, "objects")

    Enum.reduce_while(values, {:ok, []}, fn {hash, bytes}, {:ok, pending} ->
      target = Path.join(dir, hash <> ".json")

      case File.lstat(target) do
        {:error, :enoent} ->
          {:cont, {:ok, [{".pending-" <> Ipse.Usage.id(), target, bytes} | pending]}}

        {:ok, _} ->
          case bounded_file(target, uid, @value_bytes) do
            {:ok, ^bytes} -> {:cont, {:ok, pending}}
            _ -> {:halt, @error}
          end

        _ ->
          {:halt, @error}
      end
    end)
  end

  defp write_values([]), do: :ok

  defp write_values(files) do
    with :ok <-
           Transaction.stage(
             publication_cap(),
             "objects",
             Enum.map(files, fn {name, _, bytes} -> {name, bytes} end)
           ) do
      Enum.reduce_while(files, :ok, fn {name, target, _}, :ok ->
        case Transaction.install(publication_cap(), "objects", name, Path.basename(target)) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end

  defp immutable(dir, hash, bytes, uid) do
    file = Path.join(dir, hash <> ".json")

    case File.lstat(file) do
      {:error, :enoent} ->
        replace(dir, hash <> ".json", bytes, uid)

      {:ok, _} ->
        with {:ok, ^bytes} <- bounded_file(file, uid, @manifest_bytes),
             do: :ok,
             else: (_ -> @error)

      _ ->
        @error
    end
  end

  defp replace(dir, name, bytes, _uid) do
    temporary = ".pending-" <> Ipse.Usage.id()
    relative = Path.basename(dir)

    with :ok <- Transaction.stage(publication_cap(), relative, [{temporary, bytes}]),
         do: Transaction.install(publication_cap(), relative, temporary, name)
  end

  defp load(path, project, uid) do
    case File.lstat(Path.join(path, "root.json")) do
      {:error, :enoent} ->
        {:ok,
         %{
           "version" => 3,
           "project" => project,
           "generation" => 0,
           "floor" => 0,
           "floor_anchor" => nil,
           "floor_lineage" => [],
           "records" => %{},
           "operations" => %{},
           "imported_operations" => %{},
           "migration" => nil,
           "checkpoint" => nil
         }, nil}

      {:ok, _} ->
        with {:ok, bytes} <- bounded_file(Path.join(path, "root.json"), uid, 1024),
             {:ok, root} <- JSON.decode_unique(bytes),
             true <-
               (keys?(root, ~w(version project generation floor manifest)) or
                  keys?(root, ~w(version project generation floor floor_anchor manifest))) and
                 root["version"] in [2, 3] and root["project"] == project and
                 uint?(root["generation"]) and uint?(root["floor"]) and
                 JSON.sha256?(root["manifest"]),
             {:ok, bytes} <-
               bounded_file(
                 Path.join([path, "manifests", root["manifest"] <> ".json"]),
                 uid,
                 @manifest_bytes
               ),
             true <- JSON.sha256(bytes) == root["manifest"],
             {:ok, stored} <- JSON.decode_unique(bytes),
             true <- summary(stored) == Map.delete(root, "manifest"),
             {:ok, s} <- Encoding.decode(stored),
             true <- valid_state?(s, project) do
          {:ok, s, root["manifest"]}
        else
          _ -> @error
        end

      _ ->
        @error
    end
  end

  defp valid_state?(s, project) do
    keys?(
      s,
      ~w(version project generation floor floor_anchor floor_lineage records operations imported_operations migration checkpoint)
    ) and
      s["version"] === 3 and
      s["project"] == project and uint?(s["generation"]) and uint?(s["floor"]) and
      is_map(s["records"]) and
      map_size(s["records"]) <= @records and
      is_map(s["operations"]) and map_size(s["operations"]) <= @operations and
      s["generation"] == map_size(s["operations"]) and
      valid_imported_operations?(s) and
      valid_floor_anchor?(s) and
      Migration.valid_lineage?(
        s["floor_lineage"],
        s["floor_anchor"],
        s["floor"],
        Migration.operations(s)
      ) and
      valid_records?(s["records"], s) and
      Migration.valid?(s, &valid_records?(&1, s)) and
      Enum.all?(s["operations"], fn {id, r} ->
        id?(id) and
          keys?(Map.drop(r, ~w(migration_id checkpoint_id)), ~w(generation floor request_sha256)) and
          (not Map.has_key?(r, "migration_id") or id?(r["migration_id"])) and
          (not Map.has_key?(r, "checkpoint_id") or is_nil(r["checkpoint_id"]) or
             id?(r["checkpoint_id"])) and
          uint?(r["generation"]) and r["generation"] in 1..s["generation"] and
          uint?(r["floor"]) and
          JSON.sha256?(r["request_sha256"])
      end) and
      length(Enum.uniq_by(Map.values(s["operations"]), & &1["generation"])) == s["generation"] and
      envelope_bytes(s) <= @data_bytes
  rescue
    _ -> false
  end

  defp valid_records?(records, s) do
    operations = Migration.operations(s)

    is_map(records) and map_size(records) <= @records and
      Enum.all?(records, fn {key, r} ->
        keys?(r, ~w(key revision sha256 bytes operation_id)) and key?(key) and r["key"] == key and
          uint?(r["revision"]) and r["revision"] in 1..s["generation"] and
          JSON.sha256?(r["sha256"]) and is_integer(r["bytes"]) and r["bytes"] in 2..@value_bytes and
          id?(r["operation_id"]) and
          get_in(operations, [r["operation_id"], "generation"]) == r["revision"]
      end)
  end

  defp valid_imported_operations?(s) do
    staged = get_in(s, ["migration", "imported_operations"]) || %{}
    imported = s["imported_operations"]

    is_map(imported) and is_map(staged) and
      map_size(s["operations"]) + map_size(imported) + map_size(staged) +
        Migration.reserved_operation_slots(s) <= @operations and
      Enum.all?(imported, fn {id, receipt} -> id?(id) and Migration.receipt?(receipt) end) and
      Enum.all?(Map.keys(imported), &(not Map.has_key?(s["operations"], &1))) and
      Enum.all?(
        Map.keys(staged),
        &(not Map.has_key?(s["operations"], &1) and not Map.has_key?(imported, &1))
      )
  end

  defp read_record(path, uid, s, key) do
    case s["records"][key] do
      nil ->
        {:ok, nil}

      r ->
        with {:ok, bytes} <-
               bounded_file(
                 Path.join([path, "objects", r["sha256"] <> ".json"]),
                 uid,
                 @value_bytes
               ),
             true <- byte_size(bytes) == r["bytes"] and JSON.sha256(bytes) == r["sha256"],
             {:ok, value} <- JSON.decode_unique(bytes),
             true <- value?(value) do
          {:ok, Map.put(r, "value", value)}
        else
          _ -> @error
        end
    end
  end

  defp read_records(path, uid, s, keys) do
    Enum.reduce_while(keys, {:ok, []}, fn key, {:ok, records} ->
      case read_record(path, uid, s, key) do
        {:ok, r} -> {:cont, {:ok, [r | records]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, records} -> {:ok, Enum.reverse(records)}
      error -> error
    end
  end

  # At most 512 orphan files are removed in one pass. Active objects and the
  # currently selected manifest are protected while the storage lock is held.
  defp collect(path, uid, s, manifest) do
    with :ok <- Transaction.check(publication_cap()),
         do: collect_quiescent(path, uid, s, manifest)
  end

  defp collect_quiescent(path, uid, s, manifest) do
    live =
      s
      |> Migration.collections()
      |> Enum.flat_map(fn records ->
        Enum.map(records, fn {_, r} -> r["sha256"] <> ".json" end)
      end)
      |> MapSet.new()
      |> MapSet.put(".writer.lock")

    with :ok <- collect_dir(Path.join(path, "objects"), uid, live),
         :ok <-
           collect_dir(
             Path.join(path, "manifests"),
             uid,
             MapSet.new([".writer.lock" | if(manifest, do: [manifest <> ".json"], else: [])])
           ),
         :ok <- collect_root_pending(path, uid),
         do: :ok
  end

  defp collect_root_pending(path, uid) do
    with {:ok, names} <- File.ls(path), true <- length(names) <= 1028 do
      reclaim_selected(path, ".", uid, names |> Enum.filter(&pending?/1) |> Enum.take(512))
    else
      _ -> @error
    end
  end

  defp collect_dir(dir, uid, live) do
    with {:ok, names} <- File.ls(dir), true <- length(names) <= @records * 2 + 1024 do
      reclaim_selected(
        dir,
        Path.basename(dir),
        uid,
        names |> Enum.reject(&MapSet.member?(live, &1)) |> Enum.take(512)
      )
    else
      _ -> @error
    end
  end

  defp reclaim_selected(path, relative, uid, names) do
    if Enum.all?(names, fn name ->
         with true <- artifact_name?(name),
              {:ok, stat} <- File.lstat(Path.join(path, name)),
              do: safe_file?(stat, uid),
              else: (_ -> false)
       end) do
      names
      |> Enum.chunk_every(64)
      |> Enum.reduce_while(:ok, fn chunk, :ok ->
        case Transaction.reclaim(publication_cap(), relative, chunk) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    else
      @error
    end
  end

  defp disk_bytes(path, uid) do
    with {:ok, top} <- File.ls(path),
         true <-
           Enum.all?(
             top,
             &(&1 in ~w(.lock .writer.lock root.json objects manifests) or pending?(&1))
           ),
         {:ok, bytes} <- files_bytes(path, Enum.reject(top, &(&1 in ~w(objects manifests))), uid),
         {:ok, objects} <- File.ls(Path.join(path, "objects")),
         {:ok, manifests} <- File.ls(Path.join(path, "manifests")),
         true <- length(objects) <= @records * 2 + 1024 and length(manifests) <= 1024,
         {:ok, a} <- files_bytes(Path.join(path, "objects"), objects, uid),
         {:ok, b} <- files_bytes(Path.join(path, "manifests"), manifests, uid),
         true <- bytes + a + b + @control_bytes <= @total_bytes do
      {:ok, bytes + a + b}
    else
      _ -> @error
    end
  end

  defp files_bytes(dir, names, uid) do
    Enum.reduce_while(names, {:ok, 0}, fn name, {:ok, bytes} ->
      with true <- name in ~w(.lock .writer.lock root.json) or artifact_name?(name),
           {:ok, stat} <- File.lstat(Path.join(dir, name)),
           true <- safe_file?(stat, uid) do
        {:cont, {:ok, bytes + stat.size}}
      else
        _ -> {:halt, @error}
      end
    end)
  end

  defp bounded_file(path, uid, limit) do
    with {:ok, stat} <- File.lstat(path),
         true <- safe_file?(stat, uid) and stat.size <= limit,
         {:ok, bytes} <- File.open(path, [:read, :binary], &IO.binread(&1, limit + 1)),
         true <- is_binary(bytes) and byte_size(bytes) <= limit do
      {:ok, bytes}
    else
      _ -> @error
    end
  end

  defp directory(path, uid, create) do
    case File.lstat(path) do
      {:error, :enoent} when create ->
        case File.mkdir(path) do
          :ok ->
            with :ok <- File.chmod(path, 0o700),
                 :ok <- Ipse.Runner.protected_sync_directory(Path.dirname(path)),
                 do: directory(path, uid, false)

          {:error, :eexist} ->
            directory(path, uid, false)

          _ ->
            @error
        end

      {:ok, %{type: :directory, uid: ^uid, mode: mode}} when band(mode, 0o077) == 0 ->
        case Ipse.Workspace.canonical_path(path) do
          {:ok, ^path} -> :ok
          _ -> @error
        end

      _ ->
        @error
    end
  end

  defp safe_lock(path, uid) do
    case File.lstat(path) do
      {:error, :enoent} -> :ok
      {:ok, stat} -> if safe_file?(stat, uid), do: :ok, else: @error
      _ -> @error
    end
  end

  defp publication_cap, do: Process.get(@lock_key)

  defp safe_file?(s, uid),
    do: s.type == :regular and s.uid == uid and s.links == 1 and band(s.mode, 0o077) == 0

  defp summary(s), do: Map.take(s, ~w(version project generation floor floor_anchor))

  defp valid_floor_anchor?(%{"floor" => 0, "floor_anchor" => nil}), do: true

  defp valid_floor_anchor?(s) do
    id?(s["floor_anchor"]) and
      get_in(Migration.operations(s), [s["floor_anchor"], "floor"]) === s["floor"]
  end

  defp envelope_bytes(s) do
    s
    |> Migration.collections()
    |> Enum.flat_map(&Map.to_list/1)
    |> Enum.uniq_by(fn {key, record} -> {key, record["sha256"]} end)
    |> Enum.reduce(0, fn {_, record}, total -> total + record["bytes"] end)
  end

  defp terminal_reserve(%{"migration" => nil}), do: []

  defp terminal_reserve(s) do
    # A valid nonterminal import reserves an additional complete abort publication.
    # Aliases survive abort; its extra receipt cannot consume the final identity.
    known = Migration.known_operations(s)

    id =
      Enum.find_value(0..@operations, fn n ->
        candidate = n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")
        if not Map.has_key?(known, candidate), do: candidate
      end)

    {:ok, aborted, _, _} =
      Migration.prepare(
        s,
        %{
          "op" => "import.abort",
          "migration_id" => s["migration"]["id"]
        },
        id
      )

    receipt = %{
      "generation" => s["generation"] + 1,
      "floor" => s["floor"],
      "request_sha256" => String.duplicate("f", 64)
    }

    aborted = %{
      aborted
      | "generation" => receipt["generation"],
        "operations" => Map.put(s["operations"], id, receipt)
    }

    [byte_size(Encoding.encode(aborted)), 1024]
  end

  defp full_import_plan(path, uid, old, next, %{
         "op" => "import.open",
         "plan" => supplied,
         "descriptor" => descriptor
       }) do
    with {:ok, plan} <- Planning.validate(old, descriptor, supplied),
         future = planned_generation(next, plan.records),
         true <- envelope_bytes(future) <= @data_bytes,
         {:ok, sizes} <- planned_object_sizes(path, uid, plan.records),
         manifest_size = byte_size(Encoding.encode(future)),
         true <- manifest_size <= @manifest_bytes,
         terminal = terminal_reserve(future),
         true <- Enum.all?(terminal, &(&1 <= @manifest_bytes)),
         # Both the current and next complete generation may coexist at a late
         # page. The terminal manifest remains additional reserved headroom.
         sizes = [manifest_size, manifest_size, 1024 | terminal ++ sizes],
         true <- length(sizes) <= 256,
         {:ok, disk} <- disk_bytes(path, uid),
         true <- disk + @control_bytes + Enum.sum(sizes) <= @total_bytes,
         :ok <- Transaction.preflight(publication_cap(), sizes) do
      {:ok, []}
    else
      false -> {:error, :transaction_capacity}
      other -> other
    end
  end

  defp full_import_plan(_, _, _, _, _), do: {:ok, []}

  defp planned_generation(state, records) do
    pages = div(map_size(records) + 31, 32)
    known = Migration.known_operations(state)

    ids =
      0..@operations
      |> Enum.map(fn n ->
        n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")
      end)
      |> Enum.reject(&Map.has_key?(known, &1))
      |> Enum.take(pages)

    true = length(ids) == pages

    future =
      Enum.reduce(ids, state, fn id, state ->
        generation = state["generation"] + 1

        receipt = %{
          "generation" => generation,
          "floor" => state["floor"],
          "request_sha256" => String.duplicate("f", 64),
          "migration_id" => state["migration"]["id"]
        }

        %{
          state
          | "generation" => generation,
            "operations" => Map.put(state["operations"], id, receipt)
        }
      end)

    records =
      Map.new(records, fn {key, record} ->
        {key,
         Map.merge(record, %{
           "revision" => future["generation"],
           "operation_id" => List.last(ids) || state["migration"]["id"]
         })}
      end)

    future
    |> put_in(["migration", "records"], records)
    |> put_in(["migration", "after"], records |> Map.keys() |> Enum.sort() |> List.last())
  end

  defp planned_object_sizes(path, uid, records) do
    records
    |> Map.values()
    |> Enum.uniq_by(& &1["sha256"])
    |> Enum.reduce_while({:ok, []}, fn record, {:ok, sizes} ->
      file = Path.join([path, "objects", record["sha256"] <> ".json"])

      case File.lstat(file) do
        {:error, :enoent} ->
          {:cont, {:ok, [record["bytes"] | sizes]}}

        {:ok, _} ->
          with {:ok, bytes} <- bounded_file(file, uid, @value_bytes),
               true <-
                 byte_size(bytes) == record["bytes"] and JSON.sha256(bytes) == record["sha256"] do
            {:cont, {:ok, sizes}}
          else
            _ -> {:halt, @error}
          end

        _ ->
          {:halt, @error}
      end
    end)
  end

  defp data_bytes(s), do: Enum.sum(Enum.map(s["records"], fn {_, r} -> r["bytes"] end))
  defp revision(s, key), do: if(s["records"][key], do: s["records"][key]["revision"], else: 0)
  defp capacity(s), do: {:failed, Map.put(summary(s), "code", "collection_capacity")}
  defp keys?(m, fields), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(fields)
  defp uint?(x), do: JSON.safe_uint?(x)
  defp id?(x), do: is_binary(x) and Regex.match?(~r/\A[a-f0-9]{32}\z/, x)
  defp key?(x), do: is_binary(x) and Regex.match?(~r/\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,95}\z/, x)
  defp pending?(name), do: Regex.match?(~r/\A\.pending-[a-f0-9]{32}\z/, name)
  defp artifact_name?(name), do: pending?(name) or Regex.match?(~r/\A[a-f0-9]{64}\.json\z/, name)
end
