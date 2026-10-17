defmodule Ipse.Extensions.EventJobTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal}
  alias Ipse.Extensions.{Catalog, Config, Registry, Store, Manifest, Subscriptions, Actions}

  defmodule Model do
    def complete(config, messages, _tools, emit) do
      send(config.test_pid, {:job_model, messages})
      emit.({:text, "answer"})

      {:ok,
       %{
         "role" => "assistant",
         "content" => "answer",
         "provider_data" => %{"native" => "synthetic-native-secret"}
       }, %{}}
    end
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-job-artifacts-#{Ipse.Usage.id()}")

    artifacts =
      for {kind, schedule, private, event} <- [
            {:before, "before_request", true, "prompt.effective_committed"},
            {:after, "after_turn", true, "prompt.effective_committed"},
            {:metadata, "before_request", false, "prompt.effective_committed"},
            {:answer, "after_turn", true, "answer.committed"}
          ],
          into: %{} do
        declaration = %{
          "id" => "maintain",
          "handler" => "maintain",
          "event" => event,
          "event_version" => 1,
          "view" =>
            if(private,
              do: if(kind == :answer, do: "answer.presented", else: "prompt.effective"),
              else: "metadata"
            ),
          "mode" => "job",
          "schedule" => schedule,
          "required" => schedule == "before_request"
        }

        capabilities =
          ~w(event.job invoke.command host.actions host.state.read host.state.write host.context host.question) ++
            if(private,
              do: [
                if(kind == :answer, do: "event.answer.presented", else: "event.prompt.effective")
              ],
              else: []
            )

        result = %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["status"],
          "properties" => %{"status" => %{"type" => "string"}}
        }

        job = %{
          "id" => "maintain",
          "description" => "Synthetic event maintenance",
          "arguments_schema" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["event"],
            "properties" => %{"event" => %{"type" => "object"}}
          },
          "result_schema" => result
        }

        command = %{
          "id" => "forget",
          "description" => "Synthetic scoped forget",
          "arguments_schema" => %{"type" => "object", "additionalProperties" => false},
          "result_schema" => result
        }

        exports = Catalog.empty() |> Map.put("jobs", [job]) |> Map.put("commands", [command])
        directory = Path.join(root, Atom.to_string(kind))
        File.mkdir_p!(Path.join(directory, "ebin"))
        module = "Independent.EventJob#{System.unique_integer([:positive])}"

        code = """
        defmodule #{module} do
          @behaviour Ipse.Extension
          def describe, do: %{"sdk" => 1, "capabilities" => #{inspect(capabilities)}, "exports" => #{inspect(exports)}, "subscriptions" => [#{inspect(declaration)}]}
          def init(options) do
            log(options, %{"initialized" => true})
            {:ok, options}
          end
          def handle("event.job", payload, state) do
            log(state, payload)
            event = payload["arguments"]["event"]["event"]
            state = Map.merge(state, %{"text" => event["data"]["text"] || "metadata counts", "event_id" => event["event_id"], "phase" => "read"})
            if state["mode"] == "question" do
              request = %{"op" => "operator.question", "arguments" => %{"questions" => [%{"id" => "proceed", "prompt" => "Choose maintenance scope", "kind" => "single", "options" => [%{"id" => "yes", "label" => "Proceed"}, %{"id" => "no", "label" => "Stop"}]}]},
                "checkpoint" => Map.take(state, ["text", "event_id", "phase"])}
              {:ok, call(request), state}
            else
              {:ok, call(get()), state}
            end
          end
          def handle("invoke.command", _payload, state), do: {:ok, call(get()), Map.put(state, "phase", "delete_read")}
          def handle("host.actions", %{"outcome" => %{"status" => "answered"}, "checkpoint" => checkpoint}, state),
            do: {:ok, call(get()), Map.merge(state, checkpoint)}
          def handle("host.actions", payload, %{"phase" => "delete_read"} = state) do
            revision = payload["outcome"]["value"]["record"]["revision"]
            {:ok, call(%{"op" => "state.delete", "scope" => "project", "key" => "memory", "expected_revision" => revision}), Map.put(state, "phase", "done")}
          end
          def handle("host.actions", payload, %{"phase" => "read", "mode" => "recall"} = state) do
            record = payload["outcome"]["value"]["record"]
            items = if record["value"] do
              [%{"id" => "memory", "version" => Integer.to_string(record["revision"]), "text" => record["value"]["text"], "priority" => 20,
                "source" => %{"kind" => "receipt", "operation_id" => payload["operation_id"], "path" => ["record", "value", "text"]}}]
            else
              []
            end
            {:ok, call(%{"op" => "context.publish", "items" => items}), Map.put(state, "phase", "done")}
          end
          def handle("host.actions", payload, %{"phase" => "read"} = state) do
            if state["mode"] == "hold_before_write" do
              File.write!(state["pid"], System.pid())
              wait(state["gate"])
            end
            revision = payload["outcome"]["value"]["record"]["revision"]
            value = %{"text" => state["text"], "entities" => String.split(state["text"]), "source_event_id" => state["event_id"]}
            {:ok, call(%{"op" => "state.put", "scope" => "project", "key" => "memory", "expected_revision" => revision, "value" => value}), Map.put(state, "phase", "done")}
          end
          def handle("host.actions", payload, %{"phase" => "done"} = state) do
            if state["mode"] == "hang_after_write" do
              File.write!(state["pid"], System.pid())
              Process.sleep(:infinity)
            end
          status = if state["mode"] == "misreport", do: "ok", else: payload["outcome"]["status"]
          {:ok, %{"api_version" => 1, "kind" => "result", "value" => %{"status" => status}}, state}
          end
          defp get, do: %{"op" => "state.get", "scope" => "project", "key" => "memory"}
          defp call(request), do: %{"api_version" => 1, "kind" => "host_call", "request" => request}
          defp log(state, payload), do: File.write!(state["trace"], Jason.encode!(payload) <> "\n", [:append])
          defp wait(path) do
            unless File.exists?(path) do
              Process.sleep(10)
              wait(path)
            end
          end
        end
        """

        file = Path.join(root, "#{kind}.ex")
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
          "id" => "fixture/event-job",
          "version" => "0.1.0",
          "sdk" => 1,
          "protocol" => 1,
          "backend" => "elixir_worker",
          "entrypoint" => module,
          "license_file" => "LICENSE",
          "capabilities" => capabilities,
          "exports" => exports,
          "subscriptions" => [declaration],
          "options_schema" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ~w(mode trace pid gate),
            "properties" => Map.new(~w(mode trace pid gate), &{&1, %{"type" => "string"}})
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
    root = Path.join(System.tmp_dir!(), "ipse-event-job-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      root: root,
      home: Path.join(root, "home"),
      dir: Path.join(root, "sessions"),
      trace: Path.join(root, "trace.jsonl"),
      pid_file: Path.join(root, "worker.pid"),
      gate: Path.join(root, "gate")
    }
  end

  defp config(c, kind, mode, approval \\ :allow) do
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
          "instance" => "graph",
          "artifact" => artifact.digest,
          "enabled" => true,
          "options" => %{
            "mode" => mode,
            "trace" => c.trace,
            "pid" => c.pid_file,
            "gate" => c.gate
          },
          "order" => 0,
          "lifetime" => "session"
        }
      ]
    }

    {:ok, catalog} =
      Config.resolve([%{scope: "operator", path: "/synthetic/graph.json", data: data}], [])

    {:ok, entries} = Registry.prepare(catalog, c.home)

    %{
      provider: :demo,
      model: "fixture",
      provider_module: Model,
      test_pid: self(),
      home: c.home,
      approval: approval,
      extensions: entries,
      context_bytes: 65_536,
      max_steps: 3
    }
  end

  defp start(c, config, id \\ nil),
    do:
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, [config: config, cwd: c.root, state_dir: c.dir, subscriber: self(), id: id]}
      )

  defp done(pid, status), do: assert_receive({:ipse, ^pid, {:done, ^status}}, 15_000)
  defp events(c, pid), do: elem(Journal.load(c.dir, Session.info(pid).id), 1)

  defp puts(events),
    do:
      Enum.filter(
        events,
        &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "state.put")
      )

  defp eventually(fun, attempts \\ 300)
  defp eventually(fun, 0), do: assert(fun.())

  defp eventually(fun, attempts),
    do:
      if(fun.(),
        do: :ok,
        else:
          (
            Process.sleep(10)
            eventually(fun, attempts - 1)
          )
      )

  test "event jobs retain full mutation approval and source provenance", c do
    {:ok, pid} = start(c, config(c, :before, "write", :ask))
    :ok = Session.prompt(pid, "Meridian Graph")
    assert_receive {:ipse, ^pid, {:approval, ref, "extension:state.put", arguments}}, 10_000
    assert arguments["request"]["value"]["entities"] == ["Meridian", "Graph"]
    refute_receive {:job_model, _}, 100
    :ok = Session.approve(pid, ref, true)
    done(pid, :ok)
    [put] = puts(events(c, pid))
    assert put["approval"] == "approved" and put["outcome"]["status"] == "ok"
    [parent] = Enum.filter(events(c, pid), &(&1["type"] == "extension_invocation_intent"))
    assert parent["approval"] == "event_trigger"
    assert parent["event_trigger"]["event_id"] == put["request"]["value"]["source_event_id"]
    assert Subscriptions.validate_events(events(c, pid)) == :ok
    assert Actions.validate_events(events(c, pid)) == :ok

    assert {:ok, %{records: records, next: nil}} =
             Journal.source_page(c.dir, Session.info(pid).id, 0, 64)

    parent_record = Enum.find(records, &(&1.record == parent))

    assert {:ok, metadata} =
             Ipse.Lifecycle.Event.project(parent_record.source, parent, "metadata")

    assert metadata["correlations"]["causing_event_id"] == parent["event_trigger"]["event_id"]
    assert metadata["correlations"]["delivery_id"] == parent["event_trigger"]["delivery_id"]
    assert metadata["correlations"]["invocation_id"] == parent["invocation_id"]

    refute String.contains?(Jason.encode!(metadata), [
             "Meridian",
             "record_sha256",
             "intent_sha256"
           ])

    assert {:error, _} = Session.invoke_export(pid, :job, "ext__graph__maintain", %{})
    :ok = Session.close(pid)
  end

  test "answer jobs store only their selected answer after inference with separate approval", c do
    {:ok, pid} = start(c, config(c, :answer, "write", :ask))
    :ok = Session.prompt(pid, "This prompt must not become the saved answer")
    assert_receive {:job_model, _}, 10_000
    assert_receive {:ipse, ^pid, {:approval, ref, "extension:state.put", arguments}}, 10_000
    assert arguments["request"]["value"]["text"] == "answer"
    :ok = Session.approve(pid, ref, true)
    done(pid, :ok)
    rows = events(c, pid)
    delivery = Enum.find(rows, &(&1["type"] == "extension_event_intent"))
    parent = Enum.find(rows, &(&1["type"] == "extension_invocation_intent"))
    answer = Enum.find(rows, &(&1["type"] == "lifecycle_answer_committed"))
    assert parent["event_trigger"]["event_id"] == delivery["source"]["event_id"]
    assert parent["event_trigger"]["sources"]["answer"] == delivery["source"]
    assert parent["event_trigger"]["sources"]["effective"] == answer["effective_source"]
    assert Subscriptions.validate_events(rows) == :ok
    assert Subscriptions.validate_sources(c.dir, Session.info(pid).id, rows) == :ok
    assert Session.info(pid).final == "answer"
    :ok = Session.close(pid)
  end

  test "headless denial stays denied, never inherited from the subscription", c do
    {:ok, pid} = start(c, config(c, :before, "write", :deny))
    :ok = Session.prompt(pid, "denied entities")
    done(pid, :error)
    refute_receive {:job_model, _}, 100
    [put] = puts(events(c, pid))
    assert put["approval"] == "denied" and put["outcome"]["status"] == "denied"

    assert Enum.find(events(c, pid), &(&1["type"] == "extension_invocation_result"))["value"] ==
             %{"status" => "denied"}

    :ok = Session.close(pid)
  end

  test "awaited recall publishes an attributed snapshot before inference", c do
    {:ok, writer} = start(c, config(c, :before, "write"))
    :ok = Session.prompt(writer, "Meridian retained fact")
    done(writer, :ok)
    :ok = Session.close(writer)
    assert_receive {:job_model, _}
    {:ok, reader} = start(c, config(c, :before, "recall"))
    :ok = Session.prompt(reader, "Recall memory")
    done(reader, :ok)
    assert_receive {:job_model, [system | _]}
    assert String.contains?(system["content"], "Meridian retained fact")
    assert Enum.any?(events(c, reader), &(&1["type"] == "extension_context_snapshot"))
    assert Subscriptions.validate_events(events(c, reader)) == :ok
    :ok = Session.close(reader)
  end

  test "after-turn indexing cannot change the admitted answer and runs before settlement", c do
    {:ok, pid} = start(c, config(c, :after, "write"))
    :ok = Session.prompt(pid, "after-turn entities")
    assert_receive {:job_model, [system | _]}, 10_000
    refute String.contains?(system["content"], "memory")
    done(pid, :ok)
    history = events(c, pid)
    order = Enum.map(history, & &1["type"])

    assert Enum.find_index(order, &(&1 == "request_finished")) <
             Enum.find_index(order, &(&1 == "extension_event_intent"))

    assert Enum.find_index(order, &(&1 == "lifecycle_turn_settling")) <
             Enum.find_index(order, &(&1 == "extension_event_intent"))

    assert Enum.find_index(order, &(&1 == "extension_event_result")) <
             Enum.find_index(order, &(&1 == "turn_finished"))

    assert Session.info(pid).final == "answer"
    assert Subscriptions.validate_events(history) == :ok
    :ok = Session.close(pid)
  end

  test "a callback cannot relabel a denied effect as successful", c do
    {:ok, pid} = start(c, config(c, :before, "misreport", :deny))
    :ok = Session.prompt(pid, "denied but misreported")
    done(pid, :error)
    history = events(c, pid)

    assert Enum.find(history, &(&1["type"] == "extension_invocation_result"))["value"] == %{
             "status" => "ok"
           }

    assert Enum.find(history, &(&1["type"] == "extension_event_result"))["outcome"] == "failed"
    assert hd(puts(history))["outcome"]["status"] == "denied"
    assert Subscriptions.validate_events(history) == :ok
    refute_receive {:job_model, _}, 100
    :ok = Session.close(pid)
  end

  test "after-turn context publication is visible only at a later request boundary", c do
    {:ok, writer} = start(c, config(c, :after, "write"))
    :ok = Session.prompt(writer, "after stored evidence")
    done(writer, :ok)
    assert_receive {:job_model, _}
    :ok = Session.close(writer)
    {:ok, reader} = start(c, config(c, :after, "recall"))
    :ok = Session.prompt(reader, "first request")
    done(reader, :ok)
    assert_receive {:job_model, [first | _]}
    refute String.contains?(first["content"], "after stored evidence")
    :ok = Session.prompt(reader, "later request")
    done(reader, :ok)
    assert_receive {:job_model, [later | _]}
    assert String.contains?(later["content"], "after stored evidence")
    assert Enum.count(events(c, reader), &(&1["type"] == "extension_context_snapshot")) == 1
    assert Subscriptions.validate_events(events(c, reader)) == :ok
    :ok = Session.close(reader)
  end

  test "structured feedback resumes only the paused job with separate write approval", c do
    for schedule <- [:before, :after, :answer] do
      config = config(c, schedule, "question", :ask)
      {:ok, pid} = start(c, config)
      :ok = Session.prompt(pid, "Question provenance")
      assert_receive {:ipse, ^pid, {:question, question, _}}, 10_000
      id = Session.info(pid).id
      Process.exit(pid, :kill)
      eventually(fn -> not Process.alive?(pid) end)
      {:ok, resumed} = start(c, config, id)
      assert_receive {:ipse, ^resumed, {:question, ^question, _}}, 1000
      :ok = Session.answer(resumed, question, %{"proceed" => "yes"})
      assert_receive {:ipse, ^resumed, {:approval, ref, "extension:state.put", _}}, 10_000
      :ok = Session.approve(resumed, ref, true)
      done(resumed, :ok)
      assert length(puts(events(c, resumed))) == 1
      assert Enum.count(events(c, resumed), &(&1["type"] == "extension_event_intent")) == 1

      assert Enum.count(
               events(c, resumed),
               &(&1["type"] == "request_admitted" and &1["kind"] == "model")
             ) == 1

      assert Subscriptions.validate_events(events(c, resumed)) == :ok
      assert Session.info(resumed).final == "answer"
      :ok = Session.close(resumed)
    end
  end

  test "interrupted callback after a committed write never replays on idle resume", c do
    config = config(c, :before, "hang_after_write")
    {:ok, pid} = start(c, config)
    :ok = Session.prompt(pid, "committed before interruption")
    eventually(fn -> File.exists?(c.pid_file) end)
    assert length(puts(events(c, pid))) == 1
    id = Session.info(pid).id
    :ok = Session.cancel(pid)
    :ok = Session.close(pid)
    bytes = File.read!(Path.join(c.dir, id <> ".jsonl"))
    trace = File.read!(c.trace)
    {:ok, resumed} = start(c, config, id)
    assert Session.info(resumed).phase == :idle
    assert File.read!(c.trace) == trace
    assert File.read!(Path.join(c.dir, id <> ".jsonl")) == bytes
    assert length(puts(events(c, resumed))) == 1
    refute_receive {:job_model, _}, 100
    :ok = Session.close(resumed)
  end

  test "late indexed writes conflict with concurrent forget instead of resurrecting data", c do
    {:ok, writer} = start(c, config(c, :after, "write"))
    :ok = Session.prompt(writer, "initial memory")
    done(writer, :ok)
    :ok = Session.close(writer)
    {:ok, delayed} = start(c, config(c, :after, "hold_before_write"))
    :ok = Session.prompt(delayed, "stale indexing")
    eventually(fn -> File.exists?(c.pid_file) end)
    {:ok, forgetter} = start(c, config(c, :after, "forget"))
    :ok = Session.invoke_export(forgetter, :command, "ext__graph__forget", %{})
    done(forgetter, :ok)
    File.write!(c.gate, "release")
    done(delayed, :ok)
    [put] = puts(events(c, delayed))
    assert put["outcome"]["status"] == "conflict"
    assert put["outcome"]["value"]["record"]["deleted"]
    :ok = Session.close(delayed)
    :ok = Session.close(forgetter)
  end

  test "metadata job origin never discloses private prompt/source hashes", c do
    {:ok, pid} = start(c, config(c, :metadata, "write"))
    :ok = Session.prompt(pid, "synthetic-private-input")
    done(pid, :ok)
    history = events(c, pid)
    [parent] = Enum.filter(history, &(&1["type"] == "extension_invocation_intent"))

    source_hashes =
      Enum.map(parent["event_trigger"]["sources"], fn {_, source} -> source["record_sha256"] end)

    trace = File.read!(c.trace)

    refute String.contains?(trace, [
             "synthetic-private-input",
             "synthetic-native-secret" | source_hashes
           ])

    :ok = Session.close(pid)
  end
end
