defmodule Ipse.DelegationTest do
  use ExUnit.Case, async: true

  alias Ipse.Tools.Delegation

  test "admission checks host enablement and remaining children before identity and routing" do
    args = %{"task" => "Inspect a module", "context" => "Selected context"}
    call = %{"id" => "delegation-call"}
    config = %{subagents: true}

    assert {:error, "Delegation is disabled by the host."} =
             Delegation.admit(%{}, 2, %{}, %{})

    assert {:error, "Delegation is disabled by the host."} =
             Delegation.admit(Map.put(config, :delegation_origin, "parent"), 0, call, args)

    assert {:error, "Delegation limit reached for this turn."} =
             Delegation.admit(config, 2, %{}, %{})

    for id <- [nil, 42, String.duplicate("x", 257)] do
      assert {:error, "Invalid delegation call identity."} =
               Delegation.admit(config, 0, %{"id" => id}, args)
    end

    assert :ok = Delegation.admit(config, 1, call, args)
    assert :ok = Delegation.admit(config, 0, %{"id" => String.duplicate("x", 256)}, args)

    assert {:error, "Delegation role is not configured; no provider fallback was attempted."} =
             Delegation.admit(config, 0, call, Map.put(args, "role", "review"))
  end

  test "parallel admission reserves two children and validates every requested route" do
    task = %{"task" => "Inspect a module", "context" => "Selected context"}
    args = %{"tasks" => [task, task]}
    config = %{subagents: true, subagent_concurrency: 2}
    refused = {:error, "Parallel delegation is disabled or its child budget is exhausted."}

    assert :ok = Delegation.admit_parallel(config, 0, args)
    assert ^refused = Delegation.admit_parallel(config, 1, args)
    assert ^refused = Delegation.admit_parallel(%{subagents: true}, 0, args)

    assert ^refused =
             Delegation.admit_parallel(Map.put(config, :delegation_origin, "parent"), 0, args)

    assert {:error, _} = Delegation.admit_parallel(config, 0, %{"tasks" => [task]})

    assert {:error, "Delegation role is not configured; no provider fallback was attempted."} =
             Delegation.admit_parallel(config, 0, %{
               "tasks" => [task, Map.put(task, "role", "review")]
             })
  end

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

  test "children retain parent ceilings while broad yes still requires separate child approval" do
    for config <- [
          %{approval: :allow, approval_origin: :yes, headless: true},
          %{approval: :deny, approval_origin: :default_headless, headless: true}
        ] do
      parent =
        Map.merge(config, %{
          semantic_pin: %{"private" => true},
          semantic_admission: %{"pin" => %{"private" => true}}
        })

      child = Delegation.child_config(parent, "origin")

      assert child.approval == :ask and child.approval_origin == "explicit"
      assert child.headless
      refute Map.has_key?(child, :semantic_pin)
      refute Map.has_key?(child, :semantic_admission)
      assert {:ok, mode} = Ipse.Extension.Mode.capture(child)
      assert Ipse.Extension.Mode.valid?(mode)
    end

    for config <- [
          %{approval: :deny},
          %{execution_mode: :planning},
          %{execution_mode: :draft, enclosing_mode: :read_only},
          %{knowledge_ceiling: :disabled}
        ] do
      child = Delegation.child_config(config, "origin")
      assert {:ok, mode} = Ipse.Extension.Mode.capture(child)
      assert {:error, _} = Ipse.Extension.Mode.knowledge(mode, "collection.publish")

      if config[:knowledge_ceiling] != :disabled,
        do: assert(:deny == Ipse.Extension.Mode.ordinary(mode, true))
    end
  end
end
