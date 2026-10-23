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

  test "config validates an explicit MCP file without launching servers or requiring credentials",
       c do
    put(c, %{provider: "anthropic", model: "local-inspection"})
    path = Path.join(c.root, "mcp.json")
    File.write!(path, Jason.encode!(%{servers: [%{transport: "http", url: "invalid"}]}))

    output =
      capture_io(:stderr, fn ->
        assert Ipse.CLI.run(["config", "--cwd", c.cwd, "--mcp-config", path]) == 1
      end)

    assert output =~ "MCP configuration is invalid"

    File.write!(
      path,
      Jason.encode!(%{
        servers: [
          %{
            id: "remote",
            transport: "http",
            url: "https://example.invalid/mcp",
            tools: ["lookup"]
          }
        ]
      })
    )

    output =
      capture_io(fn ->
        assert Ipse.CLI.run(["config", "--cwd", c.cwd, "--mcp-config", path]) == 0
      end)

    assert Jason.decode!(output)["settings"]["provider"] == "anthropic"
    refute File.exists?(Path.join(c.home, "sessions"))
  end

  test "trusted project endpoint is rejected before credential-bearing HTTP dispatch", c do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_ip, port}} = :inet.sockname(listener)
    previous_home = System.get_env("HOME")
    previous_key = System.get_env("OPENAI_API_KEY")
    System.put_env("HOME", c.home)
    System.put_env("OPENAI_API_KEY", "fixture-project-egress")

    on_exit(fn ->
      :gen_tcp.close(listener)
      if previous_home, do: System.put_env("HOME", previous_home), else: System.delete_env("HOME")

      if previous_key,
        do: System.put_env("OPENAI_API_KEY", previous_key),
        else: System.delete_env("OPENAI_API_KEY")
    end)

    project = Path.join(c.cwd, ".ipse/config.json")
    File.mkdir_p!(Path.dirname(project))

    File.write!(
      project,
      Jason.encode!(%{
        version: 1,
        profiles: %{
          project: %{provider: "openai", model: "fixture", base_url: "http://127.0.0.1:#{port}"}
        },
        roles: %{main: "project"}
      })
    )

    capture_io(fn ->
      capture_io(:stderr, fn ->
        assert Ipse.CLI.run([
                 "run",
                 "--cwd",
                 c.cwd,
                 "--trust-project-config",
                 "--timeout-ms",
                 "1000",
                 "Synthetic project endpoint refusal"
               ]) == 1
      end)
    end)

    case :gen_tcp.accept(listener, 0) do
      {:error, :timeout} ->
        :ok

      {:ok, socket} ->
        request =
          case :gen_tcp.recv(socket, 0, 100) do
            {:ok, bytes} -> String.downcase(bytes)
            _ -> ""
          end

        :gen_tcp.close(socket)
        sent_key = String.contains?(request, "authorization: bearer fixture-project-egress")

        flunk(
          "Project endpoint received HTTP dispatch; synthetic credential observed: #{sent_key}"
        )
    end

    refute File.exists?(Path.join(c.home, "sessions"))
  end

  test "config CLI discloses the sandbox floor and an explicit operator override", c do
    put(c, %{sandbox: "native"})
    File.mkdir_p!(Path.join(c.cwd, ".ipse"))

    File.write!(
      Path.join(c.cwd, ".ipse/config.json"),
      Jason.encode!(%{version: 1, settings: %{sandbox: "off"}})
    )

    inspect_config = fn extra ->
      capture_io(fn ->
        assert Ipse.CLI.run(["config", "--cwd", c.cwd, "--trust-project-config"] ++ extra) == 0
      end)
      |> Jason.decode!()
    end

    protected = inspect_config.([])
    assert protected["settings"]["sandbox"] == "native"
    assert protected["provenance"]["sandbox"] == Path.join(c.home, "config.json")
    explicit = inspect_config.(["--sandbox", "off"])
    assert explicit["settings"]["sandbox"] == "off"
    assert explicit["provenance"]["sandbox"] == "CLI"
    refute File.exists?(Path.join(c.home, "sessions"))
  end

  test "output ceiling is durable and cannot silently change or disappear on embedded resume",
       c do
    config = %{
      provider: :ollama,
      model: "fixture",
      max_output_tokens: 32,
      home: c.home,
      approval: :deny
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
    path = Path.join(opts[:state_dir], id <> ".jsonl")
    {:ok, events} = Ipse.Journal.load(opts[:state_dir], id)
    assert hd(events)["metadata"]["max_output_tokens"] == 32

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Ipse.Session, Keyword.put(opts, :id, id)}
             )

    assert Ipse.Session.info(resumed).phase == :idle
    assert {:ok, ^events} = Ipse.Journal.load(opts[:state_dir], id)
    assert :ok = Ipse.Session.close(resumed)
    File.write!(path, "{torn", [:append])
    before = File.read!(path)

    for changed <- [Map.delete(config, :max_output_tokens), %{config | max_output_tokens: 64}] do
      assert {:error, :resume_configuration_mismatch} =
               DynamicSupervisor.start_child(
                 Ipse.Sessions,
                 {Ipse.Session, opts |> Keyword.put(:id, id) |> Keyword.put(:config, changed)}
               )

      assert File.read!(path) == before
    end

    forged = List.update_at(events, 0, &put_in(&1, ["metadata", "max_output_tokens"], 32.0))
    forged_bytes = Enum.map_join(forged, &(Jason.encode!(&1) <> "\n")) <> "{torn"
    File.write!(path, forged_bytes)

    assert {:error, :resume_configuration_mismatch} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Ipse.Session, Keyword.put(opts, :id, id)}
             )

    assert File.read!(path) == forged_bytes

    invalid = %{config | provider: :chatgpt}

    assert {:error, message} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Ipse.Session,
                opts
                |> Keyword.put(:state_dir, Path.join(c.root, "refused"))
                |> Keyword.put(:config, invalid)}
             )

    assert message =~ "does not support"
    refute File.exists?(Path.join(c.root, "refused"))
  end

  test "legacy absent output policy remains resumable with no cap", c do
    config = %{provider: :ollama, model: "fixture", home: c.home, approval: :deny}

    opts = [
      cwd: c.cwd,
      state_dir: Path.join(c.root, "sessions"),
      subscriber: self(),
      config: config
    ]

    assert {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
    id = Ipse.Session.info(pid).id
    assert :ok = Ipse.Session.close(pid)
    {:ok, events} = Ipse.Journal.load(opts[:state_dir], id)

    old =
      List.update_at(
        events,
        0,
        &Map.update!(&1, "metadata", fn meta -> Map.delete(meta, "max_output_tokens") end)
      )

    bytes = Enum.map_join(old, &(Jason.encode!(&1) <> "\n"))
    path = Path.join(opts[:state_dir], id <> ".jsonl")
    File.write!(path, bytes)

    assert {:ok, resumed} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Ipse.Session, Keyword.put(opts, :id, id)}
             )

    assert File.read!(path) == bytes
    assert :ok = Ipse.Session.close(resumed)
  end

  test "resume cannot silently change a direct provider endpoint even before the first request",
       c do
    config = %{
      provider: :ollama,
      model: "fixture",
      home: c.home,
      approval: :deny,
      base_url: "http://127.0.0.1:11435/custom"
    }

    opts = [
      config: config,
      cwd: c.cwd,
      state_dir: Path.join(c.root, "route-sessions"),
      subscriber: self()
    ]

    {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
    id = Ipse.Session.info(pid).id
    :ok = Ipse.Session.close(pid)
    path = Path.join(opts[:state_dir], id <> ".jsonl")
    before = File.read!(path)

    for changed <- [
          Map.delete(config, :base_url),
          %{config | base_url: "http://127.0.0.1:11435/other"}
        ] do
      result =
        DynamicSupervisor.start_child(
          Ipse.Sessions,
          {Ipse.Session, opts |> Keyword.put(:id, id) |> Keyword.put(:config, changed)}
        )

      if match?({:ok, _}, result), do: Ipse.Session.close(elem(result, 1))
      assert result == {:error, :resume_configuration_mismatch}
      assert File.read!(path) == before
    end

    {:ok, resumed} =
      DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, Keyword.put(opts, :id, id)})

    :ok = Ipse.Session.close(resumed)

    {:ok, events} = Ipse.Journal.load(opts[:state_dir], id)

    legacy =
      List.update_at(
        events,
        0,
        &Map.update!(&1, "metadata", fn meta -> Map.delete(meta, "provider_destination") end)
      )

    admission = Ipse.Usage.admission(id, config, "model", Ipse.Usage.id())
    completion = Ipse.Usage.completion(admission, {:ok, %{}, %{}}, 1, nil)

    File.write!(
      path,
      Enum.map_join(legacy ++ [admission, completion], &(Jason.encode!(&1) <> "\n"))
    )

    assert {:error, :resume_configuration_mismatch} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Ipse.Session,
                opts
                |> Keyword.put(:id, id)
                |> Keyword.put(:config, Map.delete(config, :base_url))}
             )

    {:ok, legacy_resumed} =
      DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, Keyword.put(opts, :id, id)})

    :ok = Ipse.Session.close(legacy_resumed)
  end

  test "CLI inspects a configured output cap locally and refuses a subscription cap", c do
    output =
      capture_io(fn ->
        assert Ipse.CLI.run([
                 "config",
                 "--no-project-config",
                 "--cwd",
                 c.cwd,
                 "--provider",
                 "ollama",
                 "--max-output-tokens",
                 "64"
               ]) == 0
      end)

    assert Jason.decode!(output)["settings"]["max_output_tokens"] == 64

    assert capture_io(:stderr, fn ->
             assert Ipse.CLI.run([
                      "config",
                      "--no-project-config",
                      "--cwd",
                      c.cwd,
                      "--provider",
                      "chatgpt",
                      "--max-output-tokens",
                      "64"
                    ]) == 1
           end) =~ "does not support"
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
