defmodule Ipse.Extension.ManagedCollectionCall do
  @moduledoc "Explicit managed publication; current protected policy and host proofs supply authority."
  alias Ipse.{Extension, JSON}

  alias Ipse.Extension.{
    Collection,
    CollectionCall,
    CollectionPolicy,
    ManagedRecipe,
    SemanticAdmission,
    SemanticConsent
  }

  @error {:error, :invalid_extension_managed_collection_call}
  @binding ~w(kind version namespace pin outer_sha256 inner_op request_sha256 recipe_sha256)
  @normalization ~w(version lineage record_key first_admitted_ms valid_until_ms category eligibility anchor_key anchor_value_sha256 live_key live_value_sha256)
  @normalization_v3 ~w(version lineage record_key first_admitted_ms valid_until_ms category eligibility format_value_sha256 metadata_changes)

  def operation?(r), do: is_map(r) and r["op"] == "collection.managed"
  def capability(_), do: "host.collection.managed"
  def mutating?(r), do: operation?(r)

  @doc "Identify the narrow new v3 capture shape; this grants no source or publication authority."
  def new_capture?(request) do
    with :ok <- validate(request),
         true <- request["metadata_version"] === 3,
         [%{"expected_revision" => 0, "value" => value}] <- request["request"]["changes"] do
      is_map(value)
    else
      _ -> false
    end
  end

  def validate(r) do
    with true <- request_keys?(r) and operation?(r),
         true <- JSON.sha256?(r["recipe_sha256"]),
         true <- get_in(r, ["request", "op"]) == "commit",
         true <- get_in(r, ["request", "advance_floor"]) === true,
         :ok <-
           CollectionCall.validate(legacy(r)),
         true <- byte_size(Jason.encode!(r)) <= 8192 do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def binding(config, parent, request) do
    with :ok <- validate(request),
         true <- parent["version"] === 3,
         true <- admitted_recipe?(config[:semantic_admission], request),
         {:ok, base} <- CollectionCall.binding(config, parent["identity"], legacy(request)) do
      {:ok,
       Map.merge(base, %{
         "kind" => "collection.managed",
         "version" => metadata_version(request),
         "outer_sha256" => JSON.digest([parent["descriptor"]]),
         "recipe_sha256" => request["recipe_sha256"]
       })
       |> version_binding(request)}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def valid_binding?(b, r, identity, metadata \\ nil) do
    with :ok <- validate(r),
         true <- binding_keys?(b, r),
         true <- b["kind"] == "collection.managed" and b["version"] === metadata_version(r),
         true <- JSON.sha256?(b["outer_sha256"]),
         true <- b["recipe_sha256"] == r["recipe_sha256"],
         base =
           b
           |> Map.drop(~w(outer_sha256 recipe_sha256 metadata_version))
           |> Map.merge(%{"kind" => "collection", "version" => 1}) do
      CollectionCall.valid_binding?(base, legacy(r), identity, metadata) and
        (is_nil(metadata) or admitted_recipe?(metadata["semantic_admission"], b))
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp admitted_recipe?(admission, b) do
    settings = admission["policy"]["settings"]
    # Registry membership makes this an explicit managed journey. It does not
    # select an effect mapping: denied read-outer attempts still need a receipt.
    match?({:ok, _}, SemanticConsent.recipe(settings, b))
  end

  @doc "Conservative exact JSON ceiling, including both full sidecar change envelopes and normalization."
  def reservation(request) do
    # Valid values are encoded with the same Jason escaping as Migration.encode.
    # Each sidecar key is <=96 ASCII bytes; revision is <=16 decimal digits.
    change = %{
      "key" => String.duplicate("k", 96),
      "expected_revision" => 9_007_199_254_740_991,
      "value" => %{}
    }

    envelope = byte_size(Jason.encode!(change)) - 2

    sidecars =
      if metadata_version(request) == 3,
        do: 4 * (6144 + envelope + 1) + (4 + envelope + 1),
        else: 2 * (6144 + envelope + 1)

    Map.merge(Ipse.Extension.Consent.zero(), %{
      "operations" => 1,
      "input_bytes" => byte_size(Jason.encode!(request)) + sidecars + 2048,
      "output_bytes" => 16_384
    })
  end

  def execute(context, intent) do
    case supersession_lookup(context, intent) do
      {:ok, nil} -> execute_validated(context, intent, nil)
      {:ok, handoff} when is_map(handoff) -> execute_validated(context, intent, handoff)
      _ -> supersession_unconfirmed()
    end
  rescue
    _ -> supersession_unconfirmed()
  catch
    :exit, _ -> supersession_unconfirmed()
  end

  defp execute_validated(context, intent, handoff) do
    parent = context.parent

    with :ok <- validate(intent["request"]),
         true <- parent["version"] === 3,
         true <-
           SemanticAdmission.valid_outer_binding?(
             parent["semantic_binding"],
             parent["identity"],
             parent["descriptor"],
             context.session_id
           ),
         true <- get_in(parent, ["semantic_binding", "class"]) == "collection.publish",
         true <- valid_binding?(intent["effect_binding"], intent["request"], context.identity),
         true <- intent["effect_binding"]["outer_sha256"] == JSON.digest([parent["descriptor"]]),
         true <- intent["effect_binding"]["pin"]["session_id"] == context.session_id,
         true <- intent["namespace"] == intent["effect_binding"]["namespace"] do
      # Supersession is refused until the native display itself retains every
      # authority lease through acknowledgement, including owner-loss ordering.
      result =
        if is_nil(handoff),
          do: Ipse.Session.Resources.file_effect(fn -> protected(context, intent) end),
          else: supersession_unconfirmed()

      if not is_nil(handoff) and not match?({:supersession, _}, result),
        do: supersession_unconfirmed(),
        else: result
    else
      _ ->
        if(is_nil(handoff),
          do: failed("collection_consent_denied"),
          else: supersession_unconfirmed()
        )
    end
  rescue
    _ ->
      if(is_nil(handoff), do: failed("collection_unavailable"), else: supersession_unconfirmed())
  catch
    :exit, _ -> if(is_nil(handoff), do: :unknown, else: supersession_unconfirmed())
  end

  defp supersession_unconfirmed,
    do:
      {:supersession,
       %{
         "version" => 1,
         "kind" => "managed_supersession_delivery",
         "purpose_sha256" => nil,
         "status" => "unconfirmed",
         "outcome" => nil
       }}

  defp supersession_lookup(context, intent) do
    GenServer.call(context.owner, {:extension_supersession, context.job_ref, intent}, 5_000)
  catch
    :exit, _ -> {:error, :managed_supersession_refused}
  end

  defp protected(context, intent) do
    accounting_scope(fn key, _ ->
      protected(Map.put(context, :managed_settlement, key), intent, key)
    end)
  end

  defp protected(context, intent, key) do
    result =
      if metadata_version(intent["request"]) == 3 do
        protected_v3(context, intent)
      else
        Ipse.Extension.ProjectIdentity.with_binding(
          context.config[:home],
          context.cwd,
          context.config[:semantic_admission]["binding"],
          fn _ -> authorized_publication(context, intent) end
        )
      end

    case result do
      {:ok, {:deferred, packet}} -> settle_deferred(context, intent, packet)
      {:deferred, packet} -> settle_deferred(context, intent, packet)
      other -> if Process.get(key) == :publishing, do: :unknown, else: normalize(other)
    end
  end

  defp authorized_publication(c, i) do
    with {:ok, current, proofs} <- current_sources(c, i),
         {:ok, plan} <- plan(c, i, current, proofs) do
      publish(c, i, current, proofs, plan)
    else
      _ -> failed("collection_consent_denied")
    end
  end

  defp protected_v3(c, i) do
    alias Ipse.Extension.ProjectIdentity
    binding = c.config[:semantic_admission]["binding"]
    scope = %{namespace: i["namespace"], format: "managed-metadata-v3"}

    existing =
      ProjectIdentity.with_existing_domain_auth(c.config[:home], c.cwd, binding, scope, fn _, _ ->
        :active
      end)

    scope = Map.merge(scope, %{operation_id: i["operation_id"], initialize: existing != :active})

    ProjectIdentity.with_domain_publication(
      c.config[:home],
      c.cwd,
      binding,
      scope,
      fn _ ->
        with {:ok, current, proofs} <- current_sources(c, i),
             {:ok, _} <- plan(c, i, current, proofs),
             :ok <- if(scope.initialize, do: native_absence(c, i), else: :ok) do
          :ok
        else
          _ -> {:error, :collection_domain_refused}
        end
      end,
      fn cap, catalog ->
        accounting_scope(fn proof_key, _ ->
          result =
            authorized_publication(
              Map.merge(c, %{managed_domain: {cap, catalog}, managed_first_proof: proof_key}),
              i
            )

          if catalog["state"] == "prepared" do
            case {result, Process.get(proof_key)} do
              {{:deferred, _}, witness} when is_map(witness) ->
                {:first_publication, witness, result}

              _ ->
                :unknown
            end
          else
            result
          end
        end)
      end
    )
  end

  defp native_absence(c, i) do
    checked_view(c, i, fn view ->
      with {:ok, result} <-
             Collection.view_read(view, %{
               "op" => "get_many",
               "keys" => [Collection.ManagedPages.format_key()]
             }),
           true <- result["witness"]["root_state"] == "absent",
           true <- is_nil(result["witness"]["root"]),
           true <- result["records"] == [nil] do
        :ok
      else
        _ -> {:error, :collection_domain_refused}
      end
    end)
  end

  # A smaller measured charge must not escape the outer Identity finalization.
  # Until this point, Consent retains the full publishing reservation.
  defp settle_deferred(c, i, packet) do
    alias Ipse.Extension.Consent
    pin = i["effect_binding"]["pin"]

    with true <- keys?(packet, ~w(version ticket actual receipt)) and packet["version"] === 1,
         ticket = packet["ticket"],
         true <- keys?(ticket, ~w(project id sequence epoch request_sha256)),
         true <- ticket["project"] == pin["project_id"] and ticket["id"] == i["operation_id"],
         true <-
           ticket["epoch"] === pin["epoch"] and ticket["request_sha256"] == i["request_sha256"],
         true <- within_reservation?(packet["actual"], reservation(i["request"])),
         receipt = packet["receipt"],
         true <- keys?(receipt, ~w(status value)) and receipt["status"] in ~w(ok conflict failed),
         true <- Ipse.Session.Resources.active?(),
         true <- Process.alive?(Ipse.Session.Resources.file_effect_owner()),
         {:ok, %{"status" => "settled", "receipt" => ^receipt}} <-
           Consent.settle(
             SemanticAdmission.control_root(c.config[:home]),
             pin["project_id"],
             ticket,
             {:known, packet["actual"], receipt}
           ) do
      {String.to_existing_atom(receipt["status"]), receipt["value"]}
    else
      _ -> :unknown
    end
  rescue
    _ -> :unknown
  catch
    _, _ -> :unknown
  end

  defp current_sources(c, i),
    do: GenServer.call(c.owner, {:extension_collection_sources, c.job_ref, i}, 5000)

  @doc false
  def supersession_sources(c, i), do: current_sources(c, i)

  @doc false
  def supersession_plan(c, i, current, proofs, operation_id, action_sha256) do
    reserved =
      Map.merge(Ipse.Extension.Consent.zero(), %{
        "operations" => 1,
        "input_bytes" => 65_536,
        "output_bytes" => 16_384
      })

    plan(c, i, current, proofs, %{
      reserved: reserved,
      operation_id: operation_id,
      action_sha256: action_sha256
    })
  end

  defp plan(c, i, current, proofs), do: plan(c, i, current, proofs, nil)

  defp plan(c, i, current, proofs, supersession) do
    pin = i["effect_binding"]["pin"]

    Ipse.Extension.Consent.with_policy(
      SemanticAdmission.control_root(c.config[:home]),
      pin["project_id"],
      pin["epoch"],
      pin["policy_sha256"],
      now(),
      fn snapshot ->
        settings = snapshot["policy"]["settings"]
        verified = Enum.map(proofs, & &1["proof"])

        matches =
          Enum.flat_map(settings["effects"], fn m ->
            with true <-
                   m["class"] == "collection.publish" and m["inner_op"] == "collection.managed",
                 true <- m["outer_sha256"] == i["effect_binding"]["outer_sha256"],
                 {:ok, constraints} <- SemanticConsent.constraints(settings, m),
                 {:ok, recipe} <- SemanticConsent.recipe(settings, m),
                 :ok <- CollectionPolicy.check(i["request"]["request"], constraints, verified),
                 [change] <- i["request"]["request"]["changes"],
                 {:ok, _} <-
                   ManagedRecipe.extract(recipe, change["key"], change["value"], verified) do
              [{m, constraints, recipe}]
            else
              _ -> []
            end
          end)

        with [{mapping, constraints, recipe}] <- matches,
             true <- JSON.digest([recipe]) == i["request"]["recipe_sha256"],
             true <- i["approval"] in ~w(saved_consent approved session_allow),
             effect =
               Map.take(mapping, ~w(operation class outer_sha256 inner_op))
               |> Map.merge(%{
                 "id" => if(supersession, do: supersession.operation_id, else: i["operation_id"]),
                 "request_sha256" =>
                   if(supersession, do: supersession.action_sha256, else: i["request_sha256"]),
                 "source_generation" => current["source_generation"],
                 "sources" =>
                   Enum.map(verified, &%{"category" => &1["origin"], "path" => &1["path"]}),
                 "reserved" =>
                   if(supersession, do: supersession.reserved, else: reservation(i["request"]))
               }),
             {:ok, reservation} <-
               SemanticConsent.authorize(pin, snapshot, current, effect, now()) do
          {:ok,
           %{
             reservation: reservation,
             constraints: constraints,
             recipe: recipe,
             publish_before_ms: snapshot["policy"]["expires_at_ms"]
           }}
        else
          _ -> {:error, :collection_policy_refused}
        end
      end
    )
  end

  defp publish(c, i, current, proofs, plan) do
    scope =
      if new_capture?(i["request"]),
        do: &Collection.with_notes_publication_deadline/2,
        else: &Collection.with_publication_deadline/2

    case scope.(plan.publish_before_ms, fn ->
           publish_authorized(c, i, current, proofs, plan)
         end) do
      {:error, :collection_deadline_fence_unavailable} ->
        failed("collection_deadline_unavailable")

      other ->
        other
    end
  end

  defp publish_authorized(c, i, current, proofs, plan) do
    alias Ipse.Extension.Consent
    pin = i["effect_binding"]["pin"]
    root = SemanticAdmission.control_root(c.config[:home])

    with {:ok, ticket} <- Consent.reserve(root, pin["project_id"], plan.reservation, now()),
         false <- Map.has_key?(ticket, "existing"),
         {:ok, ^ticket} <- Consent.admit(root, pin["project_id"], ticket, now()) do
      case Consent.publish_deferred(root, pin["project_id"], ticket, now(), fn ->
             Process.put(c.managed_settlement, :publishing)

             with {:ok, ^current, ^proofs} <- current_sources(c, i),
                  :ok <-
                    CollectionPolicy.check(
                      i["request"]["request"],
                      plan.constraints,
                      Enum.map(proofs, & &1["proof"])
                    ) do
               case storage(c, i, proofs, plan) do
                 {:ok, value, actual} ->
                   {:ok, actual, %{"status" => "ok", "value" => value}}

                 {status, value} when status in [:conflict, :failed] ->
                   {:ok, reservation(i["request"]),
                    %{"status" => Atom.to_string(status), "value" => value}}

                 _ ->
                   :unknown
               end
             else
               _ ->
                 {:ok, reservation(i["request"]),
                  %{"status" => "failed", "value" => %{"code" => "collection_source_refused"}}}
             end
           end) do
        {:ok, %{"version" => 1} = packet} ->
          {:deferred, packet}

        {:error, _} ->
          failed("collection_consent_denied")

        _ ->
          :unknown
      end
    else
      {:error, :collection_deadline_fence_unavailable} ->
        failed("collection_deadline_unavailable")

      _ ->
        failed("collection_consent_denied")
    end
  end

  defp storage(c, i, proofs, plan) do
    accounting_scope(fn key, owner -> storage(c, i, proofs, plan, key, owner) end)
  end

  defp storage(c, i, proofs, plan, key, owner) do
    request = i["request"]

    execute =
      if metadata_version(request) == 3,
        do: &Collection.execute_managed_v3/6,
        else: &Collection.execute_managed/6

    case execute.(
           SemanticAdmission.collection_root(c.config[:home]),
           i["namespace"],
           request["request"],
           i["operation_id"],
           request["recipe_sha256"],
           fn witness, read ->
             capture_accounting(
               key,
               owner,
               {i["operation_id"], witness["operation_id"]},
               request,
               plan.reservation["reserved"],
               fn ->
                 options = %{
                   request: request["request"],
                   recipe: plan.recipe,
                   constraints: plan.constraints,
                   verified_sources: Enum.map(proofs, & &1["proof"]),
                   policy_sha256: i["effect_binding"]["pin"]["policy_sha256"],
                   now_ms: now()
                 }

                 case Map.get(c, :managed_domain) do
                   {cap, catalog} ->
                     Collection.NormalizerV3.normalize(
                       witness,
                       read,
                       Map.merge(options, %{domain_cap: cap, catalog: catalog})
                     )

                   nil ->
                     Collection.Normalizer.normalize(witness, read, options)
                 end
               end
             )
           end
         ) do
      {:ok, value} ->
        with true <- valid_outcome?(request, "ok", value, i["operation_id"]),
             true <- CollectionCall.reply_fits?(i, value),
             {:ok, actual} <-
               captured_accounting(
                 key,
                 owner,
                 i["operation_id"],
                 value,
                 plan.reservation["reserved"]
               ),
             :ok <- verify_first_publication(c, i, value) do
          {:ok, value, actual}
        else
          _ -> :unknown
        end

      {:conflict, value} ->
        {:conflict, value}

      {:existing, _} ->
        failed("collection_duplicate")

      {:error, reason}
      when reason in [
             :collection_capacity,
             :collection_filesystem_unsupported,
             :collection_writer_fenced
           ] ->
        failed(Atom.to_string(reason))

      {:error, _} ->
        failed("collection_unavailable")

      _ ->
        :unknown
    end
  end

  defp verify_first_publication(
         %{managed_domain: {cap, %{"state" => "prepared"} = catalog}} = c,
         i,
         value
       ) do
    alias Collection.{ManagedPages, Migration}
    normalization = value["normalization"]
    [change] = i["request"]["request"]["changes"]

    keys =
      Enum.uniq(
        [ManagedPages.format_key(), change["key"]] ++
          Enum.map(normalization["metadata_changes"], & &1["key"])
      )

    result =
      checked_view(c, i, fn view ->
        with {:ok, snapshot} <- Collection.view_read(view, %{"op" => "get_many", "keys" => keys}),
             true <- snapshot["witness"]["root_state"] == "present",
             true <- snapshot["summary"]["generation"] == value["receipt"]["generation"],
             true <- snapshot["summary"]["floor"] == value["receipt"]["floor"],
             records = Map.new(Enum.zip(keys, snapshot["records"])),
             record = records[change["key"]],
             true <-
               published_record?(
                 record,
                 i,
                 value["receipt"]["generation"],
                 JSON.sha256(Migration.encode(change["value"]))
               ),
             {:ok, _} <- ManagedPages.open_format(cap, records[ManagedPages.format_key()]),
             true <-
               records[ManagedPages.format_key()]["sha256"] ==
                 normalization["format_value_sha256"],
             true <-
               Enum.all?(normalization["metadata_changes"], fn extra ->
                 current = records[extra["key"]]

                 if is_nil(extra["value_sha256"]) do
                   is_nil(current) and extra["expected_revision"] > 0
                 else
                   published_record?(
                     current,
                     i,
                     value["receipt"]["generation"],
                     extra["value_sha256"]
                   )
                 end
               end) do
          {:ok,
           %{
             version: 1,
             namespace: i["namespace"],
             format: "managed-metadata-v3",
             fence_id: catalog["fence_id"],
             operation_id: i["operation_id"],
             root_sha256: snapshot["witness"]["root_sha256"]
           }}
        else
          _ -> {:error, :collection_first_publication_unconfirmed}
        end
      end)

    case result do
      {:ok, witness} ->
        Process.put(c.managed_first_proof, witness)
        :ok

      _ ->
        {:error, :collection_first_publication_unconfirmed}
    end
  end

  defp verify_first_publication(_, _, _), do: :ok

  defp published_record?(record, i, generation, sha) do
    is_map(record) and record["revision"] == generation and
      record["operation_id"] == i["operation_id"] and record["sha256"] == sha and
      JSON.sha256(Collection.Migration.encode(record["value"])) == sha
  end

  defp checked_view(c, i, fun) do
    with {:ok, view} <-
           Collection.open_view(
             SemanticAdmission.collection_root(c.config[:home]),
             i["namespace"]
           ) do
      result =
        try do
          fun.(view)
        rescue
          _ -> {:error, :collection_view_unavailable}
        catch
          _, _ -> {:error, :collection_view_unavailable}
        end

      case Collection.close_view(view) do
        :ok -> result
        _ -> {:error, :collection_view_unavailable}
      end
    end
  end

  # This slot exists only in the actual storage callback process. It never crosses
  # the SDK boundary or supplies authority for an otherwise unproven outcome.
  defp accounting_scope(fun) do
    key = {__MODULE__, make_ref()}
    prior = Process.get(key, :absent)

    try do
      fun.(key, self())
    after
      if prior == :absent, do: Process.delete(key), else: Process.put(key, prior)
    end
  end

  defp capture_accounting(key, owner, {operation_id, witnessed_id}, request, reserved, fun) do
    if self() == owner and Process.get(key, :absent) == :absent do
      # Claim before inspecting the result so a second invocation cannot replace
      # either a failed first callback or a successful measurement.
      Process.put(key, :invalid)

      with true <- is_binary(operation_id) and operation_id === witnessed_id,
           {:ok, normalized, normalization} = result <- fun.(),
           {:ok, actual} <- measured_accounting(request, normalized, normalization, reserved) do
        Process.put(key, {owner, operation_id, JSON.digest([normalized]), normalization, actual})
        result
      else
        {:error, _} = error -> error
        _ -> {:error, :collection_accounting_invalid}
      end
    else
      if self() == owner, do: Process.put(key, :invalid)
      {:error, :collection_accounting_invalid}
    end
  end

  @doc false
  def measured_accounting(request, normalized, normalization, reserved) do
    original_bytes = byte_size(Jason.encode!(request["request"]))
    normalized_bytes = byte_size(Jason.encode!(normalized))
    receipt_bytes = byte_size(Jason.encode!(normalization))
    delta = normalized_bytes - original_bytes
    input = byte_size(Jason.encode!(request)) + delta + receipt_bytes
    actual = Map.put(reservation(request), "input_bytes", input)

    if delta >= 0 and is_map(normalization) and receipt_bytes <= 2048 and
         within_reservation?(actual, reserved) do
      {:ok, actual}
    else
      {:error, :collection_accounting_invalid}
    end
  rescue
    _ -> {:error, :collection_accounting_invalid}
  end

  defp captured_accounting(key, owner, operation_id, value, reserved) do
    with true <- self() == owner,
         {^owner, ^operation_id, digest, normalization, actual} <- Process.get(key),
         true <- digest == value["receipt"]["request_sha256"],
         true <- normalization === value["normalization"],
         true <- JSON.digest([normalization]) == value["binding"]["normalization_sha256"],
         true <- within_reservation?(actual, reserved) do
      {:ok, actual}
    else
      _ -> {:error, :collection_accounting_invalid}
    end
  end

  defp within_reservation?(actual, reserved) do
    is_map(actual) and is_map(reserved) and
      Enum.sort(Map.keys(actual)) == Enum.sort(Map.keys(reserved)) and
      Enum.all?(actual, fn {dimension, amount} ->
        JSON.safe_uint?(amount) and JSON.safe_uint?(reserved[dimension]) and
          amount <= reserved[dimension]
      end)
  end

  def valid_outcome?(r, status, value, id) when status in ~w(unknown denied failed conflict),
    do: validate(r) == :ok and CollectionCall.valid_outcome?(legacy(r), status, value, id)

  def valid_outcome?(r, "ok", v, _) do
    validate(r) == :ok and keys?(v, ~w(version binding normalization receipt)) and
      v["version"] === 1 and
      keys?(v["binding"], ~w(version original_request_sha256 recipe_sha256 normalization_sha256)) and
      v["binding"]["version"] === 1 and
      v["binding"]["original_request_sha256"] == JSON.digest([r["request"]]) and
      v["binding"]["recipe_sha256"] == r["recipe_sha256"] and
      v["binding"]["normalization_sha256"] == JSON.digest([v["normalization"]]) and
      normalization?(v["normalization"], r) and
      keys?(v["receipt"], ~w(generation floor request_sha256 managed_binding_sha256)) and
      Collection.Migration.receipt?(v["receipt"]) and
      v["receipt"]["managed_binding_sha256"] == JSON.digest([v["binding"]]) and
      v["receipt"]["generation"] == r["request"]["expected_generation"] + 1 and
      Extension.validate(v) == :ok
  rescue
    _ -> false
  end

  def valid_outcome?(_, _, _, _), do: false

  def bound_outcome?(event) do
    binding = event["effect_binding"]

    binding_keys?(binding, event["request"]) and binding["kind"] == "collection.managed" and
      binding["version"] === metadata_version(event["request"]) and
      SemanticConsent.pin?(binding["pin"]) and binding["namespace"] == event["namespace"] and
      binding["pin"]["namespace"] == event["namespace"] and
      binding["pin"]["identity_sha256"] == event["identity_sha256"] and
      binding["request_sha256"] == JSON.digest([event["request"]["request"]]) and
      binding["recipe_sha256"] == event["request"]["recipe_sha256"] and
      JSON.sha256?(binding["outer_sha256"]) and binding["inner_op"] == "commit" and
      valid_outcome?(
        event["request"],
        event["outcome"]["status"],
        event["outcome"]["value"],
        event["operation_id"]
      ) and
      (event["outcome"]["status"] != "conflict" or
         event["outcome"]["value"]["project"] == event["namespace"])
  rescue
    _ -> false
  end

  defp normalization?(n, r) do
    [change] = r["request"]["changes"]

    valid_metadata?(n, r) and n["record_key"] == change["key"] and
      JSON.sha256?(n["lineage"]) and JSON.safe_uint?(n["first_admitted_ms"]) and
      (is_nil(n["valid_until_ms"]) or
         (JSON.safe_uint?(n["valid_until_ms"]) and n["valid_until_ms"] > n["first_admitted_ms"])) and
      n["category"] in ~w(current ordinary preference) and
      n["eligibility"] in ~w(current never_current) and
      (not is_nil(n["valid_until_ms"]) or
         (n["category"] != "ordinary" and n["eligibility"] != "never_current")) and
      byte_size(Jason.encode!(n)) <= 2048
  end

  defp valid_metadata?(n, r) do
    if metadata_version(r) == 3 do
      keys?(n, @normalization_v3) and n["version"] === 3 and
        JSON.sha256?(n["format_value_sha256"]) and is_list(n["metadata_changes"]) and
        length(n["metadata_changes"]) in 1..5 and
        Enum.uniq_by(n["metadata_changes"], & &1["key"]) == n["metadata_changes"] and
        Enum.count(n["metadata_changes"], &is_nil(&1["value_sha256"])) <= 1 and
        Enum.count(n["metadata_changes"], &(not is_nil(&1["value_sha256"]))) <= 4 and
        Enum.all?(n["metadata_changes"], fn change ->
          keys?(change, ~w(key expected_revision value_sha256)) and
            metadata_key_v3?(change["key"]) and
            JSON.safe_uint?(change["expected_revision"]) and
            (JSON.sha256?(change["value_sha256"]) or
               (is_nil(change["value_sha256"]) and change["expected_revision"] > 0 and
                  change["key"] != Collection.ManagedPages.format_key()))
        end)
    else
      keys?(n, @normalization) and n["version"] === 2 and
        metadata_key?(n["anchor_key"], "anchor", n["lineage"]) and
        metadata_key?(n["live_key"], "live", JSON.sha256(hd(r["request"]["changes"])["key"])) and
        JSON.sha256?(n["anchor_value_sha256"]) and JSON.sha256?(n["live_value_sha256"])
    end
  end

  defp metadata_key_v3?("host.validity.format"), do: true

  defp metadata_key_v3?(key) when is_binary(key),
    do: Regex.match?(~r/\Ahost\.validity\.(?:a\.[0-9a-f]{64}|l\.0[0-2][0-9a-f]{64})\z/, key)

  defp metadata_key_v3?(_), do: false

  defp metadata_key?(key, "anchor", lineage),
    do:
      key in Enum.map(
        0..7,
        &("host.validity.anchor." <> binary_part(lineage, 0, 2) <> "." <> Integer.to_string(&1))
      )

  defp metadata_key?(key, "live", hash) do
    shard =
      hash
      |> binary_part(0, 3)
      |> String.to_integer(16)
      |> rem(512)
      |> Integer.to_string(16)
      |> String.downcase()
      |> String.pad_leading(3, "0")

    key in Enum.map(0..3, &("host.validity.live." <> shard <> "." <> Integer.to_string(&1)))
  end

  defp metadata_version(%{"metadata_version" => 3}), do: 3
  defp metadata_version(_), do: 2

  defp request_keys?(r),
    do:
      keys?(r, ~w(op request proofs recipe_sha256)) or
        (keys?(r, ~w(op request proofs recipe_sha256 metadata_version)) and
           r["metadata_version"] === 3)

  defp binding_keys?(b, r),
    do:
      keys?(b, if(metadata_version(r) == 3, do: ["metadata_version" | @binding], else: @binding)) and
        (metadata_version(r) != 3 or b["metadata_version"] === 3)

  defp version_binding(b, r),
    do: if(metadata_version(r) == 3, do: Map.put(b, "metadata_version", 3), else: b)

  defp legacy(r),
    do: r |> Map.drop(~w(recipe_sha256 metadata_version)) |> Map.put("op", "collection.call")

  defp normalize({s, _} = r) when s in [:ok, :conflict, :failed], do: r
  defp normalize({:error, _}), do: failed("collection_consent_denied")
  defp normalize(_), do: :unknown
  defp failed(code), do: {:failed, %{"code" => code}}
  defp keys?(m, keys), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(keys)
  defp now, do: System.system_time(:millisecond)
end
