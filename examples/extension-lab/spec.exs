defmodule IpseLab.Spec do
  @moduledoc false
  def object(properties \\ %{}, required \\ []),
    do: %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => properties,
      "required" => required
    }

  def text(max \\ 2048), do: %{"type" => "string", "maxLength" => max}

  def result,
    do: object(%{"status" => text(32), "value" => %{"type" => "object"}}, ~w(status value))

  def query, do: object(%{"text" => text()}, ["text"])
  def evidence, do: object(%{"text" => text(), "uri" => text(128)}, ~w(text uri))

  def descriptor(id, arguments, result \\ result()),
    do: %{
      "id" => id,
      "description" => "Synthetic extension lab: " <> id,
      "arguments_schema" => arguments,
      "result_schema" => result
    }

  def description(:memory) do
    exports = %{
      "version" => 1,
      "tools" => Enum.map(~w(remember recall forget catchup), &export/1),
      "commands" =>
        Enum.map(~w(remember recall forget export workflow catchup), &export/1) ++
          [descriptor("stats", object())],
      "services" => [],
      "jobs" =>
        Enum.map(
          ~w(capture recall),
          &descriptor(&1, object(%{"event" => %{"type" => "object"}}, ["event"]))
        )
    }

    %{
      "sdk" => 1,
      "capabilities" =>
        ~w(invoke.tool invoke.command event.job event.prompt.original event.prompt.effective host.actions host.state.read host.state.write host.question host.tools host.services host.context host.history host.history.prompt.original),
      "exports" => exports,
      "requires" => %{
        "version" => 1,
        "services" => [
          %{
            "alias" => "lookup",
            "contract" => 1,
            "arguments_schema" => query(),
            "result_schema" => evidence()
          }
        ]
      },
      "subscriptions" => [
        %{
          "id" => "recall",
          "event" => "prompt.effective_committed",
          "event_version" => 1,
          "view" => "prompt.effective",
          "mode" => "job",
          "handler" => "recall",
          "schedule" => "before_request",
          "required" => true
        },
        %{
          "id" => "capture",
          "event" => "prompt.received",
          "event_version" => 1,
          "view" => "prompt.original",
          "mode" => "job",
          "handler" => "capture",
          "schedule" => "after_turn",
          "required" => false
        }
      ]
    }
  end

  def description(:lookup),
    do: %{
      "sdk" => 1,
      "capabilities" => ["invoke.service"],
      "exports" => %{
        "version" => 1,
        "tools" => [],
        "commands" => [],
        "services" => [descriptor("query", query(), evidence())]
      }
    }

  def description(:metadata),
    do: %{
      "sdk" => 1,
      "capabilities" => ["event.notify"],
      "subscriptions" => [
        %{
          "id" => "counts",
          "event" => "prompt.received",
          "event_version" => 1,
          "view" => "metadata",
          "mode" => "notify",
          "required" => true
        }
      ]
    }

  def description(:observer),
    do: %{
      "sdk" => 1,
      "capabilities" => ["event.feed"],
      "subscriptions" => [
        %{
          "id" => "usage",
          "event" => "model.usage_observed",
          "event_version" => 1,
          "view" => "metadata",
          "mode" => "feed",
          "queue_events" => 1
        }
      ]
    }

  def description(:tool_observer) do
    subscriptions =
      for {event, view, id} <- [
            {"tool.intent_committed", "tool.input", "input"},
            {"tool.outcome_recorded", "tool.result", "result"}
          ],
          selected <- [view, "metadata"] do
        %{
          "id" => id <> if(selected == "metadata", do: "_counts", else: "_private"),
          "event" => event,
          "event_version" => 1,
          "view" => selected,
          "mode" => "feed",
          "queue_events" => 4
        }
      end

    %{
      "sdk" => 1,
      "capabilities" =>
        ~w(event.feed lifecycle.record lifecycle.tools event.tool.input event.tool.result),
      "subscriptions" => subscriptions
    }
  end

  def description(:text_observer),
    do: %{"sdk" => 1, "capabilities" => ~w(stream.text stream.text.events)}

  def options(:memory),
    do:
      object(
        %{
          "scope" => %{"type" => "string", "enum" => ~w(project session operator)},
          "capture" => %{"type" => "boolean"},
          "recall" => %{"type" => "boolean"},
          "bad_recall" => %{"type" => "boolean"}
        },
        ~w(scope capture recall bad_recall)
      )

  def options(:lookup),
    do:
      object(
        %{"text" => text(), "uri" => text(128), "fail" => %{"type" => "boolean"}},
        ~w(text uri fail)
      )

  def options(:metadata), do: object()
  def options(:observer), do: object(%{"hang" => %{"type" => "boolean"}}, ["hang"])
  def options(:tool_observer), do: object()
  def options(:text_observer), do: object()
  def module(:memory), do: "IpseLab.Memory"
  def module(:lookup), do: "IpseLab.Lookup"
  def module(:metadata), do: "IpseLab.Metadata"
  def module(:observer), do: "IpseLab.Observer"
  def module(:tool_observer), do: "IpseLab.ToolObserver"
  def module(:text_observer), do: "IpseLab.TextObserver"

  def operator(artifacts) do
    references =
      for kind <- ~w(memory lookup metadata observer tool_observer text_observer)a, into: %{} do
        bytes = File.read!(Path.join([artifacts, Atom.to_string(kind), "extension.json"]))
        {kind, :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)}
      end

    trust =
      for {kind, digest} <- references do
        item = %{
          "artifact" => digest,
          "capabilities" => description(kind)["capabilities"],
          "allow_project" => false,
          "allow_children" => false
        }

        if kind == :memory,
          do:
            Map.put(item, "service_bindings", [
              %{
                "caller" => "memory",
                "alias" => "lookup",
                "target" => "lookup",
                "artifact" => references.lookup,
                "service" => "query"
              }
            ]),
          else: item
      end

    settings = %{
      memory: %{"scope" => "project", "capture" => true, "recall" => true, "bad_recall" => false},
      lookup: %{
        "text" => "Synthetic corpus: supervisors own dependent processes.",
        "uri" => "fixture:supervision",
        "fail" => false
      },
      metadata: %{},
      observer: %{"hang" => false},
      tool_observer: %{},
      text_observer: %{}
    }

    instances =
      for {kind, digest} <- references,
          do: %{
            "instance" => Atom.to_string(kind),
            "artifact" => digest,
            "enabled" => false,
            "options" => settings[kind],
            "order" => 0,
            "lifetime" => "session"
          }

    %{"version" => 1, "extensions" => instances, "extension_trust" => trust}
  end

  defp export(id) when id in ~w(remember recall), do: descriptor(id, query())
  defp export("forget"), do: descriptor("forget", object(%{"entity" => text(32)}, ["entity"]))
  defp export("export"), do: descriptor("export", object())
  defp export("workflow"), do: descriptor("workflow", object(%{"path" => text(256)}, ["path"]))

  defp export("catchup"),
    do:
      descriptor(
        "catchup",
        object(
          %{
            "cursor" => %{"type" => "integer", "minimum" => 0},
            "snapshot" => %{"type" => ["object", "null"]},
            "pages" => %{"type" => "integer", "minimum" => 1, "maximum" => 8}
          },
          ~w(cursor snapshot pages)
        )
      )
end
