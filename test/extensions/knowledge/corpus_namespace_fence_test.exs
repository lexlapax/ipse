defmodule Ipse.KnowledgeCorpusNamespaceFenceTest do
  use ExUnit.Case, async: false
  @root Path.expand("../../..", __DIR__)

  test "Corpus fences State and MCP snapshots without weakening document checks" do
    root = Path.join(System.tmp_dir!(), "ipse-corpus-fence-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    artifact = Path.join(root, "artifact")
    helpers = Path.join(root, "helpers")
    File.mkdir!(helpers)

    {build, status} =
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

    assert status == 0, build
    refute build =~ "warning:"

    for path <- Path.wildcard(Path.join(artifact, "ebin/*.beam")),
        Path.basename(path) != "Elixir.IpseKnowledge.Store.beam" do
      File.cp!(path, Path.join(helpers, Path.basename(path)))
    end

    refute File.exists?(Path.join(helpers, "Elixir.IpseKnowledge.Store.beam"))

    paths =
      for module <- [Ipse.Extension, Jason, JSONSchex, ExJSONPointer],
          path = module |> :code.which() |> to_string() |> Path.dirname(),
          do: ["-pa", path]

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        List.flatten(paths) ++
          ["-pa", helpers, Path.join(@root, "test/support/corpus_namespace_fence.exs")],
        cd: @root,
        stderr_to_stdout: true,
        env: [{"ERL_FLAGS", "+S 1:1 +A 1"}]
      )

    assert status == 0, output

    assert Enum.count(
             String.split(output, ~r/\r?\n/),
             &(&1 === "corpus_time_controls=pass")
           ) === 1

    refute output =~ "warning:"
    refute Code.ensure_loaded?(IpseKnowledge.Corpus)
    refute Code.ensure_loaded?(IpseKnowledge.Store)
  end
end
