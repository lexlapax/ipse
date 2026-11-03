# Test-only entry point: the existing strict fixture, without test_helper.
root = "/dev/shm/ipse-recall33-combined-dcbb-20261103-01"
app = Path.join(root, "_build/test/lib/ipse")
true = Path.expand(Application.app_dir(:ipse)) == app
for module <- [Ipse.Session, Ipse.Session.ManagedUse, Ipse.Session.ManagedReads, Ipse.Extension.Collection.ObservedRead] do
  expected = Path.join([app, "ebin", Atom.to_string(module) <> ".beam"])
  ^expected = module |> :code.which() |> List.to_string() |> Path.expand()
end
for {relative, expected} <- [
      {"priv/ipse-runner", "ac424d10e2ce6809cedcb157acd70092b00ca68aa7a48201a6007ac5dccbf33b"},
      {"priv/extension-bundles/knowledge/extension.json", "7fb2aba55b8ad19a267fd6804a423d38c994611b8bba3b75776328dbf5f835fb"}
    ] do
  actual = :sha256 |> :crypto.hash(File.read!(Path.join(app, relative))) |> Base.encode16(case: :lower)
  ^expected = actual
end
{:ok, _} = Application.ensure_all_started(:ipse)
ExUnit.start(
  autorun: false,
  seed: 0,
  exclude: [:test],
  include: [test: :"test a source reappearing before model preflight leaves coverage explicitly partial"]
)
Code.require_file("test/ipse/session/native_note_recall_test.exs")
result = ExUnit.run()
if result.total != 5 or result.excluded != 4 or result.skipped != 0 or result.failures != 0, do: System.halt(1)
