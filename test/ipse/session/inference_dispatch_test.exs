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
