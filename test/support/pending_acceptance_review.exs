ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
alias Ipse.Runner.Review
alias Ipse.Session.PendingAcceptance

[root, mode] = System.argv()
facts = root |> Path.join("pending-card.json") |> File.read!() |> Jason.decode!()
event_path = Path.join(root, "pending-accept-event.json")

case mode do
  "valid" ->
    assert {:ok, event} =
             Review.with_review("accept", facts, fn permit ->
               now = System.system_time(:millisecond)
               assert {:ok, preview} = PendingAcceptance.preview(permit, facts, now)

               assert {:ok, planned} =
                        PendingAcceptance.accepted_values(preview, now + 86_400_000)

               assert {:error, :pending_acceptance_refused} =
                        Task.async(fn -> PendingAcceptance.preview(permit, facts, now) end)
                        |> Task.await()

               assert {:error, :pending_acceptance_refused} =
                        PendingAcceptance.preview(
                          permit,
                          Map.update!(facts, "render_revision", &(&1 + 1)),
                          now
                        )

               assert {:ok, ^preview} = PendingAcceptance.consume(permit, facts, now)
               assert PendingAcceptance.valid_accepted_values?(preview, planned)
               event = preview
               assert PendingAcceptance.valid_event?(event)

               assert {:error, :pending_acceptance_refused} =
                        PendingAcceptance.preview(permit, facts, now)

               assert {:error, :pending_acceptance_refused} =
                        PendingAcceptance.consume(permit, facts, now)

               {:ok, event}
             end)

    assert {:ok, values} =
             PendingAcceptance.accepted_values(
               event,
               event["review"]["observed_at_ms"] + 86_400_000
             )

    assert values["note"]["source_proof"] === facts["source_proof"]
    File.write!(event_path, Jason.encode!(event), [:exclusive])

  mode when mode in ~w(cancel stale) ->
    assert {:error, :native_review_refused} =
             Review.with_review("accept", facts, fn _ ->
               flunk("invalid input entered callback")
             end)

    refute File.exists?(event_path)

  "changed" ->
    assert {:error, :native_review_refused} =
             Review.with_review("accept", facts, fn permit ->
               changed = Map.update!(facts, "render_revision", &(&1 + 1))
               now = System.system_time(:millisecond)

               assert {:error, :pending_acceptance_refused} =
                        PendingAcceptance.consume(permit, changed, now)

               assert {:error, :pending_acceptance_refused} =
                        PendingAcceptance.consume(permit, facts, now)

               {:error, :changed}
             end)

    refute File.exists?(event_path)

  "expired" ->
    assert {:error, :expired} =
             Review.with_review("accept", facts, fn permit ->
               assert {:error, :pending_acceptance_refused} =
                        PendingAcceptance.consume(permit, facts, facts["valid_until_ms"])

               {:error, :expired}
             end)

    refute File.exists?(event_path)
end

IO.puts("PENDING_NATIVE_REVIEW_#{String.upcase(mode)}_PASSED")
