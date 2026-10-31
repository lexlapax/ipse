defmodule Ipse.Session.ExportLockTest do
  use ExUnit.Case, async: false

  alias Ipse.{Runner, Session.Lock}
  @moduletag skip: if(:os.type() == {:unix, :linux}, do: false, else: "Linux-only candidate")

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-export-lock-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, path: Path.join(root, String.duplicate("a", 32) <> ".lock")}
  end

  test "initial export-capable holder remains exclusive until owner and tracked peer stop", c do
    parent = self()

    owner =
      spawn(fn ->
        {:ok, port} = Lock.acquire_export_candidate(c.path)
        guard = Lock.current()
        peer = spawn(fn -> receive do: (:stop -> :ok) end)
        worker = spawn(fn -> receive do: (:stop -> :ok) end)
        :ok = Lock.track(peer, :peer)
        :ok = Lock.track(worker, :worker)
        send(parent, {:candidate_ready, self(), guard, peer, worker, port})
        receive do: (:stop -> :ok)
      end)

    assert_receive {:candidate_ready, ^owner, guard, peer, worker, port}, 5_000

    on_exit(fn ->
      if Process.alive?(owner), do: Process.exit(owner, :kill)
      if Process.alive?(peer), do: send(peer, :stop)
      if Process.alive?(worker), do: Process.exit(worker, :kill)
    end)

    guard_ref = Process.monitor(guard)
    owner_ref = Process.monitor(owner)
    worker_ref = Process.monitor(worker)
    initial = File.stat!(c.path)
    assert Port.info(port)
    assert {:error, _} = Runner.protected_lock(c.path)
    assert File.stat!(c.path).inode == initial.inode

    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^owner_ref, :process, ^owner, :killed}, 5_000
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, :killed}, 5_000
    assert Process.alive?(peer)
    assert Process.alive?(guard)
    assert {:error, _} = Runner.protected_lock(c.path)
    assert File.stat!(c.path).inode == initial.inode
    refute_receive {:DOWN, ^guard_ref, :process, ^guard, _}, 100

    send(peer, :stop)
    assert_receive {:DOWN, ^guard_ref, :process, ^guard, :normal}, 5_000
    assert File.stat!(c.path).inode == initial.inode
    assert {:ok, reopened} = Runner.protected_lock(c.path)
    assert :ok = Runner.unlock(reopened)
  end

  test "candidate refuses unsupported names without falling back to a legacy lock", c do
    invalid = Path.join(c.root, "not-a-session.lock")
    assert {:error, _} = Lock.acquire_export_candidate(invalid)
    refute File.exists?(invalid)
    assert {:ok, legacy} = Runner.protected_lock(invalid)
    assert :ok = Runner.unlock(legacy)
  end

  test "candidate confirms its own unexported framed release", c do
    assert {:ok, _port} = Lock.acquire_export_candidate(c.path)
    assert :ok = Lock.release(Lock.current())
    assert {:ok, reopened} = Runner.protected_lock(c.path)
    assert :ok = Runner.unlock(reopened)
  end

  test "candidate reports an exported recipient as unconfirmed until that recipient closes", c do
    fixture = Path.join(c.root, "recipient")

    {_, 0} =
      System.cmd("rustc", [
        "--edition=2021",
        "-D",
        "warnings",
        "dev/fixtures/transaction_lease_export.rs",
        "-o",
        fixture
      ])

    {:ok, port} = Lock.acquire_export_candidate(c.path)
    guard = Lock.current()
    {:os_pid, helper_pid} = Port.info(port, :os_pid)
    stat = File.stat!(c.path)
    name = :crypto.strong_rand_bytes(16)
    secret = :crypto.strong_rand_bytes(32)

    recipient =
      Port.open({:spawn_executable, fixture}, [
        :binary,
        :exit_status,
        :use_stdio,
        args: [
          "--hold-export",
          Base.encode16(name, case: :lower),
          Base.encode16(secret, case: :lower),
          Integer.to_string(helper_pid),
          Integer.to_string(stat.uid),
          Integer.to_string(stat.major_device),
          Integer.to_string(stat.inode)
        ]
      ])

    on_exit(fn -> if Port.info(recipient), do: Port.close(recipient) end)
    {:os_pid, recipient_pid} = Port.info(recipient, :os_pid)
    1 = :erlang.trace(guard, true, [:receive])

    request =
      <<1::unsigned-big-64, 1, recipient_pid::unsigned-big-32, name::binary, secret::binary,
        stat.major_device::unsigned-big-64, stat.inode::unsigned-big-64>>

    assert Port.command(port, <<?X, byte_size(request)::unsigned-big-32, request::binary>>)
    pending = recipient_line(recipient, <<>>, "HELD\n", "CLOSED\n", deadline())

    assert_export_reply(guard, port, <<>>, System.monotonic_time(:millisecond) + 5_000)

    assert {:error, :cleanup_unconfirmed} = Lock.release(guard)
    assert {:error, _} = Runner.protected_lock(c.path)
    assert Port.command(recipient, "C")
    assert <<>> = recipient_line(recipient, pending, "CLOSED\n", "", deadline())
    recipient_exit(recipient, deadline())
    assert {:ok, reopened} = Runner.protected_lock(c.path)
    assert :ok = Runner.unlock(reopened)
  end

  test "candidate release requires the complete exact frame, clean exit and owning caller" do
    previous = Process.flag(:trap_exit, true)
    on_exit(fn -> Process.flag(:trap_exit, previous) end)

    for {body, expected} <- [
          {~S|IO.binwrite(:stdio, <<?U, 8::32>>); :timer.sleep(20); IO.binwrite(:stdio, "unlocked")|,
           :ok},
          {~S|IO.binwrite(:stdio, <<?U, 8::32, "unlock">>)|, {:error, :cleanup_unconfirmed}},
          {~S|IO.binwrite(:stdio, <<?U, 8::32, "un">>); :timer.sleep(2500)|,
           {:error, :cleanup_unconfirmed}},
          {"IO.binwrite(:stdio, <<?E, 1::32, 1>>)", {:error, :cleanup_unconfirmed}},
          {~S|IO.binwrite(:stdio, <<?U, 8::32, "unlocked", 0>>)|, {:error, :cleanup_unconfirmed}},
          {~S|IO.binwrite(:stdio, <<?U, 8::32, "unlocked">>); System.halt(1)|,
           {:error, :cleanup_unconfirmed}}
        ] do
      script = "IO.binread(:stdio, 5); " <> body

      port =
        Port.open({:spawn_executable, System.find_executable("elixir")}, [
          :binary,
          :exit_status,
          :use_stdio,
          args: ["--erl", "+S 1", "-e", script]
        ])

      parent = self()
      spawn(fn -> send(parent, {:foreign_release, Runner.unlock_export_candidate(port)}) end)
      assert_receive {:foreign_release, {:error, :cleanup_unconfirmed}}, 1_000
      assert Port.info(port)
      assert Runner.unlock_export_candidate(port) == expected
    end
  end

  test "owner loss does not release the exported recipient's lock", c do
    fixture = Path.join(c.root, "recipient")

    {_, 0} =
      System.cmd("rustc", [
        "--edition=2021",
        "-D",
        "warnings",
        "dev/fixtures/transaction_lease_export.rs",
        "-o",
        fixture
      ])

    parent = self()

    owner =
      spawn(fn ->
        {:ok, port} = Lock.acquire_export_candidate(c.path)
        send(parent, {:owner_ready, self(), Lock.current(), port})
        receive do: (:stop -> :ok)
      end)

    assert_receive {:owner_ready, ^owner, guard, port}, 5_000
    guard_ref = Process.monitor(guard)
    {:os_pid, helper_pid} = Port.info(port, :os_pid)
    stat = File.stat!(c.path)
    name = :crypto.strong_rand_bytes(16)
    secret = :crypto.strong_rand_bytes(32)

    recipient =
      Port.open({:spawn_executable, fixture}, [
        :binary,
        :exit_status,
        :use_stdio,
        args: [
          "--hold-export",
          Base.encode16(name, case: :lower),
          Base.encode16(secret, case: :lower),
          Integer.to_string(helper_pid),
          Integer.to_string(stat.uid),
          Integer.to_string(stat.major_device),
          Integer.to_string(stat.inode)
        ]
      ])

    on_exit(fn ->
      if Process.alive?(owner), do: Process.exit(owner, :kill)
      if Port.info(recipient), do: Port.close(recipient)
    end)

    {:os_pid, recipient_pid} = Port.info(recipient, :os_pid)
    1 = :erlang.trace(guard, true, [:receive])

    request =
      <<1::unsigned-big-64, 1, recipient_pid::unsigned-big-32, name::binary, secret::binary,
        stat.major_device::unsigned-big-64, stat.inode::unsigned-big-64>>

    assert Port.command(port, <<?X, byte_size(request)::unsigned-big-32, request::binary>>)
    pending = recipient_line(recipient, <<>>, "HELD\n", "CLOSED\n", deadline())

    assert_export_reply(guard, port, <<>>, System.monotonic_time(:millisecond) + 5_000)

    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^guard_ref, :process, ^guard, :normal}, 5_000
    assert {:error, _} = Runner.protected_lock(c.path)
    assert Port.command(recipient, "C")
    assert <<>> = recipient_line(recipient, pending, "CLOSED\n", "", deadline())
    recipient_exit(recipient, deadline())
    assert {:ok, reopened} = Runner.protected_lock(c.path)
    assert :ok = Runner.unlock(reopened)
  end

  defp assert_export_reply(guard, port, buffer, deadline) do
    expected = <<?X, 10::unsigned-big-32, 1::unsigned-big-64, 1, 0>>

    if buffer != expected do
      assert byte_size(buffer) < byte_size(expected)
      assert binary_part(expected, 0, byte_size(buffer)) == buffer

      receive do
        {:trace, ^guard, :receive, {^port, {:data, bytes}}} ->
          assert_export_reply(guard, port, buffer <> bytes, deadline)
      after
        max(deadline - System.monotonic_time(:millisecond), 0) ->
          flunk("export response was not observed")
      end
    end
  end

  test "recipient stream accepts fragmented and coalesced exact lines and rejects extra bytes" do
    previous = Process.flag(:trap_exit, true)
    on_exit(fn -> Process.flag(:trap_exit, previous) end)

    for script <- [
          ~S|IO.binwrite(:stdio, "HELD\nCLOSED\n")|,
          ~S|IO.binwrite(:stdio, "HE"); :timer.sleep(20); IO.binwrite(:stdio, "LD\nCLO"); :timer.sleep(20); IO.binwrite(:stdio, "SED\n")|
        ] do
      port = fixture_port(script)
      pending = recipient_line(port, <<>>, "HELD\n", "CLOSED\n", deadline())
      assert <<>> = recipient_line(port, pending, "CLOSED\n", "", deadline())
      recipient_exit(port, deadline())
    end

    port = fixture_port(~S|IO.binwrite(:stdio, "HELD\nCLOSED\nEXTRA")|)

    assert_raise ExUnit.AssertionError, fn ->
      pending = recipient_line(port, <<>>, "HELD\n", "CLOSED\n", deadline())
      recipient_line(port, pending, "CLOSED\n", "", deadline())
      recipient_exit(port, deadline())
    end

    if Port.info(port), do: Port.close(port)
  end

  test "candidate release refuses missing and dead Ports" do
    assert {:error, :cleanup_unconfirmed} = Runner.unlock_export_candidate(nil)
    port = fixture_port(":ok")
    assert_receive {^port, {:exit_status, 0}}, 5_000
    assert {:error, :cleanup_unconfirmed} = Runner.unlock_export_candidate(port)
  end

  defp fixture_port(script) do
    Port.open({:spawn_executable, System.find_executable("elixir")}, [
      :binary,
      :exit_status,
      :use_stdio,
      args: ["--erl", "+S 1", "-e", script]
    ])
  end

  defp deadline, do: System.monotonic_time(:millisecond) + 5_000

  defp recipient_line(port, buffer, expected, next, deadline) do
    allowed = expected <> next

    if byte_size(buffer) > byte_size(allowed) or
         binary_part(allowed, 0, byte_size(buffer)) != buffer do
      flunk("recipient emitted unexpected output")
    end

    if byte_size(buffer) >= byte_size(expected) do
      binary_part(buffer, byte_size(expected), byte_size(buffer) - byte_size(expected))
    else
      receive do
        {^port, {:data, bytes}} when byte_size(buffer) + byte_size(bytes) <= byte_size(allowed) ->
          recipient_line(port, buffer <> bytes, expected, next, deadline)

        {^port, {:data, _}} ->
          flunk("recipient output exceeded its bound")

        {^port, {:exit_status, _}} ->
          flunk("recipient exited before the expected line")
      after
        max(deadline - System.monotonic_time(:millisecond), 0) ->
          flunk("recipient output timed out")
      end
    end
  end

  defp recipient_exit(port, deadline) do
    receive do
      {^port, {:exit_status, 0}} -> :ok
      {^port, {:exit_status, _}} -> flunk("recipient exited unsuccessfully")
      {^port, {:data, _}} -> flunk("recipient emitted trailing bytes")
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        flunk("recipient did not exit")
    end
  end
end
