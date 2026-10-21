defmodule Ipse.Builtins.AnswerFormat do
  @moduledoc "Opt-in completed presentation wrapper; provider messages remain unchanged."
  @behaviour Ipse.Extension
  @impl true
  def describe, do: %{"sdk" => 1, "capabilities" => ["transform.presentation"]}
  @impl true
  def init(options), do: {:ok, options}
  @impl true
  def handle("transform.presentation", _payload, options),
    do: {:ok, Map.take(options, ["prefix", "suffix"]), options}
end
