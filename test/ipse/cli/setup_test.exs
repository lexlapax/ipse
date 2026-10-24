Code.require_file("../../support/cli_fixture.ex", __DIR__)

defmodule Ipse.CLI.SetupTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias Ipse.CLITest.IOFixture

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-setup-" <> Ipse.Usage.id())
    cwd = Path.join(root, "workspace")
    home = Path.join(root, "operator")
    File.mkdir_p!(cwd)

    keys =
      ~w(IPSE_HOME IPSE_CONFIG IPSE_PROFILE) ++
        Enum.map(
          Map.keys(Ipse.Config.settings_schema()["properties"]),
          &("IPSE_" <> String.upcase(&1))
        )

    previous = Map.new(keys, &{&1, System.get_env(&1)})
    Enum.each(keys, &System.delete_env/1)
    System.put_env("IPSE_HOME", home)

    on_exit(fn ->
      for {key, value} <- previous do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end

      File.rm_rf!(root)
    end)

    %{root: root, cwd: cwd, home: home, path: Path.join(home, "config.json")}
  end

  defp args(c, extra \\ []),
    do: ["setup", "--cwd", c.cwd, "--provider", "demo", "--model", "scripted"] ++ extra

  test "dry run previews exact bounded JSON and changes no files", c do
    key = "fixture-setup-private-key"
    previous = System.get_env("OPENAI_API_KEY")
    System.put_env("OPENAI_API_KEY", key)

    on_exit(fn ->
      if previous,
        do: System.put_env("OPENAI_API_KEY", previous),
        else: System.delete_env("OPENAI_API_KEY")
    end)

    output = capture_io(fn -> assert Ipse.CLI.run(args(c)) == 0 end)
    assert output =~ "Dry run; add --write"
    assert output =~ "\"provider\": \"demo\""
    assert output =~ "none billing"
    refute output =~ key
    refute File.exists?(c.home)
  end

  test "explicit write creates private configuration that resolves from the operator file", c do
    capture_io(fn -> assert Ipse.CLI.run(args(c, ["--write"])) == 0 end)
    assert Bitwise.band(File.stat!(c.home).mode, 0o777) == 0o700
    assert Bitwise.band(File.stat!(c.path).mode, 0o777) == 0o600
    assert File.ls!(c.home) == ["config.json"]
    {:ok, effective} = Ipse.Config.resolve(c.cwd, c.home, [project_config: false], %{})
    assert effective.settings["provider"] == "demo"
    assert effective.provenance["provider"] == c.path
    refute File.exists?(Path.join(c.home, "auth"))
    refute File.exists?(Path.join(c.home, "sessions"))
  end

  test "existing target refuses without replace and preserves all bytes", c do
    File.mkdir_p!(c.home)
    bytes = Jason.encode!(%{version: 1, settings: %{provider: "ollama", model: "old"}})
    File.write!(c.path, bytes)

    output =
      capture_io(fn ->
        error = capture_io(:stderr, fn -> assert Ipse.CLI.run(args(c, ["--write"])) == 1 end)
        assert error =~ "Configuration already exists."
      end)

    assert output =~ "provider ollama"
    assert File.read!(c.path) == bytes
    assert File.ls!(c.home) == ["config.json"]
  end

  test "replacement retains unrelated settings and top-level values with a private exact backup",
       c do
    File.mkdir_p!(c.home)

    before = %{
      "version" => 1,
      "settings" => %{"provider" => "ollama", "model" => "old", "max_steps" => 7},
      "profiles" => %{"unused" => %{"provider" => "ollama", "model" => "kept"}},
      "roles" => %{},
      "extension_trust" => [],
      "extensions" => []
    }

    bytes = Jason.encode!(before)
    File.write!(c.path, bytes)
    File.chmod!(c.path, 0o644)
    capture_io(fn -> assert Ipse.CLI.run(args(c, ["--replace", "--write"])) == 0 end)
    after_doc = Jason.decode!(File.read!(c.path))
    assert Map.drop(after_doc, ["settings"]) == Map.drop(before, ["settings"])

    assert after_doc["settings"] == %{
             "provider" => "demo",
             "model" => "scripted",
             "sandbox" => "off",
             "max_steps" => 7
           }

    [backup] = Path.wildcard(c.path <> ".bak-*")
    assert Regex.match?(~r/\.bak-[0-9]{8}T[0-9]{6}Z\z/, backup)
    assert File.read!(backup) == bytes
    for path <- [backup, c.path], do: assert(Bitwise.band(File.stat!(path).mode, 0o777) == 0o600)
  end

  test "interactive setup requires a TTY and scoped write flags do not authorize other commands",
       c do
    assert capture_io(:stderr, fn -> assert Ipse.CLI.run(["setup", "--cwd", c.cwd]) == 1 end) =~
             "Interactive setup requires a TTY."

    for command <- ["run", "chat", "doctor"] do
      assert capture_io(:stderr, fn -> assert Ipse.CLI.run([command, "--write"]) == 1 end) =~
               "--write and --replace require ipse setup"
    end

    refute File.exists?(c.home)
  end

  test "interactive empty provider re-asks and typed write confirms the displayed file", c do
    lines =
      ["", "demo", ""] ++ if(:os.type() == {:unix, :linux}, do: [""], else: []) ++ ["write", :eof]

    {code, output} = interactive(c, lines)
    assert code == 0
    assert output =~ "Choose a listed provider; no default was selected."
    assert output =~ "OpenAI API (billed)"
    assert output =~ "Anthropic API (billed)"
    assert output =~ "Type write to save"
    assert output =~ File.read!(c.path)
    refute output =~ "Run ipse login now?"
  end

  test "cancelling the interactive preview writes nothing", c do
    lines =
      ["demo", ""] ++ if(:os.type() == {:unix, :linux}, do: [""], else: []) ++ ["cancel", :eof]

    {0, output} = interactive(c, lines)
    assert output =~ "Setup cancelled; no configuration was written."
    refute File.exists?(c.home)
  end

  test "normal admission rejects a preserved incompatible cap before any backup or write", c do
    File.mkdir_p!(c.home)

    before =
      Jason.encode!(%{
        version: 1,
        settings: %{provider: "openai", model: "fixture", max_output_tokens: 32}
      })

    File.write!(c.path, before)

    error =
      capture_io(:stderr, fn ->
        capture_io(fn ->
          assert Ipse.CLI.run([
                   "setup",
                   "--cwd",
                   c.cwd,
                   "--provider",
                   "chatgpt",
                   "--model",
                   "gpt-6.1-sol",
                   "--replace",
                   "--write"
                 ]) == 1
        end)
      end)

    assert error =~ "ChatGPT subscription does not support max_output_tokens"
    assert File.read!(c.path) == before
    assert File.ls!(c.home) == ["config.json"]
  end

  test "environment route conflicts refuse before creating configuration", c do
    System.put_env("IPSE_PROVIDER", "ollama")

    error =
      capture_io(:stderr, fn ->
        capture_io(fn -> assert Ipse.CLI.run(args(c, ["--write"])) == 1 end)
      end)

    assert error =~ "Environment or profile settings override the proposed route"
    refute File.exists?(c.home)
  end

  test "built-in subscription default is announced before auth and disappears after explicit setup",
       c do
    output =
      Ipse.Auth.with_auth_transport(fn _, _, _ -> flunk("unexpected auth request") end, fn ->
        capture_io(:stderr, fn ->
          assert Ipse.CLI.run(["run", "--cwd", c.cwd, "--no-project-config", "read only"]) == 1
        end)
      end)

    assert output =~
             "Using built-in provider default chatgpt (ChatGPT subscription). Run ipse setup to choose explicitly."

    refute File.exists?(Path.join(c.home, "sessions"))
    capture_io(fn -> assert Ipse.CLI.run(args(c, ["--write"])) == 0 end)

    output =
      capture_io(:stderr, fn ->
        capture_io([input: "/exit\n"], fn ->
          assert Ipse.CLI.run(["chat", "--cwd", c.cwd, "--no-project-config"]) == 0
        end)
      end)

    refute output =~ "Using built-in provider default"
    assert output =~ "Ipse · demo/scripted"
  end

  test "pure preview agrees exactly with written-file resolution and preserves the old source",
       c do
    raw =
      Jason.encode!(%{version: 1, settings: %{provider: "demo", model: "scripted", max_steps: 9}}) <>
        "\n"

    opts = [config: c.path, project_config: false]
    {:ok, preview} = Ipse.Config.preview(c.cwd, c.home, opts, raw, %{})
    refute File.exists?(c.home)
    :ok = Ipse.PrivateFile.write_atomic(c.path, raw)
    {:ok, actual} = Ipse.Config.resolve(c.cwd, c.home, opts, %{})
    assert Ipse.Config.manifest(preview) == Ipse.Config.manifest(actual)

    assert {:error, _} =
             Ipse.Config.preview(c.cwd, c.home, opts, String.duplicate("x", 16_385), %{})

    assert {:error, _} = Ipse.Config.preview(c.cwd, c.home, opts, %{}, %{})
    assert File.read!(c.path) == raw
  end

  defp interactive(c, lines) do
    {:ok, io} = IOFixture.start_link(self())
    on_exit(fn -> if Process.alive?(io), do: GenServer.stop(io) end)
    Enum.each(lines, &IOFixture.feed(io, &1))

    task =
      Task.Supervisor.async_nolink(Ipse.Tasks, fn ->
        receive do
          :go -> Ipse.CLI.run(["setup", "--cwd", c.cwd])
        end
      end)

    Process.group_leader(task.pid, io)
    send(task.pid, :go)
    code = Task.await(task, 10_000)
    {code, IOFixture.output(io)}
  end
end
