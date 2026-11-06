defmodule Ipse.KnowledgeResearchFetchTransferTest do
  use ExUnit.Case, async: false
  @root Path.expand("../../..", __DIR__)

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-research-fetch-transfer-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    artifact = Path.join(root, "artifact")

    {build, 0} =
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
          "state-fetched"
        ],
        stderr_to_stdout: true,
        env: [{"ERL_FLAGS", "+S 1:1 +A 1"}]
      )

    refute build =~ "warning:"
    manifest = File.read!(Path.join(artifact, "extension.json"))
    assert byte_size(manifest) <= 16_384
    assert {:ok, _} = Ipse.Extension.Artifact.decode(manifest)
    fixture = Path.join(root, "fixture-ebin")
    File.mkdir!(fixture)

    {fixture_output, fixture_status} =
      System.cmd(
        System.find_executable("elixirc"),
        paths() ++
          [
            "--warnings-as-errors",
            "-o",
            fixture,
            Path.join(@root, "dev/fixtures/knowledge.exs")
          ],
        stderr_to_stdout: true,
        env: [{"ERL_FLAGS", "+S 1:1 +A 1"}]
      )

    assert fixture_status == 0, fixture_output
    refute fixture_output =~ "warning:"

    if System.get_env("IPSE_TEST_RESEARCH_FETCH_KEEP") != "1",
      do: on_exit(fn -> File.rm_rf!(root) end)

    %{root: root, artifact: artifact, fixture: fixture}
  end

  defp paths do
    :code.get_path()
    |> Enum.map(&List.to_string/1)
    |> Enum.reject(fn path ->
      path == "." or
        Enum.any?(
          ~w(Elixir.Ipse.Development.Fixtures.Knowledge.beam Elixir.Ipse.Development.Fixtures.Knowledge.Backend.beam),
          &File.regular?(Path.join(path, &1))
        )
    end)
    |> Enum.flat_map(&["-pa", &1])
  end

  @tag :exunit_output_contract
  test "fetched transfer validates real adapter envelopes and shared body suppression", c do
    script = """
    ExUnit.start(autorun: false)
    ExUnit.after_suite(fn result ->
      if Map.take(result, [:total, :failures, :skipped, :excluded]) !=
           %{total: 23, failures: 0, skipped: 0, excluded: 0},
        do: raise("unexpected fetched-transfer counters: " <> inspect(result))
      IO.puts("RESEARCH_FETCH_TRANSFER_CONTROL_PASS")
    end)
    Code.require_file(#{inspect(Path.join(@root, "test/support/research_fetch_transfer_pure.exs"))})
    """

    {output, code} =
      System.cmd(
        System.find_executable("elixir"),
        paths() ++
          [
            "-pa",
            Path.join(c.artifact, "ebin"),
            "-e",
            script
          ],
        stderr_to_stdout: true,
        env: [{"ERL_FLAGS", "+S 1:1 +A 1"}]
      )

    assert code == 0, output

    assert Enum.count(
             String.split(output, ~r/\r?\n/),
             &(&1 === "RESEARCH_FETCH_TRANSFER_CONTROL_PASS")
           ) === 1

    refute Code.ensure_loaded?(IpseKnowledge.Research)
  end

  @tag research_fetch_session: true
  @tag timeout: 120_000
  @tag skip:
         if(
           System.get_env("IPSE_TEST_RESEARCH_FETCH_SESSION") == "1" and
             :os.type() == {:unix, :linux},
           do: false,
           else: "explicit Linux protected-storage fetched-transfer Session fixture required"
         )
  test "ordinary MCP and State approvals transfer evidence and preserve refusal, forgetting and unknown no-replay",
       c do
    {output, code} =
      System.cmd(
        System.find_executable("elixir"),
        paths() ++
          [
            "-pa",
            c.fixture,
            Path.join(@root, "test/support/research_fetch_transfer_session.exs"),
            Path.join(c.root, "journey"),
            c.artifact
          ],
        stderr_to_stdout: true,
        env: [{"ERL_FLAGS", "+S 1:1 +A 1"}]
      )

    File.write!(Path.join(c.root, "journey-private.log"), output)
    assert code == 0, output
    assert output =~ "fetched_state_journey=pass"
    refute Code.ensure_loaded?(IpseKnowledge.Research)
  end
end
