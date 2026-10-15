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
               new(),
               fn state, chunk -> consume(state, chunk, emit) end
             ) do
        finish(state)
      end
    end
  end

  def request_body(config, messages, tools) do
    %{
      "model" => config[:model],
      "store" => false,
      "stream" => true,
      "include" => ["reasoning.encrypted_content"],
      "input" => Enum.flat_map(messages, &input/1),
      "tools" => Enum.map(tools, fn tool -> Map.put(tool["function"], "type", "function") end)
    }
  end

  defp input(%{"role" => "tool"} = message),
    do: [
      %{
        "type" => "function_call_output",
        "call_id" => message["tool_call_id"],
        "output" => content(message["content"])
      }
    ]

  defp input(%{
         "role" => "assistant",
         "provider_data" => %{"provider" => "openai", "output" => output}
       })
       when is_list(output),
       do: output

  defp input(%{"role" => "assistant"} = message) do
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

  defp input(message), do: [Map.take(message, ["role", "content"])]
  defp content(value) when is_binary(value), do: value
  defp content(value), do: Jason.encode!(value)

  def new, do: %{sse: SSE.new(), response: nil, items: %{}, terminal: false}

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

  defp event(state, %{"type" => "response.completed", "response" => response}, _) do
    if response["status"] in [nil, "completed"] do
      {:ok, %{state | terminal: true, response: response}}
    else
      {:error, "OpenAI response did not complete."}
    end
  end

  defp event(_, %{"type" => type}, _)
       when type in ["error", "response.failed", "response.incomplete"],
       do:
         {:error,
          "OpenAI response failed or was incomplete. Check model access, account limits, and request settings."}

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

    message = if calls == [], do: message, else: Map.put(message, "tool_calls", calls)
    {:ok, message, response["usage"] || %{}}
  end

  def finish(_),
    do: {:error, "OpenAI stream ended before response.completed; no tools were executed."}
end
