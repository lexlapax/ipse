[selection, root, scenario] = System.argv()

allowed =
  ~w(write shell mcp) ++
    for(
      kind <- ~w(write shell mcp),
      boundary <- ~w(root_change revoke expiry owner_loss),
      do: kind <> "_" <> boundary
    )

true = selection in allowed

expected =
  if String.ends_with?(selection, "_owner_loss"),
    do: "save_managed_approval_owner_loss",
    else: "save_managed_approval_root_" <> selection

true = scenario == expected

System.put_env("IPSE_TEST_NATIVE_ROOT_APPROVAL", "1")
System.put_env("IPSE_TEST_NATIVE_ROOT_APPROVAL_ROOT", root)
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("../test_helper.exs", __DIR__)

ExUnit.configure(
  autorun: false,
  exclude: [:test],
  include: [native_root_approval: selection],
  max_cases: 1,
  seed: 791_678
)

Code.require_file("../ipse/extension/managed_collection_call_session_test.exs", __DIR__)
result = ExUnit.run()
if result.failures == 0, do: IO.puts("NATIVE_ROOT_APPROVAL_#{String.upcase(selection)}_PASSED")
System.halt(if(result.failures == 0, do: 0, else: 2))
