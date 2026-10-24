defmodule Ipse.Provider.ChatCompletions do
  @moduledoc "Pinned OpenRouter and explicit loopback Chat Completions with native continuation."
  alias Ipse.Provider.{Registry, Stream, Transport}

  def endpoint(config),
    do:
      Ipse.Provider.endpoint(
        config,
        Registry.fetch!(config[:provider]).default_base_url,
        "/chat/completions"
      )

  def validate_model(model) do
    if Ipse.Provider.model_name(model) && model != "openrouter/auto" &&
         not String.ends_with?(model, [":nitro", ":floor"]) && not String.contains?(model, ","),
       do: :ok,
       else:
         {:error,
          "OpenRouter requires an explicit model without auto-routing or routing variants."}
  end

  def validate_profile(%{"provider" => "openrouter"} = profile) do
    cond do
      not is_binary(profile["upstream"]) or
          not Regex.match?(~r/\A[a-z0-9][a-z0-9._-]{0,63}\z/, profile["upstream"]) ->
        {:error,
         "OpenRouter requires a profile with a pinned upstream; see docs/operator/configuration.md#pin-an-openrouter-upstream."}

      Map.get(profile, "data_collection", "deny") not in ["deny", "allow"] ->
        {:error, "OpenRouter data_collection must be deny or allow."}

      true ->
        validate_model(profile["model"])
    end
  end

  def validate_profile(%{"provider" => "openai_compatible"} = profile) do
    cond do
      is_nil(Ipse.Provider.model_name(profile["model"])) ->
        {:error, "Local compatible inference requires an explicit model."}

      is_nil(profile["base_url"]) or
          not Ipse.Provider.valid_base_url?(:openai_compatible, profile["base_url"]) ->
        {:error,
         "Local compatible inference requires an explicit loopback base_url; remote services are refused."}

      true ->
        :ok
    end
  end

  def validate_request(config) do
    profile = %{
      "provider" => to_string(config[:provider]),
      "model" => config[:model],
      "base_url" => config[:base_url],
      "upstream" => config[:upstream],
      "data_collection" => config[:data_collection] || "deny"
    }

    with :ok <- validate_profile(profile),
         :ok <- Registry.reasoning(config[:provider], config[:model], config[:reasoning_effort]) do
      case config[:provider] do
        :openrouter ->
          selected = config[:execution]

          if is_map(selected) and is_binary(selected[:id]) and selected[:provider] == "openrouter" and
               selected[:model] == config[:model] and selected[:upstream] == config[:upstream] and
               selected[:data_collection] == profile["data_collection"] and
               selected[:base_url] == config[:base_url] and
               selected[:reasoning_effort] == config[:reasoning_effort] and
               selected[:credential] == "OPENROUTER_API_KEY",
             do: :ok,
             else:
               {:error,
                "OpenRouter requires a profile with a pinned upstream; see docs/operator/configuration.md#pin-an-openrouter-upstream."}

        :openai_compatible ->
          if config[:api_key] in [nil, ""],
            do: :ok,
            else:
              {:error, "Local compatible inference uses no credential; remove the supplied key."}
      end
    end
  end

  def complete(config, messages, tools, emit) do
    with :ok <- validate_request(config),
         {:ok, headers} <- headers(config),
         {:ok, state} <-
           Transport.stream(
             endpoint(config),
             headers,
             request_body(config, messages, tools),
             config,
             new(config),
             &consume(&1, &2, emit)
           ),
         do: finish(state)
  end

  defp headers(%{provider: :openrouter, api_key: key}) when is_binary(key) and byte_size(key) > 0,
    do: {:ok, [{"authorization", "Bearer " <> key}, {"accept", "text/event-stream"}]}

  defp headers(%{provider: :openai_compatible}), do: {:ok, [{"accept", "text/event-stream"}]}
  defp headers(_), do: {:error, "Set OPENROUTER_API_KEY first."}

  def request_body(config, messages, tools) do
    replay = Registry.fetch!(config[:provider]).replay_key

    body = %{
      "model" => config[:model],
      "messages" => Enum.map(messages, &native(&1, replay)),
      "stream" => true,
      "stream_options" => %{"include_usage" => true}
    }

    body =
      if tools == [],
        do: body,
        else: Map.merge(body, %{"tools" => tools, "tool_choice" => "auto"})

    cap = Ipse.Provider.output_tokens(config)
    body = if cap, do: Map.put(body, "max_tokens", cap), else: body

    if config[:provider] == :openrouter do
      body =
        Map.put(body, "provider", %{
          "only" => [config[:upstream]],
          "order" => [config[:upstream]],
          "allow_fallbacks" => false,
          "require_parameters" => true,
          "data_collection" => config[:data_collection] || "deny"
        })

      if config[:reasoning_effort],
        do: Map.put(body, "reasoning", %{"effort" => config[:reasoning_effort]}),
        else: body
    else
      body
    end
  end

  defp native(%{"ipse_checkpoint" => _} = message, _) do
    if Ipse.Session.Context.valid_checkpoint?(message),
      do: %{"role" => "system", "content" => message["content"]},
      else: raise(ArgumentError, "invalid historical context checkpoint")
  end

  defp native(
         %{"role" => "assistant", "provider_data" => %{"provider" => key, "message" => native}},
         key
       ),
       do: native

  defp native(%{"role" => "developer"} = message, _),
    do: %{"role" => "system", "content" => message["content"]}

  defp native(message, _), do: Map.take(message, ~w(role content tool_calls tool_call_id))

  def new(config),
    do: %{
      sse: Stream.new_sse(),
      config: config,
      verified: false,
      done: false,
      finish_reason: nil,
      content: Stream.new_buffer(),
      reasoning: Stream.new_buffer(),
      reasoning_seen: false,
      details: [],
      detail_count: 0,
      details_seen: false,
      calls: %{},
      usage: %{},
      reported_model: nil,
      reported_upstream: nil
    }

  def consume(state, chunk, emit) do
    handler = fn event, state ->
      with {:ok, state} <- Stream.tick(state) do
        case event.data do
          "[DONE]" ->
            if state.done, do: Stream.error(), else: {:ok, %{state | done: true}}

          bytes ->
            if state.done do
              Stream.error()
            else
              case Jason.decode(bytes) do
                {:ok, data} when is_map(data) -> event(state, data, emit)
                _ -> {:error, "Invalid JSON in Chat Completions stream."}
              end
            end
        end
      end
    end

    with {:ok, state, parser} <- Stream.reduce_sse(state.sse, chunk, state, handler),
         do: {:ok, %{state | sse: parser}}
  end

  defp event(state, data, emit) do
    state =
      if data["usage"] do
        emit.({:provider_usage, data["usage"]})
        %{state | usage: data["usage"]}
      else
        state
      end

    with {:ok, state} <- identity(state, data),
         :ok <- stream_error(data, state.config),
         choices = Map.get(data, "choices", []),
         true <- is_list(choices) and length(Enum.take(choices, 2)) <= 1 do
      case choices do
        [] -> {:ok, state}
        [choice] when is_map(choice) -> choice(state, choice, data, emit)
        _ -> Stream.error()
      end
    else
      {:error, _} = error -> error
      _ -> Stream.error()
    end
  end

  defp identity(%{config: %{provider: :openrouter}} = state, data) do
    cond do
      (not state.verified or Map.has_key?(data, "model")) and data["model"] != state.config.model ->
        {:error, "OpenRouter served a different model than requested; the response was refused."}

      (not state.verified or Map.has_key?(data, "provider")) and
          not upstream?(state.config.upstream, data["provider"]) ->
        {:error, "OpenRouter served a different upstream than pinned; the response was refused."}

      true ->
        {:ok,
         %{
           state
           | verified: true,
             reported_model: data["model"] || state.reported_model,
             reported_upstream: data["provider"] || state.reported_upstream
         }}
    end
  end

  defp identity(state, data),
    do:
      {:ok,
       %{
         state
         | verified: true,
           reported_model: Ipse.Provider.model_name(data["model"]) || state.reported_model
       }}

  # The public providers catalog explicitly pairs this display name and slug.
  # Other names require exact equality; never guess aliases by case or punctuation.
  defp upstream?("openai", "OpenAI"), do: true
  defp upstream?(pinned, reported), do: pinned == reported

  defp stream_error(%{"error" => error}, config), do: reported_error(error, config)
  defp stream_error(_, _), do: :ok

  defp reported_error(error, config) do
    text =
      if is_map(error) and is_binary(error["message"]),
        do: error["message"],
        else: "provider refused the response"

    Ipse.Provider.error("Chat Completions stream failed: " <> text, config)
  end

  defp choice(state, choice, data, emit) do
    delta = choice["delta"] || %{}
    reason = choice["finish_reason"]

    cond do
      choice["index"] not in [nil, 0] or not is_map(delta) or
          delta["role"] not in [nil, "assistant"] ->
        Stream.error()

      choice["error"] ->
        reported_error(choice["error"], state.config)

      reason == "length" ->
        {:error,
         "Chat Completions reached a generation limit; the response is incomplete and no tools were executed."}

      reason in ["error", "content_filter"] ->
        reported_error(choice["error"], state.config)

      reason not in [nil, "stop", "tool_calls"] ->
        {:error, "Chat Completions returned an unsupported finish reason."}

      state.finish_reason != nil ->
        if is_map(data["usage"]) and reason in [nil, state.finish_reason] and
             delta["content"] in [nil, ""] and Map.drop(delta, ~w(role content)) == %{},
           do: {:ok, state},
           else: Stream.error()

      true ->
        with {:ok, state} <- delta(state, delta, emit),
             do: {:ok, %{state | finish_reason: reason}}
    end
  end

  defp delta(state, delta, emit) do
    text = delta["content"] || ""
    details = delta["reasoning_details"] || []

    with true <- delta["refusal"] in [nil, ""],
         true <-
           is_list(details) and length(Enum.take(details, 32_769)) + state.detail_count <= 32_768 and
             Enum.all?(details, &is_map/1),
         {:ok, content} <- Stream.append_buffer(state.content, text),
         {:ok, reasoning} <- Stream.append_buffer(state.reasoning, delta["reasoning"] || ""),
         {:ok, calls} <- calls(state.calls, delta["tool_calls"] || []) do
      if text != "", do: emit.({:text, text})

      {:ok,
       %{
         state
         | content: content,
           reasoning: reasoning,
           calls: calls,
           reasoning_seen: state.reasoning_seen or is_binary(delta["reasoning"]),
           details: Enum.reverse(details, state.details),
           detail_count: state.detail_count + length(details),
           details_seen: state.details_seen or is_list(delta["reasoning_details"])
       }}
    else
      _ -> Stream.error()
    end
  end

  defp calls(previous, fragments) when is_list(fragments) do
    if length(Enum.take(fragments, 33)) > 32 do
      Stream.error()
    else
      Enum.reduce_while(fragments, {:ok, previous}, fn call, {:ok, calls} ->
        with true <-
               is_map(call) and Stream.index?(call["index"]) and call["type"] in [nil, "function"],
             function = call["function"] || %{},
             true <- is_map(function),
             fields = Map.get(calls, call["index"], %{}),
             {:ok, fields} <- append_field(fields, "id", call["id"]),
             {:ok, fields} <- append_field(fields, "name", function["name"]),
             {:ok, fields} <- append_field(fields, "arguments", function["arguments"]),
             calls = Map.put(calls, call["index"], fields),
             true <- map_size(calls) <= 32 do
          {:cont, {:ok, calls}}
        else
          _ -> {:halt, Stream.error()}
        end
      end)
    end
  end

  defp calls(_, _), do: Stream.error()
  defp append_field(fields, _, nil), do: {:ok, fields}
  defp append_field(fields, key, bytes), do: Stream.update_field(fields, key, bytes)

  def finish(%{done: true, finish_reason: reason, verified: true} = state)
      when reason in ["stop", "tool_calls"] do
    calls =
      state.calls
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {_, fields} ->
        fields = Stream.materialize_fields(fields)

        %{
          "id" => fields["id"],
          "type" => "function",
          "function" => %{"name" => fields["name"], "arguments" => fields["arguments"] || "{}"}
        }
      end)

    with :ok <- Stream.check_deadline(state),
         {:ok, _} <- Ipse.Tools.admit_calls(calls, Ipse.Tools.empty_call_budget()),
         true <- Enum.all?(calls, &complete_call?/1) do
      text = Stream.buffer_value(state.content)
      native = %{"role" => "assistant", "content" => text}
      native = if calls == [], do: native, else: Map.put(native, "tool_calls", calls)

      native =
        if state.reasoning_seen,
          do: Map.put(native, "reasoning", Stream.buffer_value(state.reasoning)),
          else: native

      native =
        if state.details_seen,
          do: Map.put(native, "reasoning_details", Enum.reverse(state.details)),
          else: native

      message = %{
        "role" => "assistant",
        "content" => text,
        "provider_data" => %{
          "provider" => Registry.fetch!(state.config.provider).replay_key,
          "message" => native,
          "reported_model" => state.reported_model,
          "reported_upstream" => state.reported_upstream
        }
      }

      message = if calls == [], do: message, else: Map.put(message, "tool_calls", calls)
      with :ok <- Stream.check_deadline(state), do: {:ok, message, state.usage}
    else
      _ -> Stream.error()
    end
  end

  def finish(_),
    do:
      {:error,
       "Chat Completions stream ended without a successful finish reason and [DONE]; no tools were executed."}

  defp complete_call?(%{"function" => %{"name" => name, "arguments" => arguments}}) do
    with true <- is_binary(name) and byte_size(name) in 1..256,
         {:ok, value} when is_map(value) <- Ipse.JSON.decode_unique(arguments) do
      true
    else
      _ -> false
    end
  end
end
