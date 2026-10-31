# Runs only in an isolated BEAM so the deliberately replaced fixture modules
# cannot affect real Sessions or other tests.
Code.compiler_options(ignore_module_conflict: true)

case System.argv() do
  ["observation_failure"] ->
    Code.compile_string(~S'''
    defmodule Mint.HTTP do
      def connect(:http, _host, port, _options) do
        case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 2000) do
          {:ok, socket} -> {:ok, {:fixture, socket}}
          other -> other
        end
      end

      def get_socket(_), do: throw(:synthetic_observation_failure)

      def close({:fixture, socket}) do
        Process.put(:synthetic_close_attempted, true)
        :ok = :gen_tcp.close(socket)
        {:ok, :closed}
      end
    end
    ''')

    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 5000)
        closed = :gen_tcp.recv(socket, 0, 5000)
        :gen_tcp.close(socket)
        :gen_tcp.close(listener)
        closed
      end)

    result =
      Ipse.Provider.MintTransport.stream_socket(
        "http://127.0.0.1:#{port}/mcp",
        [],
        "{}",
        5000,
        4096,
        nil,
        fn _, state -> {:cont, state} end,
        fn send_once -> send_once.(System.system_time(:millisecond) + 3000) end
      )

    unless result == {:unknown, :inference_cleanup_unconfirmed},
      do: raise("incorrect result: #{inspect(result)}")

    unless Process.get(:synthetic_close_attempted), do: raise("opened socket was not closed")

    unless Task.await(server, 5000) == {:error, :closed},
      do: raise("server did not observe closure")

  ["transport_unknown"] ->
    {:ok, _} = Application.ensure_all_started(:ipse)

    Code.compile_string(~S'''
    defmodule Ipse.Session.ManagedToolUse do
      def with_effect(_, _, continuation), do: continuation.(System.system_time(:millisecond) + 3000)
    end

    defmodule SyntheticMCPAuthority do
      use GenServer
      def init(_), do: {:ok, nil}
      def handle_call({:mcp_register, _, _}, _, state), do: {:reply, :ok, state}
    end
    ''')

    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    :ok = :gen_tcp.close(listener)
    {:ok, scope} = Ipse.Session.Resources.start(self())
    {:ok, authority} = GenServer.start(SyntheticMCPAuthority, nil)
    server = %{url: "http://127.0.0.1:#{port}/mcp", timeout_ms: 5000, env: %{}}

    resource = %{
      owner: authority,
      job_ref: make_ref(),
      managed_tool: %{},
      managed_descriptor: %{digest: String.duplicate("a", 64)}
    }

    {:ok, transport} =
      Ipse.MCP.HTTPTransport.start_link(
        owner: self(),
        cleanup_owner: self(),
        cleanup_scope: scope,
        possible_effect: :atomics.new(1, []),
        server: server,
        resource: resource
      )

    :ok = GenServer.call(scope, {:track_task, transport})

    :ok =
      Ipse.MCP.HTTPTransport.send_message(
        transport,
        %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => %{}}
      )

    receive do
      {:mcp_cleanup, ^transport, {:error, :cleanup_unconfirmed}} ->
        :ok

      {:mcp_cleanup, ^transport, other} ->
        raise("unknown connection cleanup upgraded: #{inspect(other)}")
    after
      10_000 -> raise("transport did not close")
    end

    GenServer.stop(authority)
    _ = Ipse.Session.Resources.close(scope)

  _ ->
    raise("unknown fixture mode")
end
