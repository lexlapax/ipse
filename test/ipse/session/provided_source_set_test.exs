defmodule Ipse.Session.ProvidedSourceSetTest do
  use ExUnit.Case, async: true
  alias Ipse.JSON
  alias Ipse.Session.ProvidedSourceSet, as: Set

  @selected 1_000

  defp source(id, overrides \\ %{}) do
    Map.merge(
      %{
        "source_id" => id,
        "generation" => 1,
        "title" => "Release",
        "text" => "Release requires quiescence for " <> id <> ".",
        "uri" => "local:" <> id,
        "observed_at_ms" => 500,
        "event_at_ms" => nil,
        "expires_at_ms" => nil
      },
      overrides
    )
  end

  defp parent(sources, extra \\ %{}) do
    id = String.duplicate("a", 32)

    args =
      Map.merge(
        %{
          "search" => "given",
          "fetch" => "given",
          "retrieval" => "words",
          "rerank" => "judge",
          "query" => "quiescence",
          "limits" => %{"max_sources" => 10, "max_body_bytes" => 65_536, "timeout_ms" => 5000},
          "sources" => sources
        },
        extra
      )

    %{
      "type" => "extension_invocation_intent",
      "version" => 1,
      "invocation_id" => id,
      "identity" => %{
        "instance" => "research",
        "artifact_sha256" => String.duplicate("1", 64),
        "options_sha256" => String.duplicate("2", 64)
      },
      "descriptor" => %{
        "id" => "investigate_provided",
        "stage" => "invoke.command",
        "name" => "ext__research__investigate_provided",
        "source_contract" => Set.contract()
      },
      "payload" => %{
        "api_version" => 1,
        "invocation_id" => id,
        "session_id" => String.duplicate("b", 32),
        "turn_id" => String.duplicate("c", 32),
        "id" => "investigate_provided",
        "arguments" => args
      }
    }
  end

  defp sha(parent, selected \\ @selected) do
    {:ok, set} = Set.capture(parent, selected)
    Set.digest(set)
  end

  test "every bound source field, set member and invocation fact changes the digest" do
    base = parent([source("one"), source("two")])
    original = sha(base)

    variants =
      for {key, value} <- [
            {"source_id", "forged"},
            {"generation", 2},
            {"text", "Different body."},
            {"observed_at_ms", 501},
            {"expires_at_ms", 9_000}
          ] do
        put_in(base, ["payload", "arguments", "sources"], [
          Map.put(source("one"), key, value),
          source("two")
        ])
      end

    variants =
      variants ++
        [
          put_in(base, ["payload", "arguments", "sources"], [source("one")]),
          put_in(base, ["payload", "arguments", "sources"], [
            source("one"),
            source("two"),
            source("three")
          ]),
          put_in(base, ["payload", "arguments", "sources"], [source("two"), source("one")]),
          put_in(base, ["payload", "arguments", "query"], "release"),
          put_in(base, ["payload", "arguments", "as_of_ms"], @selected),
          put_in(base, ["identity", "artifact_sha256"], String.duplicate("3", 64)),
          put_in(base, ["identity", "options_sha256"], String.duplicate("4", 64)),
          put_in(base, ["payload", "arguments", "rerank"], nil)
        ]

    digests = Enum.map(variants, &sha/1)
    refute original in digests
    assert length(Enum.uniq(digests)) == length(digests)
    refute sha(base, @selected + 1) == original

    other = String.duplicate("d", 32)

    moved =
      base
      |> Map.put("invocation_id", other)
      |> put_in(["payload", "invocation_id"], other)

    refute sha(moved) == original
  end

  test "only the closed non-empty provided shape on a contract command is captured" do
    good = parent([source("one")])
    assert {:ok, set} = Set.capture(good, @selected)

    assert [%{"origin" => "provided", "partition" => "research-provided", "position" => 0}] =
             set["sources"]

    assert set["sources"] |> hd() |> Map.fetch!("body_sha256") ==
             JSON.sha256(source("one")["text"])

    refute Map.has_key?(hd(set["sources"]), "text")

    for bad <- [
          put_in(good, ["payload", "arguments", "sources"], []),
          put_in(good, ["payload", "arguments", "sources"], List.duplicate(source("x"), 11)),
          put_in(good, ["payload", "arguments", "sources"], [Map.put(source("x"), "extra", 1)]),
          put_in(good, ["payload", "arguments", "sources"], [Map.delete(source("x"), "uri")]),
          put_in(good, ["payload", "arguments", "sources"], [
            Map.put(source("x"), "generation", 0)
          ]),
          put_in(good, ["payload", "arguments", "as_of_ms"], nil),
          put_in(good, ["payload", "arguments", "store"], "notes"),
          put_in(good, ["descriptor", "stage"], "invoke.tool"),
          put_in(good, ["descriptor", "source_contract"], %{
            "version" => 2,
            "kind" => "provided_set"
          }),
          update_in(good, ["descriptor"], &Map.delete(&1, "source_contract"))
        ] do
      assert Set.capture(bad, @selected) == :error
    end

    assert Set.capture(good, -1) == :error
  end

  test "the earliest eligibility transition covers every captured source" do
    {:ok, set} =
      Set.capture(
        parent([
          source("eligible"),
          source("expiring", %{"expires_at_ms" => 4_000}),
          source("future", %{"observed_at_ms" => 3_000}),
          source("never", %{"observed_at_ms" => 2_000, "expires_at_ms" => 2_000}),
          source("expired", %{"expires_at_ms" => 900})
        ]),
        @selected
      )

    assert Set.transition(set) == 3_000

    {:ok, stable} = Set.capture(parent([source("eligible")]), @selected)
    assert Set.transition(stable) == nil

    {:ok, explicit} =
      Set.capture(
        parent([source("future", %{"observed_at_ms" => 3_000})], %{"as_of_ms" => 2_000}),
        @selected
      )

    assert explicit["as_of_ms"] == 2_000 and Set.transition(explicit) == nil
  end

  test "clock checks require the high-water and stop strictly before the transition" do
    good = parent([source("one", %{"expires_at_ms" => 2_000})])
    {:ok, event, fence} = Set.begin(good, @selected)
    assert event["transition_ms"] == 2_000 and fence.high_water == @selected
    assert Set.current_at?(event, @selected, @selected)
    assert Set.current_at?(event, @selected, 1_999)
    refute Set.current_at?(event, @selected, 2_000)
    refute Set.current_at?(event, @selected, @selected - 1)
    refute Set.current_at?(event, 1_500, 1_499)

    s = %{invocation: %{parent: good, provided_set: fence}}
    assert {:ok, s} = Set.check(s, 1_500)
    assert s.invocation.provided_set.high_water == 1_500
    assert Set.check(s, 1_499) == :error
    assert Set.check(s, 2_000) == :error
    assert {:ok, _} = Set.check(s, 1_500)

    forged = put_in(s, [:invocation, :parent, "payload", "arguments", "sources"], [source("two")])
    assert Set.check(forged, 1_600) == :error
    unfenced = %{invocation: %{parent: good, provided_set: nil}}
    assert {:ok, ^unfenced} = Set.check(unfenced, 0)
    assert {:ok, ^unfenced} = Set.guard(unfenced, "embedding.create")
    assert Set.guard(s, "embedding.create") == :error
    # The wall clock is long past this fixture's 2,000 ms transition.
    assert Set.guard(s, "model.complete") == :error
    stable = parent([source("one")])
    {:ok, _, fence} = Set.begin(stable, @selected)

    assert {:ok, _} =
             Set.guard(%{invocation: %{parent: stable, provided_set: fence}}, "model.complete")
  end

  test "intent and release records re-derive their set and bind the delivered result" do
    good = parent([source("one", %{"expires_at_ms" => 2_000})])
    {:ok, event, _} = Set.begin(good, @selected)
    assert Set.valid_intent?(event, good)
    refute Set.valid_intent?(Map.put(event, "set_sha256", String.duplicate("0", 64)), good)
    refute Set.valid_intent?(Map.put(event, "selected_at_ms", @selected + 1), good)
    refute Set.valid_intent?(Map.put(event, "source_count", 2), good)

    other = put_in(good, ["payload", "arguments", "sources"], [source("two")])
    refute Set.valid_intent?(event, other)

    result = %{"type" => "extension_invocation_result", "invocation_id" => good["invocation_id"]}
    current = Set.release(event, "current", 1_999, result)
    assert Set.valid_release?(current, event)
    refute Set.valid_release?(%{current | "checked_at_ms" => 2_000}, event)
    refute Set.valid_release?(%{current | "checked_at_ms" => @selected - 1}, event)
    refute Set.valid_release?(%{current | "result_sha256" => nil}, event)
    withheld = Set.release(event, "withheld", 2_500, nil)
    assert Set.valid_release?(withheld, event)
    refute Set.valid_release?(%{withheld | "result_sha256" => current["result_sha256"]}, event)
  end

  test "journal order requires an adjacent intent, model-only actions and a bound inline result" do
    good = parent([source("one")])
    {:ok, event, _} = Set.begin(good, @selected)

    result =
      Map.merge(good, %{
        "type" => "extension_invocation_result",
        "version" => 1,
        "value" => %{"coverage" => %{"as_of_ms" => @selected + 2}}
      })

    release = Set.release(event, "current", @selected + 5, result)

    model = %{
      "type" => "extension_action_intent",
      "parent_invocation_id" => good["invocation_id"]
    }

    feed = %{"type" => "extension_feed_delivery_intent", "sequence" => 1}

    complete = [
      good,
      event,
      Map.put(model, "request", %{"op" => "model.complete"}),
      release,
      result
    ]

    assert Set.validate_events(complete) == :ok
    assert Set.validate_events([good, feed, event | Enum.drop(complete, 2)]) == :ok

    assert Set.validate_events([good, event]) == :ok
    assert Set.validate_events([good, event, Set.release(event, "withheld", 2_000, nil)]) == :ok

    # A contract intent without its set intent was interrupted before the worker
    # started: restore accepts it, and a later invocation may follow.
    other = parent([source("two")]) |> Map.put("invocation_id", String.duplicate("e", 32))
    other = put_in(other, ["payload", "invocation_id"], other["invocation_id"])
    {:ok, other_event, _} = Set.begin(other, @selected)
    assert Set.validate_events([good]) == :ok
    assert Set.validate_events([good, feed, %{"type" => "message"}]) == :ok
    assert Set.validate_events([good, other, other_event]) == :ok

    stale = fn value ->
      stale = %{result | "value" => value}
      [good, event, Set.release(event, "current", @selected + 5, stale), stale]
    end

    for bad <- [
          [event],
          [good, Map.put(event, "set_sha256", String.duplicate("0", 64))],
          [good, Map.put(model, "request", %{"op" => "model.complete"})],
          [good, feed, release],
          [good, result],
          [good, other, event],
          [good, other, other_event, Map.put(model, "request", %{"op" => "model.complete"})],
          [good, other, other_event, result],
          [good, event, Map.put(model, "request", %{"op" => "state.put"}), release, result],
          [good, event, result],
          [good, event, Set.release(event, "withheld", 2_000, nil), result],
          [good, event, release, Map.put(result, "value", %{"forged" => true})],
          [good, event, release, %{result | "version" => 2}],
          [good, event, release, release, result],
          stale.(%{"coverage" => %{"as_of_ms" => @selected - 1}}),
          stale.(%{"coverage" => %{"as_of_ms" => @selected + 6}}),
          stale.(%{"coverage" => %{}}),
          stale.(%{})
        ] do
      assert Set.validate_events(bad) == {:error, :invalid_provided_source_set}
    end
  end

  test "a delivered value must report an as-of time inside the fence" do
    good = parent([source("one", %{"expires_at_ms" => 2_000})])
    {:ok, event, _} = Set.begin(good, @selected)
    at = &%{"coverage" => %{"as_of_ms" => &1}}

    assert Set.result_as_of?(good, event, at.(@selected), 1_500)
    assert Set.result_as_of?(good, event, at.(1_500), 1_500)
    refute Set.result_as_of?(good, event, at.(@selected - 1), 1_500)
    refute Set.result_as_of?(good, event, at.(1_501), 1_500)
    refute Set.result_as_of?(good, event, at.(2_000), 2_500)
    refute Set.result_as_of?(good, event, at.(-1), 1_500)
    refute Set.result_as_of?(good, event, %{"coverage" => %{"as_of_ms" => "1500"}}, 1_500)
    refute Set.result_as_of?(good, event, %{"status" => "ok"}, 1_500)

    refusal = %{"status" => "refused", "evidence" => [], "claims" => [], "coverage" => %{}}
    assert Set.result_as_of?(good, event, refusal, 1_500)
    refute Set.result_as_of?(good, event, %{refusal | "evidence" => [%{}]}, 1_500)

    # An explicit investigation time must be reported exactly, whatever the clock.
    explicit = put_in(good, ["payload", "arguments", "as_of_ms"], 5_000)
    {:ok, explicit_event, _} = Set.begin(explicit, @selected)
    assert explicit_event["transition_ms"] == nil
    assert Set.result_as_of?(explicit, explicit_event, at.(5_000), 1_500)
    refute Set.result_as_of?(explicit, explicit_event, at.(1_500), 1_500)
  end

  test "an installed fence clock drives every boundary check deterministically" do
    good = parent([source("one", %{"expires_at_ms" => 2_000})])
    {:ok, _, fence} = Set.begin(good, @selected)

    clocked = fn now ->
      %{invocation: %{parent: good, provided_set: Map.put(fence, :clock, fn -> now end)}}
    end

    assert Set.now(clocked.(1_999)) == 1_999
    assert {:ok, next} = Set.guard(clocked.(1_999), "model.complete")
    assert next.invocation.provided_set.high_water == 1_999
    assert Set.guard(clocked.(2_000), "model.complete") == :error
    assert Set.guard(clocked.(@selected - 1), "model.complete") == :error
    assert Set.guard(clocked.(1_500), "embedding.create") == :error
    unclocked = %{invocation: %{parent: good, provided_set: fence}}
    assert_in_delta Set.now(unclocked), System.system_time(:millisecond), 5_000
  end

  test "dispatch refuses a fenced call that selects an unregistered route before any IO" do
    parent = self()
    execute = fn _, _, _ -> send(parent, :executed) && {:ok, "sent", %{}} end

    run =
      &Ipse.InferenceDispatch.run(
        %{},
        %{provider: :demo},
        "main",
        nil,
        &1,
        fn _ -> :ok end,
        fn _ -> :ok end,
        execute
      )

    assert {:error, message} = run.(%{admission: %{}, provided_set: true})
    assert message =~ "registered inference route"
    refute_received :executed
    assert {:ok, "sent", _} = run.(%{admission: %{}, provided_set: false})
    assert_received :executed
  end

  test "restored fenced results display only a historical receipt" do
    display =
      Set.display(%{"descriptor" => %{"name" => "ext__r__i", "stage" => "invoke.command"}})

    assert display["value"] == %{
             "status" => "withheld",
             "reason" => "provided_sources_historical",
             "historical_receipt" => true
           }
  end
end
