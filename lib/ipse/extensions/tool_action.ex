defmodule Ipse.Extensions.ToolAction do
  @moduledoc "Bounded access to existing file/shell tools; authority remains in Session."
  @names ~w(read write edit shell)
  @limit 4096

  def validate(request) do
    with :ok <- Ipse.Extension.validate(request),
         true <- Enum.sort(Map.keys(request)) == ~w(arguments name op timeout_ms),
         true <- request["op"] == "tool.call" and request["name"] in @names,
         true <- is_integer(request["timeout_ms"]) and request["timeout_ms"] in 1..30_000,
         definition =
           Enum.find(
             Ipse.Tools.definitions(),
             &(get_in(&1, ["function", "name"]) == request["name"])
           ),
         :ok <-
           Ipse.MCP.Schema.validate_arguments(
             get_in(definition, ["function", "parameters"]),
             request["arguments"]
           ),
         true <-
           request["name"] != "shell" or is_nil(request["arguments"]["timeout_ms"]) or
             request["arguments"]["timeout_ms"] <= request["timeout_ms"] do
      :ok
    else
      _ -> {:error, :invalid_extension_tool_call}
    end
  rescue
    _ -> {:error, :invalid_extension_tool_call}
  end

  def execute(request, context) do
    task =
      Task.async(fn ->
        try do
          run(request, context)
        rescue
          _ -> unknown()
        catch
          _, _ -> unknown()
        end
      end)

    allowance = if request["name"] == "shell", do: setup_allowance(context), else: 0

    case Task.yield(task, request["timeout_ms"] + allowance) do
      {:ok, result} ->
        result

      _ ->
        Task.shutdown(task, :brutal_kill)
        unknown()
    end
  end

  defp setup_allowance(%{sandbox: :native}) do
    if match?({:unix, :darwin}, :os.type()), do: 25_000, else: 5_000
  end

  defp setup_allowance(_), do: 5_000

  defp run(%{"name" => "shell"} = request, context) do
    arguments = request["arguments"]

    case Ipse.Runner.run(arguments["command"], context.cwd,
           timeout_ms: arguments["timeout_ms"] || request["timeout_ms"],
           output_limit: @limit,
           sandbox: context.sandbox
         ) do
      {:ok, %{timed_out: false, output_truncated: false, exit_code: code} = result}
      when code in 0..255 ->
        complete(request, %{
          "text" => result.output,
          "exit_code" => code,
          "output_bytes" => result.output_bytes,
          "output_truncated" => false
        })

      _ ->
        unknown()
    end
  end

  defp run(request, context) do
    case {request["name"], Ipse.Tools.execute(request["name"], request["arguments"], context)} do
      {_, {:ok, text}} -> complete(request, %{"text" => text})
      {"read", {:error, _}} -> {:failed, %{"reason" => "tool_failed"}}
      _ -> unknown()
    end
  end

  defp complete(request, value) do
    if valid_outcome?(request, "ok", value) and
         Ipse.Extension.validate(%{
           "api_version" => 1,
           "invocation_id" => String.duplicate("0", 32),
           "operation_id" => String.duplicate("0", 32),
           "step" => 16,
           "outcome" => %{"status" => "ok", "value" => value}
         }) == :ok, do: {:ok, value}, else: incomplete(request)
  end

  defp incomplete(%{"name" => "read"}), do: {:failed, %{"reason" => "result_limit"}}
  defp incomplete(_), do: unknown()

  def valid_outcome?(_, status, value) when status in ~w(unknown denied), do: value == %{}

  def valid_outcome?(%{"name" => "read"}, "failed", value) do
    is_map(value) and Map.keys(value) == ["reason"] and
      value["reason"] in ~w(tool_failed result_limit)
  end

  def valid_outcome?(request, "ok", value) do
    keys =
      if request["name"] == "shell",
        do: ~w(text exit_code output_bytes output_truncated),
        else: ["text"]

    is_map(value) and Enum.sort(Map.keys(value)) == Enum.sort(keys) and
      is_binary(value["text"]) and String.valid?(value["text"]) and
      byte_size(value["text"]) <= @limit and
      (request["name"] != "shell" or
         (is_integer(value["exit_code"]) and value["exit_code"] in 0..255 and
            is_integer(value["output_bytes"]) and
            value["output_bytes"] >= byte_size(value["text"]) and
            value["output_truncated"] === false))
  rescue
    _ -> false
  end

  def valid_outcome?(_, _, _), do: false
  defp unknown, do: {:unknown, %{}}
end
