{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("test/test_helper.exs")
path = "test/ipse/extension/managed_collection_call_session_test.exs"
source = File.read!(path)
[before, rest] = String.split(source, "  for approval <- [:allow, :ask] do\n", parts: 2)
[block, after_block] = String.split(rest, "  for boundary <- [:current, :root_change] do\n    @tag nested_discovery:", parts: 2)
block = block
|> String.replace("refute Enum.any?(events, &(get_in(&1, [\"request\", \"op\"]) == \"collection.store\"))", "assert Enum.any?(events, &(get_in(&1, [\"request\", \"op\"]) == \"collection.store\"))")
|> String.replace("refute Enum.any?(events, &(&1[\"type\"] == \"managed_tool_effect_admitted\"))", "assert Enum.any?(events, &(&1[\"type\"] == \"managed_tool_effect_admitted\"))")
|> String.replace("refute File.exists?(directory)", "refute File.exists?(directory)\n      [result] = Enum.filter(events, &(&1[\"type\"] == \"extension_action_result\" and get_in(&1, [\"request\", \"op\"]) == \"collection.store\"))\n      assert result[\"outcome\"][\"status\"] == \"failed\"\n      assert result[\"outcome\"][\"value\"] == %{\"code\" => \"document_store_refused\"}")
variant = before <> "  for approval <- [:allow] do\n" <> block <>
  "  for boundary <- [:current, :root_change] do\n    @tag nested_discovery:" <> after_block
File.write!("_build/document-queued-backstop-sol-20261029/fixture.exs", variant)
ExUnit.configure(autorun: false, exclude: [:test], include: [document_decision_gate: true], seed: 47052)
Code.compile_string(variant, Path.expand(path))
result = ExUnit.run()
System.halt(if result.failures == 0, do: 0, else: 2)
