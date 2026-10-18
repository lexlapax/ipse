defmodule Ipse.Journal.Reader do
  @moduledoc "Incremental bounded JSONL decoding, validation and header discovery."
  alias Ipse.Journal.Limits
  @chunk 16_384

  def path(path, policy \\ nil, mode \\ :load) do
    with {:ok, limits} <- Limits.normalize(policy),
         {:ok, %{type: :regular}} <- File.lstat(path),
         {:ok, file} <- :file.open(String.to_charlist(path), [:read, :binary, :raw]) do
      try do
        scan(file, limits, mode)
      after
        :file.close(file)
      end
    else
      {:ok, _} -> {:error, :invalid_journal}
      {:error, _} = error -> error
    end
  end

  def scan(file, policy, mode \\ :validate) do
    with {:ok, limits} <- Limits.normalize(policy),
         {:ok, info} <- :file.read_file_info(file),
         stat = File.Stat.from_record(info),
         true <- stat.type == :regular,
         true <- mode == :header or stat.size <= limits["max_bytes"] do
      run({:file, file}, limits, mode)
    else
      false -> {:error, :journal_limit_reached}
      {:error, _} = error -> error
    end
  end

  def binary(contents, policy \\ nil) when is_binary(contents) do
    with {:ok, limits} <- Limits.normalize(policy),
         true <- byte_size(contents) <= limits["max_bytes"] do
      run({:binary, contents}, limits, :validate)
    else
      false -> {:error, :journal_limit_reached}
      {:error, _} = error -> error
    end
  end

  defp run(source, limits, mode) do
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

    read(source, limits, mode, state)
  end

  defp read(source, limits, mode, %{buffer: <<>>} = state) do
    cap = if mode == :header, do: limits["max_record_bytes"] + 1, else: limits["max_bytes"]
    extra = if mode == :header, do: 0, else: 1
    amount = min(@chunk, cap - state.read_offset + extra)

    case pread(source, state.read_offset, max(amount, 1)) do
      {:ok, bytes} when byte_size(bytes) + state.read_offset > cap ->
        {:error, :journal_limit_reached}

      {:ok, bytes} ->
        read(source, limits, mode, %{
          state
          | buffer: bytes,
            read_offset: state.read_offset + byte_size(bytes)
        })

      :eof ->
        finish(state, limits, mode)

      {:error, _} = error ->
        error
    end
  end

  defp read(source, limits, mode, state) do
    case :binary.match(state.buffer, "\n") do
      {index, 1} ->
        size = state.line_bytes + index

        if size > limits["max_record_bytes"] do
          {:error, :journal_limit_reached}
        else
          prefix = binary_part(state.buffer, 0, index)
          line = IO.iodata_to_binary(Enum.reverse([prefix | state.parts]))

          with {:ok, next, event} <- decode(line, limits, mode, state) do
            if mode == :header do
              {:ok, %{header: event}}
            else
              rest = binary_part(state.buffer, index + 1, byte_size(state.buffer) - index - 1)

              read(source, limits, mode, %{
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
          read(source, limits, mode, %{
            state
            | parts: [state.buffer | state.parts],
              line_bytes: state.line_bytes + byte_size(state.buffer),
              buffer: <<>>
          })
        end
    end
  end

  defp decode(line, limits, mode, state) do
    cond do
      state.last_quota != nil ->
        {:error, :invalid_journal_limit_record}

      state.count >= limits["max_events"] ->
        {:error, :journal_limit_reached}

      true ->
        with {:ok, event} <- Jason.decode(line),
             :ok <- quota(event, state) do
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

  defp quota(%{"type" => "journal_limit_reached"} = event, state) do
    if Limits.valid_receipt?(event) and event["byte_offset"] == state.offset and
         event["event_count"] == state.count,
       do: :ok,
       else: {:error, :invalid_journal_limit_record}
  end

  defp quota(_, _), do: :ok

  defp finish(%{line_bytes: 0}, _, :header), do: {:error, :invalid_journal}
  defp finish(%{line_bytes: 0} = state, _, _), do: result(state, :none)

  defp finish(state, limits, mode) do
    line = IO.iodata_to_binary(Enum.reverse(state.parts))

    case decode(line, limits, mode, state) do
      {:ok, _, event} when mode == :header -> {:ok, %{header: event}}
      {:ok, next, _} -> result(next, :valid)
      {:error, {:corrupt_journal, _}} when mode != :header -> result(state, :invalid)
      error -> error
    end
  end

  defp result(state, tail) do
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

  defp pread({:file, file}, offset, bytes), do: :file.pread(file, offset, bytes)

  defp pread({:binary, contents}, offset, bytes) do
    if offset >= byte_size(contents),
      do: :eof,
      else: {:ok, binary_part(contents, offset, min(bytes, byte_size(contents) - offset))}
  end
end
