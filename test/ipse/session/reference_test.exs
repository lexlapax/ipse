defmodule Ipse.Session.ReferenceTest do
  use ExUnit.Case, async: true
  alias Ipse.Session.{Reference, Saved, Context}

  @session String.duplicate("a", 32)
  @turn String.duplicate("b", 32)
  @next String.duplicate("c", 32)
  @header [
    %{"role" => "system", "content" => "fixed rules"},
    %{"role" => "user", "content" => "admitted sources"}
  ]
  @publishers %{
    "runtime" => %{"reported_model" => nil},
    "skills" => "",
    "workspace" => "workspace",
    "extensions" => ""
  }
  @metadata %{"type" => "session", "metadata" => %{"reference_layout" => "turn_reference_v1"}}
  @user %{"role" => "user", "content" => "actual request"}

  defp initial do
    {:ok, state} = Reference.restore([@metadata], @session)
    Reference.seed(state, @header, @publishers)
  end

  defp admitted do
    {:ok, [event], state, []} =
      Reference.prepare(initial(), @session, @turn, @publishers, [], [@user])

    {event, state}
  end

  defp changed, do: put_in(@publishers, ["runtime", "reported_model"], "actual-backend")

  defp committed_input(turn \\ @turn, text \\ @user["content"]),
    do: [
      Ipse.Session.Input.received(@session, turn, text, text, nil),
      %{"type" => "message", "message" => %{"role" => "user", "content" => text}}
    ]

  test "admission freezes the header and ordered tools without a redundant reference message" do
    {event, state} = admitted()
    assert state.header == @header
    assert state.epoch == 1
    assert event["catalog_sha256"] == Ipse.JSON.digest([])

    assert {:ok, [], ^state, []} =
             Reference.prepare(state, @session, @turn, @publishers, [], [@user])

    assert {:error, :reference_catalog_or_history_changed} =
             Reference.prepare(state, @session, @turn, @publishers, [%{"name" => "new"}], [@user])

    assert {:ok, restored} = Reference.restore([@metadata, event], @session)
    assert restored == state
  end

  test "changed references append after native groups and repeat a full current selection each real turn" do
    {admission, state} = admitted()

    assistant = %{
      "role" => "assistant",
      "content" => "",
      "tool_calls" => [
        %{
          "id" => "x",
          "type" => "function",
          "function" => %{"name" => "read", "arguments" => "{}"}
        }
      ],
      "provider_data" => %{"signed" => "opaque-continuation"}
    }

    tool = %{"role" => "tool", "tool_call_id" => "x", "content" => "observed"}
    history = [@user, assistant, tool]

    assert {:ok, [event], next, [message]} =
             Reference.prepare(state, @session, @turn, changed(), [], history)

    assert message["role"] == "user"
    assert Reference.reference?(message)
    assert event["position"] == 3
    assert event["source_generation"] == 1
    assert next.header == state.header
    assert {:ok, projected} = Reference.project(history, event)
    assert Enum.take(projected, 3) == history

    assert {:ok, [], ^next, []} =
             Reference.prepare(next, @session, @turn, changed(), [], projected)

    assert {:ok, [repeated], _, [again]} =
             Reference.prepare(next, @session, @next, changed(), [], projected ++ [@user])

    assert repeated["source_generation"] == 1
    assert again["content"] == message["content"]

    assert {:ok, ^next} =
             Reference.restore([@metadata, admission] ++ committed_input() ++ [event], @session)
  end

  test "clearing a reference is explicit once, then the admitted baseline applies" do
    {_, state} = admitted()
    {:ok, _, next, [changed]} = Reference.prepare(state, @session, @turn, changed(), [], [@user])

    assert {:ok, [event], cleared, [message]} =
             Reference.prepare(next, @session, @turn, @publishers, [], [@user, changed])

    assert message["content"] =~ ~s({"publishers":{}})
    assert event["source_generation"] == 2

    assert {:ok, [], ^cleared, []} =
             Reference.prepare(cleared, @session, @next, @publishers, [], [
               @user,
               changed,
               message,
               @user
             ])
  end

  test "ordered native groups cannot be split, even when the sets would balance" do
    call = %{"role" => "assistant", "tool_calls" => [%{"id" => "x"}]}
    result = %{"role" => "tool", "tool_call_id" => "x", "content" => "done"}
    assert Reference.safe_tail?([@user, call, result])

    for messages <- [
          [call],
          [result, call],
          [call, @user, result],
          [call, call, result],
          [%{"role" => "assistant", "tool_calls" => [false]}],
          [%{"role" => "assistant", "tool_calls" => [%{"id" => ""}]}],
          nil
        ] do
      refute Reference.safe_tail?(messages)
    end

    {_, state} = admitted()
    assert {:error, _} = Reference.prepare(state, @session, @turn, changed(), [], [call])
  end

  test "refresh and compaction establish explicit epochs, with identical headers between them" do
    {admission, state} = admitted()
    assert {:ok, compact, compacted} = Reference.compacted(state, @session)
    assert compacted.header == @header
    assert compacted.epoch == 2
    header = [%{"role" => "system", "content" => "reviewed rules"}, List.last(@header)]
    assert {:ok, refresh, pending} = Reference.refresh(compacted, @session, header, changed())
    assert pending.header == @header

    assert {:ok, [new], selected, []} =
             Reference.prepare(pending, @session, @next, changed(), [%{"name" => "reviewed"}], [
               @user
             ])

    assert new["reason"] == "context_refresh"
    assert new["epoch"] == 3
    assert selected.header == header

    assert {:ok, ^selected} =
             Reference.restore([@metadata, admission, compact, refresh, new], @session)
  end

  test "replay rejects altered hashes, identity, counters, duplicate envelopes and unknown fields" do
    {admission, state} = admitted()
    {:ok, [event], _, _} = Reference.prepare(state, @session, @turn, changed(), [], [@user])

    for bad <- [
          Map.put(event, "content", "forged"),
          Map.put(event, "session_id", @next),
          Map.put(event, "epoch", 2),
          Map.put(event, "source_generation", 0),
          Map.put(event, "source_generation", 2),
          Map.put(event, "policy_generation", 1),
          Map.put(event, "version", 2),
          Map.put(event, "extra", true)
        ] do
      assert {:error, :invalid_reference_context} =
               Reference.restore([@metadata, admission] ++ committed_input() ++ [bad], @session)
    end

    assert {:error, _} =
             Reference.restore(
               [@metadata, admission] ++ committed_input() ++ [event, event],
               @session
             )

    assert {:error, _} =
             Reference.restore(
               [@metadata, admission] ++
                 committed_input() ++ [Map.put(event, "session_id", @next)]
             )

    assert {:error, _} = Reference.restore([@metadata, admission, false])

    for selected <- [
          %{"unknown" => "x"},
          %{"runtime" => "x"},
          %{"extensions" => %{}},
          %{"skills" => []},
          %{"extensions" => String.duplicate("\"", 8192)}
        ] do
      content = Reference.content(selected)

      bad =
        event
        |> Map.put("content", content)
        |> Map.put("content_sha256", Ipse.JSON.sha256(content))

      assert {:error, _} =
               Reference.restore([@metadata, admission] ++ committed_input() ++ [bad], @session)
    end
  end

  test "legacy journals retain their layout and cannot admit synthetic reference records" do
    legacy = %{"type" => "session", "metadata" => %{}}
    assert {:ok, nil} = Reference.restore([legacy])
    {admission, _} = admitted()
    assert {:error, _} = Reference.restore([legacy, admission])

    assert {:error, _} =
             Reference.restore([put_in(@metadata, ["metadata", "reference_layout"], "future")])
  end

  test "replay binds envelope identity to the current committed effective input turn" do
    {admission, state} = admitted()
    {:ok, [event], next, _} = Reference.prepare(state, @session, @turn, changed(), [], [@user])
    prefix = [@metadata, admission]
    committed = prefix ++ committed_input()

    assert {:ok, ^next} = Reference.restore(committed ++ [event])
    assert {:error, _} = Reference.restore(committed ++ [Map.put(event, "turn_id", @next)])
    assert {:error, _} = Reference.restore(prefix ++ [event])
    assert {:error, _} = Reference.restore(prefix ++ Enum.take(committed_input(), 1) ++ [event])

    # A new receipt does not become a turn until its effective message commits.
    orphan_turn = String.duplicate("d", 32)

    orphan =
      Ipse.Session.Input.received(@session, orphan_turn, "orphan input", "orphan input", nil)

    assert {:ok, ^next} = Reference.restore(committed ++ [event, orphan])
    assert {:error, _} = Reference.restore(committed ++ [orphan, event])

    assert {:error, _} =
             Reference.restore(committed ++ [orphan, Map.put(event, "turn_id", orphan_turn)])

    # An interrupted orphan may be superseded by a separately committed input.
    latest = committed_input(@next, "effective next request")
    latest_state = %{next | last_turn: @next}

    assert {:ok, ^latest_state} =
             Reference.restore(prefix ++ [orphan] ++ latest ++ [Map.put(event, "turn_id", @next)])

    assert {:error, _} = Reference.restore(committed ++ latest ++ [event])
    assert {:error, _} = Reference.restore(committed ++ [%{"type" => "turn_finished"}, event])
    assert {:error, _} = Reference.restore(committed ++ [%{"type" => "cancelled"}, event])
  end

  test "replay checks input session and effective text before activating an envelope turn" do
    {admission, state} = admitted()
    {:ok, [event], _, _} = Reference.prepare(state, @session, @turn, changed(), [], [@user])
    [receipt, user] = committed_input()

    for bad <- [
          Map.put(receipt, "session_id", @next),
          Map.put(receipt, "effective_sha256", Ipse.JSON.sha256("other effective text")),
          Map.put(receipt, "source_id", false)
        ] do
      assert {:error, _} = Reference.restore([@metadata, admission, bad, user, event], @session)
    end

    # Without an explicit ID, the first receipt still binds the following records.
    assert {:error, _} =
             Reference.restore([
               @metadata,
               Map.put(receipt, "session_id", @next),
               admission,
               user,
               event
             ])

    assert {:error, _} =
             Reference.restore([
               @metadata,
               admission,
               receipt,
               user,
               %{"type" => "message", "message" => @user},
               event
             ])
  end

  test "journal projection validates positions and refuses forged ordinary reference markers" do
    {admission, state} = admitted()

    {:ok, [event], _, [message]} =
      Reference.prepare(state, @session, @turn, changed(), [], [@user])

    journal = [@metadata, admission] ++ committed_input()
    assert {:ok, [@user, ^message]} = Saved.context(journal ++ [event])
    assert {:error, _} = Saved.context(journal ++ [Map.put(event, "position", 0)])
    assert {:error, _} = Saved.context(journal ++ [%{"type" => "message", "message" => message}])
    refute Reference.reference?(Map.put(message, "content", "forged"))
    refute Reference.reference?(Map.put(message, "ipse_reference", %{}))
  end

  test "compaction retains two actual turns and never pins reference data as operator intent" do
    {_, state} = admitted()
    {:ok, _, _, [reference]} = Reference.prepare(state, @session, @turn, changed(), [], [@user])

    history = [
      @user,
      reference,
      %{"role" => "assistant", "content" => String.duplicate("old ", 1000)},
      %{"role" => "user", "content" => "second"},
      reference,
      %{"role" => "assistant", "content" => "second answer"},
      %{"role" => "user", "content" => "third"},
      reference
    ]

    assert {:ok, plan} =
             Context.prepare_compaction(
               history,
               %{context_bytes: 20_000, compact_threshold_bytes: 4000},
               @header
             )

    assert plan.user_intents == [@user["content"]]
    assert plan.tail == Enum.drop(history, 3)
    measured = Context.measure(history, %{}, @header)
    assert measured["encoded_bytes"] == byte_size(Jason.encode!(@header ++ history))
    assert measured["categories"]["reference_context"] > byte_size(reference["content"])
  end

  test "the extension contribution limit includes final nested encoding and shared framing" do
    {_, state} = admitted()
    large = Map.put(@publishers, "extensions", String.duplicate("\"", 8192))
    assert Reference.extension_bytes(large["extensions"]) > 16_384
    assert {:error, _} = Reference.prepare(state, @session, @turn, large, [], [@user])

    assert {:ok, _, _, [_]} =
             Reference.prepare(
               state,
               @session,
               @turn,
               Map.put(@publishers, "extensions", "small"),
               [],
               [@user]
             )
  end
end
