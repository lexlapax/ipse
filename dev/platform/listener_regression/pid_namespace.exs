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
