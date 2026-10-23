defmodule Ipse.MCP.HTTPOwnerCleanupTest do
  use ExUnit.Case, async: false

  test "abnormal SDK owner death confirms HTTP transport cleanup" do
    parent = self()
    {:ok, scope} = Ipse.Session.Resources.start(self())

    owner =
      spawn(fn ->
        {:ok, transport} =
          Ipse.MCP.HTTPTransport.start_link(
            owner: self(),
            server: %{timeout_ms: 5000, url: "http://127.0.0.1:1/mcp", env: %{}},
            cleanup_owner: parent,
            cleanup_scope: scope
          )

        send(parent, {:transport, transport})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:transport, transport}
    monitor = Process.monitor(transport)
    Process.exit(owner, :kill)
    assert_receive {:mcp_cleanup, ^transport, :ok}, 2000
    assert_receive {:DOWN, ^monitor, :process, ^transport, :normal}, 2000
    assert :ok = Ipse.Session.Resources.close(scope)
  end
end
