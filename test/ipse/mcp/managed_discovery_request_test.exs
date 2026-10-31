defmodule Ipse.MCP.ManagedDiscoveryRequestTest do
  use ExUnit.Case, async: false

  test "only exact host initialization and configured bounded catalog messages qualify" do
    initial = Ipse.MCP.managed_discovery_initialize_params()

    context = %{
      "server" => %{"tools" => ["synthetic"], "resources" => [], "prompts" => ["guide"]},
      "initialize_params" => initial
    }

    initialize = %{"jsonrpc" => "2.0", "id" => 0, "method" => "initialize", "params" => initial}
    notification = %{"jsonrpc" => "2.0", "method" => "notifications/initialized"}
    list = %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list", "params" => %{}}

    for message <- [
          initialize,
          notification,
          list,
          put_in(list, ["params"], %{"cursor" => "next"}),
          %{list | "method" => "prompts/list"}
        ] do
      assert Ipse.MCP.managed_discovery_request?(context, message)
    end

    for message <- [
          put_in(initialize, ["params", "clientInfo", "name"], "other"),
          Map.put(notification, "params", %{}),
          %{list | "method" => "resources/list"},
          %{list | "method" => "tools/call"},
          put_in(list, ["params"], %{"cursor" => String.duplicate("x", 1025)}),
          put_in(list, ["params"], %{"cursor" => "x", "extra" => true}),
          Map.delete(list, "id")
        ] do
      refute Ipse.MCP.managed_discovery_request?(context, message)
    end

    historical = put_in(context, ["initialize_params", "clientInfo", "version"], "0.1.0")

    assert Ipse.MCP.managed_discovery_request?(historical, %{
             initialize
             | "params" => historical["initialize_params"]
           })

    refute Ipse.MCP.managed_discovery_request?(
             put_in(historical, ["initialize_params", "clientInfo", "name"], "other"),
             initialize
           )
  end
end
