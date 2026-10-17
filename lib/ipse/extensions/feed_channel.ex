defmodule Ipse.Extensions.FeedChannel do
  @moduledoc "Owned serial event callbacks; pressure closes coverage instead of silently dropping events."
  use GenServer
  alias Ipse.Extensions.{Worker, WorkerLease, Registry, Feeds}

  def start(owner, entry, intent, source) do
    counters = :atomics.new(10, signed: false)
    :atomics.put(counters, 6, 1)

    with {:ok, pid} <- GenServer.start(__MODULE__, {owner, entry, intent, source, counters}) do
      {:ok,
       %{
         pid: pid,
         monitor: Process.monitor(pid),
         counters: counters,
         worker: nil,
         intent: intent,
         source: source,
         ready: false,
         closed: false,
         cleanup: false,
         pending: :ets.new(__MODULE__, [:set, :private]),
         ack: 0
       }}
    end
  end

  def active?(resource), do: :atomics.get(resource.counters, 6) == 1
  def admit(resource), do: send(resource.pid, {:admit, resource.intent["resource_id"]})

  def stop(resource, reason) do
    :atomics.compare_exchange(resource.counters, 10, 0, Feeds.reason_code(reason))
    :atomics.put(resource.counters, 6, 0)
    if is_pid(resource.worker), do: WorkerLease.stop_async(resource.worker, resource.counters)
    if is_pid(Map.get(resource, :pid)), do: send(resource.pid, :stop)
    :ok
  end

  def close(resource, reason) do
    stop(resource, reason)

    result =
      cond do
        resource.closed -> if resource.cleanup, do: :ok, else: {:error, :cleanup_unconfirmed}
        is_pid(resource.worker) -> WorkerLease.close(resource.worker, resource.counters)
        :atomics.get(resource.counters, 9) in [1, 2, 3] -> WorkerLease.await(resource.counters)
        true -> {:error, :cleanup_unconfirmed}
      end

    if Process.alive?(resource.pid), do: Process.exit(resource.pid, :kill)
    result
  end

  def release(counters) do
    n = :atomics.get(counters, 1)
    if n > 0 and :atomics.compare_exchange(counters, 1, n, n - 1) != :ok, do: release(counters)
    :ok
  end

  @impl true
  def init({owner, entry, intent, source, counters}) do
    channel = self()

    spawn(fn ->
      owner_ref = Process.monitor(owner)
      channel_ref = Process.monitor(channel)

      receive do
        {:DOWN, ^owner_ref, :process, _, _} ->
          :atomics.put(counters, 6, 0)
          Process.exit(channel, :kill)

        {:DOWN, ^channel_ref, :process, _, _} ->
          :atomics.put(counters, 6, 0)
      end
    end)

    {:ok,
     %{
       owner: owner,
       entry: entry,
       intent: intent,
       source: source,
       counters: counters,
       worker: nil,
       ready: false,
       scheduled: false,
       awaiting: nil,
       queue: :queue.new()
     }, {:continue, :activate}}
  end

  @impl true
  def handle_continue(:activate, s) do
    with true <- active?(s) and Registry.live?(s.entry.identity),
         {:ok, worker} <-
           Worker.start(
             owner: self(),
             store: s.entry.store,
             digest: s.entry.identity["artifact"],
             trusted: s.entry.identity["artifact"],
             artifact_sha256: s.entry.identity["artifact_sha256"],
             options: s.entry.options
           ) do
      next = %{s | worker: worker}

      try do
        with :ok <- GenServer.call(s.owner, {:feed_worker, s.intent["resource_id"], worker}),
             {:ok, _} <- Worker.call(worker, "initialize", s.entry.options),
             true <- active?(s) and Registry.live?(s.entry.identity) do
          send(s.owner, {:feed_ready, self(), s.intent["resource_id"]})
          {:noreply, next}
        else
          _ -> failed(next, "startup_failed")
        end
      catch
        :exit, _ -> failed(next, "startup_failed")
      end
    else
      _ -> failed(s, "startup_failed")
    end
  end

  @impl true
  def handle_info({:delivery, intent, payload}, s) do
    if active?(s) do
      {:noreply, schedule(%{s | queue: :queue.in({intent, payload}, s.queue)})}
    else
      release(s.counters)
      {:noreply, s}
    end
  end

  def handle_info({:admit, id}, %{intent: %{"resource_id" => id}} = s),
    do: {:noreply, schedule(%{s | ready: true})}

  def handle_info({:ack_committed, seq}, %{awaiting: seq} = s) do
    release(s.counters)
    {:noreply, schedule(%{s | awaiting: nil})}
  end

  def handle_info(:drain, s) do
    case {active?(s), :queue.out(s.queue)} do
      {true, {{:value, {intent, payload}}, queue}} ->
        reply = Feeds.ack(payload)

        with true <- Registry.live?(s.entry.identity),
             {:ok, ^reply} <- Worker.call(s.worker, "event.feed", payload),
             true <- Registry.live?(s.entry.identity) and active?(s) do
          send(s.owner, {:feed_ack, self(), s.intent["resource_id"], intent["sequence"]})
          {:noreply, %{s | queue: queue, scheduled: false, awaiting: intent["sequence"]}}
        else
          _ -> failed(s, "callback_failed")
        end

      _ ->
        {:noreply, %{s | scheduled: false}}
    end
  end

  def handle_info(:stop, s), do: {:stop, :normal, s}
  def handle_info(_, s), do: {:noreply, s}

  @impl true
  def terminate(_, s) do
    :atomics.put(s.counters, 6, 0)

    result =
      if is_pid(s.worker),
        do: WorkerLease.close(s.worker, s.counters),
        else: {:error, :cleanup_unconfirmed}

    send(s.owner, {:feed_closed, self(), s.intent["resource_id"], result == :ok})
    :ok
  end

  @impl true
  def format_status(status),
    do:
      Map.new(status, fn
        {key, _} when key in [:state, :message, :reason, :log] -> {key, :private_feed}
        item -> item
      end)

  defp failed(s, reason) do
    stop(s, reason)
    {:stop, :normal, s}
  end

  defp schedule(%{ready: true, scheduled: false, awaiting: nil} = s) do
    if active?(s) and not :queue.is_empty(s.queue) do
      send(self(), :drain)
      %{s | scheduled: true}
    else
      s
    end
  end

  defp schedule(s), do: s
end
