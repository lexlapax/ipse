defmodule Ipse.Extensions.MemoryTest do
  use ExUnit.Case, async: false
  alias Ipse.Extensions.{Memory, State, WorkingMemory}
  alias Ipse.Extensions.Memory.Records

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

  test "transitive derived recall and portable export suppress forgotten ancestors", ctx do
    assert remember(ctx, "original")["status"] == "stored"
    assert remember(ctx, "derived", %{"derived_from" => ["original"]})["status"] == "stored"
    assert remember(ctx, "grandchild", %{"derived_from" => ["derived"]})["status"] == "stored"
    assert length(invoke(ctx, "recall", %{"query" => "supervision"})["matches"]) == 3

    assert invoke(ctx, "forget", %{"source" => "original", "expected_revision" => 1})["status"] ==
             "stored"

    assert invoke(ctx, "recall", %{"query" => "supervision"})["matches"] == []

    assert Enum.all?(
             invoke(ctx, "export", %{"limit" => 16})["records"],
             &(&1["value"]["state"] == "suppressed")
           )

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
           |> get_in(["value", "state"]) == "suppressed"
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

    assert invoke(ctx, "export", %{})["records"] |> hd() |> get_in(["value", "state"]) ==
             "suppressed"

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
