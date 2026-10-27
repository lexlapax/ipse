defmodule Ipse.Provider.MintEmbedding do
  @moduledoc false

  alias Ipse.Provider.{Embedding, MintOwned}

  @limit 2_097_152
  @headers [
    {"content-type", "application/json"},
    {"accept", "application/json"},
    {"accept-encoding", "identity"}
  ]

  # Experimental host-only seam. The runtime and inputs must originate from the
  # admitted host selection. Admission must hold current authority through send;
  # this module does not implement that barrier and is not wired to Session.
  # Response bytes stay in the owned child until parsing and cleanup settle.
  def embed(%{provider: :ollama} = runtime, inputs, admit) when is_function(admit, 2) do
    with {:ok, request} <- Embedding.request_body(runtime, inputs),
         {:ok, _} <- Embedding.destination(runtime),
         timeout when is_integer(timeout) and timeout in 1..120_000 <-
           runtime[:timeout_ms] || 120_000,
         {:ok, body} <- Jason.encode(request) do
      target = Embedding.endpoint(runtime)

      facts = %{
        "kind" => "embedding",
        "provider" => "ollama",
        "model" => runtime.model,
        "target_sha256" => Ipse.JSON.sha256(target),
        "body_sha256" => Ipse.JSON.sha256(body)
      }

      MintOwned.run(
        runtime,
        :embedding,
        target,
        @headers,
        body,
        timeout,
        @limit,
        [],
        &buffer/2,
        fn send -> admit.(facts, send) end,
        fn chunks ->
          Embedding.parse(:ollama, IO.iodata_to_binary(Enum.reverse(chunks)), runtime, inputs)
        end
      )
    else
      _ -> {:unstarted, :invalid_inference_request}
    end
  rescue
    _ -> {:unknown, :inference_completion_unconfirmed}
  catch
    _, _ -> {:unknown, :inference_completion_unconfirmed}
  end

  def embed(_, _, _), do: {:unstarted, :invalid_inference_request}

  defp buffer({:data, _, bytes}, chunks), do: {:cont, [bytes | chunks]}
  defp buffer(_, chunks), do: {:cont, chunks}
end
