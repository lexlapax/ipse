defmodule IpseLab.Lookup do
  @behaviour Ipse.Extension
  @description IpseLab.Spec.description(:lookup)
  def describe, do: @description
  def init(options), do: {:ok, options}

  def handle("invoke.service", _payload, options) do
    if options["fail"], do: raise("Synthetic lookup refusal")

    {:ok, %{"api_version" => 1, "kind" => "result", "value" => Map.take(options, ~w(text uri))},
     options}
  end
end
