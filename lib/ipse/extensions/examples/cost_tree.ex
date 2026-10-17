defmodule Ipse.Extensions.Examples.CostTree do
  @moduledoc "Default-off parent/child accounting reports through explicitly granted SDK reads."
  @behaviour Ipse.Extension
  alias Ipse.Extensions.{CostSummary, UsageRead, ChildUsage}

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
    case CostSummary.new(options["rate_card"], 40_000) do
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
           case CostSummary.put(acc, row) do
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
        CostSummary.tree_report(
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
