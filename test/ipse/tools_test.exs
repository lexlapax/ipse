defmodule Ipse.ToolsTest do
  use ExUnit.Case, async: true
  alias Ipse.Tools

  setup do
    cwd = Path.join(System.tmp_dir!(), "ipse-tools-#{System.unique_integer([:positive])}")
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

  test "missing and non-directory write parents are refused before attempting a write", c do
    File.write!(Path.join(c.cwd, "parent-file"), "keep")

    for path <- ["missing/child", "parent-file/child"] do
      assert {:error, _} = Tools.execute("write", %{"path" => path, "content" => "x"}, c.context)
      refute File.exists?(Path.join(c.cwd, path))
    end

    assert File.read!(Path.join(c.cwd, "parent-file")) == "keep"
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

  test "Git metadata names remain reserved across case and ignorable format variants", c do
    for name <- [".GIT", ".GiT", ".g\u200bit", ".git\uFE0F"] do
      directory = Path.join(c.cwd, name)
      File.mkdir_p!(directory)
      File.write!(Path.join(directory, "protected"), "keep")

      assert {:error, _} =
               Tools.execute(
                 "write",
                 %{"path" => name <> "/forbidden", "content" => "x"},
                 c.context
               )

      assert {:error, _} =
               Tools.execute(
                 "edit",
                 %{"path" => name <> "/protected", "old" => "keep", "new" => "changed"},
                 c.context
               )

      assert File.read!(Path.join(directory, "protected")) == "keep"
      refute File.exists?(Path.join(directory, "forbidden"))
    end
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

  test "explicit binary reads return complete exact bytes and enforce the expected hash", c do
    bytes = <<0, 255, 10, 128, 1>> <> "café"
    File.write!(Path.join(c.cwd, "binary.docx"), bytes)
    args = %{"path" => "binary.docx", "encoding" => "base64", "max_bytes" => 4096}
    assert {:ok, text} = Tools.execute("read", args, c.context)
    assert Tools.binary_read_result?(text, args)

    for invalid <- [
          Map.put(args, "file_max_bytes", 32768),
          Map.put(args, "offset", 1),
          Map.put(args, "max_lines", 1),
          Map.delete(args, "encoding")
        ] do
      refute Tools.binary_read_result?(text, invalid)
    end

    result = Jason.decode!(text)
    assert result["complete"] and result["byte_count"] == byte_size(bytes)
    assert Base.decode64!(result["data"]) == bytes
    assert result["sha256"] == Ipse.JSON.sha256(bytes)

    assert {:ok, ^text} =
             Tools.execute("read", Map.put(args, "expected_sha256", result["sha256"]), c.context)

    assert {:error, _} =
             Tools.execute(
               "read",
               Map.put(args, "expected_sha256", Ipse.JSON.sha256("other")),
               c.context
             )

    assert {:error, _} =
             Tools.execute("read", %{args | "max_bytes" => byte_size(bytes) - 1}, c.context)

    for changed <- [
          Map.put(result, "complete", false),
          Map.put(result, "sha256", Ipse.JSON.sha256("other")),
          Map.put(result, "byte_count", 0),
          Map.put(result, "path", "other.docx")
        ] do
      refute Tools.binary_read_result?(Jason.encode!(changed), args)
    end
  end

  test "binary pages bind exact complete-file bytes and refuse changes between pages", c do
    bytes = :binary.copy(<<0, 255, 4, 9, 18>>, 2000)
    path = Path.join(c.cwd, "pages.docx")
    File.write!(path, bytes)

    base = %{
      "path" => "pages.docx",
      "encoding" => "base64",
      "max_bytes" => 4096,
      "file_max_bytes" => 32768,
      "byte_offset" => 0
    }

    assert {:ok, first} = Tools.execute("read", base, c.context)
    assert Tools.binary_read_result?(first, base)
    value = Jason.decode!(first)
    assert value["version"] == 2 and value["byte_count"] == 10000 and value["next"] == 4096
    refute Map.has_key?(value, "complete")
    assert value["sha256"] == Ipse.JSON.sha256(bytes)
    assert {:error, _} = Tools.execute("read", Map.put(base, "byte_offset", 4096), c.context)

    {parts, _} =
      Enum.map_reduce([0, 4096, 8192], 0, fn offset, count ->
        args = Map.merge(base, %{"byte_offset" => offset, "expected_sha256" => value["sha256"]})
        assert {:ok, text} = Tools.execute("read", args, c.context)
        assert byte_size(text) <= 8192 and Tools.binary_read_result?(text, args)
        page = Jason.decode!(text)
        refute Tools.binary_read_result?(Jason.encode!(Map.put(page, "offset", offset + 1)), args)
        {Base.decode64!(page["data"]), count + 1}
      end)

    assert IO.iodata_to_binary(parts) == bytes
    File.write!(path, :binary.copy(<<1>>, 10000))

    assert {:error, _} =
             Tools.execute(
               "read",
               Map.merge(
                 base,
                 %{"byte_offset" => 4096, "expected_sha256" => value["sha256"]}
               ),
               c.context
             )

    assert {:error, _} = Tools.execute("read", Map.delete(base, "byte_offset"), c.context)
  end

  test "binary reads refuse escapes, special aliases, excess bytes and mixed options", c do
    File.write!(Path.join(c.cwd, "data"), String.duplicate("x", 4097))
    File.write!(Path.join(c.cwd, "oversized"), String.duplicate("x", 4097))
    File.ln_s!(Path.join(c.cwd, "data"), Path.join(c.cwd, "symbolic"))
    File.ln!(Path.join(c.cwd, "data"), Path.join(c.cwd, "hardlink"))

    for path <- ["../outside", "symbolic", "hardlink", "data", "oversized", "."] do
      assert {:error, _} =
               Tools.execute("read", %{"path" => path, "encoding" => "base64"}, c.context)
    end

    for args <- [
          %{"path" => "data", "encoding" => "base64", "offset" => 1},
          %{"path" => "data", "encoding" => "base64", "max_lines" => 1},
          %{"path" => "data", "max_bytes" => 1},
          %{"path" => "data", "encoding" => "unknown"}
        ] do
      assert {:error, _} = Tools.execute("read", args, c.context)
    end
  end
end
