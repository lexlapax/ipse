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
reservations were the first implementation units at `f342528`. The next section
records publication and reader work separately from those prerequisite results.

## Complete-result prerequisites

The first generic units are `ResultDocument` and owner-only Writer reservations.
Thirty focused aggregate/schema/registry/catalog tests and twenty-eight
reservation/Writer/Limits tests pass. Three independent read-only implementation
reviews report no actionable findings. The aggregate exercise in the contributor
manual runs against the built runtime; ordinary SDK validation still rejects its
256-member array. Worker transport was still inline at that prerequisite snapshot.

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
unrestorable.

## Publication and historical reads

The next generic unit implements SDK-2 negotiation and terminal worker paging,
Session-owned capacity reservations and publication, strict source closure,
complete historical materialization, and bounded structured reads. A final
version-2 invocation receipt contains a saved descriptor, not a partial domain
value. Source bytes do not enter observer/feed delivery or model context.
Model reads authorize only tool-disclosed results in the same Session. Command
outputs remain private from model tools even if the model knows their IDs.

Forty-seven focused SDK/Source/View/reservation tests pass in 8.4 seconds. Ten
real Session integration tests pass in 8.9 seconds, including exact 4-MiB transfer
through 1,024 fragments and unchanged bytes after inert close/reopen. They also
exercise CLI Unicode equivalence, human/model isolation, denial before load,
schema-invalid diagnostic recovery, cancellation and aggregate-timer handling,
capacity refusal before source begin, malformed-seal rejection before tail repair,
and conformance assertions against the latest saved value. Existing invocation,
Worker, Registry, catalog, manifest and CLI tests pass all 102 cases in 46.6 seconds.

The Elixir 1.18 formatter found three layout differences in `ResultSource` before
the full suite started. Applying its formatting resolves both formatter checks.
Whole-transport review found two issues. An approval could admit an effect after
the aggregate deadline, and version-2 final receipts were missing from shared
metadata projections. Both findings were accepted. Session now checks time before
and after relevant admission writes, and Host checks the original deadline before
effect dispatch. The closed metadata vocabulary admits final completion metadata
without adding source-body access. Each original reviewer independently verified
its repair. A fresh third whole-implementation review reports no findings.
The [implementation review record](result-transport-review.md) retains the
reproductions, repairs, independent checks and verification limits.

The repair group passes 70 tests in 34.3 seconds. The final Session suite adds
both approved-action continuation and expired-approval refusal: twelve tests pass
in 9.6 seconds. Contributor aggregate/preparation examples run successfully
against the built runtime. Whole operator/developer chapters were reviewed and
documentation checks report zero errors across 246 files and 2,670 links.

The first full-suite attempt was deliberately terminated after the deadline
finding. Its SIGTERM log has no completed suite result and is not a passing gate,
even though the shell exited zero. The repaired candidate's replacement baseline
requires an actual completed passing suite summary. It completes successfully:
1,241 passed, 32 platform-tagged exclusions, 727.2 seconds, with the strict stdio
probe and unchanged 60,000-ms timeout. Build, both formatters, strict compile,
CI policy and demo pass. Four macOS Rust policy tests and 30 native integration
tests pass with six exclusions. A fresh runtime archive and its base extracted-
package verification pass with a utility-only runtime PATH. All 22 reviewed
runtime hashes still match.

The generic SDK-2 installed proof also passes. The independently built
[saved-result example](../../../examples/saved-results/README.md) publishes exact
4 MiB through 1,024 fragments, with one worker load and callback, no model calls,
confirmed cleanup and exact inert recovery. The lead independently reran its
source and installed verifiers. The installed runtime has only declared utilities
and bundled `erl` on PATH; its archive, artifact, host and prebuilt harness remain
unchanged. The [review record](result-transport-review.md) owns the hashes and
verification boundary.

At exact generic host `11d067f`, Serenity's native-enabled source suite passes
1,258 tests with 15 exclusions, followed by demo, packaging, extracted verification
and exact 4-MiB source/installed saved-result proofs. Hosted run
[39328913714](https://github.com/lexlapax/ipse/actions/runs/39328913714) is red on
both platforms from twelve invalid tests in compiler-marker fixture setup under
Elixir 1.18. The corrected isolation fixture passes twelve tests under 1.18.5;
the next integrated candidate still requires its own green platform gates.

The later
[domain migration](complete-domain-results.md) moves all fifteen presets to SDK 2
and materializes complete values before evaluation. Its actual source/installed
checks preserve full Corpus/Research quotes and Graph bases outside top-k evidence.
Whole-milestone adversarial review then found dropped counterassertions, dense
Unicode excerpts falsely reported as missing vectors and successful index aborts
reported as conflicts. All three were independently reproduced and repaired.
An independent follow-up then found case-sensitive object comparison inconsistent
with traversal's case-insensitive entity identity. That fourth defect was also
reproduced and repaired, with both opposite-polarity and equivalent-positive
regressions. A fresh whole-milestone review reports no remaining actionable
implementation finding within its documented coverage; all 82 reviewed file
hashes match at that checkpoint.
Refreshed five-case source/installed proofs and seven-case Corpus lifecycle
proofs pass. The domain-result record distinguishes those checks from final
integrated review, source baseline, platform and quality gates.

The repaired integration's full source baseline now passes 1,248 tests with
32 exclusions in 724.9 seconds. Build, both formatter versions, strict compile,
CI policy and demo pass. The failed abort-test isolation assertion is reproduced
and corrected without removing any production-module isolation checks; its
interrupted full run remains negative evidence. The replacement completed without
SIGTERM. Fresh independent artifacts pass all fifteen preset checks, five complete-
result cases and sixteen base groups in source/installed execution. Platform
checks for the committed candidate and the quality/resource gates remain open.

The user requires exact peak memory measurements before the new comparison.
Kernel largest-process lifetime RSS high water and simultaneous combined-process
peak are different measures. The second scope question remains pending; no
sampled total is accepted as an exact peak. An isolated owned model service and
private verified cache will be necessary for attribution. The existing Ollama
service and original interrupted comparison remain untouched.

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
