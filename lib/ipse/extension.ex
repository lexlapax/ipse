defmodule Ipse.Extension do
  @moduledoc "Worker SDK. SDK-2 adds private paged results; wire objects remain bounded."
  @type value :: nil | boolean() | number() | String.t() | [value()] | %{String.t() => value()}
  @type object :: %{String.t() => value()}
  @callback describe() :: object()
  @callback init(object()) :: {:ok, term()}
  @callback handle(String.t(), object(), term()) ::
              {:ok, object() | Ipse.Extension.ResultPublication.Output.t(), term()}

  @doc "Reject private runtime terms and independently bound each SDK object."
  def validate(object) do
    case Ipse.MCP.Schema.validate_object(object) do
      :ok -> :ok
      _ -> {:error, :invalid_extension_value}
    end
  end
end
