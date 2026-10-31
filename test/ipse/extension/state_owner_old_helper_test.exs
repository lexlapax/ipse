defmodule Ipse.Extension.StateOwnerOldHelperTest do
  use ExUnit.Case, async: false
  @moduletag skip: System.get_env("IPSE_STATE_OLD_HELPER_TEST") != "1"

  test "an older pinned helper refuses State without an unfenced fallback" do
    root = Path.join(System.tmp_dir!(), "ipse-state-old-helper-" <> Ipse.Usage.id())
    namespace = Ipse.JSON.sha256("old-helper-fixture")
    on_exit(fn -> File.rm_rf!(root) end)

    request = %{
      "op" => "state.put",
      "scope" => "project",
      "key" => "note",
      "expected_revision" => 0,
      "value" => %{"v" => 1}
    }

    result = Ipse.Extension.State.execute(root, namespace, request, Ipse.Usage.id())
    assert result in [{:error, :extension_state_unavailable}, {:unknown, %{}}]
    refute File.exists?(Path.join([root, namespace, "state.json"]))
  end
end
