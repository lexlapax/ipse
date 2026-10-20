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

## Derive answer text from cited claims

The retained tuning responses exposed a second source of disagreement: a model
could write one answer and attach claims saying something else. The live answer
adapter now accepts exactly `classification` and `claims`. For nonempty claims,
it derives the saved answer by joining their unchanged text with one LF. Empty
`open` and `abstain` decisions use documented fixed text. Invalid combinations
refuse the first response without retry or classification repair. Historical
prediction readers and scoring contracts remain unchanged. These mechanical
checks cannot establish claim support, completeness or correct classification.

Both independent adversarial reviews, [A](answer-review-a.md) and
[B](answer-review-b.md), report no actionable finding. The focused regression
fails before the repair and passes afterward. Decoder, measured-daemon and real
Session/runner fixtures verify strict shape, byte limits, original Unicode,
two claims sharing one evidence span with separate citation pairs, and a failed
second response with exactly two requests and no retry. Their counts overlap
the full suites. The whole evaluation chapter was reviewed, and its two literal
JSON examples and documented focused CLI exercise pass against the real adapter.

The same [461-file runtime/test inventory](answer-source.json) passes macOS's
1,363-test suite, with one skip and 36 exclusions, and Linux's 1,402-test suite,
with native sandbox enabled and 19 exclusions. Both pass build, formatting,
strict compilation and demo. Linux also passes separate 350-row synthetic
source and installed-package measured proofs, sealed scoring controls, package
build and unchanged-inventory checks. The isolated Linux snapshot has matching
runtime/test bytes; later editorial and archive documents differ. macOS native
checks were not repeated for this increment. The
[verification receipt](answer-verification.json) binds reviews, logs, inventory,
synthetic audits, package identity and the coverage limits. No real model quality,
matched resource comparison or new process-level answer-access trace is claimed.

## Preserve complete chunks and share excerpt selection

Lexical, dense and remote retrieval now use one original-byte excerpt selector.
It keeps a complete chunk whenever that chunk fits the existing 1024-byte
citation limit. Only longer chunks need cropping. Two forward scans select the
maximum distinct query-term coverage, then the shortest and earliest core.
Mechanical sentence/line boundaries retain the whole hull when possible, with
earlier context taking priority over following context. An oversized hull uses
a centered UTF8-safe window. Graph fact support spans remain independent.
Stored chunks, vectors, scoring formulas and scoped chunk fusion are unchanged;
new span bounds can legitimately change IDs and span-sensitive ranking ties.

The initial implementation preferred 512-byte context and one neighboring unit
on either side. It matched that design and passed its focused reviews, but an
exposed-data diagnostic found avoidable omissions from already-legal short
chunks. It retained 61 of 73 complete positive reference spans. Some missing
text named an approver or stated a retention rule before the selected passage.
The policy was revised before commit. The final implementation retains 73 of
73 reference spans across 45 old questions. The
[containment receipt](excerpt-containment.json) binds both implementations and
the identical exposed inputs. These checks consider annotated chunks regardless
of retrieval rank and make no eligibility, semantic-quality or private-workload
claim. The earlier prototype's similar count is separate evidence.

Both final independent reviews, [A](excerpt-review-a.md) and
[B](excerpt-review-b.md), report no actionable finding. They review the complete
revised change; their earlier compact-policy verdicts do not establish this
result. Review A also reports 204 independent context, whole-chunk and Unicode
probes. Focused controls check original byte attribution, explicit oversized
context omissions, lexical/dense/remote parity, preserved graph bases, final
rerank IDs and actual encoded Answer packing. Six 480-byte citations fit where
three 900-byte citations fit; neither policy shortens their selected conditions.
Those outer test counts include isolated suite wrappers and overlap full suites.

The same [461-file runtime/test inventory](excerpt-source.json) passes macOS's
1,369-test suite, with one skip and 36 exclusions, and Linux's 1,408-test suite,
with native sandbox enabled and 19 exclusions. Both pass build, formatting,
strict compilation, demo, all fifteen preset builds, generic package checks and
four source/installed proof pairs: base knowledge, complete results, selected
MCP query/storage and the Research gateway. Three affected manuals were reviewed
as whole chapters. Four exact operator commands pass through the real CLI with
a fresh artifact, complete actor/condition quote and final revalidation.
The [verification receipt](excerpt-verification.json) retains source, review,
log and package identities and distinguishes the intentionally stopped first
policy runs from passing checks. Their recorded process trees were empty after
the stop. macOS native tests and synthetic measured 350-row proofs were not
repeated for this increment. No actual model inference, new matched resource
comparison or engine selection is established here.

## Commit independent validation inputs

A fresh-context independent author committed fifty new questions across two
projects and 22 source documents. The author validated the detached-answer
contract, typed joins and literal references. A separate fresh-context reviewer
then read every question and answer against the complete corpus, checking source
and time eligibility, qualifications, contradictions and unanswerable cases.
The reviewer reports no findings across all fifty cases and unchanged committed
hashes. The [metadata-only receipt](private-workload.json) retains input hashes,
counts and the independent validation metadata identities.

The implementer received only metadata. The corpus, questions and answers remain
private during development and tuning. Corpus and questions may be released only
after final code and configuration are frozen; answers remain withheld until all
first predictions and the measured audit are frozen. Private semantic rationale
is retained separately. Custody is procedural, with no claim of OS isolation or
protection against disclosure outside the workflow. Relevance-grade review checks
the existing ordinal consistency; the contract provides no named prose grade
taxonomy. This preparation establishes no model-quality or resource result.

## Retain the complete excerpt diagnostic

A new diagnostic at `bfe8ca5` completed all twelve first rows for the same four
exposed questions and lexical, model-graph and dense variants. It used one fresh
owned CPU-only service/cache, a separately declared one-hour outer lifetime and
unchanged individual deadlines and budgets. The callback returned; native and
staging cleanup are confirmed. No previous attempt was replayed.

The outcome is seven `ok`, four `partial` and one `failed`. Lexical has four
execution-successful rows, dense three plus one failure, and model-graph four
partial rows after preparation failures. These are execution classifications,
not semantic grades. The [retained diagnostic receipt](tuning-excerpts.json)
binds source, declaration, original first outcomes, cleanup and offline probes.
Shared warm state and absent aggregate collection prevent a matched latency or
charged-memory claim.

Eight answer requests reconstruct exactly from their retained query receipts.
Seven responses decode; dense Q04 contains an unquoted JSON field name. Both
independent parsers reject its syntax, and the first attempt stays failed.
Of eighteen returned graph-extraction texts, four have non-object roots, four
exceed the declared one-fact limit, and one omits a required field. Nine domain
refusals correspond to those shapes; original responses remain in the journals.
Three other extraction attempts record
`complete_result_deadline` with unconfirmed completion. Service cleanup does not
turn those incomplete invocations into successful projections.

Supervisor inspection finds direct actor/timer content in lexical Q02/Q04 and a
false conflict classification for compatible processing stages in Q26. Dense
Q02 returns empty `open` despite the old reference's `answer` class. These exposed
observations guide further investigation; they are not the independent final
semantic review or a measured quality improvement. No parser repair, automatic
classification change, retry or threshold change was made.

## Bind structured output to approved model actions

The complete exposed diagnostic motivated a generic host contract rather than
parser repair in the benchmark. The increment starts at
`7e4c638be75c8d151ccc3519f22492d8c58485c4`. Model-call version 1 retains its exact
seven fields, 8 KiB encoded bound and existing providers. Version 2 requires an
object-root `response_schema`, admits a complete request through 12 KiB under
unchanged SDK bounds, and initially uses native Ollama. The full approved request
hash binds the schema. Live completion and saved-source reconstruction apply the
same duplicate-key, object-bound and schema checks to the original returned text.
An invalid completed response remains charged and retained; no repair, retry,
truncation or provider fallback follows.

Two independent designs and a cross-judge selected the versioned contract with a
direct schema field and private helpers in the existing ModelCall owner. No new
runtime module or dependency was added. Knowledge extraction and rerank profiles
explicitly select `output_contract: "json_schema_v2"`; omission keeps the text
contract. Adapters derive task cardinality and short-ID schemas, while their exact
quotation, source attribution, UTF-8 byte and candidate-permutation checks remain
independent. Old frozen evaluation plans have not been changed to select this mode.

The first review reproduced an escaping regression: a valid 1700-quote chunk
produced 3448 bytes of task input, a valid 7848-byte legacy request and an
8460-byte structured request that exceeded the provisional 8 KiB limit. The
correction gives only the new request variant bounded schema room and adds full
encoded-request preflight in the independent adapter. Both modes now preserve
that source exactly. Boundary tests include exact 12 KiB approval, native wire
and saved recovery; an independent 1800-quote probe covers legacy preflight.
The [combined review record](structured-reviews.md) retains the original finding,
corrective reviews, manual reviews and lead dispositions.

The [verification receipt](structured-model.json) binds the corrected
[source inventory](structured-source.json), full platform results, five knowledge
source/installed proof pairs and all four model-call combinations using an
unchanged precompiled SDK-1 artifact. Graph's structured lifecycle proof covers
seven source and seven installed cases. Installed SDK-1 and Graph harnesses still
load trusted proof source; stronger common installed isolation remains structural
work. macOS-specific native suites and the separate measured 350-row synthetic
comparison were not repeated for this increment.

A fresh owned CPU-only service on the approved runtime completed three synthetic
first requests for names, facts and order through the actual extension action.
Their original text passed host schema validation, usage remained recorded and
native plus staging cleanup was confirmed. This proves compatibility for the
selected runtime and those schemas. It establishes no held-out semantic quality,
matched latency, exact charged-memory comparison or engine choice.

Whole relevant manuals were reviewed and corrected. Their literal Graph, Corpus
and Research options/inference examples pass actual artifact builds, configuration
generation, import and CLI configuration inspection without a model or MCP call.
The CI installed model-call step includes both structured combinations alongside
its existing text selections; no new hosted result is claimed here.

The initial platform verification was deliberately stopped for the review repair.
SIGTERM produced process status zero without an ExUnit terminal summary. Neither
initial suite counts as passed. The fresh corrected controllers require an actual
complete summary as well as successful process status. Final evidence in the
receipt applies to that corrected source only.

## Fix acceptance scope before private inputs

On 2026-10-20 the user selected the individually qualified strategy rule from
the pending acceptance-scope question. The final selected strategy must reach
90% answer support and 95% citation support. All seven strategies and 350 first
outcomes remain published; a weaker strategy does not qualify for selection.
The [decision receipt](acceptance-direction.json) records this direction before
any new private workload release. Historical aggregate scores remain unchanged.
The declaration, scorer and engine-selection implementation are still pending
at this decision point. The [current plan](../../plan.md#p27-optional-research-graph-and-rag)
owns the acceptance requirements.

## Remaining quality work

The shared excerpt repair removes the separate dense-prefix and first-match
policies. Reranking still sees at most 128 UTF8 bytes of each selected excerpt,
and Answer admits only the longest complete rank prefix fitting its 4096-byte
input. Neither can recover upstream omissions or guarantee every qualification.
The comparison's one-fact-per-chunk preparation and narrow explicit-fact author
remain limits. No engine is selected. The completed diagnostic above exposes
remaining output-shape, deadline, retrieval/context and classification work.
Matched quality and latency benefits remain unproven.

An earlier offline diagnostic considers each positively annotated old source
chunk independently of retrieval rank. Of 73 exact reference spans, the
pre-repair dense prefix contains 19 and the first-match lexical window contains 63. A
query-aware, punctuation-aligned window prototype contains 73. Original source
hashes, reference bytes and constructed citation spans are checked. This is a
literal containment upper bound on exposed material, with no model call,
eligibility assertion, ranking measurement or semantic-quality result. The
prototype is not part of the repaired runtime. Its
[diagnostic receipt](excerpt-diagnostic.json) retains that scope.

The earlier workload stays exposed tuning material. Final validation must use the
new private commitment after final code and configuration are frozen, followed by
matched exact charged-memory/resource comparison and independent semantic review.
Whole-codebase and documentation consolidation remains a required readiness phase
before that final freeze and P27 completion.
