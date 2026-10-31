# Explicit diagnostic continuation after a proven pre-dispatch soft boundary.
# The original graph, pending oracle and source bytes are never rewritten.
case System.argv() do
  ["prepare", _, graph, _] ->
    Code.require_file(Path.join(graph, "project/dev/knowledge/managed_v3_capacity.exs"))

  [mode, directory, _] when mode in ~w(control segment) ->
    plan = directory |> Path.join("plan.json") |> File.read!() |> Jason.decode!()
    Code.require_file(Path.join(plan["graph"], "project/dev/knowledge/managed_v3_capacity.exs"))

  _ ->
    :ok
end

defmodule Ipse.Development.ManagedV3Continuation do
  @moduledoc false
  alias Ipse.Development.ManagedV3Capacity, as: C
  alias Ipse.Extension.Collection
  alias Ipse.Extension.Collection.Encoding
  alias Ipse.{JSON, Runner}
  @target 4000
  @chunk 250

  def limits do
    C.limits() |> Map.merge(%{"segment_size" => @chunk, "segments" => 8})
  end

  def ranges(last) when is_integer(last) and last in 2000..3999 do
    Enum.chunk_every(Enum.to_list((last + 1)..@target), @chunk)
    |> Enum.map(&%{"first" => hd(&1), "last" => List.last(&1)})
  end

  def soft_boundary?(source, log, path) do
    lines = String.split(source, "\n") |> Enum.with_index(1)

    case Enum.filter(lines, fn {line, _} ->
           String.trim(line) == "true = System.monotonic_time(:millisecond) - started < @soft"
         end) do
      [{_, number}] ->
        case String.split(log, "** (") do
          [_preamble, "MatchError) no match of right hand side value:\n\n    false\n\n" <> trace] ->
            frames = trace |> String.trim_trailing() |> String.split("\n")
            first = "    " <> path <> ":#{number}: anonymous fn/"

            Enum.any?(frames) and String.starts_with?(hd(frames), first) and
              Enum.all?(frames, &soft_frame?(&1, path))

          _ ->
            false
        end

      _ ->
        false
    end
  end

  defp soft_frame?(frame, path) do
    Regex.match?(
      ~r/\A    #{Regex.escape(path)}:[0-9]+: (?:anonymous fn\/[0-9]+ in Ipse\.Development\.ManagedV3Capacity\.run\/2|Ipse\.Development\.ManagedV3Capacity\.run\/2|\(file\))\z/,
      frame
    ) or
      Regex.match?(
        ~r/\A    \(elixir [^)]+\) lib\/enum\.ex:[0-9]+: Enum\.(?:map_range\/4|map\/2)\z/,
        frame
      )
  end

  def baseline_matches?(baseline, observed) do
    fields = ~w(last calls_sha256 failure_log_sha256 pending_sha256)

    Map.take(baseline, fields) === observed and
      Enum.all?(tl(fields), &JSON.sha256?(observed[&1])) and
      observed["last"] in 2000..3999
  rescue
    _ -> false
  end

  def prefix!(calls, last) do
    true = is_integer(last) and last in 2000..3999
    true = is_list(calls) and length(calls) == last
    true = Enum.map(calls, & &1["n"]) === Enum.to_list(1..last)

    Enum.each(calls, fn call ->
      true = JSON.sha256?(call["receipt_sha256"]) and JSON.sha256?(call["normalization_sha256"])

      true =
        is_number(call["publish_and_checked_readback_ms"]) and
          call["publish_and_checked_readback_ms"] >= 0

      true = call["read_units"] in 0..32

      true =
        is_integer(call["accounted_peak_bytes"]) and
          call["accounted_peak_bytes"] <= 64 * 1024 * 1024
    end)

    :ok
  end

  def prepare(directory, graph, segment) when segment in 2..8 do
    false = File.exists?(directory <> "/plan.json")
    origin = private_directory!(directory)
    :ok = C.bootstrap(graph, "bindings")
    binding = C.bindings(graph)
    true = binding === C.read(graph <> "/bindings.json")
    original = C.read(graph <> "/plan.json")
    :ok = C.check_plan!(original, graph)
    true = origin["uid"] == C.directory_identity!(graph)["uid"]
    driver = graph <> "/project/dev/knowledge/managed_v3_capacity.exs"
    log_path = graph <> "/segment-#{segment}.process.log"
    true = soft_boundary?(File.read!(driver), File.read!(log_path), driver)

    for suffix <- ~w(report.json clean.json refusal.json guard-failure.json),
        do: false = File.exists?(graph <> "/segment-#{segment}." <> suffix)

    for previous <- 1..(segment - 1),
        do: :ok = C.check_previous!(graph, original["store"], previous, original, binding)

    true =
      C.read(graph <> "/segment-#{segment}.attempt.json") ===
        C.attempt_record(segment, original, binding)

    true =
      C.read(graph <> "/segment-#{segment}.child-started.json") ===
        C.attempt_record(segment, original, binding)

    pending = C.read(original["store"] <> "/oracle/#{segment}/root.json")
    true = pending["state"] == "pending" and pending["segment"] === segment

    true =
      pending["plan_sha256"] == JSON.digest([original]) and
        pending["binding_sha256"] == JSON.digest([binding])

    calls =
      Enum.flat_map(1..segment, fn n ->
        File.read!(graph <> "/segment-#{n}.calls.jsonl")
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)
      end)

    last = length(calls)
    true = last in ((segment - 1) * 500)..(segment * 500 - 1)
    :ok = prefix!(calls, last)
    true = File.regular?(original["store"] <> "/home/project-identities/index.json")
    context = C.context(original["store"], original)
    check = C.checkpoint(context, last, directory, "reconciled")

    {:ok, export} =
      Collection.execute(
        context.root,
        context.namespace,
        %{"op" => "export.plan", "generation" => last},
        C.id("continuation-reconcile-export")
      )

    {:ok, receipts} = Encoding.unpack_receipts(export["plan"]["operations"])
    true = map_size(receipts) == last

    Enum.each(calls, fn call ->
      receipt = Map.fetch!(receipts, C.id("publication/#{call["n"]}"))

      true =
        receipt["generation"] === call["n"] and JSON.digest([receipt]) == call["receipt_sha256"]
    end)

    next = last + 1

    {:ok, %{"operation" => nil, "generation" => ^last}} =
      Collection.execute(
        context.root,
        context.namespace,
        %{"op" => "inspect", "operation_id" => C.id("publication/#{next}")},
        C.id("continuation-next-operation")
      )

    {:ok, %{"record" => nil, "generation" => ^last}} =
      Collection.execute(
        context.root,
        context.namespace,
        %{"op" => "get", "key" => C.candidate(next).key},
        C.id("continuation-next-record")
      )

    {:ok, view} = Collection.open_view(context.root, context.namespace)

    try do
      {:ok, snapshot} = Collection.view_read(view, %{"op" => "snapshot"})
      true = snapshot["witness"]["root_sha256"] == check["root_sha256"]
    after
      :ok = Collection.close_view(view)
    end

    plan = %{
      "version" => 1,
      "kind" => "diagnostic_managed_v3_soft_boundary_continuation",
      "graph" => graph,
      "directory" => directory,
      "origin" => origin,
      "controller_sha256" => JSON.sha256(File.read!(__ENV__.file)),
      "runtime_scope" => C.runtime_scope(),
      "limits" => limits(),
      "original_plan_sha256" => JSON.digest([original]),
      "original_binding_sha256" => JSON.digest([binding]),
      "store_origin" => C.directory_identity!(original["store"]),
      "baseline" => %{
        "segment" => segment,
        "last" => last,
        "checkpoint" => check,
        "calls_sha256" => JSON.digest([calls]),
        "failure_log_sha256" => JSON.sha256(File.read!(log_path)),
        "pending_sha256" => JSON.digest([pending]),
        "next_operation_id" => C.id("publication/#{next}"),
        "next_operation_absent" => true,
        "next_record_absent" => true
      },
      "chunks" => ranges(last),
      "target" => @target,
      "automatic_retries" => 0,
      "qualification_passed" => false,
      "performance_qualified" => false
    }

    for name <- ~w(work oracle),
        do:
          (
            File.mkdir!(directory <> "/" <> name)
            File.chmod!(directory <> "/" <> name, 0o700)
          )

    durable!(directory <> "/plan.json", plan, graph, binding)

    IO.inspect(%{
      reconciled: last,
      next_unattempted: next,
      chunks: plan["chunks"],
      runtime_scope: plan["runtime_scope"]
    })
  end

  defp private_directory!(directory) do
    origin = C.directory_identity!(directory)
    true = Bitwise.band(File.lstat!(directory).mode, 0o077) == 0
    true = Path.expand(__ENV__.file) == directory <> "/controller.exs"
    origin
  end

  defp selected!(directory) do
    plan = C.read(directory <> "/plan.json")
    true = plan["directory"] === directory and plan["origin"] === private_directory!(directory)

    true =
      plan["version"] === 1 and plan["kind"] == "diagnostic_managed_v3_soft_boundary_continuation"

    true = plan["controller_sha256"] == JSON.sha256(File.read!(__ENV__.file))
    true = plan["runtime_scope"] === C.runtime_scope() and plan["limits"] === limits()
    true = plan["target"] === @target and plan["chunks"] === ranges(plan["baseline"]["last"])

    true =
      plan["qualification_passed"] === false and plan["performance_qualified"] === false and
        plan["automatic_retries"] === 0

    :ok = C.bootstrap(plan["graph"], "bindings")
    binding = C.bindings(plan["graph"])
    true = JSON.digest([binding]) === plan["original_binding_sha256"]
    original = C.read(plan["graph"] <> "/plan.json")
    true = JSON.digest([original]) === plan["original_plan_sha256"]
    true = plan["store_origin"] === C.directory_identity!(original["store"])
    baseline = plan["baseline"]

    old_calls =
      Enum.flat_map(1..baseline["segment"], fn number ->
        File.read!(plan["graph"] <> "/segment-#{number}.calls.jsonl")
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)
      end)

    pending = C.read(original["store"] <> "/oracle/#{baseline["segment"]}/root.json")

    true =
      baseline_matches?(baseline, %{
        "last" => length(old_calls),
        "calls_sha256" => JSON.digest([old_calls]),
        "failure_log_sha256" =>
          JSON.sha256(File.read!(plan["graph"] <> "/segment-#{baseline["segment"]}.process.log")),
        "pending_sha256" => JSON.digest([pending])
      })

    false = File.exists?(plan["graph"] <> "/segment-#{baseline["segment"]}.report.json")
    false = File.exists?(plan["graph"] <> "/segment-#{baseline["segment"]}.clean.json")
    {plan, original, binding}
  end

  defp durable!(path, value, graph, binding) do
    C.save_durable_new(path, value, fn directory ->
      {:ok, helper} = Runner.protected_helper(graph <> "/workspace")
      true = helper === binding["helper_path"]
      :ok = C.check_helper_sha256!(JSON.sha256(File.read!(helper)))
      :ok = Runner.protected_sync_directory(directory)
    end)
  end

  def control(directory, number) do
    {plan, _, binding} = selected!(directory)
    true = number in 1..length(plan["chunks"])
    chunk = Enum.fetch!(plan["chunks"], number - 1)
    previous = previous!(directory, plan, number)

    attempt = %{
      "version" => 1,
      "number" => number,
      "chunk" => chunk,
      "plan_sha256" => JSON.digest([plan]),
      "previous_sha256" => JSON.digest([previous])
    }

    durable!(directory <> "/#{number}.attempt.json", attempt, plan["graph"], binding)
    log = directory <> "/#{number}.process.log"
    {:ok, io} = File.open(log, [:write, :binary, :exclusive])
    File.chmod!(log, 0o600)

    try do
      {:ok, port} =
        Runner.open_protected_stdio(
          binding["launch"]["elixir"],
          [
            "-pa",
            plan["graph"] <> "/build/lib/*/ebin",
            __ENV__.file,
            "segment",
            directory,
            Integer.to_string(number)
          ],
          plan["graph"] <> "/workspace",
          %{"IPSE_HOME" => plan["graph"] <> "/isolated-home/ipse"},
          limits()["hard_ms"]
        )

      try do
        frames =
          C.collect_frames(
            port,
            io,
            C.NativeFrames.new(),
            System.monotonic_time(:millisecond) + limits()["hard_ms"] + 5000
          )

        :ok = C.NativeFrames.finish!(frames)
      after
        if Port.info(port), do: :ok = Runner.close_stdio(port)
      end

      :ok = :file.sync(io)
      report = C.read(directory <> "/#{number}.report.json")
      oracle = C.read(directory <> "/oracle/#{number}/root.json")

      true =
        report === oracle and report["state"] == "confirmed" and report["last"] === chunk["last"]

      true =
        report["qualification_passed"] === false and report["performance_qualified"] === false and
          report["automatic_retries"] === 0

      calls = calls(directory, number)

      true =
        calls === report["samples"] and
          Enum.map(calls, & &1["n"]) === Enum.to_list(chunk["first"]..chunk["last"])

      true =
        report["plan_sha256"] == attempt["plan_sha256"] and
          report["previous_sha256"] == attempt["previous_sha256"]

      clean =
        Map.merge(attempt, %{
          "exit_status" => 0,
          "report_sha256" => JSON.digest([report]),
          "log_sha256" => JSON.sha256(File.read!(log)),
          "calls_sha256" => JSON.digest([calls])
        })

      durable!(directory <> "/#{number}.clean.json", clean, plan["graph"], binding)
      IO.puts("confirmed continuation #{number}; total #{chunk["last"]}; no automatic next chunk")
    after
      File.close(io)
    end
  end

  defp previous!(_directory, plan, 1), do: plan["baseline"]

  defp previous!(directory, plan, number) do
    previous = C.read(directory <> "/#{number - 1}.report.json")
    clean = C.read(directory <> "/#{number - 1}.clean.json")
    true = clean["exit_status"] === 0 and clean["plan_sha256"] === JSON.digest([plan])
    true = clean["report_sha256"] == JSON.digest([previous])
    true = previous === C.read(directory <> "/oracle/#{number - 1}/root.json")
    true = clean["calls_sha256"] == JSON.digest([calls(directory, number - 1)])

    true =
      clean["log_sha256"] == JSON.sha256(File.read!(directory <> "/#{number - 1}.process.log"))

    previous
  end

  def segment(directory, number) do
    {plan, original, binding} = selected!(directory)
    true = number in 1..length(plan["chunks"])
    chunk = Enum.fetch!(plan["chunks"], number - 1)
    previous = previous!(directory, plan, number)
    attempt = C.read(directory <> "/#{number}.attempt.json")

    true =
      attempt === %{
        "version" => 1,
        "number" => number,
        "chunk" => chunk,
        "plan_sha256" => JSON.digest([plan]),
        "previous_sha256" => JSON.digest([previous])
      }

    durable!(directory <> "/#{number}.started.json", attempt, plan["graph"], binding)

    Process.flag(:max_heap_size, %{
      size: limits()["max_heap_words"],
      kill: true,
      error_logger: true
    })

    started = System.monotonic_time(:millisecond)
    guard = spawn_link(fn -> guard(directory, number, started) end)
    context = C.context(original["store"], original)
    checked = C.checkpoint(context, chunk["first"] - 1, directory, "before-#{number}")
    true = checked["root_sha256"] == previous["checkpoint"]["root_sha256"]
    File.mkdir!(directory <> "/oracle/#{number}")
    File.chmod!(directory <> "/oracle/#{number}", 0o700)
    C.oracle(directory, number, Map.merge(attempt, %{"state" => "pending"}))
    owner = self()
    handler = "v3-continuation-#{number}"

    :ok =
      :telemetry.attach(
        handler,
        [:ipse, :extension, :collection, :staged],
        fn _, measurements, metadata, _ ->
          send(
            owner,
            {:peak, metadata.generation,
             measurements.accounted_allocated_bytes + measurements.root_publication_reserved_bytes}
          )
        end,
        nil
      )

    samples =
      Enum.map(chunk["first"]..chunk["last"], fn n ->
        true = System.monotonic_time(:millisecond) - started < limits()["soft_ms"]
        options = C.options(n)
        :ok = C.check_row!(Enum.at(original["rows"], n - 1), n, options)

        scope = %{
          namespace: context.namespace,
          format: "managed-metadata-v3",
          operation_id: C.id("publication/#{n}"),
          initialize: false
        }

        before = System.monotonic_time(:microsecond)

        {:ok, result} =
          apply(Ipse.Development.ActualV3Publication, :publish, [context, options, scope])

        elapsed = (System.monotonic_time(:microsecond) - before) / 1000
        true = result.core["receipt"]["generation"] === n

        peak =
          receive do
            {:peak, ^n, bytes} -> bytes
          after
            0 -> raise "missing actual allocation observation"
          end

        true = peak <= 64 * 1024 * 1024

        sample = %{
          "n" => n,
          "publish_and_checked_readback_ms" => elapsed,
          "read_units" => result.read_units,
          "accounted_peak_bytes" => peak,
          "receipt_sha256" => JSON.digest([result.core["receipt"]]),
          "normalization_sha256" => JSON.digest([result.core["normalization"]])
        }

        C.append(directory <> "/#{number}.calls.jsonl", sample)
        if rem(n, 50) == 0, do: IO.puts("confirmed #{n}/4000")
        sample
      end)

    :telemetry.detach(handler)
    checked = C.checkpoint(context, chunk["last"], directory, "after-#{number}")

    report =
      Map.merge(attempt, %{
        "state" => "confirmed",
        "last" => chunk["last"],
        "checkpoint" => checked,
        "samples" => samples,
        "elapsed_ms" => System.monotonic_time(:millisecond) - started,
        "qualification_passed" => false,
        "performance_qualified" => false,
        "automatic_retries" => 0
      })

    C.oracle(directory, number, report)
    C.save(directory <> "/#{number}.report.json", report)
    Process.unlink(guard)
    Process.exit(guard, :kill)
    IO.puts("clean continuation chunk #{number}; no next chunk auto-start")
  end

  defp calls(directory, number) do
    File.read!(directory <> "/#{number}.calls.jsonl")
    |> String.split("\n", trim: true)
    |> Enum.map(&Jason.decode!/1)
  end

  defp guard(directory, number, started) do
    if System.monotonic_time(:millisecond) - started >= limits()["hard_ms"] or
         :erlang.memory(:total) > limits()["beam_memory_limit"] do
      C.save(directory <> "/#{number}.guard-failure.json", %{"qualification_passed" => false})
      System.halt(86)
    else
      Process.sleep(250)
      guard(directory, number, started)
    end
  end
end

case System.argv() do
  ["prepare", directory, graph, segment] ->
    Ipse.Development.ManagedV3Continuation.prepare(directory, graph, String.to_integer(segment))

  ["control", directory, number] ->
    Ipse.Development.ManagedV3Continuation.control(directory, String.to_integer(number))

  ["segment", directory, number] ->
    Ipse.Development.ManagedV3Continuation.segment(directory, String.to_integer(number))

  _ ->
    :ok
end
