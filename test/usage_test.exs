defmodule Ipse.UsageTest do
  use ExUnit.Case, async: true
  alias Ipse.Usage

  defp metadata, do: %{"type" => "session", "metadata" => %{"usage_version" => 1}}

  defp admitted(session_id \\ Usage.id()) do
    Usage.admission(session_id, %{provider: :openai, model: "fixture-model"}, "model", Usage.id())
  end

  test "large restores retain chronological projections and reject reused attempts without quadratic work" do
    session = Usage.id()

    probe = fn count ->
      requests = for _ <- 1..count, do: admitted(session)
      {:reductions, before} = Process.info(self(), :reductions)
      assert {:ok, ledger} = Usage.restore([metadata() | requests])
      {:reductions, after_count} = Process.info(self(), :reductions)
      assert Usage.order(ledger) == Enum.map(requests, & &1["request_id"])

      assert Enum.map(Usage.snapshot(ledger)["requests"], & &1["request_id"]) ==
               Enum.map(Enum.take(requests, -16), & &1["request_id"])

      first = hd(requests)
      reused = %{admitted(session) | "attempt_id" => first["attempt_id"]}
      assert {:error, :invalid_usage_journal} = Usage.apply_event(ledger, reused)
      after_count - before
    end

    probe.(100)
    small = probe.(1000)
    large = probe.(4000)
    assert large < small * 8
  end

  test "snapshots replace cumulative observations and exact duplicates do not double count" do
    request = admitted()
    one = Usage.observation(request, %{"input_tokens" => 8, "output_tokens" => 1}, 1)
    two = Usage.observation(request, %{"input_tokens" => 8, "output_tokens" => 3}, 2)

    final =
      Usage.completion(
        request,
        {:ok, %{}, %{"input_tokens" => 8, "output_tokens" => 4}},
        12,
        two["usage"]
      )

    assert {:ok, ledger} =
             Usage.restore([metadata(), request, request, one, one, two, final, final])

    assert ledger.requests[request["request_id"]].sequence == 2

    assert [%{"usage" => %{"counts" => %{"total_tokens" => 12}}, "finality" => "final"}] =
             Usage.snapshot(ledger)["requests"]

    assert Usage.snapshot(ledger)["request_count"] == 1
  end

  test "interruption retains known partial facts while success with missing counters stays unknown" do
    request = admitted()
    observed = Usage.observation(request, %{"input_tokens" => 8}, 1)
    assert {:ok, interrupted} = Usage.restore([metadata(), request, observed])

    assert [
             %{
               "outcome" => "unknown",
               "usage" => %{"counts" => %{"input_tokens" => 8, "output_tokens" => nil}}
             }
           ] = Usage.snapshot(interrupted)["requests"]

    assert Usage.snapshot(interrupted)["unknown_outcome_count"] == 1
    final = Usage.completion(request, {:ok, %{}, %{}}, 2, observed["usage"])
    assert {:ok, completed} = Usage.restore([metadata(), request, observed, final])
    assert [%{"usage" => %{"quality" => "unavailable"}}] = Usage.snapshot(completed)["requests"]
    cancelled = Usage.completion(request, :cancelled, 3, observed["usage"])
    assert cancelled["usage"] == observed["usage"]
    assert cancelled["finality"] == "partial"
  end

  test "malformed, orphaned, conflicting and out-of-order accounting is refused" do
    request = admitted()
    observed = Usage.observation(request, %{"input_tokens" => 8}, 1)
    final = Usage.completion(request, :cancelled, 3, observed["usage"])

    for events <- [
          [metadata(), observed],
          [metadata(), final],
          [metadata(), request, Map.put(observed, "sequence", 2)],
          [metadata(), request, Map.put(observed, "attempt_id", Usage.id())],
          [
            metadata(),
            request,
            observed,
            put_in(observed, ["usage", "counts", "input_tokens"], 9)
          ],
          [metadata(), request, final, Map.put(final, "duration_ms", 4)],
          [metadata(), request, final, observed],
          [metadata(), Map.put(request, "secret", "excluded")],
          [metadata(), Map.put(request, "version", 1.0)],
          [metadata(), request, Map.put(final, "type", "unknown_usage_event")]
        ] do
      assert {:error, :invalid_usage_journal} = Usage.restore(events)
    end
  end

  test "assistant and checkpoint bindings detect removed or mismatched accounting" do
    request = admitted()
    final = Usage.completion(request, {:ok, %{}, %{}}, 1, nil)

    message = %{
      "type" => "message",
      "request_id" => request["request_id"],
      "message" => %{"role" => "assistant", "content" => "fixture"}
    }

    assert {:ok, _} = Usage.restore([metadata(), request, final, message])

    for events <- [
          [metadata(), message],
          [metadata(), request, message],
          [metadata(), request, final, message, message],
          [metadata(), request, final, Map.put(message, "type", "context_compacted")],
          [metadata(), request, final, Map.delete(message, "request_id")]
        ] do
      assert {:error, :invalid_usage_journal} = Usage.restore(events)
    end
  end

  test "legacy sessions are explicitly unmetered and bounded snapshots do not hide total request count" do
    assert {:ok, ledger} = Usage.restore([%{"type" => "session", "metadata" => %{}}])
    assert Usage.snapshot(ledger)["legacy_unmetered"]

    assert {:error, :unsupported_usage_version} =
             Usage.restore([put_in(metadata(), ["metadata", "usage_version"], 2)])

    session_id = Usage.id()
    requests = for _ <- 1..18, do: admitted(session_id)
    assert {:ok, ledger} = Usage.restore([metadata() | requests])
    assert Usage.snapshot(ledger)["request_count"] == 18
    assert Usage.snapshot(ledger)["shown_request_count"] == 16
  end

  test "request scope is bound to the actual session, selected provider and parent" do
    request = admitted()
    meta = put_in(metadata(), ["metadata", "provider"], "openai")
    assert {:ok, _} = Usage.restore([meta, request], request["session_id"])

    for changed <- [
          Map.put(request, "session_id", Usage.id()),
          Map.put(request, "parent_request_id", Usage.id()),
          Map.merge(request, %{"provider" => "chatgpt", "billing_mode" => "subscription"})
        ] do
      assert {:error, :invalid_usage_journal} =
               Usage.restore([meta, changed], request["session_id"])
    end

    assert {:error, :invalid_usage_configuration} =
             Usage.configuration(%{
               provider: :openai,
               model: "fixture",
               delegation_origin: "malformed"
             })

    assert {:error, :invalid_usage_journal} = Usage.restore([%{"metadata" => "malformed"}])
  end
end
