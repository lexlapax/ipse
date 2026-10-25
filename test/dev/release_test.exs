Code.require_file("../../dev/release.exs", __DIR__)

defmodule Ipse.Development.ReleaseTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.Release

  test "draft release matrix retains every ordinary CI verification step" do
    ci = File.read!(Path.expand("../../.github/workflows/ci.yml", __DIR__))
    release = File.read!(Path.expand("../../.github/workflows/release.yml", __DIR__))
    [_, steps] = String.split(ci, "    steps:\n", parts: 2)
    assert String.contains?(release, "    steps:\n" <> steps)
    assert release =~ "--draft --verify-tag"
    assert release =~ "verify_assets!"
    refute release =~ "--draft=false"
  end

  test "draft mutation follows both verified platform artifacts and manual validation never publishes" do
    release = File.read!(Path.expand("../../.github/workflows/release.yml", __DIR__))
    assert_release_policy!(release)

    for weakened <- [
          String.replace(
            release,
            "permissions:\n  contents: read",
            "permissions:\n  contents: write"
          ),
          String.replace(
            release,
            "        if: github.event_name == 'push'",
            "        if: always()",
            global: false
          ),
          String.replace(release, "gh release upload", "gh release edit"),
          String.replace(release, "gh release upload", "gh api"),
          String.replace(
            release,
            "          gh --version",
            "          gh --version\n          gh api repos/owner/repo/releases --method POST"
          ),
          String.replace(
            release,
            "          gh --version",
            "          gh --version\n          gh release edit tag --draft=false"
          ),
          String.replace(
            release,
            "      - name: Admit the complete asset set before creating any draft",
            "      - name: Premature upload\n        run: gh release upload tag assets\n      - name: Admit the complete asset set before creating any draft"
          )
        ] do
      assert_raise ExUnit.AssertionError, fn -> assert_release_policy!(weakened) end
    end
  end

  defp assert_release_policy!(release) do
    [header | _] = String.split(release, "jobs:\n", parts: 2)
    assert header =~ "permissions:\n  contents: read\n"
    [_, prepare, matrix, draft] = Regex.split(~r/^  (?:prepare|test|draft):\n/m, release)

    for job <- [prepare, matrix] do
      refute job =~ "gh release create"
      refute job =~ "gh release upload"
    end

    assert matrix =~ "actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9"
    assert draft =~ "actions/download-artifact@9000827ccba6bdab643e8b6fd33ac0654aef8333"
    assert matrix =~ "if-no-files-found: error"
    assert draft =~ "needs: [prepare, test]"
    assert {admit, _} = :binary.match(draft, "Release.verify_assets!")
    assert {create, _} = :binary.match(draft, "gh release create")
    assert {upload, _} = :binary.match(draft, "gh release upload")
    assert admit < create
    assert admit < upload
    assert release =~ "workflow_dispatch:"
    assert prepare =~ "GITHUB_EVENT_NAME"
    blocks = Regex.split(~r/(?=^      - name:)/m, draft)

    for name <- [
          "Create or recover an unpublished draft and attach all verified assets",
          "Re-download and inspect the complete draft asset set"
        ] do
      block = Enum.find(blocks, &String.starts_with?(&1, "      - name: " <> name <> "\n"))
      assert is_binary(block)
      assert block =~ "        if: github.event_name == 'push'\n"
    end

    for [command | args] <-
          Regex.scan(~r/\bgh\s+([a-z-]+)(?:\s+([a-z-]+))?/, release, capture: :all_but_first) do
      if command == "--version" do
        assert args in [[], [""]]
      else
        assert command == "release"
        assert List.first(args) in ~w(view create upload download)
      end
    end

    refute Regex.match?(~r/--draft(?:=|\s+)false/, release)
    assert draft =~ "gh release create \"$IPSE_RELEASE_TAG\" --draft --verify-tag"
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-release-test-" <> Ipse.Usage.id())
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "sidecar binds exact archive bytes and basename in portable checksum format", %{root: root} do
    archive = Path.join(root, "ipse-fixture.tar.gz")
    bytes = String.duplicate("fixture", 30_000)
    File.write!(archive, bytes)
    Release.write_checksum!(archive)

    assert File.read!(archive <> ".sha256") ==
             Ipse.JSON.sha256(bytes) <> "  ipse-fixture.tar.gz\n"

    assert :ok = Release.verify_checksum!(archive)
    File.write!(archive, "corrupt", [:append])
    assert_raise RuntimeError, ~r/mismatching/, fn -> Release.verify_checksum!(archive) end
    Release.write_checksum!(archive)
    File.write!(archive <> ".sha256", Release.checksum(archive) <> "  other.tar.gz\n")
    assert_raise RuntimeError, ~r/malformed/, fn -> Release.verify_checksum!(archive) end
    File.rm!(archive <> ".sha256")
    assert_raise RuntimeError, ~r/Missing/, fn -> Release.verify_checksum!(archive) end
  end

  test "only the matching stable or numbered RC tag with actual notes is admitted", %{root: root} do
    notes = Path.join(root, "docs/releases/v1.2.3.md")
    File.mkdir_p!(Path.dirname(notes))
    File.write!(notes, "release fixture")

    for tag <- ["v1.2.3", "v1.2.3-rc.1", "v1.2.3-rc.25"],
        do: assert(Release.validate_tag!(tag, "1.2.3", root) == notes)

    for tag <- ["v1.2.4", "v1.2.3-rc.0", "v1.2.3-extra", "v1x2x3", "v1.2.3\n"],
        do: assert_raise(RuntimeError, fn -> Release.validate_tag!(tag, "1.2.3", root) end)

    File.rm!(notes)
    assert_raise RuntimeError, ~r/notes/, fn -> Release.validate_tag!("v1.2.3", "1.2.3", root) end
  end

  test "checksum admission refuses linked, missing, empty and non-file archives", %{root: root} do
    archive = Path.join(root, "fixture.tar.gz")
    target = Path.join(root, "external")
    File.write!(target, "synthetic bytes")
    File.ln_s!(target, archive)
    Release.write_checksum!(archive)

    assert_raise RuntimeError, ~r/non-regular/, fn -> Release.verify_checksum!(archive) end
    assert File.read!(target) == "synthetic bytes"
    File.rm!(archive)
    assert_raise RuntimeError, fn -> Release.verify_checksum!(archive) end
    File.write!(archive, "")
    Release.write_checksum!(archive)
    assert_raise RuntimeError, ~r/empty/, fn -> Release.verify_checksum!(archive) end
    File.rm!(archive)
    File.mkdir!(archive)
    assert_raise RuntimeError, ~r/non-regular/, fn -> Release.verify_checksum!(archive) end
    File.rmdir!(archive)
    File.write!(archive, "regular bytes")
    Release.write_checksum!(archive)
    sidecar = archive <> ".sha256"
    File.rename!(sidecar, target)
    File.ln_s!(target, sidecar)
    assert_raise RuntimeError, ~r/non-regular/, fn -> Release.verify_checksum!(archive) end
  end

  test "release asset set requires both platforms and refuses extras or damaged content", %{
    root: root
  } do
    for platform <- ~w(linux-x86_64-glibc-2.39 darwin-arm64) do
      path = Path.join(root, "ipse-0.1.0-#{platform}.tar.gz")
      File.write!(path, platform)
      Release.write_checksum!(path)
    end

    assert :ok = Release.verify_assets!(root, "0.1.0")
    File.write!(Path.join(root, "unexpected"), "extra")
    assert_raise RuntimeError, ~r/exactly/, fn -> Release.verify_assets!(root, "0.1.0") end
    File.rm!(Path.join(root, "unexpected"))
    [path | _] = Path.wildcard(Path.join(root, "*.tar.gz"))
    File.write!(path, "damaged")
    assert_raise RuntimeError, ~r/mismatching/, fn -> Release.verify_assets!(root, "0.1.0") end
  end

  test "asset admission rejects wrong versions, prefixes, architectures and platform substrings",
       %{root: root} do
    for linux <- [
          "other-0.1.0-linux-x86_64-glibc-2.39.tar.gz",
          "ipse-9.9.9-linux-x86_64-glibc-2.39.tar.gz",
          "ipse-0.1.0-linux-wrong-glibc-2.39.tar.gz",
          "ipse-0.1.0-linux-x86_64-glibc-2.39-extra.tar.gz"
        ] do
      paths = [Path.join(root, linux), Path.join(root, "ipse-0.1.0-darwin-arm64.tar.gz")]

      for path <- paths do
        File.write!(path, "fixture")
        Release.write_checksum!(path)
      end

      assert_raise RuntimeError, ~r/exactly/, fn -> Release.verify_assets!(root, "0.1.0") end
      for path <- paths, suffix <- ["", ".sha256"], do: File.rm!(path <> suffix)
    end
  end

  test "RC release notes link to their actual tag without waiting for a stable tag", %{root: root} do
    source = Path.join(root, "docs/releases/v1.2.3.md")
    File.mkdir_p!(Path.dirname(source))

    File.write!(
      source,
      "[Install](https://github.com/lexlapax/ipse/blob/v1.2.3/docs/operator/install.md#complete-first-run)"
    )

    output = Path.join(root, "rendered.md")
    assert Release.release_notes!("v1.2.3-rc.1", "1.2.3", root, output) == output
    assert File.read!(output) =~ "/blob/v1.2.3-rc.1/"
    refute File.read!(output) =~ "/blob/v1.2.3/"
    Release.release_notes!("v1.2.3", "1.2.3", root, output)
    assert File.read!(output) == File.read!(source)
  end

  test "launcher follows relative links with spaces, preserves cwd and bounds link depth", %{
    root: root
  } do
    release = Path.join(root, "release directory")
    links = Path.join(root, "local bin")
    cwd = Path.join(root, "caller workspace")
    for path <- [Path.join(release, "bin"), links, cwd], do: File.mkdir_p!(path)
    launcher = Path.join(release, "ipse")
    File.cp!(Path.expand("../../dev/release-launcher.sh", __DIR__), launcher)
    File.chmod!(launcher, 0o755)

    File.write!(
      Path.join(release, "bin/ipse"),
      "#!/bin/sh\nprintf '%s\\n' \"$IPSE_WORKSPACE\" \"$PWD\" \"$@\"\n"
    )

    File.chmod!(Path.join(release, "bin/ipse"), 0o755)
    second = Path.join(links, "second")
    File.ln_s!("../release directory/ipse", second)
    link = Path.join(links, "ipse")
    File.ln_s!("second", link)
    {output, 0} = System.cmd(link, ["argument with spaces"], cd: cwd)

    assert String.split(output, "\n", trim: true) == [
             cwd,
             cwd,
             "eval",
             "Ipse.CLI.main(System.argv())",
             "argument with spaces"
           ]

    # Invoke the real script through sh so the OS's own symlink ceiling does not
    # prevent the launcher's separate bounded-loop control from being exercised.
    for index <- 1..41,
        do:
          File.ln_s!(
            if(index == 41, do: second, else: "link#{index + 1}"),
            Path.join(links, "link#{index}")
          )

    {output, 1} =
      System.cmd("sh", ["-c", ". \"$1\"", Path.join(links, "link1"), launcher],
        cd: cwd,
        stderr_to_stdout: true
      )

    assert output =~ "too many symlinks; inspect the installation link"
  end

  defp documentation_fixture(root) do
    source = Path.join(root, "source")
    bundle = Path.join(root, "bundle")

    for path <-
          ~w(README.md docs/index.md docs/operator/index.md docs/operator/install.md docs/operator/usage.md docs/developer/index.md) do
      for directory <- [source, bundle] do
        target = Path.join(directory, path)
        File.mkdir_p!(Path.dirname(target))
        File.write!(target, "# Fixture\n")
      end
    end

    for path <- ["lib/helper.ex", "examples/read me.md", "docs/archive/old/index.md"] do
      target = Path.join(source, path)
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, "source fixture\n")
    end

    File.mkdir!(Path.join(source, "native"))
    {source, bundle}
  end

  defp documentation_archive!(root, bundle) do
    archive = Path.join(root, "docs.tar.gz")
    {_, 0} = System.cmd("tar", ["-czf", archive, "-C", bundle, "."])
    archive
  end

  test "bundled manuals retain local pages and pin omitted source/history references", %{
    root: root
  } do
    {source, bundle} = documentation_fixture(root)
    commit = String.duplicate("a", 40)

    document =
      "[Install](docs/operator/install.md#fixture) [Source](lib/helper.ex) [History](docs/archive/old/index.md) [Directory](native/) [Spaced](<examples/read me.md>) [External](https://example.test/page) [Here](#fixture)\n````text\n[Literal](missing.example)\n```\n````\n~~~text\n[Literal](also-missing.example)\n~~~\n"

    File.write!(Path.join(bundle, "README.md"), document)
    notice = Path.join(bundle, "licenses/vendor-README.md")
    File.mkdir_p!(Path.dirname(notice))
    notice_bytes = "Upstream notice. [Original link](not-distributed.example)\n"
    File.write!(notice, notice_bytes)

    manifest = Release.bundle_documentation!(bundle, source, "0.1.0", commit)
    assert manifest["rewritten_links"] == 4
    assert manifest["source_ref_kind"] == "commit"
    rendered = File.read!(Path.join(bundle, "README.md"))
    assert rendered =~ "[Install](docs/operator/install.md#fixture)"
    assert rendered =~ "[Source](https://github.com/lexlapax/ipse/blob/#{commit}/lib/helper.ex)"
    assert rendered =~ "[Directory](https://github.com/lexlapax/ipse/tree/#{commit}/native)"

    assert rendered =~
             "[Spaced](<https://github.com/lexlapax/ipse/blob/#{commit}/examples/read%20me.md>)"

    assert rendered =~ "[External](https://example.test/page) [Here](#fixture)"
    assert rendered =~ "````text\n[Literal](missing.example)\n```\n````"
    assert rendered =~ "~~~text\n[Literal](also-missing.example)\n~~~"
    refute File.exists?(Path.join(bundle, "docs/archive"))
    assert File.read!(notice) == notice_bytes

    assert Release.verify_documentation_archive!(documentation_archive!(root, bundle)) == %{
             "documents" => 6,
             "source_ref" => commit,
             "missing_local_targets" => 0
           }

    assert File.read!(Path.join(source, "docs/archive/old/index.md")) == "source fixture\n"
  end

  test "documentation admission detects an omitted bundled page or unrendered source link", %{
    root: root
  } do
    {source, bundle} = documentation_fixture(root)
    Release.bundle_documentation!(bundle, source, "0.1.0", String.duplicate("b", 40))
    File.write!(Path.join(bundle, "README.md"), "[Missing](lib/helper.ex)\n")

    assert_raise RuntimeError, ~r/Missing bundled documentation target/, fn ->
      Release.verify_documentation_archive!(documentation_archive!(root, bundle))
    end

    File.write!(Path.join(bundle, "README.md"), "# Fixture\n")
    File.rm!(Path.join(bundle, "docs/operator/usage.md"))

    assert_raise MatchError, fn ->
      Release.verify_documentation_archive!(documentation_archive!(root, bundle))
    end
  end

  test "documentation rendering refuses unknown or escaping targets and labels version fallback",
       %{root: root} do
    {source, bundle} = documentation_fixture(root)
    manifest = Release.bundle_documentation!(bundle, source, "0.1.0")
    assert manifest["source_ref"] == "v0.1.0"
    assert manifest["source_ref_kind"] == "version_tag"

    assert Release.verify_documentation_archive!(documentation_archive!(root, bundle))[
             "source_ref"
           ] == "v0.1.0"

    manifest_path = Path.join(bundle, "docs/bundle-links.json")

    File.write!(manifest_path, :json.encode(%{manifest | "source_ref_kind" => "commit"}))

    assert_raise MatchError, fn ->
      Release.verify_documentation_archive!(documentation_archive!(root, bundle))
    end

    File.write!(Path.join(bundle, "README.md"), "[Unknown](missing.md)\n")

    assert_raise RuntimeError, ~r/missing from the source/, fn ->
      Release.bundle_documentation!(bundle, source, "0.1.0")
    end

    File.write!(Path.join(bundle, "README.md"), "[Escape](../outside.md)\n")
    File.write!(Path.join(root, "outside.md"), "private fixture")

    assert_raise RuntimeError, ~r/escapes/, fn ->
      Release.bundle_documentation!(bundle, source, "0.1.0")
    end

    assert File.read!(Path.join(root, "outside.md")) == "private fixture"
  end

  defp notice_fixture do
    contents = %{
      "LICENSE" => "Elixir upstream fixture\n",
      "NOTICE" => "Old upstream notice\n",
      "LICENSES/BSD-3-Clause.txt" => "New component notice\n",
      "LICENSE.txt" => "OTP upstream fixture\n"
    }

    blobs =
      Map.new(contents, fn {path, bytes} ->
        sha =
          :crypto.hash(:sha, ["blob #{byte_size(bytes)}", <<0>>, bytes])
          |> Base.encode16(case: :lower)

        {path,
         {%{"path" => path, "type" => "blob", "size" => byte_size(bytes), "sha" => sha},
          %{"encoding" => "base64", "content" => Base.encode64(bytes)}}}
      end)

    fetch = fn path ->
      cond do
        path == "repos/elixir-lang/elixir/git/trees/v1.20.4?recursive=1" ->
          %{
            "truncated" => false,
            "sha" => String.duplicate("a", 40),
            "tree" =>
              for(key <- ~w(LICENSE NOTICE LICENSES/BSD-3-Clause.txt), do: elem(blobs[key], 0))
          }

        path == "repos/erlang/otp/git/trees/OTP-29.1.1?recursive=1" ->
          %{
            "truncated" => false,
            "sha" => String.duplicate("b", 40),
            "tree" => [elem(blobs["LICENSE.txt"], 0)]
          }

        true ->
          Enum.find_value(blobs, fn {_, {item, blob}} ->
            if String.ends_with?(path, "/" <> item["sha"]), do: blob
          end) || flunk("unexpected notice request")
      end
    end

    {contents, fetch}
  end

  test "runtime notices retain both upstream layouts and bind exact decoded bytes and versions",
       %{root: root} do
    {contents, fetch} = notice_fixture()
    destination = Path.join(root, "notices")
    manifest = Release.runtime_notices!(destination, versions: {"1.20.4", "29.1.1"}, fetch: fetch)
    assert manifest["elixir"] == "1.20.4"
    assert manifest["otp"] == "29.1.1"

    for {path, bytes} <- contents do
      prefix = if path == "LICENSE.txt", do: "otp", else: "elixir"
      assert File.read!(Path.join([destination, prefix, path])) == bytes
    end

    for source <- manifest["sources"], file <- source["files"] do
      assert Release.checksum(Path.join(destination, file["path"])) == file["sha256"]

      assert file["source"] =~
               "https://api.github.com/repos/" <> source["repository"] <> "/git/blobs/"
    end

    assert :json.decode(File.read!(Path.join(destination, "runtime-notices.json"))) == manifest

    assert_raise RuntimeError, ~r/already exists/, fn ->
      Release.runtime_notices!(destination,
        versions: {"1.20.4", "29.1.1"},
        fetch: fn _ -> flunk("existing destination must not fetch") end
      )
    end
  end

  test "truncated trees, missing required files, unsafe paths and changed blob bytes stop publication",
       %{root: root} do
    {_, fetch} = notice_fixture()

    for corruption <- [:truncated, :missing, :escape, :changed, :oversized] do
      tampered = fn path ->
        data = fetch.(path)

        if String.contains?(path, "/git/trees/") do
          case corruption do
            :truncated ->
              Map.put(data, "truncated", true)

            :missing ->
              Map.put(data, "tree", [])

            :escape ->
              Map.update!(
                data,
                "tree",
                &(&1 ++
                    [
                      %{
                        "type" => "blob",
                        "path" => "../LICENSE",
                        "sha" => String.duplicate("c", 40),
                        "size" => 1
                      }
                    ])
              )

            :oversized ->
              Map.update!(data, "tree", fn items ->
                Enum.map(items, &Map.put(&1, "size", 1_048_577))
              end)

            _ ->
              data
          end
        else
          if corruption == :changed,
            do: Map.put(data, "content", Base.encode64("changed upstream bytes")),
            else: data
        end
      end

      destination = Path.join(root, Atom.to_string(corruption))

      assert_raise RuntimeError, fn ->
        Release.runtime_notices!(destination, versions: {"1.20.4", "29.1.1"}, fetch: tampered)
      end

      refute File.exists?(Path.join(destination, "runtime-notices.json"))
      refute File.exists?(Path.join(root, "LICENSE"))
    end
  end
end
