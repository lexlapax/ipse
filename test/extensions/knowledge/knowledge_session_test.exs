defmodule IpseKnowledge.KnowledgeSessionTest do
  use ExUnit.Case, async: false
  @native_fixture_child "--ipse-native-capture-child" in System.argv()

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

          input =
            Enum.find(Enum.reverse(messages), fn message ->
              message["role"] == "user" and not Ipse.Session.Reference.reference?(message)
            end)["content"]

          tool("capture", "ext__knowledge__capture", %{
            "text" => input,
            "category" => "ordinary",
            "reason" => "selected observation",
            "event_at_ms" => nil,
            "source" => %{"handle" => source["read_handle"], "quote" => input}
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

  @tag :capture_parent_case
  test "built native bundle captures an unattended source only as a protected pending proposal" do
    capture(false)
  end

  if @native_fixture_child do
    test "actual PTY input becomes a protected literal note without ordinary approval" do
      capture(true)
    end
  else
    test "actual PTY input exercises the separately built native capture artifact" do
      root = Path.join(System.tmp_dir!(), "ipse-knowledge-native-pty-" <> Ipse.Usage.id())
      File.mkdir!(root)
      File.chmod!(root, 0o700)
      on_exit(fn -> File.rm_rf!(root) end)
      driver = Path.join(root, "pty")

      assert {_, 0} =
               System.cmd(
                 "rustc",
                 [
                   "--edition=2021",
                   "-D",
                   "warnings",
                   "test/support/operator_pty.rs",
                   "-o",
                   driver
                 ],
                 stderr_to_stdout: true
               )

      paths =
        :code.get_path()
        |> Enum.map(&List.to_string/1)
        |> Enum.reject(&(&1 == "."))
        |> Enum.map(&Path.expand/1)
        |> Enum.reverse()
        |> Enum.flat_map(&["-pa", &1])

      program =
        "ExUnit.start(exclude: [:capture_parent_case]); {:ok, _} = Application.ensure_all_started(:ipse); System.argv([\"--ipse-native-capture-child\"]); Code.require_file(#{inspect(Path.expand(__ENV__.file))})"

      {output, status} =
        System.cmd(
          driver,
          [System.find_executable("elixir"), "--erl", "+S 2:2"] ++ paths ++ ["-e", program],
          stderr_to_stdout: true
        )

      assert status == 0, output
      assert output =~ "1 passed"
    end
  end

  defp capture(native?) do
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

    config =
      if native?,
        do: Map.merge(config, %{approval: :ask, approval_origin: :interactive, headless: false}),
        else: config

    {:ok, binding} = ProjectIdentity.admit(home, cwd, :folder)
    {:ok, namespace} = SemanticConsent.namespace(binding["project_id"], "knowledge")
    {:ok, catalog} = Catalog.snapshot(config)

    {:ok, sidecar_bytes} =
      Artifact.read_declared(
        Path.join(home, "extensions/artifacts"),
        artifact.digest,
        "operator.json",
        65_536
      )

    {:ok, sidecar} = JSON.decode_unique(sidecar_bytes)
    kind = if native?, do: "note", else: "pending"
    constraints = sidecar["publication"][kind]
    recipe = sidecar["recipes"][kind]
    constraints_sha = JSON.digest([constraints])
    recipe_sha = JSON.digest([recipe])

    effects =
      Enum.flat_map(catalog["entries"], fn descriptor ->
        hash = JSON.digest([descriptor])

        [
          %{
            "operation" => if(native?, do: "notes.capture", else: "notes.propose"),
            "class" => "collection.publish",
            "outer_sha256" => hash,
            "inner_op" => "collection.managed",
            "constraints_sha256" => constraints_sha,
            "recipe_sha256" => recipe_sha
          },
          %{
            "operation" => "notes.recall",
            "class" => "collection.read",
            "outer_sha256" => hash,
            "inner_op" => "collection.call",
            "managed_read" => [recipe_sha]
          }
        ]
      end)
      |> Enum.sort_by(&{&1["operation"], &1["class"], &1["outer_sha256"], &1["inner_op"]})

    selection = %{
      "version" => 2,
      "constraints" => %{constraints_sha => constraints},
      "recipes" => %{recipe_sha => recipe},
      "activation" => nil,
      "domain" => "knowledge",
      "namespace" => namespace,
      "scope" => %{"kind" => "project", "worktree_id" => nil},
      "sources" => %{
        "categories" => [if(native?, do: "interactive_operator", else: "unattended_input")],
        "exclusions" => []
      },
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

    if native? do
      {:ok, text, witness} = Session.observe_input(pid, "IPSE_FIXTURE_INPUT_1> ", 5000)
      assert text == "synthetic café 日本語 1"
      assert :ok = Session.prompt(pid, text, witness)
    else
      assert :ok = Session.prompt(pid, "Acme has owner Alex")
    end

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
    assert commit["version"] == 3
    assert commit["effect_binding"]["kind"] == "collection.managed"
    assert commit["effect_binding"]["version"] == 2
    assert commit["request"]["recipe_sha256"] == recipe_sha
    assert commit["request"]["request"]["advance_floor"] == true
    normalization = commit["outcome"]["value"]["normalization"]
    assert normalization["version"] == 2
    assert normalization["eligibility"] == if(native?, do: "current", else: "never_current")
    assert is_integer(normalization["valid_until_ms"])
    [change] = commit["request"]["request"]["changes"]
    assert String.starts_with?(change["key"], kind <> ".")

    if native?,
      do: assert(change["value"]["category"] == "ordinary"),
      else: assert(change["value"]["state"] == "pending")

    assert hd(change["value"]["evidence"]["sources"])["origin"] ==
             if(native?, do: "interactive_operator", else: "unattended_input")

    assert {:ok, _} = Session.restore_context(events)
    {:ok, after_save} = Consent.snapshot(control, binding["project_id"])
    assert map_size(after_save["operations"]) == 1

    {:ok, stored} =
      Ipse.Extension.Collection.execute(
        SemanticAdmission.collection_root(home),
        namespace,
        %{"op" => "status"},
        Ipse.Usage.id()
      )

    assert stored["generation"] == 1 and stored["floor"] == 1
    assert stored["records"] == 3
  end
end
