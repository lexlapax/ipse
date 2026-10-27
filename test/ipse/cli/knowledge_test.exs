defmodule Ipse.CLI.KnowledgeTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  test "unsupported setup flags cannot widen or bypass knowledge review" do
    for flag <- ["--yes", "--accept-edits", "--write", "--provider=demo", "--model=scripted"] do
      capture_io(:stderr, fn ->
        assert Ipse.CLI.run(["knowledge", "enable", flag]) == 1
      end)
    end
  end

  test "native setup saves exact permission, activates a new headless session and revokes" do
    assert scenario("save", "--knowledge") =~ "KNOWLEDGE_NATIVE_SETUP_SAVE_DISABLE_PASSED"
  end

  test "bare yes and a mismatched native challenge cannot grant permission" do
    for {name, mode} <- [{"cancel", "--knowledge-cancel"}, {"stale", "--knowledge-stale"}] do
      assert scenario(name, mode) =~ "KNOWLEDGE_NATIVE_REVIEW_CANCELLED"
    end
  end

  test "piped input cannot grant permission or create a project identity" do
    assert scenario("pipe", nil) =~ "KNOWLEDGE_NATIVE_PIPE_REFUSED"
  end

  test "a concurrent consent epoch change cannot be overwritten by a reviewed grant" do
    assert scenario("cas", "--knowledge-cas") =~ "KNOWLEDGE_NATIVE_REVIEW_CANCELLED"
  end

  test "review data binds actual bundled recipes and routes without creating consent" do
    root = private_root()
    home = Path.join(root, "home")
    cwd = Path.join(root, "project")
    File.mkdir!(home)
    File.chmod!(home, 0o700)
    File.mkdir!(cwd)

    client = %{
      workspace: cwd,
      home: home,
      auth_dir: Path.join(home, "auth"),
      operator_home: root,
      mcp_config: nil,
      base_url: nil,
      operator_questions: false,
      accept_edits: false,
      approval: :ask,
      approval_origin: :interactive,
      headless: false
    }

    assert {:ok, effective} =
             Ipse.Config.resolve(
               cwd,
               home,
               [provider: "demo", model: "scripted", project_config: false],
               %{}
             )

    assert {:ok, config} = Ipse.Config.runtime(effective, client)
    assert {:ok, binding} = Ipse.Extension.ProjectIdentity.admit(home, cwd, :folder)
    assert {:ok, artifact} = Ipse.Extension.Bundles.install("knowledge", home)
    control = Ipse.Extension.SemanticAdmission.control_root(home)
    refute File.exists?(control)
    now = System.system_time(:millisecond)

    assert {:ok, %{policy: policy}} =
             Ipse.CLI.Knowledge.prepare(config, binding, artifact.digest, now)

    assert Ipse.Extension.SemanticConsent.policy?(policy)
    assert policy["settings"]["activation"]["artifact_sha256"] == artifact.digest
    assert policy["settings"]["activation"]["main_timeout_ms"] == 90_000
    assert policy["settings"]["routes"] |> Enum.map(& &1["operation"]) == ["main"]
    assert length(policy["settings"]["effects"]) == 6
    assert map_size(policy["settings"]["recipes"]) == 2
    assert policy["limits"]["model_calls"] == 0
    assert policy["limits"]["cost_nanos"] == 0
    assert policy["expires_at_ms"] == now + 365 * 86_400_000

    assert {:error, _} =
             Ipse.CLI.Knowledge.prepare(
               %{config | timeout_ms: 999},
               binding,
               artifact.digest,
               now
             )

    assert {:error, _} =
             Ipse.CLI.Knowledge.prepare(config, binding, String.duplicate("0", 64), now)

    refute File.exists?(control)

    installed = Path.join([home, "extensions/artifacts", artifact.digest, "operator.json"])
    File.chmod!(installed, 0o600)
    File.write!(installed, "{}")
    assert {:error, _} = Ipse.CLI.Knowledge.prepare(config, binding, artifact.digest, now)
    refute File.exists?(control)
  end

  defp scenario(name, mode) do
    root = private_root()

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    args =
      ["--erl", "+S 2:2"] ++
        paths ++ [Path.expand("test/support/knowledge_setup.exs"), root, name]

    {executable, args} =
      if mode do
        driver = Path.join(root, "pty")

        assert {_, 0} =
                 System.cmd(
                   "rustc",
                   [
                     "--edition=2021",
                     "-D",
                     "warnings",
                     "test/support/operator_pty.rs",
                     "-o",
                     driver
                   ],
                   stderr_to_stdout: true
                 )

        {driver, [mode, System.find_executable("elixir") | args]}
      else
        {System.find_executable("elixir"), args}
      end

    {output, status} = System.cmd(executable, args, stderr_to_stdout: true)
    assert status == 0, output
    output
  end

  defp private_root do
    root = Path.join(System.tmp_dir!(), "ipse-knowledge-setup-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end
end
