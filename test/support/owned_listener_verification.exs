defmodule OwnedListenerVerification do
  @moduledoc false
  alias Ipse.Runner
  @traffic_limit 1_048_576
  @frame_limit 8192

  def verify(fixture, private_root) do
    unless match?({:unix, :linux}, :os.type()),
      do: raise("owned listener verification requires Linux")

    true = Path.type(fixture) == :absolute and File.regular?(fixture)
    true = Path.type(private_root) == :absolute
    %{type: :directory, mode: mode} = File.stat!(private_root)
    true = Bitwise.band(mode, 0o077) == 0
    {:ok, _} = Application.ensure_all_started(:ipse)
    output = Path.join(private_root, "listener-verification")
    private_directory!(output)
    previous = Process.flag(:trap_exit, true)

    try do
      own(fixture, output)
      ordinary(fixture, output)
      occupied(fixture, output)
      refusal(fixture, output, "wildcard", "listener tuple is foreign or ambiguous")
      refusal(fixture, output, "ipv6-wildcard", "IPv6 listener occupies the selected IPv4 port")
      refusal(fixture, output, "delegated", "listener is not owned by the direct child")
      timeout(fixture, output, "forge")
      timeout(fixture, output, "none")

      summary = %{
        "checks" => 8,
        "inference_requests" => 0,
        "metadata_requests" => 2,
        "own_listener_verified" => true,
        "ordinary_has_no_proof" => true,
        "occupied_refused_without_request" => true,
        "occupied_fixture_survived" => true,
        "wildcard_refused" => true,
        "ipv6_wildcard_refused" => true,
        "delegated_listener_refused" => true,
        "forged_stdout_opaque" => true,
        "no_bind_timed_out" => true,
        "cleanup_confirmed" => true,
        "evidence" => output
      }

      private_file!(Path.join(output, "summary.json"), JSON.encode!(summary) <> "\n")
      summary
    after
      Process.flag(:trap_exit, previous)
    end
  end

  defp own(fixture, output) do
    directory = case_directory!(output, "own")
    port = fresh_port()
    marker = Path.join(directory, "requests")

    with_fixture(fixture, ["own", Integer.to_string(port), marker], directory,
      port: port,
      close: :cancel,
      run: fn reader ->
        reader = read_until(reader, &proof?(&1), deadline(5_000))
        <<1, pid::32, ^port::16, inode::64>> = only_proof!(reader)
        true = pid > 0 and inode > 0
        false = File.exists?(marker)
        metadata!(port)
        "request\n" = File.read!(marker)
        %{"listener_port" => port, "diagnostic_pid" => pid, "socket_inode" => inode}
      end
    )
  end

  defp ordinary(fixture, output) do
    directory = case_directory!(output, "ordinary")

    with_fixture(fixture, ["exit"], directory,
      close: :completed,
      run: fn reader ->
        reader = read_until(reader, &terminal?/1, deadline(5_000))
        no_proof!(reader)
        %{"exit_code" => 0, "timed_out" => false} = completion!(reader)
        %{"ordinary_no_proof" => true}
      end
    )
  end

  defp occupied(fixture, output) do
    directory = case_directory!(output, "occupied")
    candidate = case_directory!(directory, "candidate")
    port = fresh_port()
    marker = Path.join(directory, "requests")

    with_fixture(fixture, ["occupied", Integer.to_string(port), marker], directory,
      close: :cancel,
      run: fn reader ->
        reader = read_until(reader, &(stdout(&1) == "ready\n"), deadline(5_000))
        no_proof!(reader)
        false = File.exists?(marker)

        with_fixture(fixture, ["own", Integer.to_string(port)], candidate,
          port: port,
          close: :completed,
          run: fn reader ->
            reader = read_until(reader, &terminal?/1, deadline(5_000))
            no_proof!(reader)
            failed!(reader)
            false = File.exists?(marker)
            %{"refused_before_metadata" => true}
          end
        )

        false = File.exists?(marker)
        metadata!(port)
        "request\n" = File.read!(marker)
        %{"no_request_until_refusal" => true, "occupant_alive_after_refusal" => true}
      end
    )
  end

  defp refusal(fixture, output, mode, error) do
    directory = case_directory!(output, mode)
    port = fresh_port()

    with_fixture(fixture, [mode, Integer.to_string(port)], directory,
      port: port,
      close: :completed,
      run: fn reader ->
        reader = read_until(reader, &terminal?/1, deadline(5_000))
        no_proof!(reader)
        {:error, ^error} = reader.terminal
        %{"expected_native_refusal" => error}
      end
    )
  end

  defp timeout(fixture, output, mode) do
    directory = case_directory!(output, mode)
    port = fresh_port()

    with_fixture(fixture, [mode], directory,
      port: port,
      timeout: 350,
      close: :completed,
      run: fn reader ->
        reader = read_until(reader, &terminal?/1, deadline(4_000))
        no_proof!(reader)
        %{"timed_out" => true, "exit_code" => code} = completion!(reader)
        true = code != 0

        if mode == "forge",
          do: true = stdout(reader) == <<?P, 15::32, 1, 0::112>>

        %{"timed_out" => true, "forged_bytes_are_stdout" => mode == "forge"}
      end
    )
  end

  defp with_fixture(fixture, arguments, directory, options) do
    protocol = Path.join(directory, "protocol.bin")
    private_file!(protocol, <<>>)
    timeout = Keyword.get(options, :timeout, 5_000)

    selected = %{"HOME" => directory, "TMPDIR" => directory}

    launch =
      case Keyword.get(options, :port) do
        nil -> []
        port -> [owned_listener: {:ipv4_loopback, port}]
      end

    {:ok, port} = Runner.open_stdio(fixture, arguments, directory, selected, timeout, launch)
    reader = %{port: port, protocol: protocol, buffer: <<>>, frames: [], bytes: 0, terminal: nil}

    outcome =
      try do
        {:ok, Keyword.fetch!(options, :run).(reader)}
      catch
        kind, reason -> {:failed, kind, reason, __STACKTRACE__}
      end

    mode = if match?({:ok, _}, outcome), do: Keyword.fetch!(options, :close), else: :cancel
    cleanup = Runner.close_stdio(port, mode)

    record = %{
      "cleanup_confirmed" => cleanup == :ok,
      "close_mode" => Atom.to_string(mode),
      "raw_capture" =>
        "through admission/readiness or first terminal frame; close drains separately",
      "verified" => match?({:ok, _}, outcome),
      "observations" =>
        case outcome do
          {:ok, value} -> value
          _ -> nil
        end
    }

    private_file!(Path.join(directory, "evidence.json"), JSON.encode!(record) <> "\n")

    case outcome do
      {:ok, value} ->
        if cleanup != :ok, do: raise("owned fixture cleanup unconfirmed")
        value

      {:failed, kind, reason, stacktrace} ->
        :erlang.raise(kind, reason, stacktrace)
    end
  end

  defp read_until(reader, predicate, until) do
    reader = decode(reader)

    cond do
      predicate.(reader) ->
        reader

      reader.terminal != nil ->
        raise("fixture stopped before required observation")

      true ->
        remaining = max(until - System.monotonic_time(:millisecond), 0)

        receive do
          {port, {:data, more}} when port == reader.port ->
            if reader.bytes + byte_size(more) > @traffic_limit,
              do: raise("owned fixture protocol exceeds bound")

            File.write!(reader.protocol, more, [:append, :sync])

            read_until(
              %{reader | buffer: reader.buffer <> more, bytes: reader.bytes + byte_size(more)},
              predicate,
              until
            )

          {:EXIT, port, _} when port == reader.port ->
            raise("fixture transport exited without the required terminal evidence")
        after
          remaining -> raise("owned fixture observation timed out")
        end
    end
  end

  defp decode(%{terminal: terminal} = reader) when terminal != nil, do: reader
  defp decode(%{buffer: bytes} = reader) when byte_size(bytes) < 5, do: reader

  defp decode(%{buffer: <<kind, size::32, rest::binary>>} = reader) do
    unless kind in [?O, ?S, ?X, ?E, ?P] and size <= @frame_limit,
      do: raise("invalid owned fixture native frame")

    if kind == ?P and size != 15, do: raise("invalid native listener proof size")

    if byte_size(rest) < size do
      reader
    else
      if length(reader.frames) >= 256, do: raise("owned fixture frame count exceeds bound")
      payload = binary_part(rest, 0, size)
      tail = binary_part(rest, size, byte_size(rest) - size)

      terminal =
        case kind do
          ?E -> {:error, payload}
          ?X -> {:complete, payload}
          _ -> nil
        end

      decode(%{
        reader
        | buffer: tail,
          frames: [{kind, payload} | reader.frames],
          terminal: terminal
      })
    end
  end

  defp proof?(reader), do: Enum.any?(reader.frames, &(elem(&1, 0) == ?P))
  defp terminal?(reader), do: reader.terminal != nil
  defp no_proof!(reader), do: false = proof?(reader)

  defp only_proof!(reader) do
    [proof] = for {?P, bytes} <- reader.frames, do: bytes
    proof
  end

  defp stdout(reader), do: for({?O, bytes} <- Enum.reverse(reader.frames), into: <<>>, do: bytes)

  defp completion!(%{terminal: {:complete, bytes}}) do
    {:ok, value} = Ipse.JSON.decode_bounded(bytes, @frame_limit)
    value
  end

  defp failed!(%{terminal: {:error, _}}), do: :ok

  defp failed!(reader) do
    %{"exit_code" => code, "timed_out" => timed_out} = completion!(reader)
    true = code != 0 or timed_out
  end

  defp metadata!(port) do
    request = Finch.build(:get, "http://127.0.0.1:#{port}/api/tags")
    {:ok, 200, bytes} = Ipse.HTTPProfile.bounded_request(request, 4096, 1_000)
    {:ok, %{"models" => []}} = Ipse.JSON.decode_bounded(bytes, 4096)
    :ok
  end

  defp fresh_port do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false, reuseaddr: false])

    try do
      {:ok, {{127, 0, 0, 1}, port}} = :inet.sockname(listener)
      port
    after
      :gen_tcp.close(listener)
    end
  end

  defp deadline(milliseconds), do: System.monotonic_time(:millisecond) + milliseconds

  defp case_directory!(root, name) do
    directory = Path.join(root, name)
    private_directory!(directory)
    directory
  end

  defp private_directory!(path) do
    File.mkdir!(path)
    File.chmod!(path, 0o700)
    sync_directory!(Path.dirname(path))
  end

  defp private_file!(path, bytes) do
    File.write!(path, bytes, [:exclusive, :sync])
    File.chmod!(path, 0o600)
    sync_directory!(Path.dirname(path))
  end

  defp sync_directory!(path) do
    {:ok, :ok} = File.open(path, [:read, :raw, :directory], &:file.sync/1)
  end
end
