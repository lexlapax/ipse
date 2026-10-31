source = File.read!("test/extensions/knowledge/producer_progress_test.exs")
replace_one = fn source, old, new ->
  1 = length(:binary.matches(source, old))
  String.replace(source, old, new)
end
source = replace_one.(source, "    drive(Producer.resume(c, outcome), d)", "    {us, result} = :timer.tc(fn -> Producer.resume(c, outcome) end)\n    if us > Process.get(:v4_callback_max_us, 0), do: Process.put(:v4_callback_peak_phase, inspect(get_in(c, [:progress, :phase])))\n    Process.put(:v4_callback_max_us, max(Process.get(:v4_callback_max_us, 0), us))\n    drive(result, d)")
source = replace_one.(source, "    {resolved, args, d} = initial_sources(sources)\n    {pages, d} = produce_pages", "    Process.put(:v4_callback_max_us, 0)\n    {resolved, args, d} = initial_sources(sources)\n    {pages, d} = produce_pages")
source = replace_one.(source, "    {{:done, {:ok, completed}}, result} = append(resolved, args, wide_facts, nil, d)\n    assert completed[\"job\"][\"cursor\"] == 8\n    assert completed[\"job\"][\"facts\"] == 256 and map_size(result.model.stages) == 0", "    {{:done, {:continue, _}}, _} = invoke(Progress.append(resolved, @profile, args, wide_facts, nil), d)\n    IO.puts(\"V4_CALLBACK_PROBE max_us=\" <> Integer.to_string(Process.get(:v4_callback_max_us)) <> \" phase=\" <> Process.get(:v4_callback_peak_phase))")
File.write!("/tmp/ipse-v4-callback-test.exs", source)
runner = File.read!("/tmp/ipse-v4-public-run.exs")
File.write!("/tmp/ipse-v4-callback-run.exs", String.replace(runner, "test/extensions/knowledge/producer_progress_test.exs", "/tmp/ipse-v4-callback-test.exs"))
