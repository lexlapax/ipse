defmodule Ipse.KnowledgeResearchTransferTest do
  use ExUnit.Case, async: false
  @root Path.expand("../../..", __DIR__)

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-research-transfer-" <> Ipse.Usage.id())
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
          "research",
          "--preset",
          "state-retained"
        ],
        stderr_to_stdout: true,
        env: [{"ERL_FLAGS", "+S 1:1 +A 1"}]
      )

    assert status == 0, output
    refute output =~ "warning:"
    manifest = File.read!(Path.join(artifact, "extension.json"))
    assert byte_size(manifest) <= 16_384
    assert {:ok, _} = Ipse.Extension.Artifact.decode(manifest)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, artifact: artifact}
  end

  defp paths do
    Enum.flat_map(Enum.reject(:code.get_path(), &(&1 == ~c".")), &["-pa", List.to_string(&1)])
  end

  test "provided-only transfer validates independent Store boundaries and Corpus suppression",
       c do
    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        paths() ++
          [
            "-pa",
            Path.join(c.artifact, "ebin"),
            Path.join(@root, "test/support/research_transfer_pure.exs")
          ],
        stderr_to_stdout: true,
        env: [{"ERL_FLAGS", "+S 1:1 +A 1"}]
      )

    assert status == 0, output
    assert output =~ "8 passed"
    refute Code.ensure_loaded?(IpseKnowledge.Research)
    refute Code.ensure_loaded?(IpseKnowledge.Store)
  end

  @tag timeout: 60_000
  test "ordinary approvals retain attributed text, share it with Corpus and preserve forgetting across Sessions",
       c do
    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        paths() ++
          [
            Path.join(@root, "test/support/research_transfer_session.exs"),
            Path.join(c.root, "journey"),
            c.artifact
          ],
        stderr_to_stdout: true,
        env: [{"ERL_FLAGS", "+S 1:1 +A 1"}]
      )

    assert status == 0, output
    assert output =~ "ordinary_state_journey=pass"
    refute Code.ensure_loaded?(IpseKnowledge.Research)
  end
end
