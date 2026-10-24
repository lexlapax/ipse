defmodule Ipse.CLI.ErrorsTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias Ipse.CLI.Errors

  @mapped ~w(invalid_handoff invalid_handoff_record resume_configuration_mismatch journal_limit_reached invalid_session session_not_found invalid_id invalid_journal incomplete_journal session_locked journal_unavailable workspace_not_found invalid_provider_endpoint question_confirmation invalid_answer)a

  test "each mapped error supplies a cause and a real recovery anchor without term dumps" do
    for reason <- @mapped do
      %{text: text, recovery: recovery} = Errors.message(reason)
      refute text =~ "Unexpected error"
      refute text =~ "%{"
      refute text =~ "#PID"
      refute text =~ "/home/"
      refute text =~ "fixture-private-key"
      [path, anchor] = String.split(recovery, "#")
      assert File.regular?(path)
      assert anchor in recovery_anchors(path)
      assert Errors.format(reason) == text <> " See " <> recovery <> "."
    end
  end

  defp recovery_anchors(path) do
    Regex.scan(~r/^\#+ (.+)$/m, File.read!(path), capture: :all_but_first)
    |> Enum.map(fn [heading] ->
      heading
      |> String.downcase()
      |> String.replace(~r/[^\p{L}\p{N}_ -]/u, "")
      |> String.replace(" ", "-")
    end)
  end

  test "binary diagnostics refuse raw paths, terms, controls and oversized text" do
    for text <- [
          "cannot resolve /home/private: :eacces",
          "failed %{token: secret}",
          "failed {:secret, value}",
          "failed #PID<0.1.0>",
          "oops\e[2J",
          <<255>>,
          String.duplicate("x", 2049)
        ] do
      output = Errors.format(text)
      assert output =~ "Unexpected error"
      refute output =~ text
    end
  end

  test "runtime error producers do not inspect arbitrary reasons" do
    for path <- Path.wildcard("lib/ipse/**/*.ex") do
      refute File.read!(path) =~ ~r/inspect\((?:reason|error)\)/,
             "arbitrary error inspection in #{path}"
    end
  end

  test "context refresh reports recovery without embedding its reason" do
    state = %{subscriber: self(), phase: :idle, job_ref: nil}
    reason = {:unexpected, "/home/private", %{token: "fixture-private"}}
    assert {:noreply, _} = Ipse.Session.Turn.context_refresh_failed(state, reason)
    assert_receive {:ipse, _, {:error, text}}
    assert text =~ "retry the context refresh command"
    refute text =~ "private"
    refute text =~ "%{"
    assert_receive {:ipse, _, {:done, {:error, ^reason}}}
  end

  test "unexpected terms and exception messages never become diagnostics" do
    secret = "/home/private/fixture-private-key"

    for term <- [
          %{api_key: secret, pid: self()},
          {:unrecognized, secret, self()},
          %{__exception__: true, __struct__: secret},
          ArgumentError.exception(secret),
          File.Error.exception(reason: :enoent, path: secret, action: "read"),
          :"/home/private/fixture-private-key"
        ] do
      output = Errors.format(term)
      assert output =~ "Unexpected error ("
      assert output =~ "#report-a-reproducible-problem"
      refute output =~ secret
      refute output =~ "#PID"
      refute output =~ "%{"
    end

    assert Errors.message({:already_registered, self()}) == Errors.message(:session_locked)
    assert Errors.message({:corrupt_journal, secret}) == Errors.message(:invalid_journal)

    assert Errors.message({:shutdown, {:failed_to_start_child, secret, :invalid_session}}) ==
             Errors.message(:invalid_session)
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-cli-errors-#{System.unique_integer([:positive])}")
    cwd = Path.join(root, "workspace")
    home = Path.join(root, "home")
    File.mkdir_p!(cwd)
    File.mkdir_p!(home)
    previous = System.get_env("IPSE_HOME")
    System.put_env("IPSE_HOME", home)

    on_exit(fn ->
      if previous, do: System.put_env("IPSE_HOME", previous), else: System.delete_env("IPSE_HOME")
      File.rm_rf!(root)
    end)

    %{cwd: cwd, home: home, state: Path.join(home, "sessions")}
  end

  test "missing, invalid and malformed sessions refuse before creating state", c do
    args = [
      "chat",
      "--cwd",
      c.cwd,
      "--no-project-config",
      "--provider",
      "demo",
      "--state-dir",
      c.state
    ]

    for {id, reason} <- [
          {String.duplicate("a", 32), :session_not_found},
          {"/home/fixture-private-key", :invalid_id}
        ] do
      assert capture_io(:stderr, fn -> assert Ipse.CLI.run(args ++ ["--resume", id]) == 1 end) ==
               "Cannot start: " <> Errors.format(reason) <> "\n"

      refute File.exists?(c.state)
    end

    File.mkdir_p!(c.state)
    id = String.duplicate("b", 32)
    path = Path.join(c.state, id <> ".jsonl")
    bytes = "{malformed-private-record\n"
    File.write!(path, bytes)

    assert capture_io(:stderr, fn -> assert Ipse.CLI.run(args ++ ["--resume", id]) == 1 end) ==
             "Cannot start: " <> Errors.format(:invalid_journal) <> "\n"

    assert File.read!(path) == bytes
  end

  test "locked and incompatible journals retain distinct errors and unchanged bytes", c do
    {:ok, id} = Ipse.Journal.create(c.state, %{provider: "demo", model: "scripted", cwd: c.cwd})
    path = Path.join(c.state, id <> ".jsonl")
    bytes = File.read!(path)

    args = [
      "chat",
      "--cwd",
      c.cwd,
      "--no-project-config",
      "--provider",
      "demo",
      "--state-dir",
      c.state,
      "--resume",
      id
    ]

    {:ok, lock} = Ipse.Runner.lock(Path.join(c.state, id <> ".lock"))

    try do
      assert capture_io(:stderr, fn -> assert Ipse.CLI.run(args) == 1 end) ==
               "Cannot start: " <> Errors.format(:session_locked) <> "\n"
    after
      Ipse.Runner.unlock(lock)
    end

    assert capture_io(:stderr, fn ->
             assert Ipse.CLI.run(args ++ ["--model", "different"]) == 1
           end) ==
             "Cannot start: " <> Errors.format(:resume_configuration_mismatch) <> "\n"

    assert File.read!(path) == bytes
  end

  test "invalid options never echo supplied values", c do
    output =
      capture_io(:stderr, fn ->
        assert Ipse.CLI.run(["--timeout-ms", "fixture-private-key"]) == 1
      end)

    assert output =~ "Unknown or invalid options. Run ipse --help"
    refute output =~ "fixture-private-key"
    refute File.exists?(c.state)
  end

  test "status emits the Auth status keys as JSON without credentials", c do
    dir = Path.join(c.home, "auth")
    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)

    record = %{
      "access_token" => "fixture-private-key",
      "refresh_token" => "fixture-private-refresh",
      "client_id" => "oaiapp_test",
      "subject" => "fixture-account",
      "email" => "fixture@example.test",
      "expires_at" => System.system_time(:second) + 3600,
      "scopes" => ["chatgpt.tokens.use.direct"]
    }

    assert :ok = Ipse.Auth.write_credentials(dir, record)
    {:ok, expected} = Ipse.Auth.status(dir)
    output = capture_io(fn -> assert Ipse.CLI.run(["status"]) == 0 end)
    assert Jason.decode!(output) == expected |> Jason.encode!() |> Jason.decode!()
    refute output =~ "fixture-private"
    refute File.exists?(c.state)
  end

  test "profile errors name the profile and field without its value", c do
    path = Path.join(c.home, "config.json")
    base = %{"provider" => "openai", "model" => "fixture"}

    for {field, value} <- [
          {"credential", "fixture-private-key"},
          {"model", "fixture-private-key?"},
          {"base_url", "https://fixture-private-key@example.test"},
          {"reasoning_effort", "fixture-private-key"},
          {"max_output_tokens", "fixture-private-key"}
        ] do
      File.write!(
        path,
        Jason.encode!(%{version: 1, profiles: %{primary: Map.put(base, field, value)}})
      )

      output =
        capture_io(:stderr, fn ->
          assert Ipse.CLI.run(["config", "--cwd", c.cwd, "--no-project-config"]) == 1
        end)

      assert output ==
               Errors.format(
                 "Profile primary: Invalid profile field #{field}. No model request was sent; see docs/operator/configuration.md#reuse-a-named-model-profile."
               ) <> "\n"

      refute output =~ "fixture-private-key"
    end

    refute File.exists?(c.state)
  end

  test "MCP errors name a server and field while withholding private values", c do
    path = Path.join(c.home, "mcp.json")
    base = %{"id" => "notes", "command" => "/bin/echo", "tools" => ["lookup"]}

    for {field, value} <- [
          {"command", "/fixture-private-key"},
          {"args", "fixture-private-key"},
          {"env", %{"OPENAI_API_KEY" => "fixture-private-key"}},
          {"tools", ["fixture-private-key?"]},
          {"timeout_ms", "fixture-private-key"}
        ] do
      File.write!(path, Jason.encode!(%{servers: [Map.put(base, field, value)]}))

      assert Ipse.MCP.Config.load(path) ==
               {:error,
                "MCP server notes has invalid #{field}. No server was launched; see docs/operator/mcp.md#configure-a-local-stdio-server."}
    end

    remote = %{
      "id" => "remote",
      "transport" => "http",
      "url" => "https://example.test/mcp",
      "tools" => ["lookup"]
    }

    for {field, value, reported} <- [
          {"url", "https://fixture-private-key@example.test", "url"},
          {"bearer_env", "fixture-private-key", "headers"}
        ] do
      File.write!(path, Jason.encode!(%{servers: [Map.put(remote, field, value)]}))

      assert Ipse.MCP.Config.load(path) ==
               {:error,
                "MCP server remote has invalid #{reported}. No server was launched; see docs/operator/mcp.md#configure-a-local-stdio-server."}
    end

    owner = Map.put(base, "env", %{"TOKEN" => "privatekey"})
    hidden = base |> Map.put("id", "privatekey") |> Map.put("command", "invalid")
    File.write!(path, Jason.encode!(%{servers: [owner, hidden]}))

    assert Ipse.MCP.Config.load(path) ==
             {:error,
              "MCP server #2 has invalid command. No server was launched; see docs/operator/mcp.md#configure-a-local-stdio-server."}

    refute File.exists?(c.state)
  end
end
