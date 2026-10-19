defmodule Ipse.Extensions.Memory.Records do
  @moduledoc "Explicit note versions, irreversible source suppression and bounded lexical ranking."
  alias Ipse.MCP.Schema
  @safe 9_007_199_254_740_991
  @string %{"type" => "string", "minLength" => 1, "maxLength" => 512}
  @integer %{"type" => "integer", "minimum" => 0, "maximum" => @safe}

  def key(source), do: Ipse.Extensions.Manifest.sha256(source)

  def schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ~w(version state source_sha256 source_generation updated_at_ms),
      "properties" => %{
        "version" => %{"type" => "integer", "enum" => [1, 2]},
        "state" => %{"type" => "string", "enum" => ~w(active suppressed)},
        "source_sha256" => %{"type" => "string", "minLength" => 64, "maxLength" => 64},
        "source_generation" => %{"type" => "integer", "minimum" => 1, "maximum" => @safe},
        "updated_at_ms" => @integer,
        "created_at_ms" => @integer,
        "expires_at_ms" => @integer,
        "source" => @string,
        "provenance" => @string,
        "kind" => %{"type" => "string", "enum" => ~w(task_card project_fact)},
        "title" => %{"type" => "string", "minLength" => 1, "maxLength" => 128},
        "text" => %{"type" => "string", "minLength" => 1, "maxLength" => 2048},
        "derived_from" => %{"type" => "array", "maxItems" => 8, "items" => @string}
      }
    }
  end

  def valid?(note, key) do
    with :ok <- Schema.validate_arguments(schema(), note),
         true <- byte_size(Jason.encode!(note)) <= 8192,
         true <- is_binary(key) and Regex.match?(~r/\A[a-f0-9]{64}\z/, key),
         true <- note["source_sha256"] == key,
         true <- note["version"] in [1, 2],
         true <- Enum.all?(~w(source_generation updated_at_ms), &is_integer(note[&1])) do
      case note["state"] do
        "suppressed" ->
          Enum.sort(Map.keys(note)) ==
            ~w(source_generation source_sha256 state updated_at_ms version)

        "active" ->
          required =
            ~w(created_at_ms expires_at_ms kind provenance source source_generation source_sha256 state text title updated_at_ms version)

          required = if note["version"] == 2, do: ["derived_from" | required], else: required

          Enum.sort(Map.keys(note)) == Enum.sort(required) and key(note["source"]) == key and
            Enum.all?(~w(created_at_ms expires_at_ms), &is_integer(note[&1])) and
            note["created_at_ms"] <= note["updated_at_ms"] and
            note["expires_at_ms"] > note["updated_at_ms"] and
            byte_size(note["text"]) <= 2048 and byte_size(note["source"]) <= 512 and
            byte_size(note["title"]) <= 128 and byte_size(note["provenance"]) <= 512 and
            Enum.all?(Map.get(note, "derived_from", []), &(byte_size(&1) <= 512))
      end
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def build(args, previous, now, retention) do
    ttl = Map.get(args, "ttl_seconds", retention)

    note = %{
      "version" => 2,
      "state" => "active",
      "source_sha256" => key(args["source"]),
      "source" => args["source"],
      "source_generation" => args["source_generation"],
      "provenance" => args["provenance"],
      "kind" => args["kind"],
      "title" => args["title"],
      "text" => args["text"],
      "derived_from" => Map.get(args, "derived_from", []),
      "created_at_ms" => if(previous, do: previous["created_at_ms"], else: now),
      "updated_at_ms" => now,
      "expires_at_ms" => now + ttl * 1000
    }

    cond do
      previous && previous["state"] == "suppressed" ->
        {:error, "source_suppressed"}

      previous && previous["version"] != 2 ->
        {:error, "migration_required"}

      previous && previous["expires_at_ms"] <= now ->
        {:error, "source_expired"}

      previous && args["source_generation"] <= previous["source_generation"] ->
        {:error, "stale_source_generation"}

      ttl > retention or not valid?(note, note["source_sha256"]) ->
        {:error, "invalid_note"}

      true ->
        {:ok, note}
    end
  end

  def suppress(key, generation, now),
    do: %{
      "version" => 2,
      "state" => "suppressed",
      "source_sha256" => key,
      "source_generation" => generation,
      "updated_at_ms" => now
    }

  def visible?(note, now),
    do: note["version"] == 2 and note["state"] == "active" and note["expires_at_ms"] > now

  def import_note(incoming, previous, now, retention) do
    cond do
      previous && previous["state"] == "suppressed" ->
        {:error, "source_suppressed"}

      incoming["state"] == "suppressed" ->
        {:ok, Map.put(incoming, "version", 2)}

      previous && previous["version"] != 2 ->
        {:error, "migration_required"}

      incoming["expires_at_ms"] > now + retention * 1000 ->
        {:error, "retention_exceeded"}

      previous && previous["expires_at_ms"] <= now ->
        {:error, "source_expired"}

      previous && incoming["source_generation"] <= previous["source_generation"] ->
        {:error, "stale_source_generation"}

      true ->
        {:ok, incoming}
    end
  end

  def recall(records, query, limit, now) do
    terms = tokens(query) |> MapSet.new()

    records
    |> Enum.filter(&visible?(&1["value"], now))
    |> Enum.flat_map(fn record ->
      note = record["value"]
      words = tokens(note["title"] <> " " <> note["text"]) |> MapSet.new()
      hits = MapSet.size(MapSet.intersection(terms, words))
      if hits == 0, do: [], else: [{hits / max(MapSet.size(terms), 1), record}]
    end)
    |> Enum.sort_by(fn {score, record} -> {-score, record["key"]} end)
    |> Enum.take(limit)
    |> Enum.map(fn {score, record} ->
      note = record["value"]
      excerpt = note["text"] |> String.graphemes() |> Enum.take(256) |> Enum.join()

      %{
        "key" => record["key"],
        "revision" => record["revision"],
        "score" => score,
        "source" => note["source"],
        "source_generation" => note["source_generation"],
        "title" => note["title"],
        "provenance" => note["provenance"],
        "excerpt" => excerpt,
        "span" => %{"start_byte" => 0, "end_byte" => byte_size(excerpt)},
        "text_sha256" => Ipse.Extensions.Manifest.sha256(note["text"])
      }
    end)
  end

  defp tokens(text), do: Regex.scan(~r/[\p{L}\p{N}_]+/u, String.downcase(text)) |> List.flatten()
end
