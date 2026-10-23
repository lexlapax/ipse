Code.require_file("../../../priv/demo/usage.exs", __DIR__)

defmodule Ipse.Extension.ChildUsageTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal, Usage}
  alias Ipse.Extension.{ChildUsage, Actions, Catalog}

  defmodule Model do
    def complete(config, messages, _, emit) do
      if config[:delegation_origin] do
        emit.({:provider_usage, %{"input_tokens" => 50, "output_tokens" => 2}})

        if config[:fixture_child_fail] do
          {:error, "Synthetic child refusal"}
        else
          {:ok, %{"role" => "assistant", "content" => "Synthetic child secret"},
           %{"input_tokens" => 50, "output_tokens" => 5}}
        end
      else
        if Enum.any?(messages, &(&1["role"] == "tool")) do
          {:ok, %{"role" => "assistant", "content" => "Synthetic parent secret"},
           %{"input_tokens" => 100, "output_tokens" => 20}}
        else
          {name, args} =
            if config[:parallel_fixture] do
              {"delegate_parallel",
               %{
                 "tasks" => [
                   %{"task" => "First", "context" => "Synthetic"},
                   %{"task" => "Second", "context" => "Synthetic"}
                 ]
               }}
            else
              {"delegate", %{"task" => "One", "context" => "Synthetic"}}
            end

          {:ok,
           %{
             "role" => "assistant",
             "content" => "",
             "tool_calls" => [
               %{
                 "id" => "synthetic-call",
                 "type" => "function",
                 "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
               }
             ]
           }, %{"input_tokens" => 100, "output_tokens" => 20}}
        end
      end
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-child-accounting-#{Usage.id()}")
    File.mkdir_p!(root)

    config =
      Ipse.UsageDemo.config(Path.join(root, "home"), true, Ipse.UsageDemo.card(), :tree)
      |> Map.merge(%{
        provider_module: Model,
        subagents: true,
        subagent_concurrency: 2,
        approval: :allow,
        parallel_fixture: true
      })

    context = %{root: root, dir: Path.join(root, "sessions"), config: config}
    on_exit(fn -> File.rm_rf!(root) end)
    context
  end

  defp start(c, config \\ nil, id \\ nil) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: config || c.config,
         cwd: c.root,
         state_dir: c.dir,
         id: id,
         subscriber: self(),
         owner: self()}
      )

    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    pid
  end

  defp run(pid) do
    :ok = Session.prompt(pid, "Synthetic delegation prompt")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 20_000
  end

  defp command(pid, name, arguments \\ %{}) do
    :ok = Session.invoke_export(pid, :command, "ext__costs__" <> name, arguments)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 20_000
    Session.info(pid).extension_result["value"]
  end

  defp child_file(c, parent, child),
    do: Path.join([c.dir, "subagents", parent, child <> ".jsonl"])

  test "parallel children are explicitly discovered, priced once and recovered without execution",
       c do
    pid = start(c)
    run(pid)
    value = command(pid, "tree_summary")
    assert value["coverage"] == "session_tree"
    assert value["request_count"] == 4 and value["child_count"] == 2
    assert value["captured_child_count"] == 2 and value["gap_count"] == 0
    assert value["enumeration_complete"] and value["cost_estimate_complete"]
    assert [%{"amount_nanos" => 1_100_000, "counts" => counts}] = value["groups"]
    assert counts["input_tokens"]["total"] == 300
    assert counts["output_tokens"]["total"] == 50
    refute Jason.encode!(value) =~ "secret"
    id = Session.info(pid).id
    :ok = Session.close(pid)
    {:ok, events} = Journal.load(c.dir, id)
    starts = Enum.filter(events, &(&1["type"] == "delegation_started"))

    assert Enum.sort(Enum.map(starts, & &1["origin_call_id"])) == [
             "synthetic-call/0",
             "synthetic-call/1"
           ]

    assert {:ok, _} = Actions.restore(events)
    assert :ok = ChildUsage.validate_sources(c.dir, id, events)

    changed =
      Enum.map(events, fn e ->
        if e["type"] == "extension_action_result" and e["request"]["op"] == "usage.child.read" and
             e["outcome"]["status"] == "ok" do
          update_in(e, ["outcome", "value", "requests"], fn [r | rest] ->
            counts =
              r["usage"]["counts"]
              |> Map.update!("input_tokens", &(&1 + 1))
              |> Map.update!("total_tokens", &(&1 + 1))

            [put_in(r, ["usage", "counts"], counts) | rest]
          end)
        else
          e
        end
      end)

    assert {:error, :invalid_extension_child_usage} =
             ChildUsage.validate_sources(c.dir, id, changed)

    path = Path.join(c.dir, id <> ".jsonl")
    before = File.read!(path)
    resumed = start(c, nil, id)
    assert Session.info(resumed).extension_result["value"] == value
    assert File.read!(path) == before
    :ok = Session.close(resumed)
  end

  test "serial delegation uses the actual raw origin and no child grant is implicit", c do
    pid = start(c, Map.put(c.config, :parallel_fixture, false))
    run(pid)
    value = command(pid, "tree_summary")
    assert value["request_count"] == 3 and value["child_count"] == 1
    assert [%{"amount_nanos" => 950_000}] = value["groups"]
    assert value["cost_estimate_complete"]

    assert {:error, _} =
             Catalog.validate(
               Catalog.empty(),
               ~w(invoke.command host.actions host.usage.children)
             )

    assert {:error, _} =
             Catalog.validate(Catalog.empty(), ~w(invoke.command host.usage host.usage.children))
  end

  test "failed child observations and uncertain parent outcomes retain unknown liability", c do
    config = c.config |> Map.put(:parallel_fixture, false) |> Map.put(:fixture_child_fail, true)
    pid = start(c, config)
    :ok = Session.prompt(pid, "Synthetic failing child")
    assert_receive {:ipse, ^pid, {:done, :error}}, 20_000
    value = command(pid, "tree_summary")
    assert value["child_count"] == 1 and value["captured_child_count"] == 1
    assert value["enumeration_complete"] and not value["cost_estimate_complete"]
    assert value["unknown_child_outcome_count"] == 1

    assert [%{"amount_nanos" => nil, "known_amount_nanos" => known, "unknown_cost_count" => 1}] =
             value["groups"]

    assert known >= 120_000
    %{"value" => %{"children" => [child]}} = command(pid, "children")

    %{"value" => %{"requests" => [request]}} =
      command(pid, "child_usage", %{"child_id" => child["child_id"]})

    assert request["outcome"] == "failed" and request["finality"] == "partial"
    assert request["usage"]["counts"]["output_tokens"] == 2
  end

  test "legacy unmetered child scope stays incomplete and unrecorded origins are never invented",
       c do
    pid = start(c, Map.put(c.config, :parallel_fixture, false))
    run(pid)
    parent = Session.info(pid).id
    {:ok, before} = Journal.load(c.dir, parent)
    [start] = Enum.filter(before, &(&1["type"] == "delegation_started"))
    child = start["child_id"]
    file = child_file(c, parent, child)

    [header | rest] =
      File.read!(file) |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

    header = update_in(header, ["metadata"], &Map.delete(&1, "usage_version"))
    File.write!(file, Enum.map_join([header | rest], "\n", &Jason.encode!/1) <> "\n")
    value = command(pid, "tree_summary")
    assert value["enumeration_complete"] and value["legacy_unmetered"]
    refute value["cost_estimate_complete"]
    {:ok, events} = Journal.load(c.dir, parent)
    assert :ok = ChildUsage.validate_sources(c.dir, parent, events)

    legacy =
      Enum.map(before, fn e ->
        if e["type"] == "delegation_started", do: Map.delete(e, "origin_call_id"), else: e
      end)

    {:ok, state} = ChildUsage.restore(legacy)

    intent =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_intent" and &1["request"]["op"] == "usage.child.read")
      )

    assert {:failed, %{"code" => "usage_child_invalid"}} =
             ChildUsage.execute(ChildUsage.context(state, intent, c.dir, nil))

    :ok = Session.close(pid)
    resumed = start(c, Map.put(c.config, :parallel_fixture, false), parent)
    assert Session.info(resumed).extension_result["value"] == value
    :ok = Session.close(resumed)
  end

  test "missing, locked and unrelated child IDs produce explicit gaps rather than zero", c do
    pid = start(c)
    run(pid)
    %{"status" => "ok", "value" => discovered} = command(pid, "children")
    [first, second] = discovered["children"]
    parent = Session.info(pid).id
    {:ok, events} = Journal.load(c.dir, parent)
    {:ok, state} = ChildUsage.restore(events)
    state = %{state | overflow: true}

    intent =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_intent" and &1["request"]["op"] == "usage.children")
      )

    initial = ChildUsage.context(state, intent, c.dir, discovered["snapshot"]["source"])
    assert {:failed, %{"code" => "usage_children_limit"}} = ChildUsage.execute(initial)
    existing = put_in(intent, ["request", "snapshot"], discovered["snapshot"])

    assert {:ok, ^discovered} =
             ChildUsage.execute(ChildUsage.context(state, existing, c.dir, nil))

    file = child_file(c, parent, first["child_id"])
    File.rename!(file, file <> ".saved")

    try do
      value = command(pid, "tree_summary")
      assert value["gap_count"] == 1 and value["captured_child_count"] == 1
      refute value["enumeration_complete"] or value["cost_estimate_complete"]
      assert value["gap_reasons"] == %{"usage_child_missing" => 1}
    after
      File.rename!(file <> ".saved", file)
    end

    {:ok, lock} =
      Ipse.Runner.lock(Path.rootname(child_file(c, parent, second["child_id"])) <> ".lock")

    try do
      assert %{"status" => "failed", "value" => %{"code" => "usage_child_busy"}} =
               command(pid, "child_usage", %{"child_id" => second["child_id"]})
    after
      Ipse.Runner.unlock(lock)
    end

    assert %{"status" => "failed", "value" => %{"code" => "usage_child_missing"}} =
             command(pid, "child_usage", %{"child_id" => Usage.id()})
  end

  test "snapshot scope, frozen prefixes and physical rows are checked before parent tail repair",
       c do
    pid = start(c)
    run(pid)
    parent = Session.info(pid).id
    %{"value" => %{"children" => [child | _]}} = command(pid, "children")
    args = %{"child_id" => child["child_id"], "limit" => 1}
    %{"status" => "ok", "value" => page} = command(pid, "child_usage", args)
    file = child_file(c, parent, child["child_id"])
    original = File.read!(file)
    assert page["snapshot"]["sha256"] == Ipse.JSON.digest([page["requests"]])

    File.write!(
      file,
      original <>
        Jason.encode!(%{"type" => "later_note", "private" => "must stay outside snapshot"}) <>
        "\n"
    )

    assert %{"value" => ^page} =
             command(pid, "child_usage", Map.put(args, "snapshot", page["snapshot"]))

    other = put_in(page["snapshot"], ["identity_sha256"], String.duplicate("a", 64))

    assert %{"status" => "failed", "value" => %{"code" => "usage_child_snapshot"}} =
             command(pid, "child_usage", Map.put(args, "snapshot", other))

    :ok = Session.close(pid)
    {:ok, events} = Journal.load(c.dir, parent)
    assert :ok = ChildUsage.validate_sources(c.dir, parent, events)

    File.write!(
      file,
      String.replace(original, "\"output_tokens\":5", "\"output_tokens\":6")
    )

    assert {:error, :invalid_extension_child_usage} =
             ChildUsage.validate_sources(c.dir, parent, events)

    path = Path.join(c.dir, parent <> ".jsonl")
    File.write!(path, "{\"truncated\":", [:append])
    before = File.read!(path)

    assert {:error, _} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                config: c.config,
                cwd: c.root,
                state_dir: c.dir,
                id: parent,
                subscriber: self(),
                owner: self()}
             )

    assert File.read!(path) == before
  end

  test "symlinked child files, changed origin and oversized journals refuse without repair", c do
    pid = start(c)
    run(pid)
    parent = Session.info(pid).id
    %{"value" => %{"children" => [child | _]}} = command(pid, "children")
    args = %{"child_id" => child["child_id"]}
    file = child_file(c, parent, child["child_id"])
    original = File.read!(file)
    saved = file <> ".saved"
    File.rename!(file, saved)
    File.ln_s!(saved, file)
    assert %{"status" => "failed"} = command(pid, "child_usage", args)
    File.rm!(file)
    File.rename!(saved, file)
    File.write!(file, String.replace(original, "synthetic-call/0", "unrelated-origin"))
    File.write!(file, String.replace(File.read!(file), "synthetic-call/1", "unrelated-origin"))

    assert %{"status" => "failed", "value" => %{"code" => "usage_child_invalid"}} =
             command(pid, "child_usage", args)

    File.write!(file, original <> String.duplicate("x", 16_777_217))

    assert %{"status" => "failed", "value" => %{"code" => "usage_child_bounds"}} =
             command(pid, "child_usage", args)

    assert File.stat!(file).size > 16_777_216
    File.write!(file, original)
  end
end
