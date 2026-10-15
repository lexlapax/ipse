defmodule Ipse.Journal do
  @moduledoc "Durable JSONL event journals for Ipse sessions."

  @id_re ~r/\A[0-9a-f]{32}\z/

  def create(state_dir, metadata) when is_map(metadata) do
    with :ok <- ensure_state_dir(state_dir),
         {:ok, encoded_metadata} <- Jason.encode(metadata) do
      id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

      event = %{
        "type" => "session",
        "metadata" => Jason.decode!(encoded_metadata),
        "created_at" => now()
      }

      case write_new(journal_path(state_dir, id), event) do
        :ok -> {:ok, id}
        error -> error
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def create(_state_dir, _metadata), do: {:error, :metadata_must_be_a_map}

  def append(state_dir, id, event) when is_map(event) do
    with :ok <- validate_id(id),
         {:ok, encoded} <- Jason.encode(event),
         path = journal_path(state_dir, id),
         {:ok, contents} <- File.read(path),
         :ok <- validate_complete_journal(contents),
         :ok <- ensure_state_dir(state_dir),
         :ok <- append_sync(path, encoded <> "\n") do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def append(_state_dir, _id, _event), do: {:error, :event_must_be_a_map}

  def load(state_dir, id) do
    with :ok <- validate_id(id),
         {:ok, contents} <- File.read(journal_path(state_dir, id)),
         {:ok, events} <- decode_journal(contents) do
      {:ok, events}
    end
  end

  @doc "Repair only the final unterminated record. Caller must hold the session lock."
  def repair_tail(state_dir, id) do
    with :ok <- validate_id(id),
         path = journal_path(state_dir, id),
         {:ok, %{type: :regular}} <- File.lstat(path),
         {:ok, contents} <- File.read(path) do
      if String.ends_with?(contents, "\n") do
        validate_complete_journal(contents)
      else
        offset =
          case List.last(:binary.matches(contents, "\n")) do
            {index, 1} -> index + 1
            nil -> 0
          end

        prefix = binary_part(contents, 0, offset)
        tail = binary_part(contents, offset, byte_size(contents) - offset)

        with {:ok, _} <- decode_complete_lines(String.split(prefix, "\n") |> Enum.drop(-1)),
             {:ok, file} <- :file.open(String.to_charlist(path), [:read, :write, :binary]) do
          try do
            case Jason.decode(tail) do
              {:ok, _} ->
                with {:ok, _} <- :file.position(file, :eof),
                     :ok <- :file.write(file, "\n"),
                     do: :file.sync(file)

              {:error, _} ->
                with {:ok, _} <- :file.position(file, offset),
                     :ok <- :file.truncate(file),
                     do: :file.sync(file)
            end
          after
            :file.close(file)
          end
        end
      end
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_journal}
    end
  end

  def list(state_dir) do
    case File.ls(state_dir) do
      {:ok, names} ->
        names
        |> Enum.flat_map(fn filename ->
          id = String.replace_suffix(filename, ".jsonl", "")

          if filename == id <> ".jsonl" and Regex.match?(@id_re, id) do
            case load(state_dir, id) do
              {:ok, [%{"type" => "session", "metadata" => metadata} | _]} ->
                [%{"id" => id, "metadata" => metadata}]

              _ ->
                []
            end
          else
            []
          end
        end)
        |> Enum.sort_by(& &1["id"])

      _ ->
        []
    end
  end

  defp ensure_state_dir(path) do
    with :ok <- File.mkdir_p(path),
         :ok <- File.chmod(path, 0o700) do
      :ok
    end
  end

  defp write_new(path, event) do
    with {:ok, encoded} <- Jason.encode(event),
         {:ok, file} <- File.open(path, [:write, :binary, :exclusive]) do
      try do
        with :ok <- File.chmod(path, 0o600),
             :ok <- IO.binwrite(file, encoded <> "\n"),
             :ok <- :file.sync(file) do
          :ok
        end
      after
        File.close(file)
      end
    end
  end

  defp append_sync(path, data) do
    with {:ok, file} <- File.open(path, [:append, :binary]) do
      try do
        with :ok <- File.chmod(path, 0o600),
             :ok <- IO.binwrite(file, data),
             :ok <- :file.sync(file) do
          :ok
        end
      after
        File.close(file)
      end
    end
  end

  defp validate_id(id) when is_binary(id) do
    if Regex.match?(@id_re, id), do: :ok, else: {:error, :invalid_id}
  end

  defp validate_id(_), do: {:error, :invalid_id}

  defp journal_path(state_dir, id), do: Path.join(state_dir, id <> ".jsonl")

  defp validate_complete_journal(contents) do
    if contents == "" or not String.ends_with?(contents, "\n") do
      {:error, :incomplete_journal}
    else
      contents
      |> String.split("\n")
      |> Enum.drop(-1)
      |> Enum.reduce_while(:ok, fn line, :ok ->
        case Jason.decode(line) do
          {:ok, _} -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, {:corrupt_journal, reason}}}
        end
      end)
    end
  end

  defp decode_journal(contents) do
    lines = String.split(contents, "\n")

    {complete_lines, tail} =
      if String.ends_with?(contents, "\n"),
        do: {Enum.drop(lines, -1), nil},
        else: {Enum.drop(lines, -1), List.last(lines)}

    with {:ok, events} <- decode_complete_lines(complete_lines),
         {:ok, events} <- decode_optional_tail(tail, events) do
      {:ok, events}
    end
  end

  defp decode_complete_lines(lines) do
    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, events} ->
      case Jason.decode(line) do
        {:ok, event} -> {:cont, {:ok, [event | events]}}
        {:error, reason} -> {:halt, {:error, {:corrupt_journal, reason}}}
      end
    end)
    |> case do
      {:ok, events} -> {:ok, Enum.reverse(events)}
      error -> error
    end
  end

  defp decode_optional_tail(nil, events), do: {:ok, events}
  defp decode_optional_tail("", events), do: {:ok, events}

  defp decode_optional_tail(tail, events) do
    case Jason.decode(tail) do
      {:ok, event} -> {:ok, events ++ [event]}
      {:error, _reason} -> {:ok, events}
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
