Code.require_file("../../../dev/fixtures/synthetic_ollama.exs", __DIR__)

defmodule Ipse.Development.SyntheticOllamaLifecycleTest do
  use ExUnit.Case, async: false
  alias Ipse.Development.SyntheticOllama

  defp available_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  defp connect(port) do
    :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 1_000)
  end

  defp post(socket, body) do
    :gen_tcp.send(
      socket,
      "POST /api/chat HTTP/1.1\r\ncontent-length: #{byte_size(body)}\r\n\r\n" <> body
    )
  end

  test "valid loopback request is observed once and the listener closes" do
    port = available_port()
    {:ok, task} = SyntheticOllama.start(port, self(), 1, 1)
    {:ok, socket} = connect(port)

    body =
      Jason.encode!(%{
        "model" => "synthetic",
        "messages" => [
          %{"role" => "user", "content" => SyntheticOllama.prompt(1)},
          %{"role" => "user", "content" => "Native capacity source synthetic"}
        ]
      })

    assert :ok = post(socket, body)
    assert_receive {:synthetic_provider_request, 1, digest, bytes, true}, 2_000
    assert digest == Ipse.JSON.sha256(body) and bytes == byte_size(body)
    assert {:ok, response} = :gen_tcp.recv(socket, 0, 2_000)
    assert response =~ "HTTP/1.1 200 Fixture"
    assert :ok = Task.await(task, 2_000)
    assert {:error, :econnrefused} = connect(port)
    :gen_tcp.close(socket)
  end

  test "malformed request reports a typed fixture error without killing its owner" do
    port = available_port()
    {:ok, task} = SyntheticOllama.start(port, self(), 1, 1)
    {:ok, socket} = connect(port)
    assert :ok = post(socket, "{")
    assert_receive {:synthetic_provider_failure, 1, :invalid_request}, 2_000
    assert {:error, {:synthetic_provider_failure, 1, :invalid_request}} = Task.await(task, 2_000)
    assert Process.alive?(self())
    refute_receive {:synthetic_provider_request, _, _, _, _}, 0
    assert {:error, :econnrefused} = connect(port)
    :gen_tcp.close(socket)
  end

  test "unexpected listener death is monitored rather than linked to its owner" do
    port = available_port()
    {:ok, task} = SyntheticOllama.start(port, self(), 1, 1)
    Process.exit(task.pid, :kill)
    assert_receive {:DOWN, ref, :process, pid, :killed}, 2_000
    assert ref == task.ref and pid == task.pid
    assert Process.alive?(self())
    assert {:error, :econnrefused} = connect(port)
  end

  test "explicit shutdown closes the listener" do
    port = available_port()
    {:ok, task} = SyntheticOllama.start(port, self(), 1, 1)
    assert Task.shutdown(task, :brutal_kill) == nil
    assert {:error, :econnrefused} = connect(port)
  end

  test "normal owner exit stops the listener even with a partial request" do
    port = available_port()
    parent = self()

    {owner, owner_monitor} =
      spawn_monitor(fn ->
        {:ok, task} = SyntheticOllama.start(port, self(), 1, 1)
        send(parent, {:listener_ready, self(), task.pid})
        receive do: (:stop -> :ok)
      end)

    assert_receive {:listener_ready, ^owner, listener}, 2_000
    listener_monitor = Process.monitor(listener)
    {:ok, socket} = connect(port)
    assert :ok = :gen_tcp.send(socket, "POST /api/chat HTTP/1.1\r\ncontent-length: 10\r\n")
    send(owner, :stop)
    assert_receive {:DOWN, ^owner_monitor, :process, ^owner, :normal}, 2_000
    assert_receive {:DOWN, ^listener_monitor, :process, ^listener, :normal}, 2_000
    assert {:error, :econnrefused} = connect(port)
    :gen_tcp.close(socket)
  end

  @tag timeout: 40_000
  test "an idle listener outlives the old 30 second accept deadline" do
    port = available_port()
    {:ok, task} = SyntheticOllama.start(port, self(), 1, 1)
    assert Task.yield(task, 30_500) == nil
    assert Process.alive?(self()) and Process.alive?(task.pid)
    assert Task.shutdown(task, :brutal_kill) == nil
    assert {:error, :econnrefused} = connect(port)
  end
end
