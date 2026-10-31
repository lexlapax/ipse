Code.require_file("test/test_helper.exs")
ExUnit.configure(exclude: [:test], include: [:witnessed_draft_lineage])
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("test/ipse/extension/session_test.exs")
