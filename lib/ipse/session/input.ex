defmodule Ipse.Session.Input do
  @moduledoc "Bounded, volatile terminal observations bound to one Session input generation."
  use GenServer

  @limit 64
  @lifetime 300_000

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc false
  def start(binding, display, timeout, client, scope) do
    GenServer.call(__MODULE__, {:start, binding, display, timeout, client, scope})
  catch
    :exit, _ -> {:error, :operator_input_unavailable}
  end

  @doc false
  def await(lease, timeout) do
    GenServer.call(__MODULE__, {:await, lease}, timeout + 5_000)
  catch
    :exit, _ -> {:error, :operator_input_unavailable}
  end

  @doc false
  def consume(witness, text, binding) do
    GenServer.call(__MODULE__, {:consume, witness, text, binding})
  catch
    :exit, _ -> {:error, :invalid_input_witness}
  end

  @doc false
  def stage(witness, text, binding),
    do: GenServer.call(__MODULE__, {:stage, witness, text, binding})

  @doc false
  def submit(ticket, text, binding),
    do: GenServer.call(__MODULE__, {:submit, ticket, text, binding})

  @doc false
  def discard(witness), do: GenServer.call(__MODULE__, {:discard, witness})
  @doc false
  def cancel_read, do: GenServer.call(__MODULE__, :cancel_read)

  @doc false
  def invalidate do
    GenServer.call(__MODULE__, :invalidate)
  catch
    :exit, _ -> :ok
  end

  @impl true
  def init(_), do: {:ok, %{entries: %{}}}

  @impl true
  def handle_call(:invalidate, {caller, _}, s) do
    s =
      Enum.reduce(s.entries, s, fn {key, e}, acc ->
        if e.target == caller do
          reason =
            if e.binding[:channel_id],
              do: :operator_input_cancelled,
              else: :operator_input_unavailable

          if e.from, do: GenServer.reply(e.from, {:error, reason})
          remove(acc, key, e)
        else
          acc
        end
      end)

    {:reply, :ok, s}
  end

  def handle_call(:cancel_read, {caller, _}, s) do
    next =
      Enum.reduce(s.entries, s, fn {key, e}, acc ->
        if e.target == caller and Map.get(e, :kind) != :staged do
          if e.from, do: GenServer.reply(e.from, {:error, :operator_input_cancelled})
          remove(acc, key, e)
        else
          acc
        end
      end)

    {:reply, :ok, next}
  end

  def handle_call({:discard, witness}, {caller, _}, s) do
    case s.entries[witness] do
      %{target: ^caller} = e -> {:reply, :ok, remove(s, witness, e)}
      _ -> {:reply, {:error, :invalid_input_witness}, s}
    end
  end

  def handle_call({:stage, witness, text, binding}, {caller, _}, s) do
    case s.entries[witness] do
      %{target: ^caller, task: nil, observation: observation} = e when is_map(observation) ->
        staged =
          Enum.filter(s.entries, fn {_, entry} ->
            entry.target == caller and Map.get(entry, :kind) == :staged
          end)

        bytes =
          Enum.reduce(staged, 0, fn {_, entry}, n -> n + byte_size(entry.observation["text"]) end)

        if Map.get(e, :kind) != :staged and binding[:purpose] == "prompt" and
             valid_witness?(e, text, binding) and length(staged) < 16 and
             bytes + byte_size(text) <= 1_048_576 do
          if e.timer, do: Process.cancel_timer(e.timer)
          ticket = make_ref()
          next = s |> update_in([:entries], &Map.delete(&1, witness))
          next = put_in(next.entries[ticket], %{e | kind: :staged, timer: nil, expires: nil})
          {:reply, {:ok, ticket}, next}
        else
          {:reply, {:error, :invalid_input_witness}, remove(s, witness, e)}
        end

      _ ->
        {:reply, {:error, :invalid_input_witness}, s}
    end
  end

  def handle_call({:submit, ticket, text, binding}, {caller, _}, s) do
    case s.entries[ticket] do
      %{target: ^caller, kind: :staged, observation: o} = e ->
        valid =
          e.binding == binding and is_binary(text) and o["text"] == text and
            o["text_sha256"] == Ipse.JSON.sha256(text)

        result =
          if valid, do: {:ok, Map.delete(o, "text")}, else: {:error, :invalid_input_witness}

        {:reply, result, remove(s, ticket, e)}

      _ ->
        {:reply, {:error, :invalid_input_witness}, s}
    end
  end

  def handle_call({:start, binding, display, timeout, client, scope}, {target, _}, s) do
    cond do
      not valid_request?(target, binding, display, timeout) or not is_pid(client) or
        node(client) != node() or Ipse.Session.Lock.for_owner(target) == nil or
        not is_pid(scope) or not Process.alive?(scope) ->
        {:reply, {:error, :operator_input_unavailable}, s}

      map_size(s.entries) >= @limit or
          Enum.any?(s.entries, fn {_, e} ->
            (e.target == target and Map.get(e, :kind) != :staged) or e.task != nil
          end) ->
        {:reply, {:error, :operator_input_busy}, s}

      true ->
        input_owner = self()

        task =
          Task.Supervisor.async_nolink(Ipse.Tasks, fn ->
            worker = self()

            spawn(fn ->
              owner_ref = Process.monitor(input_owner)
              worker_ref = Process.monitor(worker)

              receive do
                {:DOWN, ^owner_ref, :process, _, _} -> Ipse.Session.Resources.stop_async(scope)
                {:DOWN, ^worker_ref, :process, _, _} -> :ok
              end
            end)

            Ipse.Session.Resources.await_ready(scope, input_owner)
            Ipse.Session.Resources.bind(scope)

            result =
              if binding[:channel_id],
                do: Ipse.Runner.operator_input(display, timeout, 2),
                else: Ipse.Runner.operator_input(display, timeout)

            if Ipse.Session.Resources.close(scope) == :ok,
              do: result,
              else: {:error, :operator_input_unavailable}
          end)

        key = make_ref()

        entry = %{
          target: target,
          kind: :observation,
          client: client,
          target_monitor: Process.monitor(target),
          client_monitor: Process.monitor(client),
          task: task,
          from: nil,
          cancelled: false,
          binding: binding,
          display_sha256: Ipse.JSON.sha256(display),
          observation: nil,
          expires: nil,
          timer: nil
        }

        case attach(scope, task) do
          :ok ->
            send(task.pid, {:cleanup_scope_ready, scope})
            {:reply, {:ok, key}, put_in(s.entries[key], entry)}

          :error ->
            Process.demonitor(task.ref, [:flush])
            Process.exit(task.pid, :kill)
            Ipse.Session.Resources.stop_async(scope)
            {:reply, {:error, :operator_input_unavailable}, remove(s, key, %{entry | task: nil})}
        end
    end
  end

  def handle_call({:await, key}, {client, _} = from, s) do
    case s.entries[key] do
      %{client: ^client, cancelled: false, from: nil, task: nil, observation: o} when is_map(o) ->
        {:reply, {:ok, o["text"], key}, s}

      %{client: ^client, cancelled: false, from: nil} = e ->
        {:noreply, put_in(s.entries[key], %{e | from: from})}

      _ ->
        {:reply, {:error, :operator_input_unavailable}, s}
    end
  end

  def handle_call({:consume, witness, text, binding}, {caller, _}, s) do
    case s.entries[witness] do
      %{target: ^caller, observation: observation} = entry
      when is_map(observation) ->
        valid =
          Map.get(entry, :kind) != :staged and valid_witness?(entry, text, binding)

        result =
          if valid,
            do: {:ok, Map.delete(observation, "text")},
            else: {:error, :invalid_input_witness}

        {:reply, result, remove(s, witness, entry)}

      _ ->
        {:reply, {:error, :invalid_input_witness}, s}
    end
  end

  @impl true
  def handle_info({ref, result}, s) when is_reference(ref) do
    case Enum.find(s.entries, fn {_, e} -> e.task != nil and e.task.ref == ref end) do
      {key, entry} ->
        Process.demonitor(ref, [:flush])
        Process.unlink(entry.task.pid)

        case {entry.cancelled, result} do
          {false, {:ok, %{"text" => text, "display_sha256" => hash} = observation}}
          when hash == entry.display_sha256 and
                 (byte_size(text) > 0 or is_map_key(entry.binding, :channel_id)) ->
            timer = Process.send_after(self(), {:expire, key}, @lifetime)

            entry = %{
              entry
              | task: nil,
                from: nil,
                observation: observation,
                expires: System.monotonic_time(:millisecond) + @lifetime,
                timer: timer
            }

            if s.entries[key].from, do: GenServer.reply(s.entries[key].from, {:ok, text, key})
            {:noreply, put_in(s.entries[key], entry)}

          _ ->
            reason =
              case result do
                {:error, reason}
                when reason in [
                       :operator_nonterminal,
                       :operator_input_cancelled,
                       :operator_input_eof,
                       :operator_cleanup_unconfirmed,
                       :operator_input_too_large,
                       :operator_input_invalid_utf8,
                       :operator_input_interrupted
                     ] ->
                  reason

                _ ->
                  :operator_input_unavailable
              end

            if entry.from, do: GenServer.reply(entry.from, {:error, reason})
            {:noreply, remove(s, key, %{entry | task: nil})}
        end

      nil ->
        {:noreply, s}
    end
  end

  def handle_info({:expire, key}, s) do
    case s.entries[key] do
      nil -> {:noreply, s}
      entry -> {:noreply, remove(s, key, entry)}
    end
  end

  def handle_info({:DOWN, ref, :process, _, _}, s) do
    s =
      Enum.reduce(s.entries, s, fn {key, e}, acc ->
        if ref in [e.target_monitor, e.client_monitor] or (e.task != nil and ref == e.task.ref) do
          if e.from != nil, do: GenServer.reply(e.from, {:error, :operator_input_unavailable})
          remove(acc, key, if(e.task != nil and ref == e.task.ref, do: %{e | task: nil}, else: e))
        else
          acc
        end
      end)

    {:noreply, s}
  end

  def handle_info(_, s), do: {:noreply, s}

  @impl true
  def format_status(status) do
    Map.new(status, fn
      {:state, s} -> {:state, %{pending_inputs: map_size(s.entries)}}
      {key, _} when key in [:message, :reason] -> {key, :redacted}
      {:log, _} -> {:log, []}
      pair -> pair
    end)
  end

  defp remove(s, key, e) do
    Process.demonitor(e.target_monitor, [:flush])
    Process.demonitor(e.client_monitor, [:flush])
    if e.timer, do: Process.cancel_timer(e.timer)

    if e.task do
      send(e.task.pid, :ipse_cancel_operator_input)
      put_in(s.entries[key], %{e | cancelled: true, from: nil})
    else
      %{s | entries: Map.delete(s.entries, key)}
    end
  end

  defp attach(scope, task) do
    case Ipse.Session.Resources.attach(scope, task.pid) do
      :ok -> :ok
      _ -> :error
    end
  catch
    :exit, _ -> :error
  end

  defp valid_request?(target, binding, display, timeout) do
    is_pid(target) and node(target) == node() and Process.alive?(target) and
      is_map(binding) and valid_binding?(binding) and
      is_binary(binding[:cwd]) and byte_size(binding.cwd) <= 4096 and
      valid_id?(binding[:session_id]) and valid_id?(binding[:generation]) and
      is_binary(display) and String.valid?(display) and
      byte_size(display) in 1..if(binding[:channel_id], do: 16_777_216, else: 8192) and
      Ipse.CLI.Terminal.escape(display) == display and
      is_integer(timeout) and timeout in 1000..600_000
  end

  defp valid_binding?(binding) do
    keys = Enum.sort(Map.keys(binding))

    keys == [:cwd, :generation, :session_id] or
      (keys == [:channel_id, :cwd, :generation, :purpose, :render_id, :session_id] and
         valid_id?(binding.channel_id) and
         binding.purpose in ["prompt", "question", "control", "draft"] and
         if(binding.purpose in ["question", "draft"],
           do: valid_id?(binding.render_id),
           else: binding.render_id == nil
         ))
  end

  defp valid_witness?(entry, text, binding) do
    entry.binding == binding and is_binary(text) and
      byte_size(text) <= if(binding[:channel_id], do: 1_048_576, else: 8192) and
      entry.observation["text_sha256"] == Ipse.JSON.sha256(text) and
      entry.observation["text"] == text and is_integer(entry.expires) and
      System.monotonic_time(:millisecond) < entry.expires
  end

  defp valid_id?(id), do: is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id)

  @doc false
  def received(session, turn, original, effective, observation) do
    %{
      "type" => "input_received",
      "version" => if(is_map(observation) and observation["version"] === 2, do: 2, else: 1),
      "session_id" => session,
      "turn_id" => turn,
      "source_id" => Ipse.Usage.id(),
      "text" => original,
      "text_sha256" => Ipse.JSON.sha256(original),
      "effective_sha256" => Ipse.JSON.sha256(effective),
      "origin" => if(observation == nil, do: "unattended_input", else: "interactive_operator"),
      "observation" => observation
    }
  end

  @doc false
  def validate_events(events, session_id \\ nil) do
    Enum.reduce_while(events, {MapSet.new(), nil}, fn
      %{"type" => "input_received"} = e, {seen, _pending} ->
        source = {:source, e["source_id"]}
        turn = {:turn, e["turn_id"]}

        observation =
          {:observation, if(is_map(e["observation"]), do: e["observation"]["event_id"])}

        if valid_event?(e, session_id) and not MapSet.member?(seen, source) and
             not MapSet.member?(seen, turn) and
             (e["observation"] == nil or not MapSet.member?(seen, observation)) do
          seen = seen |> MapSet.put(source) |> MapSet.put(turn)
          seen = if e["observation"] == nil, do: seen, else: MapSet.put(seen, observation)
          {:cont, {seen, e}}
        else
          {:halt, {:error, :invalid_input_origin}}
        end

      %{"type" => "message", "message" => %{"role" => "user"} = message}, {seen, pending}
      when is_map(pending) ->
        if is_binary(message["content"]) and String.valid?(message["content"]) and
             Ipse.JSON.sha256(message["content"]) == pending["effective_sha256"] do
          {:cont, {seen, nil}}
        else
          {:halt, {:error, :invalid_input_origin}}
        end

      _, state ->
        {:cont, state}
    end)
    |> case do
      {%MapSet{}, _} -> :ok
      error -> error
    end
  end

  defp valid_event?(e, id) do
    Enum.sort(Map.keys(e)) ==
      Enum.sort(
        ~w(type version session_id turn_id source_id text text_sha256 effective_sha256 origin observation)
      ) and
      e["version"] in [1, 2] and valid_id?(e["session_id"]) and
      (id == nil or e["session_id"] == id) and valid_id?(e["source_id"]) and
      valid_id?(e["turn_id"]) and
      is_binary(e["text"]) and String.valid?(e["text"]) and byte_size(e["text"]) in 1..1_048_576 and
      e["text_sha256"] == Ipse.JSON.sha256(e["text"]) and valid_hash?(e["effective_sha256"]) and
      case {e["origin"], e["observation"]} do
        {"unattended_input", nil} ->
          e["version"] === 1

        {"interactive_operator", o} when is_map(o) ->
          valid_observation?(o, e["text"], e["version"])

        _ ->
          false
      end
  end

  @doc false
  def valid_observation?(o, text, version) when is_map(o) and is_binary(text) do
    common =
      valid_id?(o["event_id"]) and valid_hash?(o["display_sha256"]) and
        o["text_sha256"] == Ipse.JSON.sha256(text)

    common and
      case version do
        1 ->
          Enum.sort(Map.keys(o)) == ~w(display_sha256 event_id text_sha256 version) and
            o["version"] === 1 and byte_size(text) <= 8192

        2 ->
          Enum.sort(Map.keys(o)) ==
            ~w(display_limit display_sha256 event_id input_limit text_sha256 version) and
            o["version"] === 2 and o["input_limit"] === 1_048_576 and
            o["display_limit"] === 16_777_216 and
            byte_size(text) <= 1_048_576

        _ ->
          false
      end
  end

  def valid_observation?(_, _, _), do: false

  defp valid_hash?(hash), do: is_binary(hash) and Regex.match?(~r/\A[0-9a-f]{64}\z/, hash)
end
