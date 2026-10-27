parent = self()
sampler = spawn(fn ->
  loop = fn loop, peak ->
    receive do
      :done -> send(parent, {:rss_peak_kib, peak})
    after
      10 ->
        status = File.read!("/proc/self/status")
        rss = case Regex.run(~r/^VmRSS:\s+(\d+) kB$/m, status) do [_, n] -> String.to_integer(n); _ -> 0 end
        loop.(loop, max(peak, rss))
    end
  end
  loop.(loop, 0)
end)
{:ok, _} = Application.ensure_all_started(:ipse)
root = Path.join(System.tmp_dir!(), "ipse-history-cache-bench-" <> Ipse.Usage.id())
File.mkdir_p!(root)
{:ok, id} = Ipse.Journal.create(root, %{})
path = Path.join(root, id <> ".jsonl")
lines = for n <- 1..65_534, do: [Jason.encode!(%{"type" => "synthetic_benchmark", "sequence" => n, "payload" => String.duplicate("x", 420)}), "\n"]
File.write!(path, lines, [:append])
identity = %{"instance" => "fixture"}
request = %{"op" => "history.read", "view" => "metadata", "cursor" => 0, "snapshot" => nil, "limit" => 8}
intent = %{"type" => "extension_action_intent", "version" => 1, "operation_id" => Ipse.Usage.id(), "namespace" => id, "identity_sha256" => Ipse.JSON.digest([identity]), "approval" => "not_required", "request" => request}
{:ok, source} = Ipse.Journal.append_with_source(root, id, intent)
snapshot = Ipse.Extension.History.snapshot(source, intent)
context = %{history_dir: root, history_session: id, history_snapshot: snapshot, identity: identity, history_project_drafts: true}
{first_micros, {first, cache}} = :timer.tc(fn -> Ipse.Extension.History.execute_cached(context, intent, nil) end)
IO.puts("first records=65535 bytes=#{snapshot["byte_offset"]} elapsed_ms=#{div(first_micros,1000)} status=#{elem(first,0)}")
for iteration <- 1..3 do
  {micros, {result, _}} = :timer.tc(fn -> Ipse.Extension.History.execute_cached(context, intent, cache) end)
  IO.puts("cached=#{iteration} elapsed_us=#{micros} status=#{elem(result,0)}")
end
File.rm_rf!(root)
ranges = Enum.map(1..1024, fn n -> {n * 2, n * 2} end)
{micros, count} = :timer.tc(fn -> Enum.count(1..8000, fn _ -> Ipse.Session.DraftHistory.withheld?(ranges, 1) end) end)
IO.puts("dense_ranges=1024 lookups=8000 elapsed_us=#{micros} matches=#{count}")
send(sampler, :done)
receive do {:rss_peak_kib, value} -> IO.puts("sampled_vm_rss_peak_kib=#{value} interval_ms=10") after 5000 -> IO.puts("rss_sample_missing") end
