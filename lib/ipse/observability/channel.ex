defmodule Ipse.Observability.Channel do
  @moduledoc "Atomically bounded metadata admission, separate from callback IO and text flow control."
  use GenServer
  alias Ipse.Extensions.{Worker, Registry}

  def start(owner, entry, policy, intent) do
    counters = :atomics.new(9, signed: false)
    :atomics.put(counters, 6, 1)

    with {:ok, pid} <- GenServer.start(__MODULE__, {owner, entry, policy, counters, intent}) do
      {:ok,
       %{
         pid: pid,
         counters: counters,
         entry: entry,
         worker: nil,
         intent: intent,
         monitor: Process.monitor(pid),
         ready: false,
         closed: false,
         cleanup: false
       }}
    end
  end

  def offer(resource, event, policy) do
    counters = resource.counters
    if event["level"] == "error", do: :atomics.add(counters, 8, 1)

    cond do
      :atomics.get(counters, 6) == 0 or not Process.alive?(resource.pid) ->
        :ok

      event["group"] not in policy["groups"] or
        (event["level"] == "debug" and policy["level"] != "debug") or
          (event["level"] != "error" and rem(event["sequence"] - 1, policy["sample_every"]) != 0) ->
        :atomics.add(counters, 7, 1)

      byte_size(Jason.encode!(event)) > policy["event_bytes"] ->
        :atomics.add(counters, 3, 1)

      true ->
        slots = :atomics.add_get(counters, 1, 1)

        if slots <= policy["queue_events"] and :atomics.get(counters, 6) == 1 do
          :atomics.add(counters, 2, 1)
          send(resource.pid, {:observation, event})
        else
          release(counters)
          :atomics.add(counters, 3, 1)
        end
    end

    :ok
  end

  def admit(resource), do: send(resource.pid, {:admit, resource.intent["resource_id"]})
  def stop(resource), do: send(resource.pid, :stop)

  def revoke(resource) do
    :atomics.put(resource.counters, 6, 0)
    discarded = :atomics.exchange(resource.counters, 1, 0)
    :atomics.add(resource.counters, 3, discarded)
    :ok
  end

  def close(resource) do
    revoke(resource)

    result =
      cond do
        resource.closed -> :ok
        is_pid(resource.worker) -> close_worker(resource.worker, resource.counters)
        is_nil(resource.intent) -> :ok
        :atomics.get(resource.counters, 9) in [1, 2, 3] -> await_cleanup(resource.counters)
        true -> {:error, :cleanup_unconfirmed}
      end

    if Process.alive?(resource.pid), do: Process.exit(resource.pid, :kill)
    result
  end

  def snapshot(resource) do
    names = ~w(pending admitted dropped delivered failures active filtered errors)

    Map.new(Enum.with_index(names, 1), fn {name, index} ->
      {name, :atomics.get(resource.counters, index)}
    end)
  end

  @impl true
  def init({owner, entry, policy, counters, intent}) do
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
       policy: policy,
       counters: counters,
       worker: nil,
       intent: intent,
       ready: false,
       queue: :queue.new(),
       scheduled: false
     }, {:continue, :activate}}
  end

  @impl true
  def handle_continue(:activate, %{worker: nil} = s) do
    intent = s.intent

    with true <- :atomics.get(s.counters, 6) == 1 and Registry.live?(s.entry.identity),
         {:ok, worker} <-
           Worker.start(
             owner: self(),
             store: s.entry.store,
             digest: s.entry.identity["artifact"],
             trusted: s.entry.identity["artifact"],
             artifact_sha256: s.entry.identity["artifact_sha256"],
             options: s.entry.options
           ) do
      next = %{s | worker: worker, intent: intent}

      try do
        with :ok <- GenServer.call(s.owner, {:observer_worker, intent["resource_id"], worker}),
             {:ok, _} <- Worker.call(worker, "initialize", s.entry.options),
             true <- :atomics.get(s.counters, 6) == 1 do
          send(s.owner, {:observer_ready, self(), intent["resource_id"]})
          {:noreply, next}
        else
          _ -> failed_start(next)
        end
      catch
        :exit, _ -> failed_start(next)
      end
    else
      _ -> failed_start(s)
    end
  end

  @impl true
  def handle_info({:observation, event}, s) do
    if :atomics.get(s.counters, 6) == 1 and Ipse.Observability.Event.valid?(event) do
      {:noreply, schedule(%{s | queue: :queue.in(event, s.queue)})}
    else
      release(s.counters)
      {:noreply, s}
    end
  end

  def handle_info({:admit, id}, %{intent: %{"resource_id" => id}} = s),
    do: {:noreply, schedule(%{s | ready: true})}

  def handle_info(:drain, s) do
    case {:atomics.get(s.counters, 6), :queue.out(s.queue)} do
      {1, {{:value, event}, queue}} ->
        payload = %{
          "api_version" => 1,
          "handle" => s.intent["resource_id"],
          "event" => event,
          "limits" => Map.take(s.policy, ~w(file_bytes retained_files))
        }

        reply = %{
          "api_version" => 1,
          "kind" => "ack",
          "handle" => s.intent["resource_id"],
          "event_id" => event["event"]["event_id"],
          "sequence" => event["sequence"]
        }

        with true <- Registry.live?(s.entry.identity),
             {:ok, ^reply} <-
               Worker.call(s.worker, Ipse.Observability.Config.stage(s.entry), payload),
             true <- Registry.live?(s.entry.identity) and :atomics.get(s.counters, 6) == 1 do
          release(s.counters)
          :atomics.add(s.counters, 4, 1)
          {:noreply, schedule(%{s | queue: queue, scheduled: false})}
        else
          _ ->
            :atomics.add(s.counters, 5, 1)
            {:stop, :normal, s}
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
    discarded = :atomics.exchange(s.counters, 1, 0)
    :atomics.add(s.counters, 3, discarded)

    result =
      if is_pid(s.worker),
        do: close_worker(s.worker, s.counters),
        else: {:error, :cleanup_unconfirmed}

    if s.intent,
      do: send(s.owner, {:observer_closed, self(), s.intent["resource_id"], result == :ok})

    :ok
  end

  @impl true
  def format_status(status),
    do:
      Map.new(status, fn
        {key, _} when key in [:state, :message, :reason, :log] -> {key, :private_observer}
        item -> item
      end)

  defp schedule(%{ready: true, scheduled: false} = s) do
    if :atomics.get(s.counters, 6) == 1 and not :queue.is_empty(s.queue) do
      send(self(), :drain)
      %{s | scheduled: true}
    else
      s
    end
  end

  defp schedule(s), do: s

  defp failed_start(s) do
    :atomics.add(s.counters, 5, 1)
    {:stop, :normal, s}
  end

  defp close_worker(worker, counters) do
    case :atomics.compare_exchange(counters, 9, 0, 1) do
      :ok ->
        result = Worker.close(worker)
        :atomics.put(counters, 9, if(result == :ok, do: 2, else: 3))
        result

      _ ->
        await_cleanup(counters)
    end
  end

  defp await_cleanup(counters),
    do: await_cleanup(counters, System.monotonic_time(:millisecond) + 3_500)

  defp await_cleanup(counters, deadline) do
    case :atomics.get(counters, 9) do
      2 ->
        :ok

      1 ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(2)
          await_cleanup(counters, deadline)
        else
          {:error, :cleanup_unconfirmed}
        end

      _ ->
        {:error, :cleanup_unconfirmed}
    end
  end

  defp release(counters) do
    current = :atomics.get(counters, 1)

    if current > 0 and :atomics.compare_exchange(counters, 1, current, current - 1) != :ok,
      do: release(counters)

    :ok
  end
end
