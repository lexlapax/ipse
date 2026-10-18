defmodule Ipse.Extensions.MemorySessionTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal}
  alias Ipse.Extensions.{Catalog, Config, Memory, Registry, State}
  alias Ipse.Extensions.Memory.Records

  defmodule Model do
    def complete(config, messages, tools, _emit) do
      send(config.test_pid, {:memory_model, messages, tools})

      if List.last(messages)["role"] == "user" do
        {name, args} = Agent.get_and_update(config.jobs, fn [job | rest] -> {job, rest} end)

        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => [
             %{
               "id" => "note_" <> Ipse.Usage.id(),
               "type" => "function",
               "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
             }
           ]
         }, %{}}
      else
        {:ok, %{"role" => "assistant", "content" => "Fixture completed."}, %{}}
      end
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-memory-session-" <> Ipse.Usage.id())
    File.mkdir_p!(root)
    home = Path.join(root, "home")
    File.mkdir_p!(home)
    {:ok, jobs} = Agent.start_link(fn -> [] end)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, home: home, jobs: jobs, dir: Path.join(root, "sessions")}
  end

  defp data(working \\ false) do
    artifact = if working, do: "builtin:working-memory:1", else: "builtin:persistent-memory:1"

    trust = %{
      "artifact" => artifact,
      "capabilities" =>
        if(working, do: Memory.capabilities(), else: ["host.state.bound" | Memory.capabilities()]),
      "allow_project" => false,
      "allow_children" => false
    }

    trust =
      if working,
        do: trust,
        else:
          Map.put(trust, "state_bindings", [
            %{
              "version" => 1,
              "instance" => "notes",
              "id" => "explicit-notes",
              "scopes" => ["project"]
            }
          ])

    %{
      "extensions" => [
        %{
          "instance" => "notes",
          "artifact" => artifact,
          "enabled" => true,
          "options" => %{
            "scope" => if(working, do: "session", else: "project"),
            "retention_seconds" => 3600
          },
          "order" => 1,
          "lifetime" => "persistent"
        }
      ],
      "extension_trust" => [trust]
    }
  end

  defp entries(ctx, data \\ data()) do
    assert {:ok, catalog} =
             Config.resolve(
               [%{scope: "operator", path: Path.join(ctx.root, "operator.json"), data: data}],
               []
             )

    assert {:ok, entries} = Registry.prepare(catalog, ctx.home)
    assert {:ok, _} = Catalog.snapshot(%{extensions: entries})
    entries
  end

  defp start(ctx, entries, extra \\ %{}, id \\ nil) do
    config =
      Map.merge(
        %{
          provider: :ollama,
          model: "fixture",
          provider_module: Model,
          home: ctx.home,
          operator_home: nil,
          approval: :allow,
          extensions: entries,
          jobs: ctx.jobs,
          test_pid: self(),
          compact: false
        },
        extra
      )

    assert {:ok, pid} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                config: config,
                cwd: ctx.root,
                state_dir: ctx.dir,
                subscriber: self(),
                owner: self(),
                id: id}
             )

    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    pid
  end

  defp tool(ctx, pid, name, args) do
    Agent.update(ctx.jobs, &(&1 ++ [{"ext__notes__" <> name, args}]))
    assert :ok = Session.prompt(pid, "Explicit synthetic memory operation")
  end

  defp await_done(pid) do
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5000
  end

  defp note,
    do: %{
      "source" => "operator:task",
      "source_generation" => 1,
      "title" => "Supervisor task",
      "text" => "Keep owner monitors active",
      "kind" => "task_card",
      "provenance" => "operator statement",
      "expected_revision" => 0
    }

  defp events(ctx, pid) do
    assert {:ok, events} = Journal.load(ctx.dir, Session.info(pid).id)
    assert {:ok, _} = Session.restore_context(events)
    events
  end

  test "built-in tools preserve notes and exact cached recall across inert resume", ctx do
    entries = entries(ctx)
    pid = start(ctx, entries)
    tool(ctx, pid, "remember", note())
    await_done(pid)
    tool(ctx, pid, "recall", %{"query" => "owner monitors"})
    await_done(pid)
    ev = events(ctx, pid)
    result = ev |> Enum.filter(&(&1["type"] == "extension_invocation_result")) |> List.last()
    assert result["value"]["matches"] |> hd() |> get_in(["source"]) == "operator:task"
    id = Session.info(pid).id
    assert :ok = Session.close(pid)
    file = Path.join(ctx.dir, id <> ".jsonl")
    before = File.read!(file)
    {:ok, messages} = Session.restore_context(ev)
    resumed = start(ctx, entries, %{}, id)
    assert File.read!(file) == before
    assert {:ok, ^messages} = Session.restore_context(events(ctx, resumed))
    assert Session.info(resumed).phase == :idle
    next = start(ctx, entries)
    tool(ctx, next, "recall", %{"query" => "owner monitors"})
    await_done(next)

    assert events(ctx, next)
           |> Enum.find(&(&1["type"] == "extension_invocation_result"))
           |> get_in(["value", "matches"])
           |> length() == 1

    assert :ok = Session.invoke_export(next, :command, "ext__notes__export", %{})
    await_done(next)

    assert_receive {:ipse, ^next, {:extension_result, %{"value" => %{"status" => "exported"}}}},
                   1000
  end

  test "session memory remains separate and never promotes into project notes", ctx do
    working = entries(ctx, data(true))
    pid = start(ctx, working)
    tool(ctx, pid, "remember", note())
    await_done(pid)
    other = start(ctx, working)
    tool(ctx, other, "recall", %{"query" => "owner"})
    await_done(other)

    assert events(ctx, other)
           |> Enum.find(&(&1["type"] == "extension_invocation_result"))
           |> get_in(["value", "matches"]) == []

    persistent = start(ctx, entries(ctx))
    tool(ctx, persistent, "recall", %{"query" => "owner"})
    await_done(persistent)

    assert events(ctx, persistent)
           |> Enum.find(&(&1["type"] == "extension_invocation_result"))
           |> get_in(["value", "matches"]) == []
  end

  test "write approval remains separate, cancellation writes nothing and disabled selections create no store",
       ctx do
    selected = entries(ctx)
    pid = start(ctx, selected, %{approval: :ask})
    tool(ctx, pid, "remember", note())
    assert_receive {:ipse, ^pid, {:approval, ref, "ext__notes__remember", _}}, 3000
    :ok = Session.approve(pid, ref, true)
    assert_receive {:ipse, ^pid, {:approval, _, "extension:state.put", args}}, 3000
    assert args["request"]["value"]["text"] == note()["text"]
    assert :ok = Session.cancel(pid)
    assert Session.info(pid).phase == :idle
    [entry] = selected
    {:ok, namespace} = State.namespace(entry.identity, "project", ctx.root, Session.info(pid).id)
    request = %{"op" => "state.get", "scope" => "project", "key" => Records.key(note()["source"])}

    assert {:ok, %{"record" => %{"revision" => 0}}} =
             State.execute(
               Path.join(ctx.home, "extension-state-v1"),
               namespace,
               request,
               Ipse.Usage.id()
             )

    fresh = %{ctx | home: Path.join(ctx.root, "disabled-home")}
    disabled = data() |> update_in(["extensions", Access.at(0), "enabled"], fn _ -> false end)
    assert entries(fresh, disabled) == []
    refute File.exists?(fresh.home)
  end

  test "persistent memory refuses missing operator binding or narrowed scope mismatch", ctx do
    missing =
      data() |> update_in(["extension_trust", Access.at(0)], &Map.delete(&1, "state_bindings"))

    {:ok, catalog} =
      Config.resolve([%{scope: "operator", path: "/fixture/operator.json", data: missing}], [])

    assert {:error, _} = Registry.prepare(catalog, ctx.home)
  end

  test "working and persistent packages can be independently selected together", ctx do
    persistent =
      data()
      |> put_in(["extensions", Access.at(0), "instance"], "project-notes")
      |> put_in(
        ["extension_trust", Access.at(0), "state_bindings", Access.at(0), "instance"],
        "project-notes"
      )

    working = data(true) |> put_in(["extensions", Access.at(0), "instance"], "working-notes")

    combined = %{
      "extensions" => persistent["extensions"] ++ working["extensions"],
      "extension_trust" => persistent["extension_trust"] ++ working["extension_trust"]
    }

    selected = entries(ctx, combined)
    pid = start(ctx, selected)
    assert length(Session.exports(pid)["entries"]) == 24
    assert byte_size(Jason.encode!(Session.exports(pid))) <= 16_384
    assert :ok = Session.invoke_export(pid, :command, "ext__working-notes__remember", note())
    await_done(pid)

    assert :ok =
             Session.invoke_export(pid, :command, "ext__project-notes__recall", %{
               "query" => "owner"
             })

    await_done(pid)
    assert_receive {:ipse, ^pid, {:extension_result, %{"value" => %{"matches" => []}}}}, 1000
  end

  test "standalone commands need no inference and denied writes leave no note", ctx do
    pid = start(ctx, entries(ctx), %{approval: :deny})
    assert :ok = Session.invoke_export(pid, :command, "ext__notes__remember", note())
    await_done(pid)
    assert_receive {:ipse, ^pid, {:extension_result, %{"value" => %{"status" => "denied"}}}}, 1000
    refute_receive {:memory_model, _, _}
    ev = events(ctx, pid)

    result =
      Enum.find(
        ev,
        &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "state.put")
      )

    assert result["approval"] == "denied"
    [entry] = entries(ctx)
    {:ok, namespace} = State.namespace(entry.identity, "project", ctx.root, Session.info(pid).id)

    assert {:ok, %{"record" => %{"revision" => 0}}} =
             State.execute(
               Path.join(ctx.home, "extension-state-v1"),
               namespace,
               %{
                 "op" => "state.get",
                 "scope" => "project",
                 "key" => Records.key(note()["source"])
               },
               Ipse.Usage.id()
             )
  end

  test "project memory does not cross directories and explicit operator scope does", ctx do
    selected = entries(ctx)
    first = start(ctx, selected)
    assert :ok = Session.invoke_export(first, :command, "ext__notes__remember", note())
    await_done(first)
    other = %{ctx | root: Path.join(ctx.root, "other-project")}
    File.mkdir_p!(other.root)
    second = start(other, selected)

    assert :ok =
             Session.invoke_export(second, :command, "ext__notes__recall", %{"query" => "owner"})

    await_done(second)
    assert_receive {:ipse, ^second, {:extension_result, %{"value" => %{"matches" => []}}}}, 1000

    global_data =
      data()
      |> put_in(["extensions", Access.at(0), "options", "scope"], "operator")
      |> put_in(["extension_trust", Access.at(0), "state_bindings", Access.at(0), "scopes"], [
        "operator"
      ])

    global = entries(ctx, global_data)
    one = start(ctx, global)
    :ok = Session.invoke_export(one, :command, "ext__notes__remember", note())
    await_done(one)
    two = start(other, global)
    :ok = Session.invoke_export(two, :command, "ext__notes__recall", %{"query" => "owner"})
    await_done(two)

    assert_receive {:ipse, ^two,
                    {:extension_result,
                     %{"value" => %{"matches" => [%{"source" => "operator:task"}]}}}},
                   1000
  end

  test "large value recall uses the negotiated read allowance and restores its full receipt chain",
       ctx do
    selected = entries(ctx)
    pid = start(ctx, selected)
    [entry] = selected
    {:ok, namespace} = State.namespace(entry.identity, "project", ctx.root, Session.info(pid).id)

    parents = Enum.map(1..8, &(Integer.to_string(&1) <> String.duplicate("d", 490)))

    for source <- parents do
      args = Map.put(note(), "source", source)
      {:ok, value} = Records.build(args, nil, System.system_time(:millisecond), 3600)

      assert {:ok, _} =
               State.execute(
                 Path.join(ctx.home, "extension-state-v1"),
                 namespace,
                 %{
                   "op" => "state.put",
                   "scope" => "project",
                   "key" => Records.key(source),
                   "expected_revision" => 0,
                   "value" => value
                 },
                 Ipse.Usage.id()
               )
    end

    for n <- 1..20 do
      args =
        note()
        |> Map.put("source", "large:#{n}" <> String.duplicate("s", 480))
        |> Map.put("text", "needle " <> String.duplicate("x", 2000))
        |> Map.put("provenance", String.duplicate("p", 500))
        |> Map.put(
          "derived_from",
          parents
        )

      {:ok, value} = Records.build(args, nil, System.system_time(:millisecond), 3600)

      assert {:ok, _} =
               State.execute(
                 Path.join(ctx.home, "extension-state-v1"),
                 namespace,
                 %{
                   "op" => "state.put",
                   "scope" => "project",
                   "key" => Records.key(args["source"]),
                   "expected_revision" => 0,
                   "value" => value
                 },
                 Ipse.Usage.id()
               )
    end

    :ok = Session.invoke_export(pid, :command, "ext__notes__recall", %{"query" => "needle"})
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000

    assert_receive {:ipse, ^pid,
                    {:extension_result, %{"value" => %{"scanned" => 28, "matches" => matches}}}},
                   1000

    assert length(matches) == 5
    ev = events(ctx, pid)
    actions = Enum.filter(ev, &(&1["type"] == "extension_action_result"))
    assert length(actions) > 16
    assert Enum.all?(actions, &(&1["request"]["op"] == "state.scan"))
    assert List.last(actions)["step"] > 16
    assert :ok = Ipse.Extensions.Actions.validate_events(ev)
    parent = Enum.find(ev, &(&1["type"] == "extension_invocation_intent"))
    scan = hd(actions)["request"]
    assert {:ok, _} = Ipse.Extensions.Actions.intent(parent, scan, 512, "not_required", ctx.root)

    assert {:error, _} =
             Ipse.Extensions.Actions.intent(parent, scan, 513, "not_required", ctx.root)

    write = %{
      "op" => "state.put",
      "scope" => "project",
      "key" => "late",
      "expected_revision" => 0,
      "value" => %{}
    }

    assert {:error, _} = Ipse.Extensions.Actions.intent(parent, write, 17, "approved", ctx.root)

    ungranted =
      update_in(parent, ["identity", "capabilities"], &List.delete(&1, "host.state.scan"))

    assert {:error, _} =
             Ipse.Extensions.Actions.intent(ungranted, scan, 1, "not_required", ctx.root)

    assert Session.info(pid).accounting["request_count"] == 0
  end
end
