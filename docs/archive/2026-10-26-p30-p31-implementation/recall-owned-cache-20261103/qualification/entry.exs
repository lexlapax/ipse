runtime = "runtime.path" |> File.read!() |> String.trim()
observer = Path.expand("observer-beam")
Code.prepend_path(observer)

for module <- [Ipse.Test.RecallDiagnosticTrace, Ipse.Test.RecallDiagnostic] do
  Code.ensure_loaded!(module)
  expected = Path.join(observer, Atom.to_string(module) <> ".beam")
  ^expected = module |> :code.which() |> List.to_string() |> Path.expand()
end

app = Path.join(runtime, "_build/test/lib/ipse")
true = Path.expand(Application.app_dir(:ipse)) == app

for module <- [
      Ipse.JSON,
      Ipse.Session,
      Ipse.Session.InferenceDispatch,
      Ipse.Session.ManagedUse,
      Ipse.Session.StoredSources,
      Ipse.Session.SourceReplayCache,
      Ipse.Provider.MintTransport
    ] do
  expected = Path.join([app, "ebin", Atom.to_string(module) <> ".beam"])
  ^expected = module |> :code.which() |> List.to_string() |> Path.expand()
end

{:ok, _} = Application.ensure_all_started(:ipse)

ExUnit.start(
  autorun: false,
  seed: 0,
  exclude: [:test],
  include: [
    test: :"test a source reappearing before model preflight leaves coverage explicitly partial"
  ]
)

Code.require_file("test/ipse/session/native_note_recall_test.exs")
result = ExUnit.run()

if result.total != 5 or result.excluded != 4 or result.skipped != 0 or result.failures != 0,
  do: System.halt(1)
