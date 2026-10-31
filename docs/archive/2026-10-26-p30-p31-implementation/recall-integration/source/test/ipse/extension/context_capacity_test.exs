defmodule Ipse.Extension.ContextCapacityTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.{Actions, Context}
  alias Ipse.Session.Reference

  defp item(text, instance) do
    %{
      "id" => "context",
      "version" => "1",
      "text" => text,
      "priority" => 60,
      "source" => %{"kind" => "assertion", "uri" => nil},
      "provenance" => %{
        "instance" => instance,
        "identity_sha256" => Ipse.JSON.sha256("identity"),
        "operation_id" => Ipse.Usage.id(),
        "source_action_sha256" => nil
      }
    }
  end

  test "capacity excludes the caller's replaced contribution without disclosing other publisher text" do
    other = item("PRIVATE_OTHER_PUBLISHER", "other")
    old = item("OLD_CALLER_CONTRIBUTION", "knowledge")
    contexts = %{"other" => [other], "knowledge" => [old]}
    facts = Context.available(contexts, "knowledge", Reference.layout())
    assert Context.available?(facts)

    assert facts["occupied_other_bytes"] ==
             Context.rendered_bytes(%{"other" => [other]}, Reference.layout())

    assert facts["available_bytes"] + facts["occupied_other_bytes"] == 16_384
    refute Jason.encode!(facts) =~ "PRIVATE_OTHER_PUBLISHER"
    refute Jason.encode!(facts) =~ "OLD_CALLER_CONTRIBUTION"

    assert Context.available(%{"knowledge" => [old]}, "knowledge", Reference.layout())[
             "available_bytes"
           ] == 16_384

    assert Actions.validate_operation(%{"op" => "context.available"}) == :ok
    assert Actions.capability(%{"op" => "context.available"}) == "host.context"
    assert Actions.valid_outcome?(%{"op" => "context.available"}, "ok", facts, nil)
    refute Context.available?(Map.put(facts, "available_bytes", 16_384))
    refute Context.available?(Map.put(facts, "private_text", "not permitted"))
  end

  test "public packing measurement includes exact escaped Reference framing and provenance overhead" do
    admitted = item("quoted \" text\n日本語", "knowledge")
    public = Map.delete(admitted, "provenance")

    assert Context.preview_bytes([public], "knowledge") ==
             Context.rendered_bytes(%{"knowledge" => [admitted]}, Reference.layout())

    assert Context.preview_bytes([public], "knowledge") > byte_size(Jason.encode!(public))

    assert Ipse.Extension.context_rendered_bytes([public], "knowledge") ==
             Context.preview_bytes([public], "knowledge")
  end
end
