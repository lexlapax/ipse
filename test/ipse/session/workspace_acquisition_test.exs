defmodule Ipse.Session.WorkspaceAcquisitionTest do
  use ExUnit.Case, async: true

  alias Ipse.Extension.{Actions, Catalog, Invocation, Registry}
  alias Ipse.Session.{SourceIndex, SourceWindow, WorkspaceAcquisition}

  defp fixture do
    schema = %{"type" => "object", "additionalProperties" => true}

    descriptor = %{
      "id" => "source",
      "description" => "Synthetic acquisition",
      "arguments_schema" => schema,
      "result_schema" => schema
    }

    exports = Map.put(Catalog.empty(), "commands", [descriptor])
    digest = String.duplicate("a", 64)

    identity = %{
      "instance" => "fixture",
      "artifact" => digest,
      "artifact_sha256" => digest,
      "options_sha256" => digest,
      "exports_sha256" => Catalog.digest(exports),
      "requires_sha256" => digest,
      "subscriptions_sha256" => digest,
      "services" => [],
      "scope" => "operator",
      "source_sha256" => digest,
      "sdk" => 1,
      "protocol" => 1,
      "capabilities" => ~w(invoke.command host.actions host.actions.mixed host.tools),
      "order" => 1,
      "lifetime" => "session",
      "expires_at" => nil,
      "runtime" => %{
        "architecture" => "fixture",
        "elixir" => "fixture",
        "erts" => "fixture",
        "otp" => "fixture"
      },
      "host_sha256" => digest,
      "generation" => 1,
      "allow_children" => false
    }

    assert Registry.valid_identity?(identity)
    {:ok, catalog} = Catalog.snapshot(%{extensions: [%{identity: identity, exports: exports}]})
    [export] = catalog["entries"]
    session = String.duplicate("1", 32)
    origin = String.duplicate("b", 64)
    cwd = "/fixture/workspace"

    outer = %{
      "store" => "notes",
      "action" => "read_document",
      "args" => %{"source_id" => "fixture-source", "generation" => 1, "path" => "synthetic.docx"}
    }

    parent =
      Invocation.intent(
        identity,
        export,
        outer,
        session,
        String.duplicate("2", 32),
        nil,
        nil,
        "operator_request"
      )

    metadata = %{"cwd" => cwd, "extensions" => [identity], "extension_catalog" => catalog}
    assert Invocation.validate_intent(parent, metadata) == :ok

    %{
      session: session,
      origin: origin,
      cwd: cwd,
      parent: parent,
      identity_sha: Ipse.JSON.digest([identity]),
      state: WorkspaceAcquisition.new(metadata)
    }
  end

  defp start_request,
    do: %{
      "op" => "tool.call",
      "name" => "read",
      "timeout_ms" => 5000,
      "arguments" => %{"snapshot" => "start", "path" => "synthetic.docx"}
    }

  defp action(ctx, request, step, value) do
    {:ok, intent} =
      Actions.intent(
        ctx.parent,
        request,
        step,
        "not_required",
        ctx.cwd,
        String.duplicate("c", 64)
      )

    {:ok, result} =
      Actions.result(intent, %{"status" => "ok", "value" => %{"text" => Jason.encode!(value)}})

    {intent, result}
  end

  defp advance(ctx, state, event, parent \\ nil),
    do: WorkspaceAcquisition.advance(state, event, parent || ctx.parent, ctx.session, ctx.origin)

  defp opening(ctx, bytes, handle) do
    sha = Ipse.JSON.sha256(bytes)

    {intent, result} =
      action(ctx, start_request(), 1, %{
        "path" => "synthetic.docx",
        "byte_count" => byte_size(bytes),
        "sha256" => sha,
        "handle" => handle
      })

    state = ctx.state |> then(&advance(ctx, &1, intent)) |> then(&advance(ctx, &1, result))
    {state, intent, result, sha}
  end

  defp page(ctx, bytes, handle, sha, ordinal) do
    offset = ordinal * 4096
    size = min(4096, byte_size(bytes) - offset)
    chunk = binary_part(bytes, offset, size)
    finish = offset + size

    request = %{
      "op" => "tool.call",
      "name" => "read",
      "timeout_ms" => 5000,
      "arguments" => %{
        "snapshot" => "page",
        "path" => "synthetic.docx",
        "expected_sha256" => sha,
        "snapshot_handle" => handle,
        "byte_offset" => offset
      }
    }

    value = %{
      "path" => "synthetic.docx",
      "byte_count" => byte_size(bytes),
      "sha256" => sha,
      "handle" => handle,
      "offset" => offset,
      "data" => Base.encode64(chunk),
      "page_sha256" => Ipse.JSON.sha256(chunk),
      "next" => if(finish < byte_size(bytes), do: finish, else: nil)
    }

    action(ctx, request, ordinal + 2, value)
  end

  test "snapshot results inside a pending draft do not change source tracking" do
    ctx = fixture()
    {:ok, index} = SourceIndex.new(ctx.session, 1, ctx.origin)

    coverage =
      Map.new(
        ~w(observed indexed unavailable capacity_refused legacy_unverified pending_gaps refused),
        &{&1, 0}
      )

    window = %SourceWindow{
      index: index,
      draft_id: "draft",
      coverage: coverage,
      workspace_acquisitions: ctx.state
    }

    {intent, _} =
      action(ctx, start_request(), 1, %{
        "path" => "synthetic.docx",
        "byte_count" => 1,
        "sha256" => String.duplicate("b", 64),
        "handle" => String.duplicate("c", 32)
      })

    assert advance(ctx, ctx.state, intent, %{}).refused
    assert SourceWindow.advance(window, intent).workspace_acquisitions === ctx.state
  end

  test "the receipt requires paired ordered pages and exact Session, identity and origin" do
    ctx = fixture()
    bytes = :binary.copy("x", 32_769)
    handle = String.duplicate("4", 32)
    {state, intent, _, sha} = opening(ctx, bytes, handle)
    operation = intent["operation_id"]

    assert {:error, :workspace_acquisition_unavailable} =
             WorkspaceAcquisition.lookup(
               state,
               operation,
               ctx.session,
               ctx.origin,
               ctx.identity_sha
             )

    state =
      Enum.reduce(0..8, state, fn ordinal, state ->
        {intent, result} = page(ctx, bytes, handle, sha, ordinal)
        state |> then(&advance(ctx, &1, intent)) |> then(&advance(ctx, &1, result))
      end)

    assert {:ok, receipt} =
             WorkspaceAcquisition.lookup(
               state,
               operation,
               ctx.session,
               ctx.origin,
               ctx.identity_sha
             )

    assert receipt["byte_count"] === byte_size(bytes) and receipt["sha256"] === sha
    assert receipt["parent_invocation_id"] === ctx.parent["invocation_id"]
    assert receipt["path"] === "synthetic.docx"

    assert {:error, :workspace_acquisition_unavailable} =
             WorkspaceAcquisition.lookup(
               state,
               operation,
               ctx.session,
               String.duplicate("d", 64),
               ctx.identity_sha
             )

    assert {:error, :workspace_acquisition_unavailable} =
             WorkspaceAcquisition.lookup(
               state,
               operation,
               ctx.session,
               ctx.origin,
               String.duplicate("e", 64)
             )
  end

  test "forged pairs, duplicate operations and interrupted pages cannot create a receipt" do
    ctx = fixture()
    bytes = :binary.copy("x", 32_769)
    handle = String.duplicate("4", 32)
    {state, opening, result, sha} = opening(ctx, bytes, handle)

    forged_parent = put_in(ctx.parent, ["identity", "artifact_sha256"], String.duplicate("f", 64))
    assert advance(ctx, ctx.state, opening, forged_parent).refused
    pending = advance(ctx, ctx.state, opening)

    assert advance(ctx, pending, Map.put(result, "operation_id", String.duplicate("6", 32))).refused

    assert advance(ctx, state, opening).refused

    {page_intent, page_result} = page(ctx, bytes, handle, sha, 0)
    waiting = advance(ctx, state, page_intent)

    interrupted =
      WorkspaceAcquisition.advance(
        waiting,
        %{"type" => "cancelled"},
        nil,
        ctx.session,
        ctx.origin
      )

    assert interrupted.pending == nil and interrupted.active == %{}
    assert advance(ctx, interrupted, page_result).refused

    assert {:error, :workspace_acquisition_unavailable} =
             WorkspaceAcquisition.lookup(
               interrupted,
               opening["operation_id"],
               ctx.session,
               ctx.origin,
               ctx.identity_sha
             )
  end

  test "a matching staged continuation survives a turn and a forged result does not bind a plan" do
    ctx = fixture()
    bytes = "x"
    handle = String.duplicate("4", 32)
    {state, opening, start_result, sha} = opening(ctx, bytes, handle)
    {page_intent, page_result} = page(ctx, bytes, handle, sha, 0)
    state = state |> then(&advance(ctx, &1, page_intent)) |> then(&advance(ctx, &1, page_result))
    operation = opening["operation_id"]
    plan = String.duplicate("d", 64)
    outer = ctx.parent["payload"]["arguments"]

    args =
      outer["args"]
      |> Map.put("expected_sha256", sha)
      |> Map.put("collection_state", %{"plan_sha256" => plan})
      |> Map.put("opening_acquisition", %{
        "kind" => "workspace.read",
        "path" => "synthetic.docx",
        "operation_id" => operation
      })

    continuation = %{
      "id" => "source",
      "arguments" => %{
        "store" => outer["store"],
        "action" => "continue_collection_document",
        "args" => args
      }
    }

    value = %{"status" => "draft", "continuation" => continuation}

    {:ok, result} =
      Invocation.build_result(
        ctx.parent,
        %{"api_version" => 1, "kind" => "result", "value" => value},
        [start_result, page_result]
      )

    forged = Map.put(result, "text_sha256", String.duplicate("e", 64))
    forged_state = advance(ctx, state, forged)

    assert {:ok, unbound} =
             WorkspaceAcquisition.lookup(
               forged_state,
               operation,
               ctx.session,
               ctx.origin,
               ctx.identity_sha
             )

    refute Map.has_key?(unbound, "plan_sha256")

    state = advance(ctx, state, result)

    state =
      WorkspaceAcquisition.advance(
        state,
        %{"type" => "turn_finished"},
        nil,
        ctx.session,
        ctx.origin
      )

    assert {:ok, receipt} =
             WorkspaceAcquisition.lookup(
               state,
               operation,
               ctx.session,
               ctx.origin,
               ctx.identity_sha
             )

    assert receipt["plan_sha256"] === plan
  end

  test "sequential successful invocations reclaim receipt slots beyond sixteen acquisitions" do
    base = fixture()

    final =
      Enum.reduce(1..17, base.state, fn _, state ->
        parent =
          Invocation.intent(
            base.parent["identity"],
            base.parent["descriptor"],
            base.parent["payload"]["arguments"],
            base.session,
            Ipse.Usage.id(),
            nil,
            nil,
            "operator_request"
          )

        ctx = %{base | parent: parent, state: state}
        handle = Ipse.Usage.id()
        {state, opening, start_result, sha} = opening(ctx, "x", handle)
        {page_intent, page_result} = page(ctx, "x", handle, sha, 0)

        state =
          state |> then(&advance(ctx, &1, page_intent)) |> then(&advance(ctx, &1, page_result))

        operation = opening["operation_id"]

        assert {:ok, _} =
                 WorkspaceAcquisition.lookup(
                   state,
                   operation,
                   ctx.session,
                   ctx.origin,
                   ctx.identity_sha
                 )

        {:ok, result} =
          Invocation.build_result(
            parent,
            %{
              "api_version" => 1,
              "kind" => "result",
              "value" => %{"status" => "ok", "continuation" => nil}
            },
            [start_result, page_result]
          )

        forged = Map.put(result, "text_sha256", String.duplicate("e", 64))
        forged_state = advance(ctx, state, forged)

        assert {:ok, _} =
                 WorkspaceAcquisition.lookup(
                   forged_state,
                   operation,
                   ctx.session,
                   ctx.origin,
                   ctx.identity_sha
                 )

        state = advance(ctx, state, result)

        assert {:error, :workspace_acquisition_unavailable} =
                 WorkspaceAcquisition.lookup(
                   state,
                   operation,
                   ctx.session,
                   ctx.origin,
                   ctx.identity_sha
                 )

        state
      end)

    assert final.completed == %{}
    refute final.refused
  end
end
