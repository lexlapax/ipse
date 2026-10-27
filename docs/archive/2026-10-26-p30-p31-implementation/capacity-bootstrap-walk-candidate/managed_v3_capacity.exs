# Bounded author capacity probe. The actual publication/read-back implementation
# is source-derived from the owning integration test, never a simulated C seam.
defmodule Ipse.Development.ManagedV3Capacity.NativeFrames do
  @moduledoc false
  # Runner's reusable API owns the protected process group. Its other decoders
  # are private or coupled to worker/MCP messages, so this adapter handles only
  # the documented bounded native O/S/X/E transport, without a second launcher.
  def new, do: %{buffer: <<>>, traffic: 0, bytes: 0, terminal: nil}

  def push(state, data) when is_binary(data) do
    true = state.traffic + byte_size(data) <= 8 * 1024 * 1024
    parse(%{state | buffer: state.buffer <> data, traffic: state.traffic + byte_size(data)}, [])
  end

  defp parse(%{buffer: <<>>} = state, chunks), do: {state, Enum.reverse(chunks)}

  defp parse(%{terminal: terminal}, _) when terminal != nil,
    do: raise("native bytes after terminal result")

  defp parse(%{buffer: <<kind, size::unsigned-big-32, rest::binary>>} = state, chunks) do
    true = size <= 8192

    if byte_size(rest) < size do
      {state, Enum.reverse(chunks)}
    else
      <<payload::binary-size(^size), tail::binary>> = rest
      state = %{state | buffer: tail}

      case kind do
        kind when kind in [?O, ?S] ->
          true = state.bytes + size <= 4 * 1024 * 1024
          parse(%{state | bytes: state.bytes + size}, [payload | chunks])

        ?X ->
          {:ok, %{"exit_code" => code, "timed_out" => timeout} = result} =
            Ipse.JSON.decode_unique(payload, 2)

          true =
            map_size(result) == 2 and is_integer(code) and code in 0..255 and is_boolean(timeout)

          parse(
            %{state | terminal: %{exit_code: code, timed_out: timeout, output_truncated: false}},
            chunks
          )

        _ ->
          raise "native supervisor refused or sent an unsupported frame"
      end
    end
  end

  defp parse(state, chunks), do: {state, Enum.reverse(chunks)}

  def finish!(%{buffer: <<>>, terminal: %{exit_code: 0, timed_out: false}}), do: :ok
  def finish!(_), do: raise("native process result is incomplete or unsuccessful")
end

defmodule Ipse.Development.ManagedV3Capacity do
  alias Ipse.Extension.{Collection, ProjectIdentity}
  alias Ipse.Extension.Collection.{Migration, ManagedPages, NormalizerV3}
  alias IpseKnowledge.Knowledge.{Contracts, Records}
  alias Ipse.Runner.Transaction
  alias Ipse.JSON
  alias __MODULE__.NativeFrames
  @now 1_800_000_000_000
  @controls [201, 1201, 2201, 3201]
  @max 4000
  @soft 360_000
  @hard 480_000
  @memory 536_870_912
  @helper_sha256 "d84d77d77dc2393b36d9353b6e6d215ec86dc5ba33fe9ad7c8f378130043f91b"

  # These facts describe a bounded initial-addition control, not the annual
  # lifecycle workload or evidence that a represented source is authenticated.
  def limits do
    %{
      "publications" => @max,
      "segment_size" => 500,
      "segments" => 8,
      "soft_ms" => @soft,
      "hard_ms" => @hard,
      "beam_memory_limit" => @memory,
      "max_heap_words" => 16_000_000,
      "turnover_implemented" => false
    }
  end

  def helper_sha256, do: @helper_sha256

  def check_helper_sha256!(sha) do
    true = sha === @helper_sha256
    :ok
  end

  def check_configuration!(nil), do: :ok

  def check_configuration!(_),
    do: raise("capacity qualification refuses IPSE_RUNNER_PATH overrides")

  def directory_identity!(path) do
    true = is_binary(path) and Path.type(path) == :absolute and Path.expand(path) == path

    %{type: :directory} = File.lstat!("/")

    Enum.reduce(tl(Path.split(path)), "/", fn part, current ->
      next = Path.join(current, part)
      %{type: :directory} = File.lstat!(next)
      next
    end)

    stat = File.lstat!(path)

    %{
      "uid" => stat.uid,
      "gid" => stat.gid,
      "inode" => stat.inode,
      "major_device" => stat.major_device,
      "minor_device" => stat.minor_device
    }
  end

  def location!(graph, store, state) when state in [:new, :existing, :either] do
    graph_identity = directory_identity!(graph)
    true = Bitwise.band(File.lstat!(graph).mode, 0o077) == 0
    true = Path.type(store) == :absolute and Path.expand(store) == store
    parent = Path.dirname(store)

    true =
      Path.basename(parent) == "storage-workloads" and
        Path.basename(Path.dirname(parent)) == "_build"

    parent_identity = directory_identity!(parent)
    true = parent_identity["uid"] == graph_identity["uid"]
    true = Bitwise.band(File.lstat!(parent).mode, 0o022) == 0
    true = Regex.match?(~r/\Aipse-managed-v3-capacity-[a-z0-9-]{1,96}\z/, Path.basename(store))
    true = graph != store and not String.starts_with?(store, graph <> "/")
    true = not String.starts_with?(graph, store <> "/")

    case File.lstat(store) do
      {:error, :enoent} when state in [:new, :either] ->
        :ok

      {:ok, %{type: :directory, uid: uid, mode: mode}} when state in [:existing, :either] ->
        true = uid == graph_identity["uid"] and Bitwise.band(mode, 0o077) == 0
        directory_identity!(store)

        for name <- ~w(home work oracle) do
          child = store <> "/" <> name
          identity = directory_identity!(child)
          true = identity["uid"] == graph_identity["uid"]
          true = Bitwise.band(File.lstat!(child).mode, 0o077) == 0
        end

      _ ->
        raise "capacity store must be a fresh isolated directory, never a symlink or replacement"
    end

    %{
      "graph" => graph,
      "store" => store,
      "graph_identity" => graph_identity,
      "parent" => parent,
      "parent_identity" => parent_identity
    }
  end

  def check_location!(plan, state) do
    true = location!(plan["graph"], plan["store"], state) === plan["location"]
    :ok
  end

  def source_inputs(graph) do
    paths =
      [
        __ENV__.file,
        graph <> "/project/test/support/managed_policy.exs",
        graph <> "/project/test/ipse/extension/collection_normalizer_v3_test.exs",
        graph <> "/project/test/ipse/extension/collection_normalizer_v3_integration_test.exs"
      ] ++
        Enum.map(
          ~w(notes.ex knowledge/records.ex knowledge/contracts.ex),
          &(graph <> "/project/extensions/knowledge/src/" <> &1)
        )

    Map.new(paths, fn path ->
      directory_identity!(Path.dirname(path))
      %{type: :regular} = File.lstat!(path)
      {path, JSON.sha256(File.read!(path))}
    end)
  end

  def check_source_inputs!(graph, expected) do
    true = source_inputs(graph) === expected
    :ok
  end

  def dynamic_origins!(graph) do
    pairs = [
      {IpseKnowledge.Notes, graph <> "/project/extensions/knowledge/src/notes.ex"},
      {Records, graph <> "/project/extensions/knowledge/src/knowledge/records.ex"},
      {Contracts, graph <> "/project/extensions/knowledge/src/knowledge/contracts.ex"},
      {Ipse.Test.ManagedPolicy, graph <> "/project/test/support/managed_policy.exs"},
      {Ipse.Test.NormalizerV3Fixture,
       graph <> "/project/test/ipse/extension/collection_normalizer_v3_test.exs"},
      {Ipse.Development.ActualV3Publication,
       graph <> "/project/test/ipse/extension/collection_normalizer_v3_integration_test.exs"}
    ]

    Map.new(pairs, fn {module, path} ->
      source = module.module_info(:compile)[:source] |> List.to_string() |> Path.expand()
      true = source === Path.expand(path)
      {Atom.to_string(module), source}
    end)
  end

  def planned_row(n, opts) when n in 1..@max do
    [change] = opts.request["changes"]
    [source] = opts.verified_sources

    %{
      "number" => n,
      "key" => change["key"],
      "operation_id" => id("publication/#{n}"),
      "source_id" => source["occurrence_id"],
      "value_sha256" => JSON.sha256(Migration.encode(change["value"])),
      "value_bytes" => byte_size(Migration.encode(change["value"])),
      "category" => change["value"]["category"],
      "now_ms" => opts.now_ms,
      "source_sha256" => JSON.digest(opts.verified_sources),
      "request_sha256" => JSON.digest([opts.request]),
      "recipe_sha256" => JSON.digest([opts.recipe]),
      "constraints_sha256" => JSON.digest([opts.constraints]),
      "policy_sha256" => opts.policy_sha256
    }
  end

  def check_row!(frozen, n, opts) do
    true = frozen === planned_row(n, opts)
    :ok
  end

  def check_plan!(plan, graph) do
    true = plan["version"] === 3 and plan["graph"] === Path.expand(graph)
    true = plan["kind"] == "author_actual_core3_normalizer3_capacity"
    true = plan["limits"] === limits()
    true = plan["targets"] === [2000, 4000] and plan["controls"] === @controls
    true = plan["synthetic_sources"] === true and plan["live_source_authority"] === false
    true = plan["annual_qualified"] === false and plan["performance_qualified"] === false
    true = plan["actual_session_turns"] === 0 and plan["models"] === 0
    true = is_list(plan["rows"]) and length(plan["rows"]) == @max
    true = Enum.map(plan["rows"], & &1["number"]) === Enum.to_list(1..@max)

    for field <- ~w(key operation_id source_id),
        do: true = length(Enum.uniq_by(plan["rows"], & &1[field])) == @max

    Enum.each(plan["rows"], fn row -> check_row!(row, row["number"], options(row["number"])) end)
    true = plan["recipe_sha256"] == JSON.digest([options(1).recipe])
    true = plan["constraints_sha256"] == JSON.digest([options(1).constraints])
    true = plan["policy_sha256"] == options(1).policy_sha256
    :ok
  end

  def claim_attempt!(graph, segment, plan, binding) do
    attempt = read(graph <> "/segment-#{segment}.attempt.json")
    true = attempt === attempt_record(segment, plan, binding)
    save_new(graph <> "/segment-#{segment}.child-started.json", attempt)
  end

  def bootstrap(graph, phase \\ "prepare") do
    :ok = check_configuration!(System.get_env("IPSE_RUNNER_PATH"))
    directory_identity!(graph)
    true = Bitwise.band(File.lstat!(graph).mode, 0o077) == 0

    expected =
      if phase != "prepare" do
        plan = read(graph <> "/plan.json")
        :ok = check_source_inputs!(graph, plan["source_inputs"])
        plan["source_inputs"]
      end

    home = graph <> "/isolated-home"

    case File.mkdir(home) do
      :ok ->
        File.chmod!(home, 0o700)

      {:error, :eexist} ->
        directory_identity!(home)
        true = Bitwise.band(File.lstat!(home).mode, 0o077) == 0
    end

    System.put_env("IPSE_HOME", home <> "/ipse")
    {:ok, _} = Application.ensure_all_started(:ipse)
    load_sources(graph, expected)
  end

  def load_sources(graph, expected \\ nil) do
    captured = Map.new(source_inputs(graph), fn {path, _} -> {path, File.read!(path)} end)
    before = Map.new(captured, fn {path, bytes} -> {path, JSON.sha256(bytes)} end)
    if expected, do: true = before === expected
    project = graph <> "/project"

    for name <- ~w(notes.ex knowledge/records.ex knowledge/contracts.ex) do
      path = project <> "/extensions/knowledge/src/" <> name
      Code.compile_string(Map.fetch!(captured, path), path)
    end

    policy_path = project <> "/test/support/managed_policy.exs"
    Code.compile_string(Map.fetch!(captured, policy_path), policy_path)

    source =
      Map.fetch!(captured, project <> "/test/ipse/extension/collection_normalizer_v3_test.exs")

    {:ok, {:__block__, _, terms}} = Code.string_to_quoted(source)

    fixture =
      Enum.find(
        terms,
        &match?({:defmodule, _, [{:__aliases__, _, [:Ipse, :Test, :NormalizerV3Fixture]}, _]}, &1)
      )

    Code.compile_quoted(
      fixture,
      project <> "/test/ipse/extension/collection_normalizer_v3_test.exs"
    )

    source =
      Map.fetch!(
        captured,
        project <> "/test/ipse/extension/collection_normalizer_v3_integration_test.exs"
      )

    {:ok, {:__block__, _, terms}} = Code.string_to_quoted(source)
    {:defmodule, _, [_, [do: {:__block__, _, forms}]]} = List.last(terms)

    helpers =
      Enum.flat_map(forms, fn
        {:defp, meta, [{:publish, _, _} = head, [do: body]]} ->
          body =
            Macro.postwalk(body, fn
              {{:., _, [{:__aliases__, _, [:C]}, :execute_managed_v3]}, _, _} = call ->
                quote do:
                        Ipse.Development.ManagedV3Capacity.timed(:commit, fn -> unquote(call) end)

              {:verify_publication, _, _} = call ->
                quote do:
                        Ipse.Development.ManagedV3Capacity.timed(:checked_readback, fn ->
                          unquote(call)
                        end)

              term ->
                term
            end)

          [{:def, meta, [head, [do: body]]}]

        {:defp, meta, args} ->
          [{:def, meta, args}]

        {:alias, _, _} ->
          []

        _ ->
          []
      end)

    Code.compile_quoted(
      quote do
        defmodule Ipse.Development.ActualV3Publication do
          import ExUnit.Assertions
          alias Ipse.Extension.Collection, as: C
          alias Ipse.Extension.Collection.{ManagedPages, Migration, NormalizerV3}
          alias Ipse.Extension.ProjectIdentity, as: Identity
          alias Ipse.Test.NormalizerV3Fixture, as: F
          alias IpseKnowledge.Knowledge.Records
          alias Ipse.JSON
          unquote_splicing(helpers)
        end
      end,
      project <> "/test/ipse/extension/collection_normalizer_v3_integration_test.exs"
    )

    true = source_inputs(graph) === before
    origins = dynamic_origins!(graph)
    Process.put({__MODULE__, :loaded_sources}, {before, origins})
    :ok
  end

  def varied(number, bytes) do
    for n <- 0..div(bytes, 64), into: "", do: JSON.sha256("managed-v3-capacity/#{number}/#{n}")
  end

  def candidate(n) when n in 1..@max do
    quote =
      if n in @controls,
        do: String.duplicate(<<1>>, 251),
        else: binary_part(varied(n, 1024), 0, 1024)

    reason =
      if n in @controls,
        do: String.duplicate(<<1>>, 256),
        else: binary_part(varied(n + @max, 256), 0, 256)

    proof = %{
      "version" => 1,
      "session_id" => id("fixture-session"),
      "occurrence_id" => id("source/#{n}"),
      "version_id" => id("version/#{n}"),
      "kind" => "input.original",
      "origin" => "interactive_operator",
      "coverage" => "available",
      "path" => nil,
      "start_byte" => 0,
      "end_byte" => byte_size(quote),
      "quote" => quote,
      "quote_sha256" => JSON.sha256(quote),
      "content_sha256" => JSON.sha256(quote),
      "receipt_sha256" => JSON.sha256("explicit trusted synthetic source member #{n}")
    }

    category = if n <= 200, do: "preference", else: "ordinary"
    clock = if n in @controls, do: 9_007_199_254_740_991 - 90 * 86_400_000, else: @now
    event = if n in @controls, do: 9_007_199_254_740_991, else: nil

    {:ok, key, value} =
      apply(Records, :capture, [
        %{"text" => quote, "category" => category, "reason" => reason, "event_at_ms" => event},
        proof,
        clock
      ])

    %{key: key, value: value, proof: proof, now: clock, category: category}
  end

  def options(n) do
    c = candidate(n)
    contracts = apply(Contracts, :operator, [])

    %{
      request: %{
        "op" => "commit",
        "expected_generation" => n - 1,
        "advance_floor" => true,
        "changes" => [%{"key" => c.key, "expected_revision" => 0, "value" => c.value}]
      },
      recipe: contracts["recipes"]["note"],
      constraints: contracts["publication"]["note"],
      verified_sources: [c.proof],
      policy_sha256: JSON.sha256("reviewed synthetic capacity policy v3"),
      now_ms: c.now
    }
  end

  def prepare(graph, store) do
    false = File.exists?(graph <> "/plan.json")
    location = location!(graph, store, :new)

    rows =
      for n <- 1..@max do
        o = options(n)
        :ok = Ipse.Extension.CollectionPolicy.check(o.request, o.constraints, o.verified_sources)
        planned_row(n, o)
      end

    true = Enum.map(rows, & &1["key"]) |> Enum.uniq() |> length() == @max

    plan = %{
      "version" => 3,
      "kind" => "author_actual_core3_normalizer3_capacity",
      "graph" => graph,
      "store" => store,
      "location" => location,
      "source_inputs" => source_inputs(graph),
      "namespace" => JSON.sha256("isolated actual-v3 capacity 20261027"),
      "rows" => rows,
      "limits" => limits(),
      "targets" => [2000, 4000],
      "controls" => @controls,
      "value_size_distribution" => Enum.frequencies_by(rows, & &1["value_bytes"]),
      "recipe_sha256" => JSON.digest([options(1).recipe]),
      "constraints_sha256" => JSON.digest([options(1).constraints]),
      "policy_sha256" => options(1).policy_sha256,
      "synthetic_sources" => true,
      "live_source_authority" => false,
      "actual_session_turns" => 0,
      "models" => 0,
      "annual_qualified" => false,
      "performance_qualified" => false,
      "shape_note" =>
        "Four actual reachable5588-byte ordinary Notes with maxsafe clocks; others fixed declared epoch; conservative5598 derivation separate, not exactmaximum. Generic6144 transport separate.",
      "checkpoint_policy" =>
        "Full actual selected records/receipts verified before clean continuation; exact runtime/root drift, pending/unknown/refusal stops without replay; max8segments.",
      "import_scope" =>
        "read-only typed export plan plus measured physical headroom; no actual import/open/adoption or native complete-import preflight pass claim"
    }

    :ok = check_plan!(plan, graph)
    :ok = check_location!(plan, :new)
    save_new(graph <> "/plan.json", plan)

    IO.inspect(Map.take(plan, ~w(targets value_size_distribution controls recipe_sha256)),
      limit: :infinity
    )
  end

  def run(graph, segment) when segment in 1..8 do
    Process.flag(:max_heap_size, %{size: 16_000_000, kill: true, error_logger: true})
    started = System.monotonic_time(:millisecond)
    guard = spawn_link(fn -> guard(graph, segment, started) end)
    plan = read(graph <> "/plan.json")
    :ok = check_plan!(plan, graph)
    binding = bindings(graph)
    true = binding == read(graph <> "/bindings.json")
    store = plan["store"]
    :ok = check_location!(plan, if(segment == 1, do: :new, else: :existing))
    # A controller intent is an attempt marker, never an authority grant.
    :ok = claim_attempt!(graph, segment, plan, binding)

    if segment > 1 do
      :ok = check_previous!(graph, store, segment - 1, plan, binding)
    end

    if segment == 1 do
      false = File.exists?(store)

      for p <- [store, store <> "/home", store <> "/work", store <> "/oracle"] do
        File.mkdir!(p)
        File.chmod!(p, 0o700)
      end
    end

    c = context(store, plan)
    previous = if segment > 1, do: read(store <> "/oracle/#{segment - 1}/root.json")

    if previous do
      true = previous["state"] == "confirmed" and previous["last"] == (segment - 1) * 500
      true = previous["binding_sha256"] == JSON.digest([binding])
      true = previous["plan_sha256"] == JSON.digest([plan])
      actual = checkpoint(c, previous["last"], graph, "resume-#{segment}")
      true = actual["snapshot_sha256"] == previous["checkpoint"]["snapshot_sha256"]
      true = actual["root_sha256"] == previous["checkpoint"]["root_sha256"]
    end

    false = File.exists?(store <> "/oracle/#{segment}")
    File.mkdir!(store <> "/oracle/#{segment}")
    File.chmod!(store <> "/oracle/#{segment}", 0o700)

    oracle(store, segment, %{
      "state" => "pending",
      "segment" => segment,
      "first" => (segment - 1) * 500 + 1,
      "last_possible" => segment * 500,
      "plan_sha256" => JSON.digest([plan]),
      "binding_sha256" => JSON.digest([binding])
    })

    driver = self()
    handler = "v3-capacity-#{segment}"

    :ok =
      :telemetry.attach(
        handler,
        [:ipse, :extension, :collection, :staged],
        fn _, m, meta, _ ->
          send(
            driver,
            {:native_peak, meta.generation,
             m.accounted_allocated_bytes + m.root_publication_reserved_bytes}
          )
        end,
        nil
      )

    samples =
      for n <- ((segment - 1) * 500 + 1)..(segment * 500) do
        true = System.monotonic_time(:millisecond) - started < @soft
        o = options(n)
        :ok = check_row!(Enum.at(plan["rows"], n - 1), n, o)

        scope = %{
          namespace: c.namespace,
          format: "managed-metadata-v3",
          operation_id: id("publication/#{n}"),
          initialize: n == 1
        }

        before = System.monotonic_time(:microsecond)

        result =
          apply(Ipse.Development.ActualV3Publication, :publish, [c, o, scope, [first: n == 1]])

        after_call = System.monotonic_time(:microsecond)

        case result do
          {:ok, value} ->
            true = value.core["receipt"]["generation"] == n

            peak =
              receive do
                {:native_peak, ^n, bytes} -> bytes
              after
                0 -> raise "missing allocation observation"
              end

            true = peak <= 64 * 1024 * 1024

            row = %{
              "n" => n,
              "publish_and_checked_readback_ms" => (after_call - before) / 1000,
              "read_units" => value.read_units,
              "commit_ms" => Process.get(:v3_capacity_commit_ms),
              "checked_readback_ms" => Process.get(:v3_capacity_checked_readback_ms),
              "accounted_peak_bytes" => peak,
              "receipt_sha256" => JSON.digest([value.core["receipt"]]),
              "normalization_sha256" => JSON.digest([value.core["normalization"]]),
              "sidecars" => length(value.core["normalization"]["metadata_changes"])
            }

            append(graph <> "/segment-#{segment}.calls.jsonl", row)
            if rem(n, 50) == 0, do: IO.puts("confirmed #{n}/4000")
            row

          other ->
            save(graph <> "/segment-#{segment}.refusal.json", %{
              "number" => n,
              "request" => o.request,
              "operation_id" => scope.operation_id,
              "outcome" => inspect(other, limit: :infinity),
              "qualification_passed" => false
            })

            raise "first publication refusal/unknown at #{n}; pending oracle retained"
        end
      end

    :telemetry.detach(handler)
    last = segment * 500
    check = checkpoint(c, last, graph, "terminal-#{segment}")

    report = %{
      "state" => "confirmed",
      "segment" => segment,
      "last" => last,
      "checkpoint" => check,
      "store_identity" => directory_identity!(store),
      "plan_sha256" => JSON.digest([plan]),
      "binding_sha256" => JSON.digest([binding]),
      "previous_sha256" => if(previous, do: JSON.digest([previous])),
      "elapsed_ms" => System.monotonic_time(:millisecond) - started,
      "samples" => samples,
      "qualification_passed" => false,
      "target2k_reached" => last >= 2000,
      "target4k_reached" => last == 4000,
      "performance_qualified" => false,
      "automatic_retries" => 0
    }

    oracle(store, segment, report)
    save(graph <> "/segment-#{segment}.report.json", report)
    Process.unlink(guard)
    Process.exit(guard, :kill)
    IO.puts("clean segment #{segment}; total #{last}; no next segment auto-start")
  end

  def attempt_record(segment, plan, binding) when segment in 1..8 do
    %{
      "version" => 1,
      "kind" => "managed_v3_capacity_attempt",
      "segment" => segment,
      "plan_sha256" => JSON.digest([plan]),
      "binding_sha256" => JSON.digest([binding])
    }
  end

  def clean_record!(segment, plan, binding, report, oracle, calls, status, log_sha)
      when segment in 1..8 do
    true = status === 0
    true = report === oracle
    true = report["state"] == "confirmed" and report["segment"] === segment
    true = report["last"] === segment * 500
    true = report["checkpoint"]["notes"] === segment * 500
    true = report["checkpoint"]["status"]["generation"] === segment * 500
    true = report["checkpoint"]["status"]["operations"] === segment * 500
    true = report["plan_sha256"] === JSON.digest([plan])
    true = report["binding_sha256"] === JSON.digest([binding])
    true = report["automatic_retries"] === 0
    true = report["qualification_passed"] === false
    true = report["performance_qualified"] === false
    true = calls === report["samples"]
    true = Enum.map(calls, & &1["n"]) === Enum.to_list(((segment - 1) * 500 + 1)..(segment * 500))
    true = JSON.sha256?(log_sha)

    Map.merge(attempt_record(segment, plan, binding), %{
      "kind" => "managed_v3_capacity_clean_exit",
      "exit_status" => 0,
      "report_sha256" => JSON.digest([report]),
      "log_sha256" => log_sha,
      "calls_sha256" => JSON.digest([calls])
    })
  end

  def check_previous!(graph, store, segment, plan, binding) do
    report = read(graph <> "/segment-#{segment}.report.json")
    true = report["store_identity"] === directory_identity!(store)
    oracle = read(store <> "/oracle/#{segment}/root.json")
    calls = calls(graph, segment)
    log_sha = JSON.sha256(File.read!(graph <> "/segment-#{segment}.process.log"))
    expected = clean_record!(segment, plan, binding, report, oracle, calls, 0, log_sha)
    true = read(graph <> "/segment-#{segment}.clean.json") === expected
    :ok
  end

  def process_status!({:ok, %{exit_code: 0, timed_out: false, output_truncated: false}}), do: 0

  def process_status!(_),
    do: raise("capacity process exit is unconfirmed; attempt remains unclean")

  # Run one fresh process only. The exit receipt is written only after observing
  # zero exit and matching checked terminal artifacts. An attempt is never retried.
  def control(graph, segment) when segment in 1..8 do
    plan = read(graph <> "/plan.json")
    :ok = check_plan!(plan, graph)
    binding = bindings(graph)
    true = binding === read(graph <> "/bindings.json")
    :ok = check_location!(plan, if(segment == 1, do: :new, else: :existing))
    if segment > 1, do: check_previous!(graph, plan["store"], segment - 1, plan, binding)
    save_new(graph <> "/segment-#{segment}.attempt.json", attempt_record(segment, plan, binding))
    log = graph <> "/segment-#{segment}.process.log"
    {:ok, io} = :file.open(String.to_charlist(log), [:write, :binary, :exclusive])
    File.chmod!(log, 0o600)

    try do
      args = [
        "-pa",
        graph <> "/build/lib/*/ebin",
        __ENV__.file,
        "capacity",
        "segment",
        graph,
        Integer.to_string(segment)
      ]

      status = run_bound_process(graph, binding, args, io)

      :ok = :file.sync(io)
      :ok = :file.close(io)
      report = read(graph <> "/segment-#{segment}.report.json")
      oracle = read(plan["store"] <> "/oracle/#{segment}/root.json")

      clean =
        clean_record!(
          segment,
          plan,
          binding,
          report,
          oracle,
          calls(graph, segment),
          status,
          JSON.sha256(File.read!(log))
        )

      save_new(graph <> "/segment-#{segment}.clean.json", clean)
      IO.puts("controller observed clean exit for segment #{segment}; no automatic continuation")
    after
      :file.close(io)
    end
  end

  defp run_bound_process(graph, binding, args, io) do
    :ok = check_configuration!(System.get_env("IPSE_RUNNER_PATH"))
    {:ok, helper} = Ipse.Runner.protected_helper(graph <> "/workspace")
    true = helper === binding["helper_path"]
    :ok = check_helper_sha256!(JSON.sha256(File.read!(helper)))
    executable = binding["launch"]["elixir"]
    true = JSON.sha256(File.read!(executable)) == binding["launch"]["elixir_sha256"]
    old_trap = Process.flag(:trap_exit, true)

    try do
      {:ok, port} =
        Ipse.Runner.open_protected_stdio(
          executable,
          args,
          graph <> "/workspace",
          %{"IPSE_HOME" => graph <> "/isolated-home/ipse"},
          @hard
        )

      try do
        frames =
          collect_frames(
            port,
            io,
            NativeFrames.new(),
            System.monotonic_time(:millisecond) + @hard + 5_000
          )

        :ok = NativeFrames.finish!(frames)
        :ok = Ipse.Runner.close_stdio(port, :completed)
        process_status!({:ok, frames.terminal})
      after
        if Port.info(port), do: :ok = Ipse.Runner.close_stdio(port)
      end
    after
      Process.flag(:trap_exit, old_trap)
    end
  end

  defp collect_frames(port, io, frames, deadline) do
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {^port, {:data, data}} ->
        {frames, chunks} = NativeFrames.push(frames, data)
        Enum.each(chunks, fn chunk -> :ok = :file.write(io, chunk) end)
        if frames.terminal, do: frames, else: collect_frames(port, io, frames, deadline)

      {^port, {:exit_status, _}} ->
        raise "native supervisor exited without a terminal result"

      {:EXIT, ^port, _} ->
        raise "native supervisor exited without a terminal result"
    after
      remaining -> raise "native supervisor deadline; attempt remains unclean"
    end
  end

  defp calls(graph, segment) do
    (graph <> "/segment-#{segment}.calls.jsonl")
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&Jason.decode!/1)
  end

  def context(store, plan) do
    home = store <> "/home"
    cwd = store <> "/work"

    identity =
      if File.exists?(home <> "/project-identities/index.json"),
        do: ProjectIdentity.existing(home, cwd),
        else: ProjectIdentity.admit(home, cwd, :folder)

    {:ok, admitted} = identity

    %{
      base: store,
      home: home,
      cwd: cwd,
      binding: admitted,
      root: store <> "/collections",
      namespace: plan["namespace"]
    }
  end

  def checkpoint(c, count, graph, tag) do
    started = System.monotonic_time(:microsecond)

    {:ok, status} =
      Collection.execute(c.root, c.namespace, %{"op" => "status"}, id("status/#{tag}"))

    true = status["generation"] == count and status["operations"] == count
    {rows, witness, reads} = scan(c, nil, [], nil, 0)
    notes = Enum.filter(rows, &String.starts_with?(&1["key"], "note."))
    true = length(notes) == count

    expected =
      Map.new(1..count, fn n ->
        x = candidate(n)
        {x.key, {n, x.value}}
      end)

    Enum.each(notes, fn row ->
      {n, value} = Map.fetch!(expected, row["key"])

      true =
        row["value"] == value and row["revision"] == n and
          row["operation_id"] == id("publication/#{n}")

      true = row["sha256"] == JSON.sha256(Migration.encode(value))
    end)

    {:ok, export} =
      Collection.execute(
        c.root,
        c.namespace,
        %{"op" => "export.plan", "generation" => count},
        id("export/#{tag}")
      )

    true =
      export["descriptor"]["records"] == length(rows) and
        export["descriptor"]["operations"] == count

    true = Enum.map(rows, &[&1["key"], &1["sha256"], &1["bytes"]]) == export["plan"]["records"]
    true = length(export["descriptor"]["floor_lineage"]) == count
    true = export["descriptor"]["floor_anchor"] == id("publication/#{count}")
    operations = export["plan"]["operations"]
    {:ok, receipts} = Ipse.Extension.Collection.Encoding.unpack_receipts(operations)
    Enum.each(1..count, fn n -> true = receipts[id("publication/#{n}")]["generation"] == n end)
    metadata = Enum.reject(rows, &String.starts_with?(&1["key"], "note."))

    info = %{
      "snapshot_sha256" => JSON.digest([Enum.map(rows, &Map.drop(&1, ["value"]))]),
      "root_sha256" => witness["root_sha256"],
      "status" => status,
      "record_count" => length(rows),
      "notes" => count,
      "public_value_bytes" => Enum.sum(Enum.map(notes, & &1["bytes"])),
      "sidecar_value_bytes" => Enum.sum(Enum.map(metadata, & &1["bytes"])),
      "sidecar_records" => length(metadata),
      "max_sidecar_bytes" => Enum.max(Enum.map(metadata, & &1["bytes"])),
      "actual_scan_units" => reads,
      "diagnostic_ms" => (System.monotonic_time(:microsecond) - started) / 1000,
      "export_plan_sha256" => JSON.digest([export]),
      "export_plan_bytes" => byte_size(Migration.encode(export)),
      "collection_allocated_headroom_bytes" => 42 * 1024 * 1024 - status["allocated_bytes"],
      "total_accounted_headroom_bytes" => 64 * 1024 * 1024 - status["accounted_allocated_bytes"],
      "complete_import_native_preflight_exercised" => false,
      "import_authority_exercised" => false
    }

    save(graph <> "/checkpoint-#{tag}.json", info)
    info
  end

  def scan(c, cursor, all, root, units) do
    {:ok, view} = Collection.open_view(c.root, c.namespace)

    {rows, next, witness, used} =
      try do
        scan_window(view, cursor, [], root, 0)
      after
        :ok = Collection.close_view(view)
      end

    if is_nil(next),
      do: {all ++ rows, witness, units + used},
      else: scan(c, next, all ++ rows, witness, units + used)
  end

  def scan_window(view, cursor, all, root, used) do
    {:ok, page} = Collection.view_read(view, %{"op" => "scan", "after" => cursor, "limit" => 8})
    if root, do: true = page["witness"] == root
    next = page["next"]
    rows = all ++ page["records"]

    if is_nil(next) or used + 8 == 512,
      do: {rows, next, page["witness"], used + 8},
      else: scan_window(view, next, rows, page["witness"], used + 8)
  end

  def oracle(store, segment, value) do
    dir = store <> "/oracle/#{segment}"
    {:ok, cap} = Transaction.acquire(dir <> "/.lock", cwd: store <> "/work")

    try do
      :ok = Transaction.quota(cap, :flat, 8 * 1024 * 1024)
      pending = ".pending-" <> Ipse.Usage.id()
      :ok = Transaction.stage(cap, ".", [{pending, Migration.encode(value)}])
      :ok = Transaction.switch(cap, pending, "root.json")
    after
      :ok = Transaction.release(cap)
    end
  end

  def bindings(graph) do
    :ok = check_configuration!(System.get_env("IPSE_RUNNER_PATH"))
    sources_before = source_inputs(graph)
    origins = dynamic_origins!(graph)
    true = Process.get({__MODULE__, :loaded_sources}) === {sources_before, origins}
    plan = read(graph <> "/plan.json")
    :ok = check_source_inputs!(graph, plan["source_inputs"])
    :ok = check_location!(plan, :either)

    files =
      for path <-
            Path.wildcard(graph <> "/build/lib/*/ebin/*.beam") ++
              Path.wildcard(graph <> "/build/lib/*/consolidated/*.beam"),
          into: %{},
          do: {String.replace_prefix(path, graph <> "/", ""), JSON.sha256(File.read!(path))}

    sources =
      for path <-
            [
              __ENV__.file,
              graph <> "/project/test/support/managed_policy.exs",
              graph <> "/project/lib/ipse/extension/collection.ex",
              graph <> "/project/lib/ipse/extension/collection/normalizer_v3.ex",
              graph <> "/project/lib/ipse/extension/collection/managed_pages.ex",
              graph <> "/project/lib/ipse/extension/collection/managed_pages/planner.ex",
              graph <>
                "/project/test/ipse/extension/collection_normalizer_v3_integration_test.exs",
              graph <> "/project/test/ipse/extension/collection_normalizer_v3_test.exs"
            ] ++
              Enum.map(
                ~w(notes.ex knowledge/records.ex knowledge/contracts.ex),
                &(graph <> "/project/extensions/knowledge/src/" <> &1)
              ),
          into: %{},
          do: {path, JSON.sha256(File.read!(path))}

    {:ok, helper} = Ipse.Runner.protected_helper(graph <> "/workspace")
    true = String.starts_with?(helper, graph <> "/")
    :ok = check_helper_sha256!(JSON.sha256(File.read!(helper)))

    for m <- [
          Collection,
          NormalizerV3,
          ManagedPages,
          Ipse.Extension.Collection.ManagedPages.Planner,
          ProjectIdentity,
          ProjectIdentity.DomainAuth,
          Ipse.Runner,
          Transaction
        ],
        do: true = String.starts_with?(List.to_string(:code.which(m)), graph <> "/build/")

    %{
      "beams" => files,
      "sources" => sources,
      "helper_sha256" => JSON.sha256(File.read!(helper)),
      "helper_path" => helper,
      "dynamic_origins" => origins,
      "launch" => launch_binding!(graph),
      "plan_sha256" => JSON.digest([read(graph <> "/plan.json")]),
      "elixir" => System.version(),
      "otp" => System.otp_release(),
      "kernel" => inspect(:os.version())
    }
  end

  def launch_binding!(graph) do
    directory_identity!(graph <> "/workspace")
    executable = System.find_executable("elixir") || raise "Elixir executable unavailable"
    {:ok, executable} = Ipse.Workspace.canonical_path(executable)

    %{
      "elixir" => executable,
      "elixir_sha256" => JSON.sha256(File.read!(executable)),
      "cwd" => graph <> "/workspace",
      "transport" => "protected_stdio"
    }
  end

  def id(text), do: binary_part(JSON.sha256(text), 0, 32)

  def timed(kind, fun) do
    started = System.monotonic_time(:microsecond)
    value = fun.()

    Process.put(
      if(kind == :commit, do: :v3_capacity_commit_ms, else: :v3_capacity_checked_readback_ms),
      (System.monotonic_time(:microsecond) - started) / 1000
    )

    value
  end

  def read(path), do: path |> File.read!() |> Jason.decode!()

  def save(path, value) do
    File.write!(path, Jason.encode!(value, pretty: true) <> "\n")
    File.chmod!(path, 0o600)
  end

  def save_new(path, value) do
    {:ok, io} = :file.open(String.to_charlist(path), [:write, :binary, :exclusive])

    try do
      File.chmod!(path, 0o600)
      :ok = :file.write(io, Jason.encode!(value, pretty: true) <> "\n")
      :ok = :file.sync(io)
    after
      :ok = :file.close(io)
    end
  end

  def append(path, value) do
    File.write!(path, Jason.encode!(value) <> "\n", [:append])
    File.chmod!(path, 0o600)
  end

  def guard(graph, segment, started) do
    elapsed = System.monotonic_time(:millisecond) - started
    bytes = :erlang.memory(:total)

    if elapsed >= @hard or bytes > @memory do
      save(graph <> "/segment-#{segment}.guard-failure.json", %{
        "elapsed_ms" => elapsed,
        "beam_bytes" => bytes,
        "hard_ms" => @hard,
        "memory_limit" => @memory,
        "qualification_passed" => false
      })

      System.halt(86)
    else
      Process.sleep(250)
      guard(graph, segment, started)
    end
  end
end

case System.argv() do
  ["capacity", mode, graph | rest] when mode in ~w(prepare bindings control segment) ->
    Ipse.Development.ManagedV3Capacity.bootstrap(graph, mode)

    case mode do
      "prepare" ->
        Ipse.Development.ManagedV3Capacity.prepare(graph, hd(rest))

      "bindings" ->
        Ipse.Development.ManagedV3Capacity.save_new(
          graph <> "/bindings.json",
          Ipse.Development.ManagedV3Capacity.bindings(graph)
        )

      "control" ->
        Ipse.Development.ManagedV3Capacity.control(graph, String.to_integer(hd(rest)))

      "segment" ->
        Ipse.Development.ManagedV3Capacity.run(graph, String.to_integer(hd(rest)))
    end

  _ ->
    :ok
end
