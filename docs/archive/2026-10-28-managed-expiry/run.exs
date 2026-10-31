graph = "_build/managed-expiry-sol-20261028"
Code.prepend_paths(Path.wildcard(graph <> "/build/lib/*/ebin"))
Mix.start()
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("test/test_helper.exs")
include = if System.argv() == ["--native-only"], do: [:managed_expiry_native], else: [:managed_expiry]
ExUnit.configure(autorun: false, exclude: [:test], include: include, seed: 46805,
  max_cases: 1)
Code.require_file("test/ipse/extension/collection_expiry_native_test.exs")
Code.require_file("test/ipse/extension/collection_managed_retention_test.exs")
result = ExUnit.run()
System.halt(if result.failures == 0, do: 0, else: 1)
