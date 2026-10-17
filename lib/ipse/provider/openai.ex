defmodule Ipse.Provider.OpenAI do
  @moduledoc "Stateless Responses API adapter; retains native reasoning and function call items."
  alias Ipse.Provider.{HTTP, SSE}

  def complete(config, messages, tools, emit) do
    if config[:api_key] in [nil, ""] do
      {:error, "OpenAI credentials are missing. Sign in or configure an API key."}
    else
      url = Ipse.Provider.endpoint(config, "https://api.openai.com/v1", "/responses")

      headers = [
        {"authorization", "Bearer " <> config[:api_key]},
        {"accept", "text/event-stream"}
      ]

      with {:ok, state} <-
             HTTP.stream(
               url,
               headers,
               request_body(config, messages, tools),
               config,
               new(config[:provider]),
               fn state, chunk -> consume(state, chunk, emit) end
             ) do
        finish(state)
      end
    end
  end

  def request_body(config, messages, tools) do
    input = Enum.flat_map(messages, &input(&1, config[:provider]))

    input =
      if config[:provider] == :chatgpt and tools != [] do
        additional_tools = %{
          "type" => "additional_tools",
          "role" => "developer",
          "tools" => Enum.map(tools, &function_definition/1)
        }

        [additional_tools | input]
      else
        input
      end

    body = %{
      "model" => config[:model],
      "store" => false,
      "stream" => true,
      "include" => ["reasoning.encrypted_content"],
      "input" => input
    }

    body =
      if config[:reasoning_effort],
        do: Map.put(body, "reasoning", %{"effort" => config.reasoning_effort}),
        else: body

    if config[:provider] == :chatgpt,
      do: body,
      else: Map.put(body, "tools", Enum.map(tools, &function_definition/1))
  end

  defp function_definition(tool), do: Map.put(tool["function"], "type", "function")

  defp input(message, :chatgpt) do
    message =
      if message["role"] == "system", do: Map.put(message, "role", "developer"), else: message

    input(message, :openai)
  end

  defp input(%{"role" => "tool"} = message, _provider),
    do: [
      %{
        "type" => "function_call_output",
        "call_id" => message["tool_call_id"],
        "output" => content(message["content"])
      }
    ]

  defp input(
         %{
           "role" => "assistant",
           "provider_data" => %{"provider" => "openai", "output" => output}
         },
         _provider
       )
       when is_list(output),
       do: output

  defp input(%{"role" => "assistant"} = message, _provider) do
    text =
      if message["content"] in [nil, ""],
        do: [],
        else: [%{"role" => "assistant", "content" => message["content"]}]

    text ++
      Enum.map(message["tool_calls"] || [], fn call ->
        %{
          "type" => "function_call",
          "call_id" => call["id"],
          "name" => call["function"]["name"],
          "arguments" => call["function"]["arguments"]
        }
      end)
  end

  defp input(message, _provider), do: [Map.take(message, ["role", "content"])]
  defp content(value) when is_binary(value), do: value
  defp content(value), do: Jason.encode!(value)

  def new, do: new(:openai)

  def new(provider),
    do: %{sse: SSE.new(), response: nil, items: %{}, terminal: false, provider: provider}

  def consume(state, chunk, emit) do
    {events, parser} = SSE.feed(state.sse, chunk)

    Enum.reduce_while(events, {:ok, %{state | sse: parser}}, fn event, {:ok, state} ->
      case Jason.decode(event.data) do
        {:ok, data} ->
          case event(state, data, emit) do
            {:ok, next} -> {:cont, {:ok, next}}
            error -> {:halt, error}
          end

        _ ->
          {:halt, {:error, "Invalid JSON in provider stream."}}
      end
    end)
  end

  defp event(state, %{"type" => "response.output_text.delta", "delta" => delta}, emit) do
    emit.({:text, delta})
    {:ok, state}
  end

  defp event(
         state,
         %{"type" => "response.output_item.added", "output_index" => index, "item" => item},
         _
       ) do
    {:ok, %{state | items: Map.put(state.items, index, item)}}
  end

  defp event(
         state,
         %{
           "type" => "response.function_call_arguments.delta",
           "output_index" => index,
           "delta" => delta
         },
         _
       ) do
    item = Map.get(state.items, index, %{})
    item = Map.update(item, "arguments", delta, &(&1 <> delta))
    {:ok, %{state | items: Map.put(state.items, index, item)}}
  end

  defp event(
         state,
         %{"type" => "response.output_item.done", "output_index" => index, "item" => item},
         _
       ) do
    {:ok, %{state | items: Map.put(state.items, index, item)}}
  end

  defp event(state, %{"type" => "response.completed", "response" => response}, emit) do
    emit.({:provider_usage, response["usage"]})

    if response["status"] in [nil, "completed"] do
      {:ok, %{state | terminal: true, response: response}}
    else
      {:error, "OpenAI response did not complete."}
    end
  end

  defp event(state, %{"type" => type} = data, emit)
       when type in ["error", "response.failed"] do
    if is_map(data["response"]), do: emit.({:provider_usage, data["response"]["usage"]})
    Ipse.Provider.Error.stream(data, state.provider, state[:request_id])
  end

  defp event(_, %{"type" => "response.incomplete"} = data, emit) do
    if is_map(data["response"]), do: emit.({:provider_usage, data["response"]["usage"]})

    {:error,
     "OpenAI response failed or was incomplete. Check model access, account limits, and request settings."}
  end

  defp event(state, _, _), do: {:ok, state}

  def finish(%{terminal: true, response: response, items: items}) do
    output =
      case response["output"] do
        value when value in [nil, []] ->
          items |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1))

        value ->
          value
      end

    text =
      output
      |> Enum.filter(&(&1["type"] == "message"))
      |> Enum.flat_map(&(&1["content"] || []))
      |> Enum.filter(&(&1["type"] == "output_text"))
      |> Enum.map_join("", &(&1["text"] || ""))

    calls =
      output
      |> Enum.filter(&(&1["type"] == "function_call"))
      |> Enum.map(fn item ->
        %{
          "id" => item["call_id"],
          "type" => "function",
          "function" => %{"name" => item["name"], "arguments" => item["arguments"] || "{}"}
        }
      end)

    message = %{
      "role" => "assistant",
      "content" => text,
      "provider_data" => %{"provider" => "openai", "output" => output}
    }

    message = put_reported_model(message, response["model"])

    message = if calls == [], do: message, else: Map.put(message, "tool_calls", calls)
    {:ok, message, response["usage"] || %{}}
  end

  def finish(_),
    do: {:error, "OpenAI stream ended before response.completed; no tools were executed."}

  defp put_reported_model(message, model) do
    case Ipse.RuntimeInfo.model_name(model) do
      nil -> message
      model -> put_in(message, ["provider_data", "reported_model"], model)
    end
  end
end
