# Fresh plain VM observation; no Ipse modules, application or saved state.
false = :code.is_loaded(Ipse.Application)
false = Enum.any?(Application.started_applications(), fn {app, _, _} -> app == :ipse end)
before = System.monotonic_time(:millisecond)
beam_wall = System.system_time(:millisecond)
os_wall = :os.system_time(:millisecond)
Process.sleep(80)
elapsed = System.monotonic_time(:millisecond) - before
true = elapsed >= 60
IO.puts("beam_wall_ms=#{beam_wall}\nos_wall_ms=#{os_wall}\nbeam_sleep_ms=#{elapsed}")
[probe] = System.argv()
{output, 0} = System.cmd(probe, [])
IO.write(output)
