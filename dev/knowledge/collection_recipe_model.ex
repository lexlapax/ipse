defmodule Ipse.CollectionRecipeModel do
  @moduledoc """
  Developer-only request ledger, derived from the frozen CollectionProtocol fixture.
  Reuses actual SDK/Core validators and extension continuations, with no filesystem
  store, authority, acquisition, model, native dispatch or qualification claim.
  """
  import ExUnit.Assertions
  alias IpseKnowledge.Store.Collection, as: C
  alias IpseKnowledge.Store.Collection.Paged
  alias Ipse.JSON, as: J
  alias Ipse.Extension
  alias Ipse.Extension.CollectionStore
  alias Ipse.Extension.Collection.DocumentDraft

  def new(records, generation, opts \\ []) do
    owner = %{
      "project_id" => J.sha256("synthetic-recipe-project"),
      "session_id" => Ipse.Usage.id(),
      "identity_sha256" => J.sha256("synthetic-recipe-artifact"),
      "invocation_id" => Ipse.Usage.id()
    }

    %{
      records:
        Map.new(records, fn {key, value} ->
          assert generation > 0
          {key, %{value: value, revision: generation}}
        end),
      stages: %{},
      generation: generation,
      floor: 0,
      maintenance_epoch: Keyword.get(opts, :maintenance_epoch, 0),
      owner: owner,
      call_owner: owner,
      heads: %{},
      operations: %{},
      selected_inputs: %{},
      publications: [],
      public_sequence: 0,
      invocation: nil,
      public_results: [],
      unknown: [],
      peaks: %{
        records: map_size(records),
        private_records: 0,
        stages: 0,
        heads: 0,
        pending_bytes: 0
      },
      reads: 0,
      effects: 0,
      frames: [],
      requests: [],
      action_ids: [],
      action_intents: [],
      part_counts: [],
      outcomes: [],
      action_sequence: 0
    }
  end

  def reset(model),
    do: %{
      model
      | reads: 0,
        effects: 0,
        frames: [],
        requests: [],
        action_ids: [],
        action_intents: [],
        call_owner: model.owner,
        part_counts: [],
        outcomes: []
    }

  def packed_bytes(value) do
    bytes = json(value)

    parts =
      Stream.unfold(bytes, fn
        "" ->
          nil

        rest ->
          part = utf8(rest, min(byte_size(rest), 6144))
          {part, binary_part(rest, byte_size(part), byte_size(rest) - byte_size(part))}
      end)
      |> Enum.to_list()

    byte_size(
      json(%{
        "version" => 1,
        "kind" => "document_value",
        "sha256" => J.sha256(bytes),
        "byte_count" => byte_size(bytes),
        "parts" => parts
      })
    )
  end

  def run(result, model, hook \\ fn _, _ -> :continue end)

  def run({:call, request, continuation}, model, hook) do
    assert CollectionStore.validate(request) == :ok
    frame = %{"api_version" => 1, "kind" => "host_call", "request" => request}
    assert Extension.validate(frame) == :ok
    read = C.read_request?(request)

    {action_id, action_intent} = action_identity(request, model)

    model = %{
      model
      | reads: model.reads + if(read, do: 1, else: 0),
        effects: model.effects + if(read, do: 0, else: 1),
        frames: model.frames ++ [byte_size(json(frame))],
        requests: model.requests ++ [request],
        action_ids: model.action_ids ++ [action_id],
        action_intents: model.action_intents ++ [action_intent]
    }

    assert model.reads <= 512 and model.effects <= 16

    case hook.(request, model) do
      :stop ->
        {{:call, request, continuation}, model}

      :unknown ->
        outcome = %{"status" => "unknown", "value" => %{}}

        model = %{
          model
          | outcomes: model.outcomes ++ [outcome],
            unknown: model.unknown ++ [J.digest([request])]
        }

        {C.resume(continuation, outcome), model}

      :continue ->
        {outcome, model} = response(request, model)

        run(
          C.resume(continuation, outcome),
          %{model | outcomes: model.outcomes ++ [outcome]},
          hook
        )
    end
  end

  def run(terminal, model, _), do: {terminal, model}

  @doc "One closed-model Collection action for controllers which also own inference."
  def host(request, model) do
    {{:call, ^request, nil}, model} = run({:call, request, nil}, model, fn _, _ -> :stop end)
    {outcome, model} = response(request, model)
    {outcome, %{model | outcomes: model.outcomes ++ [outcome]}}
  end

  @doc "Drive the actual public controller against modeled Native and declared adapter replies."
  def public(
        resolved,
        command,
        arguments,
        model,
        adapter \\ fn _, _ -> raise "Unhandled public host request" end
      ) do
    session =
      if get_in(arguments, ["args", "input", "mode"]) in ~w(publish assemble),
        do: Ipse.Usage.id(),
        else: model.owner["session_id"]

    intent = public_intent(%{"id" => command, "arguments" => arguments}, session)
    payload = intent["payload"]
    framed = Ipse.Extension.Worker.frame(model.public_sequence + 1, "invoke.command", payload)

    if not match?({:ok, _}, framed) or Ipse.Extension.Invocation.validate_intent(intent) !== :ok do
      {{:blocked, :public_input_frame}, model}
    else
      {:ok, frame} = framed
      state = %{resolved: resolved, phase: :idle, ctx: nil, cont: nil, pending: nil}

      model = %{
        reset(model)
        | public_sequence: model.public_sequence + 1,
          invocation: intent,
          call_owner:
            model.owner
            |> Map.put("session_id", session)
            |> Map.put("invocation_id", intent["invocation_id"])
            |> Map.put("identity_sha256", J.digest([intent["identity"]])),
          public_results:
            model.public_results ++
              [%{command: command, input_bytes: byte_size(frame), kind: "pending"}]
      }

      public_drive(
        IpseKnowledge.Corpus.handle("invoke.command", payload, state),
        model,
        adapter,
        payload
      )
    end
  end

  defp public_drive(
         {:ok, %{"kind" => "host_call", "request" => request}, state},
         model,
         adapter,
         payload
       ) do
    assert Extension.validate(%{"api_version" => 1, "kind" => "host_call", "request" => request}) ===
             :ok

    {outcome, model} =
      if request["op"] === "collection.store" do
        host(request, model)
      else
        {outcome, model} = adapter.(request, model)
        {outcome, external(request, outcome, model)}
      end

    if outcome["status"] === "unknown" do
      {{:stop, :unknown_effect}, %{model | unknown: model.unknown ++ [J.digest([request])]}}
    else
      public_drive(
        IpseKnowledge.Corpus.handle("host.actions", %{"outcome" => outcome}, state),
        model,
        adapter,
        payload
      )
    end
  end

  defp public_drive({:ok, %{"kind" => "result", "value" => value}, _}, model, _, _) do
    model =
      public_result(model, %{
        kind: "inline",
        document_bytes: byte_size(json(value)),
        output_events: 0
      })

    {{:ok, value}, model}
  end

  defp public_drive(
         {:ok, %Ipse.Extension.ResultPublication.Output{} = output, _},
         model,
         _,
         payload
       ),
       do: publish(output, payload, model)

  defp public_drive(other, model, _, _), do: {other, model}

  defp external(request, outcome, model) do
    read = request["op"] in ~w(effect.result.read embedding.profile)
    true = read or request["op"] === "embedding.create"

    assert Extension.validate(%{"api_version" => 1, "kind" => "host_call", "request" => request}) ===
             :ok

    assert Extension.validate(outcome) === :ok

    model = %{
      model
      | reads: model.reads + if(read, do: 1, else: 0),
        effects: model.effects + if(read, do: 0, else: 1),
        requests: model.requests ++ [request],
        outcomes: model.outcomes ++ [outcome],
        frames: model.frames ++ [byte_size(json(request)), byte_size(json(outcome))],
        action_sequence: model.action_sequence + 1,
        action_ids: model.action_ids ++ [Ipse.Usage.id()]
    }

    assert model.reads <= 512 and model.effects <= 16
    model
  end

  defp public_intent(payload, session) do
    alias Ipse.Extension.Invocation
    hash = J.sha256("synthetic-recipe-artifact")

    identity =
      Map.new(
        ~w(artifact artifact_sha256 options_sha256 exports_sha256 requires_sha256 subscriptions_sha256 source_sha256 host_sha256),
        &{&1, hash}
      )
      |> Map.merge(%{
        "instance" => "recipe",
        "services" => [],
        "scope" => "operator",
        "sdk" => 2,
        "protocol" => 1,
        "capabilities" => ~w(invoke.command invoke.result.pages),
        "order" => 1,
        "lifetime" => "session",
        "expires_at" => nil,
        "runtime" => %{
          "architecture" => "fixture",
          "elixir" => "1.18.5",
          "erts" => "15",
          "otp" => "27"
        },
        "generation" => 1,
        "allow_children" => false
      })

    identity =
      if get_in(payload, ["arguments", "args", "input", "mode"]) === "assemble" do
        Map.merge(identity, %{
          "capabilities" =>
            ~w(invoke.command invoke.result.pages host.actions host.actions.mixed host.collection.store host.collection.read),
          "collection_binding" => %{
            "version" => 3,
            "id" => "documents",
            "scope" => "project",
            "profile" => Ipse.Extension.Collection.Profile.documents(),
            "source_use" => "shared_producer_v1",
            "input_validation" => %{
              "command_id" => "source",
              "action" => "restore",
              "export_action" => "backup_page",
              "plan_action" => "backup_plan"
            }
          }
        })
      else
        identity
      end

    descriptor = %{
      "id" => payload["id"],
      "description" => "Synthetic public recipe controller",
      "arguments_schema" => %{"type" => "object"},
      "result_schema" => %{"type" => "object"},
      "instance" => "recipe",
      "stage" => "invoke.command",
      "name" => "ext__recipe__" <> payload["id"]
    }

    intent =
      Invocation.intent(
        identity,
        descriptor,
        payload["arguments"],
        session,
        Ipse.Usage.id(),
        nil,
        nil,
        "operator_request"
      )

    intent
  end

  defp publish(output, _payload, model) do
    alias Ipse.Extension.{Actions, Invocation, ResultPublication, ResultSource}
    assert Enum.all?(model.action_intents, &is_map/1)
    intent = model.invocation
    producer_session = intent["payload"]["session_id"]
    {:ok, offer} = ResultPublication.offer(output)
    {:ok, begin, source} = ResultSource.open(intent, offer, 0)
    {:ok, transport} = ResultPublication.open(offer, intent["invocation_id"])
    {chunks, source} = drain_publication(output, source, transport, [])
    {:ok, seal, source} = ResultSource.seal(source, 0)

    results =
      Enum.zip(model.action_intents, model.outcomes)
      |> Enum.map(fn {action, outcome} ->
        {:ok, result} = Actions.result(action, outcome)

        true =
          Actions.valid_intent?(action, intent, "/synthetic/recipe") and
            Actions.valid_result?(result)

        result
      end)

    {:ok, final} =
      Invocation.build_saved_result(intent, ResultSource.descriptor(source), results, 0)

    action_events =
      Enum.zip(model.action_intents, results)
      |> Enum.flat_map(fn {action, result} -> [action, result] end)

    codec_events = [intent, begin] ++ chunks ++ [seal.event, final]
    events = [intent] ++ action_events ++ [begin] ++ chunks ++ [seal.event, final]
    {:ok, index} = ResultSource.restore(events)
    {:ok, %{bytes: bytes}} = ResultSource.materialize(index, final["delivery"])
    true = bytes === output.bytes
    ref = %{"version" => 1, "session_id" => producer_session, "delivery" => final["delivery"]}

    publication = %{
      ref: ref,
      bytes: bytes,
      event_count: length(codec_events),
      action_event_count: length(action_events),
      action_journal_bytes:
        Enum.sum(Enum.map(action_events, &(byte_size(Jason.encode!(&1)) + 1))),
      journal_bytes: Enum.sum(Enum.map(codec_events, &(byte_size(Jason.encode!(&1)) + 1))),
      scope:
        "production codec events only; modeled closed producer Session, not an actual journal"
    }

    model =
      %{
        model
        | selected_inputs: Map.put(model.selected_inputs, J.digest([ref]), publication),
          publications: model.publications ++ [publication]
      }
      |> public_result(%{
        kind: "sdk2_paged",
        document_bytes: byte_size(bytes),
        output_events: length(codec_events) - 2,
        codec_events: length(codec_events),
        codec_journal_bytes: publication.journal_bytes,
        action_journal_bytes: publication.action_journal_bytes,
        action_count: length(results),
        action_digest: final["actions_sha256"]
      })

    {{:published, ref}, model}
  end

  defp action_identity(request, model) do
    if get_in(model.invocation || %{}, ["payload", "arguments", "args", "input", "mode"]) ===
         "assemble" do
      true = request["request"]["op"] === "restore.input.read"
      identity = model.invocation["identity"]
      project_id = model.call_owner["project_id"]

      project = %{
        "version" => 1,
        "project_id" => project_id,
        "worktree_id" => J.sha256("synthetic-worktree"),
        "scope" => "folder",
        "root" => "/synthetic/recipe",
        "primary_root" => "/synthetic/recipe",
        "common_directory" => nil,
        "binding_sha256" => J.sha256("synthetic-binding")
      }

      binding = %{
        "kind" => "document_store",
        "version" => 1,
        "namespace" => CollectionStore.namespace(project_id),
        "profile" => Ipse.Extension.Collection.Profile.documents(),
        "operator_binding" => identity["collection_binding"],
        "project" => project,
        "session_id" => model.call_owner["session_id"],
        "identity_sha256" => J.digest([identity]),
        "request_sha256" => J.digest([request])
      }

      {:ok, action} =
        Ipse.Extension.Actions.intent(
          model.invocation,
          request,
          length(model.requests) + 1,
          "not_required",
          "/synthetic/recipe",
          nil,
          nil,
          binding
        )

      {action["operation_id"], action}
    else
      {Ipse.Usage.id(), nil}
    end
  end

  defp public_result(model, fields) do
    rows = List.update_at(model.public_results, -1, &Map.merge(&1, fields))
    %{model | public_results: rows}
  end

  defp drain_publication(output, source, transport, events) do
    if source.offset === output.byte_count do
      {Enum.reverse(events), source}
    else
      {:ok, request} = Ipse.Extension.ResultSource.request(source)
      {:ok, reply, transport} = Ipse.Extension.ResultPublication.chunk(output, transport, request)
      {:ok, event, source} = Ipse.Extension.ResultSource.push(source, reply)
      drain_publication(output, source, transport, [event | events])
    end
  end

  defp response(request, model) do
    id = List.last(model.action_ids)
    before = model

    {value, model} =
      if request["request"]["op"] === "restore.input.read",
        do: selected_read(request, model),
        else: execute(request["request"], model)

    model =
      if model.generation > before.generation, do: %{model | floor: model.generation}, else: model

    value =
      if is_map(request["request"]["progress"]),
        do: Map.put(value, "request_sha256", J.digest([request])),
        else: value

    wrapped = %{
      "version" => 1,
      "operation_id" => id,
      "request_sha256" => J.digest([request]),
      "result" => value
    }

    {wrapped, model} =
      cond do
        request["request"]["op"] === "restore.input.read" ->
          {wrapped |> Map.put("version", 3) |> Map.put("owner", model.call_owner), model}

        is_map(request["request"]["progress"]) ->
          {receipt, model} = progress(before, model, request["request"], id)
          {wrapped |> Map.put("version", 2) |> Map.put("progress", receipt), model}

        true ->
          {wrapped, model}
      end

    assert CollectionStore.valid_outcome?(request, "ok", wrapped, id),
           inspect({request, wrapped}, limit: :infinity)

    outcome = %{"status" => "ok", "value" => wrapped}
    assert Extension.validate(outcome) === :ok

    operations =
      if C.read_request?(request),
        do: model.operations,
        else:
          Map.put(model.operations, id, %{
            "generation" => model.generation,
            "floor" => model.floor,
            "request_sha256" => J.digest([request])
          })

    model = %{
      model
      | operations: operations,
        action_sequence: model.action_sequence + 1,
        frames: model.frames ++ [byte_size(json(outcome))]
    }

    {outcome, observe(model)}
  end

  defp execute(%{"op" => "snapshot"}, m),
    do:
      {Map.put(
         summary(m),
         "document_store",
         if(m.maintenance_epoch === 0,
           do: %{
             "version" => 2,
             "inline_bytes" => 8192,
             "write_parts" => 2
           },
           else: %{
             "version" => 4,
             "inline_bytes" => 8192,
             "write_parts" => 2,
             "maintenance_epoch" => m.maintenance_epoch,
             "maintenance_status" => "idle",
             "progress" => 1
           }
         )
       ), m}

  defp execute(%{"op" => "value.stat"} = r, m) do
    assert r["generation"] == m.generation
    {Map.merge(summary(m), %{"key" => r["key"], "record" => descriptor(m.records[r["key"]])}), m}
  end

  defp execute(%{"op" => "value.read"} = r, m) do
    assert r["generation"] == m.generation
    row = Map.fetch!(m.records, r["key"])
    bytes = json(row.value)
    data = slice(binary_part(bytes, r["offset"], byte_size(bytes) - r["offset"]))
    next = r["offset"] + byte_size(data)

    value =
      Map.merge(summary(m), descriptor(row))
      |> Map.merge(%{
        "key" => r["key"],
        "offset" => r["offset"],
        "data" => data,
        "next" => if(next < byte_size(bytes), do: next)
      })

    {value, m}
  end

  defp execute(%{"op" => "stage.list"}, m),
    do:
      {Map.put(
         summary(m),
         "stages",
         m.stages
         |> Map.values()
         |> Enum.map(&Map.take(&1, ~w(slot epoch state byte_count offset expires_at_ms)))
       ), m}

  defp execute(%{"op" => "stage.inspect"} = r, m) do
    assert r["generation"] == m.generation
    stage = Map.fetch!(m.stages, {r["slot"], r["epoch"]})

    {Map.put(
       summary(m),
       "stage",
       Map.take(
         stage,
         ~w(slot epoch key expected_revision byte_count sha256 state offset expires_at_ms write_publish)
       )
     ), m}
  end

  defp execute(%{"op" => "stage.available"}, m),
    do:
      {Map.put(summary(m), "available_slots", DocumentDraft.available_slots(native_state(m))), m}

  defp execute(%{"op" => "progress.inspect", "head_id" => id}, m) do
    head = Map.fetch!(m.heads, id)
    receipt = DocumentDraft.receipt(head, head, "continue", head["revision"], m.maintenance_epoch)
    {Map.put(summary(m), "progress", receipt), m}
  end

  defp execute(%{"op" => "progress.retire"} = r, m) do
    m = %{m | generation: m.generation + 1}
    {mutation(m, r), m}
  end

  defp execute(%{"op" => "value.verify"} = r, m) do
    row = Map.fetch!(m.records, r["key"])
    assert row.revision === r["expected_revision"]
    assert descriptor(row)["sha256"] === r["sha256"]
    assert descriptor(row)["byte_count"] === r["byte_count"]
    m = %{m | generation: m.generation + 1}
    {mutation(m, r), m}
  end

  defp execute(%{"op" => "value.abort"} = r, m) do
    true = Map.has_key?(m.stages, {r["slot"], r["epoch"]})
    m = %{m | generation: m.generation + 1, stages: Map.delete(m.stages, {r["slot"], r["epoch"]})}
    {mutation(m, r), m}
  end

  defp execute(%{"op" => "value.prepare_inline"} = r, m) do
    assert r["generation"] == m.generation
    false = Map.has_key?(m.stages, {r["slot"], r["epoch"]})
    value = Jason.decode!(r["data"])
    assert Paged.native_value?(value)
    assert J.sha256(r["data"]) === r["sha256"] and byte_size(r["data"]) === r["byte_count"]

    stage =
      Map.take(r, ~w(slot epoch key expected_revision byte_count sha256))
      |> Map.merge(%{
        "state" => "sealed",
        "offset" => r["byte_count"],
        "expires_at_ms" => 2_000_000_000_000,
        "value" => value,
        "parts" => [r["data"]]
      })

    m = %{
      m
      | generation: m.generation + 1,
        stages: Map.put(m.stages, {r["slot"], r["epoch"]}, stage),
        part_counts: m.part_counts ++ [div(r["byte_count"] + 6143, 6144)]
    }

    {Map.put(
       mutation(m, r),
       "stage",
       Map.take(
         stage,
         ~w(slot epoch key expected_revision byte_count sha256 state offset expires_at_ms)
       )
       |> Map.put("version", 1)
     ), m}
  end

  defp execute(%{"op" => "value.write_parts"} = r, m) do
    assert r["generation"] == m.generation
    ref = {r["slot"], r["epoch"]}
    previous = Map.get(m.stages, ref, %{"parts" => [], "offset" => 0})
    assert previous["offset"] == r["offset"]
    parts = previous["parts"] ++ r["data"]
    assert length(parts) <= 10
    bytes = IO.iodata_to_binary(parts)
    complete = byte_size(bytes) == r["byte_count"]

    stage =
      Map.take(r, ~w(slot epoch key expected_revision byte_count sha256))
      |> Map.merge(%{
        "state" => if(complete, do: "sealed", else: "open"),
        "offset" => byte_size(bytes),
        "expires_at_ms" => 2_000_000_000_000,
        "write_publish" => r["publish"],
        "parts" => parts
      })

    stage =
      if complete do
        assert J.sha256(bytes) == r["sha256"]
        value = Jason.decode!(bytes)
        assert Paged.native_value?(value)
        Map.put(stage, "value", value)
      else
        stage
      end

    m = %{
      m
      | generation: m.generation + 1,
        stages: Map.put(m.stages, ref, stage),
        part_counts: m.part_counts ++ [length(parts)]
    }

    write =
      Map.take(
        stage,
        ~w(slot epoch key expected_revision byte_count sha256 offset state expires_at_ms)
      )
      |> Map.merge(%{"publish" => r["publish"], "revision" => 0})

    {write, m} =
      if complete and r["publish"] do
        assert (m.records[r["key"]] || %{revision: 0}).revision == r["expected_revision"]

        m = %{
          m
          | records:
              Map.put(m.records, r["key"], %{value: stage["value"], revision: m.generation}),
            stages: Map.delete(m.stages, ref)
        }

        {%{write | "state" => "published", "revision" => m.generation}, m}
      else
        {write, m}
      end

    {Map.put(mutation(m, r), "write", write), m}
  end

  defp execute(%{"op" => "value.put_inline"} = r, m) do
    assert r["generation"] == m.generation
    assert (m.records[r["key"]] || %{revision: 0}).revision == r["expected_revision"]
    value = Jason.decode!(r["data"])
    assert Paged.native_value?(value)
    assert J.sha256(r["data"]) === r["sha256"] and byte_size(r["data"]) === r["byte_count"]

    m = %{
      m
      | generation: m.generation + 1,
        records: Map.put(m.records, r["key"], %{value: value, revision: m.generation + 1})
    }

    {Map.merge(mutation(m, r), %{"key" => r["key"], "record" => descriptor(m.records[r["key"]])}),
     m}
  end

  defp execute(%{"op" => "commit"} = r, m) do
    assert r["generation"] == m.generation
    next = m.generation + 1

    {records, stages} =
      Enum.reduce(r["stages"], {m.records, m.stages}, fn ref, {records, stages} ->
        stage = Map.fetch!(stages, {ref["slot"], ref["epoch"]})
        assert stage["state"] == "sealed"
        assert (records[stage["key"]] || %{revision: 0}).revision == stage["expected_revision"]
        assert Paged.native_value?(stage["value"])

        {Map.put(records, stage["key"], %{value: stage["value"], revision: next}),
         Map.delete(stages, {ref["slot"], ref["epoch"]})}
      end)

    m = %{m | records: records, stages: stages, generation: next}
    {mutation(m, r), m}
  end

  defp descriptor(nil), do: nil

  defp descriptor(row),
    do: %{
      "revision" => row.revision,
      "sha256" => J.sha256(json(row.value)),
      "byte_count" => byte_size(json(row.value))
    }

  defp summary(m),
    do: %{
      "version" => 3,
      "project" => CollectionStore.namespace(m.owner["project_id"]),
      "generation" => m.generation,
      "floor" => m.floor,
      "floor_anchor" => nil
    }

  defp mutation(m, r),
    do: %{
      "generation" => m.generation,
      "floor" => m.generation,
      "request_sha256" => J.digest([r])
    }

  defp native_state(m) do
    stages = Map.new(m.stages, fn {{slot, _}, stage} -> {"host.stage.#{slot}.header", stage} end)

    %{
      "project" => CollectionStore.namespace(m.owner["project_id"]),
      "generation" => m.generation,
      "records" => Map.merge(m.records, stages),
      "operations" => m.operations,
      "imported_operations" => %{},
      "migration" => nil,
      "document_drafts" => m.heads,
      "document_maintenance" => %{
        "version" => 1,
        "epoch" => m.maintenance_epoch,
        "status" => "idle"
      }
    }
    |> then(fn state ->
      if m.heads === %{}, do: Map.delete(state, "document_drafts"), else: state
    end)
  end

  defp progress(before, after_model, request, id) do
    tag = request["progress"]

    {:ok, head} =
      if tag["action"] === "start",
        do:
          DocumentDraft.first_head(native_state(before), tag, id, before.owner, request["slot"]),
        else: DocumentDraft.authorize(native_state(before), tag, before.owner)

    changes = progress_changes(request)

    {:ok, next} =
      cond do
        tag["action"] === "retire" ->
          DocumentDraft.retire(
            head,
            tag,
            request,
            changes,
            after_model.generation,
            after_model.maintenance_epoch
          )

        request["op"] === "value.verify" ->
          DocumentDraft.verified_reuse(head, tag, after_model.generation)

        true ->
          DocumentDraft.step(head, tag, request, changes, after_model.generation)
      end

    receipt =
      DocumentDraft.receipt(
        head,
        next,
        tag["action"],
        after_model.generation,
        after_model.maintenance_epoch
      )

    true = DocumentDraft.receipt?(receipt)

    heads =
      if is_nil(next),
        do: Map.delete(before.heads, head["id"]),
        else: Map.put(before.heads, head["id"], next)

    {receipt, %{after_model | heads: heads}}
  end

  defp progress_changes(%{"op" => "commit", "stages" => refs}),
    do: Enum.flat_map(refs, &stage_changes(&1, nil, true))

  defp progress_changes(%{"op" => "value.abort"} = r), do: stage_changes(r, nil, true)

  defp progress_changes(%{"op" => "value.put_inline"} = r),
    do: [%{"key" => r["key"], "value" => true}]

  defp progress_changes(%{"op" => "value.prepare_inline"} = r), do: stage_changes(r, true, true)

  defp progress_changes(%{"op" => "value.write_parts"} = r) do
    complete = r["offset"] + Enum.sum(Enum.map(r["data"], &byte_size/1)) === r["byte_count"]

    if complete and r["publish"],
      do: [%{"key" => r["key"], "value" => true}],
      else: stage_changes(r, true, complete)
  end

  defp progress_changes(_), do: []

  defp stage_changes(r, value, ready) do
    for part <- if(ready, do: ~w(header ready), else: ["header"]),
        do: %{"key" => "host.stage.#{r["slot"]}.#{part}", "value" => value}
  end

  defp selected_read(request, m) do
    ref = request["result_input"]
    input = Map.fetch!(m.selected_inputs, J.digest([ref]))
    assert input.ref === ref and J.sha256(input.bytes) === ref["delivery"]["sha256"]
    offset = request["request"]["offset"]
    count = min(6144, byte_size(input.bytes) - offset)
    data = binary_part(input.bytes, offset, count)

    {%{
       "delivery" => ref["delivery"],
       "offset" => offset,
       "next" => if(offset + count < byte_size(input.bytes), do: offset + count),
       "data_base64" => Base.encode64(data),
       "sha256" => J.sha256(data),
       "origin" => nil
     }, m}
  end

  defp observe(m) do
    pending = Enum.sum(Enum.map(m.stages, fn {_, stage} -> stage["offset"] end))

    private_records =
      Enum.sum(
        Enum.map(m.stages, fn {_, stage} ->
          1 + div(stage["offset"] + 6143, 6144) + if(stage["state"] === "sealed", do: 1, else: 0)
        end)
      )

    assert map_size(m.records) + private_records <= 8192
    assert map_size(m.operations) + DocumentDraft.reserved_operations(native_state(m)) <= 32768

    peaks = %{
      records: map_size(m.records),
      private_records: private_records,
      stages: map_size(m.stages),
      heads: map_size(m.heads),
      pending_bytes: pending
    }

    %{m | peaks: Map.merge(m.peaks, peaks, fn _, old, current -> max(old, current) end)}
  end

  defp json(value), do: IO.iodata_to_binary(JSON.encode!(value))
  defp slice(bytes), do: prefix(bytes, 0, min(byte_size(bytes), 6144))
  defp prefix(bytes, low, high) when low == high, do: utf8(bytes, low)

  defp prefix(bytes, low, high) do
    mid = div(low + high + 1, 2)

    if byte_size(json(utf8(bytes, mid))) <= 8192,
      do: prefix(bytes, mid, high),
      else: prefix(bytes, low, mid - 1)
  end

  defp utf8(bytes, n) do
    value = binary_part(bytes, 0, n)
    if String.valid?(value), do: value, else: utf8(bytes, n - 1)
  end
end
