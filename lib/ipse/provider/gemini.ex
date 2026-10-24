defmodule Ipse.Provider.Gemini do
  @moduledoc "Stateless Gemini streaming with immutable signed native parts."
  alias Ipse.Provider.{Registry, Stream, Transport}

  def model_name(model) when is_binary(model) do
    model = String.replace_prefix(model, "models/", "")

    if Ipse.Provider.model_name(model) && Regex.match?(~r/\A[a-z0-9][a-z0-9.-]{0,127}\z/, model),
      do: model
  end

  def model_name(_), do: nil

  def validate_profile(profile) do
    host = if is_binary(profile["base_url"]), do: URI.parse(profile["base_url"]).host

    host =
      if is_binary(host), do: host |> String.downcase() |> String.trim_trailing("."), else: host

    cond do
      is_binary(host) and
          (host == "aiplatform.googleapis.com" or host == "aiplatform.mtls.googleapis.com" or
             String.ends_with?(host, "-aiplatform.mtls.googleapis.com") or
             String.ends_with?(host, ".aiplatform.mtls.googleapis.com") or
             String.ends_with?(host, "-aiplatform.googleapis.com") or
             String.ends_with?(host, ".aiplatform.googleapis.com")) ->
        {:error, "Vertex AI is not supported yet; use a Gemini API key."}

      is_nil(model_name(profile["model"])) ->
        {:error,
         "Gemini requires an explicit lowercase model id, optionally prefixed with models/."}

      not Ipse.Provider.valid_base_url?(:gemini, profile["base_url"]) ->
        {:error,
         "Gemini base_url requires HTTPS or explicit HTTP loopback, without credentials, query or fragment."}

      true ->
        :ok
    end
  end

  def validate_request(config) do
    with :ok <- validate_profile(%{"model" => config[:model], "base_url" => config[:base_url]}),
         do: Registry.reasoning(:gemini, config[:model], config[:reasoning_effort])
  end

  def endpoint(config) do
    case validate_profile(%{"model" => config[:model], "base_url" => config[:base_url]}) do
      :ok -> :ok
      {:error, message} -> raise ArgumentError, message
    end

    model = model_name(config[:model]) || raise ArgumentError, "Invalid Gemini model id."
    spec = Registry.fetch!(:gemini)

    Ipse.Provider.endpoint(
      config,
      spec.default_base_url,
      "/models/" <> model <> ":streamGenerateContent?" <> spec.wire_query
    )
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
             new(),
             &consume(&1, &2, emit)
           ),
         do: finish(state)
  end

  defp headers(%{api_key: key}) when is_binary(key) and byte_size(key) > 0,
    do: {:ok, [{"x-goog-api-key", key}, {"accept", "text/event-stream"}]}

  defp headers(_),
    do: {:error, "Set GEMINI_API_KEY first; GOOGLE_API_KEY is not selected implicitly."}

  def request_body(config, messages, tools) do
    {system, messages} =
      Enum.split_with(
        messages,
        &(&1["role"] in ["system", "developer"] and not Map.has_key?(&1, "ipse_checkpoint"))
      )

    {contents, _, _} = Enum.reduce(messages, {[], %{}, false}, &native/2)
    body = %{"contents" => Enum.reverse(contents)}

    body =
      if system == [],
        do: body,
        else:
          Map.put(body, "systemInstruction", %{
            "parts" => [%{"text" => Enum.map_join(system, "\n\n", &(&1["content"] || ""))}]
          })

    generation = %{}
    limit = Ipse.Provider.output_tokens(config)
    generation = if limit, do: Map.put(generation, "maxOutputTokens", limit), else: generation

    generation =
      if config[:reasoning_effort] in [nil, "none"],
        do: generation,
        else:
          Map.put(generation, "thinkingConfig", %{
            "thinkingLevel" => String.upcase(config.reasoning_effort),
            "includeThoughts" => false
          })

    body = if generation == %{}, do: body, else: Map.put(body, "generationConfig", generation)

    if tools == [] do
      body
    else
      declarations =
        Enum.map(tools, fn %{"function" => function} ->
          %{
            "name" => function["name"],
            "description" => function["description"] || "",
            "parametersJsonSchema" => function["parameters"] || %{"type" => "object"}
          }
        end)

      Map.merge(body, %{
        "tools" => [%{"functionDeclarations" => declarations}],
        "toolConfig" => %{"functionCallingConfig" => %{"mode" => "AUTO"}}
      })
    end
  end

  defp native(%{"ipse_checkpoint" => _} = message, {acc, _, _}) do
    if not Ipse.Session.Context.valid_checkpoint?(message),
      do: raise(ArgumentError, "invalid historical context checkpoint")

    {[%{"role" => "user", "parts" => [%{"text" => message["content"]}]} | acc], %{}, false}
  end

  defp native(%{"role" => "tool"} = message, {acc, names, previous_tool?}) do
    {name, id} = Map.fetch!(names, message["tool_call_id"])
    response = %{"name" => name, "response" => %{"content" => message["content"] || ""}}
    response = if id, do: Map.put(response, "id", id), else: response
    part = %{"functionResponse" => response}

    acc =
      if previous_tool? do
        [previous | tail] = acc
        [Map.update!(previous, "parts", &(&1 ++ [part])) | tail]
      else
        [%{"role" => "user", "parts" => [part]} | acc]
      end

    {acc, names, true}
  end

  defp native(%{"role" => "assistant"} = message, {acc, _, _}) do
    content =
      case message["provider_data"] do
        %{"provider" => "gemini", "content" => content} ->
          content

        _ ->
          text =
            if message["content"] in [nil, ""], do: [], else: [%{"text" => message["content"]}]

          calls =
            Enum.map(message["tool_calls"] || [], fn call ->
              {:ok, args} = Ipse.JSON.decode_unique(call["function"]["arguments"])
              if not is_map(args), do: raise(ArgumentError, "tool arguments require an object")

              %{
                "functionCall" => %{
                  "name" => call["function"]["name"],
                  "args" => args
                }
              }
            end)

          %{"role" => "model", "parts" => text ++ calls}
      end

    native_calls = for %{"functionCall" => call} <- content["parts"], do: call
    calls = message["tool_calls"] || []

    if length(calls) != length(native_calls),
      do: raise(ArgumentError, "native call history mismatch")

    names =
      Enum.zip(calls, native_calls)
      |> Map.new(fn {call, native} ->
        {call["id"], {native["name"], native["id"]}}
      end)

    {[content | acc], names, false}
  end

  defp native(%{"role" => "user"} = message, {acc, _, _}),
    do:
      {[%{"role" => "user", "parts" => [%{"text" => message["content"] || ""}]} | acc], %{},
       false}

  def new,
    do: %{
      sse: Stream.new_sse(),
      parts: [],
      part_count: 0,
      part_bytes: 0,
      content: Stream.new_buffer(),
      calls: [],
      call_count: 0,
      finish_reason: nil,
      usage: %{},
      reported_model: nil,
      response_id: Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
    }

  def consume(state, bytes, emit) do
    handler = fn event, state ->
      with {:ok, state} <- Stream.tick(state),
           {:ok, data} when is_map(data) <- Ipse.JSON.decode_unique(event.data),
           do: event(state, data, emit),
           else: (_ -> {:error, "Invalid JSON in Gemini stream."})
    end

    with {:ok, state, parser} <- Stream.reduce_sse(state.sse, bytes, state, handler),
         do: {:ok, %{state | sse: parser}}
  end

  defp event(state, data, emit) do
    state =
      if Map.has_key?(data, "usageMetadata") do
        emit.({:provider_usage, data["usageMetadata"]})
        %{state | usage: data["usageMetadata"]}
      else
        state
      end

    cond do
      Map.has_key?(data, "error") ->
        {:error,
         "Gemini rejected the stream. Check the model, thinking level and signed history; start a fresh session or hand off if history is refused."}

      is_map(data["promptFeedback"]) and data["promptFeedback"]["blockReason"] != nil ->
        reason_error(data["promptFeedback"]["blockReason"])

      not is_map(state.usage) ->
        Stream.error()

      true ->
        state = %{
          state
          | reported_model: Ipse.Provider.model_name(data["modelVersion"]) || state.reported_model
        }

        case Map.get(data, "candidates", []) do
          [] -> {:ok, state}
          [candidate] when is_map(candidate) -> candidate(state, candidate, emit)
          _ -> Stream.error()
        end
    end
  end

  defp candidate(state, candidate, emit) do
    content = candidate["content"] || %{}
    parts = if is_map(content), do: Map.get(content, "parts", []), else: nil
    reason = candidate["finishReason"]

    cond do
      reason == "MAX_TOKENS" ->
        {:error,
         "Gemini reached a generation limit; the response is incomplete and no tools were executed."}

      reason not in [nil, "STOP"] ->
        reason_error(reason)

      not is_map(content) or content["role"] not in [nil, "model"] or
          candidate["index"] not in [nil, 0] ->
        Stream.error()

      not is_list(parts) or state.part_count + length(Enum.take(parts, 4097)) > 4096 ->
        Stream.error()

      state.finish_reason != nil ->
        if parts == [], do: {:ok, state}, else: Stream.error()

      true ->
        Enum.reduce_while(parts, {:ok, state}, fn part, {:ok, state} ->
          case part(state, part, emit) do
            {:ok, next} -> {:cont, {:ok, next}}
            error -> {:halt, error}
          end
        end)
        |> case do
          {:ok, state} -> {:ok, %{state | finish_reason: reason}}
          error -> error
        end
    end
  end

  defp part(state, part, emit) when is_map(part) do
    bytes = byte_size(Jason.encode!(part))

    with true <- state.part_bytes + bytes <= 8_388_608,
         true <- part["thought"] in [nil, true, false],
         {:ok, state} <- call(state, part["functionCall"]),
         text = if(part["thought"] == true, do: "", else: Map.get(part, "text", "")),
         {:ok, content} <- Stream.append_buffer(state.content, text) do
      if text != "", do: emit.({:text, text})

      {:ok,
       %{
         state
         | content: content,
           parts: [part | state.parts],
           part_count: state.part_count + 1,
           part_bytes: state.part_bytes + bytes
       }}
    else
      _ -> Stream.error()
    end
  end

  defp part(_, _, _), do: Stream.error()

  defp call(state, nil), do: {:ok, state}

  defp call(state, %{"name" => name, "args" => args} = native)
       when is_binary(name) and byte_size(name) in 1..256 and is_map(args) do
    if state.call_count < 32 do
      call = %{
        "id" => native["id"] || "gemini_#{state.response_id}_#{state.call_count}",
        "type" => "function",
        "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
      }

      {:ok, %{state | calls: [call | state.calls], call_count: state.call_count + 1}}
    else
      Stream.error()
    end
  end

  defp call(_, _), do: Stream.error()

  defp reason_error(reason) do
    name =
      if is_binary(reason) and Regex.match?(~r/\A[A-Z][A-Z0-9_]{0,63}\z/, reason),
        do: reason,
        else: "UNKNOWN"

    {:error, "Gemini refused the response (#{name}); no tools were executed."}
  end

  def finish(%{finish_reason: "STOP"} = state) do
    calls = Enum.reverse(state.calls)

    with :ok <- Stream.check_deadline(state),
         {:ok, _} <- Ipse.Tools.admit_calls(calls, Ipse.Tools.empty_call_budget()) do
      message = %{
        "role" => "assistant",
        "content" => Stream.buffer_value(state.content),
        "provider_data" => %{
          "provider" => "gemini",
          "content" => %{
            "role" => "model",
            "parts" => Enum.reverse(state.parts)
          },
          "reported_model" => state.reported_model
        }
      }

      message = if calls == [], do: message, else: Map.put(message, "tool_calls", calls)
      {:ok, message, state.usage}
    end
  end

  def finish(_),
    do:
      {:error, "Gemini stream ended without a successful finish reason; no tools were executed."}
end
