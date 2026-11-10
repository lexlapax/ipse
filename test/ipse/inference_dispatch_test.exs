Code.require_file("../support/provider_fixture.ex", __DIR__)

defmodule Ipse.InferenceDispatchTest do
  use ExUnit.Case, async: false
  alias Ipse.{InferenceDispatch, InferenceSlots, Usage}
  alias Ipse.Test.ProviderFixture

  setup do
    base = Path.join(System.tmp_dir!(), "ipse-dispatch-" <> Usage.id())
    home = Path.join(base, "operator")
    cwd = Path.join(base, "project")
    sessions = Path.join(base, "sessions")
    for path <- [home, cwd, sessions], do: File.mkdir_p!(path)
    File.chmod!(home, 0o700)
    File.chmod!(sessions, 0o700)
    on_exit(fn -> File.rm_rf!(base) end)
    %{base: base, home: home, cwd: cwd, sessions: sessions}
  end

  defp config(c, base),
    do: %{
      provider: :ollama,
      model: "fixture",
      base_url: base,
      timeout_ms: 2000,
      home: c.home,
      max_output_tokens: 32,
      extensions: [%{identity: %{"capabilities" => ~w(host.model host.embedding)}}],
      inference_services: %{"local" => %{"version" => 1, "origins" => [base]}},
      embedding_profiles: %{
        "search" => %{
          "operation" => "embedding",
          "provider" => "ollama",
          "model" => "fixture-embed",
          "base_url" => base,
          "dimensions" => 2,
          "dimension_mode" => "native",
          "timeout_ms" => 2000
        }
      }
    }

  defp context(c, runtime, session \\ Usage.id()) do
    admission =
      Usage.admission(
        session,
        runtime,
        if(runtime[:operation] == :embedding, do: "extension", else: "model"),
        Usage.id()
      )

    %{
      cwd: c.cwd,
      session_id: session,
      project_id: Ipse.JSON.sha256(c.cwd),
      request_sha256: Ipse.JSON.digest([admission]),
      priority: "foreground",
      wait_ms: 2000,
      admission: admission
    }
  end

  defp checked(c, config, fun) do
    case InferenceSlots.status(config, cwd: c.cwd) do
      {:ok, _} ->
        fun.()

      {:error, :service_filesystem_unsupported} ->
        parent = self()

        assert {:error, message} =
                 InferenceDispatch.run(
                   config,
                   config,
                   "main",
                   nil,
                   context(c, config),
                   fn _ -> :ok end,
                   fn _ ->
                     send(parent, :unexpected_gate)
                     {:ok, nil}
                   end,
                   fn _, _, _ ->
                     send(parent, :unexpected_dispatch)
                     :unknown
                   end
                 )

        assert message =~ "filesystem is unsupported"
        refute_received :unexpected_gate
        refute_received :unexpected_dispatch
        IO.puts("#{c.test}: unsupported filesystem refusal; selected positive dispatch NOT RUN")

      result ->
        flunk("bootstrap failed: #{inspect(result)}")
    end
  end

  defp text_body,
    do:
      Jason.encode!(%{
        "model" => "fixture",
        "message" => %{"role" => "assistant", "content" => "complete"},
        "done" => true,
        "done_reason" => "stop",
        "prompt_eval_count" => 1,
        "eval_count" => 1
      }) <> "\n"

  defp execute(runtime, emit, _),
    do: Ipse.Provider.complete(runtime, [%{"role" => "user", "content" => "synthetic"}], [], emit)

  test "registered main and embedding routes release one service before subsequent tool inference",
       c do
    {base, server} =
      ProviderFixture.sequence([
        text_body(),
        Jason.encode!(%{
          "model" => "fixture-embed",
          "embeddings" => [[1.0, 0.5]],
          "prompt_eval_count" => 1
        })
      ])

    on_exit(fn -> if Process.alive?(server.pid), do: Process.exit(server.pid, :kill) end)

    config = config(c, base)

    checked(c, config, fn ->
      caller = self()

      gate = fn _ ->
        assert self() == caller
        {:ok, %{checked: true}}
      end

      assert {:ok, %{"content" => "complete"}, _} =
               InferenceDispatch.run(
                 config,
                 config,
                 "main",
                 nil,
                 context(c, config),
                 fn
                   {:text, _} ->
                     assert {:ok, released} = InferenceSlots.status(config, cwd: c.cwd)
                     assert released["services"]["local"]["active"] == nil

                   _ ->
                     :ok
                 end,
                 gate,
                 fn runtime, emit, prepared ->
                   assert prepared == %{checked: true}
                   execute(runtime, emit, nil)
                 end
               )

      assert {:ok, state} = InferenceSlots.status(config, cwd: c.cwd)
      assert state["services"]["local"]["active"] == nil

      assert {:ok, embedding, _} =
               Ipse.Config.Profiles.prepare_embedding(config, %{
                 "profile" => "search",
                 "timeout_ms" => 2000
               })

      assert {:ok, %{"kind" => "embedding"}, _} =
               InferenceDispatch.run(
                 config,
                 embedding,
                 "embedding.create",
                 "search",
                 context(c, embedding),
                 fn _ -> :ok end,
                 gate,
                 fn selected, emit, _ ->
                   Ipse.Provider.request_embedding(selected, ["input"], emit)
                 end
               )

      assert {:ok, state} = InferenceSlots.status(config, cwd: c.cwd)
      assert state["services"]["local"]["active"] == nil and length(state["recent"]) == 2
      assert [{headers, _}, {embed_headers, _}] = Task.await(server)
      assert headers =~ "POST /api/chat HTTP/1.1"
      assert embed_headers =~ "POST /api/embed HTTP/1.1"
    end)
  end

  test "unknown native completion preserves original error and blocks a second route without HTTP",
       c do
    {base, server} = ProviderFixture.start("synthetic remote failure", 500, "", :whole)
    on_exit(fn -> if Process.alive?(server.pid), do: Process.exit(server.pid, :kill) end)
    config = config(c, base)

    checked(c, config, fn ->
      assert {:error, error} =
               InferenceDispatch.run(
                 config,
                 config,
                 "main",
                 nil,
                 context(c, config),
                 fn _ -> :ok end,
                 fn _ -> {:ok, nil} end,
                 &execute/3
               )

      assert error =~ "unknown outcome" and error =~ "Provider returned HTTP 500"
      Task.await(server)
      parent = self()

      assert {:error, error} =
               InferenceDispatch.run(
                 config,
                 config,
                 "main",
                 nil,
                 context(c, config),
                 fn _ -> :ok end,
                 fn _ ->
                   send(parent, :unexpected_gate)
                   {:ok, nil}
                 end,
                 fn _, _, _ ->
                   send(parent, :unexpected_dispatch)
                   {:ok, %{}, %{}}
                 end
               )

      assert error =~ "unknown outcome"
      refute_received :unexpected_gate
      refute_received :unexpected_dispatch
    end)
  end

  @tag :native_storage
  test "postqueue refusal retains its booking and a fresh admission cannot reuse it", c do
    config =
      config(c, "http://127.0.0.1:11434")
      |> Map.put(:budget, %{
        "version" => 1,
        "max_requests" => 1,
        "max_input_tokens" => 100,
        "reserve_input_tokens" => 32,
        "max_output_tokens" => 100,
        "reserve_output_tokens" => 32
      })

    session = Usage.id()
    assert {:ok, config} = Ipse.Usage.BudgetStore.attach(config, c.sessions, session, true)

    checked(c, config, fn ->
      parent = self()

      assert {:error, message} =
               InferenceDispatch.run(
                 config,
                 config,
                 "main",
                 nil,
                 context(c, config, session),
                 fn _ -> :ok end,
                 fn _ -> {:error, :source_changed} end,
                 fn _, _, _ ->
                   send(parent, :unexpected_dispatch)
                   {:ok, %{}, %{}}
                 end
               )

      assert message =~ "validation changed"
      refute_received :unexpected_dispatch
      assert {:ok, budget} = Ipse.Usage.Budget.snapshot(config)
      assert budget["request_count"] == 1
      assert budget["unsettled_count"] == 1
      assert budget["unknown_liability_count"] == 1
      assert budget["refused_count"] == 0
      assert booked(budget) == %{"requests" => 1, "input_tokens" => 32, "output_tokens" => 32}
      assert {:ok, state} = InferenceSlots.status(config, cwd: c.cwd)
      assert state["services"]["local"]["active"] == nil and state["queue"] == []
      assert state["recent"] == []

      assert {:error, error} =
               InferenceDispatch.run(
                 config,
                 config,
                 "main",
                 nil,
                 context(c, config, session),
                 fn _ -> :ok end,
                 fn _ -> flunk("exhausted budget reached the service gate") end,
                 fn _, _, _ -> flunk("exhausted budget dispatched") end
               )

      assert error =~ "Budget admission refused"
      assert {:ok, after_refusal} = Ipse.Usage.Budget.snapshot(config)
      assert after_refusal["request_count"] == 1
      assert after_refusal["refused_count"] == 1
      assert after_refusal["unsettled_count"] == 1
      assert after_refusal["unknown_liability_count"] == 1
      assert booked(after_refusal) == booked(budget)
      assert after_refusal["policy_sha256"] == budget["policy_sha256"]
      assert {:ok, ^state} = InferenceSlots.status(config, cwd: c.cwd)
    end)
  end

  test "selected default120s refuses visibly while unregistered and demo retain their direct path",
       c do
    config = config(c, "http://127.0.0.1:11434") |> Map.put(:timeout_ms, 120_000)

    assert {:error, message} =
             InferenceDispatch.run(
               config,
               config,
               "main",
               nil,
               context(c, config),
               fn _ -> :ok end,
               fn _ -> flunk("unsupported selected timeout reached gate") end,
               fn _, _, _ -> flunk("unsupported selected timeout dispatched") end
             )

    assert message =~ "100000" and message =~ "unsupported"
    refute File.exists?(Path.join(c.home, "inference-services"))

    config = %{config | inference_services: %{}}

    assert :legacy =
             InferenceDispatch.run(
               config,
               config,
               "main",
               nil,
               context(c, config),
               fn _ -> :ok end,
               fn _ -> flunk("unregistered path changed") end,
               fn _, _, nil -> :legacy end
             )

    assert {:ok, :unregistered} =
             InferenceDispatch.selection(%{}, %{provider: :demo}, "main", nil)
  end

  @tag :native_storage
  test "a retained pre-callback booking and a fresh admission use two requests for one HTTP call",
       c do
    {base, server} = ProviderFixture.start(text_body(), 200, "", :whole)
    on_exit(fn -> if Process.alive?(server.pid), do: Process.exit(server.pid, :kill) end)

    config =
      config(c, base)
      |> Map.put(:budget, %{
        "version" => 1,
        "max_requests" => 2,
        "max_input_tokens" => 100,
        "reserve_input_tokens" => 32,
        "max_output_tokens" => 100,
        "reserve_output_tokens" => 32
      })

    id = Usage.id()
    assert {:ok, config} = Ipse.Usage.BudgetStore.attach(config, c.sessions, id, true)

    checked(c, config, fn ->
      parent = self()
      first_context = context(c, config, id)

      assert {:error, error} =
               InferenceDispatch.run(
                 config,
                 config,
                 "main",
                 nil,
                 first_context,
                 fn _ -> :ok end,
                 fn _ -> {:error, :source_changed} end,
                 fn _, _, _ ->
                   send(parent, :unexpected_budget_dispatch)
                   flunk("postqueue refusal dispatched")
                 end
               )

      assert error =~ "validation changed"
      refute_received :unexpected_budget_dispatch
      assert {:ok, state} = InferenceSlots.status(config, cwd: c.cwd)
      assert state["services"]["local"]["active"] == nil
      assert state["recent"] == []
      assert {:ok, before_fresh} = Ipse.Usage.Budget.snapshot(config)
      assert before_fresh["request_count"] == 1
      assert before_fresh["unsettled_count"] == 1

      assert booked(before_fresh) == %{
               "requests" => 1,
               "input_tokens" => 32,
               "output_tokens" => 32
             }

      fresh_context = context(c, config, id)
      refute fresh_context.admission == first_context.admission

      assert {:ok, _, _} =
               InferenceDispatch.run(
                 config,
                 config,
                 "main",
                 nil,
                 fresh_context,
                 fn _ -> :ok end,
                 fn _ -> {:ok, nil} end,
                 &execute/3
               )

      assert {headers, _} = Task.await(server)
      assert headers =~ "POST /api/chat"
      assert {:ok, budget} = Ipse.Usage.Budget.snapshot(config)
      assert budget["request_count"] == 2
      assert budget["refused_count"] == 0
      assert budget["unsettled_count"] == 1
      assert budget["unknown_liability_count"] == 1
      assert budget["overdrawn"] == false
      assert booked(budget) == %{"requests" => 2, "input_tokens" => 33, "output_tokens" => 33}
      assert budget["policy_sha256"] == before_fresh["policy_sha256"]
      assert {:ok, final_state} = InferenceSlots.status(config, cwd: c.cwd)
      assert final_state["services"]["local"]["active"] == nil and final_state["queue"] == []

      assert [receipt] = final_state["recent"]
      assert receipt["status"] == "settled"
    end)
  end

  defp booked(snapshot),
    do: Map.new(snapshot["dimensions"], &{&1["unit"], &1["booked"]})

  test "visible text from an incomplete native stream is withheld when its slot becomes unknown",
       c do
    body =
      Jason.encode!(%{
        "model" => "fixture",
        "message" => %{"role" => "assistant", "content" => "Unpublished synthetic text"},
        "done" => false
      }) <> "\n"

    {base, server} = ProviderFixture.start(body, 200, "", :whole)
    on_exit(fn -> if Process.alive?(server.pid), do: Process.exit(server.pid, :kill) end)
    config = config(c, base)

    checked(c, config, fn ->
      parent = self()

      assert {:error, error} =
               InferenceDispatch.run(
                 config,
                 config,
                 "main",
                 nil,
                 context(c, config),
                 fn event -> send(parent, {:buffered_test_event, event}) end,
                 fn _ -> {:ok, nil} end,
                 &execute/3
               )

      assert error =~ "unknown outcome"

      assert_receive {:buffered_test_event,
                      {:inference_service_timing, %{"upstream_first_text_ms" => elapsed}}}

      assert is_integer(elapsed) and elapsed >= 0
      refute_received {:buffered_test_event, {:text, _}}
      Task.await(server)
      assert {:ok, state} = InferenceSlots.status(config, cwd: c.cwd)
      assert is_map(state["services"]["local"]["active"])
    end)
  end

  @tag :native_storage
  test "native embedding completion settles its service even when final budget liability rejects publication",
       c do
    body =
      Jason.encode!(%{
        "model" => "fixture-embed",
        "embeddings" => [[1.0, 0.5]],
        "prompt_eval_count" => 2
      })

    {base, server} = ProviderFixture.start(body, 200, "", :whole)
    on_exit(fn -> if Process.alive?(server.pid), do: Process.exit(server.pid, :kill) end)

    config =
      config(c, base)
      |> Map.put(:budget, %{
        "version" => 1,
        "max_requests" => 2,
        "max_input_tokens" => 1,
        "reserve_input_tokens" => 1
      })

    id = Usage.id()
    assert {:ok, config} = Ipse.Usage.BudgetStore.attach(config, c.sessions, id, true)

    checked(c, config, fn ->
      assert {:ok, embedding, _} =
               Ipse.Config.Profiles.prepare_embedding(config, %{
                 "profile" => "search",
                 "timeout_ms" => 2000
               })

      assert {:error, error} =
               InferenceDispatch.run(
                 config,
                 embedding,
                 "embedding.create",
                 "search",
                 context(c, embedding, id),
                 fn _ -> :ok end,
                 fn _ -> {:ok, nil} end,
                 fn selected, emit, _ ->
                   Ipse.Provider.request_embedding(selected, ["input"], emit)
                 end
               )

      assert error =~ "Budget liability exceeds"
      Task.await(server)
      assert {:ok, budget} = Ipse.Usage.Budget.snapshot(config)
      assert budget["overdrawn"]
      assert {:ok, slots} = InferenceSlots.status(config, cwd: c.cwd)
      assert slots["services"]["local"]["active"] == nil
      assert [receipt] = slots["recent"]
      assert receipt["status"] == "settled"
    end)
  end

  test "native service-owner loss after upstream text withholds that text even after terminal HTTP cleanup",
       c do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    base = "http://127.0.0.1:#{port}"
    on_exit(fn -> :gen_tcp.close(listener) end)
    config = config(c, base)

    checked(c, config, fn ->
      partial =
        Jason.encode!(%{
          "model" => "fixture",
          "message" => %{"role" => "assistant", "content" => "Never publish"},
          "done" => false
        }) <> "\n"

      terminal = text_body()
      parent = self()

      server =
        Task.async(fn ->
          {:ok, socket} = :gen_tcp.accept(listener, 5000)
          ProviderFixture.request(socket, "")

          :ok =
            :gen_tcp.send(
              socket,
              "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(partial) + byte_size(terminal)}\r\nconnection: close\r\n\r\n" <>
                partial
            )

          send(parent, {:owner_loss_http, self()})
          receive do: (:finish_http -> :ok)
          :gen_tcp.send(socket, terminal)
          :gen_tcp.close(socket)
        end)

      task =
        Task.async(fn ->
          InferenceDispatch.run(
            config,
            config,
            "main",
            nil,
            context(c, config),
            fn
              {:inference_service_timing, _} ->
                cap = Process.get({InferenceSlots, :callback})
                send(parent, {:actual_service_controller, cap.controller})

              event ->
                send(parent, {:owner_loss_event, event})
            end,
            fn _ -> {:ok, nil} end,
            &execute/3
          )
        end)

      assert_receive {:owner_loss_http, handler}, 3000
      assert_receive {:actual_service_controller, controller}, 3000
      monitor = Process.monitor(controller)
      Process.exit(controller, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^controller, _}, 1000
      send(handler, :finish_http)
      assert {:error, error} = Task.await(task, 5000)
      assert error =~ "unknown outcome"
      refute_received {:owner_loss_event, {:text, _}}
      Task.await(server)
      assert {:ok, slots} = InferenceSlots.status(config, cwd: c.cwd)
      assert is_map(slots["services"]["local"]["active"])
    end)
  end

  test "the finite private text chunk ceiling refuses publication without truncating a completed response",
       c do
    partial =
      Jason.encode!(%{
        "model" => "fixture",
        "message" => %{"role" => "assistant", "content" => "t"},
        "done" => false
      }) <> "\n"

    {base, server} =
      ProviderFixture.start(String.duplicate(partial, 8193) <> text_body(), 200, "", :whole)

    on_exit(fn -> if Process.alive?(server.pid), do: Process.exit(server.pid, :kill) end)
    config = config(c, base)

    checked(c, config, fn ->
      parent = self()

      assert {:error, error} =
               InferenceDispatch.run(
                 config,
                 config,
                 "main",
                 nil,
                 context(c, config),
                 fn event -> send(parent, {:ceiling_event, event}) end,
                 fn _ -> {:ok, nil} end,
                 &execute/3
               )

      assert error =~ "exceeded its private publication buffer"
      refute_received {:ceiling_event, {:text, _}}
      Task.await(server)
      assert {:ok, slots} = InferenceSlots.status(config, cwd: c.cwd)
      assert slots["services"]["local"]["active"] == nil
      assert [receipt] = slots["recent"]
      assert receipt["status"] == "settled"
    end)
  end

  # The provided-set physical-send check runs in the ordinary inference task.
  # The owner admits only its worker and tracked file effects, so a direct call
  # from that task is a fence refusal before any provider IO. This runs without
  # a supported service ledger, unlike the Session journey that reaches it.
  test "the provided-set physical-send check reaches the owner as a tracked effect" do
    parent = self()

    owner =
      spawn(fn ->
        {:ok, scope} = Ipse.Session.Resources.start(self())

        worker =
          spawn(fn ->
            {owner, scope} = receive do: ({:start, owner, scope} -> {owner, scope})
            Ipse.Session.Resources.bind(scope)

            context = %{
              config: %{},
              cwd: System.tmp_dir!(),
              session_id: Usage.id(),
              history_dir: nil,
              owner: owner,
              job_ref: make_ref(),
              phase: "model.complete",
              admission: %{},
              expected: %{},
              managed: %{dependencies: []}
            }

            task =
              Ipse.Session.Resources.async(fn ->
                facts = %{"kind" => "text"}

                {Ipse.Session.InferenceDispatch.send(context, facts, fn -> :ok end),
                 InferenceDispatch.provided_wire(context, facts)}
              end)

            send(parent, {:wire_results, Task.await(task)})
            receive do: (:stop -> :ok)
          end)

        :ok = Ipse.Session.Resources.attach(scope, worker)
        send(worker, {:start, self(), scope})
        send(parent, {:wire_owner, scope, worker})
        wire_owner(worker)
      end)

    assert_receive {:wire_owner, scope, worker}

    on_exit(fn ->
      for pid <- [worker, owner, scope], Process.alive?(pid), do: Process.exit(pid, :kill)
    end)

    assert_receive {:wire_results, {direct, tracked}}, 5_000
    assert direct == {:error, :inference_dispatch_refused}
    assert tracked == :ok
  end

  defp wire_owner(worker) do
    receive do
      {:"$gen_call", {caller, _} = from, {:inference_wire_use, _, _, _, _, _}} ->
        admitted = Ipse.Session.Resources.authorized_effect?(worker, caller)
        GenServer.reply(from, if(admitted, do: :ok, else: {:error, :inference_dispatch_refused}))
        wire_owner(worker)
    end
  end
end
