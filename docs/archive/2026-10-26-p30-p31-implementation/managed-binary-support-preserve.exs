alias Ipse.JSON
root=File.cwd!()
base="/tmp/ipse-managed-binary-proof-20261026-01"
archive=Path.join(root,"docs/archive/2026-10-26-p30-p31-implementation")
sha=fn p->JSON.sha256(File.read!(p))end
item=fn p->%{path: Path.relative_to(p,root),bytes: File.stat!(p).size,sha256: sha.(p)}end
copy=fn source,name->target=Path.join(archive,"managed-binary-"<>name);File.cp!(source,target);item.(target)end
sources=Path.wildcard("dev/knowledge/managed_metadata_binary*.*")++["test/dev/managed_metadata_binary_test.exs"]
first=for p<-Path.wildcard(Path.join(base,"final/pages-*.*"))++[Path.join(base,"final/measurements-joined.json"),Path.join(base,"final/measurements-joined.log")],do: copy.(p,"first-"<>Path.basename(p))
bound=for p<-Path.wildcard(Path.join(base,"bound/*.*")),do: copy.(p,"bound-"<>Path.basename(p))
controls=for name<-~w(calculation-first.json calculation-first.log calculation-current.json calculation-current.log compile-first.log compile-repaired.log compile-clean.log tests-first.log tests-second.log tests-repaired.log tests-expanded.log tests-calendar-final.log pages-candidate-safe-target.log pages-candidate-safe-target.json measurements-join-failed.log),do: copy.(Path.join(base,name),"preliminary-"<>name)
support=for name<-~w(freeze.exs join-bound.exs preserve.exs),do: copy.(Path.join(base,name),"support-"<>name)
design="/tmp/ipse-native-management-capsule-design-20261026/design.md"
true=sha.(design)=="3e9384b9457ea749481e429517bad728d165f6912b8b0a257748f9c8374ece03"
design_copy=copy.(design,"native-choice-design.md")
runtime=Path.join(archive,"managed-continuation-runtime.json")
beams=Path.wildcard(Path.join(base,"ebin/*.beam"))|>Enum.map(item)
report=%{kind: "pure_binary_metadata_proof_artifacts",qualification_passed: false,actual_publications: 0,native_helper_calls: 0,model_calls: 0,
  sources: Enum.map(sources,&item.(Path.join(root,&1))), prototype_beams: beams,dependency_runtime_manifest: item.(runtime),
  artifacts: first++bound++controls++support++[design_copy],
  frozen_dependency_before_after: "bound-freeze-before.json and bound-freeze-after.json:560BEAM/126source/helper verified; no helper invoked",
  measurement_jobs: 24,joined_cases: 72,first_and_bound_page_results_identical: true,
  resource_limits: %{per_job_watchdog_ms: 30000,sampled_BEAM_bytes: 536870912,main_heap_words: 16000000},
  data_disposition: "Conditional declared shape fit only; lifecycle/authenticity/import/MAC/nativeallocation/year remain open. Active4kseries remainsfailed3724; no product change."}
File.write!(Path.join(archive,"managed-binary-proof-artifacts.json"),Jason.encode!(report,pretty: true)<>"\n")
IO.puts("Preserved #{length(report.artifacts)} artifacts; #{length(report.sources)} owned source/test files; all actual publication/native/model counts0")
