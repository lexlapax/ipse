Code.require_file("../../support/research_managed_wire.exs", __DIR__)

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
    if System.get_env("IPSE_TEST_RESEARCH_KEEP") != "1", do: on_exit(fn -> File.rm_rf!(root) end)
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

  @tag skip:
         if(System.get_env("IPSE_TEST_RESEARCH_MIXED") == "1",
           do: false,
           else: "explicit native mixed Research fixture required"
         )
  @tag mixed_h1_coexistence: true
  @tag timeout: 120_000
  test "explicit provided retention coexists with managed recall and refuses a managed State tool write",
       c do
    root = Path.join(c.root, "mixed-journey")
    IO.puts("MIXED_H1_FRESH_ROOT=" <> root)
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    server = ResearchMixedWire.start(root)

    try do
      driver = Path.join(root, "seed-pty")

      assert {"", 0} =
               System.cmd(
                 "rustc",
                 [
                   "--edition=2021",
                   "-D",
                   "warnings",
                   Path.join(@root, "test/support/operator_pty.rs"),
                   "-o",
                   driver
                 ],
                 stderr_to_stdout: true
               )

      {seed_output, seed_status} =
        System.cmd(
          driver,
          ["--assertion", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
            paths() ++
            [Path.join(@root, "test/support/managed_literal_ab_seed.exs"), root, "seed"],
          stderr_to_stdout: true,
          env: [{"IPSE_TEST_LITERAL_OPERATOR_CONFIG", server.route}]
        )

      File.write!(Path.join(root, "native-seed.log"), seed_output)
      assert seed_status == 0, seed_output
      assert seed_output =~ "GENUINE_LITERAL_AB_HISTORICAL_SEED_PASSED"

      {output, status} =
        System.cmd(
          driver,
          ["--assertion", System.find_executable("elixir"), "--erl", "+S 1:1 +A 1"] ++
            paths() ++
            [
              Path.join(@root, "test/support/research_managed_coexistence.exs"),
              c.artifact,
              Path.join(@root, "extensions/knowledge/options/research-state-retained.json"),
              root,
              "save_managed_approval_research"
            ],
          stderr_to_stdout: true,
          env: [{"ERL_FLAGS", "+S 1:1 +A 1"}]
        )

      File.write!(Path.join(root, "mixed-journey.log"), output)
      assert status == 0, output
      assert output =~ "mixed_h1_coexistence=pass"
      refute Code.ensure_loaded?(IpseKnowledge.Research)
    after
      ResearchMixedWire.finish(server)
    end
  end
end
