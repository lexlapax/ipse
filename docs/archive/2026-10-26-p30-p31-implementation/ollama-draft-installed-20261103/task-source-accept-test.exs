# Focused source-acceptance control without test_helper's HOME assignment.
root = Path.expand(".")
app = Path.join(root, "_build/test/lib/ipse")
^app = Application.app_dir(:ipse) |> Path.expand()
for module <- [Ipse.Session, Ipse.Session.Draft, Ipse.Session.DraftNative, Ipse.Provider.Ollama, Ipse.Session.Saved] do
  expected = Path.join([app, "ebin", Atom.to_string(module) <> ".beam"])
  ^expected = module |> :code.which() |> List.to_string() |> Path.expand()
end
{:ok, _} = Application.ensure_all_started(:ipse)
ExUnit.start(autorun: false, seed: 0, exclude: [:test],
  include: [test: :"test native enhance command retains exact input and rejects a stale ID before acceptance"])
Code.require_file("test/ipse/session/draft_acceptance_test.exs")
result = ExUnit.run()
if result.total != 9 or result.excluded != 8 or result.skipped != 0 or result.failures != 0,
  do: System.halt(1)
