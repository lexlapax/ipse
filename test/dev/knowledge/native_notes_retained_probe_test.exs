Code.require_file("../../../dev/fixtures/synthetic_ollama_retained.exs", __DIR__)
Code.require_file("../../../dev/knowledge/native_notes_retained_probe.ex", __DIR__)

defmodule Ipse.Development.NativeNotesRetainedProbeTest do
  use ExUnit.Case, async: false
  alias Ipse.Development.{NativeNotesRetainedProbe, SyntheticOllamaRetained}
  alias Ipse.Extension.Mode

  test "the read-only ceiling allows knowledge reads and denies publications and ordinary mutations" do
    assert {:ok, mode} =
             Mode.capture(%{
               execution_mode: :read_only,
               enclosing_mode: :read_only,
               approval: :ask,
               approval_origin: :interactive
             })

    assert :ok = Mode.knowledge(mode, "collection.read")
    assert {:error, :knowledge_mode_denied} = Mode.knowledge(mode, "collection.publish")
    assert :deny = Mode.ordinary(mode, true)
  end

  test "the diagnostic refuses an unrelated root before touching it" do
    assert_raise ExUnit.AssertionError, fn ->
      NativeNotesRetainedProbe.main([
        "--run",
        "/tmp/unrelated",
        "/tmp/ipse-retained-readonly-unused"
      ])
    end
  end

  test "the synthetic listener records a real bounded request and emits a local reply" do
    port = free_port()
    assert {:ok, task} = SyntheticOllamaRetained.start(port, self())
    assert {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])

    body =
      Jason.encode!(%{
        "model" => "synthetic",
        "messages" => [
          %{"role" => "user", "content" => SyntheticOllamaRetained.prompt()},
          %{"role" => "system", "content" => "Native capacity source 1: fixture"}
        ]
      })

    request = "POST /api/chat HTTP/1.1\r\ncontent-length: #{byte_size(body)}\r\n\r\n" <> body
    assert :ok = :gen_tcp.send(socket, request)
    assert_receive {:retained_request, hash, size, true}, 5_000
    assert hash == Ipse.JSON.sha256(body) and size == byte_size(body)
    assert {:ok, reply} = :gen_tcp.recv(socket, 0, 5_000)
    assert reply =~ "200 Fixture"
    :gen_tcp.close(socket)
    assert :ok = Task.await(task, 5_000)
  end

  test "the synthetic listener cannot outlive an abnormally stopped owner" do
    port = free_port()
    parent = self()

    {owner, owner_ref} =
      spawn_monitor(fn ->
        {:ok, task} = SyntheticOllamaRetained.start(port, self())
        send(parent, {:listener_task, task.pid})

        receive do
          :stop -> exit(:shutdown)
        end
      end)

    assert_receive {:listener_task, task}, 5_000
    task_ref = Process.monitor(task)
    send(owner, :stop)
    assert_receive {:DOWN, ^owner_ref, :process, ^owner, :shutdown}, 5_000
    assert_receive {:DOWN, ^task_ref, :process, ^task, _}, 5_000
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)
    port
  end
end
