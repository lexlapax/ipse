defmodule Ipse.Journal do
  @moduledoc "Durable bounded JSONL event journals for Ipse sessions."
  alias Ipse.Journal.{Limits, Reader, Writer}
  @id_re ~r/\A[0-9a-f]{32}\z/

  def create(state_dir, metadata, policy \\ nil)

  def create(state_dir, metadata, policy) when is_map(metadata) do
    with {:ok, limits} <- Limits.normalize(policy),
         :ok <- ensure_state_dir(state_dir),
         {:ok, encoded_metadata} <- Jason.encode(metadata),
         event = %{
           "type" => "session",
           "metadata" => Jason.decode!(encoded_metadata),
           "created_at" => now()
         },
         {:ok, encoded} <- Limits.encode(event, limits),
         :ok <- initial_capacity(encoded, limits) do
      id = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

      case write_new(journal_path(state_dir, id), encoded <> "\n") do
        :ok -> {:ok, id}
        error -> error
      end
    end
  end

  def create(_, _, _), do: {:error, :metadata_must_be_a_map}

  def append(state_dir, id, event), do: inactive_append(state_dir, id, event, :plain)
  def append_observed(state_dir, id, event), do: inactive_append(state_dir, id, event, :observed)
  def append_with_source(state_dir, id, event), do: inactive_append(state_dir, id, event, :source)

  defp inactive_append(state_dir, id, event, mode) when is_map(event) do
    Ipse.FileEffect.run(fn ->
      with :ok <- validate_id(id),
           {:ok, stats} <- Reader.path(journal_path(state_dir, id), nil, :validate),
           :ok <- complete(stats),
           :ok <- ensure_state_dir(state_dir),
           :ok <- normalize_inactive(journal_path(state_dir, id)) do
        Writer.append_inactive(state_dir, id, event, mode)
      end
    end)
  end

  defp inactive_append(_, _, _, _), do: {:error, :event_must_be_a_map}

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

  def load(state_dir, id, policy \\ nil) do
    with :ok <- validate_id(id),
         {:ok, stats} <- Reader.path(journal_path(state_dir, id), policy) do
      {:ok, stats.events}
    end
  end

  @doc "Read only a bounded discovery header; this does not validate the later history."
  def header(state_dir, id) do
    with :ok <- validate_id(id),
         {:ok, %{header: header}} <- Reader.path(journal_path(state_dir, id), nil, :header),
         do: {:ok, header}
  end

  @doc "Repair only a bounded final unterminated record. Caller holds the session lock."
  def repair_tail(state_dir, id, policy \\ nil) do
    Ipse.FileEffect.run(fn -> repair(state_dir, id, policy) end)
  end

  defp repair(state_dir, id, policy) do
    with :ok <- validate_id(id),
         {:ok, limits} <- Limits.normalize(policy),
         path = journal_path(state_dir, id),
         {:ok, %{type: :regular}} <- File.lstat(path),
         {:ok, stats} <- Reader.path(path, limits, :validate) do
      max_bytes = limits["max_bytes"]

      case stats.tail do
        :none ->
          complete(stats)

        :valid when stats.bytes + 1 > max_bytes ->
          {:error, :journal_limit_reached}

        tail ->
          with {:ok, file} <- :file.open(String.to_charlist(path), [:read, :write, :binary, :raw]) do
            try do
              if tail == :valid do
                with {:ok, _} <- :file.position(file, :eof),
                     :ok <- :file.write(file, "\n"),
                     do: :file.sync(file)
              else
                with {:ok, _} <- :file.position(file, stats.complete_offset),
                     :ok <- :file.truncate(file),
                     do: :file.sync(file)
              end
            after
              :file.close(file)
            end
          end
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_journal}
    end
  end

  @doc "Discover bounded session headers; this does not validate later history."
  def list(state_dir) do
    case File.ls(state_dir) do
      {:ok, names} ->
        names
        |> Enum.flat_map(fn filename ->
          id = String.replace_suffix(filename, ".jsonl", "")

          if filename == id <> ".jsonl" and Regex.match?(@id_re, id) do
            case Reader.path(journal_path(state_dir, id), nil, :header) do
              {:ok, %{header: %{"type" => "session", "metadata" => metadata}}}
              when is_map(metadata) ->
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
    with :ok <- File.mkdir_p(path), :ok <- File.chmod(path, 0o700), do: :ok
  end

  defp normalize_inactive(path) do
    with {:ok, %{type: :regular, links: 1}} <- File.lstat(path),
         :ok <- File.chmod(path, 0o600) do
      :ok
    else
      {:error, _} = error -> error
      _ -> {:error, :journal_unavailable}
    end
  end

  defp write_new(path, bytes) do
    with {:ok, file} <- File.open(path, [:write, :binary, :exclusive]) do
      try do
        with :ok <- File.chmod(path, 0o600), :ok <- IO.binwrite(file, bytes), do: :file.sync(file)
      after
        File.close(file)
      end
    end
  end

  defp initial_capacity(encoded, limits) do
    if byte_size(encoded) + 1 + Limits.reserve_bytes() <= limits["max_bytes"],
      do: :ok,
      else: {:error, :journal_limit_reached}
  end

  defp validate_id(id) when is_binary(id) do
    if Regex.match?(@id_re, id), do: :ok, else: {:error, :invalid_id}
  end

  defp validate_id(_), do: {:error, :invalid_id}
  defp journal_path(state_dir, id), do: Path.join(state_dir, id <> ".jsonl")

  @doc false
  def validate_complete(contents) do
    with {:ok, stats} <- Reader.binary(contents), do: complete(stats)
  end

  defp complete(%{count: count, tail: :none}) when count > 0, do: :ok
  defp complete(_), do: {:error, :incomplete_journal}
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
                 Ipse.JSON.decode_bounded(line, Ipse.Lifecycle.Source.record_bytes()),
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
