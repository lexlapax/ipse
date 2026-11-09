defmodule Ipse.CLI.DocumentsTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-documents-setup-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    cwd = Path.join(root, "workspace")
    File.mkdir!(cwd)
    home = Path.join(root, "home")
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, cwd: cwd, home: home}
  end

  test "both packaged profiles preview without home, import, identity or inference", c do
    for {profile, extra} <- [{"state", []}, {"collection", [scope: "folder"]}] do
      output =
        capture_io(fn ->
          assert Ipse.CLI.Documents.run("setup", [profile: profile] ++ extra, c.home, c.cwd) == 0
        end)

      assert output =~ "Exact document selection"
      assert output =~ "\"instance\": \"documents\""
      assert output =~ "Dry run"
      refute File.exists?(c.home)
    end
  end

  test "unsupported flags and scope cannot bypass native review", c do
    for opts <- [
          [profile: "state", yes: true],
          [profile: "state", scope: "folder"],
          [profile: "collection"],
          [profile: "unknown"],
          [profile: "state", provider: "demo"]
        ] do
      capture_io(:stderr, fn ->
        assert Ipse.CLI.Documents.run("setup", opts, c.home, c.cwd) == 1
      end)

      refute File.exists?(c.home)
    end
  end

  @tag :native_storage
  test "native setup, new session and disable preserve source and provider selections", c do
    for profile <- ~w(state collection),
        do: assert(scenario(c, profile, "--knowledge") =~ "DOCUMENT_SETUP_JOURNEY_PASSED")
  end

  test "piped, cancelled, stale and concurrently changed reviews save nothing", c do
    for {name, mode} <- [
          {"pipe", nil},
          {"cancel", "--knowledge-cancel"},
          {"stale", "--knowledge-stale"},
          {"race", "--knowledge-config"}
        ] do
      assert scenario(c, name, mode) =~ "DOCUMENT_SETUP_REFUSAL_PASSED"
    end
  end

  test "shared configuration writer refuses another writer's lock and stale bytes", c do
    path = Path.join(c.home, "config.json")
    original = %{bytes: nil, document: %{"version" => 1}}
    assert :ok = Ipse.PrivateFile.write_atomic(path <> ".lock", "", replace: false)
    {:ok, lock} = Ipse.Runner.lock(path <> ".lock")

    try do
      assert {:error, _} = Ipse.CLI.Setup.write_configuration(path, ~s({"version":1}), original)
      refute File.exists?(path)
    after
      Ipse.Runner.unlock(lock)
    end

    assert :ok =
             Ipse.PrivateFile.write_atomic(path, ~s({"version":1,"settings":{"provider":"demo"}}))

    assert {:error, _} = Ipse.CLI.Setup.write_configuration(path, ~s({"version":1}), original)
    assert Path.wildcard(path <> ".bak-*") == []
  end

  test "disable previews only the option digest and replacement requires explicit review", c do
    File.mkdir!(c.home)
    path = Path.join(c.home, "config.json")
    private = "synthetic-private-option-value"

    document = %{
      "version" => 1,
      "extensions" => [
        %{
          "instance" => "documents",
          "artifact" => "builtin:prompt-annotation:1",
          "enabled" => false,
          "options" => %{"text" => private},
          "order" => 0,
          "lifetime" => "session"
        }
      ]
    }

    bytes = Jason.encode!(document)
    File.write!(path, bytes)

    output =
      capture_io(fn -> assert Ipse.CLI.Documents.run("disable", [], c.home, c.cwd) == 0 end)

    assert output =~ "options_sha256"
    refute output =~ private

    assert capture_io(:stderr, fn ->
             assert Ipse.CLI.Documents.run("setup", [profile: "state"], c.home, c.cwd) == 1
           end) =~ "--replace"

    capture_io(fn ->
      assert Ipse.CLI.Documents.run("setup", [profile: "state", replace: true], c.home, c.cwd) ==
               0
    end)

    assert File.read!(path) == bytes
    refute File.exists?(Path.join(c.home, "extensions"))
    refute File.exists?(path <> ".lock")
  end

  defp scenario(c, name, mode) do
    root = Path.join(c.root, name)
    File.mkdir!(root)
    File.chmod!(root, 0o700)

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    args =
      ["--erl", "+S 2:2"] ++
        paths ++ [Path.expand("test/support/documents_setup.exs"), root, name]

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
end
