import ExUnit.Assertions
ExUnit.start(autorun: false)
packet = __DIR__
path = "test/ipse/session/native_note_recall_strict_sources_test.exs"
actual = File.read!(Path.join([packet,"candidate",path]))
official = File.read!(Path.join([packet,"official",path]))
commands = fn body ->
  {:ok, tree} = Code.string_to_quoted(body)
  {_, commands} = Macro.prewalk(tree, [], fn
    {{:., _, [{:__aliases__, _, [:System]}, :cmd]}, _, _} = node, acc -> {node, acc ++ [node]}
    node, acc -> {node, acc}
  end)
  Enum.map(commands, fn tree ->
    tree = Macro.prewalk(tree, fn
      {:mode, _, nil} -> "recall-many"
      {{:., _, [Access, :get]}, _, [{:opts, _, nil}, key]} when key in [:sparse, :reappear] -> true
      node -> node
    end)
    tree = Macro.postwalk(tree, fn
      {:if, _, [true, [do: yes, else: _]]} -> yes
      node -> node
    end)
    Macro.to_string(tree)
  end)
end
assert commands.(actual) == commands.(official)
helper = "test/support/native_note_recall_many.exs"
assert File.read!(Path.join([packet,"candidate",helper])) == File.read!(Path.join([packet,"official",helper]))
output = Path.join(packet, "official-wrapper-check/ebin")
File.mkdir_p!(output)
assert {:ok, _, diagnostics} = Kernel.ParallelCompiler.compile_to_path([Path.join([packet,"official",path])],output,return_diagnostics: true)
assert diagnostics == [] or diagnostics == %{compile_warnings: [], runtime_warnings: []}
[test] = Ipse.Session.NativeNoteStrictSourcesRecallTest.__ex_unit__().tests
assert test.tags.recall_many == true and test.tags.recall_strict_sources == true
assert test.tags.timeout == 300_000
if System.get_env("IPSE_TEST_RECALL_MANY") == "1" do
  assert test.tags.skip == false
else
  assert is_binary(test.tags.skip)
end
selection = ExUnit.Filters.eval([:recall_strict_sources], [:test], Map.put(test.tags,:test,test.name), [])
if System.get_env("IPSE_TEST_RECALL_MANY") == "1", do: assert(selection == :ok), else: assert(match?({:skipped, _}, selection))
refute official =~ "assert System.get_env(\"IPSE_TEST_RECALL_KEEP\")"
refute official =~ "save_race"
refute Enum.any?(Application.started_applications(), fn {name,_,_}->name==:ipse end)
IO.puts("official_wrapper_compile=pass optin=#{System.get_env("IPSE_TEST_RECALL_MANY")=="1"} default_skip_correct=true native_commands_ast_equivalent=true helper_bytes_identical=true app_started=false effects=0")
System.halt(0)
