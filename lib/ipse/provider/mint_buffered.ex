defmodule Ipse.Provider.MintBuffered do
  @moduledoc false
  alias Ipse.Provider.MintOwned

  # Internal transport helper; callers must derive target and body themselves.
  # The admission callback is trusted host code, not an authority grant.
  def run(phase, runtime, kind, target, body, timeout, limit, admit, finish) do
    with {:ok, facts} <- Ipse.Provider.InferenceFacts.make(phase, kind, runtime, target, body),
         true <- facts["timeout_ms"] == timeout and facts["response_limit"] == limit do
      MintOwned.run(
        runtime,
        kind,
        target,
        [
          {"content-type", "application/json"},
          {"accept", "application/json"},
          {"accept-encoding", "identity"}
        ],
        body,
        timeout,
        limit,
        [],
        &buffer/2,
        fn send -> admit.(facts, send) end,
        fn chunks -> finish.(chunks |> Enum.reverse() |> IO.iodata_to_binary()) end
      )
    else
      _ -> {:unstarted, :invalid_inference_request}
    end
  end

  defp buffer({:data, _, bytes}, chunks), do: {:cont, [bytes | chunks]}
  defp buffer(_, chunks), do: {:cont, chunks}
end
