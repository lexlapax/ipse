# macOS-only App Sandbox enforcement probe. Run on macOS after building ipse-runner:
#   elixir dev/verify-macos-sandbox.exs /path/to/ipse-runner /path/to/workspace
# This signs a temporary ad-hoc helper app, runs real filesystem/network probes,
# and removes its temporary bundle and files. macOS retains the generated app
# container under ~/Library/Containers. It makes no repository changes.
# Add --process-boundary to check descendant cleanup. Known group escapes cause
# a nonzero exit; the default file/network probe does not establish containment.

defmodule Ipse.Development.Platform.MacSandboxProbe do
  @codesign "/usr/bin/codesign"

  def main([helper, workspace_arg]) do
    main([helper, workspace_arg], false)
  end

  def main([helper, workspace_arg, "--process-boundary"]) do
    main([helper, workspace_arg], true)
  end

  def main(_) do
    raise "usage: elixir dev/verify-macos-sandbox.exs /path/to/ipse-runner /workspace [--process-boundary]"
  end

  defp main([helper, workspace_arg], process_checks) do
    require_macos!()
    require_tool!(@codesign)

    rustc =
      System.find_executable("rustc") ||
        raise "rustc is required for the standard-library network probe"

    helper = canonical_file!(helper)
    workspace = canonical_dir!(workspace_arg)
    run!(helper, workspace, rustc, process_checks)
  end

  defp run!(helper, workspace, rustc, process_checks) do
    id = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    root_lexical = Path.join(System.tmp_dir!(), "ipse-macos-sandbox-#{id}")
    File.mkdir_p!(root_lexical)
    script = Path.join(workspace, ".ipse-macos-sandbox-probe-#{id}.sh")
    symlink_read = Path.join(workspace, ".ipse-macos-sandbox-link-#{id}")
    network_source = Path.join(workspace, ".ipse-network-probe-#{id}.rs")
    network_probe = Path.join(workspace, ".ipse-network-probe-#{id}")
    workspace_write = Path.join(workspace, "sandbox-write-#{id}")

    try do
      root = canonical_dir!(root_lexical)

      if String.starts_with?(root, workspace) do
        raise "choose a workspace that does not contain the probe temp directory"
      end

      cache = Path.join(root, "cache")
      app = Path.join(cache, "IpseRunner.app")
      contents = Path.join(app, "Contents")
      executable = Path.join([contents, "MacOS", "ipse-runner"])
      allowed_tmp = Path.join(cache, "tmp")
      outside = Path.join(root, "outside")
      outside_secret = Path.join(outside, "fake-credential")
      outside_write = Path.join(outside, "should-not-write")

      File.mkdir_p!(Path.dirname(executable))
      File.mkdir_p!(allowed_tmp)
      File.mkdir_p!(outside)
      File.write!(outside_secret, "fake-credential-sentinel\n")
      File.write!(outside_write, "outside-sentinel\n")
      File.chmod!(outside_secret, 0o644)
      File.chmod!(outside_write, 0o644)
      :ok = File.ln_s(outside_secret, symlink_read)
      File.write!(network_source, network_probe_source())

      compile_args = [
        "--edition=2021",
        "--crate-name",
        "ipse_network_probe",
        network_source,
        "-o",
        network_probe
      ]

      {_compile_output, 0} = System.cmd(rustc, compile_args, stderr_to_stdout: true)

      File.chmod!(network_probe, 0o700)
      File.cp!(helper, executable)
      File.chmod!(executable, 0o755)

      info = info_plist("org.ipse.sandbox.#{id}")
      entitlements = entitlements([workspace, allowed_tmp])
      File.write!(Path.join(contents, "Info.plist"), info)
      entitlements_path = Path.join(cache, "ipse.entitlements.plist")
      File.write!(entitlements_path, entitlements)

      # Sign only with the explicitly approved Apple command and an ad-hoc
      # signature. No personal certificate or identity lookup is used.
      run_command!(@codesign, [
        "--force",
        "--sign",
        "-",
        "--entitlements",
        entitlements_path,
        "--timestamp=none",
        app
      ])

      run_command!(@codesign, ["--verify", "--strict", "--verbose=2", app])

      {display, 0} =
        System.cmd(@codesign, ["-d", "--entitlements", ":-", app], stderr_to_stdout: true)

      require_contains!(display, "com.apple.security.app-sandbox")
      require_contains!(display, "<true/>")
      require_contains!(display, "temporary-exception.files.absolute-path.read-write")

      unless String.contains?(display, "com.apple.security.network.client") or
               String.contains?(display, "com.apple.security.network.server") do
        :ok
      else
        raise "signed helper unexpectedly grants a network entitlement"
      end

      # Establish a loopback endpoint and prove the compiled Rust client can
      # reach it outside the sandbox before checking that the same child fails.
      {listener, port, server_task} = loopback_server!()

      try do
        {"ready\n", 0} = System.cmd(network_probe, ["--self-test"])
        {"connected\n", 0} = System.cmd(network_probe, ["127.0.0.1", Integer.to_string(port)])

        outside_read_check =
          "cat #{shell_quote(outside_secret)} >/dev/null 2>&1 && exit 31; test $? -ne 0"

        outside_write_check =
          "printf x > #{shell_quote(outside_write)} 2>/dev/null && exit 32; test $? -ne 0"

        symlink_read_check =
          "cat #{shell_quote(symlink_read)} >/dev/null 2>&1 && exit 34; test $? -ne 0"

        outside_chmod_check =
          "chmod 600 #{shell_quote(outside_secret)} 2>/dev/null && exit 35; test $? -ne 0"

        workspace_write_check = "printf workspace-ok > #{shell_quote(workspace_write)}"
        workspace_chmod_check = "chmod 600 #{shell_quote(workspace_write)}"
        tmp_write_check = "printf tmp-ok > #{shell_quote(Path.join(allowed_tmp, "probe-write"))}"
        network_self_test = "#{shell_quote(network_probe)} --self-test"

        network_denial_check =
          "#{shell_quote(network_probe)} --expect-denied 127.0.0.1 #{port}"

        nested_commands = [
          outside_read_check,
          outside_write_check,
          symlink_read_check,
          outside_chmod_check,
          workspace_write_check,
          workspace_chmod_check,
          tmp_write_check,
          network_self_test,
          network_denial_check
        ]

        nested_shells =
          Enum.map(nested_commands, fn inner -> "/bin/sh -c #{shell_quote(inner)}" end)

        script_text = """
        set -eu
        # These tests run in the helper's shell child, then again in a nested
        # shell child, proving that the process tree remains constrained.
        #{Enum.join(nested_shells, "\n")}
        test "$(cat #{shell_quote(workspace_write)})" = workspace-ok
        test "$(cat #{shell_quote(Path.join(allowed_tmp, "probe-write"))})" = tmp-ok
        exit 0
        """

        File.write!(script, script_text)
        File.chmod!(script, 0o600)
        command = "/bin/sh #{shell_quote(script)}"
        {raw, status} = run_helper!(executable, [workspace, "8000", command], 15_000)

        if status != 0 do
          raise "sandbox helper failed to launch or report a result (status #{status}): #{inspect(raw)}"
        end

        frames = parse_frames!(raw)
        result = Enum.find(frames, fn {kind, _} -> kind == ?X end)

        case result do
          {?X, payload} ->
            exit_code = capture_int!(payload, "exit_code")
            if String.contains?(payload, "\"timed_out\":true"), do: raise("probe timed out")

            if exit_code != 0,
              do:
                raise(
                  "enforcement assertion failed, shell exit #{exit_code}; output=#{inspect(frames)}"
                )

          nil ->
            error = Enum.find(frames, fn {kind, _} -> kind == ?E end)
            raise "helper returned no completion frame: #{inspect(error || frames)}"
        end

        unless File.read!(outside_secret) == "fake-credential-sentinel\n",
          do: raise("outside fake credential changed")

        unless File.read!(outside_write) == "outside-sentinel\n",
          do: raise("outside file changed despite denied-write assertion")

        unless File.stat!(outside_secret).mode |> Bitwise.band(0o777) == 0o644,
          do: raise("outside fake credential metadata changed despite denied-chmod assertion")

        unless File.read!(workspace_write) == "workspace-ok",
          do: raise("sandbox did not permit workspace write")

        unless File.stat!(workspace_write).mode |> Bitwise.band(0o777) == 0o600,
          do: raise("sandbox did not permit workspace chmod control")

        IO.puts(
          "PASS: signed App Sandbox denied outside fake-credential/symlink reads, outside write/chmod, and loopback network; same Rust probe executed in-sandbox; allowed workspace chmod/write and private-tmp write; nested shell inherited policy"
        )

        IO.puts(
          "PASS: codesign strict verification; signed entitlements inspected; profile=#{id}"
        )

        if process_checks do
          process_boundaries!(
            executable,
            workspace,
            outside_secret,
            rustc
          )
        end
      after
        :gen_tcp.close(listener)
        Task.shutdown(server_task, :brutal_kill)
      end
    after
      File.rm(script)
      File.rm(symlink_read)
      File.rm(network_source)
      File.rm(network_probe)
      File.rm(workspace_write)
      File.rm_rf!(root_lexical)
    end
  end

  defp loopback_server! do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])

    {:ok, {_ip, port}} = :inet.sockname(listener)
    task = Task.async(fn -> serve(listener) end)
    {listener, port, task}
  end

  defp serve(listener) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        _ = :gen_tcp.recv(socket, 0, 1_000)
        _ = :gen_tcp.send(socket, "ipse-probe-ok\n")
        :gen_tcp.close(socket)
        serve(listener)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        raise "loopback fixture failed: #{inspect(reason)}"
    end
  end

  defp parse_frames!(binary), do: parse_frames!(binary, [])
  defp parse_frames!(<<>>, acc), do: Enum.reverse(acc)

  defp parse_frames!(<<kind, length::unsigned-big-32, rest::binary>>, acc)
       when byte_size(rest) >= length do
    <<payload::binary-size(^length), tail::binary>> = rest
    parse_frames!(tail, [{kind, payload} | acc])
  end

  defp parse_frames!(other, _acc), do: raise("malformed helper frame: #{inspect(other)}")

  defp capture_int!(json, key) do
    case Regex.run(~r/"#{Regex.escape(key)}":([0-9]+)/, json, capture: :all_but_first) do
      [value] -> String.to_integer(value)
      _ -> raise "missing #{key} in helper result #{inspect(json)}"
    end
  end

  def network_probe_source do
    """
    use std::io::Read;
    use std::net::{SocketAddr, TcpStream};
    use std::time::Duration;

    fn main_result() -> Result<(), String> {
        let args: Vec<String> = std::env::args().collect();
        if args.len() == 2 && args[1] == "--self-test" {
            println!("ready");
            return Ok(());
        }
        let expect_denied = args.len() == 4 && args[1] == "--expect-denied";
        if args.len() != 3 && !expect_denied { return Err("usage: network-probe [--expect-denied] IP PORT".into()); }
        let offset = if expect_denied {2} else {1};
        let address: SocketAddr = format!("{}:{}", args[offset], args[offset+1])
            .parse().map_err(|error| format!("invalid address: {error}"))?;
        let connection = TcpStream::connect_timeout(&address, Duration::from_secs(2));
        if expect_denied {
            return match connection {
                Err(error) if error.kind() == std::io::ErrorKind::PermissionDenied ||
                    matches!(error.raw_os_error(), Some(1) | Some(13)) => {
                        println!("connect denied by permission policy");
                        Ok(())
                    },
                Err(error) => Err(format!("expected a connect permission denial, got: {error}")),
                Ok(_) => Err("connection succeeded despite expected sandbox denial".into()),
            };
        }
        let mut stream = connection
            .map_err(|error| format!("connect denied or unavailable: {error}"))?;
        stream.set_read_timeout(Some(Duration::from_secs(2))).map_err(|error| error.to_string())?;
        let mut response = String::new();
        stream.read_to_string(&mut response).map_err(|error| error.to_string())?;
        if !response.contains("ipse-probe-ok\\n") { return Err("loopback fixture response mismatch".into()); }
        println!("connected");
        Ok(())
    }

    fn main() {
        if let Err(error) = main_result() { eprintln!("{error}"); std::process::exit(1); }
    }
    """
  end

  defp run_helper!(executable, args, timeout_ms) do
    # Keep the stdio pipe open while the Rust helper runs: it treats EOF as
    # owner death and kills the shell process group. System.cmd closes stdin.
    port =
      Port.open({:spawn_executable, String.to_charlist(executable)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        args: Enum.map(args, &String.to_charlist/1)
      ])

    collect_helper(port, [], System.monotonic_time(:millisecond) + timeout_ms)
  end

  defp collect_helper(port, chunks, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} -> collect_helper(port, [data | chunks], deadline)
      {^port, {:exit_status, status}} -> {IO.iodata_to_binary(Enum.reverse(chunks)), status}
      {^port, :closed} -> {IO.iodata_to_binary(Enum.reverse(chunks)), 1}
    after
      remaining ->
        Port.close(port)

        receive do
          {^port, {:exit_status, _status}} -> :ok
        after
          5_000 -> raise "could not confirm helper process exit after closing its port"
        end

        raise "sandbox probe helper exceeded its deadline"
    end
  end

  defp entitlements(roots) do
    roots = Enum.map(roots, &canonical_dir!/1)
    values = Enum.map_join(roots, "\n", &"      <string>#{xml_escape(&1)}</string>")

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>com.apple.security.app-sandbox</key><true/>
      <key>com.apple.security.temporary-exception.files.absolute-path.read-write</key>
      <array>
    #{values}
      </array>
    </dict></plist>
    """
  end

  defp info_plist(bundle_id) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>CFBundleExecutable</key><string>ipse-runner</string>
      <key>CFBundleIdentifier</key><string>#{bundle_id}</string>
      <key>CFBundlePackageType</key><string>APPL</string>
      <key>CFBundleName</key><string>IpseRunner</string>
      <key>CFBundleVersion</key><string>0.1</string>
      <key>CFBundleShortVersionString</key><string>0.1</string>
    </dict></plist>
    """
  end

  defp canonical_file!(path) do
    expanded = Path.expand(path)
    unless File.regular?(expanded), do: raise("not a regular file: #{expanded}")
    Path.expand(expanded)
  end

  defp canonical_dir!(path) do
    expanded = Path.expand(path)
    unless File.dir?(expanded), do: raise("not a directory: #{expanded}")
    {physical, 0} = System.cmd("/bin/sh", ["-c", "cd \"$1\" && pwd -P", "ipse-probe", expanded])
    String.trim(physical) <> "/"
  end

  defp shell_quote(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"

  defp xml_escape(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp require_macos! do
    case :os.type() do
      {:unix, :darwin} -> :ok
      other -> raise "macOS App Sandbox probe requires Darwin; current OS is #{inspect(other)}"
    end
  end

  defp require_tool!(path) do
    mode =
      case File.stat(path) do
        {:ok, %{type: :regular, mode: mode}} -> mode
        _ -> raise "required system tool missing or not a regular file: #{path}"
      end

    if Bitwise.band(mode, 0o111) == 0,
      do: raise("required system tool is not executable: #{path}")
  end

  defp require_contains!(text, part) do
    unless String.contains?(text, part),
      do: raise("codesign output missing expected entitlement #{inspect(part)}: #{inspect(text)}")
  end

  defp run_command!(exe, args) do
    {output, status} = System.cmd(exe, args, stderr_to_stdout: true)
    if status != 0, do: raise("#{exe} failed (#{status}): #{String.trim(output)}")
    output
  end

  defp process_boundaries!(helper, workspace, secret, rustc) do
    root = Path.join(workspace, ".ipse-process-probe-#{System.unique_integer([:positive])}")
    File.mkdir!(root)

    try do
      probe = Path.join(root, "process-probe")
      source = Path.join(__DIR__, "platform/macos_process_probe.rs")

      {output, status} =
        System.cmd(rustc, ["--edition=2021", source, "-o", probe], stderr_to_stdout: true)

      if status != 0, do: raise("cannot compile process fixture: #{output}")

      gaps =
        for mode <- ["group", "setsid", "setpgid"],
            event <- [:exit, :timeout, :cancel, :owner_death],
            escaped = check!(helper, workspace, secret, probe, root, mode, event),
            escaped,
            do: "#{mode}/#{event}"

      if gaps != [] do
        raise "process containment failed: #{Enum.join(gaps, ", ")}; native macOS must remain unavailable"
      end

      IO.puts("PASS: all process-boundary cases contained descendants")
    after
      File.rm_rf!(root)
    end
  end

  defp check!(helper, workspace, secret, probe, root, mode, event) do
    prefix = Path.join(root, "#{mode}-#{event}")
    ready = prefix <> ".ready"
    release = prefix <> ".release"
    effect = prefix <> ".effect"
    role = if event == :exit, do: "exit", else: "hold"

    command =
      Enum.map_join(
        [probe, "parent", mode, role, ready, release, effect, secret],
        " ",
        &shell_quote/1
      )

    owner = self()

    {pid, monitor} =
      spawn_monitor(fn ->
        port =
          Port.open({:spawn_executable, String.to_charlist(helper)}, [
            :binary,
            :exit_status,
            :use_stdio,
            args: [workspace, "1000", command]
          ])

        {:os_pid, helper_pid} = Port.info(port, :os_pid)
        send(owner, {:probe_port, self(), port, helper_pid})
        collect(port, owner, <<>>, event, System.monotonic_time(:millisecond) + 5_000)
      end)

    try do
      {port, helper_pid} =
        receive do
          {:probe_port, ^pid, port, helper_pid} ->
            {port, helper_pid}

          {:DOWN, ^monitor, :process, ^pid, reason} ->
            raise "probe owner failed: #{inspect(reason)}"
        after
          5_000 -> raise "probe owner did not start"
        end

      receive do
        {:probe_ready, ^pid} ->
          :ok

        {:DOWN, ^monitor, :process, ^pid, reason} ->
          raise "fixture failed before readiness: #{inspect(reason)}"
      after
        5_000 -> raise "descendant did not become ready"
      end

      # Readiness follows the actual group change and inherited-policy check.
      [child, group] = File.read!(ready) |> String.split() |> Enum.map(&String.to_integer/1)
      if mode != "group" and child != group, do: raise("escape did not create its own group")

      case event do
        :cancel -> send(pid, :cancel)
        :owner_death -> Process.exit(pid, :kill)
        _ -> :ok
      end

      receive do
        {:DOWN, ^monitor, :process, ^pid, reason} ->
          expected = if event == :owner_death, do: :killed, else: :normal
          if reason != expected, do: raise("fixture owner failed: #{inspect(reason)}")
      after
        5_000 -> raise "helper did not finish"
      end

      await!(fn -> Port.info(port) == nil end, 1_000, "helper port remained open")
      await!(fn -> not alive?(probe, helper_pid) end, 1_000, "helper process remained alive")
      File.write!(release, "release\n")
      Process.sleep(200)
      survived = File.exists?(effect)

      if survived do
        await!(
          fn -> not alive?(probe, child) end,
          2_000,
          "bounded descendant did not exit"
        )
      else
        if alive?(probe, child),
          do: raise("descendant still alive without an effect; inconclusive check")
      end

      if mode == "group" and survived, do: raise("ordinary group cleanup failed for #{event}")

      IO.puts(
        "#{if survived, do: "GAP", else: "PASS"}: #{mode}/#{event}, post-cleanup write=#{survived}"
      )

      survived
    after
      if Process.alive?(pid), do: Process.exit(pid, :kill)
      Process.demonitor(monitor, [:flush])
    end
  end

  defp alive?(probe, pid) do
    case System.cmd(probe, ["alive", Integer.to_string(pid)], stderr_to_stdout: true) do
      {"alive\n", 0} -> true
      {"gone\n", 0} -> false
      result -> raise "cannot check fixture liveness: #{inspect(result)}"
    end
  end

  defp collect(port, owner, buffer, event, deadline) do
    receive do
      {^port, {:data, data}} ->
        buffer = buffer <> data

        if String.contains?(buffer, "process-probe-ready\n"),
          do: send(owner, {:probe_ready, self()})

        collect(port, owner, buffer, event, deadline)

      {^port, {:exit_status, 0}} ->
        expected = if event == :timeout, do: "\"timed_out\":true", else: "\"timed_out\":false"

        unless String.contains?(buffer, expected),
          do: raise("missing expected helper result: #{inspect(buffer)}")

      {^port, {:exit_status, status}} ->
        raise "helper failed with #{status}: #{inspect(buffer)}"

      :cancel ->
        Port.close(port)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        Port.close(port)
        raise "helper exceeded probe deadline"
    end
  end

  defp await!(fun, milliseconds, error) do
    deadline = System.monotonic_time(:millisecond) + milliseconds
    await_until!(fun, deadline, error)
  end

  defp await_until!(fun, deadline, error) do
    unless fun.() do
      if System.monotonic_time(:millisecond) >= deadline, do: raise(error)
      Process.sleep(10)
      await_until!(fun, deadline, error)
    end
  end
end

Ipse.Development.Platform.MacSandboxProbe.main(System.argv())
