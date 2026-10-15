defmodule Ipse.Delegation do
  @moduledoc "Pure policy and bounds for one local delegated child session."

  @task_limit 8_192
  @context_limit 8_192
  @arguments_limit 32_768
  @max_depth 12
  @max_collection 128

  @doc "Whether delegation is explicitly enabled for this session."
  def enabled?(config) when is_map(config),
    do: Map.get(config, :subagents, false) == true and is_nil(Map.get(config, :delegation_origin))

  def enabled?(_), do: false

  @doc "Return the single local delegate tool when enabled."
  def definitions(config) do
    if enabled?(config) do
      [
        %{
          "type" => "function",
          "function" => %{
            "name" => "delegate",
            "description" =>
              "Delegate one bounded task to a local child using the same provider, model, and workspace. " <>
                "Host approval is required for delegation and for child mutations. The child returns a bounded result; it cannot delegate or use MCP tools.",
            "parameters" => %{
              "type" => "object",
              "properties" => %{
                "task" => %{"type" => "string", "maxLength" => @task_limit},
                "context" => %{"type" => "string", "maxLength" => @context_limit}
              },
              "required" => ["task", "context"],
              "additionalProperties" => false
            }
          }
        }
      ]
    else
      []
    end
  end

  @doc "Validate the exact task/context payload accepted from the model."
  def validate(args) when is_map(args) do
    with true <- Map.keys(args) |> Enum.sort() == ["context", "task"],
         task when is_binary(task) <- args["task"],
         context when is_binary(context) <- args["context"],
         true <- String.valid?(task) and String.trim(task) != "",
         true <- String.valid?(context),
         true <- byte_size(task) <= @task_limit,
         true <- byte_size(context) <= @context_limit,
         :ok <- validate_approval(args) do
      :ok
    else
      _ -> {:error, "Delegation request is invalid or exceeds its bounds."}
    end
  rescue
    _ -> {:error, "Delegation request is invalid or exceeds its bounds."}
  end

  def validate(_), do: {:error, "Delegation request is invalid or exceeds its bounds."}

  @doc "Check that complete approval arguments can be safely encoded and displayed."
  def validate_approval(args) when is_map(args) do
    with :ok <- bounded_json(args, 1),
         {:ok, encoded} <- Jason.encode(args, pretty: true),
         true <- byte_size(encoded) <= @arguments_limit do
      :ok
    else
      _ -> {:error, "Approval arguments are invalid or exceed display bounds."}
    end
  rescue
    _ -> {:error, "Approval arguments are invalid or exceed display bounds."}
  end

  def validate_approval(_),
    do: {:error, "Approval arguments are invalid or exceed display bounds."}

  def max_calls, do: 2
  def max_steps, do: 6
  def timeout_ms, do: 120_000
  def result_bytes, do: 16_384

  @doc "Build child policy from host configuration without carrying conversation state."
  def child_config(config, origin) when is_map(config) do
    config
    |> Map.drop([
      :messages,
      :transcript,
      :history,
      :context,
      :context_snapshot,
      :tools,
      :mcp_tools
    ])
    |> Map.put(:subagents, false)
    |> Map.put(:mcp_servers, [])
    |> Map.put(:approval, :ask)
    |> Map.put(:max_steps, min(parent_max_steps(config), max_steps()))
    |> Map.put(:compact, false)
    |> Map.put(:delegation_origin, origin)
  end

  def child_config(_, origin) do
    %{
      subagents: false,
      mcp_servers: [],
      approval: :ask,
      max_steps: max_steps(),
      compact: false,
      delegation_origin: origin
    }
  end

  defp parent_max_steps(%{max_steps: steps}) when is_integer(steps) and steps > 0, do: steps
  defp parent_max_steps(_), do: 30

  defp bounded_json(_value, depth) when depth > @max_depth,
    do: {:error, :depth}

  defp bounded_json(value, _depth)
       when is_binary(value) or is_boolean(value) or is_nil(value) or is_integer(value),
       do: :ok

  defp bounded_json(value, _depth) when is_float(value) do
    if value == value and abs(value) < 1.0e308, do: :ok, else: {:error, :number}
  end

  defp bounded_json(value, depth) when is_map(value) and map_size(value) <= @max_collection do
    if Enum.all?(Map.keys(value), &(is_binary(&1) and String.valid?(&1))) do
      Enum.reduce_while(value, :ok, fn {_key, child}, :ok ->
        case bounded_json(child, depth + 1) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    else
      {:error, :key}
    end
  end

  defp bounded_json(value, depth) when is_list(value) and length(value) <= @max_collection do
    Enum.reduce_while(value, :ok, fn child, :ok ->
      case bounded_json(child, depth + 1) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp bounded_json(_, _), do: {:error, :value}
end
