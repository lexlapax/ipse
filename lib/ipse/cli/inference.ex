defmodule Ipse.CLI.Inference do
  @moduledoc "Operator inspection and explicit reconciliation of protected inference reservations."
  alias Ipse.{InferenceSlots, JSON}
  alias Ipse.CLI.Terminal
  alias Ipse.InferenceSlots.Ledger

  def run(["status"], opts, home, cwd) do
    with true <- options?(opts, ~w(cwd json)a),
         {:ok, state} <- existing_state(home, cwd) do
      report = %{
        "version" => 1,
        "revision" => state["revision"],
        "services" => state["services"],
        "queue" => state["queue"],
        "recent" => state["recent"],
        "active_meaning" => "unresolved_until_known_terminal_or_operator_reconciliation"
      }

      Terminal.puts(Jason.encode!(report, pretty: opts[:json] != true))
      0
    else
      _ ->
        refused(
          "Inference state unavailable; inspect its original operator home and protected filesystem."
        )
    end
  end

  def run(["reconcile", service, reservation, revision_text], opts, home, cwd) do
    with true <- options?(opts, [:cwd]),
         true <- service?(service) and id?(reservation),
         true <- byte_size(revision_text) in 1..16,
         {revision, ""} <- Integer.parse(revision_text),
         true <- JSON.safe_uint?(revision) and Integer.to_string(revision) === revision_text,
         {:ok, state} <- existing_state(home, cwd),
         true <- state["revision"] === revision,
         %{"origins" => origins, "active" => %{"id" => ^reservation} = active} <-
           state["services"][service],
         facts = %{
           "operator_home" => home,
           "workspace" => cwd,
           "service_id" => service,
           "reservation_id" => reservation,
           "expected_revision" => revision,
           "origins" => origins,
           "active" => active,
           "reason" => "shared_service_reconciled"
         },
         {:ok, observation} <- confirm(facts),
         receipt = %{
           "version" => 1,
           "reason" => facts["reason"],
           "service_id" => service,
           "reservation_id" => reservation,
           "expected_revision" => revision,
           "operator_receipt_sha256" =>
             JSON.digest(["ipse.inference.reconciliation", 1, facts, observation])
         } do
      case InferenceSlots.reconcile(%{home: home}, service, reservation, revision, receipt,
             cwd: cwd
           ) do
        {:ok, _} ->
          Terminal.puts(
            "Recorded reconciliation for #{service}/#{reservation}. No inference was replayed."
          )

          0

        {:unknown, _} ->
          refused(
            "Reconciliation outcome is unknown. Inspect inference status before any further action."
          )

        _ ->
          refused(
            "Reconciliation refused; state changed or a service lease is still held. Inspect inference status."
          )
      end
    else
      _ ->
        refused(
          "Reconciliation refused or cancelled; select the exact active reservation and current revision from inference status. Native terminal confirmation is required."
        )
    end
  end

  def run(_, _, _, _),
    do:
      refused(
        "Use inference status [--json] or inference reconcile SERVICE_ID RESERVATION_ID REVISION. --yes is unsupported."
      )

  # Avoid constructing a service tree merely to inspect a fresh operator home.
  # Existing protected trees retain the runtime's ordinary lock/cleanup checks.
  defp existing_state(home, cwd) do
    case File.lstat(Path.join(home, "inference-services")) do
      {:error, :enoent} -> {:ok, Ledger.empty()}
      {:ok, %{type: :directory}} -> InferenceSlots.status(%{home: home}, cwd: cwd)
      _ -> {:error, :service_state_unavailable}
    end
  end

  defp confirm(facts) do
    code = Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    input = "reconcile " <> code

    display =
      Terminal.escape(
        "Reconcile this exact unresolved inference reservation?\n" <>
          "Confirm only after verifying all clients at every listed origin have no remaining work for it.\n" <>
          "A free local lock, expired request or /api/ps snapshot does not prove remote quiescence.\n" <>
          "This records your reconciliation and clears the admission block. It stops no daemon and replays no work.\n" <>
          Jason.encode!(facts, pretty: true) <>
          "\nType reconcile #{code} to confirm, or anything else to cancel.\n> "
      )

    with {:ok, observation} <- Ipse.Runner.operator_input(display, 120_000, 2),
         true <- observation["display_sha256"] === JSON.sha256(display),
         true <- observation["text"] === input,
         true <- Ipse.Session.Input.valid_observation?(Map.delete(observation, "text"), input, 2) do
      {:ok, Map.delete(observation, "text")}
    else
      _ -> {:error, :native_reconciliation_refused}
    end
  end

  defp options?(opts, allowed), do: Enum.all?(Keyword.keys(opts), &(&1 in allowed))

  defp service?(value),
    do: is_binary(value) and Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, value)

  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)

  defp refused(message) do
    Terminal.puts(:stderr, message)
    1
  end
end
