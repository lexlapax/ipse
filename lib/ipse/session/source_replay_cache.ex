defmodule Ipse.Session.SourceReplayCache do
  @moduledoc false
  use GenServer

  alias Ipse.Session.{Saved, SourceIndex}

  @input_bytes 8_388_608
  @index_bytes 8_388_608
  @entries 128
  @error {:error, :source_replay_unavailable}

  # The owner is the task's cleanup scope. This process stores only a result
  # it reconstructed itself, never a caller-supplied index or source lease.
  def start(owner) when owner == self() do
    gate = :atomics.new(1, [])

    with {:ok, pid} <- GenServer.start_link(__MODULE__, owner), do: {:ok, %{pid: pid, gate: gate}}
  end

  def restore(%{pid: pid, gate: gate}, events, id) when is_pid(pid) and is_list(events) do
    if :erlang.external_size(events) <= @input_bytes and
         :atomics.compare_exchange(gate, 1, 0, 1) == :ok do
      try do
        GenServer.call(pid, {:restore, events, id}, :infinity)
      after
        :atomics.put(gate, 1, 0)
      end
    else
      reconstruct(events, id)
    end
  rescue
    _ -> @error
  catch
    :exit, _ -> @error
  end

  @impl true
  def init(owner) do
    {:ok, %{owner_ref: Process.monitor(owner), entries: %{}, bytes: 0}}
  end

  @impl true
  def handle_call({:restore, events, id}, _from, state) when is_list(events) and is_binary(id) do
    if :erlang.external_size(events) <= @input_bytes do
      key = {id, :crypto.hash(:sha256, :erlang.term_to_binary(events, [:deterministic]))}

      case state.entries[key] do
        %{index: index} ->
          {:reply, fresh(index), state}

        nil ->
          case reconstruct(events, id) do
            {:ok, index} = result ->
              state =
                if map_size(state.entries) < @entries and
                     :erlang.external_size(index) <= @index_bytes - state.bytes do
                  # Copy retained fields away from journal decode buffers: a
                  # small sub-binary otherwise keeps its entire read chunk.
                  encoded = :erlang.term_to_binary(index, [:deterministic])
                  size = byte_size(encoded)

                  if state.bytes + size <= @index_bytes do
                    detached = :erlang.binary_to_term(encoded, [:safe])
                    entry = %{index: detached, bytes: size}

                    %{
                      state
                      | entries: Map.put(state.entries, key, entry),
                        bytes: state.bytes + size
                    }
                  else
                    state
                  end
                else
                  state
                end

              {:reply, result, state}

            error ->
              {:reply, error, state}
          end
      end
    else
      {:reply, reconstruct(events, id), state}
    end
  rescue
    _ -> {:reply, @error, state}
  catch
    _, _ -> {:reply, @error, state}
  end

  def handle_call(_, _, state), do: {:reply, @error, state}

  @impl true
  def handle_info({:DOWN, ref, :process, _, _}, %{owner_ref: ref} = state),
    do: {:stop, :normal, state}

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def format_status(status) do
    Map.new(status, fn
      {:state, state} -> {:state, %{entries: map_size(state.entries), bytes: state.bytes}}
      {:message, _} -> {:message, :redacted}
      {:reason, _} -> {:reason, :redacted}
      {:log, _} -> {:log, []}
      pair -> pair
    end)
  end

  defp reconstruct(events, id) do
    with {:ok, saved} <- Saved.restore(events, id),
         %SourceIndex{} = index <- saved.source_window.index do
      {:ok, index}
    else
      _ -> @error
    end
  end

  defp fresh(index) do
    with {:ok, identity} <-
           SourceIndex.new(index.session_id, index.policy_generation, index.origin_sha256) do
      {:ok, %{index | window_id: identity.window_id, secret: identity.secret}}
    end
  end
end
