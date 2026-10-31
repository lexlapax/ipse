Code.prepend_paths(Path.wildcard(Path.expand("_build/document-inventory-sol-20261029/lib/*/ebin")))
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("test/test_helper.exs")
tag = case System.argv() do
  ["pure"] -> :document_inventory_pure
  ["native"] -> :document_inventory_native
  ["session"] -> :document_inventory_session
end
ExUnit.configure(autorun: false, exclude: [:test], include: [tag], seed: 47080, max_cases: 1)
Code.require_file(if tag == :document_inventory_session, do: "test/ipse/extension/collection_store_session_test.exs", else: "test/ipse/extension/collection_document_inventory_test.exs")
result = ExUnit.run()
System.halt(if result.failures == 0, do: 0, else: 2)
