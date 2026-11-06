defmodule Ipse.KnowledgeGraphMCPGenerationTest do
  use ExUnit.Case, async: false
  @root Path.expand("../../..", __DIR__)

  test "MCP graph generation fences account for bounded probe calls" do
    paths =
      :code.get_path()
      |> Enum.reject(&(&1 == ~c"."))
      |> Enum.flat_map(&["-pa", List.to_string(&1)])

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        paths ++ [Path.join(@root, "test/support/graph_mcp_generation.exs")],
        cd: @root,
        stderr_to_stdout: true,
        env: [{"ERL_FLAGS", "+S 1:1 +A 1"}]
      )

    assert status == 0, output
    assert output =~ "graph_mcp_generation=pass"
  end
end
