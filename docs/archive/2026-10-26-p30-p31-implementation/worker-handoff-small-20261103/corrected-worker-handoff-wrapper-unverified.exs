Code.require_file("../../test/support/worker_handoff_trace.exs", __DIR__)

defmodule Ipse.Development.WorkerHandoffDiagnostic do
  @moduledoc false
  alias Ipse.{JSON, Journal}
  alias Ipse.Session.ManagedReference
  alias Ipse.Test.WorkerHandoffTrace

  def main([root, scenario, output]) when scenario in ~w(current source_lost) do
    true = Path.dirname(root) == "/tmp" and Path.expand(root) == root
    true = String.starts_with?(Path.basename(root), "ipse-handoff-eight-")
    true = Path.dirname(output) == "/tmp" and Path.expand(output) == output
    true = String.starts_with?(Path.basename(output), "ipse-handoff-trace-")
    {:error, :enoent} = File.lstat(output)
    seed = root |> Path.join("literal-ab-seed.json") |> File.read!() |> Jason.decode!()
    true = length(seed["keys"]) == 8 and length(seed["source_journals"]) == 2

    for source <- seed["source_journals"],
        do: true = JSON.sha256(File.read!(source["path"])) == source["sha256"]

    history = Path.join(root, "home/sessions")
    before = MapSet.new(Path.wildcard(Path.join(history, "*.jsonl")))
    File.mkdir!(output)
    File.chmod!(output, 0o700)

    write!(Path.join(output, "intent.json"), %{
      "version" => 1,
      "scenario" => scenario,
      "seed_sha256" => JSON.sha256(File.read!(Path.join(root, "literal-ab-seed.json"))),
      "qualification" => false
    })

    System.put_env("IPSE_LITERAL_AB_ROOT", root)
    System.put_env("IPSE_TEST_MANAGED_PACK", "1")
    Code.require_file("test/test_helper.exs")

    ExUnit.configure(
      autorun: false,
      exclude: [:test],
      include: [tag(scenario)],
      max_cases: 1,
      seed: 791_960
    )

    Code.require_file("test/ipse/extension/managed_collection_call_session_test.exs")

    tracer = WorkerHandoffTrace.start(self())
    :ok = WorkerHandoffTrace.enable(tracer)

    result =
      try do
        ExUnit.run()
      after
        WorkerHandoffTrace.disable()
      end

    trace = tracer |> WorkerHandoffTrace.finish() |> WorkerHandoffTrace.spans()
    true = trace["dropped"] == 0

    paths =
      MapSet.difference(MapSet.new(Path.wildcard(Path.join(history, "*.jsonl"))), before)
      |> MapSet.to_list()

    summaries = Enum.map(paths, &summarize!/1)

    write!(Path.join(output, "report.json"), %{
      "version" => 1,
      "scenario" => scenario,
      "seed_notes" => 8,
      "original_source_journals" => 2,
      "test_result" => Map.take(result, [:total, :failures, :excluded, :skipped]),
      "journals" => summaries,
      "trace" => trace,
      "scope" =>
        "instrumented synthetic eight-note fixture; no production deadline or source check changed",
      "qualification" => false
    })

    traced_handoffs =
      Enum.count(
        trace["spans"],
        &(&1["module"] == "Elixir.Ipse.Session.WorkerInput" and &1["function"] == "call")
      )

    executed = result.total - result.excluded - result.skipped
    if result.failures != 0 or executed != 1 or traced_handoffs == 0, do: System.halt(1)
    IO.puts("WORKER_HANDOFF_DIAGNOSTIC=#{output}")
  end

  def main(_), do: raise("use ROOT current|source_lost OUTPUT")

  defp tag("current"), do: :managed_pack_actual_overflow
  defp tag("source_lost"), do: :managed_pack_actual_overflow_stale

  defp summarize!(path) do
    id = Path.basename(path, ".jsonl")
    {:ok, events} = Journal.load(Path.dirname(path), id)

    {_, inputs} =
      Enum.reduce(events, {[], []}, fn event, {dependencies, inputs} ->
        case event["type"] do
          "managed_read_observed" ->
            {:ok, union} = ManagedReference.union([dependencies, event["dependencies"]])
            {union, inputs}

          "worker_input_intent" ->
            entry = %{
              "id" => event["input_id"],
              "stage" => event["stage"],
              "checked_at_ms" => event["checked_at_ms"],
              "deadline_ms" => event["deadline_ms"],
              "frame_bytes" => event["frame_bytes"],
              "observed_dependency_count" => length(dependencies),
              "observed_dependencies_match" =>
                event["dependencies_sha256"] == JSON.digest(dependencies)
            }

            {dependencies, [entry | inputs]}

          _ ->
            {dependencies, inputs}
        end
      end)

    results =
      Map.new(
        for e <- events, e["type"] == "worker_input_result", do: {e["input_id"], e["status"]}
      )

    %{
      "session_id" => id,
      "journal_sha256" => JSON.sha256(File.read!(path)),
      "worker_inputs" =>
        Enum.reverse(inputs) |> Enum.map(&Map.put(&1, "result", results[&1["id"]])),
      "managed_read_observations" => Enum.count(events, &(&1["type"] == "managed_read_observed")),
      "inference_dispatches" => Enum.count(events, &(&1["type"] == "inference_dispatch_intent"))
    }
  end

  defp write!(path, value) do
    {:ok, file} = :file.open(String.to_charlist(path), [:write, :binary, :exclusive])
    :ok = :file.write(file, Jason.encode!(value) <> "\n")
    File.chmod!(path, 0o600)
    :ok = :file.sync(file)
    :ok = :file.close(file)
  end
end

Ipse.Development.WorkerHandoffDiagnostic.main(System.argv())
