defmodule Ipse.Session.ManagedSupersession do
  @moduledoc """
  Host-owned supersession preparation for a validated uncommitted Knowledge capture.

  Preparation is consistency checking, not source, policy, operator or publication
  authority. The caller must hold the exact Session-owned purpose and source lease,
  select the reviewed recipe and policy, journal intent before effects, and perform
  the separate native relation review. Worker request data cannot choose the old
  target, mode or create an initial publication.
  """
  alias Ipse.{JSON, Usage}

  alias Ipse.Extension.{
    Collection,
    Consent,
    ManagedCollectionCall,
    Mode,
    ProjectIdentity,
    SemanticAdmission,
    SemanticConsent
  }

  alias Ipse.Extension.Collection.{NormalizerV3, ObservedRead}
  alias Ipse.Runner.Review
  alias Ipse.Session.{ManagedLifecycle, Resources, StoredSources}
  @error {:error, :managed_supersession_refused}
  @layout "managed_supersession_v1"
  @prepared ~w(type version id session_id assertion_id mode target_key pin_sha256 descriptor_sha256)
  @common ~w(type version purpose_sha256 candidate_operation_id operation_id)

  def layout, do: @layout

  def marker(metadata) when is_map(metadata) do
    case Map.fetch(metadata, "managed_supersession_layout") do
      :error -> {:ok, nil}
      {:ok, @layout} -> {:ok, @layout}
      _ -> @error
    end
  end

  def marker(_), do: @error

  def prepared?(event, session_id) do
    keys?(event, @prepared) and event["type"] == "managed_supersession_prepared" and
      event["version"] === 1 and event["session_id"] === session_id and
      Enum.all?(~w(id session_id assertion_id), &id?(event[&1])) and
      event["mode"] in ~w(ordinary temporal) and note_key?(event["target_key"]) and
      Enum.all?(~w(pin_sha256 descriptor_sha256), &JSON.sha256?(event[&1]))
  rescue
    _ -> false
  end

  @doc "Validate one owner record against the immutable prepared event and candidate action."
  def record?(event, prepared, candidate, prior) when is_list(prior) do
    sha = JSON.digest([prepared, candidate])
    capture = candidate["request"]

    with true <- prepared?(prepared, prepared["session_id"]),
         true <- candidate["type"] == "extension_action_intent" and id?(candidate["operation_id"]),
         :ok <- ManagedCollectionCall.validate(capture),
         true <- capture["metadata_version"] === 3,
         true <-
           get_in(candidate, ["effect_binding", "outer_sha256"]) == prepared["descriptor_sha256"],
         true <-
           JSON.digest([get_in(candidate, ["effect_binding", "pin"])]) == prepared["pin_sha256"],
         true <- event["version"] === 1 and event["purpose_sha256"] == sha,
         true <-
           event["candidate_operation_id"] == candidate["operation_id"] and
             id?(event["operation_id"]) do
      case {event["type"], prior} do
        {"managed_supersession_intent", []} ->
          keys?(event, @common ++ ~w(candidate_request_sha256 facts)) and
            event["candidate_request_sha256"] == JSON.digest([capture]) and
            intent_facts?(event, prepared, candidate)

        {"managed_supersession_review", [intent]} ->
          keys?(event, @common ++ ~w(review)) and same_operation?(event, intent) and
            review?(event["review"], intent["facts"])

        {"managed_supersession_result", [intent]} ->
          keys?(event, @common ++ ~w(status outcome)) and same_operation?(event, intent) and
            event["status"] in ~w(refused unconfirmed) and is_nil(event["outcome"])

        {"managed_supersession_result", [intent, review]} ->
          keys?(event, @common ++ ~w(status outcome)) and same_operation?(event, intent) and
            result_with_review?(event, intent, review, candidate)

        {"managed_supersession_delivered", [_ | _] = records} ->
          delivered?(event, prepared, candidate, records)

        _ ->
          false
      end
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  def record?(_, _, _, _), do: false

  @doc "Validate historical ordering and bindings without restoring any active authority or replaying effects."
  def validate_events(events, session_id) when is_list(events) do
    metadata = (List.first(events) || %{})["metadata"] || %{}

    types =
      ~w(managed_supersession_prepared managed_supersession_intent managed_supersession_review managed_supersession_result managed_supersession_delivered)

    with {:ok, marker} <- marker(metadata),
         true <- marker == @layout or not Enum.any?(events, &(&1["type"] in types)),
         {:ok, _} <-
           if(marker == nil,
             do: {:ok, %{}},
             else:
               Enum.reduce_while(
                 events,
                 {:ok,
                  %{
                    assertions: %{},
                    purposes: %{},
                    candidates: %{},
                    records: %{},
                    action_results: %{}
                  }},
                 fn event, {:ok, state} ->
                   case advance(event, state, metadata, session_id) do
                     {:ok, next} -> {:cont, {:ok, next}}
                     _ -> {:halt, @error}
                   end
                 end
               )
           ) do
      :ok
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  def validate_events(_, _), do: @error

  @doc false
  def execute(context, intent, %{
        purpose: prepared,
        prepared: prepared,
        source_binding: {:supersession, sha},
        proof: proof,
        source: source
      }) do
    empty = delivery(sha, "unconfirmed", nil)
    slot = {__MODULE__, make_ref()}
    Process.put(slot, %{stage: :before, intent: nil, review: nil})

    try do
      result =
        try do
          with {:ok, preview} <- preflight(context, intent, prepared, sha, proof, source),
               candidate = preview.candidate,
               facts = candidate["prepared"]["facts"],
               event = intent_event(intent, sha, candidate),
               :ok <- append(context, sha, event) do
            Process.put(slot, %{stage: :intent, intent: event, review: nil})
            command = if prepared["mode"] == "ordinary", do: "correct", else: "supersede"

            display_guard = fn continuation ->
              guard_display(context, intent, prepared, sha, preview, continuation)
            end

            Review.with_review(
              command,
              facts,
              fn permit ->
                with_sources(context, sha, preview.sources, fn ->
                  publish(context, intent, sha, preview, permit, command, slot)
                end)
              end,
              display_guard
            )
          else
            _ -> @error
          end
        rescue
          _ -> @error
        catch
          _, _ -> @error
        end

      state = Process.get(slot)
      {status, value} = finish(context, intent, result, state)

      case state.intent do
        nil ->
          {:supersession, empty}

        recorded ->
          if append(context, sha, result_event(recorded, status, value)) == :ok,
            do: {:supersession, delivery(sha, status, value)},
            else: {:supersession, empty}
      end
    after
      Process.delete(slot)
    end
  end

  def execute(_, _, _), do: {:supersession, delivery(nil, "unconfirmed", nil)}

  defp preflight(context, intent, prepared, sha, proof, source) do
    pin = get_in(intent, ["effect_binding", "pin"])
    admission = context.config[:semantic_admission]

    recipe =
      get_in(admission, ["policy", "settings", "recipes", intent["request"]["recipe_sha256"]])

    with true <- Resources.active?() and prepared?(prepared, context.session_id),
         true <- sha == JSON.digest([prepared, intent]),
         [%{"quote" => quote}] <- intent["request"]["proofs"],
         true <- quote === source["quote"] and quote === proof["quote"],
         true <-
           pin["session_id"] == context.session_id and
             JSON.digest([pin]) == prepared["pin_sha256"],
         true <-
           get_in(intent, ["effect_binding", "outer_sha256"]) == prepared["descriptor_sha256"],
         {:ok, mode} <- Mode.capture(context.config),
         true <- mode["headless"] === false and mode["approval_origin"] == "interactive",
         true <- Mode.ordinary(mode, true) in [:ask, :allow],
         :ok <- Mode.knowledge(mode, "collection.publish"),
         {:ok, :native} <- Ipse.Runner.operator_channel(),
         true <- Ipse.Extension.ManagedRecipe.valid?(recipe),
         {:ok, old} <- observe_old(context, prepared, pin, recipe),
         old_proofs when is_list(old_proofs) <-
           get_in(old, ["observation", "value", "record", "value"] ++ recipe["evidence_path"]),
         true <- length(old_proofs) == 1,
         sources = Enum.uniq(old_proofs ++ [proof]),
         {:ok, preview} <-
           with_sources(context, sha, sources, fn ->
             with {:ok, ^old} <- observe_old(context, prepared, pin, recipe),
                  {:ok, current, proofs} <-
                    ManagedCollectionCall.supersession_sources(context, intent),
                  true <- Enum.map(proofs, & &1["proof"]) === [proof],
                  {:ok, snapshot} <- policy_snapshot(context, pin),
                  :ok <-
                    SemanticConsent.check_sources(snapshot["policy"], source_categories(sources)),
                  {:ok, plan} <-
                    ManagedCollectionCall.supersession_plan(
                      context,
                      intent,
                      current,
                      proofs,
                      Usage.id(),
                      intent["request_sha256"]
                    ),
                  true <- plan.recipe === recipe,
                  lifecycle = lifecycle_context(context, pin, snapshot, recipe),
                  {:ok, candidate} <-
                    prepare_candidate(
                      lifecycle,
                      old,
                      intent["request"],
                      prepared["mode"],
                      plan.constraints,
                      [proof],
                      pin["policy_sha256"],
                      System.system_time(:millisecond)
                    ),
                  facts = candidate["prepared"]["facts"],
                  {:ok, plan} <-
                    ManagedCollectionCall.supersession_plan(
                      context,
                      intent,
                      current,
                      proofs,
                      facts["operation_id"],
                      facts["action_sha256"]
                    ) do
               {:ok,
                %{
                  candidate: candidate,
                  old: old,
                  pin: pin,
                  recipe: recipe,
                  snapshot: snapshot,
                  plan: plan,
                  current: current,
                  proofs: proofs,
                  sources: sources
                }}
             else
               _ -> @error
             end
           end) do
      {:ok, preview}
    else
      _ -> @error
    end
  end

  defp with_sources(context, sha, sources, fun) do
    StoredSources.with_verified(
      Map.put(context, :source_binding, {:supersession, sha}),
      nil,
      sources,
      fn verified ->
        if Enum.map(verified, & &1["proof"]) === sources, do: fun.(), else: @error
      end
    )
  end

  defp observe_old(context, prepared, pin, recipe) do
    ProjectIdentity.with_existing_domain_auth(
      context.config[:home],
      context.cwd,
      context.config[:semantic_admission]["binding"],
      %{namespace: pin["namespace"], format: "managed-metadata-v3"},
      fn cap, catalog ->
        ObservedRead.managed_record(
          SemanticAdmission.collection_root(context.config[:home]),
          pin["namespace"],
          %{"op" => "get_record", "key" => prepared["target_key"]},
          cap,
          catalog,
          recipe
        )
      end
    )
  end

  defp policy_snapshot(context, pin) do
    Consent.with_policy(
      SemanticAdmission.control_root(context.config[:home]),
      pin["project_id"],
      pin["epoch"],
      pin["policy_sha256"],
      System.system_time(:millisecond),
      fn snapshot -> {:ok, snapshot} end
    )
  end

  defp lifecycle_context(context, pin, snapshot, recipe),
    do: %{
      "session_id" => context.session_id,
      "job_id" => Usage.id(),
      "client_id" => Usage.id(),
      "project_id" => pin["project_id"],
      "namespace" => pin["namespace"],
      "binding_sha256" => pin["binding_sha256"],
      "management_epoch" => pin["epoch"],
      "management_sha256" =>
        Consent.management_sha256(pin["project_id"], pin["epoch"], snapshot["policy"]),
      "original_pin" => pin,
      "recipe" => recipe
    }

  defp source_categories(sources),
    do: Enum.map(sources, &%{"category" => &1["origin"], "path" => &1["path"]})

  defp guard_display(context, intent, prepared, sha, preview, continuation) do
    result =
      with_sources(context, sha, preview.sources, fn ->
        ProjectIdentity.with_existing_domain_auth(
          context.config[:home],
          context.cwd,
          context.config[:semantic_admission]["binding"],
          %{namespace: preview.pin["namespace"], format: "managed-metadata-v3"},
          fn cap, catalog ->
            Consent.with_policy(
              SemanticAdmission.control_root(context.config[:home]),
              preview.pin["project_id"],
              preview.pin["epoch"],
              preview.pin["policy_sha256"],
              System.system_time(:millisecond),
              fn snapshot ->
                with true <- snapshot === preview.snapshot,
                     :ok <-
                       SemanticConsent.check_sources(
                         snapshot["policy"],
                         source_categories(preview.sources)
                       ),
                     {:ok, current, proofs} <-
                       ManagedCollectionCall.supersession_sources(context, intent),
                     true <- current === preview.current and proofs === preview.proofs,
                     {:ok, old} <-
                       ObservedRead.managed_record(
                         SemanticAdmission.collection_root(context.config[:home]),
                         preview.pin["namespace"],
                         %{"op" => "get_record", "key" => prepared["target_key"]},
                         cap,
                         catalog,
                         preview.recipe
                       ),
                     true <- old === preview.old,
                     deadline =
                       [snapshot["policy"]["expires_at_ms"], old["metadata"]["valid_until_ms"]]
                       |> Enum.reject(&is_nil/1)
                       |> Enum.min(),
                     true <- deadline > System.system_time(:millisecond),
                     :ok <- continuation.(deadline) do
                  {:ok, :displayed}
                else
                  _ -> @error
                end
              end
            )
          end
        )
      end)

    if result == {:ok, :displayed}, do: :ok, else: @error
  end

  defp publish(context, intent, sha, preview, permit, command, slot) do
    pin = preview.pin
    control = SemanticAdmission.control_root(context.config[:home])
    facts = preview.candidate["prepared"]["facts"]

    ProjectIdentity.with_domain_publication(
      context.config[:home],
      context.cwd,
      context.config[:semantic_admission]["binding"],
      %{
        namespace: pin["namespace"],
        format: "managed-metadata-v3",
        operation_id: facts["operation_id"],
        initialize: false
      },
      fn binding ->
        with true <- binding === context.config[:semantic_admission]["binding"],
             {:ok, current, proofs} <- ManagedCollectionCall.supersession_sources(context, intent),
             true <- current === preview.current and proofs === preview.proofs,
             :ok <- Review.check(permit, command, facts),
             do: :ok,
             else: (_ -> @error)
      end,
      fn cap, catalog ->
        with {:ok, ticket} <-
               Consent.reserve(
                 control,
                 pin["project_id"],
                 preview.plan.reservation,
                 System.system_time(:millisecond)
               ),
             false <- Map.has_key?(ticket, "existing") do
          Process.put(slot, %{Process.get(slot) | stage: :reserved})

          with {:ok, ^ticket} <-
                 Consent.admit(
                   control,
                   pin["project_id"],
                   ticket,
                   System.system_time(:millisecond)
                 ) do
            Process.put(slot, %{Process.get(slot) | stage: :publishing})

            Consent.publish_deferred(
              control,
              pin["project_id"],
              ticket,
              System.system_time(:millisecond),
              fn ->
                with {:ok, current, proofs} <-
                       ManagedCollectionCall.supersession_sources(context, intent),
                     true <- current === preview.current and proofs === preview.proofs do
                  publish_core(context, intent, sha, preview, permit, command, slot, cap, catalog)
                else
                  _ -> @error
                end
              end
            )
          else
            _ -> @error
          end
        else
          _ -> @error
        end
      end
    )
  end

  defp publish_core(context, intent, sha, preview, permit, command, slot, cap, catalog) do
    prepared = preview.candidate["prepared"]
    facts = prepared["facts"]
    envelope = %{"metadata_version" => 3, "request" => prepared["request"], "facts" => facts}
    accounting = {__MODULE__, make_ref()}
    owner = self()

    try do
      result =
        Collection.execute_managed_supersession(
          SemanticAdmission.collection_root(context.config[:home]),
          preview.pin["namespace"],
          prepared["request"],
          facts["operation_id"],
          JSON.digest([preview.recipe]),
          fn witness, read ->
            with true <- self() == owner and Process.get(accounting) == nil,
                 _ <- Process.put(accounting, :claimed),
                 {:ok, normalized, normalization} = result <-
                   NormalizerV3.supersede(witness, read, %{
                     request: prepared["request"],
                     facts: facts,
                     permit: permit,
                     constraints: preview.plan.constraints,
                     verified_sources: Enum.map(preview.proofs, & &1["proof"]),
                     policy_sha256: preview.pin["policy_sha256"],
                     now_ms: System.system_time(:millisecond),
                     capture_expires_at_ms: preview.snapshot["policy"]["expires_at_ms"],
                     domain_cap: cap,
                     catalog: catalog
                   }),
                 {:ok, actual} <-
                   ManagedCollectionCall.measured_accounting(
                     envelope,
                     normalized,
                     normalization,
                     preview.plan.reservation["reserved"]
                   ) do
              Process.put(accounting, {JSON.digest([normalized]), normalization, actual})
              result
            else
              _ -> {:error, :collection_accounting_invalid}
            end
          end
        )

      case Review.consumed_receipt(permit, command, facts) do
        {:ok, review} ->
          event = %{
            "type" => "managed_supersession_review",
            "version" => 1,
            "purpose_sha256" => sha,
            "candidate_operation_id" => intent["operation_id"],
            "operation_id" => facts["operation_id"],
            "review" => review
          }

          if append(context, sha, event) == :ok do
            Process.put(slot, %{Process.get(slot) | review: event})

            with {:ok, core} <- result,
                 {digest, normalization, actual} <- Process.get(accounting),
                 true <-
                   digest == core["receipt"]["request_sha256"] and
                     normalization === core["normalization"],
                 {:ok, value} <- outcome(preview.candidate, core, review) do
              {:ok, actual, %{"status" => "ok", "value" => value}}
            else
              _ -> @error
            end
          else
            @error
          end

        _ ->
          @error
      end
    after
      Process.delete(accounting)
    end
  end

  defp finish(
         context,
         intent,
         {:ok,
          %{
            "ticket" => ticket,
            "actual" => actual,
            "receipt" => %{"status" => "ok", "value" => value} = receipt
          }},
         %{stage: :publishing, review: review}
       )
       when is_map(review) do
    pin = intent["effect_binding"]["pin"]

    case Consent.settle(
           SemanticAdmission.control_root(context.config[:home]),
           pin["project_id"],
           ticket,
           {:known, actual, receipt}
         ) do
      {:ok, %{"status" => "settled", "receipt" => ^receipt}} -> {"settled", value}
      _ -> {"unconfirmed", nil}
    end
  end

  defp finish(_, _, _, %{stage: :intent, review: nil}), do: {"refused", nil}
  defp finish(_, _, _, _), do: {"unconfirmed", nil}

  defp intent_event(intent, sha, candidate),
    do: %{
      "type" => "managed_supersession_intent",
      "version" => 1,
      "purpose_sha256" => sha,
      "candidate_operation_id" => intent["operation_id"],
      "candidate_request_sha256" => candidate["capture_request_sha256"],
      "operation_id" => candidate["prepared"]["facts"]["operation_id"],
      "facts" => candidate["prepared"]["facts"]
    }

  defp result_event(intent, status, value),
    do: %{
      "type" => "managed_supersession_result",
      "version" => 1,
      "purpose_sha256" => intent["purpose_sha256"],
      "candidate_operation_id" => intent["candidate_operation_id"],
      "operation_id" => intent["operation_id"],
      "status" => status,
      "outcome" => value
    }

  defp delivery(sha, status, value),
    do: %{
      "version" => 1,
      "kind" => "managed_supersession_delivery",
      "purpose_sha256" => sha,
      "status" => status,
      "outcome" => value
    }

  defp append(context, sha, event),
    do: GenServer.call(context.owner, {:supersession_record, context.job_ref, sha, event}, 5_000)

  @doc false

  defp advance(%{"type" => "operator_assertion"} = event, state, _, session_id) do
    if Ipse.Session.OperatorAssertion.valid_event?(event, session_id),
      do: {:ok, put_in(state, [:assertions, event["id"]], event)},
      else: @error
  end

  defp advance(%{"type" => "managed_supersession_prepared"} = event, state, metadata, session_id) do
    assertion = state.assertions[event["assertion_id"]]
    pin = get_in(metadata, ["semantic_admission", "pin"])
    expected_category = if event["mode"] == "ordinary", do: "ordinary", else: "current"

    if prepared?(event, session_id) and is_map(assertion) and
         assertion["category"] == expected_category and
         event["pin_sha256"] == JSON.digest([pin]) and
         not Map.has_key?(state.purposes, event["id"]) and
         Enum.all?(state.purposes, fn {_, p} ->
           p.prepared["assertion_id"] != event["assertion_id"]
         end) do
      {:ok,
       put_in(state, [:purposes, event["id"]], %{
         prepared: event,
         assertion: assertion,
         parent: nil,
         open: true,
         candidate: nil
       })}
    else
      @error
    end
  end

  defp advance(%{"type" => "extension_invocation_intent"} = event, state, metadata, _) do
    pending = Enum.filter(state.purposes, fn {_, p} -> p.open and is_nil(p.parent) end)

    case pending do
      [] ->
        {:ok, state}

      [{id, purpose}] ->
        if parent_assertion?(event, purpose, metadata) do
          {:ok, put_in(state, [:purposes, id, :parent], event["invocation_id"])}
        else
          {:ok, put_in(state, [:purposes, id, :open], false)}
        end

      _ ->
        @error
    end
  end

  defp advance(%{"type" => "extension_action_intent"} = event, state, metadata, _) do
    matches =
      Enum.filter(state.purposes, fn {_, purpose} ->
        purpose.open and is_nil(purpose.candidate) and
          capture_assertion?(event, purpose, metadata)
      end)

    case matches do
      [] ->
        {:ok, state}

      [{id, _}] ->
        next = put_in(state, [:purposes, id, :candidate], event)
        {:ok, put_in(next, [:candidates, event["operation_id"]], id)}

      _ ->
        @error
    end
  end

  defp advance(%{"type" => "extension_action_result"} = event, state, _, _) do
    case state.candidates[event["operation_id"]] do
      nil ->
        {:ok, state}

      id ->
        purpose = state.purposes[id]
        candidate = purpose.candidate
        records = Map.get(state.records, id, [])
        completed = records != [] and List.last(records)["type"] == "managed_supersession_result"

        if purpose.open and not Map.has_key?(state.action_results, id) and
             Ipse.Extension.Actions.result_intent(event) == candidate and
             event["outcome"] == %{
               "status" => "failed",
               "value" => %{"code" => "collection_policy_refused"}
             } do
          next = put_in(state, [:action_results, id], event)
          {:ok, if(completed, do: next, else: put_in(next, [:purposes, id, :open], false))}
        else
          @error
        end
    end
  end

  defp advance(%{"type" => type} = event, state, _, _)
       when type in ~w(managed_supersession_intent managed_supersession_review managed_supersession_result) do
    case state.candidates[event["candidate_operation_id"]] do
      nil ->
        @error

      id ->
        purpose = state.purposes[id]
        prior = Map.get(state.records, id, [])

        if purpose.open and record?(event, purpose.prepared, purpose.candidate, prior),
          do: {:ok, put_in(state, [:records, id], prior ++ [event])},
          else: @error
    end
  end

  defp advance(%{"type" => "managed_supersession_delivered"} = event, state, _, _) do
    case state.candidates[event["candidate_operation_id"]] do
      nil ->
        @error

      id ->
        purpose = state.purposes[id]
        records = Map.get(state.records, id, [])
        action = state.action_results[id]

        if purpose.open and is_map(action) and
             record?(event, purpose.prepared, purpose.candidate, records ++ [action]),
           do: {:ok, put_in(state, [:records, id], records ++ [event])},
           else: @error
    end
  end

  defp advance(%{"type" => type}, state, _, _)
       when type in ~w(cancelled turn_finished input_received) do
    purposes = Map.new(state.purposes, fn {id, purpose} -> {id, %{purpose | open: false}} end)
    {:ok, %{state | purposes: purposes}}
  end

  defp advance(_, state, _, _), do: {:ok, state}

  defp capture_assertion?(candidate, purpose, metadata) do
    capture = candidate["request"]

    recipe =
      get_in(metadata, [
        "semantic_admission",
        "policy",
        "settings",
        "recipes",
        capture["recipe_sha256"]
      ])

    [change] = capture["request"]["changes"]
    [proof] = get_in(change["value"], recipe["evidence_path"])
    assertion = purpose.assertion

    ManagedCollectionCall.validate(capture) == :ok and capture["metadata_version"] === 3 and
      is_binary(purpose.parent) and candidate["parent_invocation_id"] == purpose.parent and
      get_in(candidate, ["effect_binding", "outer_sha256"]) ==
        purpose.prepared["descriptor_sha256"] and
      JSON.digest([get_in(candidate, ["effect_binding", "pin"])]) ==
        purpose.prepared["pin_sha256"] and
      proof["session_id"] == assertion["session_id"] and
      proof["origin"] == "native_operator_assertion" and
      proof["kind"] == Ipse.Session.OperatorAssertion.kind(assertion["category"]) and
      proof["quote"] == assertion["text"] and proof["receipt_sha256"] == JSON.digest([assertion])
  rescue
    _ -> false
  end

  defp parent_assertion?(event, purpose, metadata) do
    assertion = purpose.assertion
    payload = event["payload"]
    args = payload["arguments"]

    Ipse.Extension.Invocation.validate_intent(event, metadata) == :ok and
      event["descriptor"]["stage"] == "invoke.command" and
      JSON.digest([event["descriptor"]]) == purpose.prepared["descriptor_sha256"] and
      payload["session_id"] == assertion["session_id"] and
      args["text"] == assertion["text"] and args["category"] == assertion["category"] and
      get_in(args, ["source", "quote"]) == assertion["text"]
  rescue
    _ -> false
  end

  @doc "Bind one uncommitted v3 capture candidate to the observed target and exact host-selected mode."
  def prepare_candidate(
        context,
        managed,
        capture,
        mode,
        constraints,
        verified_sources,
        policy_sha256,
        now
      ) do
    with :ok <- ManagedCollectionCall.validate(capture),
         true <- capture["metadata_version"] === 3,
         true <- ManagedLifecycle.context?(context),
         true <- capture["recipe_sha256"] == JSON.digest([context["recipe"]]),
         true <- mode in ~w(ordinary temporal),
         request = capture["request"],
         true <-
           request["expected_generation"] ===
             get_in(managed, ["observation", "witness", "root", "generation"]),
         [%{"key" => key, "expected_revision" => 0, "value" => value}] <- request["changes"],
         {:ok, prepared} <-
           ManagedLifecycle.prepare_supersession(
             context,
             managed,
             %{"key" => key, "value" => value},
             %{
               mode: mode,
               constraints: constraints,
               verified_sources: verified_sources,
               policy_sha256: policy_sha256,
               now_ms: now
             },
             "Operator reviewed the exact source and successor relation"
           ) do
      {:ok,
       %{
         "version" => 1,
         "kind" => "managed_supersession_candidate",
         "capture_request_sha256" => JSON.digest([capture]),
         "prepared" => prepared
       }}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  @doc "Build a distinct host outcome from the exact candidate, Core receipt and consumed review."
  def outcome(candidate, core, review) do
    with true <-
           is_map(candidate) and
             Enum.sort(Map.keys(candidate)) == ~w(capture_request_sha256 kind prepared version),
         true <-
           candidate["version"] === 1 and candidate["kind"] == "managed_supersession_candidate",
         true <- JSON.sha256?(candidate["capture_request_sha256"]),
         prepared when is_map(prepared) <- candidate["prepared"],
         facts when is_map(facts) <- prepared["facts"],
         request when is_map(request) <- prepared["request"],
         true <-
           facts["kind"] == "managed_literal_supersession" and
             facts["request_sha256"] == JSON.digest([request]),
         true <- facts["action_sha256"] == JSON.digest([Map.delete(facts, "action_sha256")]),
         true <- is_map(core) and core["version"] === 1,
         binding when is_map(binding) <- core["binding"],
         normalized when is_map(normalized) <- core["normalization"],
         receipt when is_map(receipt) <- core["receipt"],
         true <- Ipse.Extension.Collection.Migration.receipt?(receipt),
         true <- binding["original_request_sha256"] == JSON.digest([request]),
         true <- binding["recipe_sha256"] == JSON.digest([facts["context"]["recipe"]]),
         true <- binding["normalization_sha256"] == JSON.digest([normalized]),
         true <- receipt["managed_binding_sha256"] == JSON.digest([binding]),
         true <- receipt["generation"] === request["expected_generation"] + 1,
         true <- receipt["floor"] === receipt["generation"],
         true <-
           normalized["version"] === 3 and normalized["kind"] == "native_literal_supersession",
         true <- normalized["action_sha256"] == facts["action_sha256"],
         true <- normalized["old_lineage"] == facts["metadata"]["lineage"],
         "note." <> new_lineage <- facts["replacement"]["key"],
         true <- normalized["new_lineage"] == new_lineage,
         true <- is_map(review) and review["version"] === 1 and review["kind"] == "native_review",
         true <-
           review["command"] == if(facts["mode"] == "ordinary", do: "correct", else: "supersede"),
         true <- review["facts_sha256"] == JSON.digest([facts]),
         true <- normalized["native_review_sha256"] == JSON.digest([review]),
         value = %{
           "version" => 1,
           "kind" => "managed_supersession_outcome",
           "capture_request_sha256" => candidate["capture_request_sha256"],
           "action_sha256" => facts["action_sha256"],
           "publication" => core,
           "native_review" => review
         },
         :ok <- JSON.validate_object(value),
         true <- byte_size(Jason.encode!(value)) <= 16_384 do
      {:ok, value}
    else
      _ -> @error
    end
  rescue
    _ -> @error
  end

  defp intent_facts?(event, prepared, candidate) do
    facts = event["facts"]
    capture = candidate["request"]
    context = facts["context"]
    target = facts["target"]
    metadata = facts["metadata"]
    [new] = capture["request"]["changes"]
    source = get_in(new["value"], context["recipe"]["evidence_path"])

    old = %{
      "key" => target["key"],
      "expected_revision" => target["revision"],
      "value" => target["value"]
    }

    request = %{capture["request"] | "changes" => [old, new]}

    keys?(
      facts,
      ~w(version kind operation_id context collection target metadata replacement mode history_rule new_source_sha256 new_policy_sha256 checked_at_ms reason request_sha256 scope action_sha256)
    ) and
      facts["version"] === 1 and facts["kind"] == "managed_literal_supersession" and
      facts["operation_id"] == event["operation_id"] and ManagedLifecycle.context?(context) and
      context["session_id"] == prepared["session_id"] and target["key"] == prepared["target_key"] and
      facts["mode"] == prepared["mode"] and
      metadata["lineage"] == String.replace_prefix(target["key"], "note.", "") and
      capture["recipe_sha256"] == JSON.digest([context["recipe"]]) and
      capture["request"]["expected_generation"] === facts["collection"]["root"]["generation"] and
      new["expected_revision"] === 0 and facts["replacement"] === Map.take(new, ~w(key value)) and
      is_list(source) and length(source) == 1 and
      facts["new_source_sha256"] == JSON.digest([source]) and
      facts["new_policy_sha256"] == get_in(candidate, ["effect_binding", "pin", "policy_sha256"]) and
      facts["history_rule"] ===
        Ipse.Extension.Collection.ManagedRetention.history_rule(metadata, prepared["mode"]) and
      facts["request_sha256"] == JSON.digest([request]) and
      facts["action_sha256"] == JSON.digest([Map.delete(facts, "action_sha256")]) and
      JSON.safe_uint?(facts["checked_at_ms"]) and byte_size(Jason.encode!(facts)) <= 16_384
  rescue
    _ -> false
  end

  defp review?(review, facts) do
    command = if facts["mode"] == "ordinary", do: "correct", else: "supersede"

    keys?(
      review,
      ~w(version kind command event_id display_sha256 challenge input_sha256 observed_at_ms facts_sha256)
    ) and
      review["version"] === 1 and review["kind"] == "native_review" and
      review["command"] == command and
      id?(review["event_id"]) and is_binary(review["challenge"]) and
      Regex.match?(~r/\A[0-9a-f]{16}\z/, review["challenge"]) and
      JSON.sha256?(review["display_sha256"]) and
      review["input_sha256"] == JSON.sha256(command <> " " <> review["challenge"]) and
      review["facts_sha256"] == JSON.digest([facts]) and JSON.safe_uint?(review["observed_at_ms"]) and
      review["observed_at_ms"] >= facts["checked_at_ms"]
  rescue
    _ -> false
  end

  defp result_with_review?(event, intent, review_event, candidate) do
    if event["status"] == "unconfirmed" do
      is_nil(event["outcome"])
    else
      facts = intent["facts"]
      [new] = candidate["request"]["request"]["changes"]
      target = facts["target"]

      old = %{
        "key" => target["key"],
        "expected_revision" => target["revision"],
        "value" => target["value"]
      }

      request = %{candidate["request"]["request"] | "changes" => [old, new]}

      packet = %{
        "version" => 1,
        "kind" => "managed_supersession_candidate",
        "capture_request_sha256" => intent["candidate_request_sha256"],
        "prepared" => %{"facts" => facts, "request" => request}
      }

      result = event["outcome"]

      event["status"] == "settled" and is_map(result) and
        outcome(packet, result["publication"], review_event["review"]) == {:ok, result}
    end
  rescue
    _ -> false
  end

  defp same_operation?(event, intent),
    do:
      event["operation_id"] == intent["operation_id"] and
        event["candidate_operation_id"] == intent["candidate_operation_id"] and
        event["purpose_sha256"] == intent["purpose_sha256"]

  defp delivered?(event, prepared, candidate, records) do
    {action, records} = List.pop_at(records, -1)
    result = List.last(records)
    delivery = event["delivery"]

    keys?(event, @common ++ ~w(parent_invocation_id delivery)) and
      is_map(result) and result["type"] == "managed_supersession_result" and
      same_operation?(event, result) and
      event["parent_invocation_id"] == candidate["parent_invocation_id"] and
      Ipse.Extension.Actions.result_intent(action) == candidate and
      action["outcome"] == %{
        "status" => "failed",
        "value" => %{"code" => "collection_policy_refused"}
      } and
      keys?(delivery, ~w(version kind purpose_sha256 status outcome)) and
      delivery["version"] === 1 and delivery["kind"] == "managed_supersession_delivery" and
      delivery["purpose_sha256"] == JSON.digest([prepared, candidate]) and
      delivery["status"] === result["status"] and delivery["outcome"] === result["outcome"]
  rescue
    _ -> false
  end

  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
  defp id?(value), do: is_binary(value) and Regex.match?(~r/\A[0-9a-f]{32}\z/, value)
  defp note_key?("note." <> lineage), do: JSON.sha256?(lineage)
  defp note_key?(_), do: false
end
