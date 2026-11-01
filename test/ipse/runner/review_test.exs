defmodule Ipse.Test.ReviewRunner do
  @moduledoc false
  def operator_input(display, 120_000, 2) do
    Process.put({__MODULE__, :calls}, Process.get({__MODULE__, :calls}, 0) + 1)
    Process.put({__MODULE__, :display}, display)
    [_, input] = Regex.run(~r/\nType ([a-z][a-z0-9_-]{0,31} [0-9a-f]{16}) to confirm,/, display)

    observation = %{
      "version" => 2,
      "event_id" => String.duplicate("a", 32),
      "text" => input,
      "text_sha256" => Ipse.JSON.sha256(input),
      "display_sha256" => Ipse.JSON.sha256(display),
      "input_limit" => 1_048_576,
      "display_limit" => 16_777_216
    }

    if hook = Process.get({__MODULE__, :before_return}), do: hook.()

    case Process.get({__MODULE__, :mode}) do
      nil ->
        {:ok, observation}

      :eof ->
        {:error, :operator_input_eof}

      :bare_yes ->
        {:ok, %{observation | "text" => "yes", "text_sha256" => Ipse.JSON.sha256("yes")}}

      :trailing_space ->
        text = input <> " "
        {:ok, %{observation | "text" => text, "text_sha256" => Ipse.JSON.sha256(text)}}

      :wrong_display ->
        {:ok, %{observation | "display_sha256" => String.duplicate("0", 64)}}

      :wrong_text_hash ->
        {:ok, %{observation | "text_sha256" => String.duplicate("0", 64)}}

      :extra ->
        {:ok, Map.put(observation, "authority", true)}

      :legacy ->
        {:ok, %{observation | "version" => 1}}
    end
  end

  # This permit-state fixture does not simulate the native guarded display.
  def operator_input(_, _, _, _), do: {:error, :operator_input_unavailable}

  def now do
    case Process.get({__MODULE__, :clock}) do
      nil -> Process.get({__MODULE__, :now}, 1_000)
      clock -> :atomics.get(clock, 1)
    end
  end

  def wall_now, do: Process.get({__MODULE__, :wall_now}, System.system_time(:millisecond))
end

defmodule Ipse.Test.AcceptanceIntent do
  @moduledoc false
  def effect_intent(event, %{"fixture" => true} = request),
    do: {:ok, %{"request" => request, "acceptance_sha256" => Ipse.JSON.digest([event])}}

  def effect_intent(_, _), do: {:error, :fixture_refused}

  def normalized_acceptance?(%{"request" => %{"fixture" => true}}, %{"fixture" => "sealed"}),
    do: true

  def normalized_acceptance?(_, _), do: false
end

# This renamed fixture replaces only native IO and monotonic time. It tests the
# host permit state machine, not terminal provenance; real PTY controls are separate.
source = File.read!(Path.expand("../../../lib/ipse/runner/review.ex", __DIR__))

source =
  String.replace(
    source,
    "def bind_acceptance_request(permit, facts, intent, request, deadline) do",
    "def bind_acceptance_request(permit, facts, intent, request, deadline \\\\ nil) do"
  )

source =
  String.replace(
    source,
    "defmodule Ipse.Runner.Review do",
    "defmodule Ipse.Test.ReviewFixture do"
  )

source =
  String.replace(
    source,
    "Ipse.Session.PendingAcceptance.normalized_acceptance?(",
    "Ipse.Test.AcceptanceIntent.normalized_acceptance?("
  )

source =
  String.replace(
    source,
    ~S'''
        defimpl Inspect do
          def inspect(_, _), do: "#NativeReview<private>"
        end
    ''',
    ""
  )

source =
  String.replace(
    source,
    "alias Ipse.{JSON, Runner, Session.Resources}",
    "alias Ipse.{JSON, Session.Resources}\n  alias Ipse.Test.ReviewRunner, as: Runner"
  )

source =
  String.replace(source, "System.monotonic_time(:millisecond)", "Ipse.Test.ReviewRunner.now()")

source =
  String.replace(
    source,
    "System.system_time(:millisecond)",
    "Ipse.Test.ReviewRunner.wall_now()"
  )

source =
  String.replace(
    source,
    "Ipse.Session.PendingAcceptance.effect_intent(",
    "Ipse.Test.AcceptanceIntent.effect_intent("
  )

Code.compile_string(source, "review-permit-state-fixture.ex")
Code.require_file("../../support/managed_policy.exs", __DIR__)

defmodule Ipse.Runner.ReviewTest do
  use ExUnit.Case, async: false
  alias Ipse.Test.{ReviewFixture, ReviewRunner}
  alias Ipse.Session.Resources

  setup do
    facts = %{"target" => "synthetic", "value" => "café 日本語\e[31m", "choice" => "pin"}
    %{facts: facts}
  end

  test "coordinated review forwards held authority and refuses a rejected display", c do
    coordinator = self()
    ticket = make_ref()
    secret = make_ref()
    guard_ref = make_ref()
    authority = %{sources: ["synthetic"], owners: [0, 1, 2]}
    wall = 123_456

    task =
      Task.async(fn ->
        Resources.file_effect(fn ->
          ReviewFixture.with_coordinated_review(
            "pin",
            c.facts,
            fn _ -> send(coordinator, :unexpected_permit) end,
            fn continuation -> continuation.(wall, authority) end,
            {coordinator, ticket}
          )
        end)
      end)

    assert_receive {:managed_review_input, ^ticket, publisher, _display, _guard}, 5_000
    send(publisher, {:managed_review_guard_authority, ticket, coordinator, secret})
    send(publisher, {:managed_review_guard, ticket, secret, self(), guard_ref})

    assert_receive {:managed_review_deadline, ^ticket, ^publisher, ^guard_ref, ^wall, ^authority},
                   5_000

    send(publisher, {:managed_review_displayed, ticket, self(), guard_ref, {:error, :refused}})

    assert_receive {:managed_review_release, ^ticket, ^publisher, ^guard_ref,
                    {:error, :native_review_refused}},
                   5_000

    send(publisher, {:managed_review_result, ticket, coordinator, {:error, :refused}})
    assert {:error, :native_review_refused} = Task.await(task, 5_000)
    refute_receive :unexpected_permit
  end

  test "invalid production arguments and ordinary JSON cannot construct or consume a permit", c do
    for command <- [nil, "", "Pin", "pin\n", "pin yes", String.duplicate("a", 33)] do
      assert {:error, :native_review_refused} =
               Ipse.Runner.Review.with_review(command, c.facts, fn _ -> flunk("entered") end)
    end

    for facts <- [%{}, nil, %{"x" => self()}, %{"x" => String.duplicate("x", 16_384)}] do
      assert {:error, :native_review_refused} =
               Ipse.Runner.Review.with_review("pin", facts, fn _ -> flunk("entered") end)
    end

    assert {:error, :native_review_refused} = Ipse.Runner.Review.consume(%{}, "pin", c.facts)
    assert {:error, :native_review_refused} = Ipse.Runner.Review.check(%{}, "pin", c.facts)

    assert {:error, :native_review_refused} =
             Ipse.Runner.Review.consumed_receipt(%{}, "pin", c.facts)

    forged = %Ipse.Runner.Review.Permit{owner: self(), ref: make_ref()}
    assert inspect(forged) == "#NativeReview<private>"
    assert {:error, :native_review_refused} = Ipse.Runner.Review.consume(forged, "pin", c.facts)
  end

  test "a consumed acceptance admits only one same-owner effect claim", c do
    facts = Map.put(c.facts, "valid_until_ms", System.system_time(:millisecond) + 60_000)

    assert {:ok, :checked} =
             ReviewFixture.with_review("accept", facts, fn permit ->
               assert {:error, :native_review_refused} =
                        ReviewFixture.claim_acceptance_effect(permit, facts, %{})

               assert {:ok, receipt} = ReviewFixture.consume(permit, "accept", facts)
               intent = acceptance_intent(facts, receipt)

               assert :ok =
                        ReviewFixture.bind_acceptance_request(permit, facts, intent, %{
                          "fixture" => "sealed"
                        })

               assert {:error, :native_review_refused} =
                        ReviewFixture.bind_acceptance_request(permit, facts, intent, %{
                          "fixture" => "sealed"
                        })

               assert {:error, :native_review_refused} =
                        Task.async(fn ->
                          ReviewFixture.claim_acceptance_effect(permit, facts, intent)
                        end)
                        |> Task.await()

               assert {:ok, ^receipt} =
                        ReviewFixture.claim_acceptance_effect(permit, facts, intent)

               assert {:ok, ^receipt} =
                        ReviewFixture.claimed_acceptance_receipt(permit, facts, intent)

               assert {:ok, ^receipt} =
                        ReviewFixture.claimed_acceptance_request(permit, facts, intent, %{
                          "fixture" => "sealed"
                        })

               assert {:error, :native_review_refused} =
                        ReviewFixture.claimed_acceptance_request(permit, facts, intent, %{
                          "fixture" => "changed"
                        })

               assert {:error, :native_review_refused} =
                        ReviewFixture.claimed_acceptance_receipt(
                          permit,
                          facts,
                          Map.put(intent, "extra", true)
                        )

               assert {:error, :native_review_refused} =
                        ReviewFixture.claim_acceptance_effect(permit, facts, intent)

               assert {:error, :native_review_refused} =
                        ReviewFixture.consumed_receipt(permit, "accept", facts)

               {:ok, :checked}
             end)
  end

  test "a changed first effect claim spends the consumed acceptance", c do
    facts = Map.put(c.facts, "valid_until_ms", System.system_time(:millisecond) + 60_000)

    for change <- [:facts, :intent] do
      assert {:error, :native_review_refused} =
               ReviewFixture.with_review("accept", facts, fn permit ->
                 assert {:ok, receipt} = ReviewFixture.consume(permit, "accept", facts)
                 intent = acceptance_intent(facts, receipt)

                 assert :ok =
                          ReviewFixture.bind_acceptance_request(permit, facts, intent, %{
                            "fixture" => "sealed"
                          })

                 changed_facts =
                   if change == :facts, do: Map.put(facts, "target", "other"), else: facts

                 changed_intent =
                   if change == :intent, do: Map.put(intent, "extra", true), else: intent

                 assert {:error, :native_review_refused} =
                          ReviewFixture.claim_acceptance_effect(
                            permit,
                            changed_facts,
                            changed_intent
                          )

                 assert {:error, :native_review_refused} =
                          ReviewFixture.claim_acceptance_effect(permit, facts, intent)

                 {:ok, :refused}
               end)
    end
  end

  test "an unbound acceptance cannot claim an effect", c do
    facts = Map.put(c.facts, "valid_until_ms", System.system_time(:millisecond) + 60_000)

    assert {:error, :native_review_refused} =
             ReviewFixture.with_review("accept", facts, fn permit ->
               assert {:ok, receipt} = ReviewFixture.consume(permit, "accept", facts)
               intent = acceptance_intent(facts, receipt)

               assert {:error, :native_review_refused} =
                        ReviewFixture.claim_acceptance_effect(permit, facts, intent)

               assert {:error, :native_review_refused} =
                        ReviewFixture.bind_acceptance_request(permit, facts, intent, %{
                          "fixture" => "sealed"
                        })

               {:ok, :refused}
             end)
  end

  test "failure after an acceptance effect claim remains unconfirmed", c do
    facts = Map.put(c.facts, "valid_until_ms", System.system_time(:millisecond) + 60_000)

    for callback <- [fn -> {:error, :fixture_failure} end, fn -> raise "fixture interruption" end] do
      assert {:unknown, :native_review_unconfirmed} =
               ReviewFixture.with_review("accept", facts, fn permit ->
                 assert {:ok, receipt} = ReviewFixture.consume(permit, "accept", facts)

                 assert :ok =
                          ReviewFixture.bind_acceptance_request(
                            permit,
                            facts,
                            acceptance_intent(facts, receipt),
                            %{"fixture" => "sealed"}
                          )

                 assert {:ok, _} =
                          ReviewFixture.claim_acceptance_effect(
                            permit,
                            facts,
                            acceptance_intent(facts, receipt)
                          )

                 callback.()
               end)
    end
  end

  test "an expired acceptance cannot claim an effect", c do
    facts = Map.put(c.facts, "valid_until_ms", System.system_time(:millisecond))

    assert {:error, :native_review_refused} =
             ReviewFixture.with_review("accept", facts, fn permit ->
               assert {:ok, receipt} = ReviewFixture.consume(permit, "accept", facts)

               assert {:error, :native_review_refused} =
                        ReviewFixture.claim_acceptance_effect(
                          permit,
                          facts,
                          acceptance_intent(facts, receipt)
                        )

               {:ok, :refused}
             end)
  end

  test "a claimed acceptance stops being inspectable when its candidate expires", c do
    now = System.system_time(:millisecond)
    facts = Map.put(c.facts, "valid_until_ms", now + 1_000)
    Process.put({ReviewRunner, :wall_now}, now)

    assert {:ok, :checked} =
             ReviewFixture.with_review("accept", facts, fn permit ->
               assert {:ok, receipt} = ReviewFixture.consume(permit, "accept", facts)
               intent = acceptance_intent(facts, receipt)

               assert :ok =
                        ReviewFixture.bind_acceptance_request(permit, facts, intent, %{
                          "fixture" => "sealed"
                        })

               assert {:ok, ^receipt} =
                        ReviewFixture.claim_acceptance_effect(permit, facts, intent)

               assert {:ok, ^receipt} =
                        ReviewFixture.claimed_acceptance_receipt(permit, facts, intent)

               Process.put({ReviewRunner, :wall_now}, facts["valid_until_ms"])

               assert {:error, :native_review_refused} =
                        ReviewFixture.claimed_acceptance_receipt(permit, facts, intent)

               {:ok, :checked}
             end)
  end

  test "a claimed acceptance stops being inspectable at the earlier retention deadline", c do
    now = System.system_time(:millisecond)
    facts = Map.put(c.facts, "valid_until_ms", now + 2_000)
    Process.put({ReviewRunner, :wall_now}, now)

    assert {:ok, :checked} =
             ReviewFixture.with_review("accept", facts, fn permit ->
               assert {:ok, receipt} = ReviewFixture.consume(permit, "accept", facts)
               intent = acceptance_intent(facts, receipt)

               assert :ok =
                        ReviewFixture.bind_acceptance_request(
                          permit,
                          facts,
                          intent,
                          %{"fixture" => "sealed"},
                          now + 1_000
                        )

               assert {:ok, ^receipt} =
                        ReviewFixture.claim_acceptance_effect(permit, facts, intent)

               Process.put({ReviewRunner, :wall_now}, now + 1_000)

               assert {:error, :native_review_refused} =
                        ReviewFixture.claimed_acceptance_request(permit, facts, intent, %{
                          "fixture" => "sealed"
                        })

               {:ok, :checked}
             end)
  end

  test "an acceptance cannot be claimed after the earlier retention deadline", c do
    now = System.system_time(:millisecond)
    facts = Map.put(c.facts, "valid_until_ms", now + 2_000)
    Process.put({ReviewRunner, :wall_now}, now)

    assert {:error, :native_review_refused} =
             ReviewFixture.with_review("accept", facts, fn permit ->
               assert {:ok, receipt} = ReviewFixture.consume(permit, "accept", facts)
               intent = acceptance_intent(facts, receipt)

               assert :ok =
                        ReviewFixture.bind_acceptance_request(
                          permit,
                          facts,
                          intent,
                          %{"fixture" => "sealed"},
                          now + 1_000
                        )

               Process.put({ReviewRunner, :wall_now}, now + 1_000)

               assert {:error, :native_review_refused} =
                        ReviewFixture.claim_acceptance_effect(permit, facts, intent)

               {:ok, :refused}
             end)
  end

  defp acceptance_intent(facts, receipt) do
    event = %{
      "type" => "pending_proposal_accepted",
      "version" => 1,
      "facts" => facts,
      "review" => receipt
    }

    {:ok, intent} = Ipse.Test.AcceptanceIntent.effect_intent(event, %{"fixture" => true})
    intent
  end

  test "a matching simulated observation binds full escaped facts and can be consumed only once",
       c do
    assert {:ok, receipt} =
             ReviewFixture.with_review("pin", c.facts, fn permit ->
               assert :ok = ReviewFixture.check(permit, "pin", c.facts)
               assert :ok = ReviewFixture.check(permit, "pin", c.facts)
               assert {:ok, preview} = ReviewFixture.preview_receipt(permit, "pin", c.facts)

               assert {:error, :native_review_refused} =
                        ReviewFixture.preview_receipt(
                          permit,
                          "pin",
                          Map.put(c.facts, "changed", true)
                        )

               assert {:error, :native_review_refused} =
                        ReviewFixture.consumed_receipt(permit, "pin", c.facts)

               assert {:ok, receipt} = ReviewFixture.consume(permit, "pin", c.facts)
               assert receipt === preview

               assert {:ok, ^receipt} =
                        ReviewFixture.consumed_receipt(permit, "pin", c.facts)

               assert {:error, :native_review_refused} =
                        ReviewFixture.check(permit, "pin", c.facts)

               assert {:error, :native_review_refused} =
                        ReviewFixture.consume(permit, "pin", c.facts)

               assert receipt["kind"] == "native_review"
               assert receipt["facts_sha256"] == Ipse.JSON.digest([c.facts])
               assert receipt["input_sha256"] == Ipse.JSON.sha256("pin " <> receipt["challenge"])

               assert receipt["display_sha256"] ==
                        Ipse.JSON.sha256(Process.get({ReviewRunner, :display}))

               assert Ipse.JSON.safe_uint?(receipt["observed_at_ms"])
               {:ok, receipt}
             end)

    assert receipt["command"] == "pin"
    display = Process.get({ReviewRunner, :display})
    refute display =~ <<27>>
    assert display =~ "日本語"
    assert String.downcase(display) =~ "\\u001b"
    assert Process.get({ReviewRunner, :calls}) == 1
    assert Process.get({ReviewFixture, :permit}) == nil
  end

  test "a consumed retention review binds one effect and a finite native deadline" do
    wall = System.system_time(:millisecond)
    Process.put({ReviewRunner, :wall_now}, wall)
    operation = String.duplicate("1", 32)

    request = %{
      "op" => "commit",
      "expected_generation" => 1,
      "advance_floor" => true,
      "changes" => [
        %{
          "key" => "note." <> String.duplicate("a", 64),
          "expected_revision" => 1,
          "value" => %{"text" => "synthetic"}
        }
      ]
    }

    normalized =
      Map.update!(
        request,
        "changes",
        &(&1 ++
            [
              %{
                "key" => "host.validity.synthetic",
                "expected_revision" => 0,
                "value" => %{"v" => 1}
              }
            ])
      )

    body = %{
      "kind" => "managed_literal_retention",
      "operation_id" => operation,
      "policy" => %{"kind" => "pin"},
      "metadata" => %{
        "lineage" => String.duplicate("a", 64),
        "first_admitted_ms" => wall - 1,
        "valid_until_ms" => nil
      },
      "target" => %{
        "key" => hd(request["changes"])["key"],
        "revision" => 1,
        "value" => hd(request["changes"])["value"]
      },
      "old_deadline_ms" => nil,
      "request_sha256" => Ipse.JSON.digest([request])
    }

    facts = Map.put(body, "action_sha256", Ipse.JSON.digest([body]))

    intent = %{
      "type" => "managed_lifecycle_intent",
      "version" => 1,
      "operation_id" => operation,
      "facts" => facts
    }

    assert {:ok, :bound} =
             ReviewFixture.with_review("pin", facts, fn permit ->
               assert {:ok, review} = ReviewFixture.consume(permit, "pin", facts)

               receipt = %{
                 "version" => 3,
                 "kind" => "native_literal_retention",
                 "policy" => facts["policy"],
                 "record_key" => facts["target"]["key"],
                 "lineage" => facts["metadata"]["lineage"],
                 "category" => "pin",
                 "first_admitted_ms" => facts["metadata"]["first_admitted_ms"],
                 "action_sha256" => facts["action_sha256"],
                 "native_review_sha256" => Ipse.JSON.digest([review]),
                 "valid_until_ms" => nil,
                 "publish_before_ms" => nil
               }

               assert {:ok, bound} =
                        ReviewFixture.claim_retention_effect(
                          permit,
                          facts,
                          intent,
                          request,
                          normalized,
                          receipt
                        )

               assert bound.review === review
               assert bound.publish_before_ms > wall and bound.publish_before_ms <= wall + 30_000

               assert {:ok, ^review} =
                        ReviewFixture.claimed_retention_receipt(permit, "pin", facts)

               assert {:ok, ^bound} =
                        ReviewFixture.claimed_retention_effect(
                          permit,
                          facts,
                          intent,
                          request,
                          normalized,
                          receipt
                        )

               assert {:error, :native_review_refused} =
                        ReviewFixture.claim_retention_effect(
                          permit,
                          facts,
                          intent,
                          request,
                          normalized,
                          receipt
                        )

               assert {:error, :native_review_refused} =
                        ReviewFixture.claimed_retention_effect(
                          permit,
                          facts,
                          intent,
                          request,
                          Map.put(normalized, "expected_generation", 2),
                          receipt
                        )

               Process.put({ReviewRunner, :wall_now}, bound.publish_before_ms)

               assert {:error, :native_review_refused} =
                        ReviewFixture.claimed_retention_receipt(permit, "pin", facts)

               assert {:error, :native_review_refused} =
                        ReviewFixture.claimed_retention_effect(
                          permit,
                          facts,
                          intent,
                          request,
                          normalized,
                          receipt
                        )

               Process.put({ReviewRunner, :wall_now}, wall)
               {:ok, :bound}
             end)

    assert {:error, :native_review_refused} =
             ReviewFixture.with_review("pin", facts, fn permit ->
               assert {:ok, review} = ReviewFixture.consume(permit, "pin", facts)

               receipt = %{
                 "version" => 3,
                 "kind" => "native_literal_retention",
                 "policy" => facts["policy"],
                 "record_key" => facts["target"]["key"],
                 "lineage" => facts["metadata"]["lineage"],
                 "category" => "pin",
                 "first_admitted_ms" => facts["metadata"]["first_admitted_ms"],
                 "action_sha256" => facts["action_sha256"],
                 "native_review_sha256" => Ipse.JSON.digest([review]),
                 "valid_until_ms" => nil,
                 "publish_before_ms" => nil
               }

               forged = put_in(normalized, ["changes", Access.at(1), "key"], "other.record")

               assert {:error, :native_review_refused} =
                        ReviewFixture.claim_retention_effect(
                          permit,
                          facts,
                          intent,
                          request,
                          forged,
                          receipt
                        )

               assert {:error, :native_review_refused} =
                        ReviewFixture.claim_retention_effect(
                          permit,
                          facts,
                          intent,
                          request,
                          normalized,
                          receipt
                        )

               {:error, :refused}
             end)
  end

  test "a consumed relation review binds its effect once and expires without renewal" do
    alias Ipse.Test.ManagedPolicy, as: F
    wall = System.system_time(:millisecond)
    Process.put({ReviewRunner, :wall_now}, wall)

    recipe =
      F.policy()["settings"]["recipes"]
      |> Map.values()
      |> Enum.find(&(&1["kind"] == "literal_source"))

    request = %{"op" => "commit", "expected_generation" => 7}
    normalized = Map.put(request, "changes", [%{"key" => "synthetic replacement"}])
    old = F.proof("native_operator_assertion", "old synthetic fact")
    new = F.proof("native_operator_assertion", "new synthetic fact")

    context =
      Map.new(~w(project_id namespace binding_sha256 management_sha256), &{&1, F.hash(&1)})
      |> Map.merge(%{
        "session_id" => Ipse.Usage.id(),
        "job_id" => Ipse.Usage.id(),
        "client_id" => Ipse.Usage.id(),
        "management_epoch" => 1,
        "original_pin" => nil,
        "recipe" => recipe
      })

    for {mode, command, category, deadline} <- [
          {"ordinary", "correct", "ordinary", wall + 20_000},
          {"temporal", "supersede", "current", nil}
        ] do
      Process.put({ReviewRunner, :wall_now}, wall)

      metadata = %{
        "category" => category,
        "first_admitted_ms" => wall - 1,
        "valid_until_ms" => deadline
      }

      body = %{
        "kind" => "managed_literal_supersession",
        "mode" => mode,
        "context" => context,
        "checked_at_ms" => wall,
        "metadata" => metadata,
        "history_rule" => Ipse.Extension.Collection.ManagedRetention.history_rule(metadata, mode),
        "target" => %{"value" => %{"evidence" => %{"sources" => [old]}}},
        "replacement" => %{"value" => %{"evidence" => %{"sources" => [new]}}},
        "new_source_sha256" => Ipse.JSON.digest([[new]]),
        "request_sha256" => Ipse.JSON.digest([request])
      }

      facts = Map.put(body, "action_sha256", Ipse.JSON.digest([body]))
      intent = %{"facts" => facts, "type" => "synthetic relation intent"}

      assert {:ok, :checked} =
               ReviewFixture.with_review(command, facts, fn permit ->
                 assert {:ok, review} = ReviewFixture.consume(permit, command, facts)

                 receipt = %{
                   "kind" => "native_literal_supersession",
                   "version" => 3,
                   "action_sha256" => facts["action_sha256"],
                   "native_review_sha256" => Ipse.JSON.digest([review]),
                   "publish_before_ms" => wall + 10_000
                 }

                 assert {:ok, bound} =
                          ReviewFixture.claim_supersession_effect(
                            permit,
                            facts,
                            intent,
                            request,
                            normalized,
                            receipt
                          )

                 assert bound.publish_before_ms == wall + 10_000

                 assert {:ok, ^bound} =
                          ReviewFixture.claimed_supersession_effect(
                            permit,
                            facts,
                            intent,
                            request,
                            normalized,
                            receipt
                          )

                 assert {:error, :native_review_refused} =
                          ReviewFixture.claim_supersession_effect(
                            permit,
                            facts,
                            intent,
                            request,
                            normalized,
                            receipt
                          )

                 for {i, r, n, s} <- [
                       {Map.put(intent, "changed", true), request, normalized, receipt},
                       {intent, Map.put(request, "expected_generation", 8), normalized, receipt},
                       {intent, request, Map.put(normalized, "changed", true), receipt},
                       {intent, request, normalized,
                        Map.put(receipt, "publish_before_ms", wall + 11_000)}
                     ] do
                   assert {:error, :native_review_refused} =
                            ReviewFixture.claimed_supersession_effect(permit, facts, i, r, n, s)
                 end

                 assert {:ok, ^review} =
                          ReviewFixture.claimed_supersession_receipt(permit, command, facts)

                 Process.put({ReviewRunner, :wall_now}, bound.publish_before_ms)

                 assert {:error, :native_review_refused} =
                          ReviewFixture.claimed_supersession_receipt(permit, command, facts)

                 assert {:error, :native_review_refused} =
                          ReviewFixture.claimed_supersession_effect(
                            permit,
                            facts,
                            intent,
                            request,
                            normalized,
                            receipt
                          )

                 Process.put({ReviewRunner, :wall_now}, wall)
                 {:ok, :checked}
               end)
    end
  end

  test "changed command or exact facts spends the permit without a silent rebase", c do
    for {command, facts} <- [{"forget", c.facts}, {"pin", Map.put(c.facts, "new", true)}] do
      assert {:error, :native_review_refused} =
               ReviewFixture.with_review("pin", c.facts, fn permit ->
                 assert {:error, :native_review_refused} =
                          ReviewFixture.consume(permit, command, facts)

                 assert {:error, :native_review_refused} =
                          ReviewFixture.consume(permit, "pin", c.facts)

                 :ignored
               end)
    end
  end

  test "foreign process and forged ref do not spend the actual owner's permit", c do
    assert :ok =
             ReviewFixture.with_review("pin", c.facts, fn permit ->
               assert {:error, :native_review_refused} =
                        Task.async(fn -> ReviewFixture.check(permit, "pin", c.facts) end)
                        |> Task.await()

               assert {:error, :native_review_refused} =
                        Task.async(fn -> ReviewFixture.consume(permit, "pin", c.facts) end)
                        |> Task.await()

               forged = %{permit | ref: make_ref()}

               assert {:error, :native_review_refused} =
                        ReviewFixture.consume(forged, "pin", c.facts)

               assert {:ok, _} = ReviewFixture.consume(permit, "pin", c.facts)
               :ok
             end)
  end

  test "scope exit, callback exceptions and missing consumption cannot create success", c do
    for callback <- [fn _ -> :ok end, fn _ -> raise "synthetic before consumption" end] do
      assert {:error, :native_review_refused} =
               ReviewFixture.with_review("pin", c.facts, callback)

      assert Process.get({ReviewFixture, :permit}) == nil
    end

    assert {:error, :stale_target} =
             ReviewFixture.with_review("pin", c.facts, fn _ -> {:error, :stale_target} end)

    assert {:unknown, :native_review_unconfirmed} =
             ReviewFixture.with_review("pin", c.facts, fn permit ->
               assert {:ok, _} = ReviewFixture.consume(permit, "pin", c.facts)
               raise "synthetic effect may have happened"
             end)

    for returned <- [{:error, :synthetic_after_effect}, {:conflict, %{}}, :unexpected] do
      assert {:unknown, :native_review_unconfirmed} =
               ReviewFixture.with_review("pin", c.facts, fn permit ->
                 assert {:ok, _} = ReviewFixture.consume(permit, "pin", c.facts)
                 returned
               end)
    end

    parent = self()

    assert :ok =
             ReviewFixture.with_review("pin", c.facts, fn permit ->
               send(parent, {:spent_permit, permit})
               assert {:ok, _} = ReviewFixture.consume(permit, "pin", c.facts)
               :ok
             end)

    assert_receive {:spent_permit, permit}
    assert {:error, :native_review_refused} = ReviewFixture.consume(permit, "pin", c.facts)
    assert Process.get({ReviewFixture, :permit}) == nil
  end

  test "bare yes, whitespace, mismatched hashes and failed native restoration never enter callback",
       c do
    for mode <- [
          :bare_yes,
          :trailing_space,
          :wrong_display,
          :wrong_text_hash,
          :extra,
          :legacy,
          :eof
        ] do
      Process.put({ReviewRunner, :mode}, mode)

      assert {:error, :native_review_refused} =
               ReviewFixture.with_review("pin", c.facts, fn _ -> flunk("entered") end)
    end
  end

  test "the exact deadline refuses consumption and post-consumption expiry withholds success",
       c do
    assert {:error, :native_review_refused} =
             ReviewFixture.with_review("pin", c.facts, fn permit ->
               Process.put({ReviewRunner, :now}, 31_000)

               assert {:error, :native_review_refused} =
                        ReviewFixture.consume(permit, "pin", c.facts)

               :ignored
             end)

    Process.put({ReviewRunner, :now}, 1_000)

    assert {:unknown, :native_review_unconfirmed} =
             ReviewFixture.with_review("pin", c.facts, fn permit ->
               assert {:ok, _} = ReviewFixture.consume(permit, "pin", c.facts)
               Process.put({ReviewRunner, :now}, 31_000)
               :ok
             end)
  end

  test "closed and unrelated resource scopes cannot consume or finish a review", c do
    {:ok, scope} = Resources.start(self())
    previous = Resources.bind(scope)

    try do
      assert Resources.active?()

      assert {:error, :native_review_refused} =
               ReviewFixture.with_review("pin", c.facts, fn permit ->
                 assert :ok = Resources.finish(scope)
                 refute Resources.active?()

                 assert {:error, :native_review_refused} =
                          ReviewFixture.consume(permit, "pin", c.facts)

                 :ignored
               end)

      assert {:error, :native_review_refused} =
               ReviewFixture.with_review("pin", c.facts, fn _ -> flunk("entered") end)
    after
      Resources.bind(previous)
      if Process.alive?(scope), do: Resources.close(scope)
    end
  end

  test "resource activity admits only actual owner, tracked task and effect, then refuses after finish" do
    {:ok, scope} = Resources.start(self())
    previous = Resources.bind(scope)

    try do
      assert Resources.active?()
      assert Resources.active?(1_000)
      for timeout <- [0, -1, 5_001, 1.0, nil], do: refute(Resources.active?(timeout))

      refute Task.async(fn ->
               Resources.bind(scope)
               Resources.active?()
             end)
             |> Task.await()

      assert Resources.async(fn -> Resources.active?() end) |> Task.await()
      assert Resources.file_effect(fn -> Resources.active?() end)
      assert :ok = Resources.finish(scope)
      refute Resources.active?()
    after
      Resources.bind(previous)
      if Process.alive?(scope), do: Resources.close(scope)
    end
  end

  test "a complete maximum-size facts object is shown and the next byte refuses before native IO" do
    facts = %{"x" => String.duplicate("x", 8_192), "y" => String.duplicate("y", 8_177)}
    assert byte_size(Jason.encode!(facts)) == 16_384

    assert :ok =
             ReviewFixture.with_review("pin", facts, fn permit ->
               assert {:ok, _} = ReviewFixture.consume(permit, "pin", facts)
               :ok
             end)

    assert Process.get({ReviewRunner, :calls}) == 1

    assert {:error, :native_review_refused} =
             ReviewFixture.with_review("pin", %{facts | "y" => facts["y"] <> "y"}, fn _ ->
               flunk("entered")
             end)

    assert Process.get({ReviewRunner, :calls}) == 1
  end

  test "nested review cannot replace a pending permit", c do
    assert :ok =
             ReviewFixture.with_review("pin", c.facts, fn permit ->
               assert {:error, :native_review_refused} =
                        ReviewFixture.with_review("forget", c.facts, fn _ -> flunk("nested") end)

               assert {:ok, _} = ReviewFixture.consume(permit, "pin", c.facts)
               :ok
             end)

    assert Process.get({ReviewRunner, :calls}) == 1
  end

  test "upstream death refuses consumption and finished scope withholds a consumed result", c do
    upstream =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    monitor = Process.monitor(upstream)
    owner_key = {Resources, :effect_owner}
    previous = Process.get(owner_key)
    :ok = Resources.bind_effect_owner(upstream)

    try do
      assert {:error, :native_review_refused} =
               ReviewFixture.with_review("pin", c.facts, fn permit ->
                 send(upstream, :stop)
                 assert_receive {:DOWN, ^monitor, :process, ^upstream, :normal}

                 assert {:error, :native_review_refused} =
                          ReviewFixture.consume(permit, "pin", c.facts)

                 :ignored
               end)
    after
      if is_nil(previous), do: Process.delete(owner_key), else: Process.put(owner_key, previous)
      if Process.alive?(upstream), do: Process.exit(upstream, :kill)
      Process.demonitor(monitor, [:flush])
    end

    {:ok, scope} = Resources.start(self())
    previous_scope = Resources.bind(scope)

    try do
      assert {:unknown, :native_review_unconfirmed} =
               ReviewFixture.with_review("pin", c.facts, fn permit ->
                 assert {:ok, _} = ReviewFixture.consume(permit, "pin", c.facts)
                 :ok = Resources.finish(scope)
                 :ok
               end)
    after
      Resources.bind(previous_scope)
      if Process.alive?(scope), do: Resources.close(scope)
    end
  end

  test "the observation lifetime cannot restart after the post-input resource query", c do
    {:ok, scope} = Resources.start(self())
    previous = Resources.bind(scope)
    clock = :atomics.new(1, [])
    :atomics.put(clock, 1, 1_000)
    Process.put({ReviewRunner, :clock}, clock)
    caller = self()

    Process.put({ReviewRunner, :before_return}, fn ->
      :ok = :sys.suspend(scope)

      watcher =
        Task.async(fn ->
          try do
            wait_for_active(scope, caller, System.monotonic_time(:millisecond) + 3_000)
            :atomics.put(clock, 1, 31_000)
          after
            :sys.resume(scope)
          end
        end)

      Process.put({ReviewRunner, :entry_watcher}, watcher)
    end)

    try do
      assert {:error, :native_review_refused} =
               ReviewFixture.with_review("pin", c.facts, fn _ ->
                 flunk("expired observation entered callback")
               end)

      Task.await(Process.get({ReviewRunner, :entry_watcher}))
    after
      Process.delete({ReviewRunner, :before_return})
      Resources.bind(previous)
      if Process.alive?(scope), do: Resources.close(scope)
    end
  end

  test "deadline and upstream are rechecked after a real blocking scope query", c do
    for phase <- [:consume, :finish], loss <- [:deadline, :upstream] do
      {:ok, scope} = Resources.start(self())
      previous_scope = Resources.bind(scope)

      upstream =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      owner_key = {Resources, :effect_owner}
      previous_owner = Process.get(owner_key)
      :ok = Resources.bind_effect_owner(upstream)
      clock = :atomics.new(1, [])
      :atomics.put(clock, 1, 1_000)
      Process.put({ReviewRunner, :clock}, clock)

      try do
        result =
          ReviewFixture.with_review("pin", c.facts, fn permit ->
            if phase == :finish,
              do: assert({:ok, _} = ReviewFixture.consume(permit, "pin", c.facts))

            caller = self()
            :ok = :sys.suspend(scope)

            watcher =
              Task.async(fn ->
                try do
                  wait_for_active(scope, caller, System.monotonic_time(:millisecond) + 3_000)

                  if loss == :deadline do
                    :atomics.put(clock, 1, 31_000)
                  else
                    monitor = Process.monitor(upstream)
                    send(upstream, :stop)

                    receive do
                      {:DOWN, ^monitor, :process, ^upstream, :normal} -> :ok
                    after
                      1_000 -> flunk("upstream did not stop")
                    end
                  end
                after
                  :sys.resume(scope)
                end
              end)

            Process.put(:native_review_watcher, watcher)

            if phase == :consume do
              assert {:error, :native_review_refused} =
                       ReviewFixture.consume(permit, "pin", c.facts)

              :ignored
            else
              :ok
            end
          end)

        expected =
          if phase == :consume,
            do: {:error, :native_review_refused},
            else: {:unknown, :native_review_unconfirmed}

        assert result == expected
        assert :ok = Task.await(Process.delete(:native_review_watcher), 5_000)
      after
        Process.delete({ReviewRunner, :clock})
        Resources.bind(previous_scope)

        if is_nil(previous_owner),
          do: Process.delete(owner_key),
          else: Process.put(owner_key, previous_owner)

        if Process.alive?(upstream), do: Process.exit(upstream, :kill)
        if Process.alive?(scope), do: Resources.close(scope)
      end
    end
  end

  defp wait_for_active(scope, caller, deadline) do
    {:messages, messages} = Process.info(scope, :messages)

    if Enum.any?(messages, &match?({:"$gen_call", {^caller, _}, :active}, &1)) do
      :ok
    else
      assert System.monotonic_time(:millisecond) < deadline, "resource query was not queued"
      Process.sleep(1)
      wait_for_active(scope, caller, deadline)
    end
  end
end
