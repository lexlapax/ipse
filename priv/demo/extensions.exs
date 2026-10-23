defmodule Ipse.ExtensionDemo do
  @moduledoc false
  defmodule Model do
    def complete(config, messages, _tools, emit) do
      send(config.test_pid, {:extension_fixture_context, messages})
      emit.({:text, "fixture answer"})

      {:ok,
       %{
         "role" => "assistant",
         "content" => "fixture answer",
         "provider_data" => %{"opaque" => "synthetic-private-native"}
       }, %{}}
    end
  end

  def run do
    Application.ensure_all_started(:ipse)

    root =
      Path.join(
        System.tmp_dir!(),
        "ipse-extension-demo-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
      )

    File.mkdir_p!(root)

    try do
      instances = [
        %{
          "instance" => "annotation",
          "artifact" => "builtin:prompt-annotation:1",
          "enabled" => true,
          "options" => %{"text" => "Fixture context"},
          "order" => 1,
          "lifetime" => "session"
        },
        %{
          "instance" => "formatter",
          "artifact" => "builtin:answer-format:1",
          "enabled" => true,
          "options" => %{"prefix" => "<answer>", "suffix" => "</answer>"},
          "order" => 2,
          "lifetime" => "session"
        }
      ]

      trust =
        Enum.map(Ipse.Extension.Registry.builtins(), fn descriptor ->
          %{
            "artifact" => descriptor["artifact"],
            "capabilities" => descriptor["capabilities"],
            "allow_project" => false,
            "allow_children" => false
          }
        end)

      source = %{
        scope: "operator",
        path: "/synthetic/operator.json",
        data: %{"extensions" => instances, "extension_trust" => trust}
      }

      {:ok, catalog} = Ipse.Extension.Config.resolve([source], [])
      {:ok, entries} = Ipse.Extension.Registry.prepare(catalog, Path.join(root, "home"))

      config = %{
        provider: :ollama,
        model: "fixture",
        provider_module: Model,
        test_pid: self(),
        approval: :deny,
        home: Path.join(root, "home"),
        compact: false,
        context_bytes: 400_000,
        extensions: entries
      }

      opts = [
        config: config,
        cwd: root,
        state_dir: Path.join(root, "sessions"),
        subscriber: self()
      ]

      {:ok, session} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
      {:ok, text_handle} = Ipse.Session.subscribe_text(session)
      {:ok, event_handle} = Ipse.Session.subscribe_text(session, 2)
      :ok = Ipse.Session.prompt(session, "original fixture task")
      await(session)
      "fixture answer" = visible_text(text_handle)
      "fixture answer" = visible_text(event_handle)

      receive do
        {:extension_fixture_context, [system, reference, user]} ->
          "system" = system["role"]
          "user" = reference["role"]
          true = String.starts_with?(reference["content"], "Untrusted reference context")
          false = String.contains?(system["content"], "Fixture context")
          true = String.starts_with?(user["content"], "original fixture task")
          true = String.contains?(user["content"], "Fixture context")
      after
        1000 -> raise "Extension fixture context unavailable"
      end

      info = Ipse.Session.info(session)
      accounting = info.accounting

      %{
        "request_count" => 1,
        "legacy_unmetered" => false,
        "requests" => [
          %{
            "outcome" => "completed",
            "billing_mode" => "local",
            "usage" => %{"quality" => "unavailable"}
          }
        ]
      } = accounting

      false = String.contains?(Jason.encode!(accounting), "synthetic-private-native")
      "<answer>fixture answer</answer>" = info.final
      {:ok, events} = Ipse.Journal.load(opts[:state_dir], info.id)
      {:ok, [_user, assistant]} = Ipse.Session.restore_context(events)
      "fixture answer" = assistant["content"]
      %{"opaque" => "synthetic-private-native"} = assistant["provider_data"]
      projections = Enum.filter(events, &(&1["type"] == "extension_transform_result"))
      2 = length(projections)
      false = String.contains?(Jason.encode!(projections), "synthetic-private-native")
      :ok = Ipse.Session.close(session)
      path = Path.join(opts[:state_dir], info.id <> ".jsonl")
      bytes = File.read!(path)
      lifecycle = lifecycle_views(opts[:state_dir], info.id)

      {:ok, resumed} =
        DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts ++ [id: info.id]})

      :idle = Ipse.Session.info(resumed).phase
      ^accounting = Ipse.Session.info(resumed).accounting
      "<answer>fixture answer</answer>" = Ipse.Session.info(resumed).final
      ^bytes = File.read!(path)
      ^lifecycle = lifecycle_views(opts[:state_dir], info.id)
      :ok = Ipse.Session.close(resumed)

      local_trace(root, config)
      conformance(catalog, config.home)
      answer_views()
      history_views(root)
      runtime_epochs(root, config)
      feed_primitives()
      tool_views()

      IO.puts(
        "Extension prompt/presentation and unchanged idle resume fixture passed without inference. Local diagnostic sink fixture passed without network inference."
      )

      :ok
    after
      File.rm_rf!(root)
    end
  end

  # Projection-only runtime compatibility check; these synthetic positions are
  # not physical journal authority or an installed subscriber proof.
  defp answer_views do
    id = Ipse.Usage.id()
    {:ok, effective} = Ipse.Journal.source(id, 0, %{"type" => "synthetic"})

    record =
      Ipse.Session.Lifecycle.answer(
        Ipse.Usage.id(),
        Ipse.Usage.id(),
        %{
          "role" => "assistant",
          "content" => "fixture original",
          "provider_data" => %{"secret" => "private native"}
        },
        "fixture presented",
        effective
      )

    true = Ipse.Session.Lifecycle.valid_answer?(record)
    {:ok, source} = Ipse.Journal.source(id, 1, record)
    {:ok, original} = Ipse.Session.Lifecycle.project(source, record, "answer.original")
    {:ok, presented} = Ipse.Session.Lifecycle.project(source, record, "answer.presented")
    "fixture original" = original["data"]["text"]
    "fixture presented" = presented["data"]["text"]
    true = original["event_id"] == presented["event_id"]
    false = String.contains?(Jason.encode!(original), "private native")
    {:ok, metadata} = Ipse.Observability.build_event(source, record, 1, 0)
    true = Ipse.Observability.valid_event?(metadata)

    false =
      String.contains?(Jason.encode!(metadata), [
        "fixture original",
        "fixture presented",
        "sha256"
      ])
  end

  defp runtime_epochs(root, config) do
    directory = Path.join(root, "runtime-sessions")

    config =
      %{config | extensions: []}
      |> Map.put(:observability, Map.put(Ipse.Observability.defaults(), "mode", "local"))

    opts = [config: config, cwd: root, state_dir: directory, subscriber: self()]
    {:ok, first} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
    id = Ipse.Session.info(first).id
    :ok = Ipse.Session.close(first)

    {:ok, resumed} =
      DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts ++ [id: id]})

    :idle = Ipse.Session.info(resumed).phase
    :ok = Ipse.Session.close(resumed)
    {:ok, events} = Ipse.Journal.load(directory, id)
    {:ok, %{closed: true, count: 4}} = Ipse.Session.RuntimeLifecycle.restore(events, id)
    {:ok, []} = Ipse.Session.restore_context(events)
    :ok = Ipse.Session.RuntimeLifecycle.validate_sources(directory, id, events)
    {:ok, %{records: records, next: nil}} = Ipse.Journal.source_page(directory, id, 0, 64)

    types =
      for %{source: source, record: record} <- records,
          record["type"] in Ipse.Session.RuntimeLifecycle.types() do
        {:ok, metadata} = Ipse.Session.Lifecycle.project(source, record, "metadata")
        true = Ipse.Session.Lifecycle.valid_metadata?(metadata)
        metadata["type"]
      end

    ~w(session.started session.close_committed session.resumed session.close_committed) = types
  end

  defp feed_primitives do
    declaration = %{
      "id" => "requests",
      "event" => "model.admitted",
      "event_version" => 1,
      "view" => "metadata",
      "mode" => "feed",
      "queue_events" => 8
    }

    :ok = Ipse.Extension.Subscriptions.validate([declaration], ["event.feed"])
    session = Ipse.Usage.id()

    record =
      Ipse.Usage.admission(
        session,
        %{provider: :demo, model: "fixture"},
        "model",
        Ipse.Usage.id()
      )

    {:ok, source} = Ipse.Journal.source(session, 1, record)
    {:ok, anchor} = Ipse.Journal.source(session, 0, %{"type" => "synthetic-enrollment"})
    {:ok, event} = Ipse.Session.Lifecycle.project(source, record, "metadata")

    payload =
      Ipse.Extension.Feeds.payload(
        %{"resource_id" => Ipse.Usage.id(), "declaration" => declaration},
        anchor,
        1,
        event
      )

    :ok = Ipse.Extension.validate(payload)
    true = payload["event"]["event_id"] == source["event_id"]
    false = String.contains?(Jason.encode!(payload), "sha256")
    %{"kind" => "ack", "sequence" => 1} = Ipse.Extension.Feeds.ack(payload)
  end

  # Projection-only compatibility; synthetic positions confer no physical authority.
  defp tool_views do
    session = Ipse.Usage.id()
    turn = Ipse.Usage.id()
    request = Ipse.Usage.id()
    runtime = %{epoch: Ipse.Usage.id(), active: true}

    config = %{
      extensions: [%{identity: %{"capabilities" => ~w(lifecycle.record lifecycle.tools)}}]
    }

    {ctx, []} = Ipse.Session.ToolLifecycle.open(config, [], session, runtime, nil, nil)
    call = %{"id" => "synthetic", "function" => %{"name" => "read", "arguments" => "{}"}}

    proposal = %{
      "type" => "message",
      "request_id" => request,
      "message" => %{"role" => "assistant", "tool_calls" => [call]}
    }

    {:ok, proposal_source} = Ipse.Journal.source(session, 0, proposal)
    {ctx, []} = Ipse.Session.ToolLifecycle.proposal(ctx, proposal_source, proposal, turn)

    legacy = %{
      "type" => "tool_started",
      "call_id" => "synthetic",
      "name" => "read",
      "approval" => "not_required",
      "arguments" => nil
    }

    {:ok, intent_source} = Ipse.Journal.source(session, 1, legacy)
    {ctx, [intent]} = Ipse.Session.ToolLifecycle.start(ctx, intent_source, legacy, call, 1)
    {:ok, source} = Ipse.Journal.source(session, 2, intent)
    {:ok, private} = Ipse.Session.Lifecycle.project(source, intent, "tool.input")
    %{"name" => "read", "arguments_json" => "{}"} = private["data"]
    {:ok, metadata} = Ipse.Session.Lifecycle.project(source, intent, "metadata")
    true = Ipse.Session.Lifecycle.valid_metadata?(metadata)
    true = metadata["event_id"] == private["event_id"]
    ctx = Ipse.Session.ToolLifecycle.bind(ctx, source, intent)

    result = %{
      "type" => "message",
      "message" => %{
        "role" => "tool",
        "tool_call_id" => "synthetic",
        "content" => "fixture result",
        "ipse_tool_outcome" => %{"status" => "result_recorded", "approval" => "not_required"}
      }
    }

    {:ok, result_source} = Ipse.Journal.source(session, 3, result)
    {_, [outcome]} = Ipse.Session.ToolLifecycle.finish(ctx, result_source, result)
    {:ok, source} = Ipse.Journal.source(session, 4, outcome)

    {:ok, %{"data" => %{"text" => "fixture result"}}} =
      Ipse.Session.Lifecycle.project(source, outcome, "tool.result")
  end

  # Primitive compatibility fixture; installed SDK execution is exercised by the
  # independent-worker source tests and the later frozen-core package proof.
  defp history_views(root) do
    directory = Path.join(root, "history-unit")
    {:ok, id} = Ipse.Journal.create(directory, %{})
    {:ok, lock} = Ipse.Runner.lock(Path.join(directory, id <> ".lock"))

    try do
      :ok =
        Ipse.Journal.append(directory, id, %{
          "type" => "message",
          "message" => %{"role" => "user", "content" => "synthetic history text"}
        })

      identity = %{"instance" => "primitive-fixture"}

      for view <- ["metadata", "prompt.expanded"] do
        request = %{
          "op" => "history.read",
          "view" => view,
          "cursor" => 0,
          "snapshot" => nil,
          "limit" => 8
        }

        intent = %{
          "type" => "extension_action_intent",
          "version" => 1,
          "operation_id" => Ipse.Usage.id(),
          "namespace" => id,
          "identity_sha256" => Ipse.JSON.digest([identity]),
          "approval" => "not_required",
          "request" => request
        }

        {:ok, source} = Ipse.Journal.append_with_source(directory, id, intent)

        context = %{
          identity: identity,
          history_dir: directory,
          history_session: id,
          history_snapshot: Ipse.Extension.History.snapshot(source, intent)
        }

        {:ok, page} = Ipse.Extension.History.execute(context, intent)
        true = Ipse.Extension.History.valid_outcome?(request, "ok", page, intent["operation_id"])
        nil = page["next"]

        if view == "metadata" do
          false =
            String.contains?(Jason.encode!(page), ["synthetic history text", "record_sha256"])
        else
          true =
            Enum.any?(
              page["records"],
              &(&1["kind"] == "event" and &1["event"]["data"]["text"] == "synthetic history text")
            )
        end
      end
    after
      :ok = Ipse.Runner.unlock(lock)
    end
  end

  defp conformance(catalog, home) do
    fixture = %{
      "version" => 1,
      "cases" => [
        %{
          "id" => "hooks",
          "kind" => "prompt",
          "text" => "Synthetic conformance input",
          "expect" => %{
            "status" => "ok",
            "requests" => 1,
            "final" => "<answer>Conformance fixture completed.</answer>",
            "records" => %{"extension_transform_result" => 2}
          }
        }
      ]
    }

    {:ok, %{"passed" => true, "provider" => "synthetic"}} =
      Ipse.Extension.Conformance.run(catalog, home, fixture)
  end

  defp local_trace(root, config) do
    artifact = "builtin:local-trace:1"

    data = %{
      "extension_trust" => [
        %{
          "artifact" => artifact,
          "capabilities" => ["observe.local"],
          "allow_project" => false,
          "allow_children" => false
        }
      ],
      "extensions" => [
        %{
          "instance" => "trace",
          "artifact" => artifact,
          "enabled" => true,
          "options" => %{"directory" => Path.join(root, "trace"), "retained_leases" => 1},
          "order" => 0,
          "lifetime" => "session"
        }
      ]
    }

    {:ok, selected} =
      Ipse.Extension.Config.resolve(
        [%{scope: "operator", path: "/fixture/trace.json", data: data}],
        []
      )

    {:ok, entries} = Ipse.Extension.Registry.prepare(selected, config.home)

    config =
      %{config | extensions: entries}
      |> Map.put(:observability, Map.put(Ipse.Observability.defaults(), "mode", "local"))

    directory = Path.join(root, "trace-sessions")

    {:ok, session} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Ipse.Session, [config: config, cwd: root, state_dir: directory, subscriber: self()]}
      )

    :ok = Ipse.Session.prompt(session, "synthetic-diagnostic-private-prompt")
    await(session)
    drain_trace(session, 500)
    [sink] = Ipse.Session.diagnostics(session)["observability"]["sinks"]
    ring = Path.join([root, "trace", "trace-ring-v1"])
    catalog = ring |> Path.join("catalog.json") |> File.read!() |> Jason.decode!()
    {slot, _} = Enum.find(catalog["slots"], fn {_, id} -> id == sink["resource_id"] end)
    path = Path.join(ring, "slot-#{slot}.jsonl")
    bytes = File.read!(path)

    false =
      String.contains?(bytes, [
        "synthetic-diagnostic-private-prompt",
        "synthetic-private-native",
        "fixture answer",
        "record_sha256"
      ])

    true = String.contains?(bytes, "model.admitted")
    0 = Bitwise.band(File.stat!(path).mode, 0o077)
    id = Ipse.Session.info(session).id
    :ok = Ipse.Session.stop_observability(session)
    "off" = Ipse.Session.diagnostics(session)["observability"]["mode"]
    :ok = Ipse.Session.close(session)
    {:ok, events} = Ipse.Journal.load(directory, id)
    :ok = Ipse.Observability.validate_events(events, id)

    {:ok, next} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Ipse.Session, [config: config, cwd: root, state_dir: directory, subscriber: self()]}
      )

    :ok = Ipse.Session.prompt(next, "replacement-diagnostic-private-prompt")
    await(next)
    drain_trace(next, 500)
    [next_sink] = Ipse.Session.diagnostics(next)["observability"]["sinks"]
    catalog = ring |> Path.join("catalog.json") |> File.read!() |> Jason.decode!()
    1 = map_size(catalog["slots"])
    true = Map.values(catalog["slots"]) == [next_sink["resource_id"]]
    true = next_sink["resource_id"] != sink["resource_id"]
    :ok = Ipse.Session.close(next)
    true = length(Path.wildcard(Path.join(ring, "slot-*.jsonl*"))) <= 2
  end

  defp drain_trace(_, 0), do: raise("Local trace fixture did not settle")

  defp drain_trace(session, remaining) do
    if Enum.all?(
         Ipse.Session.diagnostics(session)["observability"]["sinks"],
         &(&1["ready"] and not &1["closed"] and &1["pending"] == 0 and &1["delivered"] > 0)
       ) do
      :ok
    else
      Process.sleep(20)
      drain_trace(session, remaining - 1)
    end
  end

  defp lifecycle_views(directory, id) do
    {:ok, %{records: records, next: nil}} = Ipse.Journal.source_page(directory, id, 0, 64)

    metadata =
      for %{source: source, record: record} <- records,
          {:ok, event} <- [Ipse.Session.Lifecycle.project(source, record, "metadata")],
          do: event

    prompts = Enum.filter(metadata, &String.starts_with?(&1["type"], "prompt."))

    ~w(prompt.received prompt.expanded_committed prompt.projection_committed) =
      Enum.map(prompts, & &1["type"])

    for type <-
          ~w(session.created model.admitted model.finished assistant.committed turn.finished) do
      true = Enum.any?(metadata, &(&1["type"] == type))
    end

    admitted = Enum.find(metadata, &(&1["type"] == "model.admitted"))
    finished = Enum.find(metadata, &(&1["type"] == "model.finished"))
    true = admitted["correlations"]["request_id"] == finished["correlations"]["request_id"]

    false =
      String.contains?(Jason.encode!(metadata), [
        "original fixture task",
        "Fixture context",
        "synthetic-private-native"
      ])

    for event <- prompts do
      entry = Enum.find(records, &(&1.source["event_id"] == event["event_id"]))

      view =
        %{
          "prompt.received" => "prompt.original",
          "prompt.expanded_committed" => "prompt.expanded",
          "prompt.projection_committed" => "prompt.projection"
        }[event["type"]]

      {:ok, private} = Ipse.Session.Lifecycle.project(entry.source, entry.record, view)
      true = String.contains?(private["data"]["text"], "original fixture task")
      false = String.contains?(Jason.encode!(event), entry.source["record_sha256"])
      false = String.contains?(Jason.encode!(private), "synthetic-private-native")
    end

    metadata
  end

  defp await(session) do
    receive do
      {:ipse, ^session, {:done, :ok}} -> :ok
      {:ipse, ^session, {:done, _}} -> raise "Extension fixture failed"
      {:ipse, ^session, _} -> await(session)
    after
      15_000 -> raise "Extension fixture timed out"
    end
  end

  defp visible_text(handle, text \\ "") do
    subscription = handle.subscription_id

    receive do
      {:ipse_text, server, %{"subscription_id" => ^subscription, "sequence" => sequence} = frame}
      when server == handle.server ->
        if frame["version"] == 2 do
          true = Ipse.Session.TextStream.valid_frame?(frame)
          {:ok, metadata} = Ipse.Session.TextStream.project_frame(frame, "metadata")

          if frame["kind"] == "text" do
            {:ok, private} = Ipse.Session.TextStream.project_frame(frame, "text.visible")
            true = metadata["event_id"] == private["event_id"]
          end
        end

        :ok = Ipse.Session.TextStream.ack(handle, sequence)
        text = text <> (frame["text"] || "")

        if frame["kind"] == "end" do
          true = frame["complete"]
          text
        else
          visible_text(handle, text)
        end
    after
      1000 -> raise "Private visible-text fixture timed out"
    end
  end
end
