defmodule Ipse.Provider.InferenceFacts do
  @moduledoc false

  # Experimental consistency facts. Equality neither authenticates their caller
  # nor establishes current permission, source eligibility or cleanup.
  def make(phase, kind, runtime, target, body) do
    with true <- is_map(runtime) and is_binary(target) and is_binary(body),
         true <-
           is_binary(runtime[:model]) and
             Ipse.Provider.model_name(runtime[:model]) == runtime[:model],
         true <- byte_size(body) <= 8_388_608,
         {:ok, execution} <- execution(phase, kind, runtime) do
      {:ok,
       Map.merge(execution, %{
         "kind" => Atom.to_string(kind),
         "provider" => Atom.to_string(runtime.provider),
         "model" => runtime.model,
         "target_sha256" => Ipse.JSON.sha256(target),
         "body_sha256" => Ipse.JSON.sha256(body)
       })}
    else
      _ -> {:error, :inference_wire_refused}
    end
  rescue
    _ -> {:error, :inference_wire_refused}
  end

  def valid?(facts) when is_map(facts) do
    keys =
      ~w(body_sha256 dimension_mode dimensions expected_model kind model phase provider response_limit target_sha256 timeout_ms)

    with true <- Enum.sort(Map.keys(facts)) == keys,
         true <-
           is_binary(facts["model"]) and
             Ipse.Provider.model_name(facts["model"]) == facts["model"],
         true <-
           Ipse.JSON.sha256?(facts["body_sha256"]) and Ipse.JSON.sha256?(facts["target_sha256"]),
         {:ok, kind, runtime} <- facts_runtime(facts),
         {:ok, execution} <- execution(facts["phase"], kind, runtime) do
      Map.take(facts, Map.keys(execution)) === execution
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def valid?(_), do: false

  defp facts_runtime(%{"kind" => "text", "provider" => "ollama"} = f),
    do:
      {:ok, :text,
       %{provider: :ollama, timeout_ms: f["timeout_ms"], max_response_bytes: f["response_limit"]}}

  defp facts_runtime(%{"kind" => "embedding", "provider" => "ollama"} = f),
    do:
      {:ok, :embedding,
       %{
         provider: :ollama,
         timeout_ms: f["timeout_ms"],
         dimensions: f["dimensions"],
         dimension_mode: f["dimension_mode"]
       }}

  defp facts_runtime(%{"kind" => "decision", "provider" => "system_one_compatible"} = f),
    do:
      {:ok, :decision,
       %{
         provider: :system_one_compatible,
         timeout_ms: f["timeout_ms"],
         model: f["model"],
         expected_model: f["expected_model"]
       }}

  defp facts_runtime(_), do: :error

  defp execution(phase, :text, %{provider: :ollama} = runtime)
       when phase in ["model", "compaction", "model.complete"] do
    timeout = runtime[:timeout_ms] || 120_000
    limit = runtime[:max_response_bytes] || 8_388_608

    if timeout in 1..120_000 and is_integer(timeout) and is_integer(limit) and
         limit in 1..8_388_608,
       do: {:ok, fields(phase, timeout, limit, nil, nil, nil)},
       else: :error
  end

  defp execution("embedding.create", :embedding, %{provider: :ollama} = runtime) do
    timeout = runtime[:timeout_ms] || 120_000
    dims = runtime[:dimensions]
    mode = runtime[:dimension_mode]

    if is_integer(timeout) and timeout in 1..120_000 and is_integer(dims) and dims in 1..4096 and
         mode in ~w(native request),
       do: {:ok, fields("embedding.create", timeout, 2_097_152, dims, mode, nil)},
       else: :error
  end

  defp execution("decision.create", :decision, %{provider: :system_one_compatible} = runtime) do
    timeout = runtime[:timeout_ms] || 120_000
    expected = runtime[:expected_model] || runtime[:model]

    if is_integer(timeout) and timeout in 1..120_000 and is_binary(expected) and
         Ipse.Provider.model_name(expected) == expected,
       do: {:ok, fields("decision.create", timeout, 65_536, nil, nil, expected)},
       else: :error
  end

  defp execution(_, _, _), do: :error

  defp fields(phase, timeout, limit, dimensions, mode, expected) do
    %{
      "phase" => phase,
      "timeout_ms" => timeout,
      "response_limit" => limit,
      "dimensions" => dimensions,
      "dimension_mode" => mode,
      "expected_model" => expected
    }
  end
end
