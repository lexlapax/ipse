defmodule Runespell.ToolsTest do
  use ExUnit.Case, async: true
  alias Runespell.Tools

  setup do
    cwd = Path.join(System.tmp_dir!(), "runespell-tools-#{System.unique_integer([:positive])}")
    File.mkdir_p!(cwd)
    on_exit(fn -> File.rm_rf!(cwd) end)
    %{cwd: cwd, context: %{cwd: cwd}}
  end

  test "reads offsets, writes, and makes a unique edit", %{cwd: cwd, context: context} do
    assert {:ok, _} =
             Tools.execute(
               "write",
               %{"path" => "notes", "content" => "first\nsecond\nthird\n"},
               context
             )

    assert {:ok, "second\n"} =
             Tools.execute("read", %{"path" => "notes", "offset" => 2, "max_lines" => 1}, context)

    assert {:ok, _} =
             Tools.execute(
               "edit",
               %{"path" => "notes", "old" => "second", "new" => "changed"},
               context
             )

    assert File.read!(Path.join(cwd, "notes")) == "first\nchanged\nthird\n"
  end

  test "rejects absent, repeated, overlapping, or empty edits", %{cwd: cwd, context: context} do
    File.write!(Path.join(cwd, "notes"), "aaa")

    for old <- ["missing", "a", "aa", ""] do
      assert {:error, _} =
               Tools.execute("edit", %{"path" => "notes", "old" => old, "new" => "x"}, context)
    end

    assert File.read!(Path.join(cwd, "notes")) == "aaa"
  end

  test "rejects escapes, symlinks, and git mutations", %{cwd: cwd, context: context} do
    File.mkdir_p!(Path.join(cwd, ".git"))
    File.ln_s!(System.tmp_dir!(), Path.join(cwd, "linked"))

    for path <- [
          "../outside",
          Path.join(System.tmp_dir!(), "outside"),
          "linked/file",
          ".git/config",
          ".git/nested/file"
        ] do
      assert {:error, _} = Tools.execute("write", %{"path" => path, "content" => "x"}, context)
    end

    assert {:error, _} = Tools.execute("read", %{"path" => "linked/file"}, context)
  end

  test "bounds a large single line and returns valid UTF-8", %{cwd: cwd, context: context} do
    File.write!(Path.join(cwd, "large"), String.duplicate("€", 30_000))
    assert {:ok, text} = Tools.execute("read", %{"path" => "large"}, context)
    assert String.valid?(text)
    assert byte_size(text) <= 65_536
    assert byte_size(text) > 65_530
  end

  test "rejects malformed arguments", %{context: context} do
    assert {:error, _} = Tools.execute("read", %{"path" => "x", "offset" => 0}, context)
    assert {:error, _} = Tools.execute("write", %{"path" => "x", "content" => nil}, context)
    assert {:error, _} = Tools.execute("edit", %{"path" => "x"}, context)
    assert {:error, _} = Tools.execute("unknown", %{}, context)
    assert Tools.mutating?("shell")
    refute Tools.mutating?("read")
    assert length(Tools.definitions()) == 4
  end
end
