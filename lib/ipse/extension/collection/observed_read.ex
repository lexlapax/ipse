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
         {:ok, collection} <- root_identity(observation["witness"], pin["namespace"]),
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
         {:ok, collection} <- root_identity(observation["witness"], pin["namespace"]),
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

  @doc """
  Bind a trusted signed historical observation to a distinct history dependency.

  The owning caller must authenticate the observation and hold the actual
  source and current-use policy leases. This consistency check grants no use
  authority. A successor edge is bound by key and hash; successor bytes need
  not remain present and are not authorized by this dependency.
  """
  def history_dependency(request, managed, pin, recipe, verified_sources, now) do
    with true <- exact?(managed, ~w(observation metadata successor_storage)),
         true <- managed["successor_storage"] in ~w(matching_record unavailable),
         metadata = managed["metadata"],
         true <-
           exact?(
             metadata,
             ~w(lineage recipe_sha256 policy_sha256 first_admitted_ms valid_until_ms category previous_category superseded_at_ms choice successor)
           ),
         true <- SemanticConsent.pin?(pin) and ManagedRecipe.valid?(recipe),
         true <-
           recipe["kind"] == "literal_source" and
             JSON.digest([recipe]) === metadata["recipe_sha256"],
         true <- JSON.sha256?(metadata["policy_sha256"]),
         true <- ManagedRetention.eligible_history_metadata?(metadata, now),
         value when is_map(value) <- get_in(managed, ["observation", "value", "record", "value"]),
         {:ok, candidate} <-
           ManagedRecipe.extract(recipe, request["key"], value, verified_sources),
         true <- candidate["lineage"] === metadata["lineage"],
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
         {:ok, current_shape} <-
           record_dependency(
             request,
             managed["observation"],
             pin,
             validity,
             metadata["policy_sha256"]
           ),
         subject =
           current_shape["subject"]
           |> Map.put("kind", "historical_record_observation")
           |> Map.put("successor", metadata["successor"])
           |> Map.put("superseded_at_ms", metadata["superseded_at_ms"]),
         dependency = current_shape |> Map.put("version", 5) |> Map.put("subject", subject),
         true <- ManagedReference.dependency?(dependency) do
      {:ok, dependency}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc """
  Bind an already authenticated accepted observation to a distinct dependency.

  This pure consistency check does not authenticate the journal, source,
  policy, signed rows or native owners. The caller must hold and verify them;
  the resulting historical reference never authorizes a later use by itself.
  """
  def accepted_dependency(event, observed, pin, recipe, verified_source, now) do
    alias Ipse.Session.PendingAcceptance

    with true <- PendingAcceptance.valid_event?(event),
         true <- exact?(observed, ~w(record link metadata witness)),
         true <-
           SemanticConsent.pin?(pin) and ManagedRecipe.valid?(recipe) and
             recipe["kind"] === "literal_source",
         true <- pin["project_id"] === event["facts"]["project_id"],
         true <- pin["namespace"] === event["facts"]["namespace"],
         true <- verified_source === event["facts"]["source_proof"],
         true <- JSON.safe_uint?(now),
         metadata = observed["metadata"],
         record = observed["record"],
         link = observed["link"],
         {:ok, values} <-
           PendingAcceptance.accepted_values(event, record["value"]["valid_until_ms"]),
         true <- record["key"] === values["note_key"] and record["value"] === values["note"],
         true <-
           record["sha256"] === values["note_sha256"] and
             record["bytes"] === byte_size(Migration.encode(values["note"])) and
             record["operation_id"] === event["facts"]["operation_id"],
         true <- link["key"] === values["link_key"] and link["value"] === values["link"],
         true <-
           link["sha256"] === values["link_sha256"] and
             link["bytes"] === byte_size(Migration.encode(values["link"])) and
             link["operation_id"] === event["facts"]["operation_id"] and
             link["revision"] === record["revision"],
         true <- metadata["lineage"] === values["note"]["lineage"],
         true <- metadata["recipe_sha256"] === JSON.digest([recipe]),
         true <- metadata["policy_sha256"] === event["facts"]["policy_sha256"],
         true <- metadata["acceptance_event_sha256"] === JSON.digest([event]),
         true <- metadata["source_proof"] === verified_source,
         true <- PendingAcceptance.accepted_retention_metadata?(event, metadata, now),
         true <-
           is_nil(metadata["choice"]) or metadata["record_value_sha256"] === record["sha256"],
         true <-
           JSON.safe_uint?(metadata["first_admitted_ms"]) and metadata["first_admitted_ms"] <= now,
         true <- valid_deadline?(metadata["valid_until_ms"], metadata["first_admitted_ms"], now),
         link_identity = %{
           "key" => link["key"],
           "revision" => link["revision"],
           "value_sha256" => link["sha256"]
         },
         validity = %{
           "recipe_sha256" => metadata["recipe_sha256"],
           "lineage" => metadata["lineage"],
           "source_versions" => [
             %{
               "id" => verified_source["occurrence_id"],
               "version" => verified_source["version_id"]
             }
           ],
           "valid_until_ms" => metadata["valid_until_ms"],
           "status" => "eligible",
           "dependencies" => [link_identity]
         },
         request = %{"op" => "get_record", "key" => record["key"]},
         value = %{"record" => record},
         observation = %{
           "version" => 1,
           "request_sha256" => JSON.digest([request]),
           "result_sha256" => JSON.digest([value]),
           "value" => value,
           "witness" => observed["witness"]
         },
         {:ok, base} <-
           record_dependency(request, observation, pin, validity, metadata["policy_sha256"]),
         acceptance = %{
           "journal_id" => values["link"]["journal_id"],
           "journal_kind" => values["link"]["journal_kind"],
           "event_sha256" => metadata["acceptance_event_sha256"],
           "link" => link_identity
         },
         acceptance =
           if(is_nil(metadata["choice"]),
             do: acceptance,
             else:
               Map.put(acceptance, "retention", %{
                 "version" => 1,
                 "kind" => "native_retention_choice",
                 "choice_sha256" => JSON.digest([metadata["choice"]]),
                 "policy" => metadata["choice"]["policy"],
                 "observed_at_ms" => metadata["choice"]["observed_at_ms"]
               })
           ),
         subject =
           base["subject"]
           |> Map.put("kind", "accepted_decision_observation")
           |> Map.put("acceptance", acceptance),
         dependency = base |> Map.put("version", 6) |> Map.put("subject", subject),
         true <- ManagedReference.dependency?(dependency) do
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
  Authenticate one stored literal while retaining its Collection owner.

  Call inside the actual matching Identity/domain-auth and management Consent
  callbacks. The trusted continuation receives the same signed historical
  observation as managed_record/6 while its Collection lock is still held.
  It grants no current-source, consent, display or publication authority.
  Native display still requires the separate complete owner/closure protocol.
  """
  def with_managed_record(root, namespace, request, cap, catalog, recipe, fun)
      when is_function(fun, 1),
      do: with_management_record(root, namespace, request, cap, catalog, recipe, fun, false)

  def with_managed_record(_, _, _, _, _, _, _), do: @error

  @doc """
  Retain an exact signed literal or accepted-decision target for native management.

  Accepted decisions require their distinct signed tag and same-root immutable
  link. This historical target route grants neither current-use eligibility nor
  source/review authority. The owning host must derive the distinct forgetting,
  retention or expiry facts and use that operation's actual publication boundary.
  This route supplies no supersession or current-use authority.
  """
  def with_managed_note_record(root, namespace, request, cap, catalog, recipe, fun)
      when is_function(fun, 1),
      do: with_management_record(root, namespace, request, cap, catalog, recipe, fun, true)

  def with_managed_note_record(_, _, _, _, _, _, _), do: @error

  defp with_management_record(root, namespace, request, cap, catalog, recipe, fun, accepted?)
       when is_function(fun, 1) do
    with {:ok, _, :get_record} <- select(request),
         "note." <> lineage <- request["key"],
         true <- JSON.sha256?(lineage),
         true <- ManagedRecipe.valid?(recipe) and recipe["kind"] == "literal_source",
         true <- request["key"] === recipe["key_prefix"] <> lineage,
         true <-
           is_map(catalog) and catalog["namespace"] === namespace and
             catalog["format"] == "managed-metadata-v3" and catalog["state"] == "active" do
      Collection.with_managed_read(root, namespace, fn witness, read ->
        values = fn selected -> held_values(witness, read, selected) end
        neighbors = fn selected -> read.(%{"op" => "neighbors", "request" => selected}) end

        with {:ok, observation} <-
               managed_record_read(values, neighbors, request, cap, lineage, recipe, accepted?),
             do: fun.(observation)
      end)
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  @doc """
  Check one accepted note, link and signed rows under the held Collection owner.

  The caller must authenticate the supplied journal event and retain current
  source and policy authority separately. This observation grants no use or
  disclosure authority and becomes historical when the callback returns.
  """
  def with_accepted_decision(root, namespace, event, cap, catalog, recipe, now, fun)
      when is_function(fun, 1) do
    alias Ipse.Session.PendingAcceptance

    with true <-
           PendingAcceptance.valid_event?(event) and event["facts"]["namespace"] === namespace,
         true <- ManagedRecipe.valid?(recipe) and recipe["kind"] === "literal_source",
         true <- JSON.safe_uint?(now),
         true <-
           is_map(catalog) and catalog["namespace"] === namespace and
             catalog["format"] === "managed-metadata-v3" and catalog["state"] === "active" do
      facts = event["facts"]

      lineage =
        JSON.digest([
          "ipse-knowledge",
          1,
          "accepted_decision",
          facts["candidate_id"],
          facts["lineage"]
        ])

      note_key = "note." <> lineage
      link_key = "accept." <> facts["candidate_id"]

      Collection.with_managed_read(root, namespace, fn witness, read ->
        values = fn selected -> held_values(witness, read, selected) end
        neighbors = fn selected -> read.(%{"op" => "neighbors", "request" => selected}) end

        keys = [
          note_key,
          link_key,
          ManagedPages.format_key(),
          recipe["override_prefix"] <> lineage
        ]

        with {:ok, first} <- values.(%{"op" => "get_many", "keys" => keys}),
             [record, link, format, nil] <- first["records"],
             true <- is_map(record) and is_map(link) and is_map(format),
             {:ok, _} <- ManagedPages.open_format(cap, format),
             {:ok, live} <-
               managed_row_read(
                 values,
                 neighbors,
                 cap,
                 :live,
                 ManagedPages.live_identity(note_key),
                 first
               ),
             {:ok, anchor} <- managed_row_read(values, neighbors, cap, :anchor, lineage, first),
             {:ok, metadata} <-
               PendingAcceptance.stored_decision_metadata(
                 event,
                 recipe,
                 record,
                 link,
                 anchor,
                 live,
                 now
               ) do
          fun.(%{
            "record" => record,
            "link" => link,
            "metadata" => metadata,
            "witness" => first["witness"]
          })
        else
          _ -> @error
        end
      end)
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  def with_accepted_decision(_, _, _, _, _, _, _, _), do: @error

  defp held_values(root, read, %{"op" => "get_many", "keys" => keys} = request) do
    with true <- Collection.ReadView.valid_request?(request),
         "present" <- root["root_state"],
         {:ok, pointer} <- JSON.decode_unique(root["root_bytes"]),
         true <- pointer["manifest"] === root["manifest_sha256"],
         {:ok, records} <-
           Enum.reduce_while(keys, {:ok, []}, fn key, {:ok, records} ->
             case read.(key) do
               {:ok, record} -> {:cont, {:ok, [record | records]}}
               _ -> {:halt, @error}
             end
           end),
         witness =
           root
           |> Map.take(~w(version root_state root_sha256 manifest_sha256))
           |> Map.put("root", pointer),
         result = %{
           "version" => 2,
           "summary" => root["root"],
           "witness" => witness,
           "keys" => keys,
           "records" => Enum.reverse(records),
           "next" => nil
         },
         true <- byte_size(Jason.encode!(result)) <= Collection.ReadView.limits().reply_bytes,
         do: {:ok, result},
         else: (_ -> @error)
  end

  defp held_values(_, _, _), do: @error

  @doc """
  Observe an exact signed historical literal at one checked root, for trusted host use.

  The authenticated retirement edge records the successor key and value hash;
  the successor need not still exist or remain current. Its separate storage
  status reports only whether matching bytes are present at this root; it does
  not establish successor source eligibility or permission. This verifies stored
  history, not source availability, current permission, a live use lease, or an
  unexpired deadline. The owning host must revalidate those separately before
  using or disclosing any value. This is not a worker or extension SDK operation.
  """
  def managed_history(root, namespace, request, cap, catalog, recipe) do
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
          managed_history_view(view, request, cap, lineage, recipe)
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

  @doc "Retain the real Collection owner while exposing one authenticated pending proposal."
  def with_managed_proposal(root, namespace, request, cap, catalog, recipe, fun)
      when is_function(fun, 1),
      do:
        held_proposal(root, namespace, request, cap, catalog, recipe, false, fn observation,
                                                                                _read ->
          fun.(observation)
        end)

  def with_managed_proposal(_, _, _, _, _, _, _), do: @error

  @doc "Retain an authenticated pending target for reducing management, regardless of a shared literal's choice or override."
  def with_managed_proposal_removal(root, namespace, request, cap, catalog, recipe, fun)
      when is_function(fun, 1),
      do:
        held_proposal(
          root,
          namespace,
          request,
          cap,
          catalog,
          recipe,
          false,
          fn observation, _read -> fun.(observation) end,
          false,
          true
        )

  def with_managed_proposal_removal(_, _, _, _, _, _, _), do: @error

  @doc "Retain the checked proposal and same-owner read closure for host-only bounded planning."
  def with_managed_proposal_plan(root, namespace, request, cap, catalog, recipe, fun)
      when is_function(fun, 2),
      do: held_proposal(root, namespace, request, cap, catalog, recipe, true, fun)

  def with_managed_proposal_plan(_, _, _, _, _, _, _), do: @error

  @doc false
  def with_managed_proposal_acceptance_plan(root, namespace, request, cap, catalog, recipe, fun)
      when is_function(fun, 3),
      do: held_proposal(root, namespace, request, cap, catalog, recipe, true, fun, true)

  def with_managed_proposal_acceptance_plan(_, _, _, _, _, _, _), do: @error

  defp held_proposal(
         root,
         namespace,
         request,
         cap,
         catalog,
         recipe,
         reuse,
         fun,
         acceptance \\ false,
         removal \\ false
       ) do
    with {:ok, _, :get_record} <- select(request),
         "pending." <> id <- request["key"],
         true <- JSON.sha256?(id),
         true <- ManagedRecipe.valid?(recipe) and recipe["kind"] == "proposal",
         true <- recipe["key_prefix"] === "pending.",
         true <-
           is_map(catalog) and catalog["namespace"] === namespace and
             catalog["format"] == "managed-metadata-v3" and catalog["state"] == "active" do
      callback = fn witness, read, alive, publish ->
        cache_key = {__MODULE__, make_ref()}
        owner = self()

        live_request = %{
          "op" => "neighbors",
          "request" => %{
            "version" => 1,
            "prefix" => ManagedPages.prefix(:live),
            "fence_bytes" => ManagedPages.width(:live),
            "needle" => ManagedPages.live_identity(request["key"])
          }
        }

        capture = fn selected ->
          result = read.(selected)

          if reuse and selected === live_request and match?({:ok, _}, result) do
            {:ok, neighbors} = result
            page_key = get_in(neighbors, ["neighbors", "selected", "key"])
            Process.put(cache_key, %{live_request => result, :page_key => page_key})
          else
            if reuse and is_binary(selected) and match?({:ok, _}, result) do
              case Process.get(cache_key) do
                %{page_key: ^selected} = cache ->
                  Process.put(cache_key, Map.put(cache, selected, result))

                _ ->
                  :ok
              end
            end
          end

          result
        end

        planned_read = fn selected ->
          with true <- self() == owner,
               :ok <- alive.() do
            cache = Process.get(cache_key, %{})

            case if(selected === live_request or is_binary(selected),
                   do: Map.pop(cache, selected),
                   else: {nil, cache}
                 ) do
              {nil, _} ->
                read.(selected)

              {result, next} ->
                Process.put(cache_key, next)
                if alive.() == :ok, do: result, else: {:error, :managed_read_refused}
            end
          else
            _ -> {:error, :managed_read_refused}
          end
        end

        try do
          values = fn selected -> held_values(witness, capture, selected) end
          neighbors = fn selected -> capture.(%{"op" => "neighbors", "request" => selected}) end

          with {:ok, observation} <-
                 managed_proposal_read(values, neighbors, request, cap, recipe, id, removal) do
            selected_read = if(reuse, do: planned_read, else: read)

            if acceptance,
              do: fun.(observation, selected_read, publish),
              else: fun.(observation, selected_read)
          end
        after
          Process.delete(cache_key)
        end
      end

      if acceptance,
        do: Collection.with_managed_acceptance_read(root, namespace, callback),
        else:
          Collection.with_managed_read(root, namespace, fn witness, read, alive ->
            callback.(witness, read, alive, nil)
          end)
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  defp managed_proposal_view(view, request, cap, recipe, id) do
    managed_proposal_read(
      &Collection.view_read(view, &1),
      &Collection.view_neighbors(view, &1),
      request,
      cap,
      recipe,
      id
    )
  end

  defp managed_proposal_read(read, neighbors, request, cap, recipe, id, removal \\ false) do
    keys = [request["key"], ManagedPages.format_key()]

    with {:ok, first} <- read.(%{"op" => "get_many", "keys" => keys}),
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
           read.(%{"op" => "get_many", "keys" => [override_key]}),
         true <-
           override["witness"] === first["witness"] and override["summary"] === first["summary"],
         true <- override["keys"] === [override_key],
         [stored_override] <- override["records"],
         true <- removal or is_nil(stored_override),
         {:ok, live} <-
           managed_row_read(
             read,
             neighbors,
             cap,
             :live,
             ManagedPages.live_identity(request["key"]),
             first
           ),
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
         {:ok, anchor} <-
           managed_row_read(read, neighbors, cap, :anchor, candidate["lineage"], first),
         %{
           "clocks" => [_, _, anchor_first, anchor_deadline]
         } <- anchor,
         true <- removal or (is_nil(anchor["choice"]) and is_nil(anchor["retirement"])),
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
    managed_record_read(
      &Collection.view_read(view, &1),
      &Collection.view_neighbors(view, &1),
      request,
      cap,
      lineage,
      recipe
    )
  end

  defp managed_record_read(read, neighbors, request, cap, lineage, recipe, accepted? \\ false) do
    keys = [request["key"], ManagedPages.format_key(), recipe["override_prefix"] <> lineage]

    with {:ok, first} <- read.(%{"op" => "get_many", "keys" => keys}),
         true <- first["keys"] === keys,
         [record, format, nil] <- first["records"],
         true <- is_map(record) and is_map(format),
         true <- first["witness"]["root_state"] == "present",
         {:ok, _} <- ManagedPages.open_format(cap, format),
         {:ok, live} <-
           managed_row_read(
             read,
             neighbors,
             cap,
             :live,
             ManagedPages.live_identity(request["key"]),
             first
           ),
         {:ok, anchor} <- managed_row_read(read, neighbors, cap, :anchor, lineage, first),
         {:ok, metadata} <-
           management_record_metadata(read, first, record, recipe, anchor, live, accepted?),
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

  defp management_record_metadata(
         read,
         first,
         %{"value" => %{"kind" => "accepted_decision"}} = record,
         recipe,
         anchor,
         live,
         true
       ) do
    key = "accept." <> record["value"]["candidate_id"]

    with {:ok, linked} <- read.(%{"op" => "get_many", "keys" => [key]}),
         true <- linked["witness"] === first["witness"] and linked["summary"] === first["summary"],
         true <- linked["keys"] === [key],
         [link] <- linked["records"] do
      Ipse.Session.PendingAcceptance.retained_decision_metadata(
        recipe,
        record,
        link,
        anchor,
        live
      )
    else
      _ -> @error
    end
  end

  defp management_record_metadata(_, _, record, recipe, anchor, live, _) do
    with sources when is_list(sources) <- get_in(record["value"], recipe["evidence_path"]),
         {:ok, candidate} <-
           ManagedRecipe.extract(recipe, record["key"], record["value"], sources),
         true <- candidate["kind"] == "literal_source" do
      ManagedRetention.metadata(candidate, record["sha256"], anchor, live)
    else
      _ -> @error
    end
  end

  defp managed_history_view(view, request, cap, lineage, recipe) do
    keys = [request["key"], ManagedPages.format_key(), recipe["override_prefix"] <> lineage]

    with {:ok, first} <- Collection.view_read(view, %{"op" => "get_many", "keys" => keys}),
         true <- first["keys"] === keys,
         [record, format, nil] <- first["records"],
         true <- is_map(record) and is_map(format) and first["witness"]["root_state"] == "present",
         {:ok, _} <- ManagedPages.open_format(cap, format),
         {:ok, live} <-
           managed_row(view, cap, :live, ManagedPages.live_identity(request["key"]), first),
         sources when is_list(sources) <- get_in(record["value"], recipe["evidence_path"]),
         {:ok, candidate} <-
           ManagedRecipe.extract(recipe, request["key"], record["value"], sources),
         true <- candidate["kind"] == "literal_source" and candidate["lineage"] === lineage,
         {:ok, anchor} <- managed_row(view, cap, :anchor, lineage, first),
         {:ok, metadata} <-
           ManagedRetention.history_metadata(candidate, record["sha256"], anchor, live),
         {:ok, successor} <-
           Collection.view_read(view, %{
             "op" => "get_many",
             "keys" => [metadata["successor"]["key"]]
           }),
         true <-
           successor["witness"] === first["witness"] and successor["summary"] === first["summary"] and
             successor["keys"] === [metadata["successor"]["key"]],
         [successor_record] <- successor["records"],
         successor_storage =
           if(
             is_map(successor_record) and
               successor_record["sha256"] === metadata["successor"]["sha256"],
             do: "matching_record",
             else: "unavailable"
           ),
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
         "metadata" => metadata,
         "successor_storage" => successor_storage
       }}
    else
      _ -> @error
    end
  end

  defp managed_row(view, cap, kind, identity, first) do
    managed_row_read(
      &Collection.view_read(view, &1),
      &Collection.view_neighbors(view, &1),
      cap,
      kind,
      identity,
      first
    )
  end

  defp managed_row_read(read, neighbors, cap, kind, identity, first) do
    request = %{
      "version" => 1,
      "prefix" => ManagedPages.prefix(kind),
      "fence_bytes" => ManagedPages.width(kind),
      "needle" => identity
    }

    with {:ok, neighbors} <- neighbors.(request),
         true <-
           neighbors["witness"] === first["witness"] and neighbors["summary"] === first["summary"],
         "initialized" <- neighbors["state"],
         key when is_binary(key) <- get_in(neighbors, ["neighbors", "selected", "key"]),
         {:ok, selected} <- read.(%{"op" => "get_many", "keys" => [key]}),
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

  @doc "Structurally project an actual Collection witness; the caller must retain and authenticate its owner."
  def root_identity(witness, namespace) do
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
