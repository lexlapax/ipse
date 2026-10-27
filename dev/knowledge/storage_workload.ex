defmodule Ipse.Development.StorageWorkload do
  @moduledoc false
  alias Ipse.Extension.Collection, as: C
  @day 86_400_000
  @base 90 * @day

  def check do
    initial = seed("representative")
    true = map_size(initial) == 2000
    true = Enum.count(initial, fn {_, n} -> is_nil(n["expires_at_ms"]) end) == 200
    maximum = seed("maximum")
    true = Enum.all?(maximum, fn {_, n} -> byte_size(Jason.encode!(n)) == 6144 end)

    {rows, queued, queued_base} =
      Enum.reduce(1..130, {initial, [], nil}, fn day, {rows, queued, queued_base} ->
        actions = daily_actions(rows, day, "representative", if(day == 90, do: 2, else: 1))
        true = length(actions) == if(day == 90, do: 61, else: 31)
        queued_base = if day == 120, do: rows, else: queued_base
        queued = if day in 120..126, do: queued ++ actions, else: queued
        rows = Enum.reduce(actions, rows, &apply_action(&2, &1))

        true =
          Enum.count(rows, fn {_, n} -> n["category"] in ~w(pin preference current) end) == 200

        if day == 126 do
          true = length(queued) == 217
          true = Enum.reduce(queued, queued_base, &apply_action(&2, &1)) == rows
        end

        {rows, queued, queued_base}
      end)

    true = length(queued) == 217 and is_map(queued_base)
    delayed = initial[Ipse.JSON.sha256("persistent:200")]
    history = rows[history_key(delayed)]
    true = history["superseded_at_ms"] == @base + 100 * @day
    true = history["expires_at_ms"] == @base + 465 * @day
    true = IpseKnowledge.Notes.eligible?(history, @base + 365 * @day)

    IO.puts(
      "storage driver pure checks passed: seed, max payloads, daily counts, 217 offline actions, delayed temporal support"
    )
  end

  def run(args) do
    # Independent bounds protect the development driver as well as the store.
    # Binary memory is sampled separately because a heap limit alone excludes it.
    Process.flag(:max_heap_size, %{size: 16_000_000, kill: true, error_logger: true})
    driver = self()
    started = System.monotonic_time(:millisecond)
    Process.put({__MODULE__, :calls}, %{})
    monitor = spawn_link(fn -> resource_guard(driver, System.monotonic_time(:millisecond)) end)
    Process.put({__MODULE__, :monitor}, monitor)
    telemetry_id = "storage-workload-" <> Ipse.Usage.id()

    :ok =
      :telemetry.attach(
        telemetry_id,
        [:ipse, :extension, :collection, :staged],
        &__MODULE__.allocation_event/4,
        driver
      )

    {opts, [], []} =
      OptionParser.parse(args,
        strict: [
          days: :integer,
          cycles: :integer,
          payload: :string,
          granularity: :string,
          output: :string,
          parent: :string
        ]
      )

    send(monitor, {:output, opts[:output]})

    days = Keyword.get(opts, :days, 365)
    cycles = Keyword.get(opts, :cycles, 10_000)
    payload = Keyword.get(opts, :payload, "representative")
    granularity = Keyword.get(opts, :granularity, "individual")
    true = days in 1..365 and cycles in 0..10_000 and payload in ~w(representative maximum)
    true = granularity in ~w(individual batched)

    {:ok, base_directory} =
      Ipse.Workspace.canonical_path(Path.expand(opts[:parent] || System.tmp_dir!()))

    parent = Path.join(base_directory, "ipse-storage-workload-" <> Ipse.Usage.id())
    File.mkdir!(parent)
    File.chmod!(parent, 0o700)
    root = Path.join(parent, "collections")
    project = Ipse.JSON.sha256("independent development storage workload v1")
    provenance = Map.put(provenance(parent), "filesystem", filesystem(parent))
    location = %{"root" => root, "project" => project, "provenance" => provenance}

    if opts[:output],
      do:
        File.write!(
          opts[:output] <> ".location.json",
          Jason.encode!(location, pretty: true) <> "\n"
        )

    IO.puts(:stderr, "storage development store retained at #{root}")

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

    try do
      initial = seed(payload)
      state = publish(state, initial)
      checkpoints = %{}

      {state, _desired, checkpoints} =
        Enum.reduce(1..days, {state, initial, checkpoints}, fn day,
                                                               {state, desired, checkpoints} ->
          {state, desired} = advance_day(state, desired, day, payload, granularity)

          checkpoints =
            if day in [30, 90, 365],
              do: Map.put(checkpoints, to_string(day), status(state)),
              else: checkpoints

          if rem(day, 30) == 0, do: restart_read(state)
          checkpoint(opts[:output], state, day, 0)

          if rem(day, 30) == 0,
            do:
              IO.puts(:stderr, "storage development day #{day}: #{map_size(state.rows)} records")

          {state, desired, checkpoints}
        end)

      # A fixed correction/forget workload tests receipt growth separately from
      # the yearly new-source turnover. It is not a replacement for that turnover.
      state =
        Enum.reduce(range(cycles), state, fn n, state ->
          state = cycle(state, n)
          state = if rem(n, 100) == 0, do: observe(state), else: state
          if rem(n, 100) == 0, do: checkpoint(opts[:output], state, days, n)
          if rem(n, 1000) == 0, do: IO.puts(:stderr, "storage development cycles #{n}")
          state
        end)

      state = if days == 365, do: migration_roundtrip(state, "final365"), else: state

      stats = status(state)
      samples = Enum.sort(state.samples)

      report = %{
        "kind" => "development_authored_storage_workload_v1",
        "days" => days,
        "cycles" => cycles,
        "payload" => payload,
        "granularity" => granularity,
        "driver_deadline_ms" => 7_200_000,
        "driver_elapsed_ms" => System.monotonic_time(:millisecond) - started,
        "provenance" => provenance,
        "retained_store" => location,
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
        "diagnostic_sampling" =>
          "status and selected get daily, every 100 cycles, terminal; native allocation every publication",
        "initial_note_count" => 2000,
        "initial_publications" => 16,
        "call_attempts_by_operation" => Process.get({__MODULE__, :calls}),
        "actual_read_calls" =>
          calls(
            ~w(status snapshot get scan export export.operations export.plan fresh_vm_snapshot)
          ),
        "actual_commit_calls" => calls(["commit"]),
        "actual_migration_calls" =>
          calls(
            ~w(import.open import.page import.operations import.commit import.abort rollback checkpoint.drop)
          ),
        "cycle_value_mode" => "small_generic_one_key_receipt_churn",
        "floor_policy" =>
          "advance on any existing-record replacement or deletion; pure additions preserve prior lineage",
        "ordinary_per_day" => 20,
        "corrections_per_day" => 4,
        "forgets_per_day" => 2,
        "temporal_supersessions_per_day" => 4,
        "delayed_temporal_first_update_day" => if(days >= 100, do: 100),
        "burst_day" => if(days >= 90, do: 90),
        "burst_multiplier" => 2,
        "persistent_initial" => %{"pins" => 100, "preferences" => 50, "current" => 50},
        "offline_days" => if(days >= 126, do: 7, else: 0),
        "offline_known_unstarted_actions" => state.queued_actions,
        "offline_actions_remaining" => length(state.offline_queue),
        "publication_samples" => length(samples),
        "publication_ms_p50" => percentile(samples, 0.50),
        "publication_ms_p95" => percentile(samples, 0.95),
        "publication_ms_max" => List.last(samples),
        "peak_accounted_disk_bytes" => state.peak,
        "peak_accounted_allocated_bytes" => state.peak_allocated,
        "maximum_post_publication_vm_memory_bytes" => state.peak_ram,
        "capture_pauses" => state.pauses,
        "checkpoints" => checkpoints,
        "migrations" => Enum.reverse(state.migrations),
        "qualification_passed" => false,
        "storage_publications_completed" => true,
        "required_migration_gate_passed" =>
          if(state.migrations != [],
            do: Enum.all?(state.migrations, &(&1["outcome"] == "passed"))
          ),
        "final" => stats,
        "runtime" => %{
          "elixir" => System.version(),
          "otp" => to_string(:erlang.system_info(:otp_release)),
          "schedulers" => System.schedulers_online(),
          "system" => inspect(:os.type()),
          "cpu" => cpu(),
          "memory" => host_memory()
        },
        "limits" =>
          "Fixtures exercise storage and pure retention; semantic quality, active Session integration, actual power loss and reference hardware remain separate gates. Managed allocated-file accounting includes a 22MiB control reservation. The reviewed native filesystem profile bounds new-file staging before payload under the actual transaction owner; this does not bound volume-wide journal/allocator overhead."
      }

      bytes = Jason.encode!(report, pretty: true)
      if opts[:output], do: File.write!(opts[:output], bytes <> "\n")
      IO.puts(bytes)
      report
    rescue
      exception ->
        failure = %{
          "kind" => "development_storage_driver_failure",
          "qualification_passed" => false,
          "error" => Exception.message(exception),
          "last_call" => Process.get({__MODULE__, :last_call}),
          "call_attempts_by_operation" => Process.get({__MODULE__, :calls}),
          "elapsed_ms" => System.monotonic_time(:millisecond) - started,
          "retained_store" => location,
          "automatic_retries" => 0
        }

        if opts[:output] do
          File.write(
            opts[:output] <> ".failure.json",
            Jason.encode!(failure, pretty: true) <> "\n"
          )
        end

        reraise exception, __STACKTRACE__
    after
      :telemetry.detach(telemetry_id)
      Process.unlink(monitor)
      Process.exit(monitor, :kill)
    end
  end

  def advance_day(state, desired, day, payload, granularity) do
    # An offline week accumulates work, then resumes by explicit bounded
    # batches. Nothing is inferred to have executed while offline.
    state =
      if day == 127 do
        resumed =
          if granularity == "individual" do
            Enum.reduce(Enum.reverse(state.offline_queue), state, fn action, state ->
              publish(state, apply_action(values(state), action))
            end)
          else
            publish(state, desired)
          end

        true = values(resumed) == desired
        %{resumed | offline_queue: []}
      else
        state
      end

    individual = granularity == "individual" and day not in 120..126

    {state, desired} =
      Enum.reduce(
        daily_actions(desired, day, payload, if(day == 90, do: 2, else: 1)),
        {state, desired},
        fn action, {state, desired} ->
          desired = apply_action(desired, action)

          state =
            cond do
              day in 120..126 ->
                true = length(state.offline_queue) < 217

                %{
                  state
                  | offline_queue: [action | state.offline_queue],
                    queued_actions: state.queued_actions + 1
                }

              individual ->
                publish(state, desired)

              true ->
                state
            end

          {state, desired}
        end
      )

    state = if day in 120..126 or individual, do: state, else: publish(state, desired)
    state = if day == 90, do: migration_roundtrip(state, "day90"), else: state
    state = if day in 120..126, do: state, else: observe(state)

    {state, desired}
  end

  def provenance(directory) do
    {:ok, helper} = Ipse.Runner.protected_helper(directory)

    sources =
      ~w(lib/ipse/extension/collection.ex lib/ipse/extension/collection/blocks.ex lib/ipse/extension/collection/migration.ex lib/ipse/extension/collection/encoding.ex lib/ipse/extension/collection/planning.ex native/ipse-storage-profile.rs extensions/knowledge/src/notes.ex dev/knowledge/storage_workload.exs dev/knowledge/storage_workload.ex dev/knowledge/storage_continuation.exs dev/knowledge/storage_annual.exs)

    %{
      "sources" => Map.new(sources, &{&1, Ipse.JSON.sha256(File.read!(&1))}),
      "native_helper_sha256" => Ipse.JSON.sha256(File.read!(helper)),
      "kernel" => inspect(:os.version()),
      "atomic_lock_owner_fencing" => "same native transaction owner; pending qualification"
    }
  end

  def filesystem(path) do
    # Provenance only. Native supported-filesystem bounds separately authorize
    # the preallocation allowance; these fields never grant quota admission.
    {text, 0} = System.cmd("stat", ["-f", "-c", "%T %S %s", path])
    [type, fragment, block] = String.split(text)

    {:ok, mountinfo} =
      File.open("/proc/self/mountinfo", [:read, :binary], &IO.binread(&1, 1_048_577))

    true = is_binary(mountinfo) and byte_size(mountinfo) <= 1_048_576

    selected =
      mountinfo
      |> String.split("\n", trim: true)
      |> Enum.flat_map(fn row ->
        case String.split(row, " - ", parts: 2) do
          [left, right] ->
            fields = String.split(left)
            [fs_type, _source | options] = String.split(right)

            point =
              Enum.at(fields, 4) |> String.replace("\\040", " ") |> String.replace("\\134", "\\")

            if path == point or String.starts_with?(path, String.trim_trailing(point, "/") <> "/") do
              [{byte_size(point), fs_type, Enum.at(fields, 5) <> "," <> Enum.join(options, ",")}]
            else
              []
            end

          _ ->
            []
        end
      end)
      |> Enum.max_by(&elem(&1, 0))

    {_, mount_type, options} = selected

    sanitized =
      options
      |> String.split(",")
      |> Enum.filter(
        &Regex.match?(
          ~r/\A(?:rw|ro|nodev|nosuid|noexec|relatime|noatime|ssd|usrquota|grpquota|prjquota|compress=[a-z0-9:]+|discard=[a-z]+|space_cache=[a-z0-9]+|huge=[a-z]+)\z/,
          &1
        )
      )
      |> Enum.uniq()
      |> Enum.sort()

    %{
      "type" => type,
      "mount_type" => mount_type,
      "fragment_size" => String.to_integer(fragment),
      "block_size" => String.to_integer(block),
      "mount_options" => sanitized,
      "measurement" => "Linux statfs reporting via stat; bounded selected mountinfo options"
    }
  end

  def seed(payload) do
    persistent =
      for n <- 1..200, into: %{} do
        category =
          cond do
            n <= 100 -> "pin"
            n <= 150 -> "preference"
            true -> "current"
          end

        note = note("persistent:#{n}", "seed:#{n}", category, @base, payload)
        {note["id"], note}
      end

    Enum.reduce(1..1800, persistent, fn n, rows ->
      created = @base - rem(n - 1, 90) * @day
      note = note("ordinary:#{n}", "seed:ordinary:#{n}", "ordinary", created, payload)
      Map.put(rows, note["id"], note)
    end)
  end

  def daily_actions(rows, day, payload, multiplier) do
    now = @base + day * @day

    expired =
      Enum.filter(rows, fn {_, row} ->
        Map.has_key?(row, "category") and not IpseKnowledge.Notes.eligible?(row, now)
      end)

    rows = Map.drop(rows, Enum.map(expired, &elem(&1, 0)))

    ordinary =
      rows
      |> Enum.filter(fn {_, r} -> r["category"] == "ordinary" end)
      |> Enum.sort_by(&elem(&1, 0))

    forgets =
      Enum.map(Enum.take(ordinary, 2 * multiplier), fn {key, r} ->
        {:ok, forgotten} = IpseKnowledge.Notes.forget(r, "development explicit forget", now)
        [{key, nil}, {"override-" <> r["lineage"], forgotten["override"]}]
      end)

    corrections =
      Enum.map(Enum.take(Enum.drop(ordinary, 2 * multiplier), 4 * multiplier), fn {key, old} ->
        replacement =
          note("correction:#{day}:#{key}", "correction:#{day}:#{key}", "ordinary", now, payload)
          |> Map.put("id", old["id"])

        attrs =
          Map.take(
            replacement,
            ~w(id lineage text evidence category reason observed_at_ms event_at_ms)
          )

        {:ok, result} = IpseKnowledge.Notes.supersede(old, attrs, now)
        [{key, result["current"]}, {history_key(old), result["history"]}]
      end)

    temporal =
      rows
      |> Enum.filter(fn {_, r} -> r["category"] == "current" end)
      |> Enum.sort_by(&elem(&1, 0))

    delayed_key = Ipse.JSON.sha256("persistent:200")

    available =
      if day < 100, do: Enum.reject(temporal, &(elem(&1, 0) == delayed_key)), else: temporal

    selected =
      for offset <- 0..(4 * multiplier - 1),
          do: Enum.at(available, rem(day * 4 + offset, length(available)))

    selected =
      if day == 100 do
        delayed = Enum.find(temporal, &(elem(&1, 0) == delayed_key))
        true = elem(delayed, 1)["created_at_ms"] == @base
        [delayed | Enum.take(Enum.reject(selected, &(elem(&1, 0) == delayed_key)), 3)]
      else
        selected
      end

    temporals =
      Enum.map(selected, fn {key, old} ->
        replacement =
          note("temporal:#{day}:#{key}", "temporal:#{day}:#{key}", "current", now, payload)
          |> Map.put("id", old["id"])

        attrs =
          Map.take(
            replacement,
            ~w(id lineage text evidence category reason observed_at_ms event_at_ms)
          )

        {:ok, result} = IpseKnowledge.Notes.supersede(old, attrs, now)
        [{key, result["current"]}, {history_key(old), result["history"]}]
      end)

    intake =
      Enum.map(1..(20 * multiplier), fn n ->
        note = note("intake:#{day}:#{n}", "source:#{day}:#{n}", "ordinary", now, payload)
        [{note["id"], note}]
      end)

    [Enum.map(expired, fn {key, _} -> {key, nil} end)] ++
      forgets ++ corrections ++ temporals ++ intake
  end

  defp history_key(note),
    do: "history-" <> Ipse.JSON.digest([note["id"], note["lineage"], note["created_at_ms"]])

  defp note(id, source, category, now, payload) do
    attrs = %{
      "id" => Ipse.JSON.sha256(id),
      "lineage" => Ipse.JSON.sha256(source),
      "text" => "Development observation #{id}",
      "evidence" => %{
        "source" => source,
        "quote" => "Independent development support #{source}",
        "padding" => ""
      },
      "category" => category,
      "reason" => "development admitted direct observation",
      "observed_at_ms" => now,
      "event_at_ms" => nil
    }

    {:ok, note} = IpseKnowledge.Notes.new(attrs, now)

    if payload == "maximum" do
      # The domain's counted metadata reservation keeps a maximum current value
      # correctable without discarding any admitted text or evidence bytes.
      pad = 6144 - byte_size(Jason.encode!(note))
      note = put_in(note, ["evidence", "padding"], varied_padding(id, pad))
      true = IpseKnowledge.Notes.valid?(note)
      note
    else
      note
    end
  end

  defp varied_padding(seed, count) do
    pieces =
      for n <- 0..div(count + 42, 43),
          do:
            Base.encode64(:crypto.hash(:sha256, seed <> ":" <> Integer.to_string(n)),
              padding: false
            )

    pieces |> IO.iodata_to_binary() |> binary_part(0, count)
  end

  def publish(state, desired) do
    current = values(state)
    keys = (Map.keys(current) ++ Map.keys(desired)) |> Enum.uniq() |> Enum.sort()

    changes =
      for key <- keys, current[key] != desired[key] do
        %{
          "key" => key,
          "expected_revision" => if(state.rows[key], do: state.rows[key]["revision"], else: 0),
          "value" => desired[key]
        }
      end

    Enum.reduce(Enum.chunk_every(changes, 128), state, fn changes, state ->
      request = %{
        "op" => "commit",
        "expected_generation" => state.generation,
        "advance_floor" =>
          Enum.any?(changes, &(Map.has_key?(state.rows, &1["key"]) or is_nil(&1["value"]))),
        "changes" => changes
      }

      started = System.monotonic_time(:microsecond)
      result = execute(state.root, state.project, request, Ipse.Usage.id())
      ms = (System.monotonic_time(:microsecond) - started) / 1000

      case result do
        {:ok, receipt} ->
          rows =
            Enum.reduce(changes, state.rows, fn c, rows ->
              if c["value"],
                do:
                  Map.put(rows, c["key"], %{
                    "revision" => receipt["generation"],
                    "value" => c["value"]
                  }),
                else: Map.delete(rows, c["key"])
            end)

          next = %{
            state
            | generation: receipt["generation"],
              rows: rows,
              samples: [ms | state.samples]
          }

          allocation = allocation(receipt["generation"])

          %{
            next
            | peak_allocated: max(state.peak_allocated, allocation),
              peak_ram: max(state.peak_ram, :erlang.memory(:total))
          }

        other ->
          raise "storage publication failed after #{state.generation}: #{inspect(other)}"
      end
    end)
  end

  def allocation_event(_, measurements, metadata, driver),
    do:
      send(
        driver,
        {:storage_allocation, metadata.generation,
         measurements.accounted_allocated_bytes + measurements.root_publication_reserved_bytes}
      )

  defp allocation(generation) do
    receive do
      {:storage_allocation, ^generation, bytes} -> bytes
    after
      0 -> raise "missing staged allocation measurement"
    end
  end

  def cycle(state, n) do
    value = cycle_value(n)

    revision = if state.rows["cycle"], do: state.rows["cycle"]["revision"], else: 0
    changes = [%{"key" => "cycle", "expected_revision" => revision, "value" => value}]

    request = %{
      "op" => "commit",
      "expected_generation" => state.generation,
      "advance_floor" => Map.has_key?(state.rows, "cycle") or is_nil(value),
      "changes" => changes
    }

    started = System.monotonic_time(:microsecond)
    result = execute(state.root, state.project, request, Ipse.Usage.id())
    ms = (System.monotonic_time(:microsecond) - started) / 1000

    case result do
      {:ok, receipt} ->
        rows =
          if value,
            do:
              Map.put(state.rows, "cycle", %{
                "revision" => receipt["generation"],
                "value" => value
              }),
            else: Map.delete(state.rows, "cycle")

        peak = max(state.peak_allocated, allocation(receipt["generation"]))

        %{
          state
          | generation: receipt["generation"],
            rows: rows,
            samples: [ms | state.samples],
            peak_allocated: peak,
            peak_ram: max(state.peak_ram, :erlang.memory(:total))
        }

      other ->
        raise "cycle #{n} publication failed: #{inspect(other)}"
    end
  end

  def cycle_value(n) do
    if rem(n, 5) == 0 do
      nil
    else
      %{"text" => "development correction #{n}", "evidence" => %{"source" => "cycle:#{n}"}}
    end
  end

  def migration_roundtrip(state, label) do
    started = System.monotonic_time(:millisecond)
    {descriptor, records, record_reads} = export_pages(state, "export", "records", 32)
    plan_started = System.monotonic_time(:microsecond)

    {:ok, %{"descriptor" => ^descriptor, "plan" => plan}} =
      execute(
        state.root,
        state.project,
        %{"op" => "export.plan", "generation" => state.generation},
        Ipse.Usage.id()
      )

    plan_ms = (System.monotonic_time(:microsecond) - plan_started) / 1000

    case migration_open(state, descriptor, plan, label, started) do
      {:opened, state, opened} ->
        complete_migration(
          state,
          opened,
          label,
          started,
          descriptor,
          records,
          descriptor["operations"],
          record_reads ++ [plan_ms]
        )

      {:refused, state} ->
        state
    end
  end

  defp migration_open(state, descriptor, plan, label, started) do
    write_started = System.monotonic_time(:microsecond)

    result =
      execute(
        state.root,
        state.project,
        %{
          "op" => "import.open",
          "expected_generation" => state.generation,
          "descriptor" => descriptor,
          "plan" => plan
        },
        Ipse.Usage.id()
      )

    case result do
      {:ok, receipt} ->
        {state, receipt} = record_migration_write(state, receipt, write_started)
        {:opened, state, receipt}

      {:failed, %{"code" => "collection_capacity"} = failure} ->
        inspected = status(state)

        true =
          inspected["generation"] == state.generation and
            inspected["floor"] == descriptor["floor"]

        true = is_nil(inspected["migration"]) and is_nil(inspected["checkpoint"])
        true = inspected["operations"] == descriptor["operations"]

        measurement = %{
          "label" => label,
          "outcome" => "failed",
          "failure" => failure,
          "descriptor" => descriptor,
          "source_unchanged" => true,
          "duration_ms" => System.monotonic_time(:millisecond) - started,
          "retry_attempts" => 0
        }

        IO.puts(
          :stderr,
          "storage development migration #{label} FAILED: collection_capacity; unchanged source inspected"
        )

        {:refused, %{state | migrations: [measurement | state.migrations]}}

      other ->
        raise "migration open has unconfirmed or unexpected outcome: #{inspect(other)}"
    end
  end

  defp complete_migration(state, opened, label, started, descriptor, records, operations, reads) do
    id = opened["migration_id"]

    {state, _, rows} =
      Enum.reduce(Enum.chunk_every(records, 32), {state, nil, %{}}, fn chunk,
                                                                       {state, after_key, rows} ->
        {state, receipt} =
          migration_write(state, %{
            "op" => "import.page",
            "expected_generation" => state.generation,
            "migration_id" => id,
            "after" => after_key,
            "records" => Enum.map(chunk, &Map.take(&1, ~w(key value)))
          })

        rows =
          Enum.reduce(chunk, rows, fn record, rows ->
            Map.put(rows, record["key"], %{
              "revision" => receipt["generation"],
              "value" => record["value"]
            })
          end)

        {state, List.last(chunk)["key"], rows}
      end)

    {state, committed} =
      migration_write(state, %{
        "op" => "import.commit",
        "expected_generation" => state.generation,
        "migration_id" => id
      })

    true = is_binary(committed["checkpoint_id"])
    state = %{state | rows: rows}

    {state, _} =
      migration_write(state, %{
        "op" => "checkpoint.drop",
        "expected_generation" => state.generation
      })

    restart_read(state)
    reads = Enum.sort(reads)

    measurement = %{
      "label" => label,
      "outcome" => "passed",
      "descriptor" => descriptor,
      "duration_ms" => System.monotonic_time(:millisecond) - started,
      "export_page_samples" => length(reads),
      "export_page_ms_p95" => percentile(reads, 0.95),
      "records" => length(records),
      "operations" => operations,
      "checkpoint_dropped" => true
    }

    %{state | migrations: [measurement | state.migrations]}
  end

  def export_pages(state, operation, field, limit) do
    result =
      Enum.reduce_while(1..256, {nil, nil, [], []}, fn _, {after_key, descriptor, pages, reads} ->
        started = System.monotonic_time(:microsecond)

        {:ok, page} =
          execute(
            state.root,
            state.project,
            %{
              "op" => operation,
              "generation" => state.generation,
              "after" => after_key,
              "limit" => limit
            },
            Ipse.Usage.id()
          )

        ms = (System.monotonic_time(:microsecond) - started) / 1000
        true = is_nil(descriptor) or descriptor == page["descriptor"]
        next = {page["next"], page["descriptor"], [page[field] | pages], [ms | reads]}
        if is_nil(page["next"]), do: {:halt, {:complete, next}}, else: {:cont, next}
      end)

    {:complete, {nil, descriptor, pages, reads}} = result
    {descriptor, pages |> Enum.reverse() |> List.flatten(), reads}
  end

  defp migration_write(state, request) do
    started = System.monotonic_time(:microsecond)
    {:ok, receipt} = execute(state.root, state.project, request, Ipse.Usage.id())
    record_migration_write(state, receipt, started)
  end

  defp record_migration_write(state, receipt, started) do
    ms = (System.monotonic_time(:microsecond) - started) / 1000
    allocated = allocation(receipt["generation"])
    next = %{state | generation: receipt["generation"], samples: [ms | state.samples]}

    {%{
       next
       | peak_allocated: max(state.peak_allocated, allocated),
         peak_ram: max(state.peak_ram, :erlang.memory(:total))
     }, receipt}
  end

  defp checkpoint(nil, _, _, _), do: :ok

  defp checkpoint(path, state, day, cycles) do
    samples = Enum.sort(state.samples)

    report = %{
      "kind" => "development_storage_partial",
      "qualification_passed" => false,
      "completed_days" => day,
      "completed_cycles" => cycles,
      "generation" => state.generation,
      "records" => map_size(state.rows),
      "publication_samples" => length(samples),
      "publication_ms_p95" => percentile(samples, 0.95),
      "peak_accounted_allocated_bytes" => state.peak_allocated,
      "maximum_post_publication_vm_memory_bytes" => state.peak_ram
    }

    File.write!(path <> ".partial.json", Jason.encode!(report, pretty: true) <> "\n")
  end

  def status(state) do
    {:ok, status} = execute(state.root, state.project, %{"op" => "status"}, Ipse.Usage.id())
    status
  end

  def observe(state) do
    stats = status(state)
    true = stats["generation"] == state.generation
    true = stats["records"] == map_size(state.rows)
    {key, expected} = Enum.min_by(state.rows, &elem(&1, 0))

    {:ok, found} =
      execute(state.root, state.project, %{"op" => "get", "key" => key}, Ipse.Usage.id())

    true = Map.take(found["record"], ~w(value revision)) == expected
    %{state | peak: max(state.peak, stats["accounted_total_bytes"])}
  end

  def apply_action(rows, action) do
    Enum.reduce(action, rows, fn
      {key, nil}, rows -> Map.delete(rows, key)
      {key, value}, rows -> Map.put(rows, key, value)
    end)
  end

  def values(state), do: Map.new(state.rows, fn {key, r} -> {key, r["value"]} end)
  defp range(0), do: []
  defp range(n), do: 1..n
  def percentile([], _), do: nil
  def percentile(samples, q), do: Enum.at(samples, max(ceil(length(samples) * q) - 1, 0))

  def restart_read(state) do
    count_call("fresh_vm_snapshot")

    code =
      "[root,project]=System.argv(); {:ok,_}=Application.ensure_all_started(:ipse); {:ok,s}=Ipse.Extension.Collection.execute(root,project,%{\"op\"=>\"snapshot\"},Ipse.Usage.id()); IO.puts(s[\"generation\"])"

    paths =
      :code.get_path()
      |> Enum.reject(&(&1 == ~c"."))
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", List.to_string(&1)])

    {output, 0} =
      System.cmd(
        System.find_executable("elixir"),
        paths ++ ["-e", code, "--", state.root, state.project],
        env: [{"ERL_FLAGS", "+S 2:2"}]
      )

    true = String.trim(output) == to_string(state.generation)
  end

  def execute(root, project, request, id) do
    count_call(request["op"])

    call = %{
      "operation" => request["op"],
      "operation_id" => id,
      "request_sha256" => Ipse.JSON.digest([request]),
      "expected_generation" => request["expected_generation"] || request["generation"]
    }

    Process.put({__MODULE__, :last_call}, call)
    if monitor = Process.get({__MODULE__, :monitor}), do: send(monitor, {:call, call})

    C.execute(root, project, request, id)
  end

  defp count_call(operation) do
    calls = Process.get({__MODULE__, :calls}, %{})
    Process.put({__MODULE__, :calls}, Map.update(calls, operation, 1, &(&1 + 1)))
    :ok
  end

  defp calls(operations) do
    counts = Process.get({__MODULE__, :calls}, %{})
    Enum.sum(Enum.map(operations, &Map.get(counts, &1, 0)))
  end

  defp cpu do
    case File.read("/proc/cpuinfo") do
      {:ok, bytes} ->
        bytes |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "model name"))

      _ ->
        "unavailable"
    end
  end

  defp host_memory do
    case File.read("/proc/meminfo") do
      {:ok, bytes} ->
        bytes |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "MemTotal"))

      _ ->
        "unavailable"
    end
  end

  def resource_guard(driver, started, output \\ nil, last_call \\ nil) do
    elapsed = System.monotonic_time(:millisecond) - started
    memory = :erlang.memory(:total)

    if memory > 512 * 1024 * 1024 or elapsed > 7_200_000 do
      # Diagnostic IO cannot postpone the untrappable stop. Its small receipt is
      # best effort; the retained store and periodic partial report remain.
      spawn(fn ->
        Process.sleep(10)
        Process.exit(driver, :kill)
      end)

      if is_binary(output) do
        receipt = %{
          "kind" => "development_driver_resource_failure",
          "qualification_passed" => false,
          "observed_vm_memory_bytes" => memory,
          "elapsed_ms" => elapsed,
          "memory_guard_bytes" => 512 * 1024 * 1024,
          "last_call" => last_call,
          "deadline_ms" => 7_200_000
        }

        File.write(
          output <> ".resource-failure.json",
          Jason.encode!(receipt, pretty: true) <> "\n"
        )
      end

      Process.exit(driver, :kill)
    else
      receive do
        {:output, path} -> resource_guard(driver, started, path, last_call)
        {:call, call} -> resource_guard(driver, started, output, call)
      after
        100 -> resource_guard(driver, started, output, last_call)
      end
    end
  end
end
