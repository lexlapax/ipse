ExUnit.start(autorun: false, max_cases: 1, timeout: 180_000, seed: 0, exclude: [p30_pending_output_revocation: true])
base = Path.expand("..", __DIR__)
File.write!(Path.join(__DIR__, "beam.pid"), System.pid() <> "\n")
:ok = Application.load(:ipse)
runtime = Path.join(base, "execution-01/lib")
app = Path.join(runtime, "ipse")
true = Application.app_dir(:ipse, "ebin") == Path.join(app, "ebin")
modules = Application.spec(:ipse, :modules)
true = length(modules) > 0
for module <- modules,
    do: true = File.regular?(Path.join(app, "ebin/#{module}.beam"))
for module <- [Ipse.Session, Ipse.Runner, Ipse.Extension.Bootstrap] do
  {:module, ^module} = Code.ensure_loaded(module)
  true = Path.dirname(to_string(:code.which(module))) == Path.join(app, "ebin")
end
%{type: :regular, links: 1} = File.lstat!(Path.join(app, "priv/ipse-runner"))
for name <- File.ls!(runtime) do
  {:ok, [{:application, dependency, _}]} =
    :file.consult(String.to_charlist(Path.join([runtime, name, "ebin", name <> ".app"])))
  true = Application.app_dir(dependency, "ebin") ==
    Path.join([runtime, name, "ebin"])
end
IO.puts("P30_COMPLETE_APP_CLOSURE_PASSED modules=#{length(modules)}")
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file(Path.join(base, "source-v2/test/extensions/knowledge/pending_assessment_current_use_test.exs"))
result = ExUnit.run()
File.write!(Path.join(__DIR__, "result.json"), Jason.encode!(result))
System.halt(if result == %{total: 2, failures: 0, skipped: 0, excluded: 1}, do: 0, else: 2)
