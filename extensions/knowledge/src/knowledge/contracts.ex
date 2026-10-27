defmodule IpseKnowledge.Knowledge.Contracts do
  @moduledoc """
  Declarative native-note publication shapes for an inert operator sidecar.

  These structural schemas neither authenticate evidence nor enforce temporal
  relationships. Records and Notes own those semantic checks; the host owns
  source authentication, consent, current eligibility and atomic publication.
  Separate retention schemas keep each operator choice closed without extending
  the host's supported JSON Schema subset.
  """
  @safe 9_007_199_254_740_991

  def operator do
    %{
      "version" => 1,
      "domain" => "knowledge",
      "preset" => "native",
      "publication" => %{
        "note" => constraints("note.", note_schema(), strong_origins()),
        "pending" => constraints("pending.", proposal_schema(), all_origins()),
        "retention" =>
          Map.new(~w(pin ordinary session duration), fn kind ->
            {kind,
             constraints(
               "override.",
               override_schema(kind),
               Enum.sort(~w(interactive_operator native_operator_answer))
             )}
          end)
      }
    }
  end

  def note_schema do
    object(%{
      "version" => version(),
      "id" => hash(),
      "lineage" => hash(),
      "text" => text(2048),
      "evidence" => evidence(),
      "category" => enum(~w(ordinary preference current)),
      "reason" => text(256),
      "created_at_ms" => uint(),
      "observed_at_ms" => uint(),
      "event_at_ms" => nullable_uint(),
      "expires_at_ms" => nullable_uint(),
      "superseded_at_ms" => %{"type" => "null"},
      "previous_category" => %{"type" => "null"},
      "metadata_reserve" => enum(["", String.duplicate("0", 64)])
    })
  end

  def proposal_schema do
    object(%{
      "version" => version(),
      "kind" => enum(["proposal"]),
      "id" => hash(),
      "lineage" => hash(),
      "state" => enum(["pending"]),
      "text" => text(2048),
      "assigned_category" => enum(~w(ordinary preference current)),
      "reason" => text(256),
      "event_at_ms" => nullable_uint(),
      "created_at_ms" => uint(),
      "expires_at_ms" => uint(),
      "evidence" => evidence()
    })
  end

  def override_schema(kind) when kind in ~w(pin ordinary session duration) do
    policy =
      if kind == "duration",
        do: object(%{"kind" => enum([kind]), "duration_ms" => Map.put(uint(), "minimum", 1)}),
        else: object(%{"kind" => enum([kind])})

    object(%{
      "version" => version(),
      "kind" => enum(["retention_override"]),
      "lineage" => hash(),
      "override" =>
        object(%{
          "version" => version(),
          "lineage" => hash(),
          "policy" => policy,
          "reason" => text(256),
          "updated_at_ms" => uint()
        }),
      "evidence" => evidence()
    })
  end

  def proof_schema do
    object(%{
      "version" => version(),
      "session_id" => fixed_text(32),
      "occurrence_id" => fixed_text(32),
      "version_id" => fixed_text(32),
      "kind" => enum(~w(input.original input.operator_answer answer.original tool.outcome)),
      "origin" => enum(all_origins()),
      "coverage" => enum(~w(available partial)),
      "path" => %{"type" => "null"},
      "start_byte" => uint(),
      "end_byte" => uint(),
      "quote" => text(1024),
      "quote_sha256" => hash(),
      "content_sha256" => hash(),
      "receipt_sha256" => hash()
    })
  end

  defp constraints(prefix, schema, origins) do
    %{
      "version" => 1,
      "key_prefix" => prefix,
      "value_schema" => schema,
      "evidence_path" => ["evidence", "sources"],
      "source_categories" => origins,
      "allow_delete" => false
    }
  end

  defp evidence do
    object(%{
      "sources" => %{
        "type" => "array",
        "minItems" => 1,
        "maxItems" => 1,
        "items" => proof_schema()
      }
    })
  end

  defp object(properties),
    do: %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => properties |> Map.keys() |> Enum.sort(),
      "properties" => properties
    }

  defp strong_origins,
    do: Enum.sort(~w(interactive_operator native_operator_answer typed_host_outcome))

  defp all_origins,
    do: Enum.sort(strong_origins() ++ ~w(unattended_input assistant_proposal))

  defp uint, do: %{"type" => "integer", "minimum" => 0, "maximum" => @safe}
  defp nullable_uint, do: Map.put(uint(), "type", ["integer", "null"])
  defp version, do: %{"type" => "integer", "enum" => [1]}
  defp enum(values), do: %{"type" => "string", "enum" => values}
  defp text(maximum), do: %{"type" => "string", "minLength" => 1, "maxLength" => maximum}
  defp fixed_text(size), do: %{"type" => "string", "minLength" => size, "maxLength" => size}
  defp hash, do: fixed_text(64)
end
