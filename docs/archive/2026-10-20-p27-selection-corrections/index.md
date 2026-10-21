# Knowledge completeness and embedding identity corrections

Historical review and verification record, recorded 2026-10-20 for the session
that began on 2026-10-19. This work
starts from `f2bfc8d7f8dd3fadedd2e18183faf4533ee63ac5`. Use the current
[Corpus](../../operator/corpus.md)/[Graph](../../operator/graph.md) operator manuals and
[embedding](../../developer/extension-effects.md#generate-and-reconstruct-embeddings) and
[knowledge](../../developer/knowledge-extensions.md) developer chapters for procedures.
P27 remains incomplete until the separate quality/resource gates pass.

## Intent and review coverage

Keep optional knowledge behavior in independently selected extensions, with
generic host approval, accounting, result-source and recovery contracts. Bounded
graph retrieval must disclose unfinished traversal. Durable dense retrieval must
not combine incompatible operator selections or provider-reported models. Explicit
approved reindexing must restore a usable homogeneous projection.

Two independent read-only review contexts were requested with configurations
gpt-6-astra and gpt-6.1-sol. The host accepted those configurations; generic child
labels do not certify backend model diversity. These are internal reviews, not
external or human sign-off. Both applied the same scope and rubric. They traced
domain, host, observability, evaluation, measurement and relevant manual paths,
with explicitly bounded coverage. Neither exhaustively audited every native or
evaluation line, ran real inference, read quality labels or replayed partial runs.

## Findings and decisions

| Finding | Evidence and decision |
| --- | --- |
| Depth exhaustion could claim complete coverage while outgoing facts remained | Both original whole-P27 reviews raised it. Root reproduced it with a chain and depth one, then added pure frontier/cycle controls and public direct/fused query checks. Act on. |
| Stored embeddings could be compared after the approved route changed | Both original reviews raised it. Root reproduced different host bindings with the same alias/reported model/width and a successful incompatible dense query. Act on. |
| A changed reported model made explicit reindex fail under an unchanged approved selection | One follow-up whole-P27 reviewer reproduced the failure in State and MCP. The other initially considered safe refusal sufficient. Root reproduced `projection_corrupt` with a failing Store regression and treated recovery as required. Act on. Both reviewers verified the repair; the initial dismissal was explicitly corrected. |

The host now offers explicit embedding request/value v2 with selection identity
derived from the original approved intent. Exact request/value v1 and private
source/descriptor/read v2 remain supported. Standalone Actions validation checks
the selection even without a usage-read action. Domain vectors require current
identity; legacy values stay structurally readable and require explicit reindex.

Store validates complete old chains before deduplication and preserves the old
head only when the shared Evidence compatibility predicate accepts every old
vector against the new homogeneous batch. Explicit incompatible reindex detaches
under the existing root CAS. Old drafts cannot be promoted by adding a version
to their token. Suppression, exact abort and delayed-publication fences remain.
There is no new grant, namespace, dependency or larger SDK/page/effect bound.

Span-specific RRF candidates are intentional because different excerpts of the
same chunk retain different authority. The optional Linux charged-RAM backend
does not become a mandatory product dependency. Neither item required a change.
Unchanged endpoints/model names cannot establish unchanged remote weights or
routing; that documented limit remains.

## Verification

The [source identity](source-identity.json) binds 453 tracked source/config/test files
with selection SHA256 `c63254be47dd3e5c8a4be5f693d9ebd65dcecd682a36b77e77daa0af821a7d93`.
Root compared every selected file
with the immutable Linux verification snapshot `f967adda62ad06803fe6440b5a6e3e89a8680ebb`.
Manuals and dated records were checked separately. Earlier initial 39-host,
45-domain and independent 84-test results remain development evidence. Both
reviewers independently passed six distinct focused tests after the reported-model repair. Root passed
the new Store and public Session regressions after first retaining the failure.

The final public selection fixture makes ten synthetic HTTP requests. It checks
index/query at A, changed-endpoint refusal and partial fallback at B, explicit
reindex, timeout-only reuse, inert restoration, then a reported-model change at
the same B endpoint with refusal before explicit reindex and successful retrieval
afterward under the same approved selection hash. It validates Actions, Usage,
Session recovery, cleanup and absence of domain modules in the host. These are
protocol checks, not retrieval-quality evidence.

| Final-candidate check | Result |
| --- | --- |
| macOS source suite, stdio probe enabled | 1,305 passed, one skipped, 34 excluded, 799.5 seconds |
| macOS explicit native suite | 30 passed, six excluded, 25.1 seconds |
| Linux source suite with native enforcement | 1,344 passed, 17 excluded, 733.9 seconds |
| Rust macOS policy, bound authority, regular-file copy | Four, three and six passed; one file-copy subprocess entry deliberately ignored |
| Source build, formatting and strict compile | Passed |
| Demo, package build and base installed verifier | Passed on macOS and Linux |
| Ten-request selection proof in source and extracted runtime | Passed on macOS and Linux |
| Shared text model-call proof in source and extracted runtime | Passed on macOS |
| Real CLI Corpus and Graph command shapes | Two Corpus and four Graph commands passed in isolated homes/workspaces, with no model calls |
| Whole affected manual review, links and CI pin policy | Passed; 266 Markdown files, 2,829 local links, zero errors |

The macOS archive SHA256 is `a2aeb5003c85e5737880cbcb029b472699549723cada1fd2340abb2d076c2774`.
The Linux archive SHA256 is `69723305ca969379cde427c2719632d8f92f3441a47efd214476a19f10723294`.
Installed proofs kept archive and extracted host files unchanged and hid the
system development toolchain from the runtime PATH. This is a PATH isolation
check, not a claim that the trusted outer verification harness was uncompiled.

The CLI driver waited for each command to finish through EOF before opening
the next chat against the same project store. It checked the retained quote,
revalidation and Graph depth-zero partial result. Its first scratch attempt
failed before CLI execution due to relative executable handling. A second
piped multiple commands without waiting and correctly encountered busy/exit
behavior. Both were harness setup failures, retained separately and excluded
from passing counts.

No dependency, grant, namespace or ordinary result/page/action ceiling was raised.
The earlier hosted f2b matrix is green but does not verify these corrections.
The stopped 25-row comparison and original 280/350 run remain immutable and are
not replayable. A fresh corrected, explicitly reused-set comparison remains open.
Read-only inspection also found an incomplete native cell lifetime in the stopped run,
with `residual_descendants` after a zero leader exit. Twenty fresh model-free
ERTS exit/resolver probes and one real-daemon metadata-only diagnostic did not
reproduce it. Its cause remains unresolved. Diagnostic-only observation changed
no production acceptance rule, requested no inference and cannot validate an
old peak. See the [retained comparison](../2026-10-19-p27-measured-integration/interrupted-comparison.md).
