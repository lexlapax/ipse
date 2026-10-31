defmodule Ipse.Extension.Collection.ObservedRead do
  @moduledoc """
  Internal storage observations for a bounded subset of public collection reads.

  The returned result and root witness are read through the same checked
  Collection view. This component grants no Identity, Consent, source,
  eligibility or Session authority: a trusted caller must obtain and retain
  those separately, bind the observation to a committed result, and recheck the
  root before use. An observation is historical as soon as its view is closed.

  Successful `get`, `snapshot`, and visible `scan` results have the same public
  shape and value as the corresponding Collection reads at the witnessed root.
  Stale scan generations refuse instead of returning the generic conflict.
  Their availability differs:
  ReadView refuses legacy root versions 2 and 3 and indexes over its 4 MiB
  encoded-cache bound. Snapshot reads no record values; the native owner still
  checks the exact root before returning its witness. Other operations refuse.
  Scan excludes reserved metadata before reading values. The internal
  `get_record` observation returns only the selected record (or nil), with the
  root witness kept separately; it is not an extension SDK operation and does
  not establish current eligibility.
  """
  alias Ipse.{JSON, Extension.Collection, Session.ManagedReference}

  alias Ipse.Extension.{
    Collection.ManagedPages,
    Collection.ManagedRetention,
    Collection.Migration,
    ManagedRecipe,
    SemanticConsent
  }

  @error {:error, :collection_observation_refused}

  @doc false
  def read(root, namespace, request) do
    with {:ok, read_request, kind} <- select(request),
         {:ok, view} <- Collection.open_view(root, namespace) do
      result =
        try do
          with {:ok, observation} <-
                 Collection.view_read(view, read_request),
               {:ok, value} <- value(kind, observation, request) do
            {:ok,
             %{
               "version" => 1,
               "request_sha256" => JSON.digest([request]),
               "result_sha256" => JSON.digest([value]),
               "value" => value,
               "witness" => observation["witness"]
             }}
          else
            _ -> @error
          end
        rescue
          _ -> @error
        catch
          _, _ -> @error
        end

      case Collection.close_view(view) do
        :ok -> result
        _ -> @error
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  @doc """
  Structurally bind a root observation to a supplied pin.

  The owning host must authenticate the observation and pin before calling this
  function. This does not authenticate the witness or grant live authority.
  """
  def root_dependency(request, observation, pin) do
    with {:ok, _, _} <- select(request),
         true <- SemanticConsent.pin?(pin),
         true <- exact?(observation, ~w(version request_sha256 result_sha256 value witness)),
         true <- observation["version"] === 1,
         true <- observation["request_sha256"] === JSON.digest([request]),
         true <- observation["result_sha256"] === JSON.digest([observation["value"]]),
         {:ok, collection} <- witnessed_root(observation["witness"], pin["namespace"]),
         dependency = %{
           "version" => 3,
           "project_id" => pin["project_id"],
           "namespace" => pin["namespace"],
           "pin_sha256" => JSON.digest([pin]),
           "policy_generation" => pin["epoch"],
           "collection" => collection,
           "subject" => %{
             "kind" => "root_observation",
             "request_sha256" => observation["request_sha256"],
             "result_sha256" => observation["result_sha256"]
           }
         },
         true <- ManagedReference.dependency?(dependency) do
      {:ok, dependency}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Structurally bind a record-only observation; the caller must authenticate every supplied fact."
  def record_dependency(request, observation, pin, validity, publication_policy \\ nil) do
    with {:ok, _, :get_record} <- select(request),
         true <- SemanticConsent.pin?(pin),
         true <- exact?(observation, ~w(version request_sha256 result_sha256 value witness)),
         :ok <- JSON.validate_object(observation),
         true <- observation["version"] === 1,
         true <- observation["request_sha256"] === JSON.digest([request]),
         value = observation["value"],
         true <-
           exact?(value, ["record"]) and observation["result_sha256"] === JSON.digest([value]),
         {:ok, collection} <- witnessed_root(observation["witness"], pin["namespace"]),
         {:ok, record} <- record_identity(value["record"], request["key"], collection),
         true <- if(is_nil(record), do: is_nil(validity), else: is_map(validity)),
         dependency = %{
           "version" => 4,
           "project_id" => pin["project_id"],
           "namespace" => pin["namespace"],
           "pin_sha256" => JSON.digest([pin]),
           "policy_generation" => pin["epoch"],
           "collection" => collection,
           "subject" => %{
             "kind" => "record_observation",
             "key" => request["key"],
             "request_sha256" => observation["request_sha256"],
             "result_sha256" => observation["result_sha256"],
             "publication_policy_sha256" => publication_policy,
             "record" => record,
             "validity" => validity
           }
         },
         true <- ManagedReference.dependency?(dependency) do
      {:ok, dependency}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc """
  Derive a literal-note dependency from a managed observation and verified sources.

  The caller must authenticate the managed observation, selected recipe, pin,
  current source proofs and time. This function checks their consistency; it
  does not obtain current consent, source eligibility or a live root lease.
  """
  def managed_dependency(request, managed, pin, recipe, verified_sources, now) do
    with true <- exact?(managed, ~w(observation metadata)),
         metadata = managed["metadata"],
         true <-
           exact?(
             Map.delete(metadata, "choice"),
             ~w(lineage recipe_sha256 policy_sha256 first_admitted_ms valid_until_ms category)
           ),
         true <- SemanticConsent.pin?(pin) and ManagedRecipe.valid?(recipe),
         true <-
           recipe["kind"] == "literal_source" and
             JSON.digest([recipe]) === metadata["recipe_sha256"],
         true <- JSON.sha256?(metadata["policy_sha256"]) and JSON.safe_uint?(now),
         true <-
           JSON.safe_uint?(metadata["first_admitted_ms"]) and metadata["first_admitted_ms"] <= now,
         true <- valid_deadline?(metadata["valid_until_ms"], metadata["first_admitted_ms"], now),
         observation = managed["observation"],
         value when is_map(value) <- get_in(observation, ["value", "record", "value"]),
         {:ok, candidate} <-
           ManagedRecipe.extract(recipe, request["key"], value, verified_sources),
         true <-
           ManagedRetention.eligible_metadata?(
             candidate,
             JSON.sha256(Migration.encode(value)),
             metadata,
             now
           ),
         [source] <- candidate["sources"],
         validity = %{
           "recipe_sha256" => metadata["recipe_sha256"],
           "lineage" => metadata["lineage"],
           "source_versions" => [
             %{"id" => source["occurrence_id"], "version" => source["version_id"]}
           ],
           "valid_until_ms" => metadata["valid_until_ms"],
           "status" => "eligible",
           "dependencies" => []
         },
         {:ok, dependency} <-
           record_dependency(request, observation, pin, validity, metadata["policy_sha256"]) do
      {:ok, dependency}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp valid_deadline?(nil, _, _), do: true

  defp valid_deadline?(deadline, first, now),
    do: JSON.safe_uint?(deadline) and deadline >= first and deadline > now

  defp deadline_within_recipe?(nil, _, _), do: true

  defp deadline_within_recipe?(age, first, deadline) when is_integer(deadline),
    do: JSON.safe_uint?(first + age) and deadline <= first + age

  defp deadline_within_recipe?(_, _, _), do: false

  @doc """
  Read a literal record and its signed managed metadata at one checked root.

  Call only inside an active ProjectIdentity domain-auth callback selected by
  the trusted host, with the selected literal recipe. Its digest must match the
  signed live page, and its override prefix selects the same-view override key.
  The result authenticates neither current source eligibility
  nor consent, and does not authorize delivery or later use. Embedded proofs
  are checked only for structural consistency with the signed value; they do
  not become authenticated current sources. Missing records,
  pending/history keys, override records and retirement refuse here. Authenticated
  native retention choices select an effective category/deadline independently
  of the original automatic baseline; they grant no source truth or use permission.
  """
  def managed_record(root, namespace, request, cap, catalog, recipe) do
    with {:ok, _, :get_record} <- select(request),
         "note." <> lineage <- request["key"],
         true <- JSON.sha256?(lineage),
         true <- ManagedRecipe.valid?(recipe) and recipe["kind"] == "literal_source",
         true <- request["key"] === recipe["key_prefix"] <> lineage,
         true <-
           is_map(catalog) and catalog["namespace"] === namespace and
             catalog["format"] == "managed-metadata-v3" and catalog["state"] == "active",
         {:ok, view} <- Collection.open_view(root, namespace) do
      result =
        try do
          managed_record_view(view, request, cap, lineage, recipe)
        rescue
          _ -> @error
        catch
          _, _ -> @error
        end

      if Collection.close_view(view) == :ok, do: result, else: @error
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  @doc """
  Observe a pending Knowledge proposal and its signed metadata at one root.

  This verifies historical publication structure, not current consent, source
  eligibility, expiry, operator display or acceptance. Call only inside the
  matching active domain-auth callback; a returned value grants no authority.
  The record's worker-supplied timestamps are not host clock evidence; the
  separate metadata contains the authenticated historical admission deadline.
  """
  def managed_proposal(root, namespace, request, cap, catalog, recipe) do
    with {:ok, _, :get_record} <- select(request),
         "pending." <> id <- request["key"],
         true <- JSON.sha256?(id),
         true <- ManagedRecipe.valid?(recipe) and recipe["kind"] == "proposal",
         true <- recipe["key_prefix"] === "pending.",
         true <-
           is_map(catalog) and catalog["namespace"] === namespace and
             catalog["format"] == "managed-metadata-v3" and catalog["state"] == "active",
         {:ok, view} <- Collection.open_view(root, namespace) do
      result =
        try do
          managed_proposal_view(view, request, cap, recipe, id)
        rescue
          _ -> @error
        catch
          _, _ -> @error
        end

      if Collection.close_view(view) == :ok, do: result, else: @error
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  defp managed_proposal_view(view, request, cap, recipe, id) do
    keys = [request["key"], ManagedPages.format_key()]

    with {:ok, first} <- Collection.view_read(view, %{"op" => "get_many", "keys" => keys}),
         true <- first["keys"] === keys and first["witness"]["root_state"] == "present",
         [record, format] when is_map(record) and is_map(format) <- first["records"],
         {:ok, _} <- ManagedPages.open_format(cap, format),
         value when is_map(value) <- record["value"],
         true <- value["kind"] == "proposal" and value["state"] == "pending",
         true <- value["id"] === id,
         sources when is_list(sources) <- get_in(value, recipe["evidence_path"]),
         {:ok, candidate} <- ManagedRecipe.extract(recipe, request["key"], value, sources),
         true <- candidate["kind"] == "proposal",
         override_key = recipe["override_prefix"] <> candidate["lineage"],
         {:ok, override} <-
           Collection.view_read(view, %{"op" => "get_many", "keys" => [override_key]}),
         true <-
           override["witness"] === first["witness"] and override["summary"] === first["summary"],
         true <- override["keys"] === [override_key],
         [nil] <- override["records"],
         {:ok, live} <-
           managed_row(view, cap, :live, ManagedPages.live_identity(request["key"]), first),
         [
           packed_lineage,
           packed_value,
           packed_recipe,
           packed_policy,
           first_ms,
           deadline_ms,
           category,
           1
         ] <- live,
         true <- unpack_hash(packed_lineage) === candidate["lineage"],
         true <- unpack_hash(packed_recipe) === JSON.digest([recipe]),
         true <- record["sha256"] === unpack_hash(packed_value),
         {:ok, anchor} <- managed_row(view, cap, :anchor, candidate["lineage"], first),
         %{
           "clocks" => [_, _, anchor_first, anchor_deadline],
           "choice" => nil,
           "retirement" => nil
         } <- anchor,
         first_ms = number(first_ms),
         deadline_ms = number(deadline_ms),
         true <- first_ms === anchor_first and deadline_ms === anchor_deadline,
         true <- JSON.safe_uint?(first_ms) and JSON.safe_uint?(deadline_ms),
         true <-
           deadline_ms >= first_ms and
             deadline_within_recipe?(candidate["max_age_ms"], first_ms, deadline_ms),
         true <-
           category in 0..2 and
             candidate["category"] === Enum.at(~w(ordinary preference current), category),
         observation = %{
           "version" => 1,
           "request_sha256" => JSON.digest([request]),
           "result_sha256" => JSON.digest([%{"record" => record}]),
           "value" => %{"record" => record},
           "witness" => first["witness"]
         } do
      {:ok,
       %{
         "observation" => observation,
         "metadata" => %{
           "lineage" => candidate["lineage"],
           "recipe_sha256" => unpack_hash(packed_recipe),
           "policy_sha256" => unpack_hash(packed_policy),
           "first_admitted_ms" => first_ms,
           "valid_until_ms" => deadline_ms,
           "category" => candidate["category"],
           "eligibility" => "never_current"
         }
       }}
    else
      _ -> @error
    end
  end

  defp managed_record_view(view, request, cap, lineage, recipe) do
    keys = [request["key"], ManagedPages.format_key(), recipe["override_prefix"] <> lineage]

    with {:ok, first} <- Collection.view_read(view, %{"op" => "get_many", "keys" => keys}),
         true <- first["keys"] === keys,
         [record, format, nil] <- first["records"],
         true <- is_map(record) and is_map(format),
         true <- first["witness"]["root_state"] == "present",
         {:ok, _} <- ManagedPages.open_format(cap, format),
         {:ok, live} <-
           managed_row(view, cap, :live, ManagedPages.live_identity(request["key"]), first),
         sources when is_list(sources) <- get_in(record["value"], recipe["evidence_path"]),
         {:ok, candidate} <-
           ManagedRecipe.extract(recipe, request["key"], record["value"], sources),
         true <- candidate["kind"] == "literal_source" and candidate["lineage"] === lineage,
         {:ok, anchor} <- managed_row(view, cap, :anchor, lineage, first),
         {:ok, metadata} <- ManagedRetention.metadata(candidate, record["sha256"], anchor, live),
         observation = %{
           "version" => 1,
           "request_sha256" => JSON.digest([request]),
           "result_sha256" => JSON.digest([%{"record" => record}]),
           "value" => %{"record" => record},
           "witness" => first["witness"]
         } do
      {:ok,
       %{
         "observation" => observation,
         "metadata" => metadata
       }}
    else
      _ -> @error
    end
  end

  defp managed_row(view, cap, kind, identity, first) do
    request = %{
      "version" => 1,
      "prefix" => ManagedPages.prefix(kind),
      "fence_bytes" => ManagedPages.width(kind),
      "needle" => identity
    }

    with {:ok, neighbors} <- Collection.view_neighbors(view, request),
         true <-
           neighbors["witness"] === first["witness"] and neighbors["summary"] === first["summary"],
         "initialized" <- neighbors["state"],
         key when is_binary(key) <- get_in(neighbors, ["neighbors", "selected", "key"]),
         {:ok, selected} <- Collection.view_read(view, %{"op" => "get_many", "keys" => [key]}),
         true <-
           selected["witness"] === first["witness"] and selected["summary"] === first["summary"],
         [record] <- selected["records"],
         {:ok, page} <- ManagedPages.open(cap, record, neighbors),
         row when not is_nil(row) <- page.entries[identity] do
      {:ok, row}
    else
      _ -> @error
    end
  end

  defp unpack_hash(value),
    do: value |> Base.url_decode64!(padding: false) |> Base.encode16(case: :lower)

  defp number(nil), do: nil
  defp number(value), do: String.to_integer(value, 36)

  defp witnessed_root(witness, namespace) do
    with true <- exact?(witness, ~w(version root_state root root_sha256 manifest_sha256)),
         true <- witness["version"] === 2 do
      case witness["root_state"] do
        "absent" ->
          if is_nil(witness["root"]) and is_nil(witness["root_sha256"]) and
               is_nil(witness["manifest_sha256"]) do
            {:ok,
             %{
               "project" => namespace,
               "generation" => 0,
               "floor" => 0,
               "floor_anchor" => nil,
               "root_state" => "absent",
               "root_sha256" => nil,
               "manifest_sha256" => nil
             }}
          else
            @error
          end

        "present" ->
          root = witness["root"]

          if exact?(root, ~w(version project generation floor floor_anchor manifest)) and
               root["version"] in [4, 5] and root["project"] === namespace and
               root["manifest"] === witness["manifest_sha256"] and
               JSON.sha256?(witness["root_sha256"]) and JSON.sha256?(witness["manifest_sha256"]) and
               JSON.sha256(Jason.encode!(root)) === witness["root_sha256"] do
            {:ok,
             Map.merge(
               Map.take(root, ~w(project generation floor floor_anchor)),
               Map.take(witness, ~w(root_state root_sha256 manifest_sha256))
             )}
          else
            @error
          end

        _ ->
          @error
      end
    else
      _ -> @error
    end
  end

  defp record_identity(nil, _, _), do: {:ok, nil}

  defp record_identity(record, key, %{"root_state" => "present", "generation" => generation}) do
    with true <- exact?(record, ~w(key revision sha256 bytes operation_id value)),
         true <-
           record["key"] === key and JSON.safe_uint?(record["revision"]) and
             record["revision"] > 0 and record["revision"] <= generation,
         true <-
           is_binary(record["operation_id"]) and
             Regex.match?(~r/\A[0-9a-f]{32}\z/, record["operation_id"]),
         :ok <- JSON.validate_object(record["value"]),
         bytes = Migration.encode(record["value"]),
         true <- byte_size(bytes) === record["bytes"] and JSON.sha256(bytes) === record["sha256"] do
      {:ok, %{"key" => key, "revision" => record["revision"], "value_sha256" => record["sha256"]}}
    else
      _ -> @error
    end
  end

  defp record_identity(_, _, _), do: @error

  defp exact?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)

  defp select(%{"op" => "snapshot"} = request) do
    if Collection.valid_request?(request),
      do: {:ok, %{"op" => "snapshot"}, :snapshot},
      else: @error
  end

  defp select(%{"op" => "get", "key" => key} = request) do
    if Collection.valid_request?(request) and not String.starts_with?(key, "host.validity."),
      do: {:ok, %{"op" => "get_many", "keys" => [key]}, :get},
      else: @error
  end

  defp select(%{"op" => "get_record", "key" => key} = request) do
    get = Map.put(request, "op", "get")

    if Collection.valid_request?(get) and not String.starts_with?(key, "host.validity."),
      do: {:ok, %{"op" => "get_many", "keys" => [key]}, :get_record},
      else: @error
  end

  defp select(
         %{"op" => "scan", "after" => cursor, "limit" => limit, "generation" => generation} =
           request
       ) do
    if Collection.valid_request?(request) and limit in 1..4 and
         (is_nil(cursor) or not String.starts_with?(cursor, "host.validity.")),
       do:
         {:ok,
          %{
            "op" => "visible_scan",
            "after" => cursor,
            "limit" => limit,
            "generation" => generation
          }, :scan},
       else: @error
  end

  defp select(
         %{
           "op" => "index",
           "after" => _,
           "limit" => _,
           "generation" => _,
           "prefix" => _
         } = request
       ) do
    selected = Map.put(request, "op", "visible_index")

    if Ipse.Extension.Collection.Directory.read_request?(selected),
      do: {:ok, selected, :index},
      else: @error
  end

  defp select(
         %{"op" => "index", "cursor" => cursor, "limit" => limit, "prefix" => prefix} = request
       ) do
    if Map.keys(request) |> Enum.sort() == ~w(cursor limit op prefix) and
         (is_nil(cursor) or (is_binary(cursor) and byte_size(cursor) <= 2048)) and
         is_integer(limit) and limit in 1..32 and Ipse.Extension.Collection.Directory.key?(prefix) and
         not String.starts_with?(prefix, "host.validity."),
       do: {:ok, %{"op" => "snapshot"}, :index},
       else: @error
  end

  defp select(_), do: @error

  defp value(
         :snapshot,
         %{"summary" => summary, "keys" => [], "records" => [], "witness" => witness},
         _
       )
       when is_map(summary) and is_map(witness),
       do: {:ok, summary}

  defp value(
         :get,
         %{"summary" => summary, "keys" => [key], "records" => [record], "witness" => witness},
         request
       )
       when is_map(summary) and is_map(witness) do
    if(request["key"] == key, do: {:ok, Map.put(summary, "record", record)}, else: @error)
  end

  defp value(
         :get_record,
         %{"summary" => summary, "keys" => [key], "records" => [record], "witness" => witness},
         request
       )
       when is_map(summary) and is_map(witness) do
    if request["key"] == key, do: {:ok, %{"record" => record}}, else: @error
  end

  defp value(
         :scan,
         %{
           "summary" => summary,
           "keys" => keys,
           "records" => records,
           "next" => next,
           "witness" => witness
         },
         request
       )
       when is_map(summary) and is_map(witness) and is_list(keys) and is_list(records) do
    if summary["generation"] === request["generation"] and length(keys) == length(records) and
         Enum.all?(keys, &(not String.starts_with?(&1, "host.validity."))),
       do: {:ok, Map.merge(summary, %{"records" => records, "next" => next})},
       else: @error
  end

  defp value(
         :index,
         %{"summary" => summary, "records" => records, "next" => next, "count" => count},
         request
       ) do
    if is_nil(request["generation"]) or summary["generation"] == request["generation"],
      do: {:ok, Map.merge(summary, %{"records" => records, "next" => next, "count" => count})},
      else: @error
  end

  defp value(_, _, _), do: @error
end
