ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("provider_fixture.ex", __DIR__)

for key <-
      ~w(IPSE_PROVIDER IPSE_MODEL IPSE_SANDBOX IPSE_MAX_STEPS IPSE_CONTEXT_BYTES IPSE_COMPACT IPSE_SUBAGENTS IPSE_SUBAGENT_CONCURRENCY IPSE_TIMEOUT_MS IPSE_MAX_OUTPUT_TOKENS IPSE_PROFILE IPSE_CONFIG),
    do: System.delete_env(key)

[root, scenario] = System.argv()
preflight_expiry? = scenario == "save_managed_approval_root_shadow_expiry"
release_expiry? = scenario == "save_managed_approval_root_shadow_release_expiry"
expiry? = preflight_expiry? or release_expiry?
denied? = scenario == "save_managed_approval_deny"
revoked? = scenario == "save_managed_approval_revoked_grant"
low_confidence? = scenario == "save_managed_approval_low_confidence"
deferred? = scenario == "save_managed_approval_defer_candidate"
output_source_lost? = scenario == "save_managed_approval_output_source_lost"
output_revoked? = scenario == "save_managed_approval_output_revoked"
pending_deadline_seed? = scenario == "save_managed_approval_pending_deadline_seed"
pending_deadline_expired? = scenario == "save_managed_approval_pending_deadline_expired"
input_source_lost? = scenario == "save_managed_approval_input_source_lost"
unknown? = scenario == "save_managed_approval_unknown"
mixed? = scenario == "save_managed_approval_mixed_v4_v7"
evaluation_seed? = scenario == "save_managed_approval_candidate_evaluation_seed"
home = Path.join(root, "home")
cwd = Path.join(root, "project")
dir = Path.join(root, "sessions")
File.mkdir_p!(home)
File.mkdir_p!(cwd)
File.chmod!(home, 0o700)

if pending_deadline_seed? or pending_deadline_expired? do
  File.mkdir_p!(Path.join(root, "work"))
  Code.require_file("managed_clock_lifecycle.exs", __DIR__)
  Ipse.Test.ManagedClockLifecycle.check_stdio_clock(root)
end

File.write!(Path.join(cwd, "synthetic.txt"), "Synthetic local observation.\n")
System.put_env("IPSE_HOME", home)

{:ok, listener} =
  :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

{:ok, {_, port}} = :inet.sockname(listener)
base = "http://127.0.0.1:#{port}"
{:ok, calls} = Agent.start_link(fn -> [] end)

deadline_seed =
  if pending_deadline_expired?,
    do: root |> Path.join("pending-deadline-seed.json") |> File.read!() |> Jason.decode!()

{:ok, assessed_key} = Agent.start_link(fn -> if deadline_seed, do: deadline_seed["key"] end)

server =
  Task.async(fn ->
    loop = fn loop, step ->
      case :gen_tcp.accept(listener, 30_000) do
        {:ok, socket} ->
          {headers, bytes} = Ipse.Test.ProviderFixture.request(socket, "")
          request = Jason.decode!(bytes)
          decision? = String.starts_with?(headers, "POST /systemone ")
          Agent.update(calls, &(&1 ++ [{if(decision?, do: :decision, else: :main), request}]))

          {response, next} =
            if decision? do
              probability = if low_confidence?, do: 0.6, else: 0.9
              choice = if deferred?, do: "defer_candidate", else: "keep_baseline"

              {%{
                 "model" => "synthetic",
                 "answers" => %{
                   "candidate" => %{
                     "type" => "choice",
                     "choice" => choice,
                     "confidence" => probability,
                     "probabilities" => %{
                       "keep_baseline" => if(deferred?, do: 1 - probability, else: probability),
                       "defer_candidate" => if(deferred?, do: probability, else: 1 - probability)
                     }
                   }
                 },
                 "usage" => %{"input_tokens" => 10, "output_tokens" => 2}
               }, step}
            else
              messages = request["messages"]

              tool = fn name ->
                Enum.find(
                  Enum.reverse(messages),
                  &(&1["role"] == "tool" and &1["tool_name"] == name)
                )
              end

              action =
                case step do
                  0 ->
                    {"read", %{"path" => "synthetic.txt"}}

                  1 ->
                    {"source_list", %{"limit" => 32}}

                  2 ->
                    page = tool.("source_list")["content"] |> Jason.decode!()

                    source =
                      Enum.find(
                        Enum.reverse(page["sources"]),
                        &(&1["kind"] == "tool.outcome" and &1["origin"] == "typed_host_outcome")
                      )

                    {"source_read", %{"handle" => source["read_handle"]}}

                  3 ->
                    page = tool.("source_read")["content"] |> Jason.decode!()

                    {"ext__knowledge__capture",
                     %{
                       "text" => "Synthetic proposed interpretation of the local observation.",
                       "category" => "ordinary",
                       "reason" => "fixture host outcome",
                       "event_at_ms" => nil,
                       "source" => %{"handle" => page["handle"], "quote" => page["text"]}
                     }}

                  _ ->
                    key = Agent.get(assessed_key, & &1)

                    if is_binary(key) and is_nil(tool.("ext__knowledge__assess")),
                      do: {"ext__knowledge__assess", %{"key" => key}},
                      else: nil
                end

              message =
                if action,
                  do: %{
                    "role" => "assistant",
                    "content" => "",
                    "tool_calls" => [
                      %{
                        "function" => %{"name" => elem(action, 0), "arguments" => elem(action, 1)}
                      }
                    ]
                  },
                  else: %{"role" => "assistant", "content" => "Fixture finished."}

              {%{
                 "model" => "synthetic",
                 "message" => message,
                 "done" => true,
                 "prompt_eval_count" => 1,
                 "eval_count" => 1
               }, step + 1}
            end

          body =
            if decision? and unknown?,
              do: "{invalid",
              else: Jason.encode!(response) <> if(decision?, do: "", else: "\n")

          :ok =
            :gen_tcp.send(
              socket,
              "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                body
            )

          :gen_tcp.close(socket)
          loop.(loop, next)

        _ ->
          :ok
      end
    end

    loop.(loop, if(pending_deadline_expired?, do: 4, else: 0))
  end)

config_path = Path.join(home, "config.json")
service_id = if pending_deadline_expired?, do: "fixture_day8", else: "fixture"

config = %{
  "version" => 1,
  "profiles" => %{
    "main" => %{
      "provider" => "ollama",
      "model" => "synthetic",
      "base_url" => base,
      "max_output_tokens" => 64,
      "timeout_ms" => 90_000
    }
  },
  "roles" => %{"main" => "main"},
  "decision_profiles" => %{
    "advice" => %{
      "operation" => "decision",
      "provider" => "system_one_compatible",
      "model" => "synthetic",
      "service_id" => service_id,
      "base_url" => base,
      "timeout_ms" => 3000
    }
  },
  "inference_services" => %{service_id => %{"version" => 1, "origins" => [base]}}
}

File.write!(config_path, Jason.encode!(config))
File.chmod!(config_path, 0o600)
duration = if expiry?, do: "35", else: "120"

assert 0 ==
         Ipse.CLI.run([
           "knowledge",
           "experiment",
           "advice",
           "1",
           duration,
           "--cwd",
           cwd,
           "--config",
           config_path,
           "--no-project-config"
         ])

{:ok, binding} = Ipse.Extension.ProjectIdentity.existing(home, cwd)
control = Ipse.Extension.SemanticAdmission.control_root(home)
{:ok, snapshot} = Ipse.Extension.Consent.existing_snapshot(control, binding["project_id"])
expires = snapshot["policy"]["expires_at_ms"]
assert snapshot["policy"]["limits"]["model_calls"] == 1

{:ok, effective} =
  Ipse.Config.resolve(cwd, home, [config: config_path, project_config: false], %{})

client = %{
  workspace: cwd,
  home: home,
  auth_dir: Path.join(home, "auth"),
  operator_home: root,
  mcp_config: nil,
  base_url: nil,
  operator_questions: false,
  accept_edits: false,
  approval: :ask,
  approval_origin: :interactive,
  headless: false
}

{:ok, runtime} = Ipse.Config.runtime(effective, client)

if pending_deadline_expired? do
  alias Ipse.Extension.{Collection, ProjectIdentity, SemanticAdmission}
  alias Ipse.Extension.Collection.ObservedRead
  alias Ipse.Session.{ManagedReference, Saved}
  now = System.system_time(:millisecond)
  assert now >= deadline_seed["seed_wall_ms"] + 8 * 86_400_000
  assert now < deadline_seed["seed_wall_ms"] + 9 * 86_400_000
  assert now > deadline_seed["valid_until_ms"]
  assert snapshot["policy"]["expires_at_ms"] > now
  source_path = Path.join(dir, deadline_seed["source_session_id"] <> ".jsonl")
  source_stat = File.stat!(source_path)
  assert source_stat.inode == deadline_seed["source_inode"]
  assert source_stat.major_device == deadline_seed["source_device"]
  assert Ipse.JSON.sha256(File.read!(source_path)) == deadline_seed["source_sha256"]
  assert {:ok, source_events} = Ipse.Journal.load(dir, deadline_seed["source_session_id"])
  assert {:ok, _} = Saved.restore(source_events, deadline_seed["source_session_id"])

  {:ok, consumer} =
    DynamicSupervisor.start_child(
      Ipse.Sessions,
      {Ipse.Session, config: runtime, cwd: cwd, state_dir: dir, subscriber: self()}
    )

  id = Ipse.Session.info(consumer).id
  state = :sys.get_state(consumer)
  admission = state.config.semantic_admission
  assert admission["status"] == "active"
  pin = admission["pin"]
  assert pin["namespace"] == deadline_seed["namespace"]

  {_, recipe} =
    Enum.find(admission["policy"]["settings"]["recipes"], fn {_, r} ->
      r["kind"] == "proposal" and r["key_prefix"] == "pending."
    end)

  request = %{"op" => "get_record", "key" => deadline_seed["key"]}
  collection = SemanticAdmission.collection_root(home)

  assert {:ok, before} =
           Collection.execute(
             collection,
             pin["namespace"],
             %{"op" => "snapshot"},
             Ipse.Usage.id()
           )

  # The signed record is still authentic. This pure comparison isolates its
  # deadline predicate; its constructed dependency grants no live authority.
  assert {:ok, :deadline_is_the_difference} =
           ProjectIdentity.with_existing_domain_auth(
             home,
             cwd,
             binding,
             %{namespace: pin["namespace"], format: "managed-metadata-v3"},
             fn cap, catalog ->
               assert {:ok, managed} =
                        ObservedRead.managed_proposal(
                          collection,
                          pin["namespace"],
                          request,
                          cap,
                          catalog,
                          recipe
                        )

               assert managed["observation"]["value"]["record"] == deadline_seed["record"]
               assert managed["metadata"]["valid_until_ms"] == deadline_seed["valid_until_ms"]
               proofs = get_in(deadline_seed, ["record", "value", "evidence", "sources"])

               assert {:ok, prior_shape} =
                        ObservedRead.proposal_dependency(
                          request,
                          managed,
                          pin,
                          recipe,
                          proofs,
                          deadline_seed["valid_until_ms"] - 1
                        )

               assert ManagedReference.dependency?(prior_shape)

               assert {:error, _} =
                        ObservedRead.proposal_dependency(
                          request,
                          managed,
                          pin,
                          recipe,
                          proofs,
                          now
                        )

               {:ok, :deadline_is_the_difference}
             end
           )

  assert :ok =
           Ipse.Session.prompt(
             consumer,
             "Assess the previously saved synthetic note " <> deadline_seed["key"] <> "."
           )

  assert_receive {:ipse, ^consumer, {:done, _}}, 20_000
  assert {:ok, events} = Ipse.Journal.load(dir, id)

  assert [read] =
           Enum.filter(
             events,
             &(get_in(&1, ["request", "purpose"]) == "decision_shadow_pending_v1" and
                 &1["type"] == "extension_action_result")
           )

  assert read["outcome"] == %{
           "status" => "failed",
           "value" => %{"code" => "collection_source_refused"}
         }

  refute Enum.any?(events, fn event ->
           event["type"] == "managed_read_observed" and
             Enum.any?(event["dependencies"] || [], &(&1["version"] == 7))
         end)

  refute Enum.any?(
           events,
           &(get_in(&1, ["request", "op"]) in ["decision.create", "collection.managed"])
         )

  refute Enum.any?(Agent.get(calls, & &1), &(elem(&1, 0) == :decision))
  assert {:ok, final} = Ipse.Extension.Consent.existing_snapshot(control, binding["project_id"])
  assert final["policy"] == snapshot["policy"]
  refute Enum.any?(final["operations"], fn {_, op} -> op["reserved"]["model_calls"] > 0 end)

  assert {:ok, ^before} =
           Collection.execute(
             collection,
             pin["namespace"],
             %{"op" => "snapshot"},
             Ipse.Usage.id()
           )

  assert {:ok, %{"record" => record}} =
           Collection.execute(
             collection,
             pin["namespace"],
             %{"op" => "get", "key" => deadline_seed["key"]},
             Ipse.Usage.id()
           )

  assert record == deadline_seed["record"]
  assert {:ok, _} = Saved.restore(events, id)
  assert :ok = Ipse.Session.close_confirmed(consumer)
  calls_before = Agent.get(calls, & &1)

  assert {:ok, resumed} =
           DynamicSupervisor.start_child(
             Ipse.Sessions,
             {Ipse.Session, config: runtime, cwd: cwd, state_dir: dir, subscriber: self(), id: id}
           )

  assert Ipse.Session.info(resumed).phase == :idle
  assert Agent.get(calls, & &1) == calls_before
  assert :ok = Ipse.Session.close_confirmed(resumed)
  assert Ipse.JSON.sha256(File.read!(source_path)) == deadline_seed["source_sha256"]
  assert File.stat!(source_path).inode == deadline_seed["source_inode"]
  :gen_tcp.close(listener)
  Task.shutdown(server, :brutal_kill)
  IO.puts("PENDING_PROPOSAL_OWN_DEADLINE_EXPIRED_PASSED")
  System.halt(0)
end

# This separate scenario creates a literal through the real native assertion
# channel so a later protected input can include both v4 and v7 source owners.
mixed_literal =
  if mixed? do
    {:ok, literal_session} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Ipse.Session, config: runtime, cwd: cwd, state_dir: dir, subscriber: self()}
      )

    literal_id = Ipse.Session.info(literal_session).id
    assert {:ok, channel} = Ipse.Session.open_input_channel(literal_session, self())
    command = "/remember ordinary Synthetic mixed-version literal."
    File.write!(Path.join(root, "supersession-input-1"), command)
    IO.write("IPSE_SUPERSESSION_READ_1> ")

    assert {:ok, ^command, witness} =
             Ipse.Session.observe_channel(literal_session, channel, %{"kind" => "prompt"}, 30_000)

    assert {:ok, ticket} = Ipse.Session.stage_input(literal_session, channel, command, witness)

    assert {:ok, %{"render_id" => render}} =
             Ipse.Session.prepare_assertion(literal_session, channel, command, ticket)

    assert {:ok, answer, answer_witness} =
             Ipse.Session.observe_channel(
               literal_session,
               channel,
               %{"kind" => "assertion", "render_id" => render},
               30_000
             )

    assert :ok =
             Ipse.Session.accept_assertion_observed(
               literal_session,
               channel,
               render,
               answer,
               answer_witness
             )

    assert_receive {:ipse, ^literal_session, {:done, :ok}}, 15_000
    assert {:ok, literal_events} = Ipse.Journal.load(dir, literal_id)

    assert [write] =
             Enum.filter(literal_events, fn event ->
               event["type"] == "extension_action_result" and
                 get_in(event, ["request", "op"]) == "collection.managed" and
                 get_in(event, ["outcome", "status"]) == "ok"
             end)

    assert [%{"key" => literal_key}] = get_in(write, ["request", "request", "changes"])
    assert String.starts_with?(literal_key, "note.")
    assert :ok = Ipse.Session.close_confirmed(literal_session)
    %{key: literal_key, session_id: literal_id}
  end

# Capture a proposal through the actual main tool in a separate Session. The
# proposal's source quote is real, but its paraphrased text must stay pending.
seed_runtime = %{runtime | approval: :deny, approval_origin: :default_headless, headless: true}

{:ok, seed} =
  DynamicSupervisor.start_child(
    Ipse.Sessions,
    {Ipse.Session, config: seed_runtime, cwd: cwd, state_dir: dir, subscriber: self()}
  )

seed_id = Ipse.Session.info(seed).id
assert :ok = Ipse.Session.prompt(seed, "Capture the actual local tool outcome.")
assert_receive {:ipse, ^seed, {:done, :ok}}, 20_000
{:ok, seed_events} = Ipse.Journal.load(dir, seed_id)

assert [seed_write] =
         Enum.filter(seed_events, fn event ->
           event["type"] == "extension_action_result" and
             get_in(event, ["request", "op"]) == "collection.managed" and
             get_in(event, ["outcome", "status"]) == "ok"
         end)

[%{"key" => key, "value" => proposed}] = get_in(seed_write, ["request", "request", "changes"])
assert String.starts_with?(key, "pending.")
assert proposed["kind"] == "proposal" and proposed["state"] == "pending"
assert proposed["text"] == "Synthetic proposed interpretation of the local observation."
namespace = :sys.get_state(seed).config.semantic_admission["pin"]["namespace"]
Agent.update(assessed_key, fn _ -> key end)
refute Enum.any?(Agent.get(calls, & &1), &(elem(&1, 0) == :decision))
assert :ok = Ipse.Session.close_confirmed(seed)

if evaluation_seed? do
  Code.require_file("../../dev/evaluation/candidate_assessment_recipe.exs", __DIR__)

  Ipse.Development.Evaluation.CandidateAssessmentRecipe.freeze(
    root,
    runtime,
    seed_id,
    key,
    seed_write["operation_id"],
    config_path,
    base
  )

  assert Enum.count(Agent.get(calls, & &1), &(elem(&1, 0) === :main)) === 5
  refute Enum.any?(Agent.get(calls, & &1), &(elem(&1, 0) === :decision))
  :gen_tcp.close(listener)
  Task.shutdown(server, :brutal_kill)
  IO.puts("CANDIDATE_ASSESSMENT_SEED_FROZEN")
  System.halt(0)
end

if pending_deadline_seed? do
  collection = Ipse.Extension.SemanticAdmission.collection_root(home)

  assert {:ok, %{"record" => record}} =
           Ipse.Extension.Collection.execute(
             collection,
             namespace,
             %{"op" => "get", "key" => key},
             Ipse.Usage.id()
           )

  normalization = get_in(seed_write, ["outcome", "value", "normalization"])
  assert normalization["eligibility"] == "never_current"
  assert normalization["valid_until_ms"] - normalization["first_admitted_ms"] == 7 * 86_400_000
  source_path = Path.join(dir, seed_id <> ".jsonl")
  stat = File.stat!(source_path)

  manifest = %{
    "version" => 1,
    "key" => key,
    "namespace" => namespace,
    "source_session_id" => seed_id,
    "source_inode" => stat.inode,
    "source_device" => stat.major_device,
    "source_sha256" => Ipse.JSON.sha256(File.read!(source_path)),
    "seed_wall_ms" => System.system_time(:millisecond),
    "record" => record,
    "valid_until_ms" => normalization["valid_until_ms"]
  }

  path = Path.join(root, "pending-deadline-seed.json")
  File.write!(path, Jason.encode!(manifest), [:exclusive])
  File.chmod!(path, 0o600)
  :gen_tcp.close(listener)
  Task.shutdown(server, :brutal_kill)
  IO.puts("PENDING_PROPOSAL_OWN_DEADLINE_SEED_PASSED")
  System.halt(0)
end

collection = Ipse.Extension.SemanticAdmission.collection_root(home)

assert {:ok, before_assessment} =
         Ipse.Extension.Collection.execute(
           collection,
           namespace,
           %{"op" => "snapshot"},
           Ipse.Usage.id()
         )

# This trusted test-side read compares the stored record, including revision;
# it is not a Worker read grant.
before_pending =
  if deferred? do
    assert {:ok, %{"record" => record}} =
             Ipse.Extension.Collection.execute(
               collection,
               namespace,
               %{"op" => "get", "key" => key},
               Ipse.Usage.id()
             )

    assert record["key"] == key
    assert record["value"]["id"] == proposed["id"]
    assert record["value"]["text"] == proposed["text"]
    assert record["value"]["state"] == "pending"
    record
  end

if revoked? do
  {:ok, current} = Ipse.Extension.Consent.existing_snapshot(control, binding["project_id"])

  assert {:ok, _} =
           Ipse.Extension.Consent.revoke(control, binding["project_id"], current["epoch"])
end

{:ok, pid} =
  DynamicSupervisor.start_child(
    Ipse.Sessions,
    {Ipse.Session, config: runtime, cwd: cwd, state_dir: dir, subscriber: self()}
  )

id = Ipse.Session.info(pid).id

if revoked? do
  state = :sys.get_state(pid)
  refute get_in(state.config, [:semantic_admission, "status"]) == "active"

  assert :ok =
           Ipse.Session.prompt(pid, "Assess the previously saved synthetic note " <> key <> ".")

  assert_receive {:ipse, ^pid, {:done, _}}, 20_000
  {:ok, events} = Ipse.Journal.load(dir, id)
  refute Enum.any?(events, &(get_in(&1, ["request", "op"]) == "decision.create"))
  refute Enum.any?(Agent.get(calls, & &1), &(elem(&1, 0) == :decision))
  {:ok, final} = Ipse.Extension.Consent.existing_snapshot(control, binding["project_id"])
  assert is_nil(final["policy"])

  refute Enum.any?(final["operations"], fn {_, operation} ->
           operation["reserved"]["model_calls"] > 0
         end)

  assert :ok = Ipse.Session.close_confirmed(pid)
  :gen_tcp.close(listener)
  Task.shutdown(server, :brutal_kill)
  IO.puts("SHADOW_EXPERIMENT_SESSION_PASSED")
  System.halt(0)
end

wait_file = fn wait_file, path, remaining ->
  if File.exists?(path),
    do: :ok,
    else:
      (
        assert remaining > 0
        Process.sleep(10)
        wait_file.(wait_file, path, remaining - 1)
      )
end

{:ok, _watcher} =
  Task.start_link(fn ->
    wait_file.(wait_file, Path.join(root, "managed-approval-input-ready"), 1500)
    assert :sys.get_state(pid).phase == :managed_approval

    if expiry? or output_source_lost? or input_source_lost? or output_revoked? do
      watcher = self()

      hook = fn
        count, {:in, {:"$gen_call", _, {:managed_preflight_begin, _, "decision.create"}}}, _
        when preflight_expiry? or input_source_lost? ->
          send(watcher, {:shadow_wire_blocked, self()})
          receive do: (:release_shadow_wire -> :ok)
          count + 1

        count, {:in, {:"$gen_call", _, {:managed_result_admit, _, "decision.create", _, _, _}}}, _
        when release_expiry? ->
          send(watcher, {:shadow_wire_blocked, self()})
          receive do: (:release_shadow_wire -> :ok)
          count + 1

        count,
        {:in,
         {:"$gen_call", _,
          {:managed_output_prepare, _, :inline,
           %{"value" => %{"status" => "assessed", "key" => ^key, "experimental" => true}}}}},
        _
        when output_source_lost? or output_revoked? ->
          send(watcher, {:shadow_output_blocked, self()})
          receive do: (:release_shadow_output -> :ok)
          count + 1

        count, _, _ ->
          count
      end

      assert :ok = :sys.install(pid, {hook, 0})

      if expiry? do
        delay = max(expires - System.system_time(:millisecond) - 4_000, 0)
        Process.sleep(delay)
      end
    end

    File.write!(Path.join(root, "managed-approval-control-checked"), "checked")

    if expiry? do
      assert_receive {:shadow_wire_blocked, ^pid}, 4_000
      Process.sleep(max(expires - System.system_time(:millisecond) + 50, 0))
      send(pid, :release_shadow_wire)
    end

    idle = fn idle, remaining ->
      if :sys.get_state(pid).phase == :idle,
        do: :ok,
        else:
          (
            assert remaining > 0
            Process.sleep(10)
            idle.(idle, remaining - 1)
          )
    end

    if input_source_lost? do
      assert_receive {:shadow_wire_blocked, ^pid}, 20_000
      journal = Path.join(dir, seed_id <> ".jsonl")
      held = journal <> ".input-source-held"
      before = File.stat!(journal)
      digest = Ipse.JSON.sha256(File.read!(journal))
      refute File.exists?(held)
      File.rename!(journal, held)

      try do
        refute File.exists?(journal)
        send(pid, :release_shadow_wire)
        idle.(idle, 2000)
      after
        if File.exists?(held) and not File.exists?(journal), do: File.rename!(held, journal)
      end

      restored = File.stat!(journal)
      assert restored.major_device == before.major_device and restored.inode == before.inode
      assert Ipse.JSON.sha256(File.read!(journal)) == digest
    else
      if output_source_lost? or output_revoked? do
        assert_receive {:shadow_output_blocked, ^pid}, 40_000
        assert length(Enum.filter(Agent.get(calls, & &1), &(elem(&1, 0) == :decision))) == 1

        if output_revoked? do
          assert {:ok, admitted} =
                   Ipse.Extension.Consent.existing_snapshot(control, binding["project_id"])

          assert Enum.any?(admitted["operations"], fn {_, op} ->
                   op["status"] == "settled" and op["actual"]["model_calls"] == 1
                 end)

          assert {:ok, _} =
                   Ipse.Extension.Consent.revoke(
                     control,
                     binding["project_id"],
                     admitted["epoch"]
                   )

          send(pid, :release_shadow_output)
          idle.(idle, 2000)
        else
          journal = Path.join(dir, seed_id <> ".jsonl")
          held = journal <> ".output-source-held"
          before = File.stat!(journal)
          digest = Ipse.JSON.sha256(File.read!(journal))
          refute File.exists?(held)
          File.rename!(journal, held)

          try do
            refute File.exists?(journal)
            send(pid, :release_shadow_output)
            idle.(idle, 2000)
          after
            if File.exists?(held) and not File.exists?(journal), do: File.rename!(held, journal)
          end

          restored = File.stat!(journal)
          assert restored.major_device == before.major_device and restored.inode == before.inode
          assert Ipse.JSON.sha256(File.read!(journal)) == digest
        end
      else
        idle.(idle, 2000)
      end
    end

    File.write!(Path.join(root, "managed-approval-exit-ready"), "ready")
  end)

IO.puts("IPSE_MANAGED_APPROVAL_CLI_READY")

assert 0 ==
         Ipse.CLI.Terminal.interact(
           pid,
           Process.monitor(pid),
           true,
           "Assess the previously saved synthetic note " <> key <> ".",
           cwd
         )

{:ok, events} = Ipse.Journal.load(dir, id)
decisions = Enum.filter(Agent.get(calls, & &1), &(elem(&1, 0) == :decision))
assert length(decisions) == if(preflight_expiry? or denied? or input_source_lost?, do: 0, else: 1)

if decisions != [] do
  [{:decision, decision}] = decisions

  assert %{"candidates" => [%{"id" => "candidate", "input" => input}]} =
           Jason.decode!(decision["state"])

  assert Jason.decode!(input) == %{
           "candidate_id" => proposed["id"],
           "text" => proposed["text"],
           "assigned_category" => proposed["assigned_category"],
           "reason" => proposed["reason"]
         }
end

assert [pending_read] =
         Enum.filter(events, fn event ->
           event["type"] == "managed_read_observed" and
             Enum.any?(event["dependencies"] || [], &(&1["version"] == 7))
         end)

assert [dependency] = pending_read["dependencies"]
assert dependency["subject"]["key"] == key
assert dependency["subject"]["validity"]["status"] == "never_current"
assert pending_read["classification"]["kind"] == "bundled_decision_shadow"

if mixed? do
  alias Ipse.Extension.ProjectIdentity
  alias Ipse.Extension.Collection.ObservedRead
  alias Ipse.Session.{ManagedReference, ManagedUse}
  state = :sys.get_state(pid)
  context = %{config: state.config, cwd: cwd, session_id: id, history_dir: dir}
  pin = state.config.semantic_admission["pin"]
  settings = state.config.semantic_admission["policy"]["settings"]

  {_, recipe} =
    Enum.find(settings["recipes"], fn {_, recipe} -> recipe["kind"] == "literal_source" end)

  request = %{"op" => "get_record", "key" => mixed_literal.key}
  domain = %{namespace: namespace, format: "managed-metadata-v3"}

  assert {:ok, literal_dependency} =
           ProjectIdentity.with_existing_domain_auth(home, cwd, binding, domain, fn cap,
                                                                                    catalog ->
             with {:ok, managed} <-
                    ObservedRead.managed_record(
                      collection,
                      namespace,
                      request,
                      cap,
                      catalog,
                      recipe
                    ),
                  proofs =
                    get_in(managed, [
                      "observation",
                      "value",
                      "record",
                      "value",
                      "evidence",
                      "sources"
                    ]),
                  {:ok, current} <-
                    ObservedRead.managed_dependency(
                      request,
                      managed,
                      pin,
                      recipe,
                      proofs,
                      System.system_time(:millisecond)
                    ) do
               {:ok, current}
             end
           end)

  assert {:ok, dependencies} = ManagedReference.union([[literal_dependency, dependency]])
  assert Enum.sort(Enum.map(dependencies, & &1["version"])) == [4, 7]
  capture = fn current, held -> {:ok, %{current: current, proofs: held.source_proofs}} end
  assert {:ok, expected} = ManagedUse.with_approval_dependencies(context, dependencies, capture)
  assert {:ok, ^expected} = ManagedUse.with_worker_dependencies(context, dependencies, capture)
  assert Enum.map(expected.current, & &1["version"]) == Enum.map(dependencies, & &1["version"])
  assert length(expected.proofs) == 2

  owner = self()

  refused = fn _, _ ->
    send(owner, :mixed_input_delivered)
    {:ok, :unexpected}
  end

  for source_id <- [mixed_literal.session_id, seed_id] do
    journal = Path.join(dir, source_id <> ".jsonl")
    held = journal <> ".mixed-test-held"
    before = File.stat!(journal)
    digest = Ipse.JSON.sha256(File.read!(journal))
    refute File.exists?(held)
    File.rename!(journal, held)

    try do
      refute match?({:ok, _}, ManagedUse.with_worker_dependencies(context, dependencies, refused))
      refute_received :mixed_input_delivered
    after
      refute File.exists?(journal), "source journal path was unexpectedly recreated"
      File.rename!(held, journal)
    end

    assert File.stat!(journal).inode == before.inode
    assert Ipse.JSON.sha256(File.read!(journal)) == digest
  end
end

for field <-
      ~w(artifact_sha256 descriptor_sha256 request_sha256 result_sha256 dependencies_sha256) do
  changed = put_in(pending_read, ["classification", field], String.duplicate("0", 64))
  tampered = Enum.map(events, fn event -> if event === pending_read, do: changed, else: event end)
  assert match?({:error, _}, Ipse.Session.Saved.restore(tampered, id))
end

if decisions != [] do
  assert [decision_intent] =
           Enum.filter(events, fn event ->
             event["type"] == "extension_action_intent" and
               get_in(event, ["request", "op"]) == "decision.create"
           end)

  request = decision_intent["request"]
  assert Ipse.Extension.DecisionExperiment.pending_input_bound?([dependency], request)
  decoded = Jason.decode!(request["input"])
  [row] = decoded["candidates"]

  altered =
    row["input"] |> Jason.decode!() |> Map.put("text", "different candidate") |> Jason.encode!()

  changed_request =
    put_in(request, ["input"], Jason.encode!(%{"candidates" => [%{row | "input" => altered}]}))

  refute Ipse.Extension.DecisionExperiment.pending_input_bound?([dependency], changed_request)
end

actions =
  Enum.filter(
    events,
    &(&1["type"] == "extension_action_result" and
        get_in(&1, ["request", "op"]) == "decision.create")
  )

assert [action] = actions
{:ok, final} = Ipse.Extension.Consent.existing_snapshot(control, binding["project_id"])
reservation = final["operations"][action["operation_id"]]

cond do
  denied? ->
    assert is_nil(reservation)

  preflight_expiry? ->
    assert is_nil(reservation)

  input_source_lost? ->
    assert is_nil(reservation)
    refute Enum.any?(events, &(&1["type"] == "extension_decision_response"))

  unknown? ->
    assert action["outcome"]["status"] != "ok"
    assert reservation["status"] == "unknown" and reservation["reserved"]["model_calls"] == 1
    refute Enum.any?(events, &(&1["type"] == "extension_decision_response"))

  release_expiry? ->
    assert reservation["status"] == "unknown" and reservation["reserved"]["model_calls"] == 1
    refute Enum.any?(events, &(&1["type"] == "extension_decision_response"))

  output_source_lost? or output_revoked? ->
    assert reservation["status"] == "settled" and reservation["actual"]["model_calls"] == 1
    assert action["outcome"]["status"] == "ok"
    if output_revoked?, do: assert(is_nil(final["policy"]))

    assert [raw] =
             Enum.filter(
               events,
               &(&1["type"] == "extension_invocation_result" and
                   get_in(&1, ["value", "status"]) == "assessed" and
                   get_in(&1, ["value", "key"]) == key)
             )

    assert [intent] =
             Enum.filter(
               events,
               &(&1["type"] == "managed_output_release_intent" and
                   &1["parent_invocation_id"] == raw["invocation_id"])
             )

    assert Enum.any?(
             events,
             &(&1["type"] == "managed_output_release_result" and
                 &1["release_id"] == intent["release_id"] and &1["decision"] == "withdrawn")
           )

    refute Enum.any?(Agent.get(calls, & &1), fn
             {:main, %{"messages" => messages}} ->
               Enum.any?(messages, fn message ->
                 message["role"] == "tool" and message["tool_name"] == "ext__knowledge__assess" and
                   String.contains?(message["content"] || "", "\"status\":\"assessed\"")
               end)

             _ ->
               false
           end)

  true ->
    assert reservation["status"] == "settled" and reservation["actual"]["model_calls"] == 1
    assert action["outcome"]["status"] == "ok"

    output =
      Agent.get(calls, & &1)
      |> Enum.find_value(fn
        {:main, %{"messages" => messages}} ->
          Enum.find(
            messages,
            &(&1["role"] == "tool" and &1["tool_name"] == "ext__knowledge__assess")
          )

        _ ->
          nil
      end)

    assert is_map(output)

    assert %{
             "status" => "assessed",
             "key" => ^key,
             "experimental" => true,
             "note_mutation" => "none",
             "advice" => advice
           } = Jason.decode!(output["content"])

    expected_advice =
      cond do
        low_confidence? -> %{"choice" => nil, "reason" => "low_probability"}
        deferred? -> %{"choice" => "defer_candidate", "reason" => "selected"}
        true -> %{"choice" => "keep_baseline", "reason" => "selected"}
      end

    assert advice == expected_advice

    assert Enum.any?(
             events,
             &(&1["type"] == "managed_output_release_result" and &1["decision"] == "current")
           )
end

refute Enum.any?(events, fn event ->
         event["type"] == "extension_action_intent" and
           get_in(event, ["request", "op"]) == "collection.managed"
       end)

assert {:ok, after_assessment} =
         Ipse.Extension.Collection.execute(
           collection,
           namespace,
           %{"op" => "snapshot"},
           Ipse.Usage.id()
         )

assert after_assessment == before_assessment

if deferred? do
  assert {:ok, %{"record" => ^before_pending}} =
           Ipse.Extension.Collection.execute(
             collection,
             namespace,
             %{"op" => "get", "key" => key},
             Ipse.Usage.id()
           )
end

assert {:ok, _} = Ipse.Session.Saved.restore(events, id)

assert :ok = Ipse.Session.close_confirmed(pid)

unless denied? or expiry? do
  prior_calls = Agent.get(calls, & &1)
  assert {:ok, closed_events} = Ipse.Journal.load(dir, id)

  intent_types =
    ~w(extension_invocation_intent extension_action_intent inference_dispatch_intent request_admitted)

  prior_intents = Enum.filter(closed_events, &(&1["type"] in intent_types))

  assert {:ok, resumed} =
           DynamicSupervisor.start_child(
             Ipse.Sessions,
             {Ipse.Session, config: runtime, cwd: cwd, state_dir: dir, subscriber: self(), id: id}
           )

  assert Ipse.Session.info(resumed).phase == :idle
  assert Agent.get(calls, & &1) == prior_calls
  assert :ok = Ipse.Session.close_confirmed(resumed)

  if deferred? do
    assert {:ok, reopened_events} = Ipse.Journal.load(dir, id)
    assert Enum.filter(reopened_events, &(&1["type"] in intent_types)) == prior_intents
    assert Agent.get(calls, & &1) == prior_calls

    assert {:ok, %{"record" => ^before_pending}} =
             Ipse.Extension.Collection.execute(
               collection,
               namespace,
               %{"op" => "get", "key" => key},
               Ipse.Usage.id()
             )
  end
end

:gen_tcp.close(listener)
Task.shutdown(server, :brutal_kill)
IO.puts("SHADOW_EXPERIMENT_SESSION_PASSED")
