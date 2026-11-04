ExUnit.start(autorun: false)
import ExUnit.Assertions
Code.require_file("provider_fixture.ex", __DIR__)
{:ok, _} = Application.ensure_all_started(:ipse)

defmodule Ipse.Test.ChatReviewLifecycle do
  import ExUnit.Assertions

  def await_client_return(result, owner, reference) do
    receive do
      {^reference, ^owner} -> result
    after
      60_000 -> flunk("CLI caller did not acknowledge the completed fixture task")
    end
  end

  def ready(pid) do
    receive do
      {:ipse, ^pid, {:pending_chat_review, token}} -> token
      {:ipse, ^pid, {:done, :error}} -> flunk("actual pending capture failed before handoff")
    after
      30_000 -> flunk("actual pending capture produced no review handoff")
    end
  end

  def finished(pid) do
    receive do
      {:ipse, ^pid, {:done, :ok}} -> :ok
      {:ipse, ^pid, {:done, status}} -> flunk("unexpected synthetic turn status: #{status}")
    after
      30_000 -> flunk("synthetic turn did not settle")
    end
  end

  def nomination_history_fences(records) do
    alias Ipse.Session.{PendingNomination, Saved}
    id = get_in(hd(records), ["metadata", "semantic_admission", "pin", "session_id"])
    assert :ok = PendingNomination.validate_events(records, id)
    assert :ok = Ipse.Extension.Invocation.validate_events(records)
    assert {:ok, _} = Ipse.Usage.restore(records, id)

    for attempt <-
          Enum.filter(
            records,
            &(&1["type"] == "pending_chat_capture_started" and &1["version"] === 2)
          ) do
      nomination = Enum.find(records, &(Ipse.JSON.digest([&1]) === attempt["nomination_sha256"]))

      assert {:ok, ^attempt} =
               PendingNomination.capture_attempt(
                 id,
                 attempt["turn_id"],
                 attempt["request_id"],
                 nomination,
                 attempt["source_proof"]
               )

      refute Map.has_key?(attempt, "attempt_id")
      assert is_binary(attempt["capture_attempt_id"])
    end

    assert {:ok, _} = Saved.restore(records, id)
    nomination = Enum.find(records, &(&1["type"] == "pending_proposal_nominated"))
    index = Enum.find_index(records, &(&1 === nomination))
    cleanup_at = index - 1
    cleanup = Enum.at(records, cleanup_at)
    assert cleanup["type"] === "managed_output_release_cleanup"

    release_at =
      Enum.find_index(records, fn record ->
        record["type"] === "managed_output_release_intent" and
          record["parent_invocation_id"] === nomination["invocation_id"]
      end)

    admission_at =
      Enum.find_index(records, fn record ->
        record["type"] === "managed_output_release_result" and
          record["release_id"] === cleanup["release_id"]
      end)

    outcome_at = cleanup_at - 1
    outcome = Enum.at(records, outcome_at)
    assert outcome["type"] === "lifecycle_tool_outcome"

    candidates = [
      List.delete_at(records, cleanup_at),
      List.delete_at(records, release_at),
      List.insert_at(records, cleanup_at, %{"type" => "fixture_unrelated_event"}),
      List.update_at(records, cleanup_at, &Map.put(&1, "status", "unknown")),
      List.update_at(records, release_at, &Map.put(&1, "session_id", String.duplicate("f", 32))),
      List.update_at(records, admission_at, &Map.put(&1, "decision", "withdrawn")),
      List.update_at(records, outcome_at, &Map.put(&1, "turn_id", String.duplicate("f", 32))),
      List.update_at(records, outcome_at, fn event ->
        put_in(event, ["result_source", "record_sha256"], Ipse.JSON.sha256("changed message"))
      end)
    ]

    for changed <- candidates do
      assert {:error, _} = PendingNomination.validate_events(changed, id)
      assert {:error, _} = Ipse.Extension.Invocation.validate_events(changed)
      assert {:error, _} = Saved.restore(changed, id)
    end

    for changed <- [
          List.insert_at(records, index, nomination),
          List.update_at(records, index, &Map.put(&1, "type", "unknown_host_nomination")),
          List.update_at(
            records,
            index,
            &Map.put(&1, "invocation_id", String.duplicate("f", 32))
          ),
          List.update_at(
            records,
            index,
            &Map.put(&1, "intent_sha256", Ipse.JSON.sha256("foreign intent"))
          ),
          List.update_at(
            records,
            index,
            &Map.put(&1, "result_sha256", Ipse.JSON.sha256("foreign result"))
          )
        ] do
      assert {:error, _} = Ipse.Extension.Invocation.validate_events(changed)
      assert {:error, _} = Saved.restore(changed, id)
    end

    release = Enum.at(records, release_at)
    raw = Enum.at(records, release_at + 1)
    admission = Enum.at(records, admission_at)
    changed_release = Map.put(release, "dependencies_sha256", Ipse.JSON.digest([]))

    changed_admission =
      Ipse.Session.ManagedOutput.admission(
        changed_release,
        raw,
        "current",
        [],
        admission["checked_at_ms"],
        admission["deadline_ms"]
      )

    changed_cleanup =
      Ipse.Session.ManagedOutput.cleanup(changed_release, changed_admission, "confirmed")

    changed =
      records
      |> List.replace_at(release_at, changed_release)
      |> List.replace_at(admission_at, changed_admission)
      |> List.replace_at(cleanup_at, changed_cleanup)

    assert :ok = PendingNomination.validate_events(changed, id)
    assert {:error, _} = Saved.restore(changed, id)
    IO.puts("NOMINATION_MANAGED_HISTORY_FENCES_CHECKED")
  end

  # These are pure transition and scoped admission probes using the actual
  # installed worker's durable nomination, not another executable artifact.
  def nomination_fences(state, records, cwd) do
    alias Ipse.Extension.{Actions, Invocation, Mode, SemanticAdmission}
    alias Ipse.Session.Resources

    [intent] =
      Enum.filter(records, fn event ->
        event["type"] == "extension_invocation_intent" and event["descriptor"]["id"] == "nominate"
      end)

    binding = intent["semantic_binding"]
    assert binding["class"] === "nomination.select"
    metadata = hd(records)["metadata"]

    assert SemanticAdmission.valid_outer_binding?(
             binding,
             intent["identity"],
             intent["descriptor"],
             state.id,
             metadata
           )

    refute "nomination.select" in Mode.classes()
    assert {:ok, mode} = Mode.capture(state.config)
    assert :ok = Mode.nomination(mode)
    assert {:error, _} = Mode.knowledge(mode, "nomination.select")

    assert {:error, _} =
             SemanticAdmission.outer_class(
               state.config.semantic_admission["policy"],
               binding["descriptor_sha256"]
             )

    probe = fn config, identity, descriptor ->
      {:ok, scope} = Resources.start(self())
      previous = Resources.bind(scope)

      try do
        result = SemanticAdmission.outer(config, cwd, state.id, identity, descriptor)
        assert :ok = Resources.finish(scope)
        result
      after
        Resources.bind(previous)
        if Process.alive?(scope), do: Resources.close(scope)
      end
    end

    assert {:ok, ^binding} = probe.(state.config, intent["identity"], intent["descriptor"])

    for config <- [
          Map.put(state.config, :execution_mode, :planning),
          Map.put(state.config, :execution_mode, :draft),
          Map.put(state.config, :execution_mode, :read_only),
          Map.put(state.config, :enclosing_mode, :planning),
          Map.put(state.config, :headless, true),
          Map.put(state.config, :knowledge_ceiling, :disabled),
          Map.merge(state.config, %{approval: :deny, approval_origin: :interactive}),
          Map.merge(state.config, %{approval: :deny, approval_origin: :explicit})
        ] do
      assert {:error, _} = probe.(config, intent["identity"], intent["descriptor"])
    end

    changed = Map.update!(intent["descriptor"], "description", &(&1 <> " changed"))
    assert {:error, _} = probe.(state.config, intent["identity"], changed)
    changed_binding = Map.put(binding, "descriptor_sha256", Ipse.JSON.digest([changed]))

    refute SemanticAdmission.valid_outer_binding?(
             changed_binding,
             intent["identity"],
             changed,
             state.id,
             metadata
           )

    assert {:error, _} =
             probe.(
               state.config,
               Map.put(intent["identity"], "artifact_sha256", String.duplicate("0", 64)),
               intent["descriptor"]
             )

    requests = [
      %{"op" => "source.list", "limit" => 1, "cursor" => nil},
      %{"op" => "tool.call", "name" => "read", "arguments" => %{"path" => "README.md"}},
      %{
        "op" => "tool.call",
        "name" => "write",
        "arguments" => %{"path" => "forbidden.txt", "content" => "forbidden"}
      },
      %{
        "op" => "tool.call",
        "name" => "shell",
        "arguments" => %{"command" => "touch forbidden-shell"}
      },
      %{"op" => "tool.call", "name" => "delegate", "arguments" => %{"task" => "forbidden"}},
      %{"op" => "mcp.call", "server" => "forbidden", "tool" => "forbidden", "arguments" => %{}},
      %{"op" => "model.complete", "profile" => "forbidden", "messages" => []}
    ]

    for flags <- [%{}, %{approval: :allow, approval_origin: :yes}, %{accept_edits: true}],
        request <- requests do
      transition = %{
        state
        | config: Map.merge(state.config, flags),
          invocation: %Ipse.Session.Invocation{parent: intent}
      }

      refute Actions.allowed_under_outer?(intent, request)

      assert {:reply, {:error, :nomination_effect_refused}, ^transition} =
               Ipse.Session.Invocation.begin_action(
                 transition,
                 request,
                 {self(), make_ref()},
                 :tool
               )
    end

    action =
      Enum.find(records, fn record ->
        record["type"] == "extension_action_result" and
          get_in(record, ["request", "op"]) == "collection.managed" and
          get_in(record, ["outcome", "status"]) == "ok"
      end)

    assert is_map(action) and Actions.valid_result?(action)
    response = %{"api_version" => 1, "kind" => "result", "value" => %{"status" => "nominated"}}
    assert {:ok, _} = Invocation.build_result(intent, response, [])
    # Structural constructors accept the same already-valid envelope under an
    # ordinary receipt; this synthetic comparison supplies no live admission.
    ordinary = put_in(intent, ["semantic_binding", "class"], "collection.read")
    assert {:ok, _} = Invocation.build_result(ordinary, response, [action])
    assert {:error, _} = Invocation.build_result(intent, response, [action])

    delivery = %{
      "version" => 1,
      "kind" => "saved.result",
      "output_id" => Ipse.JSON.sha256("nomination-output"),
      "byte_count" => 16_911,
      "sha256" => Ipse.JSON.sha256("nomination-bytes"),
      "historical_receipt" => true
    }

    assert Ipse.Extension.ResultSource.valid_descriptor?(delivery)
    assert {:ok, _} = Invocation.build_saved_result(ordinary, delivery, [], 0)
    assert {:error, _} = Invocation.build_saved_result(intent, delivery, [], 0)
    refute File.exists?(Path.join(cwd, "forbidden.txt"))
    refute File.exists?(Path.join(cwd, "forbidden-shell"))
    IO.puts("NOMINATION_ZERO_EFFECT_FENCES_CHECKED")
  end

  def session(excluded, deadline) do
    found =
      Enum.find_value(DynamicSupervisor.which_children(Ipse.Sessions), fn {_, pid, _, _} ->
        if is_pid(pid) and pid != excluded do
          try do
            {pid, Ipse.Session.info(pid)}
          catch
            :exit, _ -> nil
          end
        end
      end)

    cond do
      found ->
        found

      System.monotonic_time(:millisecond) >= deadline ->
        raise "expected live chat Session was unavailable"

      true ->
        Process.sleep(2)
        session(excluded, deadline)
    end
  end

  def followup_snapshot(session, stage) do
    state = :sys.get_state(session)

    dependencies =
      case Ipse.Session.ManagedLineage.dependencies(state.managed_lineage, state.messages) do
        {:ok, values} ->
          Enum.map(values, fn value ->
            %{
              "version" => value["version"],
              "sha256" => Ipse.JSON.digest([value]),
              "collection" => value["collection"]
            }
          end)

        _ ->
          "unavailable"
      end

    %{
      "stage" => stage,
      "session_id" => state.id,
      "phase" => Atom.to_string(state.phase),
      "turn_id" => state.turn_id,
      "last_request_id" => state.last_request_id,
      "input_generation" => state.input_generation,
      "managed_dependencies" => dependencies,
      "managed_lineage_unavailable" => not match?(%{unavailable: false}, state.managed_lineage),
      "share_barrier" => not is_nil(state.share_barrier),
      "event_cleanup_failed" => state.event_cleanup_failed,
      "task_active" => not is_nil(state.task),
      "accounting" => Ipse.Usage.snapshot(state.accounting)
    }
  end

  def settled_followup(session, previous_turn, deadline) do
    snapshot = followup_snapshot(session, "followup_settled")

    cond do
      snapshot["turn_id"] != previous_turn and snapshot["phase"] == "idle" and
          snapshot["task_active"] == false ->
        snapshot

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("same-ID followup did not reach an idle settled boundary")

      true ->
        Process.sleep(2)
        settled_followup(session, previous_turn, deadline)
    end
  end
end

[root, mode] = System.argv()
assert mode in ~w(accept cancel stale_cancel stale_turn reoffer planning_accept same_followup)

for key <- ~w(IPSE_PROVIDER IPSE_MODEL IPSE_CONFIG IPSE_PROFILE IPSE_SANDBOX IPSE_SUBAGENTS),
    do: System.delete_env(key)

home = Path.join(root, "home")
cwd = Path.join(root, "work")
history = Path.join(root, "custom-history")

for path <- [home, cwd] do
  File.mkdir_p!(path)
  File.chmod!(path, 0o700)
end

System.put_env("IPSE_HOME", home)
text = "Use the cedar release channel for this workspace."
reason = "Operator can choose this workspace release preference"

{:ok, listener} =
  :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

{:ok, {_, port}} = :inet.sockname(listener)
base = "http://127.0.0.1:#{port}"

server_owner = self()
server_finished = make_ref()

server =
  Task.async(fn ->
    result =
      try do
        steps = if mode == "stale_cancel", do: 2, else: if(mode == "stale_turn", do: 4, else: 3)

        for step <- 1..steps, reduce: [] do
          hashes ->
            case :gen_tcp.accept(listener, 60_000) do
              {:error, :closed} when mode == "same_followup" and step == 3 ->
                hashes

              {:ok, socket} ->
                try do
                  {_, bytes} = Ipse.Test.ProviderFixture.request(socket, "")
                  request = Jason.decode!(bytes)
                  assert request["model"] === "synthetic"

                  message =
                    case step do
                      1 ->
                        assert Enum.any?(
                                 request["messages"],
                                 &(&1["role"] == "user" and
                                     &1["content"] ==
                                       "Propose a durable decision for this workspace.")
                               )

                        %{
                          "role" => "assistant",
                          "content" => "",
                          "tool_calls" => [
                            %{
                              "function" => %{
                                "name" => "ext__knowledge__nominate",
                                "arguments" => %{
                                  "text" => text,
                                  "reason" => reason,
                                  "category" => "ordinary",
                                  "references" => []
                                }
                              }
                            }
                          ]
                        }

                      2 ->
                        assert Enum.any?(request["messages"], fn row ->
                                 row["role"] == "tool" and
                                   row["tool_name"] == "ext__knowledge__nominate" and
                                   row["content"] =~ "nominated"
                               end)

                        %{"role" => "assistant", "content" => text}

                      3 ->
                        if mode == "same_followup" do
                          assert Enum.any?(
                                   request["messages"],
                                   &(&1["role"] == "user" and
                                       &1["content"] ==
                                         "Continue with one ordinary sentence about this workspace.")
                                 )

                          original =
                            Enum.find(request["messages"], fn row ->
                              row["role"] == "assistant" and
                                Enum.any?(
                                  row["tool_calls"] || [],
                                  &(get_in(&1, ["function", "name"]) == "ext__knowledge__nominate")
                                )
                            end)

                          assert is_map(original)

                          assert original["thinking"] ===
                                   "FIXED_SYNTHETIC_NOMINATION_CONTINUATION"

                          assert Jason.encode!(request["messages"]) =~ "note_parts_v2"

                          %{
                            "role" => "assistant",
                            "content" => "SAME_ID_FOLLOWUP_PROVIDER_COMPLETED"
                          }
                        else
                          prompt =
                            if mode == "stale_turn",
                              do: "A separate ordinary followup.",
                              else: "Recall the decision I just accepted."

                          assert Enum.any?(
                                   request["messages"],
                                   &(&1["role"] == "user" and
                                       &1["content"] == prompt)
                                 )

                          wire = Jason.encode!(request["messages"])

                          if mode in ~w(accept reoffer planning_accept),
                            do: assert(wire =~ "note_parts_v2"),
                            else: refute(wire =~ "note_parts_v2")

                          if mode == "stale_turn" do
                            %{
                              "role" => "assistant",
                              "content" => "",
                              "tool_calls" => [
                                %{
                                  "function" => %{
                                    "name" => "ext__knowledge__nominate",
                                    "arguments" => %{
                                      "text" =>
                                        "Use the birch release channel for this workspace.",
                                      "reason" => reason,
                                      "category" => "ordinary",
                                      "references" => []
                                    }
                                  }
                                }
                              ]
                            }
                          else
                            %{"role" => "assistant", "content" => "CHAT_RECALL_VERIFIED"}
                          end
                        end

                      4 ->
                        assert mode == "stale_turn"

                        assert Enum.any?(request["messages"], fn row ->
                                 row["role"] == "tool" and
                                   row["tool_name"] == "ext__knowledge__nominate" and
                                   row["content"] =~ "nominated"
                               end)

                        %{
                          "role" => "assistant",
                          "content" => "Use the birch release channel for this workspace."
                        }
                    end

                  message =
                    if step == 1 and mode == "same_followup",
                      do: Map.put(message, "thinking", "FIXED_SYNTHETIC_NOMINATION_CONTINUATION"),
                      else: message

                  body =
                    Jason.encode!(%{
                      "model" => "synthetic",
                      "message" => message,
                      "done" => true,
                      "prompt_eval_count" => 1,
                      "eval_count" => 1
                    }) <> "\n"

                  :ok =
                    :gen_tcp.send(
                      socket,
                      "HTTP/1.1 200 Fixture\r\ncontent-type: application/x-ndjson\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                        body
                    )

                  hashes ++ [Ipse.JSON.sha256(bytes)]
                after
                  :gen_tcp.close(socket)
                end
            end
        end
      after
        :gen_tcp.close(listener)
      end

    Ipse.Test.ChatReviewLifecycle.await_client_return(result, server_owner, server_finished)
  end)

config = Path.join(home, "config.json")

File.write!(
  config,
  Jason.encode!(%{
    "version" => 1,
    "profiles" => %{
      "local" => %{
        "provider" => "ollama",
        "model" => "synthetic",
        "base_url" => base,
        "timeout_ms" => 90_000,
        "max_output_tokens" => 128
      }
    },
    "roles" => %{"main" => "local"},
    "inference_services" => %{"local" => %{"version" => 1, "origins" => [base]}}
  })
)

File.chmod!(config, 0o600)
options = ["--cwd", cwd, "--config", config, "--no-project-config"]
assert 0 === Ipse.CLI.run(["knowledge", "enable"] ++ options)

if mode in ~w(stale_cancel stale_turn) do
  client = %{
    workspace: cwd,
    home: home,
    auth_dir: Path.join(home, "auth"),
    operator_home: Ipse.Workspace.operator_home(),
    mcp_config: nil,
    base_url: nil,
    operator_questions: true,
    accept_edits: false,
    approval: :ask,
    approval_origin: :interactive,
    headless: false
  }

  assert {:ok, effective} =
           Ipse.Config.resolve(cwd, home, [config: config, project_config: false], %{})

  assert {:ok, runtime} = Ipse.Config.runtime(effective, client)

  assert {:ok, session} =
           DynamicSupervisor.start_child(
             Ipse.Sessions,
             {Ipse.Session,
              config: runtime, cwd: cwd, state_dir: history, subscriber: self(), owner: self()}
           )

  assert {:ok, reader, channel, :native} = Ipse.CLI.Input.start(session)
  assert :ok = Ipse.Session.prompt(session, "Propose a durable decision for this workspace.")
  token = Ipse.Test.ChatReviewLifecycle.ready(session)
  assert :ok = Ipse.Test.ChatReviewLifecycle.finished(session)
  refute_receive {:ipse, ^session, {:decision_card_unavailable, _}}, 0
  id = Ipse.Session.info(session).id
  pending = :sys.get_state(session).pending_chat_review
  assert pending.token === token and pending.state === :ready
  binding = pending.event
  assert {:ok, original_records} = Ipse.Journal.load(history, id)
  Ipse.Test.ChatReviewLifecycle.nomination_history_fences(original_records)
  Ipse.Test.ChatReviewLifecycle.nomination_fences(:sys.get_state(session), original_records, cwd)
  key = binding["event"]["pending_key"]
  operation = Ipse.Session.ChatReviewHandoff.operation_id(binding)
  journals = Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"]))

  foreign = Task.async(fn -> Ipse.Session.claim_chat_review(session, token) end)
  assert {:error, :chat_review_unavailable} = Task.await(foreign)
  assert {:error, :chat_review_unavailable} = Ipse.Session.claim_chat_review(session, make_ref())
  assert :sys.get_state(session).pending_chat_review.state === :ready

  second_binding =
    if mode == "stale_cancel" do
      assert :ok = Ipse.Session.cancel(session)
      nil
    else
      assert :ok = Ipse.Session.prompt(session, "A separate ordinary followup.")
      second_token = Ipse.Test.ChatReviewLifecycle.ready(session)
      assert second_token !== token
      assert :ok = Ipse.Test.ChatReviewLifecycle.finished(session)
      refute_receive {:ipse, ^session, {:decision_card_unavailable, _}}, 0
      current = :sys.get_state(session).pending_chat_review
      assert current.token === second_token and current.state === :ready
      current.event
    end

  assert {:error, :chat_review_unavailable} = Ipse.Session.claim_chat_review(session, token)
  assert {:error, _} = Ipse.Session.ChatReviewHandoff.take(session, token)

  if second_binding do
    current = :sys.get_state(session).pending_chat_review
    assert current.state === :ready and current.event === second_binding
    assert :ok = Ipse.Session.cancel(session)
  end

  assert {:error, :operator_input_unavailable} = Ipse.Session.release_input_read(session, channel)
  assert nil === Map.get(:sys.get_state(session), :pending_chat_review)
  assert journals === Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"]))
  assert {:ok, metadata} = Ipse.CLI.Knowledge.Management.pending_metadata(runtime, cwd)
  assert Enum.any?(metadata["records"], &(&1["key"] == key))
  assert {:ok, project} = Ipse.Extension.ProjectIdentity.existing(home, cwd)

  assert {:ok, consent} =
           Ipse.Extension.Consent.existing_snapshot(
             Ipse.Extension.SemanticAdmission.control_root(home),
             project["project_id"]
           )

  refute Map.has_key?(consent["operations"], operation)

  if second_binding do
    assert Enum.any?(metadata["records"], &(&1["key"] == second_binding["event"]["pending_key"]))

    refute Map.has_key?(
             consent["operations"],
             Ipse.Session.ChatReviewHandoff.operation_id(second_binding)
           )
  end

  monitor = Process.monitor(reader)
  Process.exit(reader, :kill)
  assert_receive {:DOWN, ^monitor, :process, ^reader, _}, 5_000
  assert :ok = Ipse.Session.close_confirmed(session)
  assert {:ok, records} = Ipse.Journal.load(history, id)
  assert {:ok, _} = Ipse.Session.Saved.restore(records, id)
  assert :ok = Ipse.Session.ChatReviewHandoff.verify_source(binding, history, records)

  if second_binding,
    do:
      assert(
        :ok === Ipse.Session.ChatReviewHandoff.verify_source(second_binding, history, records)
      )

  expected = if(mode == "stale_cancel", do: 1, else: 2)
  assert Enum.count(records, &(&1["type"] == "pending_chat_review_handoff")) == expected
  assert Enum.count(records, &(&1["type"] == "pending_chat_capture_started")) == expected

  assert Enum.count(records, fn event ->
           event["type"] == "extension_invocation_result" and
             event["value"] == %{"status" => "nominated"}
         end) == if(mode == "stale_cancel", do: 1, else: 2)

  assert Enum.count(records, &(&1["type"] == "source_answer_committed")) ==
           if(mode == "stale_cancel", do: 1, else: 2)

  send(server.pid, {server_finished, self()})
  assert length(Task.await(server, 10_000)) == if(mode == "stale_cancel", do: 2, else: 4)
  IO.puts("SAME_REPLY_CHAT_#{String.upcase(mode)}_PASSED")
  System.halt(0)
end

watcher_owner = self()
watcher_finished = make_ref()

permissions =
  Task.async(fn ->
    deadline = System.monotonic_time(:millisecond) + 60_000
    {original, original_info} = Ipse.Test.ChatReviewLifecycle.session(nil, deadline)
    assert Ipse.Session.permissions(original)["workspace_edits"] === (mode != "planning_accept")

    if mode == "planning_accept" do
      assert original_info.execution_mode["ceiling"] === "planning"
    end

    monitor = Process.monitor(original)
    IO.puts("CHAT_INITIAL_AUTHORITY_CHECKED")

    if mode == "planning_accept" do
      wait_normal = fn wait_normal ->
        info = Ipse.Session.info(original)

        cond do
          info.execution_mode["ceiling"] === "normal" ->
            :ok

          System.monotonic_time(:millisecond) >= deadline ->
            flunk("planning exit did not become live normal mode")

          true ->
            Process.sleep(2)
            wait_normal.(wait_normal)
        end
      end

      :ok = wait_normal.(wait_normal)
      IO.puts("CHAT_PLAN_EXIT_MODE_CHECKED")
    end

    receive do
      {:DOWN, ^monitor, :process, ^original, _} -> :ok
    after
      60_000 -> flunk("original chat Session did not close for decision review")
    end

    {resumed, resumed_info} = Ipse.Test.ChatReviewLifecycle.session(original, deadline)
    assert resumed_info.id === original_info.id
    assert Ipse.Session.permissions(resumed)["workspace_edits"] === false
    assert resumed_info.execution_mode["ceiling"] === "normal"
    assert resumed_info.execution_mode["enclosing_ceiling"] === "normal"

    if mode == "same_followup" do
      before_followup =
        Ipse.Test.ChatReviewLifecycle.followup_snapshot(resumed, "before_followup")

      File.write!(Path.join(root, "before-followup.json"), Jason.encode!(before_followup))
      IO.puts("CHAT_RESUME_AUTHORITY_CHECKED")

      settled =
        Ipse.Test.ChatReviewLifecycle.settled_followup(
          resumed,
          before_followup["turn_id"],
          deadline
        )

      File.write!(Path.join(root, "settled-followup.json"), Jason.encode!(settled))
      IO.puts("CHAT_SAME_FOLLOWUP_SETTLED")
    else
      IO.puts("CHAT_RESUME_AUTHORITY_CHECKED")
    end

    # Terminal receives messages in the actual CLI caller. Complete this Task
    # only after that loop has returned, so it cannot consume our Task result.
    Ipse.Test.ChatReviewLifecycle.await_client_return(:ok, watcher_owner, watcher_finished)
  end)

startup_mode = if mode == "planning_accept", do: ["--planning"], else: ["--accept-edits"]
chat_status = Ipse.CLI.run(["chat"] ++ startup_mode ++ ["--state-dir", history] ++ options)
assert chat_status == 0
send(permissions.pid, {watcher_finished, self()})
assert :ok = Task.await(permissions, 5_000)

if mode == "same_followup" do
  # The optional third request is explicitly unblocked after the CLI has closed.
  # No effect or turn is retried when preflight prevented that request.
  :ok = :gen_tcp.close(listener)
  send(server.pid, {server_finished, self()})
  request_hashes = Task.await(server, 5_000)
  assert length(request_hashes) in [2, 3]
  [conversation] = Path.wildcard(Path.join(history, "*.jsonl"))
  id = Path.basename(conversation, ".jsonl")
  assert {:ok, records} = Ipse.Journal.load(history, id)

  strict_saved =
    case Ipse.Session.Saved.restore(records, id) do
      {:ok, _} ->
        "pass"

      {:error, reason} ->
        %{
          "status" => "refused",
          "reason_sha256" => Ipse.JSON.sha256(:erlang.term_to_binary(reason, [:deterministic]))
        }
    end

  [handoff] = Enum.filter(records, &(&1["type"] == "pending_chat_review_handoff"))
  assert Enum.count(records, &(&1["type"] == "pending_chat_capture_started")) == 1
  [management] = Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"]))
  management_id = Path.basename(management, ".jsonl")
  assert {:ok, management_records} = Ipse.Journal.load(Path.dirname(management), management_id)
  binding = hd(management_records)["metadata"]["chat_review_handoff"]
  assert binding["event"] === handoff
  assert :ok = Ipse.Session.ChatReviewHandoff.verify_source(binding, history, records)
  assert :ok = Ipse.Session.PendingAcceptance.validate_events(management_records, management_id)
  [accepted] = Enum.filter(management_records, &(&1["type"] == "pending_proposal_accepted"))
  assert Ipse.Session.ChatReviewHandoff.matches_facts?(binding, accepted["facts"])

  assert {:ok, resolved} =
           Ipse.Session.PendingAcceptance.resolve_committed(
             management_records,
             management_id,
             Ipse.JSON.digest([accepted])
           )

  settled = Jason.decode!(File.read!(Path.join(root, "settled-followup.json")))
  turn = settled["turn_id"]

  relevant_types =
    ~w(input_received turn_finished extension_event_result extension_invocation_intent extension_action_intent extension_action_result worker_input_intent worker_input_result managed_preflight_intent managed_preflight_result managed_preflight_refused inference_dispatch_intent managed_read_observed managed_output_release_result managed_output_release_cleanup managed_root_transition managed_action_output_withheld)

  timeline =
    for event <- records,
        event["type"] in relevant_types,
        do: %{
          "record" => Map.take(event, ~w(type version turn_id request_id phase status decision)),
          "record_sha256" => Ipse.JSON.digest([event]),
          "stage" => get_in(event, ["descriptor", "stage"]),
          "request_op" => get_in(event, ["request", "op"]),
          "outcome_status" =>
            if(is_map(event["outcome"]), do: event["outcome"]["status"], else: event["outcome"]),
          "dependencies" =>
            Enum.map(event["dependencies"] || [], fn dependency ->
              %{
                "version" => dependency["version"],
                "sha256" => Ipse.JSON.digest([dependency]),
                "collection" => dependency["collection"]
              }
            end),
          "verdicts" =>
            Enum.map(
              event["verdicts"] || get_in(event, ["projection", "verdicts"]) || [],
              fn verdict ->
                Map.merge(Map.take(verdict, ~w(dependency_sha256 status)), %{
                  "current_sha256" =>
                    if(verdict["current"], do: Ipse.JSON.digest([verdict["current"]]))
                })
              end
            )
        }

  result = %{
    "version" => 1,
    "kind" => "same_id_followup_diagnostic",
    "session_id" => id,
    "followup_turn_id" => turn,
    "provider_requests" => length(request_hashes),
    "provider_request_sha256" => request_hashes,
    "source_receipt" => binding["source"],
    "handoff_sha256" => Ipse.JSON.digest([binding]),
    "acceptance_event_sha256" => Ipse.JSON.digest([accepted]),
    "acceptance_receipt_sha256" => Ipse.JSON.digest([resolved.result["receipt"]]),
    "acceptance_receipt" =>
      Map.take(
        resolved.result["receipt"],
        ~w(version operation_id project generation floor floor_anchor root_sha256 request_sha256)
      ),
    "turn_statuses" =>
      Enum.map(Enum.filter(records, &(&1["type"] == "turn_finished")), & &1["status"]),
    "timeline" => timeline,
    "strict_saved" => strict_saved,
    "source_receipt_verified" => "pass",
    "close_confirmed" => "pass"
  }

  File.write!(Path.join(root, "same-id-followup-diagnostic.json"), Jason.encode!(result))

  if length(request_hashes) == 3 and strict_saved == "pass" and
       List.last(result["turn_statuses"]) == "ok" do
    input_positions =
      Enum.with_index(records)
      |> Enum.filter(fn {event, _} -> event["type"] == "input_received" end)

    [{_, _}, {_, position}] = input_positions
    assert {:ok, before_saved} = Ipse.Session.Saved.restore(Enum.take(records, position), id)
    assert {:ok, after_saved} = Ipse.Session.Saved.restore(records, id)

    assert Enum.take(after_saved.messages, length(before_saved.messages)) ===
             before_saved.messages

    assert Enum.count(records, &(&1["type"] == "inference_dispatch_intent")) == 3

    assert Enum.any?(records, fn event ->
             event["type"] == "managed_preflight_result" and
               get_in(event, ["projection", "type"]) == "managed_root_transition" and
               get_in(event, ["projection", "version"]) == 2
           end)

    assert {:ok, current_dependencies} =
             Ipse.Session.ManagedLineage.dependencies(
               after_saved.managed_lineage,
               after_saved.messages
             )

    assert Enum.any?(current_dependencies, &(&1["version"] == 6))
    IO.puts("SAME_REPLY_CHAT_SAME_FOLLOWUP_PASSED")
  end

  IO.puts("SAME_ID_FOLLOWUP_DIAGNOSTIC_COMPLETE requests=#{length(request_hashes)}")
  System.halt(0)
end

if mode === "reoffer" do
  [original_path] =
    Enum.filter(Path.wildcard(Path.join(history, "*.jsonl")), fn path ->
      {:ok, events} = Ipse.Journal.load(history, Path.basename(path, ".jsonl"))
      Enum.any?(events, &(&1["type"] === "pending_chat_review_handoff"))
    end)

  original_id = Path.basename(original_path, ".jsonl")
  IO.puts("CHAT_EXPLICIT_REOFFER_READY")
  assert 0 === Ipse.CLI.run(["chat", "--resume", original_id, "--state-dir", history] ++ options)
end

IO.puts("CHAT_FRESH_RECALL_READY")

assert 0 === Ipse.CLI.run(["chat", "--state-dir", history] ++ options)
send(server.pid, {server_finished, self()})
assert length(Task.await(server, 10_000)) == 3

[conversation] =
  Enum.filter(Path.wildcard(Path.join(history, "*.jsonl")), fn path ->
    {:ok, events} = Ipse.Journal.load(history, Path.basename(path, ".jsonl"))
    Enum.any?(events, &(&1["type"] === "pending_chat_review_handoff"))
  end)

id = Path.basename(conversation, ".jsonl")
assert {:ok, records} = Ipse.Journal.load(history, id)
assert {:ok, _} = Ipse.Session.Saved.restore(records, id)
[handoff] = Enum.filter(records, &(&1["type"] == "pending_chat_review_handoff"))
assert Enum.count(records, &(&1["type"] == "pending_chat_capture_started")) == 1
assert Enum.count(records, &(&1["type"] == "pending_proposal_nominated")) == 1
assert Enum.count(records, &(&1["type"] == "inference_dispatch_intent")) == 2
assert handoff["text"] == text and handoff["reason"] == reason
assert handoff["source_proof"]["session_id"] == id

{management, original_binding, reoffered} =
  if mode === "reoffer" do
    management_paths = Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"]))
    assert length(management_paths) === 2

    managements =
      Enum.map(management_paths, fn path ->
        {:ok, events} = Ipse.Journal.load(Path.dirname(path), Path.basename(path, ".jsonl"))
        {path, events}
      end)

    [{original_management, original_management_records}] =
      Enum.reject(managements, fn {_, events} ->
        hd(events)["metadata"]["chat_review_handoff"]["version"] === 2
      end)

    [{management, _}] =
      Enum.filter(managements, fn {_, events} ->
        hd(events)["metadata"]["chat_review_handoff"]["version"] === 2
      end)

    refute Enum.any?(original_management_records, &(&1["type"] === "pending_acceptance_intent"))

    assert :ok =
             Ipse.Session.PendingAcceptance.validate_events(
               original_management_records,
               Path.basename(original_management, ".jsonl")
             )

    [reoffered] = Enum.filter(records, &(&1["type"] === "pending_chat_review_reoffered"))
    assert reoffered["render_revision"] === 2
    assert reoffered["client_id"] !== handoff["client_id"]
    assert reoffered["client_generation"] !== handoff["client_generation"]
    {management, hd(original_management_records)["metadata"]["chat_review_handoff"], reoffered}
  else
    [management] = Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"]))
    {management, nil, nil}
  end

management_id = Path.basename(management, ".jsonl")
assert {:ok, management_records} = Ipse.Journal.load(Path.dirname(management), management_id)
binding = hd(management_records)["metadata"]["chat_review_handoff"]
assert binding["event"] === handoff

if mode === "reoffer" do
  assert binding["version"] === 2 and binding["review"] === reoffered
  assert Ipse.Session.ChatReviewHandoff.origin(binding) === original_binding

  refute Ipse.Session.ChatReviewHandoff.operation_id(binding) ===
           Ipse.Session.ChatReviewHandoff.operation_id(original_binding)

  assert :ok = Ipse.Session.ChatReviewHandoff.verify_history(binding, records)
end

assert :ok = Ipse.Session.ChatReviewHandoff.verify_source(binding, history, records)
assert :ok = Ipse.Session.PendingAcceptance.validate_events(management_records, management_id)
accepted = Enum.filter(management_records, &(&1["type"] == "pending_proposal_accepted"))
[consumer] = Path.wildcard(Path.join(history, "*.jsonl")) -- [conversation]
consumer_id = Path.basename(consumer, ".jsonl")
assert {:ok, consumer_records} = Ipse.Journal.load(history, consumer_id)
assert Enum.count(consumer_records, &(&1["type"] == "inference_dispatch_intent")) == 1

if mode in ~w(accept reoffer planning_accept) do
  assert [event] = accepted
  assert Ipse.Session.ChatReviewHandoff.matches_facts?(binding, event["facts"])
  assert event["facts"]["session_id"] === nil

  assert {:ok, %{event: ^event, result: %{"status" => "committed"}}} =
           Ipse.Session.PendingAcceptance.resolve_committed(
             management_records,
             management_id,
             Ipse.JSON.digest([event])
           )

  assert Enum.any?(consumer_records, fn record ->
           record["type"] == "managed_read_observed" and
             Enum.any?(record["dependencies"], &(&1["version"] == 6))
         end)
else
  assert accepted === []
  refute Enum.any?(management_records, &(&1["type"] == "pending_acceptance_intent"))
end

before_journals = Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"]))

assert {:error, _} =
         Ipse.CLI.Knowledge.Management.accept_chat_candidate(%{home: home}, cwd, history, binding)

assert before_journals === Path.wildcard(Path.join([home, "knowledge-management", "*.jsonl"]))
assert {:error, _} = Ipse.Session.ChatReviewHandoff.claim_management_attempt(binding)

assert {:ok, binding} = Ipse.Extension.ProjectIdentity.existing(home, cwd)

assert {:ok, snapshot} =
         Ipse.Extension.Consent.existing_snapshot(
           Ipse.Extension.SemanticAdmission.control_root(home),
           binding["project_id"]
         )

assert Enum.all?(snapshot["operations"], fn {_, operation} -> operation["status"] == "settled" end)

if mode === "reoffer" do
  alias Ipse.Session.ChatReviewHandoff, as: H
  wrapper = hd(management_records)["metadata"]["chat_review_handoff"]
  origin = H.origin(wrapper)

  foreign_event =
    Map.put(
      origin["event"],
      "pending_key",
      "pending." <> Ipse.JSON.sha256("different synthetic candidate")
    )

  {:ok, foreign_source} = Ipse.Journal.source(id, origin["source"]["byte_offset"], foreign_event)
  foreign_origin = %{"event" => foreign_event, "source" => foreign_source}

  foreign_review =
    wrapper["review"]
    |> Map.put("origin_source", foreign_source)
    |> Map.put("origin_sha256", Ipse.JSON.digest([foreign_origin]))

  {:ok, foreign_review_source} =
    Ipse.Journal.source(id, wrapper["review_source"]["byte_offset"], foreign_review)

  assert {:ok, foreign} = H.wrap_reoffer(foreign_origin, foreign_review, foreign_review_source)
  [header | tail] = management_records
  changed = [put_in(header, ["metadata", "chat_review_handoff"], foreign) | tail]
  assert {:error, _} = Ipse.Session.PendingAcceptance.validate_events(changed, management_id)

  assert {:ok, row} =
           Ipse.Extension.Consent.operation(
             Ipse.Extension.SemanticAdmission.control_root(home),
             binding["project_id"],
             H.operation_id(wrapper)
           )

  changed_row =
    row
    |> Map.put("id", H.operation_id(foreign))
    |> Map.put("request_sha256", Ipse.JSON.digest(["chat_pending_review", 1, foreign]))

  assert {:error, _} =
           Ipse.CLI.Knowledge.Management.chat_review_prior_state(foreign, changed_row, [
             %{id: management_id, records: changed}
           ])
end

IO.puts("SAME_REPLY_CHAT_#{String.upcase(mode)}_PASSED")
