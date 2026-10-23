# P27 requirement-by-requirement acceptance audit

Historical acceptance record, dated 2026-10-23. Requirements come from the
[P27 plan](../../plan.md#p27-optional-research-graph-and-rag), repository instructions
and the developer's recorded choices. Current procedures remain in the
[operator manual](../../operator/index.md) and
[contributor training manual](../../developer/index.md).

Measured source is `817ab84944c347f76e297efaad313b1ec841ee91`. Final executable
source is `b81f68fc4fa2d670348b85705fde3424aa1edcc4`. The developer explicitly
accepted the versioned comparison with final-code correctness checks, without a
new 350-answer run solely for consolidation. Changes accompanying this audit
are documentation and evidence only. The enclosing commit records publication;
it changes no runtime, tests, native helper, package builder or evaluator code.

Correction note, 2026-10-23: the preceding publication description refers to
`a7f4982`. Commit `4171fb4` corrected that version's owner-independence and
sole-qualifier wording in this file and the comparison index. The current
follow-up names the owner record's `independent: true` compatibility flag and
its effect on scorer completeness. Frozen evidence and numeric scores are unchanged.

| Required result | Authoritative evidence inspected | Disposition |
| --- | --- | --- |
| Bounded, attributable sources/chunks/generations/typed versions/hashes/citations | [Evidence and query regressions](../../../test/extensions/knowledge/domain_regressions_test.exs), [Store tests](../../../test/extensions/knowledge/store_test.exs), [current platform receipts](final-platforms.json), complete saved source and prediction records in the bundle | Passed. Hybrid contributes once per chunk while retaining exact citation/graph bases; stale/forged/foreign selectors and unsafe times refuse. |
| Deletion/suppression, historical/as-of eligibility, delayed work and import recovery | Store controls for suppression racing projection commit, generation ceilings, addressed recovery, old drafts and tombstones; [lifecycle proofs](../../../test/extensions/knowledge/lifecycle_proof_test.exs) and [abort controls](../../../test/extensions/knowledge/index_abort_test.exs); current source/installed Knowledge checks | Passed. Unknown effects are not replayed, delayed work cannot resurrect a suppressed source, and recovery remains available within the documented bounds. |
| Contradictory/stale/negative/weak evidence and compatible positive requirements | [Graph population controls](../../../test/extensions/knowledge/graph_population_test.exs), domain regressions, all 350 saved predictions and independent claim/citation assessments | Passed within the selected reference's measured quality. Every rejected strategy and wrong/failed outcome remains visible; no universal answer-correctness claim. |
| Approvals, selected profiles, canonical usage/shared budgets, finite operations, cancellation/owner loss/partial failure/inert recovery | Host extension Session/worker/MCP/model/embedding suites, public lifecycle proofs, exact-source local/hosted/native suites, all four final source/installed measured controls, canonical request/budget records | Passed in exercised scopes. No new host-domain coupling, mandatory service, silent provider fallback or replay authority was added. |
| Zero applicable authority/isolation/replay/resurrection failures | Current deterministic and native-inclusive suites, both hosted platforms' source/native/installed checks, and four complete synthetic measured ownership/audit controls in [final platforms](final-platforms.json) | Passed. Exclusions and experimental macOS detached-process limits remain explicit; this does not claim unverified sandbox enforcement. |
| Generic host contracts before independently configurable consumers; preserve legacy grants/SDK bounds | P27H1–H5 host contracts and source/installed admission routes; independently built Corpus/Graph/Research artifacts; [external repair record](../2026-10-20-p27-external-review-r1/index.md) and [readiness review](../2026-10-21-p27-readiness-repair/index.md) | Passed. Optional effects and output contracts require explicit selection. Memory remains independent. |
| Seven strategies, new independently authored 50-question/two-project workload, publish all 350 first outcomes | Original dataset commitment, freeze and complete joined audit; `comparison/predictions.jsonl` and all per-question score rows in [evidence](evidence.tar.gz) | Passed: 344 successful and six failed first outcomes, no retries or replacement rows. Earlier exposed workload is tuning only. This released workload is now exposed too. |
| Freeze predictions and complete execution/resource audit before references | Both closed measure/audit outcomes, complete 16-stage/root audit, original retained prefix4 match, bound authority and unchanged release guard in the evidence bundle | Passed. The committed answer bytes were released at 2026-10-23T07:05:52Z after successful closure, never through an earlier failed seal. |
| Independent semantic review of every applicable answer/claim/citation; recomputed literal integrity | Two fresh-model 350-case/635-citation assessments, immutable original pair, independently corrected six verdict labels to match saved response kinds, unchanged 30-case/85-citation adjudication, separate explicit human resolution, final original-scorer output | Passed with an owner-approved method extension. Final support is independently resolved for 349 outcomes and 634 pairs; one rerank case depends on the owner. Its raw `independent: true` flag is required by the scorer to count it and close `complete_review` and the global quality gate. The owner judgment is not independent and changes neither hybrid nor any strategy's qualification. All original uncertainty remains preserved; no separate backend model attestation is claimed. |
| Select an individual strategy meeting 90% answer and 95% citation support; reject weaker strategies | Original scorer's `complete_first_grid`, `complete_review`, `quality_gates_passed`, complete final gates and all seven reports | Passed. Hybrid alone qualifies: 46/50 answers and 79/83 citation pairs. All six weaker strategies are rejected for the reference choice. Aggregate shortfalls remain visible and are not used to qualify a strategy. |
| Matched retrieval/classification/latency/request+budget/storage/exact charged-RAM comparison and justified choice | Original complete score, six hash-verified merged streams, audited schedule and per-project cell peaks, full matched-resource record; [selection and limits](index.md#select-the-reference-configuration) | Passed. Select State Corpus BM25+dense/RRF60, native 768-dimensional embeddings, no graph/reranker, missing-embedding refusal. Exact charged RAM includes cache/kernel charge and is neither RSS nor VRAM; separate cell peaks are not summed. |
| Holistic maintainable source/test/tool/example/resource organization and current manuals | [Structural review and census](../2026-10-22-p27-structural-review/index.md), actual source map, corresponding tests, current commands/builders, audience indexes and [editorial review](editorial-review.md) | Passed. Standard Elixir host layout, one generic extension host/SDK and one feature tree; one Session process with synchronous Turn/Invocation. Maintained source files 426 to 351; no line-count reduction claim. Historical files retained individually. |
| Independent whole-milestone architecture/implementation review and remediation | External 12-code/five-doc review/dispositions, subsequent whole-milestone reviews, three-model structural review and [Daybreak whole-P27 report](../2026-10-22-p27-structural-review/review-daybreak-c9a2d80.md); sole final P2 repair at b81 | Passed. Reviews cover the complete milestone, not only fixes. The final duplicate inventory finding has a causal regression, real CLI physical-byte checks and passing corrected-source baselines. No executable changes follow b81. |
| Whole-document editorial review, runnable examples, links, final checks and reviewable publication | Independent whole-chapter/source consistency review, real semantic-options validation, exact documented OTP extraction and all 185 member hashes, actual final scorer, current documentation checker and focused commit/push | Passed subject to the enclosing publication commit. Both manuals integrate the reference configuration and judging contract; status/evaluation records remain in the plan/archive. |

## Subsequent review disclosures

The [independent review](../2026-10-23-p27-independent-review/index.md)
confirmed acceptance and identified sensitivity to adjudication. Hybrid qualifies
under both primary reviews; lexical and rerank also qualify under reviewer B
alone. Only the final adjudicated scores make hybrid the sole qualifying
strategy. The comparison now publishes this sensitivity alongside its selection.

The six protocol corrections above corrected verdict labels to match saved
response kinds, without numeric effect. The separate owner resolution extends
the pre-registered method and is not an independent blinded assessment. It closes
review completeness and changes one rerank answer/citation judgment, but changes
no strategy's qualification or hybrid score. Original reviews and uncertainty
remain unchanged in the bundle.

## Verification boundaries

Local macOS: build, formatting, strict compilation, demo, 1,461 passed, one skipped,
36 excluded, package and exact installed-package proof passed. Exact runtime
[hosted run 39910875817](https://github.com/lexlapax/ipse/actions/runs/39910875817)
is green on Ubuntu and macOS, including its applicable native and installed steps.
Serenity's isolated exact-source checkout passed build, formatting, strict compile,
native-inclusive tests with 1,514 passed and 19 excluded, demo and package build.
The exact Linux archive's installed proof and all four source/installed CPU/GPU
synthetic measured controls passed; source and archive identities stayed unchanged.

Each synthetic measured proof has 350 rows, complete execution/resource audit,
16 stages and natural confirmed cleanup. Audit/path/prediction and review-binding
negative controls refuse correctly; unmeasured synthetic quality remains refused.
These controls do not load real model weights or prove physical GPU placement.
Actual model-quality and charged-RAM evidence comes from the separately versioned
held-out run. [Final platform receipts](final-platforms.json) preserve the exact
archive hash, commands, log hashes, refusals, source/installed modes and exclusions.

Earlier failed comparisons and failed hosted runs keep their original verdicts.
No replay, source replacement, threshold reduction, hidden failure, unmeasured-to-
zero substitution or unsupported sandbox claim is used for this acceptance.
