defmodule Ipse.UsageTest do
  use ExUnit.Case, async: false
  alias Ipse.Usage

  describe "usage" do
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
               Usage.restore([put_in(metadata(), ["metadata", "usage_version"], 3)])

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

  describe "usage normalizer" do
    test "Responses totals include cached input and reasoning output without double counting" do
      raw = %{
        "input_tokens" => 10,
        "output_tokens" => 4,
        "total_tokens" => 14,
        "input_tokens_details" => %{"cached_tokens" => 3, "cache_write_tokens" => 2},
        "output_tokens_details" => %{"reasoning_tokens" => 1},
        "private_extra" => "synthetic-private-usage"
      }

      for provider <- [:openai, :chatgpt] do
        usage = Usage.normalize(provider, raw)
        assert Usage.valid_usage?(usage)
        assert usage["quality"] == "totals_known"
        assert usage["counts"]["input_tokens"] == 10
        assert usage["counts"]["output_tokens"] == 4
        assert usage["counts"]["total_tokens"] == 14
        assert usage["counts"]["input_cached_tokens"] == 3
        assert usage["counts"]["input_cache_write_tokens"] == 2
        assert usage["counts"]["output_reasoning_tokens"] == 1
        assert usage["derived_fields"] == []
        refute Jason.encode!(usage) =~ "synthetic-private-usage"
      end

      assert Usage.billing_mode(:chatgpt) == "subscription"
      assert Usage.billing_mode(:openai) == "api"
    end

    test "Anthropic input totals combine distinct uncached, cache read and cache write counts" do
      usage =
        Usage.normalize(:anthropic, %{
          "input_tokens" => 5,
          "output_tokens" => 7,
          "cache_read_input_tokens" => 10,
          "cache_creation_input_tokens" => 2,
          "cache_creation" => %{
            "ephemeral_5m_input_tokens" => 1,
            "ephemeral_1h_input_tokens" => 1
          },
          "output_tokens_details" => %{"thinking_tokens" => 3},
          "server_tool_use" => %{"web_search_requests" => 1, "web_fetch_requests" => 2}
        })

      assert Usage.valid_usage?(usage)
      assert usage["counts"]["input_uncached_tokens"] == 5
      assert usage["counts"]["input_tokens"] == 17
      assert usage["counts"]["output_tokens"] == 7
      assert usage["counts"]["total_tokens"] == 24
      assert usage["counts"]["output_reasoning_tokens"] == 3
      assert usage["counts"]["input_cache_write_5m_tokens"] == 1
      assert usage["counts"]["input_cache_write_1h_tokens"] == 1
      assert usage["counts"]["provider_web_search_requests"] == 1
      assert usage["derived_fields"] == ~w(input_tokens total_tokens)
    end

    test "missing metering and optional breakdowns stay unknown, including missing Anthropic cache components" do
      usage = Usage.normalize(:openai, %{"input_tokens" => 5})
      assert usage["quality"] == "partial"
      assert usage["counts"]["input_tokens"] == 5
      assert usage["counts"]["output_tokens"] == nil
      assert usage["counts"]["total_tokens"] == nil
      assert usage["counts"]["input_cached_tokens"] == nil
      usage = Usage.normalize(:anthropic, %{"input_tokens" => 5, "output_tokens" => 2})
      assert usage["counts"]["input_uncached_tokens"] == 5
      assert usage["counts"]["input_tokens"] == nil
      assert usage["quality"] == "partial"

      for raw <- [%{}, nil] do
        usage = Usage.normalize(:ollama, raw)
        assert usage["quality"] == "unavailable"
        assert Enum.all?(Map.values(usage["counts"]), &is_nil/1)
        assert Usage.valid_usage?(usage)
      end
    end

    test "local evaluation counters and duration remain local facts rather than zero-priced API usage" do
      usage =
        Usage.normalize(:ollama, %{
          "input_tokens" => 12,
          "output_tokens" => 2,
          "input_cached_tokens" => 4,
          "provider_duration_ns" => 123_000_000
        })

      assert Usage.valid_usage?(usage)
      assert usage["counts"]["total_tokens"] == 14
      assert usage["counts"]["provider_duration_ns"] == 123_000_000
      assert usage["counts"]["output_reasoning_tokens"] == nil
      assert usage["derived_fields"] == ["total_tokens"]
      assert Usage.billing_mode(:ollama) == "local"
    end

    test "actual zero is distinct from missing and scripted usage is not applicable" do
      usage = Usage.normalize(:openai, %{"input_tokens" => 0, "output_tokens" => 0})
      assert usage["counts"]["total_tokens"] == 0
      assert usage["quality"] == "totals_known"
      demo = Usage.normalize(:demo, %{})
      assert demo["quality"] == "not_applicable"
      assert Enum.all?(Map.values(demo["counts"]), &is_nil/1)
      assert Usage.valid_usage?(demo)
      assert Usage.billing_mode(:demo) == "none"
    end

    test "invalid and inconsistent provider counters cannot produce a plausible zero bill" do
      for raw <- [
            %{"input_tokens" => -1},
            %{"input_tokens" => 1.0},
            %{"input_tokens" => true},
            %{"input_tokens" => "5"},
            %{"input_tokens" => Usage.counter_limit() + 1},
            %{"input_tokens" => 5, "output_tokens" => 2, "total_tokens" => 8},
            %{"input_tokens" => 5, "input_tokens_details" => %{"cached_tokens" => 6}},
            %{"output_tokens" => 2, "output_tokens_details" => %{"reasoning_tokens" => 3}},
            %{"input_tokens_details" => "invalid"},
            "invalid"
          ] do
        usage = Usage.normalize(:openai, raw)
        assert usage["quality"] == "invalid"
        assert Enum.all?(Map.values(usage["counts"]), &is_nil/1)
        assert Usage.valid_usage?(usage)
      end
    end

    test "stored normalized values have closed fields, strict integer counters and bounded JSON shapes" do
      valid = Usage.normalize(:openai, %{"input_tokens" => 5, "output_tokens" => 2})
      assert Usage.valid_usage?(valid)
      refute Usage.valid_usage?(Map.put(valid, "secret", "not allowed"))
      refute Usage.valid_usage?(put_in(valid, ["counts", "input_tokens"], 5.0))
      refute Usage.valid_usage?(Map.put(valid, "quality", "unavailable"))
      refute Usage.valid_usage?(Map.put(valid, "derived_fields", ["unsupported"]))
      refute Usage.valid_usage?(put_in(valid, ["counts", "unknown"], 1))

      refute Usage.valid_usage?(
               Map.put(valid, "issues", List.duplicate("unsupported_provider", 129))
             )
    end
  end

  defp metadata, do: %{"type" => "session", "metadata" => %{"usage_version" => 1}}

  defp admitted(session_id \\ Usage.id()) do
    Usage.admission(session_id, %{provider: :openai, model: "fixture-model"}, "model", Usage.id())
  end
end
