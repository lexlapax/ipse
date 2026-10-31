Code.require_file("../../support/provider_fixture.ex", __DIR__)

defmodule Ipse.Session.InferenceDispatchTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, InferenceSlots, Usage}
  alias Ipse.Test.ProviderFixture

  setup do
    base = Path.join(System.tmp_dir!(), "ipse-session-dispatch-" <> Usage.id())
    root = Path.join(base, "project")
    home = Path.join(base, "operator")
    File.mkdir_p!(root)
    File.mkdir_p!(home)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(base) end)
    %{root: root, home: home, dir: Path.join(base, "sessions")}
  end

  defp config(c, base),
    do: %{
      provider: :ollama,
      model: "fixture",
      base_url: base,
      timeout_ms: 3000,
      home: c.home,
      approval: :deny,
      max_output_tokens: 32,
      inference_services: %{"local" => %{"version" => 1, "origins" => [base]}}
    }

  defp start(c, config) do
    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: c.root, state_dir: c.dir, subscriber: self()}
      )

    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    pid
  end

  defp supported?(c, config) do
    case InferenceSlots.status(config, cwd: c.root) do
      {:ok, _} ->
        true

      {:error, :service_filesystem_unsupported} ->
        pid = start(c, config)
        assert :ok = Session.prompt(pid, "Public synthetic input")
        assert_receive {:ipse, ^pid, {:done, :error}}, 5000
        assert {:ok, events} = Ipse.Journal.load(c.dir, Session.info(pid).id)
        refute Enum.any?(events, &(&1["type"] == "inference_dispatch_intent"))

        IO.puts(
          "#{c.test}: unsupported filesystem refused; positive protected Session journey NOT RUN"
        )

        false

      other ->
        flunk("slot bootstrap failed: #{inspect(other)}")
    end
  end

  defp body(message),
    do:
      Jason.encode!(%{
        "model" => "fixture",
        "message" => message,
        "done" => true,
        "done_reason" => "stop",
        "prompt_eval_count" => 1,
        "eval_count" => 1
      }) <> "\n"

  defp selector,
    do: %{
      "operation" => "main",
      "profile" => nil,
      "processing_region" => nil,
      "storage_region" => nil,
      "cache_retention" => nil,
      "account_controls" => nil
    }

  defp held(c, config) do
    parent = self()

    task =
      Task.async(fn ->
        InferenceSlots.run(
          config,
          selector(),
          %{
            "session_id" => Usage.id(),
            "project_id" => Ipse.JSON.sha256("other-project"),
            "request_sha256" => Ipse.JSON.sha256("synthetic"),
            "priority" => "foreground"
          },
          [cwd: c.root, wait_ms: 5000, dispatch_timeout_ms: 5000],
          fn _ ->
            send(parent, {:holding_service, self()})
            receive do: (:release_service -> {:settled, :released})
          end
        )
      end)

    assert_receive {:holding_service, holder}, 3000
    {task, holder}
  end

  test "a mismatched active admission cannot commit a replay-invalid dispatch intent", c do
    config = config(c, "http://127.0.0.1:11434")
    pid = start(c, config)
    state = :sys.get_state(pid)
    turn_id = Usage.id()
    admission = Usage.admission(state.id, state.config, "model", turn_id)

    synthetic = %{
      state
      | phase: :compaction,
        active_request: admission,
        turn_id: turn_id,
        task: %{pid: self()},
        compaction: %{summary_messages: []}
    }

    runtime = Session.Context.summary_config(synthetic.config)

    prepared =
      Session.InferenceDispatch.prepare(synthetic, runtime, [], [], "compaction", admission)

    assert {:ok, %{route: route}} =
             Ipse.InferenceDispatch.selection(synthetic.config, runtime, "main", nil)

    parent = self()

    :sys.replace_state(pid, fn owner_state ->
      mismatch = %{synthetic | task: %{pid: self()}}

      refused =
        Session.InferenceDispatch.commit(
          mismatch,
          self(),
          "compaction",
          admission,
          prepared.expected,
          %{"route" => route, "reservation_id" => Usage.id()}
        )

      send(parent, {:mismatched_control, refused})
      valid_admission = Usage.admission(owner_state.id, owner_state.config, "compaction", turn_id)
      valid = %{synthetic | active_request: valid_admission, task: %{pid: self()}}

      valid_prepared =
        Session.InferenceDispatch.prepare(valid, runtime, [], [], "compaction", valid_admission)

      Session.record(valid, valid_admission)

      result =
        Session.InferenceDispatch.commit(
          valid,
          self(),
          "compaction",
          valid_admission,
          valid_prepared.expected,
          %{"route" => route, "reservation_id" => Usage.id()}
        )

      send(parent, {:valid_control, result})
      owner_state
    end)

    assert_receive {:mismatched_control, {:reply, {:error, :inference_dispatch_refused}, _}}, 5000
    assert_receive {:valid_control, {:reply, {:ok, %{"intent_id" => _}}, _}}, 5000

    assert {:ok, events} = Ipse.Journal.load(c.dir, state.id)
    assert :ok = Session.InferenceDispatch.validate_events(events)
    assert Enum.count(events, &(&1["type"] == "inference_dispatch_intent")) == 1
    intent = Enum.find(events, &(&1["type"] == "inference_dispatch_intent"))
    admission = Enum.find(events, &(&1["type"] == "request_admitted"))
    assert Session.InferenceDispatch.valid_intent?(intent, admission)

    for malformed <- [Map.put(intent, "request_id", Usage.id()), Map.put(intent, "type", "other")] do
      refute Session.InferenceDispatch.valid_intent?(malformed, admission)
    end

    decision =
      Usage.admission(
        state.id,
        %{
          provider: :system_one_compatible,
          model: "fixture",
          operation: :decision,
          expected_model: "fixture",
          service_id: "local",
          execution: %{id: "decision"}
        },
        "extension",
        turn_id
      )

    decision_intent =
      Map.merge(intent, %{
        "request_id" => decision["request_id"],
        "attempt_id" => decision["attempt_id"],
        "admission_sha256" => Ipse.JSON.digest([decision]),
        "phase" => "decision.create",
        "service_id" => "local"
      })

    assert Session.InferenceDispatch.valid_intent?(decision_intent, decision)
    assert :ok = Session.InferenceDispatch.validate_events([decision, decision_intent])
    changed_service = Map.put(decision_intent, "service_id", "other")
    refute Session.InferenceDispatch.valid_intent?(changed_service, decision)

    assert {:error, :invalid_inference_dispatch_intent} =
             Session.InferenceDispatch.validate_events([decision, changed_service])
  end

  test "a terminal managed result seal binds one exact request, phase and native result", c do
    pid = start(c, config(c, "http://127.0.0.1:11434"))
    original = :sys.get_state(pid)
    admission = Usage.admission(original.id, original.config, "model", Usage.id())
    result = {:ok, %{"role" => "assistant", "content" => "Synthetic sealed output"}, %{}}
    {:ok, value, usage} = result
    sha = Ipse.JSON.digest([%{"value" => value, "usage" => usage}])
    seal = %{request_id: admission["request_id"], phase: "model", result_sha: sha, expected: %{}}

    state = %{
      original
      | active_request: admission,
        managed_lineage: {:error, :managed_lineage_unavailable},
        managed_result_seal: seal
    }

    assert {^result, consumed} = Session.InferenceDispatch.consume_result(state, "model", result)
    assert consumed.managed_result_seal == nil
    assert {{:error, _}, _} = Session.InferenceDispatch.consume_result(consumed, "model", result)

    assert {{:error, _}, _} =
             Session.InferenceDispatch.consume_result(
               state,
               "model",
               {:ok, Map.put(value, "content", "different"), usage}
             )

    assert {{:error, _}, _} =
             Session.InferenceDispatch.consume_result(
               %{state | managed_result_seal: %{seal | request_id: Usage.id()}},
               "model",
               result
             )

    assert {{:error, _}, _} =
             Session.InferenceDispatch.consume_result(
               %{state | managed_result_seal: %{seal | phase: "compaction"}},
               "model",
               result
             )

    assert {^result, _} = Session.InferenceDispatch.consume_result(original, "model", result)
  end

  test "actual main dispatch records intent before HTTP and releases before native read and next inference",
       c do
    File.write!(Path.join(c.root, "public.txt"), "Synthetic public source")

    tool = %{
      "role" => "assistant",
      "content" => "Checking",
      "tool_calls" => [
        %{"function" => %{"name" => "read", "arguments" => %{"path" => "public.txt"}}}
      ]
    }

    {base, server} =
      ProviderFixture.sequence([
        body(tool),
        body(%{"role" => "assistant", "content" => "Complete"})
      ])

    on_exit(fn -> if Process.alive?(server.pid), do: Process.exit(server.pid, :kill) end)
    config = config(c, base)

    if supported?(c, config) do
      pid = start(c, config)
      assert :ok = Session.prompt(pid, "Read the public fixture")
      assert_receive {:ipse, ^pid, {:tool, "read", _}}, 5000
      assert {:ok, state} = InferenceSlots.status(config, cwd: c.root)
      assert state["services"]["local"]["active"] == nil
      assert_receive {:ipse, ^pid, {:done, :ok}}, 5000
      assert [{_, _}, {_, _}] = Task.await(server)
      assert {:ok, events} = Ipse.Journal.load(c.dir, Session.info(pid).id)
      intents = Enum.filter(events, &(&1["type"] == "inference_dispatch_intent"))
      assert length(intents) == 2
      assert Enum.all?(intents, &(&1["phase"] == "model"))
      assert :ok = Session.InferenceDispatch.validate_events(events)
      assert {:ok, _} = Session.restore_context(events)
      intent = hd(intents)

      for malformed <- [
            Map.put(intent, "version", 1.0),
            Map.put(intent, "extra", true),
            Map.put(intent, "attempt_id", Usage.id()),
            Map.put(intent, "phase", "decision.create")
          ],
          do:
            assert(
              {:error, _} =
                Session.restore_context(
                  Enum.map(events, fn e -> if e == intent, do: malformed, else: e end)
                )
            )

      assert {:error, _} = Session.restore_context(events ++ [intent])
      admission = Enum.find(events, &(&1["type"] == "request_admitted"))

      for boundary <-
            ~w(input_received cancelled turn_finished lifecycle_epoch_started lifecycle_epoch_closed) do
        assert {:error, _} =
                 Session.InferenceDispatch.validate_events([
                   admission,
                   %{"type" => boundary},
                   intent
                 ])
      end

      assert {:error, _} = Ipse.Usage.restore(events ++ [intent])
      assert {:ok, state} = InferenceSlots.status(config, cwd: c.root)
      assert length(state["recent"]) == 2 and state["services"]["local"]["active"] == nil
    end
  end

  test "a queued source change and forged caller fail before provider IO or shared budget reservation",
       c do
    config =
      config(c, "http://127.0.0.1:11434")
      |> Map.put(:budget, %{
        "version" => 1,
        "max_requests" => 4,
        "max_input_tokens" => 100,
        "reserve_input_tokens" => 32,
        "max_output_tokens" => 100,
        "reserve_output_tokens" => 32
      })

    if supported?(c, config) do
      {held, holder} = held(c, config)
      pid = start(c, config)
      assert :ok = Session.prompt(pid, "Synthetic queued input")
      assert_receive {:ipse, ^pid, {:inference_service_status, %{"state" => "waiting"}}}, 5000
      state = :sys.get_state(pid)

      assert {:error, :inference_dispatch_refused} =
               GenServer.call(
                 pid,
                 {:inference_dispatch_intent, state.job_ref, "model", state.active_request, %{},
                  %{}}
               )

      assert {:ok, before} = Ipse.Usage.Budget.snapshot(state.config)
      assert before["request_count"] == 0
      # A trusted-host fixture changes the actual owner Writer's current source
      # generation while the inference task is queued; no worker supplies proof.
      :sys.replace_state(state.journal_writer, fn writer ->
        update_in(writer.source_window.index.policy_generation, &(&1 + 1))
      end)

      send(holder, :release_service)
      assert {:ok, :released} = Task.await(held, 5000)
      assert_receive {:ipse, ^pid, {:done, :error}}, 5000
      assert {:ok, budget} = Ipse.Usage.Budget.snapshot(state.config)
      assert budget["request_count"] == 0
      assert {:ok, events} = Ipse.Journal.load(c.dir, state.id)
      refute Enum.any?(events, &(&1["type"] == "inference_dispatch_intent"))
      refute Enum.any?(events, &(get_in(&1, ["message", "role"]) == "assistant"))
      assert {:ok, slots} = InferenceSlots.status(config, cwd: c.root)
      assert slots["services"]["local"]["active"] == nil
    end
  end

  test "queued cancellation never reserves provider budget or admits a dispatch intent", c do
    config = config(c, "http://127.0.0.1:11434")

    if supported?(c, config) do
      {held, holder} = held(c, config)
      pid = start(c, config)
      assert :ok = Session.prompt(pid, "Queued cancellation")
      assert_receive {:ipse, ^pid, {:inference_service_status, %{"state" => "waiting"}}}, 5000
      assert :ok = Session.cancel(pid)
      assert_receive {:ipse, ^pid, {:done, :cancelled}}, 5000
      send(holder, :release_service)
      assert {:ok, :released} = Task.await(held, 5000)
      assert {:ok, events} = Ipse.Journal.load(c.dir, Session.info(pid).id)
      refute Enum.any?(events, &(&1["type"] == "inference_dispatch_intent"))
    end
  end

  test "unknown provider outcome suppresses assistant text and blocks later Session requests",
       c do
    {base, server} = ProviderFixture.start("synthetic remote failure", 500, "", :whole)
    on_exit(fn -> if Process.alive?(server.pid), do: Process.exit(server.pid, :kill) end)
    config = config(c, base)

    if supported?(c, config) do
      pid = start(c, config)
      assert :ok = Session.prompt(pid, "Synthetic failure")
      assert_receive {:ipse, ^pid, {:done, :error}}, 5000
      Task.await(server)
      assert :ok = Session.prompt(pid, "A fresh request is not reconciliation")
      assert_receive {:ipse, ^pid, {:done, :error}}, 5000
      assert {:ok, events} = Ipse.Journal.load(c.dir, Session.info(pid).id)
      assert Enum.count(events, &(&1["type"] == "inference_dispatch_intent")) == 1
      refute Enum.any?(events, &(get_in(&1, ["message", "role"]) == "assistant"))
      refute_receive {:ipse, ^pid, {:text, _}}
      assert {:ok, slots} = InferenceSlots.status(config, cwd: c.root)
      assert is_map(slots["services"]["local"]["active"])
    end
  end

  test "a named local child uses the same actual service slot and releases before the parent resumes",
       c do
    delegate = %{
      "role" => "assistant",
      "content" => "",
      "tool_calls" => [
        %{
          "function" => %{
            "name" => "delegate",
            "arguments" => %{
              "task" => "Synthetic bounded task",
              "context" => "Public fixture",
              "profile" => "small"
            }
          }
        }
      ]
    }

    child =
      Jason.encode!(%{
        "model" => "fixture-child",
        "message" => %{"role" => "assistant", "content" => "Child complete"},
        "done" => true,
        "prompt_eval_count" => 1,
        "eval_count" => 1
      }) <> "\n"

    {base, server} =
      ProviderFixture.sequence([
        body(delegate),
        child,
        body(%{"role" => "assistant", "content" => "Parent complete"})
      ])

    on_exit(fn -> if Process.alive?(server.pid), do: Process.exit(server.pid, :kill) end)

    config =
      config(c, base)
      |> Map.merge(%{
        approval: :allow,
        subagents: true,
        subagent_concurrency: 1,
        profiles: %{
          "small" => %{
            "provider" => "ollama",
            "model" => "fixture-child",
            "base_url" => base,
            "timeout_ms" => 3000
          }
        },
        roles: %{}
      })

    if supported?(c, config) do
      pid = start(c, config)
      assert :ok = Session.prompt(pid, "Complete the public child task")
      assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
      assert [{_, first}, {_, second}, {_, third}] = Task.await(server)

      assert [first["model"], second["model"], third["model"]] == [
               "fixture",
               "fixture-child",
               "fixture"
             ]

      assert {:ok, events} = Ipse.Journal.load(c.dir, Session.info(pid).id)
      assert {:ok, children} = Ipse.Extension.ChildUsage.restore(events)
      [child] = Map.values(children.index)
      assert child["cleanup_confirmed"]

      assert {:ok, child_events} =
               Ipse.Journal.load(
                 Path.join([c.dir, "subagents", Session.info(pid).id]),
                 child["child_id"]
               )

      assert Enum.count(child_events, &(&1["type"] == "inference_dispatch_intent")) == 1
      assert {:ok, _} = Session.restore_context(child_events)
      assert {:ok, slots} = InferenceSlots.status(config, cwd: c.root)
      assert slots["services"]["local"]["active"] == nil and length(slots["recent"]) == 3
    end
  end

  test "actual compaction and main requests coordinate through one registered service", c do
    long = body(%{"role" => "assistant", "content" => String.duplicate("Synthetic ", 600)})

    summary =
      body(%{
        "role" => "assistant",
        "content" =>
          Jason.encode!(%{
            "decisions" => [],
            "facts" => ["Synthetic earlier findings"],
            "open_questions" => []
          })
      })

    {base, server} =
      ProviderFixture.sequence([
        long,
        long,
        summary,
        body(%{"role" => "assistant", "content" => "Complete"})
      ])

    on_exit(fn -> if Process.alive?(server.pid), do: Process.exit(server.pid, :kill) end)

    config =
      config(c, base) |> Map.merge(%{context_bytes: 80_000, compact_threshold_bytes: 30_000})

    if supported?(c, config) do
      pid = start(c, config)

      for n <- 1..3 do
        assert :ok = Session.prompt(pid, "Synthetic bounded turn #{n}")
        assert_receive {:ipse, ^pid, {:done, :ok}}, 5000
      end

      assert [_, _, {_, compact}, _] = Task.await(server)
      assert compact["format"]["type"] == "object"
      assert {:ok, events} = Ipse.Journal.load(c.dir, Session.info(pid).id)

      assert Enum.map(
               Enum.filter(events, &(&1["type"] == "inference_dispatch_intent")),
               & &1["phase"]
             ) == ~w(model model compaction model)

      assert Enum.any?(events, &(&1["type"] == "context_compacted"))
      assert {:ok, _} = Session.restore_context(events)
      assert {:ok, slots} = InferenceSlots.status(config, cwd: c.root)
      assert slots["services"]["local"]["active"] == nil and length(slots["recent"]) == 4
    end
  end
end
