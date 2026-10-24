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

  test "release asset set requires both platforms and refuses extras or damaged content", %{
    root: root
  } do
    for platform <- ~w(linux-x86_64-glibc-2.39 darwin-arm64) do
      path = Path.join(root, "ipse-0.1.0-#{platform}.tar.gz")
      File.write!(path, platform)
      Release.write_checksum!(path)
    end

    assert :ok = Release.verify_assets!(root)
    File.write!(Path.join(root, "unexpected"), "extra")
    assert_raise RuntimeError, ~r/exactly/, fn -> Release.verify_assets!(root) end
    File.rm!(Path.join(root, "unexpected"))
    [path | _] = Path.wildcard(Path.join(root, "*.tar.gz"))
    File.write!(path, "damaged")
    assert_raise RuntimeError, ~r/mismatching/, fn -> Release.verify_assets!(root) end
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
