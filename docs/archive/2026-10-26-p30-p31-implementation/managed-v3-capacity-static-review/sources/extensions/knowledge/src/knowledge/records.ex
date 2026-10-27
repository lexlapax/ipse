defmodule IpseKnowledge.Knowledge.Records do
  @moduledoc "Pure bounded capture records; host source and publication admission remain mandatory."
  alias IpseKnowledge.Notes
  @week 604_800_000
  @safe 9_007_199_254_740_991
  @attrs ~w(text category reason event_at_ms)
  @proof ~w(version session_id occurrence_id version_id kind origin coverage path start_byte end_byte quote quote_sha256 content_sha256 receipt_sha256)
  @strong ~w(interactive_operator native_operator_answer typed_host_outcome)

  def capture(attrs, proof, now, override \\ nil) do
    with true <- keys?(attrs, @attrs) and proof?(proof) and uint?(now),
         true <- text?(attrs["text"], 2048) and text?(attrs["reason"], 256),
         true <- attrs["category"] in ~w(ordinary preference current),
         true <- is_nil(attrs["event_at_ms"]) or uint?(attrs["event_at_ms"]),
         lineage = lineage(proof),
         true <-
           is_nil(override) or
             (Notes.valid_override?(override) and override["lineage"] == lineage) do
      cond do
        not is_nil(override) and override["policy"]["kind"] == "session" ->
          {:suppressed, override}

        true ->
          note = %{
            "id" => lineage,
            "lineage" => lineage,
            "text" => attrs["text"],
            "evidence" => %{"sources" => [proof]},
            "category" => attrs["category"],
            "reason" => attrs["reason"],
            "observed_at_ms" => now,
            "event_at_ms" => attrs["event_at_ms"]
          }

          with {:ok, value} <- Notes.new(note, now, override),
               true <- Notes.eligible?(value, now) do
            if direct?(attrs, proof) do
              {:ok, "note." <> lineage, value}
            else
              # Classification cannot extend a saved operator deadline. This
              # temporary note applies the shared retention policy before either
              # durable-note or pending-proposal construction.
              attrs =
                if value["category"] == "pin",
                  do: attrs,
                  else: Map.put(attrs, "category", value["category"])

              proposal(attrs, proof, lineage, now, value["expires_at_ms"])
            end
          else
            false -> {:skipped, :expired_lineage}
            error -> error
          end
      end
    else
      _ -> {:error, :invalid_capture}
    end
  rescue
    _ -> {:error, :invalid_capture}
  end

  @doc "Claim/evidence lineage is independent of the model's paraphrase and retention choice."
  def lineage(proof) do
    proof
    |> Map.take(
      ~w(session_id occurrence_id version_id start_byte end_byte quote_sha256 content_sha256)
    )
    |> canonical_hash()
  end

  def direct?(attrs, proof) do
    proof["origin"] in @strong and attrs["text"] == proof["quote"] and
      (proof["origin"] != "typed_host_outcome" or attrs["category"] == "ordinary")
  end

  @doc "Wrap retention metadata with its separate operator evidence for constrained publication."
  def override_record(override, proof) do
    if Notes.valid_override?(override) and proof?(proof) and
         proof["origin"] in ~w(interactive_operator native_operator_answer) do
      value = %{
        "version" => 1,
        "kind" => "retention_override",
        "lineage" => override["lineage"],
        "override" => override,
        "evidence" => %{"sources" => [proof]}
      }

      if bounded?(value, 4096), do: {:ok, value}, else: {:error, :capture_capacity}
    else
      {:error, :invalid_retention_evidence}
    end
  end

  @doc "Validate stored override metadata without promoting its proof-shaped JSON into authority."
  def saved_override(nil, _lineage), do: {:ok, nil}

  def saved_override(value, lineage) do
    with true <- keys?(value, ~w(version kind lineage override evidence)),
         true <- value["version"] === 1 and value["kind"] == "retention_override",
         true <- value["lineage"] == lineage and value["override"]["lineage"] == lineage,
         true <- Notes.valid_override?(value["override"]),
         true <- keys?(value["evidence"], ["sources"]),
         [proof] <- value["evidence"]["sources"],
         true <-
           proof?(proof) and proof["origin"] in ~w(interactive_operator native_operator_answer),
         true <- bounded?(value, 4096) do
      {:ok, value["override"]}
    else
      _ -> {:error, :invalid_saved_override}
    end
  rescue
    _ -> {:error, :invalid_saved_override}
  end

  defp proposal(attrs, proof, lineage, now, policy_expiry) do
    expires = if is_nil(policy_expiry), do: now + @week, else: min(now + @week, policy_expiry)

    value = %{
      "version" => 1,
      "kind" => "proposal",
      "id" => canonical_hash(%{"lineage" => lineage, "text" => attrs["text"]}),
      "lineage" => lineage,
      "state" => "pending",
      "text" => attrs["text"],
      "assigned_category" => attrs["category"],
      "reason" => attrs["reason"],
      "event_at_ms" => attrs["event_at_ms"],
      "created_at_ms" => now,
      "expires_at_ms" => expires,
      "evidence" => %{"sources" => [proof]}
    }

    if uint?(value["expires_at_ms"]) and bounded?(value, 4096),
      do: {:ok, "pending." <> value["id"], value},
      else: {:error, :capture_capacity}
  end

  def proof?(proof) do
    keys?(proof, @proof) and proof["version"] === 1 and
      Enum.all?(~w(session_id occurrence_id version_id), &id?(proof[&1])) and
      proof["kind"] in ~w(input.original input.operator_answer answer.original tool.outcome) and
      proof["origin"] in (@strong ++ ~w(unattended_input assistant_proposal)) and
      proof["coverage"] in ~w(available partial) and is_nil(proof["path"]) and
      uint?(proof["start_byte"]) and uint?(proof["end_byte"]) and
      text?(proof["quote"], 1024) and
      proof["end_byte"] - proof["start_byte"] == byte_size(proof["quote"]) and
      proof["quote_sha256"] == hash(proof["quote"]) and
      Enum.all?(~w(content_sha256 receipt_sha256), &sha?(proof[&1])) and
      origin_kind?(proof) and bounded?(proof, 2048)
  rescue
    _ -> false
  end

  defp origin_kind?(%{"kind" => "input.original", "origin" => origin}),
    do: origin in ~w(interactive_operator unattended_input)

  defp origin_kind?(%{"kind" => "input.operator_answer", "origin" => "native_operator_answer"}),
    do: true

  defp origin_kind?(%{"kind" => "answer.original", "origin" => "assistant_proposal"}), do: true
  defp origin_kind?(%{"kind" => "tool.outcome", "origin" => "typed_host_outcome"}), do: true
  defp origin_kind?(_), do: false

  defp canonical_hash(value) do
    value
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {key, item} -> [key, item] end)
    |> JSON.encode!()
    |> IO.iodata_to_binary()
    |> hash()
  end

  defp hash(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)
  defp sha?(v), do: is_binary(v) and Regex.match?(~r/\A[0-9a-f]{64}\z/, v)
  defp id?(v), do: is_binary(v) and Regex.match?(~r/\A[0-9a-f]{32}\z/, v)
  defp uint?(v), do: is_integer(v) and v in 0..@safe
  defp text?(v, n), do: is_binary(v) and String.valid?(v) and byte_size(v) in 1..n
  defp keys?(m, keys), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(keys)

  defp bounded?(value, bytes) do
    Ipse.Extension.validate(value) == :ok and
      byte_size(IO.iodata_to_binary(JSON.encode!(value))) <= bytes
  end
end
