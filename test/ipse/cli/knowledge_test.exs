defmodule Ipse.CLI.KnowledgeTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  test "unsupported setup flags cannot widen or bypass knowledge review" do
    for flag <- ["--yes", "--accept-edits", "--write", "--provider=demo", "--model=scripted"] do
      capture_io(:stderr, fn ->
        assert Ipse.CLI.run(["knowledge", "enable", flag]) == 1
      end)
    end
  end

  test "native setup saves exact permission, activates a new headless session and revokes" do
    assert scenario("save", "--knowledge") =~ "KNOWLEDGE_NATIVE_SETUP_SAVE_DISABLE_PASSED"
  end

  for input <- ~w(argv stdin) do
    @tag timeout: 90_000, headless_pending_cli: true
    test "headless #{input} saves one attributed pending proposal without ordinary mutation authority" do
      assert scenario(unquote(input), "--knowledge", "headless_cli_untrusted_process.exs") =~
               "UNTRUSTED_CLI_#{String.upcase(unquote(input))}_PASSED"
    end
  end

  @tag timeout: 90_000, assistant_pending_direct: true
  test "a completed assistant reply remains attributed and pending under saved consent" do
    assert scenario("assistant", "--knowledge", "headless_untrusted_capture.exs") =~
             "ASSISTANT_PROPOSAL_SIGNED_PENDING_PASSED"
  end

  @tag timeout: 90_000, assistant_pending_model: true
  test "the main model can select its previous reply as a pending proposal" do
    assert scenario("assistant_model", "--knowledge", "headless_untrusted_capture.exs") =~
             "ASSISTANT_PROPOSAL_SIGNED_PENDING_PASSED"
  end

  @tag timeout: 90_000, assistant_pending_model: true
  test "the main model cannot capture an invented quote from its previous reply" do
    assert scenario("assistant_model_bad_quote", "--knowledge", "headless_untrusted_capture.exs") =~
             "ASSISTANT_PROPOSAL_BAD_QUOTE_REFUSED"
  end

  @tag timeout: 120_000, assistant_pending_public_review: true
  test "a model-selected assistant proposal can be reviewed with its original attribution" do
    assert scenario("assistant_model_review", "--knowledge", "headless_untrusted_capture.exs") =~
             "ASSISTANT_PROPOSAL_PUBLIC_REVIEW_PASSED"
  end

  @tag timeout: 120_000, assistant_pending_public_review: true
  test "recall withholds an accepted assistant proposal when its original source is missing" do
    assert scenario(
             "assistant_model_source_lost",
             "--knowledge",
             "headless_untrusted_capture.exs"
           ) =~
             "ASSISTANT_PROPOSAL_PUBLIC_REVIEW_PASSED"
  end

  @tag timeout: 120_000, assistant_pending_resume: true
  test "resuming the original Session refuses stale history before model dispatch" do
    assert scenario("assistant_model_resume", "--knowledge", "headless_untrusted_capture.exs") =~
             "ASSISTANT_PROPOSAL_PUBLIC_REVIEW_PASSED"
  end

  @tag knowledge_readiness: true
  test "saved native permission distinguishes activation matching from unavailable capture" do
    output = scenario("readiness", "--knowledge")
    assert output =~ "KNOWLEDGE_NATIVE_READINESS_PUBLICATION_UNAVAILABLE"
    assert output =~ "Broad protected note saving is not ready"
    assert output =~ "A new statement may be saved through separate native review"
  end

  test "bare yes and a mismatched native challenge cannot grant permission" do
    for {name, mode} <- [{"cancel", "--knowledge-cancel"}, {"stale", "--knowledge-stale"}] do
      assert scenario(name, mode) =~ "KNOWLEDGE_NATIVE_REVIEW_CANCELLED"
    end
  end

  test "piped input cannot grant permission or create a project identity" do
    assert scenario("pipe", nil) =~ "KNOWLEDGE_NATIVE_PIPE_REFUSED"
  end

  test "a concurrent consent epoch change cannot be overwritten by a reviewed grant" do
    assert scenario("cas", "--knowledge-cas") =~ "KNOWLEDGE_NATIVE_REVIEW_CANCELLED"
  end

  test "saved configuration changes during native review refuse instead of saving the old proposal" do
    for field <- ~w(model timeout malformed format) do
      assert scenario("config-" <> field, "--knowledge-config") =~
               "KNOWLEDGE_NATIVE_REVIEW_CANCELLED"
    end
  end

  test "review data binds actual bundled recipes and routes without creating consent" do
    root = private_root()
    home = Path.join(root, "home")
    cwd = Path.join(root, "project")
    File.mkdir!(home)
    File.chmod!(home, 0o700)
    File.mkdir!(cwd)

    client = %{
      workspace: cwd,
      home: home,
      auth_dir: Path.join(home, "auth"),
      operator_home: root,
      mcp_config: nil,
      base_url: nil,
      operator_questions: false,
      accept_edits: false,
      approval: :ask,
      approval_origin: :interactive,
      headless: false
    }

    assert {:ok, effective} =
             Ipse.Config.resolve(
               cwd,
               home,
               [provider: "demo", model: "scripted", project_config: false],
               %{}
             )

    assert {:ok, config} = Ipse.Config.runtime(effective, client)
    assert {:ok, binding} = Ipse.Extension.ProjectIdentity.admit(home, cwd, :folder)
    assert {:ok, artifact} = Ipse.Extension.Bundles.install("knowledge", home)
    control = Ipse.Extension.SemanticAdmission.control_root(home)
    refute File.exists?(control)
    now = System.system_time(:millisecond)

    assert {:ok, %{policy: policy}} =
             Ipse.CLI.Knowledge.prepare(config, binding, artifact.digest, now)

    assert Ipse.Extension.SemanticConsent.policy?(policy)
    assert policy["settings"]["activation"]["artifact_sha256"] == artifact.digest
    assert policy["settings"]["activation"]["main_timeout_ms"] == 90_000
    assert policy["settings"]["routes"] |> Enum.map(& &1["operation"]) == ["main"]
    assert map_size(policy["settings"]["recipes"]) == 2
    effects = policy["settings"]["effects"]
    recipes = policy["settings"]["recipes"] |> Map.keys() |> Enum.sort()

    descriptors =
      for {group, stage} <- [
            {"commands", "invoke.command"},
            {"tools", "invoke.tool"},
            {"jobs", "event.job"}
          ],
          descriptor <- artifact.manifest["exports"][group] do
        Map.merge(descriptor, %{
          "instance" => "knowledge",
          "stage" => stage,
          "name" => "ext__knowledge__" <> descriptor["id"]
        })
      end

    assert length(descriptors) == 6
    assert length(effects) == 10

    for descriptor <- descriptors do
      hash = Ipse.JSON.digest([descriptor])
      selected = Enum.filter(effects, &(&1["outer_sha256"] == hash))
      reads = Enum.filter(selected, &(&1["class"] == "collection.read"))
      writes = Enum.filter(selected, &(&1["class"] == "collection.publish"))

      assert [
               %{
                 "operation" => "notes.recall",
                 "inner_op" => "collection.call",
                 "managed_read" => ^recipes
               }
             ] = reads

      if descriptor["id"] == "capture" do
        assert Enum.sort(Enum.map(writes, & &1["operation"])) == ~w(notes.capture notes.propose)
        assert Enum.all?(writes, &(&1["inner_op"] == "collection.managed"))
      else
        assert writes == []
      end
    end

    assert policy["limits"]["model_calls"] == 0
    assert policy["limits"]["cost_nanos"] == 0
    assert policy["expires_at_ms"] == now + 365 * 86_400_000

    assert {:error, _} =
             Ipse.CLI.Knowledge.prepare(
               %{config | timeout_ms: 999},
               binding,
               artifact.digest,
               now
             )

    assert {:error, _} =
             Ipse.CLI.Knowledge.prepare(config, binding, String.duplicate("0", 64), now)

    assert {:error, _} =
             Ipse.CLI.Knowledge.prepare_experiment(
               config,
               binding,
               artifact.digest,
               now,
               "advice",
               2
             )

    assert {:ok, shadow} = Ipse.Extension.Bundles.install("knowledge-decision-shadow", home)

    local =
      Map.merge(config, %{
        inference_services: %{
          "fixture" => %{"version" => 1, "origins" => ["http://127.0.0.1:12345"]}
        },
        decision_profiles: %{
          "advice" => %{
            "operation" => "decision",
            "provider" => "system_one_compatible",
            "model" => "fixture",
            "service_id" => "fixture",
            "base_url" => "http://127.0.0.1:12345"
          }
        }
      })

    assert {:ok, %{policy: experiment}} =
             Ipse.CLI.Knowledge.prepare_experiment(
               local,
               binding,
               shadow.digest,
               now,
               "advice",
               2
             )

    assert experiment["limits"]["model_calls"] == 2
    assert experiment["settings"]["experiment"]["issued_at_ms"] == now
    assert experiment["expires_at_ms"] <= (div(now, 86_400_000) + 1) * 86_400_000

    assess =
      shadow.manifest["exports"]["tools"]
      |> Enum.find(&(&1["id"] == "assess"))
      |> Map.merge(%{
        "instance" => "knowledge",
        "stage" => "invoke.tool",
        "name" => "ext__knowledge__assess"
      })

    assess_effects =
      Enum.filter(experiment["settings"]["effects"], fn effect ->
        effect["outer_sha256"] == Ipse.JSON.digest([assess])
      end)

    assert Enum.sort(Enum.map(assess_effects, & &1["class"])) ==
             ~w(collection.read decision.create)

    assert Enum.any?(assess_effects, &(&1["operation"] == "notes.assess"))
    assess_hash = Ipse.JSON.digest([assess])

    assert {:ok, "decision.create"} =
             Ipse.Extension.SemanticAdmission.outer_class(experiment, assess_hash)

    missing_grant = update_in(experiment, ["settings"], &Map.delete(&1, "experiment"))

    assert {:ok, "collection.read"} =
             Ipse.Extension.SemanticAdmission.outer_class(missing_grant, assess_hash)

    additional_effect = %{
      "operation" => "unexpected.model",
      "class" => "model.complete",
      "outer_sha256" => assess_hash,
      "inner_op" => "model.complete"
    }

    widened = update_in(experiment, ["settings", "effects"], &[additional_effect | &1])

    assert {:ok, "collection.read"} =
             Ipse.Extension.SemanticAdmission.outer_class(widened, assess_hash)

    assert {:error, _} = Ipse.CLI.Knowledge.prepare(local, binding, shadow.digest, now)

    assert {:error, _} =
             Ipse.CLI.Knowledge.prepare_experiment(local, binding, shadow.digest, now, "other", 2)

    alternate = put_in(local, [:decision_profiles, "other"], local.decision_profiles["advice"])

    assert {:error, _} =
             Ipse.CLI.Knowledge.prepare_experiment(
               alternate,
               binding,
               shadow.digest,
               now,
               "other",
               2
             )

    localhost =
      local
      |> put_in([:decision_profiles, "advice", "base_url"], "http://localhost:12345")
      |> put_in([:inference_services, "fixture", "origins"], ["http://localhost:12345"])

    assert {:error, _} =
             Ipse.CLI.Knowledge.prepare_experiment(
               localhost,
               binding,
               shadow.digest,
               now,
               "advice",
               2
             )

    shadow_root = Path.join([home, "extensions/artifacts", shadow.digest])
    sidecar_path = Path.join(shadow_root, "operator.json")
    sidecar = File.read!(sidecar_path)
    File.chmod!(sidecar_path, 0o600)
    File.write!(sidecar_path, String.replace(sidecar, "decision-shadow", "native"))

    assert {:error, _} =
             Ipse.CLI.Knowledge.prepare_experiment(
               local,
               binding,
               shadow.digest,
               now,
               "advice",
               2
             )

    File.write!(sidecar_path, sidecar)

    manifest_path = Path.join(shadow_root, "extension.json")
    manifest = File.read!(manifest_path)
    File.chmod!(manifest_path, 0o600)
    File.write!(manifest_path, String.replace(manifest, "capture", "changed"))

    assert {:error, _} =
             Ipse.CLI.Knowledge.prepare_experiment(
               local,
               binding,
               shadow.digest,
               now,
               "advice",
               2
             )

    File.write!(manifest_path, "{}")

    assert {:error, _} =
             Ipse.CLI.Knowledge.prepare_experiment(
               local,
               binding,
               shadow.digest,
               now,
               "advice",
               2
             )

    refute File.exists?(control)

    installed = Path.join([home, "extensions/artifacts", artifact.digest, "operator.json"])
    File.chmod!(installed, 0o600)
    File.write!(installed, "{}")
    assert {:error, _} = Ipse.CLI.Knowledge.prepare(config, binding, artifact.digest, now)
    refute File.exists?(control)
  end

  defp scenario(name, mode, script \\ "knowledge_setup.exs") do
    root = private_root()

    paths =
      :code.get_path()
      |> Enum.map(&List.to_string/1)
      |> Enum.reject(&(&1 == "."))
      |> Enum.map(&Path.expand/1)
      |> Enum.reverse()
      |> Enum.flat_map(&["-pa", &1])

    args =
      ["--erl", "+S 2:2"] ++
        paths ++ [Path.expand("test/support/" <> script), root, name]

    {executable, args} =
      if mode do
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

        {driver, [mode, System.find_executable("elixir") | args]}
      else
        {System.find_executable("elixir"), args}
      end

    {output, status} = System.cmd(executable, args, stderr_to_stdout: true, cd: root)
    assert status == 0, output
    output
  end

  defp private_root do
    root = Path.join(System.tmp_dir!(), "ipse-knowledge-setup-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end
end
