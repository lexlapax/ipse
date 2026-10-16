defmodule Ipse.ConfigSessionTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  setup do
    root =
      Path.join(System.tmp_dir!(), "ipse-config-session-#{System.unique_integer([:positive])}")

    cwd = Path.join(root, "project")
    home = Path.join(root, "operator")
    File.mkdir_p!(Path.join(cwd, ".git"))
    File.mkdir_p!(home)
    old_home = System.get_env("IPSE_HOME")
    System.put_env("IPSE_HOME", home)

    on_exit(fn ->
      if old_home, do: System.put_env("IPSE_HOME", old_home), else: System.delete_env("IPSE_HOME")
      File.rm_rf!(root)
    end)

    %{root: root, cwd: cwd, home: home}
  end

  defp put(c, settings) do
    File.write!(
      Path.join(c.home, "config.json"),
      Jason.encode!(%{version: 1, settings: settings})
    )
  end

  test "local config command reports provenance without authentication or inference", c do
    put(c, %{provider: "anthropic", model: "local-inspection", max_steps: 4})

    output =
      capture_io(fn ->
        assert Ipse.CLI.run(["config", "--cwd", c.cwd, "--max-steps", "5"]) == 0
      end)

    manifest = Jason.decode!(output)
    assert manifest["settings"]["max_steps"] == 5
    assert manifest["provenance"]["max_steps"] == "CLI"
    assert manifest["settings"]["provider"] == "anthropic"
    refute File.exists?(Path.join(c.home, "sessions"))
    refute output =~ "auth_dir"
  end

  test "configuration is durable, source drift refuses resume and unchanged resume never replays",
       c do
    put(c, %{provider: "demo", model: "scripted"})
    assert {:ok, effective} = Ipse.Config.resolve(c.cwd, c.home, [], %{})

    config = %{
      provider: :demo,
      model: "scripted",
      home: c.home,
      approval: :deny,
      configuration: Ipse.Config.manifest(effective)
    }

    opts = [
      cwd: c.cwd,
      state_dir: Path.join(c.root, "sessions"),
      subscriber: self(),
      config: config
    ]

    assert {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
    id = Ipse.Session.info(pid).id
    assert :ok = Ipse.Session.close(pid)
    {:ok, before_events} = Ipse.Journal.load(opts[:state_dir], id)

    assert get_in(hd(before_events), ["metadata", "configuration", "fingerprint"]) ==
             effective.fingerprint

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Ipse.Session, Keyword.put(opts, :id, id)}
             )

    assert Ipse.Session.info(resumed).phase == :idle
    assert {:ok, ^before_events} = Ipse.Journal.load(opts[:state_dir], id)
    assert :ok = Ipse.Session.close(resumed)
    put(c, %{provider: "demo", model: "scripted", timeout_ms: 5000})
    assert {:ok, changed} = Ipse.Config.resolve(c.cwd, c.home, [], %{})

    changed_opts =
      opts
      |> Keyword.put(:id, id)
      |> Keyword.put(:config, %{config | configuration: Ipse.Config.manifest(changed)})

    assert {:error, :resume_configuration_mismatch} =
             DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, changed_opts})

    assert {:ok, ^before_events} = Ipse.Journal.load(opts[:state_dir], id)
    refute_receive {:ipse, _, {:tool, _, _}}, 50
  end
end
