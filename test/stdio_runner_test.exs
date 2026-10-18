defmodule Ipse.StdioRunnerTest do
  use ExUnit.Case, async: false
  alias Ipse.Runner

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-stdio-#{System.unique_integer([:positive])}")
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

    %{cwd: cwd}
  end

  test "raw input reaches a direct child and stdout/stderr frames remain separate", %{cwd: cwd} do
    script = ~S[IFS= read -r line; printf 'out:%s' "$line"; printf 'diagnostic' >&2; exit 7]
    {:ok, port} = Runner.open_stdio("/bin/sh", ["-c", script], cwd, %{}, 2_000)
    assert :ok = Runner.send_stdio(port, "hello\n")
    {frames, status} = collect(port)
    assert status == 0
    assert stream(frames, ?O) == "out:hello"
    assert stream(frames, ?S) == "diagnostic"
    assert completion(frames) == %{"exit_code" => 7, "timed_out" => false}
    refute Enum.any?(frames, &(elem(&1, 0) == ?E))
  end

  test "arguments containing shell syntax are literal and the chosen cwd is used", %{cwd: cwd} do
    argument = "quoted ' value; $(touch must-not-exist)"
    script = ~S[printf '%s\n' "$1"; printf cwd-ok > child-cwd]

    {:ok, port} =
      Runner.open_stdio("/bin/sh", ["-c", script, "fixture", argument], cwd, %{}, 2_000)

    {frames, 0} = collect(port)
    assert stream(frames, ?O) == argument <> "\n"
    assert completion(frames)["exit_code"] == 0
    assert File.read!(Path.join(cwd, "child-cwd")) == "cwd-ok"
    refute File.exists?(Path.join(cwd, "must-not-exist"))
  end

  test "large binary output is relayed losslessly in bounded frames", %{cwd: cwd} do
    script = ~S[head -c 200000 /dev/zero; printf '\377' >&2]
    {:ok, port} = Runner.open_stdio("/bin/sh", ["-c", script], cwd, %{}, 2_000)
    {frames, 0} = collect(port)
    assert stream(frames, ?O) == :binary.copy(<<0>>, 200_000)
    assert stream(frames, ?S) == <<255>>
    assert Enum.all?(frames, fn {_kind, bytes} -> byte_size(bytes) <= 8192 end)
    assert completion(frames)["exit_code"] == 0
  end

  test "only defaults and explicitly selected environment reach the child", %{cwd: cwd} do
    key = "IPSE_STDIO_INHERITED_FIXTURE"
    previous = System.get_env(key)
    System.put_env(key, "not-authorized-for-server")

    on_exit(fn ->
      if previous, do: System.put_env(key, previous), else: System.delete_env(key)
    end)

    script =
      ~S[test -z "${IPSE_STDIO_INHERITED_FIXTURE+x}" || exit 11; test "$SELECTED_VALUE" = configured || exit 12; test "$PATH" = /usr/bin:/bin || exit 13; test -z "${HOME+x}" || exit 14; printf clean]

    {:ok, port} =
      Runner.open_stdio(
        "/bin/sh",
        ["-c", script],
        cwd,
        %{"SELECTED_VALUE" => "configured"},
        2_000
      )

    {frames, 0} = collect(port)
    assert stream(frames, ?O) == "clean"
    assert completion(frames)["exit_code"] == 0
  end

  test "lifetime timeout kills synchronized ordinary descendants", %{cwd: cwd} do
    script = "(printf ready; sleep 0.7; printf escaped > timed-out-child) & wait"
    {:ok, port} = Runner.open_stdio("/bin/sh", ["-c", script], cwd, %{}, 200)
    {frames, 0} = collect(port)
    assert stream(frames, ?O) == "ready"
    assert completion(frames)["timed_out"]
    Process.sleep(800)
    refute File.exists?(Path.join(cwd, "timed-out-child"))
  end

  test "a large selected environment flushes before the first protocol write", %{cwd: cwd} do
    script = ~S[test "${#PADDING}" -eq 120000 || exit 11; IFS= read -r line; printf '%s' "$line"]

    {:ok, port} =
      Runner.open_stdio(
        "/bin/sh",
        ["-c", script],
        cwd,
        %{"PADDING" => String.duplicate("x", 120_000)},
        3_000
      )

    assert :ok = Runner.send_stdio(port, "first message\n")
    {frames, 0} = collect(port)
    assert stream(frames, ?O) == "first message"
    assert completion(frames)["exit_code"] == 0
  end

  test "owner death terminates descendants even when child input relay is blocked", %{cwd: cwd} do
    parent = self()

    owner =
      spawn(fn ->
        script = "(printf ready; sleep 0.7; printf escaped > orphan-child) & wait"
        {:ok, port} = Runner.open_stdio("/bin/sh", ["-c", script], cwd, %{}, 5_000)
        wait_ready(port, parent)
        # Child never reads input. Less than the queue bound blocks its writer
        # without stopping the independent stdin owner-death watcher.
        assert :ok = Runner.send_stdio(port, String.duplicate("x", 262_144))
        send(parent, :input_sent)
        Process.sleep(:infinity)
      end)

    on_exit(fn -> if Process.alive?(owner), do: Process.exit(owner, :kill) end)
    assert_receive :ready, 3_000
    assert_receive :input_sent, 3_000
    Process.exit(owner, :kill)
    Process.sleep(850)
    refute File.exists?(Path.join(cwd, "orphan-child"))
  end

  test "input queue overload fails closed instead of blocking EOF detection", %{cwd: cwd} do
    Process.flag(:trap_exit, true)
    script = "(sleep 0.7; printf escaped > overloaded-child) & printf ready; wait"
    {:ok, port} = Runner.open_stdio("/bin/sh", ["-c", script], cwd, %{}, 5_000)
    assert_receive {^port, {:data, initial}}, 3_000
    parent = self()

    sender =
      spawn(fn ->
        result =
          try do
            payload = [<<?I, 1_048_576::32>>, String.duplicate("x", 1_048_576)]
            Port.command(port, [payload, payload, payload, payload])
          rescue
            ArgumentError -> :closed
          end

        send(parent, {:sender_finished, result})
      end)

    on_exit(fn -> if Process.alive?(sender), do: Process.exit(sender, :kill) end)
    started = System.monotonic_time(:millisecond)
    {frames, status} = collect(port, initial)
    assert System.monotonic_time(:millisecond) - started < 2_000

    case status do
      0 ->
        assert stream(frames, ?O) == "ready"
        assert stream(frames, ?E) == "stdio input queue exceeded limit"
        assert completion(frames)["exit_code"] != 0

      {:transport_exit, :epipe} ->
        # The Port driver can encounter EPIPE while its oversized write remains
        # queued after the helper closes input. This is a failed transport, not
        # successful completion or permission to retry the server's effects.
        assert initial =~ "ready"
    end

    assert_receive {:sender_finished, _}, 2_000
    Process.sleep(800)
    refute File.exists?(Path.join(cwd, "overloaded-child"))
  end

  test "initial server exit kills background children and drains bounded output", %{cwd: cwd} do
    effects =
      for iteration <- 1..20 do
        effect = "background-child-#{iteration}"
        script = ~S[(sleep 0.7; printf escaped > "$1") & printf done]

        {:ok, port} =
          Runner.open_stdio("/bin/sh", ["-c", script, "fixture", effect], cwd, %{}, 2_000)

        {frames, status} = collect(port)

        diagnostic =
          "iteration #{iteration}: helper status #{inspect(status)}, frames #{inspect(frames)}"

        assert status == 0, diagnostic
        assert stream(frames, ?O) == "done", diagnostic
        refute Enum.any?(frames, &(elem(&1, 0) == ?E)), diagnostic
        assert completion(frames) == %{"exit_code" => 0, "timed_out" => false}, diagnostic
        Path.join(cwd, effect)
      end

    Process.sleep(800)
    Enum.each(effects, fn effect -> refute File.exists?(effect) end)
  end

  test "invalid launch configuration is rejected without starting a process", %{cwd: cwd} do
    assert {:error, _} = Runner.open_stdio("/bin/sh", [17], cwd, %{}, 1_000)
    assert {:error, _} = Runner.open_stdio("/bin/sh", [], cwd, %{"BAD=KEY" => "value"}, 1_000)
    assert {:error, _} = Runner.open_stdio("/bin/sh", [], cwd, %{}, 0)
    assert {:error, _} = Runner.open_stdio("/bin/sh", [], cwd, %{}, 1_000, sandbox: :unknown)
  end

  test "passive completion still requires the actual helper exit status", %{cwd: cwd} do
    for {status, expected} <- [{0, :ok}, {2, {:error, "stdio cleanup unconfirmed"}}] do
      port =
        Port.open({:spawn_executable, ~c"/bin/sh"}, [
          :binary,
          :exit_status,
          args: ["-c", "exec 0<&-; printf finished; sleep 0.1; exit #{status}"]
        ])

      assert_receive {^port, {:data, "finished"}}, 2000
      assert Runner.close_stdio(port, :completed) == expected
    end

    {:ok, port} = Runner.open_stdio("/bin/sh", ["-c", "printf ready; sleep 5"], cwd, %{}, 5000)
    assert_receive {^port, {:data, _}}, 2000
    assert {:error, "stdio cleanup unconfirmed"} = Runner.close_stdio(port, :completed)
  end

  test "concurrent initial exits finish after cleaning up descendants", %{cwd: cwd} do
    effects =
      1..200
      |> Task.async_stream(
        fn iteration ->
          effect = "concurrent-child-#{iteration}"
          script = ~S[(sleep 0.7; printf escaped > "$1") & printf done]

          {:ok, port} =
            Runner.open_stdio("/bin/sh", ["-c", script, "fixture", effect], cwd, %{}, 2_000)

          {frames, status} = collect(port)
          diagnostic = "iteration #{iteration}: #{inspect({status, frames})}"
          assert status == 0, diagnostic
          assert stream(frames, ?O) == "done", diagnostic
          refute Enum.any?(frames, &(elem(&1, 0) == ?E)), diagnostic
          assert completion(frames) == %{"exit_code" => 0, "timed_out" => false}, diagnostic
          effect
        end,
        max_concurrency: 16,
        timeout: 5_000
      )
      |> Enum.map(fn {:ok, effect} -> effect end)

    Process.sleep(850)
    Enum.each(effects, fn effect -> refute File.exists?(Path.join(cwd, effect)) end)
  end

  @tag :macos_sandbox
  test "macOS detached stdio pipe holder fails the bounded drain without completion", %{cwd: cwd} do
    probe = Path.join(cwd, "probe")
    secret = Path.join(Path.dirname(cwd), "outside-fixture")
    File.write!(secret, "outside-sentinel")

    assert {_, 0} =
             System.cmd(
               "rustc",
               ["--edition=2021", "test/support/macos_native_probe.rs", "-o", probe],
               stderr_to_stdout: true
             )

    {:ok, port} = Runner.open_stdio(probe, ["detach", secret], cwd, %{}, 5_000, sandbox: :native)
    started = System.monotonic_time(:millisecond)

    try do
      {frames, status} = collect(port)
      assert status == 0
      assert stream(frames, ?E) == "stdio output did not drain"
      assert completion(frames) == nil
      assert System.monotonic_time(:millisecond) - started < 2_000
      assert File.exists?(Path.join(cwd, "detached-ready"))
      refute File.exists?(Path.join(cwd, "detached-confined"))
    after
      File.write!(Path.join(cwd, "release-detached"), "go")
      if Port.info(port), do: Port.close(port)
    end

    assert Enum.any?(1..100, fn _ ->
             if File.exists?(Path.join(cwd, "detached-confined")) do
               true
             else
               Process.sleep(10)
               false
             end
           end)

    assert File.read!(secret) == "outside-sentinel"
  end

  test "malformed launch environment never starts the executable", %{cwd: cwd} do
    helper = Application.app_dir(:ipse, "priv/ipse-runner")
    duplicate = <<2::32, 1::32, "A", 1::32, "x", 1::32, "A", 1::32, "y">>

    for bytes <- [<<?I, 0::32>>, <<?L, byte_size(duplicate)::32, duplicate::binary>>] do
      port =
        Port.open({:spawn_executable, String.to_charlist(helper)}, [
          :binary,
          :exit_status,
          args: ["--stdio", cwd, "1000", "/bin/sh", "-c", "printf escaped > malformed-launch"]
        ])

      assert Port.command(port, bytes)
      {frames, 1} = collect(port)
      assert stream(frames, ?E) == "invalid launch environment"
      refute File.exists?(Path.join(cwd, "malformed-launch"))
    end
  end

  for tag <- [:native_sandbox, :macos_sandbox] do
    @tag tag
    test "#{tag} stdio policy preserves direct arguments and child env while denying outside files",
         %{cwd: cwd} do
      workspace = Path.join(cwd, "workspace")
      File.mkdir!(workspace)
      secret = Path.join(cwd, "outside/.ssh/fake-private-key")
      File.mkdir_p!(Path.dirname(secret))
      File.write!(secret, "private-fixture")
      File.chmod!(secret, 0o600)
      File.ln_s!(secret, Path.join(workspace, "outside-link"))

      script =
        ~S[set -e; test "$SELECTED_FIXTURE" = child-only; test "${#PADDING}" -eq 120000; test "$HOME" != /fake-home; test "$TMPDIR" != /fake-temp; if cat "$1"; then exit 11; fi; if printf changed > "$1"; then exit 12; fi; if chmod 777 "$1"; then exit 13; fi; if cat outside-link; then exit 14; fi; printf writable > workspace-file; chmod 700 workspace-file; IFS= read -r line; printf '%s:%s' "$line" "$2"]

      argument = "literal; $(touch escaped)"

      {:ok, port} =
        Runner.open_stdio(
          "/bin/sh",
          ["-c", script, "fixture", secret, argument],
          workspace,
          %{
            "SELECTED_FIXTURE" => "child-only",
            "PADDING" => String.duplicate("x", 120_000),
            "HOME" => "/fake-home",
            "TMPDIR" => "/fake-temp"
          },
          5_000,
          sandbox: :native
        )

      assert :ok = Runner.send_stdio(port, "hello\n")
      {frames, 0} = collect(port)
      assert completion(frames)["exit_code"] == 0
      assert stream(frames, ?O) == "hello:" <> argument
      assert File.read!(secret) == "private-fixture"
      assert Bitwise.band(File.stat!(secret).mode, 0o777) == 0o600
      assert File.read!(Path.join(workspace, "workspace-file")) == "writable"
      refute File.exists?(Path.join(workspace, "escaped"))
    end
  end

  @tag :native_sandbox
  test "native namespace worker reports exec failure without completion or a stuck spawn", %{
    cwd: cwd
  } do
    broken = Path.join(cwd, "missing-interpreter")
    File.write!(broken, "#!/no/such/fixture-interpreter\n")
    File.chmod!(broken, 0o700)

    for executable <- [Path.join(cwd, "missing-server"), broken] do
      {:ok, port} = Runner.open_stdio(executable, [], cwd, %{}, 2000, sandbox: :native)
      {frames, 1} = collect(port)
      assert stream(frames, ?E) == "cannot start stdio server"
      refute Enum.any?(frames, fn {kind, _} -> kind == ?X end)
    end
  end

  @tag :native_sandbox
  test "selected loader environment cannot execute in the unsandboxed supervisor", %{cwd: cwd} do
    workspace = Path.join(cwd, "workspace")
    File.mkdir!(workspace)
    outside = Path.join(cwd, "loader-escaped")

    File.write!(Path.join(workspace, "loader.c"), ~S"""
    #include <fcntl.h>
    #include <stdlib.h>
    #include <unistd.h>
    __attribute__((constructor)) static void fixture(void) {
      int fd=open(getenv("FIXTURE_OUTSIDE"),O_WRONLY|O_CREAT,0600);
      if(fd>=0){write(fd,"escaped",7);close(fd);}
    }
    """)

    assert {:ok, %{exit_code: 0}} =
             Runner.run("/usr/bin/cc -shared -fPIC loader.c -o loader.so", workspace,
               sandbox: :native
             )

    inside = Path.join(workspace, "loader-positive-control")

    {:ok, control} =
      Runner.open_stdio(
        "/bin/sh",
        ["-c", "true"],
        workspace,
        %{"LD_PRELOAD" => Path.join(workspace, "loader.so"), "FIXTURE_OUTSIDE" => inside},
        5_000,
        sandbox: :native
      )

    {control_frames, 0} = collect(control)
    assert completion(control_frames)["exit_code"] == 0
    assert File.read!(inside) == "escaped"

    {:ok, port} =
      Runner.open_stdio(
        "/bin/sh",
        ["-c", "printf confined"],
        workspace,
        %{"LD_PRELOAD" => Path.join(workspace, "loader.so"), "FIXTURE_OUTSIDE" => outside},
        5_000,
        sandbox: :native
      )

    {frames, 0} = collect(port)
    assert completion(frames)["exit_code"] == 0
    assert stream(frames, ?O) == "confined"
    refute File.exists?(outside)
  end

  @tag :macos_sandbox
  test "macOS selected loader environment reaches only the sandboxed direct executable", %{
    cwd: cwd
  } do
    workspace = Path.join(cwd, "workspace")
    File.mkdir!(workspace)
    source = Path.join(workspace, "loader.c")
    library = Path.join(workspace, "loader.dylib")
    executable = Path.join(workspace, "server")

    File.write!(source, ~S"""
    #include <fcntl.h>
    #include <stdlib.h>
    #include <unistd.h>
    __attribute__((constructor)) static void fixture(void) {
      int fd=open(getenv("FIXTURE_OUTSIDE"),O_WRONLY|O_CREAT,0600);
      if(fd>=0){write(fd,"fixture",7);close(fd);}
    }
    """)

    File.write!(
      Path.join(workspace, "server.c"),
      "#include <stdio.h>\nint main(void){puts(\"confined\");return 0;}\n"
    )

    assert {_, 0} =
             System.cmd("/usr/bin/clang", ["-dynamiclib", source, "-o", library],
               stderr_to_stdout: true
             )

    assert {_, 0} =
             System.cmd("/usr/bin/clang", [Path.join(workspace, "server.c"), "-o", executable],
               stderr_to_stdout: true
             )

    inside = Path.join(workspace, "loader-positive-control")

    {:ok, control} =
      Runner.open_stdio(
        executable,
        [],
        workspace,
        %{"DYLD_INSERT_LIBRARIES" => library, "FIXTURE_OUTSIDE" => inside},
        5_000,
        sandbox: :native
      )

    {control_frames, 0} = collect(control)
    assert completion(control_frames)["exit_code"] == 0
    assert File.read!(inside) == "fixture"
    outside = Path.join(cwd, "loader-escaped")

    {:ok, port} =
      Runner.open_stdio(
        executable,
        [],
        workspace,
        %{"DYLD_INSERT_LIBRARIES" => library, "FIXTURE_OUTSIDE" => outside},
        5_000,
        sandbox: :native
      )

    {frames, 0} = collect(port)
    assert completion(frames)["exit_code"] == 0
    assert stream(frames, ?O) == "confined\n"
    refute File.exists?(outside)
  end

  for tag <- [:native_sandbox, :macos_sandbox] do
    @tag tag
    test "#{tag} cancellation during setup cannot leave deferred server effects", %{cwd: cwd} do
      {:ok, port} =
        Runner.open_stdio(
          "/bin/sh",
          ["-c", "IFS= read -r line && printf escaped > setup-effect"],
          cwd,
          %{},
          5_000,
          sandbox: :native
        )

      assert :ok = Runner.close_stdio(port)
      assert Port.info(port) == nil
      refute File.exists?(Path.join(cwd, "setup-effect"))
    end

    @tag tag
    test "#{tag} owner death and confirmed cancellation stop ordinary stdio descendants", %{
      cwd: cwd
    } do
      script = "(printf ready; sleep 0.7; printf escaped > owned-child) & wait"
      parent = self()

      owner =
        spawn(fn ->
          {:ok, port} =
            Runner.open_stdio("/bin/sh", ["-c", script], cwd, %{}, 5_000, sandbox: :native)

          wait_ready(port, parent)

          receive do
            :finish -> :ok
          end
        end)

      on_exit(fn -> if Process.alive?(owner), do: Process.exit(owner, :kill) end)
      assert_receive :ready, 30_000
      Process.exit(owner, :kill)
      Process.sleep(850)
      refute File.exists?(Path.join(cwd, "owned-child"))

      {:ok, port} =
        Runner.open_stdio("/bin/sh", ["-c", script], cwd, %{}, 5_000, sandbox: :native)

      wait_ready(port, self())
      assert_receive :ready
      assert :ok = Runner.close_stdio(port)
      Process.sleep(850)
      refute File.exists?(Path.join(cwd, "owned-child"))
    end
  end

  @tag :native_sandbox
  test "native stdio denies networking and process-group escape and confirms descendant cleanup",
       %{cwd: cwd} do
    File.write!(Path.join(cwd, "probe.rs"), ~S"""
    extern "C" {fn setpgid(pid:i32,group:i32)->i32;}
    fn main(){
      assert_eq!(std::net::TcpStream::connect("127.0.0.1:9").unwrap_err().raw_os_error(),Some(1));
      assert_eq!(unsafe{setpgid(0,0)},-1);
      assert_eq!(std::io::Error::last_os_error().raw_os_error(),Some(1));
      println!("confined");
    }
    """)

    assert {:ok, %{exit_code: 0}} =
             Runner.run("/usr/bin/rustc --edition=2021 probe.rs -o probe", cwd, sandbox: :native)

    {:ok, probe} =
      Runner.open_stdio(Path.join(cwd, "probe"), [], cwd, %{}, 5_000, sandbox: :native)

    {frames, 0} = collect(probe)
    assert completion(frames)["exit_code"] == 0
    assert stream(frames, ?O) == "confined\n"

    {:ok, port} =
      Runner.open_stdio(
        "/bin/sh",
        ["-c", "(printf ready; sleep 0.7; printf escaped > native-closed-child) & wait"],
        cwd,
        %{},
        5_000,
        sandbox: :native
      )

    assert_receive {^port, {:data, bytes}}, 3_000
    assert bytes =~ "ready"
    assert :ok = Runner.close_stdio(port)
    Process.sleep(800)
    refute File.exists?(Path.join(cwd, "native-closed-child"))
  end

  test "confirmed cancellation waits for supervisor exit and stops ordinary descendants", %{
    cwd: cwd
  } do
    script = "(printf ready; sleep 0.7; printf escaped > closed-child) & wait"
    {:ok, port} = Runner.open_stdio("/bin/sh", ["-c", script], cwd, %{}, 5_000)
    assert_receive {^port, {:data, bytes}}, 3_000
    assert bytes =~ "ready"
    assert :ok = Runner.send_stdio(port, String.duplicate("x", 262_144))
    assert :ok = Runner.close_stdio(port)
    assert Port.info(port) == nil
    Process.sleep(800)
    refute File.exists?(Path.join(cwd, "closed-child"))
    assert {:error, "stdio cleanup unconfirmed"} = Runner.close_stdio(port)
  end

  test "oversized input is rejected and a closed transport cannot receive replay", %{cwd: cwd} do
    script = "printf ready; sleep 5"
    {:ok, port} = Runner.open_stdio("/bin/sh", ["-c", script], cwd, %{}, 5_000)
    assert_receive {^port, {:data, _}}, 3_000

    assert {:error, "invalid or oversized stdio input"} =
             Runner.send_stdio(port, String.duplicate("x", 1_048_577))

    assert :ok = Runner.close_stdio(port)
    assert {:error, "stdio transport is closed"} = Runner.send_stdio(port, "no replay")
  end

  defp wait_ready(port, parent, pending \\ "") do
    receive do
      {^port, {:data, data}} ->
        text = pending <> data

        if String.contains?(text, "ready"),
          do: send(parent, :ready),
          else: wait_ready(port, parent, text)
    after
      30_000 -> raise "stdio fixture did not become ready"
    end
  end

  defp collect(port, initial \\ <<>>, deadline \\ System.monotonic_time(:millisecond) + 30_000) do
    receive do
      {^port, {:data, bytes}} -> collect(port, initial <> bytes, deadline)
      {^port, {:exit_status, status}} -> {decode(initial, []), status}
      {:EXIT, ^port, reason} -> {[], {:transport_exit, reason}}
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        Port.close(port)
        flunk("stdio helper did not finish")
    end
  end

  defp decode(<<>>, acc), do: Enum.reverse(acc)

  defp decode(<<kind, size::unsigned-big-32, bytes::binary-size(size), tail::binary>>, acc)
       when size <= 1_048_576,
       do: decode(tail, [{kind, bytes} | acc])

  defp decode(_, _), do: flunk("malformed or oversized stdio helper frame")

  defp stream(frames, kind),
    do: frames |> Enum.filter(&(elem(&1, 0) == kind)) |> Enum.map_join(&elem(&1, 1))

  defp completion(frames),
    do: frames |> Enum.find_value(fn {kind, bytes} -> if kind == ?X, do: Jason.decode!(bytes) end)
end
