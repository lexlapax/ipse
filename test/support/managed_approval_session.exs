Code.require_file("provider_fixture.ex", __DIR__)

defmodule Ipse.Test.ManagedApprovalSession do
  import ExUnit.Assertions
  alias Ipse.{Session, Journal, InferenceSlots}
  alias Ipse.Test.ProviderFixture
  alias Ipse.Extension.{Collection, Consent, ProjectIdentity, SemanticAdmission}

  def config(scenario) do
    proposal = proposal(scenario)

    response =
      ProviderFixture.ndjson([
        %{
          "model" => "fixture",
          "message" => %{
            "role" => "assistant",
            "content" => "",
            "tool_calls" => [
              %{
                "function" => proposal
              }
            ]
          },
          "done" => true,
          "prompt_eval_count" => 1,
          "eval_count" => 1
        }
      ])

    final =
      ProviderFixture.ndjson([
        %{
          "model" => "fixture",
          "message" => %{
            "role" => "assistant",
            "content" => "WRITE_DONE"
          },
          "done" => true,
          "prompt_eval_count" => 1,
          "eval_count" => 1
        }
      ])

    responses = if one_request?(scenario), do: [response], else: [response, final]
    owner = self()

    collector =
      spawn(fn ->
        {base, server} = ProviderFixture.sequence(responses, 60_000)
        send(owner, {:provider_fixture_ready, self(), base})
        requests = Task.await(server, 60_000)

        receive do
          {:requests, caller, ref} -> send(caller, {ref, requests})
        after
          60_000 -> raise "fixture requests were not collected"
        end
      end)

    base =
      receive do
        {:provider_fixture_ready, ^collector, base} -> base
      after
        5000 -> flunk("fixture provider did not start")
      end

    Process.put({__MODULE__, :server}, collector)

    %{
      "version" => 1,
      "settings" => %{"timeout_ms" => 15000, "compact" => false, "max_steps" => 2},
      "profiles" => %{
        "fixture" => %{
          "provider" => "ollama",
          "model" => "fixture",
          "base_url" => base,
          "timeout_ms" => 15000
        }
      },
      "roles" => %{"main" => "fixture"},
      "budget" => %{"version" => 1, "max_requests" => 2}
    }
  end

  def run(config, cwd, home, dir, records, original_id, scenario, active_session \\ nil) do
    tool_name = proposal(scenario)["name"]
    scenario = control_scenario(scenario)
    config = Map.drop(config, [:provider_module, :fixture_root])

    consumer =
      if is_pid(active_session) do
        active_session
      else
        assert {:ok, consumer} =
                 DynamicSupervisor.start_child(
                   Ipse.Sessions,
                   {Session, config: config, cwd: cwd, state_dir: dir, subscriber: self()}
                 )

        consumer
      end

    id = Session.info(consumer).id

    if active_session do
      receive do
        {:ipse, ^consumer, {:done, :cancelled}} -> :ok
      after
        0 -> :ok
      end
    end

    consumer =
      if scenario == "save_managed_approval_resume" do
        assert :ok = Session.close_confirmed(consumer)

        assert {:ok, resumed} =
                 DynamicSupervisor.start_child(
                   Ipse.Sessions,
                   {Session, config: config, cwd: cwd, state_dir: dir, id: id, subscriber: self()}
                 )

        assert :sys.get_state(resumed).lock_mode == :resume_share_v2
        resumed
      else
        consumer
      end

    actual = :sys.get_state(consumer).config
    assert actual.semantic_admission["status"] == "active"
    source_path = Path.join(dir, original_id <> ".jsonl")
    original = File.read!(source_path)

    input_owners =
      if scenario == "save_managed_approval",
        do: inspect_worker_input(consumer, actual, home, dir, original_id, records)

    {:ok, watcher} =
      Task.start(fn ->
        input_control(consumer, actual, cwd, home, dir, original_id, original, scenario)
        File.write!(Path.join(Path.dirname(home), "managed-approval-watcher-done"), "checked")
      end)

    IO.puts("IPSE_MANAGED_APPROVAL_CLI_READY")

    assert if(scenario == "save_managed_approval_owner_loss", do: 1, else: 0) ==
             Ipse.CLI.Terminal.interact(
               consumer,
               Process.monitor(consumer),
               true,
               "Write the saved ordinary statement to result.txt, then finish.",
               cwd
             )

    wait_for(
      Path.join(Path.dirname(home), "managed-approval-watcher-done"),
      System.monotonic_time(:millisecond) + 1000
    )

    watcher_ref = Process.monitor(watcher)
    assert_receive {:DOWN, ^watcher_ref, :process, ^watcher, watcher_reason}, 1000
    assert watcher_reason in [:normal, :noproc]

    allowed =
      scenario in ~w(save_managed_approval save_managed_approval_active save_managed_approval_resume save_managed_approval_delayed)

    if allowed do
      assert File.read!(Path.join(cwd, "result.txt")) == "Synthetic ordinary statement"
    else
      refute File.exists?(Path.join(cwd, "result.txt"))
    end

    if active_session do
      assert String.starts_with?(File.read!(source_path), original)
    else
      assert File.read!(source_path) ==
               if(scenario == "save_managed_approval_source_stale",
                 do: original <> "{partial",
                 else: original
               )
    end

    assert {:ok, events} = Journal.load(dir, id)
    assert {:ok, _} = Session.Saved.restore(events, id)

    if tool_name == "shell" do
      admissions = Enum.filter(events, &(&1["type"] == "managed_tool_effect_admitted"))

      if allowed do
        assert [admitted] = admissions
        assert admitted["binding"]["name"] == "shell"

        assert [%{"status" => "confirmed", "effect_id" => effect_id}] =
                 Enum.filter(events, &(&1["type"] == "managed_tool_effect_cleanup"))

        assert effect_id == admitted["effect_id"]

        assert [%{"decision" => "current"}] =
                 Enum.filter(events, &(&1["type"] == "managed_tool_result_release"))
      else
        assert admissions == []
      end
    end

    starts = Enum.filter(events, &(&1["type"] == "tool_started"))

    if allowed or scenario in ~w(save_managed_approval_source_stale save_managed_approval_revoked) do
      assert [%{"name" => ^tool_name, "approval" => "approved"}] = starts
    else
      assert starts == []
    end

    count = if one_request?(scenario), do: 1, else: 2
    assert Enum.count(events, &(&1["type"] == "request_admitted")) == count

    assert Enum.all?(
             Enum.filter(events, &(&1["type"] == "request_finished")),
             &(&1["outcome"] == "completed" and &1["finality"] == "final")
           )

    assert {:ok, budget} = Ipse.Usage.Budget.saved(dir, id)
    assert budget["unknown_liability_count"] == 0 and budget["request_count"] == count
    assert {:ok, ledger} = InferenceSlots.status(actual, cwd: cwd)
    assert Enum.all?(ledger["services"], fn {_, service} -> service["active"] == nil end)
    request_ref = make_ref()
    send(Process.get({__MODULE__, :server}), {:requests, self(), request_ref})

    requests =
      receive do
        {^request_ref, requests} -> requests
      after
        5000 -> flunk("fixture request collection did not finish")
      end

    assert length(requests) == count
    assert Jason.encode!(elem(hd(requests), 1)) =~ "Synthetic ordinary statement"

    if tool_name == "shell" and allowed do
      {_, continuation} = List.last(requests)
      assert [result] = Enum.filter(continuation["messages"], &(&1["role"] == "tool"))
      assert result["content"] =~ "NATIVE_SHELL_RESULT"
    end

    if input_owners do
      ref = make_ref()
      send(input_owners.pid, {:inspection_result, self(), ref})
      assert_receive {^ref, :owners_checked}, 5_000
      assert :owners_checked == Task.await(input_owners, 5_000)
    end

    if Process.alive?(consumer), do: assert(:ok = Session.close_confirmed(consumer))

    if scenario == "save_managed_approval_source_stale" do
      assert {:ok, lock} = Ipse.Runner.lock(Path.join(dir, original_id <> ".lock"))
      File.write!(source_path, original)
      assert :ok = Ipse.Runner.unlock(lock)
    end

    if tool_name == "shell" do
      assert {:ok, closed} = Journal.load(dir, id)
      assert {:ok, saved} = Session.Saved.restore(closed, id)

      assert {:ok, resumed} =
               DynamicSupervisor.start_child(
                 Ipse.Sessions,
                 {Session, config: config, cwd: cwd, state_dir: dir, subscriber: self(), id: id}
               )

      assert Session.info(resumed).phase == :idle
      assert :sys.get_state(resumed).messages == saved.messages
      assert {:ok, opened} = Journal.load(dir, id)
      assert Enum.take(opened, length(closed)) == closed
      assert [marker] = Enum.drop(opened, length(closed))
      assert Session.ReleaseReceipt.valid_owner_marker?(marker, id)
      assert :ok = Session.close_confirmed(resumed)

      assert {:ok, %{"release_claim" => "signed_release_claim"}} =
               Session.Saved.inspect_saved(dir, id)

      if allowed,
        do: assert(File.read!(Path.join(cwd, "result.txt")) == "Synthetic ordinary statement"),
        else: refute(File.exists?(Path.join(cwd, "result.txt")))
    end

    IO.puts("NATIVE_MANAGED_APPROVAL_SESSION_PASSED")
  end

  # Pause the real controller immediately before its actual pipe write. All
  # handles come from the executing Session/publisher; none is manufactured.
  defp inspect_worker_input(consumer, config, home, dir, original_id, records) do
    expected = Map.new(records, &{&1["key"], &1})

    checker =
      Task.async(fn ->
        result =
          receive do
            {:worker_pipe_waiting, controller, cap, frame} ->
              try do
                assert cap.controller == controller and cap.depth == 3
                state = :sys.get_state(consumer)
                barrier = state.share_barrier
                assert is_binary(barrier.worker_input)
                assert barrier.writer_control == :transferred
                assert barrier.owner_phase == :transferred
                pending = state.invocation.worker_input
                assert pending.caller == cap.owner
                assert Enum.any?(pending.snapshot.dependencies, &(&1["version"] == 4))
                assert pending.binding.frame === frame
                <<size::32, bytes::binary-size(size)>> = frame
                assert %{"stage" => "host.actions", "payload" => payload} = Jason.decode!(bytes)
                record = get_in(payload, ["outcome", "value", "record"])
                assert record === expected[record["key"]]
                [proof] = get_in(record, ["value", "evidence", "sources"])
                assert proof["session_id"] == original_id
                assert record["value"]["text"] === proof["quote"]
                worker = :sys.get_state(pending.worker)
                assert worker.input.phase == :exported
                pipe = worker.input.binding.pipe
                assert pipe.pid == pending.binding.native_pid
                assert Port.info(cap.port, :connected) == {:connected, controller}
                assert {:os_pid, supervisor} = Port.info(cap.port, :os_pid)
                native = barrier.owner_recipient
                assert native != supervisor and barrier.writer_recipient == native
                helper = File.stat!("/proc/#{supervisor}/exe")
                actual_helper = File.stat!("/proc/#{native}/exe")

                assert {actual_helper.major_device, actual_helper.inode} ==
                         {helper.major_device, helper.inode}

                identities =
                  for fd <- File.ls!("/proc/#{native}/fd"),
                      {:ok, stat} <- [File.stat("/proc/#{native}/fd/#{fd}")],
                      do: {stat.major_device, stat.inode}

                pin = config.semantic_admission["pin"]

                paths = [
                  Path.join([home, "project-identities", ".lock"]),
                  Path.join([SemanticAdmission.control_root(home), pin["project_id"], ".lock"]),
                  Path.join([SemanticAdmission.collection_root(home), pin["namespace"], ".lock"]),
                  Path.join(dir, state.id <> ".lock"),
                  Path.join(dir, original_id <> ".lock")
                ]

                for path <- paths do
                  stat = File.stat!(path)
                  assert {stat.major_device, stat.inode} in identities
                end

                writer = :sys.get_state(state.journal_writer).share_barrier.writer_control
                assert {writer.device, writer.inode} in identities
                assert {:os_pid, session_control} = Port.info(barrier.owner_port, :os_pid)
                control = File.stat!("/proc/#{session_control}/fd/0")
                assert {control.major_device, control.inode} in identities
                assert {pipe.device, pipe.inode} in identities
                assert {:error, _} = Ipse.Runner.lock(Path.join(dir, original_id <> ".lock"))
                :owners_checked
              after
                send(controller, :release_worker_pipe)
              end
          after
            30_000 -> flunk("no original-source Worker input reached the native writer")
          end

        # Terminal consumes client events from its mailbox. Hold the Task result
        # until its caller has returned from that loop and explicitly asks.
        receive do
          {:inspection_result, caller, ref} -> send(caller, {ref, result})
        after
          30_000 -> flunk("Worker input inspection result was not collected")
        end

        result
      end)

    hook = fn
      true, _, _ ->
        true

      _,
      {:in, {_, {publisher, _}, {:session_control_ticket_worker_input, _, _, _, proofs, _}}},
      _ ->
        if Enum.any?(proofs, &(&1["session_id"] == original_id)) do
          {:dictionary, dictionary} = Process.info(publisher, :dictionary)
          {_, controller} = List.keyfind(dictionary, {Ipse.Runner.Transaction, :controller}, 0)

          gate = fn
            :released, _, _ ->
              :released

            _, {:in, {_, _, {:pipe_write, cap, _, frame}}}, _ ->
              send(checker.pid, {:worker_pipe_waiting, self(), cap, frame})

              receive do
                :release_worker_pipe -> :released
              after
                5_000 -> flunk("native Worker input ownership inspection did not finish")
              end

            state, _, _ ->
              state
          end

          assert :ok = :sys.install(controller, {gate, nil})
          true
        else
          false
        end

      state, _, _ ->
        state
    end

    assert :ok = :sys.install(consumer, {hook, false})
    checker
  end

  defp one_request?(scenario),
    do:
      control_scenario(scenario) in ~w(save_managed_approval_source_stale save_managed_approval_revoked save_managed_approval_owner_loss save_managed_approval_cancel save_managed_approval_exit)

  defp proposal("save_managed_approval_shell" <> _) do
    %{
      "name" => "shell",
      "arguments" => %{
        "command" =>
          "printf '%s' 'Synthetic ordinary statement' > result.txt; printf NATIVE_SHELL_RESULT",
        "timeout_ms" => 2000
      }
    }
  end

  defp proposal(_) do
    %{
      "name" => "write",
      "arguments" => %{"path" => "result.txt", "content" => "Synthetic ordinary statement"}
    }
  end

  defp control_scenario("save_managed_approval_shell" <> suffix),
    do: "save_managed_approval" <> suffix

  defp control_scenario(scenario), do: scenario

  defp input_control(consumer, actual, cwd, home, dir, original_id, original, scenario) do
    root = Path.dirname(home)

    wait_for(
      Path.join(root, "managed-approval-input-ready"),
      System.monotonic_time(:millisecond) + 15_000
    )

    state = :sys.get_state(consumer)
    assert state.phase == :managed_approval and state.share_barrier.phase == :review_input
    assert {:error, _} = Session.approve(consumer, make_ref(), true)
    assert {:ok, binding} = ProjectIdentity.existing(home, cwd)
    pin = actual.semantic_admission["pin"]
    control = SemanticAdmission.control_root(home)
    assert {:ok, snapshot} = Consent.existing_snapshot(control, binding["project_id"])

    assert {:ok, :checked} =
             Collection.with_managed_read(
               SemanticAdmission.collection_root(home),
               pin["namespace"],
               fn _, _, alive ->
                 assert :ok = alive.()
                 {:ok, :checked}
               end
             )

    if scenario == "save_managed_approval_active" do
      assert state.id == original_id
      assert length(state.share_barrier.snapshot.verified_sources) == 3
      assert {:error, _} = Ipse.Runner.lock(Path.join(dir, original_id <> ".lock"))
    else
      assert {:ok, lock} = Ipse.Runner.lock(Path.join(dir, original_id <> ".lock"))

      if scenario == "save_managed_approval_source_stale",
        do: File.write!(Path.join(dir, original_id <> ".jsonl"), original <> "{partial")

      assert :ok = Ipse.Runner.unlock(lock)
    end

    if scenario == "save_managed_approval_revoked",
      do: assert({:ok, _} = Consent.revoke(control, binding["project_id"], snapshot["epoch"]))

    if scenario == "save_managed_approval_delayed", do: Process.sleep(6000)
    if scenario == "save_managed_approval_owner_loss", do: Process.exit(consumer, :kill)
    File.write!(Path.join(root, "managed-approval-control-checked"), "checked")

    unless scenario == "save_managed_approval_owner_loss" do
      wait_idle(consumer, System.monotonic_time(:millisecond) + 15_000)
      File.write!(Path.join(root, "managed-approval-exit-ready"), "ready")
    end

    :checked
  end

  defp wait_idle(consumer, deadline) do
    unless :sys.get_state(consumer).phase == :idle do
      assert System.monotonic_time(:millisecond) < deadline
      Process.sleep(5)
      wait_idle(consumer, deadline)
    end
  end

  defp wait_for(path, deadline) do
    unless File.exists?(path) do
      assert System.monotonic_time(:millisecond) < deadline
      Process.sleep(5)
      wait_for(path, deadline)
    end
  end
end
