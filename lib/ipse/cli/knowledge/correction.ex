defmodule Ipse.CLI.Knowledge.Correction do
  @moduledoc false
  alias Ipse.{JSON, Usage}
  alias Ipse.CLI.Knowledge.Management

  alias Ipse.Extension.{
    Collection,
    Consent,
    ManagedCollectionCall,
    ProjectIdentity,
    SemanticAdmission
  }

  alias Ipse.Extension.Collection.NormalizerV3
  alias Ipse.Extension.Collection.ObservedRead
  alias Ipse.Journal.Writer
  alias Ipse.Runner.{ManagementTerminal, Review, Transaction}
  alias Ipse.Session.{PendingAcceptance, PendingCorrection}
  @error {:error, :pending_correction_refused}
  @unknown {:unknown, :pending_correction_unconfirmed}

  def run(config, cwd, history_dir, "pending." <> id = key, text) do
    with true <- JSON.sha256?(id) and is_binary(text) and String.valid?(text),
         true <- byte_size(text) in 1..2048 and String.trim(text) != "",
         true <- is_binary(history_dir) and Path.type(history_dir) === :absolute,
         :ok <- Management.management_effect_mode(config),
         {:ok, selected} <-
           Management.acceptance_source_selection(config, cwd, history_dir, Usage.id()),
         policy = selected.snapshot["policy"],
         request = %{
           "id" => Usage.id(),
           "operation" => "notes.capture",
           "artifact_sha256" => selected.selection.digest,
           "source_sha256" => policy["source_sha256"],
           "policy_sha256" => JSON.digest([policy]),
           "request_sha256" => JSON.digest(["native_pending_correction", 1, key, text]),
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
          overall = System.monotonic_time(:millisecond) + 120_000

          result =
            Management.controlled_review_journal_candidate(config, cwd, overall, fn owned ->
              Ipse.CLI.Terminal.puts("Management journal: #{owned.id}")
              workflow(config, cwd, history_dir, key, text, owned, ticket, request, overall)
            end)

          settle(control, project, ticket, result)

        error ->
          case Consent.settle(control, project, ticket, :unstarted) do
            {:ok, _} -> error
            _ -> @unknown
          end
      end
    else
      _ -> @error
    end
  rescue
    _ -> @unknown
  end

  def run(_, _, _, _, _), do: @error

  defp workflow(config, cwd, history_dir, key, text, owned, ticket, request, overall) do
    with {:ok, selected} <-
           Management.acceptance_source_selection(config, cwd, history_dir, owned.id),
         pin = selected.context.config.semantic_admission["pin"],
         true <-
           pin["epoch"] === ticket["epoch"] and pin["policy_sha256"] === request["policy_sha256"],
         context = %{
           "session_id" => owned.id,
           "job_id" => ticket["id"],
           "client_id" => Usage.id(),
           "project_id" => selected.binding["project_id"],
           "namespace" => pin["namespace"],
           "binding_sha256" => selected.binding["binding_sha256"],
           "management_epoch" => pin["epoch"],
           "management_sha256" =>
             Consent.management_sha256(
               selected.binding["project_id"],
               pin["epoch"],
               selected.snapshot["policy"]
             ),
           "original_pin" => pin,
           "recipe" => selected.selection.proposal
         },
         {:ok, token} <- Writer.reserve(owned.writer, %{bytes: 131_072, events: 3}) do
      result =
        try do
          wall =
            System.system_time(:millisecond) +
              max(overall - System.monotonic_time(:millisecond), 0)

          with {:ok, {handle, prepared}} <-
                 initial_review(
                   config,
                   cwd,
                   owned,
                   key,
                   selected,
                   context,
                   fn managed ->
                     with {:ok, prepared} <-
                            PendingCorrection.prepare(
                              context,
                              managed,
                              text,
                              selected.snapshot["policy"]["expires_at_ms"],
                              System.system_time(:millisecond)
                            ),
                          {:ok, caps} <- Transaction.retained_share_stack(),
                          {:ok, handle} <-
                            ManagementTerminal.begin_pending_correction_review(
                              owned,
                              caps,
                              prepared["facts"],
                              wall
                            ),
                          do: {:ok, {handle, prepared}},
                          else: (_ -> @error)
                   end
                 ) do
            reviewed_effect(
              config,
              cwd,
              history_dir,
              owned,
              token,
              prepared,
              handle,
              request["reserved"]
            )
          end
        rescue
          _ -> @unknown
        catch
          _, _ -> @unknown
        end

      if Writer.release(owned.writer, token) == :ok, do: result, else: @unknown
    else
      _ -> @error
    end
  rescue
    _ -> @unknown
  end

  # This reads authenticated historical proposal data, not a current source.
  # Source availability/consent are checked independently after native input.
  defp initial_review(config, cwd, _owned, key, selected, context, fun) do
    pin = context["original_pin"]

    ProjectIdentity.with_existing_domain_auth(
      config[:home],
      cwd,
      selected.binding,
      %{namespace: pin["namespace"], format: "managed-metadata-v3"},
      fn cap, catalog ->
        Consent.with_policy(
          SemanticAdmission.control_root(config[:home]),
          selected.binding["project_id"],
          pin["epoch"],
          pin["policy_sha256"],
          System.system_time(:millisecond),
          fn _ ->
            with {:ok, selection} <- Management.selection(config[:home]),
                 true <- selection === selected.selection do
              ObservedRead.with_managed_proposal_removal(
                SemanticAdmission.collection_root(config[:home]),
                pin["namespace"],
                %{"op" => "get_record", "key" => key},
                cap,
                catalog,
                context["recipe"],
                fun
              )
            else
              _ -> @error
            end
          end
        )
      end
    )
  end

  defp reviewed_effect(config, cwd, history_dir, owned, token, prepared, handle, reserved) do
    slot = {__MODULE__, make_ref()}

    try do
      result =
        Review.with_management_input("correct", prepared["facts"], handle, fn permit ->
          publish(config, cwd, history_dir, owned, token, prepared, permit, reserved, slot)
        end)

      case Process.get(slot) do
        :intent_unconfirmed ->
          @unknown

        state ->
          event = %{
            "type" => "managed_lifecycle_result",
            "version" => 1,
            "operation_id" => prepared["facts"]["operation_id"],
            "status" =>
              case result do
                {:ok, _} -> "settled"
                {:error, _} -> "refused"
                _ -> "unconfirmed"
              end,
            "result" =>
              case result do
                {:ok, packet} -> Map.delete(packet, "actual")
                {_, reason} -> %{"reason" => inspect(reason)}
              end
          }

          if state == nil and not match?({:error, _}, result) do
            @unknown
          else
            if Writer.append_reserved(owned.writer, token, event) == :ok,
              do: result,
              else: @unknown
          end
      end
    after
      Process.delete(slot)
    end
  end

  defp publish(config, cwd, history_dir, owned, token, prepared, permit, reserved, slot) do
    facts = prepared["facts"]
    card = facts["source_card"]

    with {:ok, selected} <-
           Management.acceptance_source_selection(config, cwd, history_dir, owned.id),
         pin = selected.context.config.semantic_admission["pin"],
         true <-
           card["capture_epoch"] === pin["epoch"] and
             card["policy_sha256"] === pin["policy_sha256"],
         true <- card["binding_sha256"] === selected.binding["binding_sha256"],
         true <- facts["context"]["original_pin"] === pin,
         true <-
           facts["context"]["management_sha256"] ===
             Consent.management_sha256(
               selected.binding["project_id"],
               pin["epoch"],
               selected.snapshot["policy"]
             ),
         true <- facts["context"]["recipe"] === selected.selection.proposal,
         :ok <-
           PendingAcceptance.check_source_policy(
             card,
             selected.snapshot["policy"],
             selected.selection.recipe,
             System.system_time(:millisecond)
           ) do
      PendingAcceptance.with_shareable_source(selected.context, card, fn source, source_lease ->
        with true <- source["proof"] === card["source_proof"] do
          scope = %{
            namespace: pin["namespace"],
            format: "managed-metadata-v3",
            operation_id: facts["operation_id"],
            initialize: false
          }

          control = SemanticAdmission.control_root(config[:home])

          authorize = fn _ ->
            case Consent.with_policy(
                   control,
                   selected.binding["project_id"],
                   pin["epoch"],
                   pin["policy_sha256"],
                   System.system_time(:millisecond),
                   fn _ -> {:ok, :authorized} end
                 ) do
              {:ok, :authorized} -> :ok
              error -> error
            end
          end

          ProjectIdentity.with_domain_publication(
            config[:home],
            cwd,
            selected.binding,
            scope,
            authorize,
            fn cap, catalog ->
              Consent.with_policy(
                control,
                selected.binding["project_id"],
                pin["epoch"],
                pin["policy_sha256"],
                System.system_time(:millisecond),
                fn snapshot ->
                  with :ok <- Review.check(permit, "correct", facts),
                       {:ok, current_selection} <- Management.selection(config[:home]),
                       true <- current_selection === selected.selection,
                       true <-
                         snapshot["policy"]["expires_at_ms"] === facts["policy_expires_at_ms"],
                       :ok <-
                         PendingAcceptance.check_source_policy(
                           card,
                           snapshot["policy"],
                           selected.selection.recipe,
                           System.system_time(:millisecond)
                         ),
                       _ <- Process.put(slot, :intent_unconfirmed),
                       :ok <- Writer.append_reserved(owned.writer, token, prepared["intent"]),
                       _ <- Process.put(slot, :intent_confirmed) do
                    measured(
                      config,
                      owned,
                      prepared,
                      permit,
                      source_lease,
                      reserved,
                      cap,
                      catalog,
                      snapshot["policy"],
                      selected.selection.recipe
                    )
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
      end)
    else
      _ -> @error
    end
  end

  defp measured(
         config,
         owned,
         prepared,
         permit,
         source_lease,
         reserved,
         cap,
         catalog,
         policy,
         note_recipe
       ) do
    facts = prepared["facts"]
    owner = self()
    slot = {__MODULE__, make_ref()}

    try do
      normalize = fn witness, read ->
        with true <- self() == owner and is_nil(Process.get(slot)),
             _ <- Process.put(slot, :claimed),
             {:ok, normalized, receipt} = result <-
               NormalizerV3.correct_pending(witness, read, %{
                 request: prepared["request"],
                 facts: facts,
                 permit: permit,
                 now_ms: System.system_time(:millisecond),
                 domain_cap: cap,
                 catalog: catalog,
                 policy: policy,
                 note_recipe: note_recipe,
                 verified_sources: [facts["source_card"]["source_proof"]]
               }),
             {:ok, actual} <-
               ManagedCollectionCall.measured_accounting(
                 %{"metadata_version" => 3, "request" => prepared["request"], "facts" => facts},
                 normalized,
                 receipt,
                 reserved
               ) do
          Process.put(slot, {JSON.digest([normalized]), receipt, actual})
          result
        else
          _ -> {:error, :collection_accounting_invalid}
        end
      end

      with {:ok, core} <-
             Collection.execute_pending_correction(
               SemanticAdmission.collection_root(config[:home]),
               facts["context"]["namespace"],
               prepared["request"],
               facts["operation_id"],
               JSON.digest([facts["context"]["recipe"]]),
               normalize,
               owned,
               prepared["intent"],
               permit,
               source_lease
             ),
           {digest, receipt, actual} <- Process.get(slot),
           true <-
             digest === core["receipt"]["request_sha256"] and receipt === core["normalization"] do
        {:ok,
         %{
           "journal_id" => owned.id,
           "operation_id" => facts["operation_id"],
           "replacement_pending_key" => Enum.at(prepared["request"]["changes"], 1)["key"],
           "actual" => actual,
           "receipt" => core
         }}
      end
    after
      Process.delete(slot)
    end
  end

  defp settle(control, project, ticket, result) do
    {outcome, report} =
      case result do
        {:closed, {:ok, packet}} ->
          {{:known, packet["actual"], Map.delete(packet, "actual")},
           {:ok, Map.delete(packet, "actual")}}

        {:closed, {:error, _} = error} ->
          {{:known, Consent.zero(), %{"refused" => true}}, error}

        {:error, _} = error ->
          {{:known, Consent.zero(), %{"refused" => true}}, error}

        _ ->
          {:unknown, @unknown}
      end

    case Consent.settle(control, project, ticket, outcome) do
      {:ok, _} -> report
      _ -> @unknown
    end
  end
end
