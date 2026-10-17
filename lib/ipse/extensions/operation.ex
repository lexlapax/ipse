defmodule Ipse.Extensions.Operation do
  @moduledoc "Closed host-operation contracts; proposals are not permission grants."
  alias Ipse.Extensions.State

  def validate(%{"op" => "history.read"} = request), do: Ipse.Extensions.History.validate(request)
  def validate(%{"op" => "usage.read"} = request), do: Ipse.Extensions.UsageRead.validate(request)

  def validate(%{"op" => "context.publish"} = request),
    do: Ipse.Extensions.Contributions.validate(request)

  def validate(%{"op" => "service.call"} = request),
    do: Ipse.Extensions.Services.validate_request(request)

  def validate(%{"op" => "tool.call"} = request), do: Ipse.Extensions.ToolAction.validate(request)

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
  def tool?(request), do: is_map(request) and request["op"] == "tool.call"
  def service?(request), do: is_map(request) and request["op"] == "service.call"
  def history?(request), do: Ipse.Extensions.History.operation?(request)
  def usage?(request), do: Ipse.Extensions.UsageRead.operation?(request)

  def capability(%{"op" => "history.read"} = request),
    do: Ipse.Extensions.History.capability(request)

  def capability(%{"op" => "context.publish"}), do: "host.context"
  def capability(%{"op" => "usage.read"}), do: "host.usage"
  def capability(%{"op" => "service.call"}), do: "host.services"
  def capability(%{"op" => "tool.call"}), do: "host.tools"
  def capability(%{"op" => "operator.question"}), do: "host.question"
  def capability(request), do: State.capability(request)
  def mutating?(%{"op" => "tool.call", "name" => name}), do: Ipse.Tools.mutating?(name)
  def mutating?(request), do: State.mutating?(request)

  def namespace(_identity, %{"op" => "operator.question"}, _cwd, _id), do: {:ok, nil}
  def namespace(_identity, %{"op" => "tool.call"}, _cwd, _id), do: {:ok, nil}
  def namespace(_identity, %{"op" => "service.call"}, _cwd, _id), do: {:ok, nil}
  def namespace(_identity, %{"op" => "context.publish"}, _cwd, _id), do: {:ok, nil}
  def namespace(_identity, %{"op" => "history.read"}, _cwd, id), do: {:ok, id}
  def namespace(_identity, %{"op" => "usage.read"}, _cwd, id), do: {:ok, id}

  def namespace(identity, request, cwd, id),
    do: State.namespace(identity, request["scope"], cwd, id)

  def valid_outcome?(%{"op" => "service.call"}, status, value, id, service),
    do: Ipse.Extensions.Services.valid_outcome?(service, status, value, id)

  def valid_outcome?(request, status, value, id, _service),
    do: valid_outcome?(request, status, value, id)

  def valid_outcome?(%{"op" => "tool.call"} = request, status, value, _),
    do: Ipse.Extensions.ToolAction.valid_outcome?(request, status, value)

  def valid_outcome?(%{"op" => "history.read"} = request, status, value, id),
    do: Ipse.Extensions.History.valid_outcome?(request, status, value, id)

  def valid_outcome?(%{"op" => "usage.read"} = request, status, value, id),
    do: Ipse.Extensions.UsageRead.valid_outcome?(request, status, value, id)

  def valid_outcome?(%{"op" => "context.publish"} = request, status, value, id),
    do: Ipse.Extensions.Contributions.valid_outcome?(request, status, value, id)

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
