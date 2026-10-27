defmodule Ipse.Session.DraftHistory do
  @moduledoc false
  alias Ipse.Journal
  @max_records 65_536
  @max_bytes 33_554_432
  @max_ranges 1024

  def withheld(directory, session, upper)
      when is_integer(upper) and upper >= 0 and upper <= @max_bytes do
    with {:ok, records} <- scan(directory, session, upper, 0, [], 0),
         events = Enum.map(records, & &1.record),
         {:ok, _} <- Ipse.Session.Draft.restore(events, session),
         :ok <- Ipse.Session.Input.validate_events(events, session),
         :ok <- Ipse.Session.OperatorAnswer.validate_events(events, session) do
      {ranges, start} =
        Enum.reduce(records, {[], nil}, fn %{record: event, source: source}, {ranges, start} ->
          case {event["type"], start} do
            {"draft_started", nil} ->
              {ranges, source["byte_offset"]}

            {type, current}
            when type in ["draft_cancelled", "draft_consumed"] and is_integer(current) ->
              {[{current, source["byte_offset"]} | ranges], nil}

            _ ->
              {ranges, start}
          end
        end)

      bounded_ranges(ranges, start)
    end
  rescue
    _ -> {:error, :invalid_draft_history}
  end

  def withheld(_, _, _), do: {:error, :invalid_draft_history}

  @doc false
  def bounded_ranges(ranges, start) when is_list(ranges) do
    cond do
      not is_nil(start) -> {:error, :pending_draft_history}
      length(ranges) > @max_ranges -> {:error, :draft_history_capacity}
      true -> {:ok, ranges}
    end
  end

  def withheld?(ranges, offset),
    do: Enum.any?(ranges, fn {first, last} -> offset >= first and offset <= last end)

  defp scan(_, _, upper, upper, acc, count) when count <= @max_records,
    do: {:ok, Enum.reverse(acc)}

  defp scan(dir, session, upper, cursor, acc, count) when count < @max_records do
    with {:ok, page} <- Journal.source_page(dir, session, cursor, 64, upper),
         true <- page.records != [] and count + length(page.records) <= @max_records do
      next = page.next || upper

      scan(
        dir,
        session,
        upper,
        next,
        Enum.reverse(page.records, acc),
        count + length(page.records)
      )
    else
      _ -> {:error, :invalid_draft_history}
    end
  end

  defp scan(_, _, _, _, _, _), do: {:error, :draft_history_capacity}
end
