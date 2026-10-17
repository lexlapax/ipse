defmodule Ipse.Extensions.FeedsTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal}
  alias Ipse.Extensions.{Feeds, Subscriptions, Store, Manifest, Registry, Config}

  defmodule Model do
    def complete(config, messages, _tools, _emit) do
      send(config.test_pid, {:feed_model, self(), messages})
      first = List.last(messages)["role"] == "user" and config[:delegation_origin] == nil

      if first and config[:gate_model],
        do:
          (receive do
             :release -> :ok
           end)

      calls =
        if first do
          case config[:scenario] do
            :delegate ->
              [
                %{
                  "id" => "private-call",
                  "function" => %{
                    "name" => "delegate",
                    "arguments" =>
                      Jason.encode!(%{
                        "task" => "private child task",
                        "context" => "private context"
                      })
                  }
                }
              ]

            :write ->
              [
                %{
                  "id" => "private-call",
                  "function" => %{
                    "name" => "write",
                    "arguments" =>
                      Jason.encode!(%{"path" => "effect.txt", "content" => "private arguments"})
                  }
                }
              ]

            :extension_question ->
              [
                %{
                  "id" => "private-call",
                  "function" => %{"name" => "ext__feed__clarify", "arguments" => "{}"}
                }
              ]

            :shell ->
              [
                %{
                  "id" => "private-call",
                  "function" => %{
                    "name" => "shell",
                    "arguments" => Jason.encode!(%{"command" => "sleep 30"})
                  }
                }
              ]

            :question ->
              [
                %{
                  "id" => "private-question",
                  "function" => %{
                    "name" => "ask_operator",
                    "arguments" =>
                      Jason.encode!(%{
                        "questions" => [
                          %{"id" => "choice", "kind" => "text", "prompt" => "private question"}
                        ]
                      })
                  }
                }
              ]

            :read ->
              [
                %{
                  "id" => "private-call",
                  "function" => %{
                    "name" => "read",
                    "arguments" => Jason.encode!(%{"path" => "fixture.txt"})
                  }
                }
              ]

            _ ->
              []
          end
        else
          []
        end

      {:ok,
       %{
         "role" => "assistant",
         "content" => "private answer",
         "tool_calls" => calls,
         "provider_data" => %{"native" => "private native continuation"}
       }, %{}}
    end
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-feed-artifacts-#{Ipse.Usage.id()}")

    artifacts =
      for kind <- [:normal, :single, :mixed, :question, :tool_private, :tool_metadata, :child],
          into: %{} do
        events =
          cond do
            kind == :child ->
              ~w(child.started child.finished)

            kind == :normal ->
              ~w(model.admitted wait.started question.waiting turn.finished)

            kind in [:tool_private, :tool_metadata] ->
              ~w(tool.intent_committed tool.outcome_recorded)

            kind == :question ->
              ~w(question.waiting)

            true ->
              ~w(model.admitted)
          end

        declarations =
          for {event, index} <- Enum.with_index(events),
              do: %{
                "id" => "feed#{index}",
                "event" => event,
                "event_version" => 1,
                "view" =>
                  if(kind == :tool_private,
                    do:
                      if(event == "tool.intent_committed", do: "tool.input", else: "tool.result"),
                    else: "metadata"
                  ),
                "mode" => "feed",
                "queue_events" => if(kind == :single, do: 1, else: 8)
              }

        declarations =
          if kind in [:mixed, :question],
            do:
              declarations ++
                [
                  %{
                    "id" => "notify",
                    "event" => "prompt.effective_committed",
                    "event_version" => 1,
                    "view" => "metadata",
                    "mode" => "notify",
                    "required" => true
                  }
                ],
            else: declarations

        declarations =
          if kind == :tool_private do
            declarations ++
              Enum.map(
                declarations,
                &(&1 |> Map.put("id", "meta_" <> &1["id"]) |> Map.put("view", "metadata"))
              )
          else
            declarations
          end

        caps =
          ["event.feed"] ++
            if(kind == :normal, do: ["lifecycle.record"], else: []) ++
            if(kind in [:mixed, :question], do: ["event.notify"], else: []) ++
            if(kind in [:tool_private, :tool_metadata],
              do: ~w(lifecycle.record lifecycle.tools),
              else: []
            ) ++
            if(kind == :tool_private,
              do:
                ~w(event.tool.input event.tool.result invoke.tool invoke.command host.actions host.question host.history host.history.tool.input host.history.tool.result),
              else: []
            )

        exports =
          if kind == :tool_private do
            Ipse.Extensions.Catalog.empty()
            |> Map.put("tools", [
              %{
                "id" => "clarify",
                "description" => "Synthetic tool clarification",
                "arguments_schema" => %{"type" => "object", "additionalProperties" => false},
                "result_schema" => %{"type" => "object"}
              }
            ])
            |> Map.put("commands", [
              %{
                "id" => "catchup",
                "description" => "Synthetic private tool catch-up",
                "arguments_schema" => %{
                  "type" => "object",
                  "additionalProperties" => false,
                  "required" => ["view"],
                  "properties" => %{
                    "view" => %{"type" => "string", "enum" => ~w(tool.input tool.result)}
                  }
                },
                "result_schema" => %{"type" => "object"}
              }
            ])
          else
            Ipse.Extensions.Catalog.empty()
          end

        directory = Path.join(root, Atom.to_string(kind))
        File.mkdir_p!(Path.join(directory, "ebin"))
        module = "Independent.Feed#{System.unique_integer([:positive])}"

        code = """
        defmodule #{module} do
          @behaviour Ipse.Extension
          def describe, do: %{"sdk" => 1, "capabilities" => #{inspect(caps)}, "subscriptions" => #{inspect(declarations)}, "exports" => #{inspect(exports)}}
          def init(options) do
            log(options, %{"initialized" => true})
            {:ok, options}
          end
          def handle("event.feed", payload, state) do
            log(state, payload)
            if state["mode"] == "hang" do
              File.write!(state["pid"], System.pid())
              Process.sleep(:infinity)
            end
            reply = if state["mode"] == "host_call" do
              %{"api_version" => 1, "kind" => "host_call", "request" => %{"op" => "state.put", "key" => "unapproved", "value" => %{}, "expected_revision" => 0}}
            else
              %{"api_version" => 1, "kind" => "ack", "handle" => payload["handle"], "sequence" => payload["sequence"], "event_id" => payload["event"]["event_id"]}
            end
            {:ok, reply, state}
          end
          def handle("event.notify", payload, state) do
            log(state, payload)
            {:ok, %{"api_version" => 1, "kind" => "ack", "delivery_id" => payload["delivery_id"], "event_id" => payload["event"]["event_id"]}, state}
          end
          def handle("invoke.tool", _, state) do
            request = %{"op" => "operator.question", "arguments" => %{"questions" => [%{"id" => "choice", "kind" => "text", "prompt" => "Synthetic tool clarification"}]}, "checkpoint" => %{}}
            {:ok, call(request), state}
          end
          def handle("invoke.command", payload, state), do: read(nil, 0, Map.merge(state, %{"history" => true, "view" => payload["arguments"]["view"], "items" => []}))
          def handle("host.actions", %{"outcome" => %{"status" => "ok", "value" => page}}, %{"history" => true} = state) do
            items = for %{"kind" => "event", "event" => event} <- page["records"], do: event
            state = Map.put(state, "items", state["items"] ++ items)
            if page["next"] == nil do
              {:ok, %{"api_version" => 1, "kind" => "result", "value" => %{"items" => state["items"]}}, state}
            else
              read(page["snapshot"], page["next"], state)
            end
          end
          def handle("host.actions", %{"outcome" => %{"status" => "answered"}}, state), do: {:ok, %{"api_version" => 1, "kind" => "result", "value" => %{"done" => true}}, state}
          defp call(request), do: %{"api_version" => 1, "kind" => "host_call", "request" => request}
          defp read(snapshot, cursor, state), do: {:ok, call(%{"op" => "history.read", "view" => state["view"], "snapshot" => snapshot, "cursor" => cursor, "limit" => 8}), state}
          defp log(state, payload), do: File.write!(state["trace"], Jason.encode!(payload) <> "\\n", [:append])
        end
        """

        file = Path.join(directory, "fixture.ex")
        File.write!(file, code)

        {output, status} =
          System.cmd(
            System.find_executable("elixirc"),
            ["-pa", Application.app_dir(:ipse, "ebin"), "-o", Path.join(directory, "ebin"), file],
            stderr_to_stdout: true
          )

        assert status == 0, output
        File.write!(Path.join(directory, "LICENSE"), "MIT synthetic fixture")

        manifest = %{
          "format" => 1,
          "id" => "fixture/feed",
          "version" => "0.1.0",
          "sdk" => 1,
          "protocol" => 1,
          "backend" => "elixir_worker",
          "entrypoint" => module,
          "license_file" => "LICENSE",
          "capabilities" => caps,
          "subscriptions" => declarations,
          "exports" => exports,
          "options_schema" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ~w(trace pid mode),
            "properties" => Map.new(~w(trace pid mode), &{&1, %{"type" => "string"}})
          },
          "runtime" => %{
            "elixir" => ">= 1.18.0",
            "otp" => [String.to_integer(System.otp_release())],
            "platforms" => [to_string(:erlang.system_info(:system_architecture))]
          },
          "files" =>
            Enum.map(["LICENSE", "ebin/Elixir.#{module}.beam"], fn path ->
              bytes = File.read!(Path.join(directory, path))
              %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Manifest.sha256(bytes)}
            end)
        }

        File.write!(Path.join(directory, "extension.json"), Jason.encode!(manifest))
        {kind, %{directory: directory, manifest: manifest}}
      end

    on_exit(fn -> File.rm_rf!(root) end)
    %{artifacts: artifacts}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-feed-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      root: root,
      home: Path.join(root, "home"),
      dir: Path.join(root, "sessions"),
      trace: Path.join(root, "trace.jsonl"),
      pid_file: Path.join(root, "worker.pid")
    }
  end

  defp config(c, kind, options \\ []) do
    {:ok, artifact} =
      Store.import(c.artifacts[kind].directory, Path.join(c.home, "extensions/artifacts"))

    data = %{
      "extension_trust" => [
        %{
          "artifact" => artifact.digest,
          "capabilities" => artifact.manifest["capabilities"],
          "allow_project" => false,
          "allow_children" => false
        }
      ],
      "extensions" => [
        %{
          "instance" => "feed",
          "artifact" => artifact.digest,
          "enabled" => Keyword.get(options, :enabled, true),
          "options" => %{
            "trace" => c.trace,
            "pid" => c.pid_file,
            "mode" => options[:mode] || "record"
          },
          "order" => 0,
          "lifetime" => "session"
        }
      ]
    }

    {:ok, catalog} =
      Config.resolve([%{scope: "operator", path: "/synthetic/feed.json", data: data}], [])

    {:ok, entries} = Registry.prepare(catalog, c.home)

    %{
      provider: :demo,
      model: "fixture",
      provider_module: Model,
      test_pid: self(),
      home: c.home,
      approval: :ask,
      extensions: entries,
      gate_model: options[:gate],
      scenario: options[:scenario]
    }
  end

  defp start(c, config, id \\ nil, owner \\ nil) do
    result =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: config, cwd: c.root, state_dir: c.dir, id: id, subscriber: self(), owner: owner}
      )

    case result do
      {:ok, pid} -> on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
      _ -> :ok
    end

    result
  end

  defp eventually(fun, attempts \\ 1000)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, n) do
    if fun.(),
      do: :ok,
      else:
        (
          Process.sleep(10)
          eventually(fun, n - 1)
        )
  end

  defp trace(c) do
    if File.exists?(c.trace),
      do: File.read!(c.trace) |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1),
      else: []
  end

  defp rows(c, id), do: elem(Journal.load(c.dir, id), 1)
  defp status(pid), do: Session.diagnostics(pid)["extension_feeds"]
  defp settled(pid), do: Enum.all?(status(pid)["feeds"], &(&1["ready"] and &1["pending"] == 0))
  defp done(pid), do: assert_receive({:ipse, ^pid, {:done, :ok}}, 10_000)
  defp alive?(pid), do: elem(System.cmd("kill", ["-0", pid], stderr_to_stdout: true), 1) == 0

  test "declarations are inert, exact and independent of notification and effect grants" do
    d = %{
      "id" => "model",
      "event" => "model.admitted",
      "event_version" => 1,
      "view" => "metadata",
      "mode" => "feed",
      "queue_events" => 1
    }

    assert :ok = Subscriptions.validate([d], ["event.feed"])

    for bad <- [
          Map.put(d, "event", "*"),
          Map.put(d, "event_version", 2),
          Map.put(d, "required", true),
          Map.put(d, "view", "prompt.original"),
          Map.put(d, "queue_events", 33),
          Map.put(d, "event", "session.resumed")
        ] do
      assert {:error, _} = Subscriptions.validate([bad], ["event.feed"])
    end

    assert {:error, _} = Subscriptions.validate([d], ["event.notify"])
    assert {:error, _} = Subscriptions.validate([], ["event.feed"])
    wait = Map.put(d, "event", "wait.started")
    assert {:error, _} = Subscriptions.validate([wait], ["event.feed"])
    assert :ok = Subscriptions.validate([wait], ~w(event.feed lifecycle.record))
    tool = %{d | "event" => "tool.intent_committed", "view" => "tool.input"}

    assert {:error, _} =
             Subscriptions.validate([tool], ~w(event.feed lifecycle.record lifecycle.tools))

    assert :ok =
             Subscriptions.validate(
               [tool],
               ~w(event.feed lifecycle.record lifecycle.tools event.tool.input)
             )

    assert {:error, _} =
             Ipse.Extensions.Catalog.validate(
               Ipse.Extensions.Catalog.empty(),
               ~w(lifecycle.tools)
             )
  end

  test "private admitted-tool views share stable source IDs with metadata and retain approval",
       c do
    {:ok, pid} = start(c, config(c, :tool_private, scenario: :write))
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "private prompt")
    assert_receive {:ipse, ^pid, {:approval, ref, "write", _}}, 3_000
    refute Enum.any?(rows(c, id), &(&1["type"] == "lifecycle_tool_intent"))
    :ok = Session.approve(pid, ref, true)
    done(pid)
    eventually(fn -> settled(pid) end)
    frames = Enum.filter(trace(c), &Map.has_key?(&1, "handle"))
    assert length(frames) == 4
    input = Enum.find(frames, &(&1["event"]["view"] == "tool.input"))["event"]
    result = Enum.find(frames, &(&1["event"]["view"] == "tool.result"))["event"]
    assert input["data"]["name"] == "write"
    assert Jason.decode!(input["data"]["arguments_json"])["content"] == "private arguments"
    assert is_binary(result["data"]["text"])
    assert input["correlations"]["tool_id"] == result["correlations"]["tool_id"]
    assert input["correlations"]["request_id"] == result["correlations"]["request_id"]
    assert result["correlations"]["causing_event_id"] == input["event_id"]

    metadata =
      Enum.filter(frames, &(&1["event"]["view"] == "metadata")) |> Enum.map(& &1["event"])

    assert Enum.all?(metadata, &Ipse.Lifecycle.Event.valid_metadata?/1)

    assert Enum.sort(Enum.map(metadata, & &1["event_id"])) ==
             Enum.sort([input["event_id"], result["event_id"]])

    refute String.contains?(Jason.encode!(metadata), [
             "private",
             "sha256",
             c.root,
             "arguments_json",
             "proposal_source"
           ])

    refute String.contains?(Jason.encode!([input, result]), [
             "private-call",
             "private native continuation"
           ])

    assert File.read!(Path.join(c.root, "effect.txt")) == "private arguments"
    assert {:ok, _} = Session.restore_context(rows(c, id))
    assert :ok = Subscriptions.validate_sources(c.dir, id, rows(c, id))
    :ok = Session.close(pid)
  end

  test "metadata tool observation alone never receives the private tool payload", c do
    {:ok, pid} = start(c, config(c, :tool_metadata, scenario: :read))
    File.write!(Path.join(c.root, "fixture.txt"), "private file contents")
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "private prompt")
    done(pid)
    eventually(fn -> settled(pid) end)
    frames = Enum.filter(trace(c), &Map.has_key?(&1, "handle"))
    assert length(frames) == 2
    assert Enum.all?(frames, &(&1["event"]["view"] == "metadata"))
    refute String.contains?(Jason.encode!(frames), ["private", "sha256", "fixture.txt"])
    assert {:ok, saved} = Ipse.Lifecycle.Tool.restore(rows(c, id), id)
    assert map_size(saved.tools) == 1
    :ok = Session.close(pid)
  end

  test "reused provider call IDs across requests retain distinct host tool occurrences", c do
    {:ok, pid} = start(c, config(c, :tool_metadata, scenario: :read))
    File.write!(Path.join(c.root, "fixture.txt"), "private data")
    id = Session.info(pid).id

    for prompt <- ["first private prompt", "second private prompt"] do
      :ok = Session.prompt(pid, prompt)
      done(pid)
      eventually(fn -> settled(pid) end)
    end

    starts = Enum.filter(rows(c, id), &(&1["type"] == "lifecycle_tool_intent"))
    assert length(starts) == 2
    assert Enum.uniq_by(starts, & &1["tool_id"]) == starts
    assert Enum.uniq_by(starts, & &1["request_id"]) == starts
    assert {:ok, _} = Session.restore_context(rows(c, id))
    assert :ok = Subscriptions.validate_sources(c.dir, id, rows(c, id))
    :ok = Session.close(pid)
  end

  test "oversized private results close that feed while metadata and native history remain", c do
    File.write!(Path.join(c.root, "fixture.txt"), String.duplicate("private-data ", 1000))
    {:ok, pid} = start(c, config(c, :tool_private, scenario: :read))
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "private prompt")
    done(pid)

    eventually(fn ->
      Enum.any?(status(pid)["feeds"], &(&1["reason"] == "view_unavailable" and &1["closed"]))
    end)

    eventually(fn ->
      Enum.all?(status(pid)["feeds"], &(&1["closed"] or (&1["ready"] and &1["pending"] == 0)))
    end)

    [outcome] = Enum.filter(rows(c, id), &(&1["type"] == "lifecycle_tool_outcome"))
    assert outcome["result"] == nil and outcome["result_bytes"] > 8192

    assert Enum.any?(
             trace(c),
             &(get_in(&1, ["event", "type"]) == "tool.outcome_recorded" and
                 get_in(&1, ["event", "view"]) == "metadata")
           )

    assert {:ok, messages} = Session.restore_context(rows(c, id))
    assert Enum.any?(messages, &(&1["role"] == "tool" and byte_size(&1["content"]) > 8192))
    assert :ok = Subscriptions.validate_sources(c.dir, id, rows(c, id))
    :ok = Session.close(pid)
  end

  test "an extension-tool question preserves its tool ID across restart without inventing elapsed downtime",
       c do
    cfg = config(c, :tool_private, scenario: :extension_question)
    {:ok, pid} = start(c, cfg)
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "private prompt")
    assert_receive {:feed_model, _, _}, 3_000
    assert_receive {:ipse, ^pid, {:approval, ref, "ext__feed__clarify", _}}, 3_000
    :ok = Session.approve(pid, ref, true)
    assert_receive {:ipse, ^pid, {:question, question, _}}, 3_000
    eventually(fn -> settled(pid) end)
    [intent] = Enum.filter(rows(c, id), &(&1["type"] == "lifecycle_tool_intent"))
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 2_000
    old = File.read!(c.trace)
    {:ok, resumed} = resume(c, cfg, id)
    assert_receive {:ipse, ^resumed, {:question, ^question, _}}, 3_000
    assert File.read!(c.trace) == old
    refute_receive {:feed_model, _, _}, 50
    :ok = Session.answer(resumed, question, %{"choice" => "continue"})
    done(resumed)
    eventually(fn -> settled(resumed) end)
    [outcome] = Enum.filter(rows(c, id), &(&1["type"] == "lifecycle_tool_outcome"))
    assert outcome["tool_id"] == intent["tool_id"]
    assert outcome["request_id"] == intent["request_id"]
    refute outcome["epoch_id"] == intent["epoch_id"]
    assert outcome["duration_ms"] == nil
    assert {:ok, _} = Session.restore_context(rows(c, id))
    assert :ok = Subscriptions.validate_sources(c.dir, id, rows(c, id))
    :ok = Session.close(resumed)
  end

  test "explicit history reads require historical grants and retain the selected structured tool view",
       c do
    {:ok, pid} = start(c, config(c, :tool_private, scenario: :read))
    File.write!(Path.join(c.root, "fixture.txt"), "private historical content")
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "private prompt")
    done(pid)
    eventually(fn -> settled(pid) end)
    live = Enum.filter(trace(c), &Map.has_key?(&1, "handle"))

    for view <- ~w(tool.input tool.result) do
      assert Ipse.Extensions.History.capability(%{"view" => view}) == "host.history." <> view
      :ok = Session.invoke_export(pid, :command, "ext__feed__catchup", %{"view" => view})
      done(pid)
      assert [%{"view" => ^view} = event] = Session.info(pid).extension_result["value"]["items"]
      original = Enum.find(live, &(&1["event"]["view"] == view))["event"]
      assert event == original
    end

    assert {:ok, _} = Session.restore_context(rows(c, id))
    assert :ok = Subscriptions.validate_sources(c.dir, id, rows(c, id))
    :ok = Session.close(pid)
  end

  test "metadata feeds start on explicit work, preserve source identity and do not approve tools",
       c do
    {:ok, pid} = start(c, config(c, :normal, scenario: :write))
    id = Session.info(pid).id
    refute File.exists?(c.trace)
    assert status(pid)["enrolled"] == false
    :ok = Session.prompt(pid, "private prompt")
    assert_receive {:ipse, ^pid, {:approval, ref, "write", _}}, 3_000
    refute File.exists?(Path.join(c.root, "effect.txt"))
    :ok = Session.approve(pid, ref, false)
    done(pid)
    eventually(fn -> settled(pid) end)
    frames = Enum.filter(trace(c), &Map.has_key?(&1, "handle"))

    assert Enum.map(frames, & &1["event"]["type"]) |> Enum.sort() ==
             ~w(model.admitted model.admitted turn.finished wait.started)

    refute String.contains?(Jason.encode!(frames), ["private", "sha256", c.root])
    all = rows(c, id)
    assert {:ok, _} = Session.restore_context(all)
    assert :ok = Subscriptions.validate_sources(c.dir, id, all)
    assert Enum.count(all, &(&1["type"] == "extension_feed_delivery_intent")) == 4
    assert Enum.count(all, &(&1["type"] == "extension_feed_delivery_result")) == 4

    for frame <- frames do
      source = frame["event"]["source"]

      assert {:ok, %{records: [%{source: actual}]}} =
               Journal.source_page(c.dir, id, source["byte_offset"], 1)

      assert source["event_id"] == actual["event_id"]
      assert frame["after"]["byte_offset"] < source["byte_offset"]
    end

    :ok = Session.close(pid)
    assert {:ok, saved} = Feeds.validate(rows(c, id), id)
    assert Enum.all?(saved.resources, fn {_, r} -> r.closed end)
  end

  test "queue pressure closes incomplete coverage and stops the blocked owned VM", c do
    {:ok, pid} = start(c, config(c, :single, scenario: :write, gate: true, mode: "hang"))
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "private prompt")
    assert_receive {:feed_model, model, _}, 3_000
    eventually(fn -> File.exists?(c.pid_file) end)
    worker = File.read!(c.pid_file)
    send(model, :release)
    assert_receive {:ipse, ^pid, {:approval, ref, "write", _}}, 3_000
    :ok = Session.approve(pid, ref, false)
    done(pid)
    eventually(fn -> match?([%{"closed" => true}], status(pid)["feeds"]) end)
    [feed] = status(pid)["feeds"]
    assert feed["reason"] == "capacity" and feed["admitted"] == 1 and feed["acknowledged"] == 0
    eventually(fn -> not alive?(worker) end)
    closed = Enum.find(rows(c, id), &(&1["type"] == "extension_feed_closed"))
    assert Ipse.Lifecycle.Source.valid?(closed["gap_source"])
    assert :ok = Subscriptions.validate_sources(c.dir, id, rows(c, id))
    :ok = Session.close(pid)
  end

  test "invalid effect replies stop a feed while the agent remains usable", c do
    {:ok, pid} = start(c, config(c, :single, gate: true, mode: "host_call"))
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "private prompt")
    assert_receive {:feed_model, model, _}, 3_000
    eventually(fn -> match?([%{"closed" => true}], status(pid)["feeds"]) end)
    [feed] = status(pid)["feeds"]
    assert feed["reason"] == "callback_failed"
    refute Enum.any?(rows(c, id), &(&1["type"] == "extension_action_intent"))
    send(model, :release)
    done(pid)
    :ok = Session.close(pid)
    assert {:ok, _} = Session.restore_context(rows(c, id))
  end

  test "callback deadline retains unconfirmed cleanup without failing successful inference", c do
    {:ok, pid} = start(c, config(c, :single, gate: true, mode: "hang"))
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "private prompt")
    assert_receive {:feed_model, model, _}, 3_000
    eventually(fn -> File.exists?(c.pid_file) end)
    worker = File.read!(c.pid_file)
    eventually(fn -> match?([%{"closed" => true}], status(pid)["feeds"]) end)
    [feed] = status(pid)["feeds"]
    assert feed["reason"] == "callback_failed" and feed["cleanup_confirmed"] == false
    eventually(fn -> not alive?(worker) end)
    assert Process.alive?(model)
    send(model, :release)
    done(pid)
    assert {:error, :cleanup_unconfirmed} = Session.close(pid)
    assert {:ok, saved} = Ipse.Diagnostics.saved(c.dir, id)
    assert saved["event_feeds"]["unconfirmed_cleanup"] == 1
    assert saved["event_feeds"]["unacknowledged"] == 1
  end

  test "notifications and feeds coexist without changing the barrier contract", c do
    {:ok, pid} = start(c, config(c, :mixed))
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "private prompt")
    done(pid)
    eventually(fn -> settled(pid) end)
    assert Enum.any?(trace(c), &Map.has_key?(&1, "delivery_id"))
    assert Enum.any?(trace(c), &Map.has_key?(&1, "handle"))
    :ok = Session.close(pid)
    assert {:ok, _} = Session.restore_context(rows(c, id))
    assert :ok = Subscriptions.validate_sources(c.dir, id, rows(c, id))
  end

  test "explicit stop and idle resume never replay or restart feed callbacks", c do
    cfg = config(c, :single)
    {:ok, pid} = start(c, cfg)
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "first private prompt")
    done(pid)
    eventually(fn -> settled(pid) end)
    :ok = Session.stop_feeds(pid)
    old = File.read!(c.trace)
    :ok = Session.prompt(pid, "second private prompt")
    done(pid)
    assert File.read!(c.trace) == old
    :ok = Session.close(pid)
    bytes = File.read!(Path.join(c.dir, id <> ".jsonl"))
    {:ok, resumed} = start(c, cfg, id)
    assert status(resumed)["enrolled"] == false
    assert File.read!(c.trace) == old
    assert File.read!(Path.join(c.dir, id <> ".jsonl")) == bytes
    :ok = Session.prompt(resumed, "third private prompt")
    done(resumed)
    eventually(fn -> settled(resumed) end)
    assert length(trace(c)) == length(String.split(old, "\n", trim: true)) + 2
    :ok = Session.close(resumed)
    assert {:ok, _} = Session.restore_context(rows(c, id))
  end

  test "child completion feeds preserve source identity and omit task/result content", c do
    cfg =
      config(c, :child, scenario: :delegate)
      |> Map.put(:subagents, true)
      |> Map.put(:approval, :allow)

    {:ok, pid} = start(c, cfg)
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "private prompt")
    done(pid)
    eventually(fn -> settled(pid) end)
    frames = Enum.filter(trace(c), &Map.has_key?(&1, "handle"))
    assert Enum.sort(Enum.map(frames, & &1["event"]["type"])) == ~w(child.finished child.started)
    completed = Enum.find(frames, &(&1["event"]["type"] == "child.finished"))["event"]
    started = Enum.find(frames, &(&1["event"]["type"] == "child.started"))["event"]
    assert completed["correlations"]["child_id"] == started["correlations"]["child_id"]
    assert completed["correlations"]["causing_event_id"] == started["event_id"]
    assert completed["data"]["status"] == "result_recorded"
    assert completed["data"]["cleanup_confirmed"]
    refute Jason.encode!(frames) =~ "private"
    assert :ok = Subscriptions.validate_sources(c.dir, id, rows(c, id))
    :ok = Session.close(pid)
    old = trace(c)
    {:ok, resumed} = resume(c, cfg, id)
    assert trace(c) == old
    assert status(resumed)["feeds"] == []
    :ok = Session.close(resumed)
  end

  test "disabled selections execute no worker and create no feed lease", c do
    {:ok, pid} = start(c, config(c, :single, enabled: false))
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "private prompt")
    done(pid)
    refute File.exists?(c.trace)
    assert Enum.all?(rows(c, id), &(&1["type"] not in Feeds.record_types()))
    :ok = Session.close(pid)
  end

  test "denied calls create no admitted-tool occurrence or private execution input", c do
    cfg = config(c, :tool_metadata, scenario: :write) |> Map.put(:approval, :deny)
    {:ok, pid} = start(c, cfg)
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "private prompt")
    done(pid)
    eventually(fn -> settled(pid) end)

    refute Enum.any?(
             rows(c, id),
             &(&1["type"] in ~w(lifecycle_tool_intent lifecycle_tool_outcome))
           )

    refute Enum.any?(trace(c), &Map.has_key?(&1, "handle"))
    refute File.exists?(Path.join(c.root, "effect.txt"))
    :ok = Session.close(pid)
  end

  test "cancel records an admitted tool's unknown outcome without replay on idle resume", c do
    cfg = config(c, :tool_metadata, scenario: :shell)
    {:ok, pid} = start(c, cfg)
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "private prompt")
    assert_receive {:ipse, ^pid, {:approval, ref, "shell", _}}, 3_000
    :ok = Session.approve(pid, ref, true)
    assert_receive {:ipse, ^pid, {:tool, "shell", _}}, 3_000
    :ok = Session.cancel(pid)
    [outcome] = Enum.filter(rows(c, id), &(&1["type"] == "lifecycle_tool_outcome"))
    assert outcome["status"] == "unknown"
    assert {:ok, _} = Session.restore_context(rows(c, id))
    :ok = Session.close(pid)
    old = trace(c)
    {:ok, resumed} = resume(c, cfg, id)
    assert Session.info(resumed).phase == :idle
    assert trace(c) == old
    assert status(resumed)["feeds"] == []
    :ok = Session.close(resumed)
    assert :ok = Subscriptions.validate_sources(c.dir, id, rows(c, id))
  end

  test "coherent tool source-position forgery refuses resume before tail repair", c do
    cfg = config(c, :tool_metadata, scenario: :read)
    File.write!(Path.join(c.root, "fixture.txt"), "private result")
    {:ok, pid} = start(c, cfg)
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "private prompt")
    done(pid)
    eventually(fn -> settled(pid) end)
    :ok = Session.close(pid)
    events = rows(c, id)
    intent = Enum.find(events, &(&1["type"] == "lifecycle_tool_intent"))
    outcome = Enum.find(events, &(&1["type"] == "lifecycle_tool_outcome"))

    {:ok, %{records: [%{record: legacy}]}} =
      Journal.source_page(c.dir, id, intent["intent_source"]["byte_offset"], 1)

    {:ok, wrong} =
      Ipse.Lifecycle.Source.build(id, intent["intent_source"]["byte_offset"] + 1, legacy)

    forged_intent = Map.put(intent, "intent_source", wrong)

    {:ok, forged_source} =
      Ipse.Lifecycle.Source.build(id, outcome["tool_source"]["byte_offset"], forged_intent)

    forged_outcome = Map.put(outcome, "tool_source", forged_source)

    forged =
      Enum.map(events, fn e ->
        cond do
          e == intent -> forged_intent
          e == outcome -> forged_outcome
          true -> e
        end
      end)

    assert {:ok, _} = Session.restore_context(forged)
    path = Path.join(c.dir, id <> ".jsonl")
    contents = Enum.map_join(forged, "\n", &Jason.encode!/1) <> "\n{"
    File.write!(path, contents)
    assert {:error, :invalid_tool_lifecycle} = resume(c, cfg, id)
    assert File.read!(path) == contents
  end

  defp resume(c, cfg, id, attempts \\ 100) do
    case start(c, cfg, id) do
      {:error, :session_locked} when attempts > 0 ->
        Process.sleep(10)
        resume(c, cfg, id, attempts - 1)

      result ->
        result
    end
  end

  test "question checkpoints stay adjacent and explicit answer starts a fresh feed without replay",
       c do
    cfg = config(c, :question, scenario: :question)
    {:ok, pid} = start(c, cfg)
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "private prompt")
    assert_receive {:ipse, ^pid, {:question, question, _}}, 3_000
    eventually(fn -> settled(pid) end)
    events = rows(c, id)
    index = Enum.find_index(events, &(&1["type"] == "operator_question"))
    assert Enum.at(events, index + 1)["type"] == "lifecycle_question_sources"
    assert {:ok, _} = Session.restore_context(events)
    assert :ok = Subscriptions.validate_sources(c.dir, id, events)
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 2_000
    old = File.read!(c.trace)
    bytes = File.read!(Path.join(c.dir, id <> ".jsonl"))
    {:ok, resumed} = resume(c, cfg, id)
    assert_receive {:ipse, ^resumed, {:question, ^question, _}}, 3_000
    assert File.read!(c.trace) == old
    assert File.read!(Path.join(c.dir, id <> ".jsonl")) == bytes
    assert {:error, :invalid_answer} = Session.answer(resumed, question, %{})
    assert status(resumed)["enrolled"] == false
    :ok = Session.answer(resumed, question, %{"choice" => "explicit private answer"})
    done(resumed)
    eventually(fn -> settled(resumed) end)
    frames = Enum.filter(trace(c), &Map.has_key?(&1, "handle"))
    assert length(frames) == 1
    assert hd(frames)["event"]["type"] == "question.waiting"
    :ok = Session.close(resumed)
    assert {:ok, _} = Session.restore_context(rows(c, id))
    assert :ok = Subscriptions.validate_sources(c.dir, id, rows(c, id))
  end

  test "cancellation interrupts a blocked feed independently of inference and preserves unknown deliveries",
       c do
    {:ok, pid} = start(c, config(c, :single, gate: true, mode: "hang"))
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "private prompt")
    assert_receive {:feed_model, model, _}, 3_000
    eventually(fn -> File.exists?(c.pid_file) end)
    worker = File.read!(c.pid_file)
    :ok = Session.cancel(pid)
    assert Session.info(pid).phase == :idle
    eventually(fn -> not Process.alive?(model) and not alive?(worker) end)
    [feed] = status(pid)["feeds"]
    assert feed["closed"] and feed["reason"] == "cancelled"
    assert feed["admitted"] == 1 and feed["acknowledged"] == 0
    :ok = Session.close(pid)
    assert {:ok, _} = Session.restore_context(rows(c, id))
  end

  test "owner death closes a blocked feed and idle resume starts no VM or model", c do
    cfg = config(c, :single, gate: true, mode: "hang")

    owner =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    {:ok, pid} = start(c, cfg, nil, owner)
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "private prompt")
    assert_receive {:feed_model, model, _}, 3_000
    eventually(fn -> File.exists?(c.pid_file) end)
    worker = File.read!(c.pid_file)
    ref = Process.monitor(pid)
    send(owner, :stop)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000
    eventually(fn -> not Process.alive?(model) and not alive?(worker) end)
    old = File.read!(c.trace)
    closed = Enum.find(rows(c, id), &(&1["type"] == "extension_feed_closed"))
    assert closed["reason"] == "consumer_down"
    {:ok, resumed} = resume(c, cfg, id)
    assert status(resumed)["feeds"] == []
    assert File.read!(c.trace) == old
    refute_receive {:feed_model, _, _}, 50
    :ok = Session.close(resumed)
    assert :ok = Subscriptions.validate_sources(c.dir, id, rows(c, id))
  end

  test "a coherently altered callback receipt refuses physical validation before repair", c do
    cfg = config(c, :single)
    {:ok, pid} = start(c, cfg)
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "private prompt")
    done(pid)
    eventually(fn -> settled(pid) end)
    :ok = Session.close(pid)
    original = rows(c, id)
    intent = Enum.find(original, &(&1["type"] == "extension_feed_delivery_intent"))
    forged_intent = Map.put(intent, "payload_sha256", String.duplicate("0", 64))

    forged =
      Enum.map(original, fn
        ^intent -> forged_intent
        %{"type" => "extension_feed_delivery_result"} -> Feeds.result(forged_intent)
        event -> event
      end)

    assert {:ok, _} = Session.restore_context(forged)
    assert {:error, :invalid_extension_feed} = Subscriptions.validate_sources(c.dir, id, forged)
    path = Path.join(c.dir, id <> ".jsonl")
    contents = Enum.map_join(forged, "\n", &Jason.encode!/1) <> "\n{"
    File.write!(path, contents)
    assert {:error, :invalid_extension_feed} = resume(c, cfg, id)
    assert File.read!(path) == contents
  end

  test "the admission ceiling spans leases and malformed sequence/closure claims refuse", c do
    {:ok, pid} = start(c, config(c, :single))
    id = Session.info(pid).id
    :ok = Session.prompt(pid, "private prompt")
    done(pid)
    eventually(fn -> settled(pid) end)
    events = rows(c, id)
    header = hd(events)
    lease = Enum.find(events, &(&1["type"] == "extension_feed_intent"))
    delivery = Enum.find(events, &(&1["type"] == "extension_feed_delivery_intent"))
    # Pure receipt-bound checks; these generated positions are not physical source authority.
    source_record = %{"type" => "synthetic"}

    deliveries =
      Enum.flat_map(1..Feeds.limit(), fn i ->
        {:ok, source} = Ipse.Lifecycle.Source.build(id, 1_000_000 + i, source_record)
        d = %{delivery | "sequence" => i, "source" => source}
        [d, Feeds.result(d)]
      end)

    history = [header, lease, Feeds.ready(lease)] ++ deliveries
    assert {:ok, %{deliveries: 10_000}} = Feeds.validate(history, id)
    another = Map.put(lease, "resource_id", Ipse.Usage.id())
    next = %{delivery | "resource_id" => another["resource_id"]}
    assert {:error, _} = Feeds.validate(history ++ [another, next], id)

    assert {:error, _} =
             Feeds.validate(
               [
                 header,
                 lease,
                 Feeds.ready(lease),
                 delivery,
                 Map.put(Feeds.result(delivery), "sequence", 2)
               ],
               id
             )

    :ok = Session.close(pid)
  end
end
