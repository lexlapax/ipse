# Structured evaluation and qualification reviews

Historical scoped review records, 2026-10-20, against base `3310605` and the new
plan-three evaluator draft. Current procedures belong to the
[evaluation training manual](../../developer/knowledge-evaluation.md).
[Verification](evaluator-verification.json) binds source, original report hashes,
platform checks and limits. The [plan](../../plan.md#p27-optional-research-graph-and-rag)
owns acceptance. These reviews do not establish whole-P27 completion.

## Lead disposition

Both runtime reviewers found the same policy inconsistency in accepted saved
failed retrieval-only outcomes. Historical Metrics intentionally left their
support accuracy null. Reusing that diagnostic disqualified 49 supported firsts
and one reviewed failure. Ordinary Runner failures were already answer-shaped
and counted correctly. Acted on the public scorer-policy finding: only scoring
declaration three now derives the support gate from correct outcomes divided by
all fifty declared firsts. Historical metrics, report-one gates and review
contracts remain unchanged. A shared private applicable-review check preserves
independent presence for every first outcome and measured actual-answer,
citation and literal judgments.

The regression failed before the correction. Focused tests and an independent
pure 350-row probe confirm 49/50 and inclusive 45/50 qualify, 44/50 fails, and
missing/non-independent failure reviews or unfinished actual answers/citations
block qualification and publication. The independent correction also confirms
historical diagnostic nulls remain unchanged. No other runtime finding was
reported. Both whole-manual reviews found no actionable issue, and both root
and reviewer A executed the literal declaration example without opening inputs.

The original reports follow, with heading levels adjusted for this collection.
No report's source inspection is presented as an independently run platform or
native proof. Complete checks are recorded separately in the receipt.

## runtime review a

### Findings

#### 1. [warning] A valid failed no-answer first outcome makes the new support policy unmeasured

**Location:** `examples/knowledge/evaluation_score.exs:517-522`, using the diagnostic support gate constructed at lines 445-451.

**Finding:** New-generation eligibility directly reuses `Metrics.semantic`'s historical `support.accuracy`. That metric intentionally remains nil when any accepted first outcome has `response_kind: "retrieval_only"`. A failed no-answer outcome can therefore disqualify a strategy with 49 supported answers even though the new policy calls for support over all 50 first outcomes, with the failure contributing zero. The new report simultaneously says the first grid and independent review are complete.

**Evidence:** Ran `/tmp/ipse-p27-review-a-v3-probe.exs` against current source and built dependency paths. It uses the existing pure 350-row qualification fixture with all seven strategies, 50 distinct attempt-one rows per strategy, bound independent semantic review and corpus-derived literal checks. The lexical strategy has 49 supported answers and 98 supported citation pairs. The fiftieth lexical row is `status: "failed"`, with no answer, claims, spans or citations. Its independent semantic entry is present with `verdict: "unmeasured"`, as Metrics requires for retrieval-only rows.

The scorer accepts the complete fixture and returns:

```text
complete_first_grid = true
complete_review = true
lexical support.correct_n = 49
lexical support.total_n = 50
lexical support.accuracy = nil
lexical citation.precision = 1.0
eligible_variants = []
quality_gates_passed = false
```

The control uses the same failed outcome with `response_kind: "answer"` and independent `unsupported` review. It returns support 0.98, `eligible_variants: ["lexical"]` and a quality pass. No outcome was dropped in either case.

**Reachability limit:** Current Runner-produced plan-three failures use `empty_prediction/4`, which sets `response_kind: "answer"` whenever the plan selects answers, at `evaluation_runner.exs:1642-1659`. Plan three requires that selection. The control demonstrates that this ordinary Runner failure shape already contributes zero correctly. This finding is an inconsistency in the accepted public scoring-three policy, not proof that a current Runner failure takes the retrieval-only shape. Do not change the historical Metrics contract to fix it.

**Suggested fix:** Give the new policy its own support denominator. For scoring declaration three, calculate qualifying support as the independently supported/correct first outcomes divided by the declared 50 outcomes, with failed no-answer outcomes contributing zero. Retain existing Metrics and historical report-one results as diagnostics. Preserve per-strategy and whole-grid checks that every saved first outcome has an independent review entry, every actual answer/abstention has a measured applicable verdict, every citation has independent semantic review and literal integrity is measured. A missing outcome, absent/non-independent failure entry or unfinished review of an actual answer must still prevent publication. Report the policy's gate value explicitly so eligibility does not contradict an unexplained diagnostic nil. Add paired controls for 45/50 with five recorded failures, 44/50, unmeasured actual answers and non-independent/missing failure entries.

### Reviewed scope

Reviewed the complete 17-file current runtime/test/helper diff against S07 base `33106056ad730eb88af74878b55becea2d4498ac`, plus surrounding Contract, Answer, Session, Runner, Freeze, Score, Metrics, Review, host ModelCall validation, independent producer schema construction and measured finalizer/audit paths. Read selected.md, new-generation-shape.md and judge.md and applied the interrogate rubric and code-quality lens.

Traced closed plan-three output selections into exact answer request transport, dynamic shown-ID schema reconstruction and independent extract/rerank schema approval. Checked preservation of historical nested option behavior, independent envelope versions, new review-binding coverage, monetary allocation, CLI summary/exit conditions and all measured-helper prepare callers. No other evidence-backed runtime finding was found.

The finalizer's synthetic unavailable rows were considered separately. Missing cell work cannot acquire measured publication merely through the scorer's row count: measured entry/audit requires completed domain stages and exact equality between the merged prediction stream and ordered audited cell streams. I did not classify an untraced placeholder bypass as a defect.

### Checks and limitations

- Ran the bounded pure 350-row support-policy probe with `elixir -pa '_build/dev/lib/*/ebin' /tmp/ipse-p27-review-a-v3-probe.exs`. Both failure shapes and the initial supported/unsupported control completed successfully and produced the values above. The probe derives only fixture helper functions from public test source; it does not load or execute the ExUnit tests.
- `mix run --no-compile --no-start` could not acquire Mix's TCP filesystem lock under the sandbox. The direct Elixir invocation supplied all current built Ipse/dependency code paths and avoided that unrelated limitation.
- Ran `git diff --check`; it passed.
- No ExUnit suite, build, full tests, model/service operation, private workload/corpus/question/gold data or evaluation report was run or opened. Reported upstream test outcomes were not counted as independently reproduced checks. Native source/installed generation-three proofs remain unverified by this review. Manuals are explicitly outside this runtime review and no documentation-completion claim is made.

### Follow-up disposition

Finding 1 is resolved in the current draft. Reviewed the revised Score and scoring-test diff. Scoring declaration three now derives its per-strategy support gate from `correct_n / length(freeze["queries"])`, while the historical branch continues to use Metrics accuracy. The shared private `applicable_review_complete?/2` requires independent review presence through Metrics, measured literal/citation judgments and a measured verdict for every actual answer/abstention. It governs both new per-strategy gates and the report's `complete_review`. Metrics itself and report-one policy are unchanged.

Independently reran the original reproduction against revised source. The same complete 350-row retrieval-only failure fixture now gives policy support 0.98, lexical eligibility and a quality pass, while preserving diagnostic Metrics support accuracy as nil.

Also ran `/tmp/ipse-p27-review-a-v3-fix-probe.exs` with current built dependency paths. Its pure public controls passed:

- One and five independently recorded first failures retain all 350 outcomes and qualify lexical at 0.98 and inclusive 0.90 support.
- Six failures retain all outcomes and refuse qualification at 0.88.
- Removing a failure review, marking it non-independent, leaving an actual answer unmeasured, or leaving a cited pair unmeasured keeps the first grid complete but makes review incomplete and refuses lexical eligibility/publication.
- Rebinding the same three failure fixtures to historical scoring declaration two preserves report version one, historical scope and an unmeasured support gate with nil value.

No additional finding from this focused correction review. These are bounded pure synthetic controls, not ExUnit, model/service or complete native-execution verification.


## runtime review b

## New evaluator generation — reviewer B

### Findings

#### 1. [warning] Version-three qualification drops an admitted failed first outcome from support

**Location:** `examples/knowledge/evaluation_score.exs:445-452`, `:517-522`; regression case at `test/knowledge_evaluation_score_test.exs:353-385`.

**Finding:** A complete, independently reviewed version-three score can have 49 supported first answers and one saved failed `retrieval_only` first row. The new per-strategy support gate takes `Metrics.semantic(...)["support"]["accuracy"]`, which is `nil` for that strategy, so `eligible_variants` excludes it despite a 49/50 (0.98) first-outcome support result.

**Evidence:** `EvaluationScore.prediction?/3` admits a failed `retrieval_only` row with no answer/claims/citations (`:272-300`), and the 350-row test constructs exactly such a valid input at `:353-383`. `Metrics.semantic_row/2` sets `support_measured = judged and response_kind != "retrieval_only"` (`examples/knowledge/metrics.exs:261`), while `Metrics.semantic/2` returns `accuracy: nil` whenever measured support is below all rows (`:206,223`). Thus the lexical gate receives `nil` at `evaluation_score.exs:448` even though all other 49 rows have supported independent verdicts and all citation pairs are reviewed. The version-three `complete_review` logic can remain true: it permits a retrieval-only verdict of `unmeasured` while `semantic.review_complete` still requires an independent review record for it. This is reachable through the public pure `EvaluationScore.score/5` contract. Current Runner-generated version-three failures keep `response_kind: "answer"` because `EvaluationContract.validate/1` requires `answer: true` and `EvaluationRunner.empty_prediction/4` derives the kind from that flag; such ordinary measured failures already count as zero correctly. The defect is therefore limited to the broader saved-row shape that Score presently admits, rather than every measured failure.

**Suggestion:** Keep `Metrics.semantic` and historical report fields unchanged. For the new selection policy only, derive each strategy's support gate from its independently reviewed `support.correct_n / 50` first rows, conditioned on complete applicable review and literal checks. Count a reviewed failed retrieval-only row as zero; retain the existing citation gate and require actual answer verdicts and all cited-pair judgments. An alternative is to reject `retrieval_only` rows for plan-three scoring, but that would change the currently admitted Score input contract and would require revising the new regression case and first-outcome policy wording.

### Review scope and limits

Read `selected.md`, `new-generation-shape.md`, `judge.md`, the interrogate reviewer rubric and code-quality lens. Reviewed the complete 17-file draft diff against `33106056ad730eb88af74878b55becea2d4498ac`, all changed tests and helper call sites, and the surrounding Contract, Answer, Freeze, Session, Runner, Score, Metrics and producer Adapters paths. Traced historical version branching, portable and execution shapes, answer bundle reconstruction, exact request transport/approval, extract/rerank schema duplication, scoring/review binding, report/CLI fields, money division, and source/installed helper option migration. I found no other high-confidence runtime defect in that scope.

This is a source-backed review. I ran no tests, builds, services/models, private inputs, or measured proofs, and made no repository changes. The brief's prior check results are not checks I ran. Documentation integration and live generation-three measured behavior remain outside this review's verification.


## manual review a

### Findings

No findings.

### Whole-document review

Read the complete current 1,872-line `docs/developer/knowledge-evaluation.md`, including its unchanged procedures and failure exercises. Reviewed it against the actual generation-three implementation and the resolved policy-only support fix, not only its added paragraphs.

Also read these complete neighboring manuals and indexes:

- `docs/developer/knowledge-extensions.md`
- `docs/developer/testing.md`
- `docs/operator/corpus.md`
- `docs/operator/graph.md`
- `docs/operator/research.md`
- `docs/operator/research-extensions.md`
- `docs/index.md`
- `docs/developer/index.md`
- `docs/operator/index.md`

The evaluation chapter keeps the reader's path from synthetic integration through independent data commitments, declaration, sealing, measured execution, answer provenance, independent review and scoring. The new generation is explained where the reader selects a plan, traces requests and interprets qualification. Current instructions remain separate from dated evidence and milestone claims. The neighboring chapters retain operator procedures and domain implementation ownership without duplicating the evaluator's qualification policy.

Checked the distinct plan-three, experiment/seal-two, request/bundle-two, prediction/review-two, scoring-three, report-two and metric-one meanings. Historical plans and the public template keep their earlier contracts; the converter explicitly selects plan three and detached answers. The measured source/installed switches and positional order match their parsers, including default generation two. The chapter does not claim that ongoing source/installed proofs, model quality or unsupported platform accounting have passed.

The qualification explanation agrees with the revised source: all 350 saved first outcomes remain, each first outcome requires an independent review entry, actual answers and citations require applicable measured verdicts, and one qualifying strategy cannot cover unfinished review elsewhere. Policy support uses fifty declared outcomes and counts recorded failures as zero. Citation precision retains its nonzero denominator and literal checks. Historical aggregate metrics remain diagnostic; engine selection and resource/platform/authority acceptance remain separate.

### Checks actually performed

Ran `/tmp/ipse-p27-manual-review-a-example.exs` using current built Ipse/dependency paths. It extracted the exact converter body from the Markdown, applied it to a temporary copy of the public benchmark template, then ran the real preparation script with `--new-blind-seed` and temporary output. The script returned `status: "ok"` and seven variants. The generated plan validated as generation three with `sealed_answers_v1`, fifty held-out queries and the expected question path. Dataset and artifact paths stayed absent. Runner, Session, ModelService and CAS fixture modules remained unloaded. The temporary example directory was removed afterward.

Compared request transport/reconstruction, host schema-failure retention, review binding, qualification fields, synthetic helper switches and CLI behavior with their implementation. The earlier pure 350-row correction controls are recorded in `/tmp/ipse-p27-evaluator-v3-review-a.md`; they were not misrepresented as new manual or native-execution runs. Ran `git diff --check`; it passed.

No model/service operation, build, ExUnit/full suite, private workload/corpus/question/gold input or evaluation report was run or opened. Source/installed/native complete proofs and the repository-wide documentation checker were not independently run by this reviewer. This review establishes no live quality, release or platform acceptance claim.


## manual review b

## Independent whole-manual review B — evaluator v3

### Findings

No actionable findings.

### Scope and evidence

Read the entire `docs/developer/knowledge-evaluation.md` (1,872 lines), not just its diff, and the complete neighboring `docs/operator/corpus.md`, `docs/operator/graph.md`, `docs/operator/research.md`, `docs/developer/knowledge-extensions.md`, `docs/developer/testing.md`, `docs/index.md`, and `docs/developer/index.md`. Compared the changed sections with the historical benchmark specification, current `EvaluationScore` implementation and focused answer/runner/score test locations, plus the v3 contract, answer, Session, Runner and review-binding source inspected during the preceding independent runtime review.

The new chapter integrates plan-3 declaration and structured answer preparation into the existing declaration → freeze → measure/audit → blind review → score flow. Its executable example converts a private copy of the historical v1 template and explicitly requires the sealed-answer commitment; it does not describe that template as an already valid plan-3 workload. The version table correctly separates plan 3, execution seal 2, answer request/bundle 2, prediction/review 2, scoring declaration 3, score report 2 and metric implementation 1. The described per-strategy gate uses supported/correct abstention first outcomes over all fifty declared queries, counts failed outcomes as zero, retains the historical aggregate metrics as diagnostics, and requires a complete saved first grid and independent review before publication. The source now computes `correct_n / length(freeze["queries"])` for plan 3, matching the chapter's 45/50 threshold exercise. The chapter keeps synthetic protocol evidence separate from held-out quality, actual local model execution, resource acceptance and platform checks.

This was a read-only editorial/source inspection. I did not run the example, a build, tests, a model or service, the docs checker, or a private workload. I make no passing claim for the ongoing Mac/Linux controls or source/installed synthetic population.

