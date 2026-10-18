defmodule Ipse.Journal.Limits do
  @moduledoc "Operator-only journal admission below finite host resource ceilings."
  @ceilings %{
    "max_bytes" => 134_217_728,
    "max_events" => 100_000,
    "max_record_bytes" => 16_777_216
  }
  @minimums %{"max_bytes" => 1_024, "max_events" => 2, "max_record_bytes" => 512}
  @reserve 512

  def defaults, do: @ceilings
  def reserve_bytes, do: @reserve

  def schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" =>
        Map.new(@ceilings, fn {key, maximum} ->
          {key, %{"type" => "integer", "minimum" => @minimums[key], "maximum" => maximum}}
        end)
    }
  end

  def normalize(nil), do: {:ok, defaults()}

  def normalize(policy) when is_map(policy) do
    limits = Map.merge(defaults(), policy)

    if Enum.all?(policy, fn {key, value} ->
         is_map_key(@ceilings, key) and is_integer(value) and
           value >= @minimums[key] and value <= @ceilings[key]
       end) and limits["max_record_bytes"] >= @reserve do
      {:ok, limits}
    else
      {:error, :invalid_journal_policy}
    end
  end

  def normalize(_), do: {:error, :invalid_journal_policy}

  def resolve(sources) do
    if Enum.any?(sources, &(&1.scope != "operator" and Map.has_key?(&1.data, "journal"))) do
      {:error, "Journal policy is operator-only; project configuration cannot replace it."}
    else
      normalize(Enum.find_value(sources, & &1.data["journal"]))
    end
  end

  def encode(event, limits) do
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

  def receipt(limits, bytes, count, reason) do
    %{
      "type" => "journal_limit_reached",
      "version" => 1,
      "reason" => reason,
      "limits" => limits,
      "byte_offset" => bytes,
      "event_count" => count
    }
  end

  def valid_receipt?(event) when is_map(event) do
    with true <-
           Enum.sort(Map.keys(event)) == ~w(byte_offset event_count limits reason type version),
         "journal_limit_reached" <- event["type"],
         1 <- event["version"],
         true <- event["reason"] in ~w(bytes events record_bytes),
         {:ok, limits} <- normalize(event["limits"]),
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

  def valid_receipt?(_), do: false

  def writable_events(events) do
    case List.last(events) do
      %{"type" => "journal_limit_reached"} -> {:error, :journal_limit_reached}
      _ -> :ok
    end
  end

  def summary(events) do
    case List.last(events) do
      %{"type" => "journal_limit_reached"} = receipt ->
        receipt
        |> Map.take(~w(reason limits byte_offset event_count))
        |> Map.put("status", "sealed")

      _ ->
        nil
    end
  end

  def validate_events(events) when is_list(events) do
    Enum.reduce_while(events, {0, false}, fn
      _, {_, true} ->
        {:halt, {:error, :invalid_journal_limit_record}}

      %{"type" => "journal_limit_reached"} = event, {index, false} ->
        if valid_receipt?(event) and event["event_count"] == index,
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

  def validate_events(_), do: {:error, :invalid_journal_limit_record}
end
