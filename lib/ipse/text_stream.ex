defmodule Ipse.TextStream do
  @moduledoc "Explicit private visible-text consumers with acknowledgment and bounded coalescing."
  use GenServer
  @bytes 65_536
  @frames 64
  @chunk 2_048
  @subscribers 4
  @deadline 5_000

  def start(owner, session_id), do: GenServer.start(__MODULE__, {owner, session_id})
  def subscribe(server, consumer), do: GenServer.call(server, {:subscribe, consumer})

  def begin(server, request_id, producer),
    do: GenServer.call(server, {:begin, request_id, producer})

  def push(nil, _, _), do: :ok

  def push(server, request_id, text),
    do: GenServer.call(server, {:push, request_id, text}, 10_000)

  def finish(nil, _, _), do: :ok

  def finish(server, request_id, outcome),
    do: GenServer.call(server, {:finish, request_id, outcome})

  def ack(%{server: server, subscription_id: id}, sequence),
    do: GenServer.call(server, {:ack, id, sequence})

  def unsubscribe(%{server: server, subscription_id: id}),
    do: GenServer.call(server, {:unsubscribe, id})

  @impl true
  def init({owner, session_id}) do
    if is_pid(owner) and id?(session_id) do
      {:ok,
       %{
         owner: owner,
         monitor: Process.monitor(owner),
         session_id: session_id,
         subscribers: %{},
         active: nil,
         pending: nil
       }}
    else
      {:stop, :invalid_text_owner}
    end
  end

  @impl true
  def handle_call({:subscribe, consumer}, {owner, _}, %{owner: owner} = s)
      when is_pid(consumer) do
    if map_size(s.subscribers) < @subscribers and is_nil(s.active) do
      id = Ipse.Usage.id()

      sub = %{
        pid: consumer,
        monitor: Process.monitor(consumer),
        queue: [],
        bytes: 0,
        outstanding: nil,
        sequence: 0
      }

      handle = %{server: self(), subscription_id: id}
      {:reply, {:ok, handle}, put_in(s, [:subscribers, id], sub)}
    else
      {:reply, {:error, :text_subscription_unavailable}, s}
    end
  end

  def handle_call({:begin, request_id, producer}, {owner, _}, %{owner: owner, active: nil} = s)
      when is_pid(producer) do
    if id?(request_id) do
      s = %{s | active: %{request_id: request_id, producer: producer}}
      {:reply, :ok, enqueue_control(s, request_id, %{"kind" => "start"})}
    else
      {:reply, {:error, :invalid_text_request}, s}
    end
  end

  def handle_call(
        {:push, request_id, text},
        {producer, _} = from,
        %{active: %{request_id: request_id, producer: producer}, pending: nil} = s
      ) do
    cond do
      map_size(s.subscribers) == 0 ->
        {:reply, :ok, s}

      not is_binary(text) or not String.valid?(text) or byte_size(text) > @bytes ->
        {:reply, {:error, :invalid_text_chunk}, close_all(s, "invalid_chunk")}

      text == "" ->
        {:reply, :ok, s}

      fits?(s, request_id, text) ->
        {:reply, :ok, enqueue_text(s, request_id, text)}

      true ->
        token = make_ref()
        timer = Process.send_after(self(), {:backpressure_timeout, token}, @deadline)

        {:noreply,
         %{
           s
           | pending: %{
               from: from,
               request_id: request_id,
               text: text,
               token: token,
               timer: timer
             }
         }}
    end
  end

  def handle_call(
        {:finish, request_id, outcome},
        {owner, _},
        %{owner: owner, active: %{request_id: request_id}} = s
      )
      when outcome in ~w(completed failed cancelled unknown) do
    outcome = if s.pending != nil and outcome == "completed", do: "unknown", else: outcome
    s = release_pending(s, {:error, :text_request_finished})

    s =
      enqueue_control(s, request_id, %{
        "kind" => "end",
        "outcome" => outcome,
        "complete" => outcome == "completed"
      })

    {:reply, :ok, %{s | active: nil}}
  end

  def handle_call({:ack, id, sequence}, {consumer, _}, s) do
    case s.subscribers[id] do
      %{pid: ^consumer, outstanding: %{sequence: ^sequence}} = sub ->
        s = put_in(s, [:subscribers, id], pump(%{sub | outstanding: nil}, id, s.session_id))
        {:reply, :ok, flush_pending(s)}

      _ ->
        {:reply, {:error, :invalid_text_acknowledgment}, s}
    end
  end

  def handle_call({:unsubscribe, id}, {consumer, _}, s) do
    case s.subscribers[id] do
      %{pid: ^consumer} -> {:reply, :ok, flush_pending(remove(s, id, "unsubscribed"))}
      _ -> {:reply, {:error, :unknown_text_subscription}, s}
    end
  end

  def handle_call(_, _, s), do: {:reply, {:error, :text_stream_refused}, s}

  @impl true
  def handle_info({:DOWN, ref, :process, _, _}, %{monitor: ref} = s),
    do: {:stop, :normal, close_all(s, "owner_down")}

  def handle_info({:DOWN, ref, :process, _, _}, s) do
    s =
      Enum.reduce(s.subscribers, s, fn {id, sub}, acc ->
        if sub.monitor == ref, do: remove(acc, id, "consumer_down"), else: acc
      end)

    {:noreply, flush_pending(s)}
  end

  def handle_info({:backpressure_timeout, token}, %{pending: %{token: token}} = s) do
    {:noreply,
     close_all(s, "backpressure_timeout") |> release_pending({:error, :text_backpressure_timeout})}
  end

  def handle_info(_, s), do: {:noreply, s}

  @impl true
  def format_status(status) do
    Map.new(status, fn
      {key, _} when key in [:state, :message, :reason, :log] -> {key, :private_text_stream}
      item -> item
    end)
  end

  defp fits?(s, request_id, text) do
    Enum.all?(s.subscribers, fn {_, sub} ->
      sub.bytes + byte_size(text) <= @bytes and
        (length(sub.queue) < @frames or coalescible?(List.last(sub.queue), request_id))
    end)
  end

  defp enqueue_text(s, request_id, text) do
    subscribers =
      Map.new(s.subscribers, fn {id, sub} ->
        frame = %{"kind" => "text", "request_id" => request_id, "text" => text}

        queue =
          if coalescible?(List.last(sub.queue), request_id) do
            List.update_at(sub.queue, -1, &Map.update!(&1, "text", fn prior -> prior <> text end))
          else
            sub.queue ++ [frame]
          end

        {id, pump(%{sub | queue: queue, bytes: sub.bytes + byte_size(text)}, id, s.session_id)}
      end)

    %{s | subscribers: subscribers}
  end

  defp enqueue_control(s, request_id, fields) do
    Enum.reduce(s.subscribers, s, fn {id, sub}, acc ->
      if length(sub.queue) >= @frames do
        remove(acc, id, "control_queue_full")
      else
        frame = Map.put(fields, "request_id", request_id)
        sub = pump(%{sub | queue: sub.queue ++ [frame]}, id, s.session_id)
        put_in(acc, [:subscribers, id], sub)
      end
    end)
  end

  defp pump(%{outstanding: nil, queue: [frame | tail]} = sub, id, session_id) do
    {frame, queue, bytes} =
      case frame do
        %{"kind" => "text", "text" => text} ->
          size = utf8_boundary(text, min(byte_size(text), @chunk))
          chunk = binary_part(text, 0, size)
          rest = binary_part(text, size, byte_size(text) - size)
          queue = if rest == "", do: tail, else: [Map.put(frame, "text", rest) | tail]
          {Map.put(frame, "text", chunk), queue, sub.bytes - size}

        _ ->
          {frame, tail, sub.bytes}
      end

    sequence = sub.sequence + 1

    payload =
      Map.merge(frame, %{
        "version" => 1,
        "session_id" => session_id,
        "generation" => 1,
        "stream_id" => frame["request_id"],
        "subscription_id" => id,
        "sequence" => sequence
      })

    send(sub.pid, {:ipse_text, self(), payload})

    %{
      sub
      | queue: queue,
        bytes: bytes,
        sequence: sequence,
        outstanding: %{sequence: sequence, bytes: byte_size(frame["text"] || "")}
    }
  end

  defp pump(sub, _, _), do: sub

  defp flush_pending(%{pending: nil} = s), do: s

  defp flush_pending(%{pending: pending} = s) do
    if fits?(s, pending.request_id, pending.text) do
      s |> enqueue_text(pending.request_id, pending.text) |> release_pending(:ok)
    else
      s
    end
  end

  defp release_pending(%{pending: nil} = s, _), do: s

  defp release_pending(%{pending: pending} = s, result) do
    Process.cancel_timer(pending.timer)
    GenServer.reply(pending.from, result)
    %{s | pending: nil}
  end

  defp remove(s, id, reason) do
    sub = s.subscribers[id]
    Process.demonitor(sub.monitor, [:flush])

    send(
      sub.pid,
      {:ipse_text, self(),
       %{
         "version" => 1,
         "kind" => "closed",
         "subscription_id" => id,
         "session_id" => s.session_id,
         "complete" => false,
         "reason" => reason,
         "unsent_bytes" => sub.bytes,
         "unsent_frames" => length(sub.queue),
         "pending_bytes" => if(s.pending, do: byte_size(s.pending.text), else: 0),
         "unacknowledged_bytes" => if(sub.outstanding, do: sub.outstanding.bytes, else: 0)
       }}
    )

    %{s | subscribers: Map.delete(s.subscribers, id)}
  end

  defp close_all(s, reason), do: Enum.reduce(Map.keys(s.subscribers), s, &remove(&2, &1, reason))
  defp coalescible?(%{"kind" => "text", "request_id" => id}, id), do: true
  defp coalescible?(_, _), do: false

  defp utf8_boundary(text, size) do
    if String.valid?(binary_part(text, 0, size)), do: size, else: utf8_boundary(text, size - 1)
  end

  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)
end
