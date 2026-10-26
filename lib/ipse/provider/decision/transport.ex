defmodule Ipse.Provider.Decision.Transport do
  @moduledoc "Explicit bounded decision HTTP transport; callers own permission, reservation and journaling."
  alias Ipse.Provider.Decision
  @limit 65_536
  @error {:error, :decision_request_failed}
  @providers [:openai, :system_one, :system_one_compatible]

  def engine(:openai), do: :openai
  def engine(provider) when provider in [:system_one, :system_one_compatible], do: :system_one
  def engine(_), do: nil

  def endpoint(config) do
    provider = config[:provider]
    base = config[:base_url] || default_base(provider)

    if provider in @providers and valid_base?(provider, base),
      do:
        String.trim_trailing(base, "/") <>
          if(provider == :openai, do: "/decisions", else: "/systemone"),
      else: raise(ArgumentError, "Invalid selected decision endpoint.")
  end

  def default_base(:openai), do: "https://api.openai.com/v1"
  def default_base(:system_one), do: "https://api.typesafe.ai/v1"
  def default_base(_), do: nil

  def valid_base?(provider, base) do
    provider in @providers and is_binary(base) and
      Ipse.Provider.valid_base_url?(:openai, base) and
      (provider != :system_one_compatible or
         URI.parse(base).host in ["127.0.0.1", "localhost", "::1"])
  rescue
    _ -> false
  end

  def destination(config) do
    target = endpoint(config)
    uri = URI.parse(target)

    facts = %{
      "origin" => URI.to_string(%URI{scheme: uri.scheme, host: uri.host, port: uri.port}),
      "target_sha256" => Ipse.JSON.sha256(target)
    }

    if Ipse.Provider.valid_destination?(facts), do: {:ok, facts}, else: @error
  rescue
    _ -> @error
  end

  def request(config, request, emit) when is_function(emit, 1) do
    with {:ok, body} <- Decision.encode(engine(config[:provider]), request, config[:model]),
         true <- model?(config[:expected_model] || config[:model]),
         true <-
           config[:provider] != :openai or
             (config[:expected_model] || config[:model]) == config[:model],
         {:ok, _} <- destination(config),
         timeout = config[:timeout_ms] || 120_000,
         true <- is_integer(timeout) and timeout in 1..120_000,
         {:ok, headers} <- headers(config),
         wire = Finch.build(:post, endpoint(config), headers, Jason.encode!(body)),
         {:ok, status, bytes} <- Ipse.HTTP.bounded_request(wire, @limit, timeout),
         true <- status in 200..299 do
      parse(config, request, bytes)
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  def request(_, _, _), do: @error

  def parse(config, request, bytes) do
    with true <- is_binary(bytes) and byte_size(bytes) <= @limit,
         {:ok, native} <- Ipse.JSON.decode_unique(bytes),
         {:ok, result, facts} <-
           Decision.decode(
             engine(config[:provider]),
             request,
             config[:expected_model] || config[:model],
             native
           ),
         usage = Ipse.Usage.normalize(config[:provider], :decision, facts["usage"]),
         true <- usage["quality"] == "totals_known" do
      {:ok,
       %{
         "kind" => "decision",
         "version" => 1,
         "result" => result,
         "reported_model" => facts["model"],
         "subset" => facts["subset"],
         "provider_response_sha256" => Ipse.JSON.sha256(bytes)
       }, facts["usage"]}
    else
      _ -> {:error, :invalid_decision_response}
    end
  rescue
    _ -> {:error, :invalid_decision_response}
  end

  def valid_result?(payload, execution, request) do
    keys?(payload, ~w(kind version result reported_model subset provider_response_sha256)) and
      payload["kind"] == "decision" and payload["version"] === 1 and
      payload["reported_model"] == execution["expected_model"] and
      payload["subset"] == execution["subset"] and
      Ipse.JSON.sha256?(payload["provider_response_sha256"]) and
      Ipse.Decision.validate_result(request, payload["result"]) == :ok
  rescue
    _ -> false
  end

  defp headers(%{provider: :system_one_compatible}), do: {:ok, json_headers()}

  defp headers(config) do
    variable = if config[:provider] == :openai, do: "OPENAI_API_KEY", else: "TYPESAFE_API_KEY"
    key = config[:api_key] || System.get_env(variable)

    if is_binary(key) and byte_size(key) in 1..16_384 and String.valid?(key) and
         not Regex.match?(~r/[\x00-\x20\x7f]/, key),
       do: {:ok, [{"authorization", "Bearer " <> key} | json_headers()]},
       else: @error
  end

  defp json_headers,
    do: [
      {"content-type", "application/json"},
      {"accept", "application/json"},
      {"accept-encoding", "identity"}
    ]

  defp model?(model), do: is_binary(model) and Ipse.Provider.model_name(model) == model
  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
end
