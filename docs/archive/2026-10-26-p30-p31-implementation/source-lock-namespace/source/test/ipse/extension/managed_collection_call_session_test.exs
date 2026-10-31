Code.require_file("../../support/provider_fixture.ex", __DIR__)
Code.require_file("../../support/managed_mcp_http.exs", __DIR__)

defmodule Ipse.Extension.ManagedCollectionCallSessionTest do
  use ExUnit.Case, async: false
  alias Ipse.{Session, Journal, JSON}

  alias Ipse.Extension.{
    Artifact,
    Catalog,
    Registry,
    SemanticAdmission,
    SemanticConsent,
    Consent,
    ProjectIdentity
  }

  defmodule Model do
    def complete(config, messages, _, _) do
      if Enum.any?(messages, &(&1["role"] == "tool")) do
        {:ok, %{"role" => "assistant", "content" => "Synthetic capture finished."}, %{}}
      else
        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => [
             %{
               "id" => "capture",
               "type" => "function",
               "function" => %{
                 "name" => "ext__capture__" <> (config[:fixture_export] || "capture"),
                 "arguments" => Jason.encode!(%{"mode" => config[:fixture_mode] || "capture"})
               }
             }
           ]
         }, %{}}
      end
    end
  end

  setup_all do
    root = Path.join(System.tmp_dir!(), "ipse-collection-sdk-artifact-" <> Ipse.Usage.id())
    File.mkdir_p!(Path.join(root, "ebin"))
    on_exit(fn -> File.rm_rf!(root) end)
    name = "Independent.Collection#{System.unique_integer([:positive])}"

    capabilities =
      ~w(invoke.tool invoke.command invoke.result.pages host.actions host.sources host.collection.read host.collection.write host.collection.managed host.tools host.model)

    exports =
      Catalog.empty()
      |> Map.put("tools", [
        %{
          "id" => "capture",
          "description" => "Synthetic constrained capture",
          "arguments_schema" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ["mode"],
            "properties" => %{"mode" => %{"type" => "string"}}
          },
          "result_schema" => %{"type" => "object"}
        }
      ])
      |> then(fn exports ->
        Map.update!(exports, "tools", fn [capture] ->
          [capture, %{capture | "id" => "inspect"}]
        end)
      end)
      |> then(fn exports -> Map.put(exports, "commands", exports["tools"]) end)

    source = """
    defmodule #{name} do
      @behaviour Ipse.Extension
      def describe, do: %{"sdk" => 2, "capabilities" => #{inspect(capabilities)}, "exports" => #{inspect(exports)}}
      def init(options), do: {:ok, options}
      def handle(stage, payload, state) when stage in ["invoke.tool", "invoke.command"] do
        File.write!(state["trace"], "entered\\n", [:append])
        state = Map.put(state, "mode", payload["arguments"]["mode"])
        cond do
        String.starts_with?(state["mode"], "legacy_get:") ->
          key = String.replace_prefix(state["mode"], "legacy_get:", "")
          call(%{"op" => "collection.call", "request" => %{"op" => "get", "key" => key}}, Map.put(state, "step", "done"))
        state["mode"] == "ordinary" ->
          call(%{"op" => "tool.call", "name" => "write", "timeout_ms" => 1000, "arguments" => %{"path" => "forbidden", "content" => "denied"}}, Map.put(state, "step", "done"))
        state["mode"] in ["read", "read_hold", "paged_read"] ->
          call(%{"op" => "collection.call", "request" => %{"op" => "snapshot"}}, Map.put(state, "step", "done"))
        state["mode"] == "helper" ->
          call(%{"op" => "collection.call", "request" => %{"op" => "snapshot"}}, Map.put(state, "step", "helper_read"))
        true ->
          call(%{"op" => "source.list", "limit" => 32}, Map.put(state, "step", "list"))
        end
      end
      def handle("host.actions", %{"outcome" => outcome}, state) do
        File.write!(state["trace"], Jason.encode!(outcome) <> "\\n", [:append])
        advance(state["step"], outcome, state)
      end
      defp advance("helper_read", outcome, state) do
        call(%{"op" => "model.complete", "version" => 1, "profile" => "extract", "instruction" => "Summarize the supplied observation", "input" => Jason.encode!(outcome), "max_output_bytes" => 1024, "timeout_ms" => 3000}, Map.put(state, "step", "done"))
      end
      defp advance("list", %{"status" => "ok", "value" => value}, state) do
        row = Enum.find(value["sources"], &(&1["kind"] == "input.original"))
        call(%{"op" => "source.read", "handle" => row["read_handle"]}, Map.put(state, "step", "read"))
      end
      defp advance("read", %{"status" => "ok", "value" => page}, state) do
        call(%{"op" => "source.quote", "handle" => page["handle"], "quote" => "Synthetic café observation"}, state |> Map.put("step", "quote") |> Map.put("page", page))
      end
      defp advance("quote", %{"status" => "ok", "value" => quote}, state) do
        {:ok, proof} = Ipse.Extension.source_proof(state["page"], quote, "Synthetic café observation")
        call(%{"op" => "collection.call", "request" => %{"op" => "snapshot"}}, state |> Map.put("step", "snapshot") |> Map.put("proof", proof))
      end
      defp advance("snapshot", %{"status" => "ok", "value" => snapshot}, state) do
        if state["mode"] == "hold", do: (File.write!(state["trace"], "held\\n", [:append]); Process.sleep(600))
        if state["mode"] == "barrier" do
          File.write!(state["trace"], "barrier\\n", [:append])
          wait = fn wait, remaining ->
            cond do
              File.exists?(state["trace"] <> ".release") -> :ok
              remaining == 0 -> raise "fixture barrier timed out"
              true -> Process.sleep(10); wait.(wait, remaining - 1)
            end
          end
          wait.(wait, 1500)
        end
        fields = ~w(session_id occurrence_id version_id start_byte end_byte quote_sha256 content_sha256)
        lineage = state["proof"] |> Map.take(fields) |> Enum.map(fn {k,v} -> [k,v] end) |> Enum.sort() |> Jason.encode!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
        text = "Synthetic café observation"
        suffix = [["lineage", lineage], ["text", text]] |> Jason.encode!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
        key = "pending." <> suffix
        value = %{"lineage" => lineage, "text" => text, "assigned_category" => "ordinary", "evidence" => %{"sources" => [state["proof"]]}}
        commit = %{"op" => "collection.managed", "recipe_sha256" => state["recipe"], "request" => %{"op" => "commit", "expected_generation" => if(state["mode"] == "conflict", do: 0, else: snapshot["generation"]), "advance_floor" => true,
          "changes" => [%{"key" => key, "expected_revision" => 0, "value" => value}]},
          "proofs" => [%{"handle" => state["page"]["handle"], "quote" => "Synthetic café observation"}]}
        commit = if state["metadata_version"] == 3, do: Map.put(commit, "metadata_version", 3), else: commit
        call(commit, Map.put(state, "step", "done"))
      end
      defp advance(_, outcome, state) do
        if state["mode"] == "read_hold" do
          File.write!(state["trace"], "read-held\\n", [:append])
          wait = fn wait, remaining ->
            cond do
              File.exists?(state["trace"] <> ".release") -> :ok
              remaining == 0 -> raise "fixture read barrier timed out"
              true -> Process.sleep(10); wait.(wait, remaining - 1)
            end
          end
          wait.(wait, 1000)
          File.write!(state["trace"], "read-returned\\n", [:append])
        end
        value = cond do
          state["mode"] in ["paged", "paged_read"] -> %{"items" => List.duplicate(String.duplicate("é", 3000), 4)}
          state["mode"] == "read_hold" -> Map.put(outcome, "worker_payload", "SYNTHETIC_MANAGED_WORKER_TEXT")
          true -> outcome
        end
        {:ok, reply} = Ipse.Extension.ResultPublication.prepare(value)
        {:ok, reply, state}
      end
      defp call(request, state), do: {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => request}, state}
    end
    """

    path = Path.join(root, "fixture.ex")
    File.write!(path, source)

    assert {"", 0} =
             System.cmd(
               System.find_executable("elixirc"),
               [
                 "--erl",
                 "+S 2:2",
                 "-pa",
                 Application.app_dir(:ipse, "ebin"),
                 "-pa",
                 Application.app_dir(:jason, "ebin"),
                 "-o",
                 Path.join(root, "ebin"),
                 path
               ],
               stderr_to_stdout: true
             )

    File.write!(Path.join(root, "LICENSE"), "MIT synthetic fixture")

    files =
      for path <- ["LICENSE", "ebin/Elixir.#{name}.beam"] do
        bytes = File.read!(Path.join(root, path))
        %{"path" => path, "bytes" => byte_size(bytes), "sha256" => JSON.sha256(bytes)}
      end

    manifest = %{
      "format" => 1,
      "id" => "fixture/collection",
      "version" => "0.1.0",
      "sdk" => 2,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => name,
      "license_file" => "LICENSE",
      "files" => files,
      "capabilities" => capabilities,
      "exports" => exports,
      "options_schema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["trace", "recipe"],
        "properties" => %{
          "trace" => %{"type" => "string"},
          "recipe" => %{"type" => "string"},
          "metadata_version" => %{"type" => "integer", "enum" => [3]}
        }
      },
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      }
    }

    File.write!(Path.join(root, "extension.json"), Jason.encode!(manifest))
    File.rm!(path)
    %{artifact: root}
  end

  setup c do
    root = Path.join(System.tmp_dir!(), "ipse-collection-sdk-" <> Ipse.Usage.id())
    home = Path.join(root, "home")
    cwd = Path.join(root, "project")
    File.mkdir_p!(home)
    File.mkdir_p!(cwd)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    trace = Path.join(root, "trace")
    {:ok, artifact} = Artifact.import(c.artifact, Path.join(home, "extensions/artifacts"))

    data = %{
      "extension_trust" => [
        %{
          "artifact" => artifact.digest,
          "capabilities" => artifact.manifest["capabilities"],
          "allow_project" => false,
          "allow_children" => false
        }
      ],
      "extensions" => [
        %{
          "instance" => "capture",
          "artifact" => artifact.digest,
          "enabled" => true,
          "options" =>
            Map.merge(
              %{"trace" => trace, "recipe" => JSON.digest([recipe()])},
              if(c[:metadata_version] == 3, do: %{"metadata_version" => 3}, else: %{})
            ),
          "order" => 0,
          "lifetime" => "session"
        }
      ]
    }

    {:ok, selected} =
      Ipse.Extension.Config.resolve(
        [%{scope: "operator", path: "/fixture/config.json", data: data}],
        []
      )

    {:ok, [entry] = entries} = Registry.prepare(selected, home)

    config = %{
      provider: :demo,
      provider_module: Model,
      model: "synthetic",
      home: home,
      approval: :deny,
      approval_origin: :default_headless,
      headless: true,
      extensions: entries
    }

    config =
      if c[:managed_mcp] do
        server =
          if c[:managed_http] do
            {url, task, listener} = Ipse.Test.ManagedMCPHTTP.start(cwd)

            on_exit(fn ->
              :gen_tcp.close(listener)
              Process.exit(task.pid, :kill)
            end)

            %{
              "id" => "notes",
              "transport" => "http",
              "url" => url,
              "allow_insecure_loopback" => true,
              "tools" => ["write_note"],
              "timeout_ms" => 10_000
            }
          else
            %{
              "id" => "notes",
              "command" => System.find_executable("elixir"),
              "args" => [
                "--erl",
                "+S 2:2",
                "-pa",
                Path.dirname(to_string(:code.which(Jason))),
                Path.expand("../../support/mcp_server.exs", __DIR__),
                cond do
                  c[:managed_gate] -> "managed_gate"
                  c[:managed_held] -> "controlled_disconnect"
                  true -> "normal"
                end
              ],
              "tools" => ["write_note"],
              "env" => %{
                "PATH" => Path.join(to_string(:code.root_dir()), "bin") <> ":/usr/bin:/bin"
              },
              "timeout_ms" => 10_000
            }
          end

        config_path = Path.join(root, "managed-mcp.json")
        File.write!(config_path, Jason.encode!(%{"servers" => [server]}))
        {:ok, servers} = Ipse.MCP.Config.load(config_path)
        Map.put(config, :mcp_servers, servers)
      else
        config
      end

    {config, provider_server} =
      if c[:registered_main] do
        body = fn message ->
          if c[:tls_main],
            do: subscription_body(message),
            else:
              Jason.encode!(%{
                "model" => "synthetic",
                "message" => message,
                "done" => true,
                "done_reason" => "stop",
                "prompt_eval_count" => 1,
                "eval_count" => 1
              }) <> "\n"
        end

        responses =
          [
            body.(%{
              "role" => "assistant",
              "content" => "",
              "tool_calls" =>
                [
                  %{
                    "function" => %{
                      "name" =>
                        if(c[:capture_write] || c[:managed_helper],
                          do: "ext__capture__capture",
                          else: "ext__capture__inspect"
                        ),
                      "arguments" => %{
                        "mode" =>
                          cond do
                            c[:managed_helper] -> "helper"
                            c[:capture_write] -> "capture"
                            c[:postjournal_expiry] -> "read_hold"
                            true -> "read"
                          end
                      }
                    }
                  }
                ] ++
                  if(c[:postjournal_expiry],
                    do: [
                      %{
                        "function" => %{
                          "name" => "read",
                          "arguments" => %{"path" => "never-started"}
                        }
                      }
                    ],
                    else: []
                  )
            }),
            body.(
              if c[:ordinary_effect],
                do: %{
                  "role" => "assistant",
                  "content" => "",
                  "tool_calls" => [
                    %{
                      "function" =>
                        if(c[:managed_mcp],
                          do: %{
                            "name" => "mcp__notes__write_note",
                            "arguments" => %{
                              "path" => "managed-mcp.txt",
                              "content" => "SYNTHETIC_MANAGED_MCP"
                            }
                          },
                          else: %{
                            "name" => "write",
                            "arguments" => %{
                              "path" => "managed-output.txt",
                              "content" => "SYNTHETIC_MANAGED_WRITE"
                            }
                          }
                        )
                    }
                  ]
                },
                else: %{"role" => "assistant", "content" => "Synthetic protected read complete."}
            )
          ] ++
            if(c[:ordinary_effect],
              do: [
                body.(%{"role" => "assistant", "content" => "Synthetic ordinary tool complete."})
              ],
              else: []
            )

        responses =
          if c[:managed_helper] && !c[:helper_stale],
            do: responses ++ [List.last(responses)],
            else: responses

        {base, server} =
          cond do
            c[:tls_main] ->
              tls_provider(responses, c[:tls_gate])

            c[:opaque_refusal] || c[:helper_stale] || c[:response_change] || c[:ordinary_effect] ->
              observed_provider(responses, if(c[:response_change], do: :second_response))

            true ->
              Ipse.Test.ProviderFixture.sequence(responses)
          end

        config =
          config
          |> Map.delete(:provider_module)
          |> Map.merge(%{
            provider: if(c[:tls_main], do: :chatgpt, else: :ollama),
            base_url: base,
            timeout_ms: if(c[:wire_expiry], do: 10_000, else: 3000),
            inference_services: %{"local" => %{"version" => 1, "origins" => [base]}}
          })

        config = if c[:tls_main], do: subscription_credentials(config, root), else: config

        config =
          if c[:managed_helper],
            do:
              Map.put(config, :profiles, %{
                "extract" => %{
                  "provider" => "ollama",
                  "model" => "synthetic",
                  "base_url" => base,
                  "timeout_ms" => 3000
                }
              }),
            else: config

        {config, server}
      else
        {config, nil}
      end

    {:ok, binding} = ProjectIdentity.admit(home, cwd, :folder)
    {:ok, namespace} = SemanticConsent.namespace(binding["project_id"], "capture")
    {:ok, catalog} = Catalog.snapshot(config)
    descriptors = catalog["entries"]

    constraints = constraints()

    selection = %{
      "version" => 2,
      "constraints" => %{JSON.digest([constraints]) => constraints},
      "recipes" => %{JSON.digest([recipe()]) => recipe()},
      "activation" => nil,
      "domain" => "knowledge",
      "namespace" => namespace,
      "scope" => %{"kind" => "project", "worktree_id" => nil},
      "sources" => %{"categories" => ["unattended_input"], "exclusions" => []},
      "storage" => %{"kind" => "local_collection", "collection" => "capture"},
      "retention" => %{"automatic" => 90, "manual" => 3650},
      "routes" => [
        %{
          "operation" => "main",
          "provider" => to_string(config.provider),
          "profile" => nil,
          "model" => "synthetic",
          "endpoint" =>
            if(provider_server,
              do: config.base_url <> if(c[:tls_main], do: "/responses", else: "/api/chat"),
              else: "demo://local"
            ),
          "service_id" => if(provider_server, do: "local", else: "demo"),
          "billing_mode" => Ipse.Usage.billing_mode(config.provider),
          "processing_region" => nil,
          "storage_region" => nil,
          "cache_retention" => nil,
          "account_controls" => nil
        }
      ],
      "effects" =>
        Enum.flat_map(descriptors, fn descriptor ->
          publish =
            if descriptor["id"] == "capture",
              do: [
                %{
                  "operation" => "notes.propose",
                  "class" => "collection.publish",
                  "outer_sha256" => JSON.digest([descriptor]),
                  "inner_op" => "collection.managed",
                  "constraints_sha256" => JSON.digest([constraints]),
                  "recipe_sha256" => JSON.digest([recipe()])
                }
              ],
              else: []

          publish ++
            [
              %{
                "operation" => "notes.recall",
                "class" => "collection.read",
                "outer_sha256" => JSON.digest([descriptor]),
                "inner_op" => "collection.call",
                "managed_read" => [JSON.digest([recipe()])]
              }
            ]
        end),
      "limits" =>
        Map.merge(Consent.zero(), %{
          "operations" => 8,
          "input_bytes" => 100_000,
          "output_bytes" => 100_000
        }),
      "period_ms" => 86_400_000,
      "expires_at_ms" =>
        System.system_time(:millisecond) + if(c[:wire_expiry], do: 6000, else: 600_000),
      "headless" => true
    }

    selection =
      if c[:managed_helper] do
        [main] = selection["routes"]
        helper = main |> Map.put("operation", "model.complete") |> Map.put("profile", "extract")
        Map.put(selection, "routes", [main, helper])
      else
        selection
      end

    selection = Map.update!(selection, "effects", &sort_mappings/1)
    assert {:ok, policy} = SemanticConsent.prepare(binding, entry.identity, selection)
    control = SemanticAdmission.control_root(home)
    {:ok, snapshot} = Consent.snapshot(control, binding["project_id"])

    {:ok, _} =
      Consent.replace(
        control,
        binding["project_id"],
        snapshot["epoch"],
        policy,
        System.system_time(:millisecond)
      )

    {:ok, selection} = Ipse.Config.Semantics.selection(policy)
    config = Map.put(config, :semantic_selections, selection)

    %{
      root: root,
      home: home,
      cwd: cwd,
      trace: trace,
      config: config,
      provider_server: provider_server,
      dir: Path.join(root, "sessions"),
      control: control,
      binding: binding,
      namespace: namespace
    }
  end

  defp constraints do
    object = fn properties ->
      %{
        "type" => "object",
        "properties" => properties,
        "required" => Map.keys(properties),
        "additionalProperties" => false
      }
    end

    proof =
      Map.new(
        ~w(version session_id occurrence_id version_id kind origin coverage path start_byte end_byte quote quote_sha256 content_sha256 receipt_sha256),
        fn k ->
          {k,
           %{
             "type" =>
               cond do
                 k in ~w(version start_byte end_byte) -> "integer"
                 k == "path" -> "null"
                 true -> "string"
               end
           }}
        end
      )

    %{
      "version" => 1,
      "key_prefix" => "pending.",
      "allow_delete" => false,
      "source_categories" => ["unattended_input"],
      "evidence_path" => ["evidence", "sources"],
      "value_schema" =>
        object.(%{
          "lineage" => %{"type" => "string"},
          "text" => %{"type" => "string"},
          "assigned_category" => %{"type" => "string"},
          "evidence" =>
            object.(%{
              "sources" => %{
                "type" => "array",
                "items" => object.(proof),
                "minItems" => 1,
                "maxItems" => 8
              }
            })
        })
    }
  end

  defp recipe do
    %{
      "version" => 1,
      "kind" => "proposal",
      "key_prefix" => "pending.",
      "constraints_sha256" => JSON.digest([constraints()]),
      "evidence_path" => ["evidence", "sources"],
      "lineage_path" => ["lineage"],
      "text_path" => ["text"],
      "category_path" => ["assigned_category"],
      "rules" => [
        %{
          "category" => "ordinary",
          "max_age_ms" => 604_800_000,
          "origins" => ["unattended_input"]
        }
      ],
      "override_prefix" => "override."
    }
  end

  defp start(c, extra \\ %{}, id \\ nil) do
    opts = [
      config: Map.merge(c.config, extra),
      cwd: c.cwd,
      state_dir: c.dir,
      subscriber: self(),
      id: id
    ]

    {:ok, pid} = DynamicSupervisor.start_child(Ipse.Sessions, {Session, opts})
    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    pid
  end

  @tag metadata_version: 3
  test "a newly reviewed legacy reader cannot expose an existing managed namespace", c do
    capture = start(c)
    assert :ok = Session.prompt(capture, "Synthetic café observation")
    assert_receive {:ipse, ^capture, {:done, :ok}}, 15_000
    assert :ok = Session.close_confirmed(capture)
    root = SemanticAdmission.collection_root(c.home)

    assert {:ok, snapshot} =
             Ipse.Extension.Collection.execute(
               root,
               c.namespace,
               %{"op" => "snapshot"},
               Ipse.Usage.id()
             )

    assert {:ok, page} =
             Ipse.Extension.Collection.scan_visible(
               root,
               c.namespace,
               %{
                 "op" => "scan",
                 "generation" => snapshot["generation"],
                 "after" => nil,
                 "limit" => 4
               },
               Ipse.Usage.id()
             )

    [record] = page["records"]
    assert record["value"]["text"] == "Synthetic café observation"
    c = legacy_reader(c)
    reader = start(c)

    assert :ok =
             Session.invoke_export(reader, :command, "ext__capture__inspect", %{
               "mode" => "legacy_get:" <> record["key"]
             })

    assert_receive {:ipse, ^reader, {:done, :ok}}, 10_000
    assert {:ok, events} = Journal.load(c.dir, Session.info(reader).id)
    result = Enum.find(events, &(&1["type"] == "extension_action_result"))

    assert result["outcome"] == %{
             "status" => "failed",
             "value" => %{"code" => "collection_consent_denied"}
           }

    refute Jason.encode!(result) =~ "Synthetic café observation"
    refute Enum.any?(events, &(&1["type"] == "managed_read_observed"))
    assert {:ok, _} = Session.restore_context(events)
  end

  test "a live legacy reader rechecks managed namespace conversion at each actual operation", c do
    c = legacy_reader(c)
    root = SemanticAdmission.collection_root(c.home)

    assert {:ok, _} =
             Ipse.Extension.Collection.execute(
               root,
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" => [
                   %{
                     "key" => "legacy",
                     "expected_revision" => 0,
                     "value" => %{"text" => "ordinary legacy value"}
                   }
                 ]
               },
               Ipse.Usage.id()
             )

    reader = start(c)

    assert :ok =
             Session.invoke_export(reader, :command, "ext__capture__inspect", %{
               "mode" => "legacy_get:legacy"
             })

    assert_receive {:ipse, ^reader, {:done, :ok}}, 10_000
    assert {:ok, events} = Journal.load(c.dir, Session.info(reader).id)
    first = Enum.find(events, &(&1["type"] == "extension_action_result"))

    assert get_in(first, ["outcome", "value", "record", "value", "text"]) ==
             "ordinary legacy value"

    assert {:ok, _} =
             Ipse.Extension.Collection.execute(
               root,
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 1,
                 "advance_floor" => false,
                 "changes" => [
                   %{
                     "key" => "host.validity.format",
                     "expected_revision" => 0,
                     "value" => %{"fixture" => "late protected-format introduction"}
                   }
                 ]
               },
               Ipse.Usage.id()
             )

    assert :ok =
             Session.invoke_export(reader, :command, "ext__capture__inspect", %{
               "mode" => "legacy_get:legacy"
             })

    assert_receive {:ipse, ^reader, {:done, :ok}}, 10_000
    assert {:ok, events} = Journal.load(c.dir, Session.info(reader).id)
    result = events |> Enum.filter(&(&1["type"] == "extension_action_result")) |> List.last()

    assert result["outcome"] == %{
             "status" => "failed",
             "value" => %{"code" => "collection_consent_denied"}
           }

    assert {:ok, _} = Session.restore_context(events)
  end

  defp legacy_reader(c) do
    assert {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    policy = snapshot["policy"]

    selection =
      policy["settings"]
      |> Map.drop(~w(version instance identity_sha256 constraints recipes activation))
      |> Map.merge(Map.take(policy, ~w(limits period_ms expires_at_ms headless)))
      |> Map.update!("effects", fn effects ->
        effects
        |> Enum.filter(&(&1["class"] == "collection.read"))
        |> Enum.map(&Map.take(&1, ~w(operation class outer_sha256 inner_op)))
      end)

    [entry] = c.config.extensions
    assert {:ok, policy} = SemanticConsent.prepare(c.binding, entry.identity, selection)
    assert policy["settings"]["version"] == 1

    assert {:ok, _} =
             Consent.replace(
               c.control,
               c.binding["project_id"],
               snapshot["epoch"],
               policy,
               System.system_time(:millisecond)
             )

    assert {:ok, selected} = Ipse.Config.Semantics.selection(policy)
    put_in(c, [:config, :semantic_selections], selected)
  end

  @tag metadata_version: 3
  test "explicit V3 activates only after actual first publication and resumes without replay",
       c do
    pid = start(c)
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    id = Session.info(pid).id
    {:ok, events} = Journal.load(c.dir, id)

    result =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "collection.managed")
      )

    assert result["outcome"]["status"] == "ok"
    assert result["effect_binding"]["version"] == 3
    assert result["effect_binding"]["metadata_version"] == 3
    assert result["outcome"]["value"]["normalization"]["version"] == 3

    state =
      c.home |> Path.join("project-identities/index.json") |> File.read!() |> Jason.decode!()

    entry = state["domain_keys"][c.binding["project_id"]]["namespaces"][c.namespace]
    assert entry["state"] == "active" and JSON.sha256?(entry["first_root_sha256"])
    assert entry["first_operation_id"] == result["operation_id"]
    assert :ok = Ipse.Extension.Actions.validate_events(events)
    assert :ok = Ipse.Extension.Invocation.validate_events(events)
    assert {:ok, _} = Session.restore_context(events)

    for changed <- [
          Map.delete(result["request"], "metadata_version"),
          Map.put(result["request"], "metadata_version", 2)
        ] do
      refute Ipse.Extension.ManagedCollectionCall.valid_binding?(
               result["effect_binding"],
               changed,
               hd(c.config.extensions).identity
             )
    end

    {:ok, ledger} = Consent.snapshot(c.control, c.binding["project_id"])
    operation = ledger["operations"][result["operation_id"]]
    assert operation["status"] == "settled"
    assert operation["actual"]["input_bytes"] < operation["reserved"]["input_bytes"]
    assert :ok = Session.close_confirmed(pid)
    before = File.read!(c.trace)
    resumed = start(c, %{}, id)
    assert :ok = Session.close_confirmed(resumed)
    assert File.read!(c.trace) == before

    next = start(c)
    assert :ok = Session.prompt(next, "Synthetic café observation")
    assert_receive {:ipse, ^next, {:done, :ok}}, 15_000
    {:ok, later} = Journal.load(c.dir, Session.info(next).id)

    follow_on =
      Enum.find(
        later,
        &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "collection.managed")
      )

    assert follow_on["outcome"]["status"] == "ok"
    assert follow_on["outcome"]["value"]["receipt"]["generation"] == 2

    state =
      c.home |> Path.join("project-identities/index.json") |> File.read!() |> Jason.decode!()

    assert state["domain_keys"][c.binding["project_id"]]["namespaces"][c.namespace] == entry
  end

  @tag metadata_version: 3
  test "saved-consent V3 publication refuses a full pending queue and settles its action", c do
    first = start(c)
    assert :ok = Session.prompt(first, "Synthetic café observation")
    assert_receive {:ipse, ^first, {:done, :ok}}, 15_000
    assert :ok = Session.close_confirmed(first)

    root = SemanticAdmission.collection_root(c.home)

    seed_pending(c, 62)

    below = start(c)
    assert :ok = Session.prompt(below, "Synthetic café observation")
    assert_receive {:ipse, ^below, {:done, :ok}}, 15_000
    assert {:ok, below_events} = Journal.load(c.dir, Session.info(below).id)

    below_result =
      Enum.find(below_events, fn event ->
        event["type"] == "extension_action_result" and
          event["request"]["op"] == "collection.managed"
      end)

    assert below_result["outcome"]["status"] == "ok"
    assert :ok = Session.close_confirmed(below)

    assert {:ok, before} =
             Ipse.Extension.Collection.execute(
               root,
               c.namespace,
               %{"op" => "snapshot"},
               Ipse.Usage.id()
             )

    before_witness = collection_witness(root, c.namespace)

    pid = start(c)
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    id = Session.info(pid).id
    assert {:ok, events} = Journal.load(c.dir, id)
    assert :ok = Ipse.Extension.Actions.validate_events(events)
    assert {:ok, _} = Session.restore_context(events)

    result =
      Enum.find(events, fn event ->
        event["type"] == "extension_action_result" and
          event["request"]["op"] == "collection.managed"
      end)

    assert result["approval"] == "saved_consent"
    assert result["effect_binding"]["metadata_version"] == 3
    assert result["outcome"]["status"] == "failed"
    assert result["outcome"]["value"]["code"] == "collection_unavailable"

    assert {:ok, after_snapshot} =
             Ipse.Extension.Collection.execute(
               root,
               c.namespace,
               %{"op" => "snapshot"},
               Ipse.Usage.id()
             )

    assert after_snapshot == before
    assert collection_witness(root, c.namespace) == before_witness
    assert {:ok, ledger} = Consent.snapshot(c.control, c.binding["project_id"])
    assert ledger["operations"][result["operation_id"]]["status"] == "settled"
    assert :ok = Session.close_confirmed(pid)
    trace = File.read!(c.trace)
    resumed = start(c, %{}, id)
    assert :ok = Session.close_confirmed(resumed)
    assert File.read!(c.trace) == trace
  end

  test "legacy saved-consent publication refuses a full pending queue", c do
    first = start(c)
    assert :ok = Session.prompt(first, "Synthetic café observation")
    assert_receive {:ipse, ^first, {:done, :ok}}, 15_000
    assert :ok = Session.close_confirmed(first)
    seed_pending(c, 63)

    root = SemanticAdmission.collection_root(c.home)
    before = collection_witness(root, c.namespace)
    pid = start(c)
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    id = Session.info(pid).id
    assert {:ok, events} = Journal.load(c.dir, id)
    assert :ok = Ipse.Extension.Actions.validate_events(events)
    assert {:ok, _} = Session.restore_context(events)

    result =
      Enum.find(events, fn event ->
        event["type"] == "extension_action_result" and
          event["request"]["op"] == "collection.managed"
      end)

    assert result["approval"] == "saved_consent"
    assert result["effect_binding"]["version"] == 2

    assert result["outcome"] == %{
             "status" => "failed",
             "value" => %{"code" => "collection_unavailable"}
           }

    assert collection_witness(root, c.namespace) == before
    assert {:ok, ledger} = Consent.snapshot(c.control, c.binding["project_id"])
    assert ledger["operations"][result["operation_id"]]["status"] == "settled"
    assert :ok = Session.close_confirmed(pid)
    trace = File.read!(c.trace)
    resumed = start(c, %{}, id)
    assert :ok = Session.close_confirmed(resumed)
    assert File.read!(c.trace) == trace
  end

  @tag metadata_version: 3
  test "competing V3 saved-consent Sessions cannot both publish at 63 pending records", c do
    competing_pending(c)
  end

  test "competing legacy saved-consent Sessions cannot both publish at 63 pending records", c do
    competing_pending(c)
  end

  defp competing_pending(c) do
    first = start(c)
    assert :ok = Session.prompt(first, "Synthetic café observation")
    assert_receive {:ipse, ^first, {:done, :ok}}, 15_000
    assert :ok = Session.close_confirmed(first)
    seed_pending(c, 62)

    left = start(c, %{fixture_mode: "barrier"})
    right = start(c, %{fixture_mode: "barrier"})
    assert :ok = Session.prompt(left, "Synthetic café observation")
    await_marker_count(c.trace, "barrier\n", 1, 1000)
    assert :ok = Session.prompt(right, "Synthetic café observation")
    await_marker_count(c.trace, "barrier\n", 2, 1000)
    File.write!(c.trace <> ".release", "go")
    assert_receive {:ipse, ^left, {:done, :ok}}, 20_000
    assert_receive {:ipse, ^right, {:done, :ok}}, 20_000

    results =
      for pid <- [left, right] do
        assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
        assert :ok = Ipse.Extension.Actions.validate_events(events)
        assert {:ok, _} = Session.restore_context(events)

        Enum.find(events, fn event ->
          event["type"] == "extension_action_result" and
            event["request"]["op"] == "collection.managed"
        end)
      end

    statuses = Enum.map(results, & &1["outcome"]["status"])
    assert Enum.all?(statuses, &(&1 in ["failed", "ok"]))
    assert Enum.count(statuses, &(&1 == "ok")) <= 1
    assert Enum.all?(results, &(&1["approval"] == "saved_consent"))
    assert {:ok, ledger} = Consent.snapshot(c.control, c.binding["project_id"])

    for result <- results do
      case ledger["operations"][result["operation_id"]] do
        nil -> assert result["outcome"]["status"] == "failed"
        operation -> assert operation["status"] == "settled"
      end
    end

    root = SemanticAdmission.collection_root(c.home)

    assert {:ok, snapshot} =
             Ipse.Extension.Collection.execute(
               root,
               c.namespace,
               %{"op" => "snapshot"},
               Ipse.Usage.id()
             )

    successes = Enum.count(statuses, &(&1 == "ok"))
    assert snapshot["generation"] == 9 + successes

    if successes == 0 do
      retry = start(c)
      assert :ok = Session.prompt(retry, "Synthetic café observation")
      assert_receive {:ipse, ^retry, {:done, :ok}}, 15_000
      assert {:ok, events} = Journal.load(c.dir, Session.info(retry).id)

      result =
        Enum.find(events, fn event ->
          event["type"] == "extension_action_result" and
            event["request"]["op"] == "collection.managed"
        end)

      assert result["outcome"]["status"] == "ok"
    end
  end

  defp seed_pending(c, count) do
    root = SemanticAdmission.collection_root(c.home)

    for batch <- 0..div(count - 1, 8) do
      size = min(8, count - batch * 8)

      changes =
        for offset <- 1..size do
          n = batch * 8 + offset
          key = "pending." <> (n |> Integer.to_string(16) |> String.pad_leading(64, "0"))
          %{"key" => key, "expected_revision" => 0, "value" => %{"synthetic" => n}}
        end

      assert {:ok, _} =
               Ipse.Extension.Collection.execute(
                 root,
                 c.namespace,
                 %{
                   "op" => "commit",
                   "expected_generation" => batch + 1,
                   "advance_floor" => false,
                   "changes" => changes
                 },
                 Ipse.Usage.id()
               )
    end
  end

  defp collection_witness(root, namespace) do
    assert {:ok, view} = Ipse.Extension.Collection.open_view(root, namespace)

    try do
      assert {:ok, result} = Ipse.Extension.Collection.view_read(view, %{"op" => "snapshot"})
      assert result["witness"]["root_state"] == "present"
      result["witness"]
    after
      assert :ok = Ipse.Extension.Collection.close_view(view)
    end
  end

  @tag metadata_version: 3
  test "V3 cannot initialize over an existing unsigned store or silently adopt V2 metadata", c do
    assert {:ok, _} =
             Ipse.Extension.Collection.execute(
               SemanticAdmission.collection_root(c.home),
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => true,
                 "changes" => [
                   %{
                     "key" => "host.validity.anchor.00.0",
                     "expected_revision" => 0,
                     "value" => %{"version" => 2, "kind" => "anchor", "entries" => %{}}
                   }
                 ]
               },
               Ipse.Usage.id()
             )

    pid = start(c)
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    result =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_result" and &1["request"]["op"] == "collection.managed")
      )

    assert result["outcome"]["status"] == "failed"

    state =
      c.home |> Path.join("project-identities/index.json") |> File.read!() |> Jason.decode!()

    assert get_in(state, ["domain_keys", c.binding["project_id"], "namespaces", c.namespace]) ==
             nil

    {:ok, ledger} = Consent.snapshot(c.control, c.binding["project_id"])
    assert ledger["operations"] == %{}
    assert collection_read(c, %{"op" => "snapshot"})["generation"] == 1
  end

  @tag metadata_version: 3
  test "V3 actual Session publications validate a nonzero live split fence", c do
    {:ok, initial} = Consent.snapshot(c.control, c.binding["project_id"])

    policy =
      Map.put(
        initial["policy"],
        "limits",
        Map.merge(Consent.zero(), %{
          "operations" => 40,
          "input_bytes" => 2_000_000,
          "output_bytes" => 2_000_000
        })
      )

    assert {:ok, _} =
             Consent.replace(
               c.control,
               c.binding["project_id"],
               initial["epoch"],
               policy,
               System.system_time(:millisecond)
             )

    assert {:ok, selection} = Ipse.Config.Semantics.selection(policy)
    c = put_in(c, [:config, :semantic_selections], selection)

    nonzero? =
      Enum.reduce(1..27, false, fn generation, seen ->
        pid = start(c)
        assert :ok = Session.prompt(pid, "Synthetic café observation")
        assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
        {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

        result =
          Enum.find(
            events,
            &(&1["type"] == "extension_action_result" and
                &1["request"]["op"] == "collection.managed")
          )

        assert result["outcome"]["status"] == "ok"
        value = result["outcome"]["value"]
        assert value["receipt"]["generation"] == generation

        assert Ipse.Extension.ManagedCollectionCall.valid_outcome?(
                 result["request"],
                 "ok",
                 value,
                 result["operation_id"]
               )

        assert {:ok, _} = Session.restore_context(events)
        assert :ok = Session.close_confirmed(pid)

        seen or
          Enum.any?(value["normalization"]["metadata_changes"], fn extra ->
            String.starts_with?(extra["key"], "host.validity.l.") and
              extra["key"] !=
                Ipse.Extension.Collection.ManagedPages.page_key(
                  :live,
                  Ipse.Extension.Collection.ManagedPages.zero(:live)
                )
          end)
      end)

    assert nonzero?
  end

  test "headless protected capture journals exact outer and inner bindings and settles once", c do
    pid = start(c)
    assert :sys.get_state(pid).config.semantic_admission["status"] == "active"
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    id = Session.info(pid).id
    {:ok, events} = Journal.load(c.dir, id)
    assert :ok = Ipse.Extension.Invocation.validate_events(events)
    assert :ok = Ipse.Extension.Actions.validate_events(events)
    assert {:ok, _} = Session.restore_context(events)

    for mutate <- [
          fn event -> put_in(event, ["semantic_binding", "pin", "epoch"], 999) end,
          fn event ->
            put_in(event, ["semantic_binding", "descriptor_sha256"], JSON.sha256("changed"))
          end,
          fn event -> Map.put(event, "version", 1) end
        ] do
      changed =
        Enum.map(events, fn event ->
          if event["type"] == "extension_invocation_intent", do: mutate.(event), else: event
        end)

      assert {:error, _} = Session.restore_context(changed)
    end

    started = Enum.find(events, &(&1["type"] == "tool_started"))
    assert started["version"] == 2

    changed_start =
      Enum.map(events, fn event ->
        if event == started,
          do: put_in(event, ["semantic_binding", "pin", "epoch"], 999),
          else: event
      end)

    assert {:error, _} = Session.restore_context(changed_start)

    downgraded =
      Enum.map(events, fn event ->
        if Map.has_key?(event, "semantic_binding"),
          do: put_in(event, ["semantic_binding", "class"], "collection.read"),
          else: event
      end)

    assert {:error, _} = Session.restore_context(downgraded)
    [header | tail] = events

    changed_policy =
      put_in(header, ["metadata", "semantic_admission", "policy", "headless"], false)

    assert {:error, _} = Session.restore_context([changed_policy | tail])
    outer = Enum.find(events, &(&1["type"] == "extension_invocation_intent"))
    assert outer["version"] == 3 and outer["approval"] == "saved_consent"

    commit =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "request", "op"]) == "commit")
      )

    assert commit["outcome"]["status"] == "ok"
    assert commit["version"] == 3 and commit["approval"] == "saved_consent"
    assert commit["namespace"] == c.namespace
    assert commit["effect_binding"]["kind"] == "collection.managed"
    assert commit["effect_binding"]["version"] == 2
    assert commit["outcome"]["value"]["normalization"]["version"] == 2
    assert commit["outcome"]["value"]["normalization"]["eligibility"] == "never_current"
    current_anchor = get_in(commit, ["outcome", "value", "normalization", "anchor_key"])

    foreign_shard =
      if String.starts_with?(current_anchor, "host.validity.anchor.00."), do: "ff", else: "00"

    for changed <- [
          Map.put(commit, "version", 2),
          put_in(commit, ["effect_binding", "recipe_sha256"], JSON.sha256("different recipe")),
          put_in(commit, ["effect_binding", "request_sha256"], JSON.sha256("different original")),
          put_in(commit, ["outcome", "value", "normalization", "version"], 1),
          put_in(
            commit,
            ["outcome", "value", "normalization", "anchor_key"],
            "host.validity.anchor." <> foreign_shard <> ".0"
          ),
          put_in(commit, ["outcome", "value", "normalization", "valid_until_ms"], nil),
          put_in(
            commit,
            ["outcome", "value", "receipt", "managed_binding_sha256"],
            JSON.sha256("foreign receipt")
          )
        ] do
      changed = Map.put(changed, "outcome_sha256", JSON.digest([changed["outcome"]]))
      refute Ipse.Extension.Actions.valid_result?(changed)

      assert {:error, _} =
               Session.restore_context(Enum.map(events, &if(&1 == commit, do: changed, else: &1)))
    end

    {:ok, current} =
      Ipse.Extension.Collection.execute(
        SemanticAdmission.collection_root(c.home),
        c.namespace,
        %{"op" => "snapshot"},
        Ipse.Usage.id()
      )

    assert current["generation"] == 1 and current["floor"] == 1

    assert {:ok, visible} =
             Ipse.Extension.Collection.scan_visible(
               SemanticAdmission.collection_root(c.home),
               c.namespace,
               %{"op" => "scan", "generation" => 1, "after" => nil, "limit" => 4},
               Ipse.Usage.id()
             )

    assert length(visible["records"]) == 1
    refute Enum.any?(visible["records"], &String.starts_with?(&1["key"], "host.validity."))

    legacy_outer =
      outer
      |> Map.delete("semantic_binding")
      |> Map.merge(%{"version" => 1, "approval" => "approved"})

    assert :ok = Ipse.Extension.Invocation.validate_intent(legacy_outer)

    assert {:error, _} =
             Ipse.Extension.Actions.intent(
               legacy_outer,
               commit["request"],
               1,
               "saved_consent",
               c.cwd,
               nil,
               nil,
               commit["effect_binding"]
             )

    {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    assert map_size(snapshot["operations"]) == 1
    assert snapshot["operations"][commit["operation_id"]]["status"] == "settled"
    assert :ok = Session.close_confirmed(pid)
    resumed = start(c, %{}, id)
    assert :ok = Session.close_confirmed(resumed)
    assert File.read!(c.trace) |> String.split("entered\n") |> length() == 2
  end

  test "revoked outer permission refuses before worker entry", c do
    pid = start(c)
    {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    {:ok, _} = Consent.revoke(c.control, c.binding["project_id"], snapshot["epoch"])
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
    refute File.exists?(c.trace)
  end

  test "legacy active admission resumes inertly without adopting a new protected outer", c do
    pid = start(c)
    id = Session.info(pid).id
    assert :ok = Session.close_confirmed(pid)
    {:ok, [header | tail]} = Journal.load(c.dir, id)

    legacy =
      header["metadata"]["semantic_admission"] |> Map.delete("policy") |> Map.put("version", 1)

    header = put_in(header, ["metadata", "semantic_admission"], legacy)

    File.write!(
      Path.join(c.dir, id <> ".jsonl"),
      Enum.map_join([header | tail], "\n", &Jason.encode!/1) <> "\n"
    )

    resumed = start(c, %{}, id)
    assert :sys.get_state(resumed).config.semantic_admission["version"] == 1
    assert :ok = Session.prompt(resumed, "Synthetic café observation")
    assert_receive {:ipse, ^resumed, {:done, :ok}}, 10_000
    refute File.exists?(c.trace)
  end

  for metadata_version <- [2, 3] do
    @tag metadata_version: metadata_version
    test "legacy journal origin cannot publish managed metadata V#{metadata_version}", c do
      pid = start(c)
      id = Session.info(pid).id
      assert :ok = Session.close_confirmed(pid)
      assert {:ok, [header | tail]} = Journal.load(c.dir, id)

      # An explicitly constructed legacy fixture has history but no recorded
      # original file binding. Resume must not manufacture that authority.
      metadata = Map.drop(header["metadata"], ~w(source_origin_layout source_origin))
      header = Map.put(header, "metadata", metadata)

      File.write!(
        Path.join(c.dir, id <> ".jsonl"),
        Enum.map_join([header | tail], "\n", &Jason.encode!/1) <> "\n"
      )

      assert {:ok, before} = Consent.snapshot(c.control, c.binding["project_id"])
      resumed = start(c, %{}, id)
      assert :ok = Session.prompt(resumed, "Synthetic café observation")
      assert_receive {:ipse, ^resumed, {:done, :ok}}, 15_000
      assert :ok = Session.close_confirmed(resumed)
      assert {:ok, ^before} = Consent.snapshot(c.control, c.binding["project_id"])
      assert {:ok, [saved_header | events]} = Journal.load(c.dir, id)
      refute Map.has_key?(saved_header["metadata"], "source_origin")

      commits =
        Enum.filter(events, fn event ->
          event["type"] == "extension_action_result" and
            get_in(event, ["request", "request", "op"]) == "commit"
        end)

      assert [_] = commits
      assert Enum.all?(commits, &(get_in(&1, ["outcome", "status"]) == "failed"))
      assert {:ok, _} = Session.restore_context([saved_header | events])
    end
  end

  test "the policy snapshot stays bounded and a low enclosing journal limit refuses before worker entry",
       c do
    pid = start(c)
    id = Session.info(pid).id
    {:ok, [header | _]} = Journal.load(c.dir, id)
    admission = header["metadata"]["semantic_admission"]
    assert admission["version"] == 2
    assert byte_size(Jason.encode!(admission)) <= 65_536
    assert {:error, _} = JSON.decode_unique(Jason.encode!(admission), 12)
    assert SemanticAdmission.valid?(admission, id)
    refute SemanticAdmission.valid?(put_in(admission, ["policy", "settings", "effects"], []), id)
    assert :ok = Session.close_confirmed(pid)
    config = Map.put(c.config, :journal, %{"max_record_bytes" => 4096})

    assert {:error, _} =
             DynamicSupervisor.start_child(
               Ipse.Sessions,
               {Session, config: config, cwd: c.cwd, state_dir: c.dir, subscriber: self()}
             )

    refute File.exists?(c.trace)

    assert Ipse.Extension.validate(%{"payload" => String.duplicate("x", 8193)}) ==
             {:error, :invalid_extension_value}
  end

  test "a read-only export enters headless planning but cannot publish or lend ordinary approval",
       c do
    read = start(c, %{execution_mode: :planning, fixture_export: "inspect", fixture_mode: "read"})
    assert :ok = Session.prompt(read, "Synthetic café observation")
    assert_receive {:ipse, ^read, {:done, :error}}, 10_000
    {:ok, events} = Journal.load(c.dir, Session.info(read).id)
    outer = Enum.find(events, &(&1["type"] == "extension_invocation_intent"))
    assert outer["semantic_binding"]["class"] == "collection.read"
    assert {:ok, _} = Session.restore_context(events)
    state = :sys.get_state(read)

    assert {:ok, dependencies} =
             Ipse.Session.ManagedLineage.dependencies(state.managed_lineage, state.messages)

    assert dependencies != [] and Enum.all?(dependencies, &(&1["version"] == 3))

    producers =
      Enum.map(state.managed_lineage.reference.occurrences, fn {_, occurrence} ->
        occurrence.producer["kind"]
      end)

    assert "collection.result" in producers
    refute "assistant" in producers
    assert {:ok, saved} = Ipse.Session.Saved.restore(events, state.id)

    [release] = Enum.filter(events, &(&1["type"] == "managed_output_release_intent"))
    [admitted] = Enum.filter(events, &(&1["type"] == "managed_output_release_result"))
    [cleanup] = Enum.filter(events, &(&1["type"] == "managed_output_release_cleanup"))
    assert admitted["decision"] == "current" and cleanup["status"] == "confirmed"
    release_at = Enum.find_index(events, &(&1 == release))
    admitted_at = Enum.find_index(events, &(&1 == admitted))
    assert release_at < admitted_at

    prefix = Enum.take_while(events, &(&1 != cleanup))
    assert {:ok, interrupted} = Ipse.Session.Saved.restore(prefix, state.id)

    assert List.last(interrupted.messages)["content"] |> Jason.decode!() |> Map.fetch!("status") ==
             "withheld"

    assert interrupted.managed_lineage.unavailable

    uncertain =
      Enum.map(events, fn event ->
        if event == cleanup, do: Map.put(event, "status", "unknown"), else: event
      end)

    assert {:ok, uncertain} = Ipse.Session.Saved.restore(uncertain, state.id)

    assert List.last(uncertain.messages)["content"] |> Jason.decode!() |> Map.fetch!("status") ==
             "withheld"

    assert uncertain.managed_lineage.unavailable

    for changed <- [
          Enum.reject(events, &(&1 == release)),
          Enum.reject(events, &(&1 == admitted)),
          Enum.reject(events, &(&1 == cleanup)),
          List.insert_at(events, admitted_at, admitted),
          List.replace_at(
            events,
            release_at,
            Map.put(release, "dependencies_sha256", JSON.sha256("foreign union"))
          ),
          List.replace_at(events, admitted_at, Map.put(admitted, "release_id", Ipse.Usage.id()))
        ] do
      case Ipse.Session.Saved.restore(changed, state.id) do
        {:error, _} ->
          :ok

        {:ok, reconstructed} ->
          assert {:error, :managed_lineage_unavailable} =
                   Ipse.Session.ManagedLineage.dependencies(
                     reconstructed.managed_lineage,
                     reconstructed.messages
                   )
      end
    end

    assert {:ok, ^dependencies} =
             Ipse.Session.ManagedLineage.dependencies(saved.managed_lineage, saved.messages)

    legacy =
      events
      |> Enum.reject(&(&1["type"] == "managed_read_observed"))
      |> Enum.map(fn
        %{"type" => "session", "metadata" => metadata} = event ->
          %{event | "metadata" => Map.delete(metadata, "managed_read_layout")}

        event ->
          event
      end)

    assert {:ok, old_saved} = Ipse.Session.Saved.restore(legacy, state.id)
    assert old_saved.messages == saved.messages
    assert old_saved.managed_lineage.unavailable

    assert {:error, :managed_lineage_unavailable} =
             Session.managed_dependencies(
               %{state | managed_lineage: old_saved.managed_lineage},
               "model"
             )

    upgraded =
      Enum.map(events, fn event ->
        if Map.has_key?(event, "semantic_binding"),
          do: put_in(event, ["semantic_binding", "class"], "collection.publish"),
          else: event
      end)

    assert {:error, _} = Session.restore_context(upgraded)
    assert :ok = Session.close_confirmed(read)

    publish = start(c, %{approval: :allow, approval_origin: :yes, fixture_export: "inspect"})
    assert :ok = Session.prompt(publish, "Synthetic café observation")
    assert_receive {:ipse, ^publish, {:done, :error}}, 10_000
    {:ok, events} = Journal.load(c.dir, Session.info(publish).id)

    commit =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "request", "op"]) == "commit")
      )

    assert commit["approval"] == "denied" and commit["outcome"]["status"] == "denied"
    assert {:ok, _} = Session.restore_context(events)
    assert :ok = Session.close_confirmed(publish)

    ordinary = start(c, %{approval: :allow, approval_origin: :yes})

    assert :ok =
             Session.invoke_export(ordinary, :command, "ext__capture__inspect", %{
               "mode" => "ordinary"
             })

    assert_receive {:ipse, ^ordinary, {:done, :ok}}, 10_000
    refute File.exists?(Path.join(c.cwd, "forbidden"))
    {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    assert snapshot["operations"] == %{}
  end

  @tag registered_main: true
  test "a registered native transport carries managed worker lineage into assistant output and replay",
       c do
    read = start(c, %{execution_mode: :planning, fixture_export: "inspect", fixture_mode: "read"})
    assert :ok = Session.prompt(read, "Synthetic registered read")
    assert_receive {:ipse, ^read, {:done, :ok}}, 10_000
    requests = Task.await(c.provider_server, 5000)
    assert length(requests) == 2
    [{_, first}, {_, second}] = requests
    refute Enum.any?(first["messages"], &(&1["role"] == "tool"))
    assert Enum.any?(second["messages"], &(&1["role"] == "tool"))
    state = :sys.get_state(read)

    assert {:ok, dependencies} =
             Ipse.Session.ManagedLineage.dependencies(state.managed_lineage, state.messages)

    assert dependencies != []

    producers =
      Enum.map(state.managed_lineage.reference.occurrences, fn {_, occurrence} ->
        occurrence.producer["kind"]
      end)

    assert "collection.result" in producers and
             Enum.any?(producers, &(&1 in ~w(assistant assistant.ollama_text)))

    assert {:ok, events} = Journal.load(c.dir, state.id)
    assert Enum.count(events, &(&1["type"] == "inference_dispatch_intent")) == 2
    assert {:ok, saved} = Ipse.Session.Saved.restore(events, state.id)

    assert {:ok, ^dependencies} =
             Ipse.Session.ManagedLineage.dependencies(saved.managed_lineage, saved.messages)

    assert :ok = Session.close_confirmed(read)
  end

  @tag registered_main: true, opaque_refusal: true
  test "a stale managed assistant with opaque continuation refuses before a third provider request",
       c do
    read = start(c, %{execution_mode: :planning, fixture_export: "inspect", fixture_mode: "read"})
    assert :ok = Session.prompt(read, "Synthetic opaque managed answer")
    assert_receive {:ipse, ^read, {:done, :ok}}, 10_000
    server = c.provider_server.pid
    assert_receive {:observed_provider_request, ^server, _}, 1000
    assert_receive {:observed_provider_request, ^server, _}, 1000
    state = :sys.get_state(read)

    assert Enum.any?(
             state.messages,
             &(&1["role"] == "assistant" and is_map(&1["provider_data"]) and &1["content"] != "")
           )

    assert {:ok, _} =
             Ipse.Extension.Collection.execute(
               SemanticAdmission.collection_root(c.home),
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" => [
                   %{
                     "key" => "synthetic.changed",
                     "expected_revision" => 0,
                     "value" => %{"text" => "changed"}
                   }
                 ]
               },
               Ipse.Usage.id()
             )

    assert :ok = Session.prompt(read, "Use the previous managed answer")
    assert_receive {:ipse, ^read, {:done, :error}}, 10_000
    refute_receive {:observed_provider_request, ^server, _}, 200
    assert {:ok, events} = Journal.load(c.dir, state.id)
    assert Enum.count(events, &(&1["type"] == "inference_dispatch_intent")) == 2
    assert Enum.count(events, &(&1["type"] == "managed_preflight_intent")) == 2
    assert Enum.count(events, &(&1["type"] == "managed_preflight_result")) == 1
    assert {:ok, _} = Ipse.Session.Saved.restore(events, state.id)
    Task.shutdown(c.provider_server, :brutal_kill)
    assert :ok = Session.close_confirmed(read)
  end

  @tag registered_main: true, capture_write: true
  test "a self-writing capture retains its raw reads and projects only host-bound historical write facts",
       c do
    pid = start(c)
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    [_, {_, request}] = Task.await(c.provider_server, 5000)
    [tool] = Enum.filter(request["messages"], &(&1["role"] == "tool"))
    historical = Jason.decode!(tool["content"])
    assert historical["status"] == "historical_write_outcome"
    assert historical["current_eligibility"] == "not_established"
    refute tool["content"] =~ "Synthetic café observation"
    state = :sys.get_state(pid)

    assert {:ok, []} =
             Ipse.Session.ManagedLineage.dependencies(state.managed_lineage, state.messages)

    assert {:ok, events} = Journal.load(c.dir, state.id)
    result = Enum.find(events, &(&1["type"] == "extension_invocation_result"))

    action =
      Enum.find(
        events,
        &(get_in(&1, ["request", "op"]) == "collection.managed" and
            &1["type"] == "extension_action_result")
      )

    [fact] = state.managed_lineage.write_facts[result["invocation_id"]]
    assert fact["operation_id"] == action["operation_id"]
    assert fact["action_sha256"] == JSON.digest([action])
    assert fact["generation"] == 1
    assert tool["content"] =~ fact["receipt_sha256"]
    assert {:ok, saved} = Ipse.Session.Saved.restore(events, state.id)
    assert saved.messages == state.messages
    assert saved.managed_reads.outputs[result["invocation_id"]] != []
    assert :ok = Session.close_confirmed(pid)
  end

  @tag :managed_output_boundary
  test "a root change during worker processing withholds the actual direct command payload", c do
    pid = start(c)

    assert :ok =
             Session.invoke_export(pid, :command, "ext__capture__inspect", %{
               "mode" => "read_hold"
             })

    await_marker(c.trace, "read-held\n", 300)

    assert {:ok, _} =
             Ipse.Extension.Collection.execute(
               SemanticAdmission.collection_root(c.home),
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" => [
                   %{"key" => "unrelated.changed", "expected_revision" => 0, "value" => %{}}
                 ]
               },
               Ipse.Usage.id()
             )

    File.write!(c.trace <> ".release", "go")
    assert_receive {:ipse, ^pid, {:extension_result, display}}, 10_000
    assert display["value"]["status"] == "withheld"
    refute Jason.encode!(display) =~ "SYNTHETIC_MANAGED_WORKER_TEXT"
    assert_receive {:ipse, ^pid, {:done, :error}}, 5000
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    assert Enum.any?(
             events,
             &(&1["type"] == "managed_output_release_result" and &1["decision"] == "withdrawn")
           )

    assert {:ok, saved} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
    assert saved.extension_state.last_display["value"]["status"] == "withheld"
    assert saved.managed_reads.outputs |> Map.values() |> Enum.any?(&(&1 != []))
  end

  @tag registered_main: true, ordinary_effect: true
  test "current managed native write starts after approval and releases one bound result", c do
    {pid, approval, path} = managed_write_approval(c)
    refute File.exists?(path)
    assert :ok = Session.approve(pid, approval, true)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
    assert File.read!(path) == "SYNTHETIC_MANAGED_WRITE"
    server = c.provider_server.pid
    for _ <- 1..3, do: assert_receive({:observed_provider_request, ^server, _}, 1000)
    refute_receive {:observed_provider_request, ^server, _}, 100
    state = :sys.get_state(pid)
    assert {:ok, events} = Journal.load(c.dir, state.id)
    assert Enum.count(events, &(&1["type"] == "managed_tool_effect_admitted")) == 1
    assert Enum.count(events, &(&1["type"] == "managed_tool_result_observed")) == 1

    assert Enum.count(
             events,
             &(&1["type"] == "managed_tool_result_release" and &1["decision"] == "current")
           ) == 1

    assert {:ok, saved} = Ipse.Session.Saved.restore(events, state.id)
    assert saved.messages == state.messages

    assert {:ok, dependencies} =
             Ipse.Session.ManagedLineage.dependencies(saved.managed_lineage, saved.messages)

    assert dependencies != []
    assert :ok = Session.close_confirmed(pid)
    Task.shutdown(c.provider_server, :brutal_kill)
  end

  for boundary <- [:root_change, :revoke, :expiry, :owner_loss] do
    @tag registered_main: true, ordinary_effect: true, wire_expiry: boundary == :expiry
    test "managed native write waiting on approval refuses #{boundary} without effect", c do
      {pid, approval, path} = managed_write_approval(c)

      case unquote(boundary) do
        :root_change ->
          assert {:ok, _} =
                   Ipse.Extension.Collection.execute(
                     SemanticAdmission.collection_root(c.home),
                     c.namespace,
                     %{
                       "op" => "commit",
                       "expected_generation" => 0,
                       "advance_floor" => false,
                       "changes" => [
                         %{
                           "key" => "changed.before.approval",
                           "expected_revision" => 0,
                           "value" => %{}
                         }
                       ]
                     },
                     Ipse.Usage.id()
                   )

        :revoke ->
          assert {:ok, policy} = Consent.snapshot(c.control, c.binding["project_id"])
          assert {:ok, _} = Consent.revoke(c.control, c.binding["project_id"], policy["epoch"])

        :expiry ->
          assert {:ok, policy} = Consent.snapshot(c.control, c.binding["project_id"])

          Process.sleep(
            max(policy["policy"]["expires_at_ms"] - System.system_time(:millisecond) + 10, 0)
          )

        :owner_loss ->
          ref = Process.monitor(pid)
          Process.exit(pid, :kill)
          assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 3000
      end

      if unquote(boundary) != :owner_loss do
        assert :ok = Session.approve(pid, approval, true)
        assert_receive {:ipse, ^pid, {:done, :error}}, 10_000
        assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
        refute Enum.any?(events, &(&1["type"] == "managed_tool_effect_admitted"))

        assert Enum.any?(
                 events,
                 &(&1["type"] == "managed_tool_result_release" and &1["decision"] == "withdrawn")
               )

        assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
        assert :ok = Session.close_confirmed(pid)
      else
        refute Process.alive?(pid)
      end

      refute File.exists?(path)
      Task.shutdown(c.provider_server, :brutal_kill)
    end
  end

  @tag registered_main: true, ordinary_effect: true, managed_mcp: true
  test "current managed MCP call admits server start and its exact request", c do
    {pid, approval, path} = managed_mcp_approval(c)
    refute File.exists?(path)
    assert :ok = Session.approve(pid, approval, true)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    assert File.read!(path) == "SYNTHETIC_MANAGED_MCP"
    server = c.provider_server.pid
    for _ <- 1..3, do: assert_receive({:observed_provider_request, ^server, _}, 1000)
    refute_receive {:observed_provider_request, ^server, _}, 100
    state = :sys.get_state(pid)
    assert {:ok, events} = Journal.load(c.dir, state.id)

    admissions = Enum.filter(events, &(&1["type"] == "managed_tool_effect_admitted"))
    assert Enum.map(admissions, &get_in(&1, ["binding", "kind"])) == ["mcp.start", "mcp.send"]

    assert Enum.count(
             events,
             &(&1["type"] == "managed_tool_effect_cleanup" and &1["status"] == "confirmed")
           ) == 2

    assert {:ok, saved} = Ipse.Session.Saved.restore(events, state.id)
    assert saved.messages == state.messages
    assert :ok = Session.close_confirmed(pid)
    Task.shutdown(c.provider_server, :brutal_kill)
  end

  for boundary <- [:root_change, :revoke, :expiry, :owner_loss] do
    @tag registered_main: true,
         ordinary_effect: true,
         managed_mcp: true,
         wire_expiry: boundary == :expiry
    test "managed MCP call waiting on approval refuses #{boundary} without effect", c do
      {pid, approval, path} = managed_mcp_approval(c)

      case unquote(boundary) do
        :root_change ->
          assert {:ok, _} =
                   Ipse.Extension.Collection.execute(
                     SemanticAdmission.collection_root(c.home),
                     c.namespace,
                     %{
                       "op" => "commit",
                       "expected_generation" => 0,
                       "advance_floor" => false,
                       "changes" => [
                         %{
                           "key" => "changed.before.mcp",
                           "expected_revision" => 0,
                           "value" => %{}
                         }
                       ]
                     },
                     Ipse.Usage.id()
                   )

        :revoke ->
          assert {:ok, policy} = Consent.snapshot(c.control, c.binding["project_id"])
          assert {:ok, _} = Consent.revoke(c.control, c.binding["project_id"], policy["epoch"])

        :expiry ->
          assert {:ok, policy} = Consent.snapshot(c.control, c.binding["project_id"])

          Process.sleep(
            max(policy["policy"]["expires_at_ms"] - System.system_time(:millisecond) + 10, 0)
          )

        :owner_loss ->
          ref = Process.monitor(pid)
          Process.exit(pid, :kill)
          assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 3000
      end

      if unquote(boundary) != :owner_loss do
        assert :ok = Session.approve(pid, approval, true)
        assert_receive {:ipse, ^pid, {:done, :error}}, 15_000
        assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
        refute Enum.any?(events, &(&1["type"] == "managed_tool_effect_admitted"))
        assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
        assert :ok = Session.close_confirmed(pid)
      end

      refute File.exists?(path)
      refute File.exists?(Path.join(c.cwd, "calls.log"))
      Task.shutdown(c.provider_server, :brutal_kill)
    end
  end

  @tag registered_main: true, ordinary_effect: true, managed_mcp: true, managed_gate: true
  test "managed MCP request refuses revocation after admitted server start", c do
    {pid, approval, path} = managed_mcp_approval(c)
    File.write!(Path.join(c.cwd, "managed-mcp-gate"), "gate")
    assert :ok = Session.approve(pid, approval, true)
    await_marker(Path.join(c.cwd, "managed-mcp-list-ready"), "", 500)
    assert {:ok, policy} = Consent.snapshot(c.control, c.binding["project_id"])
    assert {:ok, _} = Consent.revoke(c.control, c.binding["project_id"], policy["epoch"])
    File.write!(Path.join(c.cwd, "managed-mcp-list-release"), "release")
    assert_receive {:ipse, ^pid, {:done, :error}}, 15_000
    refute File.exists?(path)
    refute File.exists?(Path.join(c.cwd, "calls.log"))
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
    admissions = Enum.filter(events, &(&1["type"] == "managed_tool_effect_admitted"))
    assert Enum.map(admissions, &get_in(&1, ["binding", "kind"])) == ["mcp.start"]
    assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
    assert :ok = Session.close_confirmed(pid)
    Task.shutdown(c.provider_server, :brutal_kill)
  end

  @tag registered_main: true, ordinary_effect: true, managed_mcp: true, managed_http: true
  test "current managed HTTP MCP call admits connection and exact request", c do
    {pid, approval, path} = managed_mcp_approval(c)
    refute File.exists?(path)
    assert :ok = Session.approve(pid, approval, true)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    assert File.read!(path) == "SYNTHETIC_MANAGED_MCP"
    assert File.read!(Path.join(c.cwd, "calls.log")) == "write_note\n"
    state = :sys.get_state(pid)
    assert {:ok, events} = Journal.load(c.dir, state.id)
    admissions = Enum.filter(events, &(&1["type"] == "managed_tool_effect_admitted"))
    assert Enum.map(admissions, &get_in(&1, ["binding", "kind"])) == ["mcp.start", "mcp.send"]

    assert Enum.count(
             events,
             &(&1["type"] == "managed_tool_effect_cleanup" and &1["status"] == "confirmed")
           ) == 2

    assert {:ok, saved} = Ipse.Session.Saved.restore(events, state.id)
    assert saved.messages == state.messages
    assert :ok = Session.close_confirmed(pid)
    Task.shutdown(c.provider_server, :brutal_kill)
  end

  @tag registered_main: true, ordinary_effect: true, managed_mcp: true, managed_http: true
  test "managed HTTP MCP request refuses revocation after admitted connection", c do
    {pid, approval, path} = managed_mcp_approval(c)
    File.write!(Path.join(c.cwd, "managed-mcp-gate"), "gate")
    assert :ok = Session.approve(pid, approval, true)
    await_marker(Path.join(c.cwd, "managed-mcp-list-ready"), "ready", 500)
    assert {:ok, policy} = Consent.snapshot(c.control, c.binding["project_id"])
    assert {:ok, _} = Consent.revoke(c.control, c.binding["project_id"], policy["epoch"])
    File.write!(Path.join(c.cwd, "managed-mcp-list-release"), "release")
    assert_receive {:ipse, ^pid, {:done, :error}}, 15_000
    refute File.exists?(path)
    refute File.exists?(Path.join(c.cwd, "calls.log"))
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
    admissions = Enum.filter(events, &(&1["type"] == "managed_tool_effect_admitted"))
    assert Enum.map(admissions, &get_in(&1, ["binding", "kind"])) == ["mcp.start"]
    assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
    assert :ok = Session.close_confirmed(pid)
    Task.shutdown(c.provider_server, :brutal_kill)
  end

  for boundary <- [:revoke, :expiry] do
    @tag registered_main: true,
         ordinary_effect: true,
         managed_mcp: true,
         managed_http: true,
         managed_http_prestart: true,
         wire_expiry: boundary == :expiry
    test "managed HTTP MCP #{boundary} before approval opens no further connection", c do
      {pid, approval, path} = managed_mcp_approval(c)
      connections = Path.join(c.cwd, "managed-mcp-connections.log")
      before = File.read!(connections)
      assert {:ok, policy} = Consent.snapshot(c.control, c.binding["project_id"])

      case unquote(boundary) do
        :revoke ->
          assert {:ok, _} = Consent.revoke(c.control, c.binding["project_id"], policy["epoch"])

        :expiry ->
          Process.sleep(
            max(policy["policy"]["expires_at_ms"] - System.system_time(:millisecond) + 10, 0)
          )
      end

      assert :ok = Session.approve(pid, approval, true)
      assert_receive {:ipse, ^pid, {:done, :error}}, 15_000
      assert File.read!(connections) == before
      refute File.exists?(path)
      refute File.exists?(Path.join(c.cwd, "calls.log"))
      assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
      refute Enum.any?(events, &(&1["type"] == "managed_tool_effect_admitted"))
      assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
      assert :ok = Session.close_confirmed(pid)
      Task.shutdown(c.provider_server, :brutal_kill)
    end
  end

  @tag registered_main: true,
       ordinary_effect: true,
       managed_mcp: true,
       managed_http: true,
       managed_start_unknown: true
  test "lost HTTP initialization response preserves possible startup as unknown", c do
    {pid, approval, path} = managed_mcp_approval(c)
    id = Session.info(pid).id
    owner_ref = Process.monitor(pid)
    File.write!(Path.join(c.cwd, "managed-mcp-drop-start"), "drop")
    assert :ok = Session.approve(pid, approval, true)
    assert_receive {:ipse, ^pid, {:done, :error}}, 15_000
    assert_receive {:DOWN, ^owner_ref, :process, ^pid, _}, 5000
    assert File.read!(Path.join(c.cwd, "managed-mcp-start-received")) == "received"
    refute File.exists?(path)
    refute File.exists?(Path.join(c.cwd, "calls.log"))
    assert {:ok, events} = Journal.load(c.dir, id)

    assert Enum.any?(
             events,
             &(get_in(&1, ["message", "ipse_tool_outcome", "status"]) == "unknown")
           )

    assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
    server = c.provider_server.pid
    for _ <- 1..2, do: assert_receive({:observed_provider_request, ^server, _}, 1000)
    refute_receive {:observed_provider_request, ^server, _}, 200
    Task.shutdown(c.provider_server, :brutal_kill)
  end

  @tag registered_main: true,
       ordinary_effect: true,
       managed_mcp: true,
       managed_http: true,
       managed_http_owner_loss: true
  test "managed HTTP owner loss closes a held effect socket without replay", c do
    {pid, approval, path} = managed_mcp_approval(c)
    id = Session.info(pid).id
    owner_ref = Process.monitor(pid)
    File.write!(Path.join(c.cwd, "managed-mcp-hold-call"), "hold")
    assert :ok = Session.approve(pid, approval, true)
    await_marker(Path.join(c.cwd, "managed-mcp-call-held"), "held", 500)
    assert File.read!(path) == "SYNTHETIC_MANAGED_MCP"
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^owner_ref, :process, ^pid, :killed}, 5000
    await_marker(Path.join(c.cwd, "managed-mcp-call-closed"), "{:error, :closed}", 500)
    assert File.read!(Path.join(c.cwd, "calls.log")) == "write_note\n"
    assert {:ok, events} = Journal.load(c.dir, id)
    assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
    resumed = start(c, %{approval: :ask, approval_origin: :interactive, headless: false}, id)
    assert Session.info(resumed).phase == :idle
    assert File.read!(Path.join(c.cwd, "calls.log")) == "write_note\n"
    assert :ok = Session.close_confirmed(resumed)
    Task.shutdown(c.provider_server, :brutal_kill)
  end

  @tag registered_main: true,
       ordinary_effect: true,
       managed_mcp: true,
       managed_held: true,
       managed_stdio_owner_loss: true
  test "managed stdio owner loss stops a held server without replay", c do
    {pid, approval, path} = managed_mcp_approval(c)
    id = Session.info(pid).id
    owner_ref = Process.monitor(pid)
    assert :ok = Session.approve(pid, approval, true)
    ready = Path.join(c.cwd, "disconnect-ready")
    await_marker(ready, "", 500)
    assert File.read!(path) == "SYNTHETIC_MANAGED_MCP"
    server_pid = File.read!(ready)
    assert Regex.match?(~r/\A[0-9]+\z/, server_pid)
    transports = :sys.get_state(pid).mcp_resources |> Map.keys()
    assert length(transports) == 1
    refs = Enum.map(transports, &{&1, Process.monitor(&1)})
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^owner_ref, :process, ^pid, :killed}, 5000
    for {transport, ref} <- refs, do: assert_receive({:DOWN, ^ref, :process, ^transport, _}, 5000)
    await_os_process_exit(server_pid, 500)
    assert File.read!(Path.join(c.cwd, "calls.log")) == "write_note\n"
    assert {:ok, events} = Journal.load(c.dir, id)
    assert {:ok, _} = Ipse.Session.Saved.restore(events, id)
    resumed = start(c, %{approval: :ask, approval_origin: :interactive, headless: false}, id)
    assert Session.info(resumed).phase == :idle
    assert File.read!(Path.join(c.cwd, "calls.log")) == "write_note\n"
    assert :ok = Session.close_confirmed(resumed)
    Task.shutdown(c.provider_server, :brutal_kill)
  end

  defp await_os_process_exit(_, 0), do: flunk("synthetic MCP server remained alive")

  defp await_os_process_exit(pid, remaining) do
    case System.cmd("/bin/kill", ["-0", pid], stderr_to_stdout: true) do
      {_, 0} ->
        Process.sleep(10)
        await_os_process_exit(pid, remaining - 1)

      {_, _} ->
        :ok
    end
  end

  @tag registered_main: true,
       ordinary_effect: true,
       managed_mcp: true,
       managed_helper_identity: true
  test "managed stdio uses the build-pinned helper despite an override", c do
    {pid, approval, path} = managed_mcp_approval(c)
    marker = Path.join(c.cwd, "substitute-helper-used")
    substitute = Path.join(c.root, "substitute-helper")
    real_helper = Path.join(to_string(:code.priv_dir(:ipse)), "ipse-runner")

    File.write!(
      substitute,
      "#!/bin/sh\nif [ \"$1\" = \"--admitted-stdio\" ]; then printf invoked > #{inspect(marker)}; fi\nexec #{inspect(real_helper)} \"$@\"\n"
    )

    File.chmod!(substitute, 0o700)
    old = System.get_env("IPSE_RUNNER_PATH")

    try do
      System.put_env("IPSE_RUNNER_PATH", substitute)
      assert :ok = Session.approve(pid, approval, true)
      assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
      assert File.read!(path) == "SYNTHETIC_MANAGED_MCP"
      refute File.exists?(marker)
      assert :ok = Session.close_confirmed(pid)
    after
      if old,
        do: System.put_env("IPSE_RUNNER_PATH", old),
        else: System.delete_env("IPSE_RUNNER_PATH")

      Task.shutdown(c.provider_server, :brutal_kill)
    end
  end

  defp managed_mcp_approval(c) do
    pid = start(c, %{approval: :ask, approval_origin: :interactive, headless: false})
    assert :ok = Session.prompt(pid, "Use the synthetic managed observation in an MCP write.")

    assert_receive {:ipse, ^pid, {:approval, approval, "mcp__notes__write_note", arguments}},
                   10_000

    assert arguments == %{"path" => "managed-mcp.txt", "content" => "SYNTHETIC_MANAGED_MCP"}
    {pid, approval, Path.join(c.cwd, "managed-mcp.txt")}
  end

  defp managed_write_approval(c) do
    pid = start(c, %{approval: :ask, approval_origin: :interactive, headless: false})

    assert :ok =
             Session.prompt(pid, "Use the synthetic managed observation in a workspace write.")

    assert_receive {:ipse, ^pid, {:approval, approval, "write", arguments}}, 10_000
    assert arguments == %{"path" => "managed-output.txt", "content" => "SYNTHETIC_MANAGED_WRITE"}
    {pid, approval, Path.join(c.cwd, "managed-output.txt")}
  end

  @tag registered_main: true, postjournal_expiry: true
  test "expiry during actual tool-message journal IO settles each call once and resumes withheld",
       c do
    pid = start(c, %{execution_mode: :planning})
    owner = self()
    writer = :sys.get_state(pid).journal_writer

    gate = fn
      _, {:in, {_, _, {:append, _, %{"type" => "managed_output_release_result"} = event}}}, _ ->
        event["deadline_ms"]

      deadline,
      {:in,
       {_, _, {:append, _, %{"type" => "message", "message" => %{"role" => "tool"} = message}}}},
      _
      when is_integer(deadline) ->
        send(owner, {:managed_tool_append_waiting, self(), deadline, message["tool_call_id"]})
        receive do: (:release_tool_append -> :released)

      state, _, _ ->
        state
    end

    assert :ok = :sys.install(writer, {gate, nil})
    assert :ok = Session.prompt(pid, "Synthetic post-journal tool expiry")
    await_marker(c.trace, "read-held\n", 300)

    :sys.replace_state(pid, fn state ->
      put_in(
        state.extension_output_clock.started_ms,
        System.monotonic_time(:millisecond) - 118_500
      )
    end)

    File.write!(c.trace <> ".release", "go")
    assert_receive {:managed_tool_append_waiting, ^writer, deadline, first_call}, 5000
    assert System.system_time(:millisecond) < deadline
    Process.sleep(max(deadline - System.system_time(:millisecond) + 10, 0))
    send(writer, :release_tool_append)
    assert_receive {:ipse, ^pid, {:done, :error}}, 5000
    refute_receive {:ipse, ^pid, {:tool_result, "ext__capture__inspect", _}}, 100
    state = :sys.get_state(pid)
    assert {:ok, events} = Journal.load(c.dir, state.id)

    tools =
      Enum.filter(
        events,
        &(&1["type"] == "message" and get_in(&1, ["message", "role"]) == "tool")
      )

    assert length(tools) == 2
    assert Enum.count(tools, &(get_in(&1, ["message", "tool_call_id"]) == first_call)) == 1
    assert get_in(List.last(tools), ["message", "ipse_tool_outcome", "status"]) == "not_started"
    [cleanup] = Enum.filter(events, &(&1["type"] == "managed_output_release_cleanup"))
    assert cleanup["status"] == "unknown"
    assert {:ok, saved} = Ipse.Session.Saved.restore(events, state.id)
    assert saved.messages == state.messages
    [first, _queued] = Enum.filter(saved.messages, &(&1["role"] == "tool"))
    assert Jason.decode!(first["content"])["status"] == "withheld"
    assert :ok = Session.close_confirmed(pid)
    Task.shutdown(c.provider_server, :brutal_kill)
  end

  @tag :managed_output_boundary
  test "revocation during worker processing withholds the actual direct command payload", c do
    pid = start(c)

    assert :ok =
             Session.invoke_export(pid, :command, "ext__capture__inspect", %{
               "mode" => "read_hold"
             })

    await_marker(c.trace, "read-held\n", 300)
    {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    assert {:ok, _} = Consent.revoke(c.control, c.binding["project_id"], snapshot["epoch"])
    File.write!(c.trace <> ".release", "go")
    assert_receive {:ipse, ^pid, {:extension_result, display}}, 10_000
    assert display["value"]["status"] == "withheld"
    refute Jason.encode!(display) =~ "SYNTHETIC_MANAGED_WORKER_TEXT"
    assert_receive {:ipse, ^pid, {:done, :error}}, 5000
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
    assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
  end

  @tag :managed_output_boundary
  test "current managed paged command output becomes readable only after its causal release", c do
    pid = start(c)

    assert :ok =
             Session.invoke_export(pid, :command, "ext__capture__inspect", %{
               "mode" => "paged_read"
             })

    assert_receive {:ipse, ^pid, {:extension_result, display}}, 10_000
    assert display["delivery"]["historical_receipt"] == true
    assert_receive {:ipse, ^pid, {:done, :ok}}, 5000

    assert {:ok, %{value: %{"items" => items}}} =
             Session.materialize_result(pid, display["delivery"])

    assert length(items) == 4
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
    assert {:ok, saved} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
    assert saved.extension_state.last_display == display

    uncertain =
      Enum.map(events, fn event ->
        if event["type"] == "managed_output_release_cleanup",
          do: Map.put(event, "status", "unknown"),
          else: event
      end)

    assert {:ok, uncertain} = Ipse.Session.Saved.restore(uncertain, Session.info(pid).id)
    assert uncertain.extension_state.last_display["value"]["status"] == "withheld"

    refute Ipse.Extension.ResultSource.published?(
             uncertain.result_sources,
             Enum.find(events, &(&1["type"] == "extension_invocation_result"))
           )

    raw = Enum.find(events, &(&1["type"] == "extension_invocation_result"))
    assert Ipse.Extension.ResultSource.published?(saved.result_sources, raw)
    admission_at = Enum.find_index(events, &(&1["type"] == "managed_output_release_result"))
    assert {:ok, private} = Ipse.Extension.ResultSource.restore(Enum.take(events, admission_at))
    refute Ipse.Extension.ResultSource.published?(private, raw)
    assert {:error, _} = Ipse.Extension.ResultSource.readable_source(private, display["delivery"])
    cleanup_at = Enum.find_index(events, &(&1["type"] == "managed_output_release_cleanup"))
    assert {:ok, unconfirmed} = Ipse.Extension.ResultSource.restore(Enum.take(events, cleanup_at))
    refute Ipse.Extension.ResultSource.published?(unconfirmed, raw)

    assert {:error, _} =
             Ipse.Extension.ResultSource.readable_source(unconfirmed, display["delivery"])
  end

  @tag :managed_output_owner_loss
  test "owner loss during managed worker processing cannot release its payload", c do
    pid = start(c)

    assert :ok =
             Session.invoke_export(pid, :command, "ext__capture__inspect", %{
               "mode" => "read_hold"
             })

    await_marker(c.trace, "read-held\n", 300)
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5000
    File.write!(c.trace <> ".release", "go")
    refute_receive {:ipse, ^pid, {:extension_result, _}}, 300
    refute File.read!(c.trace) =~ "read-returned\n"
  end

  defp observed_provider(bodies, gate) do
    owner = self()

    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, {_, port}} = :inet.sockname(listener)

    task =
      Task.async(fn ->
        try do
          for {body, index} <- Enum.with_index(bodies ++ ["unexpected request"]) do
            {:ok, socket} = :gen_tcp.accept(listener, 10_000)

            try do
              {_, payload} = Ipse.Test.ProviderFixture.request(socket, "")
              send(owner, {:observed_provider_request, self(), Jason.decode!(payload)})

              if gate == :second_response and index == 1 do
                send(owner, {:managed_body_sent, self()})
                receive do: (:release_managed_body -> :ok)
              end

              :ok =
                :gen_tcp.send(
                  socket,
                  "HTTP/1.1 200 Fixture\r\ncontent-type: application/x-ndjson\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <>
                    body
                )
            after
              :gen_tcp.close(socket)
            end
          end
        after
          :gen_tcp.close(listener)
        end
      end)

    {"http://127.0.0.1:#{port}", task}
  end

  defp subscription_body(message) do
    output =
      if message["tool_calls"] do
        Enum.map(message["tool_calls"], fn call ->
          %{
            "type" => "function_call",
            "call_id" => "capture",
            "name" => call["function"]["name"],
            "arguments" => Jason.encode!(call["function"]["arguments"])
          }
        end)
      else
        [
          %{
            "type" => "message",
            "role" => "assistant",
            "content" => [%{"type" => "output_text", "text" => message["content"]}]
          }
        ]
      end

    delta =
      if message["content"] != "",
        do: [%{"type" => "response.output_text.delta", "delta" => message["content"]}],
        else: []

    completed = %{
      "type" => "response.completed",
      "response" => %{
        "status" => "completed",
        "model" => "synthetic",
        "output" => output,
        "usage" => %{"input_tokens" => 1, "output_tokens" => 1}
      }
    }

    Enum.map_join(delta ++ [completed], &("data: " <> Jason.encode!(&1) <> "\n\n"))
  end

  defp subscription_credentials(config, root) do
    directory = Path.join(root, "synthetic-auth")

    token = %{
      "access_token" => "subscription-fixture-token",
      "refresh_token" => "subscription-fixture-refresh",
      "id_token" => "subscription-fixture-id",
      "client_id" => "oaiapp_subscription_fixture",
      "ext_agent_host_id" => "urn:uuid:00112233-4455-4677-8899-aabbccddeeff",
      "subject" => "subscription-fixture-account",
      "email" => "subscription@example.test",
      "issuer" => "https://auth.openai.com",
      "token_type" => "Bearer",
      "expires_in" => 3600,
      "expires_at" => System.system_time(:second) + 3600,
      "saved_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "scopes" => ["openid", "offline_access", "chatgpt.tokens.use.direct"]
    }

    assert :ok =
             Ipse.Auth.with_credential_lock(directory, fn ->
               Ipse.Auth.write_credentials(directory, token)
             end)

    Map.put(config, :auth_dir, directory)
  end

  defp tls_provider(bodies, gate) do
    directory = Path.join(System.tmp_dir!(), "ipse-provider-tls-" <> Ipse.Usage.id())
    File.mkdir!(directory)

    certificate =
      :public_key.pkix_test_data(%{
        root: [digest: :sha256, key: {:rsa, 2048, 65537}],
        peer: [
          digest: :sha256,
          key: {:rsa, 2048, 65537},
          extensions: [{:Extension, {2, 5, 29, 17}, false, [{:dNSName, ~c"localhost"}]}]
        ]
      })

    original =
      Enum.map(:public_key.cacerts_get(), fn
        {:cert, der, _} -> der
        der when is_binary(der) -> der
      end)

    pem = fn values ->
      :public_key.pem_encode(Enum.map(values, &{:Certificate, &1, :not_encrypted}))
    end

    saved = Path.join(directory, "original.pem")
    trusted = Path.join(directory, "fixture.pem")
    File.write!(saved, pem.(original))
    File.write!(trusted, pem.(certificate[:cacerts]))
    :ok = :public_key.cacerts_load(trusted)

    on_exit(fn ->
      :ok = :public_key.cacerts_load(saved)
      File.rm_rf!(directory)
    end)

    {:ok, listener} = :ssl.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}] ++ certificate)
    {:ok, {_, port}} = :ssl.sockname(listener)
    owner = self()

    task =
      Task.async(fn ->
        try do
          for {body, index} <- Enum.with_index(bodies) do
            {:ok, socket} = :ssl.transport_accept(listener, 10_000)

            if gate == :connect and index == 1 do
              send(owner, {:managed_tls_connected, self()})
              receive do: (:continue_managed_tls -> :ok)
            end

            {:ok, tls} = :ssl.handshake(socket, 5000)

            try do
              case tls_request(tls, "") do
                {:ok, headers, payload} ->
                  send(owner, {:tls_provider_request, self(), Jason.decode!(payload)})

                  if gate in [:response, :owner_loss] and index == 1 do
                    send(owner, {:managed_tls_body_sent, self()})

                    if gate == :owner_loss do
                      closed = :ssl.recv(tls, 0, 5000)
                      throw({:expected_tls_close, closed})
                    end

                    receive do: (:release_managed_tls_body -> :ok)
                  end

                  :ok =
                    :ssl.send(
                      tls,
                      "HTTP/1.1 200 Fixture\r\ncontent-type: text/event-stream\r\ncontent-length: #{byte_size(body)}\r\nconnection: keep-alive\r\n\r\n" <>
                        body
                    )

                  assert {:error, :closed} = :ssl.recv(tls, 0, 5000)
                  {headers, Jason.decode!(payload)}

                {:error, :closed} ->
                  throw({:expected_tls_close, {:error, :closed}})
              end
            after
              :ssl.close(tls)
            end
          end
        catch
          {:expected_tls_close, result} -> {:closed, result}
        after
          :ssl.close(listener)
        end
      end)

    {"https://localhost:#{port}", task}
  end

  defp tls_request(socket, buffer) when byte_size(buffer) <= 1_048_576 do
    case :binary.split(buffer, "\r\n\r\n") do
      [headers, body] ->
        [_, length] = Regex.run(~r/content-length:\s*(\d+)/i, headers)

        if byte_size(body) >= String.to_integer(length),
          do: {:ok, headers, body},
          else: tls_more(socket, buffer)

      _ ->
        tls_more(socket, buffer)
    end
  end

  defp tls_more(socket, buffer) do
    case :ssl.recv(socket, 0, 5000) do
      {:ok, bytes} -> tls_request(socket, buffer <> bytes)
      error -> error
    end
  end

  @tag registered_main: true, tls_main: true
  test "managed ChatGPT subscription input uses the actual verified TLS adapter and owned publication",
       c do
    pid = start(c, %{execution_mode: :planning})
    assert :ok = Session.prompt(pid, "Synthetic TLS subscription read")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    requests = Task.await(c.provider_server, 5000)
    assert length(requests) == 2

    for {headers, body} <- requests do
      assert headers =~ "POST /responses HTTP/1.1"
      assert String.downcase(headers) =~ "authorization: bearer subscription-fixture-token"
      assert body["model"] == "synthetic"
    end

    {_, second} = List.last(requests)
    assert Enum.any?(second["input"], &(&1["type"] == "function_call_output"))
    state = :sys.get_state(pid)
    assert state.managed_result_seal == nil
    assert {:ok, events} = Journal.load(c.dir, state.id)

    assert Enum.all?(
             Enum.filter(events, &(&1["type"] == "request_admitted")),
             &(&1["provider"] == "chatgpt" and &1["billing_mode"] == "subscription")
           )

    assert {:ok, saved} = Ipse.Session.Saved.restore(events, state.id)
    assert saved.messages == state.messages
    assert :ok = Session.close_confirmed(pid)
  end

  @tag registered_main: true, tls_main: true, tls_gate: :connect
  test "revocation during actual ChatGPT TLS setup refuses before inference headers or body", c do
    pid = start(c, %{execution_mode: :planning})
    assert :ok = Session.prompt(pid, "Synthetic TLS revocation")
    assert_receive {:managed_tls_connected, server}, 10_000
    assert {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    assert {:ok, _} = Consent.revoke(c.control, c.binding["project_id"], snapshot["epoch"])
    send(server, :continue_managed_tls)
    assert_receive {:ipse, ^pid, {:done, :error}}, 10_000
    assert {:closed, {:error, :closed}} = Task.await(c.provider_server, 5000)
    assert_receive {:tls_provider_request, ^server, _}, 1000
    refute_receive {:tls_provider_request, ^server, _}, 100
    refute_receive {:ipse, ^pid, {:text, _}}, 100
    assert :ok = Session.close_confirmed(pid)
  end

  @tag registered_main: true, tls_main: true, tls_gate: :response
  test "actual TLS generation releases policy locks and withholds managed text after root invalidation",
       c do
    pid = start(c, %{execution_mode: :planning})
    assert :ok = Session.prompt(pid, "Synthetic TLS response check")
    assert_receive {:managed_tls_body_sent, server}, 10_000

    assert {:ok, _} =
             Ipse.Extension.Collection.execute(
               SemanticAdmission.collection_root(c.home),
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" => [
                   %{
                     "key" => "synthetic.changed",
                     "expected_revision" => 0,
                     "value" => %{"text" => "changed"}
                   }
                 ]
               },
               Ipse.Usage.id()
             )

    send(server, :release_managed_tls_body)
    assert_receive {:ipse, ^pid, {:done, :error}}, 10_000
    assert length(Task.await(c.provider_server, 5000)) == 2
    refute_receive {:ipse, ^pid, {:text, _}}, 100
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    refute Enum.any?(
             events,
             &(get_in(&1, ["message", "content"]) == "Synthetic protected read complete.")
           )

    assert :sys.get_state(pid).managed_result_seal == nil
    assert :ok = Session.close_confirmed(pid)
  end

  @tag registered_main: true, tls_main: true, tls_gate: :owner_loss
  test "killing the actual Session owner closes its managed TLS transport and releases no output",
       c do
    pid = start(c, %{execution_mode: :planning})
    assert :ok = Session.prompt(pid, "Synthetic TLS owner loss")
    assert_receive {:managed_tls_body_sent, _server}, 10_000
    monitor = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^pid, :killed}, 5000
    assert {:closed, {:error, :closed}} = Task.await(c.provider_server, 5000)
    refute_receive {:ipse, ^pid, {:text, _}}, 100
  end

  @tag registered_main: true, response_change: true
  test "a root change during generation withholds buffered native output without retaining policy locks",
       c do
    pid = start(c, %{execution_mode: :planning, fixture_export: "inspect", fixture_mode: "read"})
    assert :ok = Session.prompt(pid, "Synthetic response barrier")
    assert_receive {:managed_body_sent, server}, 10_000

    assert {:ok, _} =
             Ipse.Extension.Collection.execute(
               SemanticAdmission.collection_root(c.home),
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" => [
                   %{
                     "key" => "synthetic.changed",
                     "expected_revision" => 0,
                     "value" => %{"text" => "changed"}
                   }
                 ]
               },
               Ipse.Usage.id()
             )

    send(server, :release_managed_body)
    assert_receive {:ipse, ^pid, {:done, :error}}, 10_000
    refute_receive {:ipse, ^pid, {:text, _}}, 100
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    refute Enum.any?(
             events,
             &(get_in(&1, ["message", "content"]) == "Synthetic protected read complete.")
           )

    assert Enum.count(events, &(&1["type"] == "inference_dispatch_intent")) == 2
    assert :sys.get_state(pid).managed_result_seal == nil
    Task.shutdown(c.provider_server, :brutal_kill)
    assert :ok = Session.close_confirmed(pid)
  end

  @tag registered_main: true, response_change: true, wire_expiry: true
  test "an actual managed inference response crossing the saved policy deadline releases no output",
       c do
    pid = start(c, %{execution_mode: :planning})
    assert :ok = Session.prompt(pid, "Synthetic native expiry boundary")
    assert_receive {:managed_body_sent, server}, 10_000
    assert {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    deadline = snapshot["policy"]["expires_at_ms"]
    assert System.system_time(:millisecond) < deadline
    Process.sleep(max(deadline - System.system_time(:millisecond) + 20, 0))
    send(server, :release_managed_body)
    assert_receive {:ipse, ^pid, {:done, :error}}, 10_000
    refute_receive {:ipse, ^pid, {:text, _}}, 100
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    refute Enum.any?(
             events,
             &(get_in(&1, ["message", "content"]) == "Synthetic protected read complete.")
           )

    Task.shutdown(c.provider_server, :brutal_kill)
    assert :ok = Session.close_confirmed(pid)
  end

  @tag registered_main: true, wire_budget: true
  test "the managed wire barrier binds the actual output cap narrowed by the existing shared budget",
       c do
    pid =
      start(c, %{
        execution_mode: :planning,
        max_output_tokens: 64,
        budget: %{
          "version" => 1,
          "max_requests" => 3,
          "max_output_tokens" => 128,
          "reserve_output_tokens" => 32
        }
      })

    assert :ok = Session.prompt(pid, "Synthetic managed budget")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    requests = Task.await(c.provider_server, 5000)
    assert length(requests) == 2
    assert Enum.all?(requests, fn {_, body} -> get_in(body, ["options", "num_predict"]) == 32 end)
    assert :ok = Session.close_confirmed(pid)
  end

  @tag registered_main: true, managed_helper: true
  test "a registered helper revalidates inherited worker reads before its actual native request",
       c do
    pid = start(c, %{approval: :allow, approval_origin: :yes})
    assert :ok = Session.prompt(pid, "Synthetic current helper")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    requests = Task.await(c.provider_server, 5000)
    assert length(requests) == 3
    {_, helper} = Enum.at(requests, 1)
    assert length(helper["messages"]) == 2
    assert List.last(helper["messages"])["content"] =~ "generation"
    state = :sys.get_state(pid)
    assert {:ok, events} = Journal.load(c.dir, state.id)

    assert Enum.any?(
             events,
             &(&1["type"] == "managed_preflight_intent" and &1["phase"] == "model.complete")
           )

    assert {:ok, saved} = Ipse.Session.Saved.restore(events, state.id)
    assert saved.messages == state.messages
    assert :ok = Session.close_confirmed(pid)
  end

  @tag registered_main: true, managed_helper: true, helper_stale: true
  test "a stale helper input refuses before helper bytes and the later main request sees only withdrawn output",
       c do
    pid = start(c, %{approval: :allow, approval_origin: :yes})
    owner = self()

    gate = fn
      count, {:in, {:"$gen_call", _, {:managed_preflight_begin, _, "model.complete"}}}, _ ->
        send(owner, {:helper_preflight_blocked, self()})
        receive do: (:release_helper_preflight -> :ok)
        count + 1

      count, _, _ ->
        count
    end

    assert :ok = :sys.install(pid, {gate, 0})
    assert :ok = Session.prompt(pid, "Synthetic stale helper")
    assert_receive {:helper_preflight_blocked, ^pid}, 10_000

    assert {:ok, _} =
             Ipse.Extension.Collection.execute(
               SemanticAdmission.collection_root(c.home),
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" => [
                   %{
                     "key" => "synthetic.changed",
                     "expected_revision" => 0,
                     "value" => %{"text" => "changed"}
                   }
                 ]
               },
               Ipse.Usage.id()
             )

    send(pid, :release_helper_preflight)
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    server = c.provider_server.pid
    assert_receive {:observed_provider_request, ^server, _}, 1000
    assert_receive {:observed_provider_request, ^server, main}, 1000

    assert Enum.any?(
             main["messages"],
             &(&1["role"] == "tool" and String.contains?(&1["content"], "withdrawn"))
           )

    refute_receive {:observed_provider_request, ^server, _}, 100
    assert {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    refute Enum.any?(
             events,
             &(&1["type"] == "inference_dispatch_intent" and &1["phase"] == "model.complete")
           )

    assert {:ok, _} = Ipse.Session.Saved.restore(events, Session.info(pid).id)
    Task.shutdown(c.provider_server, :brutal_kill)
    assert :ok = Session.close_confirmed(pid)
  end

  @tag registered_main: true
  test "a changed managed root withdraws actual worker text before native provider bytes and replays from its prior intent",
       c do
    read = start(c, %{execution_mode: :planning, fixture_export: "inspect", fixture_mode: "read"})
    owner = self()

    gate = fn
      count, {:in, {:"$gen_call", _, {:managed_preflight_begin, _, "model"}}}, _ ->
        if count == 1 do
          send(owner, {:managed_preflight_blocked, self()})
          receive do: (:release_managed_preflight -> :ok)
        end

        count + 1

      count, _, _ ->
        count
    end

    assert :ok = :sys.install(read, {gate, 0})
    assert :ok = Session.prompt(read, "Synthetic changed-root read")
    assert_receive {:managed_preflight_blocked, ^read}, 10_000

    assert {:ok, _} =
             Ipse.Extension.Collection.execute(
               SemanticAdmission.collection_root(c.home),
               c.namespace,
               %{
                 "op" => "commit",
                 "expected_generation" => 0,
                 "advance_floor" => false,
                 "changes" => [
                   %{
                     "key" => "synthetic.changed",
                     "expected_revision" => 0,
                     "value" => %{"text" => "changed"}
                   }
                 ]
               },
               Ipse.Usage.id()
             )

    send(read, :release_managed_preflight)
    assert_receive {:ipse, ^read, {:done, :ok}}, 10_000
    [_, {_, request}] = Task.await(c.provider_server, 5000)
    [tool] = Enum.filter(request["messages"], &(&1["role"] == "tool"))
    assert tool["content"] =~ "Managed historical content withdrawn"
    refute tool["content"] =~ "generation"
    state = :sys.get_state(read)

    assert {:ok, []} =
             Ipse.Session.ManagedLineage.dependencies(state.managed_lineage, state.messages)

    assert {:ok, events} = Journal.load(c.dir, state.id)
    intent = Enum.find(events, &(&1["type"] == "managed_preflight_intent"))
    result = Enum.find(events, &(&1["type"] == "managed_preflight_result"))
    assert result["intent_id"] == intent["intent_id"]
    original = Enum.find(events, &(&1["type"] == "extension_invocation_result"))
    refute Ipse.Extension.Invocation.tool_message(original)["content"] =~ "withdrawn"
    assert {:ok, saved} = Ipse.Session.Saved.restore(events, state.id)
    assert saved.messages == state.messages

    tampered =
      Enum.map(events, fn event ->
        if event["type"] == "managed_preflight_result",
          do:
            put_in(event, ["projection", "binding", "tools_sha256"], JSON.sha256("foreign tools")),
          else: event
      end)

    assert {:error, _} = Ipse.Session.Saved.restore(tampered, state.id)
    assert :ok = Session.close_confirmed(read)
  end

  test "a saved grant never admits an ordinary workspace write", c do
    pid = start(c, %{fixture_mode: "ordinary"})
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
    refute File.exists?(Path.join(c.cwd, "forbidden"))
    {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
    denied = Enum.find(events, &(&1["type"] == "extension_action_result"))
    assert denied["approval"] == "denied" and denied["outcome"]["status"] == "denied"
  end

  test "SDK2 protected output retains version4 and the same original binding", c do
    pid = start(c, %{fixture_mode: "paged"})
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
    {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
    intent = Enum.find(events, &(&1["type"] == "extension_invocation_intent"))
    result = Enum.find(events, &(&1["type"] == "extension_invocation_result"))
    assert result["version"] == 4
    assert result["semantic_binding"] == intent["semantic_binding"]
    assert :ok = Ipse.Extension.Invocation.validate_events(events)
    assert {:ok, _} = Session.restore_context(events)
  end

  test "a selected operator command uses its own protected outer receipt", c do
    pid = start(c)

    assert :ok =
             Session.invoke_export(pid, :command, "ext__capture__capture", %{"mode" => "ordinary"})

    assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
    {:ok, events} = Journal.load(c.dir, Session.info(pid).id)
    intent = Enum.find(events, &(&1["type"] == "extension_invocation_intent"))
    assert intent["version"] == 3 and intent["approval"] == "saved_consent"
    assert intent["descriptor"]["stage"] == "invoke.command"
    assert intent["parent_call_id"] == nil
    assert :ok = Ipse.Extension.Invocation.validate_events(events)
    assert {:ok, _} = Session.restore_context(events)
    refute File.exists?(Path.join(c.cwd, "forbidden"))
  end

  test "revocation after worker entry is rechecked before collection reservation", c do
    pid = start(c, %{fixture_mode: "hold"})
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    await_marker(c.trace, "held\n", 300)
    {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    {:ok, _} = Consent.revoke(c.control, c.binding["project_id"], snapshot["epoch"])
    assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
    {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    commit =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "request", "op"]) == "commit")
      )

    assert commit["outcome"] == %{
             "status" => "failed",
             "value" => %{"code" => "collection_consent_denied"}
           }

    {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    assert snapshot["operations"] == %{}
  end

  test "interrupted protected outer remains unknown and never replays on resume", c do
    pid = start(c, %{fixture_mode: "hold"})
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    await_marker(c.trace, "held\n", 300)
    id = Session.info(pid).id
    assert :ok = Session.cancel(pid)
    assert :ok = Session.close_confirmed(pid)
    {:ok, events} = Journal.load(c.dir, id)

    assert Enum.any?(
             events,
             &(&1["type"] == "extension_invocation_intent" and &1["version"] == 3)
           )

    refute Enum.any?(events, &(&1["type"] == "extension_invocation_result"))
    assert {:ok, _} = Session.restore_context(events)
    before = File.read!(c.trace)
    resumed = start(c, %{}, id)
    assert File.read!(c.trace) == before
    assert :ok = Session.close_confirmed(resumed)
  end

  test "ambiguous reviewed publication mappings refuse rather than choosing a stronger operation",
       c do
    {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    policy = snapshot["policy"]
    {:ok, _, descriptor} = Catalog.lookup(c.config, "invoke.tool", "ext__capture__capture")

    mapping =
      Enum.find(
        policy["settings"]["effects"],
        &(&1["class"] == "collection.publish" and &1["outer_sha256"] == JSON.digest([descriptor]))
      )

    effects =
      sort_mappings(
        policy["settings"]["effects"] ++ [Map.put(mapping, "operation", "notes.ambiguous")]
      )

    policy =
      policy
      |> put_in(["settings", "effects"], effects)
      |> Map.put(
        "operations",
        effects |> Enum.map(& &1["operation"]) |> Enum.uniq() |> Enum.sort()
      )

    assert SemanticConsent.policy?(policy)

    {:ok, _} =
      Consent.replace(
        c.control,
        c.binding["project_id"],
        snapshot["epoch"],
        policy,
        System.system_time(:millisecond)
      )

    {:ok, selected} = Ipse.Config.Semantics.selection(policy)
    pid = start(c, %{semantic_selections: selected})
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
    {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    commit =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "request", "op"]) == "commit")
      )

    assert commit["outcome"] == %{
             "status" => "failed",
             "value" => %{"code" => "collection_consent_denied"}
           }

    {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    assert snapshot["operations"] == %{}
  end

  test "a known conflict is recorded and conservatively settled once without retry", c do
    first = start(c)
    assert :ok = Session.prompt(first, "Synthetic café observation")
    assert_receive {:ipse, ^first, {:done, :ok}}, 10_000
    assert :ok = Session.close_confirmed(first)
    second = start(c, %{fixture_mode: "conflict"})
    assert :ok = Session.prompt(second, "Synthetic café observation")
    assert_receive {:ipse, ^second, {:done, :ok}}, 10_000
    {:ok, events} = Journal.load(c.dir, Session.info(second).id)

    commits =
      Enum.filter(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "request", "op"]) == "commit")
      )

    assert [commit] = commits
    assert commit["outcome"]["status"] == "conflict"
    {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    assert snapshot["operations"][commit["operation_id"]]["status"] == "settled"

    assert snapshot["operations"][commit["operation_id"]]["actual"] ==
             Ipse.Extension.ManagedCollectionCall.reservation(commit["request"])

    assert map_size(snapshot["operations"]) == 2
  end

  test "successive protected saves settle measured input and release only verified unused input",
       c do
    {:ok, initial} = Consent.snapshot(c.control, c.binding["project_id"])
    policy = put_in(initial["policy"], ["limits", "input_bytes"], 30_000)

    assert {:ok, _} =
             Consent.replace(
               c.control,
               c.binding["project_id"],
               initial["epoch"],
               policy,
               System.system_time(:millisecond)
             )

    assert {:ok, selection} = Ipse.Config.Semantics.selection(policy)
    c = put_in(c, [:config, :semantic_selections], selection)

    saves =
      for _ <- 1..2 do
        before = collection_read(c, %{"op" => "snapshot"})

        previous =
          collection_read(c, %{
            "op" => "scan",
            "generation" => before["generation"],
            "after" => nil,
            "limit" => 32
          })

        revisions = Map.new(previous["records"], &{&1["key"], &1["revision"]})
        pid = start(c)
        assert :ok = Session.prompt(pid, "Synthetic café observation")
        assert_receive {:ipse, ^pid, {:done, :ok}}, 15_000
        {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

        [commit] =
          Enum.filter(
            events,
            &(&1["type"] == "extension_action_result" and
                get_in(&1, ["request", "op"]) == "collection.managed")
          )

        assert commit["outcome"]["status"] == "ok"
        value = commit["outcome"]["value"]
        normalization = value["normalization"]

        extra =
          for name <- ~w(anchor_key live_key) do
            key = normalization[name]
            stored = collection_read(c, %{"op" => "get", "key" => key})["record"]

            %{
              "key" => key,
              "expected_revision" => Map.get(revisions, key, 0),
              "value" => stored["value"]
            }
          end

        normalized = Map.update!(commit["request"]["request"], "changes", &(&1 ++ extra))
        assert value["receipt"]["request_sha256"] == JSON.digest([normalized])

        expected =
          byte_size(Jason.encode!(commit["request"])) + byte_size(Jason.encode!(normalized)) -
            byte_size(Jason.encode!(commit["request"]["request"])) +
            byte_size(Jason.encode!(normalization))

        {:ok, control} = Consent.snapshot(c.control, c.binding["project_id"])
        settled = control["operations"][commit["operation_id"]]
        assert settled["status"] == "settled"
        assert settled["actual"]["input_bytes"] == expected
        reserved = Ipse.Extension.ManagedCollectionCall.reservation(commit["request"])
        assert expected < reserved["input_bytes"]
        assert Map.delete(settled["actual"], "input_bytes") == Map.delete(reserved, "input_bytes")
        assert :ok = Session.close_confirmed(pid)
        {expected, reserved["input_bytes"]}
      end

    [{first_actual, first_reserved}, {_, second_reserved}] = saves
    assert first_actual + second_reserved <= 30_000
    assert first_reserved + second_reserved > 30_000
  end

  test "native loss after normalization does not refund or publish a successful managed result",
       c do
    owner = self()
    handler = {__MODULE__, make_ref()}

    :ok =
      :telemetry.attach(
        handler,
        [:ipse, :extension, :collection, :staged],
        &__MODULE__.fence_native_publication/4,
        owner
      )

    on_exit(fn -> :telemetry.detach(handler) end)
    pid = start(c)
    id = Session.info(pid).id
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    assert_receive :native_publication_fenced, 10_000
    assert_receive {:ipse, ^pid, {:done, :error}}, 15_000
    {:ok, events} = Journal.load(c.dir, id)

    [commit] =
      Enum.filter(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "op"]) == "collection.managed")
      )

    assert commit["outcome"]["status"] == "unknown"
    {:ok, control} = Consent.snapshot(c.control, c.binding["project_id"])
    operation = control["operations"][commit["operation_id"]]
    assert operation["status"] in ~w(publishing unknown)
    assert operation["actual"] == nil

    assert operation["reserved"] ==
             Ipse.Extension.ManagedCollectionCall.reservation(commit["request"])

    assert collection_read(c, %{"op" => "snapshot"})["generation"] == 0
  end

  def fence_native_publication(_, _, _, owner) do
    case Process.get({Ipse.Extension.Collection, :lock_held}) do
      %{port: port} ->
        send(owner, :native_publication_fenced)
        Port.close(port)

      _ ->
        :ok
    end
  end

  @tag metadata_version: 3
  test "V3 loss of the native owner during first-publication postproof keeps the outcome unknown",
       c do
    owner = self()
    handler = {__MODULE__, make_ref()}
    stage = :atomics.new(1, [])

    :ok =
      :telemetry.attach_many(
        handler,
        [
          [:ipse, :extension, :collection, :staged],
          [:ipse, :extension, :collection, :view_read]
        ],
        &__MODULE__.fence_first_postproof/4,
        {owner, stage}
      )

    try do
      pid = start(c)
      id = Session.info(pid).id
      assert :ok = Session.prompt(pid, "Synthetic café observation")
      assert_receive {:first_postproof_fenced, true}, 15_000
      assert_receive {:ipse, ^pid, {:done, :error}}, 15_000
      {:ok, events} = Journal.load(c.dir, id)

      [event] =
        Enum.filter(
          events,
          &(&1["type"] == "extension_action_result" and
              get_in(&1, ["request", "op"]) == "collection.managed")
        )

      assert event["outcome"]["status"] == "unknown"
      {:ok, control} = Consent.snapshot(c.control, c.binding["project_id"])
      operation = control["operations"][event["operation_id"]]
      assert operation["status"] in ~w(publishing unknown)
      assert operation["actual"] == nil and operation["receipt"] == nil

      assert operation["reserved"] ==
               Ipse.Extension.ManagedCollectionCall.reservation(event["request"])

      assert collection_read(c, %{"op" => "snapshot"})["generation"] == 1

      state =
        c.home |> Path.join("project-identities/index.json") |> File.read!() |> Jason.decode!()

      assert state["domain_keys"][c.binding["project_id"]]["namespaces"][c.namespace]["state"] ==
               "prepared"

      before = File.read!(c.trace)
      assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(pid)
      refute Process.alive?(pid)
      resumed = start(c, %{}, id)
      assert :ok = Session.close_confirmed(resumed)
      assert File.read!(c.trace) == before
      {:ok, after_control} = Consent.snapshot(c.control, c.binding["project_id"])
      assert after_control["operations"][event["operation_id"]] == operation
    after
      :telemetry.detach(handler)
    end
  end

  def fence_first_postproof(
        [:ipse, :extension, :collection, :staged],
        _,
        _,
        {_, stage}
      ) do
    :atomics.put(stage, 1, 1)
  end

  def fence_first_postproof(
        [:ipse, :extension, :collection, :view_read],
        %{records: records},
        _,
        {owner, stage}
      )
      when records >= 3 do
    if :atomics.compare_exchange(stage, 1, 1, 2) == :ok do
      case Process.get({Ipse.Extension.Collection, :lock_held}) do
        %{port: port} -> send(owner, {:first_postproof_fenced, Port.close(port)})
        _ -> send(owner, {:first_postproof_fenced, false})
      end
    end
  end

  def fence_first_postproof(_, _, _, _), do: :ok

  for version <- [2, 3] do
    @tag metadata_version: version
    test "V#{version} outer Identity loss after checked deferred publication retains full liability across inert resume",
         c do
      owner = self()

      tracer =
        spawn_link(fn ->
          Process.flag(:priority, :high)
          send(owner, :settlement_tracer_ready)
          trace_identity_completion(owner, %{})
        end)

      assert_receive :settlement_tracer_ready

      assert :erlang.trace_pattern(
               {Consent, :publish_deferred, 5},
               [{:_, [], [{:return_trace}]}],
               [
                 :local
               ]
             ) == 1

      :erlang.trace(:all, true, [:call, {:tracer, tracer}])
      handler = {__MODULE__, make_ref()}

      :ok =
        :telemetry.attach(
          handler,
          [:ipse, :extension, :collection, :staged],
          &__MODULE__.observe_settlement_port/4,
          tracer
        )

      try do
        pid = start(c)
        id = Session.info(pid).id
        assert :ok = Session.prompt(pid, "Synthetic café observation")
        assert_receive {:identity_completion_fenced, true, packet}, 15_000
        assert packet["version"] === 1
        assert_receive {:ipse, ^pid, {:done, :error}}, 15_000
        {:ok, events} = Journal.load(c.dir, id)

        [event] =
          Enum.filter(
            events,
            &(&1["type"] == "extension_action_result" and
                get_in(&1, ["request", "op"]) == "collection.managed")
          )

        assert event["outcome"]["status"] == "unknown"
        {:ok, control} = Consent.snapshot(c.control, c.binding["project_id"])
        operation = control["operations"][event["operation_id"]]
        assert operation["status"] in ~w(publishing unknown)
        assert operation["actual"] == nil and operation["receipt"] == nil

        assert operation["reserved"] ==
                 Ipse.Extension.ManagedCollectionCall.reservation(event["request"])

        assert packet["actual"]["input_bytes"] < operation["reserved"]["input_bytes"]
        assert collection_read(c, %{"op" => "snapshot"})["generation"] == 1

        if c[:metadata_version] == 3 do
          state =
            c.home
            |> Path.join("project-identities/index.json")
            |> File.read!()
            |> Jason.decode!()

          assert state["domain_keys"][c.binding["project_id"]]["namespaces"][c.namespace]["state"] ==
                   "prepared"
        end

        before = File.read!(c.trace)
        assert {:error, :cleanup_unconfirmed} = Session.close_confirmed(pid)
        refute Process.alive?(pid)
        resumed = start(c, %{}, id)
        assert :ok = Session.close_confirmed(resumed)
        assert File.read!(c.trace) == before
        {:ok, after_control} = Consent.snapshot(c.control, c.binding["project_id"])
        assert after_control["operations"][event["operation_id"]] == operation
      after
        :telemetry.detach(handler)
        :erlang.trace(:all, false, [:call])
        :erlang.trace_pattern({Consent, :publish_deferred, 5}, false, [:local])
        if Process.alive?(tracer), do: send(tracer, :stop)
      end
    end
  end

  def observe_settlement_port(_, _, _, tracer) do
    case Process.get({Ipse.Extension.Collection, :lock_held}) do
      %{port: port} -> send(tracer, {:settlement_native_port, self(), port})
      _ -> :ok
    end
  end

  defp trace_identity_completion(owner, ports) do
    receive do
      {:settlement_native_port, pid, port} ->
        trace_identity_completion(owner, Map.put(ports, pid, port))

      {:trace, pid, :return_from, {Consent, :publish_deferred, 5},
       {:ok, %{"version" => 1} = packet}} ->
        case Map.fetch(ports, pid) do
          {:ok, port} -> send(owner, {:identity_completion_fenced, Port.close(port), packet})
          :error -> send(owner, :missing_settlement_native_port)
        end

      :stop ->
        :ok

      _ ->
        trace_identity_completion(owner, ports)
    after
      30_000 -> exit(:settlement_trace_timeout)
    end
  end

  defp collection_read(c, request) do
    assert {:ok, value} =
             Ipse.Extension.Collection.execute(
               SemanticAdmission.collection_root(c.home),
               c.namespace,
               request,
               Ipse.Usage.id()
             )

    value
  end

  test "owner loss during protected publication retains liability and cannot publish after cleanup",
       c do
    pid = start(c, %{fixture_mode: "hold"})
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    await_marker(c.trace, "held\n", 300)
    owner = self()

    assert :ok = :sys.install(pid, {publication_gate(owner), 0})
    assert_receive {:publication_query_blocked, _, _}, 5000
    control_file = Path.join([c.control, c.binding["project_id"], "control.json"])
    publishing = await_publication(control_file, 300)
    assert publishing["status"] == "publishing"
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 2000
    {:ok, snapshot} = Consent.snapshot(c.control, c.binding["project_id"])
    assert snapshot["operations"][publishing["id"]]["status"] in ~w(admitted publishing unknown)
    assert snapshot["operations"][publishing["id"]]["actual"] == nil

    assert {:ok, stored} =
             Ipse.Extension.Collection.execute(
               SemanticAdmission.collection_root(c.home),
               c.namespace,
               %{"op" => "snapshot"},
               Ipse.Usage.id()
             )

    assert stored["generation"] == 0
  end

  test "an unrelated caller cannot use the actual current collection action or stale job reference",
       c do
    pid = start(c, %{fixture_mode: "hold"})
    assert :ok = Session.prompt(pid, "Synthetic café observation")
    await_marker(c.trace, "held\n", 300)
    assert :ok = :sys.install(pid, {publication_gate(self()), 0})
    assert_receive {:publication_query_blocked, ref, intent}, 5000

    foreign =
      Task.async(fn ->
        GenServer.call(pid, {:extension_collection_sources, ref, intent}, 5000)
      end)

    stale =
      Task.async(fn ->
        GenServer.call(pid, {:extension_collection_sources, make_ref(), intent}, 5000)
      end)

    changed =
      Task.async(fn ->
        GenServer.call(
          pid,
          {:extension_collection_sources, ref, Map.put(intent, "operation_id", Ipse.Usage.id())},
          5000
        )
      end)

    await_queued(pid, [foreign.pid, stale.pid, changed.pid], 300)
    send(pid, :release_publication)

    for task <- [foreign, stale, changed],
        do: assert({:error, :collection_source_refused} = Task.await(task, 5000))

    assert_receive {:ipse, ^pid, {:done, :ok}}, 10_000
    {:ok, events} = Journal.load(c.dir, Session.info(pid).id)

    result =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_result" and &1["operation_id"] == intent["operation_id"])
      )

    assert result["outcome"]["status"] == "ok"
  end

  defp publication_gate(owner) do
    fn
      count, {:in, {:"$gen_call", _, {:extension_collection_sources, ref, intent}}}, _ ->
        if get_in(intent, ["request", "request", "op"]) == "commit" do
          if count == 1 do
            send(owner, {:publication_query_blocked, ref, intent})
            receive do: (:release_publication -> :ok)
          end

          count + 1
        else
          count
        end

      count, _, _ ->
        count
    end
  end

  defp await_queued(_, _, 0),
    do: flunk("foreign proof queries did not reach the actual Session queue")

  defp await_queued(pid, callers, remaining) do
    {:messages, messages} = Process.info(pid, :messages)

    queued =
      Enum.flat_map(messages, fn
        {:"$gen_call", {caller, _}, {:extension_collection_sources, _, _}} -> [caller]
        _ -> []
      end)

    if Enum.all?(callers, &(&1 in queued)),
      do: :ok,
      else:
        (
          Process.sleep(10)
          await_queued(pid, callers, remaining - 1)
        )
  end

  defp sort_mappings(effects),
    do: Enum.sort_by(effects, &{&1["operation"], &1["class"], &1["outer_sha256"], &1["inner_op"]})

  defp await_publication(path, 0) do
    value =
      case File.read(path) do
        {:ok, bytes} -> Jason.decode!(bytes)
        error -> error
      end

    flunk("protected publishing receipt was not reached: #{inspect(value, limit: 20)}")
  end

  defp await_publication(path, remaining) do
    receipt =
      with {:ok, bytes} <- File.read(path),
           {:ok, value} <- Jason.decode(bytes),
           do:
             Enum.find_value(value["operations"], fn {_, receipt} ->
               if receipt["status"] == "publishing", do: receipt
             end)

    if is_map(receipt),
      do: receipt,
      else:
        (
          Process.sleep(10)
          await_publication(path, remaining - 1)
        )
  end

  defp await_marker_count(_, _, _, 0), do: flunk("synthetic worker barriers were not reached")

  defp await_marker_count(path, marker, count, remaining) do
    if File.exists?(path) and length(String.split(File.read!(path), marker)) - 1 >= count do
      :ok
    else
      Process.sleep(10)
      await_marker_count(path, marker, count, remaining - 1)
    end
  end

  defp await_marker(_, _, 0), do: flunk("synthetic worker marker was not reached")

  defp await_marker(path, marker, remaining) do
    if File.exists?(path) and String.contains?(File.read!(path), marker),
      do: :ok,
      else:
        (
          Process.sleep(10)
          await_marker(path, marker, remaining - 1)
        )
  end
end
