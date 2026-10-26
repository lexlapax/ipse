defmodule Ipse.Provider.Spec do
  @moduledoc "Closed provider capabilities and operator-facing identity."
  @enforce_keys [:id, :atom, :adapter, :credential, :billing_mode]
  defstruct [
    :id,
    :atom,
    :adapter,
    :replay_key,
    :default_model,
    :default_base_url,
    :base_url_policy,
    :credential,
    :billing_mode,
    :output_limit,
    :reasoning,
    :usage_extractor,
    :embedding,
    :label,
    :probe,
    :probe_base_url,
    :input_components,
    :wire_query,
    :profile_validator,
    :request_validator,
    profile_fields: %{},
    profile_defaults: %{},
    route_fields: [],
    output_limit_scope: :all_output,
    structured_output?: false,
    summary_schema?: false,
    http_hints: %{},
    secret_env: []
  ]
end

defmodule Ipse.Provider.Registry do
  @moduledoc "Provider identity, capability and credential metadata; selection never falls back."
  alias Ipse.Provider.Spec

  @codes %{
    "subscription_sharing_user_not_eligible" =>
      "ChatGPT plan usage is unavailable for this account, workspace, or policy. Check eligibility; the request was not retried.",
    "subscription_sharing_usage_limit_exceeded" =>
      "ChatGPT plan usage is blocked by a limit or app setting. Pause plan requests and check ChatGPT Settings > Usage; no reset time is inferred.",
    "subscription_sharing_usage_unavailable" =>
      "ChatGPT plan usage availability could not be checked. Preserve sign-in and try again later.",
    "subscription_sharing_unsupported_capability" =>
      "This request uses an unsupported ChatGPT plan capability. Check the parameter and adjust the request before trying again.",
    "subscription_sharing_route_not_supported" =>
      "ChatGPT plan usage does not support this method or endpoint. Verify that the request uses POST /v1/responses.",
    "subscription_sharing_invalid_user" =>
      "The ChatGPT subscriber context was rejected. Check the selected account and scopes; sign in again only after confirmed revocation or terminal refresh failure.",
    "chatpass_v2_scope_not_authorized" =>
      "The ChatGPT permission context does not authorize this operation. Check the client and grant configuration; billing was not changed.",
    "chatpass_v2_invalid_authorization_context" =>
      "The ChatGPT permission context does not authorize this operation. Check the client and grant configuration; billing was not changed.",
    "subscription_sharing_user_unavailable" =>
      "ChatGPT user or workspace information is temporarily unavailable. Preserve sign-in and try again later."
  }

  @specs [
    %Spec{
      id: "chatgpt",
      http_hints: %{codes: @codes, fallback: &__MODULE__.chatgpt_hint/3},
      atom: :chatgpt,
      adapter: Ipse.Provider.OpenAI,
      replay_key: "openai",
      default_model: "gpt-6.1-sol",
      default_base_url: "https://api.openai.com/v1",
      base_url_policy: :fixed,
      credential: :chatgpt_auth,
      billing_mode: "subscription",
      output_limit: :refuse_cap,
      reasoning: &__MODULE__.responses_reasoning/2,
      usage_extractor: &__MODULE__.responses_usage/1,
      secret_env: ["IPSE_CHATGPT_ACCESS_TOKEN"],
      label: "ChatGPT subscription",
      probe: :subscription
    },
    %Spec{
      id: "openai",
      atom: :openai,
      adapter: Ipse.Provider.OpenAI,
      replay_key: "openai",
      default_model: "gpt-6.1-sol",
      default_base_url: "https://api.openai.com/v1",
      base_url_policy: :https_or_loopback,
      credential: {:env, "OPENAI_API_KEY"},
      billing_mode: "api",
      output_limit: 16..1_000_000,
      reasoning: &__MODULE__.responses_reasoning/2,
      usage_extractor: &__MODULE__.responses_usage/1,
      embedding: %{
        usage_extractor: &__MODULE__.openai_embedding_usage/1,
        capacity_inputs: &__MODULE__.openai_embedding_inputs/0
      },
      secret_env: ["OPENAI_API_KEY"],
      label: "OpenAI API (billed)",
      probe: {"/models", :bearer}
    },
    %Spec{
      id: "ollama",
      atom: :ollama,
      adapter: Ipse.Provider.Ollama,
      replay_key: "ollama",
      default_model: "qwen3:8b",
      default_base_url: "http://127.0.0.1:11434",
      probe_base_url: "http://127.0.0.1:11434",
      base_url_policy: :https_or_loopback,
      credential: :none,
      billing_mode: "local",
      output_limit: 1..1_000_000,
      reasoning: &__MODULE__.ollama_reasoning/2,
      usage_extractor: &__MODULE__.ollama_usage/1,
      embedding: %{
        usage_extractor: &__MODULE__.ollama_embedding_usage/1,
        capacity_inputs: &__MODULE__.ollama_embedding_inputs/0
      },
      structured_output?: true,
      summary_schema?: true,
      label: "Ollama (local)",
      probe: {"/api/tags", :none}
    },
    %Spec{
      id: "anthropic",
      atom: :anthropic,
      adapter: Ipse.Provider.Anthropic,
      replay_key: "anthropic",
      default_model: "claude-sonnet-4-5",
      default_base_url: "https://api.anthropic.com",
      base_url_policy: :https_or_loopback,
      credential: {:env, "ANTHROPIC_API_KEY"},
      billing_mode: "api",
      output_limit: 1..1_000_000,
      reasoning: &__MODULE__.no_reasoning/2,
      usage_extractor: &__MODULE__.anthropic_usage/1,
      input_components: ~w(input_uncached_tokens input_cached_tokens input_cache_write_tokens),
      secret_env: ["ANTHROPIC_API_KEY"],
      label: "Anthropic API (billed)",
      probe: {"/v1/models", :anthropic}
    },
    %Spec{
      id: "gemini",
      atom: :gemini,
      adapter: Ipse.Provider.Gemini,
      replay_key: "gemini",
      default_base_url: "https://generativelanguage.googleapis.com/v1beta",
      base_url_policy: :https_or_loopback,
      wire_query: "alt=sse",
      credential: {:env, "GEMINI_API_KEY"},
      billing_mode: "api",
      output_limit: 1..1_000_000,
      reasoning: &__MODULE__.gemini_reasoning/2,
      usage_extractor: &__MODULE__.gemini_usage/1,
      secret_env: ["GEMINI_API_KEY", "GOOGLE_API_KEY"],
      label: "Gemini API (project billing; tier unknown)",
      probe: {"/models", :gemini},
      profile_validator: &Ipse.Provider.Gemini.validate_profile/1,
      request_validator: &Ipse.Provider.Gemini.validate_request/1,
      http_hints: %{
        400 =>
          "Request rejected; check model id and thinking level. Gemini requires its own signed history; start a fresh session or hand off if imported history is refused.",
        401 => "Check GEMINI_API_KEY and that the key is enabled for the Gemini API.",
        403 => "Check GEMINI_API_KEY and that the key is enabled for the Gemini API.",
        404 => "Unknown Gemini model; check the explicit model id.",
        429 => "Gemini quota or rate limit reached; check project limits and tier.",
        :server => "Gemini is unavailable; nothing was retried."
      }
    },
    %Spec{
      id: "openrouter",
      atom: :openrouter,
      adapter: Ipse.Provider.ChatCompletions,
      replay_key: "openrouter",
      default_base_url: "https://openrouter.ai/api/v1",
      base_url_policy: :https_or_loopback,
      credential: {:env, "OPENROUTER_API_KEY"},
      billing_mode: "api",
      output_limit: 1..1_000_000,
      reasoning: &__MODULE__.router_reasoning/2,
      usage_extractor: &__MODULE__.chat_usage/1,
      secret_env: ["OPENROUTER_API_KEY"],
      label: "OpenRouter API (billed, pinned upstream)",
      http_hints: %{
        401 => "Check OPENROUTER_API_KEY.",
        402 => "The OpenRouter account has insufficient credits.",
        404 => "No upstream satisfies the pinned model, upstream and data policy.",
        429 => "OpenRouter rate limited the request.",
        :server => "The pinned upstream is unavailable; nothing was retried."
      },
      probe: {"/models", :bearer},
      profile_validator: &Ipse.Provider.ChatCompletions.validate_profile/1,
      request_validator: &Ipse.Provider.ChatCompletions.validate_request/1,
      profile_fields: %{
        "upstream" => %{"type" => "string", "minLength" => 1, "maxLength" => 64},
        "data_collection" => %{"type" => "string", "enum" => ["deny", "allow"]}
      },
      profile_defaults: %{"data_collection" => "deny"},
      route_fields: [{"upstream", :upstream}, {"data_collection", :data_collection}]
    },
    %Spec{
      id: "xai",
      atom: :xai,
      adapter: Ipse.Provider.OpenAI,
      replay_key: "xai",
      default_base_url: "https://api.x.ai/v1",
      base_url_policy: :https_or_loopback,
      credential: {:env, "XAI_API_KEY"},
      billing_mode: "api",
      output_limit: 1..1_000_000,
      output_limit_scope: :visible,
      reasoning: &__MODULE__.xai_reasoning/2,
      usage_extractor: &__MODULE__.xai_usage/1,
      secret_env: ["XAI_API_KEY"],
      label: "Grok / xAI API (billed)",
      probe: {"/models", :bearer},
      http_hints: %{
        401 => "Check XAI_API_KEY; subscription credentials are a separate route.",
        403 => "Check xAI team, model and endpoint permissions; billing was not changed.",
        429 => "xAI rate or token quota reached; no fallback was attempted.",
        :server => "xAI is unavailable; nothing was retried."
      }
    },
    %Spec{
      id: "xai_oauth",
      atom: :xai_oauth,
      adapter: Ipse.Provider.OpenAI,
      replay_key: "xai",
      default_base_url: "https://api.x.ai/v1",
      base_url_policy: :fixed,
      credential: :xai_auth,
      billing_mode: "subscription",
      output_limit: 1..1_000_000,
      output_limit_scope: :visible,
      reasoning: &__MODULE__.xai_reasoning/2,
      usage_extractor: &__MODULE__.xai_usage/1,
      label: "Grok / xAI subscription (registered Ipse client required)",
      probe: :subscription,
      http_hints: %{
        401 => "Check xAI subscription sign-in; no API-key fallback was attempted.",
        403 =>
          "xAI refused client or subscription entitlement; successful browser login does not prove model access.",
        429 => "xAI subscription or model limit reached; no API-key fallback was attempted.",
        :server => "xAI is unavailable; nothing was retried."
      }
    },
    %Spec{
      id: "openai_compatible",
      atom: :openai_compatible,
      adapter: Ipse.Provider.ChatCompletions,
      replay_key: "openai_compatible",
      base_url_policy: :loopback_only,
      credential: :none,
      billing_mode: "local",
      output_limit: 1..1_000_000,
      reasoning: &__MODULE__.no_reasoning/2,
      usage_extractor: &__MODULE__.chat_usage/1,
      label: "Compatible server (local, loopback only)",
      probe: {"/models", :none},
      profile_validator: &Ipse.Provider.ChatCompletions.validate_profile/1,
      request_validator: &Ipse.Provider.ChatCompletions.validate_request/1
    },
    %Spec{
      id: "demo",
      atom: :demo,
      adapter: Ipse.Provider.Demo,
      replay_key: "demo",
      default_model: "scripted",
      base_url_policy: :https_or_loopback,
      credential: :none,
      billing_mode: "none",
      output_limit: :refuse_cap,
      reasoning: &__MODULE__.no_reasoning/2,
      label: "Demo (no model service)",
      probe: :demo
    }
  ]
  @by_id Map.new(@specs, &{&1.id, &1})
  @by_atom Map.new(@specs, &{&1.atom, &1})

  def fetch(value) when is_atom(value), do: Map.fetch(@by_atom, value)
  def fetch(value) when is_binary(value), do: Map.fetch(@by_id, value)
  def fetch(_), do: :error

  def fetch!(value) do
    case fetch(value) do
      {:ok, spec} -> spec
      :error -> raise ArgumentError, "Unknown provider"
    end
  end

  def ids, do: Enum.map(@specs, & &1.id)
  def default_id, do: "chatgpt"
  def chat_ids, do: for(spec <- @specs, spec.billing_mode != "none", do: spec.id)
  def embedding_ids, do: for(spec <- @specs, not is_nil(spec.embedding), do: spec.id)
  def atoms, do: Map.new(@specs, &{&1.id, &1.atom})
  def defaults, do: Map.new(@specs, &{&1.id, {&1.atom, &1.default_model}})
  def credentials, do: Map.new(@specs, &{&1.id, credential_reference(&1.credential)})
  def billing, do: Map.new(@specs, &{&1.atom, &1.billing_mode})
  # Rate-card enums preserve their historical presentation order.
  def rate_card_ids,
    do: ~w(openai chatgpt anthropic ollama gemini openrouter openai_compatible xai xai_oauth)

  def billing_modes, do: rate_card_ids() |> Enum.map(&fetch!(&1).billing_mode) |> Enum.uniq()
  def cost_bases, do: billing_modes() |> Enum.map(&cost_basis/1)
  def cost_basis("api"), do: "api_estimate"
  def cost_basis("subscription"), do: "api_equivalent"
  def cost_basis("local"), do: "local_estimate"
  def cost_basis(_), do: nil

  def secret_env do
    @specs
    |> Enum.sort_by(&if(&1.credential == :chatgpt_auth, do: 1, else: 0))
    |> Enum.flat_map(& &1.secret_env)
    |> Kernel.++(["TYPESAFE_API_KEY"])
    |> Enum.uniq()
  end

  def credential_reference(:chatgpt_auth), do: "ipse-auth"
  def credential_reference(:xai_auth), do: "ipse-xai-auth"
  def credential_reference({:env, name}), do: name
  def credential_reference(:none), do: "none"

  def http_hint(provider, status) do
    case fetch(provider) do
      {:ok, spec} ->
        Map.get(spec.http_hints, status) ||
          if(status in 500..599, do: Map.get(spec.http_hints, :server))

      _ ->
        nil
    end
  end

  def profile_schema do
    Enum.reduce(@specs, %{}, &Map.merge(&2, &1.profile_fields))
  end

  def profile_keys(provider) do
    case fetch(provider) do
      {:ok, spec} -> Enum.map(spec.route_fields, &elem(&1, 0))
      _ -> []
    end
  end

  def profile_values(profile) do
    spec = fetch!(profile["provider"])
    Map.merge(spec.profile_defaults, Map.take(profile, profile_keys(spec.id)))
  end

  def profile_runtime(profile) do
    values = profile_values(profile)
    Map.new(fetch!(profile["provider"]).route_fields, fn {key, atom} -> {atom, values[key]} end)
  end

  def runtime_fields(nil), do: %{}

  def runtime_fields(execution) do
    spec = fetch!(execution[:provider] || execution["provider"])

    Map.new(spec.route_fields, fn {key, atom} ->
      {atom, Map.get(execution, atom, execution[key])}
    end)
  end

  def validate_profile(profile) do
    spec = fetch!(profile["provider"])
    invalid = Map.keys(profile_schema()) -- Map.keys(spec.profile_fields)

    cond do
      Enum.any?(invalid, &Map.has_key?(profile, &1)) ->
        {:error, "Provider profile contains unsupported route fields."}

      spec.profile_validator ->
        spec.profile_validator.(profile)

      true ->
        :ok
    end
  end

  def validate_selection(settings, profile, opts) do
    case fetch(settings["provider"]) do
      {:ok, %{profile_validator: validator}} when not is_nil(validator) ->
        profile =
          profile
          |> Map.merge(Map.take(settings, ~w(provider model)))
          |> Map.put("base_url", profile["base_url"] || opts[:base_url])

        validator.(profile)

      _ ->
        :ok
    end
  end

  def validate_request(config) do
    case fetch(config[:provider]) do
      {:ok, %{request_validator: validator}} when not is_nil(validator) -> validator.(config)
      _ -> :ok
    end
  end

  def valid_profile_values?(profile) do
    spec = fetch!(profile["provider"])

    Ipse.JSON.validate_arguments(
      %{
        "type" => "object",
        "properties" => spec.profile_fields,
        "required" => profile_keys(spec.id),
        "additionalProperties" => false
      },
      Map.take(profile, profile_keys(spec.id))
    ) == :ok and (is_nil(spec.profile_validator) or spec.profile_validator.(profile) == :ok)
  end

  def router_reasoning(_, effort) when effort in ~w(none low medium high xhigh max), do: :ok
  def router_reasoning(_, _), do: unsupported_reasoning()

  def gemini_reasoning(_, effort) when effort in ~w(none low medium high), do: :ok

  def gemini_reasoning(_, _),
    do: {:error, "Gemini supports low, medium or high reasoning; none omits the control."}

  def xai_reasoning(model, effort)
      when model in ~w(grok-4.7 grok-4.6) and effort in ~w(low medium high xhigh),
      do: :ok

  def xai_reasoning("grok-4.5", effort) when effort in ~w(low medium high), do: :ok
  def xai_reasoning(_, _), do: unsupported_reasoning()

  def xai_usage(raw) do
    legacy? =
      Enum.any?(
        ~w(prompt_tokens completion_tokens prompt_tokens_details completion_tokens_details),
        &Map.has_key?(raw, &1)
      )

    modern? =
      Enum.any?(
        ~w(input_tokens output_tokens input_tokens_details output_tokens_details),
        &Map.has_key?(raw, &1)
      )

    cond do
      legacy? and modern? ->
        :error

      legacy? ->
        extract(Map.put(raw, "ipse_output_tokens", xai_legacy_output(raw)), %{
          "input_tokens" => ["prompt_tokens"],
          "output_tokens" => ["ipse_output_tokens"],
          "total_tokens" => ["total_tokens"],
          "input_cached_tokens" => ["prompt_tokens_details", "cached_tokens"],
          "output_reasoning_tokens" => ["completion_tokens_details", "reasoning_tokens"]
        })

      true ->
        responses_usage(raw)
    end
  end

  defp xai_legacy_output(raw) do
    input = raw["prompt_tokens"]
    visible = raw["completion_tokens"]
    reasoning = get_in(raw, ["completion_tokens_details", "reasoning_tokens"])
    total = raw["total_tokens"]

    cond do
      Enum.any?(
        [input, visible, reasoning, total],
        &(not is_nil(&1) and not Ipse.JSON.safe_uint?(&1))
      ) ->
        :invalid

      is_nil(visible) ->
        nil

      is_integer(input) and is_integer(total) ->
        cond do
          total == input + visible and (is_nil(reasoning) or reasoning <= visible) -> visible
          is_integer(reasoning) and total == input + visible + reasoning -> visible + reasoning
          true -> :invalid
        end

      reasoning == 0 ->
        visible

      true ->
        nil
    end
  end

  def gemini_usage(raw),
    do:
      extract(raw, %{
        "input_tokens" => {:sum, [["promptTokenCount"], ["toolUsePromptTokenCount"]]},
        "output_tokens" => {:sum, [["candidatesTokenCount"], ["thoughtsTokenCount"]]},
        "input_cached_tokens" => ["cachedContentTokenCount"],
        "output_reasoning_tokens" => ["thoughtsTokenCount"],
        "total_tokens" => ["totalTokenCount"]
      })

  def chat_usage(raw),
    do:
      extract(raw, %{
        "input_tokens" => ["prompt_tokens"],
        "output_tokens" => ["completion_tokens"],
        "total_tokens" => ["total_tokens"],
        "input_cached_tokens" => ["prompt_tokens_details", "cached_tokens"],
        "input_cache_write_tokens" => ["prompt_tokens_details", "cache_write_tokens"],
        "output_reasoning_tokens" => ["completion_tokens_details", "reasoning_tokens"]
      })

  def openai_embedding_usage(raw),
    do: extract(raw, %{"input_tokens" => ["prompt_tokens"], "total_tokens" => ["total_tokens"]})

  def ollama_embedding_usage(raw),
    do:
      extract(raw, %{
        "input_tokens" => ["prompt_eval_count"],
        "provider_duration_ns" => ["total_duration"]
      })

  def openai_embedding_inputs,
    do: [%{"prompt_tokens" => Ipse.Usage.counter_limit()}, %{"prompt_tokens" => "invalid"}]

  def ollama_embedding_inputs,
    do: [
      %{
        "prompt_eval_count" => Ipse.Usage.counter_limit(),
        "total_duration" => Ipse.Usage.counter_limit()
      },
      %{"prompt_eval_count" => "invalid"}
    ]

  def supports?(provider, field) do
    case fetch(provider) do
      {:ok, spec} -> Map.get(spec, field) == true
      :error -> false
    end
  end

  def embedding?(provider),
    do: match?({:ok, %Spec{embedding: value}} when not is_nil(value), fetch(provider))

  def auth?(provider),
    do:
      match?(
        {:ok, %Spec{credential: credential}} when credential in [:chatgpt_auth, :xai_auth],
        fetch(provider)
      )

  def reasoning(_, _, nil), do: :ok

  def reasoning(provider, model, effort) do
    case fetch(provider) do
      {:ok, spec} -> spec.reasoning.(model, effort)
      _ -> unsupported_reasoning()
    end
  end

  def responses_reasoning("gpt-6.1-sol", effort) when effort in ~w(low medium high xhigh max),
    do: :ok

  def responses_reasoning(_, _), do: unsupported_reasoning()
  def ollama_reasoning(_, "none"), do: :ok
  def ollama_reasoning(_, _), do: unsupported_reasoning()
  def no_reasoning(_, _), do: unsupported_reasoning()

  defp unsupported_reasoning,
    do: {:error, "Unsupported reasoning setting for the selected provider/model profile."}

  def responses_usage(raw),
    do:
      extract(raw, %{
        "input_tokens" => ["input_tokens"],
        "output_tokens" => ["output_tokens"],
        "total_tokens" => ["total_tokens"],
        "input_cached_tokens" => ["input_tokens_details", "cached_tokens"],
        "input_cache_write_tokens" => ["input_tokens_details", "cache_write_tokens"],
        "output_reasoning_tokens" => ["output_tokens_details", "reasoning_tokens"]
      })

  def anthropic_usage(raw),
    do:
      extract(raw, %{
        "input_uncached_tokens" => ["input_tokens"],
        "output_tokens" => ["output_tokens"],
        "input_cached_tokens" => ["cache_read_input_tokens"],
        "input_cache_write_tokens" => ["cache_creation_input_tokens"],
        "input_cache_write_5m_tokens" => ["cache_creation", "ephemeral_5m_input_tokens"],
        "input_cache_write_1h_tokens" => ["cache_creation", "ephemeral_1h_input_tokens"],
        "output_reasoning_tokens" => ["output_tokens_details", "thinking_tokens"],
        "provider_web_search_requests" => ["server_tool_use", "web_search_requests"],
        "provider_web_fetch_requests" => ["server_tool_use", "web_fetch_requests"]
      })

  def ollama_usage(raw),
    do:
      extract(
        raw,
        Map.new(
          ~w(input_tokens output_tokens input_cached_tokens provider_duration_ns),
          &{&1, [&1]}
        )
      )

  defp extract(raw, paths) do
    empty = Map.new(Ipse.Usage.counter_fields(), &{&1, nil})
    limit = Ipse.Usage.counter_limit()

    Enum.reduce_while(paths, {:ok, empty}, fn {field, path}, {:ok, counts} ->
      case read(raw, path) do
        nil ->
          {:cont, {:ok, counts}}

        n when is_integer(n) and n >= 0 and n <= limit ->
          {:cont, {:ok, Map.put(counts, field, n)}}

        _ ->
          {:halt, :error}
      end
    end)
  end

  defp read(value, {:sum, paths}) do
    values = Enum.map(paths, &read(value, &1))

    cond do
      Enum.any?(
        values,
        &(not is_nil(&1) and not (is_integer(&1) and &1 >= 0 and &1 <= Ipse.Usage.counter_limit()))
      ) ->
        :invalid

      Enum.any?(values, &is_nil/1) ->
        nil

      true ->
        Enum.sum(values)
    end
  end

  defp read(value, []), do: value
  defp read(nil, _), do: nil
  defp read(value, [key | rest]) when is_map(value), do: read(value[key], rest)
  defp read(_, _), do: :invalid

  def chatgpt_hint(code, _status, _shape) when is_binary(code) and is_map_key(@codes, code),
    do: Map.fetch!(@codes, code)

  def chatgpt_hint(_code, status, "detail") when status == 403,
    do:
      "Direct-route admission was denied. Check account, scopes, policy, or serving region; billing was not changed."

  def chatgpt_hint(_code, status, _shape) when status == 503,
    do:
      "ChatGPT plan routing or usage availability is temporarily unavailable. Preserve sign-in and try again later."

  def chatgpt_hint(_code, status, _shape) when status == 403,
    do:
      "A ChatGPT policy or permission check denied the request. Check account, scopes, and serving-region eligibility."

  def chatgpt_hint(_code, status, _shape) when status == 400,
    do:
      "ChatGPT rejected the request. Check supported inputs, tools, model, and service-tier settings."

  def chatgpt_hint(_code, status, _shape) when status == 429,
    do: "ChatGPT plan usage is limited. Pause plan requests and check ChatGPT Settings > Usage."

  def chatgpt_hint(_code, status, _shape) when status == 401,
    do:
      "The ChatGPT subscriber context was not accepted. Check the selected account and granted scopes."

  def chatgpt_hint(_code, _status, _shape),
    do:
      "Check ChatGPT plan access, account limits, and request settings. No billing path was changed."
end
