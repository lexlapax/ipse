defmodule Ipse.StdioRunnerTest do
  use ExUnit.Case, async: false
  alias Ipse.Runner

  setup do
    cwd = Path.join(System.tmp_dir!(), "ipse-stdio-#{System.unique_integer([:positive])}")
    File.mkdir_p!(cwd)
    on_exit(fn -> File.rm_rf!(cwd) end)
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
    script = "(sleep 0.7; printf escaped > background-child) & printf done"
    {:ok, port} = Runner.open_stdio("/bin/sh", ["-c", script], cwd, %{}, 2_000)
    {frames, 0} = collect(port)
    assert stream(frames, ?O) == "done"
    assert completion(frames)["exit_code"] == 0
    Process.sleep(800)
    refute File.exists?(Path.join(cwd, "background-child"))
  end

  test "invalid launch configuration is rejected without starting a process", %{cwd: cwd} do
    assert {:error, _} = Runner.open_stdio("/bin/sh", [17], cwd, %{}, 1_000)
    assert {:error, _} = Runner.open_stdio("/bin/sh", [], cwd, %{"BAD=KEY" => "value"}, 1_000)
    assert {:error, _} = Runner.open_stdio("/bin/sh", [], cwd, %{}, 0)
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
      3_000 -> raise "stdio fixture did not become ready"
    end
  end

  defp collect(port, initial \\ <<>>) do
    receive do
      {^port, {:data, bytes}} -> collect(port, initial <> bytes)
      {^port, {:exit_status, status}} -> {decode(initial, []), status}
      {:EXIT, ^port, reason} -> {[], {:transport_exit, reason}}
    after
      7_000 ->
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
