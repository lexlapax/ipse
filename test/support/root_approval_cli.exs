[selection, root, scenario] = System.argv()

allowed =
  ~w(nested_native nested_native_deny nested_native_root_change helper_embedding helper_embedding_deny helper_embedding_root_change helper_model helper_model_deny helper_model_root_change helper_decision helper_decision_deny helper_decision_root_change helper_decision_experiment helper_decision_experiment_deny helper_decision_experiment_root_change nested_mcp nested_mcp_root_change nested_mcp_revoke nested_mcp_deny nested_mcp_stale_token nested_mcp_cancel nested_mcp_owner_loss write shell mcp http mcp_pinned http_revoke http_expiry http_lost_start http_held_loss mcp_held_loss shell_running_revoke shell_running_kill mcp_start_revoke http_start_revoke) ++
    for(
      kind <- ~w(write shell mcp),
      boundary <- ~w(root_change revoke expiry owner_loss),
      do: kind <> "_" <> boundary
    )

true = selection in allowed

expected =
  cond do
    String.ends_with?(selection, "_owner_loss") ->
      "save_managed_approval_owner_loss"

    selection in ~w(nested_native_deny helper_embedding_deny helper_model_deny helper_decision_deny helper_decision_experiment_deny) ->
      "save_managed_approval_deny"

    selection in ~w(nested_mcp_deny nested_mcp_stale_token nested_mcp_cancel) ->
      "save_managed_approval_" <> String.replace_prefix(selection, "nested_mcp_", "")

    true ->
      "save_managed_approval_root_" <> selection
  end

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
