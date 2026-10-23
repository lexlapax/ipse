defmodule Ipse.MacOSFilesystemTest do
  use ExUnit.Case, async: true
  alias Ipse.Tools
  @moduletag :macos_filesystem

  test "metadata guards and target keys cover actual case and normalization aliases" do
    assert :os.type() == {:unix, :darwin}, "filesystem enforcement requires a Mac host"
    root = Path.join(System.tmp_dir!(), "ipse-macos-paths-#{Ipse.Usage.id()}")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    File.mkdir!(Path.join(root, ".git"))
    protected = Path.join(root, ".git/protected")
    File.write!(protected, "keep")

    assert File.stat!(Path.join(root, ".GIT/protected")).inode == File.stat!(protected).inode,
           "this check requires a case-insensitive filesystem"

    assert {:error, _} =
             Tools.execute("write", %{"path" => ".GIT/new", "content" => "x"}, %{cwd: root})

    assert {:error, _} =
             Tools.execute(
               "edit",
               %{"path" => ".GiT/protected", "old" => "keep", "new" => "changed"},
               %{cwd: root}
             )

    assert File.read!(protected) == "keep"
    refute File.exists?(Path.join(root, ".git/new"))

    composed = Path.join(root, "café.txt")
    decomposed = Path.join(root, "cafe\u0301.txt")
    File.write!(composed, "fixture")
    assert File.stat!(composed).inode == File.stat!(decomposed).inode
    assert Tools.path_key(composed) == Tools.path_key(decomposed)
    assert Tools.path_key(Path.join(root, "CAFÉ.txt")) == Tools.path_key(composed)
  end
end
