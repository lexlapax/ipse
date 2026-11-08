defmodule Ipse.Session.ManagedUse do
  @moduledoc """
  Current authority for host-admitted managed dependencies during a use callback.

  Historical receipts identify what to revalidate, never permission to send.
  Source ownership is acquired outside Identity/Consent; the final protected
  observation must reproduce the provisional records before entering the caller.
  The caller must put the actual send or bounded publication inside the callback.
  """
  alias Ipse.{JSON, Journal.Writer}

  alias Ipse.Extension.{
    Collection,
    Collection.ObservedRead,
    Consent,
    ManagedRecipe,
    Mode,
    ProjectIdentity,
    SemanticAdmission,
    SemanticConsent
  }

  alias Ipse.Session.{ManagedReference, PendingAcceptance, Resources, StoredSources}
  alias Ipse.Runner.Transaction
  @error {:error, :managed_dependency_unavailable}
  @max_sources 128

  @doc """
  Inspect a committed accepted decision under its original owners and current policy.

  This host-only result contains a bounded historical reference, hashes and a
  deadline, not the decision text. It is historical as soon as the leases are
  released and grants no authority to send, publish, display, or select the
  decision for a worker.
  """
  def inspect_accepted(context, link, recipe_sha) when is_map(context) and is_map(link) do
    Resources.file_effect(fn -> inspect_accepted_owned(context, link, recipe_sha) end)
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  def inspect_accepted(_, _, _), do: @error

  @doc """
  Reinspect one historical accepted-decision reference without delivering it.

  The link is discovered from the current Collection, then authenticated again
  against the original committed journal, source, signed rows and policy. The
  returned inspection is historical and must not authorize an effect or send.
  """
  def inspect_accepted_reference(context, %{"version" => 6} = dependency) do
    accepted_reference(context, dependency, fn inspection, _, _ -> {:ok, inspection} end, :import)
  end

  def inspect_accepted_reference(_, _), do: @error

  @doc false
  # Host-only retained revalidation. The callback receives hashes, a bounded
  # dependency and the two owner-bound lease tokens, never the accepted text.
  # It must not treat the callback or tokens as permission to disclose data.
  def with_accepted_reference(context, %{"version" => 6} = dependency, fun)
      when is_function(fun, 3),
      do: accepted_reference(context, dependency, fun, :retained)

  def with_accepted_reference(_, _, _), do: @error

  defp accepted_reference(context, dependency, fun, lease_mode) do
    entered = :atomics.new(1, signed: false)

    result =
      try do
        accepted_reference_owned(context, dependency, fun, lease_mode, entered)
      rescue
        _ -> @error
      catch
        _, _ -> @error
      end

    if lease_mode == :retained and :atomics.get(entered, 1) == 1 and
         not match?({:ok, _}, result),
       do: {:unknown, :accepted_reference_unconfirmed},
       else: result
  end

  defp accepted_reference_owned(context, dependency, fun, lease_mode, entered) do
    Resources.file_effect(fn ->
      admission = context.config[:semantic_admission]
      pin = admission["pin"]
      link_identity = get_in(dependency, ["subject", "acceptance", "link"])
      recipe_sha = get_in(dependency, ["subject", "validity", "recipe_sha256"])
      request = %{"op" => "get_record", "key" => link_identity["key"]}

      with true <- ManagedReference.dependency?(dependency),
           true <- dependency["project_id"] === pin["project_id"],
           true <- dependency["namespace"] === pin["namespace"],
           true <- dependency["policy_generation"] === pin["epoch"],
           true <- dependency["pin_sha256"] === JSON.digest([pin]),
           {:ok, link} <-
             protected(context, [%{"version" => 4}], fn _, _, _ ->
               with {:ok, observation} <-
                      ObservedRead.read(
                        SemanticAdmission.collection_root(context.config[:home]),
                        pin["namespace"],
                        request
                      ),
                    record when is_map(record) <- observation["value"]["record"],
                    true <-
                      link_identity === %{
                        "key" => record["key"],
                        "revision" => record["revision"],
                        "value_sha256" => record["sha256"]
                      } do
                 {:ok, record["value"]}
               else
                 _ -> @error
               end
             end),
           result <-
             inspect_accepted_owned(
               context,
               link,
               recipe_sha,
               fn inspection, journal, source ->
                 if ManagedReference.current?(
                      dependency,
                      inspection["dependency"],
                      System.system_time(:millisecond)
                    ) do
                   :atomics.put(entered, 1, 1)
                   fun.(inspection, journal, source)
                 else
                   @error
                 end
               end,
               lease_mode
             ) do
        result
      else
        _ -> @error
      end
    end)
  end

  defp inspect_accepted_owned(
         context,
         link,
         recipe_sha,
         fun \\ fn inspection, _, _ ->
           {:ok, inspection}
         end,
         lease_mode \\ :import
       ) do
    admission = context.config[:semantic_admission]
    pin = admission["pin"]
    settings = admission["policy"]["settings"]
    recipe = settings["recipes"][recipe_sha]

    with true <- JSON.sha256?(recipe_sha),
         true <- ManagedRecipe.valid?(recipe) and JSON.digest([recipe]) === recipe_sha,
         {:ok, _} <- SemanticAdmission.context(context.config, context.session_id, 0) do
      PendingAcceptance.with_shareable_committed_management_journal(
        context.config[:home],
        pin["project_id"],
        pin["namespace"],
        link,
        fn resolved, journal_lease ->
          proof = resolved.event["facts"]["source_proof"]

          StoredSources.with_shareable_verified(context, proof, fn source, source_lease ->
            with true <- source["proof"] === proof do
              protected(context, [%{"version" => 4}], fn cap, catalog, policy ->
                ObservedRead.with_accepted_decision(
                  SemanticAdmission.collection_root(context.config[:home]),
                  pin["namespace"],
                  resolved.event,
                  cap,
                  catalog,
                  recipe,
                  System.system_time(:millisecond),
                  fn observed ->
                    with true <- observed["link"]["value"] === link,
                         {:ok, deadline} <-
                           PendingAcceptance.accepted_use_policy(
                             resolved.event,
                             observed["metadata"],
                             policy,
                             recipe,
                             System.system_time(:millisecond)
                           ),
                         {:ok, dependency} <-
                           ObservedRead.accepted_dependency(
                             resolved.event,
                             observed,
                             pin,
                             recipe,
                             proof,
                             System.system_time(:millisecond)
                           ) do
                      transaction = Process.get({Ipse.Extension.Collection, :lock_held})

                      use = fn ->
                        with :ok <- Ipse.Runner.Transaction.check(transaction),
                             true <- System.system_time(:millisecond) < deadline do
                          inspection = %{
                            "acceptance_event_sha256" => JSON.digest([resolved.event]),
                            "record_sha256" => observed["record"]["sha256"],
                            "link_sha256" => observed["link"]["sha256"],
                            "valid_until_ms" => deadline,
                            "dependency" => dependency
                          }

                          fun.(inspection, journal_lease, source_lease)
                        else
                          _ -> @error
                        end
                      end

                      if lease_mode == :retained do
                        use.()
                      else
                        Ipse.Runner.Transaction.with_inactive_acceptance_journal_lease(
                          transaction,
                          journal_lease,
                          fn ->
                            Ipse.Runner.Transaction.with_source_lease(
                              transaction,
                              source_lease,
                              use
                            )
                          end
                        )
                      end
                    else
                      _ -> @error
                    end
                  end
                )
              end)
            else
              _ -> @error
            end
          end)
        end
      )
    else
      _ -> @error
    end
  end

  def with_dependencies(_context, [], fun) when is_function(fun, 1), do: fun.([])

  def with_dependencies(context, dependencies, fun) when is_function(fun, 1) do
    with {:ok, ^dependencies} <- ManagedReference.union([dependencies]),
         true <- bounded?(dependencies),
         true <- Enum.all?(dependencies, &bound?(&1, context)) do
      with_accepted_journals(context, dependencies, fn journals ->
        with_dependencies_owned(context, dependencies, fun, journals)
      end)
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  defp with_dependencies_owned(context, dependencies, fun, journals) do
    with {:ok, first} <-
           protected(context, dependencies, fn cap, catalog, _ ->
             observe(context, dependencies, cap, catalog, journals)
           end),
         true <- length(first.proofs) <= @max_sources do
      use = fn _ ->
        protected(context, dependencies, fn cap, catalog, policy ->
          checked_observation(
            use_deadline(policy, first.current),
            fn ->
              with {:ok, ^first} <- observe(context, dependencies, cap, catalog, journals),
                   true <-
                     Enum.all?(Enum.zip(dependencies, first.current), fn {old, current} ->
                       ManagedReference.current?(old, current, System.system_time(:millisecond))
                     end) do
                {:ok, first.current}
              else
                _ -> @error
              end
            end,
            fun
          )
        end)
      end

      if first.proofs == [],
        do: use.([]),
        else: StoredSources.with_verified(context, nil, first.proofs, use)
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  @doc """
  Retain transferable original sources and the actual Identity/Consent/Collection
  owners for a trusted display adapter. No bytes are displayed by this function.

  The adapter must bind its exact Session, purpose, payload and native sink,
  transfer every owner, and confirm settlement before returning. Active original
  proofs still require the owning Session's separate sealed Writer/lock handoff.
  Accepted decisions refuse here: their additional original management-journal
  owner must also be transferred by an accepted-decision display adapter.
  Once the adapter is entered, refusal, interruption or unconfirmed cleanup is
  unknown; it never becomes a claim that no display happened.
  """
  def with_display_dependencies(context, dependencies, fun)
      when is_map(context) and is_list(dependencies) and is_function(fun, 2) do
    retained_dependencies(context, dependencies, fun, :display)
  end

  def with_display_dependencies(_, _, _), do: @error

  @doc false
  # Ordinary model-tool approval additionally retains accepted-decision journals.
  # Its native adapter must export and settle every returned lease before input.
  def with_approval_dependencies(context, dependencies, fun)
      when is_map(context) and is_list(dependencies) and is_function(fun, 2),
      do: retained_dependencies(context, dependencies, fun, :approval)

  def with_approval_dependencies(_, _, _), do: @error

  @doc false
  # The Session-owned export adapter must transfer every returned journal lease
  # to its actual stdin sink. This does not open accepted-decision UI display.
  def with_worker_dependencies(context, dependencies, fun)
      when is_map(context) and is_list(dependencies) and is_function(fun, 2),
      do: retained_dependencies(context, dependencies, fun, :worker)

  def with_worker_dependencies(_, _, _), do: @error

  @doc false
  # Publication acquires Identity/Consent/Collection itself. Retain original
  # journals first, then hand the provisional observation to that publisher;
  # its actual native owner must match the selected root and import every lease.
  def with_publication_dependencies(context, dependencies, proofs, fun)
      when is_list(dependencies) and is_list(proofs) and is_function(fun, 1) do
    with true <- dependencies != [],
         {:ok, ^dependencies} <- ManagedReference.union([dependencies]),
         true <- bounded?(dependencies) and Enum.all?(dependencies, &bound?(&1, context)) do
      with_input_journals(context, dependencies, :worker, fn journals, journal_leases ->
        with {:ok, first} <-
               protected(context, dependencies, fn cap, catalog, policy ->
                 with {:ok, observed} <- observe(context, dependencies, cap, catalog, journals),
                      true <-
                        Enum.all?(Enum.zip(dependencies, observed.current), fn {old, current} ->
                          ManagedReference.current?(
                            old,
                            current,
                            System.system_time(:millisecond)
                          )
                        end) do
                   {:ok,
                    Map.put(
                      observed,
                      :deadline_ms,
                      use_deadline(policy, observed.current)["expires_at_ms"]
                    )}
                 else
                   _ -> @error
                 end
               end),
             all = Enum.uniq(first.proofs ++ proofs),
             true <- length(all) in 1..@max_sources do
          StoredSources.with_shareable_union(context, nil, all, fn _, leases, _ ->
            with true <- length(leases) + length(journal_leases) <= @max_sources,
                 true <- System.system_time(:millisecond) < first.deadline_ms,
                 true <-
                   Enum.all?(journal_leases, fn lease ->
                     match?(
                       {:ok, _},
                       PendingAcceptance.journal_share_verified_identity(lease.token, lease.link)
                     )
                   end) do
              fun.(%{
                owner: self(),
                current: first.current,
                source_proofs: all,
                source_leases: leases,
                journal_leases: journal_leases,
                deadline_ms: first.deadline_ms
              })
            else
              _ -> @error
            end
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

  defp retained_dependencies(context, dependencies, fun, purpose) do
    entered = :atomics.new(2, signed: true)

    result =
      prepare_display_dependencies(
        context,
        dependencies,
        fn current, held ->
          :atomics.put(entered, 2, held.deadline)
          :atomics.put(entered, 1, 1)
          fun.(current, held)
        end,
        purpose
      )

    if :atomics.get(entered, 1) == 1 and
         (not match?({:ok, _}, result) or
            System.monotonic_time(:millisecond) >= :atomics.get(entered, 2)),
       do: {:unknown, :managed_display_ownership_unconfirmed},
       else: result
  end

  defp prepare_display_dependencies(context, dependencies, fun, purpose) do
    with true <- dependencies != [],
         {:ok, ^dependencies} <- ManagedReference.union([dependencies]),
         true <-
           Enum.all?(
             dependencies,
             &(&1["version"] in if(purpose in [:worker, :approval],
                 do: [3, 4, 5, 6, 7],
                 else: [3, 4, 5, 7]
               ))
           ),
         true <- bounded?(dependencies) and Enum.all?(dependencies, &bound?(&1, context)) do
      Resources.file_effect(fn ->
        with_input_journals(context, dependencies, purpose, fn journals, journal_leases ->
          with {:ok, first} <-
                 protected(context, dependencies, fn cap, catalog, _ ->
                   observe(context, dependencies, cap, catalog, journals)
                 end),
               true <- length(first.proofs) <= @max_sources do
            use = fn _sources, leases, active ->
              if length(leases) + length(journal_leases) <= @max_sources and
                   Enum.all?(journal_leases, fn lease ->
                     match?(
                       {:ok, _},
                       PendingAcceptance.journal_share_verified_identity(lease.token, lease.link)
                     )
                   end) do
                display_dependencies_owned(
                  context,
                  dependencies,
                  first,
                  leases,
                  active,
                  journals,
                  journal_leases,
                  fun
                )
              else
                @error
              end
            end

            if first.proofs == [],
              do: use.([], [], false),
              else: StoredSources.with_shareable_union(context, nil, first.proofs, use)
          else
            _ -> @error
          end
        end)
      end)
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  defp display_dependencies_owned(
         context,
         dependencies,
         first,
         leases,
         active,
         journals,
         journal_leases,
         fun
       ) do
    protected(context, dependencies, fn cap, catalog, policy ->
      with {:ok, ^first} <- observe(context, dependencies, cap, catalog, journals),
           policy = use_deadline(policy, first.current),
           deadline = min(policy["expires_at_ms"], System.system_time(:millisecond) + 5_000),
           true <- System.system_time(:millisecond) < deadline,
           true <-
             Enum.all?(Enum.zip(dependencies, first.current), fn {old, current} ->
               ManagedReference.current?(old, current, System.system_time(:millisecond))
             end) do
        pin = context.config.semantic_admission["pin"]

        Collection.with_managed_read(
          SemanticAdmission.collection_root(context.config.home),
          pin["namespace"],
          fn witness, _read, alive ->
            with {:ok, pointer} <-
                   if(is_binary(witness["root_bytes"]),
                     do: JSON.decode_bounded(witness["root_bytes"], 1024),
                     else: {:ok, nil}
                   ),
                 root_witness =
                   witness
                   |> Map.take(~w(version root_state root_sha256 manifest_sha256))
                   |> Map.put("root", pointer),
                 {:ok, root} <- ObservedRead.root_identity(root_witness, pin["namespace"]),
                 true <- Enum.all?(first.current, &(&1["collection"] === root)),
                 {:ok, [identity, consent, collection] = caps} <-
                   Transaction.retained_share_stack(),
                 true <- Process.get({ProjectIdentity, :lock_held}) === true,
                 true <- Process.get({Consent, :lock_held}) === consent,
                 true <- Process.get({Collection, :lock_held}) === collection,
                 true <- Enum.all?(caps, &(&1.owner == self())),
                 :ok <- alive.(),
                 remaining = min(deadline - System.system_time(:millisecond), 5_000),
                 true <- remaining > 0 do
              fun.(first.current, %{
                owner: self(),
                identity: identity,
                consent: consent,
                collection: collection,
                source_leases: leases,
                journal_leases: journal_leases,
                source_proofs: first.proofs,
                active_sources: active,
                deadline: System.monotonic_time(:millisecond) + remaining,
                deadline_ms: deadline
              })
            else
              _ -> @error
            end
          end
        )
      else
        _ -> @error
      end
    end)
  end

  @doc """
  Select one historical literal inside its current source and policy leases.

  This is a host-only primitive. The caller owns selection and any journaled
  admission; workers must not choose the key or receive unprotected history.
  The callback receives the authenticated historical observation and its
  versioned dependency while the leases remain held. A later use must reacquire
  those leases through `with_dependencies/3`.
  """
  def with_history_selection(context, key, recipe_sha, fun) when is_function(fun, 2) do
    pin = context.config[:semantic_admission]["pin"]
    root = SemanticAdmission.collection_root(context.config[:home])
    auth = [%{"version" => 5}]

    with {:ok, first, dependency, proofs} <-
           protected(context, auth, fn cap, catalog, _ ->
             observe_history(context, root, pin, key, recipe_sha, cap, catalog)
           end),
         true <- length(proofs) in 1..@max_sources do
      StoredSources.with_verified(context, nil, proofs, fn _ ->
        protected(context, auth, fn cap, catalog, policy ->
          checked_observation(
            use_deadline(policy, [dependency]),
            fn ->
              with {:ok, ^first, ^dependency, ^proofs} <-
                     observe_history(context, root, pin, key, recipe_sha, cap, catalog),
                   true <-
                     ManagedReference.current?(
                       dependency,
                       dependency,
                       System.system_time(:millisecond)
                     ) do
                {:ok, first}
              else
                _ -> @error
              end
            end,
            fn observation -> fun.(observation, dependency) end
          )
        end)
      end)
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  @doc "Historical preflight verdicts; actual use must acquire authority again."
  def verdicts(_context, []), do: []

  def verdicts(context, dependencies) do
    if Enum.any?(dependencies, &(&1["version"] === 6)) do
      accepted_verdicts(context, dependencies)
    else
      ordinary_verdicts(context, dependencies)
    end
  end

  defp accepted_verdicts(context, dependencies) do
    with {:ok, ^dependencies} <- ManagedReference.union([dependencies]),
         true <- bounded?(dependencies) and Enum.all?(dependencies, &bound?(&1, context)) do
      ordinary = Enum.reject(dependencies, &(&1["version"] === 6))
      by_id = ordinary_verdicts(context, ordinary) |> Map.new(&{&1["dependency_sha256"], &1})

      Enum.map(dependencies, fn dependency ->
        if dependency["version"] === 6 do
          result =
            with {:ok, inspected} <- inspect_accepted_reference(context, dependency),
                 do: {:ok, inspected["dependency"]}

          verdict(dependency, result)
        else
          by_id[JSON.digest([dependency])]
        end
      end)
    else
      _ -> Enum.map(dependencies, &verdict(&1, @error))
    end
  rescue
    _ -> Enum.map(dependencies, &verdict(&1, @error))
  end

  defp ordinary_verdicts(_context, []), do: []

  defp ordinary_verdicts(context, dependencies) do
    with {:ok, ^dependencies} <- ManagedReference.union([dependencies]),
         true <- bounded?(dependencies),
         true <- Enum.all?(dependencies, &bound?(&1, context)),
         {:ok, first} <-
           protected(context, dependencies, fn cap, catalog, _ ->
             observe_all(context, dependencies, cap, catalog)
           end),
         proofs =
           first
           |> Map.values()
           |> Enum.flat_map(fn
             {:ok, _, proofs} -> proofs
             _ -> []
           end)
           |> Enum.uniq(),
         true <- length(proofs) <= @max_sources,
         {:ok, statuses} <-
           if(proofs == [], do: {:ok, %{}}, else: StoredSources.snapshot(context, proofs)),
         {:ok, verdicts} <-
           protected(context, dependencies, fn cap, catalog, policy ->
             checked_observation(
               policy,
               fn -> observe_all(context, dependencies, cap, catalog) end,
               fn second ->
                 now = System.system_time(:millisecond)

                 {:ok,
                  Enum.map(dependencies, fn dependency ->
                    id = JSON.digest([dependency])

                    result =
                      with {:ok, prior, proofs} <- first[id],
                           {:ok, current, ^proofs} <- second[id],
                           true <- Enum.all?(proofs, &(statuses[JSON.digest([&1])] === true)),
                           true <- ManagedReference.current?(prior, current, now),
                           true <- ManagedReference.current?(dependency, current, now),
                           do: {:ok, current}

                    verdict(dependency, result)
                  end)}
               end
             )
           end) do
      verdicts
    else
      _ -> Enum.map(dependencies, &verdict(&1, @error))
    end
  rescue
    _ -> Enum.map(dependencies, &verdict(&1, @error))
  end

  @doc false
  def root_transition_observation(context, dependencies, action) do
    pin = context.config[:semantic_admission]["pin"]
    root = SemanticAdmission.collection_root(context.config[:home])
    request = %{"op" => "snapshot"}
    receipt = get_in(action, ["outcome", "value", "receipt"])
    operation = action["operation_id"]

    with {:ok, ^dependencies} <- ManagedReference.union([dependencies]),
         true <- dependencies != [] and Enum.all?(dependencies, &bound?(&1, context)),
         true <- Ipse.Extension.Actions.valid_result?(action),
         true <- Ipse.Extension.ManagedCollectionCall.new_capture?(action["request"]),
         true <- action["outcome"]["status"] === "ok",
         {:ok, result} <-
           protected(context, dependencies, fn _, _, policy ->
             checked_observation(
               policy,
               fn ->
                 with {:ok, first} <- ObservedRead.read(root, pin["namespace"], request),
                      {:ok, guard} <- ObservedRead.root_dependency(request, first, pin),
                      {:ok, inspected} <-
                        Ipse.Extension.Collection.execute(
                          root,
                          pin["namespace"],
                          %{"op" => "inspect", "operation_id" => operation},
                          Ipse.Usage.id()
                        ),
                      {:ok, ^first} <- ObservedRead.read(root, pin["namespace"], request),
                      true <- inspected["operation"] === receipt,
                      true <- inspected["generation"] === receipt["generation"],
                      true <- inspected["floor"] === receipt["floor"],
                      true <- inspected["floor_anchor"] === operation,
                      true <- guard["collection"]["generation"] === receipt["generation"],
                      true <- guard["collection"]["floor"] === receipt["floor"],
                      true <- guard["collection"]["floor_anchor"] === operation do
                   {:ok, %{observation: first, guard: guard, inspected: inspected}}
                 else
                   _ -> @error
                 end
               end,
               &{:ok, &1}
             )
           end) do
      {:ok, result}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  catch
    _, _ -> @error
  end

  @doc false
  def checked_observation(policy, observe, use)
      when is_function(observe, 0) and is_function(use, 1) do
    with {:ok, current} <- observe.(),
         deadline when is_integer(deadline) <- policy["expires_at_ms"],
         true <- System.system_time(:millisecond) < deadline do
      use.(current)
    else
      _ -> @error
    end
  end

  defp use_deadline(policy, dependencies) do
    deadline =
      Enum.reduce(dependencies, policy["expires_at_ms"], fn dependency, deadline ->
        case get_in(dependency, ["subject", "validity", "valid_until_ms"]) do
          value when is_integer(value) -> min(value, deadline)
          _ -> deadline
        end
      end)

    Map.put(policy, "expires_at_ms", deadline)
  end

  defp verdict(dependency, {:ok, current}),
    do: %{
      "dependency_sha256" => JSON.digest([dependency]),
      "status" => "eligible",
      "current" => current
    }

  defp verdict(dependency, _),
    do: %{
      "dependency_sha256" => JSON.digest([dependency]),
      "status" => "unavailable",
      "current" => nil
    }

  defp bounded?(dependencies) do
    records =
      for %{"version" => version, "subject" => subject} <- dependencies,
          version in [4, 5, 6, 7],
          do: {subject["key"], get_in(subject, ["validity", "recipe_sha256"])}

    length(dependencies) <= 2048 and length(Enum.uniq(records)) <= @max_sources
  end

  @doc false
  def sources(s, caller, binding, proofs) do
    with %{pid: worker} <- s.task,
         true <- caller == worker or Ipse.Session.Resources.authorized_effect?(worker, caller),
         true <- binding_current?(s, binding),
         true <- is_list(proofs) and length(proofs) in 1..@max_sources,
         true <- Enum.all?(proofs, &(is_map(&1) and &1["session_id"] == s.id)),
         {:ok, origin} when is_map(origin) <- Writer.source_query(s.journal_writer, :origin) do
      result =
        Enum.reduce_while(proofs, {:ok, []}, fn proof, {:ok, acc} ->
          case Writer.source_query(s.journal_writer, {:stored_proof, proof}) do
            {:ok, checked} -> {:cont, {:ok, acc ++ [checked]}}
            _ -> {:halt, @error}
          end
        end)

      result
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp binding_current?(s, {:snapshot, phase, sha}) do
    case Ipse.Session.managed_dependencies(s, phase) do
      {:ok, %{sha256: ^sha}} -> true
      _ -> false
    end
  end

  defp binding_current?(s, {:inference, phase, expected}),
    do: Ipse.Session.InferenceDispatch.binding_current?(s, phase, expected)

  defp binding_current?(s, {:capture, sha}),
    do: Ipse.Session.ManagedCapture.binding_current?(s, sha)

  defp binding_current?(_, _), do: false

  defp bound?(dependency, c) do
    pin = c.config[:semantic_admission]["pin"]

    dependency["version"] in [3, 4, 5, 6, 7] and
      dependency["namespace"] == pin["namespace"] and
      dependency["project_id"] == pin["project_id"] and
      dependency["policy_generation"] === pin["epoch"] and
      dependency["pin_sha256"] == JSON.digest([pin])
  end

  defp protected(c, dependencies, fun) do
    admission = c.config[:semantic_admission]
    pin = admission["pin"]

    callback = fn cap, catalog ->
      check = fn snapshot ->
        with true <- snapshot["epoch"] === pin["epoch"],
             true <- JSON.digest([snapshot["policy"]]) === pin["policy_sha256"],
             {:ok, _} <- SemanticAdmission.context(c.config, c.session_id, 0),
             {:ok, mode} <- Mode.capture(c.config),
             :ok <- Mode.knowledge(mode, "collection.read"),
             true <- not mode["headless"] or snapshot["policy"]["headless"] do
          {:ok, fun.(cap, catalog, snapshot["policy"])}
        else
          _ -> @error
        end
      end

      root = SemanticAdmission.control_root(c.config[:home])
      now = System.system_time(:millisecond)

      if c[:experiment_ticket] do
        Consent.with_experiment_ticket(root, pin["project_id"], c.experiment_ticket, now, check)
      else
        Consent.with_policy(
          root,
          pin["project_id"],
          pin["epoch"],
          pin["policy_sha256"],
          now,
          check
        )
      end
    end

    result =
      if Enum.any?(dependencies, &(&1["version"] in [4, 5, 6, 7])) do
        ProjectIdentity.with_existing_domain_auth(
          c.config[:home],
          c.cwd,
          admission["binding"],
          %{namespace: pin["namespace"], format: "managed-metadata-v3"},
          callback
        )
      else
        ProjectIdentity.with_binding(c.config[:home], c.cwd, admission["binding"], fn _ ->
          callback.(nil, nil)
        end)
      end

    # Consent's read callback carries a pair; the owned-use callback may return
    # an opaque transport continuation result. Preserve it only after cleanup.
    case result do
      {:ok, value} -> value
      other -> other
    end
  end

  defp with_accepted_journals(context, dependencies, fun) do
    with {:ok, links} <- accepted_links(context, dependencies) do
      if links == [],
        do: fun.(%{}),
        else:
          PendingAcceptance.with_committed_management_journals(
            context.config[:home],
            context.config[:semantic_admission]["pin"]["project_id"],
            context.config[:semantic_admission]["pin"]["namespace"],
            links,
            fun
          )
    end
  end

  defp with_input_journals(context, dependencies, purpose, fun)
       when purpose in [:worker, :approval] do
    with {:ok, links} <- accepted_links(context, dependencies) do
      if links == [],
        do: fun.(%{}, []),
        else:
          PendingAcceptance.with_shareable_committed_management_journals(
            context.config[:home],
            context.config[:semantic_admission]["pin"]["project_id"],
            context.config[:semantic_admission]["pin"]["namespace"],
            links,
            fun
          )
    end
  end

  defp with_input_journals(_, _, :display, fun), do: fun.(%{}, [])

  defp accepted_links(context, dependencies) do
    accepted = Enum.filter(dependencies, &(&1["version"] === 6))

    if accepted == [] do
      {:ok, []}
    else
      admission = context.config[:semantic_admission]
      pin = admission["pin"]

      with {:ok, links} <-
             protected(context, dependencies, fn _, _, _ ->
               Enum.reduce_while(accepted, {:ok, []}, fn dependency, {:ok, links} ->
                 reference = dependency["subject"]["acceptance"]
                 identity = reference["link"]

                 with {:ok, observed} <-
                        ObservedRead.read(
                          SemanticAdmission.collection_root(context.config[:home]),
                          pin["namespace"],
                          %{"op" => "get_record", "key" => identity["key"]}
                        ),
                      record when is_map(record) <- observed["value"]["record"],
                      true <-
                        identity === %{
                          "key" => record["key"],
                          "revision" => record["revision"],
                          "value_sha256" => record["sha256"]
                        },
                      link when is_map(link) <- record["value"],
                      true <-
                        link["journal_id"] === reference["journal_id"] and
                          link["journal_kind"] === reference["journal_kind"],
                      true <- link["acceptance_event_sha256"] === reference["event_sha256"] do
                   {:cont, {:ok, links ++ [link]}}
                 else
                   _ -> {:halt, @error}
                 end
               end)
             end) do
        {:ok, links}
      else
        _ -> @error
      end
    end
  end

  defp observe(c, dependencies, cap, catalog, journals) do
    with {:ok, results} <- observe_all(c, dependencies, cap, catalog, journals) do
      Enum.reduce_while(dependencies, {:ok, %{current: [], proofs: []}}, fn dependency,
                                                                            {:ok, acc} ->
        case results[JSON.digest([dependency])] do
          {:ok, current, proofs} ->
            {:cont,
             {:ok, %{current: acc.current ++ [current], proofs: Enum.uniq(acc.proofs ++ proofs)}}}

          _ ->
            {:halt, @error}
        end
      end)
    end
  end

  defp observe_all(c, dependencies, cap, catalog, journals \\ %{}) do
    pin = c.config[:semantic_admission]["pin"]
    root = SemanticAdmission.collection_root(c.config[:home])

    {results, _} =
      Enum.reduce(dependencies, {%{}, %{}}, fn dependency, {results, cache} ->
        key =
          if dependency["version"] == 3,
            do: :root,
            else:
              {dependency["version"], dependency["subject"]["key"],
               get_in(dependency, ["subject", "validity", "recipe_sha256"])}

        result =
          Map.get_lazy(cache, key, fn ->
            if key == :root,
              do: observe_root(root, pin),
              else: observe_dependency(c, root, pin, dependency, cap, catalog, journals)
          end)

        checked =
          if key == :root do
            with {:ok, actual} <- result,
                 true <- actual === dependency["collection"],
                 do: {:ok, dependency, []}
          else
            result
          end

        {Map.put(results, JSON.digest([dependency]), checked), Map.put(cache, key, result)}
      end)

    {:ok, results}
  end

  defp observe_root(root, pin) do
    request = %{"op" => "snapshot"}

    with {:ok, observation} <- ObservedRead.read(root, pin["namespace"], request),
         {:ok, current} <- ObservedRead.root_dependency(request, observation, pin) do
      {:ok, current["collection"]}
    else
      _ -> @error
    end
  end

  defp observe_dependency(c, root, pin, %{"version" => 4} = dependency, cap, catalog, _) do
    settings = c.config[:semantic_admission]["policy"]["settings"]
    recipe_sha = get_in(dependency, ["subject", "validity", "recipe_sha256"])
    recipe = settings["recipes"][recipe_sha]
    request = %{"op" => "get_record", "key" => dependency["subject"]["key"]}

    with true <- ManagedRecipe.valid?(recipe) and JSON.digest([recipe]) == recipe_sha,
         true <- Enum.any?(settings["effects"], &(recipe_sha in Map.get(&1, "managed_read", []))),
         {:ok, managed} <-
           ObservedRead.managed_record(root, pin["namespace"], request, cap, catalog, recipe),
         value = managed["observation"]["value"]["record"]["value"],
         proofs when is_list(proofs) <-
           Enum.reduce(recipe["evidence_path"], value, fn key, value ->
             if is_map(value), do: value[key], else: nil
           end),
         :ok <-
           SemanticConsent.check_sources(
             c.config[:semantic_admission]["policy"],
             Enum.map(proofs, &%{"category" => &1["origin"], "path" => &1["path"]})
           ),
         {:ok, current} <-
           ObservedRead.managed_dependency(
             request,
             managed,
             pin,
             recipe,
             proofs,
             System.system_time(:millisecond)
           ) do
      {:ok, current, proofs}
    else
      _ -> @error
    end
  end

  defp observe_dependency(c, root, pin, %{"version" => 5} = dependency, cap, catalog, _) do
    with {:ok, _history, current, proofs} <-
           observe_history(
             c,
             root,
             pin,
             dependency["subject"]["key"],
             get_in(dependency, ["subject", "validity", "recipe_sha256"]),
             cap,
             catalog
           ) do
      {:ok, current, proofs}
    end
  end

  defp observe_dependency(c, root, pin, %{"version" => 7} = dependency, cap, catalog, _) do
    settings = c.config[:semantic_admission]["policy"]["settings"]
    recipe_sha = get_in(dependency, ["subject", "validity", "recipe_sha256"])
    recipe = settings["recipes"][recipe_sha]
    request = %{"op" => "get_record", "key" => dependency["subject"]["key"]}

    with true <-
           ManagedRecipe.valid?(recipe) and recipe["kind"] === "proposal" and
             JSON.digest([recipe]) === recipe_sha,
         true <- Enum.any?(settings["effects"], &(recipe_sha in Map.get(&1, "managed_read", []))),
         {:ok, managed} <-
           ObservedRead.managed_proposal(root, pin["namespace"], request, cap, catalog, recipe),
         value = managed["observation"]["value"]["record"]["value"],
         proofs when is_list(proofs) <-
           Enum.reduce(recipe["evidence_path"], value, fn key, v ->
             if is_map(v), do: v[key], else: nil
           end),
         :ok <-
           SemanticConsent.check_sources(
             c.config[:semantic_admission]["policy"],
             Enum.map(proofs, &%{"category" => &1["origin"], "path" => &1["path"]})
           ),
         {:ok, current} <-
           ObservedRead.proposal_dependency(
             request,
             managed,
             pin,
             recipe,
             proofs,
             System.system_time(:millisecond)
           ) do
      {:ok, current, proofs}
    else
      _ -> @error
    end
  end

  defp observe_dependency(c, root, pin, %{"version" => 6} = dependency, cap, catalog, journals) do
    settings = c.config[:semantic_admission]["policy"]["settings"]
    recipe_sha = get_in(dependency, ["subject", "validity", "recipe_sha256"])
    recipe = settings["recipes"][recipe_sha]
    acceptance = dependency["subject"]["acceptance"]

    with true <- ManagedRecipe.valid?(recipe) and JSON.digest([recipe]) === recipe_sha,
         %{event: event} <- journals[acceptance["journal_id"]],
         true <- JSON.digest([event]) === acceptance["event_sha256"],
         {:ok, %{current: current, proofs: proofs}} <-
           ObservedRead.with_accepted_decision(
             root,
             pin["namespace"],
             event,
             cap,
             catalog,
             recipe,
             System.system_time(:millisecond),
             fn observed ->
               with {:ok, _} <-
                      PendingAcceptance.accepted_use_policy(
                        event,
                        observed["metadata"],
                        c.config[:semantic_admission]["policy"],
                        recipe,
                        System.system_time(:millisecond)
                      ),
                    proof = event["facts"]["source_proof"],
                    {:ok, current} <-
                      ObservedRead.accepted_dependency(
                        event,
                        observed,
                        pin,
                        recipe,
                        proof,
                        System.system_time(:millisecond)
                      ) do
                 {:ok, %{current: current, proofs: [proof]}}
               else
                 _ -> @error
               end
             end
           ) do
      {:ok, current, proofs}
    else
      _ -> @error
    end
  end

  defp observe_history(c, root, pin, key, recipe_sha, cap, catalog) do
    settings = c.config[:semantic_admission]["policy"]["settings"]
    recipe = settings["recipes"][recipe_sha]
    request = %{"op" => "get_record", "key" => key}

    with true <- ManagedRecipe.valid?(recipe) and JSON.digest([recipe]) == recipe_sha,
         true <- Enum.any?(settings["effects"], &(recipe_sha in Map.get(&1, "managed_read", []))),
         {:ok, managed} <-
           ObservedRead.managed_history(root, pin["namespace"], request, cap, catalog, recipe),
         value = managed["observation"]["value"]["record"]["value"],
         proofs when is_list(proofs) <-
           Enum.reduce(recipe["evidence_path"], value, fn key, value ->
             if is_map(value), do: value[key], else: nil
           end),
         :ok <-
           SemanticConsent.check_sources(
             c.config[:semantic_admission]["policy"],
             Enum.map(proofs, &%{"category" => &1["origin"], "path" => &1["path"]})
           ),
         {:ok, dependency} <-
           ObservedRead.history_dependency(
             request,
             managed,
             pin,
             recipe,
             proofs,
             System.system_time(:millisecond)
           ) do
      {:ok, managed, dependency, proofs}
    else
      _ -> @error
    end
  end
end
