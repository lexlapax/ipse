defmodule Ipse.Session.Invocation do
  @moduledoc "Current invocation facts; Session owns lifecycle, approval callers and publication resources."

  defstruct parent: nil,
            request: nil,
            action: nil,
            step: 0,
            effect_sources: %{},
            results: [],
            interrupted: false

  @type t :: %__MODULE__{
          parent: map() | nil,
          request: map() | nil,
          action: map() | nil,
          step: non_neg_integer(),
          effect_sources: map(),
          results: [map()],
          interrupted: boolean()
        }

  def restore(%{kind: :extension} = question, effect_sources) do
    %__MODULE__{
      parent: question.parent,
      action: %{intent: question.action},
      step: question.action["step"],
      effect_sources: effect_sources,
      results: question.results
    }
  end

  def restore(_, _), do: %__MODULE__{}
end
