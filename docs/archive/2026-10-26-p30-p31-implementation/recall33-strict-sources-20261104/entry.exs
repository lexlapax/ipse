import ExUnit.Assertions
[mode] = System.argv()
assert mode in ~w(compile actual)
packet = __DIR__
runtime = Path.expand("../ipse-research-transfer-20261104-01/runtime/lib/ipse", packet)
:ok = Application.load(:ipse)
assert Application.app_dir(:ipse) == runtime
{:ok, modules} = :application.get_key(:ipse, :modules)
assert length(modules) == 241
for module <- modules do
  assert File.regular?(Path.join(runtime, "ebin/" <> Atom.to_string(module) <> ".beam"))
end
assert File.regular?(Path.join(runtime, "ebin/Elixir.Ipse.Extension.Bootstrap.beam"))
{:ok, priv} = Ipse.Workspace.canonical_path(to_string(:code.priv_dir(:ipse)))
assert priv == Path.join(runtime, "priv")
assert File.regular?(Path.join(priv, "ipse-runner"))
assert System.get_env("IPSE_RUNNER_PATH") == Path.join(priv, "ipse-runner")
assert {:ok, bundles} = Ipse.Extension.Bundles.inventory()
assert length(bundles) == 4

helper = Path.join(packet, "candidate/test/support/native_note_recall_many.exs")
body = File.read!(helper)
assert {:ok, _} = Code.string_to_quoted(body)
assert body =~ "if (sparse and step == 2) or (strict_sources and step > 1)"
assert body =~ "assert not strict_sources or (sparse and reappear)"
assert body =~ "assert not strict_sources or provider_timeout == 5_000"
assert body =~ "120_000 -> flunk"
assert body =~ "Enum.reduce(1..33"
assert body =~ "{:managed_preflight_begin, _, \"model\"}"
assert body =~ "note_parts_v1"
assert body =~ "same_id_idle_intents_unchanged"
ExUnit.start(autorun: false, include: [:recall_strict_sources], exclude: [:test], seed: 0, max_cases: 1)
wrapper = Path.join(packet, "candidate/test/ipse/session/native_note_recall_strict_sources_test.exs")
output = Path.join(packet, "wrapper-check/ebin")
File.mkdir_p!(output)
assert {:ok, _, diagnostics} = Kernel.ParallelCompiler.compile_to_path([wrapper], output, return_diagnostics: true)
assert diagnostics == [] or diagnostics == %{compile_warnings: [], runtime_warnings: []}
[test] = Ipse.Session.NativeNoteStrictSourcesRecallTest.__ex_unit__().tests
assert test.tags.recall_strict_sources == true and test.tags.timeout == 300_000
assert :ok = ExUnit.Filters.eval([:recall_strict_sources], [:test], Map.put(test.tags, :test, test.name), [])
assert {:excluded, _} = ExUnit.Filters.eval([:recall_strict_sources], [:test], %{test: :other}, [])
refute Enum.any?(Application.started_applications(), fn {name, _, _} -> name == :ipse end)
IO.puts("private_modules=241 bootstrap_priv=pass bundles=4 strict_wrapper_compile=pass selected_tests=1 app_started=false helper_executed=false")
if mode == "compile", do: System.halt(0)
assert System.get_env("IPSE_RECALL_STRICT_ACTUAL") == "1"
assert System.get_env("IPSE_TEST_RECALL_KEEP") == "1"
assert System.get_env("HOME") != "/home/lexlapax"
{:ok, _} = Application.ensure_all_started(:ipse)
IO.puts("STRICT_RECALL_COHORT_DISPATCH selected=1 private_modules=241")
result = ExUnit.run()
assert result.total - result.excluded - result.skipped == 1
:ok = Application.stop(:ipse)
IO.puts("STRICT_RECALL_COHORT_RESULT failures=#{result.failures} selected=1")
System.halt(if(result.failures == 0, do: 0, else: 1))
