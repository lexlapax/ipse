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
