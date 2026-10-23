defmodule Ipse.Journal do
  @moduledoc "Durable bounded JSONL event journals for Ipse sessions."

  alias Ipse.Journal.Writer
  @id_re ~r/\A[0-9a-f]{32}\z/

  def create(state_dir, metadata, policy \\ nil)

  def create(state_dir, metadata, policy) when is_map(metadata) do
    with {:ok, limits} <- normalize_limits(policy),
         :ok <- ensure_state_dir(state_dir),
         {:ok, encoded_metadata} <- Jason.encode(metadata),
         event = %{
           "type" => "session",
           "metadata" => Jason.decode!(encoded_metadata),
           "created_at" => now()
         },
         {:ok, encoded} <- encode_event(event, limits),
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
    Ipse.Session.Resources.file_effect(fn ->
      with :ok <- validate_id(id),
           {:ok, stats} <- read_path(journal_path(state_dir, id), nil, :validate),
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
         {:ok, stats} <- read_path(journal_path(state_dir, id), policy) do
      {:ok, stats.events}
    end
  end

  @doc "Read only a bounded discovery header; this does not validate the later history."
  def header(state_dir, id) do
    with :ok <- validate_id(id),
         {:ok, %{header: header}} <- read_path(journal_path(state_dir, id), nil, :header),
         do: {:ok, header}
  end

  @doc "Repair only a bounded final unterminated record. Caller holds the session lock."
  def repair_tail(state_dir, id, policy \\ nil) do
    Ipse.Session.Resources.file_effect(fn -> repair(state_dir, id, policy) end)
  end

  defp repair(state_dir, id, policy) do
    with :ok <- validate_id(id),
         {:ok, limits} <- normalize_limits(policy),
         path = journal_path(state_dir, id),
         {:ok, %{type: :regular}} <- File.lstat(path),
         {:ok, stats} <- read_path(path, limits, :validate) do
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
            case read_path(journal_path(state_dir, id), nil, :header) do
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
    if byte_size(encoded) + 1 + reserve_bytes() <= limits["max_bytes"],
      do: :ok,
      else: {:error, :journal_limit_reached}
  end

  defp validate_id(id) when is_binary(id) do
    if Regex.match?(@id_re, id), do: :ok, else: {:error, :invalid_id}
  end

  defp validate_id(_), do: {:error, :invalid_id}
  defp journal_path(state_dir, id), do: Path.join(state_dir, id <> ".jsonl")

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
        if records != [] and bytes + byte_size(line) > source_record_bytes() do
          {:ok, %{records: Enum.reverse(records), next: cursor}}
        else
          with {:ok, record} <-
                 Ipse.JSON.decode_bounded(line, source_record_bytes()),
               true <- is_map(record),
               {:ok, source} <- source(id, cursor, record) do
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
    limit = source_record_bytes()
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

  @chunk 16_384

  def read_path(path, policy \\ nil, mode \\ :load) do
    with {:ok, limits} <- normalize_limits(policy),
         {:ok, %{type: :regular}} <- File.lstat(path),
         {:ok, file} <- :file.open(String.to_charlist(path), [:read, :binary, :raw]) do
      try do
        scan_file(file, limits, mode)
      after
        :file.close(file)
      end
    else
      {:ok, _} -> {:error, :invalid_journal}
      {:error, _} = error -> error
    end
  end

  def scan_file(file, policy, mode \\ :validate) do
    with {:ok, limits} <- normalize_limits(policy),
         {:ok, info} <- :file.read_file_info(file),
         stat = File.Stat.from_record(info),
         true <- stat.type == :regular,
         true <- mode == :header or stat.size <= limits["max_bytes"] do
      read_source({:file, file}, limits, mode)
    else
      false -> {:error, :journal_limit_reached}
      {:error, _} = error -> error
    end
  end

  def read_binary(contents, policy \\ nil) when is_binary(contents) do
    with {:ok, limits} <- normalize_limits(policy),
         true <- byte_size(contents) <= limits["max_bytes"] do
      read_source({:binary, contents}, limits, :validate)
    else
      false -> {:error, :journal_limit_reached}
      {:error, _} = error -> error
    end
  end

  defp read_source(source, limits, mode) do
    state = %{
      events: [],
      count: 0,
      offset: 0,
      read_offset: 0,
      parts: [],
      line_bytes: 0,
      buffer: <<>>,
      last_quota: nil
    }

    read_chunks(source, limits, mode, state)
  end

  defp read_chunks(source, limits, mode, %{buffer: <<>>} = state) do
    cap = if mode == :header, do: limits["max_record_bytes"] + 1, else: limits["max_bytes"]
    extra = if mode == :header, do: 0, else: 1
    amount = min(@chunk, cap - state.read_offset + extra)

    case pread_source(source, state.read_offset, max(amount, 1)) do
      {:ok, bytes} when byte_size(bytes) + state.read_offset > cap ->
        {:error, :journal_limit_reached}

      {:ok, bytes} ->
        read_chunks(source, limits, mode, %{
          state
          | buffer: bytes,
            read_offset: state.read_offset + byte_size(bytes)
        })

      :eof ->
        finish_read(state, limits, mode)

      {:error, _} = error ->
        error
    end
  end

  defp read_chunks(source, limits, mode, state) do
    case :binary.match(state.buffer, "\n") do
      {index, 1} ->
        size = state.line_bytes + index

        if size > limits["max_record_bytes"] do
          {:error, :journal_limit_reached}
        else
          prefix = binary_part(state.buffer, 0, index)
          line = IO.iodata_to_binary(Enum.reverse([prefix | state.parts]))

          with {:ok, next, event} <- decode_line(line, limits, mode, state) do
            if mode == :header do
              {:ok, %{header: event}}
            else
              rest = binary_part(state.buffer, index + 1, byte_size(state.buffer) - index - 1)

              read_chunks(source, limits, mode, %{
                next
                | offset: state.offset + size + 1,
                  buffer: rest,
                  parts: [],
                  line_bytes: 0
              })
            end
          end
        end

      :nomatch ->
        if state.line_bytes + byte_size(state.buffer) > limits["max_record_bytes"] do
          {:error, :journal_limit_reached}
        else
          read_chunks(source, limits, mode, %{
            state
            | parts: [state.buffer | state.parts],
              line_bytes: state.line_bytes + byte_size(state.buffer),
              buffer: <<>>
          })
        end
    end
  end

  defp decode_line(line, limits, mode, state) do
    cond do
      state.last_quota != nil ->
        {:error, :invalid_journal_limit_record}

      state.count >= limits["max_events"] ->
        {:error, :journal_limit_reached}

      true ->
        with {:ok, event} <- Jason.decode(line),
             :ok <- check_quota(event, state) do
          events = if mode == :load, do: [event | state.events], else: state.events

          {:ok,
           %{
             state
             | count: state.count + 1,
               events: events,
               last_quota:
                 if(is_map(event) and event["type"] == "journal_limit_reached", do: event)
           }, event}
        else
          {:error, %Jason.DecodeError{}} -> {:error, {:corrupt_journal, :invalid_json}}
          {:error, _} = error -> error
        end
    end
  end

  defp check_quota(%{"type" => "journal_limit_reached"} = event, state) do
    if valid_limit_receipt?(event) and event["byte_offset"] == state.offset and
         event["event_count"] == state.count,
       do: :ok,
       else: {:error, :invalid_journal_limit_record}
  end

  defp check_quota(_, _), do: :ok

  defp finish_read(%{line_bytes: 0}, _, :header), do: {:error, :invalid_journal}
  defp finish_read(%{line_bytes: 0} = state, _, _), do: read_result(state, :none)

  defp finish_read(state, limits, mode) do
    line = IO.iodata_to_binary(Enum.reverse(state.parts))

    case decode_line(line, limits, mode, state) do
      {:ok, _, event} when mode == :header -> {:ok, %{header: event}}
      {:ok, next, _} -> read_result(next, :valid)
      {:error, {:corrupt_journal, _}} when mode != :header -> read_result(state, :invalid)
      error -> error
    end
  end

  defp read_result(state, tail) do
    {:ok,
     %{
       events: Enum.reverse(state.events),
       count: state.count,
       bytes: state.read_offset,
       complete_offset: state.offset,
       tail: tail,
       last_quota: state.last_quota
     }}
  end

  defp pread_source({:file, file}, offset, bytes), do: :file.pread(file, offset, bytes)

  defp pread_source({:binary, contents}, offset, bytes) do
    if offset >= byte_size(contents),
      do: :eof,
      else: {:ok, binary_part(contents, offset, min(bytes, byte_size(contents) - offset))}
  end

  @ceilings %{
    "max_bytes" => 134_217_728,
    "max_events" => 100_000,
    "max_record_bytes" => 16_777_216
  }
  @minimums %{"max_bytes" => 1_024, "max_events" => 2, "max_record_bytes" => 512}
  @reserve 512

  def limits, do: @ceilings
  def reserve_bytes, do: @reserve

  def limit_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" =>
        Map.new(@ceilings, fn {key, maximum} ->
          {key, %{"type" => "integer", "minimum" => @minimums[key], "maximum" => maximum}}
        end)
    }
  end

  def normalize_limits(nil), do: {:ok, limits()}

  def normalize_limits(policy) when is_map(policy) do
    limits = Map.merge(limits(), policy)

    if Enum.all?(policy, fn {key, value} ->
         is_map_key(@ceilings, key) and is_integer(value) and
           value >= @minimums[key] and value <= @ceilings[key]
       end) and limits["max_record_bytes"] >= @reserve do
      {:ok, limits}
    else
      {:error, :invalid_journal_policy}
    end
  end

  def normalize_limits(_), do: {:error, :invalid_journal_policy}

  def resolve_limits(sources) do
    if Enum.any?(sources, &(&1.scope != "operator" and Map.has_key?(&1.data, "journal"))) do
      {:error, "Journal policy is operator-only; project configuration cannot replace it."}
    else
      normalize_limits(Enum.find_value(sources, & &1.data["journal"]))
    end
  end

  def encode_event(event, limits) do
    with {:ok, encoded} <- Jason.encode_to_iodata(event),
         true <- :erlang.iolist_size(encoded) <= limits["max_record_bytes"] do
      {:ok, IO.iodata_to_binary(encoded)}
    else
      false -> {:error, :journal_limit_reached}
      {:error, _} -> {:error, :journal_record_refused}
    end
  end

  def admit(limits, bytes, count, encoded_bytes) do
    cond do
      encoded_bytes > limits["max_record_bytes"] -> {:error, "record_bytes"}
      count + 2 > limits["max_events"] -> {:error, "events"}
      bytes + encoded_bytes + 1 + @reserve > limits["max_bytes"] -> {:error, "bytes"}
      true -> :ok
    end
  end

  def limit_receipt(limits, bytes, count, reason) do
    %{
      "type" => "journal_limit_reached",
      "version" => 1,
      "reason" => reason,
      "limits" => limits,
      "byte_offset" => bytes,
      "event_count" => count
    }
  end

  def valid_limit_receipt?(event) when is_map(event) do
    with true <-
           Enum.sort(Map.keys(event)) == ~w(byte_offset event_count limits reason type version),
         "journal_limit_reached" <- event["type"],
         1 <- event["version"],
         true <- event["reason"] in ~w(bytes events record_bytes),
         {:ok, limits} <- normalize_limits(event["limits"]),
         true <- limits == event["limits"],
         true <- is_integer(event["byte_offset"]) and event["byte_offset"] >= 0,
         true <- event["byte_offset"] + @reserve <= limits["max_bytes"],
         true <- is_integer(event["event_count"]) and event["event_count"] >= 1,
         true <- event["event_count"] + 1 <= limits["max_events"] do
      true
    else
      _ -> false
    end
  end

  def valid_limit_receipt?(_), do: false

  def writable_events(events) do
    case List.last(events) do
      %{"type" => "journal_limit_reached"} -> {:error, :journal_limit_reached}
      _ -> :ok
    end
  end

  def limit_summary(events) do
    case List.last(events) do
      %{"type" => "journal_limit_reached"} = receipt ->
        receipt
        |> Map.take(~w(reason limits byte_offset event_count))
        |> Map.put("status", "sealed")

      _ ->
        nil
    end
  end

  def validate_limit_events(events) when is_list(events) do
    Enum.reduce_while(events, {0, false}, fn
      _, {_, true} ->
        {:halt, {:error, :invalid_journal_limit_record}}

      %{"type" => "journal_limit_reached"} = event, {index, false} ->
        if valid_limit_receipt?(event) and event["event_count"] == index,
          do: {:cont, {index + 1, true}},
          else: {:halt, {:error, :invalid_journal_limit_record}}

      _, {index, false} ->
        {:cont, {index + 1, false}}
    end)
    |> case do
      {:error, _} = error -> error
      _ -> :ok
    end
  end

  def validate_limit_events(_), do: {:error, :invalid_journal_limit_record}

  @keys ~w(byte_offset event_id record_sha256 session_id version)
  @limit 1_048_576
  @error {:error, :invalid_lifecycle_source}

  def source_record_bytes, do: @limit

  def source(session, offset, record) when is_map(record) do
    with true <- id?(session) and offset?(offset),
         {:ok, encoded} <- Jason.encode(record),
         {:ok, decoded} <- Ipse.JSON.decode_bounded(encoded, @limit),
         true <- decoded == record do
      {:ok,
       %{
         "version" => 1,
         "session_id" => session,
         "byte_offset" => offset,
         "event_id" => event_id(session, offset),
         "record_sha256" => Ipse.JSON.digest([record])
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def source(_, _, _), do: @error

  def valid_source?(source) when is_map(source) do
    Enum.sort(Map.keys(source)) == @keys and source["version"] === 1 and
      id?(source["session_id"]) and offset?(source["byte_offset"]) and
      hash?(source["record_sha256"]) and
      source["event_id"] == event_id(source["session_id"], source["byte_offset"])
  rescue
    _ -> false
  end

  def valid_source?(_), do: false

  @doc "Validate a content-free source reference. This is identity, not data-access authority."
  def valid_source_metadata?(source) when is_map(source) do
    Enum.sort(Map.keys(source)) == ~w(byte_offset event_id session_id version) and
      source["version"] === 1 and id?(source["session_id"]) and offset?(source["byte_offset"]) and
      source["event_id"] == event_id(source["session_id"], source["byte_offset"])
  rescue
    _ -> false
  end

  def valid_source_metadata?(_), do: false

  def source_matches?(source, record) do
    with true <- valid_source?(source),
         {:ok, expected} <- source(source["session_id"], source["byte_offset"], record) do
      expected == source
    else
      _ -> false
    end
  end

  @doc "Content hashes stay private, even when the event reference is safe to correlate."
  def source_metadata(source) do
    if valid_source?(source),
      do: {:ok, Map.delete(source, "record_sha256")},
      else: @error
  end

  defp event_id(session, offset) do
    Ipse.JSON.sha256("ipse:journal:v1:" <> session <> ":" <> Integer.to_string(offset))
    |> binary_part(0, 32)
  end

  defp offset?(value), do: is_integer(value) and value in 0..9_007_199_254_740_991
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
  defp hash?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{64}\z/, value)
end
