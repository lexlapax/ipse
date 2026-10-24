defmodule Ipse.Provider.OpenAI do
  @moduledoc "Stateless Responses API adapter with provider-bound native continuation."
  alias Ipse.Provider.Stream
  alias Ipse.Provider.Transport

  def endpoint(config),
    do:
      Ipse.Provider.endpoint(
        config,
        Ipse.Provider.Registry.fetch!(config[:provider] || :openai).default_base_url,
        "/responses"
      )

  def complete(config, messages, tools, emit) do
    if config[:api_key] in [nil, ""] do
      {:error,
       "#{label(config[:provider])} credentials are missing. Sign in or configure an API key."}
    else
      url = endpoint(config)

      headers = [
        {"authorization", "Bearer " <> config[:api_key]},
        {"accept", "text/event-stream"}
      ]

      result =
        with {:ok, state} <-
               Transport.stream(
                 url,
                 headers,
                 request_body(config, messages, tools),
                 config,
                 new(config[:provider]),
                 fn state, chunk -> consume(state, chunk, emit) end
               ) do
          finish(state)
        end

      case result do
        {:error, message} when config.provider in [:xai, :xai_oauth] and is_binary(message) ->
          {:error, String.replace_prefix(message, "OpenAI", "Grok / xAI")}

        other ->
          other
      end
    end
  end

  def request_body(config, messages, tools) do
    if config[:provider] in [:xai, :xai_oauth] and
         Enum.any?(messages, fn message ->
           case message["provider_data"] do
             %{"provider" => source} -> source != "xai"
             _ -> false
           end
         end) do
      raise ArgumentError,
            "Grok history contains another provider's native continuation; use a reviewed handoff."
    end

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

    limit = Ipse.Provider.output_tokens(config)
    body = if limit, do: Map.put(body, "max_output_tokens", limit), else: body

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
           "provider_data" => %{"provider" => source, "output" => output}
         },
         provider
       )
       when is_list(output) do
    if source == replay_key(provider) do
      output
    else
      raise ArgumentError,
            "Responses history belongs to a different provider; start a fresh session or use a reviewed handoff."
    end
  end

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
    do: %{sse: Stream.new_sse(), response: nil, items: %{}, terminal: false, provider: provider}

  def consume(state, chunk, emit) do
    handler = fn event, state ->
      with {:ok, state} <- Stream.tick(state) do
        if event.data == "[DONE]" and state.provider in [:xai, :xai_oauth] and state.terminal do
          {:ok, state}
        else
          case Jason.decode(event.data) do
            {:ok, data} when is_map(data) -> event(state, data, emit)
            _ -> {:error, "Invalid JSON in provider stream."}
          end
        end
      else
        {:error, message} when is_binary(message) -> {:error, message}
      end
    end

    with {:ok, state, parser} <- Stream.reduce_sse(state.sse, chunk, state, handler),
         do: {:ok, %{state | sse: parser}}
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
    put_item(state, index, item)
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
    with true <- Stream.index?(index),
         {:ok, item} <- Stream.update_field(Map.get(state.items, index, %{}), "arguments", delta) do
      put_item(state, index, item)
    else
      _ -> Stream.error()
    end
  end

  defp event(
         state,
         %{"type" => "response.output_item.done", "output_index" => index, "item" => item},
         _
       ) do
    put_item(state, index, item)
  end

  defp event(state, %{"type" => "response.completed", "response" => response}, emit) do
    emit.({:provider_usage, response["usage"]})

    if response["status"] in [nil, "completed"] and
         (is_nil(response["output"]) or Stream.items?(response["output"], "function_call")) do
      {:ok, %{state | terminal: true, response: response}}
    else
      if response["status"] in [nil, "completed"],
        do: Stream.error(),
        else: {:error, "OpenAI response did not complete."}
    end
  end

  defp event(state, %{"type" => type} = data, emit)
       when type in ["error", "response.failed"] do
    if is_map(data["response"]), do: emit.({:provider_usage, data["response"]["usage"]})
    Ipse.Provider.Transport.stream_error(data, state.provider, state[:request_id])
  end

  defp event(_, %{"type" => "response.incomplete"} = data, emit) do
    if is_map(data["response"]), do: emit.({:provider_usage, data["response"]["usage"]})

    {:error,
     "OpenAI response failed or was incomplete. Check model access, account limits, and request settings."}
  end

  defp event(state, _, _), do: {:ok, state}

  def finish(%{terminal: true, response: response, items: items} = state) do
    with :ok <- Stream.check_deadline(state) do
      output =
        case response["output"] do
          value when value in [nil, []] ->
            items
            |> Enum.sort_by(&elem(&1, 0))
            |> Enum.map(&Stream.materialize_fields(elem(&1, 1)))

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
        "provider_data" => %{"provider" => replay_key(state.provider), "output" => output}
      }

      message = put_reported_model(message, response["model"])
      message = put_reported_cost(message, state.provider, response["usage"])

      message = if calls == [], do: message, else: Map.put(message, "tool_calls", calls)
      with :ok <- Stream.check_deadline(state), do: {:ok, message, response["usage"] || %{}}
    end
  end

  def finish(_),
    do: {:error, "OpenAI stream ended before response.completed; no tools were executed."}

  defp put_item(state, index, item) do
    if Stream.index?(index) and is_map(item) do
      items = Map.put(state.items, index, item)

      if Stream.items?(Map.values(items), "function_call"),
        do: {:ok, %{state | items: items}},
        else: Stream.error()
    else
      Stream.error()
    end
  end

  defp put_reported_model(message, model) do
    case Ipse.Provider.model_name(model) do
      nil -> message
      model -> put_in(message, ["provider_data", "reported_model"], model)
    end
  end

  defp replay_key(nil), do: "openai"
  defp replay_key(provider), do: Ipse.Provider.Registry.fetch!(provider).replay_key
  defp label(provider) when provider in [:xai, :xai_oauth], do: "Grok / xAI"
  defp label(_), do: "OpenAI"

  defp put_reported_cost(message, provider, %{"cost_in_usd_ticks" => ticks})
       when provider in [:xai, :xai_oauth] and is_integer(ticks) and ticks >= 0 and
              ticks <= 9_007_199_254_740_991,
       do: put_in(message, ["provider_data", "reported_cost_usd_ticks"], ticks)

  defp put_reported_cost(message, _, _), do: message
end
