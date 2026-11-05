defmodule Ipse.KnowledgeGraphCaptureTest do
  use ExUnit.Case, async: false
  @root Path.expand("../../..", __DIR__)

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-graph-capture-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    artifact = Path.join(root, "artifact")

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        [
          "extensions/knowledge/build.exs",
          "--sdk",
          Application.app_dir(:ipse, "ebin"),
          "--output",
          artifact,
          "--package",
          "graph",
          "--preset",
          "state-explicit"
        ],
        cd: @root,
        stderr_to_stdout: true,
        env: [{"ERL_FLAGS", "+S 1:1 +A 1"}]
      )

    assert status == 0, output
    refute output =~ "warning:"

    assert {:ok, _} =
             Ipse.Extension.Artifact.decode(File.read!(Path.join(artifact, "extension.json")))

    %{root: root, artifact: artifact}
  end

  test "main-model stored-source capture protocol preserves evidence and lifecycle fences" do
    paths =
      :code.get_path()
      |> Enum.reject(&(&1 == ~c"."))
      |> Enum.flat_map(&["-pa", List.to_string(&1)])

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        paths ++ [Path.join(@root, "test/support/graph_main_capture.exs")],
        cd: @root,
        stderr_to_stdout: true,
        env: [{"ERL_FLAGS", "+S 1:1 +A 1"}]
      )

    assert status == 0, output
    assert output =~ "graph_identity_protocol=pass"
    refute Code.ensure_loaded?(IpseKnowledge.Graph)
    refute Code.ensure_loaded?(IpseKnowledge.Store)
  end

  @tag timeout: 60_000
  test "ordinary main-tool approvals, stale generation, denial and owner-loss replay boundary",
       c do
    paths =
      :code.get_path()
      |> Enum.reject(&(&1 == ~c"."))
      |> Enum.flat_map(&["-pa", List.to_string(&1)])

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        paths ++
          [
            Path.join(@root, "test/support/graph_capture_session.exs"),
            Path.join(c.root, "journey"),
            c.artifact
          ],
        cd: @root,
        stderr_to_stdout: true,
        env: [{"ERL_FLAGS", "+S 1:1 +A 1"}]
      )

    assert status == 0, output
    assert output =~ "graph_state_main_tool=pass"
    refute Code.ensure_loaded?(IpseKnowledge.Graph)
    refute Code.ensure_loaded?(IpseKnowledge.Store)
  end
end
