Code.require_file("../../../extensions/knowledge/src/knowledge/contracts.ex", __DIR__)
Code.require_file("../../../extensions/knowledge/src/notes.ex", __DIR__)
Code.require_file("../../../extensions/knowledge/src/knowledge/records.ex", __DIR__)

defmodule IpseKnowledge.Knowledge.ContractsTest do
  use ExUnit.Case, async: true
  alias IpseKnowledge.Knowledge.Contracts, as: C

  defp proof do
    text = "Acme has owner Alex"

    %{
      "version" => 1,
      "session_id" => String.duplicate("1", 32),
      "occurrence_id" => String.duplicate("2", 32),
      "version_id" => String.duplicate("3", 32),
      "kind" => "input.original",
      "origin" => "interactive_operator",
      "coverage" => "available",
      "path" => nil,
      "start_byte" => 0,
      "end_byte" => byte_size(text),
      "quote" => text,
      "quote_sha256" => Ipse.JSON.sha256(text),
      "content_sha256" => Ipse.JSON.sha256(text),
      "receipt_sha256" => Ipse.JSON.sha256("synthetic contract input")
    }
  end

  test "all sidecar constraints use the supported closed schema subset" do
    sidecar = C.operator()
    assert sidecar["version"] == 1
    assert byte_size(Jason.encode!(sidecar)) <= 65_536
    p = sidecar["publication"]

    for {kind, recipe} <- sidecar["recipes"] do
      assert Ipse.Extension.ManagedRecipe.valid?(recipe)
      assert recipe["constraints_sha256"] == Ipse.JSON.digest([p[kind]])
      assert recipe["key_prefix"] == p[kind]["key_prefix"]
    end

    for constraint <- [p["note"], p["pending"] | Map.values(p["retention"])] do
      assert Ipse.Extension.CollectionPolicy.valid_constraints?(constraint)
      assert constraint["allow_delete"] == false
      assert constraint["evidence_path"] == ["evidence", "sources"]
    end

    assert p["note"]["source_categories"] ==
             Enum.sort(~w(interactive_operator native_operator_answer typed_host_outcome))

    assert p["pending"]["source_categories"] ==
             Enum.sort(
               ~w(interactive_operator native_operator_answer typed_host_outcome unattended_input assistant_proposal)
             )
  end

  test "current capture output fits while pins, histories and unknown fields refuse" do
    r = IpseKnowledge.Knowledge.Records
    p = proof()

    attrs = %{
      "text" => p["quote"],
      "category" => "ordinary",
      "reason" => "selected span",
      "event_at_ms" => nil
    }

    assert {:ok, "note." <> _, note} = apply(r, :capture, [attrs, p, 0])
    assert :ok == Ipse.JSON.validate_arguments(C.note_schema(), note)

    for damaged <- [
          Map.put(note, "permission", true),
          Map.put(note, "category", "pin"),
          Map.put(note, "category", "history"),
          put_in(note, ["evidence", "sources", Access.at(0), "path"], "file.txt"),
          put_in(note, ["evidence", "sources"], [p, p])
        ] do
      assert {:error, _} = Ipse.JSON.validate_arguments(C.note_schema(), damaged)
    end

    weak = %{p | "origin" => "unattended_input"}
    assert {:ok, "pending." <> _, pending} = apply(r, :capture, [attrs, weak, 0])
    assert :ok == Ipse.JSON.validate_arguments(C.proposal_schema(), pending)
  end

  test "each retention choice has an exact independently closed policy" do
    p = proof()

    for kind <- ~w(pin ordinary session duration) do
      policy = %{"kind" => kind}
      policy = if kind == "duration", do: Map.put(policy, "duration_ms", 1), else: policy

      value = %{
        "version" => 1,
        "kind" => "retention_override",
        "lineage" => String.duplicate("a", 64),
        "override" => %{
          "version" => 1,
          "lineage" => String.duplicate("a", 64),
          "policy" => policy,
          "reason" => "operator selection",
          "updated_at_ms" => 0
        },
        "evidence" => %{"sources" => [p]}
      }

      assert :ok == Ipse.JSON.validate_arguments(C.override_schema(kind), value)

      for other <- ~w(pin ordinary session duration) -- [kind] do
        assert {:error, _} = Ipse.JSON.validate_arguments(C.override_schema(other), value)
      end

      damaged = put_in(value, ["override", "policy", "unknown"], true)
      assert {:error, _} = Ipse.JSON.validate_arguments(C.override_schema(kind), damaged)
    end
  end
end
