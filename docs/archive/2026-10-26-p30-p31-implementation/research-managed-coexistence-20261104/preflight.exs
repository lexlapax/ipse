:ok = Application.load(:ipse)
cohort = __DIR__
runtime = Path.expand("../cohort-01/runtime/lib", cohort)
true = Application.app_dir(:ipse) == Path.join(runtime, "ipse")
modules = Application.spec(:ipse, :modules)
241 = length(modules)
for module <- modules do
  {:module, ^module} = Code.ensure_loaded(module)
  true = String.starts_with?(List.to_string(:code.which(module)), Path.join(runtime, "ipse/ebin/") )
end
for dir <- Path.wildcard(Path.join(runtime, "*")) do
  [appfile] = Path.wildcard(Path.join(dir, "ebin/*.app"))
  {:ok, [{:application, app, _}]} = :file.consult(String.to_charlist(appfile))
  true = Application.app_dir(app, "ebin") == Path.join(dir, "ebin")
end
helper = Path.join(runtime, "ipse/priv/ipse-runner")
%{type: :regular, links: 1} = File.lstat!(helper)
true = File.stat!(helper).mode |> Bitwise.band(0o111) |> Kernel.!=(0)
true = to_string(:code.priv_dir(:ipse)) == Path.join(runtime, "ipse/priv")
true = String.starts_with?(to_string(:code.which(Ipse.Extension.Bootstrap)), runtime)
{:ok, bundles} = Ipse.Extension.Bundles.inventory()
~w(corpus-collection-documents corpus-state-documents knowledge knowledge-decision-shadow) = Enum.map(bundles, & &1.id)
for path <- Path.wildcard(runtime <> "/**/*", match_dot: true), File.regular?(path), do: %{type: :regular, links: 1} = File.lstat!(path)
ExUnit.start(autorun: false)
source = Path.join(cohort, "source/test/extensions/knowledge/research_transfer_test.exs")
Code.require_file(source)
tests = Ipse.KnowledgeResearchTransferTest.__ex_unit__().tests
[test] = Enum.filter(tests, &(&1.tags[:mixed_h1_coexistence] == true))
120_000 = test.tags.timeout
expected_skip = System.get_env("IPSE_TEST_RESEARCH_MIXED") != "1"
true = if expected_skip, do: is_binary(test.tags.skip), else: test.tags.skip == false
expected_result = if expected_skip, do: {:skipped, test.tags.skip}, else: :ok
^expected_result = ExUnit.Filters.eval([mixed_h1_coexistence: true], [:test], Map.put(test.tags, :test, test.name), [])
false = Enum.any?(Application.started_applications(), fn {name, _, _} -> name == :ipse end)
false = Code.ensure_loaded?(IpseKnowledge.Research)
IO.puts("complete_private_app_modules=241 dependency_apps=16 Bootstrap=private helper=private_regular_executable bundles=4 declared_mixed_case=1 native_selected=#{if expected_skip, do: 0, else: 1} skip=#{expected_skip} timeout_ms=120000 app_started=false native_calls=0 tests_run=0")
