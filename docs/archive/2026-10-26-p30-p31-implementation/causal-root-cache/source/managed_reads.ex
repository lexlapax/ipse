defmodule Ipse.Session.ManagedReads do
  @moduledoc """
  Host-owned read receipts and complete per-invocation dependency unions.

  A prepared receipt is volatile until the owning Session commits its exact
  action result. Replay checks the receipt against that chronological result;
  neither a worker result nor a restored receipt grants current eligibility.
  """
  alias Ipse.{JSON, Extension.CollectionCall}
  alias Ipse.Session.ManagedReference
  @layout "managed_reads_v1"
  @event_type "managed_read_observed"
  @keys ~w(type version session_id parent_invocation_id operation_id request_sha256 result_sha256 dependencies dependencies_sha256)
  @error {:error, :managed_read_refused}

  def layout, do: @layout

  @doc false
  def marker(metadata) when is_map(metadata) do
    case Map.fetch(metadata, "managed_read_layout") do
      :error -> {:ok, nil}
      {:ok, @layout} -> {:ok, @layout}
      _ -> @error
    end
  end

  def marker(_), do: @error

  @doc false
  def prepare(session, intent, value, dependencies) do
    with {:ok, dependencies} <- ManagedReference.union([dependencies]),
         true <- length(dependencies) in 1..8,
         event = %{
           "type" => @event_type,
           "version" => 1,
           "session_id" => session,
           "parent_invocation_id" => intent["parent_invocation_id"],
           "operation_id" => intent["operation_id"],
           "request_sha256" => intent["request_sha256"],
           "result_sha256" => JSON.digest([value]),
           "dependencies" => dependencies,
           "dependencies_sha256" => JSON.digest([dependencies])
         },
         true <- valid?(event, session, intent, value) do
      {:ok, event}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc false
  def valid?(event, session, intent, value) do
    valid_observation?(event, session, intent) and
      CollectionCall.valid_outcome?(intent["request"], "ok", value, nil) and
      event["result_sha256"] == JSON.digest([value]) and
      Enum.all?(event["dependencies"], &bound?(&1, intent, value))
  rescue
    _ -> false
  end

  def valid_observation?(event, session, intent) do
    is_map(event) and Enum.sort(Map.keys(event)) == Enum.sort(@keys) and
      CollectionCall.operation?(intent["request"]) and
      intent["request"]["request"]["op"] in ~w(get scan snapshot index) and
      event["type"] == @event_type and event["version"] === 1 and event["session_id"] === session and
      event["operation_id"] === intent["operation_id"] and
      event["parent_invocation_id"] === intent["parent_invocation_id"] and
      event["request_sha256"] === intent["request_sha256"] and
      JSON.sha256?(event["result_sha256"]) and
      is_list(event["dependencies"]) and length(event["dependencies"]) in 1..8 and
      ManagedReference.union([event["dependencies"]]) == {:ok, event["dependencies"]} and
      event["dependencies_sha256"] == JSON.digest([event["dependencies"]]) and
      byte_size(Jason.encode!(event)) <= 65_536
  rescue
    _ -> false
  end

  defp bound?(dependency, intent, value) do
    pin = intent["effect_binding"]["pin"]
    root = dependency["collection"]
    subject = dependency["subject"]

    ManagedReference.dependency?(dependency) and
      dependency["project_id"] == pin["project_id"] and
      dependency["namespace"] == pin["namespace"] and
      dependency["pin_sha256"] == JSON.digest([pin]) and
      dependency["policy_generation"] === pin["epoch"] and
      Enum.all?(~w(project generation floor floor_anchor), &(root[&1] === value[&1])) and
      case dependency["version"] do
        3 ->
          subject["request_sha256"] == JSON.digest([intent["request"]["request"]]) and
            subject["result_sha256"] == JSON.digest([value])

        4 ->
          record_bound?(subject, value)

        _ ->
          false
      end
  end

  @doc false
  def root_prerequisite?(dependency, event, binding, generation) do
    request = event["request"]
    value = event["outcome"]["value"]
    inner = request["request"]

    dependency["version"] === 3 and
      dependency["namespace"] === binding["namespace"] and
      dependency["collection"]["generation"] === generation and
      event["type"] == "extension_action_result" and event["outcome"]["status"] == "ok" and
      event["namespace"] === binding["namespace"] and
      event["effect_binding"]["pin"] === binding["pin"] and
      request["op"] == "collection.call" and
      (inner == %{"op" => "snapshot"} or
         (inner["op"] == "get" and Map.has_key?(value, "record") and value["record"] === nil) or
         (inner["op"] == "index" and inner["cursor"] === nil and
            value["coverage"] === "metadata_only" and value["count"] === 0 and
            value["records"] === [] and value["next"] === nil)) and
      CollectionCall.valid_outcome?(request, "ok", value, event["operation_id"]) and
      CollectionCall.bound_outcome?(event) and
      bound?(dependency, event, value)
  rescue
    _ -> false
  end

  @doc false
  def cached_root_prerequisite?(dependency, cache, binding, generation) do
    pin = binding["pin"]

    ManagedReference.dependency?(dependency) and dependency["version"] === 3 and
      dependency["project_id"] === pin["project_id"] and
      dependency["namespace"] === binding["namespace"] and
      dependency["namespace"] === pin["namespace"] and
      dependency["pin_sha256"] === JSON.digest([pin]) and
      dependency["policy_generation"] === pin["epoch"] and
      dependency["collection"]["generation"] === generation and
      Map.get(cache, JSON.digest([dependency])) === true
  rescue
    _ -> false
  end

  defp record_bound?(subject, value) do
    records =
      if Map.has_key?(value, "records"), do: value["records"], else: List.wrap(value["record"])

    case Enum.filter(records, &(&1["key"] == subject["key"])) do
      [record] ->
        subject["record"] === %{
          "key" => record["key"],
          "revision" => record["revision"],
          "value_sha256" => record["sha256"]
        } and
          subject["result_sha256"] == JSON.digest([%{"record" => record}]) and
          is_map(subject["validity"]) and subject["validity"]["status"] == "eligible"

      _ ->
        false
    end
  end

  @doc false
  def bind_result(session, config, parent, prepared, reads, event) do
    intent = Ipse.Extension.Actions.result_intent(event)

    needed =
      config[:managed_read_layout] == @layout and
        managed_mapping?(config[:semantic_admission], parent, intent)

    case event["outcome"] do
      %{"status" => "ok", "value" => value} when not is_nil(prepared) ->
        with true <- valid?(prepared, session, intent, value),
             true <-
               covered?(
                 config[:semantic_admission],
                 parent,
                 intent,
                 value,
                 prepared["dependencies"]
               ),
             {:ok, dependencies} <-
               ManagedReference.union([reads, prepared["dependencies"]]) do
          {:ok, prepared, dependencies}
        else
          _ -> @error
        end

      %{"status" => "ok"} when needed ->
        @error

      _ ->
        {:ok, nil, reads}
    end
  rescue
    _ -> @error
  end

  @doc false
  def managed_mapping?(admission, parent, intent) do
    CollectionCall.operation?(intent["request"]) and
      intent["request"]["request"]["op"] in ~w(get scan snapshot index) and
      Enum.any?(get_in(admission, ["policy", "settings", "effects"]) || [], fn mapping ->
        mapping["class"] == "collection.read" and mapping["inner_op"] == "collection.call" and
          is_list(mapping["managed_read"]) and
          mapping["outer_sha256"] == JSON.digest([parent["descriptor"]])
      end)
  rescue
    _ -> false
  end

  @doc false
  def covered?(admission, parent, intent, value, dependencies) do
    settings = get_in(admission, ["policy", "settings"])

    with [mapping] <-
           Enum.filter(settings["effects"], fn mapping ->
             mapping["class"] == "collection.read" and mapping["inner_op"] == "collection.call" and
               mapping["outer_sha256"] == JSON.digest([parent["descriptor"]])
           end),
         {:ok, recipes} <- Ipse.Extension.SemanticConsent.managed_recipes(settings, mapping),
         records =
           if(intent["request"]["request"]["op"] == "index",
             do: [],
             else:
               if(Map.has_key?(value, "records"),
                 do: value["records"],
                 else: List.wrap(value["record"])
               )
           ),
         {:ok, literal_keys} <- literal_keys(records, recipes, dependencies),
         roots = Enum.count(dependencies, &(&1["version"] == 3)),
         true <-
           roots ==
             if(intent["request"]["request"]["op"] == "scan" or literal_keys == [],
               do: 1,
               else: 0
             ),
         true <- length(dependencies) == roots + length(literal_keys) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp literal_keys(records, recipes, dependencies) do
    Enum.reduce_while(records, {:ok, []}, fn record, {:ok, keys} ->
      case Enum.filter(
             recipes,
             &(&1["kind"] == "literal_source" and
                 String.starts_with?(record["key"], &1["key_prefix"]))
           ) do
        [] ->
          {:cont, {:ok, keys}}

        [recipe] ->
          proofs =
            Enum.reduce(recipe["evidence_path"], record["value"], fn key, value ->
              if is_map(value), do: value[key], else: nil
            end)

          matching =
            Enum.filter(
              dependencies,
              &(&1["version"] == 4 and &1["subject"]["key"] == record["key"])
            )

          with [dependency] <- matching,
               {:ok, candidate} <-
                 Ipse.Extension.ManagedRecipe.extract(
                   recipe,
                   record["key"],
                   record["value"],
                   proofs
                 ),
               validity = dependency["subject"]["validity"],
               true <-
                 validity["recipe_sha256"] == JSON.digest([recipe]) and
                   validity["lineage"] == candidate["lineage"],
               true <-
                 validity["source_versions"] ==
                   Enum.map(
                     candidate["sources"],
                     &%{"id" => &1["occurrence_id"], "version" => &1["version_id"]}
                   ) do
            {:cont, {:ok, keys ++ [record["key"]]}}
          else
            _ -> {:halt, @error}
          end

        _ ->
          {:halt, @error}
      end
    end)
  end
end
