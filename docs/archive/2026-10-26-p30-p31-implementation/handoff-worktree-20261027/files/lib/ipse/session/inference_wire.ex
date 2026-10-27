defmodule Ipse.Session.InferenceWire do
  @moduledoc false
  alias Ipse.Provider.{Decision, Embedding, Ollama}
  alias Ipse.Provider.Decision.Transport

  # Pure, unwired preparation from a fresh trusted Session dispatch view. A
  # digest comparison does not grant authority or fence a policy change; a
  # future caller must retain current root/consent authority through send.
  def derive(phase, runtime, input, tools)
      when phase in ["model", "compaction", "model.complete"] and is_map(runtime) and
             is_list(input) and is_list(tools) do
    with true <- runtime[:provider] == :ollama and runtime[:api_key] in [nil, ""],
         true <- valid_timeout?(runtime) and valid_text_limit?(runtime),
         true <- phase == "model" or tools == [],
         true <- valid_model?(runtime[:model]),
         :ok <- Ipse.Provider.Registry.validate_request(runtime),
         :ok <-
           Ipse.Config.Profiles.reasoning("ollama", runtime[:model], runtime[:reasoning_effort]),
         :ok <- Ipse.Provider.validate_output_limit(runtime),
         true <- valid_contract?(runtime),
         target <- Ollama.endpoint(runtime),
         {:ok, body} <- Jason.encode(Ollama.request_body(runtime, input, tools)) do
      facts(:text, runtime, target, body)
    else
      _ -> {:error, :inference_wire_refused}
    end
  rescue
    _ -> {:error, :inference_wire_refused}
  catch
    _, _ -> {:error, :inference_wire_refused}
  end

  def derive("embedding.create", %{provider: :ollama} = runtime, request, []) do
    with true <- valid_timeout?(runtime),
         :ok <- Ipse.Extension.EmbeddingCall.validate(request),
         {:ok, payload} <- Embedding.request_body(runtime, request["inputs"]),
         {:ok, _} <- Embedding.destination(runtime),
         {:ok, body} <- Jason.encode(payload) do
      facts(:embedding, runtime, Embedding.endpoint(runtime), body)
    else
      _ -> {:error, :inference_wire_refused}
    end
  rescue
    _ -> {:error, :inference_wire_refused}
  end

  def derive("decision.create", %{provider: :system_one_compatible} = runtime, request, []) do
    with true <- valid_timeout?(runtime),
         :ok <- Ipse.Extension.DecisionCall.validate(request),
         {:ok, payload} <-
           Decision.encode(
             :system_one,
             Ipse.Extension.DecisionCall.neutral(request),
             runtime[:model]
           ),
         true <- valid_model?(runtime[:expected_model] || runtime[:model]),
         {:ok, _} <- Transport.destination(runtime),
         {:ok, body} <- Jason.encode(payload) do
      facts(:decision, runtime, Transport.endpoint(runtime), body)
    else
      _ -> {:error, :inference_wire_refused}
    end
  rescue
    _ -> {:error, :inference_wire_refused}
  end

  def derive(_, _, _, _), do: {:error, :inference_wire_refused}

  def matches?(expected, actual), do: valid_facts?(expected) and expected === actual

  defp valid_facts?(value) when is_map(value) do
    Enum.sort(Map.keys(value)) == ~w(body_sha256 kind model provider target_sha256) and
      {value["kind"], value["provider"]} in [
        {"text", "ollama"},
        {"embedding", "ollama"},
        {"decision", "system_one_compatible"}
      ] and valid_model?(value["model"]) and
      Ipse.JSON.sha256?(value["body_sha256"]) and Ipse.JSON.sha256?(value["target_sha256"])
  end

  defp valid_facts?(_), do: false

  defp facts(kind, runtime, target, body) do
    if byte_size(body) <= 8_388_608 do
      {:ok,
       %{
         "kind" => Atom.to_string(kind),
         "provider" => Atom.to_string(runtime.provider),
         "model" => runtime.model,
         "target_sha256" => Ipse.JSON.sha256(target),
         "body_sha256" => Ipse.JSON.sha256(body)
       }}
    else
      {:error, :inference_wire_refused}
    end
  end

  defp valid_model?(model), do: is_binary(model) and Ipse.Provider.model_name(model) == model

  defp valid_timeout?(runtime) do
    timeout = runtime[:timeout_ms] || 120_000
    is_integer(timeout) and timeout in 1..120_000
  end

  defp valid_text_limit?(runtime) do
    limit = runtime[:max_response_bytes] || 8_388_608
    is_integer(limit) and limit in 1..8_388_608
  end

  defp valid_contract?(runtime) do
    not Map.has_key?(runtime, :extension_response_schema) or
      (is_map(runtime[:extension_response_schema]) and not Map.has_key?(runtime, :summary_schema))
  end
end
