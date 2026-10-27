defmodule Ipse.InferenceSlots.Ledger do
  @moduledoc false
  alias Ipse.{JSON, Config.Semantics}
  @error {:error, :invalid_service_ledger}
  @meta ~w(session_id project_id request_sha256 route_sha256 priority dispatch_timeout_ms)
  @queued ~w(id service_id sequence created_ms expires_ms meta)
  @active ~w(id service_id meta admitted_ms)

  def empty,
    do: %{
      "version" => 1,
      "revision" => 0,
      "sequence" => 0,
      "services" => %{},
      "queue" => [],
      "recent" => []
    }

  def valid?(state) do
    keys?(state, ~w(version revision sequence services queue recent)) and state["version"] === 1 and
      JSON.safe_uint?(state["revision"]) and JSON.safe_uint?(state["sequence"]) and
      state["revision"] >= state["sequence"] and
      is_map(state["services"]) and map_size(state["services"]) <= 8 and
      Enum.all?(state["services"], fn {id, service} -> service?(id, service) end) and
      unique?(Enum.map(state["services"], fn {_, s} -> s["slot"] end)) and
      unique?(Enum.flat_map(state["services"], fn {_, s} -> s["origins"] end)) and
      is_list(state["queue"]) and length(state["queue"]) <= 64 and
      Enum.all?(state["queue"], &queued?(&1, state)) and
      unique?(Enum.map(state["queue"], & &1["sequence"])) and
      is_list(state["recent"]) and length(state["recent"]) <= 32 and
      Enum.all?(state["recent"], &recent?(&1, state)) and
      unique?(ids(state)) and bounded?(state)
  rescue
    _ -> false
  end

  def meta?(meta) do
    keys?(meta, @meta) and id?(meta["session_id"]) and JSON.sha256?(meta["project_id"]) and
      JSON.sha256?(meta["request_sha256"]) and meta["priority"] in ~w(foreground background) and
      JSON.sha256?(meta["route_sha256"]) and
      is_integer(meta["dispatch_timeout_ms"]) and meta["dispatch_timeout_ms"] in 1..100_000
  end

  def enqueue(state, service_id, origins, id, meta, now, wait_ms) do
    with true <- valid?(state) and id?(id) and meta?(meta) and JSON.safe_uint?(now),
         true <- is_integer(wait_ms) and wait_ms in 1..60_000 and JSON.safe_uint?(now + wait_ms),
         {:ok, state} <- prune(state, now),
         false <- id in ids(state),
         {:ok, state} <- bind_service(state, service_id, origins),
         true <- length(state["queue"]) < 64,
         true <- JSON.safe_uint?(state["sequence"] + 1) do
      sequence = state["sequence"] + 1

      queued = %{
        "id" => id,
        "service_id" => service_id,
        "sequence" => sequence,
        "created_ms" => now,
        "expires_ms" => now + wait_ms,
        "meta" => meta
      }

      update(%{state | "sequence" => sequence, "queue" => state["queue"] ++ [queued]}, queued)
    else
      {:error, _} = error -> error
      _ -> {:error, :service_queue_refused}
    end
  end

  def eligible?(state, id, now) do
    with true <- valid?(state) and JSON.safe_uint?(now),
         queued when is_map(queued) <- Enum.find(state["queue"], &(&1["id"] == id)),
         true <- Enum.all?(state["queue"], &(&1["created_ms"] <= now)),
         true <- queued["created_ms"] <= now and now < queued["expires_ms"] do
      state["queue"]
      |> Enum.filter(
        &(&1["service_id"] == queued["service_id"] and &1["created_ms"] <= now and
            now < &1["expires_ms"])
      )
      |> Enum.min_by(
        &{if(&1["meta"]["priority"] == "foreground", do: 0, else: 1), &1["sequence"]}
      )
      |> Map.fetch!("id")
      |> Kernel.==(id)
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def admit(state, id, now) do
    with true <- valid?(state) and eligible?(state, id, now),
         queued <- Enum.find(state["queue"], &(&1["id"] == id)),
         service = state["services"][queued["service_id"]],
         true <- is_nil(service["active"]) do
      active = %{
        "id" => id,
        "service_id" => queued["service_id"],
        "meta" => queued["meta"],
        "admitted_ms" => now
      }

      state = put_in(state, ["services", queued["service_id"], "active"], active)
      update(%{state | "queue" => Enum.reject(state["queue"], &(&1["id"] == id))}, active)
    else
      _ -> {:error, :service_not_eligible_or_unknown}
    end
  end

  def cancel_waiting(state, id) do
    if valid?(state) and Enum.any?(state["queue"], &(&1["id"] == id)) do
      update(%{state | "queue" => Enum.reject(state["queue"], &(&1["id"] == id))}, :cancelled)
    else
      {:error, :service_wait_not_found}
    end
  end

  def settle(state, service_id, id, now) do
    finish(state, service_id, id, now, "settled", nil)
  end

  def cancel_unstarted(state, service_id, id, now),
    do: finish(state, service_id, id, now, "not_started", nil)

  def reconcile(state, service_id, id, revision, receipt, now) do
    if valid?(state) and state["revision"] === revision and receipt?(receipt) and
         receipt["service_id"] === service_id and receipt["reservation_id"] === id and
         receipt["expected_revision"] === revision do
      finish(state, service_id, id, now, "reconciled", receipt)
    else
      {:error, :service_reconciliation_refused}
    end
  end

  def receipt?(receipt) do
    keys?(
      receipt,
      ~w(version reason service_id reservation_id expected_revision operator_receipt_sha256)
    ) and receipt["version"] === 1 and
      is_binary(receipt["service_id"]) and
      Regex.match?(~r/\A[a-z][a-z0-9_-]{0,63}\z/, receipt["service_id"]) and
      id?(receipt["reservation_id"]) and JSON.safe_uint?(receipt["expected_revision"]) and
      receipt["reason"] in ~w(owned_service_quiescent shared_service_reconciled) and
      JSON.sha256?(receipt["operator_receipt_sha256"])
  end

  def slot(state, service_id), do: get_in(state, ["services", service_id, "slot"])

  defp finish(state, service_id, id, now, status, receipt) do
    with true <- valid?(state) and id?(id) and JSON.safe_uint?(now),
         active when is_map(active) <- get_in(state, ["services", service_id, "active"]),
         true <- active["id"] == id and now >= active["admitted_ms"] do
      recent =
        Map.merge(active, %{"status" => status, "finished_ms" => now, "receipt" => receipt})

      state = put_in(state, ["services", service_id, "active"], nil)
      update(%{state | "recent" => Enum.take(state["recent"] ++ [recent], -32)}, recent)
    else
      _ -> {:error, :service_reservation_mismatch}
    end
  end

  defp prune(state, now) do
    if Enum.any?(state["queue"], &(&1["created_ms"] > now)) do
      {:error, :service_clock_regressed}
    else
      {:ok, %{state | "queue" => Enum.reject(state["queue"], &(&1["expires_ms"] <= now))}}
    end
  end

  defp bind_service(state, id, origins) do
    with :ok <- Semantics.validate_services(%{id => %{"version" => 1, "origins" => origins}}) do
      case state["services"][id] do
        %{"origins" => ^origins} ->
          {:ok, state}

        nil ->
          if map_size(state["services"]) >= 8 or
               Enum.any?(state["services"], fn {_, service} ->
                 Enum.any?(origins, &(&1 in service["origins"]))
               end) do
            {:error, :service_identity_conflict}
          else
            used = Enum.map(state["services"], fn {_, s} -> s["slot"] end)
            slot = Enum.find(0..7, &(&1 not in used))

            {:ok,
             put_in(state, ["services", id], %{
               "slot" => slot,
               "origins" => origins,
               "active" => nil
             })}
          end

        _ ->
          {:error, :service_identity_conflict}
      end
    else
      _ -> {:error, :invalid_service_identity}
    end
  end

  defp update(state, value) do
    state = %{state | "revision" => state["revision"] + 1}
    if valid?(state), do: {:ok, state, value}, else: @error
  end

  defp service?(id, service) do
    keys?(service, ~w(slot origins active)) and is_integer(service["slot"]) and
      service["slot"] in 0..7 and
      Semantics.validate_services(%{id => %{"version" => 1, "origins" => service["origins"]}}) ==
        :ok and
      (is_nil(service["active"]) or active?(service["active"], id))
  end

  defp active?(active, id) do
    keys?(active, @active) and id?(active["id"]) and active["service_id"] == id and
      meta?(active["meta"]) and JSON.safe_uint?(active["admitted_ms"])
  end

  defp queued?(queued, state) do
    keys?(queued, @queued) and id?(queued["id"]) and
      Map.has_key?(state["services"], queued["service_id"]) and
      is_integer(queued["sequence"]) and queued["sequence"] > 0 and
      queued["sequence"] <= state["sequence"] and
      JSON.safe_uint?(queued["created_ms"]) and JSON.safe_uint?(queued["expires_ms"]) and
      (queued["expires_ms"] - queued["created_ms"]) in 1..60_000 and meta?(queued["meta"])
  end

  defp recent?(recent, state) do
    keys?(recent, @active ++ ~w(status finished_ms receipt)) and
      Map.has_key?(state["services"], recent["service_id"]) and
      active?(Map.take(recent, @active), recent["service_id"]) and
      JSON.safe_uint?(recent["finished_ms"]) and recent["finished_ms"] >= recent["admitted_ms"] and
      ((recent["status"] in ~w(settled not_started) and is_nil(recent["receipt"])) or
         (recent["status"] == "reconciled" and receipt?(recent["receipt"]) and
            recent["receipt"]["service_id"] == recent["service_id"] and
            recent["receipt"]["reservation_id"] == recent["id"] and
            recent["receipt"]["expected_revision"] < state["revision"]))
  end

  defp ids(state),
    do:
      Enum.map(
        state["queue"] ++
          state["recent"] ++
          Enum.flat_map(state["services"], fn {_, s} -> List.wrap(s["active"]) end),
        & &1["id"]
      )

  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)
  defp unique?(values), do: length(Enum.uniq(values)) == length(values)
  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)

  defp bounded?(state) do
    bytes = Jason.encode!(state)
    byte_size(bytes) <= 65_536 and JSON.decode_unique(bytes, 12) === {:ok, state}
  end
end
