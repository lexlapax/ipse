defmodule Ipse.Journal.Writer do
  @moduledoc "Session-owned durable appends; validates before linking and monitors normal owner exit."
  use GenServer
  alias Ipse.Lifecycle.Source

  def start(directory, id, owner)
      when is_binary(directory) and is_binary(id) and owner == self() do
    case GenServer.start(__MODULE__, {directory, id, owner}) do
      {:ok, writer} ->
        Process.link(writer)
        {:ok, writer}

      error ->
        error
    end
  end

  def start(_, _, _), do: {:error, :journal_unavailable}

  def append(writer, event), do: call(writer, {:append, :plain, event})
  def append_observed(writer, event), do: call(writer, {:append, :observed, event})
  def append_with_source(writer, event), do: call(writer, {:append, :source, event})
  def close(writer), do: call(writer, :close)

  defp call(writer, request) do
    GenServer.call(writer, request, 5_000)
  catch
    :exit, _ -> {:error, :journal_write_unconfirmed}
  end

  @impl true
  def init({directory, id, owner}) do
    with true <- is_pid(owner) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id),
         path = Path.join(directory, id <> ".jsonl"),
         {:ok, stat} <- File.lstat(path),
         true <- protected?(stat),
         {:ok, file} <- :file.open(String.to_charlist(path), [:read, :append, :binary, :raw]) do
      state = %{
        file: file,
        path: path,
        id: id,
        owner: owner,
        offset: stat.size,
        identity: identity(stat)
      }

      case validate_open(state) do
        :ok ->
          {:ok, Map.put(state, :monitor, Process.monitor(owner))}

        _ ->
          :file.close(file)
          {:stop, :journal_unavailable}
      end
    else
      _ -> {:stop, :journal_unavailable}
    end
  end

  @impl true
  def handle_call({:append, mode, event}, {owner, _}, %{owner: owner} = state)
      when mode in [:plain, :observed, :source] and is_map(event) do
    case encode(state, mode, event) do
      {:ok, line, result} ->
        with :ok <- unchanged(state),
             :ok <- :file.write(state.file, line),
             :ok <- :file.sync(state.file) do
          {:reply, result, %{state | offset: state.offset + byte_size(line)}}
        else
          _ -> {:stop, :normal, {:error, :journal_write_unconfirmed}, state}
        end

      _ ->
        {:reply, {:error, :journal_record_refused}, state}
    end
  end

  def handle_call(:close, {owner, _}, %{owner: owner} = state),
    do: {:stop, :normal, :ok, state}

  def handle_call(_, _, state), do: {:reply, {:error, :journal_owner_or_record_invalid}, state}

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
         {:ok, contents} <- :file.pread(state.file, 0, state.offset),
         :ok <- Ipse.Journal.validate_complete(contents),
         :ok <- unchanged(state) do
      :ok
    else
      _ -> {:error, :journal_unavailable}
    end
  end

  defp unchanged(state) do
    with {:ok, path_stat} <- File.lstat(state.path),
         {:ok, info} <- :file.read_file_info(state.file),
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

  defp encode(state, mode, event) do
    with {:ok, encoded} <- Jason.encode(event),
         {:ok, result} <- source(state, mode, event, encoded) do
      {:ok, encoded <> "\n", result}
    end
  rescue
    _ -> {:error, :journal_record_refused}
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
