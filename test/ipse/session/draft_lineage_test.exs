defmodule Ipse.Session.DraftLineageTest do
  use ExUnit.Case, async: true
  alias Ipse.Session.DraftLineage
  alias Ipse.Usage

  test "accepted lineage is bounded and remains after projection rebase" do
    session = Usage.id()

    events =
      for _ <- 1..16, reduce: [] do
        acc ->
          id = Usage.id()

          accepted = %{
            "type" => "draft_accepted",
            "version" => 2,
            "draft_id" => id,
            "revision" => 1,
            "input_source_id" => Usage.id(),
            "question_ids" => [],
            "answer_source_ids" => [],
            "tool_evidence" => []
          }

          acc ++
            [
              accepted,
              %{
                "type" => "draft_consumed",
                "draft_id" => id,
                "accepted_turn_id" => Usage.id(),
                "session_id" => session
              },
              %{"type" => "draft_rebased"}
            ]
      end

    assert {:ok, lineages} = DraftLineage.restore(events, session)
    assert length(lineages) == 16
    [accepted, consumed, _] = Enum.take(events, 3)

    assert {:error, :invalid_draft_lineage} =
             DraftLineage.restore(events ++ [accepted, consumed], session)
  end

  test "extension helper intent requires a matching prior lineage marker" do
    session = Usage.id()
    id = Usage.id()
    turn = Usage.id()

    accepted = %{
      "type" => "draft_accepted",
      "version" => 2,
      "draft_id" => id,
      "revision" => 1,
      "input_source_id" => Usage.id(),
      "question_ids" => [],
      "answer_source_ids" => [],
      "tool_evidence" => []
    }

    consumed = %{
      "type" => "draft_consumed",
      "draft_id" => id,
      "accepted_turn_id" => turn,
      "session_id" => session
    }

    target = %{"type" => "extension_action_intent", "request" => %{"op" => "model.complete"}}
    lineage = DraftLineage.entry(accepted, turn)
    marker = DraftLineage.extension_intent(session, turn, target, [lineage])
    prefix = [accepted, consumed, %{"type" => "input_received", "turn_id" => turn}]
    assert {:ok, [^lineage]} = DraftLineage.restore(prefix ++ [marker, target], session)
    assert {:error, :invalid_draft_lineage} = DraftLineage.restore(prefix ++ [target], session)

    assert {:error, :invalid_draft_lineage} =
             DraftLineage.restore(
               prefix ++ [marker, Map.put(target, "request", %{"op" => "tool.call"})],
               session
             )
  end
end
