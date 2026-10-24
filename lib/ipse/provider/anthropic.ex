defmodule Ipse.Provider.Anthropic do
  @moduledoc "Anthropic Messages streaming adapter with native content replay."
  alias Ipse.Provider.Stream
  alias Ipse.Provider.Transport

  def endpoint(config),
    do:
      Ipse.Provider.endpoint(
        config,
        Ipse.Provider.Registry.fetch!(:anthropic).default_base_url,
        "/v1/messages"
      )

  def complete(config, messages, tools, emit) do
    if config[:api_key] in [nil, ""] do
      {:error, "Anthropic API key is missing."}
    else
      body = request_body(config, messages, tools)
      url = endpoint(config)

      headers = [
        {"x-api-key", config[:api_key]},
        {"anthropic-version", "2023-06-01"},
        {"accept", "text/event-stream"}
      ]

      state = %{
        sse: Stream.new_sse(),
        blocks: %{},
        done: false,
        stop_reason: nil,
        usage: %{},
        reported_model: nil
      }

      with {:ok, state} <-
             Transport.stream(url, headers, body, config, state, fn state, chunk ->
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
      "max_tokens" => Ipse.Provider.output_tokens(config, config[:max_tokens] || 8192),
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

  defp native(%{"ipse_checkpoint" => _} = message) do
    if Ipse.Session.Context.valid_checkpoint?(message),
      do: %{"role" => "user", "content" => message["content"]},
      else: raise(ArgumentError, "invalid historical context checkpoint")
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
    handler = fn event, state ->
      with {:ok, state} <- Stream.tick(state),
           {:ok, data} when is_map(data) <- Jason.decode(event.data) do
        event(state, data, emit)
      else
        {:error, message} when is_binary(message) -> {:error, message}
        _ -> {:error, "Invalid JSON in Anthropic stream."}
      end
    end

    with {:ok, state, parser} <- Stream.reduce_sse(state.sse, chunk, state, handler),
         do: {:ok, %{state | sse: parser}}
  end

  defp event(_, %{"type" => "error"}, _),
    do:
      {:error,
       "Anthropic reported an error. Check model access, account limits, and request settings."}

  defp event(state, %{"type" => "message_start", "message" => message}, emit) do
    emit.({:provider_usage, message["usage"]})

    {:ok,
     %{
       state
       | usage: message["usage"] || %{},
         reported_model: Ipse.Provider.model_name(message["model"])
     }}
  end

  defp event(
         state,
         %{"type" => "content_block_start", "index" => index, "content_block" => block},
         _
       ),
       do: put_block(state, index, block)

  defp event(state, %{"type" => "content_block_delta", "index" => index, "delta" => delta}, emit) do
    {field, value} =
      case delta["type"] do
        "text_delta" ->
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
      with true <- Stream.index?(index),
           {:ok, block} <- Stream.update_field(Map.get(state.blocks, index, %{}), field, value),
           {:ok, state} <- put_block(state, index, block) do
        if field == "text", do: emit.({:text, value})
        {:ok, state}
      else
        _ -> Stream.error()
      end
    else
      {:ok, state}
    end
  end

  defp event(state, %{"type" => "message_delta"} = data, emit) do
    usage = Map.merge(state.usage, data["usage"] || %{})
    emit.({:provider_usage, usage})

    {:ok,
     %{
       state
       | stop_reason: data["delta"]["stop_reason"],
         usage: usage
     }}
  end

  defp event(state, %{"type" => "message_stop"}, _), do: {:ok, %{state | done: true}}
  defp event(state, _, _), do: {:ok, state}

  def finish(%{done: true, stop_reason: reason} = state)
      when reason in ["end_turn", "tool_use", "stop_sequence"] do
    with :ok <- Stream.check_deadline(state) do
      content =
        state.blocks
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(fn {_, block} ->
          case Map.pop(Stream.materialize_fields(block), "__json") do
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
      with :ok <- Stream.check_deadline(state), do: {:ok, message, state.usage}
    end
  end

  def finish(_), do: {:error, "Anthropic response was incomplete; no tools were executed."}

  defp put_block(state, index, block) do
    if Stream.index?(index) and is_map(block) do
      blocks = Map.put(state.blocks, index, block)

      if Stream.items?(Map.values(blocks), "tool_use"),
        do: {:ok, %{state | blocks: blocks}},
        else: Stream.error()
    else
      Stream.error()
    end
  end
end
