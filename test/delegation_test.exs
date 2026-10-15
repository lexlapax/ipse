defmodule Ipse.DelegationTest do
  use ExUnit.Case, async: true

  alias Ipse.Delegation

  test "delegation requires explicit host enablement and is disabled for children" do
    refute Delegation.enabled?(%{})
    refute Delegation.enabled?(%{subagents: false})
    refute Delegation.enabled?(%{subagents: true, delegation_origin: "parent"})
    assert Delegation.enabled?(%{subagents: true})
    assert [] = Delegation.definitions(%{subagents: true, delegation_origin: "parent"})

    [tool] = Delegation.definitions(%{subagents: true})
    assert tool["type"] == "function"
    assert tool["function"]["name"] == "delegate"
    schema = tool["function"]["parameters"]
    assert schema["required"] == ["task", "context"]
    assert schema["additionalProperties"] == false
    assert schema["properties"]["task"]["maxLength"] == 8_192
  end

  test "validates exact nonblank UTF-8 task and bounded context" do
    args = %{"task" => "Inspect the failing module", "context" => "Relevant constraints"}
    assert :ok = Delegation.validate(args)
    assert {:error, _} = Delegation.validate(Map.put(args, "extra", "x"))
    assert {:error, _} = Delegation.validate(%{"task" => "  \n", "context" => "x"})
    assert {:error, _} = Delegation.validate(%{"task" => "task", "context" => <<255>>})

    assert {:error, _} =
             Delegation.validate(%{"task" => String.duplicate("x", 8_193), "context" => ""})

    assert {:error, _} =
             Delegation.validate(%{"task" => "task", "context" => String.duplicate("x", 8_193)})

    assert {:error, _} = Delegation.validate(%{"task" => "task"})
  end

  test "approval arguments preserve full JSON values only within bounded shape and bytes" do
    assert :ok = Delegation.validate_approval(%{"nested" => [%{"value" => "full"}]})
    assert {:error, _} = Delegation.validate_approval(%{task: "atom key"})

    deep = Enum.reduce(1..12, "leaf", fn _, value -> [value] end)
    assert {:error, _} = Delegation.validate_approval(%{"deep" => deep})

    many = Map.new(1..129, fn index -> {"k#{index}", index} end)
    assert {:error, _} = Delegation.validate_approval(many)

    oversized = %{"text" => String.duplicate("x", 32_800)}
    assert {:error, _} = Delegation.validate_approval(oversized)
    assert {:error, _} = Delegation.validate_approval(%{"invalid" => <<255>>})
  end

  test "budgets are fixed and child config preserves host routing while removing parent state" do
    assert Delegation.max_calls() == 2
    assert Delegation.max_steps() == 6
    assert Delegation.timeout_ms() == 120_000
    assert Delegation.result_bytes() == 16_384

    parent = %{
      provider: :fixture,
      model: "host-model",
      provider_module: Ipse.Provider.Demo,
      test_pid: self(),
      max_steps: 4,
      subagents: true,
      mcp_servers: [:host_server],
      approval: :allow,
      compact: true,
      transcript: [%{"role" => "user", "content" => "secret parent transcript"}],
      context: "private parent context",
      context_snapshot: [:private_snapshot],
      messages: [%{"role" => "assistant", "content" => "parent message"}],
      tools: [:parent_tools],
      mcp_tools: [:parent_mcp_tools]
    }

    child = Delegation.child_config(parent, "delegation-1")
    assert child.provider == :fixture
    assert child.model == "host-model"
    assert child.provider_module == Ipse.Provider.Demo
    assert child.test_pid == self()
    assert child.max_steps == 4
    assert child.approval == :ask
    assert child.compact == false
    assert child.subagents == false
    assert child.mcp_servers == []
    assert child.delegation_origin == "delegation-1"
    refute Map.has_key?(child, :transcript)
    refute Map.has_key?(child, :context)
    refute Map.has_key?(child, :context_snapshot)
    refute Map.has_key?(child, :messages)
    refute Map.has_key?(child, :tools)
    refute Map.has_key?(child, :mcp_tools)

    assert Delegation.child_config(%{max_steps: 30}, "origin").max_steps == 6
    assert Delegation.child_config(%{max_steps: 2}, "origin").max_steps == 2
    assert Delegation.child_config(%{max_steps: 0}, "origin").max_steps == 6
  end
end
