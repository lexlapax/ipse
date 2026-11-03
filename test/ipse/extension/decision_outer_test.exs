defmodule Ipse.Extension.DecisionOuterTest do
  use ExUnit.Case, async: true

  alias Ipse.Extension.Actions

  test "a decision owner cannot lend its outer authority to other effects" do
    parent = %{"semantic_binding" => %{"class" => "decision.create"}}
    read_parent = put_in(parent, ["semantic_binding", "class"], "collection.read")

    allowed = [
      %{"op" => "decision.create"},
      %{"op" => "collection.call", "request" => %{"op" => "get", "key" => "note.example"}}
    ]

    denied = [
      %{"op" => "collection.call", "request" => %{"op" => "commit"}},
      %{"op" => "collection.managed"},
      %{"op" => "tool.call", "name" => "shell"},
      %{"op" => "tool.call", "name" => "write"},
      %{"op" => "mcp.call"},
      %{"op" => "model.complete"},
      %{"op" => "embedding.create"},
      %{"op" => "state.put"},
      %{"op" => "service.call"},
      %{"op" => "operator.question"},
      %{"op" => "source.read"}
    ]

    assert Enum.all?(allowed, &Actions.allowed_under_outer?(parent, &1))
    refute Enum.any?(denied, &Actions.allowed_under_outer?(parent, &1))
    refute Actions.allowed_under_outer?(read_parent, %{"op" => "decision.create"})
    assert Actions.allowed_under_outer?(read_parent, %{"op" => "source.read"})
  end
end
