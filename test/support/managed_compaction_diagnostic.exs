# Actual Session source receipts and signed records; expiry waits for a real reviewed deadline.
defmodule Ipse.Test.ManagedCompactionDiagnostic do
  import ExUnit.Assertions
  alias Ipse.{Extension.Collection, Extension.ProjectIdentity, Session.StoredSources, Usage}
  alias Ipse.Extension.Collection.{ManagedPages, ObservedRead}

  def run(config, cwd, home, dir, session_id, ordinary, temporal, deadline) do
    admission = config.semantic_admission
    pin = admission["pin"]
    root = Ipse.Extension.SemanticAdmission.collection_root(home)
    {:ok, binding} = ProjectIdentity.existing(home, cwd)

    recipe =
      admission["policy"]["settings"]["recipes"]
      |> Map.values()
      |> Enum.find(&(&1["kind"] == "literal_source"))

    {:ok, snapshot} =
      Collection.execute(root, pin["namespace"], %{"op" => "snapshot"}, Usage.id())

    {:ok, page} =
      Collection.scan_visible(
        root,
        pin["namespace"],
        %{"op" => "scan", "after" => nil, "generation" => snapshot["generation"], "limit" => 8},
        Usage.id()
      )

    separate = Enum.find(page["records"], &(&1["value"]["text"] == "A separate claim to forget"))

    successor =
      Enum.find(page["records"], &(&1["value"]["text"] == "My fixture timezone is Europe/Berlin"))

    assert separate && successor

    history = fn ->
      ProjectIdentity.with_existing_domain_auth(
        home,
        cwd,
        binding,
        %{namespace: pin["namespace"], format: "managed-metadata-v3"},
        fn cap, catalog ->
          ObservedRead.managed_history(
            root,
            pin["namespace"],
            %{"op" => "get_record", "key" => temporal["key"]},
            cap,
            catalog,
            recipe
          )
        end
      )
    end

    current = fn ->
      ProjectIdentity.with_existing_domain_auth(
        home,
        cwd,
        binding,
        %{namespace: pin["namespace"], format: "managed-metadata-v3"},
        fn cap, catalog ->
          ObservedRead.managed_record(
            root,
            pin["namespace"],
            %{"op" => "get_record", "key" => successor["key"]},
            cap,
            catalog,
            recipe
          )
        end
      )
    end

    {:ok, _old_history} = history.()
    {:ok, _new_current} = current.()

    {_anchor_before_record, anchor_before} =
      anchor(root, pin, home, cwd, binding, ordinary["value"]["lineage"])

    assert is_map(anchor_before["choice"])
    management_dir = Path.join(home, "knowledge-management")

    retention =
      Enum.find_value(Ipse.Journal.list(management_dir), fn entry ->
        {:ok, events} = Ipse.Journal.load(management_dir, entry["id"])
        intent = Enum.find(events, &(&1["type"] == "managed_lifecycle_intent"))
        result = Enum.find(events, &(&1["type"] == "managed_lifecycle_result"))

        if intent && result && intent["facts"]["kind"] == "managed_literal_retention" &&
             intent["facts"]["target"]["key"] == ordinary["key"],
           do: {entry["id"], events, intent, result}
      end)

    assert {_retention_id, _retention_events, retention_intent, retention_result} = retention
    choice = anchor_before["choice"]

    review = %{
      "version" => 1,
      "kind" => "native_review",
      "command" => "duration",
      "event_id" => choice["event_id"],
      "display_sha256" => choice["display_sha256"],
      "challenge" => choice["challenge"],
      "input_sha256" => choice["input_sha256"],
      "observed_at_ms" => choice["observed_at_ms"],
      "facts_sha256" => Ipse.JSON.digest([retention_intent["facts"]])
    }

    assert retention_result["result"]["receipt"]["native_review_sha256"] ==
             Ipse.JSON.digest([review])

    assert {:error, _} = Ipse.CLI.Knowledge.Management.expire(config, cwd, ordinary["key"])
    proofs = temporal["value"]["evidence"]["sources"] ++ successor["value"]["evidence"]["sources"]
    assert length(proofs) == 2 and Enum.all?(proofs, &(&1["session_id"] == session_id))
    context = %{config: config, session_id: Usage.id(), history_dir: dir}

    verify = fn ->
      assert {:ok, checked} = StoredSources.with_verified(context, nil, proofs, &{:ok, &1})
      assert Enum.map(checked, & &1["proof"]) == proofs
    end

    {:ok, journal_before} = File.read(Path.join(dir, session_id <> ".jsonl"))
    verify.()
    Process.sleep(max(deadline - System.system_time(:millisecond) + 20, 0))
    interrupted_before = Enum.map(Ipse.Journal.list(management_dir), & &1["id"])

    {:ok, _root_before_interrupt} =
      Collection.execute(root, pin["namespace"], %{"op" => "snapshot"}, Usage.id())

    interrupt_handler = "compaction-diagnostic-" <> Usage.id()
    interrupt_owner = self()
    root_file = Path.join([root, pin["namespace"], "root.json"])

    control_file =
      Path.join([
        Ipse.Extension.SemanticAdmission.control_root(home),
        pin["project_id"],
        "control.json"
      ])

    evidence = Path.dirname(home)
    File.cp!(root_file, Path.join(evidence, "root-before.json"))
    File.cp!(control_file, Path.join(evidence, "control-before.json"))

    assert :ok =
             :telemetry.attach(
               interrupt_handler,
               [:ipse, :extension, :collection, :staged],
               fn _, _, _, _ ->
                 controller = Process.get({Ipse.Runner.Transaction, :controller})
                 send(interrupt_owner, {:compaction_staged, self(), controller})

                 receive do
                   :diagnostic_continue -> :ok
                 after
                   30_000 -> :ok
                 end
               end,
               nil
             )

    {victim, victim_ref} =
      spawn_monitor(fn -> Ipse.CLI.Knowledge.Management.expire(config, cwd, ordinary["key"]) end)

    assert_receive {:compaction_staged, effect, controller}, 10_000
    assert is_pid(controller)
    effect_ref = Process.monitor(effect)
    controller_ref = Process.monitor(controller)
    controller_state = :sys.get_state(controller)
    port = controller_state.port

    native_pid =
      case Port.info(port, :os_pid) do
        {:os_pid, pid} -> pid
        _ -> nil
      end

    process_before = %{
      "victim_pid" => inspect(victim),
      "effect_pid" => inspect(effect),
      "controller_pid" => inspect(controller),
      "native_os_pid" => native_pid,
      "effect_status" => inspect(Process.info(effect, :status)),
      "controller_monitors" => inspect(Process.info(controller, :monitors))
    }

    File.write!(
      Path.join(evidence, "process-before.json"),
      Jason.encode!(process_before, pretty: true)
    )

    Process.exit(victim, :kill)
    assert_receive {:DOWN, ^victim_ref, :process, ^victim, :killed}, 5_000
    assert_receive {:DOWN, ^controller_ref, :process, ^controller, controller_reason}, 5_000
    effect_alive_after_controller = Process.alive?(effect)
    port_after_controller = Port.info(port)
    send(effect, :diagnostic_continue)
    assert_receive {:DOWN, ^effect_ref, :process, ^effect, effect_reason}, 10_000
    assert :ok = :telemetry.detach(interrupt_handler)

    File.cp!(root_file, Path.join(evidence, "root-after.json"))
    File.cp!(control_file, Path.join(evidence, "control-after.json"))

    [interrupted] =
      Enum.reject(Ipse.Journal.list(management_dir), &(&1["id"] in interrupted_before))

    assert {:ok, interrupted_events} = Ipse.Journal.load(management_dir, interrupted["id"])

    interrupted_intent =
      Enum.find(interrupted_events, &(&1["type"] == "managed_lifecycle_intent"))

    interrupted_result =
      Enum.find(interrupted_events, &(&1["type"] == "managed_lifecycle_result"))

    {:ok, inspection} = Ipse.CLI.Knowledge.Management.operation(config, cwd, interrupted["id"])

    report = %{
      "processes" => process_before,
      "controller_exit" => inspect(controller_reason),
      "effect_exit" => inspect(effect_reason),
      "effect_alive_after_controller_exit" => effect_alive_after_controller,
      "port_closed_after_controller_exit" => is_nil(port_after_controller),
      "root_before_sha256" =>
        Ipse.JSON.sha256(File.read!(Path.join(evidence, "root-before.json"))),
      "root_after_sha256" => Ipse.JSON.sha256(File.read!(Path.join(evidence, "root-after.json"))),
      "control_before_sha256" =>
        Ipse.JSON.sha256(File.read!(Path.join(evidence, "control-before.json"))),
      "control_after_sha256" =>
        Ipse.JSON.sha256(File.read!(Path.join(evidence, "control-after.json"))),
      "journal_id" => interrupted["id"],
      "inspection" => inspection,
      "intent_sha256" => Ipse.JSON.digest([interrupted_intent]),
      "intent_choice_sha256" =>
        Ipse.JSON.digest([interrupted_intent["facts"]["metadata"]["choice"]]),
      "result_present" =>
        Enum.any?(interrupted_events, &(&1["type"] == "managed_lifecycle_result")),
      "result_status" => interrupted_result && interrupted_result["status"],
      "automatically_replayed" => false
    }

    File.write!(
      Path.join(evidence, "diagnostic-report.json"),
      Jason.encode!(report, pretty: true)
    )

    IO.puts("COMPACTION_DIAGNOSTIC=" <> Jason.encode!(report))
    assert effect_alive_after_controller
    assert is_nil(port_after_controller)
    assert report["root_before_sha256"] == report["root_after_sha256"]
    assert interrupted_intent["facts"]["metadata"]["choice"] == choice
    assert interrupted_result["operation_id"] == interrupted_intent["operation_id"]
    assert inspection["operation_id"] == interrupted_intent["operation_id"]
    assert inspection["action_sha256"] == interrupted_intent["facts"]["action_sha256"]
    assert interrupted_result["status"] == "unconfirmed"
    assert interrupted_result["result"] == %{"reason" => "knowledge_management_unconfirmed"}

    assert inspection["journal_status"] == "unconfirmed" and
             inspection["control_status"] == "publishing" and inspection["replayed"] == false

    assert {:ok, ^journal_before} = File.read(Path.join(dir, session_id <> ".jsonl"))
    IO.puts("COMPACTION_DIAGNOSTIC_PASSED")
  end

  defp anchor(root, pin, home, cwd, binding, lineage) do
    {:ok, result} =
      ProjectIdentity.with_existing_domain_auth(
        home,
        cwd,
        binding,
        %{namespace: pin["namespace"], format: "managed-metadata-v3"},
        fn cap, _ ->
          {:ok, view} = Collection.open_view(root, pin["namespace"])

          try do
            {:ok, neighbors} =
              Collection.view_neighbors(view, %{
                "version" => 1,
                "prefix" => ManagedPages.prefix(:anchor),
                "fence_bytes" => ManagedPages.width(:anchor),
                "needle" => lineage
              })

            key = neighbors["neighbors"]["selected"]["key"]
            {:ok, read} = Collection.view_read(view, %{"op" => "get_many", "keys" => [key]})
            assert read["witness"] == neighbors["witness"]
            [record] = read["records"]
            {:ok, page} = ManagedPages.open(cap, record, neighbors)
            {:ok, {record, page.entries[lineage]}}
          after
            assert :ok = Collection.close_view(view)
          end
        end
      )

    result
  end
end
