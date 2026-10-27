Code.require_file("../../dev/knowledge/managed_storage_workload.ex", __DIR__)

defmodule Ipse.Development.ManagedStorageWorkloadTest do
  use ExUnit.Case, async: true
  alias Ipse.Development.ManagedStorageWorkload, as: W
  alias Ipse.Extension.{CollectionPolicy, ManagedRecipe}
  alias Ipse.Session.{Input, SourceIndex}

  test "finite construction uses authentic index handles for explicitly synthetic observations" do
    assert W.limits() == %{
             publications: 1000,
             hard_ms: 480_000,
             soft_ms: 360_000,
             memory: 536_870_912
           }

    for category <- ~w(ordinary preference current) do
      fixture = W.fixture(1, category)
      assert byte_size(fixture.value["text"]) == 1024
      assert byte_size(fixture.value["reason"]) == 256
      assert byte_size(Jason.encode!(fixture.value)) <= 6144

      assert {:ok, %{"proof" => proof}} =
               SourceIndex.resolve_proof(fixture.index, fixture.proof_request)

      assert proof == fixture.proof
      options = W.options(fixture, 4)
      assert :ok == CollectionPolicy.check(options.request, options.constraints, [proof])

      assert {:ok, candidate} =
               ManagedRecipe.extract(options.recipe, fixture.key, fixture.value, [proof])

      assert candidate["category"] == category
      assert options.request["expected_generation"] == 4
      assert options.request["advance_floor"]

      assert {:error, _} =
               SourceIndex.resolve_proof(fixture.index, %{
                 fixture.proof_request
                 | "handle" => "untrusted"
               })
    end

    assert_raise FunctionClauseError, fn -> W.fixture(4001) end
  end

  test "unattended construction is never silently relabeled as operator input" do
    input = Input.received(Ipse.Usage.id(), Ipse.Usage.id(), "fixture", "fixture", nil)
    assert input["origin"] == "unattended_input"
    assert input["observation"] == nil
    assert_raise MatchError, fn -> W.fixture(1, "pin") end
  end

  test "typed outcome control keeps actual metadata text short and ordinary" do
    fixture = W.typed_fixture()
    assert fixture.proof["origin"] == "typed_host_outcome"
    assert fixture.proof["kind"] == "tool.outcome"
    assert fixture.value["category"] == "ordinary"
    assert byte_size(fixture.value["text"]) < 256
    assert fixture.value["text"] == fixture.proof["quote"]
    options = W.options(fixture, 0)
    assert :ok == CollectionPolicy.check(options.request, options.constraints, [fixture.proof])
  end

  test "unsupported operator journeys remain explicit refusal controls" do
    fixture = W.fixture(1)
    options = W.options(fixture, 0)

    witness = %{
      "root" => %{"generation" => 0},
      "recipe_sha256" => Ipse.JSON.digest([options.recipe]),
      "original_request_sha256" => Ipse.JSON.digest([options.request])
    }

    read = fn _ -> {:ok, nil} end
    assert {:ok, _, _} = Ipse.Extension.Collection.Normalizer.normalize(witness, read, options)

    for change <- [
          %{hd(options.request["changes"]) | "expected_revision" => 1},
          %{hd(options.request["changes"]) | "value" => nil}
        ] do
      request = Map.put(options.request, "changes", [change])
      changed = %{options | request: request}
      witness = Map.put(witness, "original_request_sha256", Ipse.JSON.digest([request]))

      assert {:error, :managed_normalization_refused} =
               Ipse.Extension.Collection.Normalizer.normalize(witness, read, changed)
    end

    for category <- ~w(pin history) do
      recipe =
        Map.put(options.recipe, "rules", [
          %{"category" => category, "max_age_ms" => nil, "origins" => ["interactive_operator"]}
        ])

      refute ManagedRecipe.valid?(recipe)
    end
  end
end
