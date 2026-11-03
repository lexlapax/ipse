ExUnit.start(autorun: false)
import ExUnit.Assertions
alias Ipse.{Journal, JSON, Session}
alias Ipse.Extension.{Consent, ProjectIdentity, SemanticAdmission}
alias Ipse.Extension.Collection.ObservedRead

{:ok, _} = Application.ensure_all_started(:ipse)
[root, day_arg] = System.argv()
day = if day_arg == "expired", do: 386, else: String.to_integer(day_arg)
assert day in [364, 386]
Code.require_file("managed_clock_lifecycle.exs", __DIR__)
Ipse.Test.ManagedClockLifecycle.check_stdio_clock(root)

for key <- ~w(IPSE_PROVIDER IPSE_MODEL IPSE_CONFIG IPSE_PROFILE IPSE_SANDBOX IPSE_SUBAGENTS),
    do: System.delete_env(key)

defmodule ClockRenewalUnexpectedModel do
  def complete(config, _, _, _) do
    File.write!(Path.join(config.fixture_root, "unexpected-model"), "called", [:exclusive])
    raise "native renewal must not invoke a model"
  end
end

home = Path.join(root, "home")
cwd = Path.join(root, "work")
seed = root |> Path.join("clock-late-seed.json") |> File.read!() |> Jason.decode!()
source = Path.join([home, "sessions", seed["session_id"] <> ".jsonl"])
assert JSON.sha256(File.read!(source)) == seed["source_sha256"]

assert {:ok, %{"release_claim" => "signed_release_claim"}} =
         Session.Saved.inspect_saved(Path.join(home, "sessions"), seed["session_id"])

assert {:ok, binding} = ProjectIdentity.existing(home, cwd)
assert binding === seed["binding"]
control_root = SemanticAdmission.control_root(home)
assert {:ok, before} = Consent.existing_snapshot(control_root, binding["project_id"])
now = System.system_time(:millisecond)
assert now >= seed["seed_wall_ms"] + day * 86_400_000
assert now < seed["seed_wall_ms"] + (day + 1) * 86_400_000

if day_arg == "expired" do
  assert now > before["policy"]["expires_at_ms"]
  caller = self()

  assert {:error, :consent_read_refused} =
           Consent.with_policy(
             control_root,
             binding["project_id"],
             before["epoch"],
             JSON.digest([before["policy"]]),
             now,
             fn _ ->
               send(caller, :expired_policy_callback)
               {:ok, :unexpected}
             end
           )

  refute_received :expired_policy_callback
  assert {:ok, unchanged} = Consent.existing_snapshot(control_root, binding["project_id"])
  assert unchanged === before
else
  if day == 364 do
    assert now < before["policy"]["expires_at_ms"]

    assert Ipse.CLI.run([
             "knowledge",
             "enable",
             "--cwd",
             cwd,
             "--config",
             Path.join(home, "config.json"),
             "--no-project-config"
           ]) == 0

    assert {:ok, after_renewal} = Consent.existing_snapshot(control_root, binding["project_id"])
    assert after_renewal["epoch"] == before["epoch"] + 1
    assert after_renewal["policy"]["expires_at_ms"] > before["policy"]["expires_at_ms"]

    report = %{
      "old_epoch" => before["epoch"],
      "new_epoch" => after_renewal["epoch"],
      "old_expiry_ms" => before["policy"]["expires_at_ms"],
      "new_expiry_ms" => after_renewal["policy"]["expires_at_ms"],
      "source_sha256" => seed["source_sha256"]
    }

    File.write!(Path.join(root, "clock-renewal-364.json"), Jason.encode!(report), [:exclusive])
  else
    renewal = root |> Path.join("clock-renewal-364.json") |> File.read!() |> Jason.decode!()
    assert now > renewal["old_expiry_ms"] and now < renewal["new_expiry_ms"]
    assert before["epoch"] == renewal["new_epoch"]

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
             Ipse.Config.resolve(
               cwd,
               home,
               [config: Path.join(home, "config.json"), project_config: false],
               %{}
             )

    assert {:ok, config} = Ipse.Config.runtime(effective, client)

    config =
      Map.merge(config, %{provider_module: ClockRenewalUnexpectedModel, fixture_root: root})

    dir = Path.join(home, "sessions")
    opts = [config: config, cwd: cwd, state_dir: dir, subscriber: self()]
    assert {:ok, session} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts})
    id = Session.info(session).id
    assert {:ok, channel} = Session.open_input_channel(session, self())
    command = "/remember ordinary A fresh statement after the original permission expired"
    File.write!(Path.join(root, "supersession-input-1"), command)
    IO.write("IPSE_SUPERSESSION_READ_1> ")

    assert {:ok, ^command, witness} =
             Session.observe_channel(session, channel, %{"kind" => "prompt"}, 30_000)

    assert {:ok, ticket} = Session.stage_input(session, channel, command, witness)

    assert {:ok, %{"render_id" => render}} =
             Session.prepare_assertion(session, channel, command, ticket)

    assert {:ok, input, observed} =
             Session.observe_channel(
               session,
               channel,
               %{"kind" => "assertion", "render_id" => render},
               30_000
             )

    assert :ok = Session.accept_assertion_observed(session, channel, render, input, observed)
    assert_receive {:ipse, ^session, {:done, :ok}}, 30_000
    assert :ok = Session.close_confirmed(session)
    assert {:ok, events} = Journal.load(dir, id)
    assert {:ok, _} = Session.Saved.restore(events, id)

    assert {:ok, %{"release_claim" => "signed_release_claim"}} =
             Session.Saved.inspect_saved(dir, id)

    assert [capture] =
             Enum.filter(events, fn event ->
               event["type"] == "extension_action_result" and
                 get_in(event, ["request", "op"]) == "collection.managed" and
                 get_in(event, ["outcome", "status"]) == "ok"
             end)

    assert [change] = capture["request"]["request"]["changes"]
    assert change["value"]["text"] == "A fresh statement after the original permission expired"
    assert change["value"]["category"] == "ordinary"

    assert {:ok, after_capture} = Consent.existing_snapshot(control_root, binding["project_id"])
    assert after_capture["epoch"] == before["epoch"]

    assert [operation_id] =
             Map.keys(after_capture["operations"]) -- Map.keys(before["operations"])

    operation = after_capture["operations"][operation_id]
    assert operation["status"] == "settled"
    assert operation["actual"]["operations"] == 1
    assert operation["actual"]["model_calls"] == 0

    refute Enum.any?(events, &(&1["type"] in ~w(request_admitted inference_dispatch_intent)))

    assert {:ok, old} =
             ProjectIdentity.with_existing_domain_auth(
               home,
               cwd,
               binding,
               %{namespace: seed["namespace"], format: "managed-metadata-v3"},
               fn cap, catalog ->
                 ObservedRead.managed_record(
                   SemanticAdmission.collection_root(home),
                   seed["namespace"],
                   %{"op" => "get_record", "key" => seed["current"]["key"]},
                   cap,
                   catalog,
                   seed["recipe"]
                 )
               end
             )

    assert old["observation"]["value"]["record"]["value"] === seed["current"]["value"]
    assert JSON.sha256(File.read!(source)) == seed["source_sha256"]

    report = %{
      "at_ms" => now,
      "source_sha256" => seed["source_sha256"],
      "capture_settled" => true,
      "annual_workload_qualification" => false
    }

    File.write!(Path.join(root, "clock-renewal-386.json"), Jason.encode!(report), [:exclusive])
  end
end

assert JSON.sha256(File.read!(source)) == seed["source_sha256"]

assert {:ok, %{"release_claim" => "signed_release_claim"}} =
         Session.Saved.inspect_saved(Path.join(home, "sessions"), seed["session_id"])

IO.puts("NATIVE_CLOCK_RENEWAL_PASSED=#{day}")
