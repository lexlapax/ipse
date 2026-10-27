# Bounded author capacity probe. The actual publication/read-back implementation
# is source-derived from the owning integration test, never a simulated C seam.
defmodule Ipse.Development.ManagedV3Capacity do
  alias Ipse.Extension.{Collection, ProjectIdentity}
  alias Ipse.Extension.Collection.{Migration, ManagedPages, NormalizerV3}
  alias IpseKnowledge.Knowledge.{Contracts, Records}
  alias Ipse.Runner.Transaction
  alias Ipse.JSON
  @now 1_800_000_000_000
  @controls [201, 1201, 2201, 3201]
  @max 4000
  @soft 360_000
  @hard 480_000
  @memory 536_870_912

  def bootstrap(graph) do
    home = graph <> "/isolated-home"
    File.mkdir_p!(home)
    File.chmod!(home, 0o700)
    System.put_env("IPSE_HOME", home <> "/ipse")
    System.delete_env("IPSE_RUNNER_PATH")
    {:ok, _} = Application.ensure_all_started(:ipse)
    project = graph <> "/project"

    for name <- ~w(notes.ex knowledge/records.ex knowledge/contracts.ex),
        do: Code.require_file(project <> "/extensions/knowledge/src/" <> name)

    Code.require_file(project <> "/test/support/managed_policy.exs")
    source = File.read!(project <> "/test/ipse/extension/collection_normalizer_v3_test.exs")
    {:ok, {:__block__, _, terms}} = Code.string_to_quoted(source)

    fixture =
      Enum.find(
        terms,
        &match?({:defmodule, _, [{:__aliases__, _, [:Ipse, :Test, :NormalizerV3Fixture]}, _]}, &1)
      )

    Code.compile_quoted(fixture)

    source =
      File.read!(project <> "/test/ipse/extension/collection_normalizer_v3_integration_test.exs")

    {:ok, {:__block__, _, terms}} = Code.string_to_quoted(source)
    {:defmodule, _, [_, [do: {:__block__, _, forms}]]} = List.last(terms)

    helpers =
      Enum.flat_map(forms, fn
        {:defp, meta, [{:publish, _, _} = head, [do: body]]} ->
          body =
            Macro.prewalk(body, fn
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

        {:alias, _, [{:__aliases__, _, [:Ipse]}, _]} ->
          []

        {:alias, _, _} = term ->
          [term]

        _ ->
          []
      end)

    Code.compile_quoted(
      quote do
        defmodule Ipse.Development.ActualV3Publication do
          import ExUnit.Assertions
          unquote_splicing(helpers)
        end
      end
    )

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
      Records.capture(
        %{"text" => quote, "category" => category, "reason" => reason, "event_at_ms" => event},
        proof,
        clock
      )

    %{key: key, value: value, proof: proof, now: clock, category: category}
  end

  def options(n) do
    c = candidate(n)
    contracts = Contracts.operator()

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

    rows =
      for n <- 1..@max do
        c = candidate(n)
        o = options(n)
        :ok = Ipse.Extension.CollectionPolicy.check(o.request, o.constraints, o.verified_sources)

        %{
          "number" => n,
          "key" => c.key,
          "operation_id" => id("publication/#{n}"),
          "source_id" => c.proof["occurrence_id"],
          "value_sha256" => JSON.sha256(Migration.encode(c.value)),
          "value_bytes" => byte_size(Migration.encode(c.value)),
          "category" => c.category,
          "source_sha256" => JSON.digest([c.proof]),
          "request_sha256" => JSON.digest([o.request])
        }
      end

    true = Enum.map(rows, & &1["key"]) |> Enum.uniq() |> length() == @max

    plan = %{
      "version" => 1,
      "kind" => "author_actual_core3_normalizer3_capacity",
      "graph" => graph,
      "store" => store,
      "namespace" => JSON.sha256("isolated actual-v3 capacity 20261027"),
      "rows" => rows,
      "targets" => [2000, 4000],
      "segments" => 8,
      "segment_size" => 500,
      "soft_ms" => @soft,
      "hard_ms" => @hard,
      "beam_memory_limit" => @memory,
      "max_heap_words" => 16_000_000,
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

    save(graph <> "/plan.json", plan)

    IO.inspect(Map.take(plan, ~w(targets value_size_distribution controls recipe_sha256)),
      limit: :infinity
    )
  end

  def run(graph, segment) when segment in 1..8 do
    Process.flag(:max_heap_size, %{size: 16_000_000, kill: true, error_logger: true})
    started = System.monotonic_time(:millisecond)
    guard = spawn_link(fn -> guard(graph, segment, started) end)
    plan = read(graph <> "/plan.json")
    binding = bindings(graph)
    true = binding == read(graph <> "/bindings.json")
    store = plan["store"]

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

        scope = %{
          namespace: c.namespace,
          format: "managed-metadata-v3",
          operation_id: id("publication/#{n}"),
          initialize: n == 1
        }

        before = System.monotonic_time(:microsecond)
        result = Ipse.Development.ActualV3Publication.publish(c, o, scope, first: n == 1)
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
      "elixir" => System.version(),
      "otp" => System.otp_release(),
      "kernel" => inspect(:os.version())
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

[mode, graph | rest] = System.argv()
Ipse.Development.ManagedV3Capacity.bootstrap(graph)

case mode do
  "prepare" ->
    Ipse.Development.ManagedV3Capacity.prepare(graph, hd(rest))

  "bindings" ->
    Ipse.Development.ManagedV3Capacity.save(
      graph <> "/bindings.json",
      Ipse.Development.ManagedV3Capacity.bindings(graph)
    )

  "segment" ->
    Ipse.Development.ManagedV3Capacity.run(graph, String.to_integer(hd(rest)))
end
