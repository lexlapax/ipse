defmodule Ipse.Journal.Writer do
  @moduledoc "Session-owned durable appends; validates before linking and monitors normal owner exit."
  use GenServer
  alias Ipse.Journal

  def start(directory, id, owner, policy \\ nil)

  def start(directory, id, owner, policy)
      when is_binary(directory) and is_binary(id) and owner == self() do
    case GenServer.start(__MODULE__, {directory, id, owner, policy}) do
      {:ok, writer} ->
        Process.link(writer)
        {:ok, writer}

      error ->
        error
    end
  end

  def start(_, _, _, _), do: {:error, :journal_unavailable}

  def append(writer, event), do: call(writer, {:append, :plain, event})
  def append_observed(writer, event), do: call(writer, {:append, :observed, event})
  def append_with_source(writer, event), do: call(writer, {:append, :source, event})

  @doc false
  def install_source_window(writer, window), do: call(writer, {:source_window_install, window})
  @doc false
  def source_query(writer, request), do: call(writer, {:source_query, request})
  @doc false
  def ensure_source_window(writer), do: call(writer, :source_window_ensure)

  @doc "Reserves JSONL bytes, including newlines, and events while retaining quota-marker headroom."
  def reserve(writer, capacity), do: call(writer, {:reserve, capacity})

  @doc "Appends one plain record against an owner-only, writer-local reservation token."
  def append_reserved(writer, token, event),
    do: call(writer, {:append_reserved, token, :plain, event})

  def append_reserved_observed(writer, token, event),
    do: call(writer, {:append_reserved, token, :observed, event})

  @doc "Releases unused reserved capacity; already appended bytes and events remain charged."
  def release(writer, token), do: call(writer, {:release, token})

  def close(writer), do: call(writer, :close)

  @doc false
  def append_inactive(directory, id, event, mode)
      when is_map(event) and mode in [:plain, :observed, :source] do
    Ipse.Session.Resources.file_effect(fn ->
      with {:ok, state} <- open(directory, id, self(), nil) do
        try do
          case append_record(state, mode, event) do
            {:reply, result, _} -> result
            {:stop, :normal, result, _} -> result
          end
        after
          :file.close(state.file)
        end
      end
    end)
  end

  defp call(writer, request) do
    GenServer.call(writer, request, 5_000)
  catch
    :exit, _ -> {:error, :journal_write_unconfirmed}
  end

  @impl true
  def init({directory, id, owner, policy}) do
    case open(directory, id, owner, policy) do
      {:ok, state} -> {:ok, Map.put(state, :monitor, Process.monitor(owner))}
      {:error, reason} -> {:stop, reason}
    end
  end

  defp open(directory, id, owner, policy) do
    with {:ok, limits} <- Journal.normalize_limits(policy),
         true <- is_pid(owner) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id),
         path = Path.join(directory, id <> ".jsonl"),
         {:ok, stat} <- File.lstat(path),
         true <- protected?(stat),
         {:ok, file} <- :file.open(String.to_charlist(path), [:read, :append, :binary, :raw]) do
      state = %{
        file: file,
        path: path,
        id: id,
        owner: owner,
        lock_guard: Ipse.Session.Lock.for_owner(owner),
        offset: stat.size,
        count: 0,
        limits: limits,
        sealed: false,
        reservations: %{},
        reserved_bytes: 0,
        reserved_events: 0,
        identity: identity(stat),
        source_window: nil
      }

      case validate_open(state) do
        {:ok, count} ->
          {:ok, Map.put(state, :count, count)}

        {:error, :journal_limit_reached} ->
          :file.close(file)
          {:error, :journal_limit_reached}

        _ ->
          :file.close(file)
          {:error, :journal_unavailable}
      end
    else
      _ -> {:error, :journal_unavailable}
    end
  end

  @impl true
  def handle_call(
        {:source_window_install, %Ipse.Session.SourceWindow{} = window},
        {owner, _},
        %{owner: owner, source_window: nil, id: id} = state
      ) do
    if window.index.session_id == id,
      do: {:reply, :ok, %{state | source_window: window}},
      else: {:reply, {:error, :source_index_refused}, state}
  end

  def handle_call(
        {:source_query, query},
        {owner, _},
        %{owner: owner, source_window: window} = state
      )
      when not is_nil(window) do
    result =
      case query do
        :snapshot -> {:ok, Ipse.Session.SourceWindow.snapshot(window)}
        :effective_source -> {:ok, window.effective_source}
        {operation, request} -> Ipse.Session.SourceWindow.execute(window, operation, request)
        _ -> {:error, :source_index_refused}
      end

    {:reply, result, state}
  end

  def handle_call(
        :source_window_ensure,
        {owner, _},
        %{owner: owner, source_window: window} = state
      )
      when not is_nil(window) do
    if window.historical_window == window.index.window_id,
      do: {:reply, :ok, state},
      else: append_record(state, :plain, Ipse.Session.SourceWindow.opened(window))
  end

  def handle_call({:append, _, _}, {owner, _}, %{owner: owner, sealed: true} = state),
    do: {:reply, {:error, :journal_limit_reached}, state}

  def handle_call({:append, mode, event}, {owner, _}, %{owner: owner} = state)
      when mode in [:plain, :observed, :source] and is_map(event) do
    append_record(state, mode, event)
  end

  def handle_call({:reserve, _}, {owner, _}, %{owner: owner, sealed: true} = state),
    do: {:reply, {:error, :journal_limit_reached}, state}

  def handle_call({:reserve, capacity}, {owner, _}, %{owner: owner} = state) do
    case capacity do
      %{bytes: bytes, events: events}
      when map_size(capacity) == 2 and
             is_integer(bytes) and is_integer(events) and
             events > 0 and bytes >= events * 3 ->
        if available?(state, bytes, events) do
          case unchanged(state) do
            :ok ->
              token = make_ref()

              {:reply, {:ok, token},
               %{
                 state
                 | reservations: Map.put(state.reservations, token, capacity),
                   reserved_bytes: state.reserved_bytes + bytes,
                   reserved_events: state.reserved_events + events
               }}

            _ ->
              {:stop, :normal, {:error, :journal_write_unconfirmed}, state}
          end
        else
          {:reply, {:error, :journal_reservation_unavailable}, state}
        end

      _ ->
        {:reply, {:error, :journal_reservation_invalid}, state}
    end
  end

  def handle_call({:append_reserved, token, mode, event}, {owner, _}, %{owner: owner} = state)
      when is_map(event) and mode in [:plain, :observed] do
    case Map.fetch(state.reservations, token) do
      {:ok, capacity} -> append_reserved_record(state, token, capacity, mode, event)
      :error -> {:reply, {:error, :journal_reservation_invalid}, state}
    end
  end

  def handle_call({:release, token}, {owner, _}, %{owner: owner} = state) do
    case Map.pop(state.reservations, token) do
      {nil, _} ->
        {:reply, {:error, :journal_reservation_invalid}, state}

      {capacity, reservations} ->
        {:reply, :ok,
         %{
           state
           | reservations: reservations,
             reserved_bytes: state.reserved_bytes - capacity.bytes,
             reserved_events: state.reserved_events - capacity.events
         }}
    end
  end

  def handle_call(:close, {owner, _}, %{owner: owner} = state),
    do: {:stop, :normal, :ok, state}

  def handle_call(_, _, state), do: {:reply, {:error, :journal_owner_or_record_invalid}, state}

  defp append_record(state, mode, event) do
    case encode(state, mode, event) do
      {:ok, line, result} ->
        with :ok <- unchanged(state),
             :ok <- append_line(state, line) do
          {:reply, result,
           %{
             state
             | offset: state.offset + byte_size(line),
               count: state.count + 1,
               source_window: source_advance(state, event)
           }}
        else
          _ -> {:stop, :normal, {:error, :journal_write_unconfirmed}, state}
        end

      {:limit, reason} ->
        if map_size(state.reservations) == 0,
          do: seal(state, reason),
          else: {:reply, {:error, :journal_reservation_unavailable}, state}

      _ ->
        {:reply, {:error, :journal_record_refused}, state}
    end
  end

  defp append_reserved_record(state, token, capacity, mode, event) do
    case encode(%{state | reserved_bytes: 0, reserved_events: 0}, mode, event) do
      {:ok, line, result} ->
        if capacity.events > 0 and byte_size(line) <= capacity.bytes do
          with :ok <- unchanged(state),
               :ok <- append_line(state, line) do
            remaining = %{bytes: capacity.bytes - byte_size(line), events: capacity.events - 1}

            {:reply, result,
             %{
               state
               | offset: state.offset + byte_size(line),
                 count: state.count + 1,
                 reservations: Map.put(state.reservations, token, remaining),
                 reserved_bytes: state.reserved_bytes - byte_size(line),
                 reserved_events: state.reserved_events - 1,
                 source_window: source_advance(state, event)
             }}
          else
            _ -> {:stop, :normal, {:error, :journal_write_unconfirmed}, state}
          end
        else
          {:reply, {:error, :journal_reservation_exhausted}, state}
        end

      {:limit, _} ->
        {:reply, {:error, :journal_record_refused}, state}

      _ ->
        {:reply, {:error, :journal_record_refused}, state}
    end
  end

  defp available?(state, bytes, events) do
    state.offset + state.reserved_bytes + bytes + Journal.reserve_bytes() <=
      state.limits["max_bytes"] and
      state.count + state.reserved_events + events + 1 <= state.limits["max_events"]
  end

  defp source_advance(%{source_window: nil}, _), do: nil

  defp source_advance(state, event) do
    source =
      case Journal.source(state.id, state.offset, event) do
        {:ok, source} -> source
        _ -> nil
      end

    Ipse.Session.SourceWindow.advance(state.source_window, event, source)
  end

  @impl true
  def handle_info({:DOWN, ref, :process, owner, _}, %{monitor: ref, owner: owner} = state),
    do: {:stop, :normal, state}

  @impl true
  def terminate(_, state), do: :file.close(state.file)

  @impl true
  def format_status(status) do
    Map.new(status, fn
      {:state, state} -> {:state, Map.take(state, [:id, :offset])}
      {:message, _} -> {:message, :redacted}
      {:reason, _} -> {:reason, :redacted}
      {:log, _} -> {:log, []}
      pair -> pair
    end)
  end

  defp validate_open(state) do
    with :ok <- unchanged(state),
         {:ok, stats} <- Journal.scan_file(state.file, state.limits),
         true <- stats.tail == :none and stats.count > 0,
         :ok <- unchanged(state) do
      if stats.last_quota != nil or
           stats.bytes + Journal.reserve_bytes() > state.limits["max_bytes"] or
           stats.count + 1 > state.limits["max_events"],
         do: {:error, :journal_limit_reached},
         else: {:ok, stats.count}
    else
      {:error, :journal_limit_reached} = error -> error
      _ -> {:error, :journal_unavailable}
    end
  end

  defp append_line(state, line) do
    Ipse.Session.Resources.file_effect(
      fn ->
        with {:ok, file} <- :file.open(String.to_charlist(state.path), [:append, :binary, :raw]) do
          try do
            with :ok <- unchanged(state, file),
                 :ok <- :file.write(file, line),
                 do: :file.sync(file)
          after
            :file.close(file)
          end
        end
      end,
      state.lock_guard
    )
  end

  defp unchanged(state, file \\ nil) do
    with {:ok, path_stat} <- File.lstat(state.path),
         {:ok, info} <- :file.read_file_info(file || state.file),
         file_stat = File.Stat.from_record(info),
         true <- protected?(path_stat) and protected?(file_stat),
         true <- identity(path_stat) == state.identity and identity(file_stat) == state.identity,
         true <- path_stat.size == state.offset and file_stat.size == state.offset do
      :ok
    else
      _ -> {:error, :journal_changed}
    end
  end

  defp identity(stat), do: {stat.major_device, stat.minor_device, stat.inode, stat.uid}

  defp protected?(stat),
    do: stat.type == :regular and stat.links == 1 and Bitwise.band(stat.mode, 0o077) == 0

  defp encode(_state, _mode, %{"type" => "journal_limit_reached"}),
    do: {:error, :journal_record_refused}

  defp encode(state, mode, event) do
    with {:ok, encoded} <- Journal.encode_event(event, state.limits),
         {:ok, result} <- source(state, mode, event, encoded) do
      case Journal.admit(
             state.limits,
             state.offset + state.reserved_bytes,
             state.count + state.reserved_events,
             byte_size(encoded)
           ) do
        :ok -> {:ok, encoded <> "\n", result}
        {:error, reason} -> {:limit, reason}
      end
    else
      {:error, :journal_limit_reached} -> {:limit, "record_bytes"}
      error -> error
    end
  rescue
    _ -> {:error, :journal_record_refused}
  end

  defp seal(state, reason) do
    event = Journal.limit_receipt(state.limits, state.offset, state.count, reason)
    line = Jason.encode!(event) <> "\n"

    with true <- byte_size(line) <= Journal.reserve_bytes(),
         :ok <- unchanged(state),
         :ok <- append_line(state, line) do
      {:reply, {:error, :journal_limit_reached},
       %{state | sealed: true, offset: state.offset + byte_size(line), count: state.count + 1}}
    else
      _ -> {:stop, :normal, {:error, :journal_write_unconfirmed}, state}
    end
  end

  defp source(_, :plain, _, _), do: {:ok, :ok}

  defp source(state, :observed, event, _) do
    reference =
      case Journal.source(state.id, state.offset, event) do
        {:ok, reference} -> reference
        _ -> nil
      end

    {:ok, {:ok, reference}}
  end

  defp source(state, :source, _, encoded) do
    with {:ok, decoded} <- Ipse.JSON.decode_bounded(encoded, Journal.source_record_bytes()),
         {:ok, reference} <- Journal.source(state.id, state.offset, decoded) do
      {:ok, {:ok, reference}}
    end
  end
end
