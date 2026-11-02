defmodule Ipse.CLI.Knowledge.Management do
  @moduledoc "Standalone native review and owned protected retention management; starts no model or worker."
  alias Ipse.{JSON, Journal, Usage}
  alias Ipse.Journal.Writer
  alias Ipse.Runner.Review
  alias Ipse.Session.{Lock, ManagedLifecycle, Resources}

  alias Ipse.Extension.{
    Artifact,
    Bundles,
    Collection,
    Consent,
    ManagedCollectionCall,
    ManagedRecipe,
    ProjectIdentity,
    SemanticAdmission,
    SemanticConsent
  }

  alias Ipse.Extension.Collection.{ManagedRetention, NormalizerV3, ObservedRead}
  @error {:error, :knowledge_management_refused}

  @doc false
  def reviewed_publication_admission,
    do: {:error, :native_review_publication_fence_unavailable}

  def pending_metadata(config, cwd, after_key \\ nil) do
    home = config[:home]

    with true <-
           is_nil(after_key) or
             (is_binary(after_key) and String.starts_with?(after_key, "pending.")),
         {:ok, binding} when is_map(binding) <- ProjectIdentity.existing(home, cwd),
         {:ok, namespace} <- SemanticConsent.namespace(binding["project_id"], "knowledge"),
         control = SemanticAdmission.control_root(home),
         {:ok, snapshot} when is_map(snapshot) <-
           Consent.existing_snapshot(control, binding["project_id"]),
         true <- snapshot["epoch"] > 0 do
      ProjectIdentity.with_existing_domain_auth(
        home,
        cwd,
        binding,
        %{namespace: namespace, format: "managed-metadata-v3"},
        fn _, _ ->
          Consent.with_existing_management_snapshot(
            control,
            binding["project_id"],
            snapshot["epoch"],
            Consent.management_sha256(
              binding["project_id"],
              snapshot["epoch"],
              snapshot["policy"]
            ),
            fn _ ->
              with {:ok, observation} <-
                     ObservedRead.read(SemanticAdmission.collection_root(home), namespace, %{
                       "op" => "index",
                       "prefix" => "pending.",
                       "after" => after_key,
                       "generation" => nil,
                       "limit" => 32
                     }) do
                value = observation["value"]

                {:ok,
                 %{
                   "version" => 1,
                   "kind" => "historical_pending_index",
                   "project_id" => binding["project_id"],
                   "namespace" => namespace,
                   "generation" => value["generation"],
                   "records" => value["records"],
                   "count" => value["count"],
                   "next" => value["next"],
                   "partial" => not is_nil(after_key) or not is_nil(value["next"]),
                   "signed_deadlines" => "not_checked",
                   "current_note_eligibility" => "not_checked"
                 }}
              else
                _ -> @error
              end
            end
          )
        end
      )
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  # Choosing to review later has no stored effect and grants no attestation.
  # Read the exact signed historical candidate; never renew its clock or turn
  # deferral into a suppression, automatic acceptance or new capture operation.
  def defer(config, cwd, "pending." <> id = key) when is_map(config) and is_binary(cwd) do
    home = config[:home]

    with true <- JSON.sha256?(id),
         {:ok, binding} <- ProjectIdentity.existing(home, cwd),
         {:ok, namespace} <- SemanticConsent.namespace(binding["project_id"], "knowledge"),
         control = SemanticAdmission.control_root(home),
         {:ok, snapshot} <- Consent.existing_snapshot(control, binding["project_id"]),
         true <- snapshot["epoch"] > 0,
         {:ok, selected} <- selection(home) do
      ProjectIdentity.with_existing_domain_auth(
        home,
        cwd,
        binding,
        %{namespace: namespace, format: "managed-metadata-v3"},
        fn cap, catalog ->
          Consent.with_existing_management_snapshot(
            control,
            binding["project_id"],
            snapshot["epoch"],
            Consent.management_sha256(
              binding["project_id"],
              snapshot["epoch"],
              snapshot["policy"]
            ),
            fn _ ->
              ObservedRead.with_managed_proposal_removal(
                SemanticAdmission.collection_root(home),
                namespace,
                %{"op" => "get_record", "key" => key},
                cap,
                catalog,
                selected.proposal,
                fn managed ->
                  record = managed["observation"]["value"]["record"]
                  metadata = managed["metadata"]
                  now = System.system_time(:millisecond)

                  {:ok,
                   %{
                     "version" => 1,
                     "kind" => "pending_review_later",
                     "project_id" => binding["project_id"],
                     "key" => record["key"],
                     "revision" => record["revision"],
                     "record_sha256" => record["sha256"],
                     "first_admitted_ms" => metadata["first_admitted_ms"],
                     "valid_until_ms" => metadata["valid_until_ms"],
                     "observed_at_ms" => now,
                     "status" =>
                       if(now < metadata["valid_until_ms"], do: "pending", else: "expired"),
                     "stored_effect" => "none",
                     "source_eligibility" => "not_checked",
                     "acceptance" => "requires_fresh_native_review"
                   }}
                end
              )
            end
          )
        end
      )
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def defer(_, _, _), do: @error

  def review(config, cwd, history_dir, key), do: review(config, cwd, history_dir, key, nil)

  @doc false
  def review(config, cwd, history_dir, "pending." <> id = key, batch)
      when is_map(config) and is_binary(cwd) and is_binary(history_dir) do
    overall = System.monotonic_time(:millisecond) + 120_000

    with true <- JSON.sha256?(id) and Path.type(history_dir) === :absolute,
         :ok <- management_effect_mode(config),
         {:ok, selected} <- acceptance_source_selection(config, cwd, history_dir, Usage.id()),
         policy = selected.snapshot["policy"],
         true <-
           is_nil(batch) or
             (Ipse.Session.PendingBatch.selection?(
                batch,
                selected.binding,
                selected.context.config.semantic_admission["pin"],
                selected.selection.recipe,
                selected.selection.proposal,
                policy
              ) and
                Enum.at(batch["manifest"]["items"], batch["index"])["pending_key"] === key),
         request = %{
           "id" => Usage.id(),
           "operation" => "notes.capture",
           "artifact_sha256" => selected.selection.digest,
           "source_sha256" => policy["source_sha256"],
           "policy_sha256" => JSON.digest([policy]),
           "request_sha256" => acceptance_request_sha256(key, batch),
           "source_generation" => 0,
           "headless" => false,
           "reserved" =>
             Map.merge(Consent.zero(), %{
               "operations" => 1,
               "input_bytes" => 131_072,
               "output_bytes" => 16_384
             })
         },
         control = SemanticAdmission.control_root(config[:home]),
         project = selected.binding["project_id"],
         {:ok, ticket} <-
           Consent.reserve(control, project, request, System.system_time(:millisecond)) do
      case Consent.admit(control, project, ticket, System.system_time(:millisecond)) do
        {:ok, ^ticket} ->
          Ipse.CLI.Terminal.puts("Knowledge reservation: #{ticket["id"]}")

          result =
            accept_pending_candidate(
              config,
              cwd,
              history_dir,
              key,
              overall,
              %{ticket: ticket, request: request, batch: batch}
            )

          settle_acceptance_review(control, project, ticket, result)

        error ->
          case Consent.settle(control, project, ticket, :unstarted) do
            {:ok, _} -> error
            _ -> {:unknown, :acceptance_accounting_unconfirmed}
          end
      end
    else
      _ -> @error
    end
  rescue
    _ -> {:unknown, :acceptance_publication_unconfirmed}
  end

  def review(_, _, _, _, _), do: @error

  defp acceptance_request_sha256(key, nil), do: JSON.digest(["native_pending_review", 1, key])

  defp acceptance_request_sha256(key, batch),
    do: JSON.digest(["native_pending_review", 2, key, batch["manifest_sha256"], batch["index"]])

  defp settle_acceptance_review(control, project, ticket, result) do
    {outcome, reported} =
      case result do
        {:closed, {:ok, {:host_committed, event, receipt, actual}}} ->
          {:ok, accepted_note_key} = Ipse.Session.PendingAcceptance.accepted_note_key(event)

          packet = %{
            "journal_id" => event["facts"]["journal_id"],
            "event_sha256" => JSON.digest([event]),
            "receipt" => receipt
          }

          {{:known, actual, packet},
           {:ok, Map.put(packet, "accepted_note_key", accepted_note_key)}}

        {:closed, {:error, _} = error} ->
          {{:known, Consent.zero(), %{"refused" => true}}, error}

        {:error, _} = error ->
          {{:known, Consent.zero(), %{"refused" => true}}, error}

        _ ->
          {:unknown, {:unknown, :acceptance_publication_unconfirmed}}
      end

    case Consent.settle(control, project, ticket, outcome) do
      {:ok, _} -> reported
      _ -> {:unknown, :acceptance_accounting_unconfirmed}
    end
  end

  def forget(config, cwd, key) do
    case full_facts_forget_candidate(
           config,
           cwd,
           key,
           "Operator requested forgetting this selected note"
         ) do
      {:closed, result} -> result
      result -> result
    end
  end

  def expire(config, cwd, key), do: manage(config, cwd, key, :expiry)

  def reject(config, cwd, "pending." <> id = key) do
    if JSON.sha256?(id) do
      case full_facts_removal_candidate(
             config,
             cwd,
             key,
             "Operator rejected this selected proposal",
             :reject
           ) do
        {:closed, result} -> result
        result -> result
      end
    else
      @error
    end
  end

  def reject(_, _, _), do: @error

  def retain(config, cwd, key, policy) do
    cond do
      not ManagedRetention.policy?(policy) ->
        @error

      policy["kind"] == "session" ->
        case full_facts_forget_candidate(
               config,
               cwd,
               key,
               "Operator requested session-only retention"
             ) do
          {:closed, result} -> result
          result -> result
        end

      true ->
        case full_facts_retention_effect_candidate(
               config,
               cwd,
               key,
               policy,
               "Operator requested a retention change"
             ) do
          {:closed, result} -> result
          result -> result
        end
    end
  end

  @doc """
  Derive a standalone acceptance source context from the installed bundle and
  current protected project policy. This does not retain either owner and
  grants no review or publication authority; callers must reacquire them.
  """
  def acceptance_source_selection(config, cwd, history_dir, journal_id) do
    home = config[:home]

    with {:ok, binding} when is_map(binding) <- ProjectIdentity.existing(home, cwd),
         {:ok, selection} <- selection(home),
         true <-
           ManagedRecipe.valid?(selection.proposal) and selection.proposal["kind"] === "proposal",
         {:ok, snapshot} when is_map(snapshot) <-
           Consent.existing_snapshot(SemanticAdmission.control_root(home), binding["project_id"]),
         {:ok, context} <-
           Ipse.Session.PendingAcceptance.management_source_context(
             home,
             history_dir,
             binding,
             snapshot,
             journal_id,
             selection.digest,
             selection.recipe,
             selection.proposal,
             System.system_time(:millisecond)
           ) do
      {:ok, %{context: context, binding: binding, snapshot: snapshot, selection: selection}}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc """
  Retain the exact signed pending target and its original source for a trusted
  standalone-management continuation. The callback is host-only; it must use
  the native review and publication guards before displaying or mutating data.
  """
  def with_verified_acceptance_target(
        config,
        cwd,
        history_dir,
        owned,
        key,
        fun
      )
      when is_function(fun, 5),
      do: with_verified_acceptance_target(config, cwd, history_dir, owned, key, nil, fun)

  def with_verified_acceptance_target(_, _, _, _, _, _), do: @error

  @doc false
  def with_verified_acceptance_target(
        config,
        cwd,
        history_dir,
        owned,
        key,
        supplied_context,
        fun
      )
      when is_map(config) and is_map(owned) and is_function(fun, 5) do
    with {:ok, selected, facts_context} <-
           acceptance_review_context(config, cwd, history_dir, owned, key, supplied_context),
         {:ok, first} <-
           acceptance_target_read(config, cwd, key, selected, facts_context, fn facts, _, _, _ ->
             {:ok, facts}
           end) do
      Ipse.Session.PendingAcceptance.with_shareable_source(selected.context, first, fn source,
                                                                                       lease ->
        with true <- source["proof"] === first["source_proof"] do
          acceptance_target_read(config, cwd, key, selected, facts_context, fn facts,
                                                                               observed,
                                                                               read,
                                                                               cap ->
            if facts === first,
              do: fun.(facts, observed, read, cap, lease),
              else: @error
          end)
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

  def with_verified_acceptance_target(_, _, _, _, _, _, _), do: @error

  @doc false
  def begin_acceptance_review(config, cwd, history_dir, owned, key, facts_context, wall)
      when is_integer(wall) do
    with {:ok, selected, facts_context} <-
           acceptance_review_context(config, cwd, history_dir, owned, key, facts_context) do
      acceptance_target_read(config, cwd, key, selected, facts_context, fn facts, _, _, _ ->
        with rule when is_map(rule) <-
               Enum.find(
                 selected.selection.recipe["rules"],
                 &(&1["category"] === facts["assigned_category"])
               ),
             proposed = %{
               "accepted_category" => facts["assigned_category"],
               "maximum_age_from_confirmation_ms" => rule["max_age_ms"],
               "policy_expires_at_ms" => selected.snapshot["policy"]["expires_at_ms"],
               "earlier_lineage_limits_apply" => true
             },
             annotation =
               "Acceptance records your decision, not independent truth or permission for other effects.\n" <>
                 "Proposed accepted-decision retention (null maximum age means no category age limit):\n" <>
                 Jason.encode!(proposed, pretty: true) <> "\n",
             annotation =
               if(Map.has_key?(facts, "batch"),
                 do:
                   "Immutable batch manifest #{facts["batch"]["manifest_sha256"]}; item #{facts["batch"]["index"] + 1} of #{length(facts["batch"]["manifest"]["items"])}.\n" <>
                     "This fresh code confirms only #{facts["pending_key"]}. Other items require separate fresh input; cancellation stops the remaining batch.\n" <>
                     annotation,
                 else: annotation
               ),
             {:ok, caps} <- Ipse.Runner.Transaction.retained_share_stack(),
             {:ok, handle} <-
               Ipse.Runner.ManagementTerminal.begin_historical_accept_review(
                 owned,
                 caps,
                 facts,
                 wall,
                 annotation
               ),
             do: {:ok, {handle, facts}},
             else: (_ -> @error)
      end)
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  def begin_acceptance_review(_, _, _, _, _, _, _), do: @error

  defp acceptance_review_context(
         config,
         cwd,
         history_dir,
         owned,
         "pending." <> id,
         supplied_context
       )
       when is_map(config) and is_map(owned) do
    with true <- JSON.sha256?(id),
         true <- owned[:journal_owner] === self() and is_pid(owned[:writer]),
         {:ok, selected} <- acceptance_source_selection(config, cwd, history_dir, owned[:id]),
         binding = selected.binding,
         pin = selected.context.config.semantic_admission["pin"],
         template = %{
           "operation_id" => Usage.id(),
           "journal_id" => owned.id,
           "client_id" => Usage.id(),
           "session_id" => nil,
           "project_id" => binding["project_id"],
           "namespace" => pin["namespace"],
           "binding_sha256" => binding["binding_sha256"],
           "policy_sha256" => pin["policy_sha256"],
           "capture_epoch" => pin["epoch"],
           "render_revision" => 1,
           "recipe" => selected.selection.proposal
         },
         template =
           if(is_map(supplied_context) and Map.has_key?(supplied_context, "batch"),
             do: Map.put(template, "batch", supplied_context["batch"]),
             else: template
           ),
         facts_context = if(is_nil(supplied_context), do: template, else: supplied_context),
         true <-
           is_map(facts_context) and
             Enum.sort(Map.keys(facts_context)) === Enum.sort(Map.keys(template)) and
             Map.drop(facts_context, ~w(operation_id client_id render_revision)) ===
               Map.drop(template, ~w(operation_id client_id render_revision)) do
      {:ok, selected, facts_context}
    else
      _ -> @error
    end
  end

  defp acceptance_review_context(_, _, _, _, _, _), do: @error

  @doc false
  def accept_pending_candidate(config, cwd, history_dir, key, overall_deadline),
    do: accept_pending_candidate(config, cwd, history_dir, key, overall_deadline, nil)

  @doc false
  def accept_pending_candidate(config, cwd, history_dir, key, overall_deadline, accounting)
      when is_map(config) and is_binary(cwd) and is_binary(history_dir) and is_binary(key) and
             is_integer(overall_deadline) do
    controlled_review_journal_candidate(config, cwd, overall_deadline, fn owned ->
      Ipse.CLI.Terminal.puts("Management journal: #{owned.id}")

      with true <- System.monotonic_time(:millisecond) < overall_deadline,
           {:ok, selected} <- acceptance_source_selection(config, cwd, history_dir, owned.id),
           pin = selected.context.config.semantic_admission["pin"],
           true <- acceptance_accounting_policy?(accounting, pin),
           {:ok, reservation} <- Writer.reserve(owned.writer, %{bytes: 131_072, events: 3}) do
        context = %{
          "operation_id" => if(is_nil(accounting), do: Usage.id(), else: accounting.ticket["id"]),
          "journal_id" => owned.id,
          "client_id" => Ipse.Usage.id(),
          "session_id" => nil,
          "project_id" => selected.binding["project_id"],
          "namespace" => pin["namespace"],
          "binding_sha256" => selected.binding["binding_sha256"],
          "policy_sha256" => pin["policy_sha256"],
          "capture_epoch" => pin["epoch"],
          "render_revision" => 1,
          "recipe" => selected.selection.proposal
        }

        context =
          if(is_map(accounting) and not is_nil(accounting[:batch]),
            do: Map.put(context, "batch", accounting.batch),
            else: context
          )

        wall =
          System.system_time(:millisecond) +
            max(overall_deadline - System.monotonic_time(:millisecond), 0)

        result =
          with {:ok, {handle, facts}} <-
                 begin_acceptance_review(config, cwd, history_dir, owned, key, context, wall) do
            Ipse.Runner.Review.with_management_input("accept", facts, handle, fn permit ->
              publish_consumed_acceptance(
                config,
                cwd,
                history_dir,
                owned,
                reservation,
                facts,
                permit,
                accounting
              )
            end)
          end

        if Writer.release(owned.writer, reservation) == :ok,
          do: result,
          else: {:unknown, :acceptance_journal_unconfirmed}
      else
        _ -> @error
      end
    end)
  rescue
    _ -> {:unknown, :acceptance_publication_unconfirmed}
  end

  def accept_pending_candidate(_, _, _, _, _, _), do: @error

  defp acceptance_accounting_policy?(nil, _), do: true

  defp acceptance_accounting_policy?(%{ticket: ticket, request: request}, pin) do
    ticket["epoch"] === pin["epoch"] and request["policy_sha256"] === pin["policy_sha256"]
  end

  defp acceptance_accounting_policy?(_, _), do: false

  @doc false
  def publish_consumed_acceptance(config, cwd, history_dir, owned, reservation, facts, permit),
    do:
      publish_consumed_acceptance(
        config,
        cwd,
        history_dir,
        owned,
        reservation,
        facts,
        permit,
        nil
      )

  @doc false
  def publish_consumed_acceptance(
        config,
        cwd,
        history_dir,
        owned,
        reservation,
        facts,
        permit,
        accounting
      ) do
    alias Ipse.Session.PendingAcceptance

    with true <- is_map(owned) and owned[:journal_owner] === self() and is_pid(owned[:writer]),
         true <- PendingAcceptance.valid_facts?(facts) and facts["journal_id"] === owned[:id],
         {:ok, selected} <- acceptance_source_selection(config, cwd, history_dir, owned.id),
         pin = selected.context.config.semantic_admission["pin"],
         true <-
           facts["policy_sha256"] === pin["policy_sha256"] and
             facts["capture_epoch"] === pin["epoch"],
         true <- facts["binding_sha256"] === selected.binding["binding_sha256"],
         true <- facts["namespace"] === pin["namespace"] do
      slot = {__MODULE__, make_ref()}

      try do
        result =
          PendingAcceptance.with_shareable_source(selected.context, facts, fn source,
                                                                              source_lease ->
            with true <- source["proof"] === facts["source_proof"] do
              acceptance_publication(
                config,
                cwd,
                selected,
                owned,
                reservation,
                facts,
                permit,
                source_lease,
                slot,
                accounting
              )
            else
              _ -> @error
            end
          end)

        finish_acceptance_effect(result, Process.get(slot), owned, reservation, accounting)
      after
        Process.delete(slot)
      end
    else
      _ -> @error
    end
  rescue
    _ -> {:unknown, :acceptance_publication_unconfirmed}
  catch
    _, _ -> {:unknown, :acceptance_publication_unconfirmed}
  end

  defp acceptance_publication(
         config,
         cwd,
         selected,
         owned,
         reservation,
         facts,
         permit,
         source_lease,
         slot,
         accounting
       ) do
    pin = selected.context.config.semantic_admission["pin"]
    binding = selected.binding
    control = SemanticAdmission.control_root(config[:home])

    scope = %{
      namespace: pin["namespace"],
      format: "managed-metadata-v3",
      operation_id: facts["operation_id"],
      initialize: false
    }

    authorize = fn _ ->
      case Consent.with_policy(
             control,
             binding["project_id"],
             pin["epoch"],
             pin["policy_sha256"],
             System.system_time(:millisecond),
             fn _ -> {:ok, :authorized} end
           ) do
        {:ok, :authorized} -> :ok
        error -> error
      end
    end

    ProjectIdentity.with_domain_publication(config[:home], cwd, binding, scope, authorize, fn cap,
                                                                                              catalog ->
      Consent.with_policy(
        control,
        binding["project_id"],
        pin["epoch"],
        pin["policy_sha256"],
        System.system_time(:millisecond),
        fn snapshot ->
          ObservedRead.with_managed_proposal_acceptance_plan(
            SemanticAdmission.collection_root(config[:home]),
            pin["namespace"],
            %{"op" => "get_record", "key" => facts["pending_key"]},
            cap,
            catalog,
            selected.selection.proposal,
            fn observed, read, publish ->
              context =
                facts
                |> Map.take(
                  ~w(operation_id journal_id client_id session_id project_id namespace binding_sha256 policy_sha256 capture_epoch render_revision batch)
                )
                |> Map.put("recipe", selected.selection.proposal)

              with {:ok, current_selection} <- selection(config[:home]),
                   true <- current_selection === selected.selection,
                   {:ok, ^facts} <-
                     Ipse.Session.PendingAcceptance.prepare(
                       context,
                       observed,
                       [facts["source_proof"]],
                       System.system_time(:millisecond)
                     ),
                   :ok <-
                     Ipse.Session.PendingAcceptance.check_source_policy(
                       facts,
                       snapshot["policy"],
                       selected.selection.recipe,
                       System.system_time(:millisecond)
                     ),
                   {:ok, preview} <-
                     Ipse.Session.PendingAcceptance.preview(
                       permit,
                       facts,
                       System.system_time(:millisecond)
                     ),
                   {:ok, prepared} <-
                     Ipse.Session.PendingAcceptance.prepare_storage(
                       preview,
                       selected.selection.recipe,
                       snapshot["policy"]["expires_at_ms"],
                       observed,
                       cap,
                       System.system_time(:millisecond),
                       read
                     ) do
                record_acceptance_effect(
                  owned,
                  reservation,
                  preview,
                  prepared,
                  cap,
                  read,
                  publish,
                  permit,
                  source_lease,
                  slot,
                  accounting
                )
              else
                _ -> @error
              end
            end
          )
        end
      )
    end)
  end

  defp record_acceptance_effect(
         owned,
         reservation,
         preview,
         prepared,
         cap,
         read,
         publish,
         permit,
         source_lease,
         slot,
         accounting
       ) do
    alias Ipse.Runner.Transaction
    alias Ipse.Session.PendingAcceptance

    facts = preview["facts"]

    PendingAcceptance.with_sidecar_plan(preview, prepared, cap, read, fn _, seal ->
      with {:ok, ^preview} <-
             PendingAcceptance.consume(permit, facts, System.system_time(:millisecond)),
           {:ok, intent} <-
             PendingAcceptance.effect_intent(preview, prepared["public"]["request"]),
           :ok <- Writer.append_reserved(owned.writer, reservation, preview),
           :ok <- Writer.append_reserved(owned.writer, reservation, intent),
           _ <- Process.put(slot, intent),
           {:ok, %{request: normalized}} <- seal.(permit),
           {:ok, receipt} <- Review.claim_acceptance_effect(permit, facts, intent),
           true <- receipt === preview["review"],
           true <-
             is_nil(accounting) or
               acceptance_input_bytes(preview, normalized) <=
                 accounting.request["reserved"]["input_bytes"],
           collection_cap when not is_nil(collection_cap) <-
             Process.get({Collection, :lock_held}),
           {:ok, published} <-
             Transaction.with_acceptance_journal_lease(
               collection_cap,
               owned,
               preview,
               intent,
               fn ->
                 Transaction.with_source_lease(collection_cap, source_lease, fn ->
                   deadline =
                     min(
                       prepared["retention"]["valid_until_ms"] || facts["valid_until_ms"],
                       facts["valid_until_ms"]
                     )

                   Collection.with_notes_publication_deadline(deadline, fn ->
                     publish.(preview, intent, normalized, permit)
                   end)
                 end)
               end
             ),
           true <- is_map(published) do
        {:ok, {preview, intent, normalized, published}}
      else
        _ -> {:unknown, :acceptance_publication_unconfirmed}
      end
    end)
  rescue
    _ -> {:unknown, :acceptance_publication_unconfirmed}
  end

  # This runs only after the source, Collection, Consent and Identity callbacks
  # have all returned, so a committed result never precedes their cleanup.
  defp finish_acceptance_effect(result, intent, owned, reservation, accounting) do
    alias Ipse.Session.PendingAcceptance

    case result do
      {:ok, {event, ^intent, normalized, receipt}} when is_map(intent) ->
        with {:ok, committed} <-
               PendingAcceptance.committed_result(event, intent, normalized, receipt),
             :ok <- Writer.append_reserved(owned.writer, reservation, committed) do
          if is_nil(accounting) do
            {:ok, {:host_committed, event, receipt}}
          else
            actual =
              Map.merge(Consent.zero(), %{
                "operations" => 1,
                "input_bytes" => acceptance_input_bytes(event, normalized),
                "output_bytes" => byte_size(Jason.encode!(receipt))
              })

            {:ok, {:host_committed, event, receipt, actual}}
          end
        else
          _ -> {:unknown, :acceptance_journal_unconfirmed}
        end

      _ when is_map(intent) ->
        with {:ok, unknown} <- PendingAcceptance.effect_result(intent, "unknown"),
             :ok <- Writer.append_reserved(owned.writer, reservation, unknown),
             do: {:unknown, :acceptance_publication_unconfirmed},
             else: (_ -> {:unknown, :acceptance_journal_unconfirmed})

      _ ->
        result
    end
  end

  defp acceptance_input_bytes(event, normalized),
    do: byte_size(Jason.encode!(event)) + byte_size(Jason.encode!(normalized))

  defp acceptance_target_read(config, cwd, key, selected, facts_context, fun) do
    binding = selected.binding
    pin = selected.context.config.semantic_admission["pin"]
    domain = %{namespace: pin["namespace"], format: "managed-metadata-v3"}

    ProjectIdentity.with_existing_domain_auth(config[:home], cwd, binding, domain, fn cap,
                                                                                      catalog ->
      Consent.with_policy(
        SemanticAdmission.control_root(config[:home]),
        binding["project_id"],
        pin["epoch"],
        pin["policy_sha256"],
        System.system_time(:millisecond),
        fn snapshot ->
          ObservedRead.with_managed_proposal_plan(
            SemanticAdmission.collection_root(config[:home]),
            pin["namespace"],
            %{"op" => "get_record", "key" => key},
            cap,
            catalog,
            selected.selection.proposal,
            fn observed, read ->
              with {:ok, current_selection} <- selection(config[:home]),
                   true <- current_selection === selected.selection,
                   [proof] <-
                     get_in(observed, [
                       "observation",
                       "value",
                       "record",
                       "value",
                       "evidence",
                       "sources"
                     ]),
                   {:ok, facts} <-
                     Ipse.Session.PendingAcceptance.prepare(
                       facts_context,
                       observed,
                       [proof],
                       System.system_time(:millisecond)
                     ),
                   :ok <-
                     Ipse.Session.PendingAcceptance.check_source_policy(
                       facts,
                       snapshot["policy"],
                       selected.selection.recipe,
                       System.system_time(:millisecond)
                     ) do
                fun.(facts, observed, read, cap)
              else
                _ -> @error
              end
            end
          )
        end
      )
    end)
  end

  # Private same-VM candidate for the management journal owner. No public or
  # worker operation invokes it; it does not authorize display or mutation.
  @doc false
  def share_journal_candidate(config, cwd, fun)
      when is_map(config) and is_binary(cwd) and is_function(fun, 1) do
    with {:ok, scope} <- Resources.start(self()) do
      previous = Resources.bind(scope)

      try do
        result = Resources.file_effect(fn -> share_journal_owned(config, cwd, fun) end)

        if Resources.finish(scope) == :ok,
          do: result,
          else: {:unknown, :knowledge_management_cleanup_unconfirmed}
      after
        Resources.bind(previous)
        if Process.alive?(scope), do: Resources.close(scope)
      end
    else
      _ -> @error
    end
  rescue
    _ -> {:unknown, :knowledge_management_unconfirmed}
  catch
    _, _ -> {:unknown, :knowledge_management_unconfirmed}
  end

  def share_journal_candidate(_, _, _), do: @error

  # This candidate keeps the real CLI caller's control Port in that caller;
  # the tracked journal peer may request one bound transfer. No tty is used.
  @doc false
  def controlled_share_journal_candidate(config, cwd, fun) when is_function(fun, 1),
    do:
      controlled_share_journal_candidate(
        config,
        cwd,
        System.monotonic_time(:millisecond) + 120_000,
        fun
      )

  def controlled_share_journal_candidate(_, _, _), do: @error

  @doc false
  def controlled_share_journal_candidate(config, cwd, overall_deadline, fun)
      when is_map(config) and is_binary(cwd) and is_integer(overall_deadline) and
             is_function(fun, 1) do
    controlled_share_journal(config, cwd, overall_deadline, fun, false)
  end

  def controlled_share_journal_candidate(_, _, _, _), do: @error

  # The private review candidate keeps the two actual owner channels alive
  # through input and cleanup. The original five-second setup bound still
  # applies to every transfer.
  @doc false
  def controlled_review_journal_candidate(config, cwd, overall_deadline, fun)
      when is_map(config) and is_binary(cwd) and is_integer(overall_deadline) and
             is_function(fun, 1),
      do: controlled_share_journal(config, cwd, overall_deadline, fun, true)

  def controlled_review_journal_candidate(_, _, _, _), do: @error

  defp controlled_share_journal(config, cwd, overall_deadline, fun, review?) do
    deadline = min(overall_deadline, System.monotonic_time(:millisecond) + 5_000)
    operation = :crypto.strong_rand_bytes(16)

    with {:ok, scope} <- Resources.start(self()) do
      previous = Resources.bind(scope)

      try do
        with {:ok, port} <- Ipse.Runner.open_owner_control() do
          try do
            effect = fn control ->
              share_journal_owned(config, cwd, fn owned ->
                with_management_journal_control(owned, control, fun)
              end)
            end

            result =
              if review?,
                do:
                  Resources.management_controlled_file_effect(
                    effect,
                    port,
                    operation,
                    deadline,
                    overall_deadline
                  ),
                else:
                  Resources.management_controlled_file_effect(effect, port, operation, deadline)

            if Resources.finish(scope) == :ok,
              do: result,
              else: {:unknown, :knowledge_management_cleanup_unconfirmed}
          after
            if Port.info(port), do: Ipse.Runner.close_owner_control(port)
          end
        end
      after
        Resources.bind(previous)
        if Process.alive?(scope), do: Resources.close(scope)
      end
    else
      _ -> @error
    end
  rescue
    _ -> {:unknown, :knowledge_management_unconfirmed}
  catch
    _, _ -> {:unknown, :knowledge_management_unconfirmed}
  end

  # Display-only development candidate: it uses the complete real management
  # facts but cannot accept input, mint a permit, or mutate the selected note.
  @doc false
  def full_facts_display_candidate(config, cwd, "note." <> lineage = key, reason)
      when is_map(config) and is_binary(cwd) and is_binary(reason) do
    started_mono = System.monotonic_time(:millisecond)
    started_wall = System.system_time(:millisecond)
    overall = started_mono + 120_000
    wall = started_wall + 120_000
    home = config[:home]

    with true <- JSON.sha256?(lineage),
         {:ok, binding} when is_map(binding) <- ProjectIdentity.existing(home, cwd),
         {:ok, namespace} <- SemanticConsent.namespace(binding["project_id"], "knowledge"),
         {:ok, snapshot} when is_map(snapshot) <-
           Consent.existing_snapshot(SemanticAdmission.control_root(home), binding["project_id"]),
         true <- snapshot["epoch"] > 0,
         {:ok, selected} <- selection(home),
         true <-
           System.monotonic_time(:millisecond) < overall and
             System.system_time(:millisecond) < wall do
      result =
        controlled_share_journal_candidate(config, cwd, overall, fn owned ->
          context = %{
            "session_id" => owned.id,
            "job_id" => Usage.id(),
            "client_id" => Usage.id(),
            "project_id" => binding["project_id"],
            "namespace" => namespace,
            "binding_sha256" => binding["binding_sha256"],
            "management_epoch" => snapshot["epoch"],
            "management_sha256" =>
              Consent.management_sha256(
                binding["project_id"],
                snapshot["epoch"],
                snapshot["policy"]
              ),
            "original_pin" => nil,
            "recipe" => selected.recipe
          }

          ProjectIdentity.with_existing_domain_auth(
            home,
            cwd,
            binding,
            %{namespace: namespace, format: "managed-metadata-v3"},
            fn domain_cap, catalog ->
              Consent.with_existing_management_snapshot(
                SemanticAdmission.control_root(home),
                binding["project_id"],
                snapshot["epoch"],
                context["management_sha256"],
                fn _ ->
                  ObservedRead.with_managed_record(
                    SemanticAdmission.collection_root(home),
                    namespace,
                    %{"op" => "get_record", "key" => key},
                    domain_cap,
                    catalog,
                    selected.recipe,
                    fn managed ->
                      with {:ok, ^selected} <- selection(home),
                           {:ok, prepared} <- ManagedLifecycle.prepare(context, managed, reason),
                           {:ok, caps} <- Ipse.Runner.Transaction.retained_share_stack() do
                        Ipse.Runner.ManagementTerminal.display(
                          owned,
                          caps,
                          prepared["facts"],
                          wall
                        )
                      else
                        _ -> {:error, :management_display_refused}
                      end
                    end
                  )
                end
              )
            end
          )
        end)

      management_display_completion(result, overall, wall)
    else
      _ -> @error
    end
  rescue
    _ -> {:unknown, :management_display_unconfirmed}
  end

  def full_facts_display_candidate(_, _, _, _), do: @error

  # Private end-to-end review candidate. It observes and consumes a real
  # review but deliberately performs no collection mutation.
  @doc false
  def full_facts_review_candidate(config, cwd, "note." <> lineage = key, reason)
      when is_map(config) and is_binary(cwd) and is_binary(reason) do
    overall = System.monotonic_time(:millisecond) + 120_000
    wall = System.system_time(:millisecond) + 120_000
    home = config[:home]

    with true <- JSON.sha256?(lineage),
         {:ok, binding} when is_map(binding) <- ProjectIdentity.existing(home, cwd),
         {:ok, namespace} <- SemanticConsent.namespace(binding["project_id"], "knowledge"),
         {:ok, snapshot} when is_map(snapshot) <-
           Consent.existing_snapshot(SemanticAdmission.control_root(home), binding["project_id"]),
         true <- snapshot["epoch"] > 0,
         {:ok, selected} <- selection(home) do
      result =
        controlled_review_journal_candidate(config, cwd, overall, fn owned ->
          context = %{
            "session_id" => owned.id,
            "job_id" => Usage.id(),
            "client_id" => Usage.id(),
            "project_id" => binding["project_id"],
            "namespace" => namespace,
            "binding_sha256" => binding["binding_sha256"],
            "management_epoch" => snapshot["epoch"],
            "management_sha256" =>
              Consent.management_sha256(
                binding["project_id"],
                snapshot["epoch"],
                snapshot["policy"]
              ),
            "original_pin" => nil,
            "recipe" => selected.recipe
          }

          with {:ok, {handle, prepared}} <-
                 review_target(
                   home,
                   cwd,
                   key,
                   reason,
                   binding,
                   namespace,
                   selected,
                   context,
                   fn prepared ->
                     with {:ok, caps} <- Ipse.Runner.Transaction.retained_share_stack(),
                          {:ok, handle} <-
                            Ipse.Runner.ManagementTerminal.begin_review(
                              owned,
                              caps,
                              prepared["facts"],
                              wall
                            ),
                          do: {:ok, {handle, prepared}}
                   end
                 ) do
            Review.with_management_input("forget", prepared["facts"], handle, fn permit ->
              review_target(
                home,
                cwd,
                key,
                reason,
                binding,
                namespace,
                selected,
                context,
                fn current ->
                  if current["request"] === prepared["request"] and
                       Map.drop(current["facts"], ~w(operation_id action_sha256)) ===
                         Map.drop(prepared["facts"], ~w(operation_id action_sha256)) do
                    Review.consume(permit, "forget", prepared["facts"])
                  else
                    {:error, :management_review_target_changed}
                  end
                end
              )
            end)
          end
        end)

      management_display_completion(result, overall, wall)
    else
      _ -> @error
    end
  rescue
    _ -> {:unknown, :management_review_unconfirmed}
  catch
    _, _ -> {:unknown, :management_review_unconfirmed}
  end

  def full_facts_review_candidate(_, _, _, _), do: @error

  @doc false
  def full_facts_retention_review_candidate(config, cwd, key, policy, reason),
    do: retention_candidate(config, cwd, key, policy, reason, false)

  @doc false
  def full_facts_retention_effect_candidate(config, cwd, key, policy, reason),
    do: retention_candidate(config, cwd, key, policy, reason, true)

  defp retention_candidate(config, cwd, "note." <> lineage = key, policy, reason, effect?)
       when is_map(config) and is_binary(cwd) and is_binary(reason) do
    overall = System.monotonic_time(:millisecond) + 120_000
    wall = System.system_time(:millisecond) + 120_000
    home = config[:home]
    command = ManagedRetention.command(policy)

    with true <- JSON.sha256?(lineage),
         true <- ManagedRetention.policy?(policy) and command in ~w(pin ordinary duration),
         :ok <- if(effect?, do: management_effect_mode(config), else: :ok),
         {:ok, binding} when is_map(binding) <- ProjectIdentity.existing(home, cwd),
         {:ok, namespace} <- SemanticConsent.namespace(binding["project_id"], "knowledge"),
         {:ok, snapshot} when is_map(snapshot) <-
           Consent.existing_snapshot(SemanticAdmission.control_root(home), binding["project_id"]),
         true <- snapshot["epoch"] > 0,
         {:ok, selected} <- selection(home) do
      result =
        controlled_review_journal_candidate(config, cwd, overall, fn owned ->
          context = %{
            "session_id" => owned.id,
            "job_id" => Usage.id(),
            "client_id" => Usage.id(),
            "project_id" => binding["project_id"],
            "namespace" => namespace,
            "binding_sha256" => binding["binding_sha256"],
            "management_epoch" => snapshot["epoch"],
            "management_sha256" =>
              Consent.management_sha256(
                binding["project_id"],
                snapshot["epoch"],
                snapshot["policy"]
              ),
            "original_pin" => nil,
            "recipe" => selected.recipe
          }

          with {:ok, token} <-
                 if(effect?,
                   do: Writer.reserve(owned.writer, %{bytes: 65_536, events: 3}),
                   else: {:ok, nil}
                 ) do
            result =
              with {:ok, {handle, prepared}} <-
                     review_target(
                       home,
                       cwd,
                       key,
                       reason,
                       binding,
                       namespace,
                       selected,
                       context,
                       fn prepared ->
                         with {:ok, caps} <- Ipse.Runner.Transaction.retained_share_stack(),
                              {:ok, handle} <-
                                Ipse.Runner.ManagementTerminal.begin_retention_review(
                                  owned,
                                  caps,
                                  prepared["facts"],
                                  wall
                                ),
                              do: {:ok, {handle, prepared}}
                       end,
                       policy
                     ) do
                if effect? do
                  reviewed_forget_effect(
                    config,
                    cwd,
                    binding,
                    snapshot,
                    selected,
                    owned,
                    token,
                    prepared,
                    handle
                  )
                else
                  Review.with_management_input(command, prepared["facts"], handle, fn permit ->
                    review_target(
                      home,
                      cwd,
                      key,
                      reason,
                      binding,
                      namespace,
                      selected,
                      context,
                      fn current ->
                        if current["request"] === prepared["request"] and
                             Map.drop(current["facts"], ~w(operation_id action_sha256)) ===
                               Map.drop(prepared["facts"], ~w(operation_id action_sha256)) do
                          if ManagedLifecycle.retention_review?(
                               command,
                               prepared["facts"],
                               System.system_time(:millisecond)
                             ),
                             do: Review.consume(permit, command, prepared["facts"]),
                             else: {:error, :management_review_target_changed}
                        else
                          {:error, :management_review_target_changed}
                        end
                      end,
                      policy
                    )
                  end)
                end
              end

            if is_nil(token) or Writer.release(owned.writer, token) == :ok,
              do: result,
              else: {:unknown, :knowledge_management_journal_unconfirmed}
          end
        end)

      management_display_completion(result, overall, wall)
    else
      _ -> @error
    end
  rescue
    _ -> {:unknown, :management_review_unconfirmed}
  catch
    _, _ -> {:unknown, :management_review_unconfirmed}
  end

  defp retention_candidate(_, _, _, _, _, _), do: @error

  @doc false
  def management_effect_mode(config) do
    with {:ok, mode} <- Ipse.Extension.Mode.capture(config),
         true <- mode["headless"] === false and mode["approval_origin"] == "interactive",
         true <- Ipse.Extension.Mode.ordinary(mode, true) in [:ask, :allow],
         {:ok, :native} <- Ipse.Runner.operator_channel(),
         do: :ok,
         else: (_ -> @error)
  end

  # The public forget route shares this exact-facts effect. The displayed
  # preparation, one-use permit, intent and effect belong to the same actual
  # journal peer; no serialized receipt can supply authority.
  @doc false
  def full_facts_forget_candidate(config, cwd, "note." <> lineage = key, reason)
      when is_map(config) and is_binary(cwd) and is_binary(reason) do
    if JSON.sha256?(lineage),
      do: full_facts_removal_candidate(config, cwd, key, reason, :forget),
      else: @error
  end

  def full_facts_forget_candidate(_, _, _, _), do: @error

  defp full_facts_removal_candidate(config, cwd, key, reason, action)
       when is_map(config) and is_binary(cwd) and is_binary(reason) do
    overall = System.monotonic_time(:millisecond) + 120_000
    wall = System.system_time(:millisecond) + 120_000
    home = config[:home]

    with {:ok, mode} <- Ipse.Extension.Mode.capture(config),
         true <- mode["headless"] === false and mode["approval_origin"] == "interactive",
         true <- Ipse.Extension.Mode.ordinary(mode, true) in [:ask, :allow],
         {:ok, :native} <- Ipse.Runner.operator_channel(),
         {:ok, binding} when is_map(binding) <- ProjectIdentity.existing(home, cwd),
         {:ok, namespace} <- SemanticConsent.namespace(binding["project_id"], "knowledge"),
         {:ok, snapshot} when is_map(snapshot) <-
           Consent.existing_snapshot(SemanticAdmission.control_root(home), binding["project_id"]),
         true <- snapshot["epoch"] > 0,
         {:ok, selected} <- selection(home) do
      result =
        controlled_review_journal_candidate(config, cwd, overall, fn owned ->
          context = %{
            "session_id" => owned.id,
            "job_id" => Usage.id(),
            "client_id" => Usage.id(),
            "project_id" => binding["project_id"],
            "namespace" => namespace,
            "binding_sha256" => binding["binding_sha256"],
            "management_epoch" => snapshot["epoch"],
            "management_sha256" =>
              Consent.management_sha256(
                binding["project_id"],
                snapshot["epoch"],
                snapshot["policy"]
              ),
            "original_pin" => nil,
            "recipe" => if(action == :reject, do: selected.proposal, else: selected.recipe)
          }

          with {:ok, token} <- Writer.reserve(owned.writer, %{bytes: 65_536, events: 3}) do
            result =
              try do
                with :ok <- Ipse.CLI.Terminal.puts("Management journal: #{owned.id}"),
                     {:ok, {handle, prepared}} <-
                       review_target(
                         home,
                         cwd,
                         key,
                         reason,
                         binding,
                         namespace,
                         selected,
                         context,
                         fn prepared ->
                           with {:ok, caps} <- Ipse.Runner.Transaction.retained_share_stack(),
                                begin_review =
                                  if(action == :reject,
                                    do: &Ipse.Runner.ManagementTerminal.begin_reject_review/4,
                                    else: &Ipse.Runner.ManagementTerminal.begin_review/4
                                  ),
                                {:ok, handle} <-
                                  begin_review.(
                                    owned,
                                    caps,
                                    prepared["facts"],
                                    wall
                                  ),
                                do: {:ok, {handle, prepared}}
                         end
                       ) do
                  reviewed_forget_effect(
                    config,
                    cwd,
                    binding,
                    snapshot,
                    selected,
                    owned,
                    token,
                    prepared,
                    handle
                  )
                end
              rescue
                _ -> {:unknown, :knowledge_management_unconfirmed}
              catch
                _, _ -> {:unknown, :knowledge_management_unconfirmed}
              end

            if Writer.release(owned.writer, token) == :ok,
              do: result,
              else: {:unknown, :knowledge_management_journal_unconfirmed}
          else
            _ -> {:unknown, :knowledge_management_journal_unconfirmed}
          end
        end)

      management_display_completion(result, overall, wall)
    else
      _ -> @error
    end
  rescue
    _ -> {:unknown, :knowledge_management_unconfirmed}
  catch
    _, _ -> {:unknown, :knowledge_management_unconfirmed}
  end

  defp full_facts_removal_candidate(_, _, _, _, _), do: @error

  defp reviewed_forget_effect(
         config,
         cwd,
         binding,
         snapshot,
         selected,
         owned,
         token,
         prepared,
         handle
       ) do
    slot = {__MODULE__, make_ref()}

    try do
      result =
        Review.with_management_input(
          management_command(prepared["facts"]),
          prepared["facts"],
          handle,
          fn permit ->
            Process.put(slot, :intent_unknown)

            with :ok <- Writer.append_reserved(owned.writer, token, prepared["intent"]),
                 _ <- Process.put(slot, :effect_unknown),
                 {:ok, packet} <-
                   publish(config, cwd, binding, snapshot, selected, prepared, permit, owned),
                 {:ok, _} <-
                   settle(
                     SemanticAdmission.control_root(config[:home]),
                     binding["project_id"],
                     packet["ticket"],
                     {:known, packet["actual"], packet["receipt"]}
                   ) do
              Process.put(slot, :intent_confirmed)

              {:ok,
               %{
                 "operation_id" => prepared["facts"]["operation_id"],
                 "journal_id" => owned.id,
                 "journal_directory" => owned.directory,
                 "storage_status" => "settled",
                 "receipt" => packet["receipt"]
               }}
            else
              {:error, _} = error ->
                if Process.get(slot) == :effect_unknown, do: Process.put(slot, :intent_confirmed)
                error

              _ ->
                {:unknown, :knowledge_management_unconfirmed}
            end
          end
        )

      result =
        if Process.get(slot) == :effect_unknown,
          do: {:unknown, :knowledge_management_unconfirmed},
          else: result

      case Process.get(slot) do
        :intent_unknown ->
          {:unknown, :knowledge_management_journal_unconfirmed}

        state
        when state in [:intent_confirmed, :effect_unknown] or
               (is_nil(state) and elem(result, 0) == :error) ->
          event = %{
            "type" => "managed_lifecycle_result",
            "version" => 1,
            "operation_id" => prepared["facts"]["operation_id"],
            "status" => status(result),
            "result" => result_value(result)
          }

          if Writer.append_reserved(owned.writer, token, event) == :ok,
            do: result,
            else: {:unknown, :knowledge_management_journal_unconfirmed}

        _ ->
          result
      end
    after
      Process.delete(slot)
    end
  end

  defp review_target(
         home,
         cwd,
         key,
         reason,
         binding,
         namespace,
         selected,
         context,
         fun,
         policy \\ nil
       ) do
    ProjectIdentity.with_existing_domain_auth(
      home,
      cwd,
      binding,
      %{namespace: namespace, format: "managed-metadata-v3"},
      fn domain_cap, catalog ->
        Consent.with_existing_management_snapshot(
          SemanticAdmission.control_root(home),
          binding["project_id"],
          context["management_epoch"],
          context["management_sha256"],
          fn _ ->
            proposal? = context["recipe"]["kind"] == "proposal"

            reader =
              if(proposal?,
                do: &ObservedRead.with_managed_proposal_removal/7,
                else: &ObservedRead.with_managed_note_record/7
              )

            reader.(
              SemanticAdmission.collection_root(home),
              namespace,
              %{"op" => "get_record", "key" => key},
              domain_cap,
              catalog,
              context["recipe"],
              fn managed ->
                with {:ok, ^selected} <- selection(home),
                     {:ok, prepared} <-
                       if(proposal?,
                         do: Ipse.Session.PendingRejection.prepare(context, managed, reason),
                         else:
                           if(is_nil(policy),
                             do:
                               if(managed["metadata"]["management_target"] == "accepted_decision",
                                 do:
                                   ManagedLifecycle.prepare_accepted_forget(
                                     context,
                                     managed,
                                     reason
                                   ),
                                 else: ManagedLifecycle.prepare(context, managed, reason)
                               ),
                             else:
                               ManagedLifecycle.prepare_retention(
                                 context,
                                 managed,
                                 policy,
                                 reason
                               )
                           )
                       ),
                     do: fun.(prepared)
              end
            )
          end
        )
      end
    )
  end

  # Final admission is after nested lease release, Writer/guard close and scope
  # cleanup; a delayed or lost reply cannot become a known display completion.
  @doc false
  def management_display_completion({:closed, {:ok, _}} = result, overall, wall)
      when is_integer(overall) and is_integer(wall) do
    if System.monotonic_time(:millisecond) < overall and System.system_time(:millisecond) < wall and
         System.monotonic_time(:millisecond) < overall,
       do: result,
       else: {:unknown, :management_display_unconfirmed}
  end

  def management_display_completion({:closed, {:ok, _}}, _, _),
    do: {:unknown, :management_display_unconfirmed}

  def management_display_completion(result, _, _), do: result

  defp with_management_journal_control(owned, cli_control, fun) do
    with {:ok, port} <- Ipse.Runner.open_owner_control() do
      try do
        with {:os_pid, pid} when is_integer(pid) and pid > 0 <- Port.info(port, :os_pid),
             :ok <-
               management_control_frames(
                 port,
                 <<?R, 16::32, "owner-control-v1">>,
                 cli_control.deadline,
                 <<>>
               ) do
          control = %{
            owner: self(),
            port: port,
            sender_pid: pid,
            operation: cli_control.operation,
            deadline: cli_control.deadline,
            overall_deadline: cli_control.overall_deadline,
            ticket: make_ref()
          }

          result = fun.(Map.merge(owned, %{cli_control: cli_control, journal_control: control}))
          key = {__MODULE__, :journal_control, control.ticket}

          if match?({:error, _}, result) and is_nil(Process.get(key)) do
            if Ipse.Runner.cancel_unused_owner_control(port, cli_control.deadline) == :ok,
              do: result,
              else: {:unknown, :management_control_unconfirmed}
          else
            result
          end
        else
          _ -> {:unknown, :management_control_unconfirmed}
        end
      after
        if Port.info(port), do: Ipse.Runner.close_owner_control(port)
      end
    else
      _ -> {:unknown, :management_control_unconfirmed}
    end
  end

  @doc false
  def management_journal_control_transfer(
        %{owner: owner, port: port, operation: operation, deadline: deadline, ticket: ticket},
        recipient,
        name,
        secret
      )
      when owner == self() and is_port(port) and is_reference(ticket) and is_integer(deadline) do
    key = {__MODULE__, :journal_control, ticket}

    if Process.get(key) == nil and System.monotonic_time(:millisecond) < deadline and
         Port.info(port, :connected) == {:connected, self()} do
      Process.put(key, :used)
      expected = <<?H, 17::32, operation::binary, 2, ?T, 17::32, operation::binary, 2>>

      with :ok <-
             Ipse.Runner.send_owner_control(
               port,
               operation,
               :management_journal,
               recipient,
               name,
               secret
             ),
           :ok <- management_control_frames(port, expected, deadline, <<>>) do
        :ok
      else
        _ ->
          if Port.info(port, :connected) == {:connected, self()},
            do: Ipse.Runner.close_owner_control(port)

          {:unknown, :management_control_unconfirmed}
      end
    else
      if Port.info(port, :connected) == {:connected, self()},
        do: Ipse.Runner.close_owner_control(port)

      {:unknown, :management_control_unconfirmed}
    end
  end

  def management_journal_control_transfer(_, _, _, _),
    do: {:unknown, :management_control_unconfirmed}

  defp management_control_frames(port, expected, deadline, buffer) do
    cond do
      System.monotonic_time(:millisecond) >= deadline ->
        :error

      buffer == expected ->
        :ok

      byte_size(buffer) >= byte_size(expected) or
          binary_part(expected, 0, byte_size(buffer)) != buffer ->
        :error

      true ->
        receive do
          {^port, {:data, bytes}} ->
            management_control_frames(port, expected, deadline, buffer <> bytes)

          {^port, _} ->
            :error
        after
          max(deadline - System.monotonic_time(:millisecond), 0) -> :error
        end
    end
  end

  defp share_journal_owned(config, cwd, fun) do
    home = config[:home]

    with {:ok, binding} when is_map(binding) <- ProjectIdentity.existing(home, cwd),
         {:ok, namespace} <- SemanticConsent.namespace(binding["project_id"], "knowledge"),
         directory = Path.join(home, "knowledge-management"),
         :ok <- management_directory(directory),
         id = Usage.id(),
         {:ok, _} <- Lock.acquire_share_header(Path.join(directory, id <> ".lock")) do
      guard = Lock.current()

      metadata = %{
        "kind" => "knowledge_management",
        "version" => 1,
        "project_id" => binding["project_id"],
        "namespace" => namespace,
        "pending_acceptance_layout" => Ipse.Session.PendingAcceptance.layout(),
        "source_origin_layout" => Ipse.Journal.SourceOrigin.layout(),
        "native_journal_layout" => Journal.native_owner_layout()
      }

      result =
        try do
          with {:ok, ^id} <- Journal.create_with_locked_id(directory, id, metadata, nil, guard),
               {:ok, writer} <- Writer.start(directory, id, self(), nil, :header_share_v2) do
            result =
              if Lock.track(writer, :writer) == :ok do
                try do
                  fun.(%{
                    guard: guard,
                    writer: writer,
                    directory: directory,
                    id: id,
                    cli_owner: Resources.file_effect_owner(),
                    journal_owner: self()
                  })
                catch
                  _, _ -> {:unknown, :knowledge_management_unconfirmed}
                end
              else
                {:unknown, :knowledge_management_journal_unconfirmed}
              end

            if Writer.close(writer) == :ok,
              do: result,
              else: {:unknown, :knowledge_management_journal_unconfirmed}
          else
            _ -> {:unknown, :knowledge_management_journal_unconfirmed}
          end
        catch
          _, _ -> {:unknown, :knowledge_management_unconfirmed}
        end

      if Lock.release(guard) == :ok,
        do: result,
        else: {:unknown, :knowledge_management_cleanup_unconfirmed}
    else
      _ -> @error
    end
  end

  defp manage(config, cwd, "note." <> lineage = key, policy) do
    with true <- JSON.sha256?(lineage),
         {:ok, mode} <- Ipse.Extension.Mode.capture(config),
         true <- mode["headless"] === false and mode["approval_origin"] == "interactive",
         true <- Ipse.Extension.Mode.ordinary(mode, true) in [:ask, :allow],
         {:ok, :native} <- Ipse.Runner.operator_channel(),
         {:ok, scope} <- Resources.start(self()) do
      previous = Resources.bind(scope)

      try do
        result = Resources.file_effect(fn -> owned_forget(config, cwd, key, policy) end)

        case Resources.finish(scope) do
          :ok -> result
          _ -> {:unknown, :knowledge_management_cleanup_unconfirmed}
        end
      after
        Resources.bind(previous)
        if Process.alive?(scope), do: Resources.close(scope)
      end
    else
      _ -> @error
    end
  rescue
    _ -> {:unknown, :knowledge_management_unconfirmed}
  catch
    _, _ -> {:unknown, :knowledge_management_unconfirmed}
  end

  defp manage(_, _, _, _), do: @error

  @doc "Inspect a retained management journal and current control status without replay or settlement."
  def operation(config, cwd, id) do
    directory = Path.join(config[:home], "knowledge-management")

    if is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id) and
         File.lstat(Path.join(directory, id <> ".jsonl")) === {:error, :enoent} do
      control_operation(config, cwd, id)
    else
      journal_operation(config, cwd, id, directory)
    end
  rescue
    _ -> @error
  end

  defp control_operation(config, cwd, id) do
    with {:ok, binding} when is_map(binding) <- ProjectIdentity.existing(config[:home], cwd),
         {:ok, namespace} <- SemanticConsent.namespace(binding["project_id"], "knowledge"),
         {:ok, operation} <-
           Consent.operation(
             SemanticAdmission.control_root(config[:home]),
             binding["project_id"],
             id
           ) do
      {:ok,
       %{
         "journal_id" => nil,
         "journal_status" => "unavailable",
         "project_id" => binding["project_id"],
         "namespace" => namespace,
         "operation_id" => id,
         "control_status" => operation["status"],
         "actual" => operation["actual"],
         "reserved" => operation["reserved"],
         "replayed" => false,
         "current_note_eligibility" => "not_checked"
       }}
    else
      _ -> @error
    end
  end

  defp journal_operation(config, cwd, id, directory) do
    with true <- is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id),
         {:ok, binding} when is_map(binding) <- ProjectIdentity.existing(config[:home], cwd),
         {:ok, namespace} <- SemanticConsent.namespace(binding["project_id"], "knowledge"),
         {:ok,
          %{
            events: [%{"type" => "session", "metadata" => metadata} = header | events],
            tail: tail
          }} <-
           Journal.read_path(Path.join(directory, id <> ".jsonl")),
         true <- metadata["kind"] == "knowledge_management" and metadata["version"] === 1,
         true <-
           metadata["project_id"] == binding["project_id"] and metadata["namespace"] == namespace,
         :ok <- Ipse.Journal.SourceOrigin.check_path(directory, id, metadata) do
      if Enum.any?(
           events,
           &(&1["type"] in ~w(pending_proposal_accepted pending_acceptance_intent pending_acceptance_result))
         ) do
        acceptance_operation(config, directory, id, binding, namespace, [header | events], tail)
      else
        lifecycle_operation(config, directory, id, binding, namespace, events, tail)
      end
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp lifecycle_operation(config, directory, id, binding, namespace, events, tail) do
    with intents = Enum.filter(events, &(&1["type"] == "managed_lifecycle_intent")),
         results = Enum.filter(events, &(&1["type"] == "managed_lifecycle_result")),
         true <- length(intents) <= 1 and length(results) <= 1,
         true <- length(intents) + length(results) == length(events),
         intent = List.first(intents),
         result = List.first(results),
         true <-
           is_nil(result) or (is_nil(intent) and result["status"] == "refused") or
             (is_map(intent) and result["operation_id"] == intent["operation_id"]),
         {:ok, state} when is_map(state) <-
           Consent.existing_snapshot(
             SemanticAdmission.control_root(config[:home]),
             binding["project_id"]
           ) do
      selected = intent || result
      operation = if selected, do: state["operations"][selected["operation_id"]]

      {:ok,
       %{
         "journal_id" => id,
         "journal_directory" => directory,
         "project_id" => binding["project_id"],
         "namespace" => namespace,
         "operation_id" => if(selected, do: selected["operation_id"]),
         "record_key" => if(intent, do: get_in(intent, ["facts", "target", "key"])),
         "journal_status" =>
           if(tail == :none and result, do: result["status"], else: "unconfirmed"),
         "control_status" => if(operation, do: operation["status"], else: "unavailable"),
         "action_sha256" => if(intent, do: intent["facts"]["action_sha256"]),
         "replacement_pending_key" =>
           if(
             intent && intent["facts"]["kind"] === "managed_proposal_correction" &&
               Ipse.Session.PendingCorrection.valid_facts?(intent["facts"]),
             do: Enum.at(intent["facts"]["request"]["changes"], 1)["key"]
           ),
         "replayed" => false,
         "current_note_eligibility" => "not_checked"
       }
       |> Map.reject(fn {key, value} -> key == "replacement_pending_key" and is_nil(value) end)}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp acceptance_operation(
         config,
         directory,
         id,
         binding,
         namespace,
         [_header | events] = records,
         tail
       ) do
    alias Ipse.Session.PendingAcceptance

    with :ok <- PendingAcceptance.validate_events(records, id),
         [event] <- Enum.filter(events, &(&1["type"] === "pending_proposal_accepted")),
         intents <- Enum.filter(events, &(&1["type"] === "pending_acceptance_intent")),
         results <- Enum.filter(events, &(&1["type"] === "pending_acceptance_result")),
         true <- length(intents) <= 1 and length(results) <= 1,
         true <- length(events) === 1 + length(intents) + length(results),
         {:ok, accepted_note_key} <- PendingAcceptance.accepted_note_key(event),
         {:ok, unknown} <- PendingAcceptance.unknown_effects(records, id) do
      intent = List.first(intents)
      result = List.first(results)
      batch = event["facts"]["batch"]

      batch_fields =
        if is_nil(batch),
          do: %{},
          else: %{
            "batch_manifest_sha256" => batch["manifest_sha256"],
            "batch_id" => batch["manifest"]["id"],
            "batch_index" => batch["index"],
            "batch_count" => length(batch["manifest"]["items"])
          }

      status =
        cond do
          tail != :none -> "unknown"
          unknown != [] -> "unknown"
          is_map(result) -> result["status"]
          is_nil(intent) -> "not_started"
          true -> "unknown"
        end

      {:ok,
       %{
         "journal_id" => id,
         "journal_directory" => directory,
         "project_id" => binding["project_id"],
         "namespace" => namespace,
         "operation_id" => event["facts"]["operation_id"],
         "record_key" => event["facts"]["pending_key"],
         "accepted_note_key" => accepted_note_key,
         "journal_status" => status,
         "control_status" => acceptance_control_status(config, binding, event),
         "action_sha256" => nil,
         "request_sha256" => if(intent, do: intent["request_sha256"]),
         "replayed" => false,
         "current_note_eligibility" => "not_checked"
       }
       |> Map.merge(batch_fields)}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp acceptance_control_status(config, binding, event) do
    facts = event["facts"]

    with {:ok, operation} <-
           Consent.operation(
             SemanticAdmission.control_root(config[:home]),
             binding["project_id"],
             facts["operation_id"]
           ),
         true <- operation["epoch"] === facts["capture_epoch"],
         true <-
           operation["request_sha256"] ===
             acceptance_request_sha256(facts["pending_key"], facts["batch"]),
         do: operation["status"],
         else: (_ -> "unavailable")
  end

  defp owned_forget(config, cwd, key, policy) do
    home = config[:home]

    with {:ok, binding} when is_map(binding) <- ProjectIdentity.existing(home, cwd),
         {:ok, namespace} <- SemanticConsent.namespace(binding["project_id"], "knowledge"),
         {:ok, snapshot} when is_map(snapshot) <-
           Consent.existing_snapshot(SemanticAdmission.control_root(home), binding["project_id"]),
         true <- snapshot["epoch"] > 0,
         {:ok, selection} <- selection(home),
         directory = Path.join(home, "knowledge-management"),
         :ok <- management_directory(directory),
         id = Usage.id(),
         {:ok, _} <- Lock.acquire_header(Path.join(directory, id <> ".lock")) do
      guard = Lock.current()

      result =
        try do
          metadata = %{
            "kind" => "knowledge_management",
            "version" => 1,
            "project_id" => binding["project_id"],
            "namespace" => namespace,
            "source_origin_layout" => Ipse.Journal.SourceOrigin.layout(),
            "native_journal_layout" => Journal.native_owner_layout()
          }

          with {:ok, ^id} <- Journal.create_with_locked_id(directory, id, metadata, nil, guard),
               {:ok, writer} <- Writer.start(directory, id, self(), nil, :header_v1) do
            :ok = Lock.track(writer, :writer)

            result =
              try do
                journaled_forget(
                  config,
                  cwd,
                  key,
                  binding,
                  namespace,
                  snapshot,
                  selection,
                  directory,
                  id,
                  writer,
                  policy
                )
              catch
                _, _ -> {:unknown, :knowledge_management_unconfirmed}
              end

            if Writer.close(writer) == :ok,
              do: result,
              else: {:unknown, :knowledge_management_journal_unconfirmed}
          else
            _ -> {:unknown, :knowledge_management_journal_unconfirmed}
          end
        catch
          _, _ -> {:unknown, :knowledge_management_unconfirmed}
        end

      if Lock.release(guard) == :ok,
        do: result,
        else: {:unknown, :knowledge_management_cleanup_unconfirmed}
    else
      _ -> @error
    end
  end

  defp management_directory(directory) do
    created = File.mkdir(directory)

    with true <- created in [:ok, {:error, :eexist}],
         :ok <- if(created == :ok, do: File.chmod(directory, 0o700), else: :ok),
         {:ok, stat} <- File.lstat(directory),
         true <- stat.type == :directory and Bitwise.band(stat.mode, 0o077) == 0 do
      :ok
    else
      _ -> @error
    end
  end

  defp journaled_forget(
         config,
         cwd,
         key,
         binding,
         namespace,
         snapshot,
         selection,
         directory,
         id,
         writer,
         policy
       ) do
    context = %{
      "session_id" => id,
      "job_id" => Usage.id(),
      "client_id" => Usage.id(),
      "project_id" => binding["project_id"],
      "namespace" => namespace,
      "binding_sha256" => binding["binding_sha256"],
      "management_epoch" => snapshot["epoch"],
      "management_sha256" =>
        Consent.management_sha256(binding["project_id"], snapshot["epoch"], snapshot["policy"]),
      "original_pin" => nil,
      "recipe" => selection.recipe
    }

    with {:ok, managed} <-
           ProjectIdentity.with_existing_domain_auth(
             config[:home],
             cwd,
             binding,
             %{namespace: namespace, format: "managed-metadata-v3"},
             fn cap, catalog ->
               result =
                 if policy == :expiry do
                   ObservedRead.with_managed_note_record(
                     SemanticAdmission.collection_root(config[:home]),
                     namespace,
                     %{"op" => "get_record", "key" => key},
                     cap,
                     catalog,
                     selection.recipe,
                     &{:ok, &1}
                   )
                 else
                   ObservedRead.managed_record(
                     SemanticAdmission.collection_root(config[:home]),
                     namespace,
                     %{"op" => "get_record", "key" => key},
                     cap,
                     catalog,
                     selection.recipe
                   )
                 end

               if policy == :expiry and match?({:error, _}, result) do
                 ObservedRead.managed_history(
                   SemanticAdmission.collection_root(config[:home]),
                   namespace,
                   %{"op" => "get_record", "key" => key},
                   cap,
                   catalog,
                   selection.recipe
                 )
               else
                 result
               end
             end
           ),
         now = System.system_time(:millisecond),
         {:ok, prepared} <- prepare(context, managed, policy, now),
         {:ok, token} <- Writer.reserve(writer, %{bytes: 65_536, events: 3}) do
      Ipse.CLI.Terminal.puts("Management journal: #{id}")

      try do
        result =
          review(policy, prepared["facts"], fn permit ->
            with :ok <- Writer.append_reserved(writer, token, prepared["intent"]),
                 {:ok, packet} <-
                   publish(config, cwd, binding, snapshot, selection, prepared, permit),
                 {:ok, _} <-
                   settle(
                     SemanticAdmission.control_root(config[:home]),
                     binding["project_id"],
                     packet["ticket"],
                     {:known, packet["actual"], packet["receipt"]}
                   ) do
              {:ok,
               %{
                 "operation_id" => prepared["facts"]["operation_id"],
                 "journal_id" => id,
                 "journal_directory" => directory,
                 "storage_status" => "settled",
                 "receipt" => packet["receipt"]
               }}
            else
              {:error, _} = error -> error
              _ -> {:unknown, :knowledge_management_unconfirmed}
            end
          end)

        event = %{
          "type" => "managed_lifecycle_result",
          "version" => 1,
          "operation_id" => prepared["facts"]["operation_id"],
          "status" => status(result),
          "result" => result_value(result)
        }

        case Writer.append_reserved(writer, token, event) do
          :ok -> result
          _ -> {:unknown, :knowledge_management_journal_unconfirmed}
        end
      after
        Writer.release(writer, token)
      end
    else
      _ -> @error
    end
  end

  defp prepare(
         context,
         %{"metadata" => %{"management_target" => "accepted_decision"}} = managed,
         :expiry,
         now
       ),
       do: ManagedLifecycle.prepare_accepted_expiry(context, managed, now)

  defp prepare(context, %{"metadata" => %{"category" => "history"}} = managed, :expiry, now),
    do: ManagedLifecycle.prepare_history_expiry(context, managed, now)

  defp prepare(context, managed, :expiry, now),
    do: ManagedLifecycle.prepare_expiry(context, managed, now)

  defp prepare(context, managed, policy, now) do
    if policy["kind"] == "session" or
         (managed["metadata"]["first_admitted_ms"] <= now and
            (is_nil(managed["metadata"]["valid_until_ms"]) or
               now < managed["metadata"]["valid_until_ms"])) do
      ManagedLifecycle.prepare_retention(
        context,
        managed,
        policy,
        "Operator requested this selected retention choice"
      )
    else
      @error
    end
  end

  defp review(:expiry, facts, fun) do
    Ipse.CLI.Terminal.puts("Reclaiming the selected expired signed policy:")
    Ipse.CLI.Terminal.puts(Jason.encode!(facts, pretty: true))
    fun.(nil)
  end

  defp review(policy, facts, fun),
    do: Review.with_review(ManagedRetention.command(policy), facts, fun)

  defp settle(control, project, ticket, outcome) do
    case Consent.settle(control, project, ticket, outcome) do
      {:ok, _} = settled -> settled
      _ -> {:unknown, :knowledge_management_settlement_unconfirmed}
    end
  end

  defp publish(config, cwd, binding, snapshot, selection, prepared, permit, owned \\ nil) do
    facts = prepared["facts"]
    context = facts["context"]
    namespace = context["namespace"]
    control = SemanticAdmission.control_root(config[:home])

    request = %{
      "id" => facts["operation_id"],
      "operation" => operation(facts["kind"]),
      "artifact_sha256" => selection.digest,
      "source_sha256" => JSON.digest([facts]),
      "policy_sha256" => context["management_sha256"],
      "request_sha256" => facts["action_sha256"],
      "source_generation" => prepared["request"]["expected_generation"],
      "headless" => false,
      "reserved" =>
        Map.merge(Consent.zero(), %{
          "operations" => 1,
          "input_bytes" => 65_536,
          "output_bytes" => 16_384
        })
    }

    ProjectIdentity.with_domain_publication(
      config[:home],
      cwd,
      binding,
      %{
        namespace: namespace,
        format: "managed-metadata-v3",
        operation_id: facts["operation_id"],
        initialize: false
      },
      fn actual ->
        with true <- actual === binding,
             {:ok, ^selection} <- selection(config[:home]),
             {:ok, current} when is_map(current) <-
               Consent.existing_snapshot(control, binding["project_id"]),
             true <-
               current["epoch"] === snapshot["epoch"] and current["policy"] === snapshot["policy"],
             :ok <- check_review(facts, permit),
             do: :ok,
             else: (_ -> @error)
      end,
      fn cap, catalog ->
        callback = fn ->
          measured_forget(config, prepared, request["reserved"], permit, cap, catalog, owned)
        end

        if facts["kind"] in ~w(managed_literal_expiry managed_literal_history_expiry managed_accepted_decision_expiry) do
          Consent.expire_deferred(
            control,
            binding["project_id"],
            snapshot["epoch"],
            request,
            facts,
            System.system_time(:millisecond),
            callback
          )
        else
          consent =
            cond do
              facts["kind"] == "managed_proposal_reject" ->
                &Consent.reject_deferred/8

              facts["kind"] in ~w(managed_literal_retention managed_accepted_decision_retention) ->
                &Consent.retain_deferred/8

              true ->
                &Consent.forget_deferred/8
            end

          consent.(
            control,
            binding["project_id"],
            snapshot["epoch"],
            request,
            permit,
            facts,
            System.system_time(:millisecond),
            callback
          )
        end
      end
    )
  end

  defp measured_forget(config, prepared, reserved, permit, cap, catalog, owned) do
    facts = prepared["facts"]
    envelope = %{"metadata_version" => 3, "request" => prepared["request"], "facts" => facts}
    slot = {__MODULE__, make_ref()}
    owner = self()

    try do
      normalize = fn witness, read ->
        with true <- self() == owner and Process.get(slot) == nil,
             _ <- Process.put(slot, :claimed),
             normalizer = normalizer(facts["kind"]),
             options = %{
               request: prepared["request"],
               facts: facts,
               now_ms: System.system_time(:millisecond),
               domain_cap: cap,
               catalog: catalog
             },
             options =
               if(is_nil(permit), do: options, else: Map.put(options, :permit, permit)),
             {:ok, normalized, normalization} = result <-
               normalizer.(witness, read, options),
             accounting_normalized =
               if(facts["kind"] == "managed_accepted_decision_retention",
                 do: Map.update!(normalized, "changes", &(prepared["request"]["changes"] ++ &1)),
                 else: normalized
               ),
             {:ok, actual} <-
               ManagedCollectionCall.measured_accounting(
                 envelope,
                 accounting_normalized,
                 normalization,
                 reserved
               ) do
          Process.put(slot, {JSON.digest([normalized]), normalization, actual})
          result
        else
          _ -> {:error, :collection_accounting_invalid}
        end
      end

      root = SemanticAdmission.collection_root(config[:home])
      namespace = facts["context"]["namespace"]
      request = prepared["request"]
      operation = facts["operation_id"]
      recipe = JSON.digest([facts["context"]["recipe"]])

      result =
        if facts["kind"] in ~w(managed_literal_retention managed_accepted_decision_retention) and
             is_map(owned),
           do:
             Collection.execute_managed_retention(
               root,
               namespace,
               request,
               operation,
               recipe,
               normalize,
               owned,
               prepared["intent"],
               permit
             ),
           else:
             Collection.execute_managed_v3(root, namespace, request, operation, recipe, normalize)

      with {:ok, core} <- result,
           {digest, normalization, actual} <- Process.get(slot),
           true <-
             digest == core["receipt"]["request_sha256"] and
               normalization === core["normalization"],
           true <- JSON.digest([normalization]) == core["binding"]["normalization_sha256"],
           true <- byte_size(Jason.encode!(core)) <= 16_384 do
        {:ok, actual,
         %{
           "action_sha256" => normalization["action_sha256"],
           "native_review_sha256" => normalization["native_review_sha256"],
           "publication" => core
         }}
      else
        _ -> {:unknown, :knowledge_management_unconfirmed}
      end
    after
      Process.delete(slot)
    end
  end

  defp operation("managed_literal_expiry"), do: "collection.expire"
  defp operation("managed_accepted_decision_expiry"), do: "collection.expire"
  defp operation("managed_literal_history_expiry"), do: "collection.expire"
  defp operation("managed_literal_retention"), do: "collection.retention"
  defp operation("managed_accepted_decision_retention"), do: "collection.retention"
  defp operation("managed_literal_forget"), do: "collection.forget"
  defp operation("managed_proposal_reject"), do: "collection.forget"
  defp operation("managed_accepted_decision_forget"), do: "collection.forget"

  defp check_review(%{"kind" => "managed_literal_expiry"}, nil), do: :ok
  defp check_review(%{"kind" => "managed_accepted_decision_expiry"}, nil), do: :ok
  defp check_review(%{"kind" => "managed_literal_history_expiry"}, nil), do: :ok

  defp check_review(facts, permit),
    do: Review.check(permit, management_command(facts), facts)

  defp management_command(%{"kind" => "managed_proposal_reject"}), do: "reject"
  defp management_command(facts), do: ManagedRetention.command(facts["policy"])

  defp normalizer("managed_literal_expiry"), do: &NormalizerV3.expire/3
  defp normalizer("managed_accepted_decision_expiry"), do: &NormalizerV3.expire_accepted/3
  defp normalizer("managed_literal_history_expiry"), do: &NormalizerV3.expire_history/3
  defp normalizer("managed_literal_retention"), do: &NormalizerV3.retain/3
  defp normalizer("managed_accepted_decision_retention"), do: &NormalizerV3.retain_accepted/3
  defp normalizer("managed_literal_forget"), do: &NormalizerV3.forget/3
  defp normalizer("managed_proposal_reject"), do: &NormalizerV3.reject/3
  defp normalizer("managed_accepted_decision_forget"), do: &NormalizerV3.forget_accepted/3

  @doc false
  def selection(home) do
    with {:ok, entries} <- Bundles.inventory(),
         %{digest: digest} <- Enum.find(entries, &(&1.id == "knowledge")),
         {:ok, _} <- Artifact.lookup(Path.join(home, "extensions/artifacts"), digest),
         {:ok, bytes} <-
           Artifact.read_declared(
             Path.join(home, "extensions/artifacts"),
             digest,
             "operator.json",
             65_536
           ),
         {:ok, sidecar} <- JSON.decode_unique(bytes),
         recipe = sidecar["recipes"]["note"],
         true <- ManagedRecipe.valid?(recipe) and recipe["kind"] == "literal_source" do
      {:ok, %{digest: digest, recipe: recipe, proposal: sidecar["recipes"]["pending"]}}
    else
      _ -> @error
    end
  end

  defp status({:ok, _}), do: "settled"
  defp status({:error, _}), do: "refused"
  defp status(_), do: "unconfirmed"
  defp result_value({:ok, value}), do: value
  defp result_value({_, reason}), do: %{"reason" => Atom.to_string(reason)}
end
