defmodule Ipse.MCP.CatalogStdioTest do
  use ExUnit.Case, async: false
  alias Ipse.MCP
  alias Ipse.MCP.Config

  # Real server VMs share runner CPU; keep startup out of the async fixture wave.
  # The configured five-second protocol deadline and all assertions stay intact.
  test "stdio integration supports resource-only and prompt-only capability sets" do
    root = Path.join(System.tmp_dir!(), "ipse-mcp-catalog-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)

    try do
      resource_server = stdio_server(root, "resources_only", ["notes://guide"], [])
      assert {:ok, [resource]} = MCP.discover_server(resource_server, root)
      resource_events = log_events(root)
      refute Enum.any?(resource_events, &(&1["event"] in ["read_resource", "list_prompts"]))

      assert {:ok, result} = MCP.call(resource, %{}, root)
      assert result =~ "A local fixture note."

      prompt_root = Path.join(root, "prompt")
      File.mkdir_p!(prompt_root)
      prompt_server = stdio_server(prompt_root, "prompts_only", [], ["summarize"])
      assert {:ok, [prompt]} = MCP.discover_server(prompt_server, prompt_root)
      refute Enum.any?(log_events(prompt_root), &(&1["event"] == "list_resources"))
      assert {:ok, prompt_result} = MCP.call(prompt, %{"topic" => "privacy"}, prompt_root)
      assert prompt_result =~ "[user]\nSummarize: privacy"
      assert prompt_result =~ "[assistant]\nA concise summary."
    after
      File.rm_rf!(root)
    end
  end

  test "stdio rediscovery detects metadata drift and RPC errors stay unknown" do
    root =
      Path.join(System.tmp_dir!(), "ipse-mcp-catalog-drift-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)

    try do
      drift_server = stdio_server(root, "metadata_drift", ["notes://guide"], [])
      assert {:ok, [resource]} = MCP.discover_server(drift_server, root)
      assert resource.display_name == "Guide"
      File.write!(Path.join(root, "catalog-force-drift"), "drift\n")
      assert {:ok, [changed_resource]} = MCP.discover_server(drift_server, root)
      assert changed_resource.display_name == "Guide changed"
      assert changed_resource.digest != resource.digest
      assert {:error, message} = MCP.call(resource, %{}, root)
      assert message =~ "discovery changed"
      refute Enum.any?(log_events(root), &(&1["event"] == "read_resource"))

      rpc_root = Path.join(root, "rpc")
      File.mkdir_p!(rpc_root)
      rpc_server = stdio_server(rpc_root, "resource_protocol_error", ["notes://guide"], [])
      assert {:ok, [rpc_resource]} = MCP.discover_server(rpc_server, rpc_root)
      assert {:unknown, message} = MCP.call(rpc_resource, %{}, rpc_root)
      assert message =~ "outcome unknown"
      refute message =~ "private fixture detail"
      assert Enum.any?(log_events(rpc_root), &(&1["event"] == "read_resource"))
    after
      File.rm_rf!(root)
    end
  end

  defp stdio_server(root, scenario, resources, prompts) do
    jason_ebin = :code.which(Jason) |> to_string() |> Path.dirname()
    script = Path.expand("../../support/mcp_catalog_server.exs", __DIR__)

    config = %{
      "servers" => [
        %{
          "id" => "notes",
          "command" => System.find_executable("elixir"),
          "args" => ["--erl", "+S 2:2", "-pa", jason_ebin, script, scenario],
          "tools" => [],
          "resources" => resources,
          "prompts" => prompts,
          "env" => %{"PATH" => Path.join(to_string(:code.root_dir()), "bin") <> ":/usr/bin:/bin"},
          "timeout_ms" => 5_000
        }
      ]
    }

    path = Path.join(root, "mcp.json")
    File.write!(path, Jason.encode!(config))
    assert {:ok, [server]} = Config.load(path)
    server
  end

  defp log_events(root) do
    Path.join(root, "catalog.log")
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&Jason.decode!/1)
  end
end
