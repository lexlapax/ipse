defmodule Runespell.Provider.Ollama do
  @moduledoc "Ollama native streaming chat adapter."
  alias Runespell.Provider.HTTP

  def complete(config, messages, tools, emit) do
    url = Runespell.Provider.endpoint(config, "http://127.0.0.1:11434", "/api/chat")

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

    state = %{buffer: "", content: "", thinking: "", calls: [], done: false, usage: %{}}

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

        calls =
          Enum.with_index(state.calls)
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
          "content" => state.content,
          "thinking" => state.thinking,
          "tool_calls" => state.calls
        }

        message = %{
          "role" => "assistant",
          "content" => state.content,
          "provider_data" => %{"provider" => "ollama", "message" => native}
        }

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
    parts = :binary.split(state.buffer <> chunk, "\n", [:global])
    {lines, [buffer]} = Enum.split(parts, -1)

    Enum.reduce_while(lines, {:ok, %{state | buffer: buffer}}, fn line, {:ok, state} ->
      case line(state, line, emit) do
        {:ok, state} -> {:cont, {:ok, state}}
        error -> {:halt, error}
      end
    end)
  end

  defp last_line(%{buffer: ""} = state, _), do: {:ok, state}
  defp last_line(state, emit), do: line(state, state.buffer, emit)
  defp line(state, "", _), do: {:ok, state}

  defp line(state, line, emit) do
    case Jason.decode(line) do
      {:ok, %{"error" => _}} ->
        {:error, "Ollama rejected the request. Check the model is installed and supports tools."}

      {:ok, data} when is_map(data) ->
        message = data["message"] || %{}
        delta = message["content"] || ""
        if delta != "", do: emit.({:text, delta})

        usage =
          if data["done"],
            do: %{
              "input_tokens" => data["prompt_eval_count"] || 0,
              "output_tokens" => data["eval_count"] || 0
            },
            else: state.usage

        {:ok,
         %{
           state
           | content: state.content <> delta,
             thinking: state.thinking <> (message["thinking"] || ""),
             calls: state.calls ++ (message["tool_calls"] || []),
             done: state.done or data["done"] == true,
             usage: usage
         }}

      _ ->
        {:error, "Invalid JSON in Ollama stream."}
    end
  end

  defp encode_args(args) when is_binary(args), do: args
  defp encode_args(args), do: Jason.encode!(args || %{})
end
