defmodule Ipse.RunnerStorageFramingTest do
  use ExUnit.Case, async: false

  setup_all do
    path = Path.expand("../../lib/ipse/runner.ex", __DIR__)

    wrapper = ~S'''
    def staging_fixture(port, bytes) do
      deadline = System.monotonic_time(:millisecond) + 1000
      case staging_control(port, deadline, nil, bytes, ?A) do
        {:ok, rest} -> staging_receive(port, deadline, nil, rest)
        :ok -> staging_receive(port, deadline, nil, "")
        error -> error
      end
    end
    '''

    path
    |> File.read!()
    |> String.replace("defmodule Ipse.Runner do", "defmodule Ipse.Test.StagingProtocol do",
      global: false
    )
    |> String.replace("  @root ", wrapper <> "\n  @root ", global: false)
    |> Code.compile_string(path <> ":framing_fixture")

    :ok
  end

  defp exited_port do
    Process.flag(:trap_exit, true)
    port = Port.open({:spawn_executable, System.find_executable("true")}, [:binary, :exit_status])

    # Retain the real OS receipt behind a previously received data buffer. The
    # parser must not requeue that buffer after the already queued exit receipt.
    receive do
      {^port, {:exit_status, 0}} = receipt -> send(self(), receipt)
    after
      1000 -> flunk("actual fixture process did not terminate")
    end

    port
  end

  defp frames(result) do
    body = Jason.encode!(result)
    <<?O, 1::32, ?A, ?X, byte_size(body)::32, body::binary>>
  end

  test "coalesced final acknowledgement and terminal frame survive an already queued real OS exit" do
    port = exited_port()
    bytes = frames(%{"exit_code" => 0, "timed_out" => false})
    assert :ok = apply(Ipse.Test.StagingProtocol, :staging_fixture, [port, bytes])
  end

  test "carrying a terminal frame does not weaken failure or closed-schema checks" do
    for result <- [
          %{"exit_code" => 1, "timed_out" => false},
          %{"exit_code" => 0, "timed_out" => true},
          %{"exit_code" => 0, "timed_out" => false, "unreviewed" => true}
        ] do
      assert {:error, :protected_staging_write_unavailable} =
               apply(Ipse.Test.StagingProtocol, :staging_fixture, [exited_port(), frames(result)])
    end
  end
end
