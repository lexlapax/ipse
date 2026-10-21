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
