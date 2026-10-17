defmodule Ipse.Extensions.Examples.CostSummary do
  @moduledoc "Default-off full own-session summary through bounded accounting pages."
  @behaviour Ipse.Extension
  alias Ipse.Extensions.{CostSummary, UsageRead}

  def exports do
    %{
      "version" => 1,
      "tools" => [],
      "services" => [],
      "commands" => [
        %{
          "id" => "summary",
          "description" =>
            "Summarize the captured own-session request range with configured rates.",
          "arguments_schema" => %{"type" => "object", "additionalProperties" => false},
          "result_schema" => %{"type" => "object"}
        }
      ]
    }
  end

  @impl true
  def describe,
    do: %{
      "sdk" => 1,
      "capabilities" => ~w(invoke.command host.actions host.usage host.usage.scan),
      "exports" => exports()
    }

  @impl true
  def init(options), do: {:ok, options}

  @impl true
  def handle("invoke.command", %{"id" => "summary"}, options) do
    case CostSummary.new(options["rate_card"]) do
      {:ok, accumulator} -> read(0, nil, %{accumulator: accumulator, snapshot: nil, cursor: 0})
      _ -> result(%{"status" => "invalid_rate_card"}, options)
    end
  end

  def handle("host.actions", %{"outcome" => %{"status" => "ok", "value" => page}}, state) do
    request = request(state.cursor, state.snapshot)

    with true <- UsageRead.valid_outcome?(request, "ok", page, page["snapshot"]["operation_id"]),
         {:ok, accumulator} <- accumulate(state.accumulator, page["requests"]) do
      if page["next"] == nil do
        value = CostSummary.report(accumulator, page["snapshot"], true)

        if Ipse.Extension.validate(value) == :ok do
          result(value, state)
        else
          result(%{"status" => "summary_bounds", "snapshot" => page["snapshot"]}, state)
        end
      else
        read(page["next"], page["snapshot"], %{state | accumulator: accumulator})
      end
    else
      _ -> result(%{"status" => "invalid_summary_page"}, state)
    end
  end

  def handle("host.actions", payload, state),
    do: result(%{"status" => "summary_incomplete", "outcome" => payload["outcome"]}, state)

  defp accumulate(state, requests) do
    Enum.reduce_while(requests, {:ok, state}, fn request, {:ok, current} ->
      case CostSummary.put(current, request) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  end

  defp request(cursor, snapshot),
    do: %{"op" => "usage.read", "cursor" => cursor, "limit" => 4, "snapshot" => snapshot}

  defp read(cursor, snapshot, state),
    do:
      {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => request(cursor, snapshot)},
       %{state | snapshot: snapshot, cursor: cursor}}

  defp result(value, state),
    do: {:ok, %{"api_version" => 1, "kind" => "result", "value" => value}, state}
end
