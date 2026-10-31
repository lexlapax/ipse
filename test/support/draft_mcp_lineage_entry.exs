Code.require_file("test/test_helper.exs")
ExUnit.configure(exclude: [:test], include: [:witnessed_draft_mcp])
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("test/ipse/mcp/catalog_session_test.exs")
