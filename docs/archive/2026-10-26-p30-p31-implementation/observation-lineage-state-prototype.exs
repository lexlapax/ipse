defmodule Ipse.Session.ObservationLineage do
  @moduledoc false

  # Unwired Session-owned accounting primitive. It is not a receipt verifier,
  # replay store, policy check, confinement boundary or authorization to use
  # observed data. The caller must not expose data unless every required
  # downstream boundary and durable receipt is separately enforced.
  @max_origins 32
  @max_workers 16

  defstruct origins: MapSet.new(), workers: MapSet.new(), poisoned: false

  def new, do: %__MODULE__{}

  def start_worker(%__MODULE__{poisoned: false} = state) do
    if MapSet.size(state.workers) < @max_workers do
      worker = make_ref()
      {:ok, %{state | workers: MapSet.put(state.workers, worker)}, worker}
    else
      {:error, poison(state)}
    end
  end

  def start_worker(%__MODULE__{} = state), do: {:error, poison(state)}

  # receipt_sha256 identifies a complete, separately authenticated and durably
  # committed receipt; this module only tracks the digest, not its truth.
  def observed(%__MODULE__{poisoned: false} = state, worker, receipt_sha256) do
    if MapSet.member?(state.workers, worker) and Ipse.JSON.sha256?(receipt_sha256) and
         (MapSet.member?(state.origins, receipt_sha256) or
            MapSet.size(state.origins) < @max_origins) do
      {:ok, %{state | origins: MapSet.put(state.origins, receipt_sha256)}}
    else
      {:error, poison(state)}
    end
  end

  def observed(%__MODULE__{} = state, _, _), do: {:error, poison(state)}

  # Stopping one worker never clears session obligations, including data that
  # might have passed into another worker or a saved continuation.
  def finish_worker(%__MODULE__{poisoned: false} = state, worker, :ok) do
    if MapSet.member?(state.workers, worker),
      do: {:ok, %{state | workers: MapSet.delete(state.workers, worker)}},
      else: {:error, poison(state)}
  end

  def finish_worker(%__MODULE__{} = state, _, _), do: {:error, poison(state)}

  # An untracked edge or uncertain cleanup permanently refuses this state.
  def untracked(%__MODULE__{} = state), do: poison(state)

  # Every active worker sees the entire session union. The result is obligations
  # for a future verifier, never evidence of current authority.
  def obligations(%__MODULE__{poisoned: false} = state, worker) do
    if MapSet.member?(state.workers, worker),
      do: {:ok, Enum.sort(state.origins)},
      else: {:error, poison(state)}
  end

  def obligations(%__MODULE__{} = state, _), do: {:error, poison(state)}

  defp poison(state), do: %{state | poisoned: true}
end
