defmodule Ipse.Session.InvocationJournalCapacityTest do
  use ExUnit.Case, async: true
  alias Ipse.Session.{DraftLineage, ExactActionFence, Invocation}

  @documents ~w(invoke.command host.actions host.actions.mixed host.collection.store host.tools)
  @state %{id: String.duplicate("a", 32), turn_id: String.duplicate("b", 32), config: %{}}

  defp bound(caps, state \\ %{}),
    do:
      Invocation.journal_bound(
        Map.merge(Map.put(@state, :draft_lineages, []), state),
        %{"capabilities" => caps}
      )

  test "only identities holding the document store capability carry a bound" do
    assert bound(~w(invoke.command host.actions host.actions.mixed host.tools)) == nil
    assert bound(~w(invoke.command host.actions host.collection.read)) == nil
    assert %{events: _, bytes: _} = bound(@documents)
  end

  test "the document bound charges every admitted host call at its enforced record limit" do
    calls = Ipse.Extension.Actions.limit(%{"capabilities" => @documents})
    assert calls == 528
    %{events: events, bytes: bytes} = bound(@documents)
    assert events == 2 + 3 * calls
    # Invocation intent and result, then two 64-KiB action records and one
    # fixed-size withheld receipt per call, each with its newline.
    withheld = div(bytes - 65_537 - 131_073 - calls * 2 * 65_537, calls)
    assert withheld in 1..512
    assert bytes == 65_537 + 131_073 + calls * (2 * 65_537 + withheld)

    # A store identity that also reads Collections may write a 64-KiB managed
    # read receipt per call instead.
    read = bound(@documents ++ ["host.collection.read"])
    assert read.bytes == 65_537 + 131_073 + calls * 3 * 65_537
  end

  test "draft lineage markers and an installed exact fence enlarge the bound" do
    base = bound(@documents)
    calls = 528

    lineage = %{
      "draft_id" => String.duplicate("c", 32),
      "revision" => 1,
      "accepted_turn_id" => String.duplicate("b", 32),
      "accepted_sha256" => String.duplicate("d", 64),
      "input_source_id" => nil,
      "question_ids" => [],
      "answer_source_ids" => [],
      "tool_evidence" => []
    }

    marked = bound(@documents, %{draft_lineages: [lineage]})

    marker =
      DraftLineage.extension_intent(
        @state.id,
        @state.turn_id,
        %{"type" => "extension_invocation_intent"},
        [lineage]
      )

    assert marked.events == base.events + calls + 1
    assert marked.bytes == base.bytes + (calls + 1) * (byte_size(Jason.encode!(marker)) + 1)

    fence = %{
      "version" => 2,
      "operation" => "a" <> String.duplicate("z", 63),
      "identity_sha256" => String.duplicate("e", 64),
      "descriptor_sha256" => String.duplicate("e", 64),
      "arguments_sha256" => String.duplicate("e", 64),
      "request_sha256" => String.duplicate("e", 64)
    }

    assert ExactActionFence.valid?(fence)
    fenced = bound(@documents, %{exact_action_fence: %{fence: fence, attempt: nil}})
    assert fenced.events == base.events + 1
    assert fenced.bytes == base.bytes + 1_025

    parent = %{
      "invocation_id" => String.duplicate("f", 32),
      "identity" => %{"capabilities" => @documents},
      "descriptor" => %{"id" => "build"},
      "payload" => %{
        "session_id" => @state.id,
        "turn_id" => @state.turn_id,
        "arguments" => %{}
      }
    }

    request = %{"op" => fence["operation"]}

    intent = %{
      "parent_invocation_id" => parent["invocation_id"],
      "operation_id" => String.duplicate("0", 32),
      "identity_sha256" => Ipse.JSON.digest([parent["identity"]]),
      "request" => request,
      "request_sha256" => Ipse.JSON.digest([request])
    }

    assert {:attempt, attempt} =
             ExactActionFence.attempt(%{fence: fence, attempt: nil}, parent, intent, @state.id)

    assert byte_size(Jason.encode!(attempt)) + 1 <= 1_025
  end
end
