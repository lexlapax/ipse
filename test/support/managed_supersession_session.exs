ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
[root, scenario] = System.argv()
followup = Process.delete({:managed_supersession_fixture, :followup})
assert followup in [nil, :history_use, :compaction_diagnostic]
assert followup != :history_use or scenario == "current"
assert followup != :compaction_diagnostic or scenario == "shared"

if scenario == "terminal_effect_unknown" do
  Code.require_file("managed_supersession_unknown.exs", __DIR__)
  Ipse.Test.ManagedSupersessionUnknown.interpose_after_effect(root)
end

for key <- ~w(IPSE_PROVIDER IPSE_MODEL IPSE_CONFIG IPSE_PROFILE IPSE_SANDBOX IPSE_SUBAGENTS),
    do: System.delete_env(key)

home = Path.join(root, "home")
cwd = Path.join(root, "work")

for path <- [home, cwd] do
  File.mkdir_p!(path)
  File.chmod!(path, 0o700)
end

System.put_env("IPSE_HOME", home)
config_path = Path.join(home, "config.json")

File.write!(
  config_path,
  Jason.encode!(%{"version" => 1, "settings" => %{"provider" => "demo", "model" => "scripted"}})
)

File.chmod!(config_path, 0o600)

assert Ipse.CLI.run([
         "knowledge",
         "enable",
         "--cwd",
         cwd,
         "--config",
         config_path,
         "--no-project-config"
       ]) == 0

defmodule SupersessionUnexpectedModel do
  def complete(config, _, _, _) do
    File.write!(Path.join(config.fixture_root, "unexpected-model"), "called")
    raise "native correction must not invoke a model"
  end
end

client = %{
  workspace: cwd,
  home: home,
  auth_dir: Path.join(home, "auth"),
  operator_home: root,
  mcp_config: nil,
  base_url: nil,
  operator_questions: true,
  accept_edits: false,
  approval: :ask,
  approval_origin: :interactive,
  headless: false
}

assert {:ok, effective} =
         Ipse.Config.resolve(cwd, home, [config: config_path, project_config: false], %{})

assert {:ok, config} = Ipse.Config.runtime(effective, client)
config = Map.merge(config, %{provider_module: SupersessionUnexpectedModel, fixture_root: root})
dir = Path.join(home, "sessions")
opts = [config: config, cwd: cwd, state_dir: dir, subscriber: self()]
assert {:ok, session} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
id = Ipse.Session.info(session).id
assert {:ok, channel} = Ipse.Session.open_input_channel(session, self())

idle_resume = fn active, active_id, events ->
  id = active_id
  assert :ok = Ipse.Session.close_confirmed(active)
  assert {:ok, closed} = Ipse.Journal.load(dir, id)
  assert Enum.take(closed, length(events)) === events

  assert [%{"type" => "session_release_intent", "session_id" => ^id}] =
           Enum.drop(closed, length(events))

  assert {:ok, %{"release_claim" => "signed_release_claim"}} =
           Ipse.Session.Saved.inspect_saved(dir, id)

  assert {:ok, saved_closed} = Ipse.Session.Saved.restore(closed, id)

  assert {:ok, resumed} =
           DynamicSupervisor.start_child(
             Ipse.Sessions,
             {Ipse.Session, Keyword.put(opts, :id, id)}
           )

  assert Ipse.Session.info(resumed).phase == :idle
  assert {:ok, opened} = Ipse.Journal.load(dir, id)
  assert Enum.take(opened, length(closed)) === closed
  assert [owner] = Enum.drop(opened, length(closed))
  assert Ipse.Session.ReleaseReceipt.valid_owner_marker?(owner, id)
  assert :sys.get_state(resumed).messages === saved_closed.messages
  assert :ok = Ipse.Session.close_confirmed(resumed)
  assert {:ok, final} = Ipse.Journal.load(dir, id)
  assert Enum.take(final, length(opened)) === opened

  assert [
           %{
             "type" => "session_release_intent",
             "session_id" => ^id,
             "epoch_id" => nil,
             "closure_sha256" => nil
           }
         ] = Enum.drop(final, length(opened))

  assert {:ok, %{"release_claim" => "signed_release_claim"}} =
           Ipse.Session.Saved.inspect_saved(dir, id)

  assert {:ok, saved_final} = Ipse.Session.Saved.restore(final, id)
  assert saved_final.messages === saved_closed.messages
  final
end

intake = fn active, active_channel, active_id, command, step, expected ->
  monitor = Process.monitor(active)
  File.write!(Path.join(root, "supersession-input-#{step}"), command)
  IO.write("IPSE_SUPERSESSION_READ_#{step}> ")

  assert {:ok, ^command, witness} =
           Ipse.Session.observe_channel(active, active_channel, %{"kind" => "prompt"}, 30_000)

  assert {:ok, ticket} = Ipse.Session.stage_input(active, active_channel, command, witness)

  assert {:ok, %{"render_id" => render}} =
           Ipse.Session.prepare_assertion(active, active_channel, command, ticket)

  assert {:ok, input, witness} =
           Ipse.Session.observe_channel(
             active,
             active_channel,
             %{"kind" => "assertion", "render_id" => render},
             30_000
           )

  assert :ok =
           Ipse.Session.accept_assertion_observed(active, active_channel, render, input, witness)

  receive do
    {:DOWN, ^monitor, :process, ^active, reason} ->
      flunk("native supersession Session stopped: #{inspect(reason)}")

    {:ipse, ^active, {:done, ^expected}} ->
      Process.demonitor(monitor, [:flush])
      :ok

    {:ipse, ^active, {:done, outcome}} ->
      {:ok, events} = Ipse.Journal.load(dir, active_id)

      flunk(
        "native supersession #{step} failed #{inspect(outcome)}: " <>
          Jason.encode!(Enum.map(events, &Map.take(&1, ~w(type status outcome error))))
      )
  after
    20_000 -> flunk("native supersession intake timed out")
  end
end

intake.(session, channel, id, "/remember ordinary My fixture ordinary value", 1, :ok)
intake.(session, channel, id, "/remember current My fixture timezone is UTC", 2, :ok)

if scenario == "shared" do
  intake.(session, channel, id, "/remember ordinary A separate claim to forget", 3, :ok)
end

admission = :sys.get_state(session).config.semantic_admission
pin = admission["pin"]
collection = Ipse.Extension.SemanticAdmission.collection_root(home)

assert {:ok, snapshot} =
         Ipse.Extension.Collection.execute(
           collection,
           pin["namespace"],
           %{"op" => "snapshot"},
           Ipse.Usage.id()
         )

assert {:ok, page} =
         Ipse.Extension.Collection.scan_visible(
           collection,
           pin["namespace"],
           %{
             "op" => "scan",
             "after" => nil,
             "generation" => snapshot["generation"],
             "limit" => 8
           },
           Ipse.Usage.id()
         )

ordinary = Enum.find(page["records"], &(&1["value"]["text"] == "My fixture ordinary value"))
current = Enum.find(page["records"], &(&1["value"]["category"] == "current"))

original_source =
  if scenario == "cross_session" do
    assert :ok = Ipse.Session.close_confirmed(session)
    path = Path.join(dir, id <> ".jsonl")
    {id, path, File.read!(path)}
  end

{session, id, channel, admission, pin} =
  if original_source do
    assert {:ok, active} = DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})
    active_id = Ipse.Session.info(active).id
    assert {:ok, active_channel} = Ipse.Session.open_input_channel(active, self())
    active_admission = :sys.get_state(active).config.semantic_admission
    {active, active_id, active_channel, active_admission, active_admission["pin"]}
  else
    {session, id, channel, admission, pin}
  end

input_control =
  if original_source do
    {original_id, _, _} = original_source

    Task.async(fn ->
      for command <- ~w(correct supersede) do
        deadline = System.monotonic_time(:millisecond) + 20_000

        wait = fn wait ->
          unless File.exists?(Path.join(root, "cross-#{command}-ready")) do
            assert System.monotonic_time(:millisecond) < deadline
            Process.sleep(5)
            wait.(wait)
          end
        end

        wait.(wait)
        state = :sys.get_state(session)
        assert state.share_barrier.owner_protocol == :managed_relation_review
        assert state.share_barrier.phase == :review_input
        assert length(state.share_barrier.snapshot.verified_sources) == 1

        assert [%{"session_id" => ^original_id}] =
                 state.share_barrier.relation_display_inactive_sources

        assert {:ok, _} = Ipse.Extension.ProjectIdentity.existing(home, cwd)

        assert {:ok, _} =
                 Ipse.Extension.Consent.existing_snapshot(
                   Ipse.Extension.SemanticAdmission.control_root(home),
                   pin["project_id"]
                 )

        assert {:ok, :released} =
                 Ipse.Extension.Collection.with_managed_read(collection, pin["namespace"], fn _,
                                                                                              _,
                                                                                              alive ->
                   assert :ok = alive.()
                   {:ok, :released}
                 end)

        assert {:ok, lock} = Ipse.Runner.lock(Path.join(dir, original_id <> ".lock"))
        assert :ok = Ipse.Runner.unlock(lock)
        assert {:error, _} = Ipse.Runner.lock(Path.join(dir, id <> ".lock"))
        File.write!(Path.join(root, "cross-#{command}-checked"), "checked")
      end
    end)
  end

if scenario == "disabled" do
  assert :ok = Ipse.Session.close_confirmed(session)
  assert {:ok, original_events} = Ipse.Journal.load(dir, id)

  assert Ipse.CLI.run([
           "knowledge",
           "disable",
           "--cwd",
           cwd,
           "--config",
           config_path,
           "--no-project-config"
         ]) == 0

  assert {:ok, effective_disabled} =
           Ipse.Config.resolve(cwd, home, [config: config_path, project_config: false], %{})

  assert {:ok, disabled_config} = Ipse.Config.runtime(effective_disabled, client)

  disabled_config =
    Map.merge(disabled_config, %{provider_module: SupersessionUnexpectedModel, fixture_root: root})

  disabled_opts = [config: disabled_config, cwd: cwd, state_dir: dir, subscriber: self()]

  assert {:ok, disabled_session} =
           DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, disabled_opts})

  disabled_id = Ipse.Session.info(disabled_session).id
  assert :sys.get_state(disabled_session).config.semantic_admission["status"] != "active"
  assert {:ok, disabled_channel} = Ipse.Session.open_input_channel(disabled_session, self())
  assert {:ok, before_attempt} = Ipse.Journal.load(dir, disabled_id)
  command = "/correct " <> ordinary["key"] <> " My corrected ordinary value"
  File.write!(Path.join(root, "supersession-input-3"), command)
  IO.write("IPSE_SUPERSESSION_READ_3> ")

  assert {:ok, ^command, witness} =
           Ipse.Session.observe_channel(
             disabled_session,
             disabled_channel,
             %{"kind" => "prompt"},
             30_000
           )

  assert {:ok, ticket} =
           Ipse.Session.stage_input(disabled_session, disabled_channel, command, witness)

  assert {:error, :operator_assertion_refused} =
           Ipse.Session.prepare_assertion(disabled_session, disabled_channel, command, ticket)

  assert {:ok, ^before_attempt} = Ipse.Journal.load(dir, disabled_id)

  assert {:ok, ^snapshot} =
           Ipse.Extension.Collection.execute(
             collection,
             pin["namespace"],
             %{"op" => "snapshot"},
             Ipse.Usage.id()
           )

  assert {:ok, ^original_events} = Ipse.Journal.load(dir, id)
  assert :ok = Ipse.Session.close_confirmed(disabled_session)
  assert {:ok, closed_disabled} = Ipse.Journal.load(dir, disabled_id)
  assert {:ok, _} = Ipse.Session.Saved.restore(closed_disabled, disabled_id)
  refute File.exists?(Path.join(root, "unexpected-model"))
  IO.puts("MANAGED_SUPERSESSION_DISABLED_PASSED")
  System.halt(0)
end

if scenario in ~w(terminal_unknown terminal_effect_unknown) do
  Code.require_file("managed_supersession_unknown.exs", __DIR__)

  Ipse.Test.ManagedSupersessionUnknown.run(
    session,
    opts,
    root,
    cwd,
    dir,
    id,
    ordinary,
    collection,
    pin,
    snapshot,
    if(scenario == "terminal_effect_unknown", do: :after_effect, else: :input)
  )

  IO.puts("MANAGED_SUPERSESSION_#{String.upcase(scenario)}_PASSED")
  System.halt(0)
end

shared_deadline =
  if scenario == "shared" do
    assert {:ok, choice} =
             Ipse.CLI.Knowledge.Management.retain(config, cwd, ordinary["key"], %{
               "kind" => "duration",
               "duration_ms" => 15_000
             })

    choice["receipt"]["publication"]["normalization"]["valid_until_ms"]
  end

assert {:ok, relation_snapshot} =
         Ipse.Extension.Collection.execute(
           collection,
           pin["namespace"],
           %{"op" => "snapshot"},
           Ipse.Usage.id()
         )

if scenario in ~w(current cross_session terminal shared) do
  if scenario == "terminal" do
    File.write!(
      Path.join(root, "supersession-terminal-command"),
      "/correct " <> ordinary["key"] <> " My corrected ordinary value"
    )

    IO.puts("IPSE_SUPERSESSION_TERMINAL_READY")
    assert Ipse.CLI.Terminal.interact(session, Process.monitor(session), true, nil, cwd) == 0
  else
    intake.(
      session,
      channel,
      id,
      "/correct " <> ordinary["key"] <> " My corrected ordinary value",
      if(scenario == "shared", do: 4, else: 3),
      :ok
    )

    intake.(
      session,
      channel,
      id,
      "/supersede " <> current["key"] <> " My fixture timezone is Europe/Berlin",
      if(scenario == "shared", do: 5, else: 4),
      :ok
    )
  end

  assert {:ok, events} = Ipse.Journal.load(dir, id)
  count = if scenario == "terminal", do: 1, else: 2

  extra_assertions =
    cond do
      scenario == "cross_session" -> 0
      scenario == "shared" -> 3
      true -> 2
    end

  assert length(Enum.filter(events, &(&1["type"] == "operator_assertion"))) ==
           count + extra_assertions

  assert length(Enum.filter(events, &(&1["type"] == "managed_supersession_prepared"))) == count
  assert length(Enum.filter(events, &(&1["type"] == "managed_supersession_review"))) == count
  results = Enum.filter(events, &(&1["type"] == "managed_supersession_result"))
  assert length(results) == count and Enum.all?(results, &(&1["status"] == "settled"))

  assert {:ok, after_snapshot} =
           Ipse.Extension.Collection.execute(
             collection,
             pin["namespace"],
             %{"op" => "snapshot"},
             Ipse.Usage.id()
           )

  assert after_snapshot["generation"] == relation_snapshot["generation"] + count
  assert after_snapshot["floor"] == after_snapshot["generation"]

  for event <- Enum.filter(events, &(&1["type"] == "managed_supersession_intent")) do
    facts = event["facts"]
    result = Enum.find(results, &(&1["operation_id"] == event["operation_id"]))
    receipt = result["outcome"]["publication"]["receipt"]
    normalization = result["outcome"]["publication"]["normalization"]

    assert {:ok, %{"operation" => ^receipt}} =
             Ipse.Extension.Collection.execute(
               collection,
               pin["namespace"],
               %{"op" => "inspect", "operation_id" => event["operation_id"]},
               Ipse.Usage.id()
             )

    assert {:ok, %{"record" => retained}} =
             Ipse.Extension.Collection.execute(
               collection,
               pin["namespace"],
               %{"op" => "get", "key" => facts["target"]["key"]},
               Ipse.Usage.id()
             )

    assert retained["value"] === facts["target"]["value"]

    assert :ok =
             Ipse.Extension.ProjectIdentity.with_existing_domain_auth(
               home,
               cwd,
               admission["binding"],
               %{namespace: pin["namespace"], format: "managed-metadata-v3"},
               fn cap, catalog ->
                 recipe = facts["context"]["recipe"]

                 assert {:error, :collection_observation_refused} =
                          Ipse.Extension.Collection.ObservedRead.managed_record(
                            collection,
                            pin["namespace"],
                            %{"op" => "get_record", "key" => facts["target"]["key"]},
                            cap,
                            catalog,
                            recipe
                          )

                 assert {:ok, replacement} =
                          Ipse.Extension.Collection.ObservedRead.managed_record(
                            collection,
                            pin["namespace"],
                            %{"op" => "get_record", "key" => facts["replacement"]["key"]},
                            cap,
                            catalog,
                            recipe
                          )

                 assert replacement["observation"]["value"]["record"]["value"] ===
                          facts["replacement"]["value"]

                 assert replacement["metadata"]["first_admitted_ms"] ===
                          normalization["first_admitted_ms"]

                 assert replacement["metadata"]["valid_until_ms"] ===
                          normalization["valid_until_ms"]

                 :ok
               end
             )
  end

  deliveries = Enum.filter(events, &(&1["type"] == "managed_supersession_delivered"))
  assert length(deliveries) == count

  for delivered <- deliveries do
    candidate =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_result" and
            &1["operation_id"] == delivered["candidate_operation_id"])
      )

    assert candidate["outcome"] == %{
             "status" => "failed",
             "value" => %{"code" => "collection_policy_refused"}
           }
  end

  assert :ok = Ipse.Session.ManagedSupersession.validate_events(events, id)
  first_delivery = hd(deliveries)
  delivery_index = Enum.find_index(events, &(&1 == first_delivery))

  assert {:error, :managed_supersession_refused} =
           Ipse.Session.ManagedSupersession.validate_events(
             List.insert_at(events, delivery_index + 1, first_delivery),
             id
           )

  review_index = Enum.find_index(events, &(&1["type"] == "managed_supersession_review"))
  review = Enum.at(events, review_index)

  changed_review =
    put_in(review, ["review", "facts_sha256"], Ipse.JSON.sha256("changed relation"))

  assert {:error, :managed_supersession_refused} =
           Ipse.Session.ManagedSupersession.validate_events(
             List.replace_at(events, review_index, changed_review),
             id
           )

  intent_index = Enum.find_index(events, &(&1["type"] == "managed_supersession_intent"))
  intent = Enum.at(events, intent_index)

  changed_intent =
    Map.put(intent, "candidate_request_sha256", Ipse.JSON.sha256("different candidate"))

  assert {:error, :managed_supersession_refused} =
           Ipse.Session.ManagedSupersession.validate_events(
             List.replace_at(events, intent_index, changed_intent),
             id
           )

  for index <- [intent_index, review_index, delivery_index] do
    assert :ok = Ipse.Session.ManagedSupersession.validate_events(Enum.take(events, index), id)
  end

  prepared_index = Enum.find_index(events, &(&1["type"] == "managed_supersession_prepared"))
  prepared = Enum.at(events, prepared_index)

  parent =
    Enum.find(
      Enum.drop(events, prepared_index + 1),
      &(&1["type"] == "extension_invocation_intent")
    )

  candidate =
    Enum.find(
      events,
      &(&1["type"] == "extension_action_intent" and
          &1["operation_id"] == intent["candidate_operation_id"])
    )

  stale =
    Enum.take(events, prepared_index + 1) ++
      [%{"type" => "turn_finished"}, parent, candidate, intent]

  assert {:error, :managed_supersession_refused} =
           Ipse.Session.ManagedSupersession.validate_events(stale, id)

  candidate_index = Enum.find_index(events, &(&1 == candidate))

  closed_after_candidate =
    Enum.take(events, candidate_index + 1) ++ [%{"type" => "turn_finished"}, intent]

  assert {:error, :managed_supersession_refused} =
           Ipse.Session.ManagedSupersession.validate_events(closed_after_candidate, id)

  assert prepared["id"] != nil

  refute Enum.any?(events, &(&1["type"] in ~w(request_admitted inference_dispatch_intent)))
  refute File.exists?(Path.join(root, "unexpected-model"))
  assert {:ok, saved} = Ipse.Session.Saved.restore(events, id)

  assert saved.extension_state.last_display ==
           Ipse.Session.supersession_display(List.last(deliveries))

  assert saved.messages == :sys.get_state(session).messages
  _closed_events = idle_resume.(session, id, events)

  if original_source do
    Task.await(input_control, 1000)
    {_, path, bytes} = original_source
    assert File.read!(path) === bytes
  end

  if scenario == "shared" do
    helper =
      if followup == :compaction_diagnostic do
        Code.require_file("managed_compaction_diagnostic.exs", __DIR__)
        Ipse.Test.ManagedCompactionDiagnostic
      else
        Code.require_file("managed_shared_support.exs", __DIR__)
        Ipse.Test.ManagedSharedSupport
      end

    helper.run(
      Map.put(config, :semantic_admission, admission),
      cwd,
      home,
      dir,
      id,
      ordinary,
      current,
      shared_deadline
    )
  end

  if followup == :history_use do
    Code.require_file("managed_history_use.exs", __DIR__)
    Ipse.Test.ManagedHistoryUse.run(config, opts, cwd, home, dir, current)
  end

  IO.puts(
    case scenario do
      "terminal" -> "MANAGED_SUPERSESSION_TERMINAL_PASSED"
      "shared" -> "MANAGED_SUPERSESSION_SHARED_PASSED"
      "cross_session" -> "MANAGED_SUPERSESSION_CROSS_SESSION_PASSED"
      _ -> "MANAGED_SUPERSESSION_SESSION_PASSED"
    end
  )
else
  if scenario == "old_missing" do
    assert :ok = Ipse.Session.close_confirmed(session)
    original = Path.join(dir, id <> ".jsonl")
    assert :ok = File.chmod(original, 0o000)

    try do
      assert {:ok, next_session} =
               DynamicSupervisor.start_child(Ipse.Sessions, {Ipse.Session, opts})

      next_id = Ipse.Session.info(next_session).id
      assert {:ok, next_channel} = Ipse.Session.open_input_channel(next_session, self())

      intake.(
        next_session,
        next_channel,
        next_id,
        "/correct " <> ordinary["key"] <> " My corrected ordinary value",
        3,
        :error
      )

      assert {:ok, later} = Ipse.Journal.load(dir, next_id)
      refute Enum.any?(later, &(&1["type"] == "managed_supersession_intent"))
      refute Enum.any?(later, &(&1["type"] == "managed_supersession_review"))

      assert {:ok, after_snapshot} =
               Ipse.Extension.Collection.execute(
                 collection,
                 pin["namespace"],
                 %{"op" => "snapshot"},
                 Ipse.Usage.id()
               )

      assert after_snapshot["generation"] == snapshot["generation"]
      assert :ok = Ipse.Session.close_confirmed(next_session)
    after
      assert :ok = File.chmod(original, 0o600)
    end

    refute File.exists?(Path.join(root, "unexpected-model"))
    IO.puts("MANAGED_SUPERSESSION_OLD_MISSING_PASSED")
  else
    assert scenario in ~w(relation_cancel revoke terminal_cancel)

    changed =
      if scenario == "revoke" do
        Task.async(fn ->
          limit = System.monotonic_time(:millisecond) + 20_000

          wait = fn wait ->
            unless File.exists?(Path.join(root, "supersession-review-ready")) do
              assert System.monotonic_time(:millisecond) < limit
              Process.sleep(10)
              wait.(wait)
            end
          end

          wait.(wait)
          control = Ipse.Extension.SemanticAdmission.control_root(home)
          {:ok, state} = Ipse.Extension.Consent.existing_snapshot(control, pin["project_id"])

          assert {:ok, _} =
                   Ipse.Extension.Consent.revoke(control, pin["project_id"], state["epoch"])

          File.write!(Path.join(root, "supersession-revoked"), "done")
        end)
      end

    if scenario == "terminal_cancel" do
      File.write!(
        Path.join(root, "supersession-terminal-command"),
        "/correct " <> ordinary["key"] <> " My corrected ordinary value"
      )

      IO.puts("IPSE_SUPERSESSION_TERMINAL_READY")
      assert Ipse.CLI.Terminal.interact(session, Process.monitor(session), true, nil, cwd) == 0
    else
      intake.(
        session,
        channel,
        id,
        "/correct " <> ordinary["key"] <> " My corrected ordinary value",
        3,
        :error
      )
    end

    if changed, do: Task.await(changed, 20_000)
    assert {:ok, events} = Ipse.Journal.load(dir, id)
    [result] = Enum.filter(events, &(&1["type"] == "managed_supersession_result"))
    assert result["status"] == "refused" and result["outcome"] == nil

    assert Enum.count(events, &(&1["type"] == "managed_supersession_review")) ==
             if(scenario == "revoke", do: 1, else: 0)

    assert {:ok, after_snapshot} =
             Ipse.Extension.Collection.execute(
               collection,
               pin["namespace"],
               %{"op" => "snapshot"},
               Ipse.Usage.id()
             )

    assert after_snapshot["generation"] == snapshot["generation"]

    assert {:ok, %{"record" => retained}} =
             Ipse.Extension.Collection.execute(
               collection,
               pin["namespace"],
               %{"op" => "get", "key" => ordinary["key"]},
               Ipse.Usage.id()
             )

    assert retained == ordinary
    assert :ok = Ipse.Session.ManagedSupersession.validate_events(events, id)
    assert {:ok, _} = Ipse.Session.Saved.restore(events, id)

    if scenario == "revoke" do
      altered =
        Enum.map(events, fn event ->
          if event === result, do: Map.put(event, "outcome", %{}), else: event
        end)

      assert {:error, :managed_supersession_refused} =
               Ipse.Session.ManagedSupersession.validate_events(altered, id)
    end

    assert :ok = Ipse.Session.close_confirmed(session)
    refute File.exists?(Path.join(root, "unexpected-model"))
    IO.puts("MANAGED_SUPERSESSION_#{String.upcase(scenario)}_PASSED")
  end
end
