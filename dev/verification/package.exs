defmodule Ipse.Development.Verification.Package do
  @moduledoc "Installed package behavior assertions, using the shared verification runtime."
  alias Ipse.Development.Verification.{Runtime, Scenarios}

  @job_timeout_note "Run this verifier under a bounded CI job timeout; System.cmd/3 has no per-process timeout option."

  defp verify_memory!(runtime, corpus) do
    report =
      Runtime.eval!(
        runtime,
        "Ipse.Development.Verification.Memory.run(" <> inspect(corpus) <> ")"
      )

    :ok = Scenarios.validate!(Scenarios.fetch!("memory"), report, "default")

    IO.puts(
      "PASS: bundled explicit memory, 100 records/100 queries, six sessions/two projects, exact spans and no inference."
    )

    IO.puts(:json.encode(report))
  end

  defp verify_terminal!(wrapper, release, env, root) do
    state = Path.join(root, "terminal-listing")
    File.mkdir_p!(state)
    File.chmod!(state, 0o700)
    id = String.duplicate("a", 32)
    path = Path.join(state, id <> ".jsonl")
    cwd = "/synthetic/雪\n\e[8m\u202E\u200B\u{E0001}"
    metadata = %{"provider" => "demo", "model" => "fixture", "cwd" => cwd}

    bytes =
      IO.iodata_to_binary([:json.encode(%{"type" => "session", "metadata" => metadata}), "\n"])

    File.write!(path, bytes)
    File.chmod!(path, 0o600)

    json =
      run!(
        wrapper,
        ["sessions", "--state-dir", state, "--json"],
        release,
        env,
        "terminal JSON",
        false
      )

    expected = [Map.put(metadata, "id", id)]

    unless :json.decode(json) == expected,
      do: raise("terminal JSON did not retain original values")

    text = run!(wrapper, ["sessions", "--state-dir", state], release, env, "terminal listing")

    for output <- [json, text], control <- ["\e", "\u202E", "\u200B", "\u{E0001}"] do
      if String.contains?(output, control), do: raise("terminal listing emitted a raw control")
    end

    unless String.contains?(text, "\\u001b[8m") and String.contains?(text, "\\u202e") and
             String.contains?(text, "\\u200b") and File.read!(path) == bytes,
           do: raise("terminal display escaping or read-only listing failed")

    IO.puts("PASS: bundled CLI terminal escaping, original JSON values and unchanged journal.")
  end

  defp verify_doctor!(wrapper, release, env, home, workspace, version) do
    report =
      run!(
        wrapper,
        ["doctor", "--provider", "demo", "--cwd", workspace, "--no-project-config", "--json"],
        release,
        env,
        "bundled offline doctor"
      )
      |> :json.decode()

    1 = report["version"]
    ^version = report["build"]["version"]

    expected =
      ~w(runtime.build home.layout config.files config.provider credentials.selected sandbox.native mcp.config extensions.selection sessions.store provider.reachability)

    ^expected = Enum.map(report["checks"], & &1["id"])

    for row <- report["checks"] do
      expected_experimental_warning =
        :os.type() == {:unix, :darwin} and row["id"] == "sandbox.native" and
          row["status"] == "warn" and row["detail"] =~ "macOS is experimental."

      true = row["status"] in ["ok", "skip"] or expected_experimental_warning
    end

    %{"status" => "skip"} = Enum.find(report["checks"], &(&1["id"] == "provider.reachability"))
    false = File.exists?(Path.join(home, ".ipse/auth"))
    false = File.exists?(Path.join(home, ".ipse/sessions"))

    IO.puts(
      "PASS: toolchain-free offline doctor, stable findings and no auth/session state creation."
    )
  end

  defp verify_setup!(wrapper, release, env, root) do
    home = Path.join(root, "first-run-home")
    operator = Path.join(home, ".ipse")
    workspace = Path.join(root, "first-run-workspace")
    File.mkdir!(home)
    File.chmod!(home, 0o700)
    File.mkdir!(workspace)

    env =
      env
      |> List.keystore("HOME", 0, {"HOME", home})
      |> List.keystore("IPSE_HOME", 0, {"IPSE_HOME", operator})

    args = ["setup", "--provider", "demo", "--model", "scripted", "--cwd", workspace]
    preview = run!(wrapper, args, release, env, "first-run preview")
    true = String.contains?(preview, "Dry run; add --write")
    false = File.exists?(operator)
    run!(wrapper, args ++ ["--write"], release, env, "first-run private setup")
    0o700 = Bitwise.band(File.stat!(operator).mode, 0o777)
    path = Path.join(operator, "config.json")
    0o600 = Bitwise.band(File.stat!(path).mode, 0o777)
    ["config.json"] = File.ls!(operator)

    config =
      run!(
        wrapper,
        ["config", "--cwd", workspace, "--no-project-config"],
        release,
        env,
        "first-run resolved route"
      )
      |> :json.decode()

    "demo" = config["settings"]["provider"]
    ^path = config["provenance"]["provider"]

    report =
      run!(
        wrapper,
        ["doctor", "--cwd", workspace, "--no-project-config", "--json"],
        release,
        env,
        "first-run configured doctor"
      )
      |> :json.decode()

    false = Enum.any?(report["checks"], &(&1["status"] == "fail"))
    run!(wrapper, ["demo"], workspace, env, "first-run credential-free demo")

    IO.puts(
      "PASS: toolchain-free setup preview, private save, configured doctor and demo in an isolated fresh home."
    )
  end

  defp verify_xai!(wrapper, release, env, root) do
    home = Path.join(root, "grok-home")
    workspace = Path.join(root, "grok-workspace")
    File.mkdir!(workspace)

    env =
      env
      |> List.keystore("IPSE_HOME", 0, {"IPSE_HOME", home})
      |> List.keystore("IPSE_XAI_CLIENT_ID", 0, {"IPSE_XAI_CLIENT_ID", nil})
      |> List.keystore("XAI_API_KEY", 0, {"XAI_API_KEY", "installed-grok-fixture-key"})

    args = ["setup", "--provider", "xai", "--model", "grok-4.7", "--cwd", workspace]
    preview = run!(wrapper, args, release, env, "Grok setup preview")
    true = String.contains?(preview, "api billing")
    false = String.contains?(preview, "installed-grok-fixture-key")
    false = File.exists?(home)
    run!(wrapper, args ++ ["--write"], release, env, "Grok private API setup")

    report =
      run!(
        wrapper,
        ["doctor", "--cwd", workspace, "--no-project-config", "--json"],
        release,
        env,
        "Grok offline doctor"
      )
      |> :json.decode()

    false = Enum.any?(report["checks"], &(&1["status"] == "fail"))
    false = File.exists?(Path.join(home, "auth"))

    {refusal, 1} =
      System.cmd(wrapper, ["login", "--provider", "xai_oauth"],
        cd: release,
        env: env,
        stderr_to_stdout: true
      )

    true = String.contains?(refusal, "approved Ipse client registration")
    false = String.contains?(refusal, "installed-grok-fixture-key")
    false = File.exists?(Path.join(home, "auth"))

    IO.puts(
      "PASS: installed Grok API setup/offline diagnosis and missing OAuth registration refusal; no model or authorization service contacted."
    )
  end

  defp verify_permissions!(launcher, release, env, root) do
    workspace = Path.join(root, "permissions-workspace")
    File.mkdir!(workspace)

    source = """
    {:ok, _} = Application.ensure_all_started(:ipse)
    defmodule IpsePackagePermissionFixture do
      def complete(_config, messages, _tools, _emit) do
        if List.last(messages)["role"] == "tool" do
          {:ok, %{"role" => "assistant", "content" => "Done"}, %{}}
        else
          calls = for {name, args, id} <- [
            {"write", %{"path" => "first", "content" => "hello"}, "w1"},
            {"write", %{"path" => "second", "content" => "hello"}, "w2"},
            {"shell", %{"command" => "printf fixture"}, "s1"},
            {"shell", %{"command" => "printf fixture"}, "s2"}] do
            %{"id" => id, "type" => "function", "function" => %{"name" => name,
              "arguments" => Jason.encode!(args)}}
          end
          {:ok, %{"role" => "assistant", "content" => "", "tool_calls" => calls}, %{}}
        end
      end
    end
    config = %{provider: :demo, model: "scripted", approval: :ask,
      provider_module: IpsePackagePermissionFixture, home: #{inspect(Path.join(root, "permissions-home"))}}
    opts = [config: config, cwd: #{inspect(workspace)},
      state_dir: #{inspect(Path.join(root, "permissions-state"))}, subscriber: self()]
    {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
    :ok = Ipse.Session.prompt(pid, "fixed four effects")
    wait = fn wait, count ->
      receive do
        {:ipse, ^pid, {:approval, ref, name, _}} ->
          choice = if name == "write", do: :session_edits, else: :session_command
          :ok = Ipse.Session.approve(pid, ref, choice)
          wait.(wait, count + 1)
        {:ipse, ^pid, {:done, :ok}} -> count
        _ -> wait.(wait, count)
      after
        5000 -> raise "permission proof timed out"
      end
    end
    2 = wait.(wait, 0)
    "hello" = File.read!(#{inspect(Path.join(workspace, "second"))})
    %{"workspace_edits" => true, "commands" => [_]} = Ipse.Session.permissions(pid)
    :ok = Ipse.Session.clear_permissions(pid)
    %{"workspace_edits" => false, "commands" => []} = Ipse.Session.permissions(pid)
    id = Ipse.Session.info(pid).id
    :ok = Ipse.Session.close_confirmed(pid)
    {:ok, resumed} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts ++ [id: id]})
    %{phase: :idle} = Ipse.Session.info(resumed)
    %{"workspace_edits" => false, "commands" => []} = Ipse.Session.permissions(resumed)
    :ok = Ipse.Session.close_confirmed(resumed)
    """

    run!(launcher, ["eval", source], release, env, "installed session permissions")

    IO.puts(
      "PASS: installed edit/exact-command grants reduce four prompts to two; revocation and idle resume retain no authority."
    )
  end

  defp verify_upgrade!(launcher, release, env, root) do
    upgraded = Path.join(root, "changed-host-release")
    File.cp_r!(release, upgraded)
    workspace = Path.join(root, "upgrade-workspace")
    File.mkdir!(workspace)
    state = Path.join(root, "upgrade-state")
    ids = Path.join(root, "upgrade-ids.json")

    configuration = """
    {:ok, _} = Application.ensure_all_started(:ipse)
    workspace = #{inspect(workspace)}
    state = #{inspect(state)}
    source = %{scope: "operator", path: "/fixture/upgrade.json", data: %{
      "extensions" => [%{"instance" => "annotation", "artifact" => "builtin:prompt-annotation:1",
        "enabled" => true, "options" => %{"text" => "upgrade fixture"}, "order" => 1, "lifetime" => "persistent"}],
      "extension_trust" => [%{"artifact" => "builtin:prompt-annotation:1", "capabilities" => ["transform.prompt"],
        "allow_project" => false, "allow_children" => false}]}}
    {:ok, catalog} = Ipse.Extension.Config.resolve([source], [])
    {:ok, entries} = Ipse.Extension.Registry.prepare(catalog, #{inspect(Path.join(root, "upgrade-home"))})
    config = fn selected -> %{provider: :demo, model: "scripted", approval: :deny, sandbox: :off,
      home: #{inspect(Path.join(root, "upgrade-home"))}, extensions: if(selected, do: entries, else: [])} end
    start = fn selected, id -> DynamicSupervisor.start_child(Ipse.Sessions,
      {Ipse.Session, [config: config.(selected), cwd: workspace, state_dir: state, subscriber: self()] ++ if(id, do: [id: id], else: [])}) end
    """

    create =
      configuration <>
        """
        ids = for selected <- [false, true] do
          {:ok, pid} = start.(selected, nil)
          id = Ipse.Session.info(pid).id
          :ok = Ipse.Session.close(pid)
          {:ok, resumed} = start.(selected, id)
          :ok = Ipse.Session.close(resumed)
          id
        end
        File.write!(#{inspect(ids)}, Jason.encode!(ids))
        """

    run!(launcher, ["eval", create], release, env, "same-build upgrade controls")

    frozen =
      for id <- :json.decode(File.read!(ids)),
          into: %{},
          do: {id, File.read!(Path.join(state, id <> ".jsonl"))}

    # Recompile only a test copy of the public identity module. The production
    # archive and source remain untouched; this changes a real inventoried host BEAM.
    source = File.read!(Path.expand("../../lib/ipse.ex", __DIR__))

    changed =
      Regex.replace(~r/end\s*\z/, source, "  def upgrade_fixture_marker, do: :changed\nend\n")

    compile = """
    [{Ipse, bytes}] = Code.compile_string(#{inspect(changed)})
    file = Path.join(Application.app_dir(:ipse, "ebin"), "Elixir.Ipse.beam")
    true = File.read!(file) != bytes
    File.write!(file, bytes)
    """

    next_launcher = Path.join(upgraded, "bin/ipse")
    run!(next_launcher, ["eval", compile], upgraded, env, "changed-host fixture rebuild")

    check =
      configuration <>
        """
        [plain, selected] = Jason.decode!(File.read!(#{inspect(ids)}))
        {:ok, resumed} = start.(false, plain)
        %{phase: :idle} = Ipse.Session.info(resumed)
        :ok = Ipse.Session.close(resumed)
        {:error, :resume_configuration_mismatch} = start.(true, selected)
        true = String.contains?(Ipse.CLI.Errors.format(:resume_configuration_mismatch), "handoff")
        """

    run!(next_launcher, ["eval", check], upgraded, env, "changed-host resume behavior")

    old =
      configuration <>
        """
        [_, selected] = Jason.decode!(File.read!(#{inspect(ids)}))
        {:ok, resumed} = start.(true, selected)
        :ok = Ipse.Session.close(resumed)
        """

    run!(launcher, ["eval", old], release, env, "previous release resume recovery")
    for {id, bytes} <- frozen, do: ^bytes = File.read!(Path.join(state, id <> ".jsonl"))

    IO.puts(
      "PASS: a changed host resumes an extension-free session, refuses selected extensions without mutation, and the previous build still resumes them."
    )
  end

  defp verify_recovery!(launcher, release, env, root) do
    workspace = Path.join(root, "recovery-probe")
    File.mkdir_p!(Path.join(workspace, ".git"))

    expression = """
    workspace = #{inspect(workspace)}
    File.write!(Path.join(workspace, ".git/protected"), "keep")
    {:error, _} = Ipse.Tools.execute("write", %{"path" => ".GIT/new", "content" => "x"}, %{cwd: workspace})
    {:error, _} = Ipse.Tools.execute("edit", %{"path" => ".GiT/protected", "old" => "keep", "new" => "changed"}, %{cwd: workspace})
    "keep" = File.read!(Path.join(workspace, ".git/protected"))
    false = File.exists?(Path.join(workspace, ".git/new"))
    true = Ipse.Tools.path_key("CAF" <> <<0xC3, 0x89>> <> ".txt") == Ipse.Tools.path_key("cafe" <> <<0xCC, 0x81>> <> ".txt")
    {:unknown, _} = Ipse.Runner.run(~s(printf effected > effect; kill -KILL "$PPID"), workspace)
    "effected" = File.read!(Path.join(workspace, "effect"))
    {:error, _} = Ipse.Runner.run("true", Path.join(workspace, "missing"))
    {:error, _} = Ipse.Tools.execute("write", %{"path" => "missing/child", "content" => "x"}, %{cwd: workspace})
    opaque = String.duplicate(<<0xE9, 0x9B, 0xAA>>, 85) <> "x"
    true = Ipse.Tools.valid_call_id?(opaque)
    false = Ipse.Tools.valid_call_id?(opaque <> "x")
    {:ok, _} = Ipse.Tools.Sandbox.resolve(:native, workspace)
    {:error, boundary} = Ipse.Tools.Sandbox.resolve(:native, Application.app_dir(:ipse))
    true = String.contains?(boundary, "overlaps the active helper or application")
    calls = for i <- 1..33, do: %{"id" => "bounded-" <> Integer.to_string(i),
      "function" => %{"name" => "read", "arguments" => "{}"}}
    {:error, :tool_call_limit} = Ipse.Tools.admit_calls(calls, Ipse.Tools.empty_call_budget())
    used = Enum.reduce(1..4, Ipse.Tools.empty_call_budget(), fn _, used ->
      {:ok, next} = Ipse.Tools.admit_calls(Enum.take(calls, 32), used)
      next
    end)
    {:error, :tool_call_limit} = Ipse.Tools.admit_calls(Enum.take(calls, 1), used)
    source = %{"tool_calls" => [%{"id" => opaque, "function" => %{"name" => "fixture", "arguments" => "{}"}}]}
    true = Ipse.Extension.Invocation.source_call_valid?(source, opaque, "fixture", %{})
    call = %{"id" => "duplicate", "function" => %{"name" => "write", "arguments" => "{}"}}
    assistant = %{"role" => "assistant", "content" => "", "tool_calls" => [call, call]}
    result = %{"role" => "tool", "tool_call_id" => "duplicate", "content" => "First completed"}
    events = [%{"type" => "session", "metadata" => %{}},
      %{"type" => "message", "message" => assistant}, %{"type" => "message", "message" => result}]
    {:ok, [^assistant, ^result, missing]} = Ipse.Session.restore_context(events)
    %{"status" => "unknown", "approval" => "historical_unknown"} = missing["ipse_tool_outcome"]
    operator = Path.join(workspace, "operator")
    File.mkdir_p!(operator)
    File.mkdir_p!(Path.join(workspace, ".ipse"))
    File.write!(Path.join(operator, "config.json"), Jason.encode!(%{version: 1, settings: %{sandbox: "native"}}))
    File.write!(Path.join(workspace, ".ipse/config.json"), Jason.encode!(%{version: 1, settings: %{sandbox: "off"}}))
    {:ok, protected} = Ipse.Config.resolve(workspace, operator, [trust_project_config: true], %{})
    "native" = protected.settings["sandbox"]
    true = protected.provenance["sandbox"] == Path.join(operator, "config.json")
    {:ok, explicit} = Ipse.Config.resolve(workspace, operator, [trust_project_config: true, sandbox: "off"], %{})
    "off" = explicit.settings["sandbox"]
    "CLI" = explicit.provenance["sandbox"]
    """

    run!(launcher, ["eval", expression], release, env, "recovery and sandbox authority")

    IO.puts(
      "PASS: installed shell uncertainty, call-ID bounds, write refusals, historical results, sandbox floor and metadata aliases."
    )
  end

  defp verify_text!(launcher, release, env) do
    expression = """
    text = "x" <> String.duplicate(<<0xC3, 0xA9, 0xF0, 0x9F, 0x99, 0x82>>, 23_000)
    owner = self()
    request = Ipse.Usage.id()
    {:ok, stream} = Ipse.Session.TextStream.start(owner, Ipse.Usage.id())
    {:ok, handle} = Ipse.Session.TextStream.subscribe(stream, owner, 2)
    producer = spawn(fn ->
      receive do
        :start ->
          :ok = Ipse.Session.TextStream.push_delta(stream, request, text)
          send(owner, :delta_accepted)
      end
    end)
    :ok = Ipse.Session.TextStream.begin(stream, request, producer)
    send(producer, :start)
    collect = fn collect, chunks ->
      receive do
        :delta_accepted ->
          :ok = Ipse.Session.TextStream.finish(stream, request, "completed")
          collect.(collect, chunks)
        {:ipse_text, ^stream, %{"sequence" => sequence} = frame} ->
          true = Ipse.Session.TextStream.valid_frame?(frame)
          :ok = Ipse.Session.TextStream.ack(handle, sequence)
          chunks = [frame["text"] || "" | chunks]
          if frame["kind"] == "end" do
            true = frame["complete"]
            chunks |> Enum.reverse() |> Enum.join()
          else
            collect.(collect, chunks)
          end
        {:ipse_text, ^stream, %{"kind" => "closed"}} -> raise "private text closed"
      after
        5000 -> raise "private text incomplete"
      end
    end
    ^text = collect.(collect, [])
    GenServer.stop(stream)
    """

    run!(launcher, ["eval", expression], release, env, "large private visible delta")
    IO.puts("PASS: installed large Unicode delta over the bounded v2 text channel.")
  end

  def run(%{mode: :installed} = runtime, corpus, archive) do
    release = runtime.release
    root = runtime.root
    home = runtime.home
    env = List.keystore(runtime.env, "PATH", 0, {"PATH", Path.join(root, "utilities")})
    {"PATH", path} = List.keyfind(env, "PATH", 0)

    for command <- ~w(erl elixir elixirc erlc mix rustc cargo) do
      false = :os.find_executable(String.to_charlist(command), String.to_charlist(path))
    end

    ipse_home = Path.join(home, ".ipse")
    default_workspace = Path.join(root, "caller cwd with spaces")
    override_caller = Path.join(root, "different caller cwd")
    override_workspace = Path.join(root, "explicit workspace with spaces")
    for path <- [default_workspace, override_caller, override_workspace], do: File.mkdir!(path)
    [] = File.ls!(home)
    File.mkdir!(ipse_home)
    [] = File.ls!(ipse_home)
    File.chmod!(home, 0o700)
    File.chmod!(ipse_home, 0o700)
    [_erts] = File.ls!(release) |> Enum.filter(&String.starts_with?(&1, "erts-"))
    wrapper = Path.join(release, "ipse")

    otp_launcher = Path.join(release, "bin/ipse")
    require_executable!(wrapper)
    require_executable!(otp_launcher)

    run!(wrapper, ["--help"], release, env, "bundled CLI help")
    [app] = Path.wildcard(Path.join([release, "lib", "ipse-*", "ebin", "ipse.app"]))
    {:ok, [{:application, :ipse, properties}]} = :file.consult(String.to_charlist(app))
    version = properties |> Keyword.fetch!(:vsn) |> to_string()

    unless String.starts_with?(Path.basename(archive), "ipse-#{version}-"),
      do: raise("archive name does not match its application version")

    unless String.trim(run!(wrapper, ["--version"], release, env, "bundled version")) == version,
      do: raise("bundled CLI version does not match its application")

    info =
      run!(wrapper, ["version", "--json"], release, env, "bundled build identity")
      |> :json.decode()

    true = info["version"] == version
    true = Enum.sort(Map.keys(info)) == ~w(arch commit elixir os otp_release version)

    IO.puts(
      "PASS: archive name, application version and toolchain-free CLI build identity agree."
    )

    verify_doctor!(wrapper, release, env, home, default_workspace, version)
    verify_setup!(wrapper, release, env, root)
    verify_xai!(wrapper, release, env, root)
    verify_permissions!(otp_launcher, release, env, root)
    verify_upgrade!(otp_launcher, release, env, root)

    links = Path.join(root, "launcher links")
    File.mkdir!(links)
    File.ln_s!(Path.join("..", Path.relative_to(wrapper, root)), Path.join(links, "second"))
    linked = Path.join(links, "ipse")
    File.ln_s!("second", linked)

    ^version =
      String.trim(
        run!(linked, ["--version"], override_caller, env, "symlinked launcher identity")
      )

    run!(
      linked,
      ["run", "--provider", "demo", "--yes", "Create and read the deterministic demo file"],
      override_caller,
      env,
      "symlinked caller workspace"
    )

    assert_demo_file!(override_caller)
    File.rm!(Path.join(override_caller, "ipse-demo.txt"))
    IO.puts("PASS: relative symlink chain resolves the release and preserves caller workspace.")

    verify_terminal!(wrapper, release, env, root)
    verify_recovery!(otp_launcher, release, env, root)
    verify_text!(otp_launcher, release, env)
    verify_memory!(runtime, corpus)

    [app] = Path.wildcard(Path.join([release, "lib", "ipse-*"]))

    check =
      run!(
        wrapper,
        [
          "extension",
          "check",
          "--config",
          Path.join(app, "priv/demo/operator.json"),
          "--fixture",
          Path.join(app, "priv/demo/conformance.json"),
          "--extension",
          "annotation",
          "--no-project-config",
          "--developer-trace",
          "--trace-events",
          "2"
        ],
        default_workspace,
        env,
        "bundled synthetic conformance CLI"
      )

    unless String.contains?(check, "\"provider\": \"synthetic\""),
      do: raise("release conformance CLI did not identify its synthetic provider")

    unless String.contains?(check, "\"sampling\": \"one_in_flight\"") and
             String.contains?(check, "\"cleanup_confirmed\": true"),
           do: raise("release conformance CLI did not report bounded developer tracing")

    # The first run exercises default cwd from a directory outside the release.
    run!(
      wrapper,
      ["run", "--provider", "demo", "--yes", "Create and read the deterministic demo file"],
      default_workspace,
      env,
      "demo using default cwd"
    )

    assert_demo_file!(default_workspace)

    # Invoke from another arbitrary directory and require --cwd to select the
    # actual workspace rather than the caller directory or release directory.
    run!(
      wrapper,
      [
        "run",
        "--provider",
        "demo",
        "--yes",
        "--cwd",
        override_workspace,
        "Create and read the deterministic demo file"
      ],
      override_caller,
      env,
      "demo using --cwd"
    )

    assert_demo_file!(override_workspace)
    refute_demo_file!(override_caller)
    refute_demo_file!(release)

    eval = "Code.require_file(\"verify-release.exs\")"
    output = run!(otp_launcher, ["eval", eval], release, env, "bundled runtime/helper checks")

    unless String.contains?(
             output,
             "Bundled runtime/helper, timeout cleanup, owner-death cleanup, and locks passed."
           ) do
      raise "release helper verification did not print its completion marker: #{inspect(output)}"
    end

    unless String.contains?(
             output,
             "Bundled local MCP SDK round trip passed without a development toolchain."
           ) do
      raise "release MCP verification did not print its completion marker"
    end

    unless String.contains?(
             output,
             "Bundled MCP resource and prompt round trips passed."
           ) do
      raise "release MCP resource/prompt verification did not print its completion marker"
    end

    unless String.contains?(
             output,
             "Bundled local delegation approvals and child journal verification passed."
           ) do
      raise "release delegation verification did not print its completion marker"
    end

    unless String.contains?(output, "Bundled parallel local delegation verification passed."),
      do: raise("release parallel delegation verification did not print its completion marker")

    unless String.contains?(output, "Bundled Streamable HTTP MCP round trip passed."),
      do: raise("release network MCP verification did not print its completion marker")

    unless String.contains?(output, "Bundled long-turn output checkpoint verification passed."),
      do: raise("release long-turn checkpoint verification did not print its completion marker")

    unless String.contains?(output, "Bundled structured operator question verification passed."),
      do: raise("release question verification did not print its completion marker")

    unless String.contains?(
             output,
             "Bundled scoped configuration and model-profile verification passed"
           ),
           do:
             raise(
               "release configuration/profile verification did not print its completion marker"
             )

    unless String.contains?(output, "Bundled durable research ledger verification passed"),
      do: raise("release research verification did not print its completion marker")

    unless String.contains?(output, "Bundled diagnostics and explicit handoff export passed"),
      do: raise("release diagnostics/recovery verification did not print its completion marker")

    unless String.contains?(
             output,
             "Bundled fresh handoff import and unchanged idle resume passed"
           ),
           do: raise("release handoff import verification did not print its completion marker")

    unless String.contains?(
             output,
             "Self-development skill fixture passed without inference or effects"
           ),
           do:
             raise(
               "release self-development skill verification did not print its completion marker"
             )

    unless String.contains?(
             output,
             "Extension prompt/presentation and unchanged idle resume fixture passed"
           ),
           do: raise("release extension verification did not print its completion marker")

    IO.puts(
      "PASS: extracted package help, demo from isolated fresh HOME/IPSE_HOME, default cwd, explicit --cwd, bundled MCP/delegation/extensions, and OTP/helper checks."
    )

    IO.puts("Verified default workspace: #{default_workspace}")
    IO.puts("Verified --cwd workspace: #{override_workspace}")

    IO.puts(
      "CLI and standalone checks used a utility-only PATH. The precompiled memory harness adds only the selected bundled erl; no system development toolchain was available."
    )

    IO.puts(@job_timeout_note)
    %{"passed" => true, "standalone_release_checks" => true, "explicit_memory" => true}
  end

  defp run!(executable, args, cwd, env, label, merge_stderr \\ true) do
    {output, status} =
      System.cmd(executable, args,
        cd: cwd,
        env: env,
        stderr_to_stdout: merge_stderr
      )

    if status != 0 do
      raise "#{label} failed with exit #{status}: #{String.trim(output)}"
    end

    output
  end

  defp assert_demo_file!(workspace) do
    expected = "Hello from Ipse!\n"
    path = Path.join(workspace, "ipse-demo.txt")
    actual = File.read!(path)
    unless actual == expected, do: raise("unexpected demo file at #{path}: #{inspect(actual)}")
  end

  defp refute_demo_file!(workspace) do
    path = Path.join(workspace, "ipse-demo.txt")
    if File.exists?(path), do: raise("unexpected demo file in non-selected workspace: #{path}")
  end

  defp require_executable!(path) do
    case File.stat(path) do
      {:ok, %{type: :regular, mode: mode}} when Bitwise.band(mode, 0o111) != 0 -> :ok
      _ -> raise("required release launcher missing or not executable: #{path}")
    end
  end
end
