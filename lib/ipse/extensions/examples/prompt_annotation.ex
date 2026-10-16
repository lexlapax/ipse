defmodule Ipse.Extensions.Examples.PromptAnnotation do
  @moduledoc "Opt-in attributed prompt context; no external effects."
  @behaviour Ipse.Extension
  @impl true
  def describe, do: %{"sdk" => 1, "capabilities" => ["transform.prompt"]}
  @impl true
  def init(options), do: {:ok, options}
  @impl true
  def handle("transform.prompt", _payload, options),
    do: {:ok, %{"append" => options["text"]}, options}
end
