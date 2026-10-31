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

  def forget(config, cwd, key), do: manage(config, cwd, key, %{"kind" => "session"})
  def expire(config, cwd, key), do: manage(config, cwd, key, :expiry)

  def retain(config, cwd, key, policy) do
    if ManagedRetention.policy?(policy), do: manage(config, cwd, key, policy), else: @error
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
         {:ok, id} <-
           Journal.create(directory, %{
             "kind" => "knowledge_management",
             "version" => 1,
             "project_id" => binding["project_id"],
             "namespace" => namespace,
             "source_origin_layout" => Ipse.Journal.SourceOrigin.layout()
           }),
         {:ok, _} <- Lock.acquire(Path.join(directory, id <> ".lock")) do
      guard = Lock.current()

      result =
        try do
          with {:ok, writer} <- Writer.start(directory, id, self()) do
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
               ObservedRead.managed_record(
                 SemanticAdmission.collection_root(config[:home]),
                 namespace,
                 %{"op" => "get_record", "key" => key},
                 cap,
                 catalog,
                 selection.recipe
               )
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

        if facts["kind"] == "managed_literal_expiry" do
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
  defp operation("managed_literal_retention"), do: "collection.retention"
  defp operation("managed_literal_forget"), do: "collection.forget"

  defp check_review(%{"kind" => "managed_literal_expiry"}, nil), do: :ok

  defp check_review(facts, permit),
    do: Review.check(permit, ManagedRetention.command(facts["policy"]), facts)

  defp normalizer("managed_literal_expiry"), do: &NormalizerV3.expire/3
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
