ExUnit.start(autorun: false)
import ExUnit.Assertions
alias Ipse.{JSON, Usage}
alias Ipse.CLI.Knowledge.Management
alias Ipse.Extension.{Collection, Consent, ProjectIdentity, SemanticAdmission}
alias Ipse.Extension.Collection.ObservedRead
[root, output] = System.argv()
read = fn p -> p |> File.read!() |> Jason.decode!() end

fingerprint = fn p ->
  %{"path" => p, "bytes" => File.stat!(p).size, "sha256" => JSON.sha256(File.read!(p))}
end

dir = Path.join(root, "turnover")
m = read.(Path.join(dir, "manifest.json"))
assert m["root"] == root and m["seed_kind"] == "initial" and m["segment_count"] == 7351
refute File.exists?(Path.join(dir, "inflight.json"))

for f <- m["files"] ++ m["seed_sources"] ++ [m["records_file"], m["segments_file"]],
    do: assert(fingerprint.(f["path"]) === f)

inputs = for i <- 1..45, do: read.(Path.join(dir, "input-#{i}.json"))

reports =
  for i <- 1..45 do
    closure = read.(Path.join(dir, "closed-#{i}.json"))
    assert closure["index"] == i and closure["exit_code"] == 0

    for name <- ~w(input report log),
        do: assert(fingerprint.(closure[name]["path"]) === closure[name])

    read.(closure["report"]["path"])
  end

assert Enum.map(inputs, & &1["segment"]["process_offset_day"]) |> Enum.uniq() == [21, 22, 23]
actions = Enum.flat_map(inputs, & &1["actions"])
counts = Enum.frequencies_by(actions, & &1["op"])
assert Enum.sort(Map.keys(counts)) == ~w(capture correct forget update)
records = Enum.reduce(reports, %{}, fn report, acc -> Map.merge(acc, report["new_records"]) end)
assert map_size(records) == length(actions) - counts["forget"]
targets = MapSet.new(Enum.map(actions, & &1["target"]))
surviving = Enum.reject(records, fn {id, _} -> MapSet.member?(targets, id) end)
Code.require_file(Path.join(dir, "clock.exs"))
{:ok, _} = Application.ensure_all_started(:ipse)
apply(Ipse.Test.ManagedClockLifecycle, :check_stdio_clock, [root])
home = Path.join(root, "home")
cwd = Path.join(root, "work")
{:ok, binding} = ProjectIdentity.existing(home, cwd)
{:ok, namespace} = Ipse.Extension.SemanticConsent.namespace(binding["project_id"], "knowledge")
collection = SemanticAdmission.collection_root(home)
{:ok, selected} = Management.selection(home)
{:ok, before} = ObservedRead.read(collection, namespace, %{"op" => "snapshot"})

assert before["value"] === List.last(reports)["snapshot"] and
         before["witness"]["root_sha256"] == List.last(reports)["root_sha256"]

assert before["value"]["generation"] == m["initial_snapshot"]["generation"] + length(actions)

{:ok, control} =
  Consent.existing_snapshot(SemanticAdmission.control_root(home), binding["project_id"])

assert JSON.digest([control]) == List.last(reports)["control_sha256"]
for {_, row} <- control["operations"], do: assert(row["status"] == "settled")
for {_, row} <- control["compacted"], do: assert(Enum.at(row, 4) == "settled")

for {_, expected} <- surviving do
  {:ok, observed} =
    ProjectIdentity.with_existing_domain_auth(
      home,
      cwd,
      binding,
      %{namespace: namespace, format: "managed-metadata-v3"},
      fn cap, catalog ->
        ObservedRead.managed_record(
          collection,
          namespace,
          %{"op" => "get_record", "key" => expected["key"]},
          cap,
          catalog,
          selected.recipe
        )
      end
    )

  assert observed["observation"]["value"]["record"]["value"] === expected["value"]
  assert observed["metadata"]["category"] == expected["value"]["category"]
end

for action <- Enum.filter(actions, &(&1["op"] == "forget")) do
  {:ok, value} =
    Collection.execute(
      collection,
      namespace,
      %{"op" => "get", "key" => action["target_record"]["key"]},
      Usage.id()
    )

  assert value["record"] == nil
end

{:ok, after_snapshot} = ObservedRead.read(collection, namespace, %{"op" => "snapshot"})
assert after_snapshot === before

{:ok, after_control} =
  Consent.existing_snapshot(SemanticAdmission.control_root(home), binding["project_id"])

assert after_control === control

for f <- m["files"] ++ m["seed_sources"] ++ [m["records_file"], m["segments_file"]],
    do: assert(fingerprint.(f["path"]) === f)

{:ok, status} = Collection.execute(collection, namespace, %{"op" => "status"}, Usage.id())

File.write!(
  output,
  Jason.encode!(%{
    "effects" => length(actions),
    "effect_counts" => counts,
    "additional_mixed_changes" => Enum.count(actions, &(&1["reason"] == "additional_churn")),
    "closed_segments" => 45,
    "verified_surviving_new_records" => length(surviving),
    "verified_forgotten" => counts["forget"],
    "generation" => before["value"]["generation"],
    "control_sequence" => control["sequence"],
    "root_sha256" => before["witness"]["root_sha256"],
    "collection_status" => status,
    "qualification" => false
  }) <> "\n",
  [:exclusive]
)

IO.puts("NATIVE_CALENDAR_THIRD_DAY_AUDIT_PASSED")
