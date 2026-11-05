defmodule Ipse.Test.SelectionAssessmentPhasedGuard do
  @packet Path.dirname(__ENV__.file)
  @base Path.dirname(@packet)
  @source "/home/lexlapax/projects/lexlapax/ipse/_build/verification/p30-selection-assessment-phased-20261105-02/sdk/source"
  def sha(path), do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)

  def leaves(root, rel \\ "") do
    path = Path.join(root, rel)

    case File.lstat!(path).type do
      :directory ->
        File.ls!(path) |> Enum.sort() |> Enum.flat_map(&leaves(root, Path.join(rel, &1)))

      kind ->
        [{rel, kind}]
    end
  end

  def check(phase, descriptor, digest) do
    true = sha(descriptor) === digest
    d = :json.decode(File.read!(descriptor))
    true = d["kind"] === "selection_assessment_phased_v1"
    true = phase in ["preflight", "preflight-beforeclaim"] or d["reviewed"] === true
    true = d["phases"] === ["assessment"]
    true = d["existing_cohort"] === "/dev/shm/ipse-selection-assessment-phased-20261105-03/actor"

    if phase in ["pre", "preflight"] do
      true = sha(d["control_path"]) === d["control_before_sha256"]
    end

    for ref <- d["files"] do
      true = File.stat!(ref["path"]).size === ref["bytes"]
      true = sha(ref["path"]) === ref["sha256"]
    end

    {"", 0} =
      System.cmd(
        "sha256sum",
        [
          "--check",
          "--status",
          "/home/lexlapax/projects/lexlapax/ipse/_build/verification/p30-selection-assessment-phased-20261105-02/build-evidence/final-sdk.sha256"
        ],
        cd: @source,
        stderr_to_stdout: true
      )

    all = leaves(@source)
    expected = d["sdk_pathset_sha256"]

    ^expected =
      :crypto.hash(:sha256, :erlang.term_to_binary(all, [:deterministic]))
      |> Base.encode16(case: :lower)

    for {p, :symlink} <- all do
      {resolved, 0} = System.cmd("realpath", ["-e", Path.join(@source, p)])
      true = String.starts_with?(String.trim(resolved), @source <> "/")
    end

    actual_links =
      for {p, :symlink} <- all, do: p <> " -> " <> File.read_link!(Path.join(@source, p)) <> "\n"

    true =
      IO.iodata_to_binary(actual_links) ===
        File.read!(
          "/home/lexlapax/projects/lexlapax/ipse/_build/verification/p30-selection-assessment-phased-20261105-02/build-evidence/final-sdk.links"
        )

    for {p, :regular} <- all, do: %{links: 1} = File.lstat!(Path.join(@source, p))
    :ok = Application.load(:ipse)
    241 = length(Application.spec(:ipse, :modules))

    for m <- Application.spec(:ipse, :modules) do
      expected = Path.join([@source, "_build/test/lib/ipse/ebin", Atom.to_string(m) <> ".beam"])
      ^expected = :code.which(m) |> to_string()
    end

    ebin = Path.join(@source, "_build/test/lib/ipse/ebin")
    ^ebin = Application.app_dir(:ipse, "ebin")

    for module <- [
          Ipse.Test.ProviderFixture,
          Ipse.Test.SelectionAssessmentPhased
        ] do
      {:module, ^module} = Code.ensure_loaded(module)
      expected = Path.join([@base, "helper-ebin", Atom.to_string(module) <> ".beam"])
      ^expected = :code.which(module) |> to_string()
    end

    nil = Process.whereis(Ipse.Supervisor)
    false = :ipse in Enum.map(Application.started_applications(), &elem(&1, 0))

    File.write!(
      Path.join(@packet, "evidence/guard-" <> phase <> ".json"),
      :json.encode(%{phase: phase, status: "passed", app_started: false}),
      [:exclusive]
    )
  end
end

[phase, descriptor, digest] = System.argv()
Ipse.Test.SelectionAssessmentPhasedGuard.check(phase, descriptor, digest)
