defmodule Ipse.Provider.Anthropic do
  @moduledoc "Anthropic Messages streaming adapter with native content replay."
  alias Ipse.Provider.{HTTP, SSE}

  def complete(config, messages, tools, emit) do
    if config[:api_key] in [nil, ""] do
      {:error, "Anthropic API key is missing."}
    else
      body = request_body(config, messages, tools)
      url = Ipse.Provider.endpoint(config, "https://api.anthropic.com", "/v1/messages")

      headers = [
        {"x-api-key", config[:api_key]},
        {"anthropic-version", "2023-06-01"},
        {"accept", "text/event-stream"}
      ]

      state = %{
        sse: SSE.new(),
        blocks: %{},
        done: false,
        stop_reason: nil,
        usage: %{},
        reported_model: nil
      }

      with {:ok, state} <-
             HTTP.stream(url, headers, body, config, state, fn state, chunk ->
               consume(state, chunk, emit)
             end) do
        finish(state)
      end
    end
  end

  def request_body(config, messages, tools) do
    {system, messages} = Enum.split_with(messages, &(&1["role"] in ["system", "developer"]))

    %{
      "model" => config[:model],
      "stream" => true,
      "max_tokens" => config[:max_tokens] || 8192,
      "system" => Enum.map_join(system, "\n\n", &(&1["content"] || "")),
      "messages" => Enum.map(messages, &native/1),
      "tools" =>
        Enum.map(tools, fn tool ->
          function = tool["function"]

          %{
            "name" => function["name"],
            "description" => function["description"] || "",
            "input_schema" => function["parameters"] || %{"type" => "object"}
          }
        end)
    }
  end

  defp native(%{"role" => "tool"} = message),
    do: %{
      "role" => "user",
      "content" => [
        %{
          "type" => "tool_result",
          "tool_use_id" => message["tool_call_id"],
          "content" => message["content"] || ""
        }
      ]
    }

  defp native(%{
         "role" => "assistant",
         "provider_data" => %{"provider" => "anthropic", "content" => content}
       }),
       do: %{"role" => "assistant", "content" => content}

  defp native(%{"role" => "assistant"} = message) do
    text =
      if message["content"] in [nil, ""],
        do: [],
        else: [%{"type" => "text", "text" => message["content"]}]

    calls =
      Enum.map(message["tool_calls"] || [], fn call ->
        %{
          "type" => "tool_use",
          "id" => call["id"],
          "name" => call["function"]["name"],
          "input" => Jason.decode!(call["function"]["arguments"])
        }
      end)

    %{"role" => "assistant", "content" => text ++ calls}
  end

  defp native(message), do: Map.take(message, ["role", "content"])

  def consume(state, chunk, emit) do
    {events, parser} = SSE.feed(state.sse, chunk)

    Enum.reduce_while(events, {:ok, %{state | sse: parser}}, fn event, {:ok, state} ->
      case Jason.decode(event.data) do
        {:ok, data} ->
          case event(state, data, emit) do
            {:ok, state} -> {:cont, {:ok, state}}
            error -> {:halt, error}
          end

        _ ->
          {:halt, {:error, "Invalid JSON in Anthropic stream."}}
      end
    end)
  end

  defp event(_, %{"type" => "error"}, _),
    do:
      {:error,
       "Anthropic reported an error. Check model access, account limits, and request settings."}

  defp event(state, %{"type" => "message_start", "message" => message}, _),
    do:
      {:ok,
       %{
         state
         | usage: message["usage"] || %{},
           reported_model: Ipse.RuntimeInfo.model_name(message["model"])
       }}

  defp event(
         state,
         %{"type" => "content_block_start", "index" => index, "content_block" => block},
         _
       ),
       do: {:ok, %{state | blocks: Map.put(state.blocks, index, block)}}

  defp event(state, %{"type" => "content_block_delta", "index" => index, "delta" => delta}, emit) do
    {field, value} =
      case delta["type"] do
        "text_delta" ->
          emit.({:text, delta["text"]})
          {"text", delta["text"]}

        "input_json_delta" ->
          {"__json", delta["partial_json"]}

        "thinking_delta" ->
          {"thinking", delta["thinking"]}

        "signature_delta" ->
          {"signature", delta["signature"]}

        _ ->
          {nil, ""}
      end

    if field do
      block = Map.get(state.blocks, index, %{}) |> Map.update(field, value, &(&1 <> value))
      {:ok, %{state | blocks: Map.put(state.blocks, index, block)}}
    else
      {:ok, state}
    end
  end

  defp event(state, %{"type" => "message_delta"} = data, _) do
    {:ok,
     %{
       state
       | stop_reason: data["delta"]["stop_reason"],
         usage: Map.merge(state.usage, data["usage"] || %{})
     }}
  end

  defp event(state, %{"type" => "message_stop"}, _), do: {:ok, %{state | done: true}}
  defp event(state, _, _), do: {:ok, state}

  def finish(%{done: true, stop_reason: reason} = state)
      when reason in ["end_turn", "tool_use", "stop_sequence"] do
    content =
      state.blocks
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {_, block} ->
        case Map.pop(block, "__json") do
          {nil, block} -> block
          {json, block} -> Map.put(block, "input", Jason.decode!(json))
        end
      end)

    text = content |> Enum.filter(&(&1["type"] == "text")) |> Enum.map_join("", & &1["text"])

    calls =
      content
      |> Enum.filter(&(&1["type"] == "tool_use"))
      |> Enum.map(fn block ->
        %{
          "id" => block["id"],
          "type" => "function",
          "function" => %{"name" => block["name"], "arguments" => Jason.encode!(block["input"])}
        }
      end)

    message = %{
      "role" => "assistant",
      "content" => text,
      "provider_data" => %{"provider" => "anthropic", "content" => content}
    }

    message =
      if state.reported_model,
        do: put_in(message, ["provider_data", "reported_model"], state.reported_model),
        else: message

    message = if calls == [], do: message, else: Map.put(message, "tool_calls", calls)
    {:ok, message, state.usage}
  end

  def finish(_), do: {:error, "Anthropic response was incomplete; no tools were executed."}
end
