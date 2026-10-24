defmodule Ipse.PrivateFileTest do
  use ExUnit.Case, async: true

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-private-file-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    File.chmod!(root, 0o755)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "atomic replacement protects files and creates only new directories privately", c do
    path = Path.join(c.root, "new/operator/config.json")
    assert :ok = Ipse.PrivateFile.write_atomic(path, "first")

    for dir <- [Path.join(c.root, "new"), Path.join(c.root, "new/operator")] do
      assert Bitwise.band(File.stat!(dir).mode, 0o777) == 0o700
    end

    assert Bitwise.band(File.stat!(c.root).mode, 0o777) == 0o755
    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
    File.chmod!(path, 0o644)
    assert :ok = Ipse.PrivateFile.write_atomic(path, "second")
    assert File.read!(path) == "second"
    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
    assert File.ls!(Path.dirname(path)) == ["config.json"]
  end

  test "exclusive publication preserves an existing backup and removes temporary names", c do
    path = Path.join(c.root, "backup")
    assert :ok = Ipse.PrivateFile.write_atomic(path, "original", replace: false)
    assert File.stat!(path).links == 1
    assert {:error, :eexist} = Ipse.PrivateFile.write_atomic(path, "replacement", replace: false)
    assert File.read!(path) == "original"
    assert File.ls!(c.root) == ["backup"]
  end

  test "refused parent aliases and publication failures do not damage existing bytes", c do
    target = Path.join(c.root, "target")
    File.mkdir!(target)
    File.ln_s!(target, Path.join(c.root, "alias"))

    assert {:error, :unsafe_private_directory} =
             Ipse.PrivateFile.write_atomic(Path.join(c.root, "alias/file"), "secret")

    assert File.ls!(target) == []
    assert {:error, _} = Ipse.PrivateFile.write_atomic(target, "secret")
    assert Enum.sort(File.ls!(c.root)) == ["alias", "target"]
  end
end
