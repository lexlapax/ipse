defmodule Ipse.Extension.ObservationLineageBoundaryTest do
  use ExUnit.Case, async: true

  alias Ipse.Extension.Actions

  test "the current action continuation does not carry a host root witness" do
    event = %{
      "parent_invocation_id" => "parent",
      "operation_id" => "operation",
      "step" => 1,
      "request" => %{"op" => "collection.call"},
      "outcome" => %{"status" => "ok", "value" => %{"text" => "synthetic"}},
      "host_observation" => %{"root_sha256" => String.duplicate("a", 64)}
    }

    other = put_in(event, ["host_observation", "root_sha256"], String.duplicate("b", 64))
    assert Actions.resume(event) === Actions.resume(other)
    refute Map.has_key?(Actions.resume(event), "host_observation")
    assert Actions.resume(event)["outcome"] === event["outcome"]
  end

  test "a current action outcome hash cannot distinguish equal data observed under different roots" do
    value = %{"status" => "ok", "value" => %{"text" => "synthetic"}}
    first = %{"outcome" => value, "root_sha256" => String.duplicate("a", 64)}
    second = %{"outcome" => value, "root_sha256" => String.duplicate("b", 64)}
    assert Ipse.JSON.digest([first["outcome"]]) == Ipse.JSON.digest([second["outcome"]])
    refute first["root_sha256"] == second["root_sha256"]
  end
end
