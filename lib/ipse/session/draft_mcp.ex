defmodule Ipse.Session.DraftMCP do
  @moduledoc false
  alias Ipse.JSON
  @error {:error, :invalid_draft_mcp_catalog}

  def event(session, tools, base_definitions) do
    manifests = tools |> Ipse.MCP.manifests() |> Jason.encode!() |> Jason.decode!()
    definitions = Ipse.MCP.definitions(tools)

    %{
      "type" => "draft_mcp_catalog",
      "version" => 1,
      "session_id" => session,
      "manifests_sha256" => JSON.digest(manifests),
      "definitions" => definitions,
      "base_definitions" => base_definitions,
      "definitions_sha256" => JSON.digest(definitions)
    }
  end

  def restore(events, session) do
    Enum.reduce_while(events, {:ok, nil, nil, nil, nil, nil, MapSet.new()}, fn event,
                                                                               {:ok, catalog,
                                                                                snapshot,
                                                                                reference,
                                                                                draft_id, pending,
                                                                                seen} ->
      case event do
        %{"type" => "mcp_catalog", "version" => 1, "tools" => tools} when is_list(tools) ->
          {:cont, {:ok, tools, snapshot, reference, draft_id, pending, seen}}

        %{"type" => "reference_admitted", "catalog_sha256" => hash} ->
          {:cont, {:ok, catalog, snapshot, hash, draft_id, pending, seen}}

        %{"type" => "draft_started"} ->
          next = event["mcp_snapshot"]

          if is_nil(next) or valid?(next, session || event["session_id"], catalog, reference),
            do:
              {:cont,
               {:ok, catalog, next, reference,
                {event["draft_id"], event["turn_id"], event["session_id"]}, nil, MapSet.new()}},
            else: {:halt, @error}

        %{"type" => "draft_mcp_revalidation_intent"} ->
          if pending == nil and not MapSet.member?(seen, :uncertain) and is_map(snapshot) and
               MapSet.size(seen) < 16 and
               not MapSet.member?(seen, event["revalidation_id"]) and
               Enum.sort(Map.keys(event)) ==
                 ~w(draft_id revalidation_id session_id snapshot_sha256 turn_id type version) and
               event["version"] === 1 and event["session_id"] == snapshot["session_id"] and
               (session == nil or event["session_id"] == session) and
               {event["draft_id"], event["turn_id"], event["session_id"]} == draft_id and
               JSON.sha256?(event["snapshot_sha256"]) and
               event["snapshot_sha256"] == JSON.digest([snapshot]) and
               is_binary(event["revalidation_id"]) and
               Regex.match?(~r/\A[0-9a-f]{32}\z/, event["revalidation_id"]) and
               is_binary(event["turn_id"]) and
               Regex.match?(~r/\A[0-9a-f]{32}\z/, event["turn_id"]),
             do:
               {:cont,
                {:ok, catalog, snapshot, reference, draft_id, event,
                 MapSet.put(seen, event["revalidation_id"])}},
             else: {:halt, @error}

        %{"type" => "draft_mcp_setup_intent"} ->
          if pending == nil and snapshot == nil and not MapSet.member?(seen, :uncertain) and
               MapSet.size(seen) < 16 and not MapSet.member?(seen, event["revalidation_id"]) and
               Enum.sort(Map.keys(event)) ==
                 ~w(draft_id revalidation_id session_id turn_id type version) and
               event["version"] === 1 and (session == nil or event["session_id"] == session) and
               {event["draft_id"], event["turn_id"], event["session_id"]} == draft_id and
               is_binary(event["revalidation_id"]) and
               Regex.match?(~r/\A[0-9a-f]{32}\z/, event["revalidation_id"]),
             do:
               {:cont,
                {:ok, catalog, snapshot, reference, draft_id, event,
                 MapSet.put(seen, event["revalidation_id"])}},
             else: {:halt, @error}

        %{"type" => "draft_mcp_setup_result"} ->
          if is_map(pending) and pending["type"] == "draft_mcp_setup_intent" and
               Enum.sort(Map.keys(event)) == ~w(result revalidation_id session_id type version) and
               event["version"] === 1 and event["session_id"] == pending["session_id"] and
               event["revalidation_id"] == pending["revalidation_id"] and
               event["result"] in ~w(observed unknown),
             do:
               {:cont,
                {:ok, catalog, snapshot, reference, draft_id, nil,
                 MapSet.put(
                   seen,
                   if(event["result"] == "observed", do: :setup_observed, else: :uncertain)
                 )}},
             else: {:halt, @error}

        %{"type" => "draft_mcp_snapshot"} ->
          if snapshot == nil and pending == nil and MapSet.member?(seen, :setup_observed) and
               Enum.sort(Map.keys(event)) == ~w(draft_id session_id snapshot turn_id type version) and
               event["version"] === 1 and
               {event["draft_id"], event["turn_id"], event["session_id"]} == draft_id and
               valid?(event["snapshot"], session || event["session_id"], catalog, reference),
             do:
               {:cont,
                {:ok, catalog, event["snapshot"], reference, draft_id, nil,
                 MapSet.delete(seen, :setup_observed)}},
             else: {:halt, @error}

        %{"type" => "draft_mcp_revalidation_result"} ->
          if is_map(pending) and pending["type"] == "draft_mcp_revalidation_intent" and
               Enum.sort(Map.keys(event)) == ~w(result revalidation_id session_id type version) and
               event["version"] === 1 and event["session_id"] == pending["session_id"] and
               event["revalidation_id"] == pending["revalidation_id"] and
               event["result"] in ~w(matched mismatch failed unknown),
             do:
               {:cont,
                {:ok, catalog, snapshot, reference, draft_id, nil,
                 if(event["result"] != "matched", do: MapSet.put(seen, :uncertain), else: seen)}},
             else: {:halt, @error}

        %{"type" => "draft_completed"} ->
          if pending == nil and not MapSet.member?(seen, :uncertain) and
               not MapSet.member?(seen, :setup_observed),
             do: {:cont, {:ok, catalog, snapshot, reference, nil, nil, seen}},
             else: {:halt, @error}

        %{"type" => type} when type in ["draft_cancelled", "draft_consumed"] ->
          if pending == nil,
            do:
              {:cont,
               {:ok, catalog, nil, reference, nil, nil,
                seen |> MapSet.delete(:uncertain) |> MapSet.delete(:setup_observed)}},
            else: {:halt, @error}

        _ ->
          {:cont, {:ok, catalog, snapshot, reference, draft_id, pending, seen}}
      end
    end)
    |> case do
      {:ok, _, snapshot, _, _, pending, seen} ->
        {:ok,
         %{
           snapshot: snapshot,
           interrupted:
             pending != nil or MapSet.member?(seen, :uncertain) or
               MapSet.member?(seen, :setup_observed),
           pending: pending,
           attempts:
             MapSet.size(seen |> MapSet.delete(:uncertain) |> MapSet.delete(:setup_observed))
         }}

      error ->
        error
    end
  rescue
    _ -> @error
  end

  def valid?(event, session, catalog, reference) do
    definitions = event["definitions"]
    base = event["base_definitions"]

    Enum.sort(Map.keys(event)) ==
      ~w(base_definitions definitions definitions_sha256 manifests_sha256 session_id type version) and
      event["type"] == "draft_mcp_catalog" and event["version"] === 1 and
      event["session_id"] == session and is_list(catalog) and is_list(definitions) and
      is_list(base) and
      JSON.sha256?(reference) and JSON.digest(base ++ definitions) == reference and
      byte_size(Jason.encode!(base)) <= 131_072 and
      length(definitions) == length(catalog) and length(definitions) <= 256 and
      byte_size(Jason.encode!(definitions)) <= 131_072 and
      event["manifests_sha256"] == JSON.digest(catalog) and
      event["definitions_sha256"] == JSON.digest(definitions) and
      Enum.all?(Enum.zip(catalog, definitions), fn {manifest, definition} ->
        is_map(manifest) and is_map(definition) and definition["type"] == "function" and
          get_in(definition, ["function", "name"]) == manifest["tool_id"] and
          is_binary(get_in(definition, ["function", "description"])) and
          is_map(get_in(definition, ["function", "parameters"]))
      end)
  rescue
    _ -> false
  end
end
