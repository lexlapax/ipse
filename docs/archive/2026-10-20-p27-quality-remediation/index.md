# P27 quality remediation

Historical investigation record, 2026-10-20. This work follows the verified
[external-review repair](../2026-10-20-p27-external-review-r1/index.md) at
`e703f885d92273a1e694b0d4bb2328a84d38199f`. P27 remains open. Current procedures
belong to the [evaluation training manual](../../developer/knowledge-evaluation.md),
and acceptance belongs to the [plan](../../plan.md#p27-optional-research-graph-and-rag).

## Preserve failure diagnostics

Saved incomplete extraction and rerank invocations clustered near 120 seconds.
The Session's complete-result clock starts at invocation entry; a selected model's
120-second timeout starts later. That is consistent with deadline preemption,
but the old journals and evaluation receipts do not establish the exact cause.
The evaluator discarded Session error notifications while waiting for completion.

The driver now retains distinct `failure_codes` without copying error strings.
It recognizes the current complete-result deadline notification as
`complete_result_deadline` and classifies other error notifications as
`session_error`. There are at most two distinct codes. Existing outcome,
completion, uncertainty and cleanup semantics remain separate. This adds no
retry, effect, model request or host deadline change.

The regression fails before the change because `failure_codes` is absent. After
the change, nine Session-driver tests and 24 adjacent seven-variant runner tests
pass. The deadline control delivers the actual timer message to a held fixture
and checks the real Session notification and resulting receipt. It does not wait
120 seconds or prove the historical cause. A real failing callback also confirms
that private callback error detail is absent from the diagnostic receipt.
Formatting, strict compilation and the documentation checker pass. The sandbox
initially blocked Mix's loopback lock; compilation passed with the required
loopback access. The [receipt](diagnostics.json) retains log hashes and scope.
These are credential-free fixtures, with no real model or memory comparison.

## Simplify model output and preserve admitted citations

The next repair assigns short per-request chunk IDs to extraction input. The
model returns an exact unique supporting quote and explicit polarity; the adapter
derives absolute byte coordinates and rechecks the original source. Ambiguous
repeats, changed bytes, duplicate JSON fields and invalid proposals refuse the
whole response. Reranking retains canonical span references in its input but
returns a complete permutation of short candidate IDs. Host operation/request
binding, independent approval and Store publication remain authoritative.

Answer preparation now preserves each admitted citation whole, within its
existing 1024-byte limit. It admits the longest rank prefix whose exactly encoded
input fits 4096 bytes and records all omissions. It does not skip an oversized
earlier candidate to admit a later one. An omitted contradiction remains omitted;
this policy does not establish semantic completeness. `context_evidence` records
only answer-cited spans, so comparing it with retrieval output cannot isolate
formatter losses.

The [first independent review](compact-review-a.md) reports no new actionable
finding and six passing synthetic probes. The [second review](compact-review-b.md)
also reports no new actionable finding. Both are bounded reviews of this repair
and its surrounding ownership paths, not P27 acceptance. The second report's
phrase "encoded request bytes" means the encoded model input. Its statement that
the independent held-out set "remains sealed" is imprecise: that new workload has
not yet been authored. The original reports are retained unchanged.

Focused and integration checks exercise exact Unicode attribution, overlapping
quote ambiguity, explicit negative polarity, whole-output refusal, canonical
rerank mapping, publication/recovery and whole-citation packing. They establish
no live quality, latency or resource improvement.

Final verification passes against the same [460-file runtime/test inventory](compact-source.json)
on both platforms. macOS has 1,349 passing tests, one skip and 36 exclusions,
plus 30 passing focused native tests and six exclusions. Linux has 1,388 passing
tests and 19 exclusions with native sandbox tests included. Both pass builds,
formatting, strict compilation, demo, native Rust controls, all fifteen presets,
nine source and nine installed knowledge scenarios, generic package checks and
host embedding/MCP installed controls. The five affected manuals were reviewed
as whole chapters; 22 literal JSON examples and eight real CLI build/config/import
and selection configurations pass with synthetic data. The
[verification receipt](compact-verification.json) binds source/package identities,
original and archived review hashes, log hashes and coverage limits. No actual
model inference or new charged-memory comparison ran in these checks.

## Select the declared service during tuning

The first tuning-only preparation on `e7638fe` stopped at plan validation with
`model_origin`. Its fresh service selection used a private port, while the
version-one tuning resolver required 11434. Preparation built artifacts but never
reached the execution claim or model-service launch. Its failed directory and
original scripts/logs are preserved; it is not a model-quality result.

Tuning now derives one common canonical IPv4-loopback origin from the explicitly
selected text and embedding profiles. Mixed endpoints, malformed origins and a
search-port collision refuse. The existing default port remains available when
selected. No additional plan field, provider fallback, service launch, deadline
or inference allowance is introduced. Legacy held-out and measured-resolution
policies retain their earlier contracts.

The plan regression fails before this correction and passes afterward. All 48
adjacent plan, runner and freeze tests pass. A real loopback inventory control
observes the selected listener, returns an empty inventory, and verifies refusal
before nonexistent dataset files open, with zero inference requests. Formatting,
strict compilation and documentation checks pass. The
[focused receipt](tuning-origin.json) distinguishes this development-evaluator
correction from the preceding full platform/package verification. A new real
tuning diagnostic requires a separate source, declaration and output directory;
no real model result is claimed for that correction's fixture checks.

## Retain the bounded tuning outcome

A separate declared diagnostic at `8a10be3` selected four exposed questions and
lexical, model-graph and dense variants before prediction. One fresh owned
CPU-only daemon/cache served the entire diagnostic, with shared warm state across
variants. It supplies no matched latency or memory comparison.

The service reached its original 1,200,000-ms lifetime after retaining eight of
twelve planned first rows: five `ok`, one `failed` and two `partial`. The callback
did not return, and no complete population was finalized. Native and staging
cleanup are confirmed; interrupted callback journal/budget closure remains
unconfirmed. Four earlier project/variant Sessions retained validated accounting.
An extraction receipt records `complete_result_deadline` and unconfirmed
completion. Missing rows are not invented or replayed.

An offline probe reconstructs the failed lexical request exactly from retained
receipts, without inference. Its model response has `classification: "open"`,
an empty claim list and a null answer, which violates the required answer-string
shape. Other retained prose also contradicts its own cited claims. These are
tuning observations, not independent final semantic verdicts. The
[diagnostic receipt](tuning-c2.json) binds original file hashes, terminal cleanup,
the decode probe and limits. Future work needs new declarations and preserves
this failed attempt.

## Remaining quality work

Dense retrieval still uses a 200-grapheme prefix, reranking sees at most 128 UTF8
bytes of each excerpt, and lexical windows begin at a matched query token. Whole
answer citations cannot recover context omitted upstream. The comparison's
one-fact-per-chunk preparation and narrow explicit-fact author remain limits.
No engine is selected. Compact output's quality and latency benefits remain
hypotheses until measured on exposed tuning inputs.

An offline excerpt diagnostic considers each positively annotated old source
chunk independently of retrieval rank. Of 73 exact reference spans, the current
dense prefix contains 19 and the first-match lexical window contains 63. A
query-aware, punctuation-aligned window prototype contains 73. Original source
hashes, reference bytes and constructed citation spans are checked. This is a
literal containment upper bound on exposed material, with no model call,
eligibility assertion, ranking measurement or semantic-quality result. The
prototype is not part of the repaired runtime. Its
[diagnostic receipt](excerpt-diagnostic.json) retains that scope.

The earlier workload stays exposed tuning material. Final validation requires a
new independently authored private 50-question workload with answers sealed until
first predictions are frozen, followed by matched exact charged-memory/resource
comparison and independent semantic review. Whole-codebase and documentation
consolidation remains a separate required readiness phase before P27 completion.
