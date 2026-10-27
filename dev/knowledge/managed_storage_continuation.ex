Code.require_file("managed_storage_workload.ex", __DIR__)
Code.require_file("storage_continuation.exs", __DIR__)

defmodule Ipse.Development.ManagedStorageContinuation do
  @moduledoc false
  alias Ipse.Development.{ManagedStorageWorkload, StorageContinuation}
  alias Ipse.Extension.Collection
  alias Ipse.Extension.Collection.{Blocks, Migration, Normalizer}
  alias Ipse.Runner.Transaction
  alias Ipse.Session.SourceIndex
  alias Ipse.{JSON, Usage}

  @checkpoint ~w(version kind binding original location snapshot progress segment target bootstrap_wall_ms baseline_elapsed_ms cumulative_elapsed_ms previous report_sha256)
  @snapshot ~w(root_sha256 descriptor rows_sha256 receipt_count record_count note_count classes)
  @max_segment 8
  @now 1_800_000_000_000

  def validate(checkpoint, binding, target) do
    with true <- keys?(checkpoint, @checkpoint),
         true <- checkpoint["version"] === 1 and checkpoint["kind"] == "managed_storage_capacity",
         true <- checkpoint["binding"] == binding and JSON.sha256?(binding),
         true <- checkpoint["segment"] in 1..7,
         true <- checkpoint["target"] in [2000, 4000] and target in [2000, 4000],
         true <- target >= checkpoint["target"] and checkpoint["progress"] in 1000..3999,
         true <- checkpoint["progress"] < target,
         true <- checkpoint["progress"] <= 1000 + (checkpoint["segment"] - 1) * 1000,
         true <- original?(checkpoint["original"]),
         true <- previous?(checkpoint["previous"], checkpoint["segment"]),
         true <- keys?(checkpoint["snapshot"], @snapshot),
         true <- Migration.descriptor?(checkpoint["snapshot"]["descriptor"]),
         true <- checkpoint["snapshot"]["receipt_count"] == checkpoint["progress"],
         true <- checkpoint["snapshot"]["note_count"] == checkpoint["progress"],
         true <- JSON.sha256?(checkpoint["snapshot"]["root_sha256"]),
         true <- JSON.sha256?(checkpoint["snapshot"]["rows_sha256"]),
         true <- checkpoint["snapshot"]["descriptor"]["generation"] == checkpoint["progress"],
         true <- checkpoint["snapshot"]["descriptor"]["operations"] == checkpoint["progress"],
         true <-
           checkpoint["snapshot"]["record_count"] ==
             checkpoint["snapshot"]["descriptor"]["records"],
         true <- classes?(checkpoint["snapshot"]),
         true <- checkpoint["baseline_elapsed_ms"] === 186_636,
         true <-
           is_integer(checkpoint["bootstrap_wall_ms"]) and checkpoint["bootstrap_wall_ms"] > 0,
         true <-
           is_integer(checkpoint["cumulative_elapsed_ms"]) and
             checkpoint["cumulative_elapsed_ms"] in 0..3_840_000,
         true <- keys?(checkpoint["location"], ~w(root project)),
         true <- JSON.sha256?(checkpoint["location"]["project"]),
         true <-
           checkpoint["location"]["project"] == checkpoint["snapshot"]["descriptor"]["project"],
         true <-
           is_binary(checkpoint["location"]["root"]) and
             byte_size(checkpoint["location"]["root"]) <= 4096,
         true <- JSON.sha256?(checkpoint["report_sha256"]) do
      :ok
    else
      _ -> {:error, :managed_continuation_invalid}
    end
  rescue
    _ -> {:error, :managed_continuation_invalid}
  end

  def matches?(actual, expected), do: actual == expected

  defp original?(value) do
    keys?(value, ~w(report_sha256 runtime_sha256 wire_sha256 runtime_binding_sha256)) and
      Enum.all?(Map.values(value), &JSON.sha256?/1)
  end

  defp previous?(nil, 1), do: true

  defp previous?(value, segment) when segment in 2..8 do
    keys?(value, ~w(path sha256)) and JSON.sha256?(value["sha256"]) and
      is_binary(value["path"]) and byte_size(value["path"]) <= 4096 and
      Path.basename(value["path"]) == "root.json"
  end

  defp previous?(_, _), do: false

  defp classes?(snapshot) do
    classes = snapshot["classes"]

    keys?(classes, ~w(anchor live note)) and
      Enum.all?(Map.values(classes), fn c ->
        keys?(c, ~w(records bytes)) and JSON.safe_uint?(c["records"]) and
          JSON.safe_uint?(c["bytes"])
      end) and
      classes["note"]["records"] == snapshot["note_count"] and
      Enum.sum(Enum.map(Map.values(classes), & &1["records"])) == snapshot["record_count"] and
      Enum.sum(Enum.map(Map.values(classes), & &1["bytes"])) ==
        snapshot["descriptor"]["data_bytes"]
  end

  def snapshot(location, generation) do
    root = location["root"]
    project = location["project"]

    {:ok, plan} =
      Collection.execute(
        root,
        project,
        %{"op" => "export.plan", "generation" => generation},
        Usage.id()
      )

    directory = Path.join(root, project)
    {:ok, cap} = Transaction.acquire(Path.join(directory, ".lock"), cwd: directory)

    result =
      try do
        {:ok, bytes} = Transaction.read(cap, ".", "root.json", 1024)
        pointer = Jason.decode!(bytes)

        true =
          pointer["version"] == 5 and pointer["generation"] == generation and
            pointer["project"] == project

        {:ok, manifest} =
          Transaction.read(cap, "manifests", pointer["manifest"] <> ".json", 8 * 1024 * 1024)

        true = JSON.sha256(manifest) == pointer["manifest"]

        {:ok, state, _} =
          Blocks.decode(Jason.decode!(manifest), fn hash, size ->
            Transaction.read(cap, "manifests", hash <> ".json", size)
          end)

        true = Migration.descriptor(state) == plan["descriptor"]

        true =
          Map.take(pointer, ~w(project generation floor floor_anchor)) ==
            Map.take(state, ~w(project generation floor floor_anchor))

        true = is_nil(state["migration"]) and is_nil(state["checkpoint"])
        operations = Migration.known_operations(state)
        true = map_size(operations) == generation

        true =
          Enum.all?(operations, fn {_, receipt} ->
            Migration.receipt?(receipt) and JSON.sha256?(receipt["managed_binding_sha256"])
          end)

        {rows, classes} =
          Enum.reduce(state["records"], {%{}, %{}}, fn {key, record}, {rows, classes} ->
            {:ok, value} = Transaction.read(cap, "objects", record["sha256"] <> ".json", 6144)
            true = byte_size(value) == record["bytes"] and JSON.sha256(value) == record["sha256"]
            {:ok, decoded} = JSON.decode_unique(value)
            :ok = JSON.validate_object(decoded)
            true = Migration.encode(decoded) == value
            true = operations[record["operation_id"]]["generation"] == record["revision"]

            class =
              cond do
                String.starts_with?(key, "note.") -> "note"
                String.starts_with?(key, "host.validity.anchor.") -> "anchor"
                String.starts_with?(key, "host.validity.live.") -> "live"
              end

            row = Map.take(record, ~w(revision sha256 operation_id))

            classes =
              Map.update(
                classes,
                class,
                %{"records" => 1, "bytes" => record["bytes"]},
                &%{"records" => &1["records"] + 1, "bytes" => &1["bytes"] + record["bytes"]}
              )

            {Map.put(rows, key, row), classes}
          end)

        true = classes["note"]["records"] == generation

        note_generations =
          for {key, row} <- rows, String.starts_with?(key, "note."), do: row["revision"]

        true = Enum.sort(note_generations) == Enum.to_list(1..generation)

        summary = %{
          "root_sha256" => JSON.sha256(bytes),
          "descriptor" => plan["descriptor"],
          "rows_sha256" => JSON.digest([rows]),
          "receipt_count" => map_size(operations),
          "record_count" => map_size(rows),
          "note_count" => generation,
          "classes" => classes
        }

        :ok = Transaction.check(cap)
        {summary, rows, operations}
      after
        :ok = Transaction.release(cap)
      end

    observe_memory()
    result
  end

  def run(args) do
    {opts, [], []} =
      OptionParser.parse(args,
        strict: [
          bootstrap: :boolean,
          report: :string,
          report_sha256: :string,
          runtime: :string,
          runtime_sha256: :string,
          wire: :string,
          wire_sha256: :string,
          resume: :string,
          resume_sha256: :string,
          target: :integer,
          count: :integer,
          output: :string
        ]
      )

    target = opts[:target] || 2000
    count = opts[:count] || 1000
    true = target in [2000, 4000] and count in 1..1000 and is_binary(opts[:output])
    Process.flag(:max_heap_size, %{size: 16_000_000, kill: true, error_logger: true})
    started = System.monotonic_time(:millisecond)
    Process.put({__MODULE__, :started}, started)
    Process.put({__MODULE__, :wall_started}, System.system_time(:millisecond))
    observe_memory()
    driver = self()
    guard = spawn_link(fn -> guard(driver, started, opts[:output]) end)
    telemetry = "managed-continuation-" <> Usage.id()

    :ok =
      :telemetry.attach(
        telemetry,
        [:ipse, :extension, :collection, :staged],
        fn _, m, meta, _ ->
          send(
            driver,
            {:allocated, meta.generation,
             m.accounted_allocated_bytes + m.root_publication_reserved_bytes}
          )
        end,
        nil
      )

    try do
      context = if opts[:bootstrap], do: bootstrap(opts, target), else: resume(opts, target)
      Process.put({__MODULE__, :context}, Map.drop(context, [:rows, :operations]))

      {progress, rows, operations, samples, peak} =
        if opts[:bootstrap] do
          {context.progress, context.rows, context.operations, [], 0}
        else
          publish(context, count, target, opts[:output], started)
        end

      {actual, final_rows, final_operations} = snapshot(context.location, progress)
      true = final_rows == rows
      true = final_operations == operations
      elapsed = System.monotonic_time(:millisecond) - started

      checkpoint = %{
        "version" => 1,
        "kind" => "managed_storage_capacity",
        "binding" => context.binding,
        "original" => context.original,
        "location" => context.location,
        "snapshot" => actual,
        "progress" => progress,
        "segment" => context.segment,
        "target" => target,
        "bootstrap_wall_ms" => context.wall,
        "baseline_elapsed_ms" => 186_636,
        "cumulative_elapsed_ms" => context.cumulative + elapsed,
        "previous" => context.previous
      }

      report = %{
        kind: "development_managed_storage_continuation",
        qualification_passed: false,
        original_baseline_publications: 1000,
        original_baseline_elapsed_ms: 186_636,
        total_publications: progress,
        new_publications_this_segment: progress - context.progress,
        total_new_publications: progress - 1000,
        segment: context.segment,
        target: target,
        primitive_target_reached: progress == target,
        runtime_binding_sha256: context.binding,
        native_managed_allocated_peak_bytes_this_segment: peak,
        maximum_sampled_beam_bytes: Process.get({__MODULE__, :peak_beam}),
        publication_ms: samples,
        elapsed_ms: elapsed,
        cumulative_segment_elapsed_ms: context.cumulative + elapsed,
        chronological_wall_since_bootstrap_ms: System.system_time(:millisecond) - context.wall,
        original_whole_series_chronological_wall_known: false,
        active_elapsed_excludes_final_oracle_commit: true,
        source_snapshot: actual,
        automatic_retries: 0,
        performance_qualified: false,
        domain_annual_qualified: false,
        actual_session_exercised: false,
        actual_human_input: false,
        oracle_excluded_from_product_quota: true
      }

      commit_started = System.monotonic_time(:millisecond)
      {:ok, reference} = StorageContinuation.finish(context.handle, checkpoint, report)

      report =
        report
        |> Map.put(:continuation, reference)
        |> Map.put(:oracle_commit_ms, System.monotonic_time(:millisecond) - commit_started)
        |> Map.put(
          :chronological_wall_since_bootstrap_ms,
          System.system_time(:millisecond) - context.wall
        )

      File.write!(opts[:output], Jason.encode!(report, pretty: true) <> "\n")
      IO.puts(Jason.encode!(report, pretty: true))
      report
    rescue
      error ->
        failure = %{
          qualification_passed: false,
          kind: "development_managed_continuation_failure",
          error: Exception.message(error),
          last_call: Process.get({__MODULE__, :last_call}),
          context: Process.get({__MODULE__, :context}),
          automatic_retries: 0
        }

        File.write(opts[:output] <> ".failure.json", Jason.encode!(failure, pretty: true) <> "\n")
        reraise error, __STACKTRACE__
    after
      :telemetry.detach(telemetry)
      Process.unlink(guard)
      Process.exit(guard, :kill)
    end
  end

  defp bootstrap(opts, target) do
    report = artifact(opts[:report], opts[:report_sha256], 128 * 1024)
    runtime = artifact(opts[:runtime], opts[:runtime_sha256], 2 * 1024 * 1024)
    wire = artifact(opts[:wire], opts[:wire_sha256], 4096)

    true =
      report["successful_publications"] === 1000 and report["attempted_publications"] === 1000

    true = report["stop_reason"] == "run_limit" and is_nil(report["refusal"])

    true =
      report["elapsed_ms"] === 186_636 and
        report["runtime_binding_sha256"] == JSON.digest([runtime])

    true =
      report["runtime_binding_sha256"] ==
        "ec1339fefc0be4ba8689124555a5c4c8b712fe0de95fc15b2a9ed5f3926ea1a9"

    true = wire["root"]["generation"] === 1000 and JSON.sha256?(wire["root_sha256"])

    true =
      runtime["elixir"] == System.version() and
        runtime["erts"] == to_string(:erlang.system_info(:system_version))

    Enum.each(runtime["sources"], fn {path, hash} ->
      true = JSON.sha256(File.read!(path)) == hash
    end)

    Enum.each(runtime["beams"], fn {path, hash} ->
      true = JSON.sha256(File.read!(path)) == hash
    end)

    location = report["location"]
    {:ok, helper} = Ipse.Runner.protected_helper(Path.dirname(location["root"]))
    true = runtime["helper_sha256"] == JSON.sha256(File.read!(helper))
    binding = runtime_binding(location)
    wall = Process.get({__MODULE__, :wall_started})
    directory = oracle_directory(location, 1)

    {:ok, handle} =
      StorageContinuation.start(directory, %{binding: binding, segment: 1, progress: 1000})

    Process.put({__MODULE__, :context}, %{location: location, handle: handle, binding: binding})

    {actual, rows, operations} = snapshot(location, 1000)
    true = actual["root_sha256"] == wire["root_sha256"]
    true = actual["classes"] == report["terminal_verification"]

    original = %{
      "report_sha256" => opts[:report_sha256],
      "runtime_sha256" => opts[:runtime_sha256],
      "wire_sha256" => opts[:wire_sha256],
      "runtime_binding_sha256" => report["runtime_binding_sha256"]
    }

    %{
      location: location,
      binding: binding,
      wall: wall,
      cumulative: 0,
      original: original,
      progress: 1000,
      segment: 1,
      rows: rows,
      operations: operations,
      previous: nil,
      handle: handle,
      target: target
    }
  end

  defp resume(opts, target) do
    reference = %{"path" => Path.expand(opts[:resume]), "sha256" => opts[:resume_sha256]}
    {:ok, checkpoint, _} = StorageContinuation.read(reference["path"], reference["sha256"])
    location = checkpoint["location"]
    binding = runtime_binding(location)
    :ok = validate(checkpoint, binding, target)
    verify_chain(checkpoint, binding, target)

    true =
      reference["path"] ==
        Path.join(oracle_directory(location, checkpoint["segment"], false), "root.json")

    segment = checkpoint["segment"] + 1
    directory = oracle_directory(location, segment)

    {:ok, handle} =
      StorageContinuation.start(directory, %{
        binding: binding,
        segment: segment,
        progress: checkpoint["progress"],
        previous: reference
      })

    Process.put({__MODULE__, :context}, %{location: location, handle: handle, binding: binding})

    {actual, rows, operations} = snapshot(location, checkpoint["progress"])
    true = matches?(actual, checkpoint["snapshot"])

    %{
      location: location,
      binding: binding,
      wall: checkpoint["bootstrap_wall_ms"],
      cumulative: checkpoint["cumulative_elapsed_ms"],
      original: checkpoint["original"],
      progress: checkpoint["progress"],
      segment: segment,
      rows: rows,
      operations: operations,
      previous: reference,
      handle: handle,
      target: target
    }
  end

  defp publish(context, count, target, output, started) do
    Enum.reduce_while(
      1..min(count, target - context.progress),
      {context.progress, context.rows, context.operations, [], 0},
      fn _, {generation, rows, operations, samples, peak} = current ->
        if System.monotonic_time(:millisecond) - started >= 360_000 do
          {:halt, current}
        else
          fixture = ManagedStorageWorkload.fixture(generation + 1)
          options = ManagedStorageWorkload.options(fixture, generation)
          id = Usage.id()

          Process.put({__MODULE__, :last_call}, %{
            operation_id: id,
            request: options.request,
            before_generation: generation
          })

          before = System.monotonic_time(:microsecond)

          result =
            Collection.execute_managed(
              context.location["root"],
              context.location["project"],
              options.request,
              id,
              JSON.digest([options.recipe]),
              fn witness, read ->
                {:ok, %{"proof" => proof}} =
                  SourceIndex.resolve_proof(fixture.index, fixture.proof_request)

                true = proof == fixture.proof
                Normalizer.normalize(witness, read, options)
              end
            )

          case result do
            {:ok, %{"receipt" => receipt, "normalization" => normalization, "binding" => bound}} ->
              next = generation + 1

              true =
                receipt["generation"] == next and
                  receipt["managed_binding_sha256"] == JSON.digest([bound])

              true = bound["original_request_sha256"] == JSON.digest([options.request])
              true = bound["normalization_sha256"] == JSON.digest([normalization])

              true =
                normalization["first_admitted_ms"] == @now and
                  normalization["valid_until_ms"] == @now + 90 * 86_400_000

              row = fn hash -> %{"revision" => next, "sha256" => hash, "operation_id" => id} end
              false = Map.has_key?(rows, fixture.key)

              rows =
                Map.put(rows, fixture.key, row.(JSON.sha256(Migration.encode(fixture.value))))

              rows =
                Enum.reduce(~w(anchor live), rows, fn kind, all ->
                  Map.put(
                    all,
                    normalization[kind <> "_key"],
                    row.(normalization[kind <> "_value_sha256"])
                  )
                end)

              allocated =
                receive do
                  {:allocated, ^next, bytes} -> bytes
                after
                  0 -> raise "missing native allocation observation"
                end

              ms = (System.monotonic_time(:microsecond) - before) / 1000
              observe_memory()

              if rem(next, 100) == 0,
                do:
                  File.write!(
                    output <> ".partial.json",
                    Jason.encode!(%{
                      qualification_passed: false,
                      generation: next,
                      native_managed_peak: max(peak, allocated),
                      elapsed_ms: System.monotonic_time(:millisecond) - started
                    })
                  )

              {:cont,
               {next, rows, Map.put(operations, id, receipt), [ms | samples],
                max(peak, allocated)}}

            other ->
              raise "managed publication stopped without retry at #{generation}: #{inspect(other, limit: 30)}"
          end
        end
      end
    )
  end

  defp artifact(path, hash, limit) do
    true = JSON.sha256?(hash)
    {:ok, stat} = File.lstat(path)
    true = stat.type == :regular and stat.size <= limit
    bytes = File.read!(path)
    true = JSON.sha256(bytes) == hash
    {:ok, value} = JSON.decode_unique(bytes)
    value
  end

  defp verify_chain(%{"segment" => 1, "previous" => nil}, _binding, _target), do: :ok

  defp verify_chain(current, binding, target) do
    reference = current["previous"]
    {:ok, earlier, _} = StorageContinuation.read(reference["path"], reference["sha256"])
    :ok = validate(earlier, binding, target)
    true = earlier["segment"] == current["segment"] - 1

    true =
      earlier["location"] == current["location"] and earlier["original"] == current["original"]

    true = earlier["bootstrap_wall_ms"] == current["bootstrap_wall_ms"]

    true =
      earlier["progress"] <= current["progress"] and
        current["progress"] - earlier["progress"] <= 1000

    true = earlier["cumulative_elapsed_ms"] <= current["cumulative_elapsed_ms"]

    true =
      reference["path"] ==
        Path.join(oracle_directory(current["location"], earlier["segment"], false), "root.json")

    verify_chain(earlier, binding, target)
  end

  defp observe_memory do
    memory = :erlang.memory(:total)
    Process.put({__MODULE__, :peak_beam}, max(Process.get({__MODULE__, :peak_beam}, 0), memory))
  end

  def runtime_binding(location) do
    sources =
      Path.wildcard("lib/**/*.ex") ++
        ~w(extensions/knowledge/src/notes.ex extensions/knowledge/src/knowledge/records.ex extensions/knowledge/src/knowledge/contracts.ex dev/knowledge/managed_storage_workload.ex dev/knowledge/managed_storage_workload.exs dev/knowledge/storage_continuation.exs dev/knowledge/managed_storage_continuation.ex dev/knowledge/managed_storage_continuation.exs)

    StorageContinuation.binding(
      sources,
      Path.dirname(:code.which(Collection)),
      Path.dirname(location["root"])
    )
  end

  defp oracle_directory(location, segment, create \\ true) do
    true = segment in 1..@max_segment
    parent = Path.join(Path.dirname(location["root"]), "managed-oracle")

    if create and not File.exists?(parent) do
      File.mkdir!(parent)
      File.chmod!(parent, 0o700)
      :ok = Ipse.Runner.protected_sync_directory(Path.dirname(parent))
    end

    Path.join(parent, "segment-#{segment}")
  end

  defp guard(driver, started, output) do
    elapsed = System.monotonic_time(:millisecond) - started
    memory = :erlang.memory(:total)

    if elapsed >= 480_000 or memory > 536_870_912 do
      spawn(fn ->
        Process.sleep(10)
        Process.exit(driver, :kill)
      end)

      File.write(
        output <> ".resource-failure.json",
        Jason.encode!(%{
          qualification_passed: false,
          elapsed_ms: elapsed,
          observed_beam_bytes: memory,
          deadline_ms: 480_000,
          memory_limit_bytes: 536_870_912
        })
      )

      Process.exit(driver, :kill)
    else
      receive do
      after
        100 -> guard(driver, started, output)
      end
    end
  end

  defp keys?(map, fields), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(fields)
end
