defmodule Ipse.Development.ManagedMetadata.Shapes do
  alias Ipse.Development.ManagedMetadata.Codec, as: C
  alias Ipse.JSON
  @safe 9_007_199_254_740_991
  def safe, do: @safe
  def hash(n), do: JSON.sha256(to_string(n))
  def source(n), do: Map.put(proof(), "occurrence_id", binary_part(hash(n), 0, 32))

  def lineage(n) do
    {:ok, lineage} = Ipse.Extension.ManagedRecipe.source_identity(source(n))
    lineage
  end

  def proof do
    quote = String.duplicate("q", 1024)

    %{
      "version" => 1,
      "session_id" => String.duplicate("a", 32),
      "occurrence_id" => String.duplicate("b", 32),
      "version_id" => String.duplicate("c", 32),
      "kind" => "input.operator_answer",
      "origin" => "native_operator_answer",
      "coverage" => "available",
      "path" => nil,
      "start_byte" => @safe - 1024,
      "end_byte" => @safe,
      "quote" => quote,
      "quote_sha256" => JSON.sha256(quote),
      "content_sha256" => hash("content"),
      "receipt_sha256" => hash("receipt")
    }
  end

  def full_choice(lineage) do
    %{
      "version" => 1,
      "kind" => "retention_override",
      "lineage" => lineage,
      "override" => %{
        "version" => 1,
        "lineage" => lineage,
        "policy" => %{"kind" => "duration", "duration_ms" => @safe},
        "reason" => String.duplicate("r", 256),
        "updated_at_ms" => @safe
      },
      "evidence" => %{"sources" => [proof()]}
    }
  end

  def candidate_choice(lineage) do
    %{
      "version" => 1,
      "kind" => "candidate_native_retention_choice",
      "lineage" => lineage,
      "event_id" => String.duplicate("d", 32),
      "display_sha256" => hash("display"),
      "input_sha256" => hash("input"),
      "target_key" => "note." <> lineage,
      "target_value_sha256" => hash("target"),
      "policy" => %{"kind" => "duration", "duration_ms" => @safe},
      "reason" => String.duplicate("r", 256),
      "observed_at_ms" => @safe,
      "authority_ref" => %{
        "session_id" => String.duplicate("e", 32),
        "event_id" => String.duplicate("f", 32),
        "sha256" => hash("future retained receipt")
      }
    }
  end

  def anchor(choice \\ nil),
    do: %{
      "note_first_ms" => @safe,
      "note_deadline_ms" => @safe,
      "pending_first_ms" => @safe,
      "pending_deadline_ms" => @safe,
      "choice" => choice
    }

  def live(n \\ 1, category \\ "ordinary") do
    proof = source(n)
    id = lineage(n)

    value = %{
      "lineage" => id,
      "category" => category,
      "text" => proof["quote"],
      "evidence" => %{"sources" => [proof]}
    }

    record = %{"key" => "note." <> id, "revision" => 1, "value" => value}

    row = %{
      "version" => 3,
      "record_key" => record["key"],
      "lineage" => id,
      "record_value_sha256" => JSON.sha256(C.bytes(value)),
      "recipe_sha256" => hash("recipe"),
      "policy_sha256" => hash("historical policy"),
      "first_admitted_ms" => @safe,
      "valid_until_ms" => @safe,
      "category" => category,
      "eligibility" => if(category == "history", do: "history", else: "current"),
      "sources" => [
        Map.take(
          proof,
          ~w(session_id occurrence_id version_id kind origin content_sha256 receipt_sha256)
        )
      ]
    }

    {row, record}
  end
end
