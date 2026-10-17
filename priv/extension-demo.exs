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
        Enum.map(Ipse.Extensions.Registry.builtins(), fn descriptor ->
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

      {:ok, catalog} = Ipse.Extensions.Config.resolve([source], [])
      {:ok, entries} = Ipse.Extensions.Registry.prepare(catalog, Path.join(root, "home"))

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
      :ok = Ipse.Session.prompt(session, "original fixture task")
      await(session)
      "fixture answer" = visible_text(text_handle)

      receive do
        {:extension_fixture_context, [_system, user]} ->
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

      IO.puts(
        "Extension prompt/presentation and unchanged idle resume fixture passed without inference. Local diagnostic sink fixture passed without network inference."
      )

      :ok
    after
      File.rm_rf!(root)
    end
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
          "options" => %{"directory" => Path.join(root, "trace")},
          "order" => 0,
          "lifetime" => "session"
        }
      ]
    }

    {:ok, selected} =
      Ipse.Extensions.Config.resolve(
        [%{scope: "operator", path: "/fixture/trace.json", data: data}],
        []
      )

    {:ok, entries} = Ipse.Extensions.Registry.prepare(selected, config.home)

    config =
      %{config | extensions: entries}
      |> Map.put(:observability, Map.put(Ipse.Observability.Config.defaults(), "mode", "local"))

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
    path = Path.join([root, "trace", sink["resource_id"] <> ".jsonl"])
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
    :ok = Ipse.Observability.Resources.validate(events, id)
  end

  defp drain_trace(_, 0), do: raise("Local trace fixture did not settle")

  defp drain_trace(session, remaining) do
    if Enum.all?(
         Ipse.Session.diagnostics(session)["observability"]["sinks"],
         &(&1["ready"] and &1["pending"] == 0 and &1["delivered"] > 0)
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
          {:ok, event} <- [Ipse.Lifecycle.Event.project(source, record, "metadata")],
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

      {:ok, private} = Ipse.Lifecycle.Event.project(entry.source, entry.record, view)
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
    receive do
      {:ipse_text, server, %{"sequence" => sequence} = frame} when server == handle.server ->
        :ok = Ipse.TextStream.ack(handle, sequence)
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
