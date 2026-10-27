defmodule Ipse.Provider.MintDecision do
  @moduledoc false
  alias Ipse.Provider.{Decision, MintBuffered}
  alias Ipse.Provider.Decision.Transport

  # Only the existing explicitly selected local compatible route is supported.
  # Policy and current Session authority remain the caller's responsibility.
  def request(%{provider: :system_one_compatible} = runtime, request, admit)
      when is_function(admit, 2) do
    with {:ok, payload} <- Decision.encode(:system_one, request, runtime[:model]),
         expected when is_binary(expected) <- runtime[:expected_model] || runtime[:model],
         true <- Ipse.Provider.model_name(expected) == expected,
         {:ok, _} <- Transport.destination(runtime),
         timeout when is_integer(timeout) and timeout in 1..120_000 <-
           runtime[:timeout_ms] || 120_000,
         {:ok, body} <- Jason.encode(payload) do
      MintBuffered.run(
        runtime,
        :decision,
        Transport.endpoint(runtime),
        body,
        timeout,
        65_536,
        admit,
        fn bytes -> Transport.parse(runtime, request, bytes) end
      )
    else
      _ -> {:unstarted, :invalid_inference_request}
    end
  rescue
    _ -> {:unknown, :inference_completion_unconfirmed}
  catch
    _, _ -> {:unknown, :inference_completion_unconfirmed}
  end

  def request(_, _, _), do: {:unstarted, :invalid_inference_request}
end
