ExUnit.start(autorun: false)
Code.require_file("test/test_helper.exs")
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("test/support/collection_document_source_use_suite.exs")
result = ExUnit.run()

if Map.take(result, [:total, :failures, :excluded, :skipped]) !=
     %{total: 19, failures: 0, excluded: 4, skipped: 0},
   do: System.halt(1)

IO.puts("DOCUMENT_SOURCE_USE_CONTROL_PASS 15")
