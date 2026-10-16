defmodule Ipse.Extension do
  @moduledoc "Version-one worker SDK. Only bounded JSON objects cross the host boundary."
  @type value :: nil | boolean() | number() | String.t() | [value()] | %{String.t() => value()}
  @type object :: %{String.t() => value()}
  @callback describe() :: object()
  @callback init(object()) :: {:ok, term()}
  @callback handle(String.t(), object(), term()) :: {:ok, object(), term()}

  @doc "Reject private runtime terms and independently bound each SDK object."
  def validate(object) do
    Ipse.MCP.Schema.validate_arguments(%{"type" => "object"}, object)
  end
end
