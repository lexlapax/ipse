# Proposed raw native-owner probe. Its live entry is deliberately disabled;
# running this file with `test` exercises encoding/parsing only. This does not
# use the Elixir Transaction supervisor and cannot qualify its cleanup semantics.
defmodule IpseSerenityNativeProbe do
  @real_enabled false
  @max_frame 8192
  @chunk 16_384
  @planned_size 1_048_576
  @pending ".pending-" <> String.duplicate("a", 32)

  def frame(tag, sequence, depth, extra \\ <<>>) when is_integer(tag) and is_binary(extra) do
    payload = <<sequence::unsigned-big-64, depth::unsigned-8, extra::binary>>
    <<tag::unsigned-8, byte_size(payload)::unsigned-big-32, payload::binary>>
  end

  def commands(lock) when is_binary(lock) do
    [
      frame(?A, 1, 0, lock),
      frame(?B, 2, 1, <<0, 67_108_864::unsigned-big-64>>),
      frame(?W, 3, 1, <<0, 1, @pending::binary, @planned_size::unsigned-big-32>>),
      frame(?D, 4, 1, :binary.copy(<<0x5A>>, @chunk))
    ]
  end

  # Native frames are bounded and must contain one exact tag/sequence/depth.
  # U means possibly attempted effect, not a known refusal or a pass.
  def decode_ack(bytes, expected_tag, sequence, depth) when is_binary(bytes) do
    case bytes do
      <<tag, size::unsigned-big-32, payload::binary-size(size)>> when size <= @max_frame ->
        case payload do
          <<^sequence::unsigned-big-64, ^depth::unsigned-8>> when tag == expected_tag ->
            :ok

          <<^sequence::unsigned-big-64, ^depth::unsigned-8, code::unsigned-8>> when tag == ?U ->
            {:unknown, code}

          <<^sequence::unsigned-big-64, ^depth::unsigned-8, code::unsigned-8>> when tag == ?E ->
            {:refused, code}

          _ ->
            {:error, :mismatched_ack}
        end

      _ ->
        {:error, :bad_frame}
    end
  end

  def test_vectors do
    import ExUnit.Assertions
    lock = "/fixture/transaction/.lock"
    [a, b, w, d] = commands(lock)
    assert <<?A, len::unsigned-big-32, 1::unsigned-big-64, 0, ^lock::binary>> = a
    assert len == 9 + byte_size(lock)
    assert <<?B, 18::unsigned-big-32, 2::unsigned-big-64, 1, 0, 67_108_864::unsigned-big-64>> = b

    assert <<?W, 56::unsigned-big-32, 3::unsigned-big-64, 1, 0, 1, pending::binary-size(41),
             @planned_size::unsigned-big-32>> = w

    assert pending == @pending
    assert <<?D, 16_393::unsigned-big-32, 4::unsigned-big-64, 1, data::binary-size(16_384)>> = d
    assert data == :binary.copy(<<0x5A>>, @chunk)
    assert decode_ack(frame(?D, 4, 1), ?D, 4, 1) == :ok
    assert decode_ack(frame(?U, 5, 1, <<4>>), ?D, 5, 1) == {:unknown, 4}
    assert decode_ack(frame(?E, 5, 1, <<4>>), ?D, 5, 1) == {:refused, 4}
    assert decode_ack(frame(?D, 5, 1), ?D, 4, 1) == {:error, :mismatched_ack}
    assert decode_ack(frame(?D, 4, 1) <> <<0>>, ?D, 4, 1) == {:error, :bad_frame}
    assert decode_ack(<<?D, 0, 0, 0, 9, 0>>, ?D, 4, 1) == {:error, :bad_frame}
    :ok
  end

  def run(helper, expected_sha256, lock) do
    if @real_enabled do
      proposed_raw_run(helper, expected_sha256, lock)
    else
      {:error, :live_probe_not_reviewed}
    end
  end

  # Review prototype only. The process that opens this port is the raw native
  # owner, but this bypasses Ipse.Runner's supervisor and therefore exercises no
  # supervisor/Session cleanup. The external controller must prove its fixture
  # mount and helper identities, cap lifetime/memory, and collect cleanup ACKs.
  defp proposed_raw_run(helper, expected_sha256, lock) do
    with true <- Path.type(helper) == :absolute and Path.type(lock) == :absolute,
         true <- Path.basename(lock) == ".lock",
         true <- Regex.match?(~r/\A[0-9a-f]{64}\z/, expected_sha256),
         {:ok, bytes} <- File.read(helper),
         actual <- Base.encode16(:crypto.hash(:sha256, bytes), case: :lower),
         true <- actual == expected_sha256 do
      port =
        Port.open(
          {:spawn_executable, String.to_charlist(helper)},
          [:binary, :exit_status, args: [~c"--transaction-lock", ~c"120000"]]
        )

      try do
        [a, b, w, d] = commands(lock)

        with :ok <- exchange(port, a, ?A, 1, 1),
             :ok <- exchange(port, b, ?B, 2, 1),
             :ok <- exchange(port, w, ?W, 3, 1),
             :ok <- exchange(port, d, ?D, 4, 1) do
          IO.puts("RAW_OWNER_PARTIAL_STAGED")
          # Only an independently synchronized controller may signal this after
          # confirming the exact mapper and active error table. A mere timeout,
          # malformed signal or EOF never sends more native commands.
          case IO.gets("") do
            "FAULT_INSTALLED\n" -> finish_after_fault(port, 5, @planned_size - @chunk)
            _ -> {:error, :controller_handshake_unconfirmed}
          end
        end
      after
        if Port.info(port) != nil, do: Port.close(port)
      end
    else
      _ -> {:error, :fixture_identity_refused}
    end
  end

  defp finish_after_fault(_, _, 0), do: {:error, :fault_not_observed}

  defp finish_after_fault(port, sequence, remaining) do
    count = min(remaining, @chunk)

    result =
      exchange(port, frame(?D, sequence, 1, :binary.copy(<<0x5A>>, count)), ?D, sequence, 1)

    case result do
      :ok -> finish_after_fault(port, sequence + 1, remaining - count)
      {:unknown, 4} -> {:observed, :native_io_uncertain}
      other -> {:error, {:unexpected_native_outcome, other}}
    end
  end

  defp exchange(port, bytes, tag, sequence, depth) do
    if Port.command(port, bytes),
      do:
        read_frame(port, <<>>, System.monotonic_time(:millisecond) + 5_000, tag, sequence, depth),
      else: {:error, :native_command_unavailable}
  rescue
    _ -> {:error, :native_command_unavailable}
  end

  defp read_frame(port, buffer, deadline, tag, sequence, depth) do
    case buffer do
      <<_, size::unsigned-big-32, _::binary>> when size > @max_frame ->
        {:error, :bad_frame}

      <<_, size::unsigned-big-32, payload::binary>> when byte_size(payload) >= size ->
        decode_ack(buffer, tag, sequence, depth)

      _ ->
        remaining = deadline - System.monotonic_time(:millisecond)

        if remaining <= 0 do
          {:error, :native_response_timeout}
        else
          receive do
            {^port, {:data, bytes}} when byte_size(buffer) + byte_size(bytes) <= @max_frame + 5 ->
              read_frame(port, buffer <> bytes, deadline, tag, sequence, depth)

            {^port, {:exit_status, _}} ->
              {:error, :native_owner_lost}
          after
            remaining -> {:error, :native_response_timeout}
          end
        end
    end
  end
end

case System.argv() do
  ["test"] ->
    :ok = IpseSerenityNativeProbe.test_vectors()
    IO.puts("native protocol mock: passed")

  ["run", helper, expected_sha256, lock] ->
    IO.inspect(IpseSerenityNativeProbe.run(helper, expected_sha256, lock))
    System.halt(1)

  _ ->
    IO.puts(:stderr, "usage: elixir native_probe.exs test | run HELPER EXPECTED_SHA256 LOCK")
    System.halt(2)
end
