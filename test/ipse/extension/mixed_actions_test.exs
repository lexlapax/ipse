defmodule Ipse.Extension.MixedActionsTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.Actions

  test "mixed counters independently bound every closed read family and other calls" do
    identity = %{"capabilities" => ["host.actions.mixed"]}
    effects = List.duplicate(%{"request" => %{"op" => "mcp.call"}}, 16)

    for op <-
          ~w(state.get state.list state.scan history.read usage.read usage.children usage.child.read effect.result.read) do
      request = %{"op" => op}
      reads = List.duplicate(%{"request" => request}, 512)
      assert Actions.allowed?(identity, request, Enum.take(reads, 511) ++ effects)
      refute Actions.allowed?(identity, request, reads)

      assert Actions.allowed?(
               identity,
               %{"op" => "model.complete"},
               reads ++ Enum.take(effects, 15)
             )

      refute Actions.allowed?(identity, %{"op" => "model.complete"}, reads ++ effects)
      refute Actions.allowed?(identity, request, reads ++ effects)
    end

    for op <-
          ~w(mcp.call model.complete service.call context.publish operator.question tool.call state.put state.delete) do
      refute Actions.allowed?(identity, %{"op" => op}, effects)
    end
  end
end
