[root, scenario] = System.argv()

kind =
  Map.fetch!(
    %{
      "save_managed_approval_root_write" => "write",
      "save_managed_approval_root_shell" => "shell",
      "save_managed_approval_root_mcp" => "mcp"
    },
    scenario
  )

System.put_env("IPSE_TEST_NATIVE_ROOT_APPROVAL", "1")
System.put_env("IPSE_TEST_NATIVE_ROOT_APPROVAL_ROOT", root)
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("../test_helper.exs", __DIR__)

ExUnit.configure(
  autorun: false,
  exclude: [:test],
  include: [native_root_approval: kind],
  max_cases: 1,
  seed: 791_678
)

Code.require_file("../ipse/extension/managed_collection_call_session_test.exs", __DIR__)
result = ExUnit.run()
if result.failures == 0, do: IO.puts("NATIVE_ROOT_APPROVAL_#{String.upcase(kind)}_PASSED")
System.halt(if(result.failures == 0, do: 0, else: 2))
