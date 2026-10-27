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
      ~w(invoke.tool invoke.command invoke.result.pages host.actions host.sources host.collection.read host.collection.write host.collection.managed host.tools)

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
        state["mode"] == "ordinary" ->
          call(%{"op" => "tool.call", "name" => "write", "timeout_ms" => 1000, "arguments" => %{"path" => "forbidden", "content" => "denied"}}, Map.put(state, "step", "done"))
        state["mode"] == "read" ->
          call(%{"op" => "collection.call", "request" => %{"op" => "snapshot"}}, Map.put(state, "step", "done"))
        true ->
          call(%{"op" => "source.list", "limit" => 32}, Map.put(state, "step", "list"))
        end
      end
      def handle("host.actions", %{"outcome" => outcome}, state) do
        File.write!(state["trace"], Jason.encode!(outcome) <> "\\n", [:append])
        advance(state["step"], outcome, state)
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
        fields = ~w(session_id occurrence_id version_id start_byte end_byte quote_sha256 content_sha256)
        lineage = state["proof"] |> Map.take(fields) |> Enum.map(fn {k,v} -> [k,v] end) |> Enum.sort() |> Jason.encode!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
        text = "Synthetic café observation"
        suffix = [["lineage", lineage], ["text", text]] |> Jason.encode!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
        key = "pending." <> suffix
        value = %{"lineage" => lineage, "text" => text, "assigned_category" => "ordinary", "evidence" => %{"sources" => [state["proof"]]}}
        commit = %{"op" => "collection.managed", "recipe_sha256" => state["recipe"], "request" => %{"op" => "commit", "expected_generation" => if(state["mode"] == "conflict", do: 0, else: snapshot["generation"]), "advance_floor" => true,
          "changes" => [%{"key" => key, "expected_revision" => 0, "value" => value}]},
          "proofs" => [%{"handle" => state["page"]["handle"], "quote" => "Synthetic café observation"}]}
        call(commit, Map.put(state, "step", "done"))
      end
      defp advance(_, outcome, state) do
        value = if state["mode"] == "paged", do: %{"items" => List.duplicate(String.duplicate("é", 3000), 4)}, else: outcome
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
        "properties" => %{"trace" => %{"type" => "string"}, "recipe" => %{"type" => "string"}}
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
          "options" => %{"trace" => trace, "recipe" => JSON.digest([recipe()])},
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
          "provider" => "demo",
          "profile" => nil,
          "model" => "synthetic",
          "endpoint" => "demo://local",
          "service_id" => "demo",
          "billing_mode" => "none",
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
      "expires_at_ms" => System.system_time(:millisecond) + 600_000,
      "headless" => true
    }

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
    assert_receive {:ipse, ^read, {:done, :ok}}, 10_000
    {:ok, events} = Journal.load(c.dir, Session.info(read).id)
    outer = Enum.find(events, &(&1["type"] == "extension_invocation_intent"))
    assert outer["semantic_binding"]["class"] == "collection.read"
    assert {:ok, _} = Session.restore_context(events)

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
    assert_receive {:ipse, ^publish, {:done, :ok}}, 10_000
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
    assert map_size(snapshot["operations"]) == 2
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
