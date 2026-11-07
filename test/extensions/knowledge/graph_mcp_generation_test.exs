defmodule Ipse.KnowledgeGraphMCPGenerationTest do
  use ExUnit.Case, async: false
  @root Path.expand("../../..", __DIR__)

  test "MCP graph generation fences account for bounded probe calls" do
    paths =
      for module <- [Ipse.Extension, Jason, JSONSchex, ExJSONPointer],
          path = module |> :code.which() |> to_string() |> Path.dirname(),
          do: ["-pa", path]

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        List.flatten(paths) ++ [Path.join(@root, "test/support/graph_mcp_generation.exs")],
        cd: @root,
        stderr_to_stdout: true,
        env: [{"ERL_FLAGS", "+S 1:1 +A 1"}]
      )

    assert status == 0, output
    assert output =~ "graph_mcp_generation=pass"
    refute output =~ "redefining module Ipse.Development.Fixtures.Knowledge"
  end
end
