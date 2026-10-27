defmodule IpseKnowledge.KnowledgeSessionTest do
  use ExUnit.Case, async: false

  alias Ipse.Extension.{
    Artifact,
    Catalog,
    Registry,
    Consent,
    ProjectIdentity,
    SemanticConsent,
    SemanticAdmission
  }

  alias Ipse.{Session, JSON, Journal}

  defmodule Model do
    def complete(_, messages, _, _) do
      results = Enum.filter(messages, &(&1["role"] == "tool"))

      case results do
        [] ->
          tool("list", "source_list", %{"limit" => 32})

        [result] ->
          list = Jason.decode!(result["content"])
          source = Enum.find(list["sources"], &(&1["kind"] == "input.original"))

          tool("capture", "ext__knowledge__capture", %{
            "text" => "Acme has owner Alex",
            "category" => "ordinary",
            "reason" => "selected observation",
            "event_at_ms" => nil,
            "source" => %{"handle" => source["read_handle"], "quote" => "Acme has owner Alex"}
          })

        _ ->
          {:ok,
           %{"role" => "assistant", "content" => "The unattended observation is pending review."},
           %{}}
      end
    end

    defp tool(id, name, args),
      do:
        {:ok,
         %{
           "role" => "assistant",
           "content" => "",
           "tool_calls" => [
             %{
               "id" => id,
               "type" => "function",
               "function" => %{
                 "name" => name,
                 "arguments" => Jason.encode!(args)
               }
             }
           ]
         }, %{}}
  end

  test "built native bundle captures an unattended source only as a protected pending proposal" do
    root = Path.join(System.tmp_dir!(), "ipse-native-knowledge-session-" <> Ipse.Usage.id())
    home = Path.join(root, "home")
    cwd = Path.join(root, "project")
    File.mkdir_p!(home)
    File.mkdir_p!(cwd)
    File.chmod!(home, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    output = Path.join(root, "artifact")
    sdk = Application.app_dir(:ipse, "ebin")
    paths = Path.wildcard(Path.join(Path.dirname(Path.dirname(sdk)), "*/ebin"))

    args =
      Enum.flat_map(paths, &["-pa", &1]) ++
        [
          "extensions/knowledge/build.exs",
          "--sdk",
          sdk,
          "--output",
          output,
          "--package",
          "knowledge",
          "--preset",
          "native"
        ]

    assert {build, 0} = System.cmd(System.find_executable("elixir"), args, stderr_to_stdout: true)
    assert build =~ "Built knowledge/native"
    {:ok, artifact} = Artifact.import(output, Path.join(home, "extensions/artifacts"))

    options =
      Map.new(~w(stores search fetch retrieval embedding rerank extraction), &{&1, %{}})
      |> Map.put("version", 1)

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
          "instance" => "knowledge",
          "artifact" => artifact.digest,
          "enabled" => true,
          "options" => options,
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
    {:ok, namespace} = SemanticConsent.namespace(binding["project_id"], "knowledge")
    {:ok, catalog} = Catalog.snapshot(config)
    sample = proposal_sample()

    constraints = %{
      "version" => 1,
      "key_prefix" => "pending.",
      "allow_delete" => false,
      "source_categories" => ["unattended_input"],
      "evidence_path" => ["evidence", "sources"],
      "value_schema" => schema(sample)
    }

    effects =
      Enum.flat_map(catalog["entries"], fn descriptor ->
        hash = JSON.digest([descriptor])

        [
          %{
            "operation" => "notes.propose",
            "class" => "collection.publish",
            "outer_sha256" => hash,
            "inner_op" => "collection.call",
            "constraints" => constraints
          },
          %{
            "operation" => "notes.recall",
            "class" => "collection.read",
            "outer_sha256" => hash,
            "inner_op" => "collection.call"
          }
        ]
      end)
      |> Enum.sort_by(&{&1["operation"], &1["class"], &1["outer_sha256"], &1["inner_op"]})

    selection = %{
      "domain" => "knowledge",
      "namespace" => namespace,
      "scope" => %{"kind" => "project", "worktree_id" => nil},
      "sources" => %{"categories" => ["unattended_input"], "exclusions" => []},
      "storage" => %{"kind" => "local_collection", "collection" => "knowledge"},
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
      "effects" => effects,
      "limits" =>
        Map.merge(Consent.zero(), %{
          "operations" => 8,
          "input_bytes" => 100_000,
          "output_bytes" => 200_000
        }),
      "period_ms" => 86_400_000,
      "expires_at_ms" => System.system_time(:millisecond) + 600_000,
      "headless" => true
    }

    assert {:ok, policy} = SemanticConsent.prepare(binding, entry.identity, selection)
    control = SemanticAdmission.control_root(home)
    {:ok, before} = Consent.snapshot(control, binding["project_id"])

    {:ok, _} =
      Consent.replace(
        control,
        binding["project_id"],
        before["epoch"],
        policy,
        System.system_time(:millisecond)
      )

    {:ok, selection} = Ipse.Config.Semantics.selection(policy)
    config = Map.put(config, :semantic_selections, selection)
    dir = Path.join(root, "sessions")

    {:ok, pid} =
      DynamicSupervisor.start_child(
        Ipse.Sessions,
        {Session, config: config, cwd: cwd, state_dir: dir, subscriber: self()}
      )

    on_exit(fn -> if Process.alive?(pid), do: Session.close(pid) end)
    assert :ok = Session.prompt(pid, "Acme has owner Alex")
    assert_receive {:ipse, ^pid, {:done, :ok}}, 30000
    {:ok, events} = Journal.load(dir, Session.info(pid).id)

    commit =
      Enum.find(
        events,
        &(&1["type"] == "extension_action_result" and
            get_in(&1, ["request", "request", "op"]) == "commit")
      )

    assert commit
    assert commit["outcome"]["status"] == "ok"
    assert commit["approval"] == "saved_consent"
    [change] = commit["request"]["request"]["changes"]
    assert String.starts_with?(change["key"], "pending.")
    assert change["value"]["state"] == "pending"
    assert hd(change["value"]["evidence"]["sources"])["origin"] == "unattended_input"
    assert {:ok, _} = Session.restore_context(events)
    {:ok, after_save} = Consent.snapshot(control, binding["project_id"])
    assert map_size(after_save["operations"]) == 1
  end

  defp schema(v) when is_map(v),
    do: %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => Enum.sort(Map.keys(v)),
      "properties" => Map.new(v, fn {key, value} -> {key, schema(value)} end)
    }

  defp schema([v]),
    do: %{"type" => "array", "minItems" => 1, "maxItems" => 1, "items" => schema(v)}

  defp schema(nil), do: %{"type" => "null"}
  defp schema(v) when is_integer(v), do: %{"type" => "integer"}
  defp schema(v) when is_binary(v), do: %{"type" => "string"}

  defp proposal_sample do
    text = "Acme has owner Alex"

    proof = %{
      "version" => 1,
      "session_id" => String.duplicate("1", 32),
      "occurrence_id" => String.duplicate("2", 32),
      "version_id" => String.duplicate("3", 32),
      "kind" => "input.original",
      "origin" => "unattended_input",
      "coverage" => "available",
      "path" => nil,
      "start_byte" => 0,
      "end_byte" => byte_size(text),
      "quote" => text,
      "quote_sha256" => JSON.sha256(text),
      "content_sha256" => JSON.sha256(text),
      "receipt_sha256" => JSON.sha256("synthetic fixture")
    }

    %{
      "version" => 1,
      "kind" => "proposal",
      "id" => String.duplicate("4", 64),
      "lineage" => String.duplicate("5", 64),
      "state" => "pending",
      "text" => text,
      "assigned_category" => "ordinary",
      "reason" => "selected observation",
      "event_at_ms" => nil,
      "created_at_ms" => 0,
      "expires_at_ms" => 604_800_000,
      "evidence" => %{"sources" => [proof]}
    }
  end
end
