defmodule Ipse.Development.StorageAnnual do
  @moduledoc false
  alias Ipse.Development.StorageWorkload, as: W
  alias Ipse.Development.StorageContinuation, as: Oracle
  alias Ipse.Extension.Collection.{Encoding, Migration}
  @fields ~w(generation samples peak peak_allocated peak_ram pauses migrations queued_actions)

  def run(args) do
    Process.flag(:max_heap_size, %{size: 16_000_000, kill: true, error_logger: true})
    started = System.monotonic_time(:millisecond)
    wall_started = System.system_time(:millisecond)
    driver = self()
    monitor = spawn_link(fn -> W.resource_guard(driver, started) end)
    Process.put({W, :monitor}, monitor)
    Process.put({W, :calls}, %{})
    telemetry_id = "storage-annual-" <> Ipse.Usage.id()

    :ok =
      :telemetry.attach(
        telemetry_id,
        [:ipse, :extension, :collection, :staged],
        &W.allocation_event/4,
        driver
      )

    {opts, [], []} =
      OptionParser.parse(args,
        strict: [
          segmented: :boolean,
          resume: :string,
          resume_sha256: :string,
          days: :integer,
          cycles: :integer,
          payload: :string,
          granularity: :string,
          parent: :string,
          output: :string,
          segment_publications: :integer
        ]
      )

    send(monitor, {:output, opts[:output]})

    try do
      options = %{
        "days" => opts[:days] || 365,
        "cycles" => opts[:cycles] || 10_000,
        "payload" => opts[:payload] || "maximum",
        "granularity" => opts[:granularity] || "individual",
        "segment_publications" => opts[:segment_publications] || 6000
      }

      true = options["days"] in 1..365 and options["cycles"] in 0..10_000

      true =
        options["payload"] in ~w(representative maximum) and
          options["granularity"] == "individual"

      true = options["segment_publications"] in 1..6000 and is_binary(opts[:output])
      {ctx, state, desired, progress, checkpoints} = prepare(opts, options, started, wall_started)
      Process.put({__MODULE__, :location}, ctx.location)
      state = if is_nil(ctx.previous), do: W.publish(state, desired), else: state

      {state, progress, checkpoints, complete} =
        try do
          {state, _desired, checkpoints} =
            Enum.reduce(
              sequence(progress["day"] + 1, options["days"]),
              {state, desired, checkpoints},
              fn day, {state, desired, checkpoints} ->
                {state, desired} =
                  W.advance_day(state, desired, day, options["payload"], "individual")

                checkpoints =
                  if day in [30, 90, 365],
                    do: Map.put(checkpoints, to_string(day), W.status(state)),
                    else: checkpoints

                if rem(day, 30) == 0, do: W.restart_read(state)
                partial(opts[:output], state, day, 0, ctx.segment)

                if rem(day, 30) == 0,
                  do:
                    IO.puts(
                      :stderr,
                      "storage annual segment #{ctx.segment} day #{day}, generation #{state.generation}"
                    )

                maybe_stop(ctx, state, %{"day" => day, "cycle" => 0}, checkpoints)
                {state, desired, checkpoints}
              end
            )

          state =
            Enum.reduce(sequence(progress["cycle"] + 1, options["cycles"]), state, fn n, state ->
              state = W.cycle(state, n)

              if rem(n, 100) == 0 do
                state = W.observe(state)
                partial(opts[:output], state, options["days"], n, ctx.segment)

                if rem(n, 1000) == 0,
                  do:
                    IO.puts(
                      :stderr,
                      "storage annual segment #{ctx.segment} cycles #{n}, generation #{state.generation}"
                    )

                maybe_stop(ctx, state, %{"day" => options["days"], "cycle" => n}, checkpoints)
                state
              else
                state
              end
            end)

          {state, %{"day" => options["days"], "cycle" => options["cycles"]}, checkpoints, true}
        catch
          {:clean_segment_boundary, state, progress, checkpoints} ->
            {state, progress, checkpoints, false}
        end

      state =
        if complete and options["days"] == 365,
          do: W.migration_roundtrip(state, "final365"),
          else: state

      state = W.observe(state)
      {descriptor, records, _} = W.export_pages(state, "export", "records", 32)
      actual_rows = rows(records)
      true = Oracle.record_digest(actual_rows) == Oracle.record_digest(state.rows)
      operations = ledger(state, descriptor)
      verify_ancestors(operations, descriptor, ctx.chain)
      elapsed = System.monotonic_time(:millisecond) - started

      saved_state =
        Map.new(@fields, fn key -> {key, Map.fetch!(state, String.to_existing_atom(key))} end)
        |> Map.put("checkpoints", checkpoints)

      checkpoint = %{
        "version" => 1,
        "binding" => ctx.binding,
        "options" => options,
        "segment" => ctx.segment,
        "progress" => progress,
        "descriptor" => descriptor,
        "records_digest" => Oracle.record_digest(actual_rows),
        "state" => saved_state,
        "calls" => Process.get({W, :calls}),
        "resume_calls" => ctx.resume_calls,
        "first_wall_ms" => ctx.first_wall_ms,
        "cumulative_ms" => ctx.cumulative_ms + elapsed,
        "previous" => ctx.previous
      }

      report = report(ctx, state, progress, complete, checkpoints, descriptor, elapsed)
      commit_started = System.monotonic_time(:millisecond)
      {:ok, reference} = Oracle.finish(ctx.handle, checkpoint, report)

      report =
        report
        |> Map.put("continuation", reference)
        |> Map.put("oracle_commit_ms", System.monotonic_time(:millisecond) - commit_started)
        |> Map.put("chronological_wall_ms", System.system_time(:millisecond) - ctx.first_wall_ms)

      File.write!(opts[:output], Jason.encode!(report, pretty: true) <> "\n")
      IO.puts(Jason.encode!(report, pretty: true))
      report
    rescue
      exception ->
        failure = %{
          "kind" => "development_storage_annual_failure",
          "qualification_passed" => false,
          "error" => Exception.message(exception),
          "last_call" => Process.get({W, :last_call}),
          "calls" => Process.get({W, :calls}),
          "elapsed_ms" => System.monotonic_time(:millisecond) - started,
          "retained_store" => Process.get({__MODULE__, :location}),
          "automatic_retries" => 0
        }

        if opts[:output],
          do:
            File.write(
              opts[:output] <> ".failure.json",
              Jason.encode!(failure, pretty: true) <> "\n"
            )

        reraise exception, __STACKTRACE__
    after
      :telemetry.detach(telemetry_id)
      Process.unlink(monitor)
      Process.exit(monitor, :kill)
    end
  end

  def regenerate(day, cycles, payload) do
    initial = W.seed(payload)

    {desired, actual, queue, queued_actions} =
      Enum.reduce(sequence(1, day), {initial, initial, [], 0}, fn day,
                                                                  {desired, actual, queue,
                                                                   queued_actions} ->
        actions = W.daily_actions(desired, day, payload, if(day == 90, do: 2, else: 1))
        desired = Enum.reduce(actions, desired, &W.apply_action(&2, &1))

        if day in 120..126 do
          {desired, actual, Enum.reverse(actions) ++ queue, queued_actions + length(actions)}
        else
          {desired, desired, [], queued_actions}
        end
      end)

    actual =
      Enum.reduce(sequence(1, cycles), actual, fn n, actual ->
        W.apply_action(actual, [{"cycle", W.cycle_value(n)}])
      end)

    {desired, actual, queue, queued_actions}
  end

  defp prepare(opts, options, started, wall_started) do
    project = Ipse.JSON.sha256("independent development storage workload v1")

    previous =
      if opts[:resume],
        do: %{"path" => Path.expand(opts[:resume]), "sha256" => opts[:resume_sha256]}

    parent =
      if previous do
        Path.dirname(Path.dirname(Path.dirname(previous["path"])))
      else
        {:ok, base} =
          Ipse.Workspace.canonical_path(Path.expand(opts[:parent] || System.tmp_dir!()))

        path = Path.join(base, "ipse-storage-annual-" <> Ipse.Usage.id())
        File.mkdir!(path)
        File.chmod!(path, 0o700)
        path
      end

    root = Path.join(parent, "collections")
    oracle = Path.join(parent, "oracle")

    binding =
      Oracle.binding(source_files(), Path.dirname(:code.which(Ipse.Extension.Collection)), parent)

    provenance = Map.put(W.provenance(parent), "filesystem", W.filesystem(parent))
    location = %{"root" => root, "project" => project, "provenance" => provenance}
    Process.put({__MODULE__, :location}, location)
    File.write!(opts[:output] <> ".location.json", Jason.encode!(location, pretty: true) <> "\n")
    IO.puts(:stderr, "storage annual retained store #{root}")

    state = %{
      root: root,
      project: project,
      generation: 0,
      rows: %{},
      samples: [],
      peak: 0,
      peak_allocated: 0,
      peak_ram: 0,
      pauses: 0,
      migrations: [],
      offline_queue: [],
      queued_actions: 0
    }

    {state, desired, progress, checkpoints, chain, segment, wall, prior, resume_calls, previous} =
      if previous do
        {:ok, checkpoint, _} = Oracle.read(previous["path"], previous["sha256"])
        :ok = Oracle.validate(checkpoint, binding, options)
        segment = checkpoint["segment"] + 1
        {:ok, names} = File.ls(oracle)
        true = Enum.sort(names) == Enum.map(1..checkpoint["segment"], &"segment-#{&1}")
        chain = chain(previous, oracle, checkpoint["segment"], binding, options)
        true = File.regular?(Path.join([root, project, "root.json"]))
        saved = checkpoint["state"]

        state =
          Enum.reduce(@fields, state, fn key, state ->
            Map.put(state, String.to_existing_atom(key), saved[key])
          end)

        {descriptor, records, _} = W.export_pages(state, "export", "records", 32)
        true = descriptor == checkpoint["descriptor"]
        actual_rows = rows(records)
        true = Oracle.record_digest(actual_rows) == checkpoint["records_digest"]
        operations = ledger(state, descriptor)
        verify_ancestors(operations, descriptor, chain)
        progress = checkpoint["progress"]

        {desired, actual, queue, queued_actions} =
          regenerate(progress["day"], progress["cycle"], options["payload"])

        true = Map.new(actual_rows, fn {key, row} -> {key, row["value"]} end) == actual
        true = queued_actions == saved["queued_actions"]
        state = %{state | rows: actual_rows, offline_queue: queue}
        resume_calls = merge_counts(checkpoint["resume_calls"], Process.get({W, :calls}))
        Process.put({W, :calls}, checkpoint["calls"])
        previous = Map.put(previous, "report_sha256", checkpoint["report_sha256"])

        {state, desired, progress, saved["checkpoints"], chain, segment,
         checkpoint["first_wall_ms"], checkpoint["cumulative_ms"], resume_calls, previous}
      else
        File.mkdir!(oracle)
        File.chmod!(oracle, 0o700)
        :ok = Ipse.Runner.protected_sync_directory(parent)

        {state, W.seed(options["payload"]), %{"day" => 0, "cycle" => 0}, %{}, [], 1, wall_started,
         0, %{}, nil}
      end

    true = segment in 1..4
    directory = Path.join(oracle, "segment-#{segment}")

    {:ok, handle} =
      Oracle.start(directory, %{
        "version" => 1,
        "binding" => binding,
        "segment" => segment,
        "previous" => previous
      })

    ctx = %{
      options: options,
      binding: binding,
      handle: handle,
      previous: previous,
      chain: chain,
      segment: segment,
      first_wall_ms: wall,
      cumulative_ms: prior,
      resume_calls: resume_calls,
      started: started,
      initial_samples: length(state.samples),
      location: location
    }

    {ctx, state, desired, progress, checkpoints}
  end

  defp chain(reference, oracle, number, binding, options) do
    true = reference["path"] == Path.join([oracle, "segment-#{number}", "root.json"])
    {:ok, checkpoint, _} = Oracle.read(reference["path"], reference["sha256"])
    :ok = Oracle.validate(checkpoint, binding, options)
    true = checkpoint["segment"] == number

    true =
      is_nil(reference["report_sha256"]) or
        reference["report_sha256"] == checkpoint["report_sha256"]

    if number == 1 do
      true = is_nil(checkpoint["previous"])
      [checkpoint]
    else
      previous = chain(checkpoint["previous"], oracle, number - 1, binding, options)
      true = hd(previous)["first_wall_ms"] == checkpoint["first_wall_ms"]
      true = hd(previous)["cumulative_ms"] <= checkpoint["cumulative_ms"]
      [checkpoint | previous]
    end
  end

  defp ledger(state, descriptor) do
    {:ok, %{"descriptor" => ^descriptor, "plan" => plan}} =
      W.execute(
        state.root,
        state.project,
        %{"op" => "export.plan", "generation" => state.generation},
        Ipse.Usage.id()
      )

    {:ok, operations} = Encoding.unpack_receipts(plan["operations"])

    true =
      map_size(operations) == descriptor["operations"] and
        map_size(operations) == descriptor["generation"]

    true = Migration.operation_digest(operations) == descriptor["operations_sha256"]
    operations
  end

  defp verify_ancestors(operations, descriptor, chain) do
    Enum.each(chain, fn checkpoint ->
      old = checkpoint["descriptor"]

      prefix =
        Map.filter(operations, fn {_, receipt} -> receipt["generation"] <= old["generation"] end)

      true = map_size(prefix) == old["operations"]
      true = Migration.operation_digest(prefix) == old["operations_sha256"]
      true = Migration.lineage_extends?(old["floor_lineage"], descriptor["floor_lineage"])
    end)
  end

  defp maybe_stop(ctx, state, progress, checkpoints) do
    complete =
      progress["day"] == ctx.options["days"] and progress["cycle"] == ctx.options["cycles"]

    if not complete and
         (length(state.samples) - ctx.initial_samples >= ctx.options["segment_publications"] or
            System.monotonic_time(:millisecond) - ctx.started >= 5_400_000) do
      throw({:clean_segment_boundary, state, progress, checkpoints})
    end
  end

  defp report(ctx, state, progress, complete, checkpoints, descriptor, elapsed) do
    samples = Enum.sort(state.samples)

    %{
      "kind" => "development_storage_annual_segment_v1",
      "options" => ctx.options,
      "progress" => progress,
      "segment" => ctx.segment,
      "maximum_segments" => 4,
      "driver_deadline_ms" => 7_200_000,
      "driver_elapsed_ms" => elapsed,
      "cumulative_active_before_oracle_commit_ms" => ctx.cumulative_ms + elapsed,
      "active_timing_scope" =>
        "segment start through full boundary validation; final oracle commit measured separately; chronological wall includes commits and restart gaps",
      "runtime_binding_sha256" => ctx.binding,
      "retained_store" => ctx.location,
      "previous" => ctx.previous,
      "oracle_directory" => ctx.handle.directory,
      "oracle_quota_bytes_per_segment" => 8 * 1024 * 1024,
      "oracle_excluded_from_product_managed_usage" => true,
      "live_calls" => 0,
      "nominal_turns_per_day" => 40,
      "turn_pipeline_exercised" => false,
      "capture_pipeline_exercised" => false,
      "host_source_admission_exercised" => false,
      "expiry_lineage_overrides_persisted" => false,
      "domain_recapture_protection_qualified" => false,
      "source_fixture" => "synthetic note evidence maps; no authenticated Sources artifact",
      "concurrent_control_stress" => true,
      "performance_qualified" => false,
      "qualification_passed" => false,
      "storage_publications_completed" => complete,
      "call_attempts_by_operation" => Process.get({W, :calls}),
      "startup_validation_calls_separate" => ctx.resume_calls,
      "actual_commit_calls" => Map.get(Process.get({W, :calls}), "commit", 0),
      "actual_read_calls_including_startup_validation" =>
        count(
          Process.get({W, :calls}),
          ~w(status snapshot get scan export export.operations export.plan fresh_vm_snapshot)
        ) +
          count(
            ctx.resume_calls,
            ~w(status snapshot get scan export export.operations export.plan fresh_vm_snapshot)
          ),
      "actual_migration_calls" =>
        count(
          Process.get({W, :calls}),
          ~w(import.open import.page import.operations import.commit import.abort checkpoint.drop rollback)
        ),
      "cycle_value_mode" => "small_generic_one_key_receipt_churn",
      "floor_policy" =>
        "advance on existing-record replacement or deletion; pure additions preserve lineage",
      "ordinary_per_day" => 20,
      "corrections_per_day" => 4,
      "forgets_per_day" => 2,
      "temporal_supersessions_per_day" => 4,
      "delayed_temporal_first_update_day" => 100,
      "persistent_initial" => %{"pins" => 100, "preferences" => 50, "current" => 50},
      "initial_note_count" => 2000,
      "initial_publications" => 16,
      "burst_day" => 90,
      "burst_multiplier" => 2,
      "offline_known_unstarted_actions" => state.queued_actions,
      "offline_actions_remaining" => length(state.offline_queue),
      "publication_samples" => length(samples),
      "publication_ms_mean" => Enum.sum(samples) / length(samples),
      "publication_ms_p50" => W.percentile(samples, 0.50),
      "publication_ms_p95" => W.percentile(samples, 0.95),
      "publication_ms_max" => List.last(samples),
      "diagnostic_sampling" =>
        "daily status and selected get; every100cycles; full export/receipt verification at boundaries and resumes; native allocation every publication",
      "maximum_sampled_accounted_disk_bytes" => state.peak,
      "peak_accounted_allocated_bytes" => state.peak_allocated,
      "maximum_post_publication_vm_memory_bytes" => state.peak_ram,
      "checkpoints" => checkpoints,
      "migrations" => Enum.reverse(state.migrations),
      "required_migration_gate_passed" =>
        if(state.migrations != [], do: Enum.all?(state.migrations, &(&1["outcome"] == "passed"))),
      "boundary_descriptor" =>
        descriptor
        |> Map.drop(["floor_lineage"])
        |> Map.put("floor_lineage_entries", length(descriptor["floor_lineage"])),
      "boundary_descriptor_sha256" => Ipse.JSON.digest([descriptor]),
      "full_applied_lineage_location" =>
        "protected oracle checkpoint; report retains its count/hash"
    }
  end

  defp source_files do
    Enum.sort(
      Path.wildcard("lib/**/*.ex") ++
        Path.wildcard("extensions/bundled/**/*.ex") ++
        ~w(mix.exs mix.lock native/ipse-storage-profile.rs extensions/knowledge/src/notes.ex dev/knowledge/storage_workload.ex dev/knowledge/storage_workload.exs dev/knowledge/storage_continuation.exs dev/knowledge/storage_annual.exs)
    )
  end

  defp partial(path, state, day, cycle, segment) do
    File.write!(
      path <> ".partial.json",
      Jason.encode!(%{
        "kind" => "development_storage_annual_partial",
        "qualification_passed" => false,
        "day" => day,
        "cycle" => cycle,
        "segment" => segment,
        "generation" => state.generation,
        "records" => map_size(state.rows),
        "peak_allocated" => state.peak_allocated,
        "peak_vm" => state.peak_ram
      }) <> "\n"
    )
  end

  defp rows(records), do: Map.new(records, &{&1["key"], Map.take(&1, ~w(revision value))})
  defp sequence(first, last) when first > last, do: []
  defp sequence(first, last), do: first..last
  defp merge_counts(a, b), do: Map.merge(a, b, fn _, x, y -> x + y end)
  defp count(counters, operations), do: Enum.sum(Enum.map(operations, &Map.get(counters, &1, 0)))
end
