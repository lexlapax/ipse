Code.require_file("../examples/knowledge/evaluation_freeze.exs", __DIR__)

defmodule Ipse.KnowledgeEvaluationFreezeTest do
  use ExUnit.Case, async: false
  alias IpseKnowledgeExample.EvaluationFreeze, as: Freeze
  alias Ipse.Extensions.Manifest

  setup do
    root = Path.join(System.tmp_dir!(), "ipse-evaluation-freeze-" <> Ipse.Usage.id())
    repository = Path.join(root, "repository")
    artifact = Path.join(root, "artifact")
    File.mkdir_p!(repository)
    File.mkdir_p!(Path.join(artifact, "ebin"))
    File.write!(Path.join(repository, "main.exs"), "IO.puts(\"fixture\")\n")
    git(repository, ["init", "-q"])
    git(repository, ["add", "main.exs"])
    commit(repository, "initial fixture")

    files = [
      {"LICENSE", "MIT synthetic fixture"},
      {"ebin/Elixir.Independent.FrozenArtifact.beam", "inert fixture bytes"}
    ]

    for {path, bytes} <- files, do: File.write!(Path.join(artifact, path), bytes)

    manifest = %{
      "format" => 1,
      "id" => "fixture/frozen-artifact",
      "version" => "0.1.0",
      "sdk" => 1,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => "Independent.FrozenArtifact",
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
        for {path, bytes} <- files do
          %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Manifest.sha256(bytes)}
        end
    }

    File.write!(Path.join(artifact, "extension.json"), JSON.encode!(manifest))
    plan = JSON.encode!(%{"version" => 1, "input_path" => Path.join(root, "unopened-input.json")})
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      root: root,
      repository: repository,
      artifact: artifact,
      plan: plan,
      output: Path.join(root, "frozen")
    }
  end

  test "clean source and inert copied artifacts verify without opening dataset paths", ctx do
    assert {:ok, sealed} = create(ctx)
    assert {:ok, result} = Freeze.verify(sealed["path"], sealed["sha256"])
    assert result["plan"] == JSON.decode!(ctx.plan)
    assert result["manifest"]["source"]["files"] |> Enum.map(& &1["path"]) == ["main.exs"]
    copied = result["artifact_paths"]["fixture"]
    assert copied != ctx.artifact
    refute File.exists?(result["plan"]["input_path"])
    assert :code.is_loaded(Independent.FrozenArtifact) == false

    File.write!(
      Path.join(ctx.artifact, "ebin/Elixir.Independent.FrozenArtifact.beam"),
      "changed original"
    )

    assert {:ok, _} = Freeze.verify(sealed["path"], sealed["sha256"])

    assert File.read!(Path.join(copied, "ebin/Elixir.Independent.FrozenArtifact.beam")) ==
             "inert fixture bytes"
  end

  test "copied artifact tampering refuses even when its original still matches", ctx do
    {:ok, sealed} = create(ctx)
    {:ok, result} = Freeze.verify(sealed["path"], sealed["sha256"])
    File.write!(Path.join(result["artifact_paths"]["fixture"], "LICENSE"), "tampered")
    assert {:error, :artifact_changed} = Freeze.verify(sealed["path"], sealed["sha256"])
  end

  test "manifest and plan have distinct byte identities", ctx do
    {:ok, sealed} = create(ctx)
    File.write!(Path.join(ctx.output, "plan.json"), ctx.plan <> " ")
    assert {:error, :plan_changed} = Freeze.verify(sealed["path"], sealed["sha256"])
    File.write!(Path.join(ctx.output, "plan.json"), ctx.plan)
    File.write!(sealed["path"], " ", [:append])
    assert {:error, :manifest_changed} = Freeze.verify(sealed["path"], sealed["sha256"])
  end

  test "dirty tracked or untracked source refuses before output creation", ctx do
    File.write!(Path.join(ctx.repository, "main.exs"), "changed")
    assert {:error, :dirty_source} = create(ctx)
    refute File.exists?(ctx.output)
    git(ctx.repository, ["checkout", "--", "main.exs"])
    File.write!(Path.join(ctx.repository, "untracked.exs"), "new")
    assert {:error, :dirty_source} = create(ctx)
    refute File.exists?(ctx.output)
  end

  test "new clean commits cannot use an earlier freeze", ctx do
    {:ok, sealed} = create(ctx)
    commit(ctx.repository, "new clean identity", ["--allow-empty"])
    assert {:error, :source_changed} = Freeze.verify(sealed["path"], sealed["sha256"])
  end

  test "runtime inventory detects a new code-path file", ctx do
    directory = Path.join(ctx.root, "extra-ebin")
    File.mkdir!(directory)
    Code.prepend_path(directory)
    on_exit(fn -> Code.delete_path(directory) end)
    {:ok, sealed} = create(ctx)
    File.write!(Path.join(directory, "Elixir.NewFixture.beam"), "new runtime file")
    assert {:error, :runtime_changed} = Freeze.verify(sealed["path"], sealed["sha256"])
  end

  test "an existing output is preserved and invalid plans do not create output", ctx do
    File.mkdir!(ctx.output)
    File.write!(Path.join(ctx.output, "sentinel"), "preserve")
    assert {:error, :output_exists} = create(ctx)
    assert File.read!(Path.join(ctx.output, "sentinel")) == "preserve"

    assert {:error, :invalid_plan} =
             Freeze.create(
               ctx.repository,
               "[]",
               %{"fixture" => ctx.artifact},
               Path.join(ctx.root, "invalid")
             )

    refute File.exists?(Path.join(ctx.root, "invalid"))
  end

  test "non-object manifests preserve the version-one invalid-manifest refusal", ctx do
    path = Path.join(ctx.root, "invalid-manifest.json")

    for bytes <- ["[]", "null", "1", "{}"] do
      File.write!(path, bytes)
      assert {:error, :invalid_manifest} = Freeze.verify(path, Manifest.sha256(bytes))
    end
  end

  test "portable declaration survives clean source and artifact relocation", ctx do
    {:ok, first} = declare(ctx)
    relocated = Path.join(ctx.root, "relocated")
    File.cp_r!(ctx.repository, relocated)
    copied_artifact = Path.join(ctx.root, "other-artifact")
    File.cp_r!(ctx.artifact, copied_artifact)

    other_plan =
      plan_v2(ctx)
      |> Map.put("artifacts", %{"fixture" => copied_artifact})
      |> Map.put("search_port", 22002)
      |> put_in(["profiles", "answer", "base_url"], "http://127.0.0.1:22003")

    assert {:ok, second} =
             Freeze.declare(relocated, JSON.encode!(other_plan), %{"fixture" => copied_artifact})

    assert first["bytes"] == second["bytes"]
    assert first["sha256"] == Manifest.sha256(second["bytes"])
    experiment = JSON.decode!(first["bytes"])
    refute first["bytes"] =~ ctx.root
    refute Map.has_key?(experiment["source"], "root")
    refute Map.has_key?(experiment["plan"], "search_port")
    refute Map.has_key?(experiment["plan"], "artifacts")
    refute Map.has_key?(experiment["plan"]["profiles"]["answer"], "base_url")

    assert experiment["policy"] == %{
             "metric" => "linux_memcg_charged_peak_bytes_v1",
             "device" => "cpu_only",
             "cache" => "fresh_private_inodes_per_cell",
             "expected_projects" => 2,
             "backend" => "linux_cgroup_v2_v1"
           }

    refute File.exists?(ctx.output)
    refute File.exists?(Path.join(ctx.root, "missing-corpus.json"))
    assert :code.is_loaded(Independent.FrozenArtifact) == false
  end

  test "one portable declaration yields distinct immutable local execution seals", ctx do
    {:ok, experiment} = declare(ctx)
    relocated = Path.join(ctx.root, "relocated")
    File.cp_r!(ctx.repository, relocated)

    assert {:ok, first} =
             Freeze.create_v2(ctx.repository, experiment["bytes"], resolution(ctx), ctx.output)

    second_output = Path.join(ctx.root, "second-freeze")

    second_resolution = %{
      resolution(ctx)
      | "model_origin" => "http://127.0.0.1:22112",
        "reports" => Path.join(ctx.root, "second-reports")
    }

    assert {:ok, second} =
             Freeze.create_v2(relocated, experiment["bytes"], second_resolution, second_output)

    assert {:ok, left} = Freeze.verify(first["path"], first["sha256"])
    assert {:ok, right} = Freeze.verify(second["path"], second["sha256"])
    refute first["execution_id"] == second["execution_id"]
    refute first["sha256"] == second["sha256"]
    assert left["manifest"]["experiment_sha256"] == right["manifest"]["experiment_sha256"]
    refute left["manifest"]["source"]["root"] == right["manifest"]["source"]["root"]
    assert left["plan"]["version"] == 2
    assert left["plan"]["model_origin"] == "http://127.0.0.1:22111"
    assert left["plan"]["profiles"]["answer"]["base_url"] == left["plan"]["model_origin"]

    assert left["manifest"]["attempt_registry"] ==
             Path.join(Path.dirname(first["path"]), "attempts")

    assert left["manifest"]["launch_recipe"]["execution_id"] == first["execution_id"]

    assert left["manifest"]["recipe_sha256"] ==
             Manifest.sha256(JSON.encode!(left["manifest"]["launch_recipe"]))

    refute File.exists?(first["reports"])
    File.write!(Path.join(ctx.artifact, "LICENSE"), "changed original")
    assert {:ok, _} = Freeze.verify(first["path"], first["sha256"])
    File.write!(Path.join(left["artifact_paths"]["fixture"], "LICENSE"), "changed copy")
    assert {:error, :artifact_changed} = Freeze.verify(first["path"], first["sha256"])
  end

  test "resolution is pure and rejects endpoint aliases, shared origins and extra authority",
       ctx do
    {:ok, experiment} = declare(ctx)

    missing = %{
      resolution(ctx)
      | "artifacts" => %{"fixture" => Path.join(ctx.root, "absent-artifact")}
    }

    assert {:ok, plan} = Freeze.resolve_plan(experiment["bytes"], missing)
    assert plan["artifacts"] == missing["artifacts"]
    refute File.exists?(missing["artifacts"]["fixture"])

    for origin <- [
          "http://localhost:22111",
          "http://127.0.0.1:11434",
          "https://127.0.0.1:22111",
          "http://127.0.0.1",
          "http://127.0.0.1:22111/",
          "http://user@127.0.0.1:22111",
          "http://127.0.0.1:22111?x=1",
          "http://127.0.0.1:0",
          "http://127.0.0.1:65536"
        ] do
      assert {:error, :model_origin} =
               Freeze.resolve_plan(experiment["bytes"], %{
                 resolution(ctx)
                 | "model_origin" => origin
               })
    end

    assert {:error, :search_port} =
             Freeze.resolve_plan(experiment["bytes"], %{resolution(ctx) | "search_port" => 22111})

    assert {:error, :invalid_resolution} =
             Freeze.resolve_plan(
               experiment["bytes"],
               Map.put(resolution(ctx), "attempt_registry", ctx.root)
             )

    assert {:error, :artifact_aliases} =
             Freeze.resolve_plan(experiment["bytes"], %{
               resolution(ctx)
               | "artifacts" => %{"other" => ctx.artifact}
             })

    assert {:error, :invalid_resolution} =
             Freeze.resolve_plan(experiment["bytes"], %{
               resolution(ctx)
               | "reports" => Path.join(ctx.root, "a/../reports")
             })

    changed = JSON.decode!(experiment["bytes"]) |> put_in(["policy", "metric"], "sampled_rss")

    assert {:error, :invalid_experiment} =
             Freeze.resolve_plan(JSON.encode!(changed), resolution(ctx))

    assert {:error, :invalid_experiment} =
             Freeze.resolve_plan(
               JSON.encode!(Map.put(changed, "hostname", "fixture")),
               resolution(ctx)
             )

    refute File.exists?(ctx.output)
  end

  test "canonical attempt registry stays outside ignored disposable reports", ctx do
    File.write!(Path.join(ctx.repository, ".gitignore"), ".ipse/\n")
    git(ctx.repository, ["add", ".gitignore"])
    commit(ctx.repository, "ignore local reports")
    File.mkdir!(Path.join(ctx.repository, ".ipse"))
    output = Path.join(ctx.repository, ".ipse/freeze")
    reports = Path.join(ctx.repository, ".ipse/reports")
    {:ok, experiment} = declare(ctx)

    assert {:ok, sealed} =
             Freeze.create_v2(
               ctx.repository,
               experiment["bytes"],
               %{resolution(ctx) | "reports" => reports},
               output
             )

    assert {:ok, result} = Freeze.verify(sealed["path"], sealed["sha256"])
    assert sealed["attempt_registry"] == Path.join(Path.dirname(sealed["path"]), "attempts")
    assert Bitwise.band(File.stat!(sealed["attempt_registry"]).mode, 0o777) == 0o700
    File.mkdir!(result["resolution"]["reports"])
    File.write!(Path.join(result["resolution"]["reports"], "disposable"), "fixture")
    File.write!(Path.join(sealed["attempt_registry"], "existing-first-attempt"), "retained")
    File.rm_rf!(result["resolution"]["reports"])
    assert {:ok, _} = Freeze.verify(sealed["path"], sealed["sha256"])

    assert File.read!(Path.join(sealed["attempt_registry"], "existing-first-attempt")) ==
             "retained"

    File.rm_rf!(sealed["attempt_registry"])
    elsewhere = Path.join(ctx.root, "other-registry")
    File.mkdir!(elsewhere)
    File.ln_s!(elsewhere, sealed["attempt_registry"])
    assert {:error, :registry_changed} = Freeze.verify(sealed["path"], sealed["sha256"])
  end

  test "reports overlap, existing reports and reused freeze output refuse without replacing files",
       ctx do
    {:ok, experiment} = declare(ctx)

    for reports <- [ctx.repository, ctx.root, ctx.output, Path.join(ctx.output, "reports")] do
      assert {:error, :reports_overlap} =
               Freeze.create_v2(
                 ctx.repository,
                 experiment["bytes"],
                 %{resolution(ctx) | "reports" => reports},
                 ctx.output
               )

      refute File.exists?(ctx.output)
    end

    reports = resolution(ctx)["reports"]
    File.mkdir!(reports)
    File.write!(Path.join(reports, "sentinel"), "preserve")

    assert {:error, :reports_exists} =
             Freeze.create_v2(ctx.repository, experiment["bytes"], resolution(ctx), ctx.output)

    assert File.read!(Path.join(reports, "sentinel")) == "preserve"
    File.rm_rf!(reports)

    {:ok, sealed} =
      Freeze.create_v2(ctx.repository, experiment["bytes"], resolution(ctx), ctx.output)

    bytes = File.read!(sealed["path"])

    assert {:error, :output_exists} =
             Freeze.create_v2(ctx.repository, experiment["bytes"], resolution(ctx), ctx.output)

    assert File.read!(sealed["path"]) == bytes
  end

  test "v2 detects exact plan and experiment byte tampering and later source commits", ctx do
    {:ok, experiment} = declare(ctx)

    {:ok, sealed} =
      Freeze.create_v2(ctx.repository, experiment["bytes"], resolution(ctx), ctx.output)

    plan_path = Path.join(Path.dirname(sealed["path"]), "plan.json")
    original_plan = File.read!(plan_path)
    File.write!(plan_path, original_plan <> " ")
    assert {:error, :plan_changed} = Freeze.verify(sealed["path"], sealed["sha256"])
    File.write!(plan_path, original_plan)
    experiment_path = Path.join(Path.dirname(sealed["path"]), "experiment.json")
    File.write!(experiment_path, experiment["bytes"] <> " ")
    assert {:error, :experiment_changed} = Freeze.verify(sealed["path"], sealed["sha256"])
    File.write!(experiment_path, experiment["bytes"])
    commit(ctx.repository, "new clean source", ["--allow-empty"])
    assert {:error, :source_changed} = Freeze.verify(sealed["path"], sealed["sha256"])
  end

  test "v2 runtime identity and registry permissions remain local immutable requirements", ctx do
    directory = Path.join(ctx.root, "extra-v2-ebin")
    File.mkdir!(directory)
    Code.prepend_path(directory)
    on_exit(fn -> Code.delete_path(directory) end)
    {:ok, experiment} = declare(ctx)

    {:ok, sealed} =
      Freeze.create_v2(ctx.repository, experiment["bytes"], resolution(ctx), ctx.output)

    File.chmod!(sealed["attempt_registry"], 0o755)
    assert {:error, :registry_changed} = Freeze.verify(sealed["path"], sealed["sha256"])
    File.chmod!(sealed["attempt_registry"], 0o700)
    File.write!(Path.join(directory, "Elixir.NewV2Fixture.beam"), "changed runtime")
    assert {:error, :runtime_changed} = Freeze.verify(sealed["path"], sealed["sha256"])
  end

  defp plan_v2(ctx),
    do: %{
      "version" => 1,
      "mode" => "fixture",
      "data" => %{
        "corpus" => "missing-corpus.json",
        "queries" => "missing-queries.json",
        "split" => "fixture",
        "expected_queries" => 2,
        "manifest_sha256" => String.duplicate("a", 64)
      },
      "as_of_ms" => 1,
      "artifacts" => %{"fixture" => ctx.artifact},
      "profiles" => %{
        "answer" => %{
          "provider" => "ollama",
          "model" => "fixture-answer",
          "base_url" => "http://127.0.0.1:21434"
        }
      },
      "embedding_profiles" => %{},
      "models" => %{},
      "variants" => [],
      "answer" => true,
      "interval_ms" => 100,
      "search_port" => 21435,
      "blind_seed" => String.duplicate("b", 64),
      "storage_policy" => "forget_all_then_collect_v1"
    }

  defp declare(ctx),
    do: Freeze.declare(ctx.repository, JSON.encode!(plan_v2(ctx)), %{"fixture" => ctx.artifact})

  defp resolution(ctx),
    do: %{
      "artifacts" => %{"fixture" => ctx.artifact},
      "model_origin" => "http://127.0.0.1:22111",
      "search_port" => 22110,
      "reports" => Path.join(ctx.root, "reports")
    }

  defp create(ctx),
    do: Freeze.create(ctx.repository, ctx.plan, %{"fixture" => ctx.artifact}, ctx.output)

  defp git(root, args) do
    {output, status} = System.cmd("git", ["-C", root | args], stderr_to_stdout: true)
    assert status == 0, output
  end

  defp commit(root, message, extra \\ []) do
    git(
      root,
      [
        "-c",
        "user.name=Fixture",
        "-c",
        "user.email=fixture@example.test",
        "-c",
        "commit.gpgsign=false",
        "commit",
        "-qm",
        message
      ] ++ extra
    )
  end
end
