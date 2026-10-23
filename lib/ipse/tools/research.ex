defmodule Ipse.Tools.Research do
  @moduledoc "Durable bounded evidence ledger bound to recorded external tool results."
  alias Ipse.Journal
  alias Ipse.JSON, as: Schema
  @source_limit 16
  @claim_limit 32
  @ledger_bytes 65_536
  @names ~w(research_source research_claim research_ledger)

  def names, do: @names
  def empty, do: %{"version" => 1, "sources" => [], "claims" => []}

  def definitions do
    [
      definition(
        "research_source",
        "Capture a literal excerpt and URL from one already recorded, successful MCP tool call. This verifies text provenance only, not truth or whole-page completeness. Metadata is model-reported/unverified. No network request or permissions are granted.",
        source_schema()
      ),
      definition(
        "research_claim",
        "Record a claim linked to captured source IDs. Kind is supported, inference, conflict or open. Host checks references, not semantic truth; unsupported questions must stay open. No effect permission is granted.",
        claim_schema()
      ),
      definition(
        "research_ledger",
        "Read the durable evidence ledger independently of compacted conversation context. No network request or replay.",
        object(%{}, [])
      )
    ]
  end

  def validate(name, args) do
    schema =
      case name do
        "research_source" -> source_schema()
        "research_claim" -> claim_schema()
        "research_ledger" -> object(%{}, [])
      end

    Schema.validate_arguments(schema, args)
  end

  def load(dir, id) do
    with {:ok, events} <- Journal.load(dir, id), do: restore(events)
  end

  def restore(events) do
    Enum.reduce_while(events, {:ok, empty(), []}, fn event, {:ok, ledger, prefix} ->
      case event["type"] do
        "research_source" ->
          with 1 <- event["version"],
               {:ok, expected} <-
                 source(
                   prefix,
                   source_arguments(event["source"]),
                   event["source"]["retrieved_at"]
                 ),
               true <- expected == event["source"],
               {:ok, next} <- add(ledger, "sources", expected) do
            {:cont, {:ok, next, [event | prefix]}}
          else
            _ -> {:halt, {:error, "Invalid recorded research source."}}
          end

        "research_claim" ->
          with 1 <- event["version"],
               {:ok, expected} <- claim(ledger, Map.delete(event["claim"], "id")),
               true <- expected == event["claim"],
               {:ok, next} <- add(ledger, "claims", expected) do
            {:cont, {:ok, next, [event | prefix]}}
          else
            _ -> {:halt, {:error, "Invalid recorded research claim."}}
          end

        _ ->
          {:cont, {:ok, ledger, [event | prefix]}}
      end
    end)
    |> case do
      {:ok, ledger, _} -> {:ok, ledger}
      error -> error
    end
  rescue
    _ -> {:error, "Invalid research ledger."}
  end

  def call(dir, id, name, args) do
    with :ok <- validate(name, args),
         {:ok, events} <- Journal.load(dir, id),
         {:ok, ledger} <- restore(events) do
      case name do
        "research_ledger" ->
          {:ok, Jason.encode!(with_available_results(ledger, events))}

        "research_source" ->
          with {:ok, entry} <- source(events, args, DateTime.utc_now() |> DateTime.to_iso8601()),
               {:ok, _} <- add(ledger, "sources", entry) do
            case Enum.find(ledger["sources"], &(&1["id"] == entry["id"])) do
              nil ->
                {:research_record,
                 %{"type" => "research_source", "version" => 1, "source" => entry},
                 Jason.encode!(entry)}

              existing ->
                {:ok, Jason.encode!(existing)}
            end
          end

        "research_claim" ->
          with {:ok, entry} <- claim(ledger, args),
               {:ok, _} <- add(ledger, "claims", entry) do
            case Enum.find(ledger["claims"], &(&1["id"] == entry["id"])) do
              nil ->
                {:research_record,
                 %{"type" => "research_claim", "version" => 1, "claim" => entry},
                 Jason.encode!(entry)}

              existing ->
                {:ok, Jason.encode!(existing)}
            end
          end
      end
    end
  rescue
    _ -> {:error, "Research record is invalid or exceeds bounds."}
  end

  defp source(events, args, retrieved_at) do
    results =
      Enum.filter(events, fn e ->
        get_in(e, ["message", "role"]) == "tool" and
          get_in(e, ["message", "tool_call_id"]) == args["tool_call_id"]
      end)

    intents =
      Enum.filter(
        events,
        &(&1["type"] == "tool_started" and &1["call_id"] == args["tool_call_id"] and
            Ipse.MCP.external?(&1["name"]))
      )

    with :ok <- validate("research_source", args),
         true <- url?(args["url"]),
         [result] <- results,
         [intent] <- intents,
         %{"status" => "result_recorded"} <- get_in(result, ["message", "ipse_tool_outcome"]),
         text when is_binary(text) <- get_in(result, ["message", "content"]),
         true <- byte_size(text) <= 66_048 and String.valid?(text),
         true <- String.trim(args["excerpt"]) != "" and byte_size(args["excerpt"]) <= 4000,
         true <- String.contains?(text, args["url"]) and String.contains?(text, args["excerpt"]),
         recorded_at = get_in(result, ["message", "ipse_external_result", "recorded_at"]),
         actual_time = recorded_at || retrieved_at,
         {:ok, _, _} <- DateTime.from_iso8601(actual_time) do
      entry = %{
        "url" => args["url"],
        "tool_call_id" => args["tool_call_id"],
        "tool_name" => intent["name"],
        "tool_result_sha256" => digest(text),
        "excerpt" => args["excerpt"],
        "excerpt_sha256" => digest(args["excerpt"]),
        "title" => args["title"],
        "author" => args["author"],
        "published_at" => args["published_at"],
        "metadata_status" => "model_reported_unverified"
      }

      entry =
        if recorded_at,
          do: Map.put(entry, "retrieval_time_basis", "tool_result_recorded"),
          else: entry

      {:ok, Map.merge(entry, %{"id" => identity("s", entry), "retrieved_at" => actual_time})}
    else
      _ ->
        {:error,
         "Source must match one unambiguous, successful recorded MCP result, including literal URL/excerpt. No source was captured."}
    end
  end

  defp source_arguments(entry) do
    Map.take(entry, ~w(tool_call_id url excerpt title author published_at))
  end

  defp with_available_results(ledger, events) do
    intents =
      events
      |> Enum.filter(&(&1["type"] == "tool_started" and Ipse.MCP.external?(&1["name"])))
      |> Enum.group_by(& &1["call_id"])
      |> Map.new(fn {id, rows} -> {id, if(length(rows) == 1, do: hd(rows))} end)

    result_counts =
      events
      |> Enum.filter(&(get_in(&1, ["message", "role"]) == "tool"))
      |> Enum.frequencies_by(&get_in(&1, ["message", "tool_call_id"]))

    events
    |> Enum.reverse()
    |> Enum.filter(fn e ->
      m = e["message"] || %{}

      m["role"] == "tool" and not is_nil(intents[m["tool_call_id"]]) and
        result_counts[m["tool_call_id"]] == 1 and
        get_in(m, ["ipse_tool_outcome", "status"]) == "result_recorded" and
        is_binary(m["content"])
    end)
    |> Enum.take(16)
    |> Enum.reduce(Map.put(ledger, "available_results", []), fn e, acc ->
      m = e["message"]

      ref = %{
        "tool_call_id" => m["tool_call_id"],
        "tool_name" => intents[m["tool_call_id"]]["name"],
        "arguments" => intents[m["tool_call_id"]]["arguments"],
        "result_sha256" => digest(m["content"]),
        "untrusted_preview" => String.slice(m["content"], 0, 160)
      }

      next = Map.update!(acc, "available_results", &(&1 ++ [ref]))
      if byte_size(Jason.encode!(next)) <= 66_048, do: next, else: acc
    end)
  end

  defp claim(ledger, args) do
    with :ok <- validate("research_claim", args),
         true <- String.trim(args["statement"]) != "" and byte_size(args["statement"]) <= 1000,
         ids = args["source_ids"],
         true <- length(ids) == length(Enum.uniq(ids)),
         true <- args["kind"] == "open" or ids != [],
         true <- Enum.all?(ids, fn id -> Enum.any?(ledger["sources"], &(&1["id"] == id)) end) do
      {:ok, Map.put(args, "id", identity("c", args))}
    else
      _ ->
        {:error,
         "Claim references must name captured sources; unsupported claims must remain open. Semantic support still needs review."}
    end
  end

  defp add(ledger, key, entry) do
    existing = Enum.find(ledger[key], &(&1["id"] == entry["id"]))
    limit = if key == "sources", do: @source_limit, else: @claim_limit

    cond do
      existing != nil ->
        {:ok, ledger}

      length(ledger[key]) >= limit ->
        {:error, "Research ledger entry limit reached."}

      true ->
        next = Map.update!(ledger, key, &(&1 ++ [entry]))

        if byte_size(Jason.encode!(next)) <= @ledger_bytes,
          do: {:ok, next},
          else: {:error, "Research ledger byte limit reached."}
    end
  end

  defp source_schema do
    object(
      %{
        "tool_call_id" => string(256),
        "url" => string(2048),
        "excerpt" => string(4000),
        "title" => nullable_string(256),
        "author" => nullable_string(256),
        "published_at" => nullable_string(128)
      },
      ~w(tool_call_id url excerpt)
    )
  end

  defp claim_schema do
    object(
      %{
        "statement" => string(1000),
        "kind" => %{"type" => "string", "enum" => ~w(supported inference conflict open)},
        "source_ids" => %{"type" => "array", "items" => string(64), "maxItems" => 8}
      },
      ~w(statement kind source_ids)
    )
  end

  defp definition(name, description, schema),
    do: %{
      "type" => "function",
      "function" => %{
        "name" => name,
        "description" => description,
        "strict" => false,
        "parameters" => schema
      }
    }

  defp object(properties, required),
    do: %{
      "type" => "object",
      "properties" => properties,
      "required" => required,
      "additionalProperties" => false
    }

  defp string(max), do: %{"type" => "string", "minLength" => 1, "maxLength" => max}
  defp nullable_string(max), do: %{"type" => ["string", "null"], "maxLength" => max}
  defp digest(text), do: :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)

  defp identity(prefix, entry),
    do: prefix <> "_" <> String.slice(Ipse.JSON.digest([entry]), 0, 24)

  defp url?(url) do
    uri = URI.parse(url)

    byte_size(url) <= 2048 and uri.scheme in ["https", "http"] and is_binary(uri.host) and
      uri.host != "" and is_nil(uri.userinfo) and not Regex.match?(~r/[\x00-\x20\x7f]/, url)
  end
end
