defmodule Ipse.ToolCall do
  @moduledoc "Provider call identity and aggregate admission bounds."

  @response_calls 32
  @turn_calls 128
  @response_arguments 2 * 1024 * 1024
  @turn_arguments 8 * 1024 * 1024

  def empty_budget, do: %{calls: 0, argument_bytes: 0}

  def restore_budget(messages) do
    Enum.reduce(messages, empty_budget(), fn
      %{"role" => "user"}, _ ->
        empty_budget()

      %{"role" => "assistant", "tool_calls" => calls}, used when is_list(calls) ->
        charge(used, calls)

      _, used ->
        used
    end)
  end

  def admit(calls, used) when is_list(calls) do
    bounded = Enum.take(calls, @response_calls + 1)
    next = charge(used, bounded)

    cond do
      length(bounded) > @response_calls or next.calls > @turn_calls or
        next.argument_bytes - used.argument_bytes > @response_arguments or
          next.argument_bytes > @turn_arguments ->
        {:error, :tool_call_limit}

      not valid_calls?(bounded) ->
        {:error, :tool_call_identity}

      true ->
        {:ok, next}
    end
  end

  def admit(_, _), do: {:error, :tool_call_identity}

  defp valid_calls?(calls) do
    Enum.all?(calls, fn
      %{"id" => id} = call ->
        valid_id?(id) and (is_nil(call["function"]) or is_map(call["function"]))

      _ ->
        false
    end) and length(Enum.uniq_by(calls, & &1["id"])) == length(calls)
  end

  defp charge(used, calls) do
    %{
      calls: used.calls + length(calls),
      argument_bytes: used.argument_bytes + Enum.reduce(calls, 0, &(argument_bytes(&1) + &2))
    }
  end

  defp argument_bytes(%{"function" => %{"arguments" => args}}) when is_binary(args),
    do: byte_size(args)

  defp argument_bytes(_), do: 0

  def valid_id?(id) when is_binary(id),
    do: byte_size(id) in 1..256 and String.valid?(id)

  def valid_id?(_), do: false
end
