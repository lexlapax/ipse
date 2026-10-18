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

  @doc "Sync exactly one record; a refused optional source never prevents the recovery append. Caller holds the lock."
  def append_observed(state_dir, id, event) when is_map(event) do
    with :ok <- validate_id(id),
         {:ok, encoded} <- Jason.encode(event),
         path = journal_path(state_dir, id),
         {:ok, contents} <- File.read(path),
         :ok <- validate_complete_journal(contents),
         source =
           (case Ipse.Lifecycle.Source.build(id, byte_size(contents), event) do
              {:ok, reference} -> reference
              _ -> nil
            end),
         :ok <- ensure_state_dir(state_dir),
         :ok <- append_sync(path, encoded <> "\n") do
      {:ok, source}
    end
  end

  @doc "Append and sync a record before returning its private, stable lifecycle source. Caller holds the session lock."
  def append_with_source(state_dir, id, event) when is_map(event) do
    with :ok <- validate_id(id),
         {:ok, encoded} <- Jason.encode(event),
         {:ok, decoded} <-
           Ipse.Extensions.Manifest.decode_json(encoded, Ipse.Lifecycle.Source.record_bytes()),
         path = journal_path(state_dir, id),
         {:ok, contents} <- File.read(path),
         :ok <- validate_complete_journal(contents),
         {:ok, source} <- Ipse.Lifecycle.Source.build(id, byte_size(contents), decoded),
         :ok <- ensure_state_dir(state_dir),
         :ok <- append_sync(path, encoded <> "\n") do
      {:ok, source}
    end
  end

  def append_with_source(_, _, _), do: {:error, :event_must_be_a_map}

  @doc "Read a bounded page of complete source records without replay or tail repair. Cursor is a record's byte offset."
  def source_page(state_dir, id, cursor \\ 0, limit \\ 32),
    do: source_page(state_dir, id, cursor, limit, nil)

  @doc "Optional exclusive upper byte boundary prevents a frozen history read from examining later records."
  def source_page(state_dir, id, cursor, limit, upper)
      when is_integer(cursor) and cursor in 0..9_007_199_254_740_991 and
             is_integer(limit) and limit in 1..64 and
             (is_nil(upper) or
                (is_integer(upper) and upper >= cursor and upper <= 9_007_199_254_740_991)) do
    with :ok <- validate_id(id),
         {:ok, file} <-
           :file.open(String.to_charlist(journal_path(state_dir, id)), [:read, :binary, :raw]) do
      try do
        with :ok <- source_boundary(file, cursor),
             :ok <- if(upper == nil, do: :ok, else: source_boundary(file, upper)) do
          read_sources(file, id, cursor, limit, 0, [], upper)
        end
      after
        :file.close(file)
      end
    end
  end

  def source_page(_, _, _, _, _), do: {:error, :invalid_source_page}

  def load(state_dir, id) do
    with :ok <- validate_id(id),
         {:ok, contents} <- File.read(journal_path(state_dir, id)),
         {:ok, events} <- decode_journal(contents) do
      {:ok, events}
    end
  end

  @doc "Repair only the final unterminated record. Caller must hold the session lock."
  def repair_tail(state_dir, id) do
    Ipse.FileEffect.run(fn -> repair(state_dir, id) end)
  end

  defp repair(state_dir, id) do
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

  @doc false
  def validate_complete(contents), do: validate_complete_journal(contents)

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

  defp source_boundary(_, 0), do: :ok

  defp source_boundary(file, cursor) do
    case :file.pread(file, cursor - 1, 1) do
      {:ok, "\n"} -> :ok
      _ -> {:error, :invalid_source_cursor}
    end
  end

  defp read_sources(_file, _id, cursor, _, _bytes, records, upper)
       when is_integer(upper) and cursor >= upper,
       do: {:ok, %{records: Enum.reverse(records), next: nil}}

  defp read_sources(_file, _id, cursor, 0, _bytes, records, _upper),
    do: {:ok, %{records: Enum.reverse(records), next: cursor}}

  defp read_sources(file, id, cursor, remaining, bytes, records, upper) do
    case source_line(file, cursor, <<>>, upper) do
      :eof ->
        {:ok, %{records: Enum.reverse(records), next: nil}}

      {:ok, line} ->
        if records != [] and bytes + byte_size(line) > Ipse.Lifecycle.Source.record_bytes() do
          {:ok, %{records: Enum.reverse(records), next: cursor}}
        else
          with {:ok, record} <-
                 Ipse.Extensions.Manifest.decode_json(line, Ipse.Lifecycle.Source.record_bytes()),
               true <- is_map(record),
               {:ok, source} <- Ipse.Lifecycle.Source.build(id, cursor, record) do
            read_sources(
              file,
              id,
              cursor + byte_size(line) + 1,
              remaining - 1,
              bytes + byte_size(line),
              [%{source: source, record: record} | records],
              upper
            )
          else
            _ -> {:error, :invalid_source_record}
          end
        end

      error ->
        error
    end
  end

  defp source_line(file, cursor, acc, upper) do
    limit = Ipse.Lifecycle.Source.record_bytes()
    remaining = limit + 1 - byte_size(acc)

    read = min(16_384, remaining)
    read = if upper == nil, do: read, else: min(read, upper - cursor - byte_size(acc))
    result = if read <= 0, do: :eof, else: :file.pread(file, cursor + byte_size(acc), read)

    case result do
      {:ok, chunk} ->
        case :binary.match(chunk, "\n") do
          {index, 1} ->
            {:ok, acc <> binary_part(chunk, 0, index)}

          :nomatch
          when byte_size(acc) + byte_size(chunk) > limit ->
            {:error, :source_record_too_large}

          :nomatch ->
            source_line(file, cursor, acc <> chunk, upper)
        end

      :eof when acc == <<>> ->
        :eof

      :eof ->
        {:error, :incomplete_source_record}

      {:error, _} ->
        {:error, :source_read_failed}
    end
  end
end
