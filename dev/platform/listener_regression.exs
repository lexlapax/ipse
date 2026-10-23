defmodule Ipse.Development.Platform.ListenerRegression.Instrument do
  @moduledoc false
  def replace_once!(source, anchor, replacement) do
    case String.split(source, anchor) do
      [before, after_part] -> before <> replacement <> after_part
      _ -> raise("diagnostic anchor missing or nonunique")
    end
  end

  def prepare!(repository, root, kind, reverted) do
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    native = Path.join(root, "native")
    File.mkdir!(native)

    original =
      Path.wildcard(Path.join(repository, "native/*.rs"))
      |> Map.new(fn source ->
        bytes = File.read!(source)
        File.write!(Path.join(native, Path.basename(source)), bytes, [:exclusive])
        {Path.basename(source), sha(bytes)}
      end)

    listener = Path.join(native, "ipse-listener.rs")
    source = File.read!(listener)
    anchor = "    fn inspect(pid: u32, port: u16) -> Result<Option<u64>, String> {\n"

    injection = """
        #[cfg(ipse_probe_listener_barrier)]
        {
            let path = std::env::var("IPSE_LISTENER_PROBE_BARRIER").map_err(|_| "diagnostic barrier absent")?;
            let deadline = Instant::now() + Duration::from_secs(2);
            while !std::path::Path::new(&path).is_file() {
                if Instant::now() >= deadline { return Err("diagnostic readiness barrier timed out".into()); }
                std::thread::sleep(Duration::from_millis(1));
            }
        }
    """

    source = replace_once!(source, anchor, anchor <> injection)

    source =
      if kind == :namespace and reverted do
        source
        |> replace_once!("fn table(port: u16)", "fn table(pid: u32, port: u16)")
        |> replace_once!(
          "File::open(path)",
          "File::open(path.replace(\"/proc/self/\", &format!(\"/proc/{pid}/\")))"
        )
        |> replace_once!("let Some(inode) = table(port)?", "let Some(inode) = table(pid, port)?")
        |> replace_once!("if table(port)? != Some(inode)", "if table(pid, port)? != Some(inode)")
      else
        source
      end

    File.write!(listener, source)

    if kind == :output_loss do
      stdio = Path.join(native, "ipse-stdio.rs")
      source = File.read!(stdio)

      source =
        if reverted do
          replace_once!(
            source,
            "                    if !listener.as_ref().is_some_and(listener::Listener::inspection_pending) {\n" <>
              "                        let _ = child.wait();\n                    }\n",
            "                    let _ = child.wait();\n"
          )
        else
          source
        end

      anchor =
        "                    return Ok(());\n                }\n                if kind == b'E' {"

      injected =
        "                    #[cfg(ipse_probe_output_loss)] listener::diagnostic_after_output_loss(child.id(), listener.as_ref().is_some_and(listener::Listener::inspection_pending));\n"

      File.write!(stdio, replace_once!(source, anchor, injected <> anchor))

      File.write!(
        listener,
        """

        #[cfg(ipse_probe_output_loss)]
        pub fn diagnostic_after_output_loss(pid: u32, pending: bool) {
            let root = std::path::PathBuf::from(std::env::var("IPSE_LISTENER_PROBE_OUTPUT").unwrap());
            std::fs::write(root.join("pending"), pending.to_string()).unwrap();
            std::fs::write(root.join("child-pid.tmp"), pid.to_string()).unwrap();
            std::fs::rename(root.join("child-pid.tmp"), root.join("child-pid")).unwrap();
            let deadline = std::time::Instant::now() + std::time::Duration::from_secs(2);
            while !root.join("release").is_file() && std::time::Instant::now() < deadline {
                std::thread::sleep(std::time::Duration::from_millis(1));
            }
        }
        """,
        [:append]
      )
    end

    generated =
      Path.wildcard(Path.join(native, "*.rs"))
      |> Map.new(&{Path.basename(&1), sha(File.read!(&1))})

    helper = Path.join(root, "helper")
    flags = if kind == :output_loss, do: ["--cfg", "ipse_probe_output_loss"], else: []

    {log, code} =
      System.cmd(
        "rustc",
        ["--edition=2021", "-D", "warnings", "--cfg", "ipse_probe_listener_barrier"] ++
          flags ++ [Path.join(native, "ipse-runner.rs"), "-o", helper],
        stderr_to_stdout: true
      )

    File.write!(Path.join(root, "compile.log"), log, [:exclusive])
    if code != 0, do: raise("diagnostic native compilation failed; retained compile.log")

    identity = %{
      "kind" => Atom.to_string(kind),
      "reverted" => reverted,
      "original_source" => original,
      "generated_diagnostic_source" => generated,
      "helper_sha256" => sha(File.read!(helper))
    }

    File.write!(Path.join(root, "identity.json"), JSON.encode!(identity) <> "\n", [
      :exclusive,
      :sync
    ])

    {helper, original}
  end

  def sha(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end

defmodule Ipse.Development.Platform.ListenerRegression.Namespace do
  @moduledoc false
  alias Ipse.Runner

  def verify(current, reverted, fixture, output) do
    File.mkdir!(output)
    File.chmod!(output, 0o700)
    own!(current, fixture, output, "own-current")
    own!(reverted, fixture, output, "own-reverted")
    port = free_port()
    marker = Path.join(output, "unrelated-requests")

    {:ok, occupant} =
      Runner.open_stdio(
        fixture,
        ["occupied", Integer.to_string(port), marker],
        output,
        %{},
        60_000
      )

    try do
      await_occupant(occupant, <<>>, deadline(5_000))

      results =
        Enum.reduce_while(
          for(version <- [:current, :reverted], attempt <- 1..8, do: {version, attempt}),
          [],
          fn {version, attempt}, acc ->
            helper = if version == :current, do: current, else: reverted
            name = "#{version}-#{attempt}"
            value = candidate(helper, fixture, "namespace", port, output, name)
            false = File.exists?(marker)

            if unavailable?(value) do
              {:halt,
               [
                 %{
                   "version" => Atom.to_string(version),
                   "status" => "unavailable",
                   "case" => value
                 }
                 | acc
               ]}
            else
              true = value["stdout"] == "namespace-ready\n"
              true = value["namespace_ready"]

              if version == :current do
                [] = value["facts"]
                ["listener is not owned by the direct child"] = value["errors"]
              else
                [%{"port" => ^port, "pid" => pid, "inode" => inode}] = value["facts"]
                true = pid > 0 and inode > 0
              end

              {:cont, [Map.put(value, "version", Atom.to_string(version)) | acc]}
            end
          end
        )
        |> Enum.reverse()

      available =
        length(results) == 16 and not Enum.any?(results, &(&1["status"] == "unavailable"))

      report = %{
        "status" => if(available, do: "passed", else: "unavailable"),
        "cases" => length(results),
        "unrelated_requests" => 0,
        "current_false_facts" =>
          Enum.count(results, &(&1["version"] == "current" and &1["facts"] not in [nil, []])),
        "reverted_false_facts" =>
          Enum.count(results, &(&1["version"] == "reverted" and &1["facts"] not in [nil, []])),
        "results" => results
      }

      save!(Path.join(output, "namespace.json"), JSON.encode!(report))
      report
    after
      :ok = Runner.close_stdio(occupant, :cancel)
    end
  end

  defp own!(helper, fixture, output, name) do
    port = free_port()
    value = candidate(helper, fixture, "own", port, output, name)
    [%{"port" => ^port, "pid" => pid, "inode" => inode}] = value["facts"]
    true = pid > 0 and inode > 0
    true = value["stdout"] == "ready\n"
    0 = value["native_exit"]
  end

  defp candidate(helper, fixture, mode, port, output, name) do
    directory = Path.join(output, name)
    File.mkdir!(directory)
    File.chmod!(directory, 0o700)
    barrier = Path.join(directory, "ready-barrier")
    selected = %{"PATH" => "/usr/bin:/bin", "LANG" => "C.UTF-8"}
    removed = System.get_env() |> Map.keys() |> Enum.map(&{String.to_charlist(&1), false})

    env =
      removed ++
        [
          {~c"PATH", ~c"/usr/bin:/bin"},
          {~c"LANG", ~c"C.UTF-8"},
          {~c"IPSE_LISTENER_PROBE_BARRIER", String.to_charlist(barrier)}
        ]

    native =
      Port.open({:spawn_executable, helper}, [
        :binary,
        :exit_status,
        {:env, env},
        {:args,
         [
           "--stdio-listener",
           directory,
           "3500",
           Integer.to_string(port),
           "--",
           fixture,
           mode,
           Integer.to_string(port)
         ]}
      ])

    body =
      IO.iodata_to_binary([
        <<map_size(selected)::32>>
        | Enum.map(selected, fn {key, value} ->
            [<<byte_size(key)::32>>, key, <<byte_size(value)::32>>, value]
          end)
      ])

    try do
      true = Port.command(native, [<<?L, byte_size(body)::32>>, body])

      value =
        collect(native, mode, barrier, deadline(6_000), %{
          frames: [],
          buffer: <<>>,
          raw: <<>>,
          canceled: false
        })

      save!(Path.join(directory, "protocol.bin"), value.raw)

      facts =
        for {?P, <<1, pid::32, observed_port::16, inode::64>>} <- value.frames,
            do: %{"pid" => pid, "port" => observed_port, "inode" => inode}

      result = %{
        "native_exit" => value.code,
        "facts" => facts,
        "errors" => for({?E, bytes} <- value.frames, do: bytes),
        "stdout" => stream(value.frames, ?O),
        "stderr" => stream(value.frames, ?S),
        "terminal" => for({?X, bytes} <- value.frames, do: JSON.decode!(bytes)),
        "namespace_ready" => stream(value.frames, ?O) == "namespace-ready\n"
      }

      save!(Path.join(directory, "result.json"), JSON.encode!(result))
      true = result["native_exit"] in [0, 1]
      result
    after
      if Port.info(native), do: :ok = Runner.close_stdio(native, :cancel)
    end
  end

  defp collect(port, mode, barrier, until, state) do
    remaining = max(until - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, bytes}} ->
        if byte_size(state.raw) + byte_size(bytes) > 65_536,
          do: raise("diagnostic traffic exceeds bound")

        {new_frames, buffer} = decode(state.buffer <> bytes, [])
        frames = state.frames ++ new_frames
        if length(frames) > 128, do: raise("diagnostic frame count exceeds bound")
        stdout = stream(frames, ?O)

        ready =
          if mode == "namespace", do: stdout == "namespace-ready\n", else: stdout == "ready\n"

        if ready and not File.exists?(barrier), do: save!(barrier, "ready\n")
        proof = Enum.any?(frames, &(elem(&1, 0) == ?P))

        if proof and not state.canceled,
          do: true = Port.command(port, <<?C, 0::32>>, [:nosuspend])

        collect(port, mode, barrier, until, %{
          state
          | frames: frames,
            buffer: buffer,
            raw: state.raw <> bytes,
            canceled: state.canceled or proof
        })

      {^port, {:exit_status, code}} ->
        <<>> = state.buffer
        Map.put(state, :code, code)

      {:EXIT, ^port, :normal} ->
        collect(port, mode, barrier, until, state)

      {:EXIT, ^port, reason} ->
        raise("diagnostic Port failed: #{inspect(reason)}")
    after
      remaining -> raise("diagnostic helper exceeded finite lifetime")
    end
  end

  defp decode(bytes, frames) when byte_size(bytes) < 5, do: {Enum.reverse(frames), bytes}

  defp decode(<<?P, size::32, _::binary>>, _) when size != 15,
    do: raise("invalid diagnostic P size")

  defp decode(<<kind, size::32, rest::binary>> = bytes, frames) do
    unless kind in [?O, ?S, ?P, ?E, ?X] and size <= 8192, do: raise("invalid diagnostic frame")

    if byte_size(rest) < size do
      {Enum.reverse(frames), bytes}
    else
      payload = binary_part(rest, 0, size)
      decode(binary_part(rest, size, byte_size(rest) - size), [{kind, payload} | frames])
    end
  end

  defp await_occupant(port, bytes, until) do
    receive do
      {^port, {:data, more}} when byte_size(bytes) + byte_size(more) <= 16_384 ->
        bytes = bytes <> more
        {frames, _} = decode(bytes, [])
        if stream(frames, ?O) == "ready\n", do: :ok, else: await_occupant(port, bytes, until)

      {:EXIT, ^port, _} ->
        raise("ordinary occupied fixture exited before readiness")
    after
      max(until - System.monotonic_time(:millisecond), 0) ->
        raise("ordinary occupied fixture readiness absent")
    end
  end

  defp unavailable?(value),
    do:
      not value["namespace_ready"] and
        String.contains?(value["stderr"], "namespace capability unavailable:") and
        Enum.any?(value["terminal"], &(&1["exit_code"] == 77))

  defp stream(frames, kind), do: for({^kind, bytes} <- frames, into: <<>>, do: bytes)

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])

    try do
      {:ok, {{127, 0, 0, 1}, port}} = :inet.sockname(socket)
      port
    after
      :gen_tcp.close(socket)
    end
  end

  defp deadline(ms), do: System.monotonic_time(:millisecond) + ms

  defp save!(path, bytes) do
    File.write!(path, bytes, [:exclusive, :sync])
    File.chmod!(path, 0o600)
    {:ok, :ok} = File.open(Path.dirname(path), [:read, :raw, :directory], &:file.sync/1)
  end
end

defmodule Ipse.Development.Platform.ListenerRegression.PidNamespace do
  def collect(port, until, state) do
    receive do
      {^port, {:data, bytes}} ->
        if byte_size(state.raw) + byte_size(bytes) > 65_536,
          do: raise("diagnostic traffic bound exceeded")

        {frames, buffer} = decode(state.buffer <> bytes, [])
        all = state.frames ++ frames
        if length(all) > 128, do: raise("diagnostic frame count bound exceeded")
        proof = Enum.any?(all, &(elem(&1, 0) == ?P))
        if proof and not state.canceled, do: true = Port.command(port, <<?C, 0::32>>)

        collect(port, until, %{
          state
          | raw: state.raw <> bytes,
            frames: all,
            buffer: buffer,
            canceled: state.canceled or proof
        })

      {^port, {:exit_status, code}} ->
        <<>> = state.buffer
        Map.put(state, :exit, code)

      {:EXIT, ^port, :normal} ->
        collect(port, until, state)

      {:EXIT, ^port, reason} ->
        raise("wrapper Port failed: #{inspect(reason)}")
    after
      max(until - System.monotonic_time(:millisecond), 0) ->
        raise("wrapper exceeded finite diagnostic lifetime")
    end
  end

  defp decode(bytes, frames) when byte_size(bytes) < 5, do: {Enum.reverse(frames), bytes}

  defp decode(<<kind, size::32, rest::binary>> = bytes, frames) do
    unless kind in [?O, ?S, ?P, ?E, ?X] and size <= 8192,
      do: raise("invalid diagnostic native frame")

    if kind == ?P and size != 15, do: raise("invalid P length")

    if byte_size(rest) < size,
      do: {Enum.reverse(frames), bytes},
      else:
        decode(binary_part(rest, size, byte_size(rest) - size), [
          {kind, binary_part(rest, 0, size)} | frames
        ])
  end

  def cleanup(port) do
    if Port.info(port) do
      try do
        Port.command(port, <<?C, 0::32>>)
      rescue
        ArgumentError -> :ok
      end

      drain(port, System.monotonic_time(:millisecond) + 15_000)
    end
  end

  defp drain(port, until) do
    receive do
      {^port, {:exit_status, _}} -> :ok
      {^port, {:data, _}} -> drain(port, until)
      {:EXIT, ^port, :normal} -> drain(port, until)
    after
      max(until - System.monotonic_time(:millisecond), 0) ->
        if Port.info(port), do: Port.close(port)
        raise("owned wrapper cleanup unconfirmed; inspect private evidence")
    end
  end
end

defmodule Ipse.Development.Platform.ListenerRegression.PidNamespace.Controls do
  def verify(wrapper, helper, fixture, root) do
    unless match?({:unix, :linux}, :os.type()), do: raise("PID namespace controls require Linux")

    Enum.each([wrapper, helper, fixture, root], fn path -> true = Path.type(path) == :absolute end)

    File.mkdir!(root)
    File.chmod!(root, 0o700)
    previous = Process.flag(:trap_exit, true)

    results =
      try do
        for mode <- ["inherited-listener", "ordinary", "fresh-listener"],
            do: one(wrapper, helper, fixture, root, mode)
      after
        Process.flag(:trap_exit, previous)
      end

    report = %{
      "status" =>
        if(Enum.all?(results, &(&1["status"] == "passed")), do: "passed", else: "incomplete"),
      "cases" => results,
      "http_requests" => 0,
      "helper_sha256" => sha(helper),
      "fixture_sha256" => sha(fixture),
      "wrapper_sha256" => sha(wrapper),
      "evidence" => root
    }

    save(root, "summary.json", JSON.encode!(report) <> "\n")
    report
  end

  defp one(wrapper, helper, fixture, root, mode) do
    directory = Path.join(root, mode)
    File.mkdir!(directory)
    File.chmod!(directory, 0o700)
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {{127, 0, 0, 1}, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)
    removed = Enum.map(Map.keys(System.get_env()), &{String.to_charlist(&1), false})

    native =
      Port.open({:spawn_executable, wrapper}, [
        :binary,
        :exit_status,
        {:env, removed ++ [{~c"PATH", ~c"/usr/bin:/bin"}, {~c"LANG", ~c"C.UTF-8"}]},
        {:args, [helper, fixture, directory, mode, Integer.to_string(port)]}
      ])

    selected = [{"PATH", "/usr/bin:/bin"}, {"LANG", "C.UTF-8"}]

    body =
      IO.iodata_to_binary([
        <<length(selected)::32>>
        | Enum.map(selected, fn {key, value} ->
            [<<byte_size(key)::32>>, key, <<byte_size(value)::32>>, value]
          end)
      ])

    value =
      try do
        try do
          Port.command(native, [<<?L, byte_size(body)::32>>, body])
        rescue
          ArgumentError -> :ok
        end

        Ipse.Development.Platform.ListenerRegression.PidNamespace.collect(
          native,
          System.monotonic_time(:millisecond) + 12_000,
          %{raw: <<>>, buffer: <<>>, frames: [], canceled: false}
        )
      after
        Ipse.Development.Platform.ListenerRegression.PidNamespace.cleanup(native)
      end

    save(directory, "protocol.bin", value.raw)

    read = fn name ->
      case File.read(Path.join(directory, name)) do
        {:ok, bytes} -> bytes
        {:error, :enoent} -> nil
      end
    end

    facts =
      for {?P, <<1, pid::32, observed_port::16, inode::64>>} <- value.frames,
          do: %{"pid" => pid, "port" => observed_port, "inode" => inode}

    errors = for {?E, bytes} <- value.frames, do: bytes
    terminals = for {?X, bytes} <- value.frames, do: JSON.decode!(bytes)
    stdout = for {?O, bytes} <- value.frames, into: <<>>, do: bytes
    false = File.exists?(Path.join(directory, "http-request-marker"))

    status =
      if value.exit == 77 and read.("unavailable") != nil do
        if read.("namespace.txt"),
          do: true = String.starts_with?(read.("cleanup") || "", "reaped=true\n")

        "unavailable"
      else
        true = read.("namespace.txt") != nil
        true = String.starts_with?(read.("cleanup") || "", "reaped=true\n")

        case mode do
          "inherited-listener" ->
            1 = value.exit
            [] = facts
            ["owned listener requires matching procfs and PID namespaces"] = errors
            nil = read.("selected.txt")

          "ordinary" ->
            0 = value.exit
            [] = facts
            [] = errors
            true = read.("selected.txt") != nil
            [%{"exit_code" => 0}] = terminals

          "fresh-listener" ->
            0 = value.exit
            [] = errors
            "ready\n" = stdout
            [%{"pid" => pid, "port" => ^port, "inode" => inode}] = facts
            [_, selected_pid] = Regex.run(~r/selected_getpid=(\d+)/, read.("selected.txt"))
            true = pid == String.to_integer(selected_pid) and inode > 0
        end

        "passed"
      end

    report = %{
      "mode" => mode,
      "status" => status,
      "native_exit" => value.exit,
      "facts" => facts,
      "errors" => errors,
      "terminal" => terminals,
      "stdout" => stdout,
      "selected_executed" => read.("selected.txt") != nil,
      "metadata" =>
        Map.new(["namespace.txt", "selected.txt", "cleanup", "unavailable"], &{&1, read.(&1)})
    }

    save(directory, "result.json", JSON.encode!(report) <> "\n")
    report
  end

  defp sha(path), do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)

  defp save(root, name, bytes) do
    path = Path.join(root, name)
    File.write!(path, bytes, [:exclusive, :sync])
    File.chmod!(path, 0o600)
  end
end
