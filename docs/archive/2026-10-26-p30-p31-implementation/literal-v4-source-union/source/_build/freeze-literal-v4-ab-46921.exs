Code.prepend_paths(Path.wildcard("_build/literal-v4-ab-current2-sol-20261029/lib/*/ebin"))
alias Ipse.JSON

destination = "docs/archive/2026-10-26-p30-p31-implementation/literal-v4-source-union"
File.mkdir_p!(destination)
copy = fn from, relative ->
  target = Path.join(destination, relative)
  File.mkdir_p!(Path.dirname(target))
  File.cp!(from, target)
end

sources = ~w(
  lib/ipse/session/invocation.ex
  lib/ipse/session/managed_tool_use.ex
  test/ipse/extension/managed_collection_call_session_test.exs
  test/support/managed_literal_ab_seed.exs
  test/support/operator_pty.rs
  _build/run-literal-ab-seed-46915.exs
  _build/run-literal-v4-ab-current-46920.exs
  _build/run-literal-v4-ab-current2.exs
  _build/check-literal-ab-cohort.exs
  _build/freeze-literal-v4-ab-46921.exs
)

for path <- sources, do: copy.(path, "source/" <> path)

for path <- Path.wildcard("/tmp/ipse-literal-v4-ab-current-469*.log") ++
              ~w(/tmp/ipse-literal-ab-seed-46915.log /tmp/ipse-literal-v4-ab-source-verify-46922.log) do
  copy.(path, "logs/" <> Path.basename(path))
end

seed_root = "/tmp/ipse-literal-v4-ab-46915"
seed = seed_root |> Path.join("literal-ab-seed.json") |> File.read!() |> Jason.decode!()
true = JSON.sha256(File.read!(seed["source_journal"])) == seed["source_sha256"]
false = File.exists?(seed["source_journal"] <> ".held-for-ab")
copy.(Path.join(seed_root, "literal-ab-seed.json"), "synthetic/literal-ab-seed.json")
copy.(seed["source_journal"], "synthetic/source-A.jsonl")
copy.(Path.join(seed_root, "trace"), "synthetic/final-worker-trace.jsonl")

consumers =
  Path.wildcard(Path.join(seed_root, "home/sessions/*.jsonl"))
  |> Enum.map(fn path ->
    events = path |> File.stream!() |> Enum.map(&Jason.decode!/1)
    {path, events}
  end)
  |> Enum.filter(fn {_path, events} ->
    Enum.any?(events, &(&1["type"] == "managed_read_observed" and
      Enum.any?(&1["dependencies"], fn dep -> dep["version"] == 4 end)))
  end)
  |> Enum.sort_by(fn {path, _events} -> File.stat!(path, time: :posix).mtime end)

{current_path, current_events} = List.last(consumers)
current_id = Path.basename(current_path, ".jsonl")
true = current_id != seed["session_id"]
false = Enum.any?(current_events, &(&1["type"] == "extension_action_intent" and
  get_in(&1, ["request", "op"]) == "collection.managed"))
true = Enum.any?(current_events, &(&1["type"] == "extension_action_result" and
  get_in(&1, ["request", "op"]) == "source.quote" and
  get_in(&1, ["outcome", "value", "origin"]) == "unattended_input"))

for {path, _events} <- consumers do
  copy.(path, "synthetic/consumer-" <> Path.basename(path))
end

graphs = %{
  "historical_seed" => "_build/retention-cli-final-switch-20261028/lib",
  "stale_consumer" => "_build/literal-v4-ab-current-sol-20261029/lib",
  "corrected_consumer" => "_build/literal-v4-ab-current2-sol-20261029/lib",
  "tested_gate_overlay" => "_build/strict-lifetime-followup-sol-20261029/lib"
}

inventory = fn base ->
  Path.wildcard(Path.join(base, "ipse/ebin/*.beam")) ++
    Path.wildcard(Path.join(base, "ipse/priv/*"))
  |> Enum.filter(&File.regular?/1)
  |> Map.new(fn path -> {Path.relative_to(path, base), JSON.sha256(File.read!(path))} end)
end

overlay = ~w(Ipse.Session.Invocation Ipse.Session.ManagedToolUse Ipse.Extension.Collection
  Ipse.Extension.State Ipse.CLI.Errors Ipse.CLI.Knowledge Ipse.CLI.Knowledge.Management Ipse.CLI.Terminal)
overlay_hashes =
  Map.new(overlay, fn name ->
    relative = "ipse/ebin/Elixir." <> name <> ".beam"
    tested = Path.join(graphs["corrected_consumer"], relative) |> File.read!()
    true = tested == (Path.join(graphs["tested_gate_overlay"], relative) |> File.read!())
    {name, JSON.sha256(tested)}
  end)

invocation = Path.join(graphs["corrected_consumer"], "ipse/ebin/Elixir.Ipse.Session.Invocation.beam")
{:ok, {_, [imports: imports]}} = :beam_lib.chunks(String.to_charlist(invocation), [:imports])
true = {Ipse.Session.ManagedToolUse, :publication_prerequisites?, 3} in imports
true = {Ipse.Session.ManagedToolUse, :managed_invocation?, 1} in imports

runtime = %{
  "graphs" => Map.new(graphs, fn {role, base} -> {role, %{"path" => base, "files" => inventory.(base)}} end),
  "overlay_sha256" => overlay_hashes,
  "final_consumer_session" => current_id,
  "final_consumer_journal" => "synthetic/consumer-" <> Path.basename(current_path),
  "original_source_restored_byte_exact" => true,
  "guarded_imports" => ["ManagedToolUse.publication_prerequisites?/3", "ManagedToolUse.managed_invocation?/1"]
}

File.write!(Path.join(destination, "runtime.json"), Jason.encode!(runtime, pretty: true) <> "\n")
files =
  Path.wildcard(Path.join(destination, "**/*"))
  |> Enum.filter(&File.regular?/1)
  |> Enum.reject(&(Path.basename(&1) == "manifest.json"))
  |> Map.new(fn path ->
    bytes = File.read!(path)
    {Path.relative_to(path, destination), %{"bytes" => byte_size(bytes), "sha256" => JSON.sha256(bytes)}}
  end)

manifest = %{
  "date" => "2026-10-29",
  "scope" => "Genuine historical literal seed and corrected current-gate consumer source-union refusal; local retained graphs, not aggregate or publication qualification.",
  "files" => files
}
File.write!(Path.join(destination, "manifest.json"), Jason.encode!(manifest, pretty: true) <> "\n")
IO.puts("LITERAL_V4_AB_FROZEN artifacts=#{map_size(files)} consumers=#{length(consumers)} final=#{current_id}")
