Code.require_file("test/test_helper.exs")
ExUnit.configure(exclude: [:test], include: [:bound_host])
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("test/ipse/session/share_host_job_test.exs")
