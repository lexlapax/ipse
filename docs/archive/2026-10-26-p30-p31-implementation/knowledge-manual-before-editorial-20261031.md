# Historical Knowledge training manual before editorial consolidation

2026-10-31. Historical-only snapshot of the uncommitted `docs/developer/knowledge-extensions.md` on `codex/p30-p31`, immediately before consolidating its capture/review/recall explanation. Original full-file SHA-256: `17db5b582c0344657976b8e533ce38ad48ab21a7b982c4ac8ee98957c88714fe`. The body below is preserved with relative links mechanically rebased for this archive location. Use the [current developer manual](../../developer/knowledge-extensions.md) and [operator procedures](../../operator/knowledge-permissions.md) for current behavior. The [implementation index](index.md) records its provenance and replacement.

---

# Build source-bound knowledge behavior

Follow a retained source into a current citation, then change retrieval without
bypassing source identity, approved inference, or recovery. Corpus, Graph, and
Research are independent worker packages. The native Knowledge capture package
uses the protected collection SDK. These workers use the public SDK; they do not
load domain code into the host or open their own files/sockets/executables.
Start with the [operator procedures](../../operator/corpus.md) and
[artifact builder](../../../extensions/knowledge/README.md).

## Find the owners and compiled authority

| Source under `extensions/knowledge/src/` | Responsibility |
| --- | --- |
| `knowledge.ex`, `knowledge/records.ex`, `notes.ex` | Protected capture continuation, stable evidence and note retention |
| `knowledge/contracts.ex` | Inert operator-sidecar publication schemas and managed recipes; no authority or executable setup |
| `corpus.ex` | Source/query/index commands and final revalidation |
| `graph.ex`, `research.ex` | Attributed extraction/traversal and captured-source investigations |
| `profiles.ex` | Closed named algorithms and preset compatibility |
| `store.ex`, `store/` | Root/page transactions and State/MCP adapters |
| `evidence.ex` | Safe identities, chunks/citations, ranking/fusion/facts/traversal |
| `adapters.ex` | Complete selected retrieval/embedding/text-helper interactions |
| `documents.ex`, `documents/` | Bounded extraction of acquired bytes, DOCX package checks, and optional protected PDF parser staging |

Entrypoints implement SDK callbacks directly. A compiled preset fixes capabilities;
options cannot promote lexical State code into semantic or MCP authority. All
Knowledge presets declare SDK 2 and complete-result permission. Builder/generator
check exact declarations before grants. Import, trust, and activation remain separate.
Corpus uses store/retrieval/embedding/rerank families; Graph uses stores/extraction,
with empty retrieval registry; Research uses search/fetch/BM25/optional rerank.
Reject unused/incompatible profiles before generating permissions. A syntactically
valid dense/graph/hybrid/remote-query profile is still invalid for Research.

## Follow protected capture from a Session source

Begin with a fresh reviewed statement and trace one new v3 capture. That narrow
path is executable under the selected saved permission; it does not authorize
replacement, deletion, retention or supersession. Public reviewed forgetting has
its own reducing management route, also used by session-only retention.
Pin/automatic/duration use a separate guarded management effect; correction and
supersession remain closed. Ordinary document staging,
State writes and Memory suppression keep their separate grants and storage paths.

The `knowledge/native` preset exports `capture` as a tool and command. It accepts
one text/category/reason/event-time tuple and an exact quote with an opaque Session
source handle. All seven profile registries must be empty. This path uses the
selected main model's tool calls or an explicit operator command; it performs no
secondary inference.

Follow `Knowledge.handle/3` through source read, exact quote, public SDK proof,
saved lineage override, existing-record lookup and explicit managed collection commit. The host
reconstructs the proof independently at publication and checks the current
protected permission. The artifact declares `host.collection.managed` separately
from read access and carries the exact sidecar recipe digest. Its original commit
explicitly advances the import floor. Read/write grants do not imply this capability.
A worker's origin label or JSON proof grants no permission.
The [collection SDK](../../developer/collection-sdk.md) owns that admission boundary.

`Knowledge.Records.capture/4` constructs a note only when its text equals a
complete source event with available coverage, a zero start offset and matching
source and quote hashes. Literal operator input additionally needs
`native_operator_assertion` origin with `input.assertion.ordinary`,
`input.assertion.preference` or `input.assertion.current` matching the selected
category. A literal typed tool outcome can support only `ordinary`. The host
recipe repeats these checks; the worker's classification is not admission.
Plain interactive messages, native question answers, selected fragments and
other claims become attributed pending proposals. Even a whole interactive
message can quote somebody else. The signed literal observation and managed
dependency paths recheck the recipe and refuse older literals without the
required origin/category support. Other reads and previously stored records
need separately reviewed treatment rather than silent promotion.
Ordinary notes expire after 90 days; current/preference notes retain their category.
Pins require a separate explicit operator workflow.

Trace `/remember preference Prefer concise answers.` through Terminal and
`Session.prepare_assertion/4`. Session prepares a native rendering only for an
idle, settled owner with the selected reviewed bundle and a bound original
journal. The Input service binds its one-use witness to the client, channel,
render and complete display. `OperatorAssertion.receipt/3` retains the exact
statement, category, scope and native confirmation. Session syncs that record
before requesting the existing protected `capture` command. SourceIndex admits
its category-specific occurrence; the worker receives an ordinary read handle
and quote. It cannot construct this origin by supplying JSON. The receipt proves
the operator's endorsement, not external truth or effect permission. The command
still rechecks Identity/Consent and accounts publication normally. Interrupted
confirmation/publication is never resumed by replaying the command.

The capture action retains its complete inherited-plus-own causal dependency
union. A CAS prerequisite can match its own committed
current-parent snapshot/nil-get, or an exact positive host cache entry derived
from an earlier authenticated receipt/result pair. The latter permits only a
closed snapshot, explicit nil-get or initial empty metadata-only index; arbitrary
indexes and missing `record` fields do not establish absence. Every member must
bind the same complete root, project, pin, policy and expected generation.
Record values, scans, mixed roots, missing classification or unmatched dependencies
refuse. Final source/Consent checks and the native generation CAS still decide
current publication. The native owner narrows the policy deadline by the original
lineage deadline after synced staging. Admission is the final locked decision;
an already admitted switch may physically finish later. For a pending proposal,
the held Collection reader checks the count and encoded-byte ceiling without
returning existing proposal values to the worker.

The actual terminal `/remember ordinary` control published and settled one new
literal. A later direct authorized-client headless control also saved a genuine
typed tool outcome while write/shell stayed denied. The
[causal-root cache implementation](causal-root-cache.md)
preserves the earlier recall root alongside the capture's own absence reads and
reconstructs its classification chronologically in Saved. Its
[independent review](causal-root-cache-independent-review.md)
accepts that bounded path. Every model-selected source lookup now privately
preflights **all** selected occurrence provenances under the actual Session/Writer
owners, including calls whose original dependency list was empty. Only a truly
empty or complete authenticated payload-free same-root union continues; missing
producer/cache entries and record-bearing data refuse. Result admission repeats
the actual query/selection relation, and Saved reconstructs it chronologically.
Subscriber starts omit source arguments and results use a fixed status-only
preview; full source content retains its lineage in the journal/model continuation.
The [source-tool review](managed-source-tool-preflight-independent-review.md)
accepts this bounded integration. A confirmed new-v3 capture can then project
only its own authentic prior root-only union as historical metadata, using the
exact adjacent own receipt and a freshly checked successor root. Original
messages and dependencies remain unchanged; an independently guarded notice
states that earlier root/absence observations are not current record authority.
Producer/call resolution uses the same verified mapping. This permits later
source tools without a generic stale-root rebase or retry of capture. The
[independent own-write review](own-root-transition-independent-review.md)
verifies a synthetic-model capture, later source list/read and successful final
turn with settlement, Saved and close. Earlier settled-but-failed turns remain
preserved. A separate synthetic headless Session control saves two distinct
unattended proposals across a close and resume, with settled saved consent.
That control does not qualify record-content release or all provider continuations.
Actual untrusted argv/stdin [CLI controls](headless-cli-untrusted.md)
observed no literal or proposal and returned unknown/error; that is not a confirmed
semantic refusal or working proposal path. Earlier failed stores remain historical
evidence, never replay targets. Full notes readiness remains false; these controls
do not qualify every source, owner/expiry race or later-use sink. See
the [admission implementation review](notes-publication-implementation-independent-review.md)
and [original terminal/headless evidence](remember-terminal-headless-controls.md)
for their distinct tested boundaries.

Lineage derives from source identity and span, independently of a model's text
or category. The pure Records retention model can apply a saved session-only
override to every classification and paraphrase of that evidence; it cannot renew
an anchored expired override. Its retention receipt flags a possible history gap
when a pin, enduring preference, current temporal claim or history is reduced
to a non-pin policy; this is a conservative warning, not a calculation of the
missing time range. A
new retention choice cannot predate the selected record's creation or its
supersession, although the caller must still authenticate the clock and prior
choices. Applying a saved override to a later recapture retains its original
deadline; an override dated after the recapture is refused. A new retention
choice cannot revive an expired note; session-only
suppression remains available, but cannot apply before its recorded choice time.
When changing a note already marked with an operator override, the pure retention
operation requires a prior override matching its effective note and no later than
the new choice. This is consistency only: different prior reasons can produce
the same note, so the host must authenticate the exact prior choice.
The text reason can itself equal the internal override marker. For that
ambiguous case the caller may supply `:absent` after checking protected state;
the atom is only a caller assertion, not proof that no choice exists. The host
must recheck absence under the transaction lock before applying a change. The
same assertion can be supplied for a correction; where the replacement has a
different lineage, its choice state also requires an independent host check.
These pure checks do not authenticate the source
or establish current eligibility. The local temporal check refuses a note before
its creation and a historical version before its supersession; stated event time
remains separate from observation time. A correction with the same lineage cannot
extend a finite deadline, promote it to a persistent category without an
override, or revive it after expiry; a different lineage must still be backed
by independently authenticated new evidence. The current managed host refuses legacy override
adoption until a typed operator workflow supplies that authority. An existing
public record returns its revision without replacement or TTL
renewal. New proposals have a seven-day deadline and a retained queue ceiling of
64 records/256 KiB. The worker counts retained proposals, including expired ones;
the version-3 host normalizer independently checks the same bound under the
Collection lock using encoded record sizes. Neither path silently deletes or
renews proposals to make room.

Use `Records.pending_projection/2` to parse an existing `pending.<id>` value
before presenting its data to a trusted management adapter. It checks the closed
proposal schema, exact integer version/times, bounded bytes and the lineage/text
identity. Its projection preserves original provenance and labels timestamps as
worker-recorded claims. Record schema version 1 is not a Collection revision;
neither the parsed proof nor those times authenticates source eligibility.
Standalone single-card proposal acceptance is exposed experimentally through
`knowledge review PENDING_KEY`. `Management.review/4` requires a matching native
channel and an unrestricted interactive mode, then reserves and admits a bounded
`notes.capture` operation through the existing Consent ledger. Its epoch/policy
must match the facts used for display and publication. An admitted resource
reservation alone grants no selection, source or publication authority.

Trace `Management.begin_acceptance_review/7` through an
actual signed Collection observation into `PendingAcceptance.prepare/4` and
`ManagementTerminal.begin_historical_accept_review/5`. The target Identity,
active Consent and Collection owners, plus the management journal owner, cover
the exact historical display and verified release. This display makes no claim
that the original source is currently eligible and needs no original-source
lease. It releases the target owners before waiting for human input.
The actual native display also includes the accepted category's retention rule
and policy expiry. That annotation is derived from the held installed selection
and bound by the native display receipt; final policy equality prevents changing
the rule after confirmation.

After exact native `accept CODE`, `publish_consumed_acceptance/7` independently
acquires and verifies the original source, reacquires the current target owners
and reproduces the same facts before consuming the one-use Review permit.
Revision, physical value hash, signed deadline, exact text, project/client and
policy must still match. The linked acceptance event preserves the original
provenance; it records the user's decision rather than external truth or other
effect permission. Missing sources or changed consent refuse publication even
when the historical card was displayed. An uncertain effect is inspected rather
than replayed. Current-note recall still requires fresh source authority; this
historical review path supplies none.

After all native/source/target owners close, public review settles measured
encoded event/request input and receipt output under the reservation. Known
refusals settle zero; uncertain completion retains liability. It prints both
reservation and management journal IDs. `Consent.operation/3` and the management
inspection command read recent or compacted records without granting authority,
settlement or replay. A bare reservation ID can be inspected before any journal
exists; an accepted journal additionally correlates its native event to that
ledger entry.

Without a key, `knowledge review` uses the existing bounded metadata index under
the admitted project/domain and retained management snapshot. It reads no values
and requires no active capture grant; it remains available after revocation.
Its generation, key/revision/hash/size and partial coverage describe historical
metadata, not signed eligibility. Actual selected review authenticates the target
again. No metadata list can promote a proposal.

Run the public mode checks with `mix test test/ipse/cli/management_review_public_test.exs`.
The opt-in `genuine_pending_public_review` Session control starts with real
synthetic-model capture, then exercises the actual CLI/native interaction,
finite allowance, wrong code, cancellation, duplication, expiry, revocation,
input-owner loss and read-only inspection. Use an isolated freshly built bundle
for artifact evidence; the [CLI integration record](pending-review-cli-20261031.md)
separates those controls from installed/provider qualification. The earlier
[boundary decision](pending-review-boundary-20261031.md)
explains historical display. The separate `genuine_pending_accepted_recall`
control adds a fresh Session on an explicitly registered loopback Ollama fixture,
then missing-original-source and altered-acceptance-event refusals. It verifies
actual request content and Saved reconstruction. Complete batch/reject/correct
journeys, installed behavior and model quality remain open.

Saved override values wrap the pure retention policy with separate native operator
evidence under `evidence.sources`, so they can satisfy constrained publication.
`Records.saved_override/2` checks the complete wrapper and matching lineage before
applying it. Bare policies, foreign lineages and weak-origin wrappers refuse.
This format check does not establish operator acceptance; that remains the trusted
management workflow's responsibility.

The native builder also declares `operator.json` in the artifact's hashed file
inventory. `Knowledge.Contracts.operator/0` supplies closed structural constraints
for notes, pending proposals and each of the four retention choices, plus reviewed
literal/proposal recipe data referencing the exact constraint digests. The builder
uses the public `Ipse.Extension.canonical_digest/1` helper rather than a private
host encoder. A capture
schema excludes pin/history categories. Separate retention schemas prevent an
ordinary choice from carrying a duration or silently becoming a pin. These use
the existing supported JSON Schema subset and introduce no schema evaluator.
They do not authenticate origin or establish operator acceptance. The managed
publication adapter authenticates the source and the host Normalizer independently
checks lineage, category and source clocks under the Collection lock. Its version-2
packed anchor/live pages preserve deadlines after public-record pruning and reject
experimental version-1 metadata. Managed recall must still apply these witnesses
at every dispatch before standalone activation is ready.

An operator adapter can inspect this data with
`Artifact.read_declared(store, digest, "operator.json", 65_536)`. This revalidates
the installed artifact and then rechecks the selected file's declared size and
digest. It loads no extension code and grants no permission. The sidecar is data
from a selected artifact, not an instruction to execute code or enable a feature.

To trace the actual boundary, run:

```sh
mix test test/extensions/knowledge/knowledge_records_test.exs
mix test test/extensions/knowledge/knowledge_contracts_test.exs
mix test test/extensions/knowledge/knowledge_capture_test.exs
mix test test/ipse/extension/notes_publication_admission_test.exs
mix test test/ipse/session/managed_tool_use_test.exs --only publication_prerequisite
```

The first two exercise pure records and declarative contracts with synthetic
proof inputs. The third checks worker continuations in a separate VM. The last
two separate real native admission/minimum-deadline controls from pure own-root
prerequisites. The [genuine Session control](remember-publication-absence-integration.md)
and terminal evidence cover their own compositions; older cohorts remain tied
to their original sources/helpers. These checks use no real model calls.
Conflict, denied and
unknown outcomes terminate rather than automatically retrying a mutation.

Standalone permission setup and the reviewed-statement command use separate
operator/native observation paths. Public `knowledge forget NOTE_KEY` now
authenticates one selected signed literal, presents complete facts, consumes its
one-use Review permit under fresh locks and settles a reducing CAS. The
[current-source public integration review](management-forget-current-source-independent-review.md)
distinguishes its trusted synthetic seed from genuine capture. A late or lost
Review completion can be unknown even when forgetting happened; inspect the
printed management journal before fresh work. The retained correction/supersession
protocol and its historical tests are not an enabled public path.

Turn-local managed recall and explicit expired-literal reclamation also have
focused integrations. An accepted decision has a separate version-6 dependency;
its original weak source is never relabelled as a literal operator assertion.
`ManagedRead` discovers the immutable acceptance link under protected ownership,
retains its original committed management journal outside Identity/Consent,
acquires the original Session source, then reproduces the selected read. The
signed anchor/live rows, actual event, note and link must agree before the host
admits a value to the worker. `Records.accepted_projection/2` then checks only
the delivered structure; it supplies no source or decision authority.

For a mixed or accepted batch, the worker emits `note_parts_v2` with an explicit
`claim_kind` column: `accepted_decision` or `literal_claim`. Byte offsets still
refer to the unchanged UTF-8 text. Literal-only batches retain their v1 format.
`ManagedReads` binds the exact value/result to the type-6 receipt, and
`ManagedUse` reacquires the original journal/source and current policy before
result release or inference. Preflight verdicts are historical; actual use runs
inside the existing protected callback. The Collection callback must return a
two-element result tuple so its native owner can confirm cleanup before the
adapter expands that result for its caller. No new native locking protocol or
effect permission is introduced by this read path.

Recall measures the complete rendered envelope, including
index and coverage framing, against the host's available context bytes. The
public SDK computes that measurement without loading Session or host Context
modules; the host uses the same framing functions when it constructs the saved
Reference. The estimate grants no publication authority. If even
the framing does not fit, it clears the turn-local contribution and reports
partial coverage rather than proposing an oversized publication. Each search
reports partial coverage when it starts from a later cursor, even at the last
page, or when a current record cannot be read. A single continuation cannot
establish coverage of earlier pages. A query with no lexical terms refuses
before indexing rather than matching every note. Recall and search compare each
read's key, revision, value hash and byte count with the indexed metadata; a
mismatch is a coverage gap and is not returned as the indexed record. Index
traversal also rejects an empty page with a
continuation, repeated continuation tokens and repeated keys, and bounds page
count by the 32-candidate limit. The visible count must remain stable across a
traversal, and a traversal from the beginning cannot end before accounting for
that count. An inconsistent continuation ends the pass with
`invalid_index_progress`; it does not manufacture complete coverage.
If a later index request itself fails during automatic recall, discard metadata
from earlier pages before publishing unavailable coverage, and report an unknown
candidate count. This prevents an abandoned traversal from advertising stale keys.
Index pages and current reads also have to report the same Collection generation.
If a read sees another generation, discard the accumulated notes and index keys,
report unavailable coverage and an unknown candidate count. After all reads,
including an empty index, a bounded first-page check must report the same
generation and count before the result is offered. Refusal or mismatch withholds
the pass. These checks do not hold the Collection across the whole pass or prove
that no change occurs after the final check.
Complete proposal management, historical-use delivery, shared
evidence qualification, full correction/recovery coverage and automatic capture
quality remain open. The explicit Memory procedures retain their existing scope.

## Verify independent selection before algorithm work

From a built checkout:

```sh
IPSE_SELECTION_ARTIFACTS=$(mktemp -d)
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_SELECTION_ARTIFACTS/corpus" --package corpus --preset state-lexical
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_SELECTION_ARTIFACTS/graph" --package graph --preset state-explicit
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin --output "$IPSE_SELECTION_ARTIFACTS/research" --package research --preset offline
elixir dev/verify.exs source knowledge-independence \
  --sdk _build/dev/lib/ipse/ebin --input "$IPSE_SELECTION_ARTIFACTS"
```

Expect nine memory/package/scope cases plus catalog refusal, with zero model
requests. [The proof](../../../dev/verification/knowledge.exs) pairs session WorkingMemory
and project/operator persistent Memory with each package, in distinct logical
bindings. Disabled/enabled idle/resume counters remain zero for workers, State,
MCP, embedding, and text work. Actual commands provide positive controls.
Same source IDs do not turn notes into retained evidence or vice versa. Forgetting
one store preserves the other's content. Research owns no retained knowledge store.

Inspect actual namespace-relative filenames/hashes: Research+Memory has one State
file; Corpus/Graph+Memory have two. Empty inventory proves no inert-resume claim.
Counters use arity-only OTP trace instrumentation, without arguments/payloads, and
require every target to be instrumented. Confinement needs separate OS evidence.
All three packages plus Memory exceed the existing 16-KiB catalog and must refuse
before Session/worker/store work. Pairwise compatibility grants no larger catalog.
Repeat the same artifacts in installed mode for runtime compatibility, not new quality evidence.

## Trace one source and a revalidated query

Follow Corpus source validation into Store draft claim, immutable content/chunk
writes, and final root CAS. Storage revision advances on every root mutation;
source generation identifies one complete text version. Pages/projections/citations
bind generation and content hash. Source ID alone identifies no current bytes.
[Storage training](../../developer/knowledge-storage.md) owns capacity, CAS, suppression, and migration.

Evidence's safe integers stop at 9007199254740991. Generations are positive;
observation/event/expiry/fact/query times are nonnegative, nullable only when optional.
Commands validate before storage reads where applicable; imports validate captured
fields after destination snapshot and before publication. Remote capture rejects
unsafe timestamps before typed results.

For BM25, Store supplies validated sources/heads/revision tokens/coverage. Evidence
ranks at selected time; Corpus revalidates captured roots immediately before return.
A mismatch conflicts instead of publishing stale success. It cannot revoke output
already returned. `as_of_ms` filters the currently retained generations; it does
not reconstruct a past snapshot. For example, after generation two replaces
generation one with `observed_at_ms: 200`, a query with `as_of_ms: 150` excludes it
without recovering generation one. Completeness covers eligible retained generations,
so this can be a complete abstention. Suppressed, expired/future-source, and
time-excluded-fact diagnostics remain explicit exclusions.
Unpublished source work or failed required components stay coverage gaps: an empty
ranking with a draft is partial, not complete abstention.

Graph/hybrid fusion retains each component's claims/gaps/coverage. A completed rank
calculation cannot certify bounded traversal. Only actual missing-embedding policy
can take explicit lexical fallback; graph/transport/malformed-model failures cannot.
The fallback remains partial. `Evidence.query_scope/4` owns direct/combined consistency.
Use `test/extensions/knowledge/query_completeness_test.exs` to compare matches,
no-match, unpublished drafts, forgotten/expired/future sources, and depth-limited graphs.

## Follow acquired document bytes into cited storage

`Corpus.source` offers two explicit document paths. `put_document` accepts a
filename and canonical `bytes_base64` with the ordinary source identity,
generation, expected revision and times. It extracts supplied bytes; it opens no
file. `read_document` accepts a workspace-relative `.docx` path and
`expected_sha256` instead. The compiled `state-documents`, `mcp-documents` and
document Collection presets explicitly declare native `host.tools` authority
for that path; options cannot upgrade an existing lexical artifact.

Trace `Corpus.acquire_document/4` through a native `tool.call` to `read` with
explicit `encoding: "base64"`, a 4096-byte page bound, `byte_offset: 0`, a
32768-byte complete-file bound and an optional expected hash.
The host checks the complete binary envelope, path, count, hash and current
workspace/resource scope. Initial generation-one/revision-zero acquisition may
omit the expected hash with explicit `null`; refresh requires a concrete hash.
Later pages require that hash. Corpus validates exact offsets, page hashes,
complete byte count and the reconstructed complete-file hash. After extraction,
it requests another native page-zero read pinned to that hash; the host again
hashes the whole bounded file. Only a matching result reaches Store. Every
acquisition call counts against the existing action allowance before a State/MCP
write plan. Worker code never opens paths or enlarges SDK/result envelopes.

`Documents.source_payload/1` converts the extraction into source text and typed
segment metadata. Supplied `put_document` keeps its 8192-byte extracted-text
bound. Workspace acquisition supports up to 65536 extracted UTF-8 bytes,
32 segments/chunks and 16384 canonical metadata bytes with at most 32 warnings.
It does not trim text, warnings or locators to fit. Metadata at most 2,048 bytes
keeps the packed receipt version 3: canonical document JSON and its digest wrap
the supplied-byte version 1 or acquired-byte version 2 receipt. The latter binds
the actual host acquisition operation and relative path. Larger metadata uses
compact receipt version 4, retaining exact manifest hash/byte count, segment and
warning counts, origin and one immutable manifest-head reference. Storage paging
does not change the extraction recipe.

Follow larger manifests through `document_content` JSON slices of at most 1,024 bytes
and `document` progress records. At most 16 slices/32 records fit the bound. Each
immutable page binds partition, source, generation, draft, kind, ordinal and hash.
Hydration validates exact offsets, previous links, canonical bytes and complete
typed segments/warnings against the full source text. A missing, reordered,
revised or forged page refuses; a compact header alone is not readable evidence.
Selected Source version 2 holds the privately hydrated document plus compact
origin; Source version 1 remains readable. State/MCP replies carry bounded
individual records, preserving SDK strings/depth and result limits. Single-envelope
import refuses Source version 2 until paged migration is implemented.

Larger workspace text or metadata opens the existing source draft.
`continue_document` reacquires the hash-pinned original and exact typed extraction,
rechecks draft/revision/text offset and metadata offset, then stages one metadata
slice before text, appends one UTF-8-safe 4,096-byte part, or publishes the complete
staged source. Ordinary `append` and
`publish` cannot substitute content into a document draft. The selected earlier
source remains intact until final CAS publication. An interrupted stage never
replays on resume. Draft expiry is threaded through the shared Store IO adapter
as `write_before_ms` for each proposed staged/root write. State and ordinary
fixed-profile document writes stage and sync first, then the native owner checks
the inherited deadline immediately before selecting the pointer. The original
contract permits a pre-expiry decision to finish physically later; it does not
make clock sampling and rename atomic. Notes capture uses its own narrowly
admitted v3 scope; reviewed forgetting has its separate one-use contract.
Retention/supersession and managed document mutations retain their gates. Never
drop a domain deadline to retry a draft. Explicit collection first clears an expired draft claim while
preserving the selected source, then reclaims unreferenced pages. MCP uses the
client deadline gate; this does not claim a remote server publication fence.

Follow normal Store CAS publication, hydration and `Evidence.citation/4`. A
version-2 public citation binds original binary SHA-256, extraction version,
format-specific locator and segment-local byte range, in addition to source
generation and literal quotation. Evidence revalidates the typed receipt,
canonical envelope and source spans. An ordinary text `put` cannot smuggle in
a document receipt. Partial extraction remains partial in query gaps and
coverage. Replacement and suppression use ordinary source management; the
current implementation does not watch source files or invalidate an acquired
snapshot merely because its path changes later.

Run the worker and actual Session paths together:

```sh
mix test test/extensions/knowledge/document_ingestion_test.exs \
  test/extensions/knowledge/document_acquisition_session_test.exs \
  test/ipse/extension/tool_action_binary_test.exs
```

These controls cover stored paragraph/table citations, replacement/forget,
forged metadata, changed-file refusal before writes, exact read operation
binding and owner-loss/inert-resume behavior. They use synthetic Word packages
and local State/CAS fixtures. They do not establish real Word fidelity,
larger-document storage, installed qualification or retrieval quality. The
[operator procedure](../../operator/corpus.md#acquire-a-small-word-document-from-the-workspace)
shows explicit artifact selection and a complete command.

### Inspect the extraction boundary

`Documents.extract/3` accepts already acquired bytes and a filename; it neither
opens the source path nor authorizes a fetch. The result binds the original binary
hash, an extraction recipe, and bounded text segments with format-specific
locators. Text and Markdown use byte-exact line offsets. The DOCX reader checks
package authority, bounds ZIP expansion and XML parsing, includes insertions, and
excludes deletions and supported hidden runs. Unsupported content stays partial
or refuses rather than claiming complete coverage.

Referenced headers and footers are extracted once per part and their locators
identify the region. The result remains partial: it does not resolve section
inheritance, page layout, or which pages display the text. Only bounded internal
relationships with matching content types are admitted; unreferenced parts are
not extracted.

Footnote, endnote and comment paragraphs carry their annotation ID. The parser
requires distinct numeric IDs within each part and refuses paragraphs outside
an annotation. A uniquely matched visible reference in the main body supplies a
`reference_site` paragraph locator and UTF-8 byte offset; it is a point, not a
comment range. A unique pair of direct paragraph comment-range markers before
the matching reference also identifies a nonempty span of visible extracted
text in that same emitted paragraph or table cell, with UTF-8 byte offsets.
Hidden or unexamined range markers in the main story conservatively suppress
range links. Multiple visible references leave an annotation unlinked;
duplicate range markers prevent a range. Unreferenced annotations and
references in paragraphs with no extracted text have no site.
Other document stories and ranges spanning paragraphs remain unresolved, so
annotation parts and references mark coverage partial. An annotation's text
alone does not establish where it applies in the document.

DOCX relationship targets are never fetched. A checked external relationship,
an unexamined internal relationship, or an unexamined relationship part marks
the result partial. Relationship warnings do not repeat targets or arbitrary
unexamined relationship-part names. Malformed target modes and scheme or network-path targets
without explicit external mode refuse. A normal document with relationships the
reader does not interpret can therefore be partial even when its visible body is
readable; inspect the result and original document before using it as evidence.

Recipes are format-specific: `Documents.version("docx")` is
`ipse-documents-v11`, while text, Markdown and PDF use `ipse-documents-v2`.
The legacy `version/0` returns the v2 value; use `version/1` when binding an
extraction to a source version. Earlier DOCX results are not automatically
migrated or equivalent. Future indexing must explicitly rebuild or requalify them.
The optional PDF backend requires a separately host-admitted protected parser;
its installation does not activate PDF acquisition. The
[parser contract](../../../native/ipse-pdf/README.md) describes its lifetime and
limits. The Corpus paths above provide bounded ingestion and cited retrieval.
Extraction alone supplies neither current-source authorization nor retrieval
quality qualification. Larger originals, full document capacity and paged-source
migration require separate storage work.

Exercise synthetic DOCX relationships, bounded XML and Unicode extraction from
the repository root:

```sh
ERL_FLAGS='+S 2:2' elixir -e 'ExUnit.start(seed: 20270116); Code.require_file("test/extensions/knowledge/documents_test.exs"); Code.require_file("test/extensions/knowledge/documents_fidelity_test.exs")'
```

One fixture opens a loopback listener to verify that an external relationship
is not fetched. These parser controls do not establish real Word fidelity,
PDF quality or migration; the separate Session controls exercise the bounded
ingestion path.

## Keep source bytes distinct from semantic support

Raw SHA-256 identifies text/vector bytes; ordered tagged JSON arrays identify domain
objects. Use Elixir `JSON.encode!/decode!`, not raw Erlang encoding: binary sizing
and `nil`→null semantics matter to persisted IDs. Sources allow 64 KiB UTF-8,
with at most 32 chunks. Legacy sources keep their 2048-byte recipe; explicit
Collection Source3 uses the versioned 4096-byte recipe. Document chunks remain
inside their typed segments, so separator bytes need not belong to a chunk.
Citations bind generation/content/chunk,
absolute byte range, literal quote/hash, URI, times, and origin. Quote bounds are
1024 UTF-8 bytes. None proves entailment, authenticity, or freshness.
Compact fact-page reconstruction uses `Evidence.citations/2` to validate one
source and chunk list for up to 256 spans. Each reconstructed citation still
checks its own range, quote, chunk and document locator, and the fact projection
must repack to the exact original pages. A malformed member refuses the batch.
The graph adapter similarly batches source-span validation after checking every
fact's shape; an empty explicit fact list remains valid for a valid source.
Those checks establish attribution to source bytes, not the truth of a relation.

BM25 uses k1=1.2 and b=0.75. Token offsets retain original half-open byte ranges
through normalization, including case mappings that produce multiple normalized
terms. Never apply downcased-string offsets to original bytes. The Unicode fixture
places a match after byte 1024 and checks the actual quote.

The shared excerpt selector preserves an entire short chunk. For a longer one,
it finds maximum distinct query-term coverage within 1024 bytes, shortest matching
core, then earliest original start/end. Terms from the same original token retain
one span. Whole original tokens longer than the bound still score, without counting
as complete-token coverage.

Mechanical text units end at LF or ASCII sentence punctuation followed by whitespace/
EOF, retaining trailing whitespace. Decimal punctuation stays within a unit while
abbreviations can split. A fitting whole-unit hull keeps its earliest fitting
preceding unit, then following units; preceding context wins. If too long, center
a codepoint-safe contiguous window around the core, transferring space at chunk
edges. No-match falls back to whole-unit or codepoint-safe prefix. Never concatenate
disjoint text, normalize quotes, or cross chunks. Citation reconstruction validates
that selection independently.

For `migration` in `Ada owns the migration. It proceeds only after audit.`, both
short sentences remain. Distant qualifications can still fall outside a chunk or
byte bound. Source citation integrity is not semantic completeness. Tests include
complete short chunks, omitted context, exhaustive windows, and encoded Answer
packing. Six 480-byte passages can fit where only three of six 900-byte passages
fit; escaping can reduce that number. Do not shorten away conditions to pack more.

## Retain compatible and conflicting attributed facts

Facts keep every support citation and extraction identity. Traverse positive edges
only. Before classification, claim context retains negative assertions on reached
subjects, including the seed, plus explicit opposites of selected positive facts.
A negative object's name does not become a traversal node. Conflict means same
case-insensitive subject/predicate/object with opposite polarity. `Release requires
quiescence` and `Release requires tests` are compatible: arbitrary predicates do
not imply single-valued relationships. Preserve original fields/IDs/quote bytes.
An unvisited compatible edge can still leave traversal partial.

Validate all input provenance before applying time exclusions, including facts not
reached later. Expired valid facts can be excluded; missing/replaced provenance
remains stale even when expired, and forged spans still refuse. Whole query input
is conservatively bounded at 8192 facts from retained-record/manifests limits,
with encoded snapshot constraints. One source/profile has a sole valid head;
predecessors retain profile and cannot repeat keys. Per-head facts allow 256 and
per-extraction 32. Complete claim context separately permits 256. Overflow returns
`graph_context_limit` before classification, without truncated claims.

Seed selection validates facts at as-of time, then matches complete Unicode entity
names, longest subject first with stable spelling ties. `Lease` does not match
inside `Release`. No subject match uses the query itself. Coverage records seed,
traversed edges, context/negative/counterassertion counts. At depth exhaustion,
unselected positive outgoing frontier edges make coverage partial; leaves, empty
frontiers, and fully consumed cycles can be complete.

Top-k bounds returned evidence, not each attributed claim's complete citation basis.
Claims retain support outside the rank. Without assessed facts, classification stays
open with `semantic_support_unassessed`. Publication uses zero-based evidence indexes
only when every internal basis citation appears in final evidence; otherwise retain
full basis. Fusion/truncation must create no dangling or lost provenance. Run
Evidence, graph-population, completeness, and complete-publication controls before
changing either bound.

## Fuse chunks while retaining exact citations

The reference configuration combines lexical and native dense retrieval, with
`rrf_k: 60`, `top_k: 10`, no graph component and no reranker. Build `state-dense`
with an empty `rerank` registry and select its hybrid route. The optional
`state-semantic` preset additionally grants `host.model` for reranking and was
not the measured reference artifact. The [operator example](../../operator/corpus.md#add-explicit-embeddings-and-reranking)
names that route `blend`. The [comparison record](../2026-10-23-p27-heldout-comparison/index.md)
explains the selection and its limits. Keep this choice in package configuration;
it requires no domain branch in Session or automatic provider selection.

Rerank/span IDs and fusion identity serve different purposes. `Evidence.fuse/3`
uses reciprocal rank with constant 60 over namespace/source-key/generation/content/
chunk identity. Each component contributes once per chunk despite multiple spans.
A lexical-first/dense-first chunk receives 1/61+1/61 and one final slot. Best
component rank selects its representative citation; earlier component wins ties.
Corpus orders lexical, dense, graph. Preserve every graph claim's original basis,
even outside the representative/top-k. Do not change persisted chunk/span IDs merely
to combine scores. Coverage remains the combination of actual component coverage.

Rerank input assigns deterministic e1..e16 IDs with canonical chunk:byte-start:byte-end
references and quote prefixes up to 128 bytes. A model returns one order object
naming every ID exactly once. Missing/duplicate/foreign IDs, extra fields, or bare
arrays refuse without fallback/repair. Accepted order maps to canonical candidate
IDs. The immutable continuation/host request binds identity, without another nonce.
Evaluation independently parses references, exact chunk/range/prefix, and ID order
without loading production domain code into the host.

## Preflight projections before inference

Store first claims a source-bound projection draft with token and capacity plan.
Entrypoints check remaining read/effect allowance before calls, then return validated
results through that token. Store owns packing and final publication. Explicit
fact batches pack actual JSON before claim, up to 32 facts; count is not reservation
for 32 worst-case records. Model extraction derives affordable allowance before
egress. Output exceeding it leaves a draft for inspection/exact abort. Eight heads
per source allow updates to an existing kind/profile at capacity, while a ninth
refuses before draft/model work.

Extraction/rerank profiles can select `output_contract: "json_schema_v2"`; omission
retains v1 text. Recipe version and output contract differ. Structured helpers
use task-specific schema, native Ollama, 12-KiB request within unchanged SDK bounds;
v1 retains 8 KiB. Encoded task input separately permits 4096 bytes. No source/input
is shortened to fit or rerouted to another provider. See
[accounted effects](../../developer/extension-effects.md#request-bounded-text-inference).

Extraction supplies max-facts plus c1/c2 local chunk IDs. Facts contain exactly
subject/predicate/object/polarity/chunk/quote. Negative means explicit denial,
not absent evidence. The model copies a unique literal quote, without generating
hashes/offsets. Count overlapping matches inside that selected chunk; absence,
ambiguity, whitespace/Unicode normalization, wrong chunk, duplicate keys, or any
invalid proposal refuses the whole response. Derive absolute byte spans and validate
them. Store revalidates chunks/live draft at commit. Do not apply query-time expiry
during publication and silently discard future/past validity intervals.

The private adapter also accepts explicit byte windows within canonical chunks,
up to 2048 bytes per window, for the larger Collection chunk recipe. Windows
must be valid UTF-8 and retain the original chunk identity. Quote uniqueness is
checked across the entire chunk, and citations use absolute source offsets. A
window result reports incomplete source coverage; quotes spanning windows may
be missed. No public Collection producer currently uses these windows, and the
adapter's input check does not replace current-source authorization at dispatch.
`Adapters.extraction_windows/3` plans overlapping windows for one canonical
chunk using a conservative encoded-input budget. Its reported guaranteed quote
length reflects the smallest window and overlap, capped at 1024 bytes; escaped
input can reduce that guarantee. A caller must still track each window's result,
source eligibility and completion before claiming any aggregate coverage.

For a chunk at byte 2048 containing `Éclair does not require β.`, this proposal
preserves both multibyte characters and derives the absolute range:

```json
{"facts":[{"subject":"Éclair","predicate":"requires","object":"β","polarity":"negative","chunk":"c1","quote":"Éclair does not require β."}]}
```

If the quote appears twice in that chunk, refuse; another selected chunk containing
the same quote does not make this one ambiguous. Follow package controls for
future-valid, expired, future-observed, and wrong-generation attribution.

## Authenticate embeddings and their complete vectors

Embedding.create v2 returns `selection_sha256` authenticated by the host's approved
profile binding. Adapters retain it in Evidence v2 vectors. Compatibility requires
valid current vectors with equal selection hash, host profile, reported model,
width, and encoding. Legacy v1 vectors remain readable but never compare densely.
Changed/legacy selection yields missing-embedding refusal or explicitly partial fallback.

For the opt-in `collection-dense` producer, Corpus `generation_produce` action
`selection` reads configured public metadata through `embedding.profile`, without
inference or a Usage charge. It returns `configured_profile`, `selection_sha256`
and `reported_model: nil`; configuration is not an observed provider model.
Keep its returned selection hash
on a v2 `embedding.create` request as `expected_selection_sha256` when the work
must use that same configuration. The host refuses a changed selection before
approval/intent; the result must still match the reported profile/model, complete
inputs and vectors. Read [the effect contract](../../developer/extension-effects.md#generate-and-reconstruct-embeddings)
for the closed shapes and saved snapshot binding. Neither bootstrap nor selection
pinning revalidates a captured source's eligibility or supplies authority for
stale-source egress. Version-1 public `page` delegates to the bounded v3 producer: a confirmed
pending claim binds exact authenticated source byte ranges, raw/canonical hashes
and captured job/catalog/root before inference. Each batch supplies `source_guard`
and its expected selection. `DocumentSourceUse` authenticates retained logical
records under the native read closure; live `DocumentEmbedding` admission binds
the claim's actual committing operation to this invocation, known prior batches,
trusted host time and the final one-use egress decision after approval. The short
lock does not recall bytes already admitted before a later change.

Select operator collection binding v2 with `source_use: shared_producer_v1`
explicitly; every embedding from that identity requires a guard. The configuration
generator's `--collection-source-use shared_producer_v1` is restricted to
`corpus/collection-dense`; old calls retain binding v1. Explicit inference service
metadata passes through the same generator into normal host validation. There is
no route discovery or fallback. An unsupported v1 instance can retain an inert
pending claim and refuse guarded inference without egress. `inspect` is read-only;
pending/unknown and legacy v2 claims cannot be replayed or adopted by another Session.

Version 2 uses v4 claims and ready slots for successive pages of at most eight
1,024-dimensional rows. A known ready result exposes a complete public command
for the next cursor; the next invocation authenticates the current source and
commits its own claim. A null continuation only means that the captured group's
vector pages are ready. Facts, group completion and full capacity remain open.
The [two-page synthetic Session](shared-producer-v4-public-session.md)
exercises the public continuation against an initially empty selected root. The
[guarded Session](shared-producer-guard-session.md)
and [finite-TTL](shared-producer-finite-guard-session.md)
controls exercise the private artifact's exact production delegation using a
synthetic loopback endpoint. Canonical artifact adoption is a separate build/
protocol check accepted in the
[public adoption review](shared-producer-public-adoption-independent-review.md).
Executed receipt validation remains distinct from independently
authenticated historical model provenance; its flag stays false.

Validate entire projection-chain homogeneity before deduplicating chunk IDs: a newer
duplicate cannot hide an incompatible older row. Compatible batches append. Explicit
reindex with a changed selection/model or legacy vector replaces that head's chain
with `previous: null`, preserving other heads, source, facts, and suppression. Detached pages
need explicit collection. New drafts/tokens/plans bind vector_version 2. Older drafts
remain inspectable/exactly abortable, without promotion or a fresh next step while active.

Bind each result index to the SDK's canonical digest of the exact dispatched input,
and require that digest on every page. Raw text hashes alone are different from
the host's canonical input digest and authenticate no returned vector. This
adapter check does not by itself reauthenticate previously stored vectors or prove which
model weights the provider used. Store checks each new vector against the source
chunk before publishing a projection; a mismatch refuses the entire commit. At
dense query time, Corpus compares each stored
vector's input digest with the current raw source chunk; a mismatch follows the
configured missing-embedding policy and requires reindexing. The stored row is
not deleted. Check descriptor identity, offsets/dimensions,
canonical Base64, float32 encoding, and full vector digest.
All finite float32 values including signed maxima are valid; NaN/infinity refuse.
Do not shorten vectors. Two 4096-wide vectors require 12 coordinate pages, manifest,
final CAS, claim, and embedding call: 16 effects. State admits one/two selected chunks;
MCP admits exactly one and counts reads as effects. Check complete capacity before
dispatch; metadata-heavy facts can need smaller batches.

The selection proof uses two loopback services with equal names/width but different
vectors. Query at B must refuse vectors indexed at A; explicit fallback stays partial.
Reindex at B restores eligibility. Timeout-only changes permit reuse, but a changed
reported model requires reindex. These controlled vectors prove identity separation,
not weights or retrieval quality.

## Publish and materialize the complete domain value

Store/Adapters use private done/call/stop continuations. Entrypoints turn only exact
host calls into SDK proposals and resume the same owner. Initialize every private
map key before update. Unknown effects terminate, without empty success or retry.
Each finish passes the whole public object to `ResultPublication.prepare/1`.
Invalid aggregates become explicit `result_too_large`; quotes/bases are not dropped
to align with 4096-byte transport fragments.

[Invocation training](../../developer/extension-invocations.md) owns terminal output/leases/closure.
Only committed final receipt makes saved output readable. Consumers materialize the
exact delivery before interpreting status/evidence/claims/coverage; failed reads
are retained errors, not empty rankings, fallback, or repeated queries.

```sh
elixir dev/verify.exs source knowledge-complete \
  --sdk _build/dev/lib/ipse/ebin --input "$IPSE_SELECTION_ARTIFACTS"
```

The [five-check proof](../../../dev/verification/knowledge_complete.exs) preserves ten
full quotes, escaped citations larger than fragments, graph bases beyond top-k,
opposite assertions, hashes, inert restart, no host-loaded domain modules, and zero
model calls. Repeat in installed mode with the same artifacts and compatible archive.

## Distinguish independent Research from the native ledger

Independent Research ranks provided sources or selected search/fetch gateway output
with BM25 and optional rerank. Its provided ledger normalizes supplied labels to open
assertions; it creates no native host receipts or retained Corpus. Default as-of
time is selected after capture so completion-stamped fetches are eligible. Explicit
safe integer fixes time; null refuses. Observations after selected time and expiry
at/before it exclude. Coverage retains raw captured bytes. Before each fetch/rerank,
sample remaining allowance once; below 1000 ms refuses, otherwise pass that same value.
An empty fetch queue ranks without requiring allowance for another fetch.
[Storage contracts](../../developer/knowledge-storage.md) specify exact gateway envelopes.

Native [`Tools.Research`](../../../lib/ipse/tools/research.ex) instead captures literal
URLs/excerpts from uniquely identified successful recorded MCP results. It records
result/call hashes and completion-time basis; legacy results retain capture-time
basis. Titles/authors/publication claims stay unverified. A URL and excerpt can
both occur in a multi-page result without belonging together, so inspect the source.
Its ledger lists bounded recent references without repeating retrieval.

Native claims bind unique source IDs. Supported/inference/conflict need a source;
open may have none. Shape/reference validation proves no entailment. Exact repeated
capture is idempotent. Bounds are 16 sources/32 claims/64-KiB ledger, excerpts 4000 bytes,
statements 1000 bytes/eight references, URL 2048 bytes, call ID 256 characters, arguments
16 KiB, and body/header/recovery result 66048 bytes. Bound refusal truncates no evidence.
Children cannot use these tools.

Owned work reads original events outside Session; durable research source/claim
precedes ordinary tool-result publication. A crash between them leaves a durable
entry with uncertain call outcome. Resume/export validates preceding evidence without
capture/retrieval/file replay. `ipse research --resume ID` exports this ledger only,
not Research's provided assertions. Narrative file writes need ordinary approval.

## Practice an algorithm change and prove its scope

Add two development sources with shared terms/different frequency and independently
specify order. Follow BM25 tokenization/ties, then the tests in isolated VMs:

```sh
mix test test/extensions/knowledge/evidence_test.exs test/extensions/knowledge/profiles_test.exs
mix test test/extensions/knowledge/domain_regressions_test.exs test/extensions/knowledge/graph_population_test.exs
mix test test/extensions/knowledge/packages_test.exs test/extensions/knowledge/query_completeness_test.exs
mix test test/extensions/knowledge/build_spec_test.exs
mix test test/ipse/tools/research_test.exs test/ipse/tools/research_integration_test.exs
```

Build fresh artifacts and run source/installed `knowledge` and `knowledge-complete`
with exact spans/generations/revalidation/no model calls. Storage lifecycle races
have a separate [worked exercise](../../developer/knowledge-storage.md). Research MCP has its own
`knowledge-research` scenario and reviewed artifact. Protocol controls do not qualify
semantic answers. Follow [evaluation](../../developer/knowledge-evaluation.md) for held-out predictions,
independent citation judgments, resource measurements, and strategy selection.
