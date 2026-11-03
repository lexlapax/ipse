# Strict synthetic Session, selected directly without test_helper's HOME override.
root = "/dev/shm/ipse-recall33-saved-window-20261103-01"
app = Path.join(root, "_build/test/lib/ipse")
^app = Application.app_dir(:ipse) |> Path.expand()
for module <- [Ipse.Session, Ipse.Session.Saved, Ipse.Session.SourceWindow, Ipse.Session.ManagedUse, Ipse.Session.ManagedReads, Ipse.Extension.Collection.ObservedRead] do
  expected = Path.join([app, "ebin", Atom.to_string(module) <> ".beam"])
  ^expected = module |> :code.which() |> List.to_string() |> Path.expand()
end
for {relative, expected} <- [
  {"priv/ipse-runner", "ac424d10e2ce6809cedcb157acd70092b00ca68aa7a48201a6007ac5dccbf33b"},
  {"priv/extension-bundles/knowledge/extension.json", "a76b253604abc7c41dbb03cf720b429e668f2b5699d7cd7a6c87f1cebd100a80"}
] do
  ^expected = :sha256 |> :crypto.hash(File.read!(Path.join(app, relative))) |> Base.encode16(case: :lower)
end
"1" = System.fetch_env!("IPSE_TEST_RECALL_MANY")
"1" = System.fetch_env!("IPSE_TEST_RECALL_REQUIRE_SINGLE")
"1" = System.fetch_env!("IPSE_TEST_RECALL_KEEP")
"5000" = System.fetch_env!("IPSE_TEST_RECALL_PROVIDER_TIMEOUT_MS")
{:ok, _} = Application.ensure_all_started(:ipse)
ExUnit.start(autorun: false, seed: 0, exclude: [:test], include: [test: :"test a source reappearing before model preflight leaves coverage explicitly partial"])
Code.require_file("test/ipse/session/native_note_recall_test.exs")
result = ExUnit.run()
if result.total != 5 or result.excluded != 4 or result.skipped != 0 or result.failures != 0, do: System.halt(1)
