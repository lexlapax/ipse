defmodule Ipse.Development.DocumentsBuildTest do
  use ExUnit.Case, async: false

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-documents-build-" <> Ipse.Usage.id())
    File.mkdir_p!(Path.join(root, "dev"))
    File.mkdir!(Path.join(root, "priv"))
    File.mkdir!(Path.join(root, "tools"))
    File.cp!("dev/build-native.sh", Path.join(root, "dev/build-native.sh"))

    for name <- ~w(dirname mkdir rm),
        do: File.ln_s!(System.find_executable(name), Path.join(root, "tools/" <> name))

    for {name, script} <- [
          {"rustc",
           "#!/bin/sh\nprintf '%s\\n' \"$*\" >> rust.calls\nprintf 'native' > priv/ipse-runner\n"},
          {"elixir",
           "#!/bin/sh\nprintf '%s\\n' \"$*\" >> parser.calls\nprintf 'parser' > priv/ipse-pdf\nmkdir -p priv/ipse-pdf-notices\nprintf 'notice' > priv/ipse-pdf-notices/LICENSE\n"}
        ] do
      path = Path.join(root, "tools/" <> name)
      File.write!(path, script)
      File.chmod!(path, 0o755)
    end

    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  defp build(root, flag) do
    System.cmd("/bin/sh", [Path.join(root, "dev/build-native.sh")],
      env: [{"PATH", Path.join(root, "tools")}, {"IPSE_BUILD_PDF", flag}],
      stderr_to_stdout: true
    )
  end

  test "source default needs no PDF toolchain and removes stale generated parser files", %{
    root: root
  } do
    File.write!(Path.join(root, "priv/ipse-pdf"), "stale parser")
    File.mkdir!(Path.join(root, "priv/ipse-pdf-notices"))
    File.write!(Path.join(root, "priv/ipse-pdf-notices/stale"), "stale notice")
    assert {_, 0} = build(root, nil)
    refute File.exists?(Path.join(root, "priv/ipse-pdf"))
    refute File.exists?(Path.join(root, "priv/ipse-pdf-notices"))
    refute File.exists?(Path.join(root, "parser.calls"))
    assert File.read!(Path.join(root, "rust.calls")) =~ "--edition=2021"
  end

  test "explicit parser build invokes the locked-notice builder and rejects invalid selection before building",
       %{root: root} do
    assert {_, 2} = build(root, "unexpected")
    refute File.exists?(Path.join(root, "rust.calls"))
    assert {_, 0} = build(root, "1")

    assert File.read!(Path.join(root, "parser.calls")) =~
             "native/ipse-pdf/build.exs --output priv/ipse-pdf --notices priv/ipse-pdf-notices"

    assert File.read!(Path.join(root, "priv/ipse-pdf")) == "parser"
    assert File.read!(Path.join(root, "priv/ipse-pdf-notices/LICENSE")) == "notice"
  end

  test "a built corpus artifact contains every standalone extraction module", %{root: root} do
    output = Path.join(root, "corpus")

    {log, status} =
      System.cmd(
        System.find_executable("elixir"),
        [
          "extensions/knowledge/build.exs",
          "--sdk",
          Application.app_dir(:ipse, "ebin"),
          "--output",
          output,
          "--package",
          "corpus",
          "--preset",
          "state-lexical"
        ],
        stderr_to_stdout: true
      )

    assert status == 0, log
    refute log =~ "warning:"
    manifest = JSON.decode!(File.read!(Path.join(output, "extension.json")))
    files = Map.new(manifest["files"], &{&1["path"], &1})

    for name <- ~w(Documents Documents.Zip Documents.Docx Documents.Pdf Documents.ParserStage) do
      relative = "ebin/Elixir.IpseKnowledge." <> name <> ".beam"
      bytes = File.read!(Path.join(output, relative))
      assert files[relative]["sha256"] == Ipse.JSON.sha256(bytes)
      assert files[relative]["bytes"] == byte_size(bytes)
    end

    refute :code.is_loaded(IpseKnowledge.Documents)
  end
end
