Code.prepend_paths(Path.wildcard(Path.expand("_build/managed-review-followup-sol-20261029/lib/*/ebin")))
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("test/test_helper.exs")
selection = if false,
  do: [], else: [ordinary_publication_deadline: true]
ExUnit.configure(autorun: false, exclude: [:test], include: selection, seed: 46872)
Code.require_file("test/ipse/extension/managed_collection_call_session_test.exs")
result = ExUnit.run()
System.halt(if result.failures == 0, do: 0, else: 2)
