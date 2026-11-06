defmodule Ipse.Test.PairedProtectedAnswerSession do
  @moduledoc false
  import ExUnit.Assertions
  alias Ipse.{JSON, Journal, Session}
  alias Ipse.Development.Evaluation.{ProtectedAnswer, SelectionExperiment}

  alias Ipse.Extension.{
    Activation,
    Artifact,
    Collection,
    Consent,
    ModelCall,
    ProjectIdentity,
    SemanticAdmission,
    SemanticRoutes
  }

  alias Ipse.Session.ManagedReference
  @phases ~w(setup read baseline selection candidate)
  @query "What does the first synthetic observation record?"
  @expected %{
    "setup" => [],
    "read" => [:main],
    "baseline" => [:helper],
    "selection" => [:main, :decision, :main],
    "candidate" => [:helper]
  }

  # Called only by the future reviewed entry. No source footer invokes it.
  def run(root, phase, helper_artifact, commitments) when phase in @phases do
    assert :sys.get_state(Session.Input).entries === %{}
    home = Path.join(root, "home")
    cwd = Path.join(root, "project")
    dir = Path.join(root, "sessions")
    path = Path.join(home, "config.json")
    for directory <- [home, cwd, dir], do: File.mkdir_p!(directory)
    File.chmod!(home, 0o700)
    System.put_env("IPSE_HOME", home)
    prior = if phase === "setup", do: nil, else: load(root, "setup-checkpoint.json")
    if prior, do: assert(prior["status"] === "known_closed")

    if phase !== "setup" do
      previous =
        %{
          "read" => "setup",
          "baseline" => "read",
          "selection" => "baseline",
          "candidate" => "selection"
        }[phase]

      assert load(root, previous <> "-phase-status.json")["status"] === "passed"
    end

    port = if prior, do: URI.parse(prior["base_url"]).port, else: 0
    {:ok, calls} = Agent.start_link(fn -> [] end)

    {:ok, protocol} =
      Agent.start_link(fn -> %{phase: phase, request: nil, records: nil, arguments: nil} end)

    {base, listener, server} = server(calls, protocol, port)
    if prior, do: assert(base === prior["base_url"])

    c = %{
      root: root,
      home: home,
      cwd: cwd,
      dir: dir,
      path: path,
      base: base,
      phase: phase,
      calls: calls,
      protocol: protocol,
      helper_artifact: helper_artifact,
      commitments: commitments
    }

    started = System.monotonic_time(:millisecond)

    try do
      result =
        case phase do
          "setup" -> setup(c)
          "read" -> read_prefix(runtime(c), prior)
          "baseline" -> baseline(runtime(c), prior)
          "selection" -> selection(runtime(c), prior)
          "candidate" -> candidate(runtime(c), prior)
        end

      wires = Agent.get(calls, & &1)

      save(root, phase <> "-observed.json", %{
        status: "body_completed",
        kinds: Enum.map(wires, & &1.kind),
        wire_count: length(wires),
        elapsed_ms: System.monotonic_time(:millisecond) - started
      })

      assert Enum.map(wires, & &1.kind) === @expected[phase]
      assert :sys.get_state(Session.Input).entries === %{}

      save(root, phase <> "-phase-status.json", %{
        status: "passed",
        elapsed_ms: System.monotonic_time(:millisecond) - started
      })

      result
    rescue
      error ->
        save(root, phase <> "-phase-status.json", %{
          status: "failed",
          exception_class: Atom.to_string(error.__struct__),
          wire_count: length(Agent.get(calls, & &1)),
          elapsed_ms: System.monotonic_time(:millisecond) - started
        })

        reraise(error, __STACKTRACE__)
    after
      :gen_tcp.close(listener)
      Task.shutdown(server, :brutal_kill)
      Agent.stop(calls)
      Agent.stop(protocol)
    end
  end

  defp setup(c) do
    {:ok, artifact} =
      Artifact.import(c.helper_artifact, Path.join(c.home, "extensions/artifacts"))

    configure(c, artifact)
    configured = File.read!(c.path)

    assert Ipse.CLI.run([
             "knowledge",
             "experiment",
             "advice",
             "2",
             "1800",
             "--helper-profile",
             "extract",
             "--cwd",
             c.cwd,
             "--config",
             c.path,
             "--no-project-config"
           ]) === 0

    assert File.read!(c.path) === configured
    c = runtime(c)
    {:ok, granted} = Consent.existing_snapshot(c.control, c.project["project_id"])
    policy = granted["policy"]
    knowledge = Enum.find(c.runtime.extensions, &(&1.identity["instance"] === "knowledge"))
    assert knowledge.identity["artifact_sha256"] === policy["artifact_sha256"]
    assert JSON.digest([knowledge.identity]) === policy["settings"]["identity_sha256"]
    refute "host.model" in knowledge.identity["capabilities"]

    assert Enum.any?(
             c.runtime.extensions,
             &(&1.identity["artifact_sha256"] === artifact.digest and
                 "host.model" in &1.identity["capabilities"])
           )

    labels =
      Map.new(~w(processing_region storage_region cache_retention account_controls), &{&1, nil})

    selectors =
      for {operation, profile} <- [
            {"main", nil},
            {"decision.create", "advice"},
            {"model.complete", "extract"}
          ],
          do: Map.merge(labels, %{"operation" => operation, "profile" => profile})

    {:ok, routes} = SemanticRoutes.resolve(c.runtime, selectors)
    assert routes === policy["settings"]["routes"]
    assert Activation.matches_policy?(policy["settings"]["activation"], policy)
    assert granted["epoch"] === 1 and granted["operations"] === %{}
    assert policy["limits"]["model_calls"] === 2
    issued = policy["settings"]["experiment"]["issued_at_ms"]

    assert policy["expires_at_ms"] ===
             min(issued + 1_800_000, (div(issued, 86_400_000) + 1) * 86_400_000)

    refute Enum.any?(policy["settings"]["effects"], &(&1["class"] === "model.complete"))
    {:ok, source} = start(c)
    source_id = Session.info(source).id
    namespace = :sys.get_state(source).config.semantic_admission["pin"]["namespace"]

    owned(c, source, source_id, "seed", fn ->
      {:ok, channel} = Session.open_input_channel(source, self())

      for n <- 1..8 do
        marker = "~S#{n}~ café 雪 "
        text = marker <> String.duplicate("x", 700 - byte_size(marker))
        command = "/remember ordinary " <> text
        File.write!(Path.join(c.root, "supersession-input-#{n}"), command)
        IO.write("IPSE_SUPERSESSION_READ_#{n}> ")

        assert {:ok, ^command, witness} =
                 Session.observe_channel(source, channel, %{"kind" => "prompt"}, 30_000)

        assert {:ok, ticket} = Session.stage_input(source, channel, command, witness)

        assert {:ok, %{"render_id" => render}} =
                 Session.prepare_assertion(source, channel, command, ticket)

        assert {:ok, input, observed} =
                 Session.observe_channel(
                   source,
                   channel,
                   %{"kind" => "assertion", "render_id" => render},
                   30_000
                 )

        assert :ok = Session.accept_assertion_observed(source, channel, render, input, observed)
        assert_receive {:ipse, ^source, {:done, :ok}}, 30_000
      end
    end)

    {:ok, snapshot} =
      Collection.execute(c.collection, namespace, %{"op" => "snapshot"}, Ipse.Usage.id())

    {:ok, page} =
      Collection.scan_visible(
        c.collection,
        namespace,
        %{"op" => "scan", "after" => nil, "generation" => snapshot["generation"], "limit" => 16},
        Ipse.Usage.id()
      )

    assert page["next"] === nil and length(page["records"]) === 8
    keys = Enum.map(page["records"], & &1["key"]) |> Enum.sort()

    arguments = %{
      "query" => @query,
      "packs" => [
        %{"id" => "first", "members" => Enum.take(keys, 4)},
        %{"id" => "second", "members" => Enum.drop(keys, 4)}
      ]
    }

    {:ok, policy} = Consent.existing_snapshot(c.control, c.project["project_id"])
    assert policy["policy"]["limits"]["model_calls"] === 2

    save(c.root, "setup-checkpoint.json", %{
      "status" => "known_closed",
      "base_url" => c.base,
      "config_sha256" => JSON.sha256(File.read!(c.path)),
      "source_id" => source_id,
      "originals" => fingerprints(c.dir, source_id),
      "namespace" => namespace,
      "keys" => keys,
      "snapshot" => snapshot,
      "policy" => policy,
      "arguments" => arguments,
      "helper_artifact_sha256" => artifact.digest,
      "knowledge_identity" => knowledge.identity,
      "routes" => routes,
      "commitments" => c.commitments
    })
  end

  defp read_prefix(c, p) do
    checkpoint(c, p, 0)
    {:ok, pid} = start(c)
    id = Session.info(pid).id

    owned(c, pid, id, "read", fn ->
      assert :ok =
               Session.prompt(
                 pid,
                 "Read the current synthetic observations; give no tool call or new proposal."
               )

      assert_receive {:ipse, ^pid, {:done, :ok}}, 30_000
    end)

    {:ok, events} = Journal.load(c.dir, id)

    [parent] =
      Enum.filter(
        events,
        &(get_in(&1, ["descriptor", "stage"]) === "event.job" and
            &1["type"] === "extension_invocation_intent")
      )

    actions =
      Enum.filter(
        events,
        &(&1["type"] === "extension_action_result" and
            &1["parent_invocation_id"] === parent["invocation_id"])
      )

    gets = Enum.filter(actions, &(get_in(&1, ["request", "request", "op"]) === "get"))
    assert length(gets) === 8
    [allocation] = Enum.filter(actions, &(get_in(&1, ["request", "op"]) === "context.available"))

    [index, verify] =
      Enum.filter(actions, &(get_in(&1, ["request", "request", "op"]) === "index"))

    [clear, publication] =
      Enum.filter(actions, &(get_in(&1, ["request", "op"]) === "context.publish"))

    assert clear["request"]["items"] === [] and publication["request"]["items"] !== []

    assert Enum.all?(
             [clear, publication],
             &(Ipse.Extension.Actions.valid_result?(&1) and &1["outcome"]["status"] === "ok")
           )

    positions =
      Enum.map([clear, allocation, index] ++ gets ++ [verify, publication], fn event ->
        Enum.find_index(events, &(&1 === event))
      end)

    assert positions === Enum.sort(Enum.uniq(positions))
    {:ok, request} = ProtectedAnswer.publication_request(@query, publication["request"]["items"])
    {:ok, _selected, execution} = ModelCall.prepare(c.runtime, request)
    {:ok, ^execution} = ModelCall.execution(hd(events)["metadata"], request)

    receipt = %{
      "version" => 2,
      "kind" => "protected_note_read_prefix",
      "session_id" => id,
      "events_sha256" => JSON.digest(events),
      "event_count" => length(events),
      "read_operations" => Enum.map(gets, & &1["operation_id"]),
      "answer_artifact_sha256" => p["helper_artifact_sha256"],
      "helper_execution" => execution,
      "recall_invocation_id" => parent["invocation_id"],
      "recall_artifact_sha256" => parent["identity"]["artifact_sha256"],
      "allocation_operation_id" => allocation["operation_id"],
      "index_operation_id" => index["operation_id"],
      "verification_operation_id" => verify["operation_id"],
      "publication_operation_id" => publication["operation_id"]
    }

    bytes = Jason.encode!(receipt)
    {:ok, baseline} = ProtectedAnswer.baseline_request(@query, bytes, events)
    assert length(baseline.eligible_records) === 8 and length(baseline.records) === 6
    assert baseline.request === request
    put_blob(c.root, bytes)
    input = Jason.encode!(p["arguments"])
    put_blob(c.root, input)

    save(c.root, "read-checkpoint.json", %{
      "status" => "known_closed",
      "session_id" => id,
      "source_receipt_sha256" => JSON.sha256(bytes),
      "input_sha256" => JSON.sha256(input),
      "event_count" => length(events),
      "events_sha256" => JSON.digest(events),
      "request_sha256" => JSON.digest([request])
    })

    checkpoint(c, p, 0)
  end

  defp baseline(c, p) do
    checkpoint(c, p, 0)
    references = references(c)
    read = load(c.root, "read-checkpoint.json")
    prefix = prefix(c, read)
    {:ok, source} = blob(c.root, read["source_receipt_sha256"])
    {:ok, prepared} = ProtectedAnswer.baseline_request(@query, source, prefix)
    events = answer(c, read["session_id"], prepared, "baseline")
    parent = last_answer(events)

    case_data =
      Map.take(read, ~w(input_sha256 source_receipt_sha256)) |> Map.put("case_id", "paired")

    {:ok, input} = blob(c.root, read["input_sha256"])

    {:ok, value} =
      ProtectedAnswer.baseline_project(
        case_data,
        input,
        source,
        prefix,
        events,
        read["session_id"],
        parent["invocation_id"]
      )

    assert length(value["members"]) === 6
    bytes = Jason.encode!(value)
    put_blob(c.root, bytes)

    caze =
      Map.take(read, ~w(input_sha256 source_receipt_sha256))
      |> Map.merge(%{"id" => "paired", "baseline_sha256" => JSON.sha256(bytes)})

    route = Enum.find(p["routes"], &(&1["operation"] === "decision.create"))

    spec =
      Map.take(c.commitments, ~w(source_sha256 runtime_sha256 label_commitment))
      |> Map.merge(%{
        "version" => 2,
        "artifact_sha256" => p["knowledge_identity"]["artifact_sha256"],
        "main_route_sha256" =>
          JSON.digest([Enum.find(p["routes"], &(&1["operation"] === "main"))]),
        "policy_sha256" => JSON.digest([p["policy"]["policy"]]),
        "shared_limits" => p["policy"]["policy"]["limits"],
        "engine" => %{
          "id" => "loopback",
          "availability" => "synthetic_protocol_only",
          "route_sha256" => JSON.digest([route])
        },
        "cases" => [caze]
      })

    {:ok, declaration} = SelectionExperiment.declare(spec)

    {:ok, _} =
      SelectionExperiment.verify_references(declaration, JSON.digest([declaration]), fn ->
        {:ok, references}
      end)

    save(c.root, "declaration.json", declaration)

    save(c.root, "baseline-checkpoint.json", %{
      "status" => "known_closed",
      "baseline_sha256" => JSON.sha256(bytes),
      "declaration_sha256" => JSON.digest([declaration]),
      "frozen_before_selection" => true,
      "elapsed_ms" => nil,
      "cost_nanos" => nil,
      "quality" => "unverified"
    })

    checkpoint(c, p, 0)
  end

  defp selection(c, p) do
    checkpoint(c, p, 0)
    baseline = load(c.root, "baseline-checkpoint.json")
    assert baseline["status"] === "known_closed"
    declaration = load(c.root, "declaration.json")
    assert :ok = SelectionExperiment.verify(declaration, baseline["declaration_sha256"])

    {:ok, _} =
      SelectionExperiment.verify_references(declaration, baseline["declaration_sha256"], fn ->
        {:ok, references(c)}
      end)

    read = load(c.root, "read-checkpoint.json")
    {:ok, pid} = start(c, read["session_id"])
    Agent.update(c.protocol, &Map.put(&1, :arguments, p["arguments"]))

    owned(c, pid, read["session_id"], "selection", fn ->
      terminal(
        c,
        pid,
        "selection",
        nil,
        "Use ext__knowledge__select_shadow once with the frozen alternatives. Do not mutate or publish notes."
      )
    end)

    {:ok, events} = Journal.load(c.dir, read["session_id"])

    [parent] =
      Enum.filter(
        events,
        &(&1["type"] === "extension_invocation_intent" and
            get_in(&1, ["descriptor", "id"]) === "select_shadow")
      )

    assert parent["descriptor"]["stage"] === "invoke.tool"

    {:ok, prepared} =
      ProtectedAnswer.prepare(
        declaration,
        baseline["declaration_sha256"],
        "paired",
        &blob(c.root, &1),
        events,
        read["session_id"],
        "first",
        parent["invocation_id"]
      )

    assert length(prepared.records) === 4 and length(prepared.baseline_records) === 6 and
             length(prepared.eligible_records) === 8

    save(c.root, "selection-checkpoint.json", %{
      "status" => "known_closed",
      "invocation_id" => parent["invocation_id"],
      "request_sha256" => JSON.digest([prepared.request]),
      "events_sha256" => JSON.digest(events)
    })

    checkpoint(c, p, 1)
  end

  defp candidate(c, p) do
    checkpoint(c, p, 1)
    read = load(c.root, "read-checkpoint.json")
    selected = load(c.root, "selection-checkpoint.json")
    assert selected["status"] === "known_closed"
    baseline = load(c.root, "baseline-checkpoint.json")
    declaration = load(c.root, "declaration.json")
    {:ok, before} = Journal.load(c.dir, read["session_id"])
    assert JSON.digest(before) === selected["events_sha256"]

    {:ok, prepared} =
      ProtectedAnswer.prepare(
        declaration,
        baseline["declaration_sha256"],
        "paired",
        &blob(c.root, &1),
        before,
        read["session_id"],
        "first",
        selected["invocation_id"]
      )

    events = answer(c, read["session_id"], prepared, "candidate")
    parent = last_answer(events)

    {:ok, row} =
      ProtectedAnswer.project(
        declaration,
        baseline["declaration_sha256"],
        "paired",
        &blob(c.root, &1),
        events,
        read["session_id"],
        "first",
        selected["invocation_id"],
        parent["invocation_id"]
      )

    save(c.root, "candidate-row.json", row)
    assert row["status"] === "ok" and length(row["members"]) === 4
    assert row["elapsed_ms"] === nil and row["cost_nanos"] === nil

    {:ok, first} =
      SelectionExperiment.freeze_rows(declaration, baseline["declaration_sha256"], [row])

    save_once(c.root, "first-predictions.json", first)
    first_file = Path.join(c.root, "first-predictions.json")
    first_bytes = File.read!(first_file)
    assert load(c.root, "first-predictions.json") === first
    first_sha = JSON.digest([first])

    save_once(c.root, "first-predictions-frozen.json", %{
      "version" => 1,
      "sha256" => first_sha,
      "file_sha256" => JSON.sha256(first_bytes),
      "declaration_sha256" => baseline["declaration_sha256"]
    })

    {:ok, template} =
      SelectionExperiment.prepare_reviews(
        declaration,
        baseline["declaration_sha256"],
        first,
        first_sha,
        &blob(c.root, &1)
      )

    assert length(template["semantic"]) === 2

    assert Enum.all?(
             template["semantic"],
             &(&1["independent"] === false and &1["verdict"] === "unmeasured")
           )

    save_once(c.root, "unmeasured-reviews.json", template)
    review_bytes = File.read!(Path.join(c.root, "unmeasured-reviews.json"))
    assert Jason.decode!(review_bytes) === template

    {:ok, report} =
      SelectionExperiment.score(
        declaration,
        baseline["declaration_sha256"],
        first,
        first_sha,
        fn -> {:ok, references(c)} end,
        fn ->
          assert File.read!(first_file) === first_bytes

          save_once(c.root, "review-loader-invoked.json", %{
            "version" => 1,
            "first_prediction_sha256" => first_sha,
            "review_binding_sha256" => template["review_binding_sha256"]
          })

          {:ok, review_bytes}
        end,
        &blob(c.root, &1)
      )

    assert load(c.root, "review-loader-invoked.json")["first_prediction_sha256"] === first_sha
    assert report["qualification"] === "none" and report["disposition"] === "unverified"
    assert report["known_rows_complete"] and report["comparison"] === nil
    refute report["support_and_citations_measured"]
    assert report["candidate"]["p95_ms"] === nil and report["candidate"]["cost_nanos"] === nil
    assert report["baseline"]["p95_ms"] === nil and report["baseline"]["cost_nanos"] === nil
    assert File.read!(first_file) === first_bytes
    save_once(c.root, "unqualified-report.json", report)
    report_bytes = File.read!(Path.join(c.root, "unqualified-report.json"))
    assert report_bytes === Jason.encode!(report) <> "\n"
    assert load(c.root, "unqualified-report.json") === report
    assert File.read!(Path.join(c.root, "unqualified-report.json")) === report_bytes
    idle(c, read["session_id"])
    checkpoint(c, p, 1)
    references(c)
    assert File.read!(first_file) === first_bytes
    assert File.read!(Path.join(c.root, "unmeasured-reviews.json")) === review_bytes
    assert load(c.root, "unqualified-report.json") === report
    assert File.read!(Path.join(c.root, "unqualified-report.json")) === report_bytes

    save_once(c.root, "evaluation-lifecycle-closed.json", %{
      "version" => 2,
      "declaration_sha256" => baseline["declaration_sha256"],
      "reference_sha256" => c.commitments["label_commitment"],
      "first_prediction_sha256" => first_sha,
      "first_file_sha256" => JSON.sha256(first_bytes),
      "review_sha256" => JSON.sha256(review_bytes),
      "report_sha256" => JSON.sha256(report_bytes),
      "independent_labels" => nil,
      "quality" => "unverified",
      "default" => nil
    })

    save(c.root, "paired-body-result.json", %{
      status: "observed",
      original_reads: 8,
      baseline_members: 6,
      candidate_members: 4,
      main_wires: 3,
      helper_wires: 2,
      decision_wires: 1,
      quality: "unverified",
      latency_comparison: nil,
      whole_cost: nil,
      standalone_cli: "unqualified",
      evaluation_lifecycle: "reference_v2_first_rows_and_unmeasured_review",
      independent_labels: nil
    })
  end

  defp references(c) do
    bytes = File.read!(c.commitments["reference_path"])
    assert {:ok, hash} = SelectionExperiment.commit_references(bytes)
    assert hash === c.commitments["label_commitment"]
    bytes
  end

  defp answer(c, id, prepared, phase) do
    Agent.update(
      c.protocol,
      &Map.merge(&1, %{request: prepared.request, records: prepared.records})
    )

    {:ok, pid} = start(c, id)

    owned(c, pid, id, "answer", fn ->
      terminal(c, pid, phase, prepared, nil)
    end)

    {:ok, events} = Journal.load(c.dir, id)
    {:ok, _} = Session.Saved.restore(events, id)
    events
  end

  # Native watcher/Terminal handshake is reused from the qualified v4 fixture.
  defp terminal(c, pid, phase, prepared, prompt) do
    for name <-
          ~w(managed-approval-input-ready managed-approval-control-checked managed-approval-exit-ready),
        do: File.rm(Path.join(c.root, name))

    watcher =
      Task.Supervisor.async_nolink(Ipse.Tasks, fn ->
        wait_until(fn -> :sys.get_state(pid).operator_channel !== nil end, 5_000)

        if prepared do
          assert :ok =
                   Session.invoke_export(pid, :service, "ext__paired_answer__answer_context", %{
                     "request" => prepared.request
                   })
        end

        wait_until(
          fn -> File.exists?(Path.join(c.root, "managed-approval-input-ready")) end,
          45_000
        )

        state = :sys.get_state(pid)
        spec = state.managed_approval

        assert state.phase === :managed_approval and
                 Session.ManagedApproval.current?(state, spec.input)

        assert {:error, :session_share_frozen} = Session.approve(pid, spec.id, true)

        if prepared do
          assert spec.previous_phase === :extension_service and
                   spec.arguments["request"] === prepared.request

          assert {:ok, union} =
                   ManagedReference.union([
                     spec.dependencies,
                     prepared.original_dependencies,
                     Map.get(prepared, :baseline_dependencies, [])
                   ])

          assert union === spec.dependencies
        else
          assert spec.arguments["request"]["op"] === "decision.create"
        end

        File.write!(Path.join(c.root, "managed-approval-control-checked"), "checked")
        wait_until(fn -> idle?(Session.info(pid)) end, 20_000)
        File.write!(Path.join(c.root, "managed-approval-exit-ready"), "ready")

        receive do
          :terminal_returned -> :ok
        after
          60_000 -> flunk("terminal return handshake unavailable")
        end

        %{approval_current: true, dependencies_sha256: JSON.digest(spec.dependencies)}
      end)

    try do
      IO.puts("IPSE_MANAGED_APPROVAL_CLI_READY")
      terminal = Ipse.CLI.Terminal.interact(pid, Process.monitor(pid), true, prompt, c.cwd)
      send(watcher.pid, :terminal_returned)
      observed = Task.yield(watcher, 1000)

      save(c.root, phase <> "-terminal.json", %{
        terminal_status: terminal,
        watcher_completed: match?({:ok, _}, observed),
        session_alive: Process.alive?(pid)
      })

      assert terminal === 0
      assert {:ok, _} = observed
    after
      Task.shutdown(watcher, :brutal_kill)
    end
  end

  defp idle(c, id) do
    path = Path.join(c.dir, id <> ".jsonl")
    before = File.read!(path)
    prior = Agent.get(c.calls, & &1)
    {:ok, pid} = start(c, id)

    owned(c, pid, id, "idle", fn ->
      assert Session.info(pid).phase === :idle
      Ipse.Test.ResumeAssertions.assert_idle_resume_journal(path, before, id)
    end)

    assert Agent.get(c.calls, & &1) === prior
  end

  defp prefix(c, read) do
    {:ok, all} = Journal.load(c.dir, read["session_id"])
    result = Enum.take(all, read["event_count"])
    assert JSON.digest(result) === read["events_sha256"]
    result
  end

  defp last_answer(events),
    do:
      events
      |> Enum.filter(
        &(&1["type"] === "extension_invocation_intent" and
            get_in(&1, ["descriptor", "id"]) === "answer_context")
      )
      |> List.last()

  defp start(c, id \\ nil),
    do:
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session,
         [config: c.runtime, cwd: c.cwd, state_dir: c.dir, subscriber: self()] ++
           if(id, do: [id: id], else: [])}
      )

  defp close(c, pid, id) do
    assert :ok = Session.close_confirmed(pid)
    assert {:ok, events} = Journal.load(c.dir, id)
    assert {:ok, _} = Session.Saved.restore(events, id)
  end

  # Retain the primary failure even if confirmed close or its fixed receipt fails.
  defp owned(c, pid, id, purpose, body) do
    result =
      try do
        {:ok, body.()}
      catch
        kind, reason -> {:error, kind, reason, __STACKTRACE__}
      end

    closed =
      try do
        close(c, pid, id)
        :confirmed
      catch
        _, _ -> :unconfirmed
      end

    recorded =
      try do
        path = Path.join(c.root, "owned-close-#{c.phase}-#{purpose}-#{id}.json")

        File.open!(path, [:write, :binary, :exclusive], fn file ->
          :ok = File.chmod(path, 0o600)

          :ok =
            IO.binwrite(
              file,
              Jason.encode!(%{
                phase: c.phase,
                purpose: purpose,
                status: closed,
                body_completed: match?({:ok, _}, result)
              }) <> "\n"
            )

          :ok = :file.sync(file)
        end)

        {:ok, :ok} = File.open(c.root, [:read, :raw, :directory], &:file.sync/1)
        :ok
      catch
        _, _ -> :failed
      end

    case result do
      {:error, kind, reason, stack} ->
        :erlang.raise(kind, reason, stack)

      {:ok, value} ->
        assert closed === :confirmed and recorded === :ok
        value
    end
  end

  defp idle?(%{phase: :idle}), do: true
  defp idle?(%{phase: phase}) when is_atom(phase), do: false
  defp idle?({:error, :session_share_frozen}), do: false

  defp idle?(other),
    do:
      flunk(
        "unexpected Session info class #{inspect(if(is_tuple(other), do: elem(other, 0), else: :other))}"
      )

  defp wait_until(fun, milliseconds),
    do: wait_until_at(fun, System.monotonic_time(:millisecond) + milliseconds)

  defp wait_until_at(fun, deadline) do
    assert System.monotonic_time(:millisecond) < deadline
    ready = fun.()
    assert System.monotonic_time(:millisecond) < deadline

    if ready,
      do: :ok,
      else:
        (
          Process.sleep(10)
          wait_until_at(fun, deadline)
        )
  end

  defp runtime(c) do
    {:ok, effective} =
      Ipse.Config.resolve(c.cwd, c.home, [config: c.path, project_config: false], %{})

    client = %{
      workspace: c.cwd,
      home: c.home,
      auth_dir: Path.join(c.home, "auth"),
      operator_home: c.root,
      mcp_config: nil,
      base_url: nil,
      operator_questions: true,
      accept_edits: false,
      approval: :ask,
      approval_origin: :interactive,
      headless: false
    }

    {:ok, runtime} = Ipse.Config.runtime(effective, client)
    {:ok, project} = ProjectIdentity.existing(c.home, c.cwd)
    {:ok, runtime} = Ipse.Config.Activation.fresh(runtime, c.cwd)

    Map.merge(c, %{
      runtime: runtime,
      project: project,
      control: SemanticAdmission.control_root(c.home),
      collection: SemanticAdmission.collection_root(c.home)
    })
  end

  defp checkpoint(c, p, decision_calls) do
    assert JSON.sha256(File.read!(c.path)) === p["config_sha256"]
    assert originals_unchanged?(p["originals"], fingerprints(c.dir, p["source_id"]))

    {:ok, snapshot} =
      Collection.execute(c.collection, p["namespace"], %{"op" => "snapshot"}, Ipse.Usage.id())

    assert snapshot === p["snapshot"]
    {:ok, now} = Consent.existing_snapshot(c.control, c.project["project_id"])
    old = p["policy"]
    assert now["epoch"] === old["epoch"] and now["policy"] === old["policy"]
    assert Map.take(now["operations"], Map.keys(old["operations"])) === old["operations"]
    new = Map.drop(now["operations"], Map.keys(old["operations"])) |> Map.values()
    assert length(new) === decision_calls
    assert Enum.all?(new, &(&1["status"] === "settled" and &1["actual"]["model_calls"] === 1))
  end

  defp fingerprints(dir, id),
    do: Map.new(for kind <- ~w(jsonl lock), do: {kind, pin(Path.join(dir, id <> "." <> kind))})

  defp pin(path) do
    s = File.stat!(path, time: :posix)

    %{
      "sha256" => JSON.sha256(File.read!(path)),
      "inode" => s.inode,
      "device" => s.major_device,
      "mode" => s.mode,
      "size" => s.size,
      "mtime" => s.mtime,
      "ctime" => s.ctime
    }
  end

  defp originals_unchanged?(before, after_read),
    do:
      Enum.all?(before, fn {kind, prior} ->
        current = after_read[kind]

        if kind === "lock",
          do:
            Map.delete(current, "ctime") === Map.delete(prior, "ctime") and
              current["ctime"] >= prior["ctime"],
          else: current === prior
      end)

  defp blob(root, sha) do
    bytes = File.read!(Path.join([root, "blobs", sha]))
    assert JSON.sha256(bytes) === sha
    {:ok, bytes}
  end

  defp put_blob(root, bytes) do
    File.mkdir_p!(Path.join(root, "blobs"))
    path = Path.join([root, "blobs", JSON.sha256(bytes)])
    File.write!(path, bytes, [:exclusive])
    File.chmod!(path, 0o600)
  end

  defp save(root, name, value) do
    path = Path.join(root, name)
    File.write!(path, Jason.encode!(value) <> "\n")
    File.chmod!(path, 0o600)
  end

  defp save_once(root, name, value) do
    path = Path.join(root, name)
    File.write!(path, Jason.encode!(value) <> "\n", [:exclusive, :sync])
    File.chmod!(path, 0o600)
  end

  defp load(root, name), do: Path.join(root, name) |> File.read!() |> Jason.decode!()

  defp configure(c, artifact) do
    profile = %{
      "provider" => "ollama",
      "model" => "synthetic",
      "base_url" => c.base,
      "max_output_tokens" => 256,
      "timeout_ms" => 20_000
    }

    save(c.home, "config.json", %{
      "version" => 1,
      "profiles" => %{"main" => profile, "extract" => %{profile | "timeout_ms" => 3000}},
      "roles" => %{"main" => "main"},
      "decision_profiles" => %{
        "advice" => %{
          "operation" => "decision",
          "provider" => "system_one_compatible",
          "model" => "synthetic",
          "service_id" => "fixture",
          "base_url" => c.base,
          "timeout_ms" => 3000
        }
      },
      "inference_services" => %{"fixture" => %{"version" => 1, "origins" => [c.base]}},
      "extensions" => [
        %{
          "instance" => "paired_answer",
          "artifact" => artifact.digest,
          "enabled" => true,
          "options" => %{},
          "order" => 10,
          "lifetime" => "session"
        }
      ],
      "extension_trust" => [
        %{
          "artifact" => artifact.digest,
          "capabilities" => artifact.manifest["capabilities"],
          "allow_project" => false,
          "allow_children" => false
        }
      ]
    })
  end

  # Same registered synthetic HTTP protocols as the published phased fixture.
  defp server(calls, protocol, port) do
    {:ok, listener} =
      :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, actual}} = :inet.sockname(listener)
    task = Task.Supervisor.async_nolink(Ipse.Tasks, fn -> serve(listener, calls, protocol) end)
    {"http://127.0.0.1:#{actual}", listener, task}
  end

  defp serve(listener, calls, protocol) do
    case :gen_tcp.accept(listener, 30_000) do
      {:ok, socket} ->
        try do
          {headers, bytes} = Ipse.Test.ProviderFixture.request(socket, "")
          request = Jason.decode!(bytes)
          p = Agent.get(protocol, & &1)
          decision = String.starts_with?(headers, "POST /systemone ")

          kind =
            cond do
              decision -> :decision
              p.phase in ~w(baseline candidate) -> :helper
              true -> :main
            end

          index = length(Agent.get(calls, & &1))
          Agent.update(calls, &(&1 ++ [%{kind: kind, request_sha256: JSON.digest([request])}]))
          assert Enum.at(@expected[p.phase], index) === kind
          response = response(p, kind, index, request)
          body = Jason.encode!(response) <> if(decision, do: "", else: "\n")

          :ok =
            :gen_tcp.send(
              socket,
              "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                body
            )
        after
          :gen_tcp.close(socket)
        end

        serve(listener, calls, protocol)

      {:error, :closed} ->
        :ok

      {:error, :timeout} ->
        :ok
    end
  end

  defp response(p, :helper, 0, request) do
    assert request["messages"] === Session.Context.helper_messages(p.request)
    first = hd(p.records)
    text = first["outcome"]["value"]["record"]["value"]["text"]

    answer = %{
      "kind" => "answer",
      "text" => "Synthetic answer.",
      "citations" => [
        %{
          "key" => first["key"],
          "revision" => first["revision"],
          "start_byte" => 0,
          "end_byte" => byte_size(text),
          "quote" => text,
          "quote_sha256" => JSON.sha256(text),
          "claim_start_byte" => 0,
          "claim_end_byte" => 17
        }
      ]
    }

    ollama(%{"role" => "assistant", "content" => Jason.encode!(answer)})
  end

  defp response(%{phase: "selection"}, :decision, 1, _),
    do: %{
      "model" => "synthetic",
      "answers" => %{
        "pack" => %{
          "type" => "choice",
          "choice" => "first",
          "confidence" => 0.9,
          "probabilities" => %{"first" => 0.9, "second" => 0.1}
        }
      },
      "usage" => %{"input_tokens" => 10, "output_tokens" => 2}
    }

  defp response(%{phase: "selection"} = p, :main, 0, _),
    do:
      ollama(%{
        "role" => "assistant",
        "content" => "",
        "tool_calls" => [
          %{
            "function" => %{"name" => "ext__knowledge__select_shadow", "arguments" => p.arguments}
          }
        ]
      })

  defp response(%{phase: "selection"}, :main, 2, request) do
    assert Enum.any?(
             request["messages"],
             &(&1["role"] === "tool" and &1["tool_name"] === "ext__knowledge__select_shadow")
           )

    ollama(%{"role" => "assistant", "content" => "Synthetic selection completed."})
  end

  defp response(%{phase: "read"}, :main, 0, _),
    do: ollama(%{"role" => "assistant", "content" => "Synthetic observations read."})

  defp ollama(message),
    do: %{
      "model" => "synthetic",
      "message" => message,
      "done" => true,
      "prompt_eval_count" => 1,
      "eval_count" => 1
    }
end
