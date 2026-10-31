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

  test "planning-read mode preserves approval and cannot widen read-only ceilings" do
    for ceiling <- [:draft, :planning], approval <- [:ask, :allow, :deny] do
      assert {:ok, mode} = Mode.capture(%{execution_mode: ceiling, approval: approval})
      assert Mode.planning_read(mode) == approval
      assert :deny = Mode.ordinary(mode, true)

      assert {:ok, restricted} =
               Mode.capture(%{
                 execution_mode: ceiling,
                 enclosing_mode: :read_only,
                 approval: approval
               })

      assert :deny = Mode.planning_read(restricted)
    end

    assert {:ok, normal} = Mode.capture(%{approval: :allow})
    assert :deny = Mode.planning_read(normal)

    assert {:ok, headless} =
             Mode.capture(%{
               execution_mode: :planning,
               approval: :deny,
               approval_origin: :default_headless
             })

    assert :deny = Mode.planning_read(headless)
    assert :deny = Mode.planning_read(%{})
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

  test "same-owner resume keeps local and inherited planning separate while children inherit both" do
    assert {:ok, local} = Mode.capture(%{execution_mode: :planning})
    assert {:ok, inherited} = Mode.capture(%{enclosing_mode: :planning})
    assert {:ok, resumed_local} = Mode.resume(local, %{approval: :allow, approval_origin: :yes})

    assert {:ok, resumed_inherited} =
             Mode.resume(inherited, %{approval: :allow, approval_origin: :yes})

    assert resumed_local["ceiling"] == "planning" and
             resumed_local["enclosing_ceiling"] == "normal"

    assert resumed_inherited["ceiling"] == "normal" and
             resumed_inherited["enclosing_ceiling"] == "planning"

    assert :deny == Mode.ordinary(resumed_local, true)
    assert :deny == Mode.ordinary(resumed_inherited, true)

    for parent <- [resumed_local, resumed_inherited] do
      assert {:ok, child} = Mode.inherit(parent, %{approval: :allow, approval_origin: :yes})
      assert child["enclosing_ceiling"] == "planning"
      assert :deny == Mode.ordinary(child, true)
    end

    assert {:ok, combined} =
             Mode.resume(local, %{
               execution_mode: :normal,
               enclosing_mode: :read_only,
               knowledge_ceiling: :disabled
             })

    assert combined["ceiling"] == "planning" and combined["enclosing_ceiling"] == "read_only"
    assert combined["knowledge"] == "disabled"
    refute Mode.resumed?(local, %{resumed_local | "ceiling" => "normal"})
    refute Mode.resumed?(inherited, %{resumed_inherited | "enclosing_ceiling" => "normal"})
  end
end
