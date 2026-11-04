root = Path.expand(".")
for module <- [Ipse.Session, Ipse.Session.Resources, Ipse.Session.WorkspaceAcquisition,
               Ipse.Extension.CollectionStore, Ipse.Extension.Collection.DocumentStage,
               Ipse.Extension.Collection.WorkspaceDocumentGuard, Ipse.Extension.Bundles] do
  {:module, ^module} = Code.ensure_loaded(module)
  expected = Path.join([root, "_build/test/lib/ipse/ebin", Atom.to_string(module) <> ".beam"])
  true = Path.expand(List.to_string(:code.which(module))) == expected
end
true = Path.expand(Application.app_dir(:ipse)) == Path.join(root, "_build/test/lib/ipse")
nil = System.get_env("IPSE_TEST_WORD_SHIPPED")
{:ok, bundles} = Ipse.Extension.Bundles.inventory()
%{digest: digest} = Enum.find(bundles, &(&1.id == "corpus-collection-documents"))
IO.puts("SHIPPED_CORPUS_SHA256=" <> digest)
ExUnit.start(autorun: false, seed: 0, max_failures: 1, exclude: [:test],
  include: [workspace_word_native: true,
    test: :"test public Collection preset authenticates paused Word storage and returns typed selected citation",
    test: :"test public Collection provided source continues without extra authority and old presets keep grants"])
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("test/support/resume_assertions.exs")
Code.require_file("test/extensions/knowledge/document_acquisition_session_test.exs")
result = ExUnit.run()
if result.total - result.excluded != 6 or result.failures != 0 or result.skipped != 0 do
  IO.inspect(Map.take(result, [:total, :excluded, :skipped, :failures]), label: "unexpected test result")
  System.halt(1)
end
