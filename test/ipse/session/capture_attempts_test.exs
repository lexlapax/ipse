defmodule Ipse.Session.CaptureAttemptsTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Journal, Session}
  alias Session.{Lifecycle, PendingNomination, SourceIndex}

  @session String.duplicate("f", 32)

  # This pure ledger fixture starts after nomination validation. Its constructed
  # source references establish stable proof identity, never live source access.
  defp answer(turn_byte, request_byte, text) do
    turn = String.duplicate(turn_byte, 32)
    request = String.duplicate(request_byte, 32)

    args = %{
      "text" => text,
      "reason" => "Synthetic decision",
      "category" => "ordinary",
      "references" => []
    }

    intent = %{
      "invocation_id" => String.duplicate(turn_byte, 32),
      "payload" => %{"arguments" => args}
    }

    nomination = %{
      "type" => "pending_proposal_nominated",
      "version" => 1,
      "session_id" => @session,
      "turn_id" => turn,
      "invocation_id" => intent["invocation_id"],
      "intent_sha256" => JSON.digest([intent])
    }

    input = %{"type" => "input_received", "session_id" => @session, "turn_id" => turn}
    assert {:ok, source} = Journal.source(@session, 100, input)

    committed =
      Lifecycle.answer(turn, request, %{"role" => "assistant", "content" => text}, text, source)

    assert {:ok, index} = SourceIndex.new(@session)
    assert {:ok, index} = SourceIndex.admit_answer(index, committed)
    assert {:ok, selected} = SourceIndex.answer_request(index, turn, request, text)
    assert {:ok, %{"proof" => proof}} = SourceIndex.resolve_proof(index, selected)
    intent = Map.put(intent, "type", "extension_invocation_intent")
    nomination = Map.put(nomination, "intent_sha256", JSON.digest([intent]))

    assert {:ok, attempt} =
             PendingNomination.capture_attempt(@session, turn, request, nomination, proof)

    prefix = [
      input,
      intent,
      nomination,
      %{"type" => "source_answer_committed", "version" => 1, "answer" => committed}
    ]

    %{
      turn: turn,
      request: request,
      nomination: nomination,
      attempt: attempt,
      proof: proof,
      prefix: prefix
    }
  end

  defp header, do: %{"type" => "session", "metadata" => %{}}

  defp legacy(attempt),
    do:
      attempt |> Map.take(~w(type session_id turn_id nomination_sha256)) |> Map.put("version", 1)

  test "different completed answers have independent durable attempts, including after a closed turn" do
    first = answer("a", "b", "Use cedar.")
    second = answer("c", "d", "Use birch.")

    events =
      [header() | first.prefix] ++
        [first.attempt, %{"type" => "turn_finished", "status" => "ok"}] ++
        second.prefix ++ [second.attempt]

    assert {:ok, attempts} = PendingNomination.capture_attempts(events, @session)

    assert attempts === %{
             {first.turn, first.request} => first.attempt["capture_attempt_id"],
             {second.turn, second.request} => second.attempt["capture_attempt_id"]
           }
  end

  test "a capture fence is not a metered provider attempt" do
    first = answer("a", "b", "Use cedar.")
    refute Map.has_key?(first.attempt, "attempt_id")
    assert is_binary(first.attempt["capture_attempt_id"])
    {:ok, ledger} = Ipse.Usage.restore([], @session)
    assert {:ok, ^ledger} = Ipse.Usage.apply_event(ledger, first.attempt)

    provider_attempt =
      first.attempt
      |> Map.delete("capture_attempt_id")
      |> Map.put("attempt_id", first.attempt["capture_attempt_id"])

    assert {:error, :invalid_usage_journal} = Ipse.Usage.apply_event(ledger, provider_attempt)
  end

  test "a prefix ending at started is spent without any effect outcome and cannot start again" do
    first = answer("a", "b", "Use cedar.")
    events = [header() | first.prefix] ++ [first.attempt]
    assert {:ok, attempts} = PendingNomination.capture_attempts(events, @session)

    state = %{
      turn_id: first.turn,
      last_request_id: first.request,
      post_reply_capture_attempts: attempts,
      pending_nomination: %{event: first.nomination}
    }

    assert :skip = Session.start_post_reply_capture(state, :ok)
    assert {:error, _} = PendingNomination.capture_attempts(events ++ [first.attempt], @session)

    assert {:error, _} =
             PendingNomination.capture_attempts(events ++ [legacy(first.attempt)], @session)
  end

  test "legacy started records restore the same answer fence and do not disable future answers" do
    first = answer("a", "b", "Use cedar.")
    second = answer("c", "d", "Use birch.")
    events = [header() | first.prefix] ++ [legacy(first.attempt)]
    key = {first.turn, first.request}
    assert {:ok, %{^key => id}} = PendingNomination.capture_attempts(events, @session)
    assert id === first.attempt["capture_attempt_id"]
    assert {:error, _} = PendingNomination.capture_attempts(events ++ [first.attempt], @session)

    assert {:ok, attempts} =
             PendingNomination.capture_attempts(
               events ++ second.prefix ++ [second.attempt],
               @session
             )

    assert map_size(attempts) === 2
  end

  test "attempt identity requires exact original nomination, final request and proof before turn completion" do
    first = answer("a", "b", "Use cedar.")
    other = answer("c", "d", "Use cedar.")
    prefix = [header() | first.prefix]

    assert {:ok, foreign_proof} =
             PendingNomination.capture_attempt(
               @session,
               first.turn,
               first.request,
               first.nomination,
               other.proof
             )

    assert {:ok, foreign_request} =
             PendingNomination.capture_attempt(
               @session,
               first.turn,
               other.request,
               first.nomination,
               first.proof
             )

    for changed <- [
          Map.put(first.attempt, "session_id", String.duplicate("e", 32)),
          Map.put(first.attempt, "turn_id", String.duplicate("e", 32)),
          Map.put(first.attempt, "request_id", String.duplicate("e", 32)),
          Map.put(first.attempt, "nomination_sha256", JSON.sha256("changed nomination")),
          Map.put(first.attempt, "source_proof", other.proof),
          foreign_proof,
          foreign_request,
          Map.put(first.attempt, "capture_attempt_id", String.duplicate("e", 32)),
          first.attempt
          |> Map.delete("capture_attempt_id")
          |> Map.put("attempt_id", String.duplicate("e", 32)),
          Map.put(first.attempt, "version", 3),
          Map.put(first.attempt, "extra", true)
        ] do
      assert {:error, _} = PendingNomination.capture_attempts(prefix ++ [changed], @session)
    end

    assert {:error, _} =
             PendingNomination.capture_attempts(
               prefix ++ [%{"type" => "turn_finished", "status" => "ok"}, first.attempt],
               @session
             )

    assert {:error, _} = PendingNomination.capture_attempts([header(), first.attempt], @session)
    assert {:ok, %{}} = PendingNomination.capture_attempts([], @session)
    assert {:ok, %{}} = PendingNomination.capture_attempts([header()], @session)
  end
end
