defmodule Ipse.Extensions.HistoryTest do
  use ExUnit.Case, async: false
  alias Ipse.{Journal, Session}
  alias Ipse.Lifecycle.Answer
  alias Ipse.Extensions.{History, Manifest, Config, Registry, Store, Catalog, Subscriptions}

  defmodule Model do
    def complete(config, _, _, emit) do
      text = Map.get(config, :answer_text, "history answer")
      emit.({:text, text})

      {:ok,
       %{
         "role" => "assistant",
         "content" => text,
         "provider_data" => %{"opaque" => "synthetic-native-secret"}
       }, %{}}
    end
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-history-artifact-#{Ipse.Usage.id()}")
    File.mkdir_p!(Path.join(root, "ebin"))
    module = "Independent.History#{System.unique_integer([:positive])}"

    capabilities =
      ~w(invoke.command host.actions host.history host.history.prompt.expanded host.history.answer.presented host.state.write host.question event.notify event.answer.presented)

    declaration = %{
      "id" => "answer",
      "event" => "answer.committed",
      "event_version" => 1,
      "view" => "answer.presented",
      "mode" => "notify",
      "schedule" => "after_turn",
      "required" => true
    }

    exports =
      Catalog.empty()
      |> Map.put("commands", [
        %{
          "id" => "catchup",
          "description" => "Synthetic explicit catch-up",
          "arguments_schema" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ~w(view mode),
            "properties" => %{"view" => %{"type" => "string"}, "mode" => %{"type" => "string"}}
          },
          "result_schema" => %{"type" => "object"}
        }
      ])

    code = """
    defmodule #{module} do
      @behaviour Ipse.Extension
      def describe, do: %{"sdk" => 1, "capabilities" => #{inspect(capabilities)}, "exports" => #{inspect(exports)}, "subscriptions" => [#{inspect(declaration)}]}
      def init(options), do: {:ok, options}
      def handle("event.notify", payload, state), do:
        {:ok, %{"api_version" => 1, "kind" => "ack", "delivery_id" => payload["delivery_id"], "event_id" => payload["event"]["event_id"]}, state}
      def handle("invoke.command", payload, state) do
        state = Map.merge(state, %{"mode" => payload["arguments"]["mode"], "view" => payload["arguments"]["view"], "scanned" => 0, "matched" => 0, "gaps" => 0, "text" => "", "source" => nil})
        read(nil, 0, state)
      end
      def handle("host.actions", %{"outcome" => %{"status" => "answered"}, "checkpoint" => checkpoint}, state), do:
        read(checkpoint["snapshot"], checkpoint["cursor"], Map.merge(state, checkpoint))
      def handle("host.actions", %{"outcome" => %{"status" => "ok", "value" => %{"records" => rows} = page}}, state) do
        File.write!(state["trace"], Jason.encode!(page) <> "\\n", [:append])
        state = Enum.reduce(rows, %{state | "scanned" => state["scanned"] + page["scanned"]}, fn row, acc ->
          case row do
            %{"kind" => "event", "event" => %{"data" => %{"text" => text}, "event_id" => source}} ->
              %{acc | "matched" => acc["matched"] + 1, "text" => text, "source" => source}
            %{"kind" => "gap"} -> %{acc | "gaps" => acc["gaps"] + 1}
            _ -> acc
          end
        end) |> Map.put("snapshot", page["snapshot"])
        cond do
          state["mode"] == "hold" ->
            File.write!((state["pid"]) <> ".ready-" <> System.pid(), System.pid()); File.rename!((state["pid"]) <> ".ready-" <> System.pid(), state["pid"]); Process.sleep(:infinity)
          state["mode"] == "question" ->
            checkpoint = state |> Map.take(~w(view scanned matched gaps text source snapshot)) |> Map.put("mode", "read")
              |> Map.put("cursor", page["next"] || page["snapshot"]["byte_offset"])
            call(%{"op" => "operator.question", "arguments" => %{"questions" => [%{"id" => "continue", "prompt" => "Continue synthetic catch-up?", "kind" => "text"}]}, "checkpoint" => checkpoint}, state)
          page["next"] != nil -> read(page["snapshot"], page["next"], state)
          state["mode"] == "write" ->
            call(%{"op" => "state.put", "scope" => "project", "key" => "history_note", "expected_revision" => 0,
              "value" => %{"text" => state["text"], "source_event_id" => state["source"]}}, state)
          true -> result(state, "read")
        end
      end
      def handle("host.actions", payload, state), do: result(state, payload["outcome"]["status"])
      defp read(snapshot, cursor, state), do: call(%{"op" => "history.read", "view" => state["view"], "cursor" => cursor, "snapshot" => snapshot, "limit" => 8}, state)
      defp call(request, state), do: {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => request}, state}
      defp result(state, status), do: {:ok, %{"api_version" => 1, "kind" => "result", "value" => Map.take(state, ~w(snapshot scanned matched gaps text)) |> Map.put("status", status)}, state}
    end
    """

    file = Path.join(root, "fixture.ex")
    File.write!(file, code)

    {out, 0} =
      System.cmd(
        System.find_executable("elixirc"),
        [
          "-pa",
          Application.app_dir(:ipse, "ebin"),
          "-pa",
          Application.app_dir(:jason, "ebin"),
          "-o",
          Path.join(root, "ebin"),
          file
        ],
        stderr_to_stdout: true
      )

    assert out == ""
    File.write!(Path.join(root, "LICENSE"), "MIT synthetic fixture")

    manifest = %{
      "format" => 1,
      "id" => "fixture/history",
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
        "required" => ~w(trace pid),
        "properties" => Map.new(~w(trace pid), &{&1, %{"type" => "string"}})
      },
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      },
      "files" =>
        Enum.map(["LICENSE", "ebin/Elixir.#{module}.beam"], fn path ->
          bytes = File.read!(Path.join(root, path))
          %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Manifest.sha256(bytes)}
        end)
    }

    File.write!(Path.join(root, "extension.json"), Jason.encode!(manifest))
    on_exit(fn -> File.rm_rf!(root) end)
    %{artifact: root}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-history-#{Ipse.Usage.id()}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      root: root,
      dir: Path.join(root, "sessions"),
      home: Path.join(root, "home"),
      trace: Path.join(root, "pages.jsonl"),
      pid_file: Path.join(root, "worker.pid")
    }
  end

  defp request(view \\ "metadata", cursor \\ 0, snapshot \\ nil, limit \\ 8),
    do: %{
      "op" => "history.read",
      "view" => view,
      "cursor" => cursor,
      "snapshot" => snapshot,
      "limit" => limit
    }

  defp journal(c) do
    {:ok, id} = Journal.create(c.dir, %{})
    context = %{history_dir: c.dir, history_session: id, identity: %{"instance" => "fixture"}}
    {context, id}
  end

  defp capture(context, request) do
    intent = %{
      "type" => "extension_action_intent",
      "version" => 1,
      "operation_id" => Ipse.Usage.id(),
      "namespace" => context.history_session,
      "identity_sha256" => Ipse.Compaction.digest([context.identity]),
      "approval" => "not_required",
      "request" => request
    }

    {:ok, source} =
      Journal.append_with_source(context.history_dir, context.history_session, intent)

    {%{context | identity: context.identity}
     |> Map.put(:history_snapshot, History.snapshot(source, intent)), intent}
  end

  defp config(c, approval \\ :allow) do
    {:ok, artifact} = Store.import(c.artifact, Path.join(c.home, "extensions/artifacts"))

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
          "instance" => "reader",
          "artifact" => artifact.digest,
          "enabled" => true,
          "options" => %{"trace" => c.trace, "pid" => c.pid_file},
          "order" => 0,
          "lifetime" => "session"
        }
      ]
    }

    {:ok, catalog} =
      Config.resolve([%{scope: "operator", path: "/fixture/history.json", data: data}], [])

    {:ok, entries} = Registry.prepare(catalog, c.home)

    %{
      provider: :demo,
      model: "fixture",
      provider_module: Model,
      home: c.home,
      approval: approval,
      compact: false,
      max_steps: 3,
      extensions: entries
    }
  end

  defp start(c, config, id \\ nil),
    do:
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         [
           config: config,
           cwd: c.root,
           state_dir: c.dir,
           subscriber: self(),
           owner: self(),
           id: id
         ]}
      )

  defp done(pid), do: assert_receive({:ipse, ^pid, {:done, :ok}}, 15_000)
  defp events(c, pid), do: elem(Journal.load(c.dir, Session.info(pid).id), 1)
  defp eventually(fun, attempts \\ 200)
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

  test "history grants are separate from live subscriptions and require base/actions", c do
    assert :ok = History.validate(request())

    assert :ok =
             Catalog.validate(
               Catalog.empty(),
               ~w(host.actions host.history host.history.prompt.original)
             )

    assert {:error, _} = Catalog.validate(Catalog.empty(), ~w(host.history))

    assert {:error, _} =
             Catalog.validate(Catalog.empty(), ~w(host.actions host.history.prompt.original))

    for bad <- [
          Map.put(request(), "path", c.dir),
          Map.put(request(), "session_id", Ipse.Usage.id()),
          Map.put(request(), "limit", 9),
          Map.put(request(), "cursor", -1),
          Map.put(request(), "view", "provider.native")
        ] do
      assert {:error, _} = History.validate(bad)
    end
  end

  test "metadata pages contain no raw text, native data or content hashes", c do
    {context, id} = journal(c)

    :ok =
      Journal.append(c.dir, id, %{
        "type" => "message",
        "message" => %{"role" => "user", "content" => "synthetic-private-user"}
      })

    :ok =
      Journal.append(c.dir, id, %{
        "type" => "message",
        "message" => %{
          "role" => "assistant",
          "content" => "synthetic-private-answer",
          "provider_data" => %{"native" => "synthetic-private-native"}
        }
      })

    :ok =
      Journal.append(c.dir, id, %{
        "type" => "synthetic-private-type",
        "secret" => "synthetic-private-field"
      })

    {context, intent} = capture(context, request())
    assert {:ok, value} = History.execute(context, intent)
    assert value["next"] == nil and value["scanned"] == 4
    assert History.valid_outcome?(request(), "ok", value, intent["operation_id"])
    assert Enum.count(value["records"], &(&1["kind"] == "gap")) == 1
    refute Jason.encode!(value) =~ "synthetic-private"
    refute Jason.encode!(value) =~ "sha256"
  end

  test "frozen upper boundary excludes later oversized or incomplete data", c do
    {context, id} = journal(c)
    for _ <- 1..4, do: Journal.append(c.dir, id, %{"type" => "cancelled"})
    {context, intent} = capture(context, request("metadata", 0, nil, 2))
    {:ok, first} = History.execute(context, intent)
    File.write!(Path.join(c.dir, id <> ".jsonl"), String.duplicate("x", 1_048_577), [:append])
    second_request = request("metadata", first["next"], first["snapshot"], 8)
    assert {:ok, second} = History.execute(context, %{intent | "request" => second_request})
    assert second["next"] == nil and second["scanned"] == 3
    assert second["snapshot"] == first["snapshot"]
    assert History.valid_outcome?(second_request, "ok", second, intent["operation_id"])

    assert {:ok, %{records: [], next: nil}} =
             Journal.source_page(
               c.dir,
               id,
               first["snapshot"]["byte_offset"],
               1,
               first["snapshot"]["byte_offset"]
             )
  end

  test "private views return exact recorded text and explicit unavailable/other-view rows", c do
    {context, id} = journal(c)
    turn = Ipse.Usage.id()
    received = Subscriptions.received(turn, "original private")
    {:ok, received_source} = Journal.append_with_source(c.dir, id, received)
    user = %{"role" => "user", "content" => "expanded private"}
    :ok = Journal.append(c.dir, id, %{"type" => "message", "message" => user})
    effective = Subscriptions.committed(turn, user["content"], user, received_source)
    {:ok, effective_source} = Journal.append_with_source(c.dir, id, effective)

    answer =
      Answer.build(
        turn,
        Ipse.Usage.id(),
        %{"role" => "assistant", "content" => "original answer"},
        "presented answer",
        effective_source
      )

    :ok = Journal.append(c.dir, id, answer)

    :ok =
      Journal.append(
        c.dir,
        id,
        Subscriptions.received(Ipse.Usage.id(), String.duplicate("a", 8193))
      )

    {context, intent} = capture(context, request("prompt.original"))
    assert {:ok, value} = History.execute(context, intent)
    assert Enum.count(value["records"], &(&1["kind"] == "event")) == 1
    assert Enum.any?(value["records"], &(&1["reason"] == "view_unavailable"))
    assert Enum.any?(value["records"], &(&1["kind"] == "skipped"))
    assert History.valid_outcome?(intent["request"], "ok", value, intent["operation_id"])
    refute Jason.encode!(value) =~ "expanded private"
    refute Jason.encode!(value) =~ "presented answer"
  end

  test "page budgets split records without truncation and report a single over-budget view", c do
    {context, id} = journal(c)

    for letter <- ["a", "b"] do
      :ok =
        Journal.append(c.dir, id, %{
          "type" => "message",
          "message" => %{"role" => "user", "content" => String.duplicate(letter, 7000)}
        })
    end

    {context, intent} = capture(context, request("prompt.expanded"))
    assert {:ok, first} = History.execute(context, intent)
    assert first["next"] != nil
    follow = request("prompt.expanded", first["next"], first["snapshot"])
    assert {:ok, last} = History.execute(context, %{intent | "request" => follow})
    assert last["next"] == nil

    texts =
      for row <- first["records"] ++ last["records"],
          row["kind"] == "event",
          do: row["event"]["data"]["text"]

    assert texts == [String.duplicate("a", 7000), String.duplicate("b", 7000)]
    assert History.valid_outcome?(intent["request"], "ok", first, intent["operation_id"])
    assert History.valid_outcome?(follow, "ok", last, intent["operation_id"])

    large = %{
      "type" => "message",
      "message" => %{"role" => "user", "content" => String.duplicate(<<0>>, 2100)}
    }

    {:ok, source} = Journal.append_with_source(c.dir, id, large)
    {context, intent} = capture(context, request("prompt.expanded", source["byte_offset"]))
    assert {:ok, value} = History.execute(context, intent)
    assert [%{"kind" => "gap", "reason" => "page_budget"}] = value["records"]
    assert value["next"] == nil
    assert byte_size(Jason.encode!(value)) <= 12_288
  end

  test "receipt validation rejects private data in metadata and a changed cursor or scope", c do
    {context, _id} = journal(c)
    {context, intent} = capture(context, request())
    {:ok, value} = History.execute(context, intent)
    [row] = value["records"]
    forged = put_in(row, ["event", "data"], %{"text" => "not authorized"})

    refute History.valid_outcome?(
             request(),
             "ok",
             %{value | "records" => [forged]},
             intent["operation_id"]
           )

    refute History.valid_outcome?(
             request(),
             "ok",
             %{value | "cursor" => 0.0},
             intent["operation_id"]
           )

    refute History.bound_outcome?(%{
             "namespace" => Ipse.Usage.id(),
             "outcome" => %{"status" => "ok", "value" => value}
           })

    refute History.valid_outcome?(
             request(),
             "ok",
             Map.put(value, "raw", "private"),
             intent["operation_id"]
           )
  end

  test "snapshot is bound to session, identity, view and a real initial-read anchor", c do
    {context, _} = journal(c)
    {context, intent} = capture(context, request())
    {:ok, first} = History.execute(context, intent)

    assert {:failed, %{"code" => "history_snapshot"}} =
             History.execute(%{context | identity: %{"instance" => "other"}}, intent)

    wrong = request("prompt.expanded", 0, first["snapshot"])
    assert {:error, _} = History.validate(wrong)
    altered = Map.put(first["snapshot"], "operation_id", Ipse.Usage.id())

    assert {:failed, %{"code" => "history_snapshot"}} =
             History.execute(context, %{intent | "request" => request("metadata", 0, altered)})

    assert {:failed, _} =
             History.execute(context, %{
               intent
               | "request" => request("metadata", 1, first["snapshot"])
             })

    assert {:failed, %{"code" => "history_cursor"}} =
             History.execute(context, %{
               intent
               | "request" =>
                   request("metadata", first["snapshot"]["byte_offset"] + 1, first["snapshot"])
             })
  end

  test "real SDK catch-up preserves the range and keeps later storage under full approval", c do
    {:ok, pid} = start(c, config(c, :ask))
    :ok = Session.prompt(pid, "historical source")
    done(pid)

    :ok =
      Session.invoke_export(pid, :command, "ext__reader__catchup", %{
        "view" => "answer.presented",
        "mode" => "write"
      })

    assert_receive {:ipse, ^pid, {:approval, ref, "extension:state.put", arguments}}, 15_000
    assert arguments["request"]["value"]["text"] == "history answer"
    :ok = Session.approve(pid, ref, false)
    done(pid)
    rows = events(c, pid)

    results =
      Enum.filter(
        rows,
        &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "history.read")
      )

    assert length(results) > 1
    assert length(Enum.uniq_by(results, & &1["outcome"]["value"]["snapshot"])) == 1
    assert History.validate_sources(c.dir, Session.info(pid).id, rows) == :ok

    first = hd(results)
    value = first["outcome"]["value"]

    missing = %{
      value
      | "records" => List.delete_at(value["records"], 1),
        "scanned" => value["scanned"] - 1
    }

    {:ok, forged} =
      Ipse.Extensions.Actions.result(Ipse.Extensions.Actions.result_intent(first), %{
        first["outcome"]
        | "value" => missing
      })

    changed = Enum.map(rows, fn e -> if e == first, do: forged, else: e end)

    assert {:error, :invalid_extension_history_source} =
             History.validate_sources(c.dir, Session.info(pid).id, changed)

    private =
      Enum.find(results, fn e ->
        Enum.any?(e["outcome"]["value"]["records"], &(&1["kind"] == "event"))
      end)

    value = private["outcome"]["value"]

    altered =
      Enum.map(value["records"], fn row ->
        if row["kind"] == "event",
          do: put_in(row, ["event", "data", "text"], "forged text"),
          else: row
      end)

    {:ok, forged} =
      Ipse.Extensions.Actions.result(Ipse.Extensions.Actions.result_intent(private), %{
        private["outcome"]
        | "value" => %{value | "records" => altered}
      })

    changed = Enum.map(rows, fn e -> if e == private, do: forged, else: e end)

    assert {:error, :invalid_extension_history_source} =
             History.validate_sources(c.dir, Session.info(pid).id, changed)

    assert Enum.any?(
             rows,
             &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "state.put" and
                 &1["outcome"]["status"] == "denied")
           )

    assert match?({:ok, _}, Session.restore_context(rows))
    refute File.read!(c.trace) =~ "synthetic-native-secret"
    :ok = Session.close(pid)
  end

  test "question resume continues the saved range without inference or recapture", c do
    configuration = config(c)
    {:ok, pid} = start(c, configuration)
    :ok = Session.prompt(pid, "historical source")
    done(pid)

    :ok =
      Session.invoke_export(pid, :command, "ext__reader__catchup", %{
        "view" => "prompt.expanded",
        "mode" => "question"
      })

    assert_receive {:ipse, ^pid, {:question, question, _}}, 15_000
    id = Session.info(pid).id
    Process.exit(pid, :kill)
    eventually(fn -> not Process.alive?(pid) end)
    bytes = File.read!(c.trace)
    {:ok, resumed} = start(c, configuration, id)
    assert_receive {:ipse, ^resumed, {:question, ^question, _}}, 1000
    assert File.read!(c.trace) == bytes
    :ok = Session.answer(resumed, question, %{"continue" => "continue"})
    done(resumed)
    rows = events(c, resumed)
    assert Enum.count(rows, &(&1["type"] == "request_admitted")) == 1

    reads =
      Enum.filter(
        rows,
        &(&1["type"] == "extension_action_intent" and &1["request"]["op"] == "history.read")
      )

    assert Enum.count(reads, &(&1["request"]["snapshot"] == nil)) == 1
    assert match?({:ok, _}, Session.restore_context(rows))
    :ok = Session.close(resumed)
  end

  test "physical recovery verifies a budget gap without interpreting it as a missing source", c do
    configuration = config(c) |> Map.put(:answer_text, String.duplicate(<<0>>, 2100))
    {:ok, pid} = start(c, configuration)
    :ok = Session.prompt(pid, "historical source")
    done(pid)

    :ok =
      Session.invoke_export(pid, :command, "ext__reader__catchup", %{
        "view" => "answer.presented",
        "mode" => "read"
      })

    done(pid)
    id = Session.info(pid).id
    rows = events(c, pid)

    results =
      Enum.filter(
        rows,
        &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "history.read")
      )

    assert Enum.any?(results, fn result ->
             Enum.any?(result["outcome"]["value"]["records"], &(&1["reason"] == "page_budget"))
           end)

    assert History.validate_sources(c.dir, id, rows) == :ok
    :ok = Session.close(pid)
    {:ok, resumed} = start(c, configuration, id)
    :ok = Session.close(resumed)
  end

  test "cancel and owner death stop catch-up workers; idle resume performs no replay", c do
    configuration = config(c)

    for stop <- [:cancel, :kill] do
      File.rm(c.pid_file)
      {:ok, pid} = start(c, configuration)
      :ok = Session.prompt(pid, "historical source")
      done(pid)

      :ok =
        Session.invoke_export(pid, :command, "ext__reader__catchup", %{
          "view" => "metadata",
          "mode" => "hold"
        })

      eventually(fn -> File.exists?(c.pid_file) end)
      worker = File.read!(c.pid_file)
      id = Session.info(pid).id
      if stop == :cancel, do: assert(Session.cancel(pid) == :ok), else: Process.exit(pid, :kill)

      eventually(fn ->
        elem(System.cmd("kill", ["-0", worker], stderr_to_stdout: true), 1) != 0
      end)

      if stop == :cancel, do: assert(Session.close(pid) == :ok)
      eventually(fn -> not Process.alive?(pid) end)
      path = Path.join(c.dir, id <> ".jsonl")
      bytes = File.read!(path)
      trace = File.read!(c.trace)
      {:ok, resumed} = start(c, configuration, id)
      assert Session.info(resumed).phase == :idle
      assert File.read!(path) == bytes
      assert File.read!(c.trace) == trace
      :ok = Session.close(resumed)
    end
  end
end
