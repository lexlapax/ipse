defmodule Ipse.Development.StorageBlocksProbe do
  @moduledoc false
  alias Ipse.Extension.Collection, as: C
  alias Ipse.Extension.Collection.{Blocks, Encoding, Migration}
  alias Ipse.Runner.Transaction, as: T
  @count 4096
  @operations 20_950
  @control 22 * 1024 * 1024

  def run(args) do
    Process.flag(:max_heap_size, %{size: 16_000_000, kill: true, error_logger: true})
    owner = self()
    guard = spawn_link(fn -> guard(owner, System.monotonic_time(:millisecond) + 1_200_000) end)
    {options, [], []} = OptionParser.parse(args, strict: [parent: :string, output: :string])
    {:ok, base} = Ipse.Workspace.canonical_path(Path.expand(Keyword.fetch!(options, :parent)))
    parent = Path.join(base, "blocks-probe-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    root = Path.join(parent, "collections")
    project = Ipse.JSON.sha256("independent physical planning probe")
    filesystem = filesystem(parent)
    true = filesystem["type"] == "btrfs"
    location = %{"root" => root, "project" => project}
    output = Keyword.fetch!(options, :output)
    File.write!(output <> ".location.json", Jason.encode!(location, pretty: true) <> "\n")
    IO.puts(:stderr, "planning fixture retained at #{root}")
    {:ok, _} = C.execute(root, project, %{"op" => "snapshot"}, Ipse.Usage.id())
    path = Path.join(root, project)
    {:ok, cap} = T.acquire(Path.join(path, ".lock"), cwd: parent, timeout_ms: 120_000)
    :ok = T.quota(cap, :collection, 42 * 1024 * 1024)

    {peak, records} =
      try do
        Enum.reduce(Enum.chunk_every(1..@count, 128), {0, %{}}, fn chunk, {peak, records} ->
          values =
            Enum.map(chunk, fn n ->
              value = value(n)
              bytes = Migration.encode(value)
              true = byte_size(bytes) == 6144
              hash = Ipse.JSON.sha256(bytes)
              {"note#{n}", hash, bytes, ".pending-" <> Ipse.Usage.id()}
            end)

          :ok =
            T.stage(
              cap,
              "objects",
              Enum.map(values, fn {_, _, bytes, pending} -> {pending, bytes} end)
            )

          {:ok, allocation} = T.allocation(cap)
          peak = max(peak, allocation.allocated + @control)

          Enum.each(values, fn {_, hash, _, pending} ->
            :ok = T.install(cap, "objects", pending, hash <> ".json")
          end)

          records =
            Enum.reduce(values, records, fn {key, hash, bytes, _}, rows ->
              Map.put(rows, key, %{
                "key" => key,
                "sha256" => hash,
                "bytes" => byte_size(bytes),
                "revision" => 1,
                "operation_id" => id(1)
              })
            end)

          {peak, records}
        end)
      rescue
        error ->
          T.release(cap)
          reraise error, __STACKTRACE__
      end

    true =
      records |> Map.values() |> Enum.map(& &1["sha256"]) |> Enum.uniq() |> length() == @count

    operations =
      Map.new(1..@operations, fn n ->
        {id(n),
         %{
           "generation" => n,
           "floor" => 0,
           "request_sha256" => Ipse.JSON.sha256("independent synthetic planning receipt #{n}")
         }}
      end)

    state = %{
      "version" => 3,
      "project" => project,
      "generation" => @operations,
      "floor" => 0,
      "floor_anchor" => nil,
      "floor_lineage" => [],
      "records" => records,
      "operations" => operations,
      "imported_operations" => %{},
      "migration" => nil,
      "checkpoint" => nil
    }

    {:ok, bytes, blocks} = Blocks.encode(state)

    peak =
      blocks
      |> Enum.chunk_every(128)
      |> Enum.reduce(peak, fn chunk, peak ->
        files =
          Enum.map(chunk, fn {hash, bytes} -> {hash, bytes, ".pending-" <> Ipse.Usage.id()} end)

        :ok =
          T.stage(
            cap,
            "manifests",
            Enum.map(files, fn {_, bytes, pending} -> {pending, bytes} end)
          )

        {:ok, allocation} = T.allocation(cap)

        Enum.each(files, fn {hash, _, pending} ->
          :ok = T.install(cap, "manifests", pending, hash <> ".json")
        end)

        max(peak, allocation.allocated + @control)
      end)

    manifest = Ipse.JSON.sha256(bytes)
    pending = ".pending-" <> Ipse.Usage.id()
    :ok = T.stage(cap, "manifests", [{pending, bytes}])
    :ok = T.install(cap, "manifests", pending, manifest <> ".json")
    pending = ".pending-" <> Ipse.Usage.id()

    pointer =
      state
      |> Map.take(~w(version project generation floor floor_anchor))
      |> Map.put("version", 4)
      |> Map.put("manifest", manifest)
      |> Jason.encode!()

    :ok = T.stage(cap, ".", [{pending, pointer}])
    {:ok, allocation} = T.allocation(cap)
    peak = max(peak, allocation.allocated + @control)
    :ok = T.switch(cap, pending, "root.json")
    :ok = T.release(cap)
    {:ok, before} = C.execute(root, project, %{"op" => "status"}, Ipse.Usage.id())

    {:ok, exported} =
      C.execute(
        root,
        project,
        %{"op" => "export.plan", "generation" => @operations},
        Ipse.Usage.id()
      )

    samples = :ets.new(:storage_probe, [:public, :set])
    :ets.insert(samples, {:peak, peak})
    observer = "storage-blocks-probe-" <> Ipse.Usage.id()

    :ok =
      :telemetry.attach(
        observer,
        [:ipse, :extension, :collection, :staged],
        fn _, measurements, _, table ->
          [{:peak, previous}] = :ets.lookup(table, :peak)
          :ets.insert(table, {:peak, max(previous, measurements.accounted_allocated_bytes)})
        end,
        samples
      )

    migration_id = Ipse.Usage.id()

    result =
      C.execute(
        root,
        project,
        %{
          "op" => "import.open",
          "expected_generation" => @operations,
          "descriptor" => exported["descriptor"],
          "plan" => exported["plan"]
        },
        migration_id
      )

    completed =
      case result do
        {:ok, receipt} ->
          {generation, _} =
            Enum.reduce(
              Enum.chunk_every(exported["plan"]["records"], 32),
              {receipt["generation"], nil},
              fn chunk, {generation, after_key} ->
                records =
                  Enum.map(chunk, fn [key, _, _] ->
                    number = key |> String.replace_prefix("note", "") |> String.to_integer()
                    %{"key" => key, "value" => value(number)}
                  end)

                {:ok, page} =
                  C.execute(
                    root,
                    project,
                    %{
                      "op" => "import.page",
                      "expected_generation" => generation,
                      "migration_id" => migration_id,
                      "after" => after_key,
                      "records" => records
                    },
                    Ipse.Usage.id()
                  )

                {page["generation"], List.last(records)["key"]}
              end
            )

          {:ok, commit} =
            C.execute(
              root,
              project,
              %{
                "op" => "import.commit",
                "expected_generation" => generation,
                "migration_id" => migration_id
              },
              Ipse.Usage.id()
            )

          {:ok, rollback} =
            C.execute(
              root,
              project,
              %{
                "op" => "rollback",
                "expected_generation" => commit["generation"],
                "checkpoint_id" => commit["checkpoint_id"]
              },
              Ipse.Usage.id()
            )

          %{"import_commit" => commit, "rollback" => rollback, "record_pages" => 128}

        _ ->
          nil
      end

    {:ok, after_status} = C.execute(root, project, %{"op" => "status"}, Ipse.Usage.id())

    {:ok, reexported} =
      C.execute(
        root,
        project,
        %{"op" => "export.plan", "generation" => after_status["generation"]},
        Ipse.Usage.id()
      )

    true = reexported["descriptor"]["records_sha256"] == exported["descriptor"]["records_sha256"]
    {:ok, original_ids} = Encoding.unpack_receipts(exported["plan"]["operations"])
    {:ok, retained_ids} = Encoding.unpack_receipts(reexported["plan"]["operations"])
    true = Enum.all?(original_ids, fn {id, receipt} -> retained_ids[id] == receipt end)
    :telemetry.detach(observer)
    [{:peak, peak}] = :ets.lookup(samples, :peak)
    {:ok, helper} = Ipse.Runner.protected_helper(parent)

    report = %{
      "kind" => "independent_physical_planning_fixture",
      "storage_format" => 4,
      "qualification_passed" => false,
      "individual_operations_performed" => false,
      "synthetic_receipts" => @operations,
      "distinct_values" => @count,
      "value_bytes" => 6144,
      "persistent_policy_exercised" => false,
      "control_stress_overlap" => true,
      "latency_qualified" => false,
      "retained_store" => location,
      "native_helper_sha256" => Ipse.JSON.sha256(File.read!(helper)),
      "filesystem" => filesystem,
      "kernel" => inspect(:os.version()),
      "peak_accounted_allocated_bytes" => peak,
      "fixture_manifest_bytes" => byte_size(bytes),
      "fixture_manifest_sha256" => manifest,
      "fixture_metadata_blocks" => map_size(blocks),
      "all_original_receipts_preserved" => true,
      "roundtrip_record_digest_preserved" => true,
      "completed" => completed,
      "descriptor" => exported["descriptor"],
      "plan_sha256" => Ipse.JSON.digest([exported["plan"]]),
      "import_open_result" => inspect(result),
      "before" => before,
      "after" => after_status,
      "sources" =>
        Map.new(
          ~w(lib/ipse/extension/collection.ex lib/ipse/extension/collection/blocks.ex lib/ipse/extension/collection/migration.ex lib/ipse/extension/collection/encoding.ex lib/ipse/extension/collection/planning.ex native/ipse-storage-profile.rs dev/knowledge/storage_blocks_probe.exs),
          fn file -> {file, Ipse.JSON.sha256(File.read!(file))} end
        )
    }

    if match?({:failed, _}, result) do
      true =
        before["generation"] == after_status["generation"] and
          before["floor"] == after_status["floor"]

      true = is_nil(after_status["migration"])
    else
      true =
        not is_nil(completed) and is_nil(after_status["migration"]) and
          is_nil(after_status["checkpoint"])

      true = after_status["records"] == @count and after_status["floor"] == 0
      true = after_status["generation"] == @operations + 131
    end

    File.write!(output, Jason.encode!(report, pretty: true) <> "\n")
    send(guard, :done)

    IO.puts(
      Jason.encode!(
        Map.take(
          report,
          ~w(import_open_result peak_accounted_allocated_bytes fixture_manifest_bytes)
        )
      )
    )
  end

  defp guard(owner, deadline) do
    receive do
      :done -> :ok
    after
      100 ->
        if System.monotonic_time(:millisecond) >= deadline or
             :erlang.memory(:total) > 512 * 1024 * 1024,
           do: Process.exit(owner, :kill),
           else: guard(owner, deadline)
    end
  end

  defp value(n) do
    base = %{
      "text" => "independent fixture #{n}",
      "evidence" => %{"source" => "synthetic:#{n}", "padding" => ""}
    }

    count = 6144 - byte_size(Migration.encode(base))

    padding =
      for piece <- 0..div(count + 42, 43),
          do: Base.encode64(:crypto.hash(:sha256, "#{n}:#{piece}"), padding: false)

    put_in(
      base,
      ["evidence", "padding"],
      padding |> IO.iodata_to_binary() |> binary_part(0, count)
    )
  end

  defp id(n), do: n |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(32, "0")

  defp filesystem(path) do
    {text, 0} = System.cmd("stat", ["-f", "-c", "%T %S %s", path])
    [type, fragment, block] = String.split(text)
    {:ok, data} = File.open("/proc/self/mountinfo", [:read, :binary], &IO.binread(&1, 1_048_577))
    true = is_binary(data) and byte_size(data) <= 1_048_576

    selected =
      data
      |> String.split("\n", trim: true)
      |> Enum.flat_map(fn row ->
        [left, right] = String.split(row, " - ", parts: 2)

        point =
          left
          |> String.split()
          |> Enum.at(4)
          |> String.replace("\\040", " ")
          |> String.replace("\\134", "\\")

        if path == point or String.starts_with?(path, String.trim_trailing(point, "/") <> "/"),
          do: [{byte_size(point), right}],
          else: []
      end)
      |> Enum.max_by(&elem(&1, 0))
      |> elem(1)
      |> String.split()

    [_type, _source | options] = selected

    options =
      options
      |> Enum.join(",")
      |> String.split(",")
      |> Enum.filter(
        &Regex.match?(
          ~r/\A(?:rw|ro|ssd|compress=[a-z0-9:]+|discard=[a-z]+|space_cache=[a-z0-9]+|huge=[a-z]+)\z/,
          &1
        )
      )

    %{
      "type" => type,
      "fragment_size" => String.to_integer(fragment),
      "block_size" => String.to_integer(block),
      "mount_options" => options
    }
  end
end

Ipse.Development.StorageBlocksProbe.run(System.argv())
