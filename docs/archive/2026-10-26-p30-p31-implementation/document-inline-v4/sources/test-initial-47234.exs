defmodule Ipse.Session.DocumentEmbeddingTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Usage}
  alias Ipse.Extension.{CollectionStore, EmbeddingCall}
  alias Ipse.Extension.Collection.Profile
  alias Ipse.Session.{DocumentEmbedding, Invocation}

  defp fixture do
    operator = %{
      "version" => 2,
      "id" => "documents",
      "scope" => "project",
      "profile" => Profile.documents(),
      "source_use" => "shared_producer_v1"
    }

    identity = %{
      "scope" => "operator",
      "capabilities" => ["host.embedding", "host.collection.store"],
      "collection_binding" => operator
    }

    project = %{
      "version" => 1,
      "project_id" => JSON.sha256("project"),
      "worktree_id" => JSON.sha256("worktree"),
      "scope" => "folder",
      "root" => "/fixture",
      "primary_root" => "/fixture",
      "common_directory" => nil,
      "binding_sha256" => JSON.sha256("binding")
    }

    session = Usage.id()
    parent = %{"identity" => identity, "invocation_id" => Usage.id()}

    config = %{
      provider: :ollama,
      model: "unused-main",
      timeout_ms: 20_000,
      extensions: [%{identity: identity}],
      embedding_profiles: %{
        "encoder" => %{
          "operation" => "embedding",
          "provider" => "ollama",
          "model" => "fixture",
          "dimensions" => 1024,
          "dimension_mode" => "native",
          "base_url" => "http://127.0.0.1:11555",
          "timeout_ms" => 20_000
        }
      }
    }

    profiles = %{"embedding_profiles" => Ipse.Config.Profiles.embedding_snapshot(config)}

    {:ok, profile} =
      EmbeddingCall.profile_binding(profiles, %{
        "op" => "embedding.profile",
        "version" => 1,
        "profile" => "encoder"
      })

    sha = JSON.sha256(~s({"kind":"synthetic claim"}))

    request = %{
      "op" => "embedding.create",
      "version" => 2,
      "profile" => "encoder",
      "timeout_ms" => 20_000,
      "inputs" => ["Synthetic exact source bytes"],
      "expected_selection_sha256" => profile["selection_sha256"],
      "source_guard" => %{
        "version" => 1,
        "claim_key" => "genproducer.notes",
        "claim_revision" => 2,
        "claim_sha256" => sha,
        "batch_index" => 0
      }
    }

    source = %{
      "kind" => "document_embedding_source",
      "version" => 1,
      "namespace" => CollectionStore.namespace(project["project_id"]),
      "profile" => Profile.documents(),
      "operator_binding" => operator,
      "project" => project,
      "session_id" => session,
      "identity_sha256" => JSON.digest([identity]),
      "request_sha256" => JSON.digest([request])
    }

    {:ok, binding} = EmbeddingCall.binding(config, request, source)

    %{
      identity: identity,
      project: project,
      session: session,
      parent: parent,
      config: config,
      request: request,
      binding: binding,
      invocation: %Invocation{parent: parent}
    }
  end

  defp store_event(c, request, result, operation) do
    outer = %{"op" => "collection.store", "scope" => "project", "request" => request}

    binding =
      c.binding["source_binding"]
      |> Map.put("kind", "document_store")
      |> Map.put("request_sha256", JSON.digest([outer]))

    %{
      "request" => outer,
      "effect_binding" => binding,
      "operation_id" => operation,
      "parent_invocation_id" => c.parent["invocation_id"],
      "outcome" => %{"status" => "ok", "value" => %{"result" => result}}
    }
  end

  # These exercise only the pure live-state transition. Session's separately
  # validated durable action path is the sole runtime caller of record_action.
  defp claim(c) do
    epoch = Usage.id()
    ref = %{"slot" => 0, "epoch" => epoch}
    data = ~s({"kind":"synthetic claim"})

    request = %{
      "op" => "value.prepare_inline",
      "slot" => 0,
      "epoch" => epoch,
      "key" => "genproducer.notes",
      "expected_revision" => 0,
      "byte_count" => byte_size(data),
      "sha256" => JSON.sha256(data),
      "data" => data,
      "generation" => 0
    }

    prepare = store_event(c, request, %{"stage" => ref}, Usage.id())

    commit =
      store_event(
        c,
        %{"op" => "commit", "stages" => [ref], "generation" => 1},
        %{"generation" => 2},
        Usage.id()
      )

    state =
      c.invocation
      |> DocumentEmbedding.record_action(prepare)
      |> DocumentEmbedding.record_action(commit)

    {state, prepare, commit}
  end

  defp inline_fixture do
    c = fixture()

    {seed, _} =
      Code.eval_file(
        "docs/archive/2026-10-26-p30-p31-implementation/shared-producer-host-seed/pending-v3-model.exs"
      )

    old = seed["records"]["genproducer.notes"]["value"]

    count =
      Enum.sum(
        Enum.map(old["source_bindings"], fn b ->
          seed["records"]["source.notes." <> b["source_key"]]["value"]["chunks"]
        end)
      )

    pending =
      Map.merge(old, %{
        "version" => 4,
        "recipe" => "ipse.evidence.shared_producer.pages.v4",
        "vector_cursor" => 0,
        "vector_count" => count,
        "previous_ready" => nil
      })

    data = JSON.encode!(pending) |> IO.iodata_to_binary()

    request = %{
      "op" => "value.put_inline",
      "key" => "genproducer4.notes.0",
      "expected_revision" => 0,
      "generation" => 10,
      "data" => data,
      "byte_count" => byte_size(data),
      "sha256" => JSON.sha256(data)
    }

    result = %{
      "generation" => 11,
      "floor" => 0,
      "request_sha256" => JSON.sha256("synthetic native request"),
      "key" => request["key"],
      "record" => Map.merge(Map.take(request, ~w(sha256 byte_count)), %{"revision" => 11})
    }

    event = store_event(c, request, result, Usage.id()) |> Map.put("approval", "approved")

    s = %{
      id: c.session,
      invocation: %{c.invocation | action: %{intent: event}},
      extension_output_clock: nil
    }

    %{c: c, pending: pending, request: request, event: event, state: s}
  end

  defp ready_record(pending) do
    sha = JSON.sha256("synthetic page")

    receipts =
      pending["inputs"]
      |> Enum.chunk_every(2)
      |> Enum.map(fn refs ->
        %{
          "operation_id" => Usage.id(),
          "source_sha256" => JSON.sha256("synthetic receipt"),
          "input_sha256" => Enum.map(refs, &Enum.at(&1, 3)),
          "raw_input_sha256" => Enum.map(refs, &Enum.at(&1, 4))
        }
      end)

    pending
    |> Map.drop(~w(source_bindings inputs))
    |> Map.merge(%{
      "status" => "ready",
      "claim" => %{
        "revision" => 4,
        "sha256" => JSON.sha256("claim"),
        "operation_id" => Usage.id()
      },
      "input_count" => length(pending["inputs"]),
      "input_refs_sha256" =>
        JSON.sha256(JSON.encode!(pending["inputs"]) |> IO.iodata_to_binary()),
      "receipts" => receipts,
      "page" => %{"key" => "genvec.notes." <> sha, "sha256" => sha, "byte_count" => 100}
    })
  end

  defp packed_read(value, revision) do
    bytes = JSON.encode!(value) |> IO.iodata_to_binary()

    fn _ ->
      {:ok,
       %{
         "revision" => revision,
         "operation_id" => Usage.id(),
         "value" => %{
           "version" => 1,
           "kind" => "document_value",
           "parts" => [bytes],
           "sha256" => JSON.sha256(bytes),
           "byte_count" => byte_size(bytes)
         }
       }}
    end
  end

  @tag document_inline_v4: true
  test "inline origin observes actual absence or closed ready at the pinned native generation" do
    f = inline_fixture()
    witness = %{"root" => %{"generation" => 10}}
    absent = fn _ -> {:ok, nil} end

    assert {:ok, %{revision: 0, sha256: nil}} =
             DocumentEmbedding.observe_inline(absent, witness, f.request)

    reuse = Map.put(f.request, "expected_revision", 9)
    ready = ready_record(f.pending)

    assert {:ok, %{revision: 9}} =
             DocumentEmbedding.observe_inline(packed_read(ready, 9), witness, reuse)

    for {reader, pin, request} <- [
          {absent, witness, reuse},
          {packed_read(ready, 9), witness, f.request},
          {packed_read(ready, 8), witness, reuse},
          {packed_read(f.pending, 9), witness, reuse},
          {packed_read(Map.put(ready, "unexpected", true), 9), witness, reuse},
          {packed_read(ready, 9), %{"root" => %{"generation" => 11}}, reuse}
        ] do
      assert {:error, :document_source_use_refused} =
               DocumentEmbedding.observe_inline(reader, pin, request)
    end
  end

  @tag document_inline_v4: true
  test "only the exact observed current action and known inline result seed a v4 live origin" do
    f = inline_fixture()

    assert {:ok, observed} =
             DocumentEmbedding.observe_inline(
               fn _ -> {:ok, nil} end,
               %{"root" => %{"generation" => 10}},
               f.request
             )

    assert {:reply, :ok, s} = DocumentEmbedding.prepare_inline(f.state, f.event, observed)
    live = DocumentEmbedding.record_action(s.invocation, f.event)
    assert live.document_producer.claim.operation_id === f.event["operation_id"]
    assert live.document_producer.claim.revision === 11
    assert live.document_producer.claim.guard_version === 2

    request =
      f.c.request
      |> put_in(["source_guard", "version"], 2)
      |> put_in(["source_guard", "claim_key"], f.request["key"])
      |> put_in(["source_guard", "claim_revision"], 11)
      |> put_in(["source_guard", "claim_sha256"], f.request["sha256"])

    assert DocumentEmbedding.allowed?(live, request, f.c.binding)

    refute DocumentEmbedding.allowed?(
             live,
             put_in(request, ["source_guard", "version"], 1),
             f.c.binding
           )

    refute DocumentEmbedding.allowed?(%{live | document_producer: nil}, request, f.c.binding)

    assert {:reply, {:error, :document_source_use_refused}, _} =
             DocumentEmbedding.prepare_inline(s, f.event, observed)

    for altered <- [
          Map.put(observed, :generation, 11),
          Map.put(observed, :body_sha256, JSON.sha256("foreign")),
          Map.put(observed, :sha256, JSON.sha256("unexpected old row")),
          Map.put(observed, :extra, true)
        ] do
      assert {:reply, {:error, :document_source_use_refused}, _} =
               DocumentEmbedding.prepare_inline(f.state, f.event, altered)
    end

    foreign = Map.put(f.event, "operation_id", Usage.id())

    assert {:reply, {:error, :document_source_use_refused}, _} =
             DocumentEmbedding.prepare_inline(f.state, foreign, observed)
  end

  @tag document_inline_v4: true
  test "unknown failed or mismatched inline outcomes consume the observation without authority" do
    f = inline_fixture()

    assert {:ok, observed} =
             DocumentEmbedding.observe_inline(
               fn _ -> {:ok, nil} end,
               %{"root" => %{"generation" => 10}},
               f.request
             )

    assert {:reply, :ok, s} = DocumentEmbedding.prepare_inline(f.state, f.event, observed)

    for event <- [
          put_in(f.event, ["outcome", "status"], "unknown"),
          put_in(f.event, ["outcome", "status"], "failed"),
          Map.put(f.event, "operation_id", Usage.id()),
          put_in(
            f.event,
            ["outcome", "value", "result", "record", "sha256"],
            JSON.sha256("foreign")
          )
        ] do
      refused = DocumentEmbedding.record_action(s.invocation, event)
      assert refused.document_producer.status === :poisoned
      assert is_nil(refused.document_producer.claim) and is_nil(refused.document_producer.inline)
      refute DocumentEmbedding.record_action(refused, f.event).document_producer.claim
    end
  end

  @tag document_guard_repair: true
  test "operator selection is explicit, closed and identity-aware; legacy creates cannot omit the guard" do
    c = fixture()
    assert CollectionStore.operator_binding?(c.identity["collection_binding"])

    assert CollectionStore.trust_bindings?([
             Map.put(c.identity["collection_binding"], "instance", "corpus")
           ])

    refute CollectionStore.operator_binding?(
             put_in(c.identity["collection_binding"], ["source_use"], "arbitrary")
           )

    ordinary = Map.delete(c.request, "source_guard")
    {:ok, old_binding} = EmbeddingCall.binding(c.config, ordinary)
    refute EmbeddingCall.valid_identity?(c.identity, ordinary, old_binding)

    legacy =
      c.identity
      |> put_in(["collection_binding", "version"], 1)
      |> update_in(["collection_binding"], &Map.delete(&1, "source_use"))

    assert CollectionStore.operator_binding?(legacy["collection_binding"])
    assert EmbeddingCall.valid_identity?(legacy, ordinary, old_binding)
    assert EmbeddingCall.valid_identity?(c.identity, c.request, c.binding)
    assert EmbeddingCall.valid_identity?(c.identity, c.request, c.binding, c.session)
    refute EmbeddingCall.valid_identity?(c.identity, c.request, c.binding, Usage.id())
    refute EmbeddingCall.valid_identity?(legacy, c.request, c.binding)

    refute EmbeddingCall.valid_identity?(
             c.identity,
             c.request,
             put_in(c.binding, ["source_binding", "identity_sha256"], JSON.sha256("foreign"))
           )

    refute EmbeddingCall.validate(Map.delete(c.request, "expected_selection_sha256")) == :ok
    refute EmbeddingCall.validate(put_in(c.request, ["source_guard", "batch_index"], 4)) == :ok
  end

  @tag document_guard_repair: true
  test "actual configuration schema accepts only the closed operator opt-in and preserves v1" do
    c = fixture()
    binding = Map.put(c.identity["collection_binding"], "instance", "corpus")

    trust = %{
      "artifact" => String.duplicate("a", 64),
      "capabilities" => c.identity["capabilities"],
      "allow_project" => false,
      "allow_children" => false,
      "collection_bindings" => [binding]
    }

    data = %{"extensions" => [], "extension_trust" => [trust]}
    assert :ok = Ipse.Extension.Config.validate(data)

    assert {:ok, _} =
             Ipse.Extension.Config.resolve(
               [%{scope: "operator", path: "/fixture/operator.json", data: data}],
               []
             )

    old = binding |> Map.put("version", 1) |> Map.delete("source_use")

    assert :ok =
             Ipse.Extension.Config.validate(
               put_in(data, ["extension_trust", Access.at(0), "collection_bindings"], [old])
             )

    for invalid <- [
          Map.delete(binding, "source_use"),
          Map.put(binding, "version", 1),
          Map.put(binding, "version", 3),
          Map.put(binding, "extra", true)
        ] do
      refute Ipse.Extension.Config.validate(
               put_in(data, ["extension_trust", Access.at(0), "collection_bindings"], [invalid])
             ) == :ok
    end
  end

  @tag document_guard_repair: true
  test "dispatch retains the original monotonic clock and exact selected identity" do
    c = fixture()

    invocation = %{
      c.invocation
      | action: %{intent: %{"request" => c.request, "effect_binding" => c.binding}}
    }

    data =
      DocumentEmbedding.dispatch_data(%{
        invocation: invocation,
        extension_output_clock: %{started_ms: 17}
      })

    assert data.deadline_ms === 120_017 and data.identity === c.identity

    assert DocumentEmbedding.dispatch_data(%{invocation: invocation, extension_output_clock: nil}).deadline_ms ===
             nil
  end

  test "only a newly confirmed prepare and matching original live commit create a claim" do
    c = fixture()
    refute DocumentEmbedding.allowed?(c.invocation, c.request, c.binding)
    {live, prepare, commit} = claim(c)
    assert DocumentEmbedding.allowed?(live, c.request, c.binding)
    assert live.document_producer.claim.operation_id == commit["operation_id"]
    restored = %Invocation{parent: c.parent, results: [prepare, commit]}
    refute DocumentEmbedding.allowed?(restored, c.request, c.binding)

    refute DocumentEmbedding.allowed?(
             live,
             put_in(c.request, ["source_guard", "claim_revision"], 3),
             c.binding
           )

    refute DocumentEmbedding.allowed?(
             %{live | parent: %{c.parent | "invocation_id" => Usage.id()}},
             c.request,
             c.binding
           )

    refute DocumentEmbedding.allowed?(
             live,
             c.request,
             put_in(c.binding, ["source_binding", "namespace"], JSON.sha256("foreign"))
           )
  end

  test "foreign, repeated, unknown or replacement origin cannot create or renew live authority" do
    c = fixture()
    {live, prepare, commit} = claim(c)

    wrong =
      put_in(commit, ["request", "request", "stages"], [%{"slot" => 1, "epoch" => Usage.id()}])

    wrong =
      update_in(wrong, ["effect_binding", "request_sha256"], fn _ ->
        JSON.digest([wrong["request"]])
      end)

    bad =
      c.invocation
      |> DocumentEmbedding.record_action(prepare)
      |> DocumentEmbedding.record_action(wrong)

    refute DocumentEmbedding.allowed?(bad, c.request, c.binding)

    repeated =
      c.invocation
      |> DocumentEmbedding.record_action(prepare)
      |> DocumentEmbedding.record_action(prepare)
      |> DocumentEmbedding.record_action(commit)

    assert repeated.document_producer.status == :poisoned
    unknown = put_in(commit, ["outcome", "status"], "unknown")

    pending =
      c.invocation
      |> DocumentEmbedding.record_action(prepare)
      |> DocumentEmbedding.record_action(unknown)

    refute DocumentEmbedding.allowed?(pending, c.request, c.binding)

    kept =
      live |> DocumentEmbedding.record_action(prepare) |> DocumentEmbedding.record_action(commit)

    assert kept.document_producer.claim === live.document_producer.claim
  end

  test "only matching known batch results advance and duplicate or failed outcomes poison" do
    c = fixture()
    {live, _, _} = claim(c)
    operation = Usage.id()

    inflight = %{
      live
      | document_producer: %{
          live.document_producer
          | status: :inflight,
            inflight: operation,
            count: 2
        }
    }

    event = %{
      "request" => c.request,
      "operation_id" => operation,
      "outcome" => %{"status" => "ok"}
    }

    next = DocumentEmbedding.record_action(inflight, event)
    assert next.document_producer.next === 1 and next.document_producer.status === :ready
    assert DocumentEmbedding.record_action(next, event).document_producer.status === :poisoned

    assert DocumentEmbedding.record_action(
             inflight,
             put_in(event, ["outcome", "status"], "unknown")
           ).document_producer.status === :poisoned

    assert DocumentEmbedding.record_action(inflight, Map.put(event, "operation_id", Usage.id())).document_producer.status ===
             :poisoned

    final = %{inflight | document_producer: %{inflight.document_producer | next: 1}}
    assert DocumentEmbedding.record_action(final, event).document_producer.status === :done
  end
end
