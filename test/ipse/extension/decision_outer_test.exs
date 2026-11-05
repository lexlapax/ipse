defmodule Ipse.Extension.DecisionOuterTest do
  use ExUnit.Case, async: true

  alias Ipse.Extension.Actions

  test "a decision owner cannot lend its outer authority to other effects" do
    parent = %{"semantic_binding" => %{"class" => "decision.create"}}
    read_parent = put_in(parent, ["semantic_binding", "class"], "collection.read")

    allowed = [
      %{"op" => "context.available"},
      %{"op" => "decision.create"},
      %{"op" => "collection.call", "request" => %{"op" => "get", "key" => "note.example"}}
    ]

    denied = [
      %{"op" => "context.available", "instance" => "foreign"},
      %{"op" => "context.publish"},
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

  test "allocation observation keeps its closed shape and independent capability" do
    request = %{"op" => "context.available"}
    parent = %{"semantic_binding" => %{"class" => "decision.create"}}
    nomination = put_in(parent, ["semantic_binding", "class"], "nomination.select")

    assert Actions.allowed_under_outer?(parent, request)
    assert Actions.validate_operation(request) == :ok
    assert Actions.capability(request) == "host.context"
    refute Actions.mutating?(request)
    refute Actions.allowed_under_outer?(nomination, request)
    refute Actions.allowed_under_outer?(parent, Map.put(request, :instance, "foreign"))

    assert Actions.validate_operation(Map.put(request, "instance", "foreign")) ==
             {:error, :invalid_extension_context}
  end
end
