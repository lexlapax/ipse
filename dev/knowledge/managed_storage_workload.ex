for name <- ~w(notes.ex knowledge/records.ex knowledge/contracts.ex) do
  Code.require_file(Path.expand("../../extensions/knowledge/src/" <> name, __DIR__))
end

defmodule Ipse.Development.ManagedStorageWorkload do
  @moduledoc false
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.Collection
  alias Ipse.Extension.Collection.Normalizer
  alias Ipse.Session.{Input, SourceIndex, ToolLifecycle}
  alias IpseKnowledge.Knowledge.{Contracts, Records}
  @memory 512 * 1024 * 1024
  @hard_ms 480_000
  @soft_ms 360_000
  @now 1_800_000_000_000

  def limits, do: %{publications: 1000, hard_ms: @hard_ms, soft_ms: @soft_ms, memory: @memory}

  def fixture(number, category \\ "ordinary") when number in 1..4000 do
    text = varied(number, 1024)
    {:ok, index} = SourceIndex.new(Usage.id())

    # A trusted test builder supplies a synthetic observation. SourceIndex checks
    # its schema and authenticates later handles; no terminal or human is attested.
    observation = %{
      "version" => 1,
      "event_id" => Usage.id(),
      "display_sha256" => JSON.sha256("development synthetic rendering"),
      "text_sha256" => JSON.sha256(text)
    }

    input = Input.received(index.session_id, Usage.id(), text, text, observation)
    message = %{"type" => "message", "message" => %{"role" => "user", "content" => text}}
    {:ok, index} = SourceIndex.admit_input(index, input, message)
    {:ok, %{"sources" => [row]}} = SourceIndex.list(index, %{"limit" => 1})
    resolve(index, row, varied(number + 4000, 256), category)
  end

  def typed_fixture do
    {:ok, index} = SourceIndex.new(Usage.id())

    call = %{
      "id" => "fixture-call",
      "type" => "function",
      "function" => %{"name" => "read", "arguments" => "{\"path\":\"synthetic-not-executed\"}"}
    }

    proposal = %{
      "type" => "message",
      "request_id" => Usage.id(),
      "message" => %{"role" => "assistant", "content" => "", "tool_calls" => [call]}
    }

    {:ok, proposal_source} = Ipse.Journal.source(index.session_id, 0, proposal)

    context = %{
      session: index.session_id,
      epoch: Usage.id(),
      count: 0,
      recording: true,
      proposal: nil,
      active: nil
    }

    {context, []} = ToolLifecycle.proposal(context, proposal_source, proposal, Usage.id())
    started = %{"type" => "tool_started", "approval" => "not_required"}
    {:ok, intent_source} = Ipse.Journal.source(index.session_id, 100, started)
    {context, [intent]} = ToolLifecycle.start(context, intent_source, started, call, 1)
    {:ok, tool_source} = Ipse.Journal.source(index.session_id, 200, intent)
    context = ToolLifecycle.bind(context, tool_source, intent)

    message = %{
      "type" => "message",
      "message" => %{
        "role" => "tool",
        "content" => "synthetic tool fixture; no file was read",
        "ipse_tool_outcome" => %{"status" => "result_recorded", "approval" => "not_required"}
      }
    }

    {:ok, result_source} = Ipse.Journal.source(index.session_id, 300, message)
    {_, [outcome]} = ToolLifecycle.finish(context, result_source, message)
    {:ok, index} = SourceIndex.admit_tool(index, intent, outcome, message)
    {:ok, %{"sources" => rows}} = SourceIndex.list(index, %{"limit" => 2})
    row = Enum.find(rows, &(&1["kind"] == "tool.outcome"))
    resolve(index, row, "synthetic typed-outcome positive control", "ordinary")
  end

  defp resolve(index, row, reason, category) do
    {:ok, page} = SourceIndex.read(index, %{"handle" => row["read_handle"]})
    text = page["text"]
    request = %{"handle" => page["handle"], "quote" => text}
    {:ok, _} = SourceIndex.quote(index, request)
    {:ok, %{"proof" => proof}} = SourceIndex.resolve_proof(index, request)

    {:ok, key, value} =
      Records.capture(
        %{
          "text" => text,
          "category" => category,
          "reason" => reason,
          "event_at_ms" => nil
        },
        proof,
        @now
      )

    %{index: index, proof_request: request, proof: proof, key: key, value: value}
  end

  def options(fixture, generation, now \\ @now) do
    contracts = Contracts.operator()

    %{
      request: %{
        "op" => "commit",
        "expected_generation" => generation,
        "advance_floor" => true,
        "changes" => [%{"key" => fixture.key, "expected_revision" => 0, "value" => fixture.value}]
      },
      recipe: contracts["recipes"]["note"],
      constraints: contracts["publication"]["note"],
      verified_sources: [fixture.proof],
      policy_sha256: JSON.sha256("synthetic managed workload reviewed policy fixture"),
      now_ms: now
    }
  end

  def run(args) do
    {opts, [], []} =
      OptionParser.parse(args,
        strict: [
          count: :integer,
          target: :integer,
          parent: :string,
          output: :string,
          mode: :string
        ]
      )

    count = opts[:count] || 1000
    target = opts[:target] || 2000
    mode = opts[:mode] || "operator"
    true = count in 1..1000 and target in [2000, 4000] and is_binary(opts[:output])
    true = mode in ~w(operator typed_outcome) and (mode != "typed_outcome" or count == 1)
    Process.put({__MODULE__, :mode}, mode)
    Process.flag(:max_heap_size, %{size: 16_000_000, kill: true, error_logger: true})
    started = System.monotonic_time(:millisecond)
    driver = self()
    monitor = spawn_link(fn -> guard(driver, started, opts[:output]) end)
    telemetry = "managed-storage-" <> Usage.id()

    :ok =
      :telemetry.attach(
        telemetry,
        [:ipse, :extension, :collection, :staged],
        fn _, m, meta, _ ->
          send(
            driver,
            {:allocation, meta.generation,
             m.accounted_allocated_bytes + m.root_publication_reserved_bytes}
          )
        end,
        nil
      )

    try do
      parent =
        Path.join(
          Path.expand(opts[:parent] || "_build/storage-workloads"),
          "ipse-managed-" <> Usage.id()
        )

      File.mkdir!(parent)
      File.chmod!(parent, 0o700)
      root = Path.join(parent, "collections")
      project = JSON.sha256("development managed storage capacity fixture v1")
      Process.put({__MODULE__, :location}, %{root: root, project: project})
      provenance = provenance(parent)

      File.write!(
        opts[:output] <> ".runtime.json",
        Jason.encode!(provenance, pretty: true) <> "\n"
      )

      Process.put({__MODULE__, :runtime}, JSON.digest([provenance]))

      state = %{
        generation: 0,
        successful: 0,
        attempted: 0,
        peak: 0,
        peak_beam: :erlang.memory(:total),
        samples: [],
        records: %{},
        metadata: %{},
        status: nil
      }

      {state, reason} =
        Enum.reduce_while(1..count, {state, "run_limit"}, fn number, {state, _} ->
          if System.monotonic_time(:millisecond) - started >= @soft_ms do
            {:halt, {state, "soft_boundary"}}
          else
            candidate = if mode == "operator", do: fixture(number), else: typed_fixture()
            options = options(candidate, state.generation)
            id = Usage.id()
            Process.put({__MODULE__, :last_call}, %{operation_id: id, request: options.request})
            call_started = System.monotonic_time(:microsecond)

            result =
              Collection.execute_managed(
                root,
                project,
                options.request,
                id,
                JSON.digest([options.recipe]),
                fn witness, read ->
                  {:ok, %{"proof" => current}} =
                    SourceIndex.resolve_proof(candidate.index, candidate.proof_request)

                  true = current == candidate.proof
                  Normalizer.normalize(witness, read, options)
                end
              )

            elapsed = (System.monotonic_time(:microsecond) - call_started) / 1000
            state = %{state | attempted: state.attempted + 1}

            case result do
              {:ok, %{"receipt" => receipt, "normalization" => normalization}} ->
                generation = receipt["generation"]
                true = generation == state.generation + 1

                allocation =
                  receive do
                    {:allocation, ^generation, bytes} -> bytes
                  after
                    0 -> raise "missing every-publication native allocation observation"
                  end

                state = %{
                  state
                  | generation: generation,
                    successful: state.successful + 1,
                    peak: max(state.peak, allocation),
                    peak_beam: max(state.peak_beam, :erlang.memory(:total)),
                    samples: [elapsed | state.samples],
                    records:
                      Map.put(state.records, candidate.key, %{
                        value: candidate.value,
                        revision: generation,
                        normalization: normalization
                      }),
                    metadata:
                      Enum.reduce(~w(anchor live), state.metadata, fn kind, all ->
                        Map.put(all, normalization[kind <> "_key"], %{
                          sha256: normalization[kind <> "_value_sha256"],
                          revision: generation
                        })
                      end)
                }

                state = if rem(number, 100) == 0, do: status(state, root, project), else: state
                save_partial(opts[:output], state, started)
                {:cont, {state, "run_limit"}}

              other ->
                Process.put(
                  {__MODULE__, :refusal},
                  inspect(other, limit: 50, printable_limit: 2048)
                )

                {:halt, {state, "first_publication_refusal_or_unknown"}}
            end
          end
        end)

      state = status(state, root, project)
      verification = verify(state, root, project)

      report =
        Map.put(report(state, target, reason, started), :terminal_verification, verification)

      File.write!(opts[:output], Jason.encode!(report, pretty: true) <> "\n")
      IO.puts(Jason.encode!(report, pretty: true))
      report
    rescue
      error ->
        failure = %{
          qualification_passed: false,
          error: Exception.message(error),
          last_call: Process.get({__MODULE__, :last_call}),
          location: Process.get({__MODULE__, :location}),
          automatic_retries: 0
        }

        File.write(opts[:output] <> ".failure.json", Jason.encode!(failure, pretty: true) <> "\n")
        reraise error, __STACKTRACE__
    after
      :telemetry.detach(telemetry)
      Process.unlink(monitor)
      Process.exit(monitor, :kill)
    end
  end

  defp status(state, root, project) do
    {:ok, status} = Collection.execute(root, project, %{"op" => "status"}, Usage.id())
    true = status["generation"] == state.generation
    %{state | status: status}
  end

  defp verify(state, root, project) do
    records = scan(root, project, state.generation, nil, %{}, 0)
    true = map_size(records) == map_size(state.records) + map_size(state.metadata)

    Enum.each(state.records, fn {key, expected} ->
      actual = Map.fetch!(records, key)
      true = actual["value"] == expected.value and actual["revision"] == expected.revision
    end)

    Enum.each(state.metadata, fn {key, expected} ->
      actual = Map.fetch!(records, key)
      true = actual["sha256"] == expected.sha256 and actual["revision"] == expected.revision
    end)

    Enum.reduce(records, %{}, fn {key, record}, totals ->
      true =
        JSON.sha256(Ipse.Extension.Collection.Migration.encode(record["value"])) ==
          record["sha256"]

      class =
        cond do
          String.starts_with?(key, "host.validity.anchor.") -> "anchor"
          String.starts_with?(key, "host.validity.live.") -> "live"
          String.starts_with?(key, "note.") -> "note"
        end

      Map.update(totals, class, %{"records" => 1, "bytes" => record["bytes"]}, fn t ->
        %{"records" => t["records"] + 1, "bytes" => t["bytes"] + record["bytes"]}
      end)
    end)
  end

  defp scan(root, project, generation, cursor, records, pages) when pages < 256 do
    {:ok, result} =
      Collection.execute(
        root,
        project,
        %{"op" => "scan", "generation" => generation, "after" => cursor, "limit" => 32},
        Usage.id()
      )

    records =
      Enum.reduce(result["records"], records, fn r, acc ->
        false = Map.has_key?(acc, r["key"])
        Map.put(acc, r["key"], r)
      end)

    if result["next"],
      do: scan(root, project, generation, result["next"], records, pages + 1),
      else: records
  end

  defp provenance(workspace) do
    {:ok, helper} = Ipse.Runner.protected_helper(workspace)

    source_files =
      Path.wildcard("lib/**/*.ex") ++
        ~w(dev/knowledge/managed_storage_workload.exs dev/knowledge/managed_storage_workload.ex extensions/knowledge/src/notes.ex extensions/knowledge/src/knowledge/records.ex extensions/knowledge/src/knowledge/contracts.ex)

    library =
      :code.which(Collection)
      |> List.to_string()
      |> Path.dirname()
      |> Path.dirname()
      |> Path.dirname()

    beam_files =
      Path.wildcard(Path.join([library, "*", "ebin", "*.beam"])) ++
        Path.wildcard(Path.join([library, "*", "consolidated", "*.beam"]))

    true = length(source_files) <= 256 and length(beam_files) in 1..8192
    hash = fn files -> Map.new(Enum.sort(files), &{&1, JSON.sha256(File.read!(&1))}) end

    %{
      "sources" => hash.(source_files),
      "beams" => hash.(beam_files),
      "helper_sha256" => JSON.sha256(File.read!(helper)),
      "elixir" => System.version(),
      "erts" => to_string(:erlang.system_info(:system_version)),
      "kernel" => inspect(:os.version()),
      "synthetic_only" => true
    }
  end

  defp save_partial(output, state, started) do
    File.write!(
      output <> ".partial.json",
      Jason.encode!(%{
        generation: state.generation,
        successful_publications: state.successful,
        managed_allocated_peak_bytes: state.peak,
        elapsed_ms: System.monotonic_time(:millisecond) - started,
        qualification_passed: false
      })
    )
  end

  defp report(state, target, reason, started) do
    %{
      kind: "development_managed_storage_bounded_capacity",
      qualification_passed: false,
      capacity_target: target,
      capacity_target_completed: state.successful >= target,
      stop_reason: reason,
      successful_publications: state.successful,
      attempted_publications: state.attempted,
      location: Process.get({__MODULE__, :location}),
      status: state.status,
      runtime_binding_sha256: Process.get({__MODULE__, :runtime}),
      native_managed_allocated_peak_bytes: state.peak,
      maximum_post_publication_beam_memory_bytes: state.peak_beam,
      elapsed_ms: System.monotonic_time(:millisecond) - started,
      publication_ms: Enum.reverse(state.samples),
      performance_qualified: false,
      timing_scope:
        "actual managed publication callback only; synthetic source construction and diagnostics separate",
      automatic_retries: 0,
      continuation_supported: false,
      last_call: Process.get({__MODULE__, :last_call}),
      refusal: Process.get({__MODULE__, :refusal}),
      fixture_mode: Process.get({__MODULE__, :mode}),
      synthetic_operator_observation: Process.get({__MODULE__, :mode}) == "operator",
      synthetic_tool_outcome: Process.get({__MODULE__, :mode}) == "typed_outcome",
      actual_tool_execution: false,
      host_source_index_resolution_exercised: true,
      actual_human_input: false,
      native_terminal_attestation: false,
      session_pipeline_exercised: false,
      consent_exercised: false,
      model_calls: 0,
      persistent_pin_journey: false,
      correction_journey: false,
      forget_journey: false,
      expiry_maintenance_journey: false,
      domain_annual_qualified: false,
      normalizer_limits: Normalizer.limits(),
      storage_limits: Collection.limits()
    }
  end

  defp guard(driver, started, output) do
    elapsed = System.monotonic_time(:millisecond) - started
    memory = :erlang.memory(:total)

    if elapsed >= @hard_ms or memory > @memory do
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
          deadline_ms: @hard_ms,
          memory_limit_bytes: @memory
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

  defp varied(number, length) do
    Enum.map_join(1..div(length + 63, 64), &JSON.sha256("managed development #{number}/#{&1}"))
    |> binary_part(0, length)
  end
end
