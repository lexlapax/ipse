defmodule Ipse.Test.PairedOwnerCompileCheck do
  @moduledoc false
  @base Path.dirname(__ENV__.file)
  @sdk "/home/lexlapax/projects/lexlapax/ipse/_build/verification/retained-final-runtime-d548-20261105-02/source"
  @prior "/home/lexlapax/projects/lexlapax/ipse/_build/verification/p30-paired-protected-workflow-20261105-02"
  @evidence Path.join(@base, "owner-compile-01")
  alias Ipse.JSON

  def check("qualify") do
    absent_app!()
    ports = MapSet.new(Port.list())
    verify_manifests!()
    origins = origins!()
    before = snapshot!()
    historical = Path.join([@prior, "qualification-02", "sdk-before.term"]) |> File.read!() |> :erlang.binary_to_term([:safe])
    true = before === historical
    File.write!(Path.join(@evidence, "sdk-before.term"), :erlang.term_to_binary(before), [:exclusive, :sync])
    File.chmod!(Path.join(@evidence, "sdk-before.term"), 0o600)
    prior = Path.join([@prior, "qualification-02", "qualification-result.json"]) |> File.read!() |> Jason.decode!()
    true = prior["status"] === "passed"
    reused = Enum.reject(prior["helper_files"], &String.ends_with?(&1["path"], "/Elixir.Ipse.Test.PairedProtectedAnswerSession.beam"))
    6 = length(reused)
    6 = length(File.ls!(Path.join(@base, "helper-ebin")))
    for ref <- reused do
      path = Path.join([@base, "helper-ebin", Path.basename(ref["path"])])
      true = sha(File.read!(path)) === ref["sha256"] and File.read!(path) === File.read!(ref["path"])
    end
    true = Code.prepend_path(Path.join(@base, "helper-ebin"))
    for ref <- reused do
      path = Path.join([@base, "helper-ebin", Path.basename(ref["path"])])
      module = path |> Path.basename(".beam") |> String.to_atom()
      {:module, ^module} = Code.ensure_loaded(module)
      ^path = to_string(:code.which(module))
    end
    owner = Ipse.Test.PairedProtectedAnswerSession
    owner_path = Path.join(@base, "paired_session.exs")
    {:defmodule, _, _} = ast = Code.string_to_quoted!(File.read!(owner_path), file: owner_path)
    {compiled_owner, diagnostics} = Code.with_diagnostics(fn -> Code.compile_quoted(ast, owner_path) end)
    save("owner-diagnostics.json", Enum.map(diagnostics, fn row -> %{severity: row.severity, file: row.file, position: inspect(row.position), message: row.message} end))
    [] = diagnostics
    [{^owner, owner_beam}] = compiled_owner
    File.write!(Path.join([@base, "helper-ebin", Atom.to_string(owner) <> ".beam"]), owner_beam, [:exclusive, :sync])
    :code.purge(owner)
    true = :code.delete(owner)

    sources = [
      {Ipse.Test.ProviderFixture, Path.join(@sdk, "test/support/provider_fixture.ex")},
      {Ipse.Test.ResumeAssertions, Path.join(@sdk, "test/support/resume_assertions.exs")},
      {Ipse.Development.Evaluation.Metrics, candidate("metrics.exs")},
      {Ipse.Development.Evaluation.DecisionMetrics, candidate("decision_metrics.exs")},
      {Ipse.Development.Evaluation.SelectionExperiment, candidate("selection_experiment.exs")},
      {Ipse.Development.Evaluation.ProtectedAnswer, candidate("protected_answer.exs")},
      {Ipse.Test.PairedProtectedAnswerSession, Path.join(@base, "paired_session.exs")}
    ]
    compiled = Enum.map(sources, fn {module, source} ->
      expected = Path.join([@base, "helper-ebin", Atom.to_string(module) <> ".beam"])
      {:module, ^module} = Code.ensure_loaded(module)
      ^expected = to_string(:code.which(module))
      true = to_string(Keyword.fetch!(module.module_info(:compile), :source)) === source
      {^module, object, object_path} = :code.get_object_code(module)
      true = to_string(object_path) === expected and object === File.read!(expected)
      info = File.lstat!(expected)
      true = info.type === :regular and info.links === 1 and Bitwise.band(info.mode, 0o777) === 0o600
      {module, expected}
    end)
    7 = length(compiled)
    true = Enum.sort(File.ls!(Path.join(@base, "helper-ebin"))) === Enum.sort(Enum.map(compiled, fn {_module, path} -> Path.basename(path) end))
    :non_existing = :code.which(Ipse.Test.PairedAnswerExtension)
    digest = "3972c9bf87fd9cb9998d0b63e729972bce04c4b7f193ae1660a96610799db92e"
    artifact_root = Path.join(@prior, "artifacts")
    artifact_path = Path.join(artifact_root, digest)
    {:ok, manifest} = artifact_path |> Path.join("extension.json") |> File.read!() |> Ipse.Extension.Artifact.decode()
    :ok = Ipse.Extension.Catalog.validate(manifest["exports"], manifest["capabilities"])
    true = Ipse.Extension.Artifact.compatible?(manifest)
    expected_files = Enum.sort(["extension.json" | Enum.map(manifest["files"], & &1["path"])])
    ^expected_files = for {path, :regular} <- leaves(artifact_path), do: path
    true = Enum.all?(leaves(artifact_path), fn {path, :regular} ->
      info = File.lstat!(Path.join(artifact_path, path))
      info.links === 1 and Bitwise.band(info.mode, 0o777) === 0o600
    end)
    {:ok, artifact} = Ipse.Extension.Artifact.lookup(artifact_root, digest)
    :non_existing = :code.which(Ipse.Test.PairedAnswerExtension)
    false = Enum.any?(:code.get_path(), fn path ->
      path = to_string(path)
      path === artifact_root or String.starts_with?(path, artifact_root <> "/")
    end)

    refs = Enum.map(compiled, fn {_module, path} ->
      %{path: path, bytes: File.stat!(path).size, sha256: sha(File.read!(path))}
    end)
    inventory = Enum.map_join(refs, "", &(&1.sha256 <> "  " <> Path.relative_to(&1.path, @base) <> "\n"))
    File.write!(Path.join(@base, "helper-inventory.sha256"), inventory, [:exclusive, :sync])
    absent_app!()
    true = MapSet.new(Port.list()) === ports
    true = origins!() === origins
    true = snapshot!() === before
    save("owner-qualification-result.json", %{status: "passed", artifact_origin: "02_qualified_unchanged",
      sdk_rebuilt: false, artifact_rebuilt: false, compiled_owner_modules: 1, reused_helpers: 6,
      helper_modules: 7, helper_diagnostics: 0,
      builder_diagnostics: 0, artifact_compile_diagnostics: 0, artifact_manifest_valid: true,
      artifact_closed_files: length(expected_files), artifact_path: artifact_path,
      artifact_manifest_sha256: artifact.digest, artifact_never_loaded_in_host: true,
      helper_inventory_sha256: sha(inventory), helper_files: refs, sdk_apps: 16, ipse_modules: 241,
      sdk_leaves_sha256: sha(:erlang.term_to_binary(before.leaves, [:deterministic])),
      sdk_links_sha256: JSON.digest(before.links), source_and_scm_unchanged: true,
      app_started: false, ports_unchanged: true, retained_access: false, actor_released: false})
  end

  def check("post") do
    absent_app!()
    verify_manifests!()
    origins!()
    path = Path.join(@evidence, "sdk-before.term")
    if File.regular?(path) do
      before = path |> File.read!() |> :erlang.binary_to_term([:safe])
      after_build = snapshot!()
      equal = after_build === before
      save(post_name(), %{status: if(equal, do: "passed", else: "failed"), exact: equal,
        source_runtime_dependencies_scm_paths_links: equal, app_started: false, retained_access: false})
      true = equal
    else
      save(post_name(), %{status: "unverified_preimage_missing", app_started: false, retained_access: false})
      raise "inert SDK preimage unavailable"
    end
  end

  defp candidate(name), do: Path.join([@prior, "candidate/dev/evaluation", name])
  defp post_name, do: if(System.get_env("IPSE_PAIRED_MANUAL_POST") === "1", do: "sdk-post-manual.json", else: "sdk-post.json")
  defp absent_app! do
    nil = Process.whereis(Ipse.Supervisor)
    false = Enum.any?(Application.started_applications(), &(elem(&1, 0) === :ipse))
    :non_existing = :code.which(Ipse.Test.PairedAnswerExtension)
  end
  defp origins! do
    ebins = Path.wildcard(Path.join(@sdk, "_build/test/lib/*/ebin"))
    16 = length(ebins)
    Enum.map(ebins, fn ebin ->
      [app_path] = Path.wildcard(Path.join(ebin, "*.app"))
      {:ok, [{:application, app, settings}]} = :file.consult(app_path)
      modules = Keyword.fetch!(settings, :modules)
      if app === :ipse, do: 241 = length(modules)
      for module <- modules do
        expected = Path.join(ebin, Atom.to_string(module) <> ".beam")
        ^expected = to_string(:code.which(module))
      end
      {app, ebin, length(modules)}
    end)
  end
  defp verify_manifests! do
    for name <- ~w(source.sha256 runtime.sha256 dependencies.sha256) do
      path = Path.join([Path.dirname(@sdk), "evidence", name])
      {"", 0} = System.cmd("sha256sum", ["--check", "--status", path], cd: @sdk, stderr_to_stdout: true)
    end
  end
  defp snapshot! do
    all = leaves(@sdk)
    links = for {path, :symlink} <- all do
      {resolved, 0} = System.cmd("realpath", ["-e", Path.join(@sdk, path)])
      true = String.starts_with?(String.trim(resolved), @sdk <> "/")
      [path, File.read_link!(Path.join(@sdk, path))]
    end
    scm = for {path, type} <- all, ".git" in Path.split(path), into: %{} do
      true = type === :regular
      info = File.lstat!(Path.join(@sdk, path), time: :posix)
      1 = info.links
      {path, {sha(File.read!(Path.join(@sdk, path))), info.size, info.mode, info.inode, info.major_device, info.mtime, info.ctime}}
    end
    %{type: :regular} = File.lstat!(Path.join(@sdk, ".git/index"))
    {:error, :enoent} = File.lstat(Path.join(@sdk, "deps/jason/.git/index"))
    for git <- [".git", "deps/jason/.git"], do: {:error, :enoent} = File.lstat(Path.join([@sdk, git, "objects/info/alternates"]))
    %{leaves: all, links: links, scm: scm}
  end
  defp leaves(root, relative \\ "") do
    path = Path.join(root, relative)
    case File.lstat!(path).type do
      :directory -> File.ls!(path) |> Enum.sort() |> Enum.flat_map(&leaves(root, Path.join(relative, &1)))
      type -> [{relative, type}]
    end
  end
  defp sha(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  defp save(name, value), do: File.write!(Path.join(@evidence, name), Jason.encode!(value) <> "\n", [:exclusive, :sync])
end
[phase] = System.argv()
Ipse.Test.PairedOwnerCompileCheck.check(phase)
