Code.require_file("../../../dev/knowledge/managed_v3_capacity.exs", __DIR__)
Code.require_file("../../../dev/knowledge/managed_v3_continuation.exs", __DIR__)

defmodule Ipse.Development.ManagedV3ContinuationTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.ManagedV3Continuation, as: Continuation
  alias Ipse.Development.ManagedV3Capacity, as: Capacity
  alias Ipse.JSON

  test "smaller finite chunks preserve original safety bounds and never repeat the prefix" do
    original = Capacity.limits()
    limits = Continuation.limits()

    for field <-
          ~w(publications soft_ms hard_ms beam_memory_limit max_heap_words turnover_implemented),
        do: assert(limits[field] === original[field])

    assert limits["segment_size"] == 250 and limits["segments"] == 8

    for last <- [2000, 2500, 2965, 3999] do
      chunks = Continuation.ranges(last)
      assert length(chunks) <= limits["segments"]
      assert Enum.all?(chunks, &(&1["last"] - &1["first"] + 1 <= 250))

      assert Enum.flat_map(chunks, &Enum.to_list(&1["first"]..&1["last"])) ===
               Enum.to_list((last + 1)..4000)
    end
  end

  test "only the exact frozen pre-dispatch soft guard is a reconcilable failure" do
    source = "before\n  true = System.monotonic_time(:millisecond) - started < @soft\nafter\n"
    path = "/private/frozen/driver.exs"

    log =
      "** (MatchError) no match of right hand side value:\n\n    false\n\n    #{path}:2: anonymous fn/6 in Ipse.Development.ManagedV3Capacity.run/2\n"

    assert Continuation.soft_boundary?(source, log, path)

    for changed <- [
          String.replace(log, ":2:", ":3:"),
          String.replace(log, "MatchError", "RuntimeError"),
          log <> "publication refusal/unknown",
          String.replace(log, "false", "true"),
          log <> "** (RuntimeError) native publication outcome is unknown\n",
          log <> "ambiguous trailing output\n",
          log <> log
        ] do
      refute Continuation.soft_boundary?(source, changed, path)
    end

    refute Continuation.soft_boundary?(source <> source, log, path)
    refute Continuation.soft_boundary?(source, log, "/other/driver.exs")
  end

  test "baseline provenance must be unchanged at every new chunk admission" do
    observed = %{
      "last" => 2965,
      "calls_sha256" => JSON.sha256("actual calls"),
      "failure_log_sha256" => JSON.sha256("exact failure"),
      "pending_sha256" => JSON.sha256("retained pending oracle")
    }

    baseline = Map.put(observed, "checkpoint", %{"root" => "historical observation"})
    assert Continuation.baseline_matches?(baseline, observed)

    for field <- Map.keys(observed) do
      changed =
        Map.put(observed, field, if(field == "last", do: 2964, else: JSON.sha256("changed")))

      refute Continuation.baseline_matches?(baseline, changed)
      refute Continuation.baseline_matches?(baseline, Map.delete(observed, field))
    end
  end

  test "a declared prefix must contain every actual generation once with bounded observations" do
    calls =
      for n <- 1..2965,
          do: %{
            "n" => n,
            "receipt_sha256" => JSON.sha256("receipt#{n}"),
            "normalization_sha256" => JSON.sha256("normalization#{n}"),
            "read_units" => 23,
            "publish_and_checked_readback_ms" => 700.0,
            "accounted_peak_bytes" => 40_000_000
          }

    assert :ok = Continuation.prefix!(calls, 2965)

    for altered <- [
          Enum.reverse(calls),
          tl(calls),
          [hd(calls) | calls],
          List.update_at(calls, 42, &Map.put(&1, "read_units", 33)),
          List.update_at(calls, 42, &Map.put(&1, "accounted_peak_bytes", 64 * 1024 * 1024 + 1)),
          List.update_at(calls, 42, &Map.put(&1, "receipt_sha256", "unverified"))
        ] do
      assert_raise MatchError, fn -> Continuation.prefix!(altered, 2965) end
    end
  end
end

for path <- ~w(notes.ex knowledge/contracts.ex knowledge/records.ex),
    do: Code.require_file("../../../extensions/knowledge/src/" <> path, __DIR__)
