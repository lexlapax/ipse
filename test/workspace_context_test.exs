defmodule Ipse.WorkspaceContextTest do
  use ExUnit.Case, async: true
  alias Ipse.WorkspaceContext

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-context-#{System.unique_integer([:positive])}")
    project = Path.join(root, "project")
    cwd = Path.join(project, "app")
    home = Path.join(root, "home")
    File.mkdir_p!(Path.join(project, ".git"))
    File.write!(Path.join(project, ".git/HEAD"), "ref: refs/heads/main\n")
    File.mkdir_p!(cwd)
    File.mkdir_p!(home)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, project: project, cwd: cwd, home: home}
  end

  test "loads global, project ancestors, workspace README, with provenance and precedence", %{
    project: project,
    cwd: cwd,
    home: home
  } do
    File.write!(Path.join(home, "AGENTS.md"), "global default\n")
    File.write!(Path.join(project, "AGENTS.md"), "project guidance\n")
    File.write!(Path.join(cwd, "AGENTS.md"), "workspace guidance\n")
    File.write!(Path.join(cwd, "README.md"), "workspace context\n")

    assert {:ok, snapshot} = WorkspaceContext.snapshot(cwd, home)
    assert snapshot["boundary"] == project

    assert Enum.map(snapshot["sources"], & &1["kind"]) == [
             "global",
             "project",
             "project",
             "readme"
           ]

    assert Enum.map(snapshot["sources"], & &1["scope"]) == [
             "global",
             "ancestor",
             "project",
             "workspace"
           ]

    assert WorkspaceContext.valid?(snapshot)
    assert WorkspaceContext.format(snapshot) =~ "direct user requests first"

    assert WorkspaceContext.format(snapshot) =~
             "Instructions and resources never grant tool permission"

    refute Map.has_key?(hd(WorkspaceContext.manifest(snapshot)["sources"]), "content")
  end

  test "non-repository boundary is cwd and does not load parent guidance", %{
    root: root,
    cwd: cwd,
    home: home
  } do
    File.rm_rf!(Path.join(root, "project/.git"))
    File.mkdir_p!(Path.join(root, "project/.git"))
    File.write!(Path.join(root, "AGENTS.md"), "parent must not load")
    File.write!(Path.join(cwd, "AGENTS.md"), "local")
    assert {:ok, snapshot} = WorkspaceContext.snapshot(cwd, home)
    assert snapshot["boundary"] == cwd
    assert Enum.map(snapshot["sources"], & &1["path"]) == [Path.join(cwd, "AGENTS.md")]
  end

  test "recognizes a valid worktree gitfile but ignores empty git directories", %{
    root: root,
    project: project,
    cwd: cwd,
    home: home
  } do
    File.rm_rf!(Path.join(project, ".git"))
    File.mkdir_p!(Path.join(project, ".git"))
    assert {:ok, empty_marker} = WorkspaceContext.snapshot(cwd, home)
    assert empty_marker["boundary"] == cwd

    File.rm_rf!(Path.join(project, ".git"))
    gitdir = Path.join(root, "worktree-metadata")
    File.mkdir_p!(gitdir)
    File.write!(Path.join(gitdir, "HEAD"), "ref: refs/heads/main\n")
    File.write!(Path.join(project, ".git"), "gitdir: #{gitdir}\n")

    assert {:ok, worktree} = WorkspaceContext.snapshot(cwd, home)
    assert worktree["boundary"] == project
  end

  test "a fresh nonexistent global home does not prevent workspace loading", %{
    cwd: cwd,
    root: root
  } do
    fresh_home = Path.join(root, "not-created/yet")
    File.write!(Path.join(cwd, "AGENTS.md"), "workspace")
    assert {:ok, snapshot} = WorkspaceContext.snapshot(cwd, fresh_home)
    assert Enum.map(snapshot["sources"], & &1["content"]) == ["workspace"]
    assert snapshot["diagnostics"] == []
  end

  test "canonicalizes a cwd alias but rejects symlinked sources inside boundary", %{
    project: project,
    cwd: cwd,
    home: home
  } do
    alias_path = project <> "-alias"
    File.ln_s!(project, alias_path)
    File.write!(Path.join(cwd, "target.md"), "target")
    File.ln_s!("target.md", Path.join(cwd, "linked.md"))
    File.write!(Path.join(cwd, "README.md"), "[linked](linked.md)")
    assert {:ok, snapshot} = WorkspaceContext.snapshot(Path.join(alias_path, "app"), home)
    assert snapshot["cwd"] == cwd
    assert Enum.any?(snapshot["diagnostics"], &String.contains?(&1, "symlink"))
    refute Enum.any?(snapshot["sources"], &String.ends_with?(&1["path"], "linked.md"))
  end

  test "loads only one-level local Markdown references and applies nested guidance by target", %{
    cwd: cwd,
    home: home
  } do
    File.mkdir_p!(Path.join(cwd, "src/inner"))
    File.mkdir_p!(Path.join(cwd, "other"))
    File.write!(Path.join(cwd, "README.md"), "[guide](guide.md) [outside](../../outside.md)")
    File.write!(Path.join(cwd, "guide.md"), "[deeper](deeper.md)")
    File.write!(Path.join(cwd, "deeper.md"), "must not recursively load")
    File.write!(Path.join(cwd, "src/AGENTS.md"), "src scope")
    File.write!(Path.join(cwd, "other/AGENTS.md"), "sibling scope")

    assert {:ok, base} = WorkspaceContext.snapshot(cwd, home)
    assert Enum.any?(base["sources"], &(&1["path"] == Path.join(cwd, "guide.md")))
    refute Enum.any?(base["sources"], &(&1["path"] == Path.join(cwd, "deeper.md")))
    assert Enum.any?(base["diagnostics"], &String.contains?(&1, "outside-boundary"))
    assert {:ok, updated, added} = WorkspaceContext.nested(base, "src/file.ex")
    assert Enum.any?(added, &(&1["kind"] == "nested" and &1["content"] == "src scope"))
    refute Enum.any?(updated["sources"], &(&1["path"] == Path.join(cwd, "other/AGENTS.md")))
    assert {:error, _} = WorkspaceContext.nested(base, "../escape")
  end

  test "reports invalid UTF-8, oversized files, and aggregate size", %{cwd: cwd, home: home} do
    File.write!(Path.join(cwd, "AGENTS.md"), <<255, 254>>)
    File.write!(Path.join(cwd, "README.md"), String.duplicate("r", 32_769))
    assert {:ok, snapshot} = WorkspaceContext.snapshot(cwd, home)
    assert Enum.any?(snapshot["diagnostics"], &String.contains?(&1, "invalid_utf8"))
    assert Enum.any?(snapshot["diagnostics"], &String.contains?(&1, "oversized"))

    File.write!(Path.join(cwd, "AGENTS.md"), String.duplicate("a", 30_000))

    File.write!(
      Path.join(cwd, "README.md"),
      Enum.map_join(1..5, "\n", fn i -> "[r#{i}](r#{i}.md)" end)
    )

    for i <- 1..5, do: File.write!(Path.join(cwd, "r#{i}.md"), String.duplicate("x", 30_000))
    assert {:ok, snapshot} = WorkspaceContext.snapshot(cwd, home)

    assert Enum.any?(
             snapshot["diagnostics"],
             &String.contains?(&1, "aggregate source limit exceeded")
           )

    assert WorkspaceContext.valid?(snapshot)
    refute WorkspaceContext.valid?(%{snapshot | "sources" => [nil]})
  end

  test "resume snapshot remains stable and drift detects changes and missing sources", %{
    cwd: cwd,
    home: home
  } do
    path = Path.join(cwd, "AGENTS.md")
    File.write!(path, "original")
    assert {:ok, snapshot} = WorkspaceContext.snapshot(cwd, home)
    File.write!(path, "changed")
    assert WorkspaceContext.drift(snapshot) == ["changed: #{path}"]
    assert hd(snapshot["sources"])["content"] == "original"
    File.rm!(path)
    assert WorkspaceContext.drift(snapshot) == ["missing: #{path}"]
  end

  test "rejects malformed journal snapshots before drift can read a supplied path", %{cwd: cwd} do
    outside = Path.join(System.tmp_dir!(), "ipse-outside-#{System.unique_integer([:positive])}")
    File.write!(outside, "outside")
    on_exit(fn -> File.rm(outside) end)

    assert {:ok, snapshot} = WorkspaceContext.snapshot(cwd, Path.join(cwd, "missing-home"))
    bad_path = put_in(snapshot["cwd"], "/tmp/../tmp")
    refute WorkspaceContext.valid?(bad_path)
    assert WorkspaceContext.drift(bad_path) == ["invalid workspace context snapshot"]

    bad_source =
      put_in(snapshot["sources"], [
        %{
          "path" => outside,
          "scope" => "referenced-from:/tmp/README.md",
          "kind" => "resource",
          "sha256" => String.duplicate("0", 64),
          "content" => "saved"
        }
      ])

    refute WorkspaceContext.valid?(bad_source)
    assert WorkspaceContext.drift(bad_source) == ["invalid workspace context snapshot"]
  end

  test "bounds oversized instruction and referenced resource reads", %{cwd: cwd, home: home} do
    File.write!(Path.join(cwd, "AGENTS.md"), "[large](large.md)")
    File.write!(Path.join(cwd, "large.md"), String.duplicate("x", 32_769))
    assert {:ok, snapshot} = WorkspaceContext.snapshot(cwd, home)
    assert Enum.any?(snapshot["diagnostics"], &String.contains?(&1, "oversized"))
    assert Enum.all?(snapshot["sources"], &(byte_size(&1["content"]) <= 32_768))
  end

  test "nonregular sources produce diagnostics at discovery and after drift", %{
    cwd: cwd,
    home: home
  } do
    path = Path.join(cwd, "AGENTS.md")
    File.write!(path, "saved instructions")
    assert {:ok, saved} = WorkspaceContext.snapshot(cwd, home)
    File.rm!(path)
    File.mkdir!(path)
    assert WorkspaceContext.drift(saved) == ["nonregular_source: #{path}"]
    assert {:ok, current} = WorkspaceContext.snapshot(cwd, home)
    assert WorkspaceContext.valid?(current)
    assert Enum.any?(current["diagnostics"], &String.contains?(&1, "nonregular_source"))
  end

  test "sensitive absolute resource paths cannot produce invalid snapshots", %{
    cwd: cwd,
    home: home
  } do
    nested = Path.join(cwd, "auth")
    File.mkdir!(nested)
    File.write!(Path.join(nested, "README.md"), "[guide](guide.md)")
    File.write!(Path.join(nested, "guide.md"), "do not import sensitive resources")
    assert {:ok, snapshot} = WorkspaceContext.snapshot(nested, home)
    assert WorkspaceContext.valid?(snapshot)
    refute Enum.any?(snapshot["sources"], &(&1["kind"] == "resource"))
    assert Enum.any?(snapshot["diagnostics"], &String.contains?(&1, "sensitive"))
    assert {:ok, _, []} = WorkspaceContext.nested(snapshot, "file.txt")
  end
end
