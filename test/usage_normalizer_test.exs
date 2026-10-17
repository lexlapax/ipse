defmodule Ipse.Usage.NormalizerTest do
  use ExUnit.Case, async: true
  alias Ipse.Usage.Normalizer

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
      usage = Normalizer.normalize(provider, raw)
      assert Normalizer.valid?(usage)
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

    assert Normalizer.billing_mode(:chatgpt) == "subscription"
    assert Normalizer.billing_mode(:openai) == "api"
  end

  test "Anthropic input totals combine distinct uncached, cache read and cache write counts" do
    usage =
      Normalizer.normalize(:anthropic, %{
        "input_tokens" => 5,
        "output_tokens" => 7,
        "cache_read_input_tokens" => 10,
        "cache_creation_input_tokens" => 2,
        "cache_creation" => %{"ephemeral_5m_input_tokens" => 1, "ephemeral_1h_input_tokens" => 1},
        "output_tokens_details" => %{"thinking_tokens" => 3},
        "server_tool_use" => %{"web_search_requests" => 1, "web_fetch_requests" => 2}
      })

    assert Normalizer.valid?(usage)
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
    usage = Normalizer.normalize(:openai, %{"input_tokens" => 5})
    assert usage["quality"] == "partial"
    assert usage["counts"]["input_tokens"] == 5
    assert usage["counts"]["output_tokens"] == nil
    assert usage["counts"]["total_tokens"] == nil
    assert usage["counts"]["input_cached_tokens"] == nil
    usage = Normalizer.normalize(:anthropic, %{"input_tokens" => 5, "output_tokens" => 2})
    assert usage["counts"]["input_uncached_tokens"] == 5
    assert usage["counts"]["input_tokens"] == nil
    assert usage["quality"] == "partial"

    for raw <- [%{}, nil] do
      usage = Normalizer.normalize(:ollama, raw)
      assert usage["quality"] == "unavailable"
      assert Enum.all?(Map.values(usage["counts"]), &is_nil/1)
      assert Normalizer.valid?(usage)
    end
  end

  test "local evaluation counters and duration remain local facts rather than zero-priced API usage" do
    usage =
      Normalizer.normalize(:ollama, %{
        "input_tokens" => 12,
        "output_tokens" => 2,
        "input_cached_tokens" => 4,
        "provider_duration_ns" => 123_000_000
      })

    assert Normalizer.valid?(usage)
    assert usage["counts"]["total_tokens"] == 14
    assert usage["counts"]["provider_duration_ns"] == 123_000_000
    assert usage["counts"]["output_reasoning_tokens"] == nil
    assert usage["derived_fields"] == ["total_tokens"]
    assert Normalizer.billing_mode(:ollama) == "local"
  end

  test "actual zero is distinct from missing and scripted usage is not applicable" do
    usage = Normalizer.normalize(:openai, %{"input_tokens" => 0, "output_tokens" => 0})
    assert usage["counts"]["total_tokens"] == 0
    assert usage["quality"] == "totals_known"
    demo = Normalizer.normalize(:demo, %{})
    assert demo["quality"] == "not_applicable"
    assert Enum.all?(Map.values(demo["counts"]), &is_nil/1)
    assert Normalizer.valid?(demo)
    assert Normalizer.billing_mode(:demo) == "none"
  end

  test "invalid and inconsistent provider counters cannot produce a plausible zero bill" do
    for raw <- [
          %{"input_tokens" => -1},
          %{"input_tokens" => 1.0},
          %{"input_tokens" => true},
          %{"input_tokens" => "5"},
          %{"input_tokens" => Normalizer.limit() + 1},
          %{"input_tokens" => 5, "output_tokens" => 2, "total_tokens" => 8},
          %{"input_tokens" => 5, "input_tokens_details" => %{"cached_tokens" => 6}},
          %{"output_tokens" => 2, "output_tokens_details" => %{"reasoning_tokens" => 3}},
          %{"input_tokens_details" => "invalid"},
          "invalid"
        ] do
      usage = Normalizer.normalize(:openai, raw)
      assert usage["quality"] == "invalid"
      assert Enum.all?(Map.values(usage["counts"]), &is_nil/1)
      assert Normalizer.valid?(usage)
    end
  end

  test "stored normalized values have closed fields, strict integer counters and bounded JSON shapes" do
    valid = Normalizer.normalize(:openai, %{"input_tokens" => 5, "output_tokens" => 2})
    assert Normalizer.valid?(valid)
    refute Normalizer.valid?(Map.put(valid, "secret", "not allowed"))
    refute Normalizer.valid?(put_in(valid, ["counts", "input_tokens"], 5.0))
    refute Normalizer.valid?(Map.put(valid, "quality", "unavailable"))
    refute Normalizer.valid?(Map.put(valid, "derived_fields", ["unsupported"]))
    refute Normalizer.valid?(put_in(valid, ["counts", "unknown"], 1))

    refute Normalizer.valid?(
             Map.put(valid, "issues", List.duplicate("unsupported_provider", 129))
           )
  end
end
