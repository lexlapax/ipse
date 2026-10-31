defmodule Ipse.Session.ManagedOutputNativeTest do
  use ExUnit.Case, async: false
  @moduletag timeout: 120_000

  test "a genuinely reviewed short literal expires during an explicit worker read" do
    root = Path.join(System.tmp_dir!(), "ipse-output-literal-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    runtime = Path.join(root, "lib/ipse")
    File.mkdir_p!(runtime)
    File.cp_r!(Application.app_dir(:ipse, "ebin"), Path.join(runtime, "ebin"))
    assert {:ok, priv} = Ipse.Workspace.canonical_path(Application.app_dir(:ipse, "priv"))
    File.cp_r!(priv, Path.join(runtime, "priv"))

    for dependency <- ~w(jason jsonschex ex_json_pointer) do
      File.ln_s!(
        Application.app_dir(String.to_existing_atom(dependency)),
        Path.join(root, "lib/" <> dependency)
      )
    end

    sources = Path.join(root, "sources/extensions/knowledge")
    File.mkdir_p!(Path.dirname(sources))
    File.cp_r!("extensions/knowledge", sources)
    File.cp!("LICENSE", Path.join(root, "sources/LICENSE"))
    entry = Path.join(sources, "src/knowledge.ex")
    before = "defp advance(:recall_read_only, value, state), do: finish(state, value)"
    assert length(:binary.matches(File.read!(entry), before)) == 1

    source = File.read!(entry)
    subscriptions = ~r/"subscriptions" => \[.*?\n      \],/s
    assert length(Regex.scan(subscriptions, source)) == 1
    # This fixture isolates explicit read/release; automatic recall has its own
    # native controls and must not consume the short lifetime before this read.
    source = Regex.replace(subscriptions, source, "")
    jobs = ~r/"jobs" => \[\n\s+entry\(.*?\n\s+\)\n\s+\]/s
    assert length(Regex.scan(jobs, source)) == 1
    source = Regex.replace(jobs, source, "\"jobs\" => []")
    profiles = Path.join(sources, "src/profiles.ex")
    profile_source = File.read!(profiles)
    assert length(:binary.matches(profile_source, "host.context event.job)")) == 1

    File.write!(
      profiles,
      String.replace(profile_source, "host.context event.job)", "host.context)")
    )

    File.write!(
      entry,
      String.replace(
        source,
        before,
        "defp advance(:recall_read_only, value, state) do\n" <>
          "Process.sleep(4000)\nfinish(state, value)\nend"
      )
    )

    bundle_root = Path.join(runtime, "priv/extension-bundles")
    File.rm_rf!(bundle_root)
    output = Path.join(bundle_root, "knowledge")

    {text, status} =
      System.cmd(
        System.find_executable("elixir"),
        [
          Path.join(sources, "build.exs"),
          "--sdk",
          Path.join(runtime, "ebin"),
          "--output",
          output,
          "--package",
          "knowledge",
          "--preset",
          "native"
        ],
        stderr_to_stdout: true,
        env: [{"ERL_FLAGS", "+S 2:2"}]
      )

    assert status == 0, text
    manifest = File.read!(Path.join(output, "extension.json"))

    File.write!(
      Path.join(bundle_root, "catalog.json"),
      Jason.encode!(%{
        "version" => 1,
        "artifacts" => [
          %{
            "id" => "knowledge",
            "path" => "knowledge",
            "manifest_sha256" => Ipse.JSON.sha256(manifest)
          }
        ]
      })
    )

    assert {:ok, [_]} = Ipse.Extension.Bundles.inventory(bundle_root)

    driver = Path.join(root, "pty")

    assert {"", 0} =
             System.cmd(
               "rustc",
               ["--edition=2021", "-D", "warnings", "test/support/operator_pty.rs", "-o", driver],
               stderr_to_stdout: true
             )

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "." or Path.expand(&1) == Application.app_dir(:ipse, "ebin")))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    {text, status} =
      System.cmd(
        driver,
        ["--assertion", System.find_executable("elixir"), "--erl", "+S 2:2"] ++
          paths ++
          [
            "-pa",
            Path.join(runtime, "ebin"),
            Path.expand("test/support/managed_output_expiry.exs"),
            root,
            "save"
          ],
        stderr_to_stdout: true
      )

    assert status == 0, text
    assert text =~ "NATIVE_MANAGED_OUTPUT_LITERAL_EXPIRY_PASSED"
  end
end
