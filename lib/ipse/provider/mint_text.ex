defmodule Ipse.Provider.MintText do
  @moduledoc false
  alias Ipse.Provider.{MintBuffered, Ollama}

  # No credentials are discarded: credential-bearing Ollama routes remain
  # unsupported here. This seam does not implement Session admission.
  def complete(phase, %{provider: :ollama} = runtime, messages, tools, admit)
      when is_list(messages) and is_list(tools) and is_function(admit, 2) do
    with true <- phase in ["model", "compaction", "model.complete"],
         true <- phase == "model" or tools == [],
         true <- runtime[:api_key] in [nil, ""],
         model when is_binary(model) <- runtime[:model],
         true <- Ipse.Provider.model_name(model) == model,
         :ok <- Ipse.Provider.Registry.validate_request(runtime),
         :ok <- Ipse.Config.Profiles.reasoning("ollama", model, runtime[:reasoning_effort]),
         :ok <- Ipse.Provider.validate_output_limit(runtime),
         :ok <- Ipse.Provider.response_contract(runtime),
         timeout when is_integer(timeout) and timeout in 1..120_000 <-
           runtime[:timeout_ms] || 120_000,
         limit when is_integer(limit) and limit in 1..8_388_608 <-
           runtime[:max_response_bytes] || 8_388_608,
         target <- Ollama.endpoint(runtime),
         {:ok, body} <- Jason.encode(Ollama.request_body(runtime, messages, tools)) do
      MintBuffered.run(
        phase,
        runtime,
        :text,
        target,
        body,
        timeout,
        limit,
        admit,
        &Ollama.parse_buffered/1
      )
    else
      _ -> {:unstarted, :invalid_inference_request}
    end
  rescue
    _ -> {:unknown, :inference_completion_unconfirmed}
  catch
    _, _ -> {:unknown, :inference_completion_unconfirmed}
  end

  def complete(_, _, _, _, _), do: {:unstarted, :invalid_inference_request}
end
