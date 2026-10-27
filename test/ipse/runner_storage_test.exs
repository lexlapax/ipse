defmodule Ipse.RunnerStorageTest do
  use ExUnit.Case, async: true

  setup do
    path = Path.join(System.tmp_dir!(), "ipse-allocation-" <> Ipse.Usage.id())
    File.mkdir!(path)
    File.chmod!(path, 0o700)
    on_exit(fn -> File.rm_rf!(path) end)
    %{path: path}
  end

  test "native allocation includes directories and active, staged and retained files", c do
    for name <- ~w(.lock root.json .pending-operation) do
      File.write!(Path.join(c.path, name), "bounded data")
      File.chmod!(Path.join(c.path, name), 0o600)
    end

    assert {:ok, usage} = Ipse.Runner.storage_allocation(c.path)
    assert usage["logical_bytes"] >= 36
    assert usage["entries"] == 4
    assert usage["allocated_bytes"] >= 0
    assert rem(usage["allocated_bytes"], 512) == 0

    assert {:error, :storage_allocation_unavailable} =
             Ipse.Runner.storage_allocation(c.path <> "/.")
  end

  test "unsafe links, modes and root types fail closed", c do
    file = Path.join(c.path, "data")
    File.write!(file, "x")
    File.chmod!(file, 0o600)
    File.ln!(file, Path.join(c.path, "hardlink"))
    assert {:error, :storage_allocation_unavailable} = Ipse.Runner.storage_allocation(c.path)
    File.rm!(Path.join(c.path, "hardlink"))
    File.ln_s!(file, Path.join(c.path, "symlink"))
    assert {:error, :storage_allocation_unavailable} = Ipse.Runner.storage_allocation(c.path)
    File.rm!(Path.join(c.path, "symlink"))
    File.chmod!(file, 0o644)
    assert {:error, :storage_allocation_unavailable} = Ipse.Runner.storage_allocation(c.path)
    assert {:error, :storage_allocation_unavailable} = Ipse.Runner.storage_allocation(file)
  end

  test "private staging is exclusive, bounded and preserves all maximum input bytes", c do
    path = Path.join(c.path, ".pending-" <> Ipse.Usage.id())
    bytes = String.duplicate("x", 8 * 1024 * 1024)
    assert :ok = Ipse.Runner.protected_staging_write(path, bytes)
    assert File.read!(path) == bytes
    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600

    assert {:error, :protected_staging_write_unavailable} =
             Ipse.Runner.protected_staging_write(path, "replacement")

    assert File.read!(path) == bytes

    assert {:error, :protected_staging_write_unavailable} =
             Ipse.Runner.protected_staging_write(Path.join(c.path, "ordinary"), "x")

    assert {:error, :protected_staging_write_unavailable} =
             Ipse.Runner.protected_staging_write(
               Path.join(c.path, ".pending-" <> Ipse.Usage.id()),
               bytes <> "x"
             )
  end

  test "one bounded native batch creates separately private complete files", c do
    files = for n <- 1..128, do: {".pending-" <> Ipse.Usage.id(), "entry #{n}"}
    assert :ok = Ipse.Runner.protected_staging_write_many(c.path, files)

    for {name, bytes} <- files do
      path = Path.join(c.path, name)
      assert File.read!(path) == bytes
      assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
    end

    assert {:error, :protected_staging_write_unavailable} =
             Ipse.Runner.protected_staging_write_many(c.path, [hd(files), hd(files)])
  end
end
