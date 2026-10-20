# Pure declaration owner reviews

Historical scoped review records, 2026-10-20, against base `2c72b69`. Original report prose is retained below with headings nested one level. Original hashes and verification are in [the receipt](contract-verification.json). Current guidance: [knowledge evaluation training](../../developer/knowledge-evaluation.md). Scope and remaining work: [implementation record](index.md#give-evaluation-declarations-a-pure-owner) and [plan](../../plan.md#p27-optional-research-graph-and-rag). Neither report claims runtime execution or P27 acceptance.

## Review a

### Findings

No findings.

### Reviewed scope

Reviewed the entire current S07 working diff against HEAD, base commit `2c72b69`, and the complete new `dev/evaluation/contract.exs`. This includes all 16 tracked changed paths, the deleted Plan implementation, every changed caller/test/formatter entry, Runner's remaining consumers and error boundary, Freeze's projection/resolution and generic-v1 boundaries, and measured source/installed launch paths. Read the complete selected design and independent judgment.

Read all 1,742 lines of `docs/developer/knowledge-evaluation.md`, including the unchanged procedures surrounding the new declaration section. Its changed ownership, API, example, and full-versus-shape explanation agree with the implementation. The chapter continues to distinguish historical v1 behavior, measured v2 execution, synthetic evidence and held-out quality. The worked declaration exercise correctly uses the public template and `iex -S mix`; execution exercises explicitly load Runner.

### Evidence and checks

- Ran a bounded source-only Elixir AST comparison in `/tmp/ipse-p27-review-a-probe.exs`. All 11 moved Plan function clauses and 13 moved Runner function clauses match, after removing source metadata, replacing the private throw tag, resolving the plan-fields attribute to the historical field list, and replacing the old remote validation call with its new local owner. This includes full admission, model-origin interpretation, variant semantics and selected-command lookup. Inspected the private require/fail helper bodies separately; their direct throw and former fail indirection have the same effect.
- Traced each remaining Runner preflight caller back to complete declaration validation. The new `Map.keys(variant["bindings"])` requirement therefore follows the already-validated exact verb set. Session's binding validation remains the executable catalog check.
- Inspected Freeze's former shape checks alongside both new shape clauses. Closed execution/portable keys, versions, profile-map restrictions and public error translation remain the same. Generic version-one `create/4` does not acquire full benchmark admission.
- Searched active source, scripts, tests and documentation for deleted Plan paths, old module references and `Runner.validate` calls; no missed active callers were found. Historical archive records are outside this caller-migration requirement.
- Checked explicit Contract loading from Runner, Freeze, measured execution and the pure preparation script. Source/installed measured verification helpers now load Runner explicitly. Measured source admission includes the real Contract path and digest.
- Ran `git diff --check`; it passed.

No ExUnit suite, build, full test run, service/model operation, private corpus/question/gold input or evaluation report was run or opened. The AST probe checks extraction equivalence and does not establish runtime or installed execution success. The task owner's reported 8,738-outcome oracle and focused-test status were treated as context, not independently reproduced evidence.


## Review b

## S07 contract consolidation — reviewer B

### Findings

No findings.

### Scope and evidence

Reviewed the full current working-tree diff against `2c72b69`, including `.formatter.exs`, both changed evaluator modules, the deleted `evaluation_plan.exs`, all four changed scripts, all changed tests and support code, and the complete new `dev/evaluation/contract.exs` (725 lines). Compared the moved build recipe and full validation against the old Plan and Runner source, and compared Freeze's former execution and portable shape predicates with `EvaluationContract.validate_shape/2`. Traced `Runner.checked/1`, both preflight and cell `required_verbs` uses, measured source-file admission, source and installed verifier loads, and repository-wide live call sites. The remaining Plan/Runner.validate references are in dated historical archive scripts that target their historical source.

The new Contract owns the five intended result-returning operations. Runner translates Contract errors into its existing error domain; Freeze maps the shape result to its existing `invalid_plan`/`invalid_experiment` errors. The use of `Map.keys(variant["bindings"])` in Runner follows complete Contract validation, whose `required_verbs` check makes those keys exact. No retained forwarding Plan or Runner.validate wrapper, missed live caller, or producer-domain load was found in the reviewed source.

Read `docs/developer/knowledge-evaluation.md` in full (1,742 lines), not only its diff. The new declaration exercise matches the v1 public template and the source API, distinguishes complete admission from Freeze's shape checks, and describes the correct execution load. The surrounding chapter remains a coherent training path; I found no contradictory path, API, or full-versus-shape claim introduced by S07.

This was source-only review. I ran no tests, builds, service/model calls, or private-workload checks; the reported 8,738-case oracle and ongoing focused tests in the task brief are independent evidence, not tests I ran. I made no repository changes.

