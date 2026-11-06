ExUnit.start(autorun: false)
Code.require_file("test/test_helper.exs")
ExUnit.configure(exclude: [:test], include: [:witnessed_draft_mcp])
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("test/ipse/mcp/catalog_session_test.exs")
result = ExUnit.run()

if Map.take(result, [:total, :failures, :excluded, :skipped]) !=
     %{total: 10, failures: 0, excluded: 9, skipped: 0},
   do: System.halt(1)

IO.puts("WITNESSED_DRAFT_CONTROL_PASS")
