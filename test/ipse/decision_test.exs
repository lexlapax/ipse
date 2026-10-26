defmodule Ipse.DecisionTest do
  use ExUnit.Case, async: true
  alias Ipse.Decision

  defp request do
    %{
      "version" => 1,
      "profile" => "advisory",
      "input" => "Source-bound evidence",
      "questions" => [
        %{
          "id" => "eligible",
          "type" => "predicate",
          "instructions" => "Is the evidence eligible?"
        },
        %{
          "id" => "store",
          "type" => "choice",
          "instructions" => "Which permitted store?",
          "choices" => ["notes", "documents"]
        },
        %{
          "id" => "strength",
          "type" => "score",
          "instructions" => "Assess durability",
          "levels" => ["low", "medium", "high"]
        }
      ]
    }
  end

  defp result do
    %{
      "version" => 1,
      "answers" => [
        %{"id" => "eligible", "type" => "predicate", "probability" => 0.8},
        %{
          "id" => "store",
          "type" => "choice",
          "choice" => "notes",
          "confidence" => 0.7,
          "probabilities" => [
            %{"id" => "notes", "probability" => 0.7},
            %{"id" => "documents", "probability" => 0.3}
          ]
        },
        %{
          "id" => "strength",
          "type" => "score",
          "score" => 1.3,
          "confidence" => 0.5,
          "probabilities" => [
            %{"id" => "0", "probability" => 0.2},
            %{"id" => "1", "probability" => 0.3},
            %{"id" => "2", "probability" => 0.5}
          ]
        }
      ]
    }
  end

  test "typed requests preserve stable string alternatives and fractional rubric scores" do
    assert :ok = Decision.validate_request(request())
    assert :ok = Decision.validate_result(request(), result())
    assert {:ok, "notes"} = Decision.select(request(), result(), "store", ["notes"], 0.6)
    assert {:defer, _} = Decision.select(request(), result(), "store", ["documents"], 0.6)
    assert {:defer, _} = Decision.select(request(), result(), "store", ["notes"], 0.9)
    assert {:defer, _} = Decision.select(request(), result(), "store", ["unselected"], 0.6)
  end

  test "valid per-question refusal leaves independent answers structurally usable" do
    mixed =
      put_in(result(), ["answers", Access.at(0)], %{"id" => "eligible", "type" => "refusal"})

    assert :ok = Decision.validate_result(request(), mixed)
    assert {:ok, "notes"} = Decision.select(request(), mixed, "store", ["notes"], 0.6)
    refused = put_in(mixed, ["answers", Access.at(1)], %{"id" => "store", "type" => "refusal"})
    assert :ok = Decision.validate_result(request(), refused)
    assert {:defer, _} = Decision.select(request(), refused, "store", ["notes"], 0)
  end

  test "unknown fields, IDs, types, bool coercion and repeated questions refuse" do
    req = request()

    for invalid <- [
          Map.put(req, "execute", true),
          Map.put(req, "version", 1.0),
          put_in(req, ["questions", Access.at(1), "choices"], [true, false]),
          put_in(req, ["questions", Access.at(1), "choices"], ["notes", "notes"]),
          Map.put(req, "questions", [hd(req["questions"]), hd(req["questions"])]),
          Map.put(req, "input", String.duplicate("x", 16_385)),
          Map.put(req, "input", <<255>>),
          Map.put(req, "questions", []),
          nil
        ] do
      assert {:error, :invalid_decision_request} = Decision.validate_request(invalid)
    end
  end

  test "count, order, option coverage, probability sum and confidence must match" do
    res = result()

    for invalid <- [
          Map.put(res, "answers", tl(res["answers"])),
          Map.put(res, "answers", Enum.reverse(res["answers"])),
          put_in(res, ["answers", Access.at(0), "probability"], 1.1),
          put_in(res, ["answers", Access.at(0), "probability"], true),
          put_in(res, ["answers", Access.at(1), "confidence"], 1.1),
          put_in(res, ["answers", Access.at(1), "probabilities", Access.at(1), "id"], "notes"),
          put_in(
            res,
            ["answers", Access.at(1), "probabilities", Access.at(1), "probability"],
            0.1
          ),
          put_in(res, ["answers", Access.at(1), "choice"], "documents"),
          put_in(res, ["answers", Access.at(2), "score"], 1),
          put_in(res, ["answers", Access.at(2), "score"], 3),
          put_in(res, ["answers", Access.at(2), "probabilities", Access.at(0), "id"], "low"),
          Map.put(res, "grants_permission", true),
          nil
        ] do
      assert {:error, :invalid_decision_result} = Decision.validate_result(request(), invalid)
    end
  end

  test "corruption in an independent question prevents selection from the whole result" do
    corrupt = put_in(result(), ["answers", Access.at(2), "score"], 200)
    assert {:defer, _} = Decision.select(request(), corrupt, "store", ["notes"], 0)
  end
end
