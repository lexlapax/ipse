root = Path.expand(".")
for module <- [Ipse.Session, Ipse.Session.WorkspaceAcquisition, Ipse.Session.SourceWindow,
               Ipse.Extension.WorkspaceSnapshot, Ipse.Extension.Collection.DocumentStage,
               Ipse.Extension.Collection.WorkspaceDocumentGuard, Ipse.Extension.Bundles] do
  {:module, ^module} = Code.ensure_loaded(module)
  expected = Path.join([root, "_build/test/lib/ipse/ebin", Atom.to_string(module) <> ".beam"])
  true = Path.expand(List.to_string(:code.which(module))) == expected
end
true = Path.expand(Application.app_dir(:ipse)) == Path.join(root, "_build/test/lib/ipse")
{:ok, bundles} = Ipse.Extension.Bundles.inventory()
%{digest: digest} = Enum.find(bundles, &(&1.id == "corpus-collection-documents"))
true = is_binary(digest)
IO.puts("SHIPPED_CORPUS_SHA256=" <> digest)
ExUnit.start(autorun: false, seed: 0, exclude: [:test],
  include: [test: :"test cancellation during dormant document-effect registration withholds publication"])
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("test/support/resume_assertions.exs")
Code.require_file("/dev/shm/ipse-word-larger-proof-20261103-01/peer-cancel-fixture.exs")
result = ExUnit.run()
if result.total - result.excluded != 1 or result.failures != 0 or result.skipped != 0 do
  IO.inspect(Map.take(result, [:total, :excluded, :skipped, :failures]), label: "unexpected test result")
  System.halt(1)
end
