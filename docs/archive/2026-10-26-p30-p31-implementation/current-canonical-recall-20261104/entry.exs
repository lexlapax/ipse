runtime = "/home/lexlapax/projects/lexlapax/ipse/_build/verification/regression-groups-frozen-20261104-02/serial/source"
app = Path.join(runtime, "_build/test/lib/ipse")
true = Path.expand(Application.app_dir(:ipse)) == app
for module <- [Ipse.JSON, Ipse.Session, Ipse.Runner, Ipse.Extension.Bootstrap, Ipse.Session.ManagedUse, Ipse.Session.ManagedLineage, Ipse.Session.SourceWindow] do
  {:module, ^module} = Code.ensure_loaded(module)
  true = Path.expand(to_string(:code.which(module))) == Path.join([app, "ebin", Atom.to_string(module) <> ".beam"])
end
{:ok, _} = Application.ensure_all_started(:ipse)
ExUnit.start(autorun: false, seed: 0, max_cases: 1, exclude: [:test], include: [test: :"test a fresh Session recalls 33 short, natively reviewed notes"])
Code.require_file("test/ipse/session/native_note_recall_test.exs", __DIR__)
result = ExUnit.run()
File.write!(Path.join(__DIR__, "result.json"), Jason.encode!(result), [:exclusive])
if result.total != 5 or result.excluded != 4 or result.skipped != 0 or result.failures != 0, do: System.halt(1)
