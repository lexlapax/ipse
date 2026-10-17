defmodule Ipse.Extensions.CostsTest do
  use ExUnit.Case, async: true
  alias Ipse.Extensions.Costs
  alias Ipse.Usage.Normalizer

  defp card do
    %{
      "version" => 1,
      "id" => "synthetic",
      "revision" => "2026-10-17-a",
      "currency" => "USD",
      "source" => "operator:synthetic-test-rates",
      "published_on" => "2026-10-17",
      "rows" => [
        %{
          "id" => "fixture-model",
          "provider" => "openai",
          "billing_mode" => "api",
          "basis" => "api_estimate",
          "model" => "fixture",
          "endpoint_sha256" => nil,
          "from" => "2026-01-01",
          "until" => "2027-01-01",
          "input_min" => 0,
          "input_max" => nil,
          "input_mode" => "flat",
          "rates" => %{"input" => "2", "output" => "10"}
        }
      ]
    }
  end

  defp request(provider \\ :openai, raw \\ %{"input_tokens" => 100, "output_tokens" => 20}) do
    %{
      "provider" => to_string(provider),
      "billing_mode" => Normalizer.billing_mode(provider),
      "model" => "fixture",
      "reported_model" => nil,
      "endpoint_sha256" => nil,
      "admitted_at_ms" => DateTime.to_unix(~U[2026-10-17 00:00:00Z], :millisecond),
      "outcome" => "completed",
      "finality" => "final",
      "usage" => Normalizer.normalize(provider, raw)
    }
  end

  defp change_row(card, updates),
    do: Map.update!(card, "rows", fn [row] -> [Map.merge(row, updates)] end)

  defp split(mode \\ "cache_split") do
    rates =
      if mode == "cache_split",
        do: %{
          "input_uncached" => "2",
          "input_cached" => "0.5",
          "input_cache_write" => "2.5",
          "output" => "10"
        },
        else: %{
          "input_uncached" => "2",
          "input_cached" => "0.5",
          "input_cache_write_5m" => "2.5",
          "input_cache_write_1h" => "4",
          "output" => "10"
        }

    change_row(card(), %{"input_mode" => mode, "rates" => rates})
  end

  test "flat costs use explicit decimal rates and inclusive output, without adding reasoning twice" do
    req =
      request(:openai, %{
        "input_tokens" => 100,
        "output_tokens" => 20,
        "output_tokens_details" => %{"reasoning_tokens" => 7}
      })

    assert :ok = Costs.validate(card())
    assert {:ok, result} = Costs.estimate(card(), req)
    assert result["status"] == "estimated"
    assert result["amount_nanos"] == 400_000
    assert result["known_amount_nanos"] == 400_000
    assert result["basis"] == "api_estimate"
    assert result["provider"] == "openai"
    assert result["billing_mode"] == "api"
    assert result["requested_model"] == "fixture"
    assert result["rated_model"] == "fixture"
    assert result["reported_model"] == nil
    assert result["input_mode"] == "flat"
    assert result["currency_scale"] == 9
    assert result["scope"] == "text_tokens_and_reported_extras"
  end

  test "cached and cache-write quantities partition input rather than adding to it" do
    req =
      request(:openai, %{
        "input_tokens" => 100,
        "output_tokens" => 20,
        "input_tokens_details" => %{"cached_tokens" => 20, "cache_write_tokens" => 10}
      })

    assert {:ok, result} = Costs.estimate(split(), req)
    assert result["amount_nanos"] == 375_000
    assert Enum.find(result["components"], &(&1["unit"] == "input_uncached"))["count"] == 70
  end

  test "Anthropic TTL writes are disjoint and reported server requests use request units" do
    req =
      request(:anthropic, %{
        "input_tokens" => 70,
        "output_tokens" => 20,
        "cache_read_input_tokens" => 20,
        "cache_creation_input_tokens" => 10,
        "cache_creation" => %{"ephemeral_5m_input_tokens" => 6, "ephemeral_1h_input_tokens" => 4},
        "server_tool_use" => %{"web_search_requests" => 2, "web_fetch_requests" => 3}
      })

    rates =
      hd(split("cache_ttl_split")["rows"])["rates"]
      |> Map.merge(%{"web_search" => "1", "web_fetch" => "2"})

    c = change_row(split("cache_ttl_split"), %{"provider" => "anthropic", "rates" => rates})
    assert {:ok, result} = Costs.estimate(c, req)
    assert result["amount_nanos"] == 8_381_000
    assert result["missing"] == []
  end

  test "sub-nano components are added exactly before one ceiling, with no floats" do
    c = change_row(card(), %{"rates" => %{"input" => "0.000000001", "output" => "0.000000001"}})

    assert {:ok, result} =
             Costs.estimate(c, request(:openai, %{"input_tokens" => 1, "output_tokens" => 1}))

    assert result["amount_nanos"] == 1
    assert result["rounding"] == "ceiling_per_request"
  end

  test "missing counters retain a known subtotal and never produce a zero total" do
    assert {:ok, result} = Costs.estimate(split(), request())
    assert result["status"] == "partial"
    assert result["amount_nanos"] == nil
    assert result["known_amount_nanos"] == 200_000
    assert "count:input_cached" in result["missing"]
    assert {:ok, absent} = Costs.estimate(card(), request(:openai, %{}))
    assert absent["amount_nanos"] == nil
    assert absent["known_amount_nanos"] == nil

    assert {:ok, zero} =
             Costs.estimate(
               split(),
               request(:openai, %{"input_tokens" => 0, "output_tokens" => 0})
             )

    assert zero["status"] == "estimated"
    assert zero["amount_nanos"] == 0
  end

  test "contradictory cache partitions cannot contribute apparently known input cost" do
    req =
      request(:openai, %{
        "input_tokens" => 100,
        "output_tokens" => 20,
        "input_tokens_details" => %{"cached_tokens" => 80, "cache_write_tokens" => 50}
      })

    assert {:ok, result} = Costs.estimate(split(), req)
    assert result["amount_nanos"] == nil
    assert result["known_amount_nanos"] == 200_000
    assert "input_partition_unknown_or_inconsistent" in result["missing"]

    req =
      request(:anthropic, %{
        "input_tokens" => 70,
        "output_tokens" => 20,
        "cache_read_input_tokens" => 20,
        "cache_creation_input_tokens" => 10,
        "cache_creation" => %{"ephemeral_5m_input_tokens" => 6, "ephemeral_1h_input_tokens" => 6}
      })

    c = change_row(split("cache_ttl_split"), %{"provider" => "anthropic"})
    assert {:ok, result} = Costs.estimate(c, req)
    assert result["known_amount_nanos"] == 150_000 + 200_000
    assert "cache_ttl_partition_unknown_or_inconsistent" in result["missing"]
  end

  test "cancellation or an unknown outcome leaves computed usage a partial estimate" do
    for outcome <- ~w(failed cancelled unknown) do
      req = Map.merge(request(), %{"outcome" => outcome, "finality" => "partial"})
      assert {:ok, result} = Costs.estimate(card(), req)
      assert result["status"] == "partial"
      assert result["amount_nanos"] == nil
      assert result["known_amount_nanos"] == 400_000
      assert "incomplete_request" in result["missing"]
    end
  end

  test "subscription rates require an explicit equivalent identity, never an API billing fallback" do
    req = request(:chatgpt)
    assert {:ok, result} = Costs.estimate(card(), req)
    assert result["status"] == "not_applicable"
    assert result["amount_nanos"] == nil
    assert result["missing"] == ["subscription_is_not_api_spend"]

    c =
      change_row(card(), %{
        "provider" => "chatgpt",
        "billing_mode" => "subscription",
        "basis" => "api_equivalent"
      })

    assert {:ok, result} = Costs.estimate(c, req)
    assert result["basis"] == "api_equivalent"
    assert result["amount_nanos"] == 400_000

    assert {:error, :invalid_rate_card} =
             Costs.validate(change_row(c, %{"basis" => "api_estimate"}))
  end

  test "local duration is explicitly configured and demo is not metered" do
    req =
      request(:ollama, %{
        "input_tokens" => 100,
        "output_tokens" => 20,
        "provider_duration_ns" => 500_000_000
      })

    assert {:ok, result} = Costs.estimate(card(), req)
    assert result["missing"] == ["local_cost_unconfigured"]

    c =
      change_row(card(), %{
        "provider" => "ollama",
        "billing_mode" => "local",
        "basis" => "local_estimate",
        "rates" => %{"input" => "2", "output" => "10", "duration_second" => "0.01"}
      })

    assert {:ok, result} = Costs.estimate(c, req)
    assert result["basis"] == "local_estimate"
    assert result["amount_nanos"] == 5_400_000
    assert {:ok, demo} = Costs.estimate(card(), request(:demo))
    assert demo["status"] == "not_applicable"
    assert demo["amount_nanos"] == nil
  end

  test "unpriced reported extras and unknown configured extras keep the total unknown" do
    req =
      request(:anthropic, %{
        "input_tokens" => 100,
        "output_tokens" => 20,
        "cache_read_input_tokens" => 0,
        "cache_creation_input_tokens" => 0,
        "server_tool_use" => %{"web_search_requests" => 2}
      })

    c = change_row(card(), %{"provider" => "anthropic"})
    assert {:ok, result} = Costs.estimate(c, req)
    assert result["amount_nanos"] == nil
    assert "rate:web_search" in result["missing"]
    c = change_row(card(), %{"rates" => %{"input" => "2", "output" => "10", "web_search" => "1"}})
    assert {:ok, result} = Costs.estimate(c, request())
    assert "count:web_search" in result["missing"]
  end

  test "exact reported model and endpoint identity refuse implicit aliases or fallback" do
    for changes <- [
          %{"reported_model" => "different"},
          %{"endpoint_sha256" => String.duplicate("a", 64)}
        ] do
      assert {:ok, result} = Costs.estimate(card(), Map.merge(request(), changes))
      assert result["status"] == "unpriced"
      assert result["missing"] == ["rate_unavailable"]
    end
  end

  test "date and token bands are half-open and overlapping candidates refuse" do
    [row] = card()["rows"]

    c =
      Map.put(card(), "rows", [
        %{row | "input_max" => 100},
        %{
          row
          | "id" => "large",
            "input_min" => 100,
            "rates" => %{"input" => "4", "output" => "20"}
        }
      ])

    assert :ok = Costs.validate(c)
    assert {:ok, result} = Costs.estimate(c, request())
    assert result["row_id"] == "large"
    assert result["amount_nanos"] == 800_000
    assert {:ok, missing} = Costs.estimate(c, request(:openai, %{}))
    assert missing["missing"] == ["input_band_unknown"]

    assert {:error, :invalid_rate_card} =
             Costs.validate(Map.put(card(), "rows", [row, %{row | "id" => "overlap"}]))

    expired =
      Map.put(
        request(),
        "admitted_at_ms",
        DateTime.to_unix(~U[2027-01-01 00:00:00Z], :millisecond)
      )

    assert {:ok, missing} = Costs.estimate(card(), expired)
    assert missing["missing"] == ["rate_unavailable"]
  end

  test "a changed configured revision/rate changes provenance without changing input" do
    c =
      card()
      |> Map.put("revision", "second")
      |> change_row(%{"rates" => %{"input" => "4", "output" => "20"}})

    assert {:ok, old} = Costs.estimate(card(), request())
    assert {:ok, new} = Costs.estimate(c, request())
    assert old["card_sha256"] != new["card_sha256"]
    assert new["amount_nanos"] == old["amount_nanos"] * 2
  end

  test "malformed rates, authority-bearing sources, dates and unknown dimensions refuse" do
    for rate <- [2.0, "-1", "1e2", "0.0000000001", "01", "nan"] do
      assert {:error, :invalid_rate_card} =
               Costs.validate(
                 change_row(card(), %{"rates" => %{"input" => rate, "output" => "10"}})
               )
    end

    for changes <- [
          %{"source" => "https://user:secret@example.test/rates"},
          %{"source" => "https://example.test/rates?key=secret"},
          %{"published_on" => "2026-02-30"},
          %{"currency" => "usd"},
          %{"version" => 1.0},
          %{"unexpected" => true}
        ] do
      assert {:error, :invalid_rate_card} = Costs.validate(Map.merge(card(), changes))
    end

    assert {:error, :invalid_cost_request} =
             Costs.estimate(card(), Map.put(request(), "private", "not admitted"))

    assert {:error, :invalid_rate_card} = Costs.validate(change_row(card(), %{"input_max" => 0}))
  end

  test "amount overflow is visible rather than rounded into a plausible JSON number" do
    c = change_row(card(), %{"rates" => %{"input" => "999999999", "output" => "999999999"}})

    req =
      request(:openai, %{
        "input_tokens" => 500_000_000_000,
        "output_tokens" => 500_000_000_000
      })

    assert {:ok, result} = Costs.estimate(c, req)
    assert result["amount_nanos"] == nil
    assert result["known_amount_nanos"] == nil
    assert result["missing"] == ["amount_overflow"]
  end
end
