for path <- ~w(profiles notes knowledge/contracts knowledge/records knowledge/decision_policy),
    do:
      Code.require_file(
        Path.expand("../../../extensions/knowledge/src/" <> path <> ".ex", __DIR__)
      )

source = Path.expand("../../../extensions/knowledge/src/knowledge.ex", __DIR__) |> File.read!()

Code.compile_string(
  String.replace(source, "@preset \"native\"", "@preset \"decision-shadow\"", global: false)
  |> String.replace(
    "defmodule IpseKnowledge.Knowledge do",
    "defmodule IpseKnowledge.SelectionShadowFixture do",
    global: false
  )
)

Code.compile_string(
  String.replace(
    source,
    "defmodule IpseKnowledge.Knowledge do",
    "defmodule IpseKnowledge.NativeSelectionBoundary do",
    global: false
  )
)

defmodule IpseKnowledge.SelectionShadowTest do
  use ExUnit.Case, async: false
  alias IpseKnowledge.SelectionShadowFixture, as: K
  alias Ipse.JSON

  defp records(n \\ 8, width \\ 700) do
    for number <- 1..n do
      hash = JSON.sha256(Integer.to_string(number))

      attrs = %{
        "id" => hash,
        "lineage" => hash,
        "text" => String.duplicate("x", width - 8) <> " café 雪",
        "evidence" => %{"sources" => [%{"fixture" => "not-source-authority"}]},
        "category" => "ordinary",
        "reason" => "protocol fixture",
        "observed_at_ms" => 0,
        "event_at_ms" => nil
      }

      {:ok, note} = IpseKnowledge.Notes.new(attrs, 0)
      bytes = Ipse.Extension.Collection.Migration.encode(note)

      %{
        "key" => "note." <> hash,
        "revision" => 1,
        "value" => note,
        "bytes" => byte_size(bytes),
        "sha256" => JSON.sha256(bytes)
      }
    end
  end

  defp options,
    do:
      Map.new(~w(stores search fetch retrieval embedding rerank extraction), &{&1, %{}})
      |> Map.put("version", 1)

  defp args(rows),
    do: %{
      "query" => "Who owns café 雪?",
      "packs" => [
        %{"id" => "first", "members" => Enum.take(rows, 4) |> Enum.map(& &1["key"])},
        %{
          "id" => "second",
          "members" =>
            Enum.drop(rows, div(length(rows), 2)) |> Enum.take(4) |> Enum.map(& &1["key"])
        }
      ]
    }

  defp budget do
    zero = Ipse.Extension.Consent.zero()

    available =
      Map.merge(zero, %{
        "operations" => 2,
        "model_calls" => 1,
        "input_bytes" => 100_000,
        "output_bytes" => 100_000
      })

    %{
      "version" => 1,
      "scope" => "saved_policy",
      "project" => JSON.sha256("namespace"),
      "epoch" => 1,
      "policy_sha256" => JSON.sha256("policy"),
      "observed_at_ms" => 1,
      "period_start_ms" => 0,
      "period_end_ms" => 1000,
      "limits" => available,
      "charged" => zero,
      "available" => available,
      "nonterminal_reserved" => zero,
      "unknown_reserved" => zero,
      "warning_dimensions" => [],
      "exhausted_dimensions" => []
    }
  end

  defp run(rows, opts \\ []) do
    {:ok, state} = K.init(options())
    request = Keyword.get(opts, :args, args(rows))
    start = K.handle("invoke.tool", %{"id" => "select_shadow", "arguments" => request}, state)
    drive(start, rows, opts, [])
  end

  defp drive({:ok, %Ipse.Extension.ResultPublication.Output{bytes: bytes}, _}, _, _, calls),
    do: {JSON.decode_unique(bytes) |> elem(1), Enum.reverse(calls)}

  defp drive({:ok, %{"kind" => "result", "value" => value}, _}, _, _, calls),
    do: {value, Enum.reverse(calls)}

  defp drive({:ok, %{"kind" => "host_call", "request" => request}, state}, rows, opts, calls) do
    assert length(calls) < 40

    outcome =
      case request do
        %{"op" => "context.available"} ->
          value =
            Ipse.Extension.Context.available(%{}, "knowledge", Ipse.Session.Reference.layout())

          changed =
            (state.phase == :selection_output_allocation and
               opts[:change_output_allocation] === true) or
              (state.phase == :selection_allocation_check and opts[:change_allocation] === true)

          value =
            if changed,
              do: %{value | "occupied_other_bytes" => 1, "available_bytes" => 16_383},
              else: value

          %{"status" => "ok", "value" => value}

        %{"purpose" => "saved_policy_budget_v1"} ->
          value =
            if opts[:budget_empty],
              do: put_in(budget(), ["available", "model_calls"], 0),
              else: budget()

          %{"status" => "ok", "value" => value}

        %{"op" => "collection.call", "request" => %{"op" => "index", "limit" => limit}} ->
          generation = if state.phase == :recall_verify and opts[:change_root], do: 2, else: 1

          %{
            "status" => "ok",
            "value" => %{
              "records" =>
                Enum.take(rows, limit) |> Enum.map(&Map.take(&1, ~w(key revision bytes sha256))),
              "next" => if(length(rows) > limit, do: "more", else: nil),
              "count" => length(rows),
              "generation" => generation
            }
          }

        %{"op" => "collection.call", "request" => %{"op" => "get", "key" => key}} ->
          row = Enum.find(rows, &(&1["key"] == key))
          row = if opts[:change_record], do: Map.put(row, "revision", 2), else: row
          %{"status" => "ok", "value" => %{"record" => row, "generation" => 1}}

        %{"op" => "decision.create"} ->
          cond do
            opts[:failure] ->
              opts[:failure]

            opts[:malformed] ->
              %{"status" => "ok", "value" => %{"result" => %{"version" => 1, "answers" => []}}}

            opts[:refusal] ->
              %{
                "status" => "ok",
                "value" => %{
                  "result" => %{
                    "version" => 1,
                    "answers" => [%{"id" => "pack", "type" => "refusal"}]
                  }
                }
              }

            true ->
              [question] = request["questions"]
              probability = if opts[:low], do: 0.6, else: 0.9

              result = %{
                "version" => 1,
                "answers" => [
                  %{
                    "id" => "pack",
                    "type" => "choice",
                    "choice" => "second",
                    "confidence" => probability,
                    "probabilities" =>
                      Enum.map(
                        question["choices"],
                        &%{
                          "id" => &1,
                          "probability" =>
                            if(&1 == "second", do: probability, else: 1 - probability)
                        }
                      )
                  }
                ]
              }

              %{"status" => "ok", "value" => %{"result" => result}}
          end
      end

    next =
      K.handle(
        "host.actions",
        %{
          "operation_id" => String.pad_leading(Integer.to_string(length(calls) + 1, 16), 32, "0"),
          "outcome" => outcome
        },
        state
      )

    drive(next, rows, opts, [request | calls])
  end

  defp decisions(calls), do: Enum.count(calls, &(&1["op"] == "decision.create"))

  test "only shadow artifact exposes selection and native callback cannot enter it" do
    assert Enum.any?(K.describe()["exports"]["tools"], &(&1["id"] == "select_shadow"))

    refute Enum.any?(
             IpseKnowledge.NativeSelectionBoundary.describe()["exports"]["tools"],
             &(&1["id"] == "select_shadow")
           )

    assert :ok =
             Ipse.Extension.Catalog.validate(
               K.describe()["exports"],
               K.describe()["capabilities"]
             )

    {:ok, s} = IpseKnowledge.NativeSelectionBoundary.init(options())

    assert {:ok, %{"value" => %{"status" => "refused"}}, _} =
             IpseKnowledge.NativeSelectionBoundary.handle(
               "invoke.tool",
               %{"id" => "select_shadow", "arguments" => args(records())},
               s
             )
  end

  test "over-budget current protocol retains real greedy baseline beyond four records" do
    {value, calls} = run(records())

    assert value["status"] == "selection_shadow" and value["experimental"],
           inspect(Map.take(value, ~w(status code)))

    assert value["context_mutation"] == "none" and
             value["eligible_rendered_bytes"] > value["allocation_bytes"]

    assert value["baseline"]["included"] > 4 and value["candidate"]["included"] == 4
    assert length(value["reads"]) == 8 and decisions(calls) == 1

    refute Enum.any?(
             calls,
             &(&1["op"] in ~w(context.publish collection.managed state.put tool.call))
           )

    assert value["baseline"]["rendered_bytes"] <= value["allocation_bytes"]
  end

  test "fitting complete set bypasses budget observation and decision entirely" do
    {value, calls} = run(records(2, 20))
    assert value["status"] == "selection_shadow" and value["candidate"] == nil
    assert value["outcome"]["receipt"]["reason"] == "complete_set_fits"
    assert value["baseline"]["included"] == 2 and decisions(calls) == 0
    refute Enum.any?(calls, &Map.has_key?(&1, "purpose"))
  end

  test "malformed, refused and low-probability advice keep the measured ordinary baseline" do
    for opts <- [[malformed: true], [refusal: true], [low: true]] do
      {v, calls} = run(records(), opts)
      assert v["candidate"] == nil and v["baseline"]["included"] > 4 and decisions(calls) == 1
      refute v["outcome"]["receipt"]["reason"] == "selected"
    end
  end

  test "known denial and failed timeout preserve their exact non-advice subtype" do
    for failure <- [
          %{"status" => "denied", "value" => %{}},
          %{"status" => "failed", "value" => %{"code" => "decision_timeout"}}
        ] do
      {v, _} = run(records(), failure: failure)
      assert v["candidate"] == nil and v["baseline"]["included"] > 4
      assert v["outcome"]["receipt"]["reason"] in ~w(decision_denied decision_timeout)
    end
  end

  test "unknown decision stops without another call or successful fallback" do
    {v, calls} = run(records(), failure: %{"status" => "unknown", "value" => %{}})
    assert v["status"] == "interrupted" and v["outcome"]["status"] == "unknown"
    assert List.last(calls)["op"] == "decision.create"
  end

  test "exhausted observation bypasses dispatch but never supplies a grant" do
    {v, calls} = run(records(), budget_empty: true)
    assert v["outcome"]["receipt"]["reason"] == "budget_unavailable" and decisions(calls) == 0
    assert v["baseline"]["included"] > 4
  end

  test "changed allocation, root or record cannot release selected data" do
    for opts <- [
          [change_allocation: true],
          [change_output_allocation: true],
          [change_root: true],
          [change_record: true]
        ] do
      {v, _} = run(records(), opts)
      assert v["status"] == "refused"
    end
  end

  test "foreign alternatives and incomplete candidate sets refuse before decision" do
    r = records()

    foreign =
      put_in(args(r), ["packs", Access.at(0), "members"], ["note." <> String.duplicate("f", 64)])

    {v, calls} = run(r, args: foreign)
    assert v["status"] == "refused" and decisions(calls) == 0
    {v, calls} = run(records(17, 20))
    assert v["status"] == "refused" and decisions(calls) == 0
  end
end
