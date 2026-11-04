root = Path.expand(".")
for module <- [Ipse.Session, Ipse.Session.Resources, Ipse.Session.WorkspaceAcquisition,
               Ipse.Extension.CollectionStore, Ipse.Extension.Collection.DocumentStage,
               Ipse.Extension.Collection.WorkspaceDocumentGuard] do
  {:module, ^module} = Code.ensure_loaded(module)
  expected = Path.join([root, "_build/test/lib/ipse/ebin", Atom.to_string(module) <> ".beam"])
  true = Path.expand(List.to_string(:code.which(module))) == expected
end
true = Path.expand(Application.app_dir(:ipse)) == Path.join(root, "_build/test/lib/ipse")
ExUnit.start(autorun: false, seed: 0)
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("test/ipse/session/workspace_acquisition_test.exs")
Code.require_file("test/ipse/extension/collection/workspace_document_guard_test.exs")
Code.require_file("test/ipse/session/resources_authority_test.exs")
Code.require_file("test/ipse/session/workspace_snapshot_binding_test.exs")
result = ExUnit.run()
if result.total != 16 or result.failures != 0, do: System.halt(1)
