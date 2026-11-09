ExUnit.start(autorun: false)
import ExUnit.Assertions
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("provider_fixture.ex", __DIR__)

for key <-
      ~w(IPSE_PROVIDER IPSE_MODEL IPSE_SANDBOX IPSE_MAX_STEPS IPSE_CONTEXT_BYTES IPSE_COMPACT IPSE_SUBAGENTS IPSE_SUBAGENT_CONCURRENCY IPSE_TIMEOUT_MS IPSE_MAX_OUTPUT_TOKENS IPSE_PROFILE IPSE_CONFIG),
    do: System.delete_env(key)

# One fresh synthetic project per scenario. The native PTY driver answers the
# experiment review, each /remember review and the decision approval; only the
# scenario named save_managed_approval_deny answers that approval with "n".
[root, scenario] = System.argv()

scenarios =
  ~w(save_managed_approval_selection save_managed_approval_deny save_managed_approval_selection_fits save_managed_approval_input_source_lost save_managed_approval_unknown)

assert scenario in scenarios
approved? = scenario == "save_managed_approval_selection"
denied? = scenario == "save_managed_approval_deny"
fits? = scenario == "save_managed_approval_selection_fits"
input_source_lost? = scenario == "save_managed_approval_input_source_lost"
unknown? = scenario == "save_managed_approval_unknown"
alias Ipse.Extension.{Collection, Consent, ProjectIdentity, ResultSource, SemanticAdmission}
home = Path.join(root, "home")
cwd = Path.join(root, "project")
dir = Path.join(root, "sessions")
File.mkdir_p!(home)
File.mkdir_p!(cwd)
File.chmod!(home, 0o700)
System.put_env("IPSE_HOME", home)

{:ok, listener} =
  :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

{:ok, {_, port}} = :inet.sockname(listener)
base = "http://127.0.0.1:#{port}"
{:ok, calls} = Agent.start_link(fn -> [] end)
# The selection arguments are installed only after seeding; no earlier main
# request can receive a selection tool call.
{:ok, arguments} = Agent.start_link(fn -> nil end)

server =
  Task.async(fn ->
    loop = fn loop ->
      case :gen_tcp.accept(listener, 30_000) do
        {:ok, socket} ->
          {headers, bytes} = Ipse.Test.ProviderFixture.request(socket, "")
          request = Jason.decode!(bytes)
          decision? = String.starts_with?(headers, "POST /systemone ")
          Agent.update(calls, &(&1 ++ [{if(decision?, do: :decision, else: :main), request}]))

          body =
            cond do
              decision? and unknown? ->
                "{invalid"

              decision? ->
                Jason.encode!(%{
                  "model" => "synthetic",
                  "answers" => %{
                    "pack" => %{
                      "type" => "choice",
                      "choice" => "second",
                      "confidence" => 0.9,
                      "probabilities" => %{"first" => 0.1, "second" => 0.9}
                    }
                  },
                  "usage" => %{"input_tokens" => 10, "output_tokens" => 2}
                })

              true ->
                selection = Agent.get(arguments, & &1)

                answered? =
                  Enum.any?(
                    request["messages"],
                    &(&1["role"] == "tool" and &1["tool_name"] == "ext__knowledge__select_shadow")
                  )

                message =
                  if is_map(selection) and not answered?,
                    do: %{
                      "role" => "assistant",
                      "content" => "",
                      "tool_calls" => [
                        %{
                          "function" => %{
                            "name" => "ext__knowledge__select_shadow",
                            "arguments" => selection
                          }
                        }
                      ]
                    },
                    else: %{"role" => "assistant", "content" => "Fixture finished."}

                Jason.encode!(%{
                  "model" => "synthetic",
                  "message" => message,
                  "done" => true,
                  "prompt_eval_count" => 1,
                  "eval_count" => 1
                }) <> "\n"
            end

          :ok =
            :gen_tcp.send(
              socket,
              "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                body
            )

          :gen_tcp.close(socket)
          loop.(loop)

        _ ->
          :ok
      end
    end

    loop.(loop)
  end)

config_path = Path.join(home, "config.json")

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
      "service_id" => "fixture",
      "base_url" => base,
      "timeout_ms" => 3000
    }
  },
  "inference_services" => %{"fixture" => %{"version" => 1, "origins" => [base]}}
}

File.write!(config_path, Jason.encode!(config))
File.chmod!(config_path, 0o600)
configured = File.read!(config_path)

# Native route review: the real CLI writes one finite project grant.
reviewed_at = System.system_time(:millisecond)

assert 0 ==
         Ipse.CLI.run([
           "knowledge",
           "experiment",
           "advice",
           "1",
           "120",
           "--cwd",
           cwd,
           "--config",
           config_path,
           "--no-project-config"
         ])

assert File.read!(config_path) == configured
{:ok, binding} = ProjectIdentity.existing(home, cwd)
control = SemanticAdmission.control_root(home)
{:ok, granted} = Consent.existing_snapshot(control, binding["project_id"])
policy = granted["policy"]
assert granted["operations"] == %{}
assert policy["limits"]["model_calls"] == 1
assert policy["expires_at_ms"] > reviewed_at
assert policy["expires_at_ms"] <= System.system_time(:millisecond) + 120_000

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

# Seed literal notes through the actual native assertion channel of one
# original Session. Eight 700-byte notes exceed the recall allocation; two
# short notes fit it.
statement = fn n ->
  marker = "~S#{n}~ café 雪 "
  marker <> String.duplicate("x", 700 - byte_size(marker))
end

statements =
  if fits?,
    do: Enum.map(1..2, &"Synthetic fitting statement #{&1}."),
    else: Enum.map(1..8, statement)

{:ok, seed} =
  DynamicSupervisor.start_child(
    Ipse.Sessions,
    {Ipse.Session, config: runtime, cwd: cwd, state_dir: dir, subscriber: self()}
  )

seed_id = Ipse.Session.info(seed).id
state = :sys.get_state(seed)
admission = state.config.semantic_admission
assert admission["status"] == "active" and admission["policy"] == policy
namespace = admission["pin"]["namespace"]
assert {:ok, channel} = Ipse.Session.open_input_channel(seed, self())

for {text, step} <- Enum.with_index(statements, 1) do
  command = "/remember ordinary " <> text
  File.write!(Path.join(root, "supersession-input-#{step}"), command)
  IO.write("IPSE_SUPERSESSION_READ_#{step}> ")

  assert {:ok, ^command, witness} =
           Ipse.Session.observe_channel(seed, channel, %{"kind" => "prompt"}, 30_000)

  assert {:ok, ticket} = Ipse.Session.stage_input(seed, channel, command, witness)

  assert {:ok, %{"render_id" => render}} =
           Ipse.Session.prepare_assertion(seed, channel, command, ticket)

  assert {:ok, answer, answer_witness} =
           Ipse.Session.observe_channel(
             seed,
             channel,
             %{"kind" => "assertion", "render_id" => render},
             30_000
           )

  assert :ok =
           Ipse.Session.accept_assertion_observed(seed, channel, render, answer, answer_witness)

  assert_receive {:ipse, ^seed, {:done, :ok}}, 15_000
end

{:ok, seed_events} = Ipse.Journal.load(dir, seed_id)

keys =
  seed_events
  |> Enum.filter(fn event ->
    event["type"] == "extension_action_result" and
      get_in(event, ["request", "op"]) == "collection.managed" and
      get_in(event, ["outcome", "status"]) == "ok"
  end)
  |> Enum.flat_map(&Enum.map(get_in(&1, ["request", "request", "changes"]), fn c -> c["key"] end))
  |> Enum.sort()

assert length(keys) == length(statements) and Enum.all?(keys, &String.starts_with?(&1, "note."))
assert :ok = Ipse.Session.close_confirmed(seed)
refute Enum.any?(Agent.get(calls, & &1), &(elem(&1, 0) == :decision))

{first, second} = Enum.split(keys, div(length(keys), 2))

Agent.update(arguments, fn _ ->
  %{
    "query" => "Which synthetic statements should the next answer use?",
    "packs" => [%{"id" => "first", "members" => first}, %{"id" => "second", "members" => second}]
  }
end)

collection = SemanticAdmission.collection_root(home)
seed_journal = Path.join(dir, seed_id <> ".jsonl")
seed_digest = Ipse.JSON.sha256(File.read!(seed_journal))
seed_inode = File.stat!(seed_journal).inode

assert {:ok, before_selection} =
         Collection.execute(collection, namespace, %{"op" => "snapshot"}, Ipse.Usage.id())

calls_before = length(Agent.get(calls, & &1))
{:ok, seeded} = Consent.existing_snapshot(control, binding["project_id"])
assert seeded["policy"] == policy and map_size(seeded["operations"]) == length(keys)

assert Enum.all?(Map.values(seeded["operations"]), fn op ->
         op["operation"] == "notes.capture" and op["status"] == "settled" and
           op["actual"]["model_calls"] == 0
       end)

{:ok, pid} =
  DynamicSupervisor.start_child(
    Ipse.Sessions,
    {Ipse.Session, config: runtime, cwd: cwd, state_dir: dir, subscriber: self()}
  )

id = Ipse.Session.info(pid).id

knowledge =
  Enum.find(
    :sys.get_state(pid).config.extensions,
    &(&1.identity["instance"] == "knowledge")
  )

assert knowledge.identity["artifact_sha256"] == policy["artifact_sha256"]
refute "host.model" in knowledge.identity["capabilities"]

selection_calls = fn -> Enum.drop(Agent.get(calls, & &1), calls_before) end

wait = fn wait, ready?, remaining ->
  if ready?.(),
    do: :ok,
    else:
      (
        assert remaining > 0
        Process.sleep(10)
        wait.(wait, ready?, remaining - 1)
      )
end

idle = fn -> wait.(wait, fn -> :sys.get_state(pid).phase == :idle end, 2000) end

{:ok, _watcher} =
  Task.start_link(fn ->
    if fits? do
      # A fitting complete set never reaches native approval.
      answered? = fn ->
        Enum.any?(selection_calls.(), fn
          {:main, %{"messages" => messages}} ->
            Enum.any?(
              messages,
              &(&1["role"] == "tool" and &1["tool_name"] == "ext__knowledge__select_shadow")
            )

          _ ->
            false
        end)
      end

      wait.(wait, answered?, 3000)
      idle.()
    else
      wait.(
        wait,
        fn -> File.exists?(Path.join(root, "managed-approval-input-ready")) end,
        3000
      )

      assert :sys.get_state(pid).phase == :managed_approval

      if input_source_lost? do
        watcher = self()

        hook = fn
          count, {:in, {:"$gen_call", _, {:managed_preflight_begin, _, "decision.create"}}}, _ ->
            send(watcher, {:shadow_wire_blocked, self()})
            receive do: (:release_shadow_wire -> :ok)
            count + 1

          count, _, _ ->
            count
        end

        assert :ok = :sys.install(pid, {hook, 0})
      end

      File.write!(Path.join(root, "managed-approval-control-checked"), "checked")

      if input_source_lost? do
        assert_receive {:shadow_wire_blocked, ^pid}, 20_000
        held = seed_journal <> ".input-source-held"
        refute File.exists?(held)
        File.rename!(seed_journal, held)

        try do
          refute File.exists?(seed_journal)
          send(pid, :release_shadow_wire)
          idle.()
        after
          if File.exists?(held) and not File.exists?(seed_journal),
            do: File.rename!(held, seed_journal)
        end
      else
        idle.()
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
           "Compare the frozen synthetic note packs once; do not change notes or context.",
           cwd
         )

{:ok, events} = Ipse.Journal.load(dir, id)
decisions = for {:decision, request} <- selection_calls.(), do: request
mains = for {:main, request} <- selection_calls.(), do: request
assert length(decisions) == if(approved? or unknown?, do: 1, else: 0)

for decision <- decisions,
    do: assert(decision["questions"]["pack"]["type"] == "choice")

assert [invocation] =
         Enum.filter(
           events,
           &(&1["type"] == "extension_invocation_intent" and
               get_in(&1, ["descriptor", "id"]) == "select_shadow")
         )

assert invocation["payload"]["arguments"] == Agent.get(arguments, & &1)

children =
  Enum.filter(
    events,
    &(&1["type"] in ~w(extension_action_intent extension_action_result) and
        &1["parent_invocation_id"] == invocation["invocation_id"])
  )

# Selection never publishes context, writes a note or calls another tool.
refute Enum.any?(
         children,
         &(get_in(&1, ["request", "op"]) in ~w(context.publish collection.managed state.put tool.call))
       )

refute Enum.any?(events, &(get_in(&1, ["request", "op"]) == "collection.managed"))

actions =
  Enum.filter(
    events,
    &(&1["type"] == "extension_action_result" and
        get_in(&1, ["request", "op"]) == "decision.create")
  )

{:ok, final} = Consent.existing_snapshot(control, binding["project_id"])
assert final["epoch"] == granted["epoch"] and final["policy"] == policy
# Seeding settled one zero-call capture operation per note; those stay unchanged.
assert Map.take(final["operations"], Map.keys(seeded["operations"])) == seeded["operations"]
added = Map.drop(final["operations"], Map.keys(seeded["operations"]))

reservation =
  case actions do
    [action] -> final["operations"][action["operation_id"]]
    [] -> nil
  end

cond do
  fits? ->
    assert actions == []
    assert added == %{}
    refute Enum.any?(children, &(get_in(&1, ["request", "purpose"]) == "saved_policy_budget_v1"))

  denied? or input_source_lost? ->
    assert [_] = actions
    assert is_nil(reservation)
    refute Enum.any?(events, &(&1["type"] == "extension_decision_response"))

    assert added == %{}
    refute Enum.any?(final["operations"], fn {_, op} -> op["reserved"]["model_calls"] > 0 end)

  unknown? ->
    assert [action] = actions
    assert action["outcome"]["status"] != "ok"
    assert reservation["status"] == "unknown" and reservation["reserved"]["model_calls"] == 1
    refute Enum.any?(events, &(&1["type"] == "extension_decision_response"))

  approved? ->
    assert [action] = actions
    assert action["outcome"]["status"] == "ok"
    assert reservation["status"] == "settled" and reservation["actual"]["model_calls"] == 1
    assert Map.keys(added) == [action["operation_id"]]
end

assert {:ok, after_selection} =
         Collection.execute(collection, namespace, %{"op" => "snapshot"}, Ipse.Usage.id())

assert after_selection == before_selection
assert File.stat!(seed_journal).inode == seed_inode
assert Ipse.JSON.sha256(File.read!(seed_journal)) == seed_digest
assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
assert :ok = Ipse.Session.close_confirmed(pid)

# The released comparison is read from the tool message the main model saw. A
# large result arrives as a saved.result descriptor; materialize its exact bytes.
if approved? or denied? or fits? do
  assert length(mains) == 2

  [content] =
    for request <- mains,
        message <- request["messages"],
        message["role"] == "tool" and message["tool_name"] == "ext__knowledge__select_shadow",
        uniq: true,
        do: message["content"]

  delivered = Jason.decode!(content)

  value =
    if ResultSource.valid_descriptor?(delivered) do
      assert {:ok, result} = ResultSource.read_saved(dir, id, delivered["output_id"])
      assert byte_size(result.bytes) == delivered["byte_count"]
      assert Ipse.JSON.sha256(result.bytes) == delivered["sha256"]
      result.value
    else
      delivered
    end

  assert %{"status" => "selection_shadow", "experimental" => true, "context_mutation" => "none"} =
           value

  assert value["eligible_count"] == length(keys)
  assert Enum.sort(Enum.map(value["reads"], & &1["key"])) == keys

  for read <- value["reads"] do
    assert [event] =
             Enum.filter(
               events,
               &(&1["type"] == "extension_action_result" and
                   &1["operation_id"] == read["read_operation_id"])
             )

    assert event["parent_invocation_id"] == invocation["invocation_id"]
    assert event["request"]["op"] == "collection.call"
    assert event["request"]["request"] == %{"op" => "get", "key" => read["key"]}
    assert event["outcome"]["status"] == "ok"

    assert Map.take(event["outcome"]["value"]["record"], ~w(key revision sha256 bytes)) ==
             Map.take(read, ~w(key revision sha256 bytes))

    assert [observed] =
             Enum.filter(
               events,
               &(&1["type"] == "managed_read_observed" and
                   &1["operation_id"] == read["read_operation_id"])
             )

    assert Enum.any?(
             observed["dependencies"],
             &(&1["version"] == 4 and &1["subject"]["key"] == read["key"])
           )
  end

  assert Enum.any?(
           events,
           &(&1["type"] == "managed_output_release_result" and &1["decision"] == "current")
         )

  baseline = value["baseline"]
  assert baseline["rendered_bytes"] <= value["allocation_bytes"]
  assert value["allocation_bytes"] <= 8192

  if fits? do
    assert value["eligible_rendered_bytes"] <= value["allocation_bytes"]
    assert baseline["included"] == 2 and Enum.sort(baseline["members"]) == keys
    assert value["candidate"] == nil and value["budget_observation"] == nil
    assert value["outcome"]["receipt"]["reason"] == "complete_set_fits"
  else
    # The complete ordinary greedy baseline stays the comparator.
    assert value["eligible_rendered_bytes"] > value["allocation_bytes"]
    assert baseline["included"] > 4 and baseline["included"] < 8
    assert length(baseline["members"]) == baseline["included"]
    assert value["budget_observation"]["available"]["model_calls"] == 1
    assert value["budget_observation"]["epoch"] == granted["epoch"]

    if approved? do
      candidate = value["candidate"]
      assert candidate["included"] == 4 and Enum.sort(candidate["members"]) == second
      assert candidate["rendered_bytes"] <= value["allocation_bytes"]
      assert value["outcome"]["receipt"]["reason"] == "selected"
    else
      assert value["candidate"] == nil
      assert value["outcome"]["receipt"]["reason"] == "decision_denied"
    end
  end
end

# Reopen the same Session: idle, no new work intents and no extra wire call.
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
assert :ok = Ipse.Session.close_confirmed(resumed)
assert {:ok, reopened} = Ipse.Journal.load(dir, id)
assert Enum.filter(reopened, &(&1["type"] in intent_types)) == prior_intents
assert Agent.get(calls, & &1) == prior_calls
assert {:ok, reopened_grant} = Consent.existing_snapshot(control, binding["project_id"])

assert Map.take(reopened_grant, ~w(epoch policy operations)) ==
         Map.take(final, ~w(epoch policy operations))

:gen_tcp.close(listener)
Task.shutdown(server, :brutal_kill)
IO.puts("SELECTION_SHADOW_SESSION_PASSED")
