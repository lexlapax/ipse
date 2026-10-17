defmodule Ipse.Extensions.Operation do
  @moduledoc "Closed host-operation contracts; proposals are not permission grants."
  alias Ipse.Extensions.State

  def validate(%{"op" => "operator.question"} = request) do
    with true <- Enum.sort(Map.keys(request)) == ~w(arguments checkpoint op),
         :ok <- Ipse.Extension.validate(request),
         {:ok, _} <- Ipse.Questions.validate(request["arguments"]),
         true <- is_map(request["checkpoint"]),
         true <- byte_size(Jason.encode!(request["checkpoint"])) <= 8192 do
      :ok
    else
      _ -> {:error, :invalid_extension_question}
    end
  rescue
    _ -> {:error, :invalid_extension_question}
  end

  def validate(request), do: State.validate(request)
  def question?(request), do: is_map(request) and request["op"] == "operator.question"
  def capability(%{"op" => "operator.question"}), do: "host.question"
  def capability(request), do: State.capability(request)
  def mutating?(request), do: State.mutating?(request)

  def namespace(_identity, %{"op" => "operator.question"}, _cwd, _id), do: {:ok, nil}

  def namespace(identity, request, cwd, id),
    do: State.namespace(identity, request["scope"], cwd, id)

  def valid_outcome?(%{"op" => "operator.question"} = request, "answered", value, _) do
    Enum.sort(Map.keys(value)) == ["answers"] and
      match?({:ok, _}, Ipse.Questions.validate_answers(request["arguments"], value["answers"]))
  rescue
    _ -> false
  end

  def valid_outcome?(%{"op" => "operator.question"}, status, value, _)
      when status in ~w(cancelled unknown) do
    value == %{}
  end

  def valid_outcome?(%{"op" => "operator.question"}, _, _, _), do: false

  def valid_outcome?(request, status, value, id),
    do: State.valid_outcome?(request, status, value, id)
end
