defmodule Ipse.CLI.DoctorTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  alias Ipse.CLI.Doctor

  @ids ~w(runtime.build home.layout config.files config.provider credentials.selected sandbox.native mcp.config extensions.selection sessions.store provider.reachability)

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-doctor-" <> Ipse.Usage.id())
    cwd = Path.join(root, "workspace")
    home = Path.join(root, "operator")
    File.mkdir_p!(cwd)
    previous = System.get_env("IPSE_HOME")
    System.put_env("IPSE_HOME", home)

    on_exit(fn ->
      if previous, do: System.put_env("IPSE_HOME", previous), else: System.delete_env("IPSE_HOME")
      File.rm_rf!(root)
    end)

    %{root: root, cwd: cwd, home: home}
  end

  defp doctor(c, opts \\ []),
    do: Doctor.run([provider: "demo", project_config: false] ++ opts, c.home, c.cwd)

  defp finding(report, id), do: Enum.find(report["checks"], &(&1["id"] == id))

  defp save(c, data, mode \\ 0o600) do
    File.mkdir_p!(c.home)
    File.chmod!(c.home, 0o700)
    path = Path.join(c.home, "config.json")
    File.write!(path, Jason.encode!(data))
    File.chmod!(path, mode)
    path
  end

  test "stable offline JSON shape and missing private state remain read-only", c do
    {0, report} = doctor(c)
    assert report["version"] == 1
    assert report["build"] == Ipse.build_info()
    assert Enum.map(report["checks"], & &1["id"]) == @ids

    for row <- report["checks"] do
      assert row["status"] in ~w(ok warn fail skip)
      assert is_binary(row["summary"])
      assert is_binary(row["recovery"])
    end

    assert finding(report, "home.layout")["status"] == "ok"
    assert finding(report, "sessions.store")["status"] == "ok"
    assert finding(report, "credentials.selected")["status"] == "ok"
    assert finding(report, "provider.reachability")["status"] == "skip"
    refute File.exists?(c.home)

    output =
      capture_io(fn ->
        assert Ipse.CLI.run([
                 "doctor",
                 "--json",
                 "--provider",
                 "demo",
                 "--no-project-config",
                 "--cwd",
                 c.cwd
               ]) == 0
      end)

    assert Jason.decode!(output)["checks"] == report["checks"]
    refute File.exists?(c.home)
  end

  test "unsafe directory modes fail; default provider and readable operator files warn", c do
    path = save(c, %{version: 1}, 0o644)
    {_, report} = Doctor.run([project_config: false], c.home, c.cwd)
    assert finding(report, "config.files")["status"] == "warn"
    assert finding(report, "config.provider")["status"] == "warn"
    assert finding(report, "config.provider")["summary"] =~ "built-in default"
    assert finding(report, "config.provider")["summary"] =~ "ipse setup"
    assert File.stat!(path).mode |> Bitwise.band(0o777) == 0o644

    File.mkdir!(Path.join(c.home, "auth"))
    File.chmod!(Path.join(c.home, "auth"), 0o755)
    {1, report} = doctor(c)
    assert finding(report, "home.layout")["status"] == "fail"
    File.chmod!(Path.join(c.home, "auth"), 0o700)
    File.chmod!(c.home, 0o777)
    {1, report} = doctor(c)
    assert finding(report, "home.layout")["status"] == "fail"
    assert File.stat!(c.home).mode |> Bitwise.band(0o777) == 0o777
  end

  test "invalid configuration, endpoint and MCP each produce independent findings", c do
    path = save(c, %{version: 1})
    File.write!(path, "{invalid-private-value")
    {1, report} = doctor(c)
    assert finding(report, "config.files")["status"] == "fail"
    assert finding(report, "config.provider")["status"] == "skip"
    refute Jason.encode!(report) =~ "invalid-private-value"

    File.rm!(path)
    {1, report} = doctor(c, base_url: "https://private-value@example.test")
    assert finding(report, "config.provider")["status"] == "fail"
    refute Jason.encode!(report) =~ "private-value"

    {1, report} = doctor(c, mcp_config: Path.join(c.root, "missing-mcp"))
    assert finding(report, "mcp.config")["status"] == "fail"
  end

  test "untrusted project files retain independent parse and trust diagnostics", c do
    path = Path.join(c.cwd, ".ipse/config.json")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{version: 1, settings: %{provider: "demo"}}))
    {1, report} = Doctor.run([], c.home, c.cwd)
    row = Enum.find(finding(report, "config.files")["detail"], &(&1["path"] == path))
    assert row["parsed"]
    refute row["trusted"]
    assert row["summary"] =~ "not admitted"

    assert finding(report, "config.files")["summary"] =~
             "requires explicit --trust-project-config"

    File.write!(path, "{private-invalid")
    {1, report} = Doctor.run([], c.home, c.cwd)
    row = Enum.find(finding(report, "config.files")["detail"], &(&1["path"] == path))
    refute row["parsed"]
    refute row["trusted"]
    refute Jason.encode!(report) =~ "private-invalid"
    refute File.exists?(c.home)
  end

  test "selected profile and role credentials never expose their synthetic key", c do
    key = "fixture-doctor-private-key"
    previous = System.get_env("OPENAI_API_KEY")
    System.put_env("OPENAI_API_KEY", key)

    on_exit(fn ->
      if previous,
        do: System.put_env("OPENAI_API_KEY", previous),
        else: System.delete_env("OPENAI_API_KEY")
    end)

    save(c, %{
      version: 1,
      profiles: %{api: %{provider: "openai", model: "fixture"}},
      roles: %{routine: "api"}
    })

    {0, report} = doctor(c)
    assert finding(report, "credentials.selected")["status"] == "ok"
    refute Jason.encode!(report) =~ key
    System.delete_env("OPENAI_API_KEY")
    {1, report} = doctor(c)
    assert finding(report, "credentials.selected")["status"] == "fail"
    refute Jason.encode!(report) =~ key
  end

  test "subscription expiry is inspected without refreshing the credentials", c do
    dir = Path.join(c.home, "auth")
    File.mkdir_p!(dir)
    File.chmod!(c.home, 0o700)
    File.chmod!(dir, 0o700)

    record = %{
      "client_id" => "oaiapp_fixture",
      "subject" => "fixture",
      "access_token" => "doctor-private-access",
      "refresh_token" => "doctor-private-refresh",
      "expires_at" => 0
    }

    :ok = Ipse.Auth.write_credentials(dir, record)
    path = Path.join(dir, "chatgpt.json")
    bytes = File.read!(path)
    {1, report} = Doctor.run([provider: "chatgpt", project_config: false], c.home, c.cwd)
    assert finding(report, "credentials.selected")["status"] == "fail"
    assert File.read!(path) == bytes
    assert File.ls!(dir) == ["chatgpt.json"]
    refute Jason.encode!(report) =~ "doctor-private"

    :ok =
      Ipse.Auth.write_credentials(
        dir,
        Map.put(record, "expires_at", System.system_time(:second) + 3600)
      )

    {0, report} = Doctor.run([provider: "chatgpt", project_config: false], c.home, c.cwd)
    assert finding(report, "credentials.selected")["status"] == "ok"
    assert finding(report, "provider.reachability")["status"] == "skip"
  end

  test "session inspection preserves a real held lock and malformed headers", c do
    store = Path.join(c.home, "sessions")
    {:ok, id} = Ipse.Journal.create(store, %{provider: "demo", model: "scripted", cwd: c.cwd})
    bad = Path.join(store, String.duplicate("a", 32) <> ".jsonl")
    File.write!(bad, "{invalid\n")
    {:ok, lock} = Ipse.Runner.lock(Path.join(store, id <> ".lock"))

    try do
      {0, report} = doctor(c)
      assert finding(report, "sessions.store")["status"] == "warn"

      assert finding(report, "sessions.store")["summary"] =~
               "1 readable session headers; 1 unreadable"

      assert File.read!(bad) == "{invalid\n"
      assert {:error, reason} = Ipse.Runner.lock(Path.join(store, id <> ".lock"))
      assert reason =~ "cannot acquire session lock"
    after
      Ipse.Runner.unlock(lock)
    end
  end

  test "offline means no connection; explicit probing sends exactly one GET", c do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    on_exit(fn -> :gen_tcp.close(listener) end)
    opts = [provider: "ollama", base_url: "http://127.0.0.1:#{port}", project_config: false]
    {0, report} = Doctor.run(opts, c.home, c.cwd)
    assert finding(report, "provider.reachability")["status"] == "skip"
    assert {:error, :timeout} = :gen_tcp.accept(listener, 0)

    owner = self()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        {:ok, request} = :gen_tcp.recv(socket, 0, 5000)
        send(owner, {:probe, request})

        :gen_tcp.send(
          socket,
          "HTTP/1.1 200 OK\r\ncontent-length: 999999999\r\nconnection: close\r\n\r\n"
        )

        :gen_tcp.close(socket)
      end)

    {0, report} = Doctor.run([probe_provider: true] ++ opts, c.home, c.cwd)
    assert finding(report, "provider.reachability")["status"] == "ok"
    assert_receive {:probe, request}
    assert String.starts_with?(request, "GET /api/tags HTTP/1.1\r\n")
    refute request =~ "POST"
    Task.await(server)
    assert {:error, :timeout} = :gen_tcp.accept(listener, 0)
    refute File.exists?(c.home)
  end

  test "extension admission verifies selected artifacts without starting workers", c do
    artifact = "builtin:prompt-annotation:1"

    trust = %{
      artifact: artifact,
      capabilities: ["transform.prompt"],
      allow_project: false,
      allow_children: false
    }

    instance = %{
      instance: "annotation",
      artifact: artifact,
      enabled: true,
      options: %{text: "Synthetic note"},
      order: 0,
      lifetime: "session"
    }

    config = %{version: 1, extension_trust: [trust], extensions: [instance]}
    save(c, config)
    {0, report} = doctor(c)
    row = finding(report, "extensions.selection")
    assert row["status"] == "ok"
    assert row["detail"] == ["annotation"]
    refute File.exists?(Path.join(c.home, "sessions"))

    missing = String.duplicate("a", 64)

    save(c, %{
      config
      | extension_trust: [%{trust | artifact: missing}],
        extensions: [%{instance | artifact: missing}]
    })

    {1, report} = doctor(c)
    assert finding(report, "extensions.selection")["status"] == "fail"
    refute File.exists?(Path.join(c.home, "extensions"))
  end

  test "native policy availability is distinct from enforcement and requested policy", c do
    if :os.type() in [{:unix, :linux}, {:unix, :darwin}] do
      {0, report} = doctor(c)
      native = finding(report, "sandbox.native")
      assert native["status"] == if(:os.type() == {:unix, :darwin}, do: "warn", else: "ok")
      assert native["detail"] =~ "kernel enforcement was not probed"

      for {policy, status, code} <- [{"off", "warn", 0}, {"native", "fail", 1}] do
        assert {^code, refused} =
                 Doctor.run(
                   [provider: "demo", project_config: false, sandbox: policy],
                   c.home,
                   Application.app_dir(:ipse)
                 )

        assert finding(refused, "sandbox.native")["status"] == status
      end
    end
  end

  test "credential, rate and server probe refusals are bounded and never retried", c do
    for status <- [401, 403, 429, 503] do
      {:ok, listener} =
        :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

      {:ok, {_, port}} = :inet.sockname(listener)

      server =
        Task.async(fn ->
          {:ok, socket} = :gen_tcp.accept(listener, 5000)
          {:ok, _} = :gen_tcp.recv(socket, 0, 5000)

          :gen_tcp.send(
            socket,
            "HTTP/1.1 #{status} Refused\r\ncontent-length: 0\r\nconnection: close\r\n\r\n"
          )

          :gen_tcp.close(socket)
        end)

      try do
        {1, report} =
          Doctor.run(
            [
              provider: "ollama",
              project_config: false,
              base_url: "http://127.0.0.1:#{port}",
              probe_provider: true
            ],
            c.home,
            c.cwd
          )

        assert finding(report, "provider.reachability")["status"] == "fail"
        Task.await(server)
        assert {:error, :timeout} = :gen_tcp.accept(listener, 0)
      after
        :gen_tcp.close(listener)
      end
    end

    assert capture_io(:stderr, fn ->
             assert Ipse.CLI.run(["run", "--probe-provider", "never dispatch"]) == 1
           end) =~ "--probe-provider requires ipse doctor"
  end

  test "explicit route probes use the selected API headers without masking a failed main route",
       c do
    key_values = %{
      "OPENAI_API_KEY" => "fixture-doctor-openai-private",
      "ANTHROPIC_API_KEY" => "fixture-doctor-anthropic-private"
    }

    previous = Map.new(key_values, fn {key, _} -> {key, System.get_env(key)} end)
    Enum.each(key_values, fn {key, value} -> System.put_env(key, value) end)

    on_exit(fn ->
      for {key, value} <- previous,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    base = "http://127.0.0.1:#{port}"

    save(c, %{
      version: 1,
      settings: %{provider: "openai", model: "fixture"},
      profiles: %{aux: %{provider: "anthropic", model: "fixture", base_url: base}},
      roles: %{routine: "aux", review: "aux"}
    })

    server =
      Task.async(fn ->
        for status <- [401, 200] do
          {:ok, socket} = :gen_tcp.accept(listener, 5_000)
          {:ok, request} = :gen_tcp.recv(socket, 0, 5_000)

          :gen_tcp.send(
            socket,
            "HTTP/1.1 #{status} Fixture\r\ncontent-length: 0\r\nconnection: close\r\n\r\n"
          )

          :gen_tcp.close(socket)
          String.downcase(request)
        end
      end)

    try do
      {1, report} =
        Doctor.run([project_config: false, base_url: base, probe_provider: true], c.home, c.cwd)

      row = finding(report, "provider.reachability")
      assert row["status"] == "fail"

      assert Enum.map(row["detail"], &{&1["provider"], &1["status"]}) == [
               {"openai", "fail"},
               {"anthropic", "ok"}
             ]

      [main, role] = Task.await(server)
      assert String.starts_with?(main, "get /models http/1.1\r\n")
      assert main =~ "authorization: bearer fixture-doctor-openai-private\r\n"
      assert String.starts_with?(role, "get /v1/models http/1.1\r\n")
      assert role =~ "x-api-key: fixture-doctor-anthropic-private\r\n"
      assert role =~ "anthropic-version: 2023-06-01\r\n"
      human = capture_io(fn -> Doctor.print(report, false) end)

      for secret <- Map.values(key_values) do
        refute Jason.encode!(report) =~ secret
        refute human =~ secret
      end

      assert {:error, :timeout} = :gen_tcp.accept(listener, 0)
    after
      :gen_tcp.close(listener)
    end
  end

  test "new provider probes stay offline by default and use only their native metadata headers",
       c do
    for {provider, variable, header} <- [
          {"gemini", "GEMINI_API_KEY", "x-goog-api-key"},
          {"openrouter", "OPENROUTER_API_KEY", "authorization"},
          {"openai_compatible", nil, nil}
        ] do
      previous = if variable, do: System.get_env(variable)
      if variable, do: System.put_env(variable, "fixture-probe-private")

      {:ok, listener} =
        :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

      {:ok, {_, port}} = :inet.sockname(listener)

      profile = %{
        "provider" => provider,
        "model" => "fixture",
        "base_url" => "http://127.0.0.1:#{port}"
      }

      profile =
        if provider == "openrouter", do: Map.put(profile, "upstream", "openai"), else: profile

      save(c, %{
        "version" => 1,
        "profiles" => %{"selected" => profile},
        "roles" => %{"main" => "selected"}
      })

      try do
        assert {0, report} = Doctor.run([project_config: false], c.home, c.cwd)
        assert finding(report, "provider.reachability")["status"] == "skip"
        assert {:error, :timeout} = :gen_tcp.accept(listener, 0)

        server =
          Task.async(fn ->
            {:ok, socket} = :gen_tcp.accept(listener, 5000)
            {:ok, request} = :gen_tcp.recv(socket, 0, 5000)

            :ok =
              :gen_tcp.send(
                socket,
                "HTTP/1.1 200 OK\r\ncontent-length: 0\r\nconnection: close\r\n\r\n"
              )

            :gen_tcp.close(socket)
            String.downcase(request)
          end)

        assert {0, report} =
                 Doctor.run([project_config: false, probe_provider: true], c.home, c.cwd)

        assert finding(report, "provider.reachability")["status"] == "ok"
        request = Task.await(server)
        assert String.starts_with?(request, "get /models http/1.1\r\n")

        if header do
          assert request =~
                   header <>
                     ": " <>
                     if(provider == "openrouter", do: "bearer ", else: "") <>
                     "fixture-probe-private"
        else
          refute request =~ "authorization:"
          refute request =~ "x-goog-api-key:"
        end

        refute Jason.encode!(report) =~ "fixture-probe-private"
        assert {:error, :timeout} = :gen_tcp.accept(listener, 0)
      after
        :gen_tcp.close(listener)

        if variable do
          if previous, do: System.put_env(variable, previous), else: System.delete_env(variable)
        end
      end
    end
  end

  @tag timeout: 20_000
  test "a stalled metadata response reaches the total deadline and closes its client", c do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    owner = self()

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5_000)
        {:ok, request} = :gen_tcp.recv(socket, 0, 5_000)
        send(owner, {:stalled_probe, request})
        closed = :gen_tcp.recv(socket, 0, 13_000)
        :gen_tcp.close(socket)
        closed
      end)

    try do
      started = System.monotonic_time(:millisecond)

      {1, report} =
        Doctor.run(
          [
            provider: "ollama",
            project_config: false,
            base_url: "http://127.0.0.1:#{port}",
            probe_provider: true
          ],
          c.home,
          c.cwd
        )

      elapsed = System.monotonic_time(:millisecond) - started
      assert elapsed < 13_000
      assert finding(report, "provider.reachability")["status"] == "fail"
      assert_receive {:stalled_probe, request}
      assert String.starts_with?(request, "GET /api/tags HTTP/1.1\r\n")
      assert Task.await(server, 5_000) == {:error, :closed}
      assert {:error, :timeout} = :gen_tcp.accept(listener, 0)
    after
      :gen_tcp.close(listener)
    end
  end
end
