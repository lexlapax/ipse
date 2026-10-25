defmodule Ipse.LinuxSandboxTest do
  use ExUnit.Case, async: false
  alias Ipse.Runner

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-linux-probe-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    source = Path.join(root, "probe.rs")
    probe = Path.join(root, "probe")
    File.write!(source, probe_source())
    %{probe_source: source, probe: probe}
  end

  setup ctx do
    root =
      Path.join(System.tmp_dir!(), "ipse-linux-sandbox-#{System.unique_integer([:positive])}")

    cwd = Path.join(root, "workspace")
    File.mkdir_p!(cwd)
    on_exit(fn -> File.rm_rf!(root) end)

    if ctx[:native_sandbox] do
      assert {:ok, %{exit_code: 0}} = Runner.run("true", cwd, sandbox: :native)

      unless File.regular?(ctx.probe) do
        rustc =
          System.find_executable("rustc") ||
            flunk("native enforcement probes require the documented Rust build toolchain")

        assert {_, 0} =
                 System.cmd(rustc, ["--edition=2021", ctx.probe_source, "-o", ctx.probe],
                   stderr_to_stdout: true
                 )
      end

      File.cp!(ctx.probe, Path.join(cwd, "probe"))
    end

    %{root: root, cwd: cwd}
  end

  test "protected workspace refusal names only the overlapping category", ctx do
    home = Path.join(ctx.root, "private-account")
    state = Path.join(ctx.root, "private-state")
    previous = Map.new(["HOME", "IPSE_HOME"], &{&1, System.get_env(&1)})
    System.put_env("HOME", home)
    System.put_env("IPSE_HOME", state)

    on_exit(fn ->
      for {key, value} <- previous do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    for {path, category} <- [
          {Path.join(home, ".ssh"), ".ssh credentials/state"},
          {Path.join(home, ".ipse"), ".ipse credentials/state"},
          {state, "IPSE_HOME state"}
        ] do
      File.mkdir_p!(path)
      assert {:error, reason} = Ipse.Tools.Sandbox.resolve(:native, path)
      assert reason =~ category
      refute reason =~ home
      refute reason =~ state
      assert Ipse.CLI.Errors.format(reason) =~ category
    end
  end

  test "native capability either executes explicitly or fails closed without effects", %{cwd: cwd} do
    previous = System.get_env("IPSE_HOME")
    home = Path.join(Path.dirname(cwd), "state")
    File.mkdir!(home)
    File.chmod!(home, 0o700)
    System.put_env("IPSE_HOME", home)

    on_exit(fn ->
      if previous, do: System.put_env("IPSE_HOME", previous), else: System.delete_env("IPSE_HOME")
    end)

    marker = Path.join(cwd, "capability-marker")

    case Runner.run("printf explicit > capability-marker", cwd, sandbox: :native) do
      {:ok, result} ->
        assert result.exit_code == 0
        assert File.read!(marker) == "explicit"

      {:error, reason} ->
        assert is_binary(reason) and reason != ""
        refute File.exists?(marker)
        IO.puts("Native sandbox unavailable; enforcement was not exercised: #{reason}")
    end
  end

  @tag :native_sandbox
  test "Bash descriptor paths support nested reads and writes without exposing procfs", ctx do
    File.write!(Path.join(ctx.cwd, "input.txt"), "workspace descriptor\n")

    File.write!(Path.join(ctx.cwd, "descriptors.sh"), ~S"""
    set -euo pipefail
    test ! -e /proc
    mapfile -t rows < <(printf 'one\ntwo\n')
    test "${#rows[@]}" -eq 2
    cmp <(printf same) <(printf same)
    printf 'substitution output\n' > >(cat > output.txt)
    wait
    grep -qx 'substitution output' output.txt
    bash -ec 'mapfile -t rows < <(printf grandchild); test "${rows[0]}" = grandchild'
    exec 7< input.txt
    grep -qx 'workspace descriptor' /dev/fd/7
    exec 8> writable.txt
    printf 'descriptor write\n' > /dev/fd/8
    grep -qx 'descriptor write' writable.txt
    printf 'stdin descriptor\n' | grep -qx 'stdin descriptor' /dev/stdin
    if ls /dev/.ipse-proc; then exit 11; fi
    if cat /dev/.ipse-proc/self/environ; then exit 12; fi
    if cat /dev/.ipse-proc/1/status; then exit 13; fi
    test ! -e /dev/.ipse-proc/sys
    printf 'Bash descriptors work; procfs data denied\n'
    """)

    assert {:ok, result} = Runner.run("bash descriptors.sh", ctx.cwd, sandbox: :native)
    assert result.exit_code == 0
    assert result.output =~ "Bash descriptors work; procfs data denied"
    assert File.read!(Path.join(ctx.cwd, "output.txt")) == "substitution output\n"
    assert File.read!(Path.join(ctx.cwd, "writable.txt")) == "descriptor write\n"
  end

  @tag :native_sandbox
  test "outside fake credentials and symlink targets cannot be read, overwritten, or chmodded",
       ctx do
    secret_dir = Path.join(ctx.root, "outside/.ssh")
    File.mkdir_p!(secret_dir)
    secret = Path.join(secret_dir, "fixture-key")
    File.write!(secret, "fixture-private-value")
    File.chmod!(secret, 0o600)
    File.ln_s!(secret, Path.join(ctx.cwd, "credential-link"))

    command =
      "set -e; " <>
        "if cat #{quote_shell(secret)}; then exit 11; fi; " <>
        "if printf changed > #{quote_shell(secret)}; then exit 12; fi; " <>
        "if chmod 777 #{quote_shell(secret)}; then exit 13; fi; " <>
        "if cat credential-link; then exit 14; fi; " <>
        "if printf changed > credential-link; then exit 15; fi; " <>
        "if chmod 777 credential-link; then exit 16; fi; printf confined"

    assert {:ok, result} = Runner.run(command, ctx.cwd, sandbox: :native)
    assert result.exit_code == 0
    assert result.output =~ "confined"
    refute result.output =~ "fixture-private-value"
    assert File.read!(secret) == "fixture-private-value"
    assert Bitwise.band(File.stat!(secret).mode, 0o777) == 0o600
  end

  @tag :native_sandbox
  test "system metadata is read-only while workspace chmod and Elixir compilation work", %{
    cwd: cwd
  } do
    key = "IPSE_NATIVE_TEST_SECRET"
    previous = System.get_env(key)
    System.put_env(key, "fixture-must-not-reach-child")

    on_exit(fn ->
      if previous, do: System.put_env(key, previous), else: System.delete_env(key)
    end)

    File.write!(
      Path.join(cwd, "compile.ex"),
      "defmodule NativeSandboxFixture do\n def answer, do: 42\nend\n"
    )

    assert {:ok, result} =
             Runner.run(
               ~S[set -e; test -z "${IPSE_NATIVE_TEST_SECRET+x}"; printf workspace > writable; chmod 700 writable; if chmod 777 /usr/bin/sh; then exit 12; fi; test ! -e /proc; export ERL_FLAGS='+S 2'; elixirc compile.ex; test -s Elixir.NativeSandboxFixture.beam; printf compiled],
               cwd,
               sandbox: :native,
               timeout_ms: 20_000
             )

    assert result.exit_code == 0
    assert result.output =~ "Read-only file system"
    assert result.output =~ "compiled"
    assert Bitwise.band(File.stat!(Path.join(cwd, "writable")).mode, 0o777) == 0o700
    assert File.regular?(Path.join(cwd, "Elixir.NativeSandboxFixture.beam"))
  end

  @tag :native_sandbox
  test "Rust compilation and subprocess fallback work with only private connected socket pairs",
       ctx do
    File.cp!(ctx.probe_source, Path.join(ctx.cwd, "compile.rs"))

    assert {:ok, result} =
             Runner.run(
               "/usr/bin/rustc --edition=2021 compile.rs -o compiled-probe && ./compiled-probe spawn",
               ctx.cwd,
               sandbox: :native,
               timeout_ms: 20_000
             )

    assert result.exit_code == 0
    assert result.output == "private pairs and subprocesses work; external sockets denied\n"
  end

  @tag :native_sandbox
  test "network positive control connects but a sandboxed Rust TCP probe gets EPERM", ctx do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    on_exit(fn -> :gen_tcp.close(listener) end)
    {:ok, port} = :inet.port(listener)

    assert {"network allowed\n", 0} =
             System.cmd(ctx.probe, ["network", Integer.to_string(port), "allow"])

    assert {:ok, connection} = :gen_tcp.accept(listener, 2_000)
    :gen_tcp.close(connection)
    assert {:ok, result} = Runner.run("./probe network #{port} deny", ctx.cwd, sandbox: :native)
    assert result.exit_code == 0
    assert result.output == "network denied\n"
    assert {:error, :timeout} = :gen_tcp.accept(listener, 100)
  end

  @tag :native_sandbox
  test "host signals, SysV IPC, pidfds and process-group escape are denied while threads work",
       ctx do
    host_pid = System.pid()

    assert {:ok, result} =
             Runner.run("./probe isolation #{String.trim(host_pid)}", ctx.cwd, sandbox: :native)

    assert result.exit_code == 0
    assert result.output == "isolation denied; threads work\n"
  end

  @tag :native_sandbox
  test "user code retains ordinary signal and exit semantics inside its PID namespace", ctx do
    assert {:ok, result} = Runner.run("./probe signal-self", ctx.cwd, sandbox: :native)
    assert result.exit_code == 143
    assert result.output == ""
    assert {:ok, result} = Runner.run("exit 37", ctx.cwd, sandbox: :native)
    assert result.exit_code == 37
    refute result.timed_out
  end

  @tag :native_sandbox
  test "private descriptor view cannot reopen a live host process's anonymous pipe", ctx do
    port =
      Port.open({:spawn_executable, String.to_charlist(ctx.probe)}, [
        :binary,
        :exit_status,
        args: ["host-pipe"]
      ])

    on_exit(fn -> if Port.info(port), do: Port.close(port) end)
    [pid, fd] = port_line(port) |> String.trim() |> String.split(" ")

    assert {:ok, result} =
             Runner.run("./probe host-pipe-attack #{pid} #{fd}", ctx.cwd, sandbox: :native)

    assert result.exit_code == 0
    assert result.output == "host pipe is outside the descriptor namespace\n"
    assert Port.command(port, "check")
    assert port_line(port) == "host pipe unchanged\n"
    assert_receive {^port, {:exit_status, 0}}, 2000
  end

  @tag :native_sandbox
  test "a disposable host child's resource limits cannot be changed through prlimit64", ctx do
    port =
      Port.open({:spawn_executable, String.to_charlist(ctx.probe)}, [
        :binary,
        :exit_status,
        args: ["host-limit"]
      ])

    on_exit(fn -> if Port.info(port), do: Port.close(port) end)
    [pid, soft, hard] = port_line(port) |> String.trim() |> String.split(" ")
    expected = "#{soft} #{hard}\n"
    assert {^expected, 0} = System.cmd(ctx.probe, ["host-limit-query", pid])

    assert {:ok, result} =
             Runner.run("./probe host-limit-attack #{pid}", ctx.cwd, sandbox: :native)

    assert result.exit_code == 0
    assert result.output == "host process mutation denied; self limits work\n"
    assert Port.command(port, "check")
    assert String.trim(port_line(port)) == "#{soft} #{hard}"
    assert_receive {^port, {:exit_status, 0}}, 2_000
  end

  @tag :native_sandbox
  test "timeout kills synchronized descendants before their delayed write", %{cwd: cwd} do
    owner = self()

    assert {:ok, result} =
             Runner.run(
               "(printf child-started; sleep 0.7; printf escaped > timeout-effect) & wait",
               cwd,
               sandbox: :native,
               timeout_ms: 200,
               emit: fn event -> send(owner, event) end
             )

    assert_receive {:tool_output, "child-started"}, 2_000
    assert result.timed_out
    Process.sleep(800)
    refute File.exists?(Path.join(cwd, "timeout-effect"))
  end

  @tag :native_sandbox
  test "owner death kills synchronized descendants before their delayed write", %{cwd: cwd} do
    parent = self()

    owner =
      spawn(fn ->
        Runner.run("(printf child-started; sleep 0.7; printf escaped > owner-effect) & wait", cwd,
          sandbox: :native,
          emit: fn event -> send(parent, event) end
        )
      end)

    on_exit(fn -> if Process.alive?(owner), do: Process.exit(owner, :kill) end)
    assert_receive {:tool_output, "child-started"}, 5_000
    Process.exit(owner, :kill)
    Process.sleep(850)
    refute File.exists?(Path.join(cwd, "owner-effect"))
  end

  defp quote_shell(text), do: "'" <> String.replace(text, "'", "'\\''") <> "'"

  defp port_line(port, pending \\ "") do
    receive do
      {^port, {:data, bytes}} ->
        text = pending <> bytes
        if String.ends_with?(text, "\n"), do: text, else: port_line(port, text)

      {^port, {:exit_status, code}} ->
        flunk("resource-limit host probe exited early: #{code}")
    after
      3_000 -> flunk("resource-limit host probe did not respond")
    end
  end

  defp probe_source do
    ~S"""
    use std::net::TcpStream;
    use std::io::{Read,Write};
    #[repr(C)] #[derive(Default)] struct Limit {soft:u64,hard:u64}
    extern "C" { fn kill(pid:i32, signal:i32)->i32; fn syscall(n:i64,...)->i64; fn socketpair(domain:i32,kind:i32,protocol:i32,pair:*mut i32)->i32; fn socket(domain:i32,kind:i32,protocol:i32)->i32; fn close(fd:i32)->i32; fn pipe2(pair:*mut i32,flags:i32)->i32; fn read(fd:i32,buffer:*mut std::ffi::c_void,size:usize)->isize; }
    #[cfg(target_arch="x86_64")] const PRLIMIT:i64=302;
    #[cfg(target_arch="aarch64")] const PRLIMIT:i64=261;
    fn limits(pid:i32)->Limit {let mut out=Limit::default(); assert_eq!(unsafe{syscall(PRLIMIT,pid,7,0usize,&mut out as *mut Limit)},0);out}
    fn denied(result:i64) { assert_eq!(result,-1); assert_eq!(std::io::Error::last_os_error().raw_os_error(),Some(1)); }
    fn main() {
      let args:Vec<String>=std::env::args().collect();
      if args[1]=="spawn" {
        use std::os::unix::process::CommandExt;
        for kind in [1,5] {let mut pair=[-1;2];assert_eq!(unsafe{socketpair(1,kind,0,pair.as_mut_ptr())},0);for fd in pair {unsafe{close(fd);}}}
        let mut pair=[-1;2];denied(unsafe{socketpair(1,2,0,pair.as_mut_ptr())} as i64);
        denied(unsafe{socketpair(2,1,0,pair.as_mut_ptr())} as i64);
        for domain in [1,2,10] {denied(unsafe{socket(domain,1,0)} as i64);}
        let mut command=std::process::Command::new("/usr/bin/rustc");command.arg("--version");
        unsafe{command.pre_exec(||Ok(()));}
        assert!(command.output().unwrap().status.success());
        println!("private pairs and subprocesses work; external sockets denied");
      } else if args[1]=="network" {
        let result=TcpStream::connect(format!("127.0.0.1:{}",args[2]));
        if args[3]=="allow" {result.unwrap(); println!("network allowed");}
        else {assert_eq!(result.unwrap_err().raw_os_error(),Some(1)); println!("network denied");}
      } else if args[1]=="signal-self" {
        assert!(std::process::id()>1);
        unsafe{kill(std::process::id() as i32,15);}
        panic!("default SIGTERM did not stop the command");
      } else if args[1]=="host-pipe" {
        let mut pair=[-1;2]; assert_eq!(unsafe{pipe2(pair.as_mut_ptr(),0x80000|0x800)},0);
        println!("{} {}",std::process::id(),pair[1]); std::io::stdout().flush().unwrap();
        let mut one=[0u8;1]; std::io::stdin().read_exact(&mut one).unwrap();
        assert_eq!(unsafe{read(pair[0],one.as_mut_ptr().cast(),1)},-1);
        assert_eq!(std::io::Error::last_os_error().raw_os_error(),Some(11));
        println!("host pipe unchanged");
      } else if args[1]=="host-pipe-attack" {
        let path=format!("/dev/.ipse-proc/{}/fd/{}",args[2],args[3]);
        let attempt=std::fs::OpenOptions::new().write(true).open(path);
        assert_eq!(attempt.unwrap_err().raw_os_error(),Some(2));
        println!("host pipe is outside the descriptor namespace");
      } else if args[1]=="host-limit" {
        let before=limits(0); println!("{} {} {}",std::process::id(),before.soft,before.hard); std::io::stdout().flush().unwrap();
        let mut one=[0u8;1];std::io::stdin().read_exact(&mut one).unwrap();
        let after=limits(0);println!("{} {}",after.soft,after.hard);
      } else if args[1]=="host-limit-query" {
        let value=limits(args[2].parse().unwrap());println!("{} {}",value.soft,value.hard);
      } else if args[1]=="host-limit-attack" {
        let pid:i32=args[2].parse().unwrap();let own=limits(0);
        let attempt=Limit {soft:1,hard:own.hard};
        denied(unsafe{syscall(PRLIMIT,pid,7,&attempt as *const Limit,0usize)});
        denied(unsafe{syscall(PRLIMIT,pid,7,0usize,0usize)});
        #[cfg(target_arch="x86_64")] let mutation=[141,142,144,203,251,314,256,279,440,448];
        #[cfg(target_arch="aarch64")] let mutation=[140,118,119,122,30,274,238,239,440,448];
        for nr in mutation {denied(unsafe{syscall(nr,pid,0usize,0usize,0usize,0usize,0usize)});}
        assert_eq!(limits(0).soft,own.soft);
        println!("host process mutation denied; self limits work");
      } else {
        let pid:i32=args[2].parse().unwrap();
        // Ancestor-namespace host PIDs are not visible in the private namespace.
        assert_eq!(unsafe{kill(pid,0)},-1);
        assert_eq!(std::io::Error::last_os_error().raw_os_error(),Some(3));
        denied(unsafe{syscall(434,pid,0)});
        #[cfg(target_arch="x86_64")] let (shm,setsid,setpgid)=(29,112,109);
        #[cfg(target_arch="aarch64")] let (shm,setsid,setpgid)=(194,157,154);
        denied(unsafe{syscall(shm,0,0,0)});
        denied(unsafe{syscall(setsid)});
        denied(unsafe{syscall(setpgid,0,0)});
        std::thread::spawn(|| 42).join().unwrap();
        println!("isolation denied; threads work");
      }
    }
    """
  end
end
