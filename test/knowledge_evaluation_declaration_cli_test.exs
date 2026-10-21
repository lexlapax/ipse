Code.require_file("../dev/verification/cli.exs", __DIR__)
Ipse.Development.Verification.Runtime.load_fixture!(:knowledge)
Code.require_file("../dev/evaluation/runner.exs", __DIR__)
Code.require_file("support/frozen_model_selection.exs", __DIR__)

defmodule Ipse.KnowledgeEvaluationDeclarationCLITest do
  use ExUnit.Case, async: false
  alias Ipse.Development.Evaluation.Contract

  @tag timeout: 120_000
  test "plain CLI retains and reopens the exact precompiled evaluator before accessing inputs" do
    root = Path.join(System.tmp_dir!(), "ipse-precompiled-cli-" <> Ipse.Usage.id())
    repository = Path.join(root, "repository ")
    File.mkdir_p!(repository)
    on_exit(fn -> File.rm_rf!(root) end)
    source = Path.expand("..", __DIR__)
    {files, 0} = System.cmd("git", ["ls-files", "-z"], cd: source)

    for relative <- String.split(files, <<0>>, trim: true),
        File.regular?(Path.join(source, relative)) do
      target = Path.join(repository, relative)
      File.mkdir_p!(Path.dirname(target))
      File.cp!(Path.join(source, relative), target)
    end

    git!(repository, ["init", "-q"])
    git!(repository, ["add", "."])

    git!(repository, [
      "-c",
      "user.name=Fixture",
      "-c",
      "user.email=fixture@example.test",
      "-c",
      "commit.gpgsign=false",
      "commit",
      "-qm",
      "synthetic evaluator source"
    ])

    artifact = Path.join(root, "artifact")
    inert_artifact!(artifact)

    spec =
      JSON.decode!(File.read!("examples/knowledge/benchmark-spec.json"))
      |> Map.put("blind_seed", String.duplicate("b", 64))
      |> Map.update!("artifacts", &Map.new(&1, fn {id, _} -> {id, artifact} end))

    assert {:ok, plan} = Contract.build(spec)
    plan_path = Path.join(root, "plan.json")
    private!(plan_path, JSON.encode!(plan))
    experiment = Path.join(root, "experiment.json")

    assert {0, %{"status" => "ok", "result" => declared}} =
             cli(repository, ["--phase", "declare", "--plan", plan_path, "--output", experiment])

    resolution = %{
      "artifacts" => plan["artifacts"],
      "model_origin" => "http://127.0.0.1:47631",
      "search_port" => 47632,
      "reports" => Path.join(root, "reports"),
      "data_manifest" => Path.join(root, "unopened-data/manifest.json"),
      "model_service" =>
        FrozenModelSelection.configuration(plan["models"], root, "http://127.0.0.1:47631")
    }

    resolution_path = Path.join(root, "resolution.json")
    private!(resolution_path, JSON.encode!(resolution))
    frozen = Path.join(root, "frozen")

    assert {0, %{"status" => "ok", "result" => seal}} =
             plain_cli(repository, [
               "--phase",
               "freeze-measured",
               "--experiment",
               experiment,
               "--experiment-sha256",
               declared["sha256"],
               "--resolution",
               resolution_path,
               "--output",
               frozen,
               "--sdk",
               Application.app_dir(:ipse, "ebin"),
               "--repository",
               repository
             ])

    runtime = frozen <> ".runtime/runtime"
    assert File.dir?(Path.join(runtime, "harness"))
    manifest = JSON.decode!(File.read!(seal["path"]))

    for module <- Ipse.Development.Verification.Scenarios.evaluator().modules do
      assert Enum.any?(
               manifest["runtime"]["files"],
               &(Path.basename(&1["path"]) == Atom.to_string(module) <> ".beam")
             )
    end

    before = Ipse.Development.Verification.Runtime.inventory(frozen <> ".runtime")
    predictions = Path.join(root, "must-not-create-predictions")

    args = [
      "--phase",
      "predict",
      "--freeze",
      seal["path"],
      "--freeze-sha256",
      seal["sha256"],
      "--data-manifest",
      resolution["data_manifest"],
      "--output",
      predictions
    ]

    assert {1, %{"status" => "failed", "reason" => %{"code" => "measured_entry_required"}}} =
             plain_cli(repository, args)

    relative = [
      "--phase",
      "predict",
      "--freeze",
      "frozen/manifest.json",
      "--freeze-sha256",
      seal["sha256"],
      "--data-manifest",
      "unopened-data/manifest.json",
      "--output",
      "must-not-create-predictions"
    ]

    assert {1, %{"status" => "failed", "reason" => %{"code" => "measured_entry_required"}}} =
             plain_cli(root, relative)

    assert before == Ipse.Development.Verification.Runtime.inventory(frozen <> ".runtime")
    beam = Path.join(runtime, "harness/Elixir.Ipse.Development.Evaluation.Author.beam")
    original = File.read!(beam)
    File.rm!(beam)

    try do
      assert {1, %{"status" => "failed", "reason" => %{"code" => "frozen_runtime_refused"}}} =
               plain_cli(repository, args)
    after
      File.write!(beam, original)
    end

    extra = Path.join(runtime, "harness/Elixir.UnlistedFixture.beam")
    File.write!(extra, "inert unlisted fixture bytes")

    try do
      assert {1, %{"status" => "failed", "reason" => %{"code" => "frozen_runtime_refused"}}} =
               plain_cli(repository, args)
    after
      File.rm!(extra)
    end

    refute File.exists?(predictions)
    refute File.exists?(Path.dirname(resolution["data_manifest"]))
    refute File.exists?(resolution["reports"])

    assert {0, %{"status" => "ok", "result" => _}} =
             cli(repository, [
               "--phase",
               "declare",
               "--plan",
               plan_path,
               "--output",
               Path.join(root, "second-experiment.json")
             ])
  end

  test "real CLI preserves a portable declaration and seals only an inert measured identity" do
    root = Path.join(System.tmp_dir!(), "ipse-declaration-cli-" <> Ipse.Usage.id())
    repository = Path.join(root, "repository")
    artifact = Path.join(root, "artifact")
    File.mkdir_p!(repository)
    File.chmod!(root, 0o700)
    on_exit(fn -> File.rm_rf!(root) end)
    File.write!(Path.join(repository, "main.exs"), "IO.puts(\"inert repository\")\n")
    git!(repository, ["init", "-q"])
    git!(repository, ["add", "main.exs"])

    git!(repository, [
      "-c",
      "user.name=Fixture",
      "-c",
      "user.email=fixture@example.test",
      "-c",
      "commit.gpgsign=false",
      "commit",
      "-qm",
      "initial inert fixture"
    ])

    inert_artifact!(artifact)

    spec =
      JSON.decode!(File.read!("examples/knowledge/benchmark-spec.json"))
      |> Map.put("blind_seed", String.duplicate("b", 64))
      |> Map.update!("artifacts", &Map.new(&1, fn {id, _} -> {id, artifact} end))

    assert {:ok, plan} = Contract.build(spec)
    plan_path = Path.join(root, "public-plan.json")
    private!(plan_path, JSON.encode!(plan))
    experiment_path = Path.join(root, "experiment.json")

    assert {0, %{"status" => "ok", "result" => declared}} =
             cli(repository, [
               "--phase",
               "declare",
               "--plan",
               plan_path,
               "--output",
               experiment_path
             ])

    experiment_bytes = File.read!(experiment_path)
    experiment_sha256 = declared["sha256"]
    assert experiment_sha256 == Ipse.JSON.sha256(experiment_bytes)
    assert declared["path"] == experiment_path
    assert private?(experiment_path)
    experiment = JSON.decode!(experiment_bytes)
    assert experiment["version"] == 2
    assert experiment["kind"] == "knowledge_experiment"
    refute Map.has_key?(experiment["source"], "root")
    refute Map.has_key?(experiment, "runtime")
    refute String.contains?(experiment_bytes, root)
    refute Map.has_key?(experiment["plan"], "artifacts")
    refute Map.has_key?(experiment["plan"], "search_port")

    assert experiment["policy"] == %{
             "metric" => "linux_memcg_charged_peak_bytes_v1",
             "device" => "cpu_only",
             "cache" => "fresh_private_inodes_per_cell",
             "expected_projects" => 2,
             "backend" => "linux_cgroup_v2_v2",
             "completion_policy" => "bounded_natural_drain_v1",
             "population_drain_limit_ms" => 2000
           }

    assert map_size(experiment["artifacts"]) == 7
    assert length(Enum.uniq(Map.values(experiment["artifacts"]))) == 1

    for profile <-
          Map.values(experiment["plan"]["profiles"]) ++
            Map.values(experiment["plan"]["embedding_profiles"]) do
      refute Map.has_key?(profile, "base_url")
    end

    resolution = %{
      "artifacts" => plan["artifacts"],
      "model_origin" => "http://127.0.0.1:47631",
      "search_port" => 47632,
      "reports" => Path.join(root, "reports"),
      "data_manifest" => Path.join(root, "missing-dataset/manifest.json"),
      "model_service" =>
        FrozenModelSelection.configuration(plan["models"], root, "http://127.0.0.1:47631")
    }

    resolution_path = Path.join(root, "resolution.json")
    private!(resolution_path, JSON.encode!(resolution))
    frozen = Path.join(root, "frozen")

    assert {0, %{"status" => "ok", "result" => seal}} =
             cli(repository, [
               "--phase",
               "freeze-measured",
               "--experiment",
               experiment_path,
               "--experiment-sha256",
               experiment_sha256,
               "--resolution",
               resolution_path,
               "--output",
               frozen
             ])

    manifest_bytes = File.read!(seal["path"])
    assert seal["sha256"] == Ipse.JSON.sha256(manifest_bytes)
    manifest = JSON.decode!(manifest_bytes)
    assert manifest["version"] == 2
    assert manifest["experiment_sha256"] == experiment_sha256
    assert manifest["source"]["root"] == repository
    assert manifest["resolution"] == resolution
    assert manifest["attempt_registry"] == Path.join(frozen, "attempts")
    assert File.dir?(manifest["attempt_registry"])
    assert manifest["artifacts"] == experiment["artifacts"]
    assert is_map(manifest["runtime"]) and is_map(manifest["provenance"])
    assert manifest["launch_recipe"]["reports"] == resolution["reports"]
    assert private?(seal["path"])
    assert private?(resolution_path)
    assert File.read!(experiment_path) == experiment_bytes
    assert File.read!(Path.join(frozen, "experiment.json")) == experiment_bytes
    resolved_plan = JSON.decode!(File.read!(Path.join(frozen, "plan.json")))
    assert resolved_plan["version"] == 2
    assert resolved_plan["model_origin"] == resolution["model_origin"]
    assert resolved_plan["search_port"] == resolution["search_port"]

    for profile <-
          Map.values(resolved_plan["profiles"]) ++ Map.values(resolved_plan["embedding_profiles"]) do
      assert profile["base_url"] == resolution["model_origin"]
    end

    missing_dataset = Path.join(root, "missing-dataset/manifest.json")
    predictions = Path.join(root, "predictions")

    assert {1, %{"status" => "failed", "reason" => %{"code" => "measured_entry_required"}}} =
             cli(repository, [
               "--phase",
               "predict",
               "--freeze",
               seal["path"],
               "--freeze-sha256",
               seal["sha256"],
               "--data-manifest",
               missing_dataset,
               "--output",
               predictions
             ])

    refute File.exists?(predictions)
    refute File.exists?(Path.dirname(missing_dataset))
    refute File.exists?(resolution["reports"])

    changed = Path.join(root, "changed-experiment.json")
    private!(changed, experiment_bytes <> " ")
    refused = Path.join(root, "refused-freeze")

    assert {1, %{"status" => "failed", "reason" => %{"code" => "experiment_changed"}}} =
             cli(repository, [
               "--phase",
               "freeze-measured",
               "--experiment",
               changed,
               "--experiment-sha256",
               experiment_sha256,
               "--resolution",
               resolution_path,
               "--output",
               refused
             ])

    refute File.exists?(refused)
    assert File.read!(experiment_path) == experiment_bytes
    assert :code.is_loaded(Independent.DeclarationCLIArtifact) == false
  end

  defp cli(repository, args) do
    paths = Path.wildcard(Path.join([Path.dirname(Application.app_dir(:ipse)), "*", "ebin"]))
    fixture = :code.which(Ipse.Development.Fixtures.Knowledge) |> to_string() |> Path.dirname()
    paths = [fixture | paths]
    code = Enum.flat_map(paths, &["-pa", &1])
    script = Path.expand("scripts/evaluate-knowledge.exs")

    {bytes, status} =
      System.cmd(System.find_executable("elixir"), code ++ [script | args],
        cd: repository,
        stderr_to_stdout: true
      )

    assert {:ok, message} = JSON.decode(String.trim(bytes)), bytes
    {status, message}
  end

  defp plain_cli(repository, args) do
    {bytes, status} =
      System.cmd(
        System.find_executable("elixir"),
        [Path.expand("scripts/evaluate-knowledge.exs") | args],
        cd: repository,
        stderr_to_stdout: true
      )

    decoded =
      try do
        JSON.decode(String.trim(bytes))
      rescue
        _ -> {:error, :invalid_json}
      end

    assert match?({:ok, _}, decoded), String.slice(bytes, -4000, 4000)
    {:ok, message} = decoded
    {status, message}
  end

  defp inert_artifact!(path) do
    File.mkdir_p!(Path.join(path, "ebin"))

    files = [
      {"LICENSE", "MIT synthetic fixture"},
      {"ebin/Elixir.Independent.DeclarationCLIArtifact.beam", "inert fixture bytes"}
    ]

    for {name, bytes} <- files, do: File.write!(Path.join(path, name), bytes)

    manifest = %{
      "format" => 1,
      "id" => "fixture/declaration-cli-artifact",
      "version" => "0.1.0",
      "sdk" => 1,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => "Independent.DeclarationCLIArtifact",
      "license_file" => "LICENSE",
      "options_schema" => %{"type" => "object", "additionalProperties" => false},
      "capabilities" => [],
      "exports" => %{"version" => 1, "commands" => [], "tools" => [], "services" => []},
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      },
      "files" =>
        for {name, bytes} <- files do
          %{"path" => name, "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
        end
    }

    File.write!(Path.join(path, "extension.json"), JSON.encode!(manifest))
  end

  defp private!(path, bytes) do
    File.write!(path, bytes, [:exclusive])
    File.chmod!(path, 0o600)
  end

  defp private?(path), do: Bitwise.band(File.stat!(path).mode, 0o777) == 0o600

  defp git!(root, args) do
    {bytes, status} = System.cmd("git", ["-C", root | args], stderr_to_stdout: true)
    assert status == 0, bytes
  end
end
