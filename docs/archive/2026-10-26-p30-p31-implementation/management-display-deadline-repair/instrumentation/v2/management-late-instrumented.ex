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

  def forget(_config, _cwd, _key),
    do: apply(__MODULE__, :reviewed_publication_admission, [])

  def expire(config, cwd, key), do: manage(config, cwd, key, :expiry)

  def retain(_config, _cwd, _key, policy) do
    cond do
      not ManagedRetention.policy?(policy) -> @error
      policy["kind"] != "session" -> {:error, :collection_deadline_fence_unavailable}
      true -> apply(__MODULE__, :reviewed_publication_admission, [])
    end
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
    deadline = min(overall_deadline, System.monotonic_time(:millisecond) + 5_000)
    operation = :crypto.strong_rand_bytes(16)

    with {:ok, scope} <- Resources.start(self()) do
      previous = Resources.bind(scope)

      try do
        with {:ok, port} <- Ipse.Runner.open_owner_control() do
          try do
            result =
              Resources.management_controlled_file_effect(
                fn control ->
                  share_journal_owned(config, cwd, fn owned ->
                    with_management_journal_control(owned, control, fun)
                  end)
                end,
                port,
                operation,
                deadline
              )

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

  def controlled_share_journal_candidate(_, _, _, _), do: @error

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

      management_display_completion(result, overall, System.system_time(:millisecond) - 1)
    else
      _ -> @error
    end
  rescue
    _ -> {:unknown, :management_display_unconfirmed}
  end

  def full_facts_display_candidate(_, _, _, _), do: @error

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
            ticket: make_ref()
          }

          fun.(Map.merge(owned, %{cli_control: cli_control, journal_control: control}))
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

    with true <- is_binary(id) and Regex.match?(~r/\A[0-9a-f]{32}\z/, id),
         {:ok, binding} when is_map(binding) <- ProjectIdentity.existing(config[:home], cwd),
         {:ok, namespace} <- SemanticConsent.namespace(binding["project_id"], "knowledge"),
         {:ok, [%{"type" => "session", "metadata" => metadata} | events]} <-
           Journal.load(directory, id),
         true <- metadata["kind"] == "knowledge_management" and metadata["version"] === 1,
         true <-
           metadata["project_id"] == binding["project_id"] and metadata["namespace"] == namespace,
         :ok <- Ipse.Journal.SourceOrigin.check_path(directory, id, metadata),
         intents = Enum.filter(events, &(&1["type"] == "managed_lifecycle_intent")),
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
         "journal_status" => if(result, do: result["status"], else: "unconfirmed"),
         "control_status" => if(operation, do: operation["status"], else: "unavailable"),
         "action_sha256" => if(intent, do: intent["facts"]["action_sha256"]),
         "replayed" => false,
         "current_note_eligibility" => "not_checked"
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
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
                 ObservedRead.managed_record(
                   SemanticAdmission.collection_root(config[:home]),
                   namespace,
                   %{"op" => "get_record", "key" => key},
                   cap,
                   catalog,
                   selection.recipe
                 )

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

  defp publish(config, cwd, binding, snapshot, selection, prepared, permit) do
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
          measured_forget(config, prepared, request["reserved"], permit, cap, catalog)
        end

        if facts["kind"] in ~w(managed_literal_expiry managed_literal_history_expiry) do
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
            if facts["kind"] == "managed_literal_retention",
              do: &Consent.retain_deferred/8,
              else: &Consent.forget_deferred/8

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

  defp measured_forget(config, prepared, reserved, permit, cap, catalog) do
    facts = prepared["facts"]
    envelope = %{"metadata_version" => 3, "request" => prepared["request"], "facts" => facts}
    slot = {__MODULE__, make_ref()}
    owner = self()

    try do
      result =
        Collection.execute_managed_v3(
          SemanticAdmission.collection_root(config[:home]),
          facts["context"]["namespace"],
          prepared["request"],
          facts["operation_id"],
          JSON.digest([facts["context"]["recipe"]]),
          fn witness, read ->
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
                 {:ok, actual} <-
                   ManagedCollectionCall.measured_accounting(
                     envelope,
                     normalized,
                     normalization,
                     reserved
                   ) do
              Process.put(slot, {JSON.digest([normalized]), normalization, actual})
              result
            else
              _ -> {:error, :collection_accounting_invalid}
            end
          end
        )

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
  defp operation("managed_literal_history_expiry"), do: "collection.expire"
  defp operation("managed_literal_retention"), do: "collection.retention"
  defp operation("managed_literal_forget"), do: "collection.forget"

  defp check_review(%{"kind" => "managed_literal_expiry"}, nil), do: :ok
  defp check_review(%{"kind" => "managed_literal_history_expiry"}, nil), do: :ok

  defp check_review(facts, permit),
    do: Review.check(permit, ManagedRetention.command(facts["policy"]), facts)

  defp normalizer("managed_literal_expiry"), do: &NormalizerV3.expire/3
  defp normalizer("managed_literal_history_expiry"), do: &NormalizerV3.expire_history/3
  defp normalizer("managed_literal_retention"), do: &NormalizerV3.retain/3
  defp normalizer("managed_literal_forget"), do: &NormalizerV3.forget/3

  defp selection(home) do
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
      {:ok, %{digest: digest, recipe: recipe}}
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
