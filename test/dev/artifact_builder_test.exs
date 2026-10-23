defmodule Ipse.ArtifactBuilderTest do
  use ExUnit.Case, async: true

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-artifact-builder-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)

    files =
      ~w(LICENSE dev/build-artifact.exs examples/model.ex examples/mcp.ex examples/saved_results.ex examples/extension-lab/spec.exs) ++
        Enum.map(~w(memory lookup metadata observer tool_observer text_observer), fn kind ->
          "examples/extension-lab/src/#{kind}.ex"
        end)

    for relative <- files do
      target = Path.join(root, relative)
      File.mkdir_p!(Path.dirname(target))
      File.cp!(relative, target)
    end

    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, output: Path.join(root, "artifact"), sdk: Application.app_dir(:ipse, "ebin")}
  end

  defp build(ctx, recipe, extra \\ []) do
    System.cmd(
      System.find_executable("elixir"),
      [
        Path.join(ctx.root, "dev/build-artifact.exs"),
        recipe,
        "--sdk",
        ctx.sdk,
        "--output",
        ctx.output
      ] ++ extra,
      cd: ctx.root,
      stderr_to_stdout: true
    )
  end

  defp refused(ctx, recipe, extra \\ []) do
    {log, status} = build(ctx, recipe, extra)
    assert status != 0, log
    assert File.lstat(ctx.output) == {:error, :enoent}
    assert Path.wildcard(ctx.output <> ".building-*") == []
    log
  end

  test "duplicate flags cannot redirect construction and closed recipe options refuse", ctx do
    foreign = Path.join(ctx.root, "foreign")

    for {recipe, extra} <- [
          {"model-calls", ["--output", foreign]},
          {"model-calls", ["--sdk", ctx.sdk]},
          {"mcp-actions", ["--omit", "host.mcp", "--omit", "host.actions.mixed"]},
          {"mcp-actions", ["--omit", "host.mcp,host.mcp"]},
          {"mcp-actions", ["--omit", "unknown"]},
          {"model-calls", ["--omit", "host.mcp"]},
          {"unknown", []}
        ] do
      refused(ctx, recipe, extra)
      assert File.lstat(foreign) == {:error, :enoent}
    end
  end

  test "existing content and dangling output links remain unchanged", ctx do
    File.mkdir!(ctx.output)
    sentinel = Path.join(ctx.output, "sentinel")
    File.write!(sentinel, "preserve")
    {log, status} = build(ctx, "model-calls")
    assert status != 0, log
    assert File.read!(sentinel) == "preserve"
    assert File.ls!(ctx.output) == ["sentinel"]
    File.rm!(sentinel)
    File.rmdir!(ctx.output)
    File.ln_s!("absent-target", ctx.output)
    {log, status} = build(ctx, "model-calls")
    assert status != 0, log
    assert File.read_link(ctx.output) == {:ok, "absent-target"}
    assert Path.wildcard(ctx.output <> ".building-*") == []
  end

  test "compilation warnings refuse publication and remove the owned stage", ctx do
    path = Path.join(ctx.root, "examples/model.ex")
    source = File.read!(path)

    source =
      String.replace(
        source,
        "def init(options), do: {:ok, options}",
        "def init(options) do\n    unused = 1\n    {:ok, options}\n  end"
      )

    File.write!(path, source)
    assert refused(ctx, "model-calls") =~ "warning:"
  end

  test "the lab's shared entrypoint declaration is an invariant", ctx do
    {log, 0} = build(ctx, "extension-lab")
    refute log =~ "warning:"
    assert length(Path.wildcard(Path.join(ctx.output, "*/extension.json"))) == 7
    path = Path.join(ctx.root, "examples/extension-lab/src/memory.ex")

    source =
      File.read!(path)
      |> String.replace("defmodule IpseLab.Memory do", "defmodule IpseLab.RenamedMemory do")

    File.write!(path, source)
    refused(%{ctx | output: Path.join(ctx.root, "changed")}, "extension-lab")
  end

  test "the shared lab declarations cannot emit diagnostics before worker compilation", ctx do
    path = Path.join(ctx.root, "examples/extension-lab/spec.exs")
    File.write!(path, File.read!(path) <> "\nIO.warn(\"Synthetic declaration warning\")\n")
    assert refused(ctx, "extension-lab") =~ "Synthetic declaration warning"
  end

  test "a requested MCP omission cannot silently miss its source declaration", ctx do
    path = Path.join(ctx.root, "examples/mcp.ex")
    source = File.read!(path) |> String.replace("@capabilities ~w(", "@capabilities ~w(\n")
    File.write!(path, source)
    refused(ctx, "mcp-actions", ["--omit", "host.mcp"])
  end

  test "SDK2 compilation contains its on-load effect and publishes only declared files", ctx do
    {log, status} = build(ctx, "saved-results")
    assert status == 0, log
    refute log =~ "warning:"
    manifest = File.read!(Path.join(ctx.output, "extension.json")) |> JSON.decode!()
    assert manifest["sdk"] == 2
    expected = ["LICENSE", "ebin/Elixir.IpseSavedResultsExample.Worker.beam"]
    assert Enum.map(manifest["files"], & &1["path"]) == expected

    files =
      Path.wildcard(ctx.output <> "/**/*")
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(&Path.relative_to(&1, ctx.output))
      |> Enum.sort()

    assert files == Enum.sort(["extension.json" | expected])
    assert Path.wildcard(ctx.root <> "/**/worker-loads.log") == []
    assert Path.wildcard(ctx.output <> ".building-*") == []
    assert :code.is_loaded(IpseSavedResultsExample.Worker) == false
  end

  @tag :builder_identity
  test "rebuilding fixed source does not put temporary stage names into artifact identity", ctx do
    {log, 0} = build(ctx, "model-calls")
    refute log =~ "warning:"
    second = %{ctx | output: Path.join(ctx.root, "second")}
    {log, 0} = build(second, "model-calls")
    refute log =~ "warning:"

    for relative <- ~w(extension.json LICENSE ebin/Elixir.IpseModelExample.Complete.beam) do
      assert File.read!(Path.join(ctx.output, relative)) ==
               File.read!(Path.join(second.output, relative))
    end

    beam = File.read!(Path.join(ctx.output, "ebin/Elixir.IpseModelExample.Complete.beam"))
    {:ok, _, chunks} = :beam_lib.all_chunks(beam)
    checker = Map.fetch!(Map.new(chunks), ~c"ExCk")
    assert checker == :erlang.term_to_binary(:erlang.binary_to_term(checker), [:deterministic])
  end
end
