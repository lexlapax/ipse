Code.require_file("provider_fixture.ex", __DIR__)

defmodule Ipse.Test.ManagedApprovalSession do
  import ExUnit.Assertions
  alias Ipse.{Session, Journal, InferenceSlots}
  alias Ipse.Test.ProviderFixture
  alias Ipse.Extension.{Collection, Consent, ProjectIdentity, SemanticAdmission}

  def config(scenario) do
    response =
      ProviderFixture.ndjson([
        %{
          "model" => "fixture",
          "message" => %{
            "role" => "assistant",
            "content" => "",
            "tool_calls" => [
              %{
                "function" => %{
                  "name" => "write",
                  "arguments" => %{
                    "path" => "result.txt",
                    "content" => "Synthetic ordinary statement"
                  }
                }
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

  def run(config, cwd, home, dir, _records, original_id, scenario, active_session \\ nil) do
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

    starts = Enum.filter(events, &(&1["type"] == "tool_started"))

    if allowed or scenario in ~w(save_managed_approval_source_stale save_managed_approval_revoked) do
      assert [%{"name" => "write", "approval" => "approved"}] = starts
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
    if Process.alive?(consumer), do: assert(:ok = Session.close_confirmed(consumer))

    if scenario == "save_managed_approval_source_stale" do
      assert {:ok, lock} = Ipse.Runner.lock(Path.join(dir, original_id <> ".lock"))
      File.write!(source_path, original)
      assert :ok = Ipse.Runner.unlock(lock)
    end

    IO.puts("NATIVE_MANAGED_APPROVAL_SESSION_PASSED")
  end

  defp one_request?(scenario),
    do:
      scenario in ~w(save_managed_approval_source_stale save_managed_approval_revoked save_managed_approval_owner_loss save_managed_approval_cancel save_managed_approval_exit)

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
