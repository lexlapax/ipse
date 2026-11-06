defmodule Ipse.Test.PackagedPairedPreparation do
  @moduledoc false
  @base Path.dirname(__ENV__.file)
  alias Ipse.JSON
  alias Ipse.Development.Verification.Runtime, as: Inventory

  def run(descriptor) do
    d = Jason.decode!(File.read!(descriptor))
    false = d["reviewed"]
    false = d["execution_enabled"]
    true = d["kind"] === "packaged_paired_protected_answer_v2"

    true =
      is_binary(d["package_commit"]) and Regex.match?(~r/\A[0-9a-f]{40}\z/, d["package_commit"])

    true =
      Enum.all?(
        ~w(archive_sha256 sidecar_sha256 artifact_sha256 pty_sha256 source_commitment),
        &JSON.sha256?(d[&1])
      )

    false = File.exists?(d["storage"])
    nil = Process.whereis(Ipse.Supervisor)
    false = Enum.any?(Application.started_applications(), &(elem(&1, 0) === :ipse))
    ports = MapSet.new(Port.list())

    {"", 0} =
      System.cmd("/usr/bin/sha256sum", ["--check", "--status", Path.join(@base, "inputs.sha256")])

    true = Path.expand(Application.app_dir(:ipse)) === Path.join(d["package"], "lib/ipse-0.1.0")
    :ok = Application.load(:ex_unit)
    true = to_string(Application.spec(:ex_unit, :vsn)) === System.version()
    true = Path.expand(Application.app_dir(:ex_unit)) === d["ex_unit"]
    :non_existing = :code.which(Ipse.Test.PairedAnswerExtension)
    out = Path.join(@base, "prepared-current-02")
    false = File.exists?(out)
    File.mkdir!(out)
    File.chmod!(out, 0o700)
    for name <- ~w(verification-ebin helper-ebin), do: File.mkdir!(Path.join(out, name))

    verify = [
      {Ipse.Development.Verification.Scenarios, source("verification_scenarios.exs")},
      {Ipse.Development.Verification.Runtime, source("verification_runtime.exs")}
    ]

    compile!(verify, Path.join(out, "verification-ebin"))
    true = apply(Inventory, :digest, [d["archive"]]) === d["archive_sha256"]
    true = apply(Inventory, :digest, [d["sidecar"]]) === d["sidecar_sha256"]
    true = apply(Inventory, :digest, [d["pty"]]) === d["pty_sha256"]
    true = JSON.sha256(File.read!(d["references"])) === d["reference_sha256"]
    :ok = origins!(d)
    before = inventories(d)
    save(out, "before.term", :erlang.term_to_binary(before, [:deterministic]))

    helper_sources = [
      {Ipse.Test.ProviderFixture, source("provider_fixture.ex")},
      {Ipse.Test.ResumeAssertions, source("resume_assertions.exs")},
      {Ipse.Development.Evaluation.Metrics, source("metrics.exs")},
      {Ipse.Development.Evaluation.DecisionMetrics, source("decision_metrics.exs")},
      {Ipse.Development.Evaluation.SelectionExperiment, source("selection_experiment.exs")},
      {Ipse.Development.Evaluation.ProtectedAnswer, source("protected_answer.exs")},
      {Ipse.Test.PairedProtectedAnswerSession, Path.join(@base, "paired_session.exs")}
    ]

    helper_files = compile!(helper_sources, Path.join(out, "helper-ebin"))

    {:ok, reference_sha} =
      apply(Ipse.Development.Evaluation.SelectionExperiment, :commit_references, [
        File.read!(d["references"])
      ])

    true = reference_sha === d["reference_sha256"]
    artifact_root = Path.dirname(d["artifact"])
    {:ok, artifact} = Ipse.Extension.Artifact.lookup(artifact_root, Path.basename(d["artifact"]))
    true = artifact.digest === d["artifact_sha256"]
    true = Ipse.Extension.Artifact.compatible?(artifact.manifest)

    :ok =
      Ipse.Extension.Catalog.validate(
        artifact.manifest["exports"],
        artifact.manifest["capabilities"]
      )

    :non_existing = :code.which(Ipse.Test.PairedAnswerExtension)
    true = inventories(d) === before
    nil = Process.whereis(Ipse.Supervisor)
    false = Enum.any?(Application.started_applications(), &(elem(&1, 0) === :ipse))
    true = MapSet.new(Port.list()) === ports

    helper_inventory =
      Enum.map_join(helper_files, "", fn file ->
        JSON.sha256(File.read!(file)) <> "  " <> file <> "\n"
      end)

    save(out, "helpers.sha256", helper_inventory)

    verification_inventory =
      Path.wildcard(Path.join(out, "verification-ebin/*.beam"))
      |> Enum.map_join("", fn file -> JSON.sha256(File.read!(file)) <> "  " <> file <> "\n" end)

    save(out, "verification.sha256", verification_inventory)

    compiled =
      d
      |> Map.put("prepared", true)
      |> Map.put("helper_inventory_sha256", JSON.sha256(helper_inventory))
      |> Map.put("verification_inventory_sha256", JSON.sha256(verification_inventory))
      |> Map.put("before_sha256", JSON.sha256(File.read!(Path.join(out, "before.term"))))

    save(out, "descriptor.review-false.json", Jason.encode!(compiled) <> "\n")

    save(
      out,
      "result.json",
      Jason.encode!(%{
        status: "passed",
        helper_modules: 7,
        verification_modules: 2,
        diagnostics: 0,
        package_unchanged: true,
        ex_unit_unchanged: true,
        artifact_unchanged: true,
        app_started: false,
        ports_unchanged: true,
        actor_released: false,
        retained_access: false
      }) <> "\n"
    )

    IO.puts("PACKAGED_PAIRED_PREPARATION_PASSED")
  end

  def inventories(d),
    do: Map.new(~w(package ex_unit artifact), &{&1, apply(Inventory, :inventory, [d[&1]])})

  def origins!(d) do
    :ok =
      case Application.load(:ipse) do
        :ok -> :ok
        {:error, {:already_loaded, :ipse}} -> :ok
      end

    for module <- Application.spec(:ipse, :modules) do
      true =
        to_string(:code.which(module)) ===
          Path.join([d["package"], "lib/ipse-0.1.0/ebin", Atom.to_string(module) <> ".beam"])
    end

    :ok
  end

  defp compile!(sources, output) do
    {files, diagnostics} =
      Code.with_diagnostics(fn ->
        Enum.map(sources, fn {module, file} ->
          ast = Code.string_to_quoted!(File.read!(file), file: file)

          nodes =
            case ast do
              {:__block__, _, nodes} -> nodes
              node -> [node]
            end

          [definition] =
            Enum.filter(nodes, fn
              {:defmodule, _, [{:__aliases__, _, parts}, _]} -> Module.concat(parts) === module
              _ -> false
            end)

          definition =
            if module === Inventory, do: inventory_definition!(definition), else: definition

          [{^module, beam}] = Code.compile_quoted(definition, file)
          target = Path.join(output, Atom.to_string(module) <> ".beam")
          save(output, Path.basename(target), beam)
          target
        end)
      end)

    [] = diagnostics
    true = Code.prepend_path(output)

    for {module, _} <- sources do
      :code.purge(module)
      true = :code.delete(module)
      {:module, ^module} = Code.ensure_loaded(module)

      true =
        to_string(:code.which(module)) === Path.join(output, Atom.to_string(module) <> ".beam")
    end

    files
  end

  defp inventory_definition!({:defmodule, meta, [name, [do: body]]}) do
    nodes =
      case body do
        {:__block__, _, nodes} -> nodes
        node -> [node]
      end

    names = [:inventory, :walk, :digest, :identity]
    functions = Enum.filter(nodes, &(function_name(&1) in names))

    true =
      Enum.frequencies(Enum.map(functions, &function_name/1)) ===
        %{inventory: 1, walk: 1, digest: 1, identity: 1}

    {:defmodule, meta, [name, [do: {:__block__, [], functions}]]}
  end

  defp function_name({kind, _, [{name, _, _}, _]}) when kind in [:def, :defp], do: name
  defp function_name(_), do: nil

  defp source(name), do: Path.join([@base, "sources", name])

  defp save(dir, name, bytes) do
    file = Path.join(dir, name)
    File.write!(file, bytes, [:exclusive, :sync])
    File.chmod!(file, 0o600)
  end
end
