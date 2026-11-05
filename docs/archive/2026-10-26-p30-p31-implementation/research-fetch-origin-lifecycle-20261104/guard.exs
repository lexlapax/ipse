defmodule Ipse.Test.ResearchOriginClosure do
  @base Path.expand(__DIR__)
  @sdk Path.expand("../consent-knowledge-research-sdk-18e3-20261104-02", __DIR__)
  def sha(path), do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)

  def leaves(root, rel \\ "") do
    path = Path.join(root, rel)

    case File.lstat!(path).type do
      :directory ->
        File.ls!(path)
        |> Enum.reject(&(&1 == ".git"))
        |> Enum.sort()
        |> Enum.flat_map(&leaves(root, Path.join(rel, &1)))

      type when type in [:regular, :symlink] ->
        [{rel, type}]
    end
  end

  def check(phase, path, digest) do
    true = sha(path) == digest
    d = :json.decode(File.read!(path))
    true = d["kind"] == "research_origin_coherent_sdk_v1"
    true = phase == "preflight" or d["reviewed"] === true

    for ref <- d["files"] do
      true = File.stat!(ref["path"]).size === ref["bytes"]
      true = sha(ref["path"]) == ref["sha256"]
    end

    for {manifest, cwd} <- [
          {@sdk <> "/evidence/candidate-source.sha256", @sdk <> "/source"},
          {@sdk <> "/closure-supplement-02/runtime.sha256", @sdk <> "/source"},
          {@sdk <> "/closure-supplement-02/explicit-artifacts.sha256",
           @sdk <> "/candidate-artifacts"}
        ] do
      {"", 0} =
        System.cmd("/usr/bin/sha256sum", ["--check", "--status", manifest],
          cd: cwd,
          stderr_to_stdout: true
        )
    end

    for {root, parts, manifest, links} <- [
          {@sdk <> "/source", ~w(_build/test/lib priv deps), "runtime-pathset.txt",
           "runtime.links"},
          {@sdk <> "/candidate-artifacts", ["research-state-fetched", "corpus-state-documents"],
           "explicit-artifacts-pathset.txt", "explicit-artifacts.links"}
        ] do
      all = Enum.flat_map(parts, &leaves(root, &1)) |> Enum.sort()
      actual = Enum.map_join(all, "", fn {p, t} -> Atom.to_string(t) <> "\t" <> p <> "\n" end)
      ^actual = File.read!(@sdk <> "/closure-supplement-02/" <> manifest)

      raw =
        Enum.flat_map(all, fn {p, t} ->
          if t == :symlink do
            {real, 0} = System.cmd("/usr/bin/realpath", ["-e", "--", Path.join(root, p)])
            true = String.starts_with?(String.trim(real), root <> "/")
            [p <> " -> " <> File.read_link!(Path.join(root, p)) <> "\n"]
          else
            %{links: 1} = File.lstat!(Path.join(root, p))
            []
          end
        end)
        |> IO.iodata_to_binary()

      ^raw = File.read!(@sdk <> "/closure-supplement-02/" <> links)
    end

    :ok = Application.load(:ipse)
    true = length(Application.spec(:ipse, :modules)) === 241
    true = to_string(Application.app_dir(:ipse)) == @sdk <> "/source/_build/test/lib/ipse"

    for module <- Application.spec(:ipse, :modules) do
      true =
        Path.dirname(to_string(:code.which(module))) ==
          @sdk <> "/source/_build/test/lib/ipse/ebin"
    end

    true = Path.dirname(to_string(:code.which(Ipse.Extension.Bootstrap))) == d["host_ebin"]
    true = Process.whereis(Ipse.Supervisor) == nil
    false = Code.ensure_loaded?(IpseKnowledge.Research)
    false = Code.ensure_loaded?(IpseKnowledge.Corpus)

    for name <- ~w(research corpus) do
      artifact = d[name]

      {:ok, _manifest} =
        Ipse.Extension.Artifact.decode(File.read!(artifact["root"] <> "/extension.json"))

      true = sha(artifact["root"] <> "/extension.json") == artifact["digest"]
    end

    result = %{
      phase: phase,
      source_runtime_artifacts_helpers: "passed",
      modules: 241,
      applications: 16,
      app_started: false
    }

    File.write!(@base <> "/evidence/guard-" <> phase <> ".json", :json.encode(result), [
      :exclusive
    ])

    IO.puts("research_closure=" <> phase <> " pass")
  end
end

[phase, descriptor, digest] = System.argv()
Ipse.Test.ResearchOriginClosure.check(phase, descriptor, digest)
