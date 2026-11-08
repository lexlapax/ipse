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

  defmodule PlainModel do
    def complete(config, messages, _, _) do
      if is_pid(config[:test_pid]), do: send(config.test_pid, {:plain_model_called, messages})
      {:ok, %{"role" => "assistant", "content" => "Synthetic next turn"}, %{}}
    end
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
        "properties" => %{
          "request" => %{"type" => "object"},
          "marker" => %{"type" => "string"}
        },
        "additionalProperties" => false
      },
      "result_schema" => %{"type" => "object"}
    }

    shadow = %{
      "id" => "shadow",
      "description" => "Synthetic decision-policy integration fixture",
      "arguments_schema" => %{
        "type" => "object",
        "required" => ["facts", "consumer"],
        "properties" => %{
          "facts" => %{"type" => "object"},
          "consumer" => %{"type" => "string", "enum" => ~w(notes.select notes.assess)}
        },
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
      Ipse.Extension.Catalog.empty()
      |> Map.put("commands", [command, shadow])
      |> Map.put("jobs", [job])

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
      alias IpseKnowledge.Knowledge.DecisionPolicy, as: Policy
      def describe, do: %{"sdk" => 1, "capabilities" => #{inspect(caps)}, "exports" => #{inspect(exports)}, "subscriptions" => #{inspect(subscriptions)}}
      def init(options), do: {:ok, options}
      def handle("invoke.command", %{"id" => "shadow", "arguments" => %{"facts" => facts, "consumer" => consumer}}, state) do
        policy = Policy.default(consumer) |> Map.merge(%{"strategy" => "decision", "profile" => "advice"})
        {:ok, plan} = Policy.plan(policy, facts, :development_experiment)
        if plan.request do
          {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => plan.request}, Map.put(state, :plan, plan)}
        else
          {:ok, value} = Policy.apply(plan, nil)
          {:ok, %{"api_version" => 1, "kind" => "result", "value" => value}, state}
        end
      end
      def handle("invoke.command", payload, state), do: {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => payload["arguments"]["request"]}, state}
      def handle("event.job", _, state), do: {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => #{inspect(request())}}, state}
      def handle("host.actions", %{"outcome" => %{"status" => "ok", "value" => value}}, %{plan: plan} = state) do
        {:ok, result} = Policy.apply(plan, value["result"])
        {:ok, %{"api_version" => 1, "kind" => "result", "value" => result}, Map.delete(state, :plan)}
      end
      def handle("host.actions", %{"outcome" => outcome}, %{plan: _} = state), do: {:ok, %{"api_version" => 1, "kind" => "result", "value" => %{"status" => outcome["status"]}}, Map.delete(state, :plan)}
      def handle("host.actions", payload, state), do: {:ok, %{"api_version" => 1, "kind" => "result", "value" => payload["outcome"]}, state}
    end
    """

    file = Path.join(root, "fixture.ex")
    File.write!(file, source)

    {log, status} =
      System.cmd(
        System.find_executable("elixirc"),
        [
          "-pa",
          Application.app_dir(:ipse, "ebin"),
          "-o",
          Path.join(root, "ebin"),
          file,
          "extensions/knowledge/src/knowledge/decision_policy.ex"
        ],
        stderr_to_stdout: true
      )

    assert status == 0, log
    File.write!(Path.join(root, "LICENSE"), "MIT synthetic fixture")

    paths = [
      "LICENSE"
      | Path.wildcard(Path.join(root, "ebin/*.beam")) |> Enum.map(&Path.relative_to(&1, root))
    ]

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

    on_exit(fn ->
      # Focused owner-loss/failure cases need the shared artifact retained
      # until the external process/worker audit has confirmed closure.
      case File.lstat(root <> ".retain") do
        {:error, :enoent} -> File.rm_rf!(root)
        _ -> :ok
      end
    end)

    %{artifact: root, capabilities: caps}
  end

  setup context do
    if context[:preserve_failure] do
      File.write!(context.artifact <> ".retain", "retain for independent audit\n")
    end

    parent =
      if context[:preserve_failure],
        do: Path.expand("_build/verification/fence-fixtures"),
        else: System.tmp_dir!()

    root = Path.join(parent, "ipse-decision-session-" <> Usage.id())
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    File.mkdir!(Path.join(root, "sessions"))
    File.chmod!(Path.join(root, "sessions"), 0o700)

    on_exit(fn ->
      unless context[:preserve_failure], do: File.rm_rf!(root)
    end)

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

  defp expected_decision_wire do
    %{
      "model" => "fixture",
      "state" => request()["input"],
      "questions" => %{
        "relevant" => %{"type" => "noul", "instructions" => "Does this apply?"}
      }
    }
  end

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

  defp start_fenced(ctx, config, owner, fence, id \\ nil, include_fence \\ true) do
    opts = [
      config: config,
      cwd: ctx.root,
      state_dir: ctx.dir,
      id: id,
      subscriber: self(),
      owner: owner
    ]

    opts = if include_fence, do: Keyword.put(opts, :exact_action_fence, fence), else: opts
    assert {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts})

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :kill)
    end)

    pid
  end

  defp no_subscriber_fixture(ctx) do
    root = Path.join(ctx.root, "no-subscriber-artifact")
    ebin = Path.join(root, "ebin")
    File.mkdir_p!(ebin)
    module = "Independent.DecisionNoSubscriber#{System.unique_integer([:positive])}"
    caps = ~w(invoke.command host.actions host.decision)
    original = ctx.artifact |> Path.join("extension.json") |> File.read!() |> Jason.decode!()
    command = hd(original["exports"]["commands"])
    exports = Ipse.Extension.Catalog.empty() |> Map.put("commands", [command])

    source = """
    defmodule #{module} do
      @behaviour Ipse.Extension
      def describe, do: %{"sdk" => 1, "capabilities" => #{inspect(caps)}, "exports" => #{inspect(exports)}, "subscriptions" => []}
      def init(options), do: {:ok, options}
      def handle("invoke.command", payload, state), do: {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => payload["arguments"]["request"]}, state}
      def handle("host.actions", payload, state), do: {:ok, %{"api_version" => 1, "kind" => "result", "value" => payload["outcome"]}, state}
    end
    """

    file = Path.join(root, "fixture.ex")
    File.write!(file, source)

    {log, status} =
      System.cmd(
        System.find_executable("elixirc"),
        ["-pa", Application.app_dir(:ipse, "ebin"), "-o", ebin, file],
        stderr_to_stdout: true
      )

    assert status == 0, log
    File.write!(Path.join(root, "LICENSE"), "MIT synthetic fixture")

    paths = [
      "LICENSE"
      | Path.wildcard(Path.join(ebin, "*.beam")) |> Enum.map(&Path.relative_to(&1, root))
    ]

    files =
      Enum.map(paths, fn path ->
        bytes = File.read!(Path.join(root, path))
        %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
      end)

    manifest =
      original
      |> Map.put("id", "fixture/decision-no-subscriber")
      |> Map.put("entrypoint", module)
      |> Map.put("capabilities", caps)
      |> Map.put("exports", exports)
      |> Map.put("subscriptions", [])
      |> Map.put("files", files)

    File.write!(Path.join(root, "extension.json"), Jason.encode!(manifest))
    %{ctx | artifact: root, capabilities: caps}
  end

  @tag preserve_failure: true
  test "a different parent argument refuses an identical decision request before approval and after resume",
       ctx do
    ctx = no_subscriber_fixture(ctx)
    {base, tag} = http()
    cfg = config(ctx, base)

    {:ok, entry, descriptor} =
      Ipse.Extension.Catalog.lookup(cfg, "invoke.command", "ext__advice__decide")

    expected_args = %{"request" => request(), "marker" => "expected"}
    changed_args = Map.put(expected_args, "marker", "changed")
    assert changed_args["request"] == expected_args["request"]
    refute Ipse.JSON.digest([changed_args]) == Ipse.JSON.digest([expected_args])

    fence = %{
      "version" => 2,
      "operation" => "decision.create",
      "identity_sha256" => Ipse.JSON.digest([entry.identity]),
      "descriptor_sha256" => Ipse.JSON.digest([descriptor]),
      "arguments_sha256" => Ipse.JSON.digest([expected_args]),
      "request_sha256" => Ipse.JSON.digest([request()])
    }

    first = start_fenced(ctx, cfg, self(), fence)
    id = Session.info(first).id
    assert :ok = Session.invoke_export(first, :command, "ext__advice__decide", changed_args)
    assert_receive {:ipse, ^first, {:done, :error}}, 10_000
    refute_receive {:ipse, ^first, {:approval, _, "extension:decision.create", _}}, 100
    refute_receive {:decision_http, ^tag, _, _, _}, 100
    assert :ok = Session.close_confirmed(first)

    resumed = start_fenced(ctx, cfg, self(), fence, id, false)
    assert :ok = Session.invoke_export(resumed, :command, "ext__advice__decide", expected_args)
    assert_receive {:ipse, ^resumed, {:done, :error}}, 10_000
    refute_receive {:ipse, ^resumed, {:approval, _, "extension:decision.create", _}}, 100
    refute_receive {:decision_http, ^tag, _, _, _}, 100
    assert :ok = Session.close_confirmed(resumed)

    assert {:ok, history} = Journal.load(ctx.dir, id)
    assert {:ok, _} = Session.Saved.restore(history, id)

    assert [%{"matched" => false} = attempt] =
             Enum.filter(history, &(&1["type"] == "exact_action_fence_attempt"))

    assert attempt["request_sha256"] == Ipse.JSON.digest([request()])
    assert attempt["arguments_sha256"] == Ipse.JSON.digest([changed_args])

    refute Enum.any?(history, fn event ->
             event["type"] == "extension_action_intent" and
               get_in(event, ["request", "op"]) == "decision.create"
           end)

    refute Enum.any?(
             history,
             &(&1["type"] in ~w(inference_dispatch_intent extension_decision_request))
           )
  end

  for matching <- [false, true] do
    @tag preserve_failure: true
    test "same-ID resume completes an unrelated user turn after a consumed fence (match=#{matching})",
         ctx do
      ctx = no_subscriber_fixture(ctx)
      {base, tag} = http()
      cfg = config(ctx, base, %{provider_module: PlainModel, test_pid: self(), subagents: true})
      assert Ipse.Extension.Subscriptions.snapshot(cfg)["entries"] == []

      {:ok, entry, descriptor} =
        Ipse.Extension.Catalog.lookup(cfg, "invoke.command", "ext__advice__decide")

      fence = %{
        "version" => 2,
        "operation" => "decision.create",
        "identity_sha256" => Ipse.JSON.digest([entry.identity]),
        "descriptor_sha256" => Ipse.JSON.digest([descriptor]),
        "arguments_sha256" => Ipse.JSON.digest([%{"request" => request()}]),
        "request_sha256" => Ipse.JSON.digest([request()])
      }

      first = start_fenced(ctx, cfg, self(), fence)
      id = Session.info(first).id

      if unquote(matching) do
        invoke(first)

        assert_receive {:ipse, ^first, {:approval, ref, "extension:decision.create", proposed}},
                       5_000

        assert proposed["request"] == request()
        refute_receive {:decision_http, ^tag, _, _, _}, 100
        assert :ok = Session.approve(first, ref, true)
        assert_receive {:decision_http, ^tag, handler, _, body}, 5_000
        assert body == expected_decision_wire()
        send(handler, {:respond, native()})
        assert_receive {:ipse, ^first, {:done, :ok}}, 10_000
        assert Session.info(first).extension_result["value"]["status"] == "ok"
      else
        invoke(first, Map.put(request(), "input", "Different instruction"))
        assert_receive {:ipse, ^first, {:done, :error}}, 10_000
        refute_receive {:ipse, ^first, {:approval, _, "extension:decision.create", _}}, 100
        refute_receive {:decision_http, ^tag, _, _, _}, 100
      end

      assert :ok = Session.close_confirmed(first)

      resumed = start_fenced(ctx, cfg, self(), fence, id, false)
      assert :ok = Session.prompt(resumed, "Unrelated synthetic user turn")
      assert_receive {:plain_model_called, messages}, 10_000

      assert Enum.any?(
               messages,
               &(&1["role"] == "user" and &1["content"] == "Unrelated synthetic user turn")
             )

      assert_receive {:ipse, ^resumed, {:done, :ok}}, 10_000
      assert {:ok, history} = Journal.load(ctx.dir, id)

      assert Enum.any?(
               history,
               &(&1["type"] == "message" and get_in(&1, ["message", "role"]) == "assistant" and
                   get_in(&1, ["message", "content"]) == "Synthetic next turn")
             )

      assert [%{"matched" => unquote(matching)}] =
               Enum.filter(history, &(&1["type"] == "exact_action_fence_attempt"))

      assert {:ok, _} = Actions.restore(history)
      refute_receive {:decision_http, ^tag, _, _, _}, 100
      assert :ok = Session.close_confirmed(resumed)
    end
  end

  for {matching, interruption, supply_on_resume} <- [
        {true, :cancel, false},
        {true, :owner_loss, true},
        {false, :mismatch, true},
        {true, :approved, true}
      ] do
    @tag preserve_failure: true
    test "exact action stays spent after #{interruption} and same-ID resume (match=#{matching})",
         ctx do
      {base, tag} = http()
      cfg = config(ctx, base, %{provider_module: PlainModel, subagents: true})

      {:ok, entry, descriptor} =
        Ipse.Extension.Catalog.lookup(cfg, "invoke.command", "ext__advice__decide")

      fence = %{
        "version" => 2,
        "operation" => "decision.create",
        "identity_sha256" => Ipse.JSON.digest([entry.identity]),
        "descriptor_sha256" => Ipse.JSON.digest([descriptor]),
        "arguments_sha256" => Ipse.JSON.digest([%{"request" => request()}]),
        "request_sha256" => Ipse.JSON.digest([request()])
      }

      owner =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      on_exit(fn -> if Process.alive?(owner), do: Process.exit(owner, :kill) end)
      pid = start_fenced(ctx, cfg, owner, fence)
      id = Session.info(pid).id

      req =
        if unquote(matching),
          do: request(),
          else: Map.put(request(), "input", "Different instruction")

      invoke(pid, req)

      if unquote(matching) do
        assert_receive {:ipse, ^pid, {:approval, ref, "extension:decision.create", proposed}},
                       5_000

        assert proposed["request"] == request()
        refute_receive {:decision_http, ^tag, _, _, _}, 100

        case unquote(interruption) do
          :cancel ->
            assert :ok = Session.cancel(pid)
            assert_receive {:ipse, ^pid, {:done, :cancelled}}, 5_000
            assert :ok = Session.close_confirmed(pid)

          :owner_loss ->
            monitor = Process.monitor(pid)
            Process.exit(owner, :kill)
            assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 10_000

          :approved ->
            assert :ok = Session.approve(pid, ref, true)
            assert_receive {:decision_http, ^tag, handler, _, body}, 5_000
            assert body == expected_decision_wire()

            send(handler, {:respond, native()})
            assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
            assert Session.info(pid).extension_result["value"]["status"] == "ok"
            assert :ok = Session.close_confirmed(pid)
        end
      else
        assert_receive {:ipse, ^pid, {:done, :error}}, 10_000
        refute_receive {:ipse, ^pid, {:approval, _, "extension:decision.create", _}}, 100
        assert :ok = Session.close_confirmed(pid)
      end

      resumed = start_fenced(ctx, cfg, self(), fence, id, unquote(supply_on_resume))

      facts = %{
        "version" => 1,
        "availability" => "available",
        "coverage" => "complete",
        "allocation_bytes" => 6,
        "eligible_count" => 2,
        "eligible_rendered_bytes" => 6,
        "budget_available" => true,
        "query" => "synthetic query",
        "candidates" => [%{"id" => "a", "rendered" => "aaa"}, %{"id" => "b", "rendered" => "bbb"}],
        "alternatives" => [
          %{"id" => "first", "members" => ["a"]},
          %{"id" => "second", "members" => ["b"]}
        ],
        "baseline_id" => "first"
      }

      assert :ok =
               Session.invoke_export(resumed, :command, "ext__advice__shadow", %{
                 "facts" => facts,
                 "consumer" => "notes.select"
               })

      assert_receive {:ipse, ^resumed, {:done, :ok}}, 10_000
      assert Session.info(resumed).extension_result["value"]["action"]["members"] == ["a", "b"]
      assert {:ok, before_prompt} = Journal.load(ctx.dir, id)
      assert :ok = Session.prompt(resumed, "Synthetic next turn requiring a decision")
      assert_receive {:ipse, ^resumed, {:done, :error}}, 10_000
      refute_receive {:ipse, ^resumed, {:approval, _, "extension:decision.create", _}}, 100
      refute_receive {:decision_http, ^tag, _, _, _}, 200
      assert {:ok, history} = Journal.load(ctx.dir, id)
      appended = Enum.drop(history, length(before_prompt))

      assert [event_intent] =
               Enum.filter(appended, &(&1["type"] == "extension_event_intent"))

      assert get_in(event_intent, ["declaration", "mode"]) == "job"
      assert get_in(event_intent, ["declaration", "required"]) == true

      assert [event_result] =
               Enum.filter(appended, &(&1["type"] == "extension_event_result"))

      assert event_result ==
               Ipse.Extension.Subscriptions.result(event_intent, "unknown", false)

      refute Enum.any?(appended, fn event ->
               (event["type"] == "extension_action_intent" and
                  get_in(event, ["request", "op"]) == "decision.create") or
                 event["type"] in ~w(inference_dispatch_intent extension_decision_request)
             end)

      assert [%{"matched" => matched}] =
               Enum.filter(history, &(&1["type"] == "exact_action_fence_attempt"))

      assert matched === unquote(matching)

      intents =
        Enum.filter(
          history,
          &(&1["type"] == "extension_action_intent" and
              get_in(&1, ["request", "op"]) == "decision.create")
        )

      assert length(intents) == if(unquote(interruption) == :approved, do: 1, else: 0)
      assert {:ok, _} = Actions.restore(history)
      assert {:ok, _} = Ipse.Session.SourceWindow.restore(history, id)
      assert {:ok, _} = Ipse.Session.ExactActionFence.restore(history, id)
      assert {:ok, _} = Ipse.Session.Saved.restore(history, id)
      assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(resumed)
    end
  end

  defp experimental_artifact(ctx) do
    path = Path.join(ctx.root, "experimental-artifact")
    File.cp_r!(ctx.artifact, path)
    sidecar = Jason.encode!(%{"domain" => "knowledge", "preset" => "decision-shadow"})
    File.write!(Path.join(path, "operator.json"), sidecar)
    manifest_path = Path.join(path, "extension.json")
    manifest = Jason.decode!(File.read!(manifest_path))

    manifest =
      manifest
      |> Map.put("id", "ipse-knowledge/knowledge")
      |> Map.update!("files", fn files ->
        files ++
          [
            %{
              "path" => "operator.json",
              "bytes" => byte_size(sidecar),
              "sha256" => Ipse.JSON.sha256(sidecar)
            }
          ]
      end)

    File.write!(manifest_path, Jason.encode!(manifest))
    %{ctx | artifact: path}
  end

  test "a digest-marked experiment with no reviewed claim sends no decision request", ctx do
    {base, tag} = http()
    ctx = experimental_artifact(ctx)
    pid = start(ctx, config(ctx, base))
    invoke(pid)
    assert_receive {:ipse, ^pid, {:approval, ref, "extension:decision.create", _}}, 5_000
    assert :ok = Session.approve(pid, ref, true)
    done(pid)
    refute_receive {:decision_http, ^tag, _, _, _}, 100
    refute Enum.any?(events(ctx, pid), &(&1["type"] == "extension_decision_response"))
  end

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

            :disconnect ->
              :ok

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

  test "synthetic shadow selection exercises the Knowledge planner through Session approval",
       ctx do
    {base, tag} = http()
    cfg = config(ctx, base)
    pid = start(ctx, cfg)

    facts = %{
      "version" => 1,
      "availability" => "available",
      "coverage" => "complete",
      "allocation_bytes" => 3,
      "eligible_count" => 2,
      "eligible_rendered_bytes" => 6,
      "budget_available" => true,
      "query" => "synthetic query",
      "candidates" => [%{"id" => "a", "rendered" => "aaa"}, %{"id" => "b", "rendered" => "bbb"}],
      "alternatives" => [
        %{"id" => "first", "members" => ["a"]},
        %{"id" => "second", "members" => ["b"]}
      ],
      "baseline_id" => "first"
    }

    fitting = Map.put(facts, "allocation_bytes", 6)

    assert :ok =
             Session.invoke_export(pid, :command, "ext__advice__shadow", %{
               "facts" => fitting,
               "consumer" => "notes.select"
             })

    done(pid)
    assert Session.info(pid).extension_result["value"]["action"]["members"] == ["a", "b"]
    refute_receive {:decision_http, ^tag, _, _, _}, 100
    refute Enum.any?(events(ctx, pid), &(&1["type"] == "request_admitted"))

    projected_fitting =
      fitting
      |> Map.put("version", 2)
      |> Map.put("source_binding_sha256", String.duplicate("a", 64))
      |> Map.put("baseline_id", nil)
      |> Map.update!("alternatives", fn alternatives ->
        Enum.map(alternatives, &Map.put(&1, "rendered_bytes", 5))
      end)

    assert :ok =
             Session.invoke_export(pid, :command, "ext__advice__shadow", %{
               "facts" => projected_fitting,
               "consumer" => "notes.select"
             })

    done(pid)
    assert Session.info(pid).extension_result["value"]["action"]["members"] == ["a", "b"]
    refute_receive {:decision_http, ^tag, _, _, _}, 100
    refute Enum.any?(events(ctx, pid), &(&1["type"] == "request_admitted"))

    assert :ok =
             Session.invoke_export(pid, :command, "ext__advice__shadow", %{
               "facts" => facts,
               "consumer" => "notes.select"
             })

    assert_receive {:ipse, ^pid, {:approval, ref, "extension:decision.create", proposed}}, 5_000
    assert proposed["request"]["questions"] |> hd() |> Map.fetch!("id") == "pack"
    refute_receive {:decision_http, ^tag, _, _, _}, 100
    assert :ok = Session.approve(pid, ref, true)
    assert_receive {:decision_http, ^tag, handler, _headers, body}, 5_000
    assert body["questions"]["pack"]["type"] == "choice"

    send(
      handler,
      {:respond,
       %{
         "model" => "fixture",
         "answers" => %{
           "pack" => %{
             "type" => "choice",
             "choice" => "second",
             "confidence" => 0.2,
             "probabilities" => %{"first" => 0.1, "second" => 0.9}
           }
         },
         "usage" => %{"input_tokens" => 10, "output_tokens" => 2}
       }}
    )

    done(pid)
    result = Session.info(pid).extension_result["value"]
    assert result["action"] == %{"pack" => "second", "members" => ["b"]}
    assert result["receipt"]["source_facts"] == "untrusted"
    ev = events(ctx, pid)
    assert {:ok, _} = Actions.restore(ev)
    assert Enum.count(ev, &(&1["type"] == "request_admitted")) == 1

    refute Enum.any?(
             ev,
             &(&1["type"] == "extension_action_intent" and
                 &1["request"]["op"] in ~w(state.put collection.managed))
           )

    assert :ok =
             Session.invoke_export(pid, :command, "ext__advice__shadow", %{
               "facts" => facts,
               "consumer" => "notes.select"
             })

    assert_receive {:ipse, ^pid, {:approval, denied, "extension:decision.create", _}}, 5_000
    assert :ok = Session.approve(pid, denied, false)
    done(pid)
    assert Session.info(pid).extension_result["value"] == %{"status" => "denied"}
    refute_receive {:decision_http, ^tag, _, _, _}, 100
    ev = events(ctx, pid)
    assert Enum.count(ev, &(&1["type"] == "request_admitted")) == 1
    assert {:ok, _} = Actions.restore(ev)
    id = Session.info(pid).id
    assert :ok = Session.close_confirmed(pid)
    resumed = start(ctx, cfg, id)
    assert Session.info(resumed).phase == :idle
    refute_receive {:decision_http, ^tag, _, _, _}, 100
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
    after_resume = File.read!(path)
    assert String.starts_with?(after_resume, before)

    suffix =
      binary_part(after_resume, byte_size(before), byte_size(after_resume) - byte_size(before))

    [marker] = String.split(suffix, "\n", trim: true) |> Enum.map(&Jason.decode!/1)
    assert Ipse.Session.ReleaseReceipt.valid_owner_marker?(marker, id)
    refute_receive {:decision_http, ^tag, _, _, _}, 100
  end

  test "synthetic shadow assessment keeps low-probability candidates on the baseline", ctx do
    {base, tag} = http()
    pid = start(ctx, config(ctx, base))

    facts = %{
      "version" => 1,
      "availability" => "available",
      "budget_available" => true,
      "candidates" => [
        %{"id" => "a", "input" => "first synthetic candidate"},
        %{"id" => "b", "input" => "second synthetic candidate"}
      ],
      "alternatives" => ~w(keep_baseline defer_candidate)
    }

    assert :ok =
             Session.invoke_export(pid, :command, "ext__advice__shadow", %{
               "facts" => Map.put(facts, "candidates", []),
               "consumer" => "notes.assess"
             })

    done(pid)
    assert Session.info(pid).extension_result["value"]["action"]["candidates"] == []
    refute_receive {:decision_http, ^tag, _, _, _}, 100
    refute Enum.any?(events(ctx, pid), &(&1["type"] == "request_admitted"))

    assert :ok =
             Session.invoke_export(pid, :command, "ext__advice__shadow", %{
               "facts" => facts,
               "consumer" => "notes.assess"
             })

    assert_receive {:ipse, ^pid, {:approval, ref, "extension:decision.create", proposed}}, 5_000
    assert Enum.map(proposed["request"]["questions"], & &1["id"]) == ["a", "b"]
    refute_receive {:decision_http, ^tag, _, _, _}, 100
    assert :ok = Session.approve(pid, ref, true)
    assert_receive {:decision_http, ^tag, handler, _headers, body}, 5_000
    assert Map.keys(body["questions"]) |> Enum.sort() == ["a", "b"]

    send(
      handler,
      {:respond,
       %{
         "model" => "fixture",
         "answers" => %{
           "a" => %{
             "type" => "choice",
             "choice" => "defer_candidate",
             "confidence" => 0.4,
             "probabilities" => %{"defer_candidate" => 0.9, "keep_baseline" => 0.1}
           },
           "b" => %{
             "type" => "choice",
             "choice" => "defer_candidate",
             "confidence" => 0.4,
             "probabilities" => %{"defer_candidate" => 0.6, "keep_baseline" => 0.4}
           }
         },
         "usage" => %{"input_tokens" => 10, "output_tokens" => 2}
       }}
    )

    done(pid)
    result = Session.info(pid).extension_result["value"]

    assert result["action"]["candidates"] == [
             %{"id" => "a", "choice" => "defer_candidate", "reason" => "selected"},
             %{"id" => "b", "choice" => "keep_baseline", "reason" => "low_probability"}
           ]

    assert result["receipt"]["source_facts"] == "untrusted"
    ev = events(ctx, pid)
    assert {:ok, _} = Actions.restore(ev)

    refute Enum.any?(
             ev,
             &(&1["type"] == "extension_action_intent" and
                 &1["request"]["op"] in ~w(state.put collection.managed))
           )
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

  test "shadow assessment preserves independent advice when OpenAI refuses one question", ctx do
    {base, tag} = http()
    old_key = System.get_env("OPENAI_API_KEY")
    System.put_env("OPENAI_API_KEY", "synthetic-shadow-credential")

    on_exit(fn ->
      if old_key,
        do: System.put_env("OPENAI_API_KEY", old_key),
        else: System.delete_env("OPENAI_API_KEY")
    end)

    cfg = config(ctx, base)

    profile =
      cfg.decision_profiles["advice"]
      |> Map.merge(%{
        "provider" => "openai",
        "model" => "gpt-6-luna",
        "expected_model" => "gpt-6-luna"
      })

    pid = start(ctx, Map.put(cfg, :decision_profiles, %{"advice" => profile}))

    facts = %{
      "version" => 1,
      "availability" => "available",
      "budget_available" => true,
      "candidates" => [
        %{"id" => "a", "input" => "first synthetic candidate"},
        %{"id" => "b", "input" => "second synthetic candidate"}
      ],
      "alternatives" => ~w(keep_baseline defer_candidate)
    }

    assert :ok =
             Session.invoke_export(pid, :command, "ext__advice__shadow", %{
               "facts" => facts,
               "consumer" => "notes.assess"
             })

    assert_receive {:ipse, ^pid, {:approval, ref, "extension:decision.create", _}}, 5_000
    assert :ok = Session.approve(pid, ref, true)
    assert_receive {:decision_http, ^tag, handler, headers, body}, 5_000
    assert headers =~ "POST /decisions HTTP/1.1"
    assert Enum.map(body["questions"], & &1["name"]) == ["a", "b"]

    send(
      handler,
      {:respond,
       %{
         "model" => "gpt-6-luna",
         "answers" => [
           %{"name" => "a", "type" => "refusal"},
           %{
             "name" => "b",
             "type" => "choice",
             "choice" => "defer_candidate",
             "confidence" => 0.4,
             "probabilities" => [
               %{"value" => "defer_candidate", "probability" => 0.9},
               %{"value" => "keep_baseline", "probability" => 0.1}
             ]
           }
         ],
         "usage" => %{"input_tokens" => 10, "output_tokens" => 0}
       }}
    )

    done(pid)

    assert Session.info(pid).extension_result["value"]["action"]["candidates"] == [
             %{"id" => "a", "choice" => "keep_baseline", "reason" => "refusal"},
             %{"id" => "b", "choice" => "defer_candidate", "reason" => "selected"}
           ]

    ev = events(ctx, pid)
    assert {:ok, _} = Actions.restore(ev)
    refute Jason.encode!(ev) =~ "synthetic-shadow-credential"
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
      assert Session.info(pid).extension_result["value"]["value"]["code"] == "decision_response"
    end

    ev = events(ctx, pid)
    refute Enum.any?(ev, &(&1["type"] == "extension_decision_response"))
    assert {:ok, _} = Usage.restore(ev)
    assert {:ok, _} = Actions.restore(ev)
  end

  test "a disconnected decision request remains a request failure with partial accounting", ctx do
    {base, tag} = http()
    pid = start(ctx, config(ctx, base, %{approval: :allow}))
    invoke(pid)
    assert_receive {:decision_http, ^tag, handler, _, _}, 5000
    send(handler, :disconnect)
    done(pid)

    assert Session.info(pid).extension_result["value"] == %{
             "status" => "failed",
             "value" => %{"code" => "decision_request_failed"}
           }

    ev = events(ctx, pid)
    refute Enum.any?(ev, &(&1["type"] == "extension_decision_response"))

    assert %{"outcome" => "failed", "finality" => "partial"} =
             Enum.find(ev, &(&1["type"] == "request_finished"))

    assert {:ok, _} = Usage.restore(ev)
    assert {:ok, _} = Actions.restore(ev)
    refute_receive {:decision_http, ^tag, _, _, _}, 200
  end

  test "malformed decision retains finite budget liability and is not replayed on resume", ctx do
    {base, tag} = http()
    cfg = config(ctx, base, %{approval: :allow, budget: %{"version" => 1, "max_requests" => 1}})
    pid = start(ctx, cfg)
    id = Session.info(pid).id
    invoke(pid)
    assert_receive {:decision_http, ^tag, handler, _, _}, 5000
    send(handler, {:respond, put_in(native(), ["answers", "relevant", "noul"], 1.5)})
    done(pid)
    assert Session.info(pid).extension_result["value"]["value"]["code"] == "decision_response"
    assert :ok = Session.close_confirmed(pid)
    assert {:ok, snapshot} = Budget.saved(ctx.dir, id)
    assert snapshot["request_count"] == 1
    assert snapshot["unsettled_count"] + snapshot["partial_count"] >= 1
    resumed = start(ctx, cfg, id)
    assert Session.info(resumed).phase == :idle
    refute_receive {:decision_http, ^tag, _, _, _}, 200
    invoke(resumed)
    done(resumed)
    refute_receive {:decision_http, ^tag, _, _, _}, 200
    assert {:ok, events} = Journal.load(ctx.dir, id)
    assert {:ok, _} = Usage.restore(events)
    assert {:ok, _} = Actions.restore(events)
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
