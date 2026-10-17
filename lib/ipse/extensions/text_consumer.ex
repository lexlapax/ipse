defmodule Ipse.Extensions.TextConsumer do
  @moduledoc "Owned worker adapter for acknowledged private visible-text frames."
  use GenServer
  alias Ipse.Extensions.{Registry, Worker}

  def start(owner, coordinator, entry, intent),
    do: GenServer.start(__MODULE__, {owner, coordinator, entry, intent})

  def activate(pid, handle), do: GenServer.call(pid, {:activate, handle}, :infinity)

  def close(%{pid: pid, worker: worker}) do
    result = if is_pid(worker), do: Worker.close(worker), else: {:error, :cleanup_unconfirmed}
    monitor = Process.monitor(pid)
    if Process.alive?(pid), do: Process.exit(pid, :kill)

    receive do
      {:DOWN, ^monitor, :process, ^pid, _} -> result
    after
      1_000 -> {:error, :cleanup_unconfirmed}
    end
  end

  @impl true
  def init({owner, coordinator, entry, intent}) do
    consumer = self()

    spawn(fn ->
      owner_ref = Process.monitor(owner)
      consumer_ref = Process.monitor(consumer)

      receive do
        {:DOWN, ^owner_ref, :process, _, _} -> Process.exit(consumer, :kill)
        {:DOWN, ^consumer_ref, :process, _, _} -> :ok
      end
    end)

    {:ok,
     %{
       owner: owner,
       owner_ref: Process.monitor(owner),
       coordinator: coordinator,
       entry: entry,
       intent: intent,
       worker: nil,
       handle: nil,
       broker_ref: nil,
       sequence: 0,
       frames: 0,
       bytes: 0,
       close_reason: "startup_failed"
     }}
  end

  @impl true
  def handle_call({:activate, handle}, {caller, _}, %{coordinator: caller, handle: nil} = s) do
    entry = s.entry

    with true <- Registry.live?(entry.identity),
         {:ok, worker} <-
           Worker.start(
             owner: self(),
             store: entry.store,
             digest: entry.identity["artifact"],
             trusted: entry.identity["artifact"],
             artifact_sha256: entry.identity["artifact_sha256"],
             options: entry.options
           ) do
      s = %{s | worker: worker, handle: handle, broker_ref: Process.monitor(handle.server)}

      try do
        with :ok <-
               GenServer.call(s.owner, {:extension_text_worker, s.intent["resource_id"], worker}),
             {:ok, _} <- Worker.call(worker, "initialize", entry.options),
             true <- Registry.live?(entry.identity) do
          {:reply, :ok, %{s | close_reason: "consumer_down"}}
        else
          _ -> {:stop, :normal, {:error, :text_consumer_unavailable}, s}
        end
      catch
        :exit, _ -> {:stop, :normal, {:error, :text_consumer_unavailable}, s}
      end
    else
      _ -> {:stop, :normal, {:error, :text_consumer_unavailable}, s}
    end
  end

  def handle_call(_, _, s), do: {:reply, {:error, :text_consumer_refused}, s}

  @impl true
  def handle_info({:ipse_text, broker, frame}, %{handle: %{server: broker}} = s) do
    sequence = Map.get(frame, "sequence", 0)
    payload = %{"api_version" => 1, "handle" => s.intent["resource_id"], "frame" => frame}

    with true <- frame["subscription_id"] == s.handle.subscription_id,
         true <- frame["session_id"] == s.intent["session_id"],
         true <- frame["kind"] == "closed" or sequence == s.sequence + 1,
         true <- Registry.live?(s.entry.identity),
         {:ok, reply} <- Worker.call(s.worker, "stream.text", payload),
         true <-
           reply == %{
             "api_version" => 1,
             "handle" => s.intent["resource_id"],
             "kind" => "ack",
             "sequence" => sequence
           },
         true <- Registry.live?(s.entry.identity),
         :ok <- acknowledge(s.handle, frame) do
      next = %{
        s
        | sequence: sequence,
          frames: s.frames + 1,
          bytes: s.bytes + byte_size(Map.get(frame, "text", ""))
      }

      if frame["kind"] == "closed" do
        {:stop, :normal, %{next | close_reason: "stream_closed"}}
      else
        {:noreply, next}
      end
    else
      _ ->
        {:stop, :normal, %{s | close_reason: "consumer_failed"}}
    end
  catch
    :exit, _ ->
      {:stop, :normal, %{s | close_reason: "consumer_failed"}}
  end

  def handle_info({:DOWN, ref, :process, _, _}, %{owner_ref: ref} = s),
    do: {:stop, :normal, s}

  def handle_info({:DOWN, ref, :process, _, _}, %{broker_ref: ref} = s) do
    {:stop, :normal, %{s | close_reason: "stream_closed"}}
  end

  def handle_info(_, s), do: {:noreply, s}

  @impl true
  def terminate(_, s) do
    cleanup = if is_pid(s.worker), do: Worker.close(s.worker), else: :ok

    if s.handle, do: unsubscribe(s.handle)

    send(
      s.owner,
      {:extension_text_closed, self(), s.intent["resource_id"], s.close_reason, s.frames, s.bytes,
       cleanup == :ok}
    )

    :ok
  end

  @impl true
  def format_status(status) do
    Map.new(status, fn
      {key, _} when key in [:state, :message, :reason, :log] -> {key, :private_text_consumer}
      item -> item
    end)
  end

  defp acknowledge(_, %{"kind" => "closed"}), do: :ok
  defp acknowledge(handle, frame), do: Ipse.TextStream.ack(handle, frame["sequence"])

  defp unsubscribe(handle) do
    Ipse.TextStream.unsubscribe(handle)
  catch
    :exit, _ -> :ok
  end
end
