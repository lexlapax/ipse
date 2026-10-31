Code.require_file("test/test_helper.exs")
ExUnit.configure(exclude: [:test], include: [:witnessed_draft_inference])
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("test/ipse/extension/inference_dispatch_session_test.exs")
