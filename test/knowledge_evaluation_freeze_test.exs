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
