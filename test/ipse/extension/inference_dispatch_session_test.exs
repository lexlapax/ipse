Code.require_file("../../support/provider_fixture.ex", __DIR__)

defmodule Ipse.Extension.InferenceDispatchSessionTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Usage, InferenceSlots}
  alias Ipse.Extension.{Artifact, Config, Registry}
  alias Ipse.Test.ProviderFixture

  defmodule DraftModel do
    def complete(config, messages, _, _) do
      send(config.test_pid, {:draft_fixture_model, messages})
      {:ok, %{"role" => "assistant", "content" => "synthetic proposal"}, %{}}
    end
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-sdk-dispatch-fixture-" <> Usage.id())
    File.mkdir_p!(Path.join(root, "ebin"))
    module = "Independent.InferenceDispatchFixture#{System.unique_integer([:positive])}"

    caps =
      ~w(invoke.command host.actions host.model host.embedding host.decision host.history host.history.tool.result host.history.prompt.expanded)

    command = %{
      "id" => "infer",
      "description" => "Synthetic explicit inference",
      "arguments_schema" => %{
        "type" => "object",
        "required" => ["request"],
        "additionalProperties" => false,
        "properties" => %{"request" => %{"type" => "object"}}
      },
      "result_schema" => %{"type" => "object"}
    }

    exports = Map.put(Ipse.Extension.Catalog.empty(), "commands", [command])

    source = """
    defmodule #{module} do
      @behaviour Ipse.Extension
      def describe, do: %{"sdk" => 1, "capabilities" => #{inspect(caps)}, "exports" => #{inspect(exports)}}
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
        ["-pa", Application.app_dir(:ipse, "ebin"), "-o", Path.join(root, "ebin"), file],
        stderr_to_stdout: true
      )

    assert status == 0, log
    File.write!(Path.join(root, "LICENSE"), "MIT synthetic fixture")
    paths = ["LICENSE", "ebin/Elixir.#{module}.beam"]

    manifest = %{
      "format" => 1,
      "id" => "fixture/inference-dispatch",
      "version" => "0.1.0",
      "sdk" => 1,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => module,
      "license_file" => "LICENSE",
      "options_schema" => %{"type" => "object", "additionalProperties" => false},
      "capabilities" => caps,
      "exports" => exports,
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
    base = Path.join(System.tmp_dir!(), "ipse-sdk-dispatch-" <> Usage.id())
    home = Path.join(base, "operator")
    cwd = Path.join(base, "project")
    File.mkdir_p!(home)
    File.mkdir_p!(cwd)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(base) end)
    %{base: base, home: home, cwd: cwd, sessions: Path.join(base, "sessions")}
  end

  defp config(c, base) do
    {:ok, artifact} = Artifact.import(c.artifact, Path.join(c.home, "extensions/artifacts"))

    data = %{
      "extensions" => [
        %{
          "instance" => "probe",
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
          "capabilities" => c.capabilities,
          "allow_project" => false,
          "allow_children" => false
        }
      ]
    }

    {:ok, selected} =
      Config.resolve(
        [%{scope: "operator", path: Path.join(c.home, "operator.json"), data: data}],
        []
      )

    {:ok, entries} = Registry.prepare(selected, c.home)

    %{
      provider: :demo,
      model: "unused",
      home: c.home,
      timeout_ms: 3000,
      extensions: entries,
      approval: :allow,
      compact: false,
      inference_services: %{"local" => %{"version" => 1, "origins" => [base]}},
      model_profiles: %{
        "answer" => %{
          "provider" => "ollama",
          "model" => "fixture",
          "base_url" => base,
          "timeout_ms" => 3000
        }
      },
      embedding_profiles: %{
        "search" => %{
          "operation" => "embedding",
          "provider" => "ollama",
          "model" => "fixture",
          "base_url" => base,
          "dimensions" => 2,
          "dimension_mode" => "native",
          "timeout_ms" => 3000
        }
      },
      decision_profiles: %{
        "advice" => %{
          "operation" => "decision",
          "provider" => "system_one_compatible",
          "model" => "fixture",
          "expected_model" => "fixture",
          "service_id" => "local",
          "base_url" => base,
          "timeout_ms" => 3000
        }
      }
    }
  end

  defp pin_config(c, config) do
    alias Ipse.Extension.{
      Consent,
      ProjectIdentity,
      SemanticAdmission,
      SemanticConsent,
      SemanticRoutes
    }

    {:ok, binding} = ProjectIdentity.admit(c.home, c.cwd, :folder)
    identity = hd(config.extensions).identity

    {:ok, _, descriptor} =
      Ipse.Extension.Catalog.lookup(config, "invoke.command", "ext__probe__infer")

    labels = %{
      "processing_region" => nil,
      "storage_region" => nil,
      "cache_retention" => nil,
      "account_controls" => nil
    }

    selectors =
      for {operation, profile} <- [
            {"main", nil},
            {"model.complete", "answer"},
            {"embedding.create", "search"},
            {"decision.create", "advice"}
          ],
          do: Map.merge(labels, %{"operation" => operation, "profile" => profile})

    {:ok, routes} = SemanticRoutes.resolve(config, selectors)
    {:ok, namespace} = SemanticConsent.namespace(binding["project_id"], "notes")

    selection = %{
      "domain" => "knowledge",
      "namespace" => namespace,
      "scope" => %{"kind" => "project", "worktree_id" => nil},
      "sources" => %{"categories" => ["unattended_input"], "exclusions" => []},
      "storage" => %{"kind" => "local_collection", "collection" => "notes"},
      "retention" => %{"automatic" => 90, "manual" => 3650},
      "routes" => routes,
      "effects" => [
        %{
          "operation" => "notes.propose",
          "class" => "collection.publish",
          "outer_sha256" => Ipse.JSON.digest([descriptor]),
          "inner_op" => "collection.call",
          "constraints" => %{
            "version" => 1,
            "key_prefix" => "note.",
            "allow_delete" => false,
            "source_categories" => ["unattended_input"],
            "evidence_path" => ["sources"],
            "value_schema" => %{
              "type" => "object",
              "properties" => %{
                "sources" => %{"type" => "array", "items" => %{"type" => "string"}}
              },
              "required" => ["sources"],
              "additionalProperties" => false
            }
          }
        }
      ],
      "limits" => Map.merge(Consent.zero(), %{"operations" => 4, "input_bytes" => 100_000}),
      "period_ms" => 86_400_000,
      "expires_at_ms" => System.system_time(:millisecond) + 600_000,
      "headless" => true
    }

    {:ok, policy} = SemanticConsent.prepare(binding, identity, selection)
    root = SemanticAdmission.control_root(c.home)
    {:ok, snapshot} = Consent.snapshot(root, binding["project_id"])

    {:ok, _} =
      Consent.replace(
        root,
        binding["project_id"],
        snapshot["epoch"],
        policy,
        System.system_time(:millisecond)
      )

    {:ok, selected} = Ipse.Config.Semantics.selection(policy)
    {Map.put(config, :semantic_selections, selected), root, binding}
  end

  test "accepted draft lineage binds actual unregistered extension model, embedding and decision helpers",
       c do
    text =
      Jason.encode!(%{
        "model" => "fixture",
        "message" => %{"role" => "assistant", "content" => "fixture result"},
        "done" => true
      }) <> "\n"

    embedding =
      Jason.encode!(%{
        "model" => "fixture",
        "embeddings" => [[1.0, 0.5]],
        "prompt_eval_count" => 1
      })

    decision =
      Jason.encode!(%{
        "model" => "fixture",
        "answers" => %{"relevant" => %{"type" => "noul", "noul" => 0.8}},
        "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
      })

    {base, server} = ProviderFixture.sequence([text, embedding, decision])
    on_exit(fn -> if Process.alive?(server.pid), do: Process.exit(server.pid, :kill) end)

    config =
      config(c, base)
      |> Map.delete(:inference_services)
      |> Map.merge(%{provider_module: DraftModel, test_pid: self()})

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: c.cwd, state_dir: c.sessions, subscriber: self()}
      )

    id = Session.info(pid).id
    assert :ok = Session.start_draft(pid, "private helper draft")
    assert_receive {:draft_fixture_model, _}, 5_000
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5_000
    {:ok, %{id: draft_id, revision: 1}} = Session.draft(pid)
    assert :ok = Session.replace_draft(pid, draft_id, 1, "accepted request")
    assert :ok = Session.close_confirmed(pid)
    {:ok, events} = Ipse.Journal.load(c.sessions, id)
    {:ok, draft} = Ipse.Session.Draft.restore(events, id)
    {:ok, render} = Ipse.Session.DraftAcceptance.render(draft, Usage.id())
    text_input = "accept " <> render["code"]

    observation = %{
      "version" => 2,
      "event_id" => Usage.id(),
      "display_limit" => 16_777_216,
      "input_limit" => 1_048_576,
      "display_sha256" => Ipse.JSON.sha256(render["display"]),
      "text_sha256" => Ipse.JSON.sha256(text_input)
    }

    {:ok, receipt} = Ipse.Session.DraftAcceptance.receipt(draft, render, text_input, observation)
    assert :ok = Ipse.Journal.append(c.sessions, id, Ipse.Session.Draft.accepted(draft, receipt))

    {:ok, resumed} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: c.cwd, state_dir: c.sessions, id: id, subscriber: self()}
      )

    on_exit(fn -> if Process.alive?(resumed), do: Session.close_confirmed(resumed) end)
    assert :ok = Session.consume_draft(resumed, draft_id, 2)
    assert_receive {:draft_fixture_model, input}, 5_000
    refute inspect(input) =~ "private helper draft"
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 5_000

    request = %{
      "op" => "model.complete",
      "version" => 1,
      "profile" => "answer",
      "instruction" => "Return synthetic text",
      "input" => "Public fixture",
      "max_output_bytes" => 1024,
      "timeout_ms" => 3000
    }

    assert :ok =
             Session.invoke_export(resumed, :command, "ext__probe__infer", %{"request" => request})

    assert_receive {:ipse, ^resumed, {:done, :ok}}, 10_000

    embedding_request = %{
      "op" => "embedding.create",
      "version" => 1,
      "profile" => "search",
      "inputs" => ["Public fixture"],
      "timeout_ms" => 3000
    }

    assert :ok =
             Session.invoke_export(resumed, :command, "ext__probe__infer", %{
               "request" => embedding_request
             })

    assert_receive {:ipse, ^resumed, {:done, :ok}}, 10_000

    decision_request = %{
      "op" => "decision.create",
      "version" => 1,
      "profile" => "advice",
      "input" => "Public fixture",
      "timeout_ms" => 3000,
      "questions" => [
        %{"id" => "relevant", "type" => "predicate", "instructions" => "Synthetic fixture"}
      ]
    }

    assert :ok =
             Session.invoke_export(resumed, :command, "ext__probe__infer", %{
               "request" => decision_request
             })

    assert_receive {:ipse, ^resumed, {:done, :ok}}, 10_000
    assert [{http, _}, {http2, _}, {http3, _}] = Task.await(server)
    assert http =~ "POST /api/chat" and http2 =~ "POST /api/embed" and http3 =~ "POST /systemone"

    {:ok, source_page} = Ipse.Journal.source_page(c.sessions, id, 0, 64)
    draft_start = Enum.find(source_page.records, &(&1.record["type"] == "draft_started"))

    history_request = %{
      "op" => "history.read",
      "view" => "prompt.expanded",
      "cursor" => draft_start.source["byte_offset"],
      "snapshot" => nil,
      "limit" => 8
    }

    assert :ok =
             Session.invoke_export(resumed, :command, "ext__probe__infer", %{
               "request" => history_request
             })

    assert_receive {:ipse, ^resumed, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(resumed)
    {:ok, events} = Ipse.Journal.load(c.sessions, id)

    history =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "op"]) == "history.read")
      )

    assert history["outcome"]["status"] == "ok"
    assert Enum.any?(history["outcome"]["value"]["records"], &(&1["reason"] == "draft_withheld"))
    refute inspect(history) =~ "private helper draft"
    assert :ok = Ipse.Extension.Subscriptions.validate_sources(c.sessions, id, events)

    assert Enum.any?(
             events,
             &(&1["type"] == "draft_extension_intent" and
                 &1["target_type"] == "extension_action_intent")
           )

    assert Enum.any?(
             events,
             &(&1["type"] == "draft_extension_intent" and &1["target_type"] == "request_admitted")
           )

    for type <-
          ~w(extension_invocation_intent extension_action_intent extension_model_request extension_embedding_request extension_decision_request) do
      assert Enum.any?(
               events,
               &(&1["type"] == "draft_extension_intent" and &1["target_type"] == type)
             )
    end

    assert Enum.any?(
             events,
             &(&1["type"] == "extension_action_intent" and
                 get_in(&1, ["request", "op"]) == "history.read")
           )

    assert {:ok, _} = Session.Saved.restore(events, id)
  end

  test "actual independent SDK text, embedding and decision share the registered endpoint and publish only settled results",
       c do
    text =
      Jason.encode!(%{
        "model" => "fixture",
        "message" => %{"role" => "assistant", "content" => "Complete"},
        "done" => true,
        "done_reason" => "stop",
        "prompt_eval_count" => 1,
        "eval_count" => 1
      }) <> "\n"

    embedding =
      Jason.encode!(%{
        "model" => "fixture",
        "embeddings" => [[1.0, 0.5]],
        "prompt_eval_count" => 1
      })

    decision =
      Jason.encode!(%{
        "model" => "fixture",
        "answers" => %{"relevant" => %{"type" => "noul", "noul" => 0.8}},
        "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
      })

    {base, server} = ProviderFixture.sequence([text, embedding, decision])
    on_exit(fn -> if Process.alive?(server.pid), do: Process.exit(server.pid, :kill) end)
    config = config(c, base)

    case InferenceSlots.status(config, cwd: c.cwd) do
      {:error, :service_filesystem_unsupported} ->
        IO.puts("#{c.test}: filesystem unsupported; positive SDK service journey NOT RUN")

      {:ok, _} ->
        {config, _control, _binding} = pin_config(c, config)

        {:ok, pid} =
          DynamicSupervisor.start_child(
            Ipse.Sessions,
            {Session, config: config, cwd: c.cwd, state_dir: c.sessions, subscriber: self()}
          )

        on_exit(fn -> if Process.alive?(pid), do: Session.close_confirmed(pid) end)
        assert :sys.get_state(pid).config.semantic_admission["status"] == "active"

        requests = [
          %{
            "op" => "model.complete",
            "version" => 1,
            "profile" => "answer",
            "instruction" => "Return synthetic text",
            "input" => "Public fixture",
            "max_output_bytes" => 1024,
            "timeout_ms" => 3000
          },
          %{
            "op" => "embedding.create",
            "version" => 1,
            "profile" => "search",
            "inputs" => ["Public fixture"],
            "timeout_ms" => 3000
          },
          %{
            "op" => "decision.create",
            "version" => 1,
            "profile" => "advice",
            "input" => "Public fixture",
            "timeout_ms" => 3000,
            "questions" => [
              %{"id" => "relevant", "type" => "predicate", "instructions" => "Synthetic fixture"}
            ]
          }
        ]

        for request <- requests do
          assert :ok =
                   Session.invoke_export(pid, :command, "ext__probe__infer", %{
                     "request" => request
                   })

          assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
          assert {:ok, state} = InferenceSlots.status(config, cwd: c.cwd)
          assert state["services"]["local"]["active"] == nil
        end

        assert [{h1, _}, {h2, _}, {h3, _}] = Task.await(server)
        assert h1 =~ "POST /api/chat" and h2 =~ "POST /api/embed" and h3 =~ "POST /systemone"
        assert {:ok, events} = Ipse.Journal.load(c.sessions, Session.info(pid).id)
        assert {:ok, _} = Session.restore_context(events)

        assert Enum.map(
                 Enum.filter(events, &(&1["type"] == "inference_dispatch_intent")),
                 & &1["phase"]
               ) == ~w(model.complete embedding.create decision.create)

        results = Enum.filter(events, &(&1["type"] == "extension_action_result"))
        assert length(results) == 3 and Enum.all?(results, &(&1["outcome"]["status"] == "ok"))
        assert {:ok, state} = InferenceSlots.status(config, cwd: c.cwd)
        assert length(state["recent"]) == 3

      other ->
        flunk("bootstrap failed: #{inspect(other)}")
    end
  end

  test "a different project's actual SDK embedding waits for main HTTP without reserving its budget",
       c do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    base = "http://127.0.0.1:#{port}"
    on_exit(fn -> :gen_tcp.close(listener) end)
    config = config(c, base) |> Map.put(:budget, %{"version" => 1, "max_requests" => 2})

    case InferenceSlots.status(config, cwd: c.cwd) do
      {:error, :service_filesystem_unsupported} ->
        IO.puts("#{c.test}: filesystem unsupported; positive concurrent SDK journey NOT RUN")

      {:ok, _} ->
        parent = self()

        server =
          Task.async(fn ->
            for {kind, response} <- [
                  {:main,
                   Jason.encode!(%{
                     "model" => "fixture",
                     "message" => %{"role" => "assistant", "content" => "Complete"},
                     "done" => true,
                     "prompt_eval_count" => 1,
                     "eval_count" => 1
                   }) <> "\n"},
                  {:embedding,
                   Jason.encode!(%{
                     "model" => "fixture",
                     "embeddings" => [[1.0, 0.5]],
                     "prompt_eval_count" => 1
                   })}
                ] do
              {:ok, socket} = :gen_tcp.accept(listener, 5000)
              {headers, _} = ProviderFixture.request(socket, "")
              send(parent, {:actual_dispatch_http, kind, self(), headers})
              if kind == :main, do: receive(do: (:respond -> :ok))

              :ok =
                :gen_tcp.send(
                  socket,
                  "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(response)}\r\nconnection: close\r\n\r\n" <>
                    response
                )

              :gen_tcp.close(socket)
            end
          end)

        on_exit(fn -> if Process.alive?(server.pid), do: Process.exit(server.pid, :kill) end)
        main_config = config |> Map.merge(%{provider: :ollama, model: "fixture", base_url: base})
        other = Path.join(c.base, "different-project")
        File.mkdir_p!(other)

        {:ok, main} =
          DynamicSupervisor.start_child(
            Ipse.Sessions,
            {Session, config: main_config, cwd: c.cwd, state_dir: c.sessions, subscriber: self()}
          )

        {:ok, sdk} =
          DynamicSupervisor.start_child(
            Ipse.Sessions,
            {Session, config: config, cwd: other, state_dir: c.sessions, subscriber: self()}
          )

        on_exit(fn ->
          for pid <- [main, sdk], Process.alive?(pid), do: Session.close_confirmed(pid)
        end)

        assert :ok = Session.prompt(main, "Synthetic main request")
        assert_receive {:actual_dispatch_http, :main, handler, first}, 5000
        assert first =~ "POST /api/chat"

        request = %{
          "op" => "embedding.create",
          "version" => 1,
          "profile" => "search",
          "inputs" => ["Synthetic input"],
          "timeout_ms" => 3000
        }

        assert :ok =
                 Session.invoke_export(sdk, :command, "ext__probe__infer", %{"request" => request})

        assert_receive {:ipse, ^sdk, {:inference_service_status, %{"state" => "waiting"}}}, 5000
        assert {:error, :timeout} = :gen_tcp.accept(listener, 100)
        assert {:ok, budget} = Ipse.Usage.Budget.snapshot(:sys.get_state(sdk).config)
        assert budget["request_count"] == 0
        send(handler, :respond)
        assert_receive {:actual_dispatch_http, :embedding, _, second}, 5000
        assert second =~ "POST /api/embed"
        assert_receive {:ipse, ^main, {:done, :ok}}, 5000
        assert_receive {:ipse, ^sdk, {:done, :ok}}, 5000
        Task.await(server)
        assert {:ok, state} = InferenceSlots.status(config, cwd: c.cwd)
        assert state["services"]["local"]["active"] == nil and length(state["recent"]) == 2

      other ->
        flunk("bootstrap failed: #{inspect(other)}")
    end
  end

  test "revocation while an actual SDK call is queued refuses protected final admission before HTTP",
       c do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)
    on_exit(fn -> :gen_tcp.close(listener) end)

    config =
      config(c, "http://127.0.0.1:#{port}")
      |> Map.put(:budget, %{"version" => 1, "max_requests" => 2})

    case InferenceSlots.status(config, cwd: c.cwd) do
      {:error, :service_filesystem_unsupported} ->
        IO.puts("#{c.test}: filesystem unsupported; protected queued revocation journey NOT RUN")

      {:ok, _} ->
        {config, control, binding} = pin_config(c, config)
        parent = self()

        selector = %{
          "operation" => "embedding.create",
          "profile" => "search",
          "processing_region" => nil,
          "storage_region" => nil,
          "cache_retention" => nil,
          "account_controls" => nil
        }

        held =
          Task.async(fn ->
            InferenceSlots.run(
              config,
              selector,
              %{
                "session_id" => Usage.id(),
                "project_id" => Ipse.JSON.sha256("other"),
                "request_sha256" => Ipse.JSON.sha256("synthetic"),
                "priority" => "foreground"
              },
              [cwd: c.cwd, wait_ms: 5000, dispatch_timeout_ms: 5000],
              fn _ ->
                send(parent, {:protected_held_service, self()})
                receive do: (:release -> {:settled, :released})
              end
            )
          end)

        assert_receive {:protected_held_service, holder}, 3000

        {:ok, pid} =
          DynamicSupervisor.start_child(
            Ipse.Sessions,
            {Session, config: config, cwd: c.cwd, state_dir: c.sessions, subscriber: self()}
          )

        on_exit(fn -> if Process.alive?(pid), do: Session.close_confirmed(pid) end)
        assert :sys.get_state(pid).config.semantic_admission["status"] == "active"

        request = %{
          "op" => "embedding.create",
          "version" => 1,
          "profile" => "search",
          "inputs" => ["Public input"],
          "timeout_ms" => 3000
        }

        assert :ok =
                 Session.invoke_export(pid, :command, "ext__probe__infer", %{"request" => request})

        assert_receive {:ipse, ^pid, {:inference_service_status, %{"state" => "waiting"}}}, 5000
        alias Ipse.Extension.Consent
        {:ok, current} = Consent.snapshot(control, binding["project_id"])
        assert {:ok, _} = Consent.revoke(control, binding["project_id"], current["epoch"])
        send(holder, :release)
        assert {:ok, :released} = Task.await(held, 5000)
        assert_receive {:ipse, ^pid, {:done, :ok}}, 5000
        assert {:error, :timeout} = :gen_tcp.accept(listener, 100)
        assert {:ok, budget} = Ipse.Usage.Budget.snapshot(:sys.get_state(pid).config)
        assert budget["request_count"] == 0
        assert {:ok, events} = Ipse.Journal.load(c.sessions, Session.info(pid).id)

        refute Enum.any?(
                 events,
                 &(&1["type"] in ~w(inference_dispatch_intent extension_effect_result))
               )

        [result] = Enum.filter(events, &(&1["type"] == "extension_action_result"))
        assert result["outcome"]["status"] == "failed"
        assert {:ok, slots} = InferenceSlots.status(config, cwd: c.cwd)
        assert slots["services"]["local"]["active"] == nil and length(slots["recent"]) == 1

      other ->
        flunk("bootstrap failed: #{inspect(other)}")
    end
  end
end
