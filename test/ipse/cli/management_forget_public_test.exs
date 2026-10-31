defmodule Ipse.CLI.ManagementForgetPublicTest do
  use ExUnit.Case, async: true
  alias Ipse.CLI.Knowledge.Management

  test "public forget refuses denied, headless and narrowed modes before touching storage" do
    root = Path.join(System.tmp_dir!(), "ipse-public-forget-mode-" <> Ipse.Usage.id())
    config = %{home: root, headless: false, approval: :ask, approval_origin: :interactive}
    key = "note." <> Ipse.JSON.sha256("synthetic public forget target")

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

  test "public retention refuses denied and headless modes before touching storage" do
    root = Path.join(System.tmp_dir!(), "ipse-session-retention-mode-" <> Ipse.Usage.id())
    config = %{home: root, headless: false, approval: :ask, approval_origin: :interactive}
    key = "note." <> Ipse.JSON.sha256("synthetic session retention target")

    for policy <- [
          %{"kind" => "session"},
          %{"kind" => "pin"},
          %{"kind" => "ordinary"},
          %{"kind" => "duration", "duration_ms" => 86_400_000}
        ],
        extra <- [
          %{approval: :deny},
          %{headless: true},
          %{approval_origin: :yes},
          %{execution_mode: :read_only},
          %{execution_mode: :planning},
          %{execution_mode: :draft},
          %{enclosing_mode: :planning}
        ] do
      assert {:error, :knowledge_management_refused} =
               Management.retain(Map.merge(config, extra), root, key, policy)

      refute File.exists?(root)
    end
  end

  test "private retention effects refuse denied and headless modes before touching storage" do
    root = Path.join(System.tmp_dir!(), "ipse-private-retention-mode-" <> Ipse.Usage.id())
    config = %{home: root, headless: false, approval: :ask, approval_origin: :interactive}
    key = "note." <> Ipse.JSON.sha256("synthetic retention target")

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
               Management.full_facts_retention_effect_candidate(
                 Map.merge(config, extra),
                 root,
                 key,
                 %{"kind" => "pin"},
                 "synthetic"
               )

      refute File.exists?(root)
    end
  end
end
