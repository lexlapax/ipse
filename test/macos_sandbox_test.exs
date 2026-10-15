defmodule Ipse.MacOSSandboxTest do
  use ExUnit.Case, async: false
  alias Ipse.Runner
  @moduletag :macos_sandbox

  setup_all do
    assert :os.type() == {:unix, :darwin}, "macOS enforcement requires a Mac host"
    root = Path.join(System.tmp_dir!(), "ipse-macos-native-#{System.unique_integer([:positive])}")
    cwd = Path.join(root, "workspace")
    home = Path.join(root, "state")
    File.mkdir_p!(cwd)
    File.mkdir!(home)
    File.chmod!(home, 0o700)
    previous = System.get_env("IPSE_HOME")
    System.put_env("IPSE_HOME", home)

    on_exit(fn ->
      if previous, do: System.put_env("IPSE_HOME", previous), else: System.delete_env("IPSE_HOME")
      File.rm_rf!(root)
    end)

    probe = Path.join(cwd, "probe")

    assert {_, 0} =
             System.cmd(
               "rustc",
               ["--edition=2021", "test/support/macos_native_probe.rs", "-o", probe],
               stderr_to_stdout: true
             )

    secret = Path.join(root, "outside-fixture-key")
    File.write!(secret, "fixture-private-value")
    File.chmod!(secret, 0o600)
    %{root: root, cwd: cwd, home: home, probe: probe, secret: secret}
  end

  test "outside files, symlink targets and signed cache are protected", ctx do
    File.ln_s!(ctx.secret, Path.join(ctx.cwd, "secret-link"))

    assert {:ok, policy} =
             Ipse.MacOSSandbox.prepare(Application.app_dir(:ipse, "priv/ipse-runner"), ctx.cwd)

    command =
      "set -e; " <>
        Enum.map_join(
          [ctx.secret, Path.join(ctx.cwd, "secret-link")],
          " ",
          fn path ->
            "if cat #{q(path)}; then exit 11; fi; if printf changed > #{q(path)}; then exit 12; fi; if chmod 777 #{q(path)}; then exit 13; fi;"
          end
        ) <>
        " if printf changed > #{q(policy.worker)}; then exit 14; fi; if chmod 777 #{q(policy.worker)}; then exit 15; fi; printf confined"

    assert {:ok, result} = Runner.run(command, ctx.cwd, sandbox: :native)
    assert result.exit_code == 0
    assert result.output =~ "confined"
    refute result.output =~ "fixture-private-value"
    assert File.read!(ctx.secret) == "fixture-private-value"
    assert Bitwise.band(File.stat!(ctx.secret).mode, 0o777) == 0o600
  end

  test "workspace, temporary home and installed Elixir work with a scrubbed environment", ctx do
    key = "IPSE_NATIVE_TEST_SECRET"
    previous = System.get_env(key)
    System.put_env(key, "fixture-must-not-reach-child")

    on_exit(fn ->
      if previous, do: System.put_env(key, previous), else: System.delete_env(key)
    end)

    File.write!(
      Path.join(ctx.cwd, "compile.ex"),
      "defmodule MacNativeFixture do\n def answer, do: 42\nend\n"
    )

    assert {:ok, result} =
             Runner.run(
               ~S[set -e; test -z "${IPSE_NATIVE_TEST_SECRET+x}"; printf workspace > writable; chmod 700 writable; printf temp > "$HOME/temp"; test "$HOME" = "$TMPDIR"; export ERL_FLAGS='+S 2'; elixirc compile.ex; test -s Elixir.MacNativeFixture.beam; printf compiled],
               ctx.cwd,
               sandbox: :native,
               timeout_ms: 20_000
             )

    assert result.exit_code == 0
    assert result.output =~ "compiled"
    assert Bitwise.band(File.stat!(Path.join(ctx.cwd, "writable")).mode, 0o777) == 0o700
  end

  test "network positive control connects and sandboxed connect returns EPERM", ctx do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    on_exit(fn -> :gen_tcp.close(listener) end)
    {:ok, port} = :inet.port(listener)
    assert {"network allow\n", 0} = System.cmd(ctx.probe, ["network", to_string(port), "allow"])
    assert {:ok, connection} = :gen_tcp.accept(listener, 2_000)
    :gen_tcp.close(connection)

    assert {:ok, %{exit_code: 0, output: "network deny\n"}} =
             Runner.run("./probe network #{port} deny", ctx.cwd, sandbox: :native)

    assert {:error, :timeout} = :gen_tcp.accept(listener, 100)
  end

  test "host signals and resource limit increases are denied", ctx do
    assert {:ok, %{exit_code: 0, output: "host signals denied\n"}} =
             Runner.run("exec ./probe signals #{System.pid()}", ctx.cwd, sandbox: :native)

    assert {:ok, %{exit_code: 0, output: "resource limits enforced\n"}} =
             Runner.run("./probe limits", ctx.cwd, sandbox: :native, timeout_ms: 5_000)
  end

  test "timeout and owner death stop ordinary process-group children", ctx do
    parent = self()

    assert {:ok, result} =
             Runner.run(
               "(printf timeout-ready; sleep 1.7; printf escaped > timeout-effect) & wait",
               ctx.cwd,
               sandbox: :native,
               timeout_ms: 1_000,
               emit: &send(parent, &1)
             )

    assert_receive {:tool_output, "timeout-ready"}, 2_000
    assert result.timed_out

    owner =
      spawn(fn ->
        Runner.run(
          "(printf owner-ready; sleep 0.7; printf escaped > owner-effect) & wait",
          ctx.cwd,
          sandbox: :native,
          emit: &send(parent, &1)
        )
      end)

    on_exit(fn -> if Process.alive?(owner), do: Process.exit(owner, :kill) end)
    assert_receive {:tool_output, "owner-ready"}, 10_000
    Process.exit(owner, :kill)
    Process.sleep(1_850)
    refute File.exists?(Path.join(ctx.cwd, "timeout-effect"))
    refute File.exists?(Path.join(ctx.cwd, "owner-effect"))
  end

  test "detached child can outlive its parent but stays confined and cannot hold completion open",
       ctx do
    task =
      Task.async(fn ->
        Runner.run("exec ./probe detach #{q(ctx.secret)}", ctx.cwd, sandbox: :native)
      end)

    await_file(Path.join(ctx.cwd, "detached-ready"), 1_000)

    assert {:ok, %{exit_code: 0, timed_out: false}} =
             Task.await(task, 2_000)

    File.write!(Path.join(ctx.cwd, "release-detached"), "go")
    await_file(Path.join(ctx.cwd, "detached-confined"), 100)
    assert File.read!(ctx.secret) == "fixture-private-value"
  end

  test "workspace containing the running application fails closed" do
    assert {:error, reason} =
             Runner.run("printf changed > must-not-run", File.cwd!(), sandbox: :native)

    assert reason =~ "overlaps"
    refute File.exists?(Path.join(File.cwd!(), "must-not-run"))
  end

  test "a changed signed worker is rejected before command execution", ctx do
    assert {:ok, policy} =
             Ipse.MacOSSandbox.prepare(Application.app_dir(:ipse, "priv/ipse-runner"), ctx.cwd)

    original = File.read!(policy.worker)

    try do
      File.write!(policy.worker, original <> "changed")

      assert {:error, _} =
               Runner.run("printf changed > corrupt-worker-effect", ctx.cwd, sandbox: :native)

      refute File.exists?(Path.join(ctx.cwd, "corrupt-worker-effect"))
    after
      File.write!(policy.worker, original)
    end
  end

  defp await_file(path, tries) when tries > 0 do
    if File.regular?(path),
      do: :ok,
      else:
        (
          Process.sleep(20)
          await_file(path, tries - 1)
        )
  end

  defp await_file(_path, 0), do: flunk("detached child did not complete its bounded probe")
  defp q(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"
end
