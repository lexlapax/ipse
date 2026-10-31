defmodule Ipse.MCP.ManagedHTTPCleanupTest do
  use ExUnit.Case, async: false

  alias Ipse.MCP.HTTPTransport
  alias Ipse.Session.Resources

  for shutdown <- [:close, :owner_loss] do
    @tag timeout: 30_000, cleanup_owner_loss: shutdown == :owner_loss
    test "#{shutdown} of an interrupted managed request cannot confirm cleanup" do
      previous_trap = Process.flag(:trap_exit, true)
      previous_scope = Resources.current()
      {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
      {:ok, {_, port}} = :inet.sockname(listener)
      {:ok, scope} = Resources.start(self())
      Resources.bind(scope)
      owner = self()

      # The real controlled peer owns a real socket; state injection isolates the
      # HTTPTransport close branch from Session admission, tested elsewhere.
      task =
        Resources.async(fn ->
          Resources.controlled_owned_effect(
            fn ->
              {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
              send(owner, {:managed_socket_open, self()})
              receive do: (:never -> :ok)
              :gen_tcp.close(socket)
            end,
            10_000
          )
        end)

      assert_receive {:managed_socket_open, peer}, 5000
      {:ok, socket} = :gen_tcp.accept(listener, 5000)
      peer_ref = Process.monitor(peer)
      server = %{timeout_ms: 10_000, url: "http://127.0.0.1:#{port}/mcp", env: %{}}

      transport_owner =
        if unquote(shutdown) == :close,
          do: self(),
          else: spawn(fn -> receive do: (:stop -> :ok) end)

      {:ok, transport} =
        HTTPTransport.start_link(owner: transport_owner, cleanup_owner: self(), server: server)

      :sys.replace_state(transport, &%{&1 | task: task, task_managed: true})

      try do
        if unquote(shutdown) == :close do
          assert {:error, :cleanup_unconfirmed} = HTTPTransport.close(transport)
        else
          Process.exit(transport_owner, :kill)
        end

        assert_receive {:mcp_cleanup, ^transport, {:error, :cleanup_unconfirmed}}, 5000
        refute_receive {:mcp_cleanup, ^transport, :ok}, 50
        assert_receive {:DOWN, ^peer_ref, :process, ^peer, _}, 5000
        assert {:error, :closed} = :gen_tcp.recv(socket, 0, 5000)
      after
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
        if Process.alive?(transport), do: Process.exit(transport, :kill)
        if Process.alive?(task.pid), do: Process.exit(task.pid, :kill)

        if transport_owner != self() and Process.alive?(transport_owner),
          do: Process.exit(transport_owner, :kill)

        _ = Resources.close(scope)
        Resources.bind(previous_scope)
        Process.flag(:trap_exit, previous_trap)
      end
    end
  end

  test "a managed cleanup failure remains unconfirmed after the transport closes" do
    server = %{timeout_ms: 10_000, url: "http://127.0.0.1:1/mcp", env: %{}}

    {:ok, transport} =
      HTTPTransport.start_link(owner: self(), cleanup_owner: self(), server: server)

    ref = make_ref()
    worker = spawn(fn -> receive do: (:stop -> :ok) end)
    :sys.replace_state(transport, &%{&1 | task: %{pid: worker, ref: ref}, task_managed: true})
    send(transport, {ref, {:error, :cleanup_unconfirmed}})

    assert_receive {:mcp_transport_closed, :invalid_http_transport}, 5000
    assert_receive {:mcp_cleanup, ^transport, {:error, :cleanup_unconfirmed}}, 5000
    refute_receive {:mcp_cleanup, ^transport, :ok}, 50
    send(worker, :stop)
  end
end
