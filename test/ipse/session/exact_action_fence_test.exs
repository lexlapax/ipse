defmodule Ipse.Session.ExactActionFenceTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Session.ExactActionFence}

  @session String.duplicate("a", 32)
  @parent_id String.duplicate("b", 32)
  @operation_id String.duplicate("c", 32)

  defp sample do
    parent = %{
      "type" => "extension_invocation_intent",
      "invocation_id" => @parent_id,
      "payload" => %{
        "session_id" => @session,
        "turn_id" => String.duplicate("e", 32),
        "arguments" => %{"key" => "pending.expected"}
      },
      "identity" => %{"artifact_sha256" => JSON.sha256("artifact"), "instance" => "sample"},
      "descriptor" => %{"id" => "assess", "stage" => "invoke.tool"}
    }

    request = %{"op" => "decision.create", "question" => "exact instruction"}

    action = %{
      "type" => "extension_action_intent",
      "parent_invocation_id" => @parent_id,
      "operation_id" => @operation_id,
      "identity_sha256" => JSON.digest([parent["identity"]]),
      "request" => request,
      "request_sha256" => JSON.digest([request])
    }

    fence = %{
      "version" => 2,
      "operation" => "decision.create",
      "identity_sha256" => JSON.digest([parent["identity"]]),
      "descriptor_sha256" => JSON.digest([parent["descriptor"]]),
      "arguments_sha256" => JSON.digest([parent["payload"]["arguments"]]),
      "request_sha256" => JSON.digest([request])
    }

    header = %{
      "type" => "session",
      "metadata" => %{
        "source_layout" => ExactActionFence.layout(),
        "exact_action_fence" => fence
      }
    }

    {header, parent, action, fence}
  end

  test "only a closed host start option with a live owner is accepted" do
    {_, _, _, fence} = sample()
    assert {:ok, nil} = ExactActionFence.option([])
    assert {:ok, ^fence} = ExactActionFence.option(exact_action_fence: fence, owner: self())
    assert {:error, _} = ExactActionFence.option(exact_action_fence: fence)

    assert {:error, _} =
             ExactActionFence.option(
               exact_action_fence: Map.put(fence, "extra", true),
               owner: self()
             )

    assert {:error, _} = ExactActionFence.option(exact_action_fence: nil, owner: self())
    old_fence = fence |> Map.put("version", 1) |> Map.delete("arguments_sha256")
    assert {:error, _} = ExactActionFence.option(exact_action_fence: old_fence, owner: self())

    assert {:error, _} =
             ExactActionFence.header(%{
               "source_layout" => ExactActionFence.layout(),
               "exact_action_fence" => old_fence
             })
  end

  test "the v2 layout and closed fence header must appear together" do
    {header, _, _, fence} = sample()
    assert {:ok, ^fence} = ExactActionFence.header(header["metadata"])
    assert {:ok, nil} = ExactActionFence.header(%{"source_layout" => "session_sources_v1"})

    for metadata <- [
          %{"source_layout" => ExactActionFence.layout()},
          %{"source_layout" => "session_sources_v1", "exact_action_fence" => fence},
          %{"source_layout" => ExactActionFence.layout(), "exact_action_fence" => %{}},
          %{"exact_action_fence" => fence}
        ] do
      assert {:error, _} = ExactActionFence.header(metadata)
    end
  end

  test "resume restores the saved fence before checking delegated policy" do
    {header, _, _, fence} = sample()
    metadata = header["metadata"]

    for requested <- [nil, fence] do
      assert {:ok, config} =
               ExactActionFence.resume_config(metadata, %{
                 subagents: true,
                 exact_action_fence: requested
               })

      assert config.exact_action_fence === fence
      refute Ipse.Tools.Delegation.enabled?(config)
    end

    changed = Map.put(fence, "request_sha256", JSON.sha256("different"))
    assert {:error, _} = ExactActionFence.resume_config(metadata, %{exact_action_fence: changed})

    assert {:error, _} =
             ExactActionFence.resume_config(%{"source_layout" => "session_sources_v1"}, %{
               exact_action_fence: fence
             })

    assert {:ok, config} =
             ExactActionFence.resume_config(%{"source_layout" => "session_sources_v1"}, %{
               subagents: true,
               exact_action_fence: nil
             })

    assert Ipse.Tools.Delegation.enabled?(config)
  end

  test "the composite layout retains source-window admission but rejects missing fence" do
    {header, _, _, _} = sample()
    assert Ipse.Session.SourceWindow.enabled?(%{source_layout: "session_sources_v1"})
    assert Ipse.Session.SourceWindow.enabled?(%{source_layout: ExactActionFence.layout()})
    refute Ipse.Session.SourceWindow.enabled?(%{source_layout: nil})
    assert {:ok, %{admitted: true}} = Ipse.Session.SourceWindow.restore([header], @session)
    missing = update_in(header, ["metadata"], &Map.delete(&1, "exact_action_fence"))
    assert {:error, _} = Ipse.Session.SourceWindow.restore([missing], @session)
  end

  test "one exact action is bound before approval and remains consumed after replay" do
    {header, parent, action, fence} = sample()
    assert {:ok, ready} = ExactActionFence.restore([header, parent], @session)
    assert ready.fence === fence and ready.attempt === nil
    assert {:attempt, attempt} = ExactActionFence.attempt(ready, parent, action, @session)
    assert attempt["matched"] === true
    assert {:ok, spent} = ExactActionFence.restore([header, parent, attempt, action], @session)
    assert ExactActionFence.permitted?(spent, parent, action)
    assert :consumed = ExactActionFence.attempt(spent, parent, action, @session)

    assert {:error, _} =
             ExactActionFence.restore([header, parent, attempt, action, action], @session)

    assert {:error, _} = ExactActionFence.restore([header, parent, action], @session)

    result = Map.put(action, "type", "extension_action_result")

    assert {:ok, _} =
             ExactActionFence.restore([header, parent, attempt, action, result], @session)

    assert {:error, _} = ExactActionFence.restore([header, parent, attempt, result], @session)

    assert {:error, _} =
             ExactActionFence.restore([header, parent, attempt, action, result, result], @session)

    # A crash after the durable attempt and before the action remains consumed.
    assert {:ok, pending} = ExactActionFence.restore([header, parent, attempt], @session)
    assert :consumed = ExactActionFence.attempt(pending, parent, action, @session)
  end

  test "direct source replay refuses attempts and actions after their parent has ended" do
    {header, parent, action, _fence} = sample()
    assert {:ok, ready} = ExactActionFence.restore([header, parent], @session)
    assert {:attempt, attempt} = ExactActionFence.attempt(ready, parent, action, @session)
    ended = %{"type" => "extension_invocation_result", "invocation_id" => @parent_id}
    assert {:ok, _} = ExactActionFence.restore([header, parent, ended], @session)
    assert {:error, _} = ExactActionFence.restore([header, parent, ended, attempt], @session)

    assert {:error, _} =
             Ipse.Session.SourceWindow.restore([header, parent, ended, attempt], @session)

    assert {:error, _} =
             ExactActionFence.restore([header, parent, attempt, ended, action], @session)

    assert {:error, _} = ExactActionFence.restore([header, parent, parent], @session)
    assert {:error, _} = ExactActionFence.restore([header, ended], @session)
  end

  test "cancellation, interrupted turns, new user messages and supersession close the parent" do
    {header, parent, action, _} = sample()
    assert {:ok, ready} = ExactActionFence.restore([header, parent], @session)
    assert {:attempt, attempt} = ExactActionFence.attempt(ready, parent, action, @session)

    for closed <- [
          %{"type" => "cancelled"},
          %{"type" => "turn_finished", "status" => "error"},
          %{"type" => "message", "message" => %{"role" => "user"}},
          %{"type" => "managed_supersession_delivered", "parent_invocation_id" => @parent_id}
        ] do
      assert {:ok, _} = ExactActionFence.restore([header, parent, closed], @session)
      assert {:error, _} = ExactActionFence.restore([header, parent, closed, attempt], @session)

      assert {:error, _} =
               Ipse.Session.SourceWindow.restore([header, parent, closed, attempt], @session)

      assert {:ok, spent} = ExactActionFence.restore([header, parent, attempt, closed], @session)
      assert :consumed = ExactActionFence.attempt(spent, parent, action, @session)
    end

    assert {:error, _} =
             ExactActionFence.restore(
               [header, parent, %{"type" => "turn_finished", "status" => "ok"}],
               @session
             )

    assert {:ok, _} =
             ExactActionFence.restore(
               [header, %{"type" => "turn_finished", "status" => "ok"}],
               @session
             )

    assert {:error, _} =
             ExactActionFence.restore(
               [
                 header,
                 parent,
                 %{
                   "type" => "managed_supersession_delivered",
                   "parent_invocation_id" => String.duplicate("f", 32)
                 }
               ],
               @session
             )
  end

  test "changed request, parent arguments, identity or descriptor cannot authorize an action" do
    {header, parent, action, _} = sample()

    for {different_parent, different_action} <- [
          {parent, put_in(action, ["request", "question"], "changed")},
          {put_in(parent, ["payload", "arguments", "key"], "pending.other"), action},
          {put_in(parent, ["identity", "instance"], "other"), action},
          {put_in(parent, ["descriptor", "id"], "other"), action}
        ] do
      request = different_action["request"]

      different_action =
        different_action
        |> Map.put("request_sha256", JSON.digest([request]))
        |> Map.put("identity_sha256", JSON.digest([different_parent["identity"]]))

      assert {:ok, ready} = ExactActionFence.restore([header, different_parent], @session)

      assert {:attempt, attempt} =
               ExactActionFence.attempt(ready, different_parent, different_action, @session)

      refute attempt["matched"]

      assert {:ok, spent} =
               ExactActionFence.restore([header, different_parent, attempt], @session)

      refute ExactActionFence.permitted?(spent, different_parent, different_action)

      assert :consumed =
               ExactActionFence.attempt(spent, different_parent, different_action, @session)

      assert {:error, _} =
               ExactActionFence.restore(
                 [header, different_parent, attempt, different_action],
                 @session
               )
    end
  end

  test "changed or forged parent arguments fail after a matching attempt and on replay" do
    {header, parent, action, _} = sample()
    assert {:ok, ready} = ExactActionFence.restore([header, parent], @session)
    assert {:attempt, attempt} = ExactActionFence.attempt(ready, parent, action, @session)
    assert {:ok, spent} = ExactActionFence.restore([header, parent, attempt], @session)
    changed = put_in(parent, ["payload", "arguments", "key"], "pending.other")
    refute ExactActionFence.permitted?(spent, changed, action)
    assert {:error, _} = ExactActionFence.restore([header, changed, attempt], @session)
    forged = Map.put(attempt, "arguments_sha256", JSON.digest([changed["payload"]["arguments"]]))
    assert {:error, _} = ExactActionFence.restore([header, parent, forged], @session)
    assert :consumed = ExactActionFence.attempt(spent, changed, action, @session)
    missing = update_in(parent, ["payload"], &Map.delete(&1, "arguments"))
    assert {:error, _} = ExactActionFence.restore([header, missing], @session)
    refute ExactActionFence.permitted?(spent, missing, action)
  end

  test "unrelated operations are untouched and forged attempt histories refuse" do
    {header, parent, action, _} = sample()
    assert {:ok, ready} = ExactActionFence.restore([header, parent], @session)
    other = put_in(action, ["request", "op"], "history.read")
    assert :unrestricted = ExactActionFence.attempt(ready, parent, other, @session)
    assert ExactActionFence.permitted?(ready, parent, other)
    assert {:attempt, attempt} = ExactActionFence.attempt(ready, parent, action, @session)

    for changed <- [
          Map.put(attempt, "matched", false),
          Map.put(attempt, "fence_sha256", JSON.sha256("foreign")),
          Map.put(attempt, "identity_sha256", JSON.sha256("foreign")),
          Map.put(attempt, "session_id", String.duplicate("d", 32)),
          Map.put(attempt, "extra", true)
        ] do
      assert {:error, _} = ExactActionFence.restore([header, parent, changed], @session)
    end

    legacy = %{"type" => "session", "metadata" => %{"source_layout" => "session_sources_v1"}}
    assert {:error, _} = ExactActionFence.restore([legacy, attempt], @session)
  end
end
