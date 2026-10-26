defmodule Ipse.Provider.DecisionTest do
  use ExUnit.Case, async: true
  alias Ipse.Provider.Decision, as: Wire

  defp fixture(name), do: JSON.decode!(File.read!("test/fixtures/decisions/#{name}.json"))

  test "OpenAI request uses named typed questions, string choices and explicit no-cache mode" do
    assert {:ok, body} = Wire.encode(:openai, fixture("request"), "gpt-6-luna")
    assert body["input"] == "Pinned notes and source-bound candidates."
    assert body["prompt_cache_options"] == %{"mode" => "explicit"}

    assert Enum.at(body["questions"], 1) == %{
             "name" => "store",
             "type" => "choice",
             "instructions" => "Which admitted store is relevant?",
             "choices" => [%{"value" => "notes"}, %{"value" => "documents"}]
           }

    assert Enum.at(body["questions"], 2)["levels"] == [
             %{"label" => "low"},
             %{"label" => "medium"},
             %{"label" => "high"}
           ]

    refute Map.has_key?(body, "tools")
  end

  test "System One explicitly maps predicate to Noul and preserves named criteria and rubric" do
    assert {:ok, body} = Wire.encode(:system_one, fixture("request"), "jev-fixture-pinned")
    assert body["questions"]["eligible"]["type"] == "noul"
    assert body["questions"]["store"]["criteria"] == %{"notes" => nil, "documents" => nil}
    assert body["questions"]["strength"]["criteria"] == ["low", "medium", "high"]
    assert body["state"] == fixture("request")["input"]
  end

  test "native distributions and independent raw confidence survive normalization" do
    assert {:ok, openai, facts} =
             Wire.decode(:openai, fixture("request"), "gpt-6-luna", fixture("openai"))

    assert {:ok, system_one, other} =
             Wire.decode(
               :system_one,
               fixture("request"),
               "jev-fixture-pinned",
               fixture("system-one")
             )

    assert openai == system_one
    choice = Enum.at(openai["answers"], 1)
    assert choice["confidence"] == 0.55
    assert Enum.find(choice["probabilities"], &(&1["id"] == "notes"))["probability"] == 0.7
    assert facts["subset"] == "openai-decisions-text-v1"
    assert other["subset"] == "systemone-text-v1"
    assert facts["usage"]["input_tokens_details"]["cached_tokens"] == 20
  end

  test "OpenAI refusal is distinct from malformed output and other answers remain present" do
    native =
      put_in(fixture("openai"), ["answers", Access.at(0)], %{
        "type" => "refusal",
        "name" => "eligible"
      })

    assert {:ok, result, _} = Wire.decode(:openai, fixture("request"), "gpt-6-luna", native)
    assert hd(result["answers"]) == %{"type" => "refusal", "id" => "eligible"}
    assert length(result["answers"]) == 3
    malformed = put_in(native, ["answers", Access.at(0), "name"], "not_eligible")

    assert {:error, :invalid_decision_response} =
             Wire.decode(:openai, fixture("request"), "gpt-6-luna", malformed)
  end

  test "cross-model, changed labels, boolean coercion, missing options and forged usage refuse" do
    req = fixture("request")
    native = fixture("openai")

    for invalid <- [
          Map.put(native, "model", "gpt-other"),
          put_in(
            native,
            ["answers", Access.at(2), "probabilities", Access.at(1), "label"],
            "different"
          ),
          put_in(native, ["answers", Access.at(1), "probabilities", Access.at(1), "value"], true),
          put_in(native, ["answers", Access.at(1), "probabilities"], []),
          put_in(native, ["usage", "input_tokens"], -1),
          put_in(native, ["usage", "total_tokens"], 100),
          Map.put(native, "permission", "allow")
        ] do
      assert {:error, :invalid_decision_response} =
               Wire.decode(:openai, req, "gpt-6-luna", invalid)
    end
  end

  test "System One checks exact question identities and full score legend" do
    req = fixture("request")
    native = fixture("system-one")

    for invalid <- [
          put_in(native, ["answers", "extra"], %{"type" => "noul", "noul" => 1}),
          put_in(native, ["answers", "strength", "legend", "1"], "changed"),
          update_in(native, ["answers"], &Map.delete(&1, "eligible")),
          put_in(native, ["answers", "eligible"], %{"type" => "refusal"})
        ] do
      assert {:error, :invalid_decision_response} =
               Wire.decode(:system_one, req, "jev-fixture-pinned", invalid)
    end
  end

  test "usage totals and cache partitions are exact safe integers from the selected subset" do
    native = fixture("openai")

    for invalid <- [
          put_in(native, ["usage", "total_tokens"], 112.0),
          put_in(native, ["usage", "input_tokens_details", "cached_tokens"], 101),
          put_in(native, ["usage", "input_tokens_details", "cache_write_tokens"], 81),
          put_in(native, ["usage", "input_tokens_details", "unknown_partition"], 1),
          put_in(native, ["usage", "output_tokens_details"], %{"reasoning_tokens" => 13}),
          put_in(native, ["usage", "output_tokens_details"], %{"reasoning_tokens" => 1.0})
        ] do
      assert {:error, :invalid_decision_response} =
               Wire.decode(:openai, fixture("request"), "gpt-6-luna", invalid)
    end

    unknown = update_in(native, ["usage"], &Map.delete(&1, "input_tokens_details"))
    assert {:ok, _, facts} = Wire.decode(:openai, fixture("request"), "gpt-6-luna", unknown)
    refute Map.has_key?(facts["usage"], "input_tokens_details")
  end

  test "unsupported subsets and missing model do not coerce into another engine request" do
    req = fixture("request")
    assert {:error, _} = Wire.encode(:system_one, req, nil)
    assert {:error, _} = Wire.encode(:openai, req, "jev-fixture-pinned")
    assert {:error, _} = Wire.encode(:unknown, req, "gpt-6-luna")
    long = put_in(req, ["questions", Access.at(2), "levels"], Enum.map(1..11, &"level-#{&1}"))
    assert {:error, _} = Wire.encode(:system_one, long, "jev-fixture-pinned")
    assert {:error, _} = Wire.encode(:openai, long, "gpt-6-luna")
  end
end
