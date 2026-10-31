graph = "_build/retention-deadline-sol-20261028"
Code.prepend_paths(Path.wildcard(graph <> "/build/lib/*/ebin"))
Mix.start()
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("test/test_helper.exs")
ExUnit.configure(autorun: false, exclude: [:test], include: [:retention_deadline_fence], seed: 46803,
  max_cases: 1)
Code.require_file("test/ipse/runner/transaction_deadline_test.exs")
Code.require_file("test/ipse/session/managed_retention_native_test.exs")
result = ExUnit.run()
System.halt(if result.failures == 0, do: 0, else: 1)
