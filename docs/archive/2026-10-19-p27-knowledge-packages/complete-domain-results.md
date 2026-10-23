# Complete knowledge results, 2026-10-19

Historical implementation and verification record after generic transport
candidate `11d067f6e19c670702168b196fb550ea0aadb34d`. This unit does not complete
P27 or establish model quality. The [plan](../../plan.md#p27-optional-research-graph-and-rag)
owns acceptance. Use [knowledge training](../2026-10-22-before-structural-consolidation/docs/developer/knowledge-extensions.md#publish-and-read-the-complete-domain-value)
and the [evaluation manual](../2026-10-22-before-structural-consolidation/docs/developer/knowledge-evaluation.md#materialize-before-interpreting-a-result)
for current procedures. The [generic transport review](result-transport-review.md)
owns its separate architecture, deadline and publication checks.
The later [platform record](platform-verification.md) completes exact-source
Serenity and hosted Ubuntu/macOS checks at `fb980a0`. The
[memory investigation](resource-memory-grounding.md) separately constrains the
still-unimplemented exact peak measurements. Earlier checkpoints below retain
their original status and limits.

## Preserve the logical result

Corpus, Graph and Research now declare SDK 2. All fifteen compiled presets grant
`invoke.result.pages`; builder and operator generation require the matching SDK
and capability identity. Each entrypoint prepares its whole result through
`ResultPublication.prepare/1`. Small results retain inline behavior. Valid larger
results publish complete saved documents. Invalid aggregates return an explicit
small `result_too_large` refusal. No quote, citation, provenance or Graph basis
is cropped to fit transport. Domain request, source, quote and work bounds remain.

The evaluation driver materializes saved delivery through Session before exposing
a domain value to predictions or metrics. Its receipt retains the descriptor,
exact source bytes in Base64, byte count, digest and historical provenance.
Missing or forged sources produce a failed first receipt with a null value.
Matching journal completion remains a separate fact. There is no inline fallback,
replacement query, retry or model request after a failed read. Existing protocol
proof consumers use the same complete-result reader.

## Exercise actual independent workers

The [complete-result verifier](https://github.com/lexlapax/ipse/blob/111228c1eadf6816f76e3b3981030000907f2e5a/examples/knowledge/verify-complete-results.exs)
uses real imported artifacts and ordinary Sessions, with a provider that refuses
any model call. The lead ran its source and extracted-runtime forms successfully:

| Case | Complete observed result |
| --- | --- |
| Research, ten sources | 16,921 bytes; ten unchanged 1,024-byte quotes with exact spans and provenance |
| Research, escaped text | One 6,705-byte encoded citation crosses a 4,096-byte fragment boundary intact |
| Corpus, ten sources | 17,228 bytes; ten complete quotations after source revalidation |
| Graph, eight facts | 16,977 bytes after the polarity repair; one ranked evidence passage and all eight complete claim bases, including unranked citations |
| Opposing assertions | Both attributed claims, polarities and exact citation bases survive direct Graph and Corpus graph retrieval with `top_k: 1` |

Both executions verify complete hashes, exact historical reads, inert restart,
unchanged journals, confirmed cleanup, zero model requests and no domain modules
loaded into the host. Graph uses eight explicitly bounded one-fact extractions;
the existing worst-case effect plan remains enforced.

Installed mode compiles the trusted proof harness in the outer development VM,
then loads prebuilt harness and artifact BEAMs in the release. Its runtime PATH
contains declared utilities and bundled `erl`, with no system toolchain. Archive,
artifact, extracted host and harness inventories remain unchanged. The host archive
SHA-256 is `d30dcec6769006d37ebd733eec5b2dc61cada8a9cd98aa166c2bf49362c1c062`.
It is the previously verified generic host archive; independently rebuilt domain
artifacts contain this unit's changes. No new host runtime source changed here.

All fifteen preset builds pass manifest, catalog, file-hash and host-module
exclusion checks. The existing public base proof passes all sixteen groups;
query-completeness controls pass three tests. The isolated package suite passes
twenty-two inner domain cases after the Unicode regression. Consumer controls pass seven tests, including
a deterministic lost-source case after final completion and a positive exact-byte
result larger than 16 KiB. Mixed SDK preflight passes its selected runner case.

## Review and remaining gates

Whole-unit adversarial review covers all three packages, selected trust/build
identity, unchanged evidence/store call chains, result consumers, failed rows,
source and installed proofs, workflow gates and manuals. Reviewer A reports no
actionable findings and independently passes eleven focused outer tests and the
actual complete-result source proof. Reviewers B and C also report no actionable
findings after tracing the whole unit and manuals. C independently verifies
complete Research output, unchanged small inline output and refusal of malformed
delivery without a supplied inline fallback. These are three independent review
contexts; there is no configured panel or claim of different serving models.
That review snapshot predates the whole-milestone repairs below; its hashes do
not establish review of the later changes. The first integrated full suite exposed one stale expectation
outside those changed files: the profile test still required offline Research's
two SDK-1 invocation grants. Its exact expected list now also contains
`invoke.result.pages`; network and inference exclusions remain. No runtime code
changed. The lead deliberately stopped that already-failing run and retained its
negative log. The completed-summary guard rejected the SIGTERM attempt even though
Mix returned zero. Its replacement completed with 1,240 passing tests, 32 excluded
and three failures. All three were positive build-spec fixtures missing the now
required SDK identity. Adding SDK 2 to those fixture manifests preserves strict
operator admission. Sixteen focused fixture and Session-result tests pass after
the corrections. Neither negative full-suite attempt is a passing gate.

## Whole-milestone review and repairs

Two further reviewers examined the whole P27 architecture and implementation,
including unchanged domain algorithms. Both identified lost counterassertions;
one also identified a dense Unicode excerpt failure and the other a successful
abort reported as a conflict. The lead reproduced all three before repair.

Graph previously classified only facts selected by positive-edge traversal.
Negative assertions remained stored but disappeared from claim context. The
repair adds current validated counterassertions to the reached facts before
classification and evidence ranking, using the classifier's conflict predicate.
It preserves positive-only traversal, explicit edge limits and each claim's own
citation basis. Coverage distinguishes walked edges from context facts. The
pure evidence suite initially passed seventeen tests, including opposing polarities at
`top_k: 1` and exclusion of stale or unrelated assertions. Source and installed
five-case proofs preserve the conflict through both Graph and Corpus retrieval.

Dense Corpus excerpts selected 200 graphemes before the 1,024-byte quote check.
A single combining grapheme exceeded that byte limit and falsely produced
`missing_embedding` despite a valid vector. Corpus now applies the shared UTF8
byte-prefix boundary after its ordinary excerpt selection. The real callback
regression covers dense and hybrid queries, ASCII and combining text, and both
present and absent vectors. Actual missing vectors still refuse.

Store's committed abort receipt omitted the root generation. Corpus therefore
rejected a successful durable abort at its unchanged generation fence. The
receipt now includes the generation actually committed, including when a source
replacement differs from the draft's target generation. Twenty focused Store
and public Corpus abort controls pass for State and MCP CAS. Source and installed
Corpus lifecycle exercises also pass all seven cases. Their malformed and
unavailable cases explicitly abort the retained draft without another provider
request. Owner-loss cleanup remains explicitly unconfirmed in its separate case.

The independent follow-up found a further inconsistency. Traversal matches entity
names without case, but conflict detection compared object names as raw strings.
Opposite assertions about `lock` and `LOCK` could remain supported, while two
equivalent positive assertions could falsely conflict. The lead reproduced the
lost contradiction before repair. Conflict detection now uses the same folded
object identity as traversal while preserving original fields, IDs and citations.
The permanent control fails before repair and checks both polarity cases in both
input orders. All eighteen Evidence tests pass afterward, as do independent
direct and fused retrieval probes for the earlier repairs.

Reviewer A independently reports no finding in the Store and Unicode repairs.
Reviewer B independently confirms the counterassertion and Unicode repairs, then
implements the accepted object-identity correction. Fresh reviewer C then reports
no remaining actionable implementation finding across the whole milestone's
reviewed scope. Its inventory records 82 file hashes and distinguishes complete
reads from selected host sections and test inventory. The lead confirms all 82
hashes at that checkpoint. C independently probes both object/polarity cases in
both orders, expiry exclusion and UTF8 prefix validity. It also finds and verifies
the correction of manual wording that implied indexing or extraction could
promote historical imports to current evidence. The integrated baseline remains
open at this checkpoint. The nine-file focused
integration group passed 68 tests before the final object-identity correction;
that result does not replace the refreshed baseline.

The refreshed baseline exposed one mistake in the new abort test: its isolation
loop also required the test-only `CASFixture` module to be absent. The evaluation
runner intentionally requires that fixture in the host. The lead reproduced the
load-order failure by loading the real runner before the abort test. Removing
only the test helper from that loop makes the same control pass; all seven
production domain-module isolation assertions remain. That already-failing full
run was deliberately stopped, and its SIGTERM log was rejected by the completed-
summary guard. Its result is not a passing gate. Runtime and proof files did not
change. The original review inventory remains a snapshot, with the test-only
correction recorded separately.

## Completed local baseline

The replacement run completes with 1,248 passed and 32 tagged exclusions in
724.9 seconds on local macOS, using the strict stdio probe and unchanged
60,000-ms test deadline. The completed-summary guard accepts its final result
and confirms no SIGTERM. Build, formatting under Elixir 1.20.3 and 1.18.5,
warnings-as-errors compilation, pinned CI action policy and the credential-free
demo pass. No runtime or test file changed during that run.

All fifteen presets were rebuilt after the final object-identity repair. Their
manifest, capability, catalog and host-module exclusion checks pass. Fresh source
and installed executions pass all five complete-result cases and all sixteen
base protocol groups. These installed checks reuse the unchanged generic host
archive with independently rebuilt domain artifacts. Runtime, proof and manual
hashes still match the review. The subsequent abort-test fixture correction has
its separate review; plan and archive status are updated from actual receipts.
Operator examples for all three artifact configurations and imports pass through
the real CLI in isolated temporary homes. The final documentation check covers
249 Markdown files and 2,700 local links with zero errors.

This completes the local integration gate. A focused commit and push, then
exact-candidate Linux and hosted checks, remain the next platform gate. It does
not establish held-out quality, exact comparison resources or engine selection.

## Platform and resource boundaries

Generic host `11d067f` passes the Linux native-enabled suite on Serenity:
1,258 passed, 15 excluded, followed by demo, package verification and exact 4-MiB
source/installed saved-result proofs. Its hosted
[run 39328913714](https://github.com/lexlapax/ipse/actions/runs/39328913714)
failed on both platforms with twelve invalid tests from fixture setup. The
Elixir 1.18 compiler executes the synthetic `@on_load` marker in its compilation
VM. Setup now confirms and removes that compiler marker before testing the
separate import boundary; import must still leave the marker absent. Twelve
Session-result tests pass with the corrected fixture under Elixir 1.18.5.
The earlier hosted run remains red, and the next candidate requires its own
passing platform gates.

The user requires exact peak memory for the comparison. Existing BEAM allocation
samples cannot satisfy that requirement. Research identified kernel lifetime
largest-process RSS high water as a portable metric for fresh owned process
scopes, distinct from simultaneous combined-process memory. The combined-process
scope question remains pending. No measurement implementation, model-service
restart or new model comparison is claimed here.

The workflow now runs generic SDK-2 source/installed proofs and complete knowledge
source/installed proofs. Exact-source hosted and Linux receipts remain separate
gates. Lifecycle/authority audit, the new exposed full comparison, independent
semantic judgments and resource/engine selection remain open. The original
interrupted comparison and its unknown request liability are untouched.
