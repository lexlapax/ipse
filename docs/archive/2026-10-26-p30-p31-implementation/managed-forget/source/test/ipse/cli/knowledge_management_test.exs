defmodule Ipse.CLI.KnowledgeManagementTest do
  use ExUnit.Case, async: true
  alias Ipse.CLI.Knowledge.Management

  test "native management cannot widen execution ceilings or explicit effect denial" do
    root = Path.join(System.tmp_dir!(), "ipse-management-denied-" <> Ipse.Usage.id())
    config = %{home: root, headless: false, approval: :ask, approval_origin: :interactive}
    key = "note." <> Ipse.JSON.sha256("synthetic denied target")

    for extra <- [
          %{approval: :deny},
          %{headless: true},
          %{approval_origin: :yes},
          %{execution_mode: :read_only},
          %{execution_mode: :planning},
          %{execution_mode: :draft},
          %{enclosing_mode: :planning}
        ] do
      assert {:error, :knowledge_management_refused} =
               Management.forget(Map.merge(config, extra), root, key)

      refute File.exists?(root)
    end
  end
end
