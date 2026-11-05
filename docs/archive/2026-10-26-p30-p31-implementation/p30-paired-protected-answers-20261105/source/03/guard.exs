defmodule Ipse.Test.PairedProtectedAnswerGuard do
  @moduledoc false
  @base Path.dirname(__ENV__.file)
  @outer "/home/lexlapax/projects/lexlapax/ipse/_build/verification/retained-final-runtime-d548-20261105-02"
  @sdk Path.join(@outer, "source")
  defp sha(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  # Same typed leaf inventory as the published phased guard, not find rendering.
  def leaves(root, relative \\ "") do
    path = Path.join(root, relative)
    case File.lstat!(path).type do
      :directory -> File.ls!(path) |> Enum.sort() |> Enum.flat_map(&leaves(root, Path.join(relative, &1)))
      type -> [{relative, type}]
    end
  end
  def check(phase, descriptor, digest) do
    true = sha(File.read!(descriptor)) === digest
    d = Jason.decode!(File.read!(descriptor))
    true = d["kind"] === "paired_protected_answer_protocol_v1"
    true = phase === "preflight" or d["reviewed"] === true
    for reference <- d["files"] do
      true = File.stat!(reference["path"]).size === reference["bytes"]
      true = sha(File.read!(reference["path"])) === reference["sha256"]
    end
    inventory = Path.join(@base, "helper-inventory.sha256")
    true = sha(File.read!(inventory)) === d["compiled_helper_inventory_sha256"]
    {"", 0} = System.cmd("sha256sum", ["--check", "--status", inventory], cd: @base, stderr_to_stdout: true)
    declared_helpers = for ref <- d["files"], String.starts_with?(ref["path"], Path.join(@base, "helper-ebin") <> "/"),
      do: Path.basename(ref["path"])
    true = Enum.sort(File.ls!(Path.join(@base, "helper-ebin"))) === Enum.sort(declared_helpers)
    for {name, expected} <- [{"source.sha256", d["sdk_source_manifest_sha256"]},
      {"runtime.sha256", d["sdk_runtime_manifest_sha256"]}] do
      path = Path.join([@outer, "evidence", name])
      true = sha(File.read!(path)) === expected
      {"", 0} = System.cmd("sha256sum", ["--check", "--status", path], cd: @sdk, stderr_to_stdout: true)
    end
    all = leaves(@sdk)
    true = sha(:erlang.term_to_binary(all, [:deterministic])) === d["sdk_leaves_sha256"]
    links = for {path, :symlink} <- all, do: [path, File.read_link!(Path.join(@sdk, path))]
    true = Ipse.JSON.digest(links) === d["sdk_links_sha256"]
    for {path, :symlink} <- all do
      {resolved, 0} = System.cmd("realpath", ["-e", Path.join(@sdk, path)])
      true = String.starts_with?(String.trim(resolved), @sdk <> "/")
    end
    for {path, :regular} <- all, do: %{links: 1} = File.lstat!(Path.join(@sdk, path))
    16 = length(Path.wildcard(Path.join(@sdk, "_build/test/lib/*/ebin")))
    :ok = Application.load(:ipse)
    241 = length(Application.spec(:ipse, :modules))
    for module <- Application.spec(:ipse, :modules) do
      expected = Path.join([@sdk, "_build/test/lib/ipse/ebin", Atom.to_string(module) <> ".beam"])
      ^expected = to_string(:code.which(module))
    end
    for module <- [Ipse.Test.ProviderFixture, Ipse.Test.ResumeAssertions,
      Ipse.Development.Evaluation.Metrics, Ipse.Development.Evaluation.DecisionMetrics,
      Ipse.Development.Evaluation.SelectionExperiment, Ipse.Development.Evaluation.ProtectedAnswer,
      Ipse.Test.PairedProtectedAnswerSession] do
      {:module, ^module} = Code.ensure_loaded(module)
      expected = Path.join([@base, "helper-ebin", Atom.to_string(module) <> ".beam"])
      ^expected = to_string(:code.which(module))
    end
    :non_existing = :code.which(Ipse.Test.PairedAnswerExtension)
    false = Enum.any?(Application.started_applications(), &(elem(&1, 0) === :ipse))
    File.write!(Path.join([@base, "evidence", "guard-#{phase}.json"]), Jason.encode!(%{status: "passed", app_started: false}))
  end
end
[phase, descriptor, digest] = System.argv()
Ipse.Test.PairedProtectedAnswerGuard.check(phase, descriptor, digest)
