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

    for name <-
          ~w(Documents Documents.Zip Documents.Docx Documents.Docx.Styles Documents.Pdf Documents.ParserStage) do
      relative = "ebin/Elixir.IpseKnowledge." <> name <> ".beam"
      bytes = File.read!(Path.join(output, relative))
      assert files[relative]["sha256"] == Ipse.JSON.sha256(bytes)
      assert files[relative]["bytes"] == byte_size(bytes)
    end

    refute :code.is_loaded(IpseKnowledge.Documents)
  end

  test "Cargo diagnostics never become metadata JSON, including colored fresh-cache output", %{
    root: root
  } do
    parser = Path.join(root, "native/ipse-pdf")
    File.mkdir_p!(Path.join(parser, "notices"))
    File.cp!("native/ipse-pdf/build.exs", Path.join(parser, "build.exs"))
    File.cp!("LICENSE", Path.join(root, "LICENSE"))

    for {name, bytes} <- [
          {"dependency-inventory.json", JSON.encode!(%{"packages" => []})},
          {"Cargo.lock", "synthetic fixture"},
          {"Cargo.toml", "synthetic fixture"},
          {"DEPENDENCIES.md", "synthetic fixture"}
        ],
        do: File.write!(Path.join(parser, name), bytes)

    cargo = Path.join(root, "tools/cargo")

    File.write!(cargo, """
    #!/bin/sh
    printf '\\033[31mSynthetic Cargo diagnostic\\033[0m\\n' >&2
    case "$1" in
      metadata) printf '%s' "$IPSE_FAKE_METADATA" ;;
      build) mkdir -p "$CARGO_TARGET_DIR/release"; printf parser > "$CARGO_TARGET_DIR/release/ipse-pdf" ;;
      *) exit 9 ;;
    esac
    """)

    File.chmod!(cargo, 0o755)

    args = [
      Path.join(parser, "build.exs"),
      "--output",
      Path.join(root, "output/ipse-pdf"),
      "--notices",
      Path.join(root, "output/notices")
    ]

    env = [
      {"PATH", Path.join(root, "tools") <> ":" <> System.get_env("PATH")},
      {"CARGO_TERM_COLOR", "always"},
      {"IPSE_FAKE_METADATA", JSON.encode!(%{"packages" => [%{"name" => "ipse-pdf"}]})}
    ]

    {log, status} =
      System.cmd(System.find_executable("elixir"), args, env: env, stderr_to_stdout: true)

    assert status == 0, log
    assert log =~ "Synthetic Cargo diagnostic"
    assert File.read!(Path.join(root, "output/ipse-pdf")) == "parser"
    File.rm_rf!(Path.join(root, "output"))

    {log, status} =
      System.cmd(System.find_executable("elixir"), args,
        env: List.keystore(env, "IPSE_FAKE_METADATA", 0, {"IPSE_FAKE_METADATA", "not JSON"}),
        stderr_to_stdout: true
      )

    assert status != 0, log
    refute File.exists?(Path.join(root, "output"))
  end
end
