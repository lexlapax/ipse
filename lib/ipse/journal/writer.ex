defmodule Ipse.Journal.Writer do
  @moduledoc "Session-owned durable appends; validates before linking and monitors normal owner exit."
  use GenServer
  alias Ipse.Lifecycle.Source
  alias Ipse.Journal.{Limits, Reader}

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
  def close(writer), do: call(writer, :close)

  @doc false
  def append_inactive(directory, id, event, mode)
      when is_map(event) and mode in [:plain, :observed, :source] do
    Ipse.FileEffect.run(fn ->
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
    with {:ok, limits} <- Limits.normalize(policy),
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
        identity: identity(stat)
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
  def handle_call({:append, _, _}, {owner, _}, %{owner: owner, sealed: true} = state),
    do: {:reply, {:error, :journal_limit_reached}, state}

  def handle_call({:append, mode, event}, {owner, _}, %{owner: owner} = state)
      when mode in [:plain, :observed, :source] and is_map(event) do
    append_record(state, mode, event)
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
           %{state | offset: state.offset + byte_size(line), count: state.count + 1}}
        else
          _ -> {:stop, :normal, {:error, :journal_write_unconfirmed}, state}
        end

      {:limit, reason} ->
        seal(state, reason)

      _ ->
        {:reply, {:error, :journal_record_refused}, state}
    end
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
         {:ok, stats} <- Reader.scan(state.file, state.limits),
         true <- stats.tail == :none and stats.count > 0,
         :ok <- unchanged(state) do
      if stats.last_quota != nil or
           stats.bytes + Limits.reserve_bytes() > state.limits["max_bytes"] or
           stats.count + 1 > state.limits["max_events"],
         do: {:error, :journal_limit_reached},
         else: {:ok, stats.count}
    else
      {:error, :journal_limit_reached} = error -> error
      _ -> {:error, :journal_unavailable}
    end
  end

  defp append_line(state, line) do
    Ipse.FileEffect.run(
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
    with {:ok, encoded} <- Limits.encode(event, state.limits),
         {:ok, result} <- source(state, mode, event, encoded) do
      case Limits.admit(state.limits, state.offset, state.count, byte_size(encoded)) do
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
    event = Limits.receipt(state.limits, state.offset, state.count, reason)
    line = Jason.encode!(event) <> "\n"

    with true <- byte_size(line) <= Limits.reserve_bytes(),
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
      case Source.build(state.id, state.offset, event) do
        {:ok, reference} -> reference
        _ -> nil
      end

    {:ok, {:ok, reference}}
  end

  defp source(state, :source, _, encoded) do
    with {:ok, decoded} <- Ipse.Extensions.Manifest.decode_json(encoded, Source.record_bytes()),
         {:ok, reference} <- Source.build(state.id, state.offset, decoded) do
      {:ok, {:ok, reference}}
    end
  end
end
