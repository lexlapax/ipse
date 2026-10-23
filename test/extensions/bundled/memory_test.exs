defmodule Ipse.Builtins.MemoryTest do
  use ExUnit.Case, async: false
  alias Ipse.Builtins.Memory
  alias Ipse.Extension.State
  alias Ipse.Builtins.WorkingMemory
  alias Ipse.Builtins.Memory.Records

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-memory-" <> Ipse.Usage.id())
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, namespace: String.duplicate("a", 64)}
  end

  defp args(source, extra \\ %{}) do
    Map.merge(
      %{
        "source" => source,
        "source_generation" => 1,
        "title" => source,
        "text" => "A sourced fact about supervision",
        "kind" => "project_fact",
        "provenance" => "operator-confirmed:fixture",
        "expected_revision" => 0
      },
      extra
    )
  end

  defp begin_call(id, args) do
    {:ok, state} = Memory.init(%{"scope" => "project", "retention_seconds" => 3600})

    stage =
      if id in ~w(import export inventory collect migrate),
        do: "invoke.command",
        else: "invoke.tool"

    Memory.handle(stage, %{"id" => id, "arguments" => args}, state)
  end

  defp drive(ctx, {:ok, %{"kind" => "host_call", "request" => request}, state}, actions) do
    id = Ipse.Usage.id()
    {status, value} = State.execute(ctx.root, ctx.namespace, request, id)
    assert State.valid_outcome?(request, to_string(status), value, id)

    next =
      Memory.handle(
        "host.actions",
        %{"outcome" => %{"status" => to_string(status), "value" => value}},
        state
      )

    drive(ctx, next, [request | actions])
  end

  defp drive(_ctx, {:ok, %{"kind" => "result", "value" => value}, _}, actions),
    do: {value, Enum.reverse(actions)}

  defp invoke(ctx, id, args), do: drive(ctx, begin_call(id, args), []) |> elem(0)
  defp remember(ctx, source, extra \\ %{}), do: invoke(ctx, "remember", args(source, extra))
  defp inspect_note(ctx, source), do: invoke(ctx, "inspect", %{"source" => source})["record"]

  test "explicit notes rank with exact provenance and refuse stale updates or unconfigured retention",
       ctx do
    assert {:error, :invalid_memory_options} = Memory.init(%{"scope" => "project"})

    assert {:error, :invalid_memory_options} =
             WorkingMemory.init(%{"scope" => "project", "retention_seconds" => 3600})

    assert {:ok, _} = WorkingMemory.init(%{"scope" => "session", "retention_seconds" => 3600})

    assert remember(ctx, "docs/otp", %{"text" => "Supervision uses OTP monitors."})["status"] ==
             "stored"

    assert remember(ctx, "docs/http", %{"text" => "HTTP uses verified TLS."})["status"] ==
             "stored"

    recall = invoke(ctx, "recall", %{"query" => "OTP monitors"})
    assert recall["status"] == "recalled"
    assert [%{"source" => "docs/otp", "revision" => 1} = match] = recall["matches"]
    assert match["excerpt"] == "Supervision uses OTP monitors."

    assert binary_part(match["excerpt"], match["span"]["start_byte"], match["span"]["end_byte"]) ==
             match["excerpt"]

    assert invoke(ctx, "recall", %{"query" => "unanswerable"})["matches"] == []

    assert remember(ctx, "docs/otp", %{"expected_revision" => 1})["status"] ==
             "stale_source_generation"

    assert remember(ctx, "docs/otp", %{"source_generation" => 2})["status"] == "conflict"

    assert remember(ctx, "docs/otp", %{"expected_revision" => 1, "source_generation" => 2})[
             "revision"
           ] == 2

    assert remember(ctx, "long", %{"ttl_seconds" => 3601})["status"] == "invalid_note"

    assert remember(ctx, "unicode", %{"text" => String.duplicate("界", 1000)})["status"] ==
             "invalid_note"

    assert inspect_note(ctx, "long")["revision"] == 0

    assert remember(ctx, "escaped", %{"text" => String.duplicate(<<0>>, 2048)})["status"] ==
             "invalid_note"

    selected = invoke(ctx, "export", %{"sources" => ["docs/otp"], "limit" => 1})
    assert [%{"key" => key}] = selected["records"]
    assert key == Records.key("docs/otp")
    assert selected["next"] == nil
  end

  test "forget suppresses reread, stale continuation, reingestion, restart and old imports",
       ctx do
    assert remember(ctx, "source")["status"] == "stored"
    old = inspect_note(ctx, "source")

    {:ok, %{"request" => read}, state} =
      begin_call(
        "remember",
        args("source", %{"expected_revision" => 1, "source_generation" => 2})
      )

    {:ok, value} = State.execute(ctx.root, ctx.namespace, read, Ipse.Usage.id())

    delayed =
      Memory.handle("host.actions", %{"outcome" => %{"status" => "ok", "value" => value}}, state)

    assert invoke(ctx, "forget", %{"source" => "source", "expected_revision" => 1})["state"] ==
             "suppressed"

    assert {result, [_]} = drive(ctx, delayed, [])
    assert result["status"] == "conflict"

    assert remember(ctx, "source", %{"expected_revision" => 2, "source_generation" => 100})[
             "status"
           ] == "source_suppressed"

    assert invoke(ctx, "import", Map.take(old, ~w(key value)) |> Map.put("expected_revision", 2))[
             "status"
           ] == "source_suppressed"

    suppression = inspect_note(ctx, "source")
    refute Jason.encode!(suppression) =~ "supervision"
    refute Map.has_key?(suppression["value"], "source")
    assert invoke(ctx, "recall", %{"query" => "supervision"})["matches"] == []
    exported = invoke(ctx, "export", %{})
    assert [%{"value" => %{"state" => "suppressed"}}] = exported["records"]
    other = %{ctx | namespace: String.duplicate("b", 64)}

    assert invoke(other, "import", hd(exported["records"]) |> Map.put("expected_revision", 0))[
             "status"
           ] == "stored"

    assert invoke(
             other,
             "import",
             Map.take(old, ~w(key value)) |> Map.put("expected_revision", 1)
           )["status"] == "source_suppressed"
  end

  test "transitive derived recall excludes forgotten ancestors while export preserves records",
       ctx do
    assert remember(ctx, "original")["status"] == "stored"
    assert remember(ctx, "derived", %{"derived_from" => ["original"]})["status"] == "stored"
    assert remember(ctx, "grandchild", %{"derived_from" => ["derived"]})["status"] == "stored"
    assert length(invoke(ctx, "recall", %{"query" => "supervision"})["matches"]) == 3

    assert invoke(ctx, "forget", %{"source" => "original", "expected_revision" => 1})["status"] ==
             "stored"

    assert invoke(ctx, "recall", %{"query" => "supervision"})["matches"] == []

    exported =
      invoke(ctx, "export", %{"limit" => 16})["records"] |> Map.new(&{&1["key"], &1["value"]})

    assert exported[Records.key("original")]["state"] == "suppressed"
    assert exported[Records.key("derived")]["state"] == "active"
    assert exported[Records.key("derived")]["derived_from"] == ["original"]
    assert exported[Records.key("grandchild")]["derived_from"] == ["derived"]

    inventory = invoke(ctx, "inventory", %{"limit" => 16})
    assert length(inventory["records"]) == 3
    refute Jason.encode!(inventory) =~ "sourced fact"

    assert invoke(ctx, "collect", %{
             "source" => "derived",
             "cause_source" => "original",
             "expected_revision" => 1
           })["state"] == "suppressed"

    assert invoke(ctx, "collect", %{
             "source" => "grandchild",
             "cause_source" => "derived",
             "expected_revision" => 1
           })["state"] == "suppressed"

    for source <- ~w(original derived grandchild) do
      refute Map.has_key?(inspect_note(ctx, source)["value"], "text")
    end

    assert remember(ctx, "orphan", %{"derived_from" => ["missing-parent"]})["status"] == "stored"
    assert invoke(ctx, "recall", %{"query" => "supervision"})["matches"] == []

    assert invoke(ctx, "export", %{"sources" => ["orphan"]})["records"]
           |> hd()
           |> get_in(["value", "state"]) == "active"
  end

  test "model inspection hides expired and blocked text without changing stored notes", ctx do
    assert remember(ctx, "parent")["status"] == "stored"
    assert remember(ctx, "child", %{"derived_from" => ["parent"]})["status"] == "stored"
    assert remember(ctx, "grandchild", %{"derived_from" => ["child"]})["status"] == "stored"
    assert remember(ctx, "orphan", %{"derived_from" => ["absent"]})["status"] == "stored"
    assert remember(ctx, "visible")["status"] == "stored"

    assert invoke(ctx, "forget", %{"source" => "parent", "expected_revision" => 1})["status"] ==
             "stored"

    {:ok, expired} = Records.build(args("expired"), nil, 1000, 60)

    assert {:ok, _} =
             State.execute(
               ctx.root,
               ctx.namespace,
               %{
                 "op" => "state.put",
                 "scope" => "project",
                 "key" => Records.key("expired"),
                 "expected_revision" => 0,
                 "value" => expired
               },
               Ipse.Usage.id()
             )

    path = Path.join([ctx.root, ctx.namespace, "state.json"])
    before = File.read!(path)

    for source <- ~w(expired child grandchild orphan) do
      inspected = invoke(ctx, "inspect", %{"source" => source})
      assert inspected["status"] == "inspected"
      assert inspected["record"]["revision"] == 1
      refute Map.has_key?(inspected["record"]["value"], "text")
      refute Map.has_key?(inspected["record"]["value"], "title")
      refute Map.has_key?(inspected["record"]["value"], "provenance")
      assert inspected["visibility"] == "metadata_only"
    end

    assert inspect_note(ctx, "visible")["value"]["text"] == args("visible")["text"]
    assert inspect_note(ctx, "missing")["revision"] == 0
    assert File.read!(path) == before
  end

  test "inspection refuses a changed generation before reading dependency visibility", ctx do
    assert remember(ctx, "child", %{"derived_from" => ["parent"]})["status"] == "stored"
    {:ok, %{"request" => request}, state} = begin_call("inspect", %{"source" => "child"})
    assert {:ok, read} = State.execute(ctx.root, ctx.namespace, request, Ipse.Usage.id())

    next =
      Memory.handle("host.actions", %{"outcome" => %{"status" => "ok", "value" => read}}, state)

    assert {:ok, %{"kind" => "host_call", "request" => scan}, _} = next
    assert scan["op"] == "state.scan" and scan["generation"] == read["generation"]
    assert remember(ctx, "parent")["status"] == "stored"
    assert {result, [_]} = drive(ctx, next, [])
    assert result["status"] == "conflict"
    refute Jason.encode!(result) =~ "sourced fact"
  end

  test "remember and import validate expiry at completed read time", ctx do
    now = System.system_time(:millisecond)

    {:ok, previous} =
      Records.build(args("delayed-read", %{"ttl_seconds" => 2}), nil, now - 3000, 3600)

    key = Records.key("delayed-read")

    assert {:ok, _} =
             State.execute(
               ctx.root,
               ctx.namespace,
               %{
                 "op" => "state.put",
                 "scope" => "project",
                 "key" => key,
                 "expected_revision" => 0,
                 "value" => previous
               },
               Ipse.Usage.id()
             )

    update = args("delayed-read", %{"source_generation" => 2, "expected_revision" => 1})
    {:ok, incoming} = Records.build(update, nil, now, 3600)

    for {id, arguments} <- [
          {"remember", update},
          {"import", %{"key" => key, "value" => incoming, "expected_revision" => 1}}
        ] do
      {:ok, %{"request" => read}, state} = begin_call(id, arguments)
      # The invocation began while the target was live; its read completes after expiry.
      state = %{state | now: now - 2000}
      assert {:ok, value} = State.execute(ctx.root, ctx.namespace, read, Ipse.Usage.id())

      assert {:ok, %{"kind" => "result", "value" => %{"status" => "source_expired"}}, _} =
               Memory.handle(
                 "host.actions",
                 %{"outcome" => %{"status" => "ok", "value" => value}},
                 state
               )
    end
  end

  test "absent collection checks revisions without creating suppression", ctx do
    for {arguments, status} <- [
          {%{"source" => "missing", "expected_revision" => 0}, "not_found"},
          {%{"source" => "missing", "expected_revision" => 0, "cause_source" => "parent"},
           "not_found"},
          {%{"source" => "missing", "expected_revision" => 1}, "conflict"},
          {%{"source" => "missing", "expected_revision" => 1, "cause_source" => "parent"},
           "conflict"}
        ] do
      assert {result, [request]} = drive(ctx, begin_call("collect", arguments), [])
      assert request["op"] == "state.get"
      assert result["status"] == status
      assert inspect_note(ctx, "missing")["revision"] == 0
    end

    assert remember(ctx, "missing")["status"] == "stored"
  end

  test "unmigrated parents block transitive model reads until explicit migration", ctx do
    {:ok, parent} =
      Records.build(args("legacy-parent"), nil, System.system_time(:millisecond), 3600)

    legacy = parent |> Map.put("version", 1) |> Map.delete("derived_from")
    assert Records.valid?(legacy, Records.key("legacy-parent"))

    assert {:ok, _} =
             State.execute(
               ctx.root,
               ctx.namespace,
               %{
                 "op" => "state.put",
                 "scope" => "project",
                 "key" => Records.key("legacy-parent"),
                 "expected_revision" => 0,
                 "value" => legacy
               },
               Ipse.Usage.id()
             )

    assert remember(ctx, "child", %{"derived_from" => ["legacy-parent"]})["status"] == "stored"
    assert remember(ctx, "grandchild", %{"derived_from" => ["child"]})["status"] == "stored"

    for source <- ~w(legacy-parent child grandchild) do
      inspected = invoke(ctx, "inspect", %{"source" => source})
      assert inspected["visibility"] == "metadata_only"
      refute Map.has_key?(inspected["record"]["value"], "text")
    end

    assert invoke(ctx, "recall", %{"query" => "supervision"})["matches"] == []

    assert invoke(ctx, "migrate", %{"source" => "legacy-parent", "expected_revision" => 1})[
             "status"
           ] == "stored"

    assert invoke(ctx, "recall", %{"query" => "supervision"})["matches"]
           |> Enum.map(& &1["source"])
           |> Enum.sort() == ~w(child grandchild legacy-parent)

    assert invoke(ctx, "inspect", %{"source" => "grandchild"})["visibility"] == "full"
  end

  test "legacy active backups restore unchanged before explicit migration", ctx do
    for {source, now} <- [
          {"legacy-live", System.system_time(:millisecond)},
          {"legacy-expired", 1000}
        ] do
      {:ok, note} = Records.build(args(source), nil, now, 3600)
      legacy = note |> Map.put("version", 1) |> Map.delete("derived_from")

      assert {:ok, _} =
               State.execute(
                 ctx.root,
                 ctx.namespace,
                 %{
                   "op" => "state.put",
                   "scope" => "project",
                   "key" => Records.key(source),
                   "expected_revision" => 0,
                   "value" => legacy
                 },
                 Ipse.Usage.id()
               )
    end

    exported = invoke(ctx, "export", %{"limit" => 16})["records"]
    restored = %{ctx | namespace: String.duplicate("c", 64)}

    for record <- exported do
      assert invoke(restored, "import", Map.put(record, "expected_revision", 0))["status"] ==
               "stored"
    end

    assert invoke(restored, "export", %{"limit" => 16})["records"] == exported
    assert invoke(restored, "recall", %{"query" => "supervision"})["matches"] == []

    {:ok, replacement} =
      Records.build(
        args("legacy-live", %{"source_generation" => 2}),
        nil,
        System.system_time(:millisecond),
        3600
      )

    assert invoke(restored, "import", %{
             "key" => Records.key("legacy-live"),
             "value" => replacement,
             "expected_revision" => 1
           })["status"] == "migration_required"

    assert invoke(restored, "export", %{"limit" => 16})["records"] == exported

    for source <- ~w(legacy-live legacy-expired) do
      assert invoke(restored, "inspect", %{"source" => source})["visibility"] == "metadata_only"

      assert invoke(restored, "migrate", %{"source" => source, "expected_revision" => 1})[
               "status"
             ] == "stored"

      original = Enum.find(exported, &(&1["key"] == Records.key(source)))["value"]
      assert inspect_note(restored, source)["value"]["expires_at_ms"] == original["expires_at_ms"]
    end

    assert [%{"source" => "legacy-live"}] =
             invoke(restored, "recall", %{"query" => "supervision"})["matches"]

    {:ok, renewal} =
      Records.build(
        args("legacy-expired", %{"source_generation" => 2}),
        nil,
        System.system_time(:millisecond),
        3600
      )

    assert invoke(restored, "import", %{
             "key" => Records.key("legacy-expired"),
             "value" => renewal,
             "expected_revision" => 2
           })["status"] == "source_expired"
  end

  test "complete export restores blocked notes without inventing permanent suppression", ctx do
    assert remember(ctx, "child", %{"derived_from" => ["parent"]})["status"] == "stored"
    assert remember(ctx, "grandchild", %{"derived_from" => ["child"]})["status"] == "stored"
    assert remember(ctx, "forgotten-parent")["status"] == "stored"

    assert remember(ctx, "dependent", %{"derived_from" => ["forgotten-parent"]})["status"] ==
             "stored"

    assert invoke(ctx, "forget", %{"source" => "forgotten-parent", "expected_revision" => 1})[
             "status"
           ] == "stored"

    {:ok, expired} = Records.build(args("expired"), nil, 1000, 60)

    assert {:ok, _} =
             State.execute(
               ctx.root,
               ctx.namespace,
               %{
                 "op" => "state.put",
                 "scope" => "project",
                 "key" => Records.key("expired"),
                 "expected_revision" => 0,
                 "value" => expired
               },
               Ipse.Usage.id()
             )

    assert {:ok, page} =
             State.execute(
               ctx.root,
               ctx.namespace,
               %{
                 "op" => "state.scan",
                 "scope" => "project",
                 "after" => nil,
                 "generation" => nil,
                 "limit" => 16
               },
               Ipse.Usage.id()
             )

    exported = invoke(ctx, "export", %{"limit" => 16})
    assert exported["records"] == Enum.map(page["records"], &Map.take(&1, ~w(key value)))
    restored = %{ctx | namespace: String.duplicate("b", 64)}

    for record <- Enum.sort_by(exported["records"], &(&1["value"]["state"] != "suppressed")) do
      assert invoke(restored, "import", Map.put(record, "expected_revision", 0))["status"] ==
               "stored"
    end

    assert invoke(restored, "export", %{"limit" => 16})["records"] == exported["records"]

    for store <- [ctx, restored] do
      assert invoke(store, "recall", %{"query" => "supervision"})["matches"] == []
      assert remember(store, "parent")["status"] == "stored"

      assert invoke(store, "recall", %{"query" => "supervision"})["matches"]
             |> Enum.map(& &1["source"])
             |> Enum.sort() == ~w(child grandchild parent)

      assert remember(store, "dependent", %{"source_generation" => 2, "expected_revision" => 1})[
               "status"
             ] == "stored"

      assert inspect_note(store, "expired")["value"]["expires_at_ms"] == expired["expires_at_ms"]
      refute Map.has_key?(inspect_note(store, "expired")["value"], "text")

      assert remember(store, "expired", %{"source_generation" => 2, "expected_revision" => 1})[
               "status"
             ] == "source_expired"
    end
  end

  test "expiry hides notes without hidden writes, collection keeps suppression and migration is explicit",
       ctx do
    {:ok, expired} = Records.build(args("expired"), nil, 1000, 60)
    key = Records.key("expired")

    put = %{
      "op" => "state.put",
      "scope" => "project",
      "key" => key,
      "expected_revision" => 0,
      "value" => expired
    }

    assert {:ok, _} = State.execute(ctx.root, ctx.namespace, put, Ipse.Usage.id())
    file = Path.join([ctx.root, ctx.namespace, "state.json"])
    before = File.read!(file)
    assert invoke(ctx, "recall", %{"query" => "supervision"})["matches"] == []

    assert invoke(ctx, "export", %{})["records"] |> hd() |> Map.fetch!("value") == expired

    assert File.read!(file) == before

    assert remember(ctx, "expired", %{"source_generation" => 2, "expected_revision" => 1})[
             "status"
           ] == "source_expired"

    assert invoke(ctx, "collect", %{"source" => "expired", "expected_revision" => 1})["state"] ==
             "suppressed"

    assert remember(ctx, "fresh")["status"] == "stored"
    fresh = inspect_note(ctx, "fresh")
    legacy = fresh["value"] |> Map.put("version", 1) |> Map.delete("derived_from")
    assert Records.valid?(legacy, fresh["key"])

    assert {:ok, _} =
             State.execute(
               ctx.root,
               ctx.namespace,
               %{put | "key" => fresh["key"], "expected_revision" => 1, "value" => legacy},
               Ipse.Usage.id()
             )

    assert invoke(ctx, "recall", %{"query" => "supervision"})["matches"] == []

    assert invoke(ctx, "migrate", %{"source" => "fresh", "expected_revision" => 2})["status"] ==
             "stored"

    assert inspect_note(ctx, "fresh")["value"]["expires_at_ms"] == fresh["value"]["expires_at_ms"]
    assert length(invoke(ctx, "recall", %{"query" => "supervision"})["matches"]) == 1

    legacy_suppression =
      Records.suppress(Records.key("unknown-plaintext-id"), 7, 1000) |> Map.put("version", 1)

    assert invoke(ctx, "import", %{
             "key" => legacy_suppression["source_sha256"],
             "value" => legacy_suppression,
             "expected_revision" => 0
           })["state"] == "suppressed"

    persisted = inspect_note(ctx, "unknown-plaintext-id")["value"]
    assert persisted["version"] == 2
    assert persisted["source_generation"] == 7
    refute Map.has_key?(persisted, "source")

    assert remember(ctx, "unknown-plaintext-id", %{
             "expected_revision" => 1,
             "source_generation" => 8
           })["status"] == "source_suppressed"
  end
end
