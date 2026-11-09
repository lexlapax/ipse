defmodule Ipse.Runner.StdioAdmissionTest do
  use ExUnit.Case, async: false
  # Managed stdio startup admission is Linux-only; macOS refuses --admitted-stdio.
  @moduletag skip:
               if(:os.type() == {:unix, :linux}, do: false, else: "Linux managed stdio startup")
  alias Ipse.Runner

  @tag timeout: 30_000
  test "native stdio grants the actual start and acknowledges deadline-bound pipe writes" do
    root = Path.join(System.tmp_dir!(), "ipse-stdio-admit-" <> Ipse.Usage.id())
    File.mkdir!(root)
    marker = Path.join(root, "started")
    Process.flag(:trap_exit, true)

    assert {:ok, port} =
             Runner.open_stdio(
               "/bin/sh",
               ["-c", "printf started > \"$1\"; exec /bin/cat", "fixture", marker],
               root,
               %{},
               10_000,
               protected_supervisor: true,
               admit_start: true
             )

    try do
      {frames, buffer} = await_frames(port, <<>>, [], &Enum.member?(&1, {?R, <<>>}))
      assert frames == [{?R, <<>>}]
      refute File.exists?(marker)
      assert :ok = Runner.grant_stdio_start(port, System.system_time(:millisecond) + 3000)
      {_, buffer} = await_frames(port, buffer, [], &Enum.member?(&1, {?A, <<>>}))
      await_file(marker, System.monotonic_time(:millisecond) + 3000)

      expired = :crypto.strong_rand_bytes(16)

      assert :ok =
               Runner.send_stdio_before(
                 port,
                 "expired\n",
                 System.system_time(:millisecond),
                 expired
               )

      {frames, buffer} = await_frames(port, buffer, [], &Enum.member?(&1, {?A, expired <> <<0>>}))
      refute Enum.any?(frames, fn {kind, _} -> kind == ?O end)

      live = :crypto.strong_rand_bytes(16)

      assert :ok =
               Runner.send_stdio_before(
                 port,
                 "current\n",
                 System.system_time(:millisecond) + 3000,
                 live
               )

      {frames, _} =
        await_frames(port, buffer, [], fn frames ->
          Enum.member?(frames, {?A, live <> <<1>>}) and
            Enum.any?(frames, &match?({?O, "current\n"}, &1))
        end)

      assert Enum.count(frames, &(&1 == {?A, live <> <<1>>})) == 1
      assert :ok = Runner.close_stdio(port, :cancel)
    after
      close_port(port)
    end
  end

  @tag timeout: 30_000
  test "expired startup grant never runs the configured server" do
    root = Path.join(System.tmp_dir!(), "ipse-stdio-refuse-" <> Ipse.Usage.id())
    File.mkdir!(root)
    marker = Path.join(root, "started")
    Process.flag(:trap_exit, true)

    assert {:ok, port} =
             Runner.open_stdio(
               "/bin/sh",
               ["-c", "printf started > \"$1\"", "fixture", marker],
               root,
               %{},
               10_000,
               protected_supervisor: true,
               admit_start: true
             )

    try do
      {_, _} = await_frames(port, <<>>, [], &Enum.member?(&1, {?R, <<>>}))
      assert :ok = Runner.grant_stdio_start(port, System.system_time(:millisecond))
      assert_receive {^port, {:exit_status, _}}, 5000
      refute File.exists?(marker)
    after
      close_port(port)
    end
  end

  defp await_file(path, deadline) do
    cond do
      File.exists?(path) ->
        assert File.read!(path) == "started"

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("server did not start")

      true ->
        Process.sleep(5)
        await_file(path, deadline)
    end
  end

  defp await_frames(port, buffer, frames, predicate),
    do: await_frames(port, buffer, frames, predicate, System.monotonic_time(:millisecond) + 5000)

  defp await_frames(port, buffer, frames, predicate, deadline) do
    {parsed, buffer} = parse(buffer, [])
    frames = frames ++ parsed

    if predicate.(frames) do
      {frames, buffer}
    else
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {^port, {:data, bytes}} ->
          await_frames(port, buffer <> bytes, frames, predicate, deadline)

        {^port, {:exit_status, status}} ->
          flunk("native supervisor exited before expected frame: #{status}")
      after
        remaining -> flunk("native supervisor did not emit the expected frame")
      end
    end
  end

  defp parse(<<kind, size::unsigned-big-32, rest::binary>>, frames)
       when byte_size(rest) >= size do
    <<body::binary-size(^size), tail::binary>> = rest
    parse(tail, frames ++ [{kind, body}])
  end

  defp parse(rest, frames), do: {frames, rest}

  defp close_port(port) do
    if Port.info(port), do: Port.close(port)
  rescue
    _ -> :ok
  end
end
