defmodule IpseKnowledge.Notes do
  @moduledoc """
  Pure note retention, temporal history and lineage override policy.

  Admission owns source/origin verification. A lineage is the admitted claim and
  evidence identity, not a hash of a model paraphrase. These functions neither
  perform IO nor grant permission. Keep returned overrides when collecting notes;
  the storage adapter advances its import floor before removing any derivative.
  """
  @day 86_400_000
  @ordinary 90 * @day
  @history 365 * @day
  @categories ~w(ordinary pin preference current history)
  @fields ~w(version id lineage text evidence category reason created_at_ms observed_at_ms event_at_ms expires_at_ms superseded_at_ms previous_category metadata_reserve)
  @metadata_reserve String.duplicate("0", 64)
  @attrs ~w(id lineage text evidence category reason observed_at_ms event_at_ms)
  @override ~w(version lineage policy reason updated_at_ms)

  def day_ms, do: @day

  @doc "Construct an admitted note, applying a saved operator override before classification."
  def new(attrs, now, override \\ nil) do
    with true <- keys?(attrs, @attrs) and uint?(now),
         true <- attrs["category"] in ~w(ordinary pin preference current) do
      note =
        Map.merge(attrs, %{
          "version" => 1,
          "created_at_ms" => now,
          "expires_at_ms" => if(attrs["category"] == "ordinary", do: now + @ordinary),
          "superseded_at_ms" => nil,
          "previous_category" => nil,
          "metadata_reserve" => @metadata_reserve
        })

      with true <- valid?(note) do
        if is_nil(override), do: {:ok, note}, else: apply_override(note, override)
      else
        _ -> {:error, :invalid_note}
      end
    else
      _ -> {:error, :invalid_note}
    end
  rescue
    _ -> {:error, :invalid_note}
  end

  @doc "A read is eligibility only and never changes observed time or expiry."
  def eligible?(note, now) do
    valid?(note) and uint?(now) and
      (is_nil(note["expires_at_ms"]) or now < note["expires_at_ms"])
  end

  @doc "Retain superseded temporal support for 365 days; pinned support stays pinned."
  def supersede(old, attrs, now, override \\ nil) do
    with true <- valid?(old) and is_nil(old["superseded_at_ms"]) and uint?(now),
         true <- now >= old["created_at_ms"] and attrs["id"] == old["id"],
         {:ok, replacement} <- new(attrs, now, override) do
      expires =
        case old["category"] do
          "pin" -> nil
          "current" -> now + @history
          "preference" -> now + @ordinary
          _ -> old["expires_at_ms"]
        end

      historical = %{
        old
        | "category" => "history",
          "previous_category" => old["category"],
          "superseded_at_ms" => now,
          "expires_at_ms" => expires,
          "metadata_reserve" => ""
      }

      if valid?(historical),
        do: {:ok, %{"current" => replacement, "history" => historical}},
        else: {:error, :invalid_note}
    else
      {:suppressed, _} = suppressed -> suppressed
      _ -> {:error, :invalid_note}
    end
  rescue
    _ -> {:error, :invalid_note}
  end

  @doc "One-step operator policy changes bind the claim/evidence lineage, including session-only."
  def retention(note, policy, reason, now) do
    override = %{
      "version" => 1,
      "lineage" => note["lineage"],
      "policy" => policy,
      "reason" => reason,
      "updated_at_ms" => now
    }

    with true <- valid?(note) and valid_override?(override),
         result when elem(result, 0) in [:ok, :suppressed] <- apply_override(note, override) do
      {:ok,
       %{
         "note" => if(elem(result, 0) == :ok, do: elem(result, 1)),
         "override" => override,
         "advance_floor" => true,
         "historical_gap" => note["category"] == "history" and policy["kind"] != "pin",
         "shared_evidence" => "retain while another authorized dependent requires it"
       }}
    else
      _ -> {:error, :invalid_retention}
    end
  rescue
    _ -> {:error, :invalid_retention}
  end

  @doc "Forgetting retains only bounded lineage suppression; callers remove selected dependents."
  def forget(note, reason, now), do: retention(note, %{"kind" => "session"}, reason, now)

  def apply_override(note, override) do
    with true <- valid?(note) and valid_override?(override),
         true <- note["lineage"] == override["lineage"] do
      case override["policy"] do
        %{"kind" => "session"} ->
          {:suppressed, override}

        policy ->
          {category, expiry} =
            case policy do
              %{"kind" => "pin"} ->
                {"pin", nil}

              %{"kind" => "ordinary"} ->
                {"ordinary", override["updated_at_ms"] + @ordinary}

              %{"kind" => "duration", "duration_ms" => duration} ->
                {"ordinary", override["updated_at_ms"] + duration}
            end

          # A saved downgrade's deadline is anchored to the operator change,
          # never to a later retrieval, paraphrase or automatic recapture.
          changed = %{
            note
            | "category" => if(is_nil(note["superseded_at_ms"]), do: category, else: "history"),
              "expires_at_ms" => expiry,
              "reason" => "operator override",
              "metadata_reserve" => ""
          }

          if valid?(changed), do: {:ok, changed}, else: {:error, :invalid_retention}
      end
    else
      _ -> {:error, :invalid_retention}
    end
  end

  @doc "Eligible expiry is explicit; override metadata must survive this collection."
  def expired(notes, now) when is_list(notes) do
    if uint?(now) and Enum.all?(notes, &valid?/1) do
      {:ok,
       Enum.filter(notes, fn note ->
         not is_nil(note["expires_at_ms"]) and now >= note["expires_at_ms"]
       end)}
    else
      {:error, :invalid_note}
    end
  end

  @doc "State the retained observation window, including unknown stated event time."
  def coverage(note, now) do
    if valid?(note) and uint?(now) do
      %{
        "available" => eligible?(note, now),
        "observed_at_ms" => note["observed_at_ms"],
        "event_at_ms" => note["event_at_ms"],
        "superseded_at_ms" => note["superseded_at_ms"],
        "expires_at_ms" => note["expires_at_ms"],
        "truth" => "support is an attributed observation, not a current truth guarantee"
      }
    else
      {:error, :invalid_note}
    end
  end

  def valid?(note) do
    keys?(note, @fields) and note["version"] === 1 and hash?(note["id"]) and
      hash?(note["lineage"]) and text?(note["text"], 4096) and is_map(note["evidence"]) and
      note["evidence"] != %{} and note["category"] in @categories and
      text?(note["reason"], 256) and uint?(note["created_at_ms"]) and
      uint?(note["observed_at_ms"]) and nullable_uint?(note["event_at_ms"]) and
      nullable_uint?(note["expires_at_ms"]) and nullable_uint?(note["superseded_at_ms"]) and
      note["metadata_reserve"] in [@metadata_reserve, ""] and
      history?(note) and
      (note["category"] not in ~w(ordinary) or is_integer(note["expires_at_ms"])) and
      (note["category"] not in ~w(pin preference current) or is_nil(note["expires_at_ms"])) and
      json_size?(note, 6144)
  rescue
    _ -> false
  end

  def valid_override?(o) do
    keys?(o, @override) and o["version"] === 1 and hash?(o["lineage"]) and
      text?(o["reason"], 256) and uint?(o["updated_at_ms"]) and policy?(o["policy"]) and
      json_size?(o, 1024)
  rescue
    _ -> false
  end

  defp policy?(%{"kind" => kind} = p) when kind in ~w(pin ordinary session),
    do: keys?(p, ["kind"])

  defp policy?(%{"kind" => "duration"} = p),
    do: keys?(p, ~w(kind duration_ms)) and uint?(p["duration_ms"]) and p["duration_ms"] > 0

  defp policy?(_), do: false

  defp history?(%{"category" => "history"} = n),
    do:
      is_integer(n["superseded_at_ms"]) and n["previous_category"] in (@categories -- ["history"])

  defp history?(n), do: is_nil(n["superseded_at_ms"]) and is_nil(n["previous_category"])
  defp nullable_uint?(x), do: is_nil(x) or uint?(x)
  defp uint?(x), do: is_integer(x) and x in 0..9_007_199_254_740_991
  defp hash?(x), do: is_binary(x) and Regex.match?(~r/\A[a-f0-9]{64}\z/, x)
  defp text?(x, bytes), do: is_binary(x) and String.valid?(x) and byte_size(x) in 1..bytes
  defp keys?(m, fields), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(fields)

  defp json_size?(m, limit) do
    if Ipse.Extension.validate(m) == :ok do
      bytes = IO.iodata_to_binary(JSON.encode!(m))
      byte_size(bytes) <= limit and JSON.decode!(bytes) == m
    else
      false
    end
  end
end
