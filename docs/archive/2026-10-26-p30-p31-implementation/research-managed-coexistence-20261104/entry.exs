cohort = __DIR__
evidence = Path.join(cohort, "execution-01")
File.write!(Path.join(evidence, "beam.pid"), System.pid() <> "\n", [:exclusive])
"1" = System.fetch_env!("IPSE_TEST_RESEARCH_MIXED")
:ok = Application.load(:ipse)
runtime = Path.expand("../cohort-01/runtime/lib", cohort)
true = Application.app_dir(:ipse) == Path.join(runtime, "ipse")
241 = length(Application.spec(:ipse, :modules))
for module <- Application.spec(:ipse, :modules) do
  {:module, ^module} = Code.ensure_loaded(module)
  true = String.starts_with?(to_string(:code.which(module)), Path.join(runtime, "ipse/ebin/"))
end
true = to_string(:code.priv_dir(:ipse)) == Path.join(runtime, "ipse/priv")
%{type: :regular, links: 1} = File.lstat!(Path.join(runtime, "ipse/priv/ipse-runner"))
{:ok, bundles} = Ipse.Extension.Bundles.inventory()
4 = length(bundles)
false = Code.ensure_loaded?(IpseKnowledge.Research)
ExUnit.start(autorun: false, max_cases: 1, seed: 0)
ExUnit.configure(include: [mixed_h1_coexistence: true], exclude: [:test])
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file(Path.join(cohort, "source/test/extensions/knowledge/research_transfer_test.exs"))
result = ExUnit.run()
File.write!(Path.join(evidence, "result.json"), Jason.encode!(result), [:exclusive, :sync])
roots = Path.wildcard(Path.join(System.tmp_dir!(), "ipse-research-transfer-*"))
File.write!(Path.join(evidence, "fixture-roots.txt"), Enum.join(roots, "\n") <> "\n", [:exclusive])
artifacts = for root <- roots, artifact = Path.join(root, "artifact"), File.regular?(Path.join(artifact, "extension.json")) do
  bytes = File.read!(Path.join(artifact, "extension.json"))
  {:ok, _} = Ipse.Extension.Artifact.decode(bytes)
  manifest = Jason.decode!(bytes)
  for file <- manifest["files"] do
    data = File.read!(Path.join(artifact, file["path"]))
    true = byte_size(data) == file["bytes"] and Ipse.JSON.sha256(data) == file["sha256"]
  end
  %{manifest_sha256: Ipse.JSON.sha256(bytes), manifest_bytes: byte_size(bytes), declared_files: length(manifest["files"]), bytes_match_manifest: true}
end
File.write!(Path.join(evidence, "artifacts-safe.json"), Jason.encode!(artifacts), [:exclusive])
System.halt(if result == %{total: 3, failures: 0, skipped: 0, excluded: 2}, do: 0, else: 2)
