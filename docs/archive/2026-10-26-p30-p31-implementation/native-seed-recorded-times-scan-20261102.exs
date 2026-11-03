alias Ipse.JSON
root = "/tmp/ipse-native-seed-initial-20261102-first"
audit = "/tmp/ipse-native-seed-audit-initial-20261102-first.json"
seed = root |> Path.join("manifest.json") |> File.read!() |> Jason.decode!()
summary = audit |> File.read!() |> Jason.decode!()
true = summary["root"] == root and summary["verified_records"] == 2000
true = summary["unchanged_root"] and summary["unchanged_control"]
reports = for i <- 1..length(seed["plan"]), do: root |> Path.join("checkpoints/report-#{i}.json") |> File.read!() |> Jason.decode!()
sources = reports |> Enum.flat_map(& &1["sources"]) |> Enum.uniq_by(& &1["path"])
true = length(sources) == summary["unchanged_sources"]
keys = MapSet.new(~w(checked_at_ms observed_at_ms created_at_ms accepted_at_ms reviewed_at_ms started_at_ms finished_at_ms published_at_ms))
walk = fn walk, value, acc ->
  cond do
    is_map(value) -> Enum.reduce(value, acc, fn {key, v}, acc ->
      acc = if MapSet.member?(keys,key) and is_integer(v) and v >= 0, do: Map.update(acc,key,v,&max(&1,v)), else: acc
      walk.(walk,v,acc)
    end)
    is_list(value) -> Enum.reduce(value,acc,fn v,a -> walk.(walk,v,a) end)
    true -> acc
  end
end
{times, events} = Enum.reduce(sources, {%{},0}, fn source,{times,events} ->
  bytes = File.read!(source["path"])
  true = byte_size(bytes) == source["bytes"] and JSON.sha256(bytes) == source["sha256"]
  records = bytes |> String.split("\n",trim: true) |> Enum.map(&Jason.decode!/1)
  {Enum.reduce(records,times,fn event,acc -> walk.(walk,event,acc) end),events+length(records)}
end)
last = times |> Map.values() |> Enum.max()
start = seed["created_wall_ms"] + 21*86_400_000
true = last < start
report = %{"kind"=>"synthetic_seed_recorded_times", "sources_verified"=>length(sources), "events_read"=>events,"recognized_maxima_ms"=>times,"latest_recognized_ms"=>last,"next_day_start_ms"=>start,"gap_ms"=>start-last,"source_scope"=>"exact retained seed source bytes; designated timestamp names only; excludes clock deadlines and is not an upper bound on physical completion", "native_operations"=>0,"qualification"=>false}
File.write!("/tmp/ipse-native-seed-timestamp-audit-20261102.json",Jason.encode!(report,pretty: true)<>"\n",[:exclusive])
IO.puts(Jason.encode!(report))
