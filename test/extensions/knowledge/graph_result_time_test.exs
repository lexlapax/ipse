defmodule Ipse.KnowledgeGraphResultTimeTest do
  use ExUnit.Case, async: false
  @root Path.expand("../../..", __DIR__)

  test "Graph samples current eligibility after preparing an inline or paged result" do
    paths =
      for module <- [Ipse.Extension, Jason, JSONSchex, ExJSONPointer],
          path = module |> :code.which() |> to_string() |> Path.dirname(),
          do: ["-pa", path]

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        List.flatten(paths) ++ [Path.join(@root, "test/support/graph_result_time.exs")],
        cd: @root,
        stderr_to_stdout: true,
        env: [{"ERL_FLAGS", "+S 1:1 +A 1"}]
      )

    assert status == 0, output
    assert output =~ "graph_result_time=pass"
    refute Code.ensure_loaded?(IpseKnowledge.Graph)
  end
end
