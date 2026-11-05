Code.require_file("../../../dev/evaluation/protected_answer.exs", __DIR__)

defmodule Ipse.Development.Evaluation.ProtectedAnswerTest do
  use ExUnit.Case, async: true
  alias Ipse.JSON
  alias Ipse.Extension.{Invocation, ResultDocument, ResultSource, Worker}
  alias Ipse.Session.{ManagedLineage, ManagedOutput, ManagedReference, WorkerInput}
  alias Ipse.Development.Evaluation.{ProtectedAnswer, Metrics, SelectionExperiment}

  defp record(text \\ "Synthetic café observation") do
    key = "note." <> JSON.sha256(text)

    value = %{
      "text" => text,
      "evidence" => %{"sources" => [%{"attribution" => "constructed, not authority"}]}
    }

    encoded = Ipse.Extension.Collection.Migration.encode(value)

    row = %{
      "key" => key,
      "revision" => 7,
      "value" => value,
      "sha256" => JSON.sha256(encoded),
      "bytes" => byte_size(encoded),
      "operation_id" => String.duplicate("a", 32)
    }

    %{
      "key" => key,
      "revision" => 7,
      "outcome" => %{"status" => "ok", "value" => %{"record" => row}}
    }
  end

  defp response(record) do
    text = record["outcome"]["value"]["record"]["value"]["text"]

    %{
      "kind" => "answer",
      "text" => "A synthetic claim.",
      "citations" => [
        %{
          "key" => record["key"],
          "revision" => record["revision"],
          "start_byte" => 0,
          "end_byte" => byte_size(text),
          "quote" => text,
          "quote_sha256" => JSON.sha256(text),
          "claim_start_byte" => 0,
          "claim_end_byte" => 18
        }
      ]
    }
  end

  test "complete context and maximum query are preserved through the ordinary v4 validator" do
    r = record(String.duplicate("é", 1000))
    query = String.duplicate("q", 4096)
    assert {:ok, request} = ProtectedAnswer.request(query, [r])
    assert request["input"] === query
    assert {:ok, [outcome]} = JSON.decode_unique(request["context"])
    assert outcome === r["outcome"]
    assert request["version"] === 4 and request["timeout_ms"] === 3000
    assert request["response_schema"] === ProtectedAnswer.schema()
    assert {:error, _} = ProtectedAnswer.request(query <> "q", [r])
  end

  test "context cannot trim evidence, overflow SDK limits or duplicate source members" do
    r = record()
    assert {:error, _} = ProtectedAnswer.request("query", [r, r])
    assert {:error, _} = ProtectedAnswer.request("query", [])
    assert {:error, _} = ProtectedAnswer.request("query", Enum.map(1..17, &record(to_string(&1))))

    assert {:error, _} =
             ProtectedAnswer.request("query", [
               record(String.duplicate("a", 5000)),
               record(String.duplicate("b", 5000))
             ])

    assert {:error, _} =
             ProtectedAnswer.request("query", [
               put_in(r, ["outcome", "value", "record", "value", "text"], "forged")
             ])
  end

  test "the full six-note engine-free baseline uses the same bounded v4 request and citation schema" do
    records = Enum.map(1..6, &record("observation #{&1} " <> String.duplicate("x", 700)))
    assert {:ok, request} = ProtectedAnswer.request("Frozen question", records)
    assert {:ok, outcomes} = JSON.decode_unique(request["context"])
    assert outcomes === Enum.map(records, & &1["outcome"])
    assert length(outcomes) === 6 and byte_size(request["context"]) <= 8192
    assert request["profile"] === "extract" and request["timeout_ms"] === 3000
    assert {:ok, candidate} = ProtectedAnswer.request("Frozen question", Enum.take(records, 4))
    assert Map.drop(candidate, ["context"]) === Map.drop(request, ["context"])

    value = %{
      response(hd(records))
      | "citations" => Enum.flat_map(records, &response(&1)["citations"])
    }

    assert {:ok, prediction} = ProtectedAnswer.response(value, records, "query", "baseline")
    assert length(prediction["citations"]) === 6
    input_bytes = Jason.encode!(%{"query" => "Frozen question", "packs" => []})
    source_bytes = Jason.encode!(%{"scope" => "constructed shape only"})

    baseline = %{
      "case_id" => "query",
      "input_sha256" => JSON.sha256(input_bytes),
      "source_receipt_sha256" => JSON.sha256(source_bytes),
      "prediction" => prediction,
      "members" => Enum.map(records, & &1["key"]),
      "elapsed_ms" => nil,
      "cost_nanos" => nil
    }

    baseline_bytes = Jason.encode!(baseline)

    c = %{
      "id" => "query",
      "input_sha256" => baseline["input_sha256"],
      "source_receipt_sha256" => baseline["source_receipt_sha256"],
      "baseline_sha256" => JSON.sha256(baseline_bytes)
    }

    hash = JSON.sha256("constructed")

    {:ok, d} =
      SelectionExperiment.declare(%{
        "version" => 1,
        "source_sha256" => hash,
        "runtime_sha256" => hash,
        "artifact_sha256" => hash,
        "main_route_sha256" => hash,
        "policy_sha256" => hash,
        "label_commitment" => hash,
        "shared_limits" => Ipse.Extension.Consent.zero(),
        "engine" => %{
          "id" => "loopback",
          "availability" => "synthetic_protocol_only",
          "route_sha256" => hash
        },
        "cases" => [c]
      })

    blobs = Map.new([input_bytes, source_bytes, baseline_bytes], &{JSON.sha256(&1), &1})

    assert {:ok, %{"query" => ^baseline}} =
             SelectionExperiment.verify_inputs(d, JSON.digest([d]), &Map.fetch(blobs, &1))

    row =
      Map.take(c, ~w(input_sha256 source_receipt_sha256 baseline_sha256))
      |> Map.merge(%{
        "case_id" => "query",
        "status" => "ok",
        "selection_output_sha256" => hash,
        "prediction" => prediction,
        "members" => baseline["members"],
        "elapsed_ms" => nil,
        "cost_nanos" => nil
      })

    assert {:error, _} = SelectionExperiment.freeze_rows(d, JSON.digest([d]), [row])

    assert {:error, _} =
             ProtectedAnswer.request(
               "Frozen question",
               Enum.map(1..6, &record("#{&1}" <> String.duplicate("x", 1400)))
             )

    assert {:error, _} =
             ProtectedAnswer.baseline_project(
               %{"prediction" => prediction},
               "{}",
               "{}",
               [],
               [],
               Ipse.Usage.id(),
               Ipse.Usage.id()
             )
  end

  test "an exact note and claim span becomes a pair with integrity only, not entailment" do
    r = record()
    assert {:ok, prediction} = ProtectedAnswer.response(response(r), [r], "query", "answer")
    assert prediction["response_kind"] === "answer"
    assert [%{"citation_id" => id, "integrity" => "valid"}] = prediction["citations"]
    assert JSON.sha256?(id)
    assert {:ok, semantic} = Metrics.semantic([prediction], [])
    refute semantic["support"]["complete"]
    refute semantic["citation"]["complete"]
    assert semantic["support"]["accuracy"] === nil
  end

  test "source revision, quote hash, selection membership and exact UTF8 boundaries are mandatory" do
    r = record("é evidence")
    v = response(r)
    [citation] = v["citations"]

    for change <- [
          %{"key" => "note." <> JSON.sha256("foreign")},
          %{"revision" => 7.0},
          %{"revision" => 8},
          %{"quote_sha256" => JSON.sha256("foreign")},
          %{"quote" => "different"},
          %{"start_byte" => 1},
          %{"end_byte" => 1},
          %{"end_byte" => 999},
          %{"start_byte" => -1},
          %{"claim_end_byte" => 999},
          %{"claim_start_byte" => 18},
          %{"extra" => "permission"}
        ] do
      assert {:error, _} =
               ProtectedAnswer.response(
                 %{v | "citations" => [Map.merge(citation, change)]},
                 [r],
                 "query",
                 "answer"
               )
    end
  end

  test "each claim/span gets a distinct pair, while duplicate citations refuse" do
    r = record()
    v = response(r)
    [citation] = v["citations"]

    assert {:error, _} =
             ProtectedAnswer.response(
               %{v | "citations" => [citation, citation]},
               [r],
               "query",
               "answer"
             )

    other = %{citation | "claim_start_byte" => 2, "claim_end_byte" => 8}

    assert {:ok, p} =
             ProtectedAnswer.response(
               %{v | "citations" => [citation, other]},
               [r],
               "query",
               "answer"
             )

    assert length(Enum.uniq_by(p["citations"], & &1["citation_id"])) === 2
  end

  test "abstention needs no citations and unsupported answer shapes never become empty success" do
    r = record()
    abstention = %{"kind" => "abstention", "text" => "Insufficient evidence.", "citations" => []}
    assert {:ok, p} = ProtectedAnswer.response(abstention, [r], "query", "answer")
    assert p["response_kind"] === "abstention" and p["expected_refusal"] === false

    for v <- [
          Map.put(abstention, "kind", "answer"),
          Map.put(abstention, "text", ""),
          Map.put(abstention, "text", <<255>>),
          Map.put(abstention, "extra", true),
          Map.put(abstention, "citations", response(r)["citations"])
        ] do
      assert {:error, _} = ProtectedAnswer.response(v, [r], "query", "answer")
    end
  end

  test "complete baseline, original question, exact chosen pack and record versions stay matched" do
    records = Enum.map(1..6, &record("observation #{&1}"))
    keys = Enum.map(records, & &1["key"])
    baseline = %{"members" => keys}

    input = %{
      "query" => "Frozen question",
      "packs" => [
        %{"id" => "first", "members" => Enum.take(keys, 4)},
        %{"id" => "second", "members" => Enum.drop(keys, 2)}
      ]
    }

    selection = %{
      "status" => "selection_shadow",
      "input_sha256" => JSON.digest([input]),
      "baseline" => baseline,
      "candidate" => %{"members" => Enum.take(keys, 4)},
      "reads" =>
        Enum.map(records, fn r ->
          Map.take(r, ~w(key revision))
          |> Map.put("sha256", r["outcome"]["value"]["record"]["sha256"])
        end)
    }

    assert {:ok, selected} =
             ProtectedAnswer.selection_members(baseline, selection, input, records, "first")

    assert selected === Enum.take(records, 4)
    assert length(baseline["members"]) === 6

    for changed <- [
          put_in(selection, ["baseline", "members"], Enum.take(keys, 4)),
          put_in(selection, ["candidate", "members"], Enum.reverse(Enum.take(keys, 4))),
          Map.put(selection, "reads", tl(selection["reads"])),
          put_in(selection, ["reads", Access.at(0), "revision"], 8),
          put_in(selection, ["reads", Access.at(0), "sha256"], JSON.sha256("forged"))
        ] do
      assert {:error, _} =
               ProtectedAnswer.selection_members(baseline, changed, input, records, "first")
    end

    assert {:error, _} =
             ProtectedAnswer.selection_members(
               baseline,
               selection,
               %{input | "query" => "changed"},
               records,
               "first"
             )

    assert {:error, _} =
             ProtectedAnswer.selection_members(baseline, selection, input, records, "second")
  end

  test "missing or untyped failed output preserves an unknown row and absent measurements" do
    hash = JSON.sha256("constructed")

    c = %{
      "id" => "one",
      "input_sha256" => hash,
      "source_receipt_sha256" => hash,
      "baseline_sha256" => hash
    }

    spec = %{
      "version" => 1,
      "source_sha256" => hash,
      "runtime_sha256" => hash,
      "artifact_sha256" => hash,
      "main_route_sha256" => hash,
      "policy_sha256" => hash,
      "engine" => %{
        "id" => "loopback",
        "availability" => "synthetic_protocol_only",
        "route_sha256" => hash
      },
      "label_commitment" => hash,
      "shared_limits" => Ipse.Extension.Consent.zero(),
      "cases" => [c]
    }

    {:ok, d} = SelectionExperiment.declare(spec)
    sha = JSON.digest([d])

    for events <- [[], [%{"type" => "turn_finished", "outcome" => "error"}]] do
      assert {:ok, row} =
               ProtectedAnswer.project(
                 d,
                 sha,
                 "one",
                 fn _ -> flunk("must not load") end,
                 events,
                 Ipse.Usage.id(),
                 "first",
                 Ipse.Usage.id(),
                 Ipse.Usage.id()
               )

      assert row["status"] === "unknown" and row["prediction"] === nil
      assert row["members"] === [] and row["selection_output_sha256"] === nil
      assert row["elapsed_ms"] === nil and row["cost_nanos"] === nil
    end

    {:ok, unavailable} =
      SelectionExperiment.declare(put_in(spec, ["engine", "availability"], "unavailable"))

    assert {:ok, row} =
             ProtectedAnswer.project(
               unavailable,
               JSON.digest([unavailable]),
               "one",
               fn _ -> flunk("must not load") end,
               [],
               Ipse.Usage.id(),
               "first",
               Ipse.Usage.id(),
               Ipse.Usage.id()
             )

    assert row["status"] === "unavailable" and row["prediction"] === nil
  end

  defp helper_outcome_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ~w(status value),
      "properties" => %{
        "status" => %{"type" => "string", "enum" => ["ok"]},
        "value" => %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["text"],
          "properties" => %{"text" => %{"type" => "string", "maxLength" => 8192}}
        }
      }
    }
  end

  defp parent(result_schema \\ helper_outcome_schema(), stage \\ "invoke.service") do
    hash = JSON.sha256("fixture")

    identity = %{
      "instance" => "answer",
      "artifact" => hash,
      "artifact_sha256" => hash,
      "options_sha256" => hash,
      "exports_sha256" => hash,
      "requires_sha256" => hash,
      "subscriptions_sha256" => hash,
      "services" => [],
      "scope" => "operator",
      "source_sha256" => hash,
      "sdk" => 2,
      "protocol" => 1,
      "capabilities" =>
        ~w(invoke.service invoke.command invoke.result.pages host.actions host.model),
      "order" => 1,
      "lifetime" => "session",
      "expires_at" => nil,
      "runtime" => %{
        "architecture" => "fixture",
        "elixir" => "1.18.5",
        "erts" => "15",
        "otp" => "27"
      },
      "host_sha256" => hash,
      "generation" => 1,
      "allow_children" => false
    }

    id = if stage === "invoke.command", do: "select_shadow", else: "answer_context"

    descriptor = %{
      "id" => id,
      "description" => "Constructed output protocol",
      "instance" => "answer",
      "stage" => stage,
      "name" => "ext__answer__" <> id,
      "arguments_schema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{}
      },
      "result_schema" => result_schema
    }

    assert Ipse.Extension.Registry.valid_identity?(identity)

    p =
      Invocation.intent(
        identity,
        descriptor,
        %{},
        Ipse.Usage.id(),
        Ipse.Usage.id(),
        nil,
        nil,
        "operator_request"
      )

    assert :ok = Invocation.validate_intent(p)
    p
  end

  defp released(value) do
    p = parent()

    {:ok, result} =
      Invocation.build_result(p, %{"api_version" => 1, "kind" => "result", "value" => value})

    intent = ManagedOutput.intent(p["payload"]["session_id"], p, result, [], 10, 1000)
    admission = ManagedOutput.admission(intent, result, "current", [], 11, 1000)
    cleanup = ManagedOutput.cleanup(intent, admission, "confirmed")
    {p, result, intent, admission, cleanup, [p, intent, result, admission, cleanup]}
  end

  test "only exact current matching confirmed service output is extractable" do
    value = %{
      "status" => "ok",
      "value" => %{"text" => "constructed protocol, not actual authority"}
    }

    {p, result, intent, admission, cleanup, events} = released(value)

    assert {:error, _} =
             Invocation.build_result(p, %{
               "api_version" => 1,
               "kind" => "result",
               "value" => Map.put(value, "extra", true)
             })

    id = p["payload"]["session_id"]
    assert {:ok, ^result, ^value} = ProtectedAnswer.released(events, p, id)

    for changed <- [
          List.delete(events, cleanup),
          List.delete(events, admission),
          events ++ [cleanup],
          events ++ [result],
          List.replace_at(events, 4, %{cleanup | "status" => "unknown"}),
          List.replace_at(
            events,
            3,
            ManagedOutput.admission(intent, result, "withdrawn", [], 11, 1000)
          ),
          List.replace_at(events, 2, Map.put(result, "value", %{"forged" => true}))
        ] do
      assert {:error, _} = ProtectedAnswer.released(changed, p, id)
    end

    assert {:error, _} = ProtectedAnswer.released(events, p, Ipse.Usage.id())
  end

  test "service paging refuses while command selector paging requires complete current confirmed release" do
    schema = %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ~w(text detail),
      "properties" => Map.new(~w(text detail), &{&1, %{"type" => "string", "maxLength" => 8192}})
    }

    service = parent(schema)
    p = parent(schema, "invoke.command")
    value = %{"text" => String.duplicate("é", 3000), "detail" => String.duplicate("é", 3000)}

    assert {:error, _} =
             ResultDocument.encode(%{value | "text" => String.duplicate("é", 6000)}, schema)

    assert {:error, _} = ResultDocument.encode(Map.put(value, "extra", true), schema)
    {:ok, bytes} = ResultDocument.encode(value, p["descriptor"]["result_schema"])

    offer = %{
      "api_version" => 1,
      "kind" => "result_producer",
      "output" => %{
        "version" => 1,
        "byte_count" => byte_size(bytes),
        "sha256" => JSON.sha256(bytes)
      }
    }

    assert {:error, :invalid_extension_result_source} = ResultSource.open(service, offer, 1)
    {:ok, begin, source} = ResultSource.open(p, offer, 1)
    {chunks, source} = chunks(source, bytes, [])
    {:ok, proof, source} = ResultSource.seal(source, 3)
    {:ok, result} = Invocation.build_saved_result(p, ResultSource.descriptor(source), [], 4)
    intent = ManagedOutput.intent(p["payload"]["session_id"], p, result, [], 5, 1000)
    admission = ManagedOutput.admission(intent, result, "current", [], 6, 1000)
    cleanup = ManagedOutput.cleanup(intent, admission, "confirmed")
    events = [p, begin] ++ chunks ++ [proof.event, intent, result, admission, cleanup]

    assert {:ok, ^result, ^value} =
             ProtectedAnswer.released(events, p, p["payload"]["session_id"])

    assert {:error, _} =
             ProtectedAnswer.released(
               List.delete(events, hd(chunks)),
               p,
               p["payload"]["session_id"]
             )

    assert {:error, _} =
             ProtectedAnswer.released(List.delete(events, cleanup), p, p["payload"]["session_id"])
  end

  test "malformed declaration and invalid strict read prefix cannot manufacture projection authority" do
    assert {:error, _} =
             ProtectedAnswer.prepare(
               %{},
               JSON.sha256("bad"),
               "case",
               fn _ -> flunk("read not allowed") end,
               [],
               Ipse.Usage.id(),
               "pack",
               Ipse.Usage.id()
             )

    assert {:error, _} =
             ProtectedAnswer.project(
               %{},
               JSON.sha256("bad"),
               "case",
               fn _ -> flunk("read not allowed") end,
               [],
               Ipse.Usage.id(),
               "pack",
               Ipse.Usage.id(),
               Ipse.Usage.id()
             )
  end

  defp v4(n) do
    r = record("original observation #{n}")
    hash = &JSON.sha256/1

    d = %{
      "version" => 4,
      "project_id" => hash.("project"),
      "namespace" => hash.("namespace"),
      "pin_sha256" => hash.("pin"),
      "policy_generation" => 4,
      "collection" => %{
        "project" => hash.("namespace"),
        "generation" => 10,
        "floor" => 0,
        "floor_anchor" => nil,
        "manifest_sha256" => hash.("manifest"),
        "root_state" => "present",
        "root_sha256" => hash.("root")
      },
      "subject" => %{
        "kind" => "record_observation",
        "key" => r["key"],
        "request_sha256" => JSON.digest([%{"op" => "get_record", "key" => r["key"]}]),
        "result_sha256" => JSON.digest([r["outcome"]["value"]]),
        "publication_policy_sha256" => nil,
        "record" => %{
          "key" => r["key"],
          "revision" => 7,
          "value_sha256" => r["outcome"]["value"]["record"]["sha256"]
        },
        "validity" => %{
          "recipe_sha256" => hash.("recipe"),
          "lineage" => hash.("lineage #{n}"),
          "source_versions" => [%{"id" => hash.("source"), "version" => hash.("source version")}],
          "valid_until_ms" => nil,
          "status" => "eligible",
          "dependencies" => []
        }
      }
    }

    assert ManagedReference.dependency?(d)
    d
  end

  defp lineage(parent, deps) do
    {:ok, state} = ManagedLineage.new(parent["payload"]["session_id"])

    message = %{
      "role" => "user",
      "content" => "Constructed protected observations, not a live lease"
    }

    {:ok, _, reference} =
      ManagedReference.admit(
        state.reference,
        %{"kind" => "reference", "id" => "source.observations", "parent_id" => nil},
        0,
        message,
        deps
      )

    {%{state | reference: reference, frozen_header: true}, [message]}
  end

  defp initial_input(parent, dependencies) do
    {:ok, frame} = Worker.frame(1, "invoke.service", parent["payload"])

    input = %{
      "type" => "worker_input_intent",
      "version" => 1,
      "input_id" => Ipse.Usage.id(),
      "session_id" => parent["payload"]["session_id"],
      "invocation_id" => parent["invocation_id"],
      "parent_sha256" => JSON.digest([parent]),
      "actions_sha256" => JSON.digest([]),
      "stage" => "invoke.service",
      "payload_sha256" => JSON.digest([parent["payload"]]),
      "artifact_sha256" => parent["identity"]["artifact_sha256"],
      "protocol_id" => 1,
      "frame_sha256" => JSON.sha256(frame),
      "frame_bytes" => byte_size(frame),
      "dependencies_sha256" => JSON.digest(dependencies),
      "checked_at_ms" => 1000,
      "deadline_ms" => 6000
    }

    assert WorkerInput.valid_intent?(input, parent, JSON.digest([]), parent["payload"])

    result = %{
      "type" => "worker_input_result",
      "version" => 1,
      "input_id" => input["input_id"],
      "intent_sha256" => JSON.digest([input]),
      "status" => "delivered"
    }

    {input, result}
  end

  defp helper_preflight(parent, state, messages, dependencies, request) do
    {:ok, state} = ManagedLineage.advance(state, parent, messages, messages)
    operation = Ipse.Usage.id()

    action = %{
      "type" => "extension_action_intent",
      "parent_invocation_id" => parent["invocation_id"],
      "operation_id" => operation,
      "request" => request
    }

    {:ok, state} = ManagedLineage.advance(state, action, messages, messages)

    route = %{
      "operation" => "model.complete",
      "profile" => "extract",
      "provider" => "ollama",
      "model" => "synthetic",
      "billing_mode" => "local"
    }

    state = %{
      state
      | admission: %{
          "pin" => %{"epoch" => 4},
          "policy" => %{"settings" => %{"routes" => [route]}}
        }
    }

    admission =
      Ipse.Usage.admission(
        parent["payload"]["session_id"],
        %{provider: :ollama, model: "synthetic", execution: %{id: "extract"}},
        "extension",
        Ipse.Usage.id()
      )
      |> Map.put("request_id", operation)

    assert Ipse.Usage.operation(admission) === "text"
    {:ok, state} = ManagedLineage.advance(state, admission, messages, messages)
    now = admission["admitted_at_ms"]
    helper = Ipse.Session.Context.helper_messages(request)

    intent = %{
      "type" => "managed_preflight_intent",
      "version" => 1,
      "intent_id" => Ipse.Usage.id(),
      "session_id" => parent["payload"]["session_id"],
      "turn_id" => admission["turn_id"],
      "request_id" => operation,
      "phase" => "model.complete",
      "admission_sha256" => JSON.digest([admission]),
      "before_sha256" => JSON.digest(messages),
      "dependencies_sha256" => JSON.digest(dependencies),
      "input_sha256" => JSON.digest([helper]),
      "tools_sha256" => JSON.digest([[]]),
      "snapshot_sha256" => JSON.digest(["model.complete", helper, dependencies]),
      "route_sha256" => JSON.digest([route]),
      "source_generation" => 1,
      "policy_generation" => 4,
      "checked_at_ms" => now,
      "deadline_ms" => now + 3000
    }

    result = %{
      "type" => "managed_preflight_result",
      "version" => 1,
      "intent_id" => intent["intent_id"],
      "projection" => nil,
      "verdicts" =>
        Enum.map(
          dependencies,
          &%{"dependency_sha256" => JSON.digest([&1]), "status" => "eligible", "current" => &1}
        )
    }

    {state, operation, intent, result}
  end

  test "both answer arms inherit every original record plus real extra root dependencies" do
    parent = parent()
    original = Enum.map(1..6, &v4/1)

    root =
      hd(original)
      |> Map.put("version", 3)
      |> Map.put("subject", %{
        "kind" => "root_observation",
        "request_sha256" => JSON.sha256("root request"),
        "result_sha256" => JSON.sha256("root result")
      })

    assert ManagedReference.dependency?(root)
    {:ok, union} = ManagedReference.union([original, [root]])
    {state, messages} = lineage(parent, union)
    {input, delivery} = initial_input(parent, union)
    # Both arms require ALL six original observations, even when one renders four.
    for count <- [6, 4] do
      assert {:ok, request} =
               ProtectedAnswer.request(
                 "Same frozen question",
                 Enum.map(1..count, &record("original observation #{&1}"))
               )

      assert {:ok, ^union} =
               ProtectedAnswer.entry_dependencies(
                 state,
                 messages,
                 parent,
                 original,
                 input,
                 delivery,
                 union
               )

      {model, operation, intent, checked} =
        helper_preflight(parent, state, messages, union, request)

      assert :ok =
               ProtectedAnswer.model_dependencies(
                 model,
                 messages,
                 parent,
                 request,
                 operation,
                 union,
                 intent,
                 checked
               )
    end

    {:ok, without_root} = ManagedReference.union([original])
    {reduced, same_text} = lineage(parent, without_root)
    {input, delivery} = initial_input(parent, without_root)

    assert {:error, _} =
             ProtectedAnswer.entry_dependencies(
               reduced,
               same_text,
               parent,
               original,
               input,
               delivery,
               union
             )
  end

  test "missing one original dependency and copied bare context cannot qualify a service" do
    parent = parent()
    original = Enum.map(1..6, &v4/1)

    for retained <- [Enum.take(original, 5), Enum.take(original, 4)] do
      {:ok, partial} = ManagedReference.union([retained])
      {state, messages} = lineage(parent, partial)
      {input, delivery} = initial_input(parent, partial)

      assert {:error, _} =
               ProtectedAnswer.entry_dependencies(
                 state,
                 messages,
                 parent,
                 original,
                 input,
                 delivery
               )
    end

    {:ok, bare} = ManagedLineage.new(parent["payload"]["session_id"])

    copied = [
      %{
        "role" => "user",
        "content" => Jason.encode!(Enum.map(1..6, &record("original observation #{&1}")))
      }
    ]

    {input, delivery} = initial_input(parent, [])

    assert {:error, _} =
             ProtectedAnswer.entry_dependencies(bare, copied, parent, original, input, delivery)
  end

  test "initial service input must bind its real frame parent full union and confirmed delivery" do
    parent = parent()
    original = [v4(1), v4(2)]
    {:ok, union} = ManagedReference.union([original])
    {state, messages} = lineage(parent, union)
    {input, delivery} = initial_input(parent, union)

    assert {:ok, ^union} =
             ProtectedAnswer.entry_dependencies(
               state,
               messages,
               parent,
               original,
               input,
               delivery
             )

    for changed <- [
          Map.put(input, "dependencies_sha256", JSON.digest([hd(union)])),
          Map.put(input, "parent_sha256", JSON.sha256("foreign parent")),
          Map.put(input, "payload_sha256", JSON.sha256("copied context")),
          Map.put(input, "frame_sha256", JSON.sha256("other frame")),
          Map.put(input, "stage", "host.actions")
        ] do
      assert {:error, _} =
               ProtectedAnswer.entry_dependencies(
                 state,
                 messages,
                 parent,
                 original,
                 changed,
                 delivery
               )
    end

    assert {:error, _} =
             ProtectedAnswer.entry_dependencies(state, messages, parent, original, input, %{
               delivery
               | "status" => "unknown"
             })

    assert {:error, _} =
             ProtectedAnswer.entry_dependencies(state, messages, parent, original, input, %{
               delivery
               | "intent_sha256" => JSON.sha256("other intent")
             })
  end

  test "model preflight must bind the exact inherited union request admission and eligible verdicts" do
    parent = parent()
    original = [v4(1), v4(2)]
    {:ok, union} = ManagedReference.union([original])
    {state, messages} = lineage(parent, union)

    {:ok, request} =
      ProtectedAnswer.request("Same frozen question", [record("original observation 1")])

    {model, operation, intent, checked} =
      helper_preflight(parent, state, messages, union, request)

    assert :ok =
             ProtectedAnswer.model_dependencies(
               model,
               messages,
               parent,
               request,
               operation,
               union,
               intent,
               checked
             )

    for changed <- [
          Map.put(intent, "request_id", Ipse.Usage.id()),
          Map.put(intent, "phase", "model"),
          Map.put(intent, "dependencies_sha256", JSON.digest([hd(union)])),
          Map.put(intent, "input_sha256", JSON.sha256("other context")),
          Map.put(intent, "snapshot_sha256", JSON.sha256("other union")),
          Map.put(intent, "admission_sha256", JSON.sha256("other admission"))
        ] do
      assert {:error, _} =
               ProtectedAnswer.model_dependencies(
                 model,
                 messages,
                 parent,
                 request,
                 operation,
                 union,
                 changed,
                 checked
               )
    end

    assert {:error, _} =
             ProtectedAnswer.model_dependencies(
               model,
               messages,
               parent,
               %{request | "input" => "different"},
               operation,
               union,
               intent,
               checked
             )

    assert {:error, _} =
             ProtectedAnswer.model_dependencies(
               model,
               messages,
               put_in(parent, ["payload", "arguments"], %{"request" => request}),
               request,
               operation,
               union,
               intent,
               checked
             )

    assert {:error, _} =
             ProtectedAnswer.model_dependencies(
               model,
               messages,
               parent,
               request,
               operation,
               tl(union),
               intent,
               checked
             )

    assert {:error, _} =
             ProtectedAnswer.model_dependencies(
               model,
               messages,
               parent,
               request,
               operation,
               union,
               intent,
               %{checked | "intent_id" => Ipse.Usage.id()}
             )

    assert {:error, _} =
             ProtectedAnswer.model_dependencies(
               model,
               messages,
               parent,
               request,
               operation,
               union,
               intent,
               %{checked | "verdicts" => tl(checked["verdicts"])}
             )

    withheld =
      update_in(
        checked,
        ["verdicts", Access.at(0)],
        &Map.merge(&1, %{"status" => "unavailable", "current" => nil})
      )

    assert {:error, _} =
             ProtectedAnswer.model_dependencies(
               model,
               messages,
               parent,
               request,
               operation,
               union,
               intent,
               withheld
             )

    assert {:error, _} =
             ProtectedAnswer.model_dependencies(
               %{model | unavailable: true},
               messages,
               parent,
               request,
               operation,
               union,
               intent,
               checked
             )
  end

  test "committed live prefix retains request admission that Saved recovery intentionally clears" do
    events =
      "docs/archive/2026-10-26-p30-p31-implementation/own-root-transition/journals/model.jsonl"
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

    session = get_in(hd(events), ["metadata", "source_origin", "session_id"])
    assert {:ok, _} = Ipse.Session.Saved.restore(events, session)

    stop =
      Enum.find_index(events, fn event ->
        event["type"] === "managed_preflight_intent" and event["phase"] === "model"
      end)

    intent = Enum.at(events, stop)

    start =
      Enum.find_index(events, fn event ->
        event["type"] === "request_admitted" and event["request_id"] === intent["request_id"]
      end)

    assert is_integer(start) and start < stop
    assert {:ok, recovered} = Ipse.Session.Saved.restore(Enum.take(events, stop), session)
    assert recovered.managed_lineage.admissions === %{}

    assert {:ok, live} = ProtectedAnswer.live_prefix(events, session, start, stop)
    assert live.managed_lineage.admissions[intent["request_id"]] === Enum.at(events, start)

    assert {:ok, checking} =
             ManagedLineage.advance(live.managed_lineage, intent, live.messages, live.messages)

    refute checking.unavailable

    assert {:error, _} =
             ManagedLineage.advance(
               recovered.managed_lineage,
               intent,
               recovered.messages,
               recovered.messages
             )

    result_position =
      Enum.find_index(events, fn event ->
        event["type"] === "managed_preflight_result" and
          event["intent_id"] === intent["intent_id"]
      end)

    assert {:ok, projected} =
             ProtectedAnswer.live_prefix(events, session, start, result_position + 1)

    assert is_nil(projected.managed_lineage.preflight)
    assert {:ok, expected} = Ipse.Session.Saved.context(Enum.take(events, result_position + 1))
    assert projected.messages === expected

    altered =
      List.replace_at(
        events,
        start,
        Map.put(Enum.at(events, start), "request_id", Ipse.Usage.id())
      )

    assert {:error, _} = ProtectedAnswer.live_prefix(altered, session, start, result_position + 1)
    assert {:error, _} = ProtectedAnswer.live_prefix(events, session, stop + 1, stop)
  end

  defp chunks(%{offset: offset} = source, bytes, acc) when offset === byte_size(bytes),
    do: {Enum.reverse(acc), source}

  defp chunks(source, bytes, acc) do
    n = min(4096, byte_size(bytes) - source.offset)
    fragment = binary_part(bytes, source.offset, n)

    reply = %{
      "api_version" => 1,
      "kind" => "result_chunk",
      "output" => %{
        "version" => 1,
        "output_id" => source.begin["output_id"],
        "offset" => source.offset,
        "next" => source.offset + n,
        "complete" => source.offset + n === byte_size(bytes),
        "data_base64" => Base.encode64(fragment),
        "sha256" => JSON.sha256(fragment)
      }
    }

    {:ok, event, source} = ResultSource.push(source, reply)
    chunks(source, bytes, [event | acc])
  end
end
