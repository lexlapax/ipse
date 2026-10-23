defmodule Ipse.Session.TextStream do
  @moduledoc "Explicit private visible-text consumers with acknowledgment and bounded coalescing."
  use GenServer
  @bytes 65_536
  @frames 64
  @chunk 2_048
  @subscribers 4
  @deadline 5_000

  defmodule RequiredFailure do
    defexception message:
                   "Required visible-text delivery failed; inspect stream coverage before retrying."
  end

  def start(owner, session_id, policy_ref \\ nil),
    do: GenServer.start(__MODULE__, {owner, session_id, policy_ref})

  def subscribe(server, consumer, version \\ 1, required \\ false),
    do: GenServer.call(server, {:subscribe, consumer, version, required})

  def begin_with_policy(server, request_id, producer),
    do: GenServer.call(server, {:begin_with_policy, request_id, producer})

  def deliver(server, request_id, text, required) do
    result =
      try do
        push_delta(server, request_id, text)
      catch
        :exit, _ -> {:error, :text_stream_unavailable}
      end

    if required and result != :ok, do: raise(RequiredFailure)
    :ok
  end

  def check(server, request_id), do: GenServer.call(server, {:check, request_id})

  def enrolled?(nil, _, _), do: false

  def enrolled?(server, id, consumer) do
    GenServer.call(server, {:enrolled, id, consumer}) == true
  catch
    :exit, _ -> false
  end

  def begin(server, request_id, producer),
    do: GenServer.call(server, {:begin, request_id, producer})

  def push(nil, _, _), do: :ok

  def push(server, request_id, text),
    do: GenServer.call(server, {:push, request_id, text}, 10_000)

  @doc false
  def push_delta(nil, _, _), do: :ok

  def push_delta(server, request_id, text) when is_binary(text) do
    if String.valid?(text),
      do: push_chunks(server, request_id, text),
      else: push(server, request_id, text)
  end

  def push_delta(server, request_id, text), do: push(server, request_id, text)

  defp push_chunks(server, request_id, text) when byte_size(text) <= @bytes,
    do: push(server, request_id, text)

  defp push_chunks(server, request_id, text) do
    size = utf8_boundary(text, @bytes)
    chunk = binary_part(text, 0, size)
    rest = binary_part(text, size, byte_size(text) - size)

    with :ok <- push(server, request_id, chunk),
         do: push_chunks(server, request_id, rest)
  end

  def finish(nil, _, _), do: :ok

  def finish(server, request_id, outcome),
    do: GenServer.call(server, {:finish, request_id, outcome}, 10_000)

  def ack(%{server: server, subscription_id: id}, sequence),
    do: GenServer.call(server, {:ack, id, sequence})

  def unsubscribe(%{server: server, subscription_id: id}),
    do: GenServer.call(server, {:unsubscribe, id})

  @impl true
  def init({owner, session_id, policy_ref}) do
    if is_pid(owner) and id?(session_id) do
      {:ok,
       %{
         owner: owner,
         policy_ref: policy_ref,
         monitor: Process.monitor(owner),
         session_id: session_id,
         epoch_id: Ipse.Usage.id(),
         subscribers: %{},
         lost_required: %{},
         active: nil,
         pending: nil
       }}
    else
      {:stop, :invalid_text_owner}
    end
  end

  @impl true
  def handle_call({:subscribe, consumer, version, required}, {owner, _}, %{owner: owner} = s)
      when is_pid(consumer) and version in [1, 2] and is_boolean(required) do
    if map_size(s.subscribers) + map_size(s.lost_required) < @subscribers and is_nil(s.active) do
      id = Ipse.Usage.id()

      sub = %{
        pid: consumer,
        monitor: Process.monitor(consumer),
        queue: [],
        bytes: 0,
        outstanding: nil,
        sequence: 0,
        version: version,
        required: required
      }

      handle = %{server: self(), subscription_id: id}
      next = put_in(s, [:subscribers, id], sub)
      policy_changed(next)
      {:reply, {:ok, handle}, next}
    else
      {:reply, {:error, :text_subscription_unavailable}, s}
    end
  end

  def handle_call({:enrolled, id, consumer}, {owner, _}, %{owner: owner} = s),
    do: {:reply, match?(%{pid: ^consumer}, s.subscribers[id]), s}

  def handle_call({:begin_with_policy, request_id, producer}, from, s) do
    required = required?(s)

    case handle_call({:begin, request_id, producer}, from, s) do
      {:reply, :ok, next} -> {:reply, {:ok, required}, next}
      other -> other
    end
  end

  def handle_call(
        {:check, request_id},
        {producer, _},
        %{active: %{request_id: request_id, producer: producer}} = s
      ),
      do: {:reply, delivery_status(s), s}

  def handle_call({:begin, request_id, producer}, {owner, _}, %{owner: owner, active: nil} = s)
      when is_pid(producer) do
    if id?(request_id) do
      s = %{
        s
        | active: %{
            request_id: request_id,
            producer: producer,
            stream_id: Ipse.Usage.id(),
            offset: 0,
            required_failed: map_size(s.lost_required) > 0
          }
      }

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
      s.active.required_failed ->
        {:reply, {:error, :required_text_consumer_closed}, s}

      map_size(s.subscribers) == 0 ->
        {:reply, :ok, s}

      not is_binary(text) or not String.valid?(text) or byte_size(text) > @bytes ->
        {:reply, {:error, :invalid_text_chunk}, close_all(s, "invalid_chunk")}

      text == "" ->
        {:reply, :ok, s}

      s.active.offset + byte_size(text) > 9_007_199_254_740_991 ->
        {:reply, {:error, :text_position_limit}, close_all(s, "position_limit")}

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
               timer: timer,
               kind: :text
             }
         }}
    end
  end

  def handle_call(
        {:finish, request_id, outcome},
        {caller, _} = from,
        %{active: %{request_id: request_id}} = s
      )
      when outcome in ~w(completed failed cancelled unknown) and
             (caller == s.owner or caller == s.active.producer) do
    sealing = s.pending != nil and s.pending.kind == :finish
    outcome = if s.pending != nil and outcome == "completed", do: "unknown", else: outcome
    s = release_pending(s, {:error, :text_request_finished})

    s =
      if sealing do
        close_all(s, "request_finished")
      else
        enqueue_control(s, request_id, %{
          "kind" => "end",
          "outcome" => outcome,
          "complete" => outcome == "completed"
        })
      end

    if outcome == "completed" and delivery_status(s) == :ok and not required_drained?(s) do
      token = make_ref()
      timer = Process.send_after(self(), {:backpressure_timeout, token}, @deadline)

      {:noreply,
       %{
         s
         | pending: %{
             from: from,
             request_id: request_id,
             text: "",
             token: token,
             timer: timer,
             kind: :finish
           }
       }}
    else
      {:reply, delivery_status(s), %{s | active: nil}}
    end
  end

  def handle_call({:ack, id, sequence}, {consumer, _}, s) do
    case s.subscribers[id] do
      %{pid: ^consumer, outstanding: %{sequence: ^sequence}} = sub ->
        s = put_in(s, [:subscribers, id], pump(%{sub | outstanding: nil}, id, s))
        {:reply, :ok, flush_pending(s)}

      _ ->
        {:reply, {:error, :invalid_text_acknowledgment}, s}
    end
  end

  def handle_call({:unsubscribe, id}, {consumer, _}, s) do
    case {s.subscribers[id], s.lost_required[id]} do
      {%{pid: pid}, _} when consumer in [pid, s.owner] ->
        {:reply, :ok, flush_pending(remove(s, id, "unsubscribed"))}

      {nil, pid} when is_pid(pid) and consumer in [pid, s.owner] ->
        next = %{s | lost_required: Map.delete(s.lost_required, id)}
        policy_changed(next)
        {:reply, :ok, next}

      _ ->
        {:reply, {:error, :unknown_text_subscription}, s}
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
    blocked =
      Enum.filter(s.subscribers, fn {_, sub} ->
        if s.pending.kind == :finish,
          do: sub.required and (sub.outstanding != nil or sub.queue != []),
          else: not fits_sub?(sub, s.pending.text, s.active.stream_id)
      end)

    next = Enum.reduce(blocked, s, fn {id, _}, acc -> remove(acc, id, "backpressure_timeout") end)
    {:noreply, flush_pending(next)}
  end

  def handle_info(_, s), do: {:noreply, s}

  @impl true
  def format_status(status) do
    Map.new(status, fn
      {key, _} when key in [:state, :message, :reason, :log] -> {key, :private_text_stream}
      item -> item
    end)
  end

  defp fits?(s, _request_id, text) do
    Enum.all?(s.subscribers, fn {_, sub} ->
      fits_sub?(sub, text, s.active.stream_id)
    end)
  end

  defp fits_sub?(sub, text, stream_id),
    do:
      sub.bytes + byte_size(text) <= @bytes and
        (length(sub.queue) < @frames or coalescible?(List.last(sub.queue), stream_id))

  defp delivery_status(%{active: %{required_failed: true}}),
    do: {:error, :required_text_consumer_closed}

  defp delivery_status(_), do: :ok

  defp required_drained?(s),
    do:
      Enum.all?(s.subscribers, fn {_, sub} ->
        not sub.required or (sub.outstanding == nil and sub.queue == [])
      end)

  defp enqueue_text(s, request_id, text) do
    subscribers =
      Map.new(s.subscribers, fn {id, sub} ->
        frame = %{
          "kind" => "text",
          "request_id" => request_id,
          "text" => text,
          "stream_id" => s.active.stream_id,
          "offset" => s.active.offset
        }

        queue =
          if coalescible?(List.last(sub.queue), s.active.stream_id) do
            List.update_at(sub.queue, -1, &Map.update!(&1, "text", fn prior -> prior <> text end))
          else
            sub.queue ++ [frame]
          end

        {id, pump(%{sub | queue: queue, bytes: sub.bytes + byte_size(text)}, id, s)}
      end)

    %{
      s
      | subscribers: subscribers,
        active: %{s.active | offset: s.active.offset + byte_size(text)}
    }
  end

  defp enqueue_control(s, request_id, fields) do
    Enum.reduce(s.subscribers, s, fn {id, sub}, acc ->
      if length(sub.queue) >= @frames do
        remove(acc, id, "control_queue_full")
      else
        frame =
          Map.merge(fields, %{
            "request_id" => request_id,
            "stream_id" => s.active.stream_id,
            "offset" => s.active.offset
          })

        sub = pump(%{sub | queue: sub.queue ++ [frame]}, id, s)
        put_in(acc, [:subscribers, id], sub)
      end
    end)
  end

  defp pump(%{outstanding: nil, queue: [frame | tail]} = sub, id, context) do
    {frame, queue, bytes} =
      case frame do
        %{"kind" => "text", "text" => text} ->
          size = utf8_boundary(text, min(byte_size(text), @chunk))
          chunk = binary_part(text, 0, size)
          rest = binary_part(text, size, byte_size(text) - size)

          queue =
            if rest == "",
              do: tail,
              else: [frame |> Map.put("text", rest) |> Map.update!("offset", &(&1 + size)) | tail]

          {Map.put(frame, "text", chunk), queue, sub.bytes - size}

        _ ->
          {frame, tail, sub.bytes}
      end

    sequence = sub.sequence + 1

    payload =
      Map.merge(frame, %{
        "version" => sub.version,
        "session_id" => context.session_id,
        "generation" => 1,
        "stream_id" => if(sub.version == 1, do: frame["request_id"], else: frame["stream_id"]),
        "subscription_id" => id,
        "sequence" => sequence
      })

    payload =
      if sub.version == 2,
        do:
          Map.put(
            payload,
            "source",
            frame_source(context.epoch_id, payload, frame["offset"])
          ),
        else: payload

    payload = Map.delete(payload, "offset")

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

  defp flush_pending(%{active: %{required_failed: true}} = s) do
    finishing = s.pending.kind == :finish
    s = release_pending(s, {:error, :required_text_consumer_closed})
    if finishing, do: %{s | active: nil}, else: s
  end

  defp flush_pending(%{pending: %{kind: :finish}} = s) do
    if required_drained?(s), do: %{release_pending(s, :ok) | active: nil}, else: s
  end

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
      {:ipse_text, self(), closed_frame(s, id, sub, reason)}
    )

    active =
      if s.active != nil and sub.required, do: %{s.active | required_failed: true}, else: s.active

    lost =
      if sub.required and reason != "unsubscribed",
        do: Map.put(s.lost_required, id, sub.pid),
        else: s.lost_required

    next = %{s | subscribers: Map.delete(s.subscribers, id), active: active, lost_required: lost}
    policy_changed(next)
    next
  end

  defp required?(s),
    do: map_size(s.lost_required) > 0 or Enum.any?(s.subscribers, fn {_, sub} -> sub.required end)

  defp policy_changed(%{policy_ref: nil}), do: :ok
  defp policy_changed(s), do: send(s.owner, {:text_policy, self(), s.policy_ref, required?(s)})

  defp closed_frame(s, id, sub, reason) do
    frame = %{
      "version" => sub.version,
      "kind" => "closed",
      "subscription_id" => id,
      "session_id" => s.session_id,
      "complete" => false,
      "reason" => reason,
      "unsent_bytes" => sub.bytes,
      "unsent_frames" => length(sub.queue),
      "pending_bytes" => if(s.pending, do: byte_size(s.pending.text), else: 0),
      "unacknowledged_bytes" => if(sub.outstanding, do: sub.outstanding.bytes, else: 0)
    }

    if sub.version == 2,
      do: Map.put(frame, "source", frame_source(s.epoch_id, frame, 0)),
      else: frame
  end

  defp close_all(s, reason), do: Enum.reduce(Map.keys(s.subscribers), s, &remove(&2, &1, reason))
  defp coalescible?(%{"kind" => "text", "stream_id" => id}, id), do: true
  defp coalescible?(_, _), do: false

  defp utf8_boundary(text, size) do
    if String.valid?(binary_part(text, 0, size)), do: size, else: utf8_boundary(text, size - 1)
  end

  defp id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)

  @normal ~w(version kind session_id generation stream_id request_id subscription_id sequence source)
  @closed ~w(version kind subscription_id session_id complete reason unsent_bytes unsent_frames pending_bytes unacknowledged_bytes source)
  @reasons ~w(unsubscribed consumer_down owner_down invalid_chunk backpressure_timeout control_queue_full position_limit request_finished)
  @types %{
    "start" => "text.started",
    "text" => "text.delta",
    "end" => "text.finished",
    "closed" => "text.subscription_closed"
  }
  @max 9_007_199_254_740_991

  def frame_source(epoch, frame, offset) do
    base = %{
      "version" => 1,
      "kind" => "ephemeral",
      "session_id" => frame["session_id"],
      "epoch_id" => epoch
    }

    body =
      if frame["kind"] == "closed" do
        Map.merge(base, %{
          "scope" => "subscription",
          "subscription_id" => frame["subscription_id"]
        })
      else
        Map.merge(base, %{
          "scope" => "stream",
          "stream_id" => frame["stream_id"],
          "request_id" => frame["request_id"],
          "start_byte" => offset,
          "end_byte" => offset + byte_size(frame["text"] || "")
        })
      end

    Map.put(body, "event_id", identity(body, frame["kind"]))
  end

  def project_frame(frame, view) do
    with true <- valid_frame?(frame),
         {:ok, data} <- data(frame, view),
         event = %{
           "version" => 1,
           "data_version" => 1,
           "event_id" => frame["source"]["event_id"],
           "type" => @types[frame["kind"]],
           "source" => frame["source"],
           "origin" => "host",
           "view" => view,
           "correlations" =>
             if(frame["kind"] == "closed", do: %{}, else: Map.take(frame, ["request_id"])),
           "data" => data
         },
         :ok <- Ipse.Extension.validate(event) do
      {:ok, event}
    else
      _ -> {:error, :invalid_ephemeral_event}
    end
  rescue
    _ -> {:error, :invalid_ephemeral_event}
  end

  def valid_frame?(frame) do
    source = frame["source"]

    frame["version"] === 2 and id?(frame["session_id"]) and id?(frame["subscription_id"]) and
      source["session_id"] == frame["session_id"] and valid_source?(source, frame["kind"]) and
      fields?(frame) and Ipse.Extension.validate(frame) == :ok
  rescue
    _ -> false
  end

  defp fields?(%{"kind" => "closed"} = f) do
    keys?(f, @closed) and f["complete"] === false and f["reason"] in @reasons and
      f["source"]["subscription_id"] == f["subscription_id"] and
      Enum.all?(~w(unsent_bytes unsent_frames pending_bytes unacknowledged_bytes), &uint?(f[&1]))
  end

  defp fields?(f) do
    extra =
      case f["kind"] do
        "start" -> []
        "text" -> ["text"]
        "end" -> ~w(outcome complete)
        _ -> ["unsupported"]
      end

    keys?(f, @normal ++ extra) and f["generation"] === 1 and id?(f["request_id"]) and
      id?(f["stream_id"]) and uint?(f["sequence"]) and f["sequence"] > 0 and
      f["stream_id"] == f["source"]["stream_id"] and f["request_id"] == f["source"]["request_id"] and
      position?(f)
  end

  defp position?(%{"kind" => "start", "source" => s}),
    do: s["start_byte"] == 0 and s["end_byte"] == 0

  defp position?(%{"kind" => "text", "source" => s, "text" => t}) do
    is_binary(t) and String.valid?(t) and byte_size(t) in 1..2048 and
      s["end_byte"] - s["start_byte"] == byte_size(t)
  end

  defp position?(%{"kind" => "end", "source" => s} = f) do
    s["start_byte"] == s["end_byte"] and f["outcome"] in ~w(completed failed cancelled unknown) and
      f["complete"] === (f["outcome"] == "completed")
  end

  defp position?(_), do: false

  defp valid_source?(s, kind) do
    s["version"] === 1 and s["kind"] == "ephemeral" and id?(s["session_id"]) and
      id?(s["epoch_id"]) and
      source_fields?(s, kind) and s["event_id"] == identity(Map.delete(s, "event_id"), kind)
  end

  defp source_fields?(s, "closed") do
    keys?(s, ~w(version kind session_id epoch_id scope subscription_id event_id)) and
      s["scope"] == "subscription" and id?(s["subscription_id"])
  end

  defp source_fields?(s, kind) when kind in ~w(start text end) do
    keys?(
      s,
      ~w(version kind session_id epoch_id scope stream_id request_id start_byte end_byte event_id)
    ) and
      s["scope"] == "stream" and id?(s["stream_id"]) and id?(s["request_id"]) and
      uint?(s["start_byte"]) and
      uint?(s["end_byte"]) and s["end_byte"] >= s["start_byte"]
  end

  defp source_fields?(_, _), do: false

  defp data(%{"kind" => "text", "text" => text}, "text.visible"), do: {:ok, %{"text" => text}}

  defp data(%{"kind" => "text", "text" => text}, "metadata"),
    do: {:ok, %{"output_bytes" => byte_size(text)}}

  defp data(%{"kind" => "start"}, "metadata"), do: {:ok, %{}}
  defp data(%{"kind" => "end"} = f, "metadata"), do: {:ok, Map.take(f, ~w(outcome complete))}

  defp data(%{"kind" => "closed"} = f, "metadata"),
    do:
      {:ok,
       Map.take(
         f,
         ~w(complete reason unsent_bytes unsent_frames pending_bytes unacknowledged_bytes)
       )}

  defp data(_, _), do: {:error, :unsupported_view}

  defp identity(body, kind),
    do:
      Ipse.JSON.digest([
        %{"domain" => "ipse.ephemeral.text.v1", "kind" => kind, "source" => body}
      ])
      |> binary_part(0, 32)

  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
  defp uint?(v), do: is_integer(v) and v in 0..@max
end
