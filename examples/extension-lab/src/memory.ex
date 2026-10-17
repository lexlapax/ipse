defmodule IpseLab.Memory do
  @behaviour Ipse.Extension
  @description IpseLab.Spec.description(:memory)
  @package_version "LAB_PACKAGE_VERSION"
  def describe, do: @description
  def init(options), do: {:ok, %{options: options}}

  def handle("event.job", payload, state) do
    event = payload["arguments"]["event"]["event"]
    operation = payload["id"]

    if state.options[operation] do
      case operation do
        "capture" ->
          read(Map.merge(state, %{phase: "capture", facts: [fact(event)], manual: false}))

        "recall" ->
          read(Map.merge(state, %{phase: "recall", query: event["data"]["text"]}))
      end
    else
      finish("disabled", %{}, state)
    end
  end

  def handle(stage, payload, state) when stage in ~w(invoke.tool invoke.command) do
    args = payload["arguments"]

    case payload["id"] do
      "remember" ->
        entry =
          extract(args["text"], %{
            "id" => payload["invocation_id"],
            "view" => "explicit_invocation",
            "source" => nil
          })

        read(Map.merge(state, %{phase: "capture", facts: [entry], manual: true}))

      "recall" ->
        read(Map.merge(state, %{phase: "recall", query: args["text"]}))

      "forget" ->
        read(Map.merge(state, %{phase: "forget", entity: args["entity"]}))

      "export" ->
        read(Map.put(state, :phase, "export"))

      "workflow" ->
        request = %{
          "op" => "operator.question",
          "arguments" => %{
            "questions" => [
              %{
                "id" => "choice",
                "kind" => "single",
                "prompt" => "Which synthetic note should be written?",
                "recommended" => "first",
                "options" => [
                  %{"id" => "first", "label" => "First note"},
                  %{"id" => "second", "label" => "Second note"}
                ]
              }
            ]
          },
          "checkpoint" => %{"path" => args["path"]}
        }

        call(request, Map.put(state, :phase, "question"))

      "catchup" ->
        history(
          Map.merge(state, %{
            phase: "history",
            cursor: args["cursor"],
            snapshot: args["snapshot"],
            remaining: args["pages"],
            facts: [],
            gaps: [],
            scanned: 0,
            manual: false
          })
        )
    end
  end

  def handle(
        "host.actions",
        %{"outcome" => %{"status" => "answered"}, "checkpoint" => checkpoint} = payload,
        state
      ) do
    choice = payload["outcome"]["value"]["answers"]["choice"]

    call(
      %{
        "op" => "tool.call",
        "name" => "write",
        "arguments" => %{
          "path" => checkpoint["path"],
          "content" => "Operator selected #{choice}\n"
        },
        "timeout_ms" => 1_000
      },
      Map.put(state, :phase, "workflow_done")
    )
  end

  def handle("host.actions", payload, state) do
    outcome = payload["outcome"]

    if outcome["status"] != "ok" do
      finish(outcome["status"], %{}, state)
    else
      continue(state.phase, payload, state)
    end
  end

  defp continue("history", payload, state) do
    page = payload["outcome"]["value"]
    facts = for %{"kind" => "event", "event" => event} <- page["records"], do: fact(event)

    gaps =
      for %{"kind" => "gap", "source" => source, "reason" => reason} <- page["records"],
          do: %{"event_id" => source["event_id"], "reason" => reason}

    next = %{
      state
      | cursor: page["next"],
        snapshot: page["snapshot"],
        remaining: state.remaining - 1,
        facts: state.facts ++ facts,
        gaps: state.gaps ++ gaps,
        scanned: state.scanned + page["scanned"]
    }

    if next.cursor != nil and next.remaining > 0,
      do: history(next),
      else: read(%{next | phase: "capture"})
  end

  defp continue("capture", payload, state) do
    record = payload["outcome"]["value"]["record"]
    graph = record["value"] || empty()

    cond do
      record["deleted"] and record["revision"] > 0 ->
        finish("blocked", details(state, graph), state)

      not state.manual and not graph["automatic"] ->
        finish("blocked", details(state, graph), state)

      true ->
        existing = Enum.map(graph["sources"], & &1["id"]) ++ graph["forgotten_sources"]

        fresh =
          state.facts
          |> Enum.uniq_by(& &1["id"])
          |> Enum.reject(&(&1["id"] in existing or &1["entities"] == []))

        fresh =
          Enum.reject(
            fresh,
            &Enum.any?(&1["entities"], fn entity -> entity in graph["forgotten_entities"] end)
          )

        merged = summarize(%{graph | "sources" => graph["sources"] ++ fresh})

        cond do
          fresh == [] ->
            finish("unchanged", details(state, graph), state)

          length(merged["sources"]) > 8 or length(merged["entities"]) > 16 or
              byte_size(IO.iodata_to_binary(:json.encode(merged))) > 7_000 ->
            finish("capacity", details(state, graph), state)

          true ->
            put(merged, record["revision"], Map.merge(state, %{phase: "stored", graph: merged}))
        end
    end
  end

  defp continue("forget", payload, state) do
    record = payload["outcome"]["value"]["record"]
    graph = record["value"] || empty()

    if state.entity == "all" do
      call(
        %{
          "op" => "state.delete",
          "scope" => state.options["scope"],
          "key" => "graph",
          "expected_revision" => record["revision"]
        },
        Map.put(state, :phase, "forgotten")
      )
    else
      {removed, retained} = Enum.split_with(graph["sources"], &(state.entity in &1["entities"]))

      next =
        summarize(%{
          graph
          | "sources" => retained,
            "forgotten_sources" =>
              Enum.uniq(graph["forgotten_sources"] ++ Enum.map(removed, & &1["id"])),
            "forgotten_entities" => Enum.uniq([state.entity | graph["forgotten_entities"]])
        })

      if byte_size(IO.iodata_to_binary(:json.encode(next))) > 7_000,
        do: finish("capacity", %{}, state),
        else: put(next, record["revision"], Map.put(state, :phase, "forgotten"))
    end
  end

  defp continue("export", payload, state),
    do: finish("ok", payload["outcome"]["value"]["record"], state)

  defp continue("recall", payload, state) do
    record = payload["outcome"]["value"]["record"]
    summary = get_in(record, ["value", "summary"])

    item =
      if is_binary(summary) and summary != "",
        do: [
          %{
            "id" => "memory",
            "version" => Integer.to_string(record["revision"]),
            "text" => summary,
            "priority" => 20,
            "source" => %{
              "kind" => "receipt",
              "operation_id" => payload["operation_id"],
              "path" => ["record", "value", "summary"]
            }
          }
        ],
        else: []

    call(
      %{
        "op" => "service.call",
        "alias" => "lookup",
        "arguments" => %{"text" => state.query},
        "checkpoint" => %{}
      },
      Map.merge(state, %{phase: "lookup", items: item})
    )
  end

  defp continue("lookup", payload, state) do
    value = payload["outcome"]["value"]["result"]

    item = %{
      "id" => "lookup",
      "version" => "1",
      "text" => value["text"],
      "priority" => 10,
      "source" => %{
        "kind" => "receipt",
        "operation_id" => payload["operation_id"],
        "path" => ["result", if(state.options["bad_recall"], do: "absent", else: "text")]
      }
    }

    call(
      %{"op" => "context.publish", "items" => state.items ++ [item]},
      Map.put(state, :phase, "recalled")
    )
  end

  defp continue("stored", _payload, state),
    do: finish("stored", details(state, state.graph), state)

  defp continue("forgotten", _payload, state),
    do:
      call(%{"op" => "context.publish", "items" => []}, Map.put(state, :phase, "forgotten_done"))

  defp continue("forgotten_done", _payload, state), do: finish("forgotten", %{}, state)

  defp continue("recalled", _payload, state),
    do: finish("recalled", %{"memory_items" => length(state.items)}, state)

  defp continue("workflow_done", _payload, state), do: finish("written", %{}, state)

  defp fact(event),
    do:
      extract(event["data"]["text"], %{
        "id" => event["event_id"],
        "view" => event["view"],
        "source" => event["source"]
      })

  defp extract(text, origin) do
    entities =
      for [_, entity] <-
            Regex.scan(~r/entity:\s*([A-Za-z][A-Za-z0-9_-]{0,31})(?![A-Za-z0-9_-])/, text),
          do: entity

    links =
      for [_, from, to] <-
            Regex.scan(
              ~r/link:\s*([A-Za-z][A-Za-z0-9_-]{0,31})(?![A-Za-z0-9_-])\s*->\s*([A-Za-z][A-Za-z0-9_-]{0,31})(?![A-Za-z0-9_-])/,
              text
            ),
          do: %{"from" => from, "to" => to}

    Map.merge(origin, %{
      "entities" => Enum.uniq(entities ++ Enum.flat_map(links, &Map.values/1)),
      "links" => links,
      "package_version" => @package_version,
      "extractor_version" => "labels-1"
    })
  end

  defp empty,
    do: %{
      "version" => 1,
      "automatic" => true,
      "sources" => [],
      "entities" => [],
      "links" => [],
      "forgotten_sources" => [],
      "forgotten_entities" => [],
      "summary" => ""
    }

  defp summarize(graph) do
    entities = graph["sources"] |> Enum.flat_map(& &1["entities"]) |> Enum.uniq() |> Enum.sort()

    links =
      for source <- graph["sources"],
          link <- source["links"],
          do: Map.put(link, "source_event_id", source["id"])

    %{
      graph
      | "entities" => entities,
        "links" => links,
        "summary" =>
          if(entities == [], do: "", else: "Known entities: " <> Enum.join(entities, ", "))
    }
  end

  defp details(state, graph),
    do: %{
      "sources" => length(graph["sources"]),
      "entities" => length(graph["entities"]),
      "next" => Map.get(state, :cursor),
      "snapshot" => Map.get(state, :snapshot),
      "gaps" => Map.get(state, :gaps, []),
      "scanned" => Map.get(state, :scanned, 0),
      "coverage" => "recorded_views_only"
    }

  defp read(state),
    do: call(%{"op" => "state.get", "scope" => state.options["scope"], "key" => "graph"}, state)

  defp put(graph, revision, state),
    do:
      call(
        %{
          "op" => "state.put",
          "scope" => state.options["scope"],
          "key" => "graph",
          "expected_revision" => revision,
          "value" => graph
        },
        state
      )

  defp history(state),
    do:
      call(
        %{
          "op" => "history.read",
          "view" => "prompt.original",
          "cursor" => state.cursor,
          "snapshot" => state.snapshot,
          "limit" => 8
        },
        state
      )

  defp call(request, state),
    do: {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => request}, state}

  defp finish(status, value, state),
    do:
      {:ok,
       %{
         "api_version" => 1,
         "kind" => "result",
         "value" => %{"status" => status, "value" => value}
       }, state}
end
