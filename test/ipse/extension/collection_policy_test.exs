defmodule Ipse.Extension.CollectionPolicyTest do
  use ExUnit.Case, async: true
  alias Ipse.Extension.CollectionPolicy, as: Policy

  defp object(properties) do
    %{
      "type" => "object",
      "properties" => properties,
      "required" => Map.keys(properties),
      "additionalProperties" => false
    }
  end

  defp proof(origin \\ "interactive_operator"),
    do: %{"origin" => origin, "occurrence_id" => String.duplicate("a", 32)}

  defp constraints do
    receipt =
      object(%{"origin" => %{"type" => "string"}, "occurrence_id" => %{"type" => "string"}})

    %{
      "version" => 1,
      "key_prefix" => "note.",
      "allow_delete" => false,
      "source_categories" => ["interactive_operator", "native_operator_answer"],
      "evidence_path" => ["evidence", "sources"],
      "value_schema" =>
        object(%{
          "text" => %{"type" => "string", "minLength" => 1, "maxLength" => 4096},
          "evidence" =>
            object(%{
              "sources" => %{
                "type" => "array",
                "items" => receipt,
                "minItems" => 1,
                "maxItems" => 8
              }
            })
        })
    }
  end

  defp change(key \\ "note.a", receipts \\ [proof()]),
    do: %{
      "key" => key,
      "expected_revision" => 0,
      "value" => %{"text" => "Attributable observation", "evidence" => %{"sources" => receipts}}
    }

  defp request(changes),
    do: %{
      "op" => "commit",
      "expected_generation" => 0,
      "advance_floor" => false,
      "changes" => changes
    }

  test "reviewed schema and authenticated receipts constrain every change" do
    c = constraints()
    assert Policy.valid_constraints?(c)
    assert :ok = Policy.check(request([change()]), c, [proof()])

    assert {:error, :collection_policy_refused} =
             Policy.check(request([change(), change("pending.b")]), c, [proof()])

    assert {:error, :collection_policy_refused} =
             Policy.check(request([change("note.b", [proof("assistant_proposal")])]), c, [proof()])

    changed = put_in(change(), ["value", "unreviewed"], true)
    assert {:error, :collection_policy_refused} = Policy.check(request([changed]), c, [proof()])
  end

  test "one strong source does not upgrade a mixed batch" do
    mixed = [proof(), proof("unattended_input")]

    assert {:error, :collection_policy_refused} =
             Policy.check(request([change()]), constraints(), mixed)

    assert {:error, :collection_policy_refused} =
             Policy.check(request([change()]), constraints(), [])

    assert {:error, :collection_policy_refused} =
             Policy.check(request([change()]), constraints(), [proof(), proof()])
  end

  test "pending policy uses its own prefix and source categories" do
    c = %{
      constraints()
      | "key_prefix" => "pending.",
        "source_categories" => ["assistant_proposal", "unattended_input"]
    }

    p = proof("assistant_proposal")
    assert :ok = Policy.check(request([change("pending.a", [p])]), c, [p])

    assert {:error, :collection_policy_refused} =
             Policy.check(request([change("note.a", [p])]), c, [p])
  end

  test "deletion permission never bypasses source checks or the storage floor" do
    delete = %{change() | "value" => nil}
    r = %{request([delete]) | "advance_floor" => true}
    assert {:error, :collection_policy_refused} = Policy.check(r, constraints(), [proof()])
    c = %{constraints() | "allow_delete" => true}
    assert :ok = Policy.check(r, c, [proof()])
    assert {:error, :collection_policy_refused} = Policy.check(r, c, [])

    assert {:error, :collection_policy_refused} =
             Policy.check(%{r | "advance_floor" => false}, c, [proof()])
  end

  test "missing, duplicated and substituted evidence refuses" do
    for evidence <- [
          [],
          [proof(), proof()],
          [Map.put(proof(), "occurrence_id", String.duplicate("b", 32))]
        ] do
      assert {:error, :collection_policy_refused} =
               Policy.check(request([change("note.a", evidence)]), constraints(), [proof()])
    end

    absent = put_in(change(), ["value", "evidence"], %{"sources" => nil})

    assert {:error, :collection_policy_refused} =
             Policy.check(request([absent]), constraints(), [proof()])
  end

  test "review cannot admit open schemas, unknown constraints or malformed field paths" do
    c = constraints()
    refute Policy.valid_constraints?(Map.put(c, "worker_override", true))
    refute Policy.valid_constraints?(put_in(c, ["value_schema", "additionalProperties"], true))

    refute Policy.valid_constraints?(
             put_in(c, ["value_schema", "properties", "evidence", "additionalProperties"], true)
           )

    for path <- [[], List.duplicate("evidence", 9), ["evidence.sources"], [nil]] do
      refute Policy.valid_constraints?(%{c | "evidence_path" => path})
    end

    refute Policy.valid_constraints?(%{c | "source_categories" => ["worker_says_verified"]})
  end

  test "a schema matching value is insufficient without resolved host receipts" do
    assert {:error, :collection_policy_refused} =
             Policy.check(request([change()]), constraints(), nil)

    assert {:error, :collection_policy_refused} =
             Policy.check(%{"op" => "snapshot"}, constraints(), [proof()])

    assert {:error, :collection_policy_refused} =
             Policy.check(request([change()]), nil, [proof()])
  end
end
