# P27 resumption after P26 acceptance, 2026-10-19

Historical work record, not a completion verdict. P27 is active and incomplete.
The [plan](../../plan.md#p27-optional-research-graph-and-rag) owns acceptance;
the [evaluation manual](../../developer/knowledge-evaluation.md) owns procedures.
The original [paused continuation](continuation.md) remains unchanged as evidence
of the interrupted experiment. The user authorized resuming after P26 review,
repairs and verification, now [accepted](../2026-10-19-p26-remediation/index.md#scoped-acceptance).

## Verify saved evidence before using it

Resumption began at clean source `5e2d85e`, following runtime candidate `25f1d8e`.
The private bundle manifest SHA-256 matches
`41ea57b8f5a032c709e61a7692a8e9f8611700067db8eb73fe3139b86885b855`.
All 3,962 listed files matched their recorded lengths and hashes. This check
hashed bytes without exposing reference labels or prediction semantics. No saved
file was rewritten. Ollama and an unrelated existing BEAM process were left alone.

## Audit the interrupted Session

The saved `lumen/hybrid` journal contains 1,061 events: 20 admitted requests,
19 completions and one unfinished answer invocation/action. Its budget journal
contains 79 events: 20 reservations, 20 dispatch intents, 19 observations and
19 settlements. Pure `Budget.Ledger.restore/3` validates the ledger and reports
one unsettled request and one unknown liability, without overdraw.

The outstanding action is `model.complete` on profile `p27_answer`. There is no
saved response, observation or completion for that request. The audit preserves
its reservation and unknown outcome; it neither dispatches nor settles it.
Cleanup remains unconfirmed. The old budget root will not be renewed or reused.

Journal SHA-256:
`ee91d1106681b4526f4fca7a58feb372125c92804ec8fe50e93d01109acd0962`.
Budget journal SHA-256:
`edba3ccb43917242a5679f081c7ca58fb5baaac6d3e02796f30eb5a7796ba8c4`.
The content-free audit is retained privately under
`.ipse/continuations/p27-2026-10-19-resume/task-state/interrupted-session-audit.json`.
The 280-row partial experiment remains unfinalized and unscored.

## Repair sequence and current work

1. Reproduce the runner's inference-step mismatch. Preflight now reports the
   actual selected Session limit. The existing synthetic dense Session fixture
   failed with 30 against its declared 20-request budget. An initial equal-cap
   implementation passed that fixture, but the quota control then exposed a
   second boundary: Session refused before canonical budget admission. The final
   setting is allocated request cap plus one, preserving budget-refusal records
   without permitting extra dispatch. Host defaults, token/request budgets and
   SDK limits remain unchanged. The public Runner fixture now completes 31
   scripted answer requests in one Session with a declared 31-request budget.
   All 31 dispatches, canonical usage records and booked requests match, while
   the UI still shows only its latest sixteen. That test passed in 28.5 seconds,
   with 39.9 seconds total including setup and an explicit 60,000-ms deadline.
2. Design bounded public query-result transport before implementing it. The
   existing worker closes after each invocation, and saved effect reads cover
   upstream MCP/embedding data only. No current API can page a computed large
   domain result later. Preserve all ten ranked candidates, complete quotations,
   attributed claim bases and provenance. Compare distinct designs, including
   ownership, cancellation, suppression, recovery and exact reconstruction.
3. The permanent same-chunk regression fails before repair. Candidate IDs now
   bind the chunk digest and exact absolute span offsets, consistently across
   coverage/model adapters, permutation validation, application and evaluation
   approval. The public Session rerank fixture keeps both lexical and dense
   spans from one chunk and approves their distinct IDs: one test passed in
   19.2 seconds, with 33 tag exclusions and explicit 60,000-ms timeout. Full
   domain verification also passes; no candidate was discarded.
4. The quota fixture reproduced failed answer rows becoming `retrieval_only`.
   Answer-policy failures now retain `response_kind: "answer"`, with null answer,
   empty claims and the failed status. Intentional retrieval-only plans remain
   unmeasured. Existing metric algorithms/version are unchanged; a new regression
   proves independent unsupported review counts a failed answer as zero, while
   retrieval-only stays unmeasured. Eleven focused tests pass in 14.6 seconds
   with explicit 60,000-ms timeout. Original prediction rows remain unchanged.
5. Reconcile all P27-01..14 requirements, run source/native/installed/platform
   gates, and review the whole operator/developer manuals and examples.
6. Freeze a new exposed comparison with explicit finite budgets and fresh local
   model metadata. Preserve the prior failures. Finalize/hash all first
   predictions before references or independent semantic review. Quality gates
   remain 90% support/correct abstention, 95% semantic citation precision and
   zero authority/isolation/replay/resurrection failures.

The inherited multi-variant fixture deadline issue is repaired and verified at
`25f1d8e`, with all variants/assertions retained and no increased deadline. Its
exact-source hosted matrix passed both platforms. Older append/MCP-discovery
negatives remain unexplained; the green run does not establish their cause.
Independent semantic reviewer dispatch remains a later explicit authorization
step after a concrete blinded packet exists.

## Verification of the first repair group

On local macOS, build, formatting and warnings-as-errors compilation pass. The
full source suite passes 1,169 tests with 32 tagged exclusions in 717.2 seconds,
using the strict stdio cleanup probe and an explicit 60,000-ms test timeout.
The credential-free demo also passes. This baseline covers the three runtime
repairs above. The later test-only expansion from seventeen to thirty-one
requests passes separately; it does not change runtime code or raise a deadline.
The pure Evidence, package and metric regression group passes all 25 tests.
Three independent repair reviews found no blocking source defect. The whole-
manual review found the old seventeen-request exercise; it now follows the
thirty-one-request fixture. These reviews cover the repairs, not the unfinished
result transport or full P27 acceptance.

The revised [transport proposal](result-transport-design.md) received three
independent design-review passes at SHA-256
`902fd294ac1367211c25cb79568faced127361e8800fd8c1525e2775b10cadc2`.
First-round findings about stage eligibility, terminal dispatch, the original
deadline, aggregate decoding, journal reservation, restore validation and bounded
reader cursors were accepted and specified before implementation. A design pass
does not establish runtime correctness. Generic aggregate validation and Writer
reservations are the first implementation units; Session publication, source
closure, readers, installed proofs and knowledge-package integration remain open.

## Complete-result prerequisites

The first generic units are `ResultDocument` and owner-only Writer reservations.
Thirty focused aggregate/schema/registry/catalog tests and twenty-eight
reservation/Writer/Limits tests pass. Three independent read-only implementation
reviews report no actionable findings. The aggregate exercise in the contributor
manual runs against the built runtime; ordinary SDK validation still rejects its
256-member array. The current worker transport remains inline.

The final prerequisite baseline passes build, formatting with Elixir 1.20.3 and
1.18.5, warnings-as-errors compilation, the CI policy check and the credential-free
demo. Its full source suite passes 1,192 tests with 32 tagged exclusions in
723.6 seconds, using the strict stdio cleanup probe and an explicit 60,000-ms test
timeout. Documentation checks cover 246 Markdown files and 2,660 local links with
zero errors. A separate whole-chapter review of persistence and artifact training
finds no documentation issues. These are local prerequisite results, not final
P27 native, installed, platform, semantic-quality or resource acceptance.

Implementation found Jason's existing 1,024-byte integer-token ceiling, including
a minus sign. The aggregate encoder uses the same ceiling; the 8,192-byte lexical
guard remains for other primitive tokens. Global codec configuration is unchanged.
The proposal also clarifies explicit preparation failure and legal unsealed
diagnostic prefixes. Complete malformed or schema-invalid producer bytes remain
unreadable until a valid seal; failing such validation must not make a Session
unrestorable. That source-state behavior is still an implementation/proof task.

## Synthetic result and identity reproduction

A separate domain-test VM reproduced both remaining boundaries with synthetic
provided sources and no model, network or held-out input. Ten 1,024-byte quotations
produce a 16,911-byte complete result: evidence 16,573 bytes, claims 103, coverage
144, plus the other fields and JSON object overhead. Current Research returns
`refused(result_too_large)` at the unchanged 12,000-byte ceiling. This measures
the assembled result, not an estimated number of source bytes.

Two distinct citation spans in one chunk survive fusion as two candidates, but
their rerank IDs collapse to one chunk ID. A complete order is refused as
`invalid_rerank`. The first scratch probe accidentally selected a different source
for its second citation and failed its duplicate-ID premise. After binding both
citations to the same actual source, the intended reproduction passed. Only this
corrected probe is counted as evidence. Its content-free report is private under
`task-state/synthetic-boundaries-before.json` in the resumption directory.
