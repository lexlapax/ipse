ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
[root, scenario] = System.argv()

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

intake = fn active, active_channel, active_id, command, step, expected ->
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
    {:ipse, ^active, {:done, ^expected}} ->
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

ordinary = Enum.find(page["records"], &(&1["value"]["category"] == "ordinary"))
current = Enum.find(page["records"], &(&1["value"]["category"] == "current"))

if scenario in ~w(current terminal) do
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
      3,
      :ok
    )

    intake.(
      session,
      channel,
      id,
      "/supersede " <> current["key"] <> " My fixture timezone is Europe/Berlin",
      4,
      :ok
    )
  end

  assert {:ok, events} = Ipse.Journal.load(dir, id)
  count = if scenario == "terminal", do: 1, else: 2
  assert length(Enum.filter(events, &(&1["type"] == "operator_assertion"))) == count + 2
  assert length(Enum.filter(events, &(&1["type"] == "managed_supersession_prepared"))) == count
  assert length(Enum.filter(events, &(&1["type"] == "managed_supersession_review"))) == count
  results = Enum.filter(events, &(&1["type"] == "managed_supersession_result"))
  assert length(results) == count and Enum.all?(results, &(&1["status"] == "settled"))
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
  assert :ok = Ipse.Session.close_confirmed(session)

  assert {:ok, resumed} =
           DynamicSupervisor.start_child(
             Ipse.Sessions,
             {Ipse.Session, Keyword.put(opts, :id, id)}
           )

  assert Ipse.Session.info(resumed).phase == :idle
  assert :ok = Ipse.Session.close_confirmed(resumed)
  assert {:ok, ^events} = Ipse.Journal.load(dir, id)

  if scenario == "current" do
    Code.require_file("managed_history_use.exs", __DIR__)
    Ipse.Test.ManagedHistoryUse.run(config, opts, cwd, home, dir, current)
  end

  IO.puts(
    if scenario == "terminal",
      do: "MANAGED_SUPERSESSION_TERMINAL_PASSED",
      else: "MANAGED_SUPERSESSION_SESSION_PASSED"
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
    refute Enum.any?(events, &(&1["type"] == "managed_supersession_review"))

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
    assert :ok = Ipse.Session.close_confirmed(session)
    refute File.exists?(Path.join(root, "unexpected-model"))
    IO.puts("MANAGED_SUPERSESSION_#{String.upcase(scenario)}_PASSED")
  end
end
