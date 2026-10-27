Code.require_file("../../support/provider_fixture.ex", __DIR__)

defmodule Ipse.Extension.DecisionSessionTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal, Usage}
  alias Ipse.Extension.{Actions, Artifact, Config, Registry, ChildUsage}
  alias Ipse.Usage.Budget

  defmodule NoModel do
    def complete(_, _, _, _),
      do: raise("Unexpected conversation inference in explicit decision fixture")
  end

  defmodule DelegateModel do
    def complete(config, messages, _, _) do
      if config[:delegation_origin] == nil and not Enum.any?(messages, &(&1["role"] == "tool")) do
        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => [
             %{
               "id" => "child",
               "type" => "function",
               "function" => %{
                 "name" => "delegate",
                 "arguments" =>
                   Jason.encode!(%{"task" => "Synthetic task", "context" => "Fixture"})
               }
             }
           ]
         }, %{"input_tokens" => 3, "output_tokens" => 1}}
      else
        {:ok, %{"role" => "assistant", "content" => "Synthetic task complete"},
         %{"input_tokens" => 3, "output_tokens" => 1}}
      end
    end
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-decision-artifact-" <> Usage.id())
    File.mkdir_p!(Path.join(root, "ebin"))
    module = "Independent.DecisionFixture#{System.unique_integer([:positive])}"
    caps = ~w(invoke.command event.job host.actions host.decision)

    command = %{
      "id" => "decide",
      "description" => "Synthetic explicit decision",
      "arguments_schema" => %{
        "type" => "object",
        "required" => ["request"],
        "properties" => %{"request" => %{"type" => "object"}},
        "additionalProperties" => false
      },
      "result_schema" => %{"type" => "object"}
    }

    job = %{
      "id" => "decide",
      "description" => "Explicit fixture decision before a model request",
      "arguments_schema" => %{
        "type" => "object",
        "required" => ["event"],
        "properties" => %{"event" => %{"type" => "object"}},
        "additionalProperties" => false
      },
      "result_schema" => %{"type" => "object"}
    }

    exports =
      Ipse.Extension.Catalog.empty() |> Map.put("commands", [command]) |> Map.put("jobs", [job])

    subscriptions = [
      %{
        "id" => "decide",
        "handler" => "decide",
        "event" => "prompt.effective_committed",
        "event_version" => 1,
        "view" => "metadata",
        "mode" => "job",
        "schedule" => "before_request",
        "required" => true
      }
    ]

    source = """
    defmodule #{module} do
      @behaviour Ipse.Extension
      def describe, do: %{"sdk" => 1, "capabilities" => #{inspect(caps)}, "exports" => #{inspect(exports)}, "subscriptions" => #{inspect(subscriptions)}}
      def init(options), do: {:ok, options}
      def handle("invoke.command", payload, state), do: {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => payload["arguments"]["request"]}, state}
      def handle("event.job", _, state), do: {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => #{inspect(request())}}, state}
      def handle("host.actions", payload, state), do: {:ok, %{"api_version" => 1, "kind" => "result", "value" => payload["outcome"]}, state}
    end
    """

    file = Path.join(root, "fixture.ex")
    File.write!(file, source)

    {log, status} =
      System.cmd(
        System.find_executable("elixirc"),
        ["-pa", Application.app_dir(:ipse, "ebin"), "-o", Path.join(root, "ebin"), file],
        stderr_to_stdout: true
      )

    assert status == 0, log
    File.write!(Path.join(root, "LICENSE"), "MIT synthetic fixture")
    paths = ["LICENSE", "ebin/Elixir.#{module}.beam"]

    manifest = %{
      "format" => 1,
      "id" => "fixture/decision",
      "version" => "0.1.0",
      "sdk" => 1,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => module,
      "license_file" => "LICENSE",
      "options_schema" => %{"type" => "object", "additionalProperties" => false},
      "capabilities" => caps,
      "exports" => exports,
      "subscriptions" => subscriptions,
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      },
      "files" =>
        Enum.map(paths, fn path ->
          bytes = File.read!(Path.join(root, path))
          %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
        end)
    }

    File.write!(Path.join(root, "extension.json"), Jason.encode!(manifest))
    on_exit(fn -> File.rm_rf!(root) end)
    %{artifact: root, capabilities: caps}
  end

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-decision-session-" <> Usage.id())
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    File.mkdir!(Path.join(root, "sessions"))
    File.chmod!(Path.join(root, "sessions"), 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, home: Path.join(root, "home"), dir: Path.join(root, "sessions")}
  end

  defp request do
    %{
      "op" => "decision.create",
      "version" => 1,
      "profile" => "advice",
      "input" => "Fresh development fixture",
      "questions" => [
        %{"id" => "relevant", "type" => "predicate", "instructions" => "Does this apply?"}
      ],
      "timeout_ms" => 10_000
    }
  end

  defp native(model \\ "fixture"),
    do: %{
      "model" => model,
      "answers" => %{"relevant" => %{"type" => "noul", "noul" => 0.8}},
      "usage" => %{"input_tokens" => 10, "output_tokens" => 2}
    }

  defp config(ctx, base, options \\ %{}) do
    {:ok, artifact} = Artifact.import(ctx.artifact, Path.join(ctx.home, "extensions/artifacts"))

    data = %{
      "extensions" => [
        %{
          "instance" => "advice",
          "artifact" => artifact.digest,
          "enabled" => true,
          "options" => %{},
          "order" => 1,
          "lifetime" => "persistent"
        }
      ],
      "extension_trust" => [
        %{
          "artifact" => artifact.digest,
          "capabilities" => ctx.capabilities,
          "allow_project" => false,
          "allow_children" => true
        }
      ]
    }

    {:ok, selected} =
      Config.resolve(
        [%{scope: "operator", path: Path.join(ctx.root, "operator.json"), data: data}],
        []
      )

    {:ok, entries} = Registry.prepare(selected, ctx.home)

    Map.merge(
      %{
        provider: :ollama,
        model: "unused",
        provider_module: NoModel,
        home: ctx.home,
        extensions: entries,
        approval: :ask,
        compact: false,
        decision_profiles: %{
          "advice" => %{
            "operation" => "decision",
            "provider" => "system_one_compatible",
            "model" => "fixture",
            "expected_model" => "fixture",
            "service_id" => "development",
            "base_url" => base
          }
        }
      },
      options
    )
  end

  defp start(ctx, config, id \\ nil) do
    assert {:ok, pid} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session,
                config: config, cwd: ctx.root, state_dir: ctx.dir, id: id, subscriber: self()}
             )

    on_exit(fn -> if Process.alive?(pid), do: Session.close_confirmed(pid) end)
    pid
  end

  defp invoke(pid, request \\ request()),
    do:
      assert(
        :ok = Session.invoke_export(pid, :command, "ext__advice__decide", %{"request" => request})
      )

  defp done(pid), do: assert_receive({:ipse, ^pid, {:done, _}}, 10_000)
  defp events(ctx, pid), do: elem(Journal.load(ctx.dir, Session.info(pid).id), 1)

  defp http do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_, port}} = :inet.sockname(listener)
    owner = self()
    tag = make_ref()
    acceptor = spawn(fn -> accept(listener, owner, tag) end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      Process.exit(acceptor, :kill)
    end)

    {"http://127.0.0.1:#{port}", tag}
  end

  defp accept(listener, owner, tag) do
    case :gen_tcp.accept(listener, 30_000) do
      {:ok, socket} ->
        try do
          {headers, bytes} = Ipse.Test.ProviderFixture.request(socket, "")
          send(owner, {:decision_http, tag, self(), headers, Jason.decode!(bytes)})
          :ok = :inet.setopts(socket, active: :once)

          receive do
            {:respond, value} ->
              body = if is_binary(value), do: value, else: Jason.encode!(value)

              :gen_tcp.send(socket, [
                "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n",
                body
              ])

            {:tcp_closed, ^socket} ->
              send(owner, {:decision_http_closed, tag})

            {:tcp_error, ^socket, _} ->
              send(owner, {:decision_http_closed, tag})
          after
            20_000 -> :ok
          end
        after
          :gen_tcp.close(socket)
        end

        accept(listener, owner, tag)

      _ ->
        :ok
    end
  end

  test "approval precedes actual egress and canonical typed response survives inert resume",
       ctx do
    {base, tag} = http()
    cfg = config(ctx, base)
    pid = start(ctx, cfg)
    invoke(pid)
    assert_receive {:ipse, ^pid, {:approval, ref, "extension:decision.create", proposed}}, 5000
    assert proposed["request"] == request()
    assert proposed["execution"]["service_id"] == "development"
    assert proposed["execution"]["billing_mode"] == "local"
    assert proposed["effect_binding"]["kind"] == "decision"
    assert proposed["namespace"] == Session.info(pid).id
    refute_receive {:decision_http, ^tag, _, _, _}, 100
    :ok = Session.approve(pid, ref, true)
    assert_receive {:decision_http, ^tag, handler, headers, body}, 5000
    assert headers =~ "POST /systemone HTTP/1.1"
    refute String.downcase(headers) =~ "authorization"
    assert body["state"] == request()["input"]
    send(handler, {:respond, native()})
    done(pid)
    ev = events(ctx, pid)
    assert {:ok, _} = Usage.restore(ev, Session.info(pid).id)
    assert {:ok, _} = Actions.restore(ev)

    order =
      ~w(extension_action_intent extension_decision_request request_admitted request_usage_observed extension_decision_response request_finished extension_action_result)

    positions = Enum.map(order, fn type -> Enum.find_index(ev, &(&1["type"] == type)) end)
    assert Enum.all?(positions, &is_integer/1)
    assert positions == Enum.sort(positions)
    admission = Enum.find(ev, &(&1["type"] == "request_admitted"))
    assert admission["version"] == 3 and admission["operation"] == "decision"
    outcome = Enum.find(ev, &(&1["type"] == "extension_action_result"))["outcome"]
    assert outcome["status"] == "ok"
    assert outcome["value"]["usage"]["counts"]["input_tokens"] == 10
    assert outcome["value"]["usage"]["counts"]["output_tokens"] == 2

    assert outcome["value"]["result"]["answers"] == [
             %{"id" => "relevant", "type" => "predicate", "probability" => 0.8}
           ]

    assert {:ok, page} = Session.sources(pid, "source.list", %{"limit" => 32})

    assert Enum.sort(Enum.map(page["sources"], & &1["kind"])) ==
             ~w(decision.advice effect.outcome)

    advice = Enum.find(page["sources"], &(&1["kind"] == "decision.advice"))

    assert {:ok, evidence} =
             Session.sources(pid, "source.read", %{"handle" => advice["read_handle"]})

    assert Jason.decode!(evidence["text"]) == outcome["value"]["result"]

    for type <-
          ~w(extension_decision_request extension_decision_response request_admitted request_finished extension_action_result) do
      original = Enum.find(ev, &(&1["type"] == type))

      bad =
        case type do
          "extension_decision_request" ->
            put_in(original, ["execution", "service_id"], "unselected")

          "extension_decision_response" ->
            put_in(original, ["payload", "reported_model"], "unselected")

          "request_admitted" ->
            Map.put(original, "expected_model", "unselected")

          "request_finished" ->
            put_in(original, ["usage", "counts", "input_tokens"], 11)

          "extension_action_result" ->
            put_in(original, ["outcome", "value", "selection_sha256"], String.duplicate("0", 64))
        end

      corrupted = Enum.map(ev, fn event -> if event == original, do: bad, else: event end)
      assert {:error, _} = Usage.restore(corrupted, Session.info(pid).id)
    end

    id = Session.info(pid).id
    :ok = Session.close_confirmed(pid)
    path = Path.join(ctx.dir, id <> ".jsonl")
    before = File.read!(path)
    resumed = start(ctx, cfg, id)
    assert Session.info(resumed).phase == :idle
    assert File.read!(path) == before
    refute_receive {:decision_http, ^tag, _, _, _}, 100
  end

  test "each hosted wire subset retains its explicit route and key choice", ctx do
    {base, tag} = http()

    for {provider, key, model} <- [
          {"openai", "OPENAI_API_KEY", "gpt-6-luna"},
          {"system_one", "TYPESAFE_API_KEY", "fixture"}
        ] do
      old = System.get_env(key)
      System.put_env(key, "synthetic-decision-credential")
      on_exit(fn -> if old, do: System.put_env(key, old), else: System.delete_env(key) end)
      cfg = config(ctx, base, %{approval: :allow})

      profile =
        cfg.decision_profiles["advice"]
        |> Map.put("provider", provider)
        |> Map.put("model", model)
        |> Map.put("expected_model", model)

      pid = start(ctx, Map.put(cfg, :decision_profiles, %{"advice" => profile}))
      invoke(pid)
      assert_receive {:decision_http, ^tag, handler, headers, body}, 5000
      assert headers =~ "Bearer synthetic-decision-credential"
      assert body["model"] == model

      response =
        if provider == "openai",
          do: %{
            "model" => model,
            "answers" => [%{"name" => "relevant", "type" => "predicate", "probability" => 0.8}],
            "usage" => %{"input_tokens" => 10, "output_tokens" => 2}
          },
          else: native(model)

      send(handler, {:respond, response})
      done(pid)
      assert Session.info(pid).extension_result["value"]["status"] == "ok"
      ev = events(ctx, pid)
      assert {:ok, _} = Usage.restore(ev)
      assert {:ok, _} = Actions.restore(ev)
      assert Enum.find(ev, &(&1["type"] == "request_admitted"))["billing_mode"] == "api"
      refute Jason.encode!(ev) =~ "synthetic-decision-credential"
    end
  end

  test "denial, unrecordable responses and unenforceable output budgets dispatch zero requests",
       ctx do
    {base, tag} = http()

    for options <- [
          %{approval: :deny},
          %{approval: :allow, journal: %{"max_record_bytes" => 32_768}},
          %{
            approval: :allow,
            budget: %{"version" => 1, "max_output_tokens" => 20, "reserve_output_tokens" => 20}
          }
        ] do
      pid = start(ctx, config(ctx, base, options))
      invoke(pid)
      done(pid)
      refute_receive {:decision_http, ^tag, _, _, _}, 100
      ev = events(ctx, pid)

      if options[:budget] do
        assert Enum.count(ev, &(&1["type"] == "request_admitted")) == 1
        assert Enum.find(ev, &(&1["type"] == "request_finished"))["outcome"] == "failed"
        assert {:ok, _} = Usage.restore(ev)
      else
        refute Enum.any?(ev, &(&1["type"] == "request_admitted"))
      end
    end
  end

  test "cancellation closes an actually dispatched HTTP request and never replays on resume",
       ctx do
    {base, tag} = http()
    cfg = config(ctx, base, %{approval: :allow})
    pid = start(ctx, cfg)
    invoke(pid)
    assert_receive {:decision_http, ^tag, _, _, _}, 5000
    :ok = Session.cancel(pid)
    assert_receive {:decision_http_closed, ^tag}, 5000
    ev = events(ctx, pid)
    assert {:ok, _} = Usage.restore(ev)
    assert {:ok, _} = Actions.restore(ev)
    refute Enum.any?(ev, &(&1["type"] == "extension_decision_response"))
    finished = Enum.find(ev, &(&1["type"] == "request_finished"))
    assert finished["outcome"] == "cancelled"
    assert finished["finality"] == "partial"
    id = Session.info(pid).id
    :ok = Session.close_confirmed(pid)
    resumed = start(ctx, cfg, id)
    assert Session.info(resumed).phase == :idle
    refute_receive {:decision_http, ^tag, _, _, _}, 100
  end

  test "wrong native model and malformed distributions fail without advice or substitution",
       ctx do
    {base, tag} = http()
    pid = start(ctx, config(ctx, base, %{approval: :allow}))

    for response <- [native("unselected"), put_in(native(), ["answers", "relevant", "noul"], 1.5)] do
      invoke(pid)
      assert_receive {:decision_http, ^tag, handler, _, _}, 5000
      send(handler, {:respond, response})
      done(pid)
      assert Session.info(pid).extension_result["value"]["status"] == "failed"
    end

    ev = events(ctx, pid)
    refute Enum.any?(ev, &(&1["type"] == "extension_decision_response"))
    assert {:ok, _} = Usage.restore(ev)
    assert {:ok, _} = Actions.restore(ev)
  end

  for interruption <- [:timeout, :owner_loss] do
    test "#{interruption} closes HTTP, retains shared liability and never replays", ctx do
      {base, tag} = http()
      cfg = config(ctx, base, %{approval: :allow, budget: %{"version" => 1, "max_requests" => 1}})
      pid = start(ctx, cfg)
      id = Session.info(pid).id
      guard = Ipse.Session.Lock.for_owner(pid)
      monitor = Process.monitor(pid)
      guard_monitor = Process.monitor(guard)

      req =
        if unquote(interruption) == :timeout,
          do: Map.put(request(), "timeout_ms", 1000),
          else: request()

      invoke(pid, req)
      assert_receive {:decision_http, ^tag, _, _, _}, 5000

      if unquote(interruption) == :owner_loss do
        Process.exit(pid, :kill)
        assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5000
        assert_receive {:DOWN, ^guard_monitor, :process, ^guard, _}, 10_000
      else
        done(pid)
        :ok = Session.close_confirmed(pid)
      end

      assert_receive {:decision_http_closed, ^tag}, 5000
      assert {:ok, ev} = Journal.load(ctx.dir, id)
      assert {:ok, _} = Session.restore_context(ev)
      refute Enum.any?(ev, &(&1["type"] == "extension_decision_response"))
      assert {:ok, snapshot} = Budget.saved(ctx.dir, id)
      assert snapshot["unsettled_count"] + snapshot["partial_count"] >= 1
      assert snapshot["request_count"] == 1
      resumed = start(ctx, cfg, id)
      assert Session.info(resumed).phase == :idle
      refute_receive {:decision_http, ^tag, _, _, _}, 100
      invoke(resumed)
      done(resumed)
      refute_receive {:decision_http, ^tag, _, _, _}, 100
      assert {:ok, after_refusal} = Budget.saved(ctx.dir, id)
      assert after_refusal["refused_count"] == 1
      assert after_refusal["request_count"] == 1
    end
  end

  test "child decisions require separate approval and settle the parent's shared budget", ctx do
    {base, tag} = http()

    cfg =
      config(ctx, base, %{
        provider_module: DelegateModel,
        subagents: true,
        approval: :ask,
        budget: %{"version" => 1, "max_requests" => 5}
      })

    pid = start(ctx, cfg)
    :ok = Session.prompt(pid, "Run the synthetic delegated task")
    assert_receive {:ipse, ^pid, {:approval, ref, "extension:decision.create", _}}, 10_000
    refute_receive {:decision_http, ^tag, _, _, _}, 100
    :ok = Session.approve(pid, ref, true)
    assert_receive {:decision_http, ^tag, handler, _, _}, 5000
    send(handler, {:respond, native()})
    assert_receive {:ipse, ^pid, {:approval, delegate_ref, "delegate", _}}, 10_000
    :ok = Session.approve(pid, delegate_ref, true)
    assert_receive {:ipse, ^pid, {:approval, child_ref, name, proposed}}, 10_000

    assert String.starts_with?(name, "child ") and
             String.ends_with?(name, "/extension:decision.create")

    assert proposed["request"] == request()
    assert proposed["execution"]["service_id"] == "development"
    refute_receive {:decision_http, ^tag, _, _, _}, 100
    :ok = Session.approve(pid, child_ref, true)
    assert_receive {:decision_http, ^tag, child_handler, _, _}, 5000
    send(child_handler, {:respond, native()})
    done(pid)
    ev = events(ctx, pid)
    id = Session.info(pid).id
    assert {:ok, index} = ChildUsage.restore(ev)
    [child] = Map.values(index.index)
    assert child["cleanup_confirmed"]
    assert {:ok, ledger, _, _, accounting} = ChildUsage.read_for_budget(ctx.dir, id, child)

    decision =
      ledger.requests |> Map.values() |> Enum.find(&(&1.admission["operation"] == "decision"))

    assert decision.admission["parent_session_id"] == id
    assert decision.completion["outcome"] == "completed"

    assert Enum.any?(
             accounting,
             &(&1["type"] == "request_admitted" and &1["operation"] == "decision")
           )

    assert {:ok, child_events} =
             Journal.load(Path.join([ctx.dir, "subagents", id]), child["child_id"])

    assert hd(child_events)["metadata"]["usage_version"] == 3
    assert hd(child_events)["metadata"]["mcp_servers"] == []
    assert Enum.any?(child_events, &(&1["type"] == "extension_decision_response"))
    assert {:ok, snapshot} = Budget.saved(ctx.dir, id)
    assert snapshot["request_count"] == 5
    assert snapshot["unsettled_count"] == 0
    assert snapshot["refused_count"] == 0
  end

  test "concurrent decision attempts dispatch only one remaining shared reservation", ctx do
    {base, tag} = http()
    id = Usage.id()
    cfg = config(ctx, base, %{budget: %{"version" => 1, "max_requests" => 1}})
    assert {:ok, attached} = Ipse.Usage.BudgetStore.attach(cfg, ctx.dir, id, true)
    assert {:ok, runtime, _} = Ipse.Config.Decisions.prepare(attached, request())
    owner = self()

    tasks =
      for _ <- 1..8 do
        Task.async(fn ->
          send(owner, {:ready, self()})

          receive do
            :go ->
              admission = Usage.admission(id, runtime, "extension", Usage.id())

              Budget.run(runtime, admission, fn _ -> :ok end, fn selected, emit ->
                Ipse.Provider.Decision.Transport.request(
                  selected,
                  Ipse.Extension.DecisionCall.neutral(request()),
                  emit
                )
              end)
          end
        end)
      end

    for task <- tasks, do: assert_receive({:ready, task_pid} when task_pid == task.pid, 1000)
    Enum.each(tasks, &send(&1.pid, :go))
    assert_receive {:decision_http, ^tag, handler, _, _}, 5000
    send(handler, {:respond, native()})
    results = Enum.map(tasks, &Task.await(&1, 10_000))
    assert Enum.count(results, &match?({:ok, _, _}, &1)) == 1
    assert Enum.count(results, &match?({:error, _}, &1)) == 7
    refute_receive {:decision_http, ^tag, _, _, _}, 100
    assert {:ok, snapshot} = Budget.snapshot(attached)
    assert snapshot["request_count"] == 1
    assert snapshot["refused_count"] == 7
    assert snapshot["unsettled_count"] == 0
  end
end
