defmodule Ipse.Builtins.CostSummary do
  @moduledoc "Default-off full own-session summary through bounded accounting pages."
  @behaviour Ipse.Extension
  alias Ipse.Usage.Costs, as: Accumulator
  alias Ipse.Extension.UsageRead

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
    case Accumulator.summary(options["rate_card"]) do
      {:ok, accumulator} -> read(0, nil, %{accumulator: accumulator, snapshot: nil, cursor: 0})
      _ -> result(%{"status" => "invalid_rate_card"}, options)
    end
  end

  def handle("host.actions", %{"outcome" => %{"status" => "ok", "value" => page}}, state) do
    request = request(state.cursor, state.snapshot)

    with true <- UsageRead.valid_outcome?(request, "ok", page, page["snapshot"]["operation_id"]),
         {:ok, accumulator} <- accumulate(state.accumulator, page["requests"]) do
      if page["next"] == nil do
        value = Accumulator.report(accumulator, page["snapshot"], true)

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
      case Accumulator.put_request(current, request) do
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

      Ipse.Extension.UsageRead.validate(request) != :ok ->
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

defmodule Ipse.Builtins.CostTree do
  @moduledoc "Default-off parent/child accounting reports through explicitly granted SDK reads."
  @behaviour Ipse.Extension
  alias Ipse.Usage.Costs
  alias Ipse.Extension.UsageRead
  alias Ipse.Extension.ChildUsage

  def exports do
    paging = %{
      "cursor" => %{"type" => "integer", "minimum" => 0, "maximum" => 10_000},
      "limit" => %{"type" => "integer", "minimum" => 1, "maximum" => 4},
      "snapshot" => %{"type" => ["object", "null"]}
    }

    commands =
      for {id, description, properties, required} <- [
            {"tree_summary", "Summarize captured parent and registered direct-child accounting.",
             %{}, []},
            {"children",
             "Page the actual registered direct children without conversation content.", paging,
             []},
            {"child_usage", "Page a registered child's captured canonical accounting.",
             Map.put(paging, "child_id", %{
               "type" => "string",
               "minLength" => 32,
               "maxLength" => 32
             }), ["child_id"]}
          ],
          do: %{
            "id" => id,
            "description" => description,
            "arguments_schema" => %{
              "type" => "object",
              "additionalProperties" => false,
              "properties" => properties,
              "required" => required
            },
            "result_schema" => %{"type" => "object"}
          }

    %{"version" => 1, "tools" => [], "services" => [], "commands" => commands}
  end

  @impl true
  def describe,
    do: %{
      "sdk" => 1,
      "capabilities" =>
        ~w(invoke.command host.actions host.usage host.usage.scan host.usage.children),
      "exports" => exports()
    }

  @impl true
  def init(options), do: {:ok, options}

  @impl true
  def handle("invoke.command", %{"id" => "tree_summary"}, options) do
    case Costs.summary(options["rate_card"], 40_000) do
      {:ok, accumulator} ->
        read(request("usage.read", 0, nil), %{
          accumulator: accumulator,
          mode: :tree,
          root: nil,
          discovery: nil,
          children: [],
          captured: [],
          index: 0,
          child_snapshot: nil,
          steps: 0,
          request: nil
        })

      _ ->
        result(%{"status" => "invalid_rate_card"}, options)
    end
  end

  def handle("invoke.command", %{"id" => id, "arguments" => args}, options)
      when id in ~w(children child_usage) do
    op = if id == "children", do: "usage.children", else: "usage.child.read"
    r = request(op, Map.get(args, "cursor", 0), args["snapshot"])
    r = Map.put(r, "limit", Map.get(args, "limit", 4))
    r = if id == "child_usage", do: Map.put(r, "child_id", args["child_id"]), else: r

    if ChildUsage.validate(r) == :ok,
      do: {:ok, call(r), %{options: options, mode: :page}},
      else: result(%{"status" => "invalid_arguments"}, options)
  end

  def handle("host.actions", payload, %{mode: :page} = state),
    do: result(payload["outcome"], state)

  def handle("host.actions", payload, %{mode: :tree} = state) do
    state = %{state | steps: payload["step"]}

    case payload["outcome"] do
      %{"status" => "ok", "value" => page} ->
        validator = if state.request["op"] == "usage.read", do: UsageRead, else: ChildUsage

        if validator.valid_outcome?(state.request, "ok", page, page["snapshot"]["operation_id"]) do
          accept(page, state)
        else
          result(%{"status" => "invalid_summary_page"}, state)
        end

      outcome ->
        if state.request["op"] == "usage.child.read" do
          child = Enum.at(state.children, state.index)

          capture = %{
            "child" => child,
            "snapshot" => state.child_snapshot,
            "complete" => false,
            "error" => outcome["value"]["code"] || "unknown"
          }

          next_child(%{
            state
            | captured: state.captured ++ [capture],
              index: state.index + 1,
              child_snapshot: nil
          })
        else
          result(%{"status" => "summary_incomplete", "outcome" => outcome}, state)
        end
    end
  end

  defp accept(%{"children" => children} = page, state) do
    state = %{state | children: state.children ++ children, discovery: page["snapshot"]}

    if page["next"],
      do: read(request("usage.children", page["next"], page["snapshot"]), state),
      else: next_child(state)
  end

  defp accept(%{"requests" => rows} = page, state) do
    case Enum.reduce_while(rows, {:ok, state.accumulator}, fn row, {:ok, acc} ->
           case Costs.put_request(acc, row) do
             {:ok, next} -> {:cont, {:ok, next}}
             error -> {:halt, error}
           end
         end) do
      {:ok, accumulator} ->
        state = %{state | accumulator: accumulator}

        if state.request["op"] == "usage.read" do
          state = %{state | root: page["snapshot"]}

          if page["next"],
            do: read(request("usage.read", page["next"], page["snapshot"]), state),
            else: read(request("usage.children", 0, nil), state)
        else
          state = %{state | child_snapshot: page["snapshot"]}

          if page["next"] do
            read(child_request(state, page["next"], page["snapshot"]), state)
          else
            capture = %{
              "child" => Enum.at(state.children, state.index),
              "snapshot" => page["snapshot"],
              "complete" => true
            }

            next_child(%{
              state
              | captured: state.captured ++ [capture],
                index: state.index + 1,
                child_snapshot: nil
            })
          end
        end

      _ ->
        result(%{"status" => "summary_bounds"}, state)
    end
  end

  defp next_child(state) do
    if state.index < length(state.children),
      do: read(child_request(state, 0, nil), state),
      else: finish(state)
  end

  defp child_request(state, cursor, snapshot),
    do:
      request("usage.child.read", cursor, snapshot)
      |> Map.put("child_id", Enum.at(state.children, state.index)["child_id"])

  defp request(op, cursor, snapshot),
    do: %{"op" => op, "cursor" => cursor, "limit" => 4, "snapshot" => snapshot}

  defp read(request, state) do
    if state.steps >= 10_000 do
      finish(state)
    else
      {:ok, call(request), %{state | request: request}}
    end
  end

  defp finish(state) do
    captured =
      if state.child_snapshot do
        state.captured ++
          [
            %{
              "child" => Enum.at(state.children, state.index),
              "snapshot" => state.child_snapshot,
              "complete" => false,
              "error" => "scan_limit"
            }
          ]
      else
        state.captured
      end

    if state.root do
      value =
        Costs.tree_report(
          state.accumulator,
          state.root,
          state.discovery,
          captured,
          state.children
        )

      if Ipse.Extension.validate(value) == :ok,
        do: result(value, state),
        else: result(%{"status" => "summary_bounds"}, state)
    else
      result(%{"status" => "summary_incomplete"}, state)
    end
  end

  defp call(request), do: %{"api_version" => 1, "kind" => "host_call", "request" => request}

  defp result(value, state),
    do: {:ok, %{"api_version" => 1, "kind" => "result", "value" => value}, state}
end
