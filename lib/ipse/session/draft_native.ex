defmodule Ipse.Session.DraftNative do
  @moduledoc false

  def policy(%{provider: :chatgpt}), do: :chatgpt
  def policy(%{provider: :openai}), do: :openai
  def policy(%{provider: :ollama}), do: :ollama
  def policy(%{provider: :anthropic}), do: :anthropic
  def policy(_), do: :none

  @doc false
  def plain_text_only?(message),
    do:
      ollama_draft_without_tools?(message) and
        get_in(message, ["provider_data", "message", "thinking"]) === ""

  @doc false
  def ollama_draft_without_tools?(
        %{
          "role" => "assistant",
          "content" => content,
          "provider_data" => %{"provider" => "ollama", "message" => native} = data
        } = message
      ) do
    is_binary(content) and String.valid?(content) and is_map(native) and
      Enum.all?(Map.keys(data), &(&1 in ~w(provider message reported_model))) and
      (not Map.has_key?(data, "reported_model") or
         Ipse.Provider.model_name(data["reported_model"]) === data["reported_model"]) and
      Enum.sort(Map.keys(native)) == ~w(content role thinking tool_calls) and
      native["role"] === "assistant" and native["content"] === content and
      is_binary(native["thinking"]) and byte_size(native["thinking"]) <= 8_388_608 and
      String.valid?(native["thinking"]) and native["tool_calls"] === [] and
      message["tool_calls"] in [nil, []]
  rescue
    _ -> false
  end

  def ollama_draft_without_tools?(_), do: false

  # Match exactly what Ollama.finish_state emits, including its generated IDs
  # when the native call has no ID. Never invent associations for other shapes.
  def ollama_draft_with_tools?(
        %{
          "tool_calls" => calls,
          "provider_data" => %{"provider" => "ollama", "message" => native}
        } = message
      )
      when is_list(calls) and calls != [] and length(calls) <= 32 and is_map(native) do
    clean =
      message
      |> Map.delete("tool_calls")
      |> put_in(["provider_data", "message", "tool_calls"], [])

    native_calls = native["tool_calls"]

    ollama_draft_without_tools?(clean) and is_list(native_calls) and
      length(native_calls) == length(calls) and
      Enum.all?(Enum.with_index(Enum.zip(native_calls, calls)), fn {{original, normalized}, index} ->
        ollama_call?(original, normalized, index)
      end)
  rescue
    _ -> false
  end

  def ollama_draft_with_tools?(_), do: false

  defp ollama_call?(
         %{"function" => %{"name" => name, "arguments" => arguments} = function} = native,
         %{
           "id" => id,
           "type" => "function",
           "function" => %{"name" => name, "arguments" => encoded} = normalized_function
         } = normalized,
         index
       ) do
    Enum.all?(Map.keys(native), &(&1 in ~w(id function))) and
      Enum.sort(Map.keys(function)) == ~w(arguments name) and
      Enum.sort(Map.keys(normalized)) == ~w(function id type) and
      Enum.sort(Map.keys(normalized_function)) == ~w(arguments name) and
      is_binary(name) and name != "" and is_binary(id) and
      if(Map.has_key?(native, "id"),
        do: native["id"] === id,
        else: Regex.match?(~r/\Aollama_[0-9a-f]{16}_#{index}\z/, id)
      ) and
      encoded === if(is_binary(arguments), do: arguments, else: Jason.encode!(arguments || %{}))
  end

  defp ollama_call?(_, _, _), do: false

  def isolated_ollama?(prefix, segment, tail) do
    with true <- Enum.all?([prefix, segment, tail], &Ipse.Session.Reference.safe_tail?/1),
         ids <- for(message <- segment, call <- message["tool_calls"] || [], do: call["id"]),
         true <- length(ids) == length(Enum.uniq(ids)),
         inside <- tool_ids(segment),
         outside <- tool_ids(prefix ++ tail),
         true <- MapSet.disjoint?(inside, outside) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp tool_ids(messages) do
    messages
    |> Enum.flat_map(fn message ->
      native_calls =
        case message["provider_data"] do
          %{"provider" => "ollama", "message" => %{"tool_calls" => calls}} when is_list(calls) ->
            calls

          _ ->
            []
        end

      Enum.map((message["tool_calls"] || []) ++ native_calls, & &1["id"]) ++
        [message["tool_call_id"]]
    end)
    |> Enum.filter(&is_binary/1)
    |> MapSet.new()
  end

  @doc false
  def anthropic_draft_without_tools?(
        %{
          "role" => "assistant",
          "content" => content,
          "provider_data" => %{"provider" => "anthropic", "content" => parts} = data
        } = message
      ) do
    is_binary(content) and String.valid?(content) and
      Enum.all?(Map.keys(data), &(&1 in ~w(provider content reported_model))) and
      (not Map.has_key?(data, "reported_model") or
         Ipse.Provider.model_name(data["reported_model"]) === data["reported_model"]) and
      is_list(parts) and parts != [] and Ipse.Provider.Stream.items?(parts, "tool_use") and
      Enum.all?(parts, fn
        %{"type" => "text", "text" => text} = part ->
          Enum.sort(Map.keys(part)) == ~w(text type) and is_binary(text) and String.valid?(text)

        %{"type" => "thinking", "thinking" => thinking, "signature" => signature} = part ->
          Enum.sort(Map.keys(part)) == ~w(signature thinking type) and
            is_binary(thinking) and byte_size(thinking) <= 8_388_608 and
            String.valid?(thinking) and is_binary(signature) and
            byte_size(signature) in 1..8_388_608 and String.valid?(signature)

        %{"type" => "redacted_thinking", "data" => data} = part ->
          Enum.sort(Map.keys(part)) == ~w(data type) and is_binary(data) and
            byte_size(data) in 1..8_388_608 and String.valid?(data)

        _ ->
          false
      end) and
      (not Enum.any?(parts, &(&1["type"] == "redacted_thinking")) or
         Enum.any?(parts, &(&1["type"] == "text"))) and
      parts |> Enum.filter(&(&1["type"] == "text")) |> Enum.map_join(& &1["text"]) ===
        content and message["tool_calls"] in [nil, []]
  rescue
    _ -> false
  end

  def anthropic_draft_without_tools?(_), do: false

  # Validate the same ordered normalization used by the Anthropic adapter.
  # Signed and redacted thinking blocks remain opaque and are never rewritten.
  def anthropic_draft_with_tools?(
        %{
          "tool_calls" => calls,
          "provider_data" => %{"provider" => "anthropic", "content" => parts}
        } = message
      )
      when is_list(calls) and calls != [] and length(calls) <= 32 and is_list(parts) do
    native_calls = Enum.filter(parts, &(is_map(&1) and &1["type"] === "tool_use"))
    other_parts = Enum.reject(parts, &(is_map(&1) and &1["type"] === "tool_use"))
    # The text-less tool turn is valid; use an empty text solely to apply the
    # existing opaque-block validator without changing the original message.
    checked_parts =
      if Enum.any?(other_parts, &(is_map(&1) and &1["type"] === "text")),
        do: other_parts,
        else: other_parts ++ [%{"type" => "text", "text" => ""}]

    clean =
      message |> Map.delete("tool_calls") |> put_in(["provider_data", "content"], checked_parts)

    Ipse.Provider.Stream.items?(parts, "tool_use") and
      anthropic_draft_without_tools?(clean) and length(native_calls) == length(calls) and
      Enum.all?(Enum.zip(native_calls, calls), fn {native, normalized} ->
        anthropic_call?(native, normalized)
      end)
  rescue
    _ -> false
  end

  def anthropic_draft_with_tools?(_), do: false

  defp anthropic_call?(
         %{"type" => "tool_use", "id" => id, "name" => name, "input" => input} = native,
         %{
           "id" => id,
           "type" => "function",
           "function" => %{"name" => name, "arguments" => encoded} = function
         } = normalized
       ) do
    Enum.sort(Map.keys(native)) == ~w(id input name type) and
      Enum.sort(Map.keys(normalized)) == ~w(function id type) and
      Enum.sort(Map.keys(function)) == ~w(arguments name) and
      is_binary(id) and byte_size(id) in 1..512 and String.valid?(id) and
      is_binary(name) and byte_size(name) in 1..512 and String.valid?(name) and
      is_map(input) and encoded === Jason.encode!(input)
  end

  defp anthropic_call?(_, _), do: false

  def isolated_anthropic?(prefix, segment, tail) do
    with true <- Enum.all?(prefix ++ tail, &anthropic_retained_message?/1),
         true <-
           Enum.all?(segment, fn
             %{"provider_data" => _} = message ->
               anthropic_draft_without_tools?(message) or anthropic_draft_with_tools?(message)

             _ ->
               true
           end),
         true <- Enum.all?([prefix, segment, tail], &Ipse.Session.Reference.safe_tail?/1),
         ids <- for(message <- segment, call <- message["tool_calls"] || [], do: call["id"]),
         true <- length(ids) == length(Enum.uniq(ids)),
         true <- MapSet.disjoint?(anthropic_ids(segment), anthropic_ids(prefix ++ tail)) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  # Anthropic's adapter ignores foreign provider data and rebuilds these
  # assistant messages from normalized content and calls.
  defp anthropic_retained_message?(%{
         "role" => "assistant",
         "provider_data" => %{"provider" => provider}
       })
       when is_binary(provider) and provider != "" and provider != "anthropic",
       do: true

  defp anthropic_retained_message?(%{"provider_data" => _} = message),
    do: anthropic_draft_without_tools?(message) or anthropic_draft_with_tools?(message)

  defp anthropic_retained_message?(_), do: true

  defp anthropic_ids(messages) do
    messages
    |> Enum.flat_map(fn message ->
      parts =
        case message["provider_data"] do
          %{"provider" => "anthropic", "content" => parts} -> parts
          _ -> []
        end

      native =
        if is_list(parts),
          do: Enum.filter(parts, &(is_map(&1) and &1["type"] === "tool_use")),
          else: []

      Enum.map((message["tool_calls"] || []) ++ native, & &1["id"]) ++ [message["tool_call_id"]]
    end)
    |> Enum.filter(&is_binary/1)
    |> MapSet.new()
  end

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

  # Both explicitly selected OpenAI routes use the stateless Responses adapter.
  # The validator never rewrites an output item; the complete interval is removed.
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
