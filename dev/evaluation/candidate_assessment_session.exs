Code.require_file("candidate_assessment.exs", __DIR__)

defmodule Ipse.Development.Evaluation.CandidateAssessmentSession do
  @moduledoc """
  Single-case development owner using the existing shadow Session and ledger.

  No work runs on load. prepare/5 is pure apart from the supplied read-only blob
  loader. run/5 is OFF unless a reviewed entry explicitly sets enabled: true.
  Enabling this test owner grants nothing: normal saved experiment consent,
  native per-operation approval, source/current-use and replay gates still apply.
  It never creates or replaces a policy and never publishes a second candidate.
  """
  import ExUnit.Assertions
  alias Ipse.{JSON, Journal, Session}
  alias Ipse.Extension.{Collection, Consent, ProjectIdentity, SemanticAdmission, SemanticConsent}
  alias Ipse.Extension.{Actions, DecisionCall, Invocation, ResultSource}
  alias Ipse.Session.ManagedOutput
  alias Ipse.Development.Evaluation.CandidateAssessment, as: Assessment
  @route_keys ~w(provider model base_url timeout_ms)a
  @intent_types ~w(input_received extension_invocation_intent extension_action_intent worker_input_intent request_admitted inference_dispatch_intent)

  def main(_), do: {:error, :execution_disabled}
  def route_digest(config), do: JSON.digest([Map.take(config, @route_keys)])

  def prepare(declaration, sha, case_id, load, options) do
    with {:ok, baselines} <- Assessment.verify_inputs(declaration, sha, load),
         {:ok, recipe} <- Assessment.execution(declaration, sha, case_id),
         true <- declaration["spec"]["decision_route"]["availability"] !== "unavailable",
         true <- options?(options),
         true <- options.output === Path.join([options.root, "cases", case_id]),
         true <- route_digest(options.config) === declaration["spec"]["main_route_sha256"],
         true <- options.config[:provider_module] == nil,
         true <- decision_route?(options.config, declaration["spec"]["decision_route"]),
         true <-
           Enum.any?(options.config[:extensions] || [], fn entry ->
             get_in(entry, [:identity, "instance"]) === "knowledge" and
               get_in(entry, [:identity, "artifact_sha256"]) === recipe["artifact_sha256"]
           end),
         {:ok, input_bytes} <- load.(recipe["input_sha256"]),
         {:ok, input} <- JSON.decode_unique(input_bytes),
         {:ok, source_bytes} <- load.(recipe["source_receipt_sha256"]),
         {:ok, source} <- JSON.decode_unique(source_bytes),
         true <- source?(source),
         true <- source["journal_sha256"] === baselines[case_id]["journal_sha256"] do
      {:ok,
       %{
         recipe: recipe,
         baseline: baselines[case_id],
         input: input,
         source: source,
         options: options,
         decision_route: declaration["spec"]["decision_route"]
       }}
    else
      _ -> {:error, :candidate_execution_preflight}
    end
  rescue
    _ -> {:error, :candidate_execution_preflight}
  end

  def run(declaration, sha, case_id, load, options) do
    with {:ok, prepared} <- prepare(declaration, sha, case_id, load, options),
         true <- options.enabled do
      execute(declaration, sha, prepared)
    else
      false -> {:error, :execution_disabled}
      error -> error
    end
  end

  defp execute(declaration, sha, p) do
    # Everything above this point precedes App, Session, native or model work.
    o = p.options
    assert {:error, :enoent} = File.lstat(o.output)

    for name <-
          ~w(managed-approval-input-ready managed-approval-control-checked managed-approval-exit-ready),
        do: assert({:error, :enoent} === File.lstat(Path.join(o.output, name)))

    source_path = Path.join(o.state_dir, p.source["session_id"] <> ".jsonl")
    source_bytes = File.read!(source_path)
    assert JSON.sha256(source_bytes) === p.source["journal_sha256"]
    assert {:ok, original} = Journal.load(o.state_dir, p.source["session_id"])
    assert {:ok, _} = Session.Saved.restore(original, p.source["session_id"])
    assert original_capture?(original, p.baseline, p.recipe["arguments"]["key"])
    File.mkdir_p!(Path.dirname(o.output))
    File.mkdir!(o.output)
    File.chmod!(o.output, 0o700)
    {:ok, _} = Application.ensure_all_started(:ipse)
    assert :sys.get_state(Ipse.Session.Input).entries === %{}
    {:ok, project} = ProjectIdentity.existing(o.config.home, o.cwd)
    control = SemanticAdmission.control_root(o.config.home)
    {:ok, before_policy} = Consent.existing_snapshot(control, project["project_id"])
    assert JSON.digest([before_policy["policy"]]) === declaration["spec"]["policy_sha256"]
    assert before_policy["policy"]["limits"] === declaration["spec"]["shared_limits"]
    {:ok, namespace} = SemanticConsent.namespace(project["project_id"], "knowledge")
    collection = SemanticAdmission.collection_root(o.config.home)

    {:ok, before_collection} =
      Collection.execute(collection, namespace, %{"op" => "snapshot"}, Ipse.Usage.id())

    {:ok, %{"record" => record}} =
      Collection.execute(
        collection,
        namespace,
        %{"op" => "get", "key" => p.recipe["arguments"]["key"]},
        Ipse.Usage.id()
      )

    assert matched_record?(p, record)
    # This probe confirms the original is closed; actual reads reacquire it in
    # the normal managed owners. It does not transfer a proof or grant a read.
    {:ok, original_lock} = Ipse.Runner.protected_lock(Path.rootname(source_path) <> ".lock")
    assert :ok = Ipse.Runner.unlock(original_lock)

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: o.config, cwd: o.cwd, state_dir: o.state_dir, owner: self(), subscriber: self()}
      )

    id = Session.info(pid).id
    started = System.monotonic_time(:millisecond)
    watcher = approval_watcher(pid, o.output)

    try do
      IO.puts("IPSE_MANAGED_APPROVAL_CLI_READY")

      terminal =
        Ipse.CLI.Terminal.interact(
          pid,
          Process.monitor(pid),
          true,
          "Use ext__knowledge__assess once for the saved candidate " <>
            record["key"] <> ". Do not capture, accept, edit, or publish any note.",
          o.cwd
        )

      elapsed = System.monotonic_time(:millisecond) - started

      save(o.output, "terminal.json", %{
        "declaration_sha256" => sha,
        "case_id" => p.recipe["case_id"],
        "session_id" => id,
        "terminal_status" => terminal,
        "elapsed_ms" => elapsed
      })

      assert :ok = Session.close_confirmed(pid)
      {:ok, events} = Journal.load(o.state_dir, id)
      # Preserve observed completion and full private history before assertions.
      save(o.output, "observed.json", %{
        "declaration_sha256" => sha,
        "case_id" => p.recipe["case_id"],
        "session_id" => id,
        "terminal_status" => terminal,
        "elapsed_ms" => elapsed,
        "journal_sha256" => JSON.sha256(File.read!(Path.join(o.state_dir, id <> ".jsonl")))
      })

      assert {:ok, _} = Session.Saved.restore(events, id)
      refute Enum.any?(events, &(get_in(&1, ["request", "op"]) === "collection.managed"))

      {:ok, after_collection} =
        Collection.execute(collection, namespace, %{"op" => "snapshot"}, Ipse.Usage.id())

      assert after_collection === before_collection
      assert File.read!(source_path) === source_bytes
      {:ok, after_policy} = Consent.existing_snapshot(control, project["project_id"])

      assert after_policy["epoch"] === before_policy["epoch"] and
               after_policy["policy"] === before_policy["policy"]

      row = result_row(p, events, before_policy, after_policy, elapsed)
      save(o.output, "row.json", row)
      assert terminal === 0
      idle(o, id, events)
      {:ok, final_policy} = Consent.existing_snapshot(control, project["project_id"])
      assert final_policy === after_policy
      assert File.read!(source_path) === source_bytes
      assert :sys.get_state(Ipse.Session.Input).entries === %{}

      save(o.output, "complete.json", %{
        "declaration_sha256" => sha,
        "case_id" => p.recipe["case_id"],
        "row_sha256" => JSON.digest([row]),
        "original_journal_sha256" => p.source["journal_sha256"],
        "consumer_journal_sha256" =>
          JSON.sha256(File.read!(Path.join(o.state_dir, id <> ".jsonl"))),
        "ledger_snapshot_sha256" => JSON.digest([final_policy]),
        "collection_unchanged" => true,
        "strict_saved_idle_no_replay" => true,
        "qualification" => false
      })

      {:ok, row}
    after
      if Process.alive?(pid), do: Session.close_confirmed(pid)
      if Process.alive?(watcher), do: Process.exit(watcher, :kill)
    end
  end

  # Same native approval readiness/exit handshake as shadow_pending_candidate_cli.
  # These sidecars coordinate its existing PTY; they grant no approval.
  defp approval_watcher(pid, root) do
    spawn(fn ->
      deadline = System.monotonic_time(:millisecond) + 120_000
      wait(fn -> File.regular?(Path.join(root, "managed-approval-input-ready")) end, deadline)

      wait(
        fn ->
          approval_control_ready?(
            pid,
            System.monotonic_time(:millisecond),
            deadline
          )
        end,
        deadline
      )

      File.write!(Path.join(root, "managed-approval-control-checked"), "checked", [:exclusive])

      wait(
        fn ->
          phase_observed?(Session.info(pid), :idle, System.monotonic_time(:millisecond), deadline)
        end,
        deadline
      )

      File.write!(Path.join(root, "managed-approval-exit-ready"), "ready", [:exclusive])
    end)
  end

  @doc false
  def approval_control_ready?(pid, now, deadline) do
    assert now < deadline

    case :sys.get_state(pid) do
      %{
        phase: :managed_approval,
        share_barrier: %{phase: :review_input},
        managed_approval: %{id: id}
      } ->
        assert {:error, :session_share_frozen} = Session.approve(pid, id, true)
        true

      _ ->
        false
    end
  end

  @doc false
  def phase_observed?(response, expected, now, deadline) do
    assert now < deadline
    phase_observed?(response, expected)
  end

  @doc false
  def phase_observed?({:error, :session_share_frozen}, _), do: false
  def phase_observed?(%{phase: phase}, expected) when is_atom(phase), do: phase === expected

  def phase_observed?(_, _),
    do: flunk("Session status unavailable during assessment coordination")

  defp wait(check, deadline) do
    assert System.monotonic_time(:millisecond) < deadline
    observed = check.()
    assert System.monotonic_time(:millisecond) < deadline

    if observed do
      :ok
    else
      assert System.monotonic_time(:millisecond) < deadline
      Process.sleep(10)
      wait(check, deadline)
    end
  end

  def result_row(p, events, before_policy, after_policy, _observed_phase_elapsed) do
    actions =
      Enum.filter(
        events,
        &(&1["type"] === "extension_action_result" and
            get_in(&1, ["request", "op"]) === "decision.create")
      )

    added = Map.keys(after_policy["operations"]) -- Map.keys(before_policy["operations"])
    assert length(actions) <= 1 and length(added) <= 1

    for {id, old} <- before_policy["operations"],
        do: assert(after_policy["operations"][id] === old)

    row = Map.take(p.recipe, ~w(case_id input_sha256 baseline_sha256 source_receipt_sha256))

    base =
      Map.merge(row, %{
        "status" => "unknown",
        "choice" => nil,
        # This owner measures the added advice phase, not the matched whole task.
        "elapsed_ms" => nil,
        "cost_nanos" => nil,
        "response_sha256" => nil
      })

    case actions do
      [action] ->
        assert action["operation_id"] in added or added === []
        input = Jason.decode!(action["request"]["input"])
        assert [%{"id" => "candidate", "input" => frozen}] = input["candidates"]
        assert Jason.decode!(frozen) === p.input
        [question] = action["request"]["questions"]
        assert question["choices"] === ~w(defer_candidate keep_baseline)
        assert JSON.sha256(question["instructions"]) === p.decision_route["rubric_sha256"]
        operation = after_policy["operations"][action["operation_id"]]

        results = completed_results(p, events, action["parent_invocation_id"])

        if get_in(action, ["outcome", "status"]) === "ok" and is_map(operation) and
             operation["status"] === "settled" and length(results) === 1 and
             elem(hd(results), 1)["status"] === "assessed" and
             elem(hd(results), 1)["key"] === p.recipe["arguments"]["key"] do
          assert added === [action["operation_id"]]
          [{result, value}] = results
          assert result["identity"]["artifact_sha256"] === p.recipe["artifact_sha256"]
          advice = value["advice"]
          assert advice["choice"] in [nil, "keep_baseline", "defer_candidate"]

          Map.merge(base, %{
            "status" => if(is_nil(advice["choice"]), do: "abstained", else: "ok"),
            "choice" => advice["choice"],
            "response_sha256" => JSON.digest([value])
          })
        else
          outcome = action["outcome"]

          case results do
            [{_result, %{"status" => "interrupted", "outcome" => ^outcome} = value}] ->
              case causal_status(p, events, action) do
                status when status in ~w(denied refused cancelled) ->
                  Map.merge(base, %{"status" => status, "response_sha256" => JSON.digest([value])})

                _ ->
                  base
              end

            _ ->
              base
          end
        end

      [] ->
        case completed_results(p, events, nil) do
          [{_result, %{"status" => "refused"} = value}] when added === [] ->
            Map.merge(base, %{"status" => "refused", "response_sha256" => JSON.digest([value])})

          _ ->
            base
        end
    end
  end

  defp completed_results(p, events, invocation) do
    Enum.flat_map(events, fn result ->
      if result["type"] === "extension_invocation_result" and
           (is_nil(invocation) or result["invocation_id"] === invocation) and
           get_in(result, ["identity", "artifact_sha256"]) === p.recipe["artifact_sha256"] do
        case released_value(events, result, p.recipe["arguments"]["key"]) do
          {:ok, value} -> [{result, value}]
          _ -> []
        end
      else
        []
      end
    end)
  end

  defp causal_status(p, events, action) do
    with [intent] <-
           Enum.filter(
             events,
             &(&1["type"] === "extension_action_intent" and
                 &1["operation_id"] === action["operation_id"])
           ),
         true <- Actions.result_intent(action) === intent,
         [parent] <-
           Enum.filter(
             events,
             &(&1["type"] === "extension_invocation_intent" and
                 &1["invocation_id"] === action["parent_invocation_id"])
           ),
         true <- Actions.valid_intent?(intent, parent, p.options.cwd),
         true <- Actions.valid_result?(action),
         {:ok, ledger} <- Ipse.Usage.restore(events, parent["payload"]["session_id"]),
         record = ledger.requests[action["operation_id"]],
         response =
           Enum.find(
             events,
             &(&1["type"] === "extension_decision_response" and
                 &1["request_id"] === action["operation_id"])
           ),
         true <- DecisionCall.valid_result_source?(action, record, response) do
      case {action["approval"], action["outcome"], record} do
        {"denied", %{"status" => "denied"}, nil} ->
          "denied"

        {_, %{"status" => "failed", "value" => %{"code" => "decision_limit"}}, nil} ->
          "refused"

        {_, %{"status" => "failed", "value" => %{"code" => code}},
         %{completion: %{"outcome" => "cancelled"}}}
        when code in ~w(decision_cancelled decision_timeout) ->
          "cancelled"

        _ ->
          "unknown"
      end
    else
      _ -> "unknown"
    end
  rescue
    _ -> "unknown"
  end

  defp released_value(events, result, expected_key) do
    invocation = result["invocation_id"]

    actions =
      Enum.filter(
        events,
        &(&1["type"] === "extension_action_result" and &1["parent_invocation_id"] === invocation)
      )

    with [parent] <-
           Enum.filter(
             events,
             &(&1["type"] === "extension_invocation_intent" and &1["invocation_id"] === invocation)
           ),
         true <- Invocation.result_intent(result) === parent,
         :ok <- Invocation.validate_intent(parent),
         true <- parent["descriptor"]["id"] === "assess",
         true <- parent["payload"]["arguments"] === %{"key" => expected_key},
         true <- result["action_count"] === length(actions),
         true <- result["actions_sha256"] === JSON.digest(actions),
         [intent] <-
           Enum.filter(
             events,
             &(&1["type"] === "managed_output_release_intent" and
                 &1["parent_invocation_id"] === invocation)
           ),
         true <-
           ManagedOutput.valid_intent?(
             intent,
             parent["payload"]["session_id"],
             parent,
             result["actions_sha256"]
           ),
         [admission] <-
           Enum.filter(
             events,
             &(&1["type"] === "managed_output_release_result" and
                 &1["release_id"] === intent["release_id"])
           ),
         true <- admission["decision"] === "current",
         true <- ManagedOutput.valid_admission?(admission, intent, result, []),
         [cleanup] <-
           Enum.filter(
             events,
             &(&1["type"] === "managed_output_release_cleanup" and
                 &1["release_id"] === intent["release_id"])
           ),
         true <- cleanup["status"] === "confirmed",
         true <- ManagedOutput.valid_cleanup?(cleanup, intent, admission) do
      if result["version"] in [2, 4] do
        with {:ok, index} <- ResultSource.restore(events),
             {:ok, %{value: value}} <- ResultSource.materialize(index, result["delivery"]),
             do: {:ok, value}
      else
        # execute/3 has already strictly reconstructed the complete history.
        # Rebuild the inline document with the public schema validator, retaining
        # the actual recorded action union instead of inventing empty effects.
        with {:ok, checked} <-
               Invocation.build_result(parent, %{
                 "api_version" => 1,
                 "kind" => "result",
                 "value" => result["value"]
               }),
             true <-
               Map.take(checked, ~w(value text text_sha256)) ===
                 Map.take(result, ~w(value text text_sha256)),
             do: {:ok, result["value"]}
      end
    else
      _ -> {:error, :assessment_delivery_unconfirmed}
    end
  rescue
    _ -> {:error, :assessment_delivery_unconfirmed}
  end

  defp original_capture?(events, b, key),
    do:
      Enum.any?(
        events,
        &(&1["type"] === "extension_action_result" and &1["operation_id"] === b["operation_id"] and
            get_in(&1, ["outcome", "status"]) === "ok" and
            get_in(&1, ["request", "op"]) === "collection.managed" and
            Enum.any?(get_in(&1, ["request", "request", "changes"]) || [], fn c ->
              c["key"] === key
            end))
      )

  defp matched_record?(p, record) do
    v = record["value"]
    proofs = get_in(v, ["evidence", "sources"])

    input =
      if p.recipe["stratum"] === "pending",
        do: %{
          "candidate_id" => v["id"],
          "text" => v["text"],
          "assigned_category" => v["assigned_category"],
          "reason" => v["reason"]
        },
        else: v

    record["key"] === p.recipe["arguments"]["key"] and input === p.input and
      is_list(proofs) and length(proofs) === 1 and
      hd(proofs)["session_id"] === p.source["session_id"]
  end

  defp idle(o, id, before) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         config: o.config,
         cwd: o.cwd,
         state_dir: o.state_dir,
         owner: self(),
         subscriber: self(),
         id: id}
      )

    try do
      assert Session.info(pid).phase === :idle
      assert :ok = Session.close_confirmed(pid)
      {:ok, after_events} = Journal.load(o.state_dir, id)
      assert {:ok, _} = Session.Saved.restore(after_events, id)

      assert Enum.filter(after_events, &(&1["type"] in @intent_types)) ===
               Enum.filter(before, &(&1["type"] in @intent_types))
    after
      if Process.alive?(pid), do: Session.close_confirmed(pid)
    end
  end

  defp options?(o) do
    is_map(o) and
      Enum.sort(Map.keys(o)) === Enum.sort(~w(enabled root output cwd state_dir config)a) and
      is_boolean(o.enabled) and is_binary(o.root) and Path.type(o.root) === :absolute and
      Path.expand(o.root) === o.root and
      String.starts_with?(Path.basename(o.root), "ipse-candidate-shadow-") and
      Enum.all?(
        [o.output, o.cwd, o.state_dir, o.config[:home]],
        &(is_binary(&1) and String.starts_with?(Path.expand(&1), Path.expand(o.root) <> "/"))
      ) and
      o.config[:headless] === false and o.config[:approval] === :ask and
      o.config[:accept_edits] !== true
  end

  defp decision_route?(config, route) do
    profile = (config[:decision_profiles] || %{})["advice"]

    engine =
      if is_map(profile),
        do:
          %{
            "openai" => "openai_decisions",
            "system_one" => "typesafe_jev",
            "system_one_compatible" => "compatible_loopback"
          }[profile["provider"]]

    is_map(profile) and profile["operation"] === "decision" and engine === route["engine"] and
      Map.get(profile, "expected_model", profile["model"]) === route["model"]
  end

  defp source?(s),
    do:
      is_map(s) and Enum.sort(Map.keys(s)) === ~w(journal_sha256 session_id version) and
        s["version"] === 1 and is_binary(s["session_id"]) and
        Regex.match?(~r/\A[0-9a-f]{32}\z/, s["session_id"]) and JSON.sha256?(s["journal_sha256"])

  defp save(root, name, value),
    do: File.write!(Path.join(root, name), Jason.encode!(value) <> "\n", [:exclusive])
end
