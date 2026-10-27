defmodule Ipse.Provider.MintBuffered do
  @moduledoc false
  alias Ipse.Provider.MintOwned

  # Internal transport helper; callers must derive target and body themselves.
  # The admission callback is trusted host code, not an authority grant.
  def run(runtime, kind, target, body, timeout, limit, admit, finish) do
    facts = %{
      "kind" => Atom.to_string(kind),
      "provider" => Atom.to_string(runtime.provider),
      "model" => runtime.model,
      "target_sha256" => Ipse.JSON.sha256(target),
      "body_sha256" => Ipse.JSON.sha256(body)
    }

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
  end

  defp buffer({:data, _, bytes}, chunks), do: {:cont, [bytes | chunks]}
  defp buffer(_, chunks), do: {:cont, chunks}
end
