defmodule Ipse.Session.DraftNative do
  @moduledoc false

  def policy(%{provider: :chatgpt}), do: :chatgpt
  def policy(_), do: :none

  def visible_models(messages) do
    messages
    |> Enum.flat_map(fn
      %{"role" => "assistant", "provider_data" => %{"reported_model" => value}} ->
        case Ipse.Provider.model_name(value) do
          nil -> []
          model -> [model]
        end

      _ ->
        []
    end)
    |> MapSet.new()
  end

  # This validator is deliberately limited to the stateless ChatGPT Responses
  # adapter. It never rewrites an output item; the complete interval is removed.
  def responses_owned?(messages) when is_list(messages) do
    Enum.all?(messages, fn
      %{"provider_data" => data} = message -> valid_assistant?(message, data)
      _ -> true
    end)
  rescue
    _ -> false
  end

  def responses_owned?(_), do: false

  def isolated_responses?(prefix, segment, tail) do
    with true <- responses_owned?(prefix ++ segment ++ tail),
         true <- Ipse.Session.Reference.safe_tail?(prefix),
         true <- Ipse.Session.Reference.safe_tail?(segment),
         true <- Ipse.Session.Reference.safe_tail?(tail),
         true <- unique_interval_ids?(segment),
         inside <- identifiers(segment),
         outside <- identifiers(prefix ++ tail),
         true <- MapSet.disjoint?(inside, outside) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp valid_assistant?(message, data) do
    is_map(data) and message["role"] == "assistant" and data["provider"] == "openai" and
      Enum.all?(Map.keys(data), &(&1 in ~w(provider output reported_model))) and
      is_list(data["output"]) and length(data["output"]) in 1..128 and
      Enum.all?(data["output"], &valid_item?/1) and
      text(data["output"]) == (message["content"] || "") and
      calls(data["output"]) == (message["tool_calls"] || [])
  end

  defp valid_item?(%{"type" => "reasoning", "id" => id} = item) do
    nonempty?(id) and only?(item, ~w(type id summary content encrypted_content status)) and
      (is_nil(item["encrypted_content"]) or is_binary(item["encrypted_content"])) and
      text_parts?(item["summary"], "summary_text") and
      text_parts?(item["content"], "reasoning_text")
  end

  defp valid_item?(%{"type" => "message", "id" => id, "content" => content} = item) do
    nonempty?(id) and only?(item, ~w(type id role status phase content)) and
      item["role"] == "assistant" and is_list(content) and
      Enum.all?(content, fn
        %{"type" => "output_text", "text" => text} = part ->
          is_binary(text) and String.valid?(text) and
            only?(part, ~w(type text annotations logprobs)) and
            part["annotations"] in [nil, []] and part["logprobs"] in [nil, []]

        _ ->
          false
      end)
  end

  defp valid_item?(
         %{
           "type" => "function_call",
           "id" => id,
           "call_id" => call_id,
           "name" => name,
           "arguments" => args
         } = item
       ) do
    nonempty?(id) and nonempty?(call_id) and nonempty?(name) and is_binary(args) and
      only?(item, ~w(type id call_id name arguments status))
  end

  defp valid_item?(_), do: false

  defp text(output) do
    output
    |> Enum.filter(&(&1["type"] == "message"))
    |> Enum.flat_map(& &1["content"])
    |> Enum.map_join("", & &1["text"])
  end

  defp calls(output) do
    output
    |> Enum.filter(&(&1["type"] == "function_call"))
    |> Enum.map(fn item ->
      %{
        "id" => item["call_id"],
        "type" => "function",
        "function" => %{"name" => item["name"], "arguments" => item["arguments"]}
      }
    end)
  end

  defp only?(item, allowed), do: Enum.all?(Map.keys(item), &(&1 in allowed))
  defp nonempty?(value), do: is_binary(value) and byte_size(value) in 1..512
  defp text_parts?(nil, _), do: true

  defp text_parts?(parts, type) when is_list(parts),
    do:
      Enum.all?(parts, fn
        %{"type" => ^type, "text" => text} = item ->
          is_binary(text) and only?(item, ~w(type text))

        _ ->
          false
      end)

  defp text_parts?(_, _), do: false

  defp identifiers(messages) do
    Enum.reduce(messages, MapSet.new(), fn message, acc ->
      native = get_in(message, ["provider_data", "output"]) || []

      acc =
        Enum.reduce(native, acc, fn item, set ->
          Enum.reduce([item["id"], item["call_id"]], set, fn value, set ->
            if is_binary(value), do: MapSet.put(set, value), else: set
          end)
        end)

      call_ids = Enum.map(message["tool_calls"] || [], & &1["id"]) ++ [message["tool_call_id"]]

      Enum.reduce(call_ids, acc, fn value, set ->
        if is_binary(value), do: MapSet.put(set, value), else: set
      end)
    end)
  end

  defp unique_interval_ids?(messages) do
    item_ids =
      for message <- messages,
          item <- get_in(message, ["provider_data", "output"]) || [],
          do: item["id"]

    call_ids = for message <- messages, call <- message["tool_calls"] || [], do: call["id"]

    length(item_ids) == length(Enum.uniq(item_ids)) and
      length(call_ids) == length(Enum.uniq(call_ids))
  end
end
