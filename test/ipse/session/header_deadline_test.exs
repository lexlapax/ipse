defmodule Ipse.Session.HeaderDeadlineTest do
  use ExUnit.Case, async: false
  alias Ipse.Runner

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-header-deadline-" <> Ipse.Usage.id())
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "one deadline applies across individually responsive chunks", c do
    {p, trace} = peer(c.root, "slow")
    bytes = :binary.copy("x", 32_768) <> "\n"
    start = System.monotonic_time(:millisecond)
    assert {:ok, _} = Runner.session_header_begin(p, start + 300)

    assert {:error, :header_unconfirmed} =
             Runner.session_header_write(p, bytes, self(), start + 300)

    elapsed = System.monotonic_time(:millisecond) - start
    assert elapsed >= 250 and elapsed < 1_500
    assert File.read!(trace) == "BHD"
  end

  test "a stalled first response consumes the same finite deadline", c do
    {p, trace} = peer(c.root, "stall")
    start = System.monotonic_time(:millisecond)

    assert {:error, :header_unconfirmed} =
             Runner.session_header_write(p, "{}\n", self(), start + 300)

    elapsed = System.monotonic_time(:millisecond) - start
    assert elapsed >= 250 and elapsed < 1_500
    assert File.read!(trace) == "H"
  end

  defp peer(root, mode) do
    trace = Path.join(root, "trace")

    p =
      Port.open({:spawn_executable, System.find_executable("elixir")}, [
        :binary,
        :exit_status,
        :use_stdio,
        args: ["--erl", "+S 1", "dev/fixtures/session_header_slow_peer.exs"],
        env: [
          {~c"IPSE_HEADER_PEER_TRACE", String.to_charlist(trace)},
          {~c"IPSE_HEADER_PEER_MODE", String.to_charlist(mode)}
        ]
      ])

    on_exit(fn -> if Port.info(p), do: Port.close(p) end)
    ready(p, <<>>, System.monotonic_time(:millisecond) + 5_000)
    {p, trace}
  end

  defp ready(_p, <<?R, 0::32>>, _deadline), do: :ok

  defp ready(p, bytes, deadline) when byte_size(bytes) < 5 do
    receive do
      {^p, {:data, data}} when byte_size(bytes) + byte_size(data) <= 5 ->
        ready(p, bytes <> data, deadline)

      {^p, _} ->
        flunk("invalid peer readiness")
    after
      max(deadline - System.monotonic_time(:millisecond), 0) -> flunk("peer readiness timed out")
    end
  end
end
