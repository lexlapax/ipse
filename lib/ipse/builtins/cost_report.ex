defmodule Ipse.Builtins.CostReport do
  @moduledoc "Default-off accounting report through granted host reads and explicit rate-card estimates."
  @behaviour Ipse.Extension
  alias Ipse.Usage.Costs

  @fields ~w(operation provider billing_mode model reported_model endpoint_sha256 admitted_at_ms outcome finality usage)
  @safe 9_007_199_254_740_991

  def exports do
    %{
      "version" => 1,
      "tools" => [],
      "services" => [],
      "commands" => [
        %{
          "id" => "report",
          "description" =>
            "Read a bounded own-session accounting page with configured cost estimates.",
          "arguments_schema" => %{
            "type" => "object",
            "additionalProperties" => false,
            "properties" => %{
              "cursor" => %{"type" => "integer", "minimum" => 0, "maximum" => 10_000},
              "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 4},
              "snapshot" => %{"type" => ["object", "null"]}
            }
          },
          "result_schema" => %{"type" => "object"}
        }
      ]
    }
  end

  @impl true
  def describe,
    do: %{
      "sdk" => 1,
      "capabilities" => ~w(invoke.command host.actions host.usage),
      "exports" => exports()
    }

  @impl true
  def init(options), do: {:ok, options}

  @impl true
  def handle("invoke.command", %{"id" => "report", "arguments" => args}, state) do
    request = %{
      "op" => "usage.read",
      "cursor" => Map.get(args, "cursor", 0),
      "limit" => Map.get(args, "limit", 4),
      "snapshot" => Map.get(args, "snapshot")
    }

    cond do
      Costs.validate(state["rate_card"]) != :ok ->
        result(%{"status" => "invalid_rate_card"}, state)

      Ipse.Extensions.UsageRead.validate(request) != :ok ->
        result(%{"status" => "invalid_arguments"}, state)

      true ->
        {:ok,
         %{
           "api_version" => 1,
           "kind" => "host_call",
           "request" => request
         }, state}
    end
  end

  def handle("host.actions", %{"outcome" => %{"status" => "ok", "value" => page}}, state) do
    value =
      case report(state["rate_card"], page) do
        {:ok, report} -> report
        {:error, :invalid_rate_card} -> %{"status" => "invalid_rate_card"}
      end

    result =
      if Ipse.Extension.validate(value) == :ok,
        do: value,
        else: %{
          "status" => "report_bounds",
          "retry_cursor" => page["cursor"],
          "snapshot" => page["snapshot"]
        }

    result(result, state)
  end

  def handle("host.actions", payload, state),
    do:
      result(
        %{"status" => payload["outcome"]["status"], "details" => payload["outcome"]["value"]},
        state
      )

  def report(card, page) do
    with :ok <- Costs.validate(card) do
      priced =
        Enum.map(page["requests"], fn request ->
          {:ok, quote} = Costs.estimate(card, Map.take(request, @fields))
          {request, quote}
        end)

      groups =
        priced
        |> Enum.group_by(fn {r, q} ->
          {r["provider"], r["billing_mode"], q["basis"], r["operation"] || "text"}
        end)
        |> Enum.sort_by(fn {key, _} -> key end)
        |> Enum.map(fn {{provider, billing, basis, operation}, rows} ->
          amounts = Enum.map(rows, fn {_, q} -> q["amount_nanos"] end)

          known =
            Enum.flat_map(rows, fn {_, q} ->
              if is_integer(q["known_amount_nanos"]), do: [q["known_amount_nanos"]], else: []
            end)

          sum = Enum.sum(known)
          overflow = sum > @safe
          total = if Enum.all?(amounts, &is_integer/1) and not overflow, do: Enum.sum(amounts)

          group = %{
            "provider" => provider,
            "billing_mode" => billing,
            "basis" => basis,
            "request_count" => length(rows),
            "unknown_cost_count" => Enum.count(amounts, &is_nil/1),
            "amount_nanos" => total,
            "known_amount_nanos" => if(known != [] and not overflow, do: sum),
            "overflow" => overflow
          }

          if operation == "embedding", do: Map.put(group, "operation", operation), else: group
        end)

      rows =
        Enum.map(priced, fn {r, q} ->
          Map.take(
            r,
            ~w(operation request_id attempt_id parent_session_id parent_request_id selected_profile kind)
          )
          |> Map.put(
            "estimate",
            Map.drop(
              q,
              ~w(version card_id revision card_sha256 source published_on currency currency_scale rounding scope)
            )
          )
        end)

      {:ok,
       %{
         "status" => "reported",
         "coverage" => "page",
         "snapshot" => page["snapshot"],
         "cursor" => page["cursor"],
         "next" => page["next"],
         "requests" => rows,
         "groups" => groups,
         "rate_card" =>
           Map.take(card, ~w(id revision currency source published_on))
           |> Map.put("sha256", Ipse.JSON.digest([card])),
         "currency_scale" => 9,
         "rounding" => "ceiling_per_request"
       }}
    end
  end

  defp result(value, state),
    do: {:ok, %{"api_version" => 1, "kind" => "result", "value" => value}, state}
end
