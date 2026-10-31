# Read-only actual-store verification for this frozen synthetic investigation.
# Writes only a new diagnostic report; no publication, repair or replay occurs.
[graph, directory, output] = System.argv() |> Enum.map(&Path.expand/1)
Code.require_file(graph <> "/project/dev/knowledge/managed_v3_capacity.exs")
alias Ipse.Development.ManagedV3Capacity, as: C
alias Ipse.Extension.Collection
alias Ipse.Extension.Collection.Encoding
alias Ipse.{JSON, Runner}

true =
  JSON.sha256(File.read!(graph <> "/plan.json")) ==
    "546471ff93133a026f25bac1ac528add2b22399e5e9deed31c2d66e90611acfc"

true =
  JSON.sha256(File.read!(graph <> "/bindings.json")) ==
    "9abf0874c1d753188d8febf85426dae11245ccdaf609848c24895af11a3ab303"

true =
  JSON.sha256(File.read!(directory <> "/plan.json")) ==
    "babf6fad26994254c840d80e6138de1f7d7e6cf6c855b56c11cbb56aa0c3737b"

true =
  JSON.sha256(File.read!(directory <> "/controller.exs")) ==
    "57996de4f726f7d09b70c69ce80796b914599a571178c581a2c76b63f5718dbc"

:ok = C.bootstrap(graph, "bindings")
binding = C.bindings(graph)
true = binding === C.read(graph <> "/bindings.json")
original = C.read(graph <> "/plan.json")
plan = C.read(directory <> "/plan.json")
true = plan["origin"] === C.directory_identity!(directory)
true = plan["store_origin"] === C.directory_identity!(original["store"])
true = plan["runtime_scope"] === C.runtime_scope()
true = plan["runtime_scope"]["production_admitted"] === false
true = plan["original_plan_sha256"] === JSON.digest([original])
true = plan["original_binding_sha256"] === JSON.digest([binding])
baseline = plan["baseline"]

read_calls = fn path ->
  File.read!(path) |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
end

old_calls =
  Enum.flat_map(1..baseline["segment"], &read_calls.(graph <> "/segment-#{&1}.calls.jsonl"))

true = JSON.digest([old_calls]) === baseline["calls_sha256"]
true = length(old_calls) === baseline["last"]

true =
  JSON.sha256(File.read!(graph <> "/segment-#{baseline["segment"]}.process.log")) ===
    baseline["failure_log_sha256"]

true =
  C.read(original["store"] <> "/oracle/#{baseline["segment"]}/root.json")
  |> then(&(JSON.digest([&1]) === baseline["pending_sha256"]))

true = baseline["next_operation_absent"] === true and baseline["next_record_absent"] === true
false = File.exists?(graph <> "/segment-#{baseline["segment"]}.clean.json")
false = File.exists?(graph <> "/segment-#{baseline["segment"]}.report.json")

for previous <- 1..(baseline["segment"] - 1),
    do: :ok = C.check_previous!(graph, original["store"], previous, original, binding)

{continuation_calls, final_report} =
  Enum.reduce(Enum.with_index(plan["chunks"], 1), {[], baseline}, fn {chunk, number},
                                                                     {all, previous} ->
    report = C.read(directory <> "/#{number}.report.json")
    clean = C.read(directory <> "/#{number}.clean.json")
    calls = read_calls.(directory <> "/#{number}.calls.jsonl")
    true = clean["exit_status"] === 0 and report["state"] == "confirmed"
    true = report === C.read(directory <> "/oracle/#{number}/root.json")
    true = clean["report_sha256"] === JSON.digest([report])
    true = clean["plan_sha256"] === JSON.digest([plan])
    true = clean["calls_sha256"] === JSON.digest([calls])
    true = clean["log_sha256"] === JSON.sha256(File.read!(directory <> "/#{number}.process.log"))
    true = clean["previous_sha256"] === JSON.digest([previous])
    true = report["previous_sha256"] === clean["previous_sha256"]
    true = report["last"] === chunk["last"]

    true =
      report["samples"] === calls and
        Enum.map(calls, & &1["n"]) === Enum.to_list(chunk["first"]..chunk["last"])

    true = report["performance_qualified"] === false and report["qualification_passed"] === false
    {all ++ calls, report}
  end)

calls = old_calls ++ continuation_calls
true = length(calls) === 4000 and Enum.map(calls, & &1["n"]) === Enum.to_list(1..4000)
true = File.regular?(original["store"] <> "/home/project-identities/index.json")
context = C.context(original["store"], original)
check = C.checkpoint(context, 4000, directory, "final-independent")
true = check["root_sha256"] === final_report["checkpoint"]["root_sha256"]

{:ok, export} =
  Collection.execute(
    context.root,
    context.namespace,
    %{"op" => "export.plan", "generation" => 4000},
    C.id("independent-final-export")
  )

{:ok, receipts} = Encoding.unpack_receipts(export["plan"]["operations"])
true = map_size(receipts) === 4000

Enum.each(calls, fn call ->
  receipt = Map.fetch!(receipts, C.id("publication/#{call["n"]}"))
  true = receipt["generation"] === call["n"] and JSON.digest([receipt]) === call["receipt_sha256"]
  true = call["accounted_peak_bytes"] <= 64 * 1024 * 1024
end)

{:ok, %{"operation" => nil, "generation" => 4000}} =
  Collection.execute(
    context.root,
    context.namespace,
    %{"op" => "inspect", "operation_id" => C.id("publication/4001")},
    C.id("independent-next-operation")
  )

true = check["status"]["accounted_allocated_bytes"] <= 64 * 1024 * 1024
true = check["status"]["allocated_bytes"] <= 42 * 1024 * 1024
times = Enum.map(calls, & &1["publish_and_checked_readback_ms"]) |> Enum.sort()
nearest = fn probability -> Enum.at(times, ceil(length(times) * probability) - 1) end

summary = %{
  "version" => 1,
  "kind" => "diagnostic_available_host_managed_v3_capacity",
  "graph" => graph,
  "continuation" => directory,
  "source_scope" => C.runtime_scope(),
  "actual_publications" => 4000,
  "actual_native_receipts_checked" => map_size(receipts),
  "actual_session_turns" => 0,
  "models" => 0,
  "synthetic_sources" => true,
  "target2k_reached" => true,
  "target4k_reached" => true,
  "unknown_replays" => 0,
  "automatic_retries" => 0,
  "original_baseline_artifacts_unchanged" => true,
  "pending_oracle_promoted" => false,
  "root_sha256" => check["root_sha256"],
  "checkpoint" => check,
  "max_accounted_publication_peak_bytes" =>
    Enum.max(Enum.map(calls, & &1["accounted_peak_bytes"])),
  "publication_readback_ms" => %{
    "p50" => nearest.(0.5),
    "p95" => nearest.(0.95),
    "maximum" => List.last(times),
    "sum" => Enum.sum(times)
  },
  "all_calls_sha256" => JSON.digest([calls]),
  "original_binding_sha256" => JSON.digest([binding]),
  "continuation_plan_sha256" => JSON.digest([plan]),
  "final_report_sha256" => JSON.digest([final_report]),
  "verifier_sha256" => JSON.sha256(File.read!(__ENV__.file)),
  "production_admitted" => false,
  "turnover_qualified" => false,
  "performance_qualified" => false,
  "qualification_passed" => false
}

:ok =
  C.save_durable_new(output, summary, fn path ->
    {:ok, helper} = Runner.protected_helper(graph <> "/workspace")
    true = helper === binding["helper_path"]
    :ok = C.check_helper_sha256!(JSON.sha256(File.read!(helper)))
    :ok = Runner.protected_sync_directory(path)
  end)

IO.puts("ACTUAL_4000_PUBLICATIONS_AND_NATIVE_RECEIPTS_VERIFIED")

IO.inspect(
  Map.take(
    summary,
    ~w(actual_publications actual_native_receipts_checked root_sha256 max_accounted_publication_peak_bytes publication_readback_ms)
  )
)
