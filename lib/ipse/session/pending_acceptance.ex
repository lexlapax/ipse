defmodule Ipse.Session.PendingAcceptance do
  @moduledoc """
  Host-only exact pending-card facts and native decision receipt.

  Shaped facts and proofs do not establish source, storage, consent or terminal
  authority. Historical review constructs facts inside Identity, active Consent
  and retained Collection owners, without claiming current source eligibility.
  Release display owners before input, then acquire the actual original source
  and reacquire the target owners and reproduce the facts before consuming the
  actual one-use Review permit. This module does not publish a decision.
  """
  alias Ipse.{JSON, Runner.Review}
  alias Ipse.Extension.{Collection.ManagedPages, Collection.Migration, ManagedRecipe}

  @context ~w(operation_id journal_id client_id session_id project_id namespace binding_sha256 policy_sha256 capture_epoch render_revision recipe)
  @facts ~w(version kind operation_id journal_id client_id session_id project_id namespace binding_sha256 policy_sha256 capture_epoch render_revision pending_key candidate_id record_schema_version record_revision record_sha256 lineage text text_sha256 assigned_category reason source_proof recipe_sha256 publication_policy_sha256 first_admitted_ms valid_until_ms root_sha256)
  @receipt ~w(version kind command event_id display_sha256 challenge input_sha256 observed_at_ms facts_sha256)
  @proposal ~w(version kind id lineage state text assigned_category reason event_at_ms created_at_ms expires_at_ms evidence)
  @layout "pending_acceptance_v1"
  @error {:error, :pending_acceptance_refused}
  @journal_share_slot {__MODULE__, :journal_share}

  def layout, do: @layout

  @doc """
  Bind standalone management source checks to one protected policy snapshot.

  The caller must obtain the binding and snapshot under their owners and
  authenticate the artifact and recipes from the installed bundle. This
  constructs source-correlation data only; it does not authorize a review,
  publication, delivery, or an extension Session.
  """
  def management_source_context(
        home,
        history_dir,
        binding,
        snapshot,
        journal_id,
        artifact,
        note,
        proposal,
        now
      ) do
    alias Ipse.Extension.{SemanticAdmission, SemanticConsent, SemanticRoutes}

    with true <- is_binary(home) and Path.type(home) === :absolute,
         true <- is_binary(history_dir) and Path.type(history_dir) === :absolute,
         true <- SemanticConsent.binding?(binding) and id?(journal_id),
         true <- is_map(snapshot) and JSON.safe_uint?(snapshot["epoch"]) and snapshot["epoch"] > 0,
         policy when is_map(policy) <- snapshot["policy"],
         true <-
           SemanticConsent.policy?(policy) and JSON.safe_uint?(now) and
             now < policy["expires_at_ms"],
         true <- JSON.sha256?(artifact) and policy["artifact_sha256"] === artifact,
         true <- policy["project"] === binding["project_id"],
         settings = policy["settings"],
         true <- settings["version"] === 2 and settings["domain"] === "knowledge",
         {:ok, namespace} <-
           SemanticConsent.namespace(binding["project_id"], settings["storage"]["collection"]),
         true <- namespace === settings["namespace"],
         true <-
           settings["scope"]["kind"] === "project" or
             settings["scope"]["worktree_id"] === binding["worktree_id"],
         true <- ManagedRecipe.valid?(note) and note["kind"] === "literal_source",
         true <- ManagedRecipe.valid?(proposal) and proposal["kind"] === "proposal",
         true <- management_recipe?(settings, note) and management_recipe?(settings, proposal),
         {:ok, selectors} <- SemanticRoutes.selectors(settings["routes"]),
         pin = %{
           "version" => 1,
           "session_id" => journal_id,
           "project_id" => binding["project_id"],
           "worktree_id" => binding["worktree_id"],
           "binding_sha256" => binding["binding_sha256"],
           "epoch" => snapshot["epoch"],
           "policy_sha256" => JSON.digest([policy]),
           "identity_sha256" => settings["identity_sha256"],
           "namespace" => namespace,
           "routes_sha256" => JSON.digest([settings["routes"]]),
           "source_sha256" => policy["source_sha256"]
         },
         admission = %{
           "version" => 2,
           "binding" => binding,
           "instance" => settings["instance"],
           "pin" => pin,
           "selectors" => selectors,
           "status" => "active",
           "policy" => policy
         },
         true <- SemanticAdmission.valid?(admission, journal_id) do
      {:ok,
       %{
         history_dir: history_dir,
         session_id: journal_id,
         config: %{home: home, semantic_admission: admission}
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp management_recipe?(settings, recipe) do
    sha = JSON.digest([recipe])

    Enum.any?(settings["effects"], fn mapping ->
      mapping["class"] === "collection.publish" and mapping["recipe_sha256"] === sha and
        Ipse.Extension.SemanticConsent.recipe(settings, mapping) === {:ok, recipe}
    end)
  end

  @doc "Validate historical acceptance ordering and uniqueness without restoring authority."
  def validate_events(events, journal_id) when is_list(events) do
    metadata = (List.first(events) || %{})["metadata"] || %{}
    selected = Enum.filter(events, &(&1["type"] === "pending_proposal_accepted"))

    effect_events =
      Enum.filter(
        events,
        &(&1["type"] in ~w(pending_acceptance_intent pending_acceptance_result))
      )

    marker = metadata["pending_acceptance_layout"]

    with true <- (is_nil(marker) and selected === []) or id?(journal_id),
         true <- is_nil(marker) or marker === @layout,
         true <- marker === @layout or (selected === [] and effect_events === []),
         {:ok, _} <-
           Enum.reduce_while(
             selected,
             {:ok,
              %{events: MapSet.new(), operations: MapSet.new(), candidates: MapSet.new(), at: nil}},
             fn event, {:ok, state} ->
               facts = event["facts"]
               review = event["review"]
               session = if metadata["kind"] === "knowledge_management", do: nil, else: journal_id

               project =
                 metadata["project_id"] ||
                   get_in(metadata, ["semantic_admission", "pin", "project_id"])

               namespace =
                 metadata["namespace"] ||
                   get_in(metadata, ["semantic_admission", "pin", "namespace"])

               with true <- valid_event?(event),
                    true <- facts["journal_id"] === journal_id and facts["session_id"] === session,
                    true <- is_nil(project) or facts["project_id"] === project,
                    true <- is_nil(namespace) or facts["namespace"] === namespace,
                    true <- is_nil(state.at) or review["observed_at_ms"] >= state.at,
                    false <- MapSet.member?(state.events, review["event_id"]),
                    false <- MapSet.member?(state.operations, facts["operation_id"]),
                    false <- MapSet.member?(state.candidates, facts["candidate_id"]) do
                 {:cont,
                  {:ok,
                   %{
                     events: MapSet.put(state.events, review["event_id"]),
                     operations: MapSet.put(state.operations, facts["operation_id"]),
                     candidates: MapSet.put(state.candidates, facts["candidate_id"]),
                     at: review["observed_at_ms"]
                   }}}
               else
                 _ -> {:halt, @error}
               end
             end
           ),
         {:ok, _} <- effect_history(events) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def validate_events(_, _), do: @error

  @doc """
  Retain and revalidate the original source while a trusted caller runs.

  The consuming context must be the actual Session or management owner with an
  admitted project binding and history directory. This verifies source identity
  and same-project ownership; the caller must separately retain current Consent,
  check source exclusions, display or effect authority, and all other owners.
  """
  def with_verified_source(context, facts, fun) when is_map(context) and is_function(fun, 1) do
    with true <- source_context?(context, facts) do
      proof = facts["source_proof"]

      Ipse.Session.StoredSources.with_verified(context, nil, [proof], fn
        [%{"proof" => ^proof} = source] -> fun.(source)
        _ -> @error
      end)
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    :exit, _ -> @error
  end

  def with_verified_source(_, _, _), do: @error

  @doc "Retain the same verified original source with an owner-bound shareable lease."
  def with_shareable_source(context, facts, fun) when is_map(context) and is_function(fun, 2) do
    if get_in(facts, ["source_proof", "session_id"]) === context[:session_id] do
      @error
    else
      with_shareable_source_union(context, facts, fn
        source, [%{token: lease}], false -> fun.(source, lease)
        _, _, _ -> @error
      end)
    end
  rescue
    _ -> @error
  catch
    :exit, _ -> @error
  end

  def with_shareable_source(_, _, _), do: @error

  @doc """
  Verify the original source and identify whether its Session owner is active.

  Inactive sources carry transferable leases. An active source carries no such
  lease; a caller using it for a native effect must separately retain and share
  its actual Session/Writer owner. This check grants no review or effect authority.
  """
  def with_shareable_source_union(context, facts, fun)
      when is_map(context) and is_function(fun, 3) do
    with true <- source_context?(context, facts) do
      proof = facts["source_proof"]

      Ipse.Session.StoredSources.with_shareable_union(context, nil, [proof], fn
        [%{"proof" => ^proof} = source], leases, active -> fun.(source, leases, active)
        _, _, _ -> @error
      end)
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    :exit, _ -> @error
  end

  def with_shareable_source_union(_, _, _), do: @error

  @doc "Check the exact current semantic policy and source selection; this grants no lease."
  def check_source_policy(facts, policy, note_recipe, now) do
    with true <- facts?(facts) and JSON.safe_uint?(now),
         true <- Ipse.Extension.SemanticConsent.policy?(policy),
         true <- JSON.digest([policy]) === facts["policy_sha256"],
         true <- policy["project"] === facts["project_id"],
         true <- get_in(policy, ["settings", "namespace"]) === facts["namespace"],
         true <- now < policy["expires_at_ms"] and now < facts["valid_until_ms"],
         true <- ManagedRecipe.valid?(note_recipe) and note_recipe["kind"] === "literal_source",
         settings = policy["settings"],
         note_sha = JSON.digest([note_recipe]),
         true <-
           Enum.any?(settings["effects"], fn mapping ->
             mapping["class"] === "collection.publish" and mapping["recipe_sha256"] === note_sha and
               Ipse.Extension.SemanticConsent.recipe(settings, mapping) === {:ok, note_recipe}
           end),
         true <-
           Enum.any?(settings["effects"], fn mapping ->
             mapping["class"] === "collection.publish" and
               mapping["recipe_sha256"] === facts["recipe_sha256"] and
               match?(
                 {:ok, %{"kind" => "proposal"}},
                 Ipse.Extension.SemanticConsent.recipe(settings, mapping)
               )
           end),
         :ok <-
           Ipse.Extension.SemanticConsent.check_sources(policy, [
             %{
               "category" => facts["source_proof"]["origin"],
               "path" => facts["source_proof"]["path"]
             }
           ]) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp source_context?(context, facts) do
    admission = get_in(context, [:config, :semantic_admission])
    pin = if is_map(admission), do: admission["pin"]

    facts?(facts) and
      Ipse.Extension.SemanticAdmission.valid?(admission, context[:session_id]) and
      is_map(pin) and admission["status"] === "active" and
      pin["project_id"] === facts["project_id"] and pin["namespace"] === facts["namespace"] and
      pin["binding_sha256"] === facts["binding_sha256"] and
      pin["policy_sha256"] === facts["policy_sha256"] and pin["epoch"] === facts["capture_epoch"] and
      context[:session_id] === (facts["session_id"] || facts["journal_id"]) and
      is_binary(context[:history_dir])
  end

  @doc "Construct the exact public effect intent; this record does not grant execution authority."
  def effect_intent(event, request) do
    with true <- valid_event?(event),
         facts = event["facts"],
         true <- Ipse.Extension.Collection.valid_request?(request),
         true <- request["op"] === "commit" and request["advance_floor"] === true,
         true <- request["expected_generation"] >= facts["record_revision"],
         [pending, note, link] <- request["changes"],
         true <- is_map(note["value"]),
         {:ok, values} <- accepted_values(event, note["value"]["valid_until_ms"]),
         true <-
           pending === %{
             "key" => facts["pending_key"],
             "expected_revision" => facts["record_revision"],
             "value" => nil
           },
         true <-
           note === %{
             "key" => values["note_key"],
             "expected_revision" => 0,
             "value" => values["note"]
           },
         true <-
           link === %{
             "key" => values["link_key"],
             "expected_revision" => 0,
             "value" => values["link"]
           },
         true <- byte_size(Migration.encode(request)) <= 65_536 do
      {:ok,
       %{
         "type" => "pending_acceptance_intent",
         "version" => 1,
         "journal_id" => facts["journal_id"],
         "operation_id" => facts["operation_id"],
         "acceptance_sha256" => JSON.digest([event]),
         "root_sha256" => facts["root_sha256"],
         "request_sha256" => JSON.digest([request]),
         "request" => request
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Check combined request structure without authenticating its sidecars or granting authority."
  def normalized_acceptance?(intent, request) do
    public = intent["request"]

    with true <- is_map(intent) and is_map(public),
         true <- intent["request_sha256"] === JSON.digest([public]),
         true <- Ipse.Extension.Collection.valid_request?(request),
         true <- Map.delete(request, "changes") === Map.delete(public, "changes"),
         changes when is_list(changes) <- request["changes"],
         originals when is_list(originals) <- public["changes"],
         true <- length(originals) === 3,
         {^originals, extras} <- Enum.split(changes, length(originals)),
         true <- length(extras) in 1..5,
         true <- Enum.all?(extras, &String.starts_with?(&1["key"], "host.validity.")) do
      true
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc "Record a refused or unconfirmed attempt without claiming a committed publication."
  def effect_result(intent, status) when status in ~w(refused unknown) do
    if is_map(intent) and intent["type"] === "pending_acceptance_intent" and
         id?(intent["journal_id"]) and id?(intent["operation_id"]) do
      {:ok,
       %{
         "type" => "pending_acceptance_result",
         "version" => 1,
         "journal_id" => intent["journal_id"],
         "operation_id" => intent["operation_id"],
         "intent_sha256" => JSON.digest([intent]),
         "status" => status
       }}
    else
      @error
    end
  rescue
    _ -> @error
  end

  def effect_result(_, _), do: @error

  @doc "Bind a confirmed Collection receipt to the exact accepted event and combined request."
  def committed_result(event, intent, request, receipt) do
    with true <- valid_event?(event),
         {:ok, ^intent} <- effect_intent(event, intent["request"]),
         true <- normalized_acceptance?(intent, request),
         true <- Migration.receipt?(receipt),
         true <-
           Enum.sort(Map.keys(receipt)) ===
             ~w(floor generation managed_binding_sha256 request_sha256),
         true <- receipt["generation"] === request["expected_generation"] + 1,
         true <- receipt["floor"] >= receipt["generation"],
         true <- receipt["request_sha256"] === JSON.digest([request]),
         true <-
           receipt["managed_binding_sha256"] ===
             JSON.digest(["pending_acceptance", 1, event, intent]),
         true <- byte_size(Migration.encode(request)) <= 65_536 do
      {:ok,
       %{
         "type" => "pending_acceptance_result",
         "version" => 1,
         "journal_id" => intent["journal_id"],
         "operation_id" => intent["operation_id"],
         "intent_sha256" => JSON.digest([intent]),
         "status" => "committed",
         "normalized_request" => request,
         "receipt" => receipt
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "List interrupted or unconfirmed effects for inspection; never issue an effect or retry."
  def unknown_effects(events, journal_id) do
    with :ok <- validate_events(events, journal_id),
         {:ok, history} <- effect_history(events) do
      unknown =
        for {operation, %{intent: intent, result: result}} <- history,
            is_nil(result) or result["status"] === "unknown",
            do: {operation, intent}

      {:ok, unknown |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1))}
    else
      _ -> @error
    end
  end

  @doc "Resolve one structurally validated committed acceptance from an already authenticated journal."
  def resolve_committed(events, journal_id, event_sha256) when is_list(events) do
    with true <- JSON.sha256?(event_sha256),
         :ok <- validate_events(events, journal_id),
         [event] <-
           Enum.filter(
             events,
             &(&1["type"] === "pending_proposal_accepted" and JSON.digest([&1]) === event_sha256)
           ),
         operation = event["facts"]["operation_id"],
         [intent] <-
           Enum.filter(
             events,
             &(&1["type"] === "pending_acceptance_intent" and &1["operation_id"] === operation)
           ),
         [result] <-
           Enum.filter(
             events,
             &(&1["type"] === "pending_acceptance_result" and &1["operation_id"] === operation)
           ),
         true <- result["status"] === "committed",
         {:ok, ^result} <-
           committed_result(event, intent, result["normalized_request"], result["receipt"]) do
      {:ok, %{event: event, intent: intent, result: result}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def resolve_committed(_, _, _), do: @error

  @doc """
  Retain an original management journal and resolve its exact committed link.

  The home, project and namespace are selected by the host. The supplied link
  is untrusted until the caller also checks it against the held Collection.
  This does not establish current source, policy or output authority.
  """
  def with_committed_management_journal(home, project, namespace, link, fun)
      when is_binary(home) and is_map(link) and is_function(fun, 1) do
    with_management_journal(home, project, namespace, link, false, fn resolved, _ ->
      fun.(resolved)
    end)
  end

  def with_committed_management_journal(_, _, _, _, _), do: @error

  @doc "Retain a bounded ordered set of committed review journals for one current-use callback."
  def with_committed_management_journals(home, project, namespace, links, fun)
      when is_list(links) and is_function(fun, 1) do
    with true <- length(links) <= 128 and Enum.all?(links, &is_map/1),
         links =
           links
           |> Enum.uniq()
           |> Enum.sort_by(&{&1["journal_id"], &1["acceptance_event_sha256"]}),
         true <- length(Enum.uniq_by(links, & &1["journal_id"])) === length(links) do
      retain_management_journals(home, project, namespace, links, %{}, fun)
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def with_committed_management_journals(_, _, _, _, _), do: @error

  defp retain_management_journals(_, _, _, [], resolved, fun), do: fun.(resolved)

  defp retain_management_journals(home, project, namespace, [link | rest], resolved, fun) do
    with_committed_management_journal(home, project, namespace, link, fn checked ->
      retain_management_journals(
        home,
        project,
        namespace,
        rest,
        Map.put(resolved, link["journal_id"], checked),
        fun
      )
    end)
  end

  @doc "Retain an authenticated inactive management journal with a private transferable lock."
  def with_shareable_committed_management_journal(home, project, namespace, link, fun)
      when is_binary(home) and is_map(link) and is_function(fun, 2) do
    with_shareable_committed_management_journals(home, project, namespace, [link], fn resolved,
                                                                                      [lease] ->
      fun.(Map.fetch!(resolved, link["journal_id"]), lease.token)
    end)
  end

  def with_shareable_committed_management_journal(_, _, _, _, _), do: @error

  @doc false
  def with_shareable_committed_management_journals(home, project, namespace, links, fun)
      when is_list(links) and is_function(fun, 2) do
    with true <- length(links) in 1..128 and Enum.all?(links, &is_map/1),
         links =
           Enum.sort_by(Enum.uniq(links), &{&1["journal_id"], &1["acceptance_event_sha256"]}),
         true <- length(Enum.uniq_by(links, & &1["journal_id"])) == length(links),
         nil <- Process.get(@journal_share_slot) do
      Process.put(@journal_share_slot, %{})

      try do
        retain_shareable_journals(home, project, namespace, links, %{}, [], fun)
      after
        Process.delete(@journal_share_slot)
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def with_shareable_committed_management_journals(_, _, _, _, _), do: @error

  defp retain_shareable_journals(_, _, _, [], resolved, leases, fun), do: fun.(resolved, leases)

  defp retain_shareable_journals(home, project, namespace, [link | rest], resolved, leases, fun) do
    with_management_journal(home, project, namespace, link, true, fn checked, token ->
      retain_shareable_journals(
        home,
        project,
        namespace,
        rest,
        Map.put(resolved, link["journal_id"], checked),
        leases ++ [%{journal_id: link["journal_id"], link: link, token: token}],
        fun
      )
    end)
  end

  defp with_management_journal(home, project, namespace, link, shareable, fun) do
    with true <-
           Path.type(home) == :absolute and JSON.sha256?(project) and JSON.sha256?(namespace),
         true <- not shareable or is_map(Process.get(@journal_share_slot)),
         true <- link["journal_kind"] === "knowledge_management" and id?(link["journal_id"]),
         true <- JSON.sha256?(link["acceptance_event_sha256"]),
         directory = Path.join(home, "knowledge-management"),
         id = link["journal_id"],
         lock_path = Path.join(directory, id <> ".lock"),
         path = Path.join(directory, id <> ".jsonl"),
         {:ok, before_lock} <- File.lstat(lock_path),
         true <- journal_private?(before_lock),
         {:ok, lock} <-
           if(shareable,
             do: Ipse.Runner.share_source_lock(lock_path),
             else: Ipse.Runner.lock_source(lock_path)
           ) do
      monitor = :erlang.monitor(:port, lock)

      result =
        try do
          with true <-
                 journal_lock_live?(lock, monitor) and journal_same_lock?(lock_path, before_lock),
               {:ok, token} <- prepare_journal_share(shareable, lock, before_lock, link),
               {:ok, file} <- :file.open(String.to_charlist(path), [:read, :binary, :raw]) do
            try do
              with {:ok, before} <- :file.read_file_info(file),
                   {:ok, stats} <- Ipse.Journal.scan_file(file, nil, :load),
                   true <- stats.tail === :none,
                   metadata when is_map(metadata) <- (List.first(stats.events) || %{})["metadata"],
                   true <-
                     metadata["kind"] === "knowledge_management" and
                       metadata["project_id"] === project and metadata["namespace"] === namespace,
                   true <-
                     metadata["native_journal_layout"] === Ipse.Journal.native_owner_layout() and
                       metadata["pending_acceptance_layout"] === @layout,
                   {:ok, origin} when is_map(origin) <-
                     Ipse.Journal.SourceOrigin.recorded(metadata, id),
                   :ok <- Ipse.Journal.SourceOrigin.check(file, path, id, metadata),
                   {:ok, resolved} <-
                     resolve_committed(stats.events, id, link["acceptance_event_sha256"]),
                   [_, note, _] <- resolved.intent["request"]["changes"],
                   {:ok, values} <-
                     accepted_values(resolved.event, note["value"]["valid_until_ms"]),
                   true <- values["link"] === link,
                   result = fun.(resolved, token),
                   true <- journal_unchanged?(file, before),
                   :ok <- Ipse.Journal.SourceOrigin.check(file, path, id, metadata),
                   true <-
                     journal_lock_live?(lock, monitor) and
                       journal_same_lock?(lock_path, before_lock) do
                result
              else
                _ -> @error
              end
            after
              :file.close(file)
            end
          else
            _ -> @error
          end
        rescue
          _ -> @error
        catch
          _, _ -> @error
        end

      live = journal_lock_live?(lock, monitor)

      share =
        Enum.find(Process.get(@journal_share_slot) || %{}, fn {_, state} -> state.port == lock end)

      share_ok =
        not shareable or
          match?(
            {_, %{phase: phase}} when phase in [:ready, :settled],
            share
          )

      if shareable and match?({_, _}, share) do
        {token, _} = share
        Process.put(@journal_share_slot, Map.delete(Process.get(@journal_share_slot), token))
      end

      released =
        if shareable,
          do: Ipse.Runner.unlock_export_candidate(lock),
          else: Ipse.Runner.unlock(lock)

      Process.demonitor(monitor, [:flush])
      if live and share_ok and released == :ok, do: result, else: @error
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp prepare_journal_share(false, _, _, _), do: {:ok, nil}

  defp prepare_journal_share(true, port, before, link) do
    deadline = System.monotonic_time(:millisecond) + 5_000

    with shares when is_map(shares) and map_size(shares) < 128 <- Process.get(@journal_share_slot),
         {:os_pid, pid} when is_integer(pid) and pid > 0 <- Port.info(port, :os_pid),
         {:ok, %{device: device, inode: inode}} <-
           Ipse.Runner.session_header_lock_identity(port, deadline),
         true <- device == before.major_device and inode == before.inode do
      token = make_ref()

      put_journal_share(token, %{
        token: token,
        link: link,
        owner: self(),
        port: port,
        identity: %{pid: pid, device: device, inode: inode},
        phase: :ready
      })

      {:ok, token}
    else
      _ -> @error
    end
  end

  @doc false
  def journal_share_identity(token) do
    case journal_share(token) do
      %{token: ^token, owner: owner, port: port, identity: identity, phase: :ready}
      when owner == self() ->
        if Port.info(port, :connected) == {:connected, owner}, do: {:ok, identity}, else: @error

      _ ->
        @error
    end
  rescue
    _ -> @error
  end

  @doc false
  def journal_share_verified_identity(token, link) do
    with %{link: ^link} <- journal_share(token),
         {:ok, identity} <- journal_share_identity(token),
         do: {:ok, identity},
         else: (_ -> @error)
  end

  @doc false
  def journal_share_export(token, operation, recipient, deadline) do
    case journal_share(token) do
      %{token: ^token, owner: owner, port: port, phase: :ready} = state when owner == self() ->
        put_journal_share(token, %{state | phase: :poisoned})

        if Ipse.Runner.session_share_export(port, 1, 1, operation, recipient, deadline) == :ok do
          put_journal_share(
            token,
            Map.merge(state, %{phase: :shared, operation: operation})
          )

          :ok
        else
          @error
        end

      _ ->
        @error
    end
  end

  @doc false
  def journal_share_settle(token, operation, deadline) do
    case journal_share(token) do
      %{token: ^token, owner: owner, port: port, phase: :shared, operation: ^operation} = state
      when owner == self() ->
        put_journal_share(token, %{state | phase: :poisoned})

        if Ipse.Runner.session_share_settle(port, 2, 1, operation, deadline) == :ok do
          put_journal_share(token, %{state | phase: :settled})
          :ok
        else
          @error
        end

      _ ->
        @error
    end
  end

  defp journal_share(token), do: Map.get(Process.get(@journal_share_slot) || %{}, token)

  defp put_journal_share(token, state),
    do: Process.put(@journal_share_slot, Map.put(Process.get(@journal_share_slot), token, state))

  defp journal_private?(stat),
    do: stat.type == :regular and stat.links == 1 and Bitwise.band(stat.mode, 0o077) == 0

  defp journal_same_lock?(path, original) do
    case File.lstat(path) do
      {:ok, now} ->
        journal_private?(now) and
          {now.major_device, now.minor_device, now.inode, now.uid} ===
            {original.major_device, original.minor_device, original.inode, original.uid}

      _ ->
        false
    end
  end

  defp journal_unchanged?(file, before) do
    fields = ~w(size mtime ctime mode links major_device minor_device inode uid gid)a

    case :file.read_file_info(file) do
      {:ok, after_info} ->
        Map.take(File.Stat.from_record(before), fields) ===
          Map.take(File.Stat.from_record(after_info), fields)

      _ ->
        false
    end
  end

  defp journal_lock_live?(lock, monitor) do
    Port.info(lock, :connected) == {:connected, self()} and
      receive do
        {:DOWN, ^monitor, :port, ^lock, _} -> false
        {^lock, {:exit_status, _}} -> false
        {:EXIT, ^lock, _} -> false
      after
        0 -> true
      end
  rescue
    _ -> false
  end

  defp effect_history(events) do
    Enum.reduce_while(events, {:ok, %{accepted: %{}, effects: %{}}}, fn event, {:ok, state} ->
      case event["type"] do
        "pending_proposal_accepted" ->
          {:cont, {:ok, put_in(state, [:accepted, event["facts"]["operation_id"]], event)}}

        "pending_acceptance_intent" ->
          operation = event["operation_id"]
          accepted = state.accepted[operation]

          with true <- is_map(accepted) and not Map.has_key?(state.effects, operation),
               {:ok, ^event} <- effect_intent(accepted, event["request"]) do
            {:cont, {:ok, put_in(state, [:effects, operation], %{intent: event, result: nil})}}
          else
            _ -> {:halt, @error}
          end

        "pending_acceptance_result" ->
          operation = event["operation_id"]

          with %{intent: intent, result: nil} <- state.effects[operation],
               {:ok, ^event} <-
                 if(event["status"] === "committed",
                   do:
                     committed_result(
                       state.accepted[operation],
                       intent,
                       event["normalized_request"],
                       event["receipt"]
                     ),
                   else: effect_result(intent, event["status"])
                 ) do
            {:cont, {:ok, put_in(state, [:effects, operation, :result], event)}}
          else
            _ -> {:halt, @error}
          end

        _ ->
          {:cont, {:ok, state}}
      end
    end)
    |> case do
      {:ok, state} -> {:ok, state.effects}
      error -> error
    end
  end

  @doc """
  Build exact card facts from a host-authenticated observation and matching
  source proofs. Historical proofs describe the signed proposal; publication
  requires independent fresh source verification under its actual owner.
  """
  def prepare(context, managed, verified_sources, now) do
    with true <- context?(context) and JSON.safe_uint?(now),
         true <- exact?(managed, ~w(metadata observation)),
         observation when is_map(observation) <- managed["observation"],
         record when is_map(record) <- get_in(observation, ["value", "record"]),
         metadata when is_map(metadata) <- managed["metadata"],
         "pending." <> id <- record["key"],
         true <- JSON.sha256?(id),
         value when is_map(value) <- record["value"],
         true <- proposal?(value, id),
         true <-
           observation["request_sha256"] ===
             JSON.digest([%{"op" => "get_record", "key" => record["key"]}]),
         true <- observation["result_sha256"] === JSON.digest([%{"record" => record}]),
         bytes = Migration.encode(value),
         true <- byte_size(bytes) <= 6144 and record["sha256"] === JSON.sha256(bytes),
         true <- positive?(record["revision"]),
         witness when is_map(witness) <- observation["witness"],
         true <- witness["root_state"] === "present" and JSON.sha256?(witness["root_sha256"]),
         root when is_map(root) <- witness["root"],
         true <-
           root["project"] === context["namespace"] and
             root["manifest"] === witness["manifest_sha256"],
         true <- JSON.sha256(Jason.encode!(root)) === witness["root_sha256"],
         true <- record["revision"] <= root["generation"],
         {:ok, candidate} <-
           ManagedRecipe.extract(context["recipe"], record["key"], value, verified_sources),
         true <- candidate["kind"] === "proposal" and candidate["lineage"] === metadata["lineage"],
         true <- candidate["recipe_sha256"] === metadata["recipe_sha256"],
         true <-
           candidate["category"] === metadata["category"] and
             metadata["eligibility"] === "never_current",
         true <- JSON.sha256?(metadata["policy_sha256"]),
         true <-
           JSON.safe_uint?(metadata["first_admitted_ms"]) and
             metadata["first_admitted_ms"] <= now and JSON.safe_uint?(metadata["valid_until_ms"]) and
             now < metadata["valid_until_ms"],
         true <-
           is_binary(value["reason"]) and String.valid?(value["reason"]) and
             byte_size(value["reason"]) in 1..256,
         [proof] <- candidate["sources"],
         facts = %{
           "version" => 1,
           "kind" => "pending_proposal_card",
           "operation_id" => context["operation_id"],
           "journal_id" => context["journal_id"],
           "client_id" => context["client_id"],
           "session_id" => context["session_id"],
           "project_id" => context["project_id"],
           "namespace" => context["namespace"],
           "binding_sha256" => context["binding_sha256"],
           "policy_sha256" => context["policy_sha256"],
           "capture_epoch" => context["capture_epoch"],
           "render_revision" => context["render_revision"],
           "pending_key" => record["key"],
           "candidate_id" => id,
           "record_schema_version" => value["version"],
           "record_revision" => record["revision"],
           "record_sha256" => record["sha256"],
           "lineage" => candidate["lineage"],
           "text" => candidate["text"],
           "text_sha256" => JSON.sha256(candidate["text"]),
           "assigned_category" => candidate["category"],
           "reason" => value["reason"],
           "source_proof" => proof,
           "recipe_sha256" => candidate["recipe_sha256"],
           "publication_policy_sha256" => metadata["policy_sha256"],
           "first_admitted_ms" => metadata["first_admitted_ms"],
           "valid_until_ms" => metadata["valid_until_ms"],
           "root_sha256" => witness["root_sha256"]
         },
         facts =
           if(Map.has_key?(context, "batch"),
             do: Map.put(facts, "batch", context["batch"]),
             else: facts
           ),
         true <- facts?(facts),
         {:ok, display, _} <- Review.preview_display("accept", facts),
         true <- byte_size(display) <= review_display_limit(facts) do
      {:ok, facts}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Consume the live same-owner permit only after caller revalidation; this does not publish."
  def consume(permit, facts, now) do
    with true <- facts?(facts) and JSON.safe_uint?(now) and now < facts["valid_until_ms"],
         {:ok, receipt} <- Review.consume(permit, "accept", facts),
         {:ok, ^receipt} <- Review.consumed_receipt(permit, "accept", facts),
         true <-
           review?(receipt, facts) and receipt["observed_at_ms"] <= now and
             receipt["observed_at_ms"] >= facts["first_admitted_ms"] and
             receipt["observed_at_ms"] < facts["valid_until_ms"] do
      {:ok, event(facts, receipt)}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Inspect the exact pending event for bounded planning without consuming authority."
  def preview(permit, facts, now) do
    with true <- facts?(facts) and JSON.safe_uint?(now) and now < facts["valid_until_ms"],
         {:ok, receipt} <- Review.preview_receipt(permit, "accept", facts),
         true <-
           review?(receipt, facts) and receipt["observed_at_ms"] <= now and
             receipt["observed_at_ms"] >= facts["first_admitted_ms"] and
             receipt["observed_at_ms"] < facts["valid_until_ms"] do
      {:ok, event(facts, receipt)}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp event(facts, receipt),
    do: %{
      "type" => "pending_proposal_accepted",
      "version" => 1,
      "facts" => facts,
      "review" => receipt
    }

  @doc "Check historical event structure; it is not a current permit or publication authority."
  def valid_event?(event) do
    exact?(event, ~w(type version facts review)) and event["type"] === "pending_proposal_accepted" and
      event["version"] === 1 and facts?(event["facts"]) and
      review?(event["review"], event["facts"]) and
      event["review"]["observed_at_ms"] >= event["facts"]["first_admitted_ms"] and
      event["review"]["observed_at_ms"] < event["facts"]["valid_until_ms"]
  rescue
    _ -> false
  end

  @doc "Validate card shape only; this does not authenticate its source or grant authority."
  def valid_facts?(facts) do
    facts?(facts)
  rescue
    _ -> false
  end

  @doc false
  def review_display_limit(facts), do: if(Map.has_key?(facts, "batch"), do: 65_536, else: 8192)

  @doc """
  Construct the bounded accepted-decision and immutable link values for an event.

  This is a pure encoding operation. The caller must authenticate the native
  review, original source, current policy and signed deadlines under the actual
  owners, and derive the accepted deadline from that policy. Neither the event
  nor these values are a permit or evidence of publication.
  """
  def accepted_values(event, valid_until_ms) do
    with true <- valid_event?(event),
         facts = event["facts"],
         true <- is_nil(facts["session_id"]) or facts["session_id"] === facts["journal_id"],
         accepted_at = event["review"]["observed_at_ms"],
         true <-
           if(is_nil(valid_until_ms),
             do: facts["assigned_category"] in ~w(preference current),
             else: JSON.safe_uint?(valid_until_ms) and valid_until_ms > accepted_at
           ),
         lineage = accepted_lineage(facts),
         note_key = "note." <> lineage,
         link_key = "accept." <> facts["candidate_id"],
         event_sha256 = JSON.digest([event]),
         link = %{
           "version" => 1,
           "kind" => "candidate_acceptance_link",
           "candidate_id" => facts["candidate_id"],
           "journal_id" => facts["journal_id"],
           "journal_kind" =>
             if(is_nil(facts["session_id"]), do: "knowledge_management", else: "session"),
           "pending_key" => facts["pending_key"],
           "pending_revision" => facts["record_revision"],
           "pending_value_sha256" => facts["record_sha256"],
           "original_lineage" => facts["lineage"],
           "accepted_note_key" => note_key,
           "acceptance_event_sha256" => event_sha256,
           "source_proof_sha256" => JSON.digest([facts["source_proof"]])
         },
         link_bytes = Migration.encode(link),
         note = %{
           "version" => 1,
           "kind" => "accepted_decision",
           "lineage" => lineage,
           "candidate_id" => facts["candidate_id"],
           "text" => facts["text"],
           "category" => facts["assigned_category"],
           "reason" => facts["reason"],
           "source_proof" => facts["source_proof"],
           "acceptance_event_sha256" => event_sha256,
           "acceptance_link_sha256" => JSON.sha256(link_bytes),
           "accepted_at_ms" => accepted_at,
           "valid_until_ms" => valid_until_ms
         },
         note_bytes = Migration.encode(note),
         true <- byte_size(link_bytes) <= 6144 and byte_size(note_bytes) <= 6144 do
      {:ok,
       %{
         "note_key" => note_key,
         "note" => note,
         "note_sha256" => JSON.sha256(note_bytes),
         "link_key" => link_key,
         "link" => link,
         "link_sha256" => JSON.sha256(link_bytes)
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Check exact structural linkage only; current-use authority must be checked separately."
  def valid_accepted_values?(event, values) when is_map(values) do
    with note when is_map(note) <- values["note"],
         {:ok, expected} <- accepted_values(event, note["valid_until_ms"]) do
      values === expected
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def valid_accepted_values?(_, _), do: false

  @doc "Derive the intended note key from a validated acceptance event; proves neither publication nor current eligibility."
  def accepted_note_key(event) do
    if valid_event?(event), do: {:ok, "note." <> accepted_lineage(event["facts"])}, else: @error
  rescue
    _ -> @error
  end

  @doc """
  Check a retained accepted-decision target for native management.

  The caller must authenticate the anchor/live rows and same-root record/link
  under Identity and management Consent. Eligibility tag 3 binds this distinct
  representation; the literal recipe supplies category limits only. This does
  not authenticate current sources, the original review journal, or later use.
  A stored native retention choice must bind this exact unchanged value; it may
  override the effective category/deadline while original clocks remain separate.
  Expired targets remain removable. No returned value grants a Review permit.
  """
  def retained_decision_metadata(recipe, record, link, anchor, live) do
    with true <- ManagedRecipe.valid?(recipe) and recipe["kind"] === "literal_source",
         true <- recipe["key_prefix"] === "note.",
         note when is_map(note) <- record["value"],
         true <-
           exact?(
             note,
             ~w(version kind lineage candidate_id text category reason source_proof acceptance_event_sha256 acceptance_link_sha256 accepted_at_ms valid_until_ms)
           ),
         true <- note["version"] === 1 and note["kind"] === "accepted_decision",
         true <-
           is_binary(note["text"]) and String.valid?(note["text"]) and
             byte_size(note["text"]) in 1..2048,
         true <-
           is_binary(note["reason"]) and String.valid?(note["reason"]) and
             byte_size(note["reason"]) in 1..256,
         true <-
           Enum.all?(
             ~w(lineage candidate_id acceptance_event_sha256 acceptance_link_sha256),
             &JSON.sha256?(note[&1])
           ),
         {:ok, original_lineage} <- ManagedRecipe.source_identity(note["source_proof"]),
         {:ok, candidate_id} <- ManagedRecipe.proposal_identity(original_lineage, note["text"]),
         true <- candidate_id === note["candidate_id"],
         lineage =
           accepted_lineage(%{"candidate_id" => candidate_id, "lineage" => original_lineage}),
         true <- note["lineage"] === lineage and record["key"] === "note." <> lineage,
         true <- record["sha256"] === JSON.sha256(Migration.encode(note)),
         true <- record["bytes"] === byte_size(Migration.encode(note)),
         true <- positive?(record["revision"]) and id?(record["operation_id"]),
         value when is_map(value) <- link["value"],
         true <-
           exact?(
             value,
             ~w(version kind candidate_id journal_id journal_kind pending_key pending_revision pending_value_sha256 original_lineage accepted_note_key acceptance_event_sha256 source_proof_sha256)
           ),
         true <- value["version"] === 1 and value["kind"] === "candidate_acceptance_link",
         true <-
           value["candidate_id"] === candidate_id and
             value["original_lineage"] === original_lineage,
         true <-
           value["accepted_note_key"] === record["key"] and
             value["pending_key"] === "pending." <> candidate_id,
         true <-
           id?(value["journal_id"]) and value["journal_kind"] in ~w(session knowledge_management),
         true <-
           positive?(value["pending_revision"]) and JSON.sha256?(value["pending_value_sha256"]),
         true <- value["acceptance_event_sha256"] === note["acceptance_event_sha256"],
         true <- value["source_proof_sha256"] === JSON.digest([note["source_proof"]]),
         true <- link["key"] === "accept." <> candidate_id,
         true <-
           link["revision"] === record["revision"] and
             link["operation_id"] === record["operation_id"],
         true <-
           link["sha256"] === JSON.sha256(Migration.encode(value)) and
             link["sha256"] === note["acceptance_link_sha256"],
         true <- link["bytes"] === byte_size(Migration.encode(value)),
         {:ok, _} <- ManagedPages.pack(:anchor, ManagedPages.zero(:anchor), %{lineage => anchor}),
         %{"clocks" => [first, baseline, _, _], "choice" => choice, "retirement" => nil} <- anchor,
         true <-
           JSON.safe_uint?(first) and JSON.safe_uint?(note["accepted_at_ms"]) and
             first <= note["accepted_at_ms"],
         deadline = note["valid_until_ms"],
         true <-
           if(is_nil(deadline),
             do: note["category"] in ~w(preference current),
             else: JSON.safe_uint?(deadline) and deadline > note["accepted_at_ms"]
           ),
         true <-
           is_nil(baseline) or
             (JSON.safe_uint?(baseline) and not is_nil(deadline) and deadline <= baseline),
         rule when is_map(rule) <-
           Enum.find(recipe["rules"], &(&1["category"] === note["category"])),
         age = rule["max_age_ms"],
         true <-
           is_nil(age) or
             (JSON.safe_uint?(age) and JSON.safe_uint?(first + age) and not is_nil(baseline) and
                baseline <= first + age),
         {:ok, category, effective_deadline} <- accepted_retention(note, record, choice),
         [_, _, _, packed_policy, _, _, _, 3] <- live,
         policy =
           packed_policy |> Base.url_decode64!(padding: false) |> Base.encode16(case: :lower),
         true <- JSON.sha256?(policy),
         true <-
           live ===
             live_row(
               lineage,
               record["sha256"],
               JSON.digest([recipe]),
               policy,
               first,
               effective_deadline,
               category,
               3
             ) do
      metadata = %{
        "lineage" => lineage,
        "recipe_sha256" => JSON.digest([recipe]),
        "policy_sha256" => policy,
        "first_admitted_ms" => first,
        "valid_until_ms" => effective_deadline,
        "category" => category,
        "management_target" => "accepted_decision"
      }

      {:ok, if(is_nil(choice), do: metadata, else: Map.put(metadata, "choice", choice))}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Pure elapsed-deadline check for authenticated retained accepted metadata; grants no publication authority."
  def expired_retained_decision_metadata?(metadata, now) do
    fields =
      ~w(lineage recipe_sha256 policy_sha256 first_admitted_ms valid_until_ms category management_target)

    fields = if is_nil(metadata["choice"]), do: fields, else: ["choice" | fields]

    exact?(metadata, fields) and
      metadata["management_target"] === "accepted_decision" and
      metadata["category"] in ~w(ordinary preference current pin) and
      JSON.safe_uint?(now) and JSON.safe_uint?(metadata["first_admitted_ms"]) and
      JSON.safe_uint?(metadata["valid_until_ms"]) and metadata["valid_until_ms"] > 0 and
      metadata["first_admitted_ms"] < metadata["valid_until_ms"] and
      metadata["valid_until_ms"] <= now
  rescue
    _ -> false
  end

  defp accepted_retention(note, _record, nil), do: {:ok, note["category"], note["valid_until_ms"]}

  defp accepted_retention(note, record, choice) do
    with true <- choice["kind"] === "native_management",
         true <- choice["lineage"] === note["lineage"] and choice["target_key"] === record["key"],
         true <- choice["target_value_sha256"] === record["sha256"],
         true <- choice["observed_at_ms"] >= note["accepted_at_ms"],
         do:
           Ipse.Extension.Collection.ManagedRetention.selected(
             choice["policy"],
             choice["observed_at_ms"]
           ),
         else: (_ -> @error)
  end

  @doc "Check an accepted note and link against already authenticated rows; this grants no current-use authority."
  def stored_decision_metadata(event, recipe, record, link, anchor, live, now) do
    with true <- valid_event?(event) and JSON.safe_uint?(now),
         note when is_map(note) <- record["value"],
         {:ok, values} <- accepted_values(event, note["valid_until_ms"]),
         true <- record["key"] === values["note_key"] and record["value"] === values["note"],
         true <- link["key"] === values["link_key"] and link["value"] === values["link"],
         true <- record["operation_id"] === event["facts"]["operation_id"],
         true <- link["operation_id"] === event["facts"]["operation_id"],
         {:ok, retained} <- retained_decision_metadata(recipe, record, link, anchor, live),
         true <- retained["policy_sha256"] === event["facts"]["policy_sha256"],
         true <- retained["first_admitted_ms"] <= event["review"]["observed_at_ms"],
         true <- retained["first_admitted_ms"] <= now,
         true <- is_nil(retained["valid_until_ms"]) or now < retained["valid_until_ms"],
         metadata =
           retained
           |> Map.delete("management_target")
           |> Map.merge(%{
             "acceptance_event_sha256" => JSON.digest([event]),
             "source_proof" => event["facts"]["source_proof"]
           }),
         metadata =
           if(is_nil(retained["choice"]),
             do: metadata,
             else: Map.put(metadata, "record_value_sha256", record["sha256"])
           ),
         true <- accepted_retention_metadata?(event, metadata, now) do
      {:ok, metadata}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Pure consistency of an authenticated accepted category or native retention choice; grants no lease."
  def accepted_retention_metadata?(event, metadata, now) do
    with true <- valid_event?(event) and JSON.safe_uint?(now),
         lineage = accepted_lineage(event["facts"]),
         true <- metadata["lineage"] === lineage do
      case metadata["choice"] do
        nil ->
          metadata["category"] === event["facts"]["assigned_category"]

        choice ->
          with true <- JSON.sha256?(metadata["record_value_sha256"]),
               true <- choice["kind"] === "native_management" and choice["lineage"] === lineage,
               true <- choice["target_key"] === "note." <> lineage,
               true <- choice["target_value_sha256"] === metadata["record_value_sha256"],
               true <-
                 choice["observed_at_ms"] >= event["review"]["observed_at_ms"] and
                   choice["observed_at_ms"] <= now,
               anchor = %{
                 "clocks" => [metadata["first_admitted_ms"], nil, nil, nil],
                 "choice" => choice,
                 "retirement" => nil
               },
               {:ok, _} <-
                 ManagedPages.pack(:anchor, ManagedPages.zero(:anchor), %{lineage => anchor}),
               {:ok, category, deadline} <-
                 Ipse.Extension.Collection.ManagedRetention.selected(
                   choice["policy"],
                   choice["observed_at_ms"]
                 ),
               do: metadata["category"] === category and metadata["valid_until_ms"] === deadline,
               else: (_ -> false)
      end
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc "Check current semantic policy for an already authenticated accepted decision; grants no lease."
  def accepted_use_policy(event, metadata, policy, recipe, now) do
    with true <- valid_event?(event) and is_map(metadata) and JSON.safe_uint?(now),
         true <- Ipse.Extension.SemanticConsent.policy?(policy),
         true <- policy["project"] === event["facts"]["project_id"],
         true <- get_in(policy, ["settings", "namespace"]) === event["facts"]["namespace"],
         true <- now < policy["expires_at_ms"],
         true <- ManagedRecipe.valid?(recipe) and recipe["kind"] === "literal_source",
         true <- metadata["recipe_sha256"] === JSON.digest([recipe]),
         true <- metadata["acceptance_event_sha256"] === JSON.digest([event]),
         true <- metadata["source_proof"] === event["facts"]["source_proof"],
         true <- accepted_retention_metadata?(event, metadata, now),
         deadline = metadata["valid_until_ms"],
         true <- is_nil(deadline) or (JSON.safe_uint?(deadline) and now < deadline),
         settings = policy["settings"],
         recipe_sha = JSON.digest([recipe]),
         true <-
           Enum.any?(settings["effects"], fn mapping ->
             mapping["class"] === "collection.publish" and mapping["recipe_sha256"] === recipe_sha and
               Ipse.Extension.SemanticConsent.recipe(settings, mapping) === {:ok, recipe}
           end),
         true <-
           Enum.any?(settings["effects"], fn mapping ->
             mapping["class"] === "collection.read" and
               mapping["inner_op"] === "collection.call" and
               case Ipse.Extension.SemanticConsent.managed_recipes(settings, mapping) do
                 {:ok, recipes} -> recipe in recipes
                 _ -> false
               end
           end),
         :ok <-
           Ipse.Extension.SemanticConsent.check_sources(policy, [
             %{
               "category" => event["facts"]["source_proof"]["origin"],
               "path" => event["facts"]["source_proof"]["path"]
             }
           ]) do
      {:ok,
       if(is_nil(deadline),
         do: policy["expires_at_ms"],
         else: min(deadline, policy["expires_at_ms"])
       )}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc """
  Derive a bounded accepted-decision clock from an already authenticated anchor.

  This pure calculation does not authenticate the event, recipe, prior anchor,
  source or policy. The caller must obtain those under the actual owners. A
  prior native choice or retirement refuses: neither may be erased or renewed.
  The literal recipe supplies only the category retention bound; it does not
  relabel the candidate's source or establish literal-source eligibility.
  """
  def retention_plan(event, recipe, prior, policy_deadline, now) do
    with true <- valid_event?(event) and JSON.safe_uint?(now),
         facts = event["facts"],
         at = event["review"]["observed_at_ms"],
         true <- at <= now and now < facts["valid_until_ms"],
         true <-
           ManagedRecipe.valid?(recipe) and recipe["kind"] === "literal_source" and
             recipe["key_prefix"] === "note.",
         rule when is_map(rule) <-
           Enum.find(recipe["rules"], &(&1["category"] === facts["assigned_category"])),
         true <- is_nil(policy_deadline) or JSON.safe_uint?(policy_deadline),
         lineage = accepted_lineage(facts),
         {:ok, row} <- accepted_anchor(prior, lineage),
         %{"clocks" => [old_first, old_baseline, pending, pending_baseline]} <- row,
         true <- (is_nil(old_first) or old_first <= at) and (is_nil(pending) or pending <= at),
         first = old_first || at,
         age = rule["max_age_ms"],
         calculated = if(is_nil(age), do: nil, else: first + age),
         true <- is_nil(calculated) or JSON.safe_uint?(calculated),
         baseline = if(is_nil(old_first), do: calculated, else: earlier(old_baseline, calculated)),
         effective = earlier(baseline, policy_deadline),
         true <- is_nil(effective) or effective > now,
         updated = %{row | "clocks" => [first, baseline, pending, pending_baseline]},
         {:ok, _} <- ManagedPages.pack(:anchor, ManagedPages.zero(:anchor), %{lineage => updated}),
         {:ok, values} <- accepted_values(event, effective) do
      {:ok,
       %{
         "anchor" => updated,
         "first_admitted_ms" => first,
         "valid_until_ms" => effective,
         "recipe_sha256" => JSON.digest([recipe]),
         "values" => values
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp accepted_anchor(nil, _lineage),
    do: {:ok, %{"clocks" => [nil, nil, nil, nil], "choice" => nil, "retirement" => nil}}

  defp accepted_anchor(%{"choice" => nil, "retirement" => nil} = row, lineage) do
    case ManagedPages.pack(:anchor, ManagedPages.zero(:anchor), %{lineage => row}) do
      {:ok, _} -> {:ok, row}
      _ -> @error
    end
  end

  defp accepted_anchor(_, _), do: @error
  defp earlier(nil, value), do: value
  defp earlier(value, nil), do: value
  defp earlier(a, b), do: min(a, b)

  @doc """
  Prepare public changes using an anchor authenticated at the held pending root.

  The caller supplies the actual same-owner Collection read closure and matching
  domain capability. This is not authority to publish: source, active consent,
  review consumption, sidecars, journal intent and native deadline still require
  their own checks under the appropriate owners.
  """
  def prepare_storage(event, recipe, policy_deadline, managed, cap, now, read)
      when is_function(read, 1) do
    with true <- valid_event?(event),
         facts = event["facts"],
         witness when is_map(witness) <- get_in(managed, ["observation", "witness"]),
         true <- witness["root_sha256"] === facts["root_sha256"],
         root when is_map(root) <- witness["root"],
         lineage = accepted_lineage(facts),
         true <- ManagedRecipe.valid?(recipe) and recipe["kind"] === "literal_source",
         {:ok, nil} <- read.("reject." <> facts["candidate_id"]),
         {:ok, nil} <- read.(recipe["override_prefix"] <> lineage),
         {:ok, prior} <- retained_anchor(cap, lineage, witness, root, read),
         {:ok, retention} <- retention_plan(event, recipe, prior, policy_deadline, now),
         {:ok, public} <- public_plan(event, retention["values"], managed, now, read) do
      {:ok, %{"retention" => retention, "prior_anchor" => prior, "public" => public}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def prepare_storage(_, _, _, _, _, _, _), do: @error

  @doc """
  Plan the exact signed-page edits for a prepared candidate without sealing them.

  The caller must use the original held read and capability. This checks old
  row values and page geometry, but grants no permission to sign or publish and
  does not establish source, policy, review or journal authority.
  """
  def plan_sidecars(event, prepared, cap, read) when is_function(read, 1) do
    with true <- valid_event?(event),
         facts = event["facts"],
         retention when is_map(retention) <- prepared["retention"],
         values when is_map(values) <- retention["values"],
         true <- valid_accepted_values?(event, values),
         true <- JSON.sha256?(retention["recipe_sha256"]),
         true <- JSON.safe_uint?(retention["first_admitted_ms"]),
         true <- retention["valid_until_ms"] === values["note"]["valid_until_ms"],
         lineage = values["note"]["lineage"],
         anchor = retention["anchor"],
         {:ok, _} <- ManagedPages.pack(:anchor, ManagedPages.zero(:anchor), %{lineage => anchor}),
         [first, _, _, _] <- anchor["clocks"],
         true <- first === retention["first_admitted_ms"],
         expected_anchor =
           if(is_nil(prepared["prior_anchor"]),
             do: :absent,
             else: {:equal, prepared["prior_anchor"]}
           ),
         old_live =
           live_row(
             facts["lineage"],
             facts["record_sha256"],
             facts["recipe_sha256"],
             facts["publication_policy_sha256"],
             facts["first_admitted_ms"],
             facts["valid_until_ms"],
             facts["assigned_category"],
             1
           ),
         new_live =
           live_row(
             lineage,
             values["note_sha256"],
             retention["recipe_sha256"],
             facts["policy_sha256"],
             first,
             retention["valid_until_ms"],
             facts["assigned_category"],
             3
           ),
         {:ok, anchors} <-
           ManagedPages.Planner.plan_checked(
             cap,
             :anchor,
             [{lineage, expected_anchor, anchor}],
             read
           ),
         {:ok, lives} <-
           ManagedPages.Planner.plan_checked(
             cap,
             :live,
             [
               {ManagedPages.live_identity(facts["pending_key"]), {:equal, old_live}, nil},
               {ManagedPages.live_identity(values["note_key"]), :absent, new_live}
             ],
             read
           ),
         true <-
           Enum.all?([anchors, lives], &(&1.witness["root_sha256"] === facts["root_sha256"])),
         changes = anchors.changes ++ lives.changes,
         true <- length(changes) <= 5,
         true <- Enum.count(changes, &is_nil(&1.body)) <= 1,
         true <- Enum.count(changes, &(not is_nil(&1.body))) <= 4,
         true <-
           Enum.all?(changes, &(is_nil(&1.body) or ManagedPages.encoded_size(&1.body) <= 6144)) do
      {:ok, %{anchor: anchors, live: lives}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def plan_sidecars(_, _, _, _), do: @error

  @doc """
  Retain one checked plan and expose a one-use sealing closure to its owner.

  Sealing requires the exact consumed native review, the same live Collection
  owner and matching domain capability. It does not authenticate current source
  or policy, append an intent, or grant publication authority; those remain
  caller obligations. The closure returns both the signed sidecar changes and
  their exact combined request, and expires when the callback returns.
  """
  def with_sidecar_plan(event, prepared, cap, read, fun)
      when is_function(read, 1) and is_function(fun, 2) do
    with %Ipse.Extension.ProjectIdentity.DomainAuth.Capability{owner: owner, seal: seal_fn} <- cap,
         true <- owner == self() and is_function(seal_fn, 2),
         {:ok, _intent} <- effect_intent(event, get_in(prepared, ["public", "request"])),
         deadline = get_in(prepared, ["retention", "valid_until_ms"]),
         true <- sealing_current?(event, deadline),
         {:ok, plans} <- plan_sidecars(event, prepared, cap, read),
         collection_cap when not is_nil(collection_cap) <-
           Process.get({Ipse.Extension.Collection, :lock_held}),
         :ok <- Ipse.Runner.Transaction.check(collection_cap) do
      owner = self()
      slot = {__MODULE__, make_ref()}
      Process.put(slot, {owner, collection_cap, plans})

      seal = fn permit ->
        if self() == owner do
          case Process.delete(slot) do
            {^owner, ^collection_cap, ^plans} ->
              seal_retained(event, prepared, plans, cap, collection_cap, permit, deadline)

            _ ->
              @error
          end
        else
          @error
        end
      end

      try do
        fun.(plans, seal)
      after
        Process.delete(slot)
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  def with_sidecar_plan(_, _, _, _, _), do: @error

  defp seal_retained(event, prepared, plans, cap, collection_cap, permit, deadline) do
    facts = event["facts"]
    pointer = plans.anchor.witness["root"]
    bytes = Jason.encode!(pointer)

    witness = %{
      "version" => 2,
      "root" => plans.anchor.summary,
      "root_state" => plans.anchor.witness["root_state"],
      "root_bytes" => bytes,
      "root_sha256" => plans.anchor.witness["root_sha256"],
      "manifest_sha256" => plans.anchor.witness["manifest_sha256"],
      "operation_id" => facts["operation_id"]
    }

    with true <- Process.get({Ipse.Extension.Collection, :lock_held}) === collection_cap,
         :ok <- Ipse.Runner.Transaction.check(collection_cap),
         {:ok, receipt} <- Review.consumed_receipt(permit, "accept", facts),
         true <- receipt === event["review"] and JSON.sha256(bytes) === facts["root_sha256"],
         true <- sealing_current?(event, deadline),
         {:ok, anchors} <- ManagedPages.Planner.seal_changes(cap, witness, plans.anchor),
         {:ok, lives} <- ManagedPages.Planner.seal_changes(cap, witness, plans.live),
         changes = anchors ++ lives,
         true <- length(changes) <= 5,
         public when is_map(public) <- get_in(prepared, ["public", "request"]),
         {:ok, intent} <- effect_intent(event, public),
         normalized = Map.update!(public, "changes", &(&1 ++ changes)),
         true <- Ipse.Extension.Collection.valid_request?(normalized),
         true <- sealing_current?(event, deadline),
         :ok <- Ipse.Runner.Transaction.check(collection_cap),
         :ok <- Review.bind_acceptance_request(permit, facts, intent, normalized, deadline) do
      {:ok, %{changes: changes, request: normalized}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp sealing_current?(event, deadline) do
    now = System.system_time(:millisecond)

    JSON.safe_uint?(now) and now < event["facts"]["valid_until_ms"] and
      (is_nil(deadline) or (JSON.safe_uint?(deadline) and now < deadline))
  end

  defp live_row(lineage, value, recipe, policy, first, deadline, category, eligibility) do
    packed =
      Enum.map([lineage, value, recipe, policy], fn hash ->
        Base.url_encode64(Base.decode16!(hash, case: :lower), padding: false)
      end)

    number = fn value ->
      if is_nil(value), do: nil, else: value |> Integer.to_string(36) |> String.downcase()
    end

    category =
      Map.fetch!(%{"ordinary" => 0, "preference" => 1, "current" => 2, "pin" => 3}, category)

    packed ++ [number.(first), number.(deadline), category, eligibility]
  end

  defp retained_anchor(cap, lineage, witness, root, read) do
    request = %{
      "op" => "neighbors",
      "request" => %{
        "version" => 1,
        "prefix" => ManagedPages.prefix(:anchor),
        "fence_bytes" => ManagedPages.width(:anchor),
        "needle" => lineage
      }
    }

    with {:ok, observation} <- read.(request),
         {:ok, %{kind: :anchor}} <- ManagedPages.observation(observation),
         true <-
           observation["witness"] === witness and
             observation["summary"]["version"] === 3 and
             Map.take(observation["summary"], ~w(project generation floor floor_anchor)) ===
               Map.take(root, ~w(project generation floor floor_anchor)),
         "initialized" <- observation["state"],
         key when is_binary(key) <- get_in(observation, ["neighbors", "selected", "key"]),
         {:ok, record} when is_map(record) <- read.(key),
         true <- record["revision"] <= root["generation"],
         {:ok, page} <- ManagedPages.open(cap, record, observation) do
      {:ok, page.entries[lineage]}
    else
      _ -> @error
    end
  end

  @doc """
  Build the three public CAS changes against an observed pending record.

  The read closure must belong to the same held Collection owner and root as
  the observation. This candidate does not check signed sidecars, suppression,
  source eligibility or current consent and must never be published by itself.
  The host normalizer must revalidate those facts, plan and seal all sidecars,
  and enforce the native final-decision deadline before mutation.
  """
  def public_plan(event, values, managed, now, read) when is_function(read, 1) do
    with true <- valid_accepted_values?(event, values) and JSON.safe_uint?(now),
         facts = event["facts"],
         true <- event["review"]["observed_at_ms"] <= now and now < facts["valid_until_ms"],
         true <- exact?(managed, ~w(metadata observation)),
         metadata when is_map(metadata) <- managed["metadata"],
         observation when is_map(observation) <- managed["observation"],
         record when is_map(record) <- get_in(observation, ["value", "record"]),
         witness when is_map(witness) <- observation["witness"],
         root when is_map(root) <- witness["root"],
         value when is_map(value) <- record["value"],
         true <- proposal?(value, facts["candidate_id"]),
         true <-
           record["key"] === facts["pending_key"] and
             record["revision"] === facts["record_revision"] and
             record["sha256"] === facts["record_sha256"] and
             record["sha256"] === JSON.sha256(Migration.encode(value)),
         true <-
           value["lineage"] === facts["lineage"] and value["text"] === facts["text"] and
             value["assigned_category"] === facts["assigned_category"] and
             value["reason"] === facts["reason"] and
             get_in(value, ["evidence", "sources"]) === [facts["source_proof"]],
         true <-
           metadata["lineage"] === facts["lineage"] and
             metadata["recipe_sha256"] === facts["recipe_sha256"] and
             metadata["policy_sha256"] === facts["publication_policy_sha256"] and
             metadata["category"] === facts["assigned_category"] and
             metadata["eligibility"] === "never_current" and
             metadata["first_admitted_ms"] === facts["first_admitted_ms"] and
             metadata["valid_until_ms"] === facts["valid_until_ms"],
         true <-
           witness["root_state"] === "present" and witness["root_sha256"] === facts["root_sha256"] and
             root["project"] === facts["namespace"] and
             root["manifest"] === witness["manifest_sha256"] and
             JSON.sha256(Jason.encode!(root)) === facts["root_sha256"] and
             positive?(root["generation"]) and root["generation"] >= record["revision"],
         true <-
           observation["request_sha256"] ===
             JSON.digest([%{"op" => "get_record", "key" => record["key"]}]) and
             observation["result_sha256"] === JSON.digest([%{"record" => record}]),
         {:ok, nil} <- read.(values["note_key"]),
         {:ok, nil} <- read.(values["link_key"]),
         request = %{
           "op" => "commit",
           "expected_generation" => root["generation"],
           "advance_floor" => true,
           "changes" => [
             %{"key" => record["key"], "expected_revision" => record["revision"], "value" => nil},
             %{"key" => values["note_key"], "expected_revision" => 0, "value" => values["note"]},
             %{"key" => values["link_key"], "expected_revision" => 0, "value" => values["link"]}
           ]
         },
         true <- Ipse.Extension.Collection.valid_request?(request),
         true <- byte_size(Migration.encode(request)) <= 65_536 do
      {:ok,
       %{
         "request" => request,
         "request_sha256" => JSON.digest([request]),
         "root_sha256" => facts["root_sha256"],
         "event_sha256" => JSON.digest([event]),
         "pending_sha256" => facts["record_sha256"],
         "note_sha256" => values["note_sha256"],
         "link_sha256" => values["link_sha256"]
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def public_plan(_, _, _, _, _), do: @error

  defp context?(c) do
    batch_shape?(c, @context) and Enum.all?(~w(operation_id journal_id client_id), &id?(c[&1])) and
      session_matches_journal?(c) and
      Enum.all?(~w(project_id namespace binding_sha256 policy_sha256), &JSON.sha256?(c[&1])) and
      positive?(c["capture_epoch"]) and positive?(c["render_revision"]) and
      ManagedRecipe.valid?(c["recipe"]) and c["recipe"]["kind"] === "proposal"
  end

  defp proposal?(value, id) do
    exact?(value, @proposal) and value["version"] === 1 and value["kind"] === "proposal" and
      value["state"] === "pending" and value["id"] === id and
      JSON.safe_uint?(value["created_at_ms"]) and JSON.safe_uint?(value["expires_at_ms"]) and
      (is_nil(value["event_at_ms"]) or JSON.safe_uint?(value["event_at_ms"])) and
      exact?(value["evidence"], ["sources"])
  end

  defp facts?(facts) do
    batch_shape?(facts, @facts) and
      (not Map.has_key?(facts, "batch") or
         Ipse.Session.PendingBatch.member?(facts["batch"], facts)) and
      facts["version"] === 1 and facts["kind"] === "pending_proposal_card" and
      Enum.all?(~w(operation_id journal_id client_id), &id?(facts[&1])) and
      session_matches_journal?(facts) and
      Enum.all?(
        ~w(project_id namespace binding_sha256 policy_sha256 candidate_id record_sha256 lineage text_sha256 recipe_sha256 publication_policy_sha256 root_sha256),
        &JSON.sha256?(facts[&1])
      ) and
      facts["pending_key"] === "pending." <> facts["candidate_id"] and
      facts["record_schema_version"] === 1 and
      positive?(facts["record_revision"]) and positive?(facts["capture_epoch"]) and
      positive?(facts["render_revision"]) and
      is_binary(facts["text"]) and String.valid?(facts["text"]) and
      byte_size(facts["text"]) in 1..2048 and
      facts["text_sha256"] === JSON.sha256(facts["text"]) and
      facts["assigned_category"] in ~w(ordinary preference current) and
      is_binary(facts["reason"]) and String.valid?(facts["reason"]) and
      byte_size(facts["reason"]) in 1..256 and
      ManagedRecipe.source_identity(facts["source_proof"]) === {:ok, facts["lineage"]} and
      ManagedRecipe.proposal_identity(facts["lineage"], facts["text"]) ===
        {:ok, facts["candidate_id"]} and
      JSON.safe_uint?(facts["first_admitted_ms"]) and JSON.safe_uint?(facts["valid_until_ms"]) and
      facts["first_admitted_ms"] < facts["valid_until_ms"] and
      byte_size(Jason.encode!(facts)) <= if(Map.has_key?(facts, "batch"), do: 16_384, else: 8192)
  end

  defp batch_shape?(value, keys),
    do:
      exact?(value, keys) or
        (exact?(value, keys ++ ["batch"]) and is_nil(value["session_id"]) and
           Ipse.Session.PendingBatch.valid_binding?(value["batch"]))

  defp review?(receipt, facts) do
    exact?(receipt, @receipt) and receipt["version"] === 1 and receipt["kind"] === "native_review" and
      receipt["command"] === "accept" and id?(receipt["event_id"]) and
      JSON.sha256?(receipt["display_sha256"]) and
      is_binary(receipt["challenge"]) and Regex.match?(~r/\A[0-9a-f]{16}\z/, receipt["challenge"]) and
      receipt["input_sha256"] === JSON.sha256("accept " <> receipt["challenge"]) and
      JSON.safe_uint?(receipt["observed_at_ms"]) and
      receipt["facts_sha256"] === JSON.digest([facts])
  end

  defp accepted_lineage(facts),
    do:
      JSON.digest([
        "ipse-knowledge",
        1,
        "accepted_decision",
        facts["candidate_id"],
        facts["lineage"]
      ])

  defp positive?(v), do: JSON.safe_uint?(v) and v > 0

  defp session_matches_journal?(value),
    do:
      is_nil(value["session_id"]) or
        (id?(value["session_id"]) and value["session_id"] === value["journal_id"])

  defp id?(v), do: is_binary(v) and Regex.match?(~r/\A[0-9a-f]{32}\z/, v)
  defp exact?(v, keys), do: is_map(v) and Enum.sort(Map.keys(v)) == Enum.sort(keys)
end
