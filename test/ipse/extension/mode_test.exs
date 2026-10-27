defmodule Ipse.Extension.ModeTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.Mode

  test "default headless denial is explicit and grants no ordinary mutation" do
    assert {:ok, mode} = Mode.capture(%{approval: :deny, approval_origin: :default_headless})
    assert :ok = Mode.knowledge(mode, "collection.publish")
    assert :deny = Mode.ordinary(mode, true)
    assert :not_required = Mode.ordinary(mode, false)
    assert {:error, _} = Mode.knowledge(mode, "tool.call")
    assert {:error, _} = Mode.knowledge(mode, "mcp.call")
    assert {:error, _} = Mode.knowledge(mode, "service.call")
  end

  test "legacy or explicit deny cannot be inferred as default headless" do
    for config <- [%{approval: :deny}, %{approval: :deny, approval_origin: :explicit}] do
      assert {:ok, mode} = Mode.capture(config)
      assert {:error, :knowledge_mode_denied} = Mode.knowledge(mode, "collection.publish")
    end
  end

  test "broad yes cannot override pause, disabled, or an active or enclosing ceiling" do
    for ceiling <- [:read_only, :planning, :draft], field <- [:execution_mode, :enclosing_mode] do
      config = Map.put(%{approval: :allow, approval_origin: :yes}, field, ceiling)
      assert {:ok, mode} = Mode.capture(config)
      assert :ok = Mode.knowledge(mode, "collection.read")

      for effect <- Mode.classes() -- ["collection.read"] do
        assert {:error, :knowledge_mode_denied} = Mode.knowledge(mode, effect)
      end

      assert :deny = Mode.ordinary(mode, true)
    end

    for ceiling <- [:paused, :disabled] do
      assert {:ok, mode} = Mode.capture(%{approval: :allow, knowledge_ceiling: ceiling})
      assert {:error, :knowledge_disabled} = Mode.knowledge(mode, "collection.read")
    end
  end

  test "closed schema rejects malformed, float, contradictory, and unknown mode data" do
    assert {:ok, mode} = Mode.capture(%{})

    for value <- [
          nil,
          %{},
          Map.put(mode, "version", 1.0),
          Map.put(mode, "extra", true),
          Map.put(mode, "approval", "unknown"),
          Map.put(mode, "ceiling", "unknown"),
          %{mode | "approval_origin" => "default_headless"},
          %{mode | "approval_origin" => "yes"}
        ] do
      refute Mode.valid?(value)
      assert {:error, _} = Mode.knowledge(value, "collection.publish")
      assert :deny = Mode.ordinary(value, true)
    end
  end

  test "resume and child inheritance retain saved explicit restrictions despite CLI yes" do
    for ceiling <- [:read_only, :planning, :draft] do
      assert {:ok, saved} = Mode.capture(%{execution_mode: ceiling})
      assert {:ok, resumed} = Mode.inherit(saved, %{approval: :allow, approval_origin: :yes})
      assert :deny = Mode.ordinary(resumed, true)
      assert {:error, _} = Mode.knowledge(resumed, "collection.publish")
      assert {:ok, child} = Mode.inherit(resumed, %{approval: :allow, approval_origin: :yes})
      assert :deny = Mode.ordinary(child, true)
    end

    assert {:ok, denied} = Mode.capture(%{approval: :deny})
    assert {:ok, retained} = Mode.inherit(denied, %{approval: :allow, approval_origin: :yes})
    assert retained["approval"] == "deny" and retained["approval_origin"] == "explicit"
    assert {:ok, headless} = Mode.capture(%{approval: :deny, approval_origin: :default_headless})

    assert {:ok, interactive} =
             Mode.inherit(headless, %{approval: :ask, approval_origin: :interactive})

    assert Mode.valid?(interactive) and not interactive["headless"]
    assert interactive["approval"] == "ask"
  end
end
