Code.require_file("../../../extensions/knowledge/src/notes.ex", __DIR__)
Code.require_file("../../../extensions/knowledge/src/knowledge/contracts.ex", __DIR__)
Code.require_file("../../../extensions/knowledge/src/knowledge/records.ex", __DIR__)

defmodule IpseKnowledge.Knowledge.RecordsTest do
  use ExUnit.Case, async: true
  alias IpseKnowledge.Knowledge.Records, as: R
  @day 86_400_000

  defp proof(
         origin \\ "native_operator_assertion",
         quote \\ "Acme has owner Alex",
         category \\ "ordinary"
       ) do
    kind =
      case origin do
        "native_operator_answer" -> "input.operator_answer"
        "assistant_proposal" -> "answer.original"
        "typed_host_outcome" -> "tool.outcome"
        "native_operator_assertion" -> "input.assertion." <> category
        _ -> "input.original"
      end

    %{
      "version" => 1,
      "session_id" => String.duplicate("1", 32),
      "occurrence_id" => String.duplicate("2", 32),
      "version_id" => String.duplicate("3", 32),
      "kind" => kind,
      "origin" => origin,
      "coverage" => "available",
      "path" => nil,
      "start_byte" => 0,
      "end_byte" => byte_size(quote),
      "quote" => quote,
      "quote_sha256" => Ipse.JSON.sha256(quote),
      "content_sha256" => Ipse.JSON.sha256(quote),
      "receipt_sha256" => Ipse.JSON.sha256("synthetic trusted-function input")
    }
  end

  defp attrs(text \\ "Acme has owner Alex", category \\ "ordinary"),
    do: %{
      "text" => text,
      "category" => category,
      "reason" => "selected source span",
      "event_at_ms" => nil
    }

  test "exact reviewed statements create notes only in their reviewed category" do
    assert {:ok, "note." <> _, value} = R.capture(attrs(), proof(), 0)
    assert IpseKnowledge.Notes.valid?(value)
    assert value["expires_at_ms"] == 90 * @day
    assert value["evidence"]["sources"] == [proof()]

    assert {:ok, _, persistent} =
             R.capture(
               attrs("Acme has owner Alex", "current"),
               proof("native_operator_assertion", "Acme has owner Alex", "current"),
               0
             )

    assert persistent["expires_at_ms"] == nil

    assert {:ok, "pending." <> _, _} =
             R.capture(attrs("Acme has owner Alex", "current"), proof(), 0)
  end

  test "even a whole native message can quote somebody else and stays pending" do
    for text <- ["Acme has owner Alex", "A third party reports: Acme has owner Alex"] do
      assert {:ok, "pending." <> _, _} =
               R.capture(attrs(text, "current"), proof("interactive_operator", text), 0)
    end
  end

  test "an answer to a native question remains a proposal without question-bound attestation" do
    for text <- ["yes", "blue", "Acme has owner Alex"] do
      source = proof("native_operator_answer", text)
      assert {:ok, "pending." <> _, %{"state" => "pending"}} = R.capture(attrs(text), source, 0)
    end
  end

  test "a host-admitted question answer keeps its origin and is proposed for review" do
    alias Ipse.Session.{OperatorAnswer, SourceIndex}
    alias Ipse.Tools.Questions
    session = Ipse.Usage.id()
    client = Ipse.Usage.id()
    {:ok, index} = SourceIndex.new(session)

    arguments = %{
      "questions" => [
        %{
          "id" => "choice",
          "kind" => "single",
          "prompt" => "Choose a color",
          "options" => [%{"id" => "a", "label" => "Red"}, %{"id" => "b", "label" => "Blue"}]
        }
      ]
    }

    call = %{
      "id" => "question-source",
      "type" => "function",
      "function" => %{"name" => "ask_operator", "arguments" => Jason.encode!(arguments)}
    }

    question = %{id: call["id"], call: call, arguments: arguments}
    {:ok, render} = OperatorAnswer.render(question, "choice", client)
    input = "answer #{render["code"]} 2"

    observation = %{
      "version" => 2,
      "event_id" => Ipse.Usage.id(),
      "display_sha256" => Ipse.JSON.sha256(render["display"]),
      "text_sha256" => Ipse.JSON.sha256(input),
      "input_limit" => 1_048_576,
      "display_limit" => 16_777_216
    }

    {:ok, choice, piece} = OperatorAnswer.parse(question, render, input, observation)

    message =
      Questions.tool_result(
        call,
        Jason.encode!(%{
          "answers" => %{"choice" => choice},
          "notice" => "Clarification only; no action permission."
        }),
        "result_recorded"
      )

    {:ok, origin} = OperatorAnswer.receipt(session, question, client, [piece], message)

    event = %{
      "type" => "operator_answer",
      "version" => 2,
      "id" => question.id,
      "message" => message,
      "origin" => origin
    }

    checkpoint = %{
      "type" => "operator_question",
      "version" => 1,
      "id" => question.id,
      "call" => call,
      "arguments" => arguments
    }

    assert {:ok, admitted} = SourceIndex.admit_operator_answer(index, event, checkpoint)
    assert {:ok, page} = SourceIndex.list(admitted, %{"limit" => 32})
    source = Enum.find(page["sources"], &(&1["origin"] == "native_operator_answer"))

    assert {:ok, resolved} =
             SourceIndex.resolve_proof(admitted, %{
               "handle" => source["read_handle"],
               "quote" => "2"
             })

    assert resolved["proof"]["origin"] == "native_operator_answer"

    assert {:ok, "pending." <> _, %{"state" => "pending"}} =
             R.capture(attrs("2"), resolved["proof"], 0)
  end

  test "a selected fragment or partially covered event remains a proposal" do
    p = proof()

    fragment = %{
      p
      | "start_byte" => 12,
        "end_byte" => 12 + byte_size(p["quote"]),
        "content_sha256" => Ipse.JSON.sha256("not a direct assertion: " <> p["quote"])
    }

    longer = %{
      p
      | "content_sha256" => Ipse.JSON.sha256(p["quote"] <> " was quoted from a report")
    }

    partial = %{p | "coverage" => "partial"}

    for source <- [fragment, longer, partial] do
      assert {:ok, "pending." <> _, %{"state" => "pending"}} = R.capture(attrs(), source, 0)
    end
  end

  test "retention metadata preserves separate native evidence in a closed publication wrapper" do
    p = proof("interactive_operator")

    override = %{
      "version" => 1,
      "lineage" => R.lineage(p),
      "policy" => %{"kind" => "session"},
      "reason" => "operator selection",
      "updated_at_ms" => 0
    }

    assert {:ok, stored} = R.override_record(override, p)
    assert stored["evidence"]["sources"] == [p]
    assert {:ok, ^override} = R.saved_override(stored, override["lineage"])
    assert {:ok, nil} = R.saved_override(nil, override["lineage"])

    for origin <- ~w(unattended_input assistant_proposal typed_host_outcome) do
      assert {:error, :invalid_retention_evidence} = R.override_record(override, proof(origin))
    end

    for damaged <- [
          override,
          Map.put(stored, "permission", true),
          put_in(stored, ["evidence", "sources"], []),
          put_in(stored, ["override", "updated_at_ms"], -1)
        ] do
      assert {:error, :invalid_saved_override} = R.saved_override(damaged, override["lineage"])
    end

    assert {:error, :invalid_saved_override} = R.saved_override(stored, String.duplicate("f", 64))
  end

  test "saved ordinary and duration deadlines cap every paraphrase and classification" do
    p = proof()

    for policy <- [%{"kind" => "ordinary"}, %{"kind" => "duration", "duration_ms" => @day}],
        category <- ~w(ordinary preference current),
        text <- [p["quote"], "Alex owns Acme"] do
      override = %{
        "version" => 1,
        "lineage" => R.lineage(p),
        "policy" => policy,
        "reason" => "operator chose shorter retention",
        "updated_at_ms" => 0
      }

      deadline = if policy["kind"] == "ordinary", do: 90 * @day, else: @day

      assert {:skipped, :expired_lineage} =
               R.capture(attrs(text, category), p, deadline, override)

      assert {:ok, _, value} = R.capture(attrs(text, category), p, deadline - 1, override)
      assert value["expires_at_ms"] == deadline
      if value["kind"] == "proposal", do: assert(value["assigned_category"] == "ordinary")
    end

    override = %{
      "version" => 1,
      "lineage" => R.lineage(p),
      "policy" => %{"kind" => "duration", "duration_ms" => 30 * @day},
      "reason" => "operator retention",
      "updated_at_ms" => 0
    }

    assert {:ok, _, pending} = R.capture(attrs("Alex owns Acme"), p, 0, override)
    assert pending["expires_at_ms"] == 7 * @day
  end

  test "unattended input, assistant text and a native answer's unsupported premise stay pending" do
    for origin <- ~w(unattended_input assistant_proposal) do
      assert {:ok, "pending." <> _, value} = R.capture(attrs(), proof(origin), 0)
      assert value["state"] == "pending"
      assert value["expires_at_ms"] == 7 * @day
      assert hd(value["evidence"]["sources"])["origin"] == origin
    end

    assert {:ok, "pending." <> _, _} =
             R.capture(
               attrs("The operator confirmed Alex owns Acme"),
               proof("native_operator_answer", "2"),
               0
             )
  end

  test "pending projection preserves the original source and only exposes recorded claims" do
    for origin <- ~w(unattended_input assistant_proposal) do
      source = proof(origin)
      assert {:ok, key, value} = R.capture(attrs(), source, 100)
      assert {:ok, projection} = R.pending_projection(key, value)
      assert projection["key"] == key
      assert projection["record_schema_version"] === 1
      assert projection["candidate_id"] == value["id"]
      assert projection["lineage"] == R.lineage(source)
      assert projection["text"] == value["text"]
      assert projection["text_sha256"] == Ipse.JSON.sha256(value["text"])
      assert projection["source_provenance"] === source
      assert projection["worker_recorded_created_at_ms"] == 100
      assert projection["worker_recorded_expires_at_ms"] == 100 + 7 * @day
      refute Map.has_key?(projection, "revision")
      refute Map.has_key?(projection, "eligible")
      refute Map.has_key?(projection, "accepted")
      refute Map.has_key?(projection, "consent")

      # Worker times are returned as claims, not used as host eligibility clocks.
      claims = %{value | "created_at_ms" => 500, "expires_at_ms" => 0}
      assert {:ok, projected_claims} = R.pending_projection(key, claims)
      assert projected_claims["worker_recorded_expires_at_ms"] == 0
    end
  end

  test "pending projection refuses mismatched identity, text, proof and closed format" do
    assert {:ok, key, value} = R.capture(attrs(), proof("assistant_proposal"), 0)
    assert key == "pending.1d21a24a1112ab0285c47b1208f8de27e7616f31239e588f7fa905378fd67bea"

    damaged = [
      Map.put(value, "version", 2),
      Map.put(value, "version", 1.0),
      Map.put(value, "kind", "note"),
      Map.put(value, "state", "accepted"),
      Map.put(value, "id", String.duplicate("f", 64)),
      Map.put(value, "lineage", String.duplicate("f", 64)),
      Map.put(value, "text", "different candidate"),
      Map.put(value, "extra", true),
      Map.delete(value, "reason"),
      Map.put(value, "created_at_ms", -1),
      Map.put(value, "created_at_ms", 0.0),
      Map.put(value, "expires_at_ms", 1.0),
      Map.put(value, "event_at_ms", 0.0),
      put_in(value, ["evidence", "sources"], []),
      put_in(value, ["evidence", "sources", Access.at(0), "quote"], "altered"),
      put_in(value, ["evidence", "sources", Access.at(0), "origin"], "native_operator_assertion"),
      put_in(value, ["evidence", "sources", Access.at(0), "receipt_sha256"], "invalid")
    ]

    for record <- damaged do
      assert {:error, :invalid_pending_projection} = R.pending_projection(key, record)
    end

    assert {:error, :invalid_pending_projection} = R.pending_projection("pending.other", value)
    assert {:error, :invalid_pending_projection} = R.pending_projection(key, nil)

    # A shaped but different receipt cannot be authenticated by a pure parser.
    claimed =
      put_in(
        value,
        ["evidence", "sources", Access.at(0), "receipt_sha256"],
        Ipse.JSON.sha256("different unverified receipt")
      )

    assert {:ok, projected} = R.pending_projection(key, claimed)

    assert projected["source_provenance"]["receipt_sha256"] !=
             hd(value["evidence"]["sources"])["receipt_sha256"]
  end

  test "typed tool completion supports only its literal outcome and cannot become a preference" do
    p = proof("typed_host_outcome", ~s({"status":"completed","tool":"shell"}))
    assert {:ok, "note." <> _, _} = R.capture(attrs(p["quote"]), p, 0)
    assert {:ok, "pending." <> _, _} = R.capture(attrs("All tests passed"), p, 0)
    assert {:ok, "pending." <> _, _} = R.capture(attrs(p["quote"], "preference"), p, 0)
  end

  test "accepted projection retains its weak original source and does not become a literal assertion" do
    for origin <- ~w(unattended_input assistant_proposal) do
      source = proof(origin)
      assert {:ok, _, pending} = R.capture(attrs(), source, 100)

      assert {:ok, lineage} =
               Ipse.Extension.canonical_digest([
                 "ipse-knowledge",
                 1,
                 "accepted_decision",
                 pending["id"],
                 pending["lineage"]
               ])

      key = "note." <> lineage

      value = %{
        "version" => 1,
        "kind" => "accepted_decision",
        "lineage" => lineage,
        "candidate_id" => pending["id"],
        "text" => pending["text"],
        "category" => "ordinary",
        "reason" => pending["reason"],
        "source_proof" => source,
        "acceptance_event_sha256" => Ipse.JSON.sha256("unverified native-event claim"),
        "acceptance_link_sha256" => Ipse.JSON.sha256("unverified link claim"),
        "accepted_at_ms" => 200,
        "valid_until_ms" => 300
      }

      assert {:ok, projected} = R.accepted_projection(key, value)
      assert projected["claim_kind"] == "accepted_decision"
      assert projected["source_provenance"] === source
      assert projected["recorded_accepted_at_ms"] == 200
      refute IpseKnowledge.Notes.valid?(value)
      refute R.direct?(attrs(), projected["source_provenance"])
      refute Map.has_key?(projected, "eligible")
      refute Map.has_key?(projected, "consent")

      for bad <- [
            Map.put(value, "version", 1.0),
            Map.put(value, "text", "other candidate"),
            Map.put(value, "lineage", Ipse.JSON.sha256("other lineage")),
            Map.put(value, "valid_until_ms", 200),
            Map.put(value, "valid_until_ms", nil),
            Map.put(value, "eligible", true),
            Map.put(value, "acceptance_event_sha256", "bad"),
            put_in(value, ["source_proof", "origin"], "native_operator_assertion")
          ] do
        assert {:error, :invalid_accepted_projection} = R.accepted_projection(key, bad)
      end

      assert {:error, :invalid_accepted_projection} = R.accepted_projection("note.other", value)

      claimed =
        Map.put(value, "acceptance_event_sha256", Ipse.JSON.sha256("different shaped claim"))

      assert {:ok, _} = R.accepted_projection(key, claimed)
      persistent = %{value | "category" => "preference", "valid_until_ms" => nil}
      assert {:ok, _} = R.accepted_projection(key, persistent)
    end
  end

  test "paraphrasing and category changes retain claim/evidence overrides without TTL renewal" do
    p = proof()
    lineage = R.lineage(p)

    override = %{
      "version" => 1,
      "lineage" => lineage,
      "policy" => %{"kind" => "session"},
      "reason" => "operator chose session only",
      "updated_at_ms" => 0
    }

    assert {:error, :invalid_capture} =
             R.capture(attrs(), p, 0, %{override | "updated_at_ms" => @day})

    assert {:suppressed, ^override} = R.capture(attrs(), p, @day, override)

    assert {:suppressed, ^override} =
             R.capture(attrs("Alex is Acme's owner", "preference"), p, @day, override)

    expired = %{override | "policy" => %{"kind" => "ordinary"}}
    assert {:skipped, :expired_lineage} = R.capture(attrs(), p, 90 * @day, expired)

    assert {:error, :invalid_capture} =
             R.capture(attrs(), p, 0, %{override | "lineage" => Ipse.JSON.sha256("other claim")})
  end

  test "file content, changed spans, unknown origin and extra input fields cannot enter capture" do
    for p <- [
          %{proof() | "kind" => "tool.content", "origin" => "attributed_reference"},
          %{proof() | "path" => "private/file.txt"},
          %{proof() | "end_byte" => 1},
          %{proof() | "origin" => "worker_says_native"},
          %{proof() | "quote_sha256" => Ipse.JSON.sha256("changed")}
        ] do
      assert {:error, :invalid_capture} = R.capture(attrs(), p, 0)
    end

    assert {:error, :invalid_capture} = R.capture(Map.put(attrs(), "allow", true), proof(), 0)
  end

  test "maximum selected UTF-8 span fits a note and oversized escaped proposals refuse explicitly" do
    quote = String.duplicate("λ", 512)
    assert {:ok, _, note} = R.capture(attrs(quote), proof("native_operator_assertion", quote), 0)
    assert byte_size(Jason.encode!(note)) <= 6144
    oversized = attrs(String.duplicate("\n", 2048))
    assert {:error, :capture_capacity} = R.capture(oversized, proof("assistant_proposal"), 0)
  end
end
