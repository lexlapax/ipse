defmodule Ipse.Provider.Ollama do
  @moduledoc "Ollama native streaming chat adapter."
  alias Ipse.Provider.{Fragments, HTTP, Lines}

  def endpoint(config), do: Ipse.Provider.endpoint(config, "http://127.0.0.1:11434", "/api/chat")

  def complete(config, messages, tools, emit) do
    url = endpoint(config)

    {messages, _} =
      Enum.map_reduce(messages, %{}, fn message, names ->
        native = to_native(message)

        native =
          if message["role"] == "tool",
            do:
              native
              |> Map.delete("tool_call_id")
              |> Map.put("tool_name", names[message["tool_call_id"]] || ""),
            else: native

        names =
          Enum.reduce(message["tool_calls"] || [], names, fn call, names ->
            Map.put(names, call["id"], call["function"]["name"])
          end)

        {native, names}
      end)

    body = %{
      "model" => config[:model],
      "messages" => messages,
      "tools" => tools,
      "stream" => true
    }

    limit = Ipse.Provider.Limits.output_tokens(config)
    body = if limit, do: Map.put(body, "options", %{"num_predict" => limit}), else: body

    body =
      if is_map(config[:summary_schema]) do
        Map.merge(body, %{
          "format" => config.summary_schema,
          "think" => false,
          "options" => %{
            "temperature" => 0,
            "num_predict" => Ipse.Provider.Limits.narrow(limit, 4096)
          }
        })
      else
        body
      end

    state = %{
      lines: Lines.new(:lf),
      content: Fragments.new(),
      thinking: Fragments.new(),
      calls: [],
      call_count: 0,
      done: false,
      usage: %{},
      reported_model: nil
    }

    headers =
      if config[:api_key] in [nil, ""],
        do: [],
        else: [{"authorization", "Bearer " <> config[:api_key]}]

    with {:ok, state} <-
           HTTP.stream(url, headers, body, config, state, fn state, chunk ->
             consume(state, chunk, emit)
           end),
         {:ok, state} <- last_line(state, emit) do
      if state.done do
        response_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
        content = Fragments.value(state.content)
        thinking = Fragments.value(state.thinking)
        native_calls = Enum.reverse(state.calls)

        calls =
          Enum.with_index(native_calls)
          |> Enum.map(fn {call, index} ->
            %{
              "id" => call["id"] || "ollama_#{response_id}_#{index}",
              "type" => "function",
              "function" => %{
                "name" => call["function"]["name"],
                "arguments" => encode_args(call["function"]["arguments"])
              }
            }
          end)

        native = %{
          "role" => "assistant",
          "content" => content,
          "thinking" => thinking,
          "tool_calls" => native_calls
        }

        message = %{
          "role" => "assistant",
          "content" => content,
          "provider_data" => %{"provider" => "ollama", "message" => native}
        }

        message =
          if state.reported_model,
            do: put_in(message, ["provider_data", "reported_model"], state.reported_model),
            else: message

        message = if calls == [], do: message, else: Map.put(message, "tool_calls", calls)
        {:ok, message, state.usage}
      else
        {:error, "Ollama stream ended before its completion marker; no tools were executed."}
      end
    end
  end

  defp to_native(%{
         "role" => "assistant",
         "provider_data" => %{"provider" => "ollama", "message" => native}
       }),
       do: native

  defp to_native(message) do
    message = Map.take(message, ["role", "content", "tool_calls", "tool_call_id"])

    if message["tool_calls"] do
      Map.update!(message, "tool_calls", fn calls ->
        Enum.map(calls, fn call ->
          update_in(call, ["function", "arguments"], fn args ->
            if is_binary(args), do: Jason.decode!(args), else: args
          end)
        end)
      end)
    else
      message
    end
  end

  defp consume(state, chunk, emit) do
    with {:ok, lines, parser} <- Lines.feed(state.lines, chunk) do
      Enum.reduce_while(lines, {:ok, %{state | lines: parser}}, fn line, {:ok, state} ->
        case line(state, line, emit) do
          {:ok, state} -> {:cont, {:ok, state}}
          error -> {:halt, error}
        end
      end)
    end
  end

  defp last_line(state, emit), do: line(state, Lines.tail(state.lines), emit)
  defp line(state, "", _), do: {:ok, state}

  defp line(state, line, emit) do
    with {:ok, state} <- Fragments.tick(state), do: decode_line(state, line, emit)
  end

  defp decode_line(state, line, emit) do
    case Jason.decode(line) do
      {:ok, %{"error" => _}} ->
        {:error, "Ollama rejected the request. Check the model is installed and supports tools."}

      {:ok, data} when is_map(data) ->
        message = data["message"] || %{}
        delta = message["content"] || ""
        calls = message["tool_calls"] || []

        usage =
          if data["done"],
            do: %{
              "input_tokens" => data["prompt_eval_count"],
              "output_tokens" => data["eval_count"],
              "input_cached_tokens" => data["prompt_eval_cached_count"],
              "provider_duration_ns" => data["total_duration"]
            },
            else: state.usage

        if data["done"] == true, do: emit.({:provider_usage, usage})

        if data["done"] == true and data["done_reason"] == "length" do
          {:error,
           "Ollama reached a generation limit; the response is incomplete and no tools were executed."}
        else
          with true <- is_list(calls) and length(Enum.take(calls, 33)) + state.call_count <= 32,
               {:ok, content} <- Fragments.append(state.content, delta),
               {:ok, thinking} <- Fragments.append(state.thinking, message["thinking"] || "") do
            if delta != "", do: emit.({:text, delta})

            {:ok,
             %{
               state
               | content: content,
                 thinking: thinking,
                 calls: Enum.reverse(calls, state.calls),
                 call_count: state.call_count + length(calls),
                 done: state.done or data["done"] == true,
                 usage: usage,
                 reported_model:
                   Ipse.RuntimeInfo.model_name(data["model"]) || state.reported_model
             }}
          else
            _ -> Fragments.error()
          end
        end

      _ ->
        {:error, "Invalid JSON in Ollama stream."}
    end
  end

  defp encode_args(args) when is_binary(args), do: args
  defp encode_args(args), do: Jason.encode!(args || %{})
end
