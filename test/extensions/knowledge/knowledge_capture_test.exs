defmodule IpseKnowledge.KnowledgeCaptureTest do
  use ExUnit.Case, async: false

  @suite ~S"""
  ExUnit.start(autorun: false)
  for path <- ~w(profiles notes knowledge/contracts knowledge/records knowledge/decision_policy knowledge),
    do: Code.require_file(Path.join("extensions/knowledge/src", path <> ".ex"))

  "extensions/knowledge/src/knowledge.ex"
  |> File.read!()
  |> String.replace("defmodule IpseKnowledge.Knowledge do", "defmodule IpseKnowledge.KnowledgeShadowFixture do")
  |> String.replace(~s(@preset "native"), ~s(@preset "decision-shadow"))
  |> Code.compile_string()

  defmodule IpseKnowledge.KnowledgeCaptureSuite do
  use ExUnit.Case, async: true
  alias IpseKnowledge.Knowledge, as: K
  alias IpseKnowledge.KnowledgeShadowFixture, as: Shadow

  defp options,
    do:
      Map.new(~w(stores search fetch retrieval embedding rerank extraction), &{&1, %{}})
      |> Map.put("version", 1)

  defp attrs(text \\ "Acme has owner Alex"),
    do: %{
      "text" => text,
      "category" => "ordinary",
      "reason" => "explicit observation",
      "event_at_ms" => nil,
      "source" => %{"handle" => "synthetic.handle", "quote" => "Acme has owner Alex"}
    }

  defp page(origin) do
    text = "Acme has owner Alex"
    ids = Map.new(~w(occurrence_id version_id chunk_id), &{&1, String.duplicate("1", 32)})

    Map.merge(ids, %{
      "version" => 1,
      "kind" => case origin do
        "assistant_proposal" -> "answer.original"
        "native_operator_assertion" -> "input.assertion.ordinary"
        _ -> "input.original"
      end,
      "origin" => origin,
      "coverage" => "available",
      "text" => text,
      "offset" => 0,
      "content_sha256" => Ipse.JSON.sha256(text),
      "handle" => "synthetic.handle",
      "next" => nil,
      "complete" => true,
      "original_bytes" => byte_size(text),
      "reason" => nil,
      "provenance" => %{"receipt_sha256" => Ipse.JSON.sha256("synthetic trusted-function input")},
      "window" => %{"version" => 1, "session_id" => String.duplicate("2", 32)}
    })
  end

  defp quote_receipt(page),
    do:
      Map.take(page, ~w(occurrence_id version_id chunk_id origin coverage content_sha256))
      |> Map.merge(%{
        "start_byte" => 0,
        "end_byte" => byte_size(page["text"]),
        "quote_sha256" => Ipse.JSON.sha256(page["text"])
      })

  defp respond(state, value),
    do: K.handle("host.actions", %{"operation_id" => String.duplicate("a", 32), "outcome" => %{"status" => "ok", "value" => value}}, state)

  defp shadow_respond(state, value),
    do: Shadow.handle("host.actions", %{"operation_id" => String.duplicate("a", 32), "outcome" => %{"status" => "ok", "value" => value}}, state)

  defp request({:ok, %{"kind" => "host_call", "request" => request}, state}), do: {request, state}

  defp value({:ok, %Ipse.Extension.ResultPublication.Output{bytes: bytes}, state}),
    do: {JSON.decode!(bytes), state}

  defp value({:ok, %{"kind" => "result", "value" => value}, state}), do: {value, state}

  defp start(origin \\ "native_operator_assertion", args \\ attrs()) do
    {:ok, state} = K.init(options())

    {%{"op" => "source.read"}, state} =
      request(K.handle("invoke.tool", %{"id" => "capture", "arguments" => args}, state))

    page = page(origin)
    {%{"op" => "source.quote"}, state} = request(respond(state, page))

    {%{"op" => "collection.call", "request" => %{"op" => "get", "key" => "override." <> _}},
     state} = request(respond(state, quote_receipt(page)))

    state
  end

  test "reviewed native capture carries public stable proof into a create-only commit" do
    state = start()

    {%{"request" => %{"key" => "note." <> _}}, state} =
      request(respond(state, %{"record" => nil}))

    {commit, state} = request(respond(state, %{"record" => nil, "generation" => 7}))
    assert commit["request"]["expected_generation"] == 7
    assert commit["op"] == "collection.managed"
    assert commit["request"]["advance_floor"] == true
    assert {:ok, commit["recipe_sha256"]} ==
             Ipse.Extension.canonical_digest([IpseKnowledge.Knowledge.Contracts.recipe("note")])
    [change] = commit["request"]["changes"]
    assert change["expected_revision"] == 0

    assert change["value"]["evidence"]["sources"] |> hd() |> Map.fetch!("origin") ==
             "native_operator_assertion"

    assert commit["proofs"] == [
             %{"handle" => "synthetic.handle", "quote" => "Acme has owner Alex"}
           ]

    assert byte_size(IO.iodata_to_binary(JSON.encode!(commit))) <= 8192

    {%{"status" => "saved", "category" => "ordinary"}, %{phase: :idle}} =
      value(respond(state, %{"generation" => 8}))
  end

  test "shadow capture returns its save result without starting an assessment" do
    {:ok, %{phase: :idle}} = Shadow.init(options())
    state = start()
    {_, state} = request(respond(state, %{"record" => nil}))
    {commit, state} = request(respond(state, %{"record" => nil, "generation" => 7}))
    [change] = commit["request"]["changes"]

    {%{"status" => "saved", "key" => key, "receipt" => %{"generation" => 8}}, %{phase: :idle}} =
      value(shadow_respond(state, %{"generation" => 8}))
    assert key == change["key"]
  end

  test "shadow assessment reads an existing note before requesting advice" do
    state = start()
    {_, state} = request(respond(state, %{"record" => nil}))
    {commit, _} = request(respond(state, %{"record" => nil, "generation" => 7}))
    [change] = commit["request"]["changes"]
    key = change["key"]
    note = change["value"]
    {:ok, idle} = Shadow.init(options())

    {read, pending} =
      request(Shadow.handle("invoke.tool", %{"id" => "assess", "arguments" => %{"key" => key}}, idle))

    assert read == %{"op" => "collection.call", "request" => %{"op" => "get", "key" => key}}

    {decision, pending} =
      request(shadow_respond(pending, %{"record" => %{"key" => key, "value" => note}}))

    assert decision["op"] == "decision.create"
    assert JSON.decode!(decision["input"])["candidates"] == [
             %{"id" => "candidate", "input" => IO.iodata_to_binary(JSON.encode!(note))}
           ]

    answer = fn probability ->
      %{"version" => 1, "answers" => [%{
        "id" => "candidate", "type" => "choice", "choice" => "defer_candidate",
        "confidence" => probability,
        "probabilities" => [
          %{"id" => "defer_candidate", "probability" => probability},
          %{"id" => "keep_baseline", "probability" => 1 - probability}
        ]
      }]}
    end

    for {result, expected_choice, expected_reason} <- [
          {answer.(0.9), "defer_candidate", "selected"},
          {answer.(0.6), nil, "low_probability"},
          {%{"version" => 1, "answers" => [%{"id" => "candidate", "type" => "refusal"}]}, nil, "refusal"}
        ] do
      {%{"status" => "assessed", "key" => ^key, "experimental" => true,
         "note_mutation" => "none", "advice" => %{"choice" => ^expected_choice, "reason" => ^expected_reason}},
       %{phase: :idle}} = value(shadow_respond(pending, %{"result" => result}))
    end

    {%{"status" => "refused"}, %{phase: :idle}} =
      value(shadow_respond(pending, %{"result" => %{}}))

    assert Enum.any?(Shadow.describe()["exports"]["tools"], &(&1["id"] == "assess"))
    refute Enum.any?(K.describe()["exports"]["tools"], &(&1["id"] == "assess"))
  end

  test "shadow assessment refuses a missing or mismatched note" do
    {:ok, idle} = Shadow.init(options())
    key = "note." <> String.duplicate("a", 64)

    for record <- [nil, %{"key" => key, "value" => %{}}, %{"key" => "note.wrong", "value" => %{}}] do
      {_, pending} =
        request(Shadow.handle("invoke.tool", %{"id" => "assess", "arguments" => %{"key" => key}}, idle))

      {%{"status" => "refused"}, %{phase: :idle}} = shadow_respond(pending, %{"record" => record}) |> value()
    end
  end

  defp pending_page(rows, total, generation, next \\ nil),
    do: %{"records" => rows, "count" => total, "generation" => generation,
      "coverage" => "metadata_only", "prefix" => "pending.", "next" => next}

  defp empty_pending(state, generation) do
    state = if state.phase == :capture_budget, do: elem(request(respond(state,budget())),1), else: state
    request(respond(state, pending_page([], 0, generation)))
  end

  defp budget_state(generation \\ 7) do
    state = start("assistant_proposal")
    {_, state} = request(respond(state, %{"record" => nil}))
    {request, state} = request(respond(state, %{"records" => [], "generation" => generation}))
    assert request == %{"op" => "collection.call", "purpose" => "saved_policy_budget_v1", "request" => %{"op" => "status"}}
    state
  end

  defp capacity_state(generation \\ 7) do
    {request,state} = request(respond(budget_state(generation),budget()))
    assert request == %{"op" => "collection.call", "request" => %{"op" => "index", "prefix" => "pending.", "cursor" => nil, "limit" => 32}}
    state
  end

  defp budget(n \\ 0, unknown \\ 0) do
    zero = Map.new(~w(operations model_calls input_bytes output_bytes download_bytes cost_nanos),&{&1,0})
    limits = Map.merge(zero,%{"operations" => 100,"input_bytes" => 2097152,"output_bytes" => 4194304})
    %{"version" => 1,"scope" => "saved_policy","project" => String.duplicate("a",64),"epoch" => 1,
      "policy_sha256" => String.duplicate("b",64),"observed_at_ms" => 1000,"period_start_ms" => 0,"period_end_ms" => 86400000,
      "limits" => limits,"charged" => Map.put(zero,"operations",n),"available" => Map.put(limits,"operations",max(100-n,0)),
      "nonterminal_reserved" => Map.put(zero,"operations",unknown),"unknown_reserved" => Map.put(zero,"operations",unknown),
      "warning_dimensions" => if(n >= 80,do: ["operations"],else: []),"exhausted_dimensions" => if(n >= 100,do: ["operations"],else: [])}
  end

  defp rows(count, bytes \\ 512) do
    for n <- 1..count, count > 0 do
      %{"key" => "pending." <> (Integer.to_string(n,16) |> String.pad_leading(64,"0")),
        "revision" => 1, "bytes" => bytes, "sha256" => String.duplicate("a",64)}
    end
  end

  test "capturing a pending proposal does not start shadow assessment" do
    state = start("assistant_proposal")
    {_, state} = request(respond(state, %{"record" => nil}))
    {_, state} = request(respond(state, %{"records" => [], "generation" => 7}))
    {_, state} = empty_pending(state, 7)
    {%{"status" => "saved", "category" => "pending"}, %{phase: :idle}} =
      value(shadow_respond(state, %{"generation" => 8}))
  end

  test "shadow assessment explicitly reads one pending proposal and returns advice only" do
    state = start("assistant_proposal")
    {_, state} = request(respond(state, %{"record" => nil}))
    {_, state} = request(respond(state, %{"records" => [], "generation" => 7}))
    {commit, _} = empty_pending(state, 7)
    [change] = commit["request"]["changes"]
    key = change["key"]
    proposal = change["value"]
    assert "pending." <> _ = key

    {:ok, idle} = Shadow.init(options())
    {read, pending} = request(Shadow.handle("invoke.tool", %{"id" => "assess", "arguments" => %{"key" => key}}, idle))
    assert read == %{"op" => "collection.call", "purpose" => "decision_shadow_pending_v1",
      "request" => %{"op" => "get", "key" => key}}
    {decision, pending} = request(shadow_respond(pending, %{"record" => %{"key" => key, "value" => proposal}}))
    assert decision["op"] == "decision.create"
    [candidate] = JSON.decode!(decision["input"])["candidates"]
    assert JSON.decode!(candidate["input"]) == %{
      "candidate_id" => proposal["id"], "text" => proposal["text"],
      "assigned_category" => proposal["assigned_category"], "reason" => proposal["reason"]
    }

    result = %{"version" => 1, "answers" => [%{"id" => "candidate", "type" => "choice",
      "choice" => "keep_baseline", "confidence" => 0.9,
      "probabilities" => [%{"id" => "keep_baseline", "probability" => 0.9},
        %{"id" => "defer_candidate", "probability" => 0.1}]}]}
    {%{"status" => "assessed", "key" => ^key, "note_mutation" => "none"}, %{phase: :idle}} =
      value(shadow_respond(pending, %{"result" => result}))
  end

  test "an operator-event fragment queues a proposal instead of a literal note" do
    {:ok, state} = K.init(options())
    {_, state} = request(K.handle("invoke.tool", %{"id" => "capture", "arguments" => attrs()}, state))
    full = "The report says: Acme has owner Alex"
    page = %{page("interactive_operator") | "text" => full, "content_sha256" => Ipse.JSON.sha256(full), "original_bytes" => byte_size(full)}
    {_, state} = request(respond(state, page))
    quote = attrs()["source"]["quote"]
    start = byte_size("The report says: ")
    receipt = %{quote_receipt(page) | "start_byte" => start, "end_byte" => start + byte_size(quote), "quote_sha256" => Ipse.JSON.sha256(quote)}
    {_, state} = request(respond(state, receipt))
    {%{"request" => %{"op" => "index", "prefix" => "pending." <> _}}, _} = request(respond(state, %{"record" => nil}))
  end

  test "duplicate capture never overwrites or renews an existing record" do
    state = start()
    {_, state} = request(respond(state, %{"record" => nil}))

    {%{"status" => "existing", "renewed" => false, "revision" => 3}, _} =
      value(respond(state, %{"record" => %{"revision" => 3}, "generation" => 9}))
  end

  test "pending duplicate detection uses metadata only and never renews a match" do
    state = start("assistant_proposal")
    {%{"request" => %{"op" => "index", "prefix" => key, "cursor" => nil, "limit" => 1}}, state} =
      request(respond(state, %{"record" => nil}))
    assert "pending." <> _ = key

    {%{"status" => "existing", "key" => ^key, "revision" => 3, "renewed" => false}, _} =
      value(respond(state, %{"records" => [%{"key" => key, "revision" => 3}], "generation" => 9}))

    for records <- [[], [%{"key" => key <> ".suffix", "revision" => 4}]] do
      {_, queued} = request(respond(state, %{"records" => records, "generation" => 9}))
      {commit, _} = empty_pending(queued, 9)
      assert commit["request"]["expected_generation"] == 9
      assert [%{"key" => ^key, "expected_revision" => 0}] = commit["request"]["changes"]
    end

    {%{"status" => "refused", "code" => "invalid_index_progress"}, _} =
      value(respond(state, %{"records" => [%{"key" => "other", "revision" => 1}], "generation" => 9}))
  end

  test "saved session-only suppression stops paraphrases before any commit" do
    state = start("interactive_operator", attrs("Alex owns Acme"))

    override = %{
      "version" => 1,
      "lineage" => state.ctx.lineage,
      "policy" => %{"kind" => "session"},
      "reason" => "operator forgot this",
      "updated_at_ms" => 0
    }

    {:ok, stored} = IpseKnowledge.Knowledge.Records.override_record(override, state.ctx.proof)
    {%{"status" => "suppressed"}, _} =
      value(respond(state, %{"record" => %{"value" => stored}}))

    {%{"status" => "refused", "code" => "invalid_saved_override"}, _} =
      value(
        respond(state, %{
          "record" => %{"value" => %{stored | "lineage" => String.duplicate("f", 64)}}
        })
      )
  end

  test "assistant claims remain pending and retain independent protected-host queue enforcement" do
    state = start("assistant_proposal")

    {%{"request" => %{"op" => "index", "prefix" => "pending." <> _}}, state} =
      request(respond(state, %{"record" => nil}))

    {_, state} = request(respond(state, %{"records" => [], "generation" => 5}))
    {commit, _} = empty_pending(state, 5)
    assert commit["op"] == "collection.managed"
    assert commit["request"]["expected_generation"] == 5
    assert {:ok, commit["recipe_sha256"]} ==
             Ipse.Extension.canonical_digest([IpseKnowledge.Knowledge.Contracts.recipe("pending")])
    [change] = commit["request"]["changes"]
    assert change["value"]["kind"] == "proposal"
    assert change["value"]["state"] == "pending"
    assert change["value"]["expires_at_ms"] - change["value"]["created_at_ms"] == 604_800_000

  end

  test "conflict and unknown effects return terminal evidence without retrying" do
    state = start()
    {_, state} = request(respond(state, %{"record" => nil}))
    {_, state} = request(respond(state, %{"record" => nil, "generation" => 1}))

    for status <- ~w(conflict unknown failed) do
      {%{"status" => "interrupted", "outcome" => %{"status" => ^status}}, %{phase: :idle}} =
        value(
          K.handle("host.actions", %{"outcome" => %{"status" => status, "value" => %{}}}, state)
        )
    end
  end

  test "malformed invocations and source proof tampering cannot reach publication" do
    {:ok, state} = K.init(options())

    for args <- [
          Map.put(attrs(), "origin", "interactive_operator"),
          %{attrs() | "text" => String.duplicate("x", 2049)},
          %{attrs() | "category" => "pin"}
        ] do
      {%{"status" => "refused"}, _} =
        value(K.handle("invoke.tool", %{"id" => "capture", "arguments" => args}, state))
    end

    {_, state} =
      request(K.handle("invoke.tool", %{"id" => "capture", "arguments" => attrs()}, state))

    {_, state} = request(respond(state, page("interactive_operator")))

    {%{"status" => "refused", "code" => "source_refused"}, _} =
      value(
        respond(state, %{
          quote_receipt(page("interactive_operator"))
          | "quote_sha256" => Ipse.JSON.sha256("forged")
        })
      )
  end

  test "the 52nd projected pending record warns without pausing or changing consent limits" do
    state = capacity_state()
    {request, state} = request(respond(state,pending_page(Enum.take(rows(51),32),51,7,"next")))
    assert request["request"]["cursor"] == "next"
    {commit, state} = request(respond(state,pending_page(Enum.drop(rows(51),32),51,7)))
    assert commit["op"] == "collection.managed"
    assert [%{"expected_revision" => 0, "key" => "pending." <> _}] = commit["request"]["changes"]
    {saved, _} = value(respond(state,%{"generation" => 8}))
    assert saved["status"] == "saved"
    assert saved["capacity"]["notice"] == "pending_capacity_80_percent"
    assert saved["capacity"]["scope"] == "pending_queue"
    assert saved["capacity"]["records"] == 52
    refute Map.has_key?(saved["capacity"],"consent")
    state = capacity_state()
    {_, state} = request(respond(state,pending_page(Enum.take(rows(50),32),50,7,"next")))
    {_, state} = request(respond(state,pending_page(Enum.drop(rows(50),32),50,7)))
    {saved, _} = value(respond(state,%{"generation" => 8}))
    refute Map.has_key?(saved,"capacity")
    # Legacy admitted rows can exceed today's 4 KiB proposal constructor.
    state = capacity_state()
    {_, state} = request(respond(state,pending_page(Enum.take(rows(36,5900),32),36,7,"next")))
    {_, state} = request(respond(state,pending_page(Enum.drop(rows(36,5900),32),36,7)))
    {saved, _} = value(respond(state,%{"generation" => 8}))
    assert saved["capacity"]["records"] == 37
    assert saved["capacity"]["bytes"] * 5 >= 262144 * 4
  end

  test "a full pending queue returns a visible pause without a mutation or bytes claim" do
    {paused, state} = value(respond(capacity_state(),pending_page(rows(32),64,7,"rest")))
    assert paused["status"] == "paused" and paused["mutation"] == "none"
    assert paused["code"] == "pending_capacity"
    assert paused["capacity"]["records"] == 64
    assert paused["capacity"]["bytes"] == nil
    assert state.phase == :idle
  end

  test "a complete pending byte inventory can pause before count64 without touching pins" do
    state = capacity_state()
    {_, state} = request(respond(state,pending_page(Enum.take(rows(63,4160),32),63,7,"next")))
    {paused, _} = value(respond(state,pending_page(Enum.drop(rows(63,4160),32),63,7)))
    assert paused["status"] == "paused"
    assert paused["capacity"]["records"] == 63
    assert paused["capacity"]["bytes"] == 262080
    assert paused["mutation"] == "none"
  end

  test "untrusted pending metadata progress and root changes refuse rather than authorizing capture" do
    valid = pending_page(rows(1),1,7)
    invalid = [Map.put(valid,"generation",8),Map.put(valid,"prefix","note."),
      Map.put(valid,"coverage","complete"),Map.put(valid,"count",2),
      Map.put(valid,"records",[%{"key" => "pending.bad"}]),
      Map.put(valid,"records",[%{hd(rows(1)) | "key" => "note." <> String.duplicate("a",64)}]),
      Map.put(valid,"records",["malformed"])]
    for page <- invalid do
      {refused, state} = value(respond(capacity_state(),page))
      assert refused == %{"status" => "refused", "code" => "invalid_pending_capacity_index"}
      assert state.phase == :idle
    end
    {_, state} = request(respond(capacity_state(),pending_page(Enum.take(rows(63),20),63,7,"same")))
    {refused, _} = value(respond(state,pending_page(rows(63)|>Enum.drop(20)|>Enum.take(20),63,7,"same")))
    assert refused["code"] == "invalid_pending_capacity_index"
    for final <- [pending_page(Enum.drop(rows(36),32),36,8),pending_page(Enum.drop(rows(36),32),37,7)] do
      {_, state} = request(respond(capacity_state(),pending_page(Enum.take(rows(36),32),36,7,"next")))
      {refused, _} = value(respond(state,final))
      assert refused["code"] == "invalid_pending_capacity_index"
    end
  end

  test "deduplication finishes before the queue inventory and does not renew a stored candidate" do
    state = start("assistant_proposal")
    {request, state} = request(respond(state,%{"record" => nil}))
    key = request["request"]["prefix"]
    {existing, state} = value(respond(state,%{"records" => [%{"key" => key,"revision" => 9}],"generation" => 7}))
    assert existing["status"] == "existing" and existing["renewed"] == false
    assert state.phase == :idle
  end

  test "generic permission failures and unknown outcomes are not relabeled as budget pauses" do
    for status <- ~w(denied failed unknown conflict) do
      {interrupted, state} = value(K.handle("host.actions",%{"operation_id" => String.duplicate("a",32),
        "outcome" => %{"status" => status,"value" => %{}}},capacity_state()))
      assert interrupted["status"] == "interrupted"
      assert interrupted["outcome"]["status"] == status
      assert state.phase == :idle
    end
  end

  test "the burst declaration counts320raw proposals independently of native effects" do
    raw = Enum.map(1..320, fn n ->
      cond do
        n <= 64 -> {:new,n}
        n <= 128 -> {:duplicate,n-64}
        n <= 160 -> {:invalid,n}
        true -> {:new,n}
      end
    end)
    assert length(Enum.chunk_every(raw,8)) == 40
    assert Enum.frequencies_by(raw,&elem(&1,0)) == %{new: 224,duplicate: 64,invalid: 32}
    # These are raw inputs, not simulated native approvals or actual admissions.
    assert Enum.count(raw,fn {kind,_}->kind==:new end) > 100
  end

  test "only an observed saved budget warns at80 and pauses at100 before queue or mutation" do
    for {n,warning} <- [{0,false},{79,false},{80,true},{99,true}] do
      {_,state} = request(respond(budget_state(),budget(n)))
      {_,state} = empty_pending(state,7)
      {saved,_} = value(respond(state,%{"generation" => 8}))
      assert saved["status"] == "saved"
      assert Map.has_key?(saved,"budget") == warning
      if warning do
        assert saved["budget"]["observation"] == "advisory"
        assert saved["budget"]["scope"] == "saved_policy"
        assert saved["budget"]["snapshot"]["charged"]["operations"] == n
      end
    end
    {paused,state} = value(respond(budget_state(),budget(100)))
    assert paused["status"] == "paused" and paused["code"] == "saved_policy_budget"
    assert paused["mutation"] == "none" and state.phase == :idle
    assert paused["budget"]["snapshot"]["exhausted_dimensions"] == ["operations"]
    refute Map.has_key?(paused,"capacity")
  end

  test "unresolved saved liabilities retain pressure without asserting service quarantine" do
    {paused,_} = value(respond(budget_state(),budget(100,100)))
    assert paused["budget"]["snapshot"]["unknown_reserved"]["operations"] == 100
    assert paused["budget"]["snapshot"]["nonterminal_reserved"]["operations"] == 100
    refute Map.has_key?(paused["budget"],"quarantine")
    refute Map.has_key?(paused["budget"],"service_quarantine")
  end

  test "actual encoded tool previews show readable allowance and queue notices within the existing 800 characters" do
    for {n,size} <- [{80,:normal},{100,:normal},{80,:maximum},{100,:maximum}] do
      snapshot = budget(n)
      snapshot = %{snapshot | "observed_at_ms" => 1762000000000,
        "period_start_ms" => 1761955200000, "period_end_ms" => 1762041600000}
      snapshot =
        if size == :maximum do
          maximum = 9_007_199_254_740_991
          used = if n == 100,do: maximum,else: div(maximum * 4 + 4,5)
          resources = ~w(operations model_calls input_bytes output_bytes download_bytes cost_nanos)
          %{snapshot | "epoch" => maximum,
            "limits" => Map.new(resources,&{&1,maximum}),
            "charged" => Map.new(resources,&{&1,used}),
            "available" => Map.new(resources,&{&1,maximum-used}),
            "warning_dimensions" => resources,
            "exhausted_dimensions" => if(n == 100,do: resources,else: [])}
        else
          snapshot
        end
      outcome = respond(budget_state(),snapshot)
      result =
        if n == 100 do
          {value,_} = value(outcome)
          value
        else
          {_,state} = request(outcome)
          {_,state} = empty_pending(state,7)
          {value,_} = value(respond(state,%{"generation" => 8}))
          value
        end
      preview = String.slice(Jason.encode!(result),0,800)
      assert String.contains?(preview,if(n == 100,do: "Saving paused:",else: "Saved knowledge allowance is nearing a limit."))
      assert String.contains?(preview,"Observed capacity: #{snapshot["available"]["operations"]} operations")
      assert String.contains?(preview,"#{snapshot["available"]["input_bytes"]} input bytes")
      assert String.contains?(preview,"#{snapshot["available"]["output_bytes"]} output bytes")
      assert result["budget"]["snapshot"] === snapshot
      assert result["budget"]["snapshot"]["limits"] == snapshot["limits"]
      assert result["budget"]["snapshot"]["charged"] == snapshot["charged"]
      assert result["budget"]["snapshot"]["observed_at_ms"] == snapshot["observed_at_ms"]
      refute Map.has_key?(result["budget"],"permission")
    end
    {_,state} = request(respond(capacity_state(),pending_page(Enum.take(rows(51),32),51,7,"next")))
    {_,state} = request(respond(state,pending_page(Enum.drop(rows(51),32),51,7)))
    {saved,_} = value(respond(state,%{"generation" => 8}))
    assert String.contains?(String.slice(Jason.encode!(saved),0,800),"Pending proposals are nearing queue capacity:")
    {paused,_} = value(respond(capacity_state(),pending_page(rows(32),64,7,"rest")))
    assert String.contains?(String.slice(Jason.encode!(paused),0,800),"Saving paused:")
    assert paused["capacity"]["bytes"] == nil
  end

  test "unused zero dimensions never pause but known positive zero-limit pressure does" do
    {_,state} = request(respond(budget_state(),budget()))
    assert state.phase == :pending_capacity
    equality = budget() |> put_in(["limits","model_calls"],1) |> put_in(["charged","model_calls"],1)
      |> Map.put("warning_dimensions",["model_calls"]) |> Map.put("exhausted_dimensions",["model_calls"])
    {_,state} = request(respond(budget_state(),equality))
    assert state.phase == :pending_capacity
    {_,state} = empty_pending(state,7)
    {saved,_} = value(respond(state,%{"generation" => 8}))
    assert saved["status"] == "saved" and saved["budget"]["capture_blocked_dimensions"] == []
    for resource <- ~w(operations input_bytes output_bytes) do
      disabled = budget() |> put_in(["limits",resource],0) |> put_in(["available",resource],0)
      {paused,_} = value(respond(budget_state(),disabled))
      assert paused["code"] == "saved_policy_budget"
      assert paused["budget"]["capture_blocked_dimensions"] == [resource]
    end
    impossible = budget() |> put_in(["charged","model_calls"],1) |> put_in(["unknown_reserved","model_calls"],1)
      |> put_in(["nonterminal_reserved","model_calls"],1) |> Map.put("exhausted_dimensions",["model_calls"])
    {paused,_} = value(respond(budget_state(),impossible))
    assert paused["code"] == "saved_policy_budget"
    assert paused["budget"]["snapshot"]["exhausted_dimensions"] == ["model_calls"]
  end

  test "malformed saved budget callbacks refuse without guessing balance or creating a permit" do
    v = budget(80)
    for bad <- [Map.put(v,"operation_ids",[]),Map.put(v,"epoch",0),Map.put(v,"scope","service"),
      Map.put(v,"policy_sha256","bad"),put_in(v,["available","operations"],21),
      Map.put(v,"warning_dimensions",[]),put_in(v,["unknown_reserved","operations"],81),
      Map.put(v,"observed_at_ms",86400000)] do
      {refused,state} = value(respond(budget_state(),bad))
      assert refused == %{"status" => "refused","code" => "invalid_saved_budget_snapshot"}
      assert state.phase == :idle
    end
  end

  test "a later real admission refusal stays a refusal after an earlier advisory snapshot" do
    {_,state} = request(respond(budget_state(),budget(80)))
    {commit,state} = empty_pending(state,7)
    assert commit["op"] == "collection.managed"
    {interrupted,_} = value(K.handle("host.actions",%{"operation_id" => String.duplicate("a",32),
      "outcome" => %{"status" => "failed","value" => %{"code" => "collection_consent_denied"}}},state))
    assert interrupted["status"] == "interrupted"
    assert interrupted["outcome"]["value"]["code"] == "collection_consent_denied"
    refute Map.has_key?(interrupted,"budget")
  end

  test "budget observation failures remain unattributed and cannot become budget pauses" do
    for status <- ~w(denied failed unknown) do
      {interrupted,state} = value(K.handle("host.actions",%{"operation_id" => String.duplicate("a",32),
        "outcome" => %{"status" => status,"value" => %{}}},budget_state()))
      assert interrupted["status"] == "interrupted" and interrupted["outcome"]["status"] == status
      refute Map.has_key?(interrupted,"budget")
      assert state.phase == :idle
    end
  end

  end
  result = ExUnit.run()
  if result.failures > 0, do: System.halt(1)
  """

  test "bounded capture continuations run in an independent VM" do
    modules = [IpseKnowledge.Profiles, IpseKnowledge.Knowledge]
    before = Enum.map(modules, &:code.is_loaded/1)
    sdk = Application.app_dir(:ipse, "ebin")
    paths = Path.wildcard(Path.join(Path.dirname(Path.dirname(sdk)), "*/ebin"))
    args = ["--erl", "+S 2:2"] ++ Enum.flat_map(paths, &["-pa", &1]) ++ ["-e", @suite]
    {output, status} = System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)
    assert status == 0, output
    assert output =~ "27 passed"
    assert Enum.map(modules, &:code.is_loaded/1) == before
  end
end
