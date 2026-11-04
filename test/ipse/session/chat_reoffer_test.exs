Code.require_file("../../support/managed_policy.exs", __DIR__)

defmodule Ipse.Session.ChatReofferTest do
  use ExUnit.Case, async: true
  alias Ipse.{JSON, Journal, Session.ChatReviewHandoff}
  alias Ipse.Extension.{Consent, Mode}
  alias Ipse.CLI.Knowledge.Management
  alias Ipse.Test.ManagedPolicy, as: F

  setup do
    proof = F.proof("assistant_proposal")
    session = proof["session_id"]

    pin =
      Map.new(
        ~w(project_id worktree_id binding_sha256 policy_sha256 identity_sha256 namespace routes_sha256 source_sha256),
        &{&1, F.hash(&1)}
      )
      |> Map.merge(%{"version" => 1, "session_id" => session, "epoch" => 1})

    event = %{
      "type" => "pending_chat_review_handoff",
      "version" => 1,
      "handoff_id" => String.duplicate("b", 32),
      "session_id" => session,
      "turn_id" => String.duplicate("c", 32),
      "request_id" => String.duplicate("d", 32),
      "client_id" => String.duplicate("e", 32),
      "client_generation" => String.duplicate("f", 32),
      "nomination_sha256" => F.hash("nomination"),
      "capture_intent_sha256" => F.hash("intent"),
      "capture_result_sha256" => F.hash("result"),
      "pending_key" => "pending." <> F.hash("pending"),
      "text" => proof["quote"],
      "category" => "ordinary",
      "reason" => "Synthetic recommendation",
      "source_proof" => proof,
      "pin" => pin
    }

    assert {:ok, source} = Journal.source(session, 100, event)
    original = %{"event" => event, "source" => source}
    assert ChatReviewHandoff.valid?(original)
    assert {:ok, mode} = Mode.capture(%{approval: :ask, approval_origin: :interactive})

    assert {:ok, review} =
             ChatReviewHandoff.reoffer(
               original,
               String.duplicate("1", 32),
               String.duplicate("2", 32),
               String.duplicate("3", 32),
               2,
               mode
             )

    assert {:ok, review_source} = Journal.source(session, 200, review)
    assert {:ok, wrapper} = ChatReviewHandoff.wrap_reoffer(original, review, review_source)
    header = %{"type" => "session", "metadata" => %{"execution_mode" => mode}}
    records = [header, event, %{"type" => "turn_finished", "status" => "ok"}, review]

    %{
      original: original,
      wrapper: wrapper,
      review: review,
      source: review_source,
      mode: mode,
      records: records,
      session: session
    }
  end

  test "fresh reoffer retains immutable provenance while binding a new review and focus", c do
    assert ChatReviewHandoff.origin(c.wrapper) === c.original
    assert ChatReviewHandoff.client_id(c.wrapper) === c.review["client_id"]
    assert ChatReviewHandoff.client_generation(c.wrapper) === c.review["client_generation"]
    assert ChatReviewHandoff.render_revision(c.wrapper) === 2

    refute ChatReviewHandoff.operation_id(c.wrapper) ===
             ChatReviewHandoff.operation_id(c.original)

    assert :ok = ChatReviewHandoff.validate_reoffers(c.records, c.session)
    assert {:error, _} = ChatReviewHandoff.claim_management_attempt(c.wrapper)
    assert ChatReviewHandoff.current_review?(c.wrapper, c.records)
    refute ChatReviewHandoff.current_review?(c.original, c.records)

    refute ChatReviewHandoff.current_review?(
             c.wrapper,
             c.records ++ [%{"type" => "input_received"}]
           )

    refute ChatReviewHandoff.current_review?(c.wrapper, c.records ++ [%{"type" => "cancelled"}])

    refute ChatReviewHandoff.current_review?(
             c.wrapper,
             c.records ++ [%{"type" => "source_window_opened"}]
           )
  end

  test "a foreign caller cannot turn a valid serialized origin into an append or input pause",
       c do
    owner =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    on_exit(fn -> send(owner, :stop) end)
    snapshot = make_ref()
    channel = "actual-owner-channel"

    state = %{
      phase: :idle,
      task: nil,
      share_barrier: nil,
      operator_channel: %{id: channel, client: owner, reader: self(), generation: "generation"},
      chat_reoffer_snapshot: %{ref: snapshot},
      journal_writer: self()
    }

    assert {:reply, {:error, :chat_review_unavailable}, next} =
             Ipse.Session.handle_call(
               {:activate_chat_reoffer, channel, snapshot, c.original, 2},
               {self(), make_ref()},
               state
             )

    assert next === state
    refute_receive {:"$gen_call", _, _}

    assert {:reply, {:error, :chat_review_unavailable}, ^state} =
             Ipse.Session.handle_call(
               {:activate_chat_reoffer, channel, make_ref(), c.original, 2},
               {self(), make_ref()},
               state
             )
  end

  test "startup snapshot does not arm a reader and an authorized read invalidates it first", c do
    owner = self()

    reader =
      spawn(fn ->
        receive do
          message -> send(owner, {:unexpected_reader_message, message})
        end
      end)

    on_exit(fn -> Process.exit(reader, :kill) end)
    channel = "startup-channel"

    state = %{
      id: c.session,
      phase: :idle,
      task: nil,
      share_barrier: nil,
      draft: nil,
      turn_id: nil,
      last_request_id: nil,
      input_generation: 0,
      config: %{approval: :ask, approval_origin: :interactive},
      operator_channel: %{id: channel, client: owner, reader: reader, generation: "generation"},
      chat_review_reoffer: true,
      chat_reoffer_choices: [
        %{key: c.original["event"]["pending_key"], sha256: JSON.digest([c.original["event"]])}
      ],
      chat_reoffer_snapshot: nil
    }

    assert {:reply, {:ok, snapshot}, prepared} =
             Ipse.Session.handle_call(
               {:chat_reoffer_snapshot, channel},
               {owner, make_ref()},
               state
             )

    assert is_reference(snapshot.ref)
    assert prepared.chat_reoffer_snapshot.turn === nil
    assert prepared.chat_reoffer_snapshot.request === nil
    refute_receive {:unexpected_reader_message, _}

    busy = %{prepared | phase: :managed_approval}
    request = {:observe_channel, channel, %{"kind" => "prompt"}, 1_000}

    assert {:reply, {:error, :operator_input_unavailable}, ^busy} =
             Ipse.Session.handle_call(request, {owner, make_ref()}, busy)

    assert {:reply, {:error, :operator_input_busy}, invalidated} =
             Ipse.Session.handle_call(request, {reader, make_ref()}, busy)

    assert invalidated.chat_reoffer_snapshot === nil

    invalid_request = {:observe_channel, channel, %{"kind" => "unknown"}, 1_000}

    assert {:reply, {:error, :operator_input_unavailable}, invalidated} =
             Ipse.Session.handle_call(invalid_request, {reader, make_ref()}, prepared)

    assert invalidated.chat_reoffer_snapshot === nil
  end

  test "wrong source, old client, repeated focus or render, and non-idle history cannot redraw",
       c do
    for review <- [
          Map.put(c.review, "client_id", c.original["event"]["client_id"]),
          Map.put(c.review, "client_generation", c.original["event"]["client_generation"]),
          Map.put(c.review, "origin_sha256", F.hash("foreign origin")),
          Map.put(c.review, "session_id", String.duplicate("f", 32)),
          Map.put(c.review, "render_revision", 1),
          put_in(c.review, ["mode", "ceiling"], "planning"),
          Map.put(c.review, "extra", true)
        ] do
      refute ChatReviewHandoff.valid_reoffer?(review, c.original)

      assert {:error, _} =
               ChatReviewHandoff.validate_reoffers(
                 List.replace_at(c.records, 3, review),
                 c.session
               )
    end

    assert {:ok, foreign_source} = Journal.source(String.duplicate("f", 32), 200, c.review)
    assert {:error, _} = ChatReviewHandoff.wrap_reoffer(c.original, c.review, foreign_source)
    assert {:ok, early_source} = Journal.source(c.session, 50, c.review)
    assert {:error, _} = ChatReviewHandoff.wrap_reoffer(c.original, c.review, early_source)
    assert {:error, _} = ChatReviewHandoff.validate_reoffers(c.records ++ [c.review], c.session)

    assert {:error, _} =
             ChatReviewHandoff.validate_reoffers(
               List.insert_at(c.records, 3, %{"type" => "input_received"}),
               c.session
             )

    later =
      c.review
      |> Map.put("review_id", String.duplicate("4", 32))
      |> Map.put("render_revision", 3)
      |> Map.put("client_id", String.duplicate("5", 32))
      |> Map.put("client_generation", String.duplicate("6", 32))

    assert {:error, _} = ChatReviewHandoff.validate_reoffers(c.records ++ [later], c.session)
    later = Map.put(later, "focus_id", String.duplicate("7", 32))
    assert :ok = ChatReviewHandoff.validate_reoffers(c.records ++ [later], c.session)
    assert :ok = ChatReviewHandoff.validate_reoffers([], c.session)
  end

  defp operation(wrapper, receipt) do
    %{
      "id" => ChatReviewHandoff.operation_id(wrapper),
      "epoch" => wrapper["event"]["pin"]["epoch"],
      "status" => "settled",
      "request_sha256" => JSON.digest(["chat_pending_review", 1, wrapper]),
      "actual" => Consent.zero(),
      "receipt" => receipt
    }
  end

  defp refused_journal(wrapper) do
    %{
      id: String.duplicate("8", 32),
      records: [
        %{
          "type" => "session",
          "metadata" => %{
            "kind" => "knowledge_management",
            "version" => 1,
            "pending_acceptance_layout" => Ipse.Session.PendingAcceptance.layout(),
            "chat_review_handoff" => wrapper
          }
        }
      ]
    }
  end

  test "known refusal can reoffer but unknown, missing contradictory and wrong accounting cannot",
       c do
    assert {:ok, :unstarted} = Management.chat_review_prior_state(c.original, nil, [])
    refused = operation(c.original, %{"refused" => true})
    assert {:ok, :refused} = Management.chat_review_prior_state(c.original, refused, [])
    journal = refused_journal(c.original)
    assert {:ok, :refused} = Management.chat_review_prior_state(c.original, refused, [journal])
    assert {:error, _} = Management.chat_review_prior_state(c.original, nil, [journal])

    for changed <- [
          Map.put(refused, "status", "reserved"),
          Map.put(refused, "status", "admitted"),
          Map.put(refused, "status", "publishing"),
          Map.put(refused, "status", "unknown"),
          Map.put(refused, "status", "overrun"),
          Map.put(refused, "status", "reconciled_overrun"),
          Map.put(refused, "epoch", 2),
          Map.put(refused, "request_sha256", F.hash("foreign request")),
          Map.put(refused, "receipt", %{"reconciled" => true}),
          put_in(refused, ["actual", "operations"], 1)
        ] do
      assert {:error, _} = Management.chat_review_prior_state(c.original, changed, [journal])
    end

    assert {:error, _} =
             Management.chat_review_prior_state(c.original, refused, [journal, journal])

    forged =
      put_in(journal, [:records, Access.at(0), "metadata", "chat_review_handoff"], c.wrapper)

    assert {:error, _} = Management.chat_review_prior_state(c.original, refused, [forged])
  end

  test "compacted accounting needs a matching validated disposition, not a hash alone", c do
    compact =
      operation(c.original, %{"refused" => true})
      |> Map.delete("receipt")
      |> Map.merge(%{
        "receipt_compacted" => true,
        "receipt_sha256" => JSON.digest([%{"refused" => true}])
      })

    assert {:error, _} = Management.chat_review_prior_state(c.original, compact, [])

    assert {:ok, :refused} =
             Management.chat_review_prior_state(c.original, compact, [refused_journal(c.original)])

    assert {:error, _} =
             Management.chat_review_prior_state(
               c.original,
               Map.put(compact, "receipt_sha256", F.hash("other receipt")),
               [refused_journal(c.original)]
             )
  end
end
