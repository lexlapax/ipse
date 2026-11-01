defmodule Ipse.Provider.Ollama do
  @moduledoc "Ollama native streaming chat adapter."
  alias Ipse.Provider.Stream
  alias Ipse.Provider.Transport

  def validate_profile(profile) do
    with true <-
           not Map.has_key?(profile, "ollama_context_tokens") or
             context_tokens?(profile["ollama_context_tokens"]),
         true <-
           not Map.has_key?(profile, "ollama_model_pin") or
             pin?(profile["ollama_model_pin"], profile["ollama_context_tokens"]) do
      :ok
    else
      _ -> context_error()
    end
  end

  def validate_request(config) do
    value = config[:ollama_context_tokens]

    cond do
      not (is_nil(value) or context_tokens?(value)) ->
        context_error()

      Map.has_key?(config, :ollama_model_pin) and not pin?(config[:ollama_model_pin], value) ->
        context_error()

      not selected_pin?(config) ->
        {:error, "Pinned Ollama inference requires the matching saved named profile selection."}

      true ->
        :ok
    end
  end

  defp context_tokens?(value), do: is_integer(value) and value in 512..262_144

  defp pin?(pin, context),
    do:
      Ipse.Provider.Ollama.Models.valid_pin?(pin) and
        (is_nil(context) or context >= pin["minimum_context_tokens"])

  # Pinned runtime data must come from the saved named execution selection.
  # Dropping only the runtime field cannot silently resume an unpinned route.
  defp selected_pin?(config) do
    execution = config[:execution] || %{}
    if is_map(execution), do: selected_pin?(config, execution), else: false
  end

  defp selected_pin?(config, execution) do
    configured = Map.fetch(config, :ollama_model_pin)
    selected = execution_field(execution, :ollama_model_pin)

    case {configured, selected} do
      {:error, :error} ->
        true

      {{:ok, pin}, {:ok, pin}} ->
        execution_field(execution, :provider) == {:ok, "ollama"} and
          execution_field(execution, :model) == Map.fetch(config, :model) and
          execution_field(execution, :ollama_context_tokens) ==
            Map.fetch(config, :ollama_context_tokens)

      _ ->
        false
    end
  end

  defp execution_field(execution, key) do
    case Map.fetch(execution, key) do
      :error -> Map.fetch(execution, Atom.to_string(key))
      value -> value
    end
  end

  defp context_error,
    do:
      {:error,
       "Ollama context request must be an integer in 512..262144 tokens and satisfy any valid model pin."}

  def endpoint(config),
    do:
      Ipse.Provider.endpoint(
        config,
        Ipse.Provider.Registry.fetch!(:ollama).default_base_url,
        "/api/chat"
      )

  def request_body(config, messages, tools) do
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

    limit = Ipse.Provider.output_tokens(config)
    body = if limit, do: Map.put(body, "options", %{"num_predict" => limit}), else: body

    body =
      if config[:ollama_context_tokens],
        do:
          Map.update(
            body,
            "options",
            %{"num_ctx" => config.ollama_context_tokens},
            &Map.put(&1, "num_ctx", config.ollama_context_tokens)
          ),
        else: body

    body = if config[:reasoning_effort] == "none", do: Map.put(body, "think", false), else: body

    body =
      if is_map(config[:extension_response_schema]),
        do: Map.put(body, "format", config.extension_response_schema),
        else: body

    if is_map(config[:summary_schema]) do
      Map.merge(body, %{
        "format" => config.summary_schema,
        "think" => false,
        "options" =>
          Map.merge(body["options"] || %{}, %{
            "temperature" => 0,
            "num_predict" => Ipse.Provider.narrow_output_tokens(limit, 4096)
          })
      })
    else
      body
    end
  end

  def complete(config, messages, tools, emit) do
    url = endpoint(config)
    body = request_body(config, messages, tools)

    state = new_state()

    headers =
      if config[:api_key] in [nil, ""],
        do: [],
        else: [{"authorization", "Bearer " <> config[:api_key]}]

    with :ok <- Ipse.Provider.Ollama.Models.request_allowed?(config),
         {:ok, state} <-
           Transport.stream(url, headers, body, config, state, fn state, chunk ->
             consume(state, chunk, emit)
           end),
         {:ok, state} <- last_line(state, emit),
         :ok <- Stream.check_deadline(state),
         do: finish_state(state)
  end

  # Unwired owned transport uses the same native parser with a private sink.
  @doc false
  def parse_buffered(bytes) when is_binary(bytes) do
    sink = fn _ -> :ok end

    with {:ok, state} <- consume(new_state(), bytes, sink),
         {:ok, state} <- last_line(state, sink),
         do: finish_state(state)
  end

  defp new_state do
    %{
      lines: Stream.new_lines(:lf),
      content: Stream.new_buffer(),
      thinking: Stream.new_buffer(),
      calls: [],
      call_count: 0,
      done: false,
      usage: %{},
      reported_model: nil
    }
  end

  defp finish_state(state) do
    if state.done do
      response_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
      content = Stream.buffer_value(state.content)
      thinking = Stream.buffer_value(state.thinking)
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
      with :ok <- Stream.check_deadline(state), do: {:ok, message, state.usage}
    else
      {:error, "Ollama stream ended before its completion marker; no tools were executed."}
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
    with {:ok, parser, state} <-
           Stream.reduce_lines(state.lines, chunk, state, fn line, state ->
             line(state, line, emit)
           end),
         do: {:ok, %{state | lines: parser}}
  end

  defp last_line(state, emit) do
    with :ok <- Stream.check_deadline(state),
         {:ok, tail, parser} <- Stream.finish_lines(state.lines) do
      state = %{state | lines: parser}
      if is_nil(tail), do: {:ok, state}, else: line(state, tail, emit)
    end
  end

  defp line(state, "", _) do
    with :ok <- Stream.check_deadline(state), do: {:ok, state}
  end

  defp line(%{done: true}, _line, _emit),
    do: {:error, "Ollama stream contained data after its completion marker."}

  defp line(state, line, emit) do
    with {:ok, state} <- Stream.tick(state),
         {:ok, state} <- decode_line(state, line, emit),
         :ok <- Stream.check_deadline(state),
         do: {:ok, state}
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
               {:ok, content} <- Stream.append_buffer(state.content, delta),
               {:ok, thinking} <- Stream.append_buffer(state.thinking, message["thinking"] || "") do
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
                 reported_model: Ipse.Provider.model_name(data["model"]) || state.reported_model
             }}
          else
            _ -> Stream.error()
          end
        end

      _ ->
        {:error, "Invalid JSON in Ollama stream."}
    end
  end

  defp encode_args(args) when is_binary(args), do: args
  defp encode_args(args), do: Jason.encode!(args || %{})
end
