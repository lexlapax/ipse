base = "docs/archive/2026-10-26-p30-p31-implementation/"
hash = fn bytes -> Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) end

manifests = [
  {"shared-producer-selection-adoption",
   "df7c466ab04b233f7939a112487a9e46c8645c93955bb038502c97760803030f"},
  {"shared-producer-range-claim",
   "c464ec617ef4d403f47582068de49f749185263d0a95361ef6ddb5acd84d5d12"}
]

decoded =
  Enum.map(manifests, fn {name, expected} ->
    bytes = File.read!(base <> name <> "/manifest.json")
    ^expected = hash.(bytes)
    m = :json.decode(bytes)

    rows =
      Enum.flat_map(~w(source logs reports runtime ancestors), &Map.get(m, &1, [])) ++
        [m["helper"]] ++ Enum.flat_map(Map.get(m, "artifacts", []), & &1["files"])

    Enum.each(rows, fn r ->
      stat = File.lstat!(r["path"])

      if r["type"] == "symlink" do
        true = stat.type == :symlink
        true = File.read_link!(r["path"]) == r["target"]
        true = stat.mode == r["mode"] and stat.uid == r["uid"]
      else
        true = stat.type == :regular and stat.size == r["bytes"]
        true = hash.(File.read!(r["path"])) == r["sha256"]
      end
    end)

    Enum.each(Map.get(m, "artifacts", []), fn artifact ->
      paths = Enum.map(artifact["files"], & &1["path"])
      root = paths |> Enum.map(&Path.dirname/1) |> Enum.min_by(&byte_size/1)
      {listed, 0} = System.cmd("rg", ["--files", "--hidden", "--no-ignore", root])
      true = MapSet.new(String.split(listed, "\n", trim: true)) == MapSet.new(paths)
    end)

    IO.puts("#{name}: #{length(rows)} exact rows; #{length(m["runtime"])} runtime nodes verified")
    m
  end)

[selection, ranges] = decoded
true = selection["runtime"] === ranges["runtime"]
true = selection["helper"] === ranges["helper"]
IO.puts("Range runtime/helper exactly identical to selection cohort")

events =
  File.read!(base <> "shared-producer-selection-adoption/actual/synthetic-session.jsonl")
  |> String.split("\n", trim: true)
  |> Enum.map(&:json.decode/1)

173 = length(events)

[profile] =
  Enum.filter(
    events,
    &(&1["type"] == "extension_action_result" and
        get_in(&1, ["request", "op"]) == "embedding.profile")
  )

"not_required" = profile["approval"]
true = profile["effect_binding"]["profile"] === profile["outcome"]["value"]["profile"]

true =
  profile["effect_binding"]["selection_sha256"] ===
    profile["outcome"]["value"]["selection_sha256"]

[setup] =
  Enum.filter(
    events,
    &(&1["type"] == "extension_invocation_result" and
        get_in(&1, ["payload", "arguments", "action"]) == "selection")
  )

v = setup["value"]["coverage"]
true = v["configured_profile"] === profile["outcome"]["value"]["profile"]
true = v["selection_sha256"] === profile["outcome"]["value"]["selection_sha256"]
:null = v["reported_model"]
%{"reads_used" => 1, "effects_used" => 0} = v["coverage"]

[page] =
  Enum.filter(
    events,
    &(&1["type"] == "extension_invocation_result" and
        get_in(&1, ["payload", "arguments", "action"]) == "page")
  )

0 = page["action_count"]
[%{"code" => "shared_producer_source_dispatch_unavailable"}] = page["value"]["gaps"]

false =
  Enum.any?(
    events,
    &(&1["type"] in ~w(request_admitted request_finished extension_effect_result extension_embedding_request))
  )

boundary =
  :json.decode(
    File.read!(base <> "shared-producer-selection-adoption/actual/native-boundary.json")
  )

true = boundary["before"] === boundary["after"]
:null = boundary["claim"]

IO.puts(
  "Retained actual selection journal: 173 events; profile binding/value/setup exact; page zero actions; boundary unchanged; no inference admission"
)
