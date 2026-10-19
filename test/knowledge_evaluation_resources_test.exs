Code.require_file("../examples/knowledge/evaluation_resources.exs", __DIR__)

defmodule Ipse.KnowledgeEvaluationResourcesTest do
  use ExUnit.Case, async: false
  alias IpseKnowledgeExample.EvaluationResources, as: Resources

  test "budget reconciliation detects missing admissions and uncovered historical peaks" do
    alias Ipse.{Budget.Ledger, Usage}
    id = Usage.id()
    root = %{"session_id" => id, "state_dir_sha256" => String.duplicate("a", 64)}

    policy = %{
      "version" => 1,
      "max_requests" => 1,
      "max_input_tokens" => 100,
      "reserve_input_tokens" => 40
    }

    a = Usage.admission(id, %{provider: :openai, model: "fixture"}, "model", Usage.id())
    refused = Usage.admission(id, %{provider: :openai, model: "fixture"}, "model", Usage.id())
    header = Ledger.header(root, policy)
    assert {:ok, initial} = Ledger.restore([header], root, policy)
    assert {:ok, reserved, _} = Ledger.reserve(initial, a)

    dispatch = %{
      "type" => "dispatch_intent",
      "request_id" => a["request_id"],
      "attempt_id" => a["attempt_id"]
    }

    high = Usage.observation(a, %{"input_tokens" => 60, "output_tokens" => 2}, 1)
    low = Usage.observation(a, %{"input_tokens" => 7, "output_tokens" => 2}, 2)

    observed = fn event ->
      %{
        "type" => "observed",
        "request_id" => a["request_id"],
        "attempt_id" => a["attempt_id"],
        "usage" => event["usage"]
      }
    end

    finished = Usage.completion(a, {:error, "synthetic interruption"}, 9, low["usage"])
    refusal = %{"type" => "refused", "admission" => refused}
    events = [a, high, low, finished, refused]

    usage = %{
      requests: %{
        a["request_id"] => %{admission: a, observation: low["usage"], completion: finished},
        refused["request_id"] => %{admission: refused, observation: nil, completion: nil}
      }
    }

    assert {:ok, state} =
             Ledger.restore(
               [header, reserved, dispatch, observed.(high), observed.(low), refusal],
               root,
               policy
             )

    assert Resources.reconcile_budget(state, usage, events, id) == :ok

    assert {:ok, rolled_back} =
             Ledger.restore([header, reserved, dispatch, observed.(low), refusal], root, policy)

    assert {:error, :evaluation_budget_source_mismatch} =
             Resources.reconcile_budget(rolled_back, usage, events, id)

    assert {:error, :evaluation_budget_source_mismatch} =
             Resources.reconcile_budget(%{state | refusals: %{}}, usage, events, id)

    assert {:error, :evaluation_budget_source_mismatch} =
             Resources.reconcile_budget(state, usage, events, Usage.id())

    concealed = put_in(usage, [:requests, refused["request_id"], :observation], low["usage"])

    assert {:error, :evaluation_budget_source_mismatch} =
             Resources.reconcile_budget(state, concealed, events, id)
  end

  test "nearest-rank latency keeps missing observations and every failed query" do
    assert Resources.distribution([100, nil, 1, 3]) == %{
             "n" => 4,
             "observed" => 3,
             "unknown" => 1,
             "p50_ms" => 3,
             "p95_ms" => 100
           }

    assert Resources.distribution([])["p95_ms"] == nil
    rows = [row("Q1", "ok"), row("Q2", "failed"), row("Q3", "unavailable")]
    timings = [timing("Q1", 1000), timing("Q2", 100_000)]
    report = Resources.summary(rows, timings, [], [budget()])
    [variant] = report["variants"]
    refute report["complete"]
    assert variant["queries"]["declared"] == 3
    assert variant["queries"]["missing"] == 1
    assert variant["queries"]["statuses"] == %{"ok" => 1, "failed" => 1, "unavailable" => 1}
    [phase] = variant["phases"]
    assert phase["n"] == 2 and phase["p50_ms"] == 1.0 and phase["p95_ms"] == 100.0
    refute Resources.summary(rows, timings ++ [hd(timings)], [], [budget()])["complete"]
  end

  test "metering preserves unknown input and inapplicable embedding output" do
    records = [request("embedding", nil, nil, nil), request("text", 4, 2, 7)]
    report = Resources.summary([row("Q1", "failed")], [timing("Q1", 9000)], records, [budget()])
    assert report["complete"]
    [variant] = report["variants"]
    assert variant["requests"]["attempted"] == 2
    assert variant["requests"]["dispatch_intents"] == 2
    [embedding, answer] = Enum.sort_by(variant["requests"]["groups"], & &1["role"], :desc)
    assert embedding["role"] == "query_embedding"
    assert embedding["input_tokens"]["total"] == nil
    assert embedding["input_tokens"]["unknown_requests"] == 1
    assert embedding["output_tokens"]["status"] == "not_applicable"
    assert embedding["output_tokens"]["total"] == nil
    assert embedding["latency_ms"]["unknown"] == 1
    assert answer["input_tokens"]["total"] == 4
    assert variant["money"] == %{"status" => "unpriced", "amount" => nil}
    refute Resources.summary([row("Q1", "failed")], [timing("Q1", 9000)], records, [])["complete"]
  end

  test "phase clocks preserve return, raise and throw without retaining private reasons" do
    root = Path.join(System.tmp_dir!(), "ipse-resource-clock-" <> Ipse.Usage.id())
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    context = %{
      "phase" => "query",
      "project" => "alpha",
      "variant" => "lexical",
      "query_id" => "Q1"
    }

    assert Resources.measure(root, context, fn -> :result end) == :result

    assert_raise RuntimeError, "private-synthetic-reason", fn ->
      Resources.measure(root, context, fn -> raise "private-synthetic-reason" end)
    end

    assert catch_throw(
             Resources.measure(root, context, fn -> throw(:private_synthetic_reason) end)
           ) == :private_synthetic_reason

    bytes = File.read!(Path.join(root, "timings.jsonl"))
    refute bytes =~ "private"
    samples = bytes |> String.split("\n", trim: true) |> Enum.map(&JSON.decode!/1)
    assert Enum.map(samples, & &1["outcome"]) == ~w(returned raised throw)
    assert Enum.all?(samples, &(&1["elapsed_us"] >= 0 and &1["query_id"] == "Q1"))
  end

  defp row(id, status),
    do: %{"project" => "alpha", "variant" => "lexical", "query_id" => id, "status" => status}

  defp timing(id, elapsed),
    do: %{
      "project" => "alpha",
      "variant" => "lexical",
      "query_id" => id,
      "phase" => "query",
      "outcome" => "returned",
      "elapsed_us" => elapsed
    }

  defp budget,
    do: %{
      "project" => "alpha",
      "variant" => "lexical",
      "accounting_verified" => true,
      "budget" => %{"currency" => nil}
    }

  defp request(operation, input, output, duration),
    do: %{
      "project" => "alpha",
      "variant" => "lexical",
      "attribution" => "confirmed",
      "verb" => if(operation == "embedding", do: "query", else: "answer"),
      "budget_admitted" => true,
      "dispatch_intent" => true,
      "budget_settled" => true,
      "request" => %{
        "operation" => operation,
        "outcome" => "completed",
        "duration_ms" => duration,
        "usage" => %{"counts" => %{"input_tokens" => input, "output_tokens" => output}}
      }
    }
end
