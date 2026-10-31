defmodule Ipse.Session.ShareBarrierTest do
  use ExUnit.Case, async: false
  @moduletag skip: if(:os.type() == {:unix, :linux}, do: false, else: "Linux native share")
  alias Ipse.{Journal, Runner}
  alias Ipse.Journal.Writer
  alias Ipse.Session.Lock

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-share-barrier-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  defp start_owned(c) do
    id = Ipse.Usage.id()
    path = Path.join(c.root, id <> ".lock")
    assert {:ok, port} = Lock.acquire_share_header(path)
    guard = Lock.current()
    metadata = %{"source_origin_layout" => Ipse.Journal.SourceOrigin.layout()}
    assert {:ok, ^id} = Journal.create_with_locked_id(c.root, id, metadata, nil, guard)
    assert {:ok, writer} = Writer.start(c.root, id, self(), nil, :header_share_v2)
    assert :ok = Lock.track(writer, :writer)
    assert :ok = Writer.append(writer, %{"type" => "fixture_before"})
    %{id: id, path: path, port: port, guard: guard, writer: writer}
  end

  defp response(request) do
    assert {:reply, value} = :gen_server.receive_response(request, 8_000)
    value
  end

  defp barrier(s, operation) do
    request = Writer.request_share_barrier(s.writer, operation, make_ref(), make_ref())
    assert {:ok, token, snapshot} = response(request)
    assert snapshot.session_id == s.id
    assert snapshot.offset == File.stat!(Path.join(Path.dirname(s.path), s.id <> ".jsonl")).size
    assert :ok = response(Lock.request_share_arm(s.guard, s.writer, token, operation))
    token
  end

  defp finish(s) do
    assert :ok = Writer.close(s.writer)
    assert :ok = Lock.release(s.guard)
  end

  test "writer barrier drains, refuses new mutations, and cancels before export", c do
    s = start_owned(c)
    operation = :crypto.strong_rand_bytes(16)
    token = barrier(s, operation)
    assert {:error, :journal_share_frozen} = Writer.append(s.writer, %{"type" => "forbidden"})

    assert {:error, :journal_write_unconfirmed} =
             Writer.thaw_share_barrier(s.writer, token, operation)

    assert :ok = response(Lock.request_share_cancel(s.guard, token, operation))
    assert :ok = Writer.thaw_share_barrier(s.writer, token, operation)
    assert :ok = Writer.append(s.writer, %{"type" => "fixture_after"})
    finish(s)
    assert {:ok, events} = Journal.load(c.root, s.id)
    refute Enum.any?(events, &(&1["type"] == "forbidden"))
    assert Enum.any?(events, &(&1["type"] == "fixture_after"))
  end

  defp receive_frame(port, kind, buffer \\ <<>>) do
    case buffer do
      <<^kind, length::32, body::binary-size(length)>> ->
        body

      _ ->
        receive do
          {^port, {:data, bytes}} when byte_size(buffer) + byte_size(bytes) <= 256 ->
            receive_frame(port, kind, buffer <> bytes)

          {^port, {:exit_status, status}} ->
            flunk("collector exited before reply: #{status}")
        after
          8_000 -> flunk("collector response timed out")
        end
    end
  end

  @tag :native_sandbox
  test "original header owner stays locked through recipient close, then writer thaws", c do
    s = start_owned(c)
    operation = :crypto.strong_rand_bytes(16)
    token = barrier(s, operation)
    helper = Path.join(to_string(:code.priv_dir(:ipse)), "ipse-runner")

    collector =
      Port.open({:spawn_executable, String.to_charlist(helper)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :hide,
        args: ["--lease-collect-close-v2"]
      ])

    {:os_pid, collector_pid} = Port.info(collector, :os_pid)
    {:os_pid, exporter_pid} = Port.info(s.port, :os_pid)
    stat = File.stat!(s.path)
    name = :crypto.strong_rand_bytes(16)
    secret = :crypto.strong_rand_bytes(32)

    entry =
      <<exporter_pid::32, name::binary, secret::binary, stat.major_device::64, stat.inode::64>>

    init = <<10_000::64, operation::binary, 1, 0, entry::binary>>
    assert Port.command(collector, <<?I, byte_size(init)::32, init::binary>>)

    request =
      <<collector_pid::32, name::binary, secret::binary, stat.major_device::64, stat.inode::64>>

    deadline = System.monotonic_time(:millisecond) + 5_000
    export = response(Lock.request_share_export(s.guard, token, operation, request, deadline))
    IO.inspect(export, label: "EXPORT_RESULT")
    receive do msg -> IO.inspect(msg, label: "COLLECTOR_MESSAGE") after 1000 -> :ok end
    assert export == :ok
    assert receive_frame(collector, ?L) == <<operation::binary, 1>>
    assert {:error, _} = Runner.protected_lock(s.path)
    assert {:error, :journal_share_frozen} = Writer.append(s.writer, %{"type" => "forbidden"})

    assert {:error, :journal_write_unconfirmed} =
             Writer.thaw_share_barrier(s.writer, token, operation)

    assert Port.command(collector, <<?C, operation::binary>>)
    deadline = System.monotonic_time(:millisecond) + 5_000
    assert :ok = response(Lock.request_share_settle(s.guard, token, operation, deadline))
    assert receive_frame(collector, ?C) == <<operation::binary, 1>>
    assert_receive {^collector, {:exit_status, 0}}, 8_000
    assert {:error, _} = Runner.protected_lock(s.path)
    assert :ok = Writer.thaw_share_barrier(s.writer, token, operation)
    assert :ok = Writer.append(s.writer, %{"type" => "fixture_after_share"})
    finish(s)
    assert {:ok, events} = Journal.load(c.root, s.id)
    refute Enum.any?(events, &(&1["type"] == "forbidden"))
    assert Enum.any?(events, &(&1["type"] == "fixture_after_share"))
  end
end
