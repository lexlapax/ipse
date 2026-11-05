# Build source-bound knowledge behavior

Follow a retained source into a current citation, then change retrieval without
bypassing source identity, approved inference, or recovery. Corpus, Graph, and
Research are independent worker packages. The native Knowledge capture package
uses the protected collection SDK. These workers use the public SDK; they do not
load domain code into the host or open their own files/sockets/executables.
Start with the [operator procedures](../operator/corpus.md) and
[artifact builder](../../extensions/knowledge/README.md).

## Find the owners and compiled authority

| Source under `extensions/knowledge/src/` | Responsibility |
| --- | --- |
| `knowledge.ex`, `knowledge/records.ex`, `notes.ex` | Protected capture continuation, stable evidence and note retention |
| `knowledge/contracts.ex` | Inert operator-sidecar publication schemas and managed recipes; no authority or executable setup |
| `corpus.ex` | Source/query/index commands and final revalidation |
| `graph.ex`, `research.ex` | Main-tool facts/traversal, investigations and explicit provided/fetched State capture |
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
with empty retrieval registry; Research uses search/fetch/BM25/optional rerank; its opt-in `state-retained`
preset additionally selects State storage for explicit provided-text retention.
`state-fetched` combines selected MCP fetch with ordinary State retention; it has
no search, ranking or model export.
Reject unused/incompatible profiles before generating permissions. A syntactically
valid dense/graph/hybrid/remote-query profile is still invalid for Research.

### Follow packaged document selection

`dev/build-bundles.exs` builds the two lexical document presets alongside native
notes and writes their existing inert bundle catalog. `Bundles.inventory/0`
checks manifest identities without loading code. `CLI.Documents` constructs the
ordinary `documents` instance, exact manifest capability ceiling and project
State or document Collection binding. `Config.preview/5` validates proposed bytes
through normal resolution; no temporary operator file or artifact import is
needed for preview. This selection uses no semantic-notes activation overlay.

On `documents setup --write`, a fresh native `enable CODE` receipt binds the
complete escaped selection. The shared `CLI.Setup.write_configuration/4` writer
holds a retained OS lock at `CONFIG.lock`, rereads exact original bytes, imports
the digest-pinned bundle and optionally admits the explicitly chosen folder or
repository identity, then rereads before backup and private atomic publication.
Provider setup uses the same lock. Retain its inode after unlock. A failed save
can leave an inert artifact or explicitly admitted identity; it grants no saved
extension selection. The lock coordinates Ipse setup writers, not arbitrary
editors or hostile directory replacement.

`documents disable` reviews the selected identity and option digest, then saves
`enabled: false`. It retains trust/data and changes only subsequent new sessions;
it is not live revocation of a pinned worker. Replacement preserves old trust
entries and refuses an incompatible ceiling for an already trusted digest.
Keep unrelated options and provider profiles out of setup's rendered review.

Run the source controls together:

```sh
mix test test/ipse/cli/documents_test.exs test/ipse/cli/setup_test.exs test/ipse/extension/bundles_test.exs
```

The synthetic native journey
uses the shipped artifacts, ordinary mutation approvals, acquisition, exact
citations, Saved reconstruction and close/resume. Collection additionally needs
explicit `lexical_index` build before namespace query; successful ingestion alone
does not create that index. These controls establish source-runtime behavior;
rendered Word fidelity and full-profile capacity require separate qualification.

For the exact archive from a reviewed checkout, repeat the same fixture using
the packaged runtime and its four inert bundles: `corpus-collection-documents`,
`corpus-state-documents`, `knowledge`, and `knowledge-decision-shadow`:

```sh
IPSE_DOCUMENT_PROOF_PARENT=$(mktemp -d)
elixir dev/verification/documents_setup_installed.exs "$IPSE_ARCHIVE" "$IPSE_DOCUMENT_PROOF_PARENT/run"
```

Set `IPSE_ARCHIVE` to that archive first and retain its adjacent checksum. Run
from a development environment with Elixir/OTP, Rust and `tar`; the verifier
copies the existing precompiled ExUnit library and compiles the synthetic PTY
before launch. Runtime PATH has utilities and the package's own ERTS tools,
including its bundled `erlc`, without system Elixir/Mix/Rust/Cargo. It checks actual
CLI setup, ordinary action approvals, Saved/close/resume, disable, four refusal
cases, exact bundled code origin and unchanged extracted files. Both document
profiles also refuse missing-original evidence before and after an idle Session
reopen, then return the original citation when the same file is restored. The
reopen adds no extension invocation or action intent, or model request admission;
the numbered acquisition is not repeated. Private fixture logs and a structured
report stay under the new output directory. Run terminal suites sequentially
within a bounded job; synthetic input proves no human use.

## Follow protected capture from a Session source

Trace one reviewed statement from the terminal into a stored note, then into
the next conversation. The `knowledge/native` preset exports `capture` as a
tool and command, with no secondary inference and all seven profile registries
empty. Its argument contains text, category, reason, event time and an exact
quote selected through an opaque Session source handle. Operator procedures
belong to [Knowledge management](../operator/knowledge-permissions.md).

### Establish what the source supports

Start with `/remember preference Prefer concise answers.` in an idle Session.
`Session.prepare_assertion/4` binds a rendering to the native client/channel,
complete statement, category and project/artifact/policy scope. The one-use
input witness and `OperatorAssertion.receipt/3` record the actual native
confirmation. Session syncs it before invoking capture. SourceIndex exposes
the resulting `input.assertion.preference` occurrence through an ordinary
read handle; supplying JSON cannot create this origin.

Follow `Knowledge.handle/3` through source read, exact quote, the public SDK
proof helper, saved lineage override, existing-record lookup and managed
Collection commit. The host independently reconstructs the original proof and
checks the current protected permission. The worker needs the distinct
`host.collection.managed` capability and exact sidecar recipe digest; ordinary
read/write grants supply neither. The [Collection SDK](collection-sdk.md)
owns this admission boundary.

`Records.capture/4` creates a literal note only for a complete, available source
whose exact text, zero start offset and source/quote hashes agree. A reviewed
operator statement additionally needs a category-specific
`native_operator_assertion` occurrence. A typed host outcome supports only
`ordinary`. Plain messages, native question answers, selected fragments and
other attributed claims become pending proposals. A whole interactive message
can still quote somebody else. The host recipe repeats these checks; worker
classification and proof-shaped JSON supply no source authority.

Ordinary notes have a 90-day host ceiling; current statements and preferences
follow the reviewed category rule. Pending proposals have seven days and a
retained ceiling of 64 records/256 KiB, including expired rows. The v3 normalizer
checks the held Collection summary through `PendingCapacity.check/3` before
publication. The worker does not load other proposal values to count the queue.
Neither silently removes proposals to make room.
Recorded endorsement establishes the user's statement, not external truth or
permission for another effect.

### Check a new proposal's queue and saved allowance separately

Follow the pending branch from its exact-prefix existing-key index. A duplicate
finishes as `existing` before allowance or queue inspection, without another
publication or a renewed lifetime. A new pending candidate requests the public
`saved_policy_budget_v1` status purpose through `collection.call`. The host binds
that read-only observation to the admitted capability, project, namespace,
artifact and current policy epoch. The worker validates its closed resource
vectors, arithmetic, warning dimensions and period; malformed or unavailable
metadata is a refusal, not inferred exhaustion.

The worker treats zero available operations, input or output bytes as no observed
capture capacity, including a zero limit with zero charge. Unused model/download/
cost dimensions do not block a capture merely because their zero-unit reservation
matches a limit. The compact notice places readable advice before its full
unchanged accounting snapshot so the ordinary bounded terminal preview retains
it. The observation grants no reservation or permission; a stale positive result
can still lose the final atomic admission race.

Next, the worker pages only `pending.` metadata, with the existing 32-row page
bound and one unchanged generation. It checks sorted unique keys, progress,
declared counts and exact byte sizes. The projected new count/encoded value
warns at 80% (52 of 64 records), while a full queue or excess projected bytes
returns `paused` / `pending_capacity` without a commit. Budget exhaustion uses
the separate `saved_policy_budget` code. Both preserve all existing proposals
and protected records. The final normalizer still checks held queue capacity,
source and current permission; advisory worker metadata cannot replace it.

### Admit one bounded publication

The capture action retains its complete inherited-plus-own dependency union.
Its CAS prerequisites must be an authentic current-parent snapshot/nil-get or
an exact positive host cache entry derived from a committed observation/result
pair. Cached classification permits closed snapshots, explicit nil-gets and
an initial empty metadata-only index. Values, scans, mixed roots, unmatched
receipts and missing classifications refuse. Every member must bind one complete
root, project, pin, policy and expected generation.

After source resolution, the host repeats current source, recipe and Consent
checks under the final publication owners. The native owner narrows the policy
deadline by the original lineage deadline after synced staging. Its final locked
decision is the admission point; an admitted switch may finish physically later.
An uncertain return remains unknown and is never replayed. This narrow new-v3
route does not enable replacement or supersession.

Before each model-selected source lookup, the host privately resolves every
selected occurrence and its complete provenance union, including an initially
empty call. It repeats that relation at result admission and Saved reconstruction.
Subscriber starts omit source arguments; previews use a fixed status-only message.
Authenticated content retains its full lineage in the journal/model continuation.
After a confirmed own capture, the Worker-input path can preserve its exact prior
root-only union as explicitly historical using the adjacent own receipt and
freshly checked successor root. Model preparation can additionally compose a
bounded ordered chain of those already authenticated own-capture transitions.
Every hop retains its original dependency union, completed output and exact
operation/receipt mapping, and every signed record remains a prerequisite of
every write. The final freshly observed native root must equal the chain's end.
Original dependencies/messages remain unchanged; compact version-3 model
evidence references the already validated actions rather than carrying new
authority. Live and Saved replay rebuild the complete chain and compare the
whole event. Gaps, ambiguous successors, changed scope, missing classifications
and unknown or unrecorded intervening writes refuse. See
[the source-owner flow](session-sources.md#read-through-a-real-synthetic-session)
for the adjacent Worker and separate model-history boundaries.

Lineage derives from source identity and span independently of model text or
retention classification. Pure `Notes` retention helpers retain anchored clocks:
reading or recapturing the same evidence cannot renew an expired lifetime. A
new choice cannot predate creation/supersession or revive an expired note.
Same-lineage correction cannot extend a finite deadline or promote persistence
without a separately authenticated override; different-lineage evidence needs
its own source check. These pure calculations grant no live permission.

`Records.saved_override/2` validates a complete wrapper with separate native
operator evidence under `evidence.sources`. Bare policies, foreign lineages and
weak-origin wrappers refuse. Under the temporary managed-read containment, an
existing override value has no selected current-literal recipe and its generic
worker read is refused, so capture paths needing it cannot proceed. Do not
remove or bypass that override. Generic reads and scans also refuse unrelated or
pending values without a selected authenticated literal recipe; metadata-only
indexes and empty gets remain available. The separately approved bundled shadow
assessment uses the distinct protected single-proposal path described below.
Pending capture checks duplicates by an
exact-prefix metadata index, without reading or renewing the proposal. Restoring
safe unrelated/override value reads requires an independently reviewed,
same-root host classification and is not complete. When the internal override
marker is also a possible user reason, `:absent` is only a host assertion requiring
a fresh protected absence check. The host authenticates the exact prior choice
before applying a change.

Recorded managed-read results are checked by the same classification rule on
Saved reconstruction: an unmatched nonempty generic value cannot be covered
only by a version-3 root receipt. This can make an older recorded Session refuse
reconstruction; preserve the journal and follow the operator's
[recovery procedure](../operator/recovery.md#find-the-original-session).
The separate marked version-7 proposal assessment is unchanged. Older unmarked
histories without a managed-read receipt do not pass through this check and need
separate qualification.

Public forgetting and session-only retention use their reducing management route;
pin/automatic/duration use a separate guarded effect. Interactive literal
correction and supersession have their own Session-owned source/policy review
and publication adapter; generic unreviewed replacement remains unavailable.
Follow [the source-owner flow](session-sources.md#retain-sources-through-a-protected-display-or-review).

### Confirm a pending decision

`Records.pending_projection/2` parses a closed, bounded `pending.<id>` value and
its lineage/text identity. It labels stored timestamps as worker claims. Schema
version 1 is distinct from a Collection revision, and parsing authenticates no
source freshness or acceptance.

Without a key, `knowledge review` lists bounded historical metadata under the
admitted project/domain and retained management snapshot. It reads no proposal
values and works after revocation. A key/revision/hash/size or partial-coverage
claim supplies no signed eligibility.

For `knowledge review PENDING_KEY`, `Management.review/4` requires a matching
native channel and unrestricted interactive mode. It reserves and admits a
bounded `notes.capture` operation through the existing Consent ledger. The
reservation's epoch/policy must match the displayed and published facts; a
resource reservation alone grants no source or effect authority.

Trace `Management.begin_acceptance_review/7` through the signed retained target,
`PendingAcceptance.prepare/4` and
`ManagementTerminal.begin_historical_accept_review/5`. Identity, active Consent,
Collection and management-journal owners cover the complete historical display.
The original source need not be available for this display. The native receipt
also binds the proposed category retention rule and policy expiry derived from
the held installed selection. Target owners release before waiting for input.
Standalone facts have no conversation Session ID. If a future chat caller supplies
one, the card validator requires it to equal the journal ID; the ID by itself
does not establish a live Session, terminal or publication authority. Source
revalidation also requires the current admission to be pinned to the consuming
Session or management journal, rather than another Session in the same project.
`PendingAcceptance.with_shareable_source_union/3` reuses the existing source
owner checks for both cases: an inactive source supplies its transferable lease;
an active source supplies no lease and requires the caller to retain and share
the actual Session and Writer separately. This adapter alone does not authorize
display, acceptance or publication.

After exact native `accept CODE`, publication acquires and verifies the original
source, reacquires current target owners and reproduces the same facts before
consuming the one-use Review permit. Revision, physical value hash, signed
deadline, text, project/client and policy must agree. The event and immutable
link preserve the original proof. Acceptance records a user decision without
promoting its premises to established truth or granting other effects. Source
loss or changed consent refuses publication even after historical display.

After checked owner cleanup, the public caller settles measured event/request
input and receipt output. Known pre-publication refusals settle zero; uncertainty
retains liability. Preserve both printed IDs. `Consent.operation/3` and
`knowledge operation ID` inspect recent/compacted resource records without
settlement or replay, including a reservation created before any journal.
An acceptance journal additionally correlates the native event with its ledger
entry. Selected batches reuse this per-card publication boundary. Deferral and
pending text editing have separate paths below.

### Freeze a bounded selection and accept each item separately

`CLI.Knowledge.Batch` handles `knowledge review KEY KEY [...]`. It admits two to
eight distinct keys, checks active source-selection policy, then reads each exact
signed historical candidate under existing Identity/Consent owners. All initial
cards must describe the same Collection root. `Session.PendingBatch` freezes an
at-most-eight-item, at-most-8-KiB manifest with project/binding/policy/recipe,
source provenance, exact text, revision/value hash, signed admission/deadline and
category retention rules. The manifest digest uses the existing canonical JSON
digest. These data grant no source or review authority.

For each selected key, the batch owner calls ordinary `Management.review` with
that immutable manifest and item index. This creates a separate resource
reservation and management journal. An optional closed `batch` member in the
pending card records the full manifest, hash and index; its selected member must
match the actual prepared card. Original cards/events remain readable without
this member. The native display repeats the complete manifest and identifies the
current item; its fresh `accept CODE` and exact facts digest cover the batch member
as well as that candidate. No per-item permit is derived from another item's
input, and selecting argv keys grants no acceptance.

Manifest-bearing facts use the existing Review limits of 16 KiB of facts and
64 KiB of escaped display, with no raised native/global quota. The manifest itself
still has the 8-KiB bound; ordinary one-card review retains its original 8-KiB
display bound. Oversized facts or displays refuse without truncation. Accepted
note/link values and per-publication sidecar/read/change limits are unchanged.

Publication reconstructs the exact card, including manifest membership, under
fresh current source/Consent/Collection owners. Each candidate keeps its own
native permit, journal intent, source lease and final publication deadline. An
earlier batch publication may advance the root; the next card uses that actual
root while matching its frozen revision/value/provenance and signed clocks.
Changed candidates cannot substitute into the manifest. Stop after cancellation,
refusal or uncertainty and retain earlier confirmed results. Never automatically
replay a stopped item or roll back earlier accepted decisions. The accepted event
persists the full immutable selection, while operation inspection exposes its
manifest identity/index without granting current eligibility. Account for each
item's existing operation and the additional manifest bytes in its journal/input.

### Leave the exact candidate pending

`Management.defer/3` implements `knowledge defer PENDING_KEY` as a checked
historical read. Reuse the existing project identity, installed recipe,
management snapshot and `ObservedRead.with_managed_proposal_removal/7` adapter
to authenticate the exact record and signed clocks at one held root. Capture
may be disabled or revoked; no original-source lease is needed for this read.
The returned `pending_review_later` result identifies the record revision/hash,
first admission and deadline, and reports `pending` or `expired` at observation.

Deferral neither mutates the Collection nor saves a snooze deadline. It creates
no Review permit, human-acceptance event, journal, worker or resource reservation.
This preserves the original seven-day bound and leaves later acceptance to its
independent fresh display/source/consent checks. JSON and nonterminal clients may
request the read because its result grants no attestation or publication authority.
Repeat it against expired or revoked fixtures and compare the complete root,
control snapshot and existing journal bytes before and after; `observed_at_ms`
is the only changing response field when the candidate and expiry status are stable.

### Reject a proposal without retiring its source

`knowledge reject PENDING_KEY` uses the existing management journal, protected
native display and one-use Review flow. Unlike acceptance, it retains the
existing management snapshot after capture revocation and requires no original
source reacquisition. `ObservedRead.with_managed_proposal_removal/7` authenticates the
actual pending record and signed anchor/live rows. `PendingRejection.prepare/3`
binds its exact revision, value hash, text/proof, project, management epoch and
two fully displayed public CAS changes: delete the pending record and insert `reject.<id>`.
Preparation and decoded facts supply no authority.

The target owners release before native `reject CODE` input. Publication repeats
Identity, installed selection and management-policy checks under their owners.
`Consent.reject_deferred/8` reserves one reducing `collection.forget` operation;
`NormalizerV3.reject/3` reproduces the exact facts against the current Collection
root, checks the original signed row, consumes the actual permit and repairs
only its live index. The source anchor remains byte-for-byte unchanged: several
candidate texts and a literal can share that anchor. Lineage-wide retirement
would incorrectly suppress those other records. The reducing reader also allows
a signed literal choice/retirement or saved override on that shared lineage;
those cannot prevent deletion of a separately authenticated pending target.
Acceptance retains its stricter eligibility reader.

The public rejection marker binds the candidate ID, original revision/hash and
management operation. It grants no current-use authority. Fresh automatic
publication refuses any marker at that candidate key; acceptance also checks
its absence. Capture normalization caches exact reads only within its held,
unchanged Collection callback, retaining the 32 charged-read ceiling while
checking suppression. Nothing persists that cache across owners or generations.
The advancing backup floor prevents an older root from undoing the deletion.
Suppression markers and management ledger/journal costs remain part of workload
qualification; they are not silently pruned.

After all owner cleanup, the caller settles measured usage and writes the
management result. Lost replies retain uncertainty and never replay. Exercise
the synthetic-source/native-terminal controls with:

```sh
mix test test/ipse/cli/management_reject_public_test.exs test/ipse/session/pending_rejection_test.exs --include native_sandbox
```

These controls cover live/expired pending targets after capture revocation,
shared-lineage isolation, exact recapture suppression, forged permits,
cancellation, stale codes, concurrent policy/root changes and a shared literal's
native pin/forget choices. The separate opt-in `genuine_pending_rejection` case
starts with actual synthetic-model Session production and checks public rejection
after native disable and unavailable original-source storage, preserving original
journals and a peer proposal. Run it against an isolated fresh-bundle runtime as
for the public acceptance controls below. These are source components; installed
use and annual workload capacity remain separate.

### Edit pending text under its original source

`CLI.Knowledge.Correction` owns standalone text editing. It reuses the existing
management journal/native display, protected selection and finite `notes.capture`
reservation. `PendingCorrection.prepare/5` combines a checked historical pending
observation with its current capture pin, replacement text and policy expiry.
It preserves source attribution, category, reason, worker-recorded times and
signed admission clocks. The new source/text identity is a new pending key;
the displayed three-change request removes the old row, inserts the replacement
and inserts a candidate-specific correction/suppression link at the old ID.
Preparation or a parsed link grants no review or publication authority.

Historical display holds Identity, active Consent, Collection and management
journal owners; it does not require the original source. They release before
`correct CODE` input. Publication reacquires that actual source through the
existing `PendingAcceptance.with_shareable_source/3`, checks the current pin,
installed selection, source policy and unchanged stored target, and repeats the
exact preparation. A signed literal choice on a shared lineage does not supply
new pending authority; source/override and current-consent checks still apply.

`NormalizerV3.correct_pending/3` checks the actual signed old row and original
anchor, unchanged first/deadline and replacement schema/source binding. Public
CAS prerequisites were already checked by Core. Bounded live-page planning
requires the exact old row and an absent new identity. `PendingCapacity.replace/4`
accounts for the removed pending bytes, allowing an exact replacement at the
64-item ceiling without evicting another item or exceeding 256 KiB. Its source
anchor stays unchanged. The normalizer consumes the live permit only after
those checks and seals at most five sidecars under the original 32-read ceiling.

Generic Collection publication refuses the new correction kind.
`Collection.execute_pending_correction/10` instead claims the exact reviewed
intent/request/normalization, freezes the actual last synced lifecycle intent
through the existing Writer/journal lease and attaches the actual original-source
lease to the same native transaction. Its final deadline is the earliest of
pending expiry, active policy expiry and remaining native permit life. This
uses existing native protocols; no new Rust permission or global limit is added.
After all owners and journal cleanup confirm, the caller settles measured usage.
Uncertain effects retain liability and never replay. Journal inspection reports
the intended replacement key without asserting its presence or acceptance.

The `genuine_pending_correction` journey starts with actual Session production
and a fresh artifact, using synthetic model behavior. It checks stale/cancelled
input, source loss and revocation during input, exact original proof/clock and
peer preservation, old-key refusal and separate fresh acceptance of the edit.
The distinct `genuine_pending_correction_deadline` journey shortens a trusted
fixture's saved policy, stages before its real deadline and waits past it;
the root remains unchanged, liability stays unknown and repeated inspection
is inert. Neither fixture manufactures native completion or establishes installed,
human, full-workload or real-model quality.

### Revalidate recall before use

Automatic recall alternates bounded metadata pages with current reads without
another model. It compares each read's key, revision, value hash, byte count and
Collection generation with the index. Index traversal rejects repeated
keys/tokens, an empty page with a continuation and inconsistent counts, refusing
invalid progress. A final first-page check must reproduce the same generation/count.
A failed index call or a changed generation during a read or final check discards
the pass and reports unavailable coverage with an unknown candidate count.

The worker can continue beyond 32 candidates while all notes read so far fit.
When they do not fit, it attempts the existing selection over the first 32 eligible
notes, subject to the host bounds. It reserves a final read and counts page
dependencies, every successful read and worst-case proof and management-journal
owners before issuing further work. Reaching a bound or omitting a note reports
partial coverage. Those worker counts cover this invocation only; inherited
history can make the host's final union too large, in which case admission still
refuses. Search keeps its separate 32-candidate bound, and a later cursor
remains partial.

A missing original is distinguishable from a generic source refusal only for a
single literal record and its one inactive original journal. On Linux, the host
holds an identity-checked source lock, rechecks the original directory and file
absence, and re-observes the exact collection root, record, signed metadata and
current source policy. A lock, identity, policy, ambiguous source or collection
failure remains a general refusal and withholds the pass. The missing-journal
outcome carries no later-use absence dependency: if that journal reappears after
the check, the omission remains partial and is not automatically repaired. Full
fitting-set coverage across arbitrary sparse collections or that reappearance race
requires a separate host discovery and final-use contract.

Accepted decisions use a distinct version-6 dependency. `ManagedRead` discovers
their immutable link, retains the original committed management journal outside
Identity/Consent, obtains the original Session source, then reproduces the
protected read. Signed anchor/live rows, actual event, note and link must agree
before committing a read result. A direct link or an accepted record without
its selected recipe refuses. `Records.accepted_projection/2` checks only that
delivered structure; it does not authenticate acceptance.

Mixed/accepted context uses `note_parts_v2` with fields `key`, `revision`,
`read_operation_id`, `claim_kind`, `offset_bytes`, `total_bytes` and `text`.
Claim kind is `accepted_decision` or `literal_claim`; offsets refer to unchanged
UTF-8 bytes. Literal-only context retains v1. Recall measures the complete
rendered envelope, including index and coverage framing, using the public SDK
and the host's shared framing functions. If even framing does not fit, it clears
the turn-local contribution and reports partial coverage.

`ManagedReads` binds the exact result to its receipt. `ManagedUse` obtains
historical preflight verdicts, then independently reacquires original journal/
source ownership and current policy around actual result release or inference.
The registered provider route is required. The Collection callback returns a
two-element result tuple so its native owner can confirm cleanup before the
adapter expands the result for its caller. Neither replay nor a preflight verdict
establishes current authority. See [Session sources](session-sources.md) for
source ownership and [Collection reads](collection-sdk.md#revalidate-reads-and-downstream-use)
for the generic host boundary.

Managed export inputs use a separate native delivery admission after read
commitment. Its version-3–7 adapter transfers original Session sources and
consuming Session/Writer controls to the same native stdin writer; accepted
decisions additionally transfer their original acceptance journals. Complete
settlement precedes callback release. Read
validation and a saved acceptance alone do not authorize that input. The
[input contract](session-sources.md#deliver-a-managed-export-input-under-its-original-owners)
defines its owner, deadline and uncertainty checks.

### Trace finite shadow selection and assessment

The separately built `knowledge/decision-shadow` preset adds `assess` and
`select_shadow`; the ordinary `knowledge/native` preset continues to make no
secondary decision calls. Follow the operator's [local experiment](../operator/knowledge-permissions.md#try-a-local-shadow-assessment)
from the reviewed project policy to a fresh Session. `CLI.Knowledge` binds the
inventoried bundle digest, numeric loopback route, exact `advice` profile, finite
call count and expiry to the review. The policy replaces the prior project grant;
it cannot acquire extra authority from worker-supplied labels.

`SemanticAdmission` recognizes the decision outer only for the reviewed
protected-read and decision mappings. `Actions` enforces the same restriction
during live execution and replay: this owner can read a protected collection and
request `decision.create`. It also admits the exact read-only
`{"op":"context.available"}` request under the independently declared
`host.context` capability. Extra fields refuse; `context.publish`, collection
writes, shell, MCP and unrelated operations remain unavailable under that outer.
`ManagedRead` binds the selected literal note or
pending candidate to its current source and policy. A separate native approval
precedes the project Consent ledger reservation; the exact shipped shadow digest,
route and source union are checked
again before send. Successful work settles one call; an uncertain effect retains
its liability. An admitted send can finish after expiry, while result release
checks the reviewed deadline again. None of this establishes a monetary cap or
qualifies a hosted engine.

For `select_shadow`, follow the initial allocation read into a complete index of
at most sixteen notes and protected reads of every eligible record. Keep each
key, revision, value hash, read operation and source dependency. The worker
rechecks the index and allocation, then renders the complete ordinary greedy
baseline using the smaller of the host's available bytes and the existing
8,192-byte recall ceiling. A fitting complete set bypasses the decision. An
over-budget set can compare explicitly supplied packs of at most four records;
those packs never replace the full baseline. Advisory saved-policy availability
does not reserve capacity: the actual decision still needs current source
owners, native approval and the shared atomic reservation. Recheck allocation
before releasing the comparison. Neither projection is published into context
or saved as a note. The [decision training chapter](decisions.md#trace-a-protected-shadow-comparison)
owns the projection algorithm, frozen experiment inputs and scoring adapters;
protocol completion supplies no answer-quality result or default strategy change.

For `assess`, the worker retains its bounded assessment plan until the host
returns the validated decision result. `DecisionPolicy.apply/2` maps it to the
permitted choice or an abstention reason; the tool returns the choice only when
the policy selected it. The result is marked experimental and records that it
does not mutate the note; the separately approved decision call is an effect.
`ManagedOutput.release` rechecks the invocation's dependency union before
releasing that result, so a stale note or source is withheld instead of being
presented as current advice. The pending assessment does not change ordinary
capture, accept a proposal or establish the truth of its premise.

For a pending key, the bundled worker requests an explicitly marked single
`collection.call` get. The host requires the reviewed decision outer and the
matching `notes.assess` mapping, then checks the actual installed artifact and
digest-checked sidecar against the current bundled-shadow inventory before it
returns any candidate bytes. Generic gets and scans retain their containment.
The signed observation, exact original Session proof and active policy produce a
version-7 `pending_proposal_observation` with `never_current` status; it is not
a current note. `ManagedReads` binds that result and the host's historical
classification receipt to the Session, parent, artifact, descriptor, pin and
full request/result. Replay checks the recorded relation; it does not substitute
for current authority or cryptographically authenticate a wholly forged journal.

At decision reservation, `DecisionExperiment` checks that the decoded request
contains the signed proposal's exact ID, text, assigned category and reason with
the two allowed choices. The pinned bundle supplies the instruction text.
`ManagedUse` retains or reacquires the original source and current Consent for
worker delivery, approval, dispatch and output; it repeats the signed candidate
and deadline checks before use. Loss or change can withhold a result after the
decision call has already been charged. Keep the source Session's original
journal and lock files; a historical key or receipt grants no current use.

Run the focused synthetic controls when changing this boundary:

```sh
mix test test/ipse/extension/decision_outer_test.exs test/extensions/knowledge/shadow_experiment_session_test.exs test/extensions/knowledge/shadow_pending_candidate_session_test.exs
mix test test/extensions/knowledge/selection_shadow_test.exs
mix test test/ipse/extension/managed_collection_call_session_test.exs --only pending_original_source_boundary
```

To check the same prior-Session pending-candidate path in a built package, first
record its independently expected SHA-256 and source commit label. Set the
archive, independently recorded values and an **absent** private output
directory below, then run:

```sh
IPSE_ARCHIVE=/absolute/path/to/ipse.tar.gz
IPSE_SHADOW_PROOF_ROOT=/absolute/private/path/new-shadow-proof
IPSE_ARCHIVE_SHA256=replace-with-recorded-64-character-sha256
IPSE_ARCHIVE_COMMIT=replace-with-recorded-40-character-commit
elixir dev/verification/pending_shadow_installed.exs \
  "$IPSE_ARCHIVE" "$IPSE_SHADOW_PROOF_ROOT" \
  "$IPSE_ARCHIVE_SHA256" "$IPSE_ARCHIVE_COMMIT"
```

The verifier checks the archive and checksum sidecar, checks the reported commit
label, and runs the existing source fixture against the extracted release and its
bundled worker. It needs a native Linux PTY, Rust compiler and precompiled
ExUnit. Each scenario has a fresh synthetic project and loopback services: an
approved assessment, denial, source loss before dispatch and before output, and
an unknown decision followed by Session reopening. It stops on the first
failure. Preserve its private output and inspect its result before another run;
terminal logs contain synthetic approval codes. A package label and matching
checksum identify the checked artifact but do not prove its source provenance.
These controls do not establish independent human use or live-service quality.

The shipped-bundle Session fixtures cover prior-Session protected note and
proposal reads, approval, settlement, denial, pre-Session revocation and grant
expiry interpositions. They use loopback fixtures, not a real account or a
quality assessment. Same-Session
assessment immediately after a write remains unsupported: historical root
observations can make the subsequent protected preflight refuse. Do not remove
those dependencies or automatically retry the failed effect.

### Verify the complete boundary

The builder includes inert `operator.json` in the artifact's hashed inventory.
`Knowledge.Contracts.operator/0` supplies closed note/proposal/retention schemas
and reviewed recipe digests using the public canonical-digest helper. Read it
with `Artifact.read_declared(store, digest, "operator.json", 65_536)` to revalidate
the installed bytes without loading extension code. Sidecar data grants no
execution or activation authority. Capture excludes pin/history categories;
separate retention schemas prevent an ordinary choice from carrying a duration.
The normalizer independently checks source, lineage, category and clocks. Packed
signed anchor/live pages retain deadlines after public-record pruning and refuse
experimental v1 metadata.

From a built checkout, run the focused contracts:

```sh
mix test test/extensions/knowledge/knowledge_records_test.exs test/extensions/knowledge/knowledge_contracts_test.exs
mix test test/extensions/knowledge/knowledge_capture_test.exs test/extensions/knowledge/knowledge_recall_test.exs
mix test test/ipse/session/managed_reads_test.exs test/ipse/session/managed_use_test.exs
mix test test/ipse/cli/management_review_public_test.exs
```

Pure records/projections use synthetic proof inputs; worker continuations execute
in a separate VM. Actual source/publication controls are separate from those
consistency checks. The opt-in `genuine_pending_public_review` case exercises
synthetic Session capture through actual CLI/native review, cancellation, finite
allowance, duplicate/expiry/revocation refusal and owner-loss inspection.
`genuine_pending_accepted_recall` adds a registered loopback provider request,
missing-source and altered-acceptance-event controls, Saved reconstruction and
confirmed close. Its disclosed one-use BEAM pause checks the actual native
importer's source, management-journal, policy, Session/Writer and stdin
descriptions before the unchanged write. These observations are distinct from
human use or installed qualification. The [public CLI record](../archive/2026-10-26-p30-p31-implementation/pending-review-cli-20261031.md)
and [recall record](../archive/2026-10-26-p30-p31-implementation/accepted-recall-20261031.md)
describe fresh-artifact isolation and exact limits. Run terminal suites
sequentially. These fixtures qualify no real model quality, installed journey,
complete lifecycle or untested provider continuation. Milestone status belongs
to [the plan](../plan.md).


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
requests. [The proof](../../dev/verification/knowledge.exs) pairs session WorkingMemory
and project/operator persistent Memory with each package, in distinct logical
bindings. Disabled/enabled idle/resume counters remain zero for workers, State,
MCP, embedding, and text work. Actual commands provide positive controls.
Same source IDs do not turn notes into retained evidence or vice versa. Forgetting
one store preserves the other's content. This exercise selects offline Research, which owns no retained knowledge store.
The separate `state-retained` and `state-fetched` presets share a store only
through explicit operator-selected State bindings, scope and partition.

Inspect actual namespace-relative filenames/hashes: Research+Memory has one State
file; Corpus/Graph+Memory have two. Empty inventory proves no inert-resume claim.
Counters use arity-only OTP trace instrumentation, without arguments/payloads, and
require every target to be instrumented. Confinement needs separate OS evidence.
The artifacts selected by this exercise, plus Memory, exceed the existing
16-KiB catalog and must refuse before Session/worker/store work. Pairwise compatibility grants no larger catalog.
Repeat the same artifacts in installed mode for runtime compatibility, not new quality evidence.

## Trace one source and a revalidated query

Follow Corpus source validation into Store draft claim, immutable content/chunk
writes, and final root CAS. Storage revision advances on every root mutation;
source generation identifies one complete text version. Pages/projections/citations
bind generation and content hash. Source ID alone identifies no current bytes.
[Storage training](knowledge-storage.md) owns capacity, CAS, suppression, and migration.

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

Direct Corpus BM25 snapshot queries use
`Evidence.rank_lexical_with_table_context/4` after source hydration. It keeps the
positive `rank_lexical/4` hits first, then fills remaining `top_k` slots with
deterministically ordered chunks from different cells in a matched cell's row.
The source key, generation and content hash must all match, as must the Word part,
table, row and any region or annotation identity. A returned companion uses the
ordinary validated source excerpt and citation, with `method: "table_context"`
and score zero; the method does not assert lexical match or semantic support.
The coverage member records the returned count, truncation among eligible chunks
and the single-block cell-chunk scope. `multi_block_chunks_expanded: false` is a
scope declaration, not a count of omitted chunks; a packed group can qualify if
the chunk has a single-block locator. `truncated: false` does not prove row
completeness. No match means no expansion, and long chunks still use
the bounded excerpt selector. A later explicit reranker can change result order.

This path serves State/MCP BM25 snapshots and Collection's explicit-source BM25
query. The indexed Collection namespace query, hybrid/graph component ranking
and independent Research keep their existing lexical ranking. In particular, an
indexed query has not hydrated arbitrary neighboring cells. None of these paths
changes stored chunks, source bytes or ingestion. Test the row-context candidate,
both document Session profiles and the indexed and packed-group limits separately.

Graph/hybrid fusion retains each component's claims/gaps/coverage. A completed rank
calculation cannot certify bounded traversal. Only actual missing-embedding policy
can take explicit lexical fallback; graph/transport/malformed-model failures cannot.
The fallback remains partial. `Evidence.query_scope/4` owns direct/combined consistency.
Use `test/extensions/knowledge/query_completeness_test.exs` to compare matches,
no-match, unpublished drafts, forgotten/expired/future sources, and depth-limited graphs.

### Rank explicitly selected Collection vectors

The `collection-dense` preset also admits dense and graph-free hybrid retrieval
with `missing_embedding: "refuse"`.
Its `query_selected` requires the original six selected-source fields plus exact
`vector_selection` and `fact_selection` objects. BM25 retains its original shape.
The ordinary Collection namespace `query` remains lexical; selected coverage must
never be described as a namespace search.

Follow `Corpus.collection_query/2` into the existing
`Collection.Selected` reader. It hydrates complete raw bundles and vector/fact
groups under one native Collection generation, checks all source bindings and
rechecks the catalog before returning its private snapshot. The snapshot retains
that native generation for a later fence. Corpus then uses the existing
`Adapters.embedding_profile` read to compare the actual configured selection
digest before proposing inference. The `embedding.create` request independently
pins the same digest; no source passage is sent by this query operation.

The query uses the same prefix formatting, typed vector reconstruction,
`dense_candidates`, cosine ranking and graph-free hybrid fusion as State Corpus.
Only the query gets a prefix. Every stored vector must retain its chunk-input
digest and full profile/model/selection/dimensions/encoding identity. Supplied
projection validation establishes structure and attribution, not a model receipt.
After inference, a fresh catalog read must retain the captured native generation
and catalog hash. This also catches intervening projection/root changes that did
not replace the raw catalog body. For current-time queries, recheck source expiry
using the time after that read. A mismatch returns no evidence or claims.

Coverage preserves selected-only scope, the stored-provenance limitation and
later-use-authority false. It counts the one query inference separately from
Collection, profile and vector-result reads. This is a coherent snapshot checked before return,
not authority for later egress or a promise to revoke an already returned result.
The existing source-bound producer binding still requires a producer claim for
every embedding request; query consumers use the ordinary v1 binding in a
separate reviewed configuration. Do not remove that host check to reuse a
producer instance for unclaimed query text.

Run the actual public-artifact/native Session controls:

```sh
mix test test/extensions/knowledge/collection_adapter_session_test.exs --only public_semantic_selected
```

The fixtures supply their generation privately, then use the actual registered
Ollama adapter for synthetic query embeddings. They check cosine ordering that
differs from lexical order, Unicode prefix bytes, Word citation/partial coverage,
Collection change during approval, actual wall-clock expiry and an unselected
encoder recipe with no dispatch. Action and Saved validation remain in the
journey. They qualify no live model quality or complete producer workload.

## Follow acquired document bytes into cited storage

`Corpus.source` offers two explicit document paths. `put_document` accepts a
filename and canonical `bytes_base64` with the ordinary source identity,
generation, expected revision and times. It extracts supplied bytes; it opens no
file. `read_document` accepts a workspace-relative `.docx` path and
`expected_sha256` instead. The compiled `state-documents`, `mcp-documents` and
document Collection presets explicitly declare native `host.tools` authority
for that path; options cannot upgrade an existing lexical artifact.

Trace `Corpus.acquire_document/5` through the selected store profile. Initial
generation-one/revision-zero acquisition may omit `expected_sha256` with
explicit `null`; refresh requires a concrete hash. State and MCP document
presets use native base64 reads of at most 4096 bytes per page with a 32768-byte
complete-file bound. Corpus validates the offsets, page hashes, complete byte
count and reconstructed hash, then asks for a hash-pinned page-zero read before
proposing the write plan.

Collection acquisition instead opens a host-owned snapshot bounded at 1 MiB and
reads ordered pages of at most 4096 bytes. `WorkspaceSnapshot` binds its volatile
handle to the owning Worker and Session; the Writer's `WorkspaceAcquisition`
projection verifies the actual opening and page results, full hash and
continuation plan. A resumed invocation cannot replay the volatile handle. The
shipped Collection artifact's source-head publication goes through
`WorkspaceDocumentGuard`: it binds the actual invocation and receipt, then
rechecks the original path, size and hash before the Collection commit. The
guard recognizes the exact host catalog digest; an independently built artifact
with a different digest cannot use its guarded workspace-document publication.
The original-file observation is point-in-time, not a file lock through commit.
Snapshot opening counts as an other call and pages count as mixed reads. Worker
code never opens paths or enlarges SDK/result envelopes.

`Documents.source_payload/1` converts the extraction into source text and typed
segment metadata. Supplied `put_document` keeps its 8192-byte extracted-text
bound. Workspace acquisition supports up to 65536 extracted UTF-8 bytes,
32 stored segment groups, 32 chunks and 16384 canonical metadata bytes with at most 32 warnings.
It does not trim text, warnings or locators to fit. Test original bytes,
extracted text and chunk count independently: a source can exceed 32 chunks
without reaching 64 KiB. A pure parser or source-payload check does not exercise
the host's original-byte snapshot limit. In the actual Session control, require
the expected native acquisition phase, unchanged prior head, exact UTF-8
citations after file restoration, confirmed close and idle reconstruction without
new effect intents. The [installed Collection ceiling control](../archive/2026-10-26-p30-p31-implementation/word-installed-capacity-20261104.md)
provides a worked synthetic example; it does not qualify full-store capacity or
Word rendering. Metadata at most 2,048 bytes
keeps the packed receipt version 3: canonical document JSON and its digest wrap
the supplied-byte version 1 or acquired-byte version 2 receipt. The latter binds
the actual host acquisition operation and relative path. Larger metadata uses
compact receipt version 4, retaining exact manifest hash/byte count, segment and
warning counts, origin and one immutable manifest-head reference. Storage paging
does not change the extraction recipe.

For recipes v14 through v18, an extraction with more than 32 blocks can pack adjacent
plain paragraphs and table cells from one part into groups. Each group contains at most
64 original blocks and fits the selected chunk-byte bound. Its `block_group`
locator stores compact rows `[paragraph, text_bytes]` or
`[paragraph, text_bytes, table, row, cell]`. V16 through v18 rows may append a `numbering` map
after the optional table coordinates. Original paragraph numbers may have
gaps; they must increase within the group. Other locator fields, such as annotation
anchors or header regions, prevent grouping. The complete text keeps the same
newline joins as an unpacked extraction. Evidence checks row widths, coordinates,
summed byte counts, UTF-8 boundaries, separators and the complete group hash.
Groups remain subject to the existing metadata and chunk ceilings; packing does
not truncate an extraction or increase storage/action allowances. Recipes before
v14 retain their existing block boundaries. Stored sources are never repacked on read.

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
`continue_document` reacquires the hash-pinned original and exact typed extraction;
`continue_collection_document` does the same with a new bounded snapshot while
retaining the Writer-validated opening receipt and plan. The continuation
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
Managed document mutations and generic unreviewed supersession retain their gates;
native-note retention and interactive literal replacement use their reviewed routes. Never
drop a domain deadline to retry a draft. Explicit collection first clears an expired draft claim while
preserving the selected source, then reclaims unreferenced pages. MCP uses the
client deadline gate; this does not claim a remote server publication fence.

Follow normal Store CAS publication, hydration and `Evidence.citation/4`. A
document citation binds original binary SHA-256, extraction version and exact
locations alongside source generation and literal quotation. Its outer version
is 2 for legacy sources and 3 for Collection sources. Inside `document`, version 1
retains the original single locator and local byte range. A quotation crossing
packed blocks uses version 2, one `part` and compact `spans` rows. `span_fields`
names their columns: paragraph, local start/end, quotation start/end, then
table/row/cell coordinates. V14 and v15 rows contain five values for paragraphs
and eight for table cells. V16 through v18 rows have nine fixed positions: the first five,
nullable table/row/cell coordinates and nullable numbering metadata. Quotation
offsets retain the newline gaps between original blocks.

For example, suppose a v16 citation quotes the following four complete blocks:

```text
First café item
amberneedle exact evidence
Plain middle
Table numbered
```

If the first two paragraphs are numbered starting at 3, the third is plain and
the fourth is the next numbered paragraph in table 1, row 1, cell 1, the span
rows have these byte ranges. End offsets are exclusive; `é` occupies two UTF-8
bytes and each joining newline occupies one quotation byte.

| Paragraph | Local range | Quote range | Table/row/cell | Numbering ordinal and label |
| --- | --- | --- | --- | --- |
| 1 | 0–16 | 0–16 | null/null/null | 3, `3.` |
| 2 | 0–26 | 17–43 | null/null/null | 4, `4.` |
| 3 | 0–12 | 44–56 | null/null/null | null |
| 4 | 0–14 | 57–71 | 1/1/1 | 5, `5.` |

The actual numbering map also carries its version, list identity, level,
template and suffix. The derived labels are metadata, not characters in the
quote.

Rows must be ordered and are reconstructed exactly from the stored block map;
changed coordinates, offsets or column labels refuse. Evidence revalidates the typed receipt,
canonical envelope and source spans. An ordinary text `put` cannot smuggle in
a document receipt. Partial extraction remains partial in query gaps and
coverage. Replacement and suppression use ordinary source management.

Follow `Corpus.check_document_use/3` before query publication. It collects acquired
originals from returned evidence and each claim's complete citation basis, deduplicates
path/hash/byte-count references and checks the compiled `host.tools` capability.
Packed v3 and compact v4 receipts retain the acquisition identity. Provided-byte
receipts have no workspace acquisition and trigger no fetch. For an acquired
original up to 32 KiB, the native binary read returns one byte plus complete-file
metadata. For a larger original, snapshot verification returns metadata without
retaining file bytes. Corpus checks the exact envelope, host operation ID, path,
hash and count. A failure publishes neither
evidence nor claims. Capability absence refuses rather than widening authority.

The continuation then revalidates State/MCP source tokens or the captured Collection
native generation and source eligibility. A revision changed during the file check
therefore withholds the result even when the file bytes still match. Query coverage
retains original acquisition provenance separately from `workspace_file_checks`,
`workspace_store_revalidation`, `workspace_invocation_effects` and
`workspace_invocation_reads`.
Corpus counts its emitted calls across adapters so added checks share the existing
16-effect/512-read allowance; the host independently enforces that ceiling. Legacy
workspace reads and snapshot openings/verifications count as other calls; snapshot
pages count as reads. None gains mutation approval from the read. The private
classifier covers only operations Corpus emits and reuses `Collection.read_request?/1`.

The same guard runs before legacy document embedding, rerank input and vector commit.
Model-only presets lack `host.tools`, so an acquired document cannot use those
routes. The shared Collection producer retains its separate source-claim protocol;
this guard does not establish workspace-file checks for its embedding batches.
There is no watcher, automatic rename detection, reindex or deletion. Checks cover
returned evidence/claims, not a namespace-wide filesystem snapshot, and hold no file
lock through subsequent consumers. Earlier journals/results remain historical.
The native host can refuse a symlink at tool-context admission before any read intent;
the parent then remains conservatively unknown and is never replayed.

Run the worker and actual Session paths together:

```sh
mix test test/extensions/knowledge/document_ingestion_test.exs \
  test/extensions/knowledge/document_acquisition_session_test.exs \
  test/extensions/knowledge/document_paragraph_packing_test.exs \
  test/ipse/extension/tool_action_binary_test.exs
```

These controls cover stored paragraph/table citations, replacement/forget,
forged metadata, changed-file refusal before writes and query return, exact read
operation binding, revision change during a query check, and owner-loss/inert-resume
behavior. State and Collection controls replace, rename, delete and redirect the
original after acquisition, then explicitly restore it. They use synthetic Word packages
and local State/CAS fixtures. The opt-in `workspace_word_native` controls add
the Collection snapshot, source-change, owner-loss and cancellation boundaries;
see the [testing manual](testing.md#exercise-actual-os-policy-and-native-protocols).
They do not establish real Word fidelity, full document capacity or retrieval
quality. The
[operator procedure](../operator/corpus.md#acquire-a-small-word-document-from-the-workspace)
shows explicit artifact selection and a complete command.

The `many_paragraph_document` controls cover mixed paragraphs/cells through both
native storage profiles, source change during staging and cited retrieval after
resume. The optional original-file control requires the exact public fixture
identified in the [packing record](../archive/2026-10-26-p30-p31-implementation/word-block-packing-20261031.md):

```sh
IPSE_PUBLIC_WORD_FIXTURE=/absolute/path/Comment001.docx mix test test/extensions/knowledge/document_acquisition_session_test.exs --only public_many_block_document
```

It refuses a different file hash, uses no inference and checks source-offset
integrity against a separate parser process. It does not compare Word rendering.

### Inspect the extraction boundary

`Documents.extract/3` accepts already acquired bytes and a filename; it neither
opens the source path nor authorizes a fetch. The result binds the original binary
hash, an extraction recipe, and bounded text segments with format-specific
locators. Text and Markdown use byte-exact line offsets. The DOCX reader checks
package authority, bounds ZIP expansion and XML parsing, includes insertions, and
excludes deletions and supported hidden runs. Unsupported content stays partial
or refuses rather than claiming complete coverage.

An undefined selected `pStyle` or `rStyle` contributes no paragraph or
character style. This does not repair a missing inheritance parent or an invalid
style graph. Document defaults, valid styles and direct run properties still
govern hidden text. Undefined explicit paragraph references combined with a
visibility-bearing default paragraph style refuse until that interaction is
qualified; omission of `pStyle` keeps the existing default policy. The segment
`style` value is the raw declared reference, not proof of an applied heading.

A table's direct `tblPr/tblStyle` reference uses the same bounded style graph
as paragraph and character references, with an exact table-style type check.
Only table graphs without hidden-text properties are supported. The parser
rejects hidden conditional table properties, unknown or wrong-type references,
duplicate references and references after row content. Each table tracks its
own selection, while its cell locators retain their original table/row/cell
identity. Ambiguous visibility remains outside the supported subset.

For directly numbered body paragraphs, v16 through v18 derive list locators from
the internal `numbering.xml` relationship and matching content type. The supported
graph has explicit `singleLevel`, level zero, decimal format, start and a bounded
template containing one `%1`; an optional level-zero start override sets the
instance's initial ordinal. Counters advance in body order per `numId`, including
table paragraphs. An interleaved list has its own counter. The locator's versioned
`numbering` map records `num_id`, `level`, `ordinal`, `template`, derived `label`
and `suffix`. For example, template `%1.` with ordinal 3 produces `3.`, but that
label is not prepended to the source paragraph or its quote. Compact group rows
append the map after any table coordinates. V2 multi-block citation spans instead
use fixed table, row, cell and numbering positions, with `null` for absent fields;
the `span_fields` list names each position. Evidence validates its shape and
the label's derivation, then reconstructs the citation from the authenticated source
record rather than trusting a submitted map.

The reader refuses style-inherited numbering, nested levels, bullets, other formats,
unrecognized numbering definitions or overrides, and revision-affected numbered
paragraphs. A numbered paragraph with an ambiguous hidden paragraph marker or no
visible text also refuses, so it cannot silently move later counters. Excluded
deleted paragraphs do not advance the counters. The numbering part still receives
`part_not_extracted`, leaving coverage partial; these restrictions do not establish
general Word rendering fidelity. The body, numbering and any parsed styles parts
must use the same WordprocessingML dialect for numbered paragraphs. Mixed parts
refuse as an implementation boundary; the reader does not claim the package is
invalid under the standard.

Referenced headers and footers are extracted once per part and their locators
identify the region. The result remains partial: it does not resolve section
inheritance, page layout, or which pages display the text. Only bounded internal
relationships with matching content types are admitted; unreferenced parts are
not extracted.

The parser distinguishes footnote/endnote layout entries by their declared
`type`: `separator`, `continuationSeparator` or `continuationNotice`. It excludes
their text from emitted segments and their identities from anchor-completeness
requirements. It still validates their numeric IDs and uniqueness against all
entries in that part, and visits their paragraphs in the same part-wide ordinal
sequence. A normal or omitted type keeps an ordinary note, including one with a
negative or zero ID; an unknown type refuses rather than guessing. Comments do
not accept note-layout types.

Ordinary footnote, endnote and comment paragraphs carry their annotation ID. The parser
requires distinct numeric IDs within each part and refuses paragraphs outside
an annotation. A uniquely matched visible reference in the main body supplies a
`reference_site` paragraph or table-cell locator and UTF-8 byte offset; it is a point, not a
comment range. A unique pair of direct paragraph comment-range markers before
the matching reference also identifies a nonempty span of visible extracted
text in that same emitted paragraph or table cell, with UTF-8 byte offsets.
Hidden or unexamined range markers in the main story conservatively suppress
range links. Multiple visible references leave an annotation unlinked;
duplicate range markers prevent a range. Unreferenced annotations and
references in paragraphs with no extracted text have no site.
Coverage checks every declared annotation identity and every visible body
reference. Uniquely linked footnote/endnote paragraphs and point or supported
same-paragraph comments need no unresolved-anchor warning. An orphan, empty
annotation, missing target, ambiguous reference or unmapped range keeps coverage
partial. Other document stories and ranges spanning paragraphs remain unresolved.
Unsupported annotation rendering, including automatically numbered note marks,
retains its own warning even when the reference site is resolved. An annotation's
text alone does not establish where it applies in the document.

DOCX relationship targets are never fetched. A checked external relationship,
an unexamined internal relationship, or an unexamined relationship part marks
the result partial. Relationship warnings do not repeat targets or arbitrary
unexamined relationship-part names. Malformed target modes and scheme or network-path targets
without explicit external mode refuse. A normal document with relationships the
reader does not interpret can therefore be partial even when its visible body is
readable; inspect the result and original document before using it as evidence.

The reader admits the exact internal `stylesWithEffects` relationship and content
type only with both style parts present. It parses each through the same bounded
style parser and requires identical dialect, type, inheritance, default and hidden-state
graphs before reading body text. Presentation properties omitted by that parser
may differ. An ambiguous graph, unsupported namespace, missing part or substituted
relationship still refuses; this does not implement general Word text effects.
Both parts count toward the aggregate expanded-byte bound.

Recipes are format-specific: `Documents.version("docx")` is
`ipse-documents-v18`, while text, Markdown and PDF use `ipse-documents-v2`.
The legacy `version/0` returns the v2 value; use `version/1` when binding an
extraction to a source version. Earlier DOCX results are not automatically
migrated or equivalent. V14 through v17 packed receipts and citations retain their
original recipes and remain readable; v16 extends the bounded block-map geometry
with the separate numbering map. V17 retains that geometry and changes only
undefined selected paragraph/character style handling. V18 retains that geometry
and excludes the declared footnote/endnote layout entries described above.
A future recipe cannot inherit that geometry without explicit validation support.
Future indexing must explicitly rebuild or requalify older extraction results.
The optional PDF backend requires a separately host-admitted protected parser;
its installation does not activate PDF acquisition. The
[parser contract](../../native/ipse-pdf/README.md) describes its lifetime and
limits. The Corpus paths above provide bounded ingestion and cited retrieval.
Extraction alone supplies neither current-source authorization nor retrieval
quality qualification. Larger originals, full document capacity and paged-source
migration require separate storage work.

Exercise synthetic DOCX relationships, bounded XML and Unicode extraction from
the repository root:

```sh
elixir --erl '+S 2:2' \
  -pa _build/dev/lib/ipse/ebin -pa _build/dev/lib/jason/ebin \
  -e 'Application.load(:ipse); ExUnit.start(seed: 791782); Code.require_file("test/extensions/knowledge/documents_fidelity_test.exs"); Code.require_file("test/extensions/knowledge/documents_test.exs"); Code.require_file("test/extensions/knowledge/document_paragraph_packing_test.exs")'
```

Include declared layout entries before an ordinary footnote/endnote and verify
both the emitted text and the later note's original paragraph position. Also
check ordinary negative-ID and unreferenced notes: neither punctuation-like text
nor an absent body reference permits omitting their content. Duplicate numeric
IDs across layout and ordinary entries must still refuse.

The artifact control uses the built SDK above without starting the Ipse
application. One fixture opens a loopback listener to verify that an external
relationship is not fetched; use a terminal permitted to open that listener.
These parser controls do not establish real Word fidelity,
PDF quality or migration; the separate Session controls exercise the bounded
ingestion path.

To verify an independently built Corpus artifact, use a parser-enabled source
host because the complete document proof also exercises the optional PDF backend:

```sh
IPSE_BUILD_PDF=1 ./dev/build.sh
IPSE_DOCUMENT_CHECK=$(mktemp -d)
elixir extensions/knowledge/build.exs --sdk _build/dev/lib/ipse/ebin \
  --output "$IPSE_DOCUMENT_CHECK/corpus" --package corpus --preset state-documents
elixir dev/verify.exs source documents --sdk _build/dev/lib/ipse/ebin \
  --input "$IPSE_DOCUMENT_CHECK/corpus"
```

Require all nine named checks, including linked and orphaned Word annotations,
revision visibility, packed citations and the explicit/default-off PDF distinction.
The proof inventories the actual artifact and host before and after execution;
it does not rebuild an input artifact. These synthetic controls establish no
independent Word-rendering or retrieval-quality result. After building a matching
standard archive and setting `IPSE_ARCHIVE` to its exact path, verify the same
artifact bytes in the installed runtime:

```sh
elixir dev/verify.exs installed documents --archive "$IPSE_ARCHIVE" \
  --input "$IPSE_DOCUMENT_CHECK/corpus"
```

## Keep source bytes distinct from semantic support

Raw SHA-256 identifies text/vector bytes; ordered tagged JSON arrays identify domain
objects. Use Elixir `JSON.encode!/decode!`, not raw Erlang encoding: binary sizing
and `nil`→null semantics matter to persisted IDs. Sources allow 64 KiB UTF-8,
with at most 32 chunks. Legacy sources keep their 2048-byte recipe; explicit
Collection Source3 uses the versioned 4096-byte recipe. Document chunks remain
inside their typed segments. V14–v18 groups may contain several original blocks and
their newline joins; separators between groups need not belong to a chunk.
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

## Capture relationships through the main tool path

Follow the [Graph operator exercise](../operator/graph.md#capture-through-the-main-model)
from an existing State source to a main-model-selected tool. Graph's `capture`
export belongs only to `invoke.tool`; it is not an additional `/ext` command.
The `state-explicit` artifact needs no `host.model` capability for this path.
The normal main provider proposes the relationships; Graph invokes no second
provider. Explicit `extract` commands and optional model-extraction presets keep
their separate contracts.

Start with a source stored under the selected State binding, scope and partition.
For source `manual:release`, generation 1, containing `Release requires
quiescence.`, the main tool arguments are:

```json
{
  "store": "notes", "extraction": "asserted",
  "source_id": "manual:release", "generation": 1,
  "relations": [{
    "subject": "Release", "predicate": "requires", "object": "quiescence",
    "polarity": "positive", "inferred": false,
    "valid_from_ms": null, "valid_to_ms": null,
    "quote": "Release requires quiescence."
  }]
}
```

Trace the continuation through these existing owners:

1. Normal main-tool approval admits the exact `ext__graph__capture` arguments.
   Each later State mutation still passes the ordinary approval policy; the
   default ask policy presents its own request. Neither
   this descriptor nor a stored quote grants saved knowledge permission.
2. `Graph.capture/2` validates closed arguments, a State store and an explicit
   extraction profile, then requests `Store.snapshot`. Bounds are one to eight
   relations and at most two independently derived chunks. A nonexplicit
   profile refuses before any host work; changing options cannot add authority.
3. The `capture_snapshot` continuation selects the exact source ID/generation
   and checks current stored-source eligibility. `Store.provided_quote_range/2`
   requires one exact occurrence across the entire source, including overlapping
   occurrences. Unlike the optional extractor's per-chunk uniqueness rule,
   another occurrence elsewhere in this source also makes capture ambiguous.
   `Evidence.chunks`, `citation` and `fact` derive the actual chunk, absolute
   UTF-8 byte coordinates, hashes and existing fact identity. Model-proposed
   citations, chunk IDs and extra fact fields are not accepted.
4. Graph supplies those facts to its existing `extract` continuation:
   `Store.projection_open`, the explicit `Adapters` branch and
   `Store.projection_commit`. Source generation, revision, draft, selected chunks,
   exact spans and existing storage/effect limits remain checked. A source
   replacement after the first snapshot refuses at the ordinary projection
   claim; it cannot publish under a stale source generation.
5. Existing projection predecessors retain prior facts and deduplicate unchanged
   fact IDs. Query revalidation, opposing-polarity context, inferred labels and
   validity-time filtering apply exactly as described below. Source replacement
   invalidates prior-generation facts; forgetting suppresses later capture.

Malformed/ambiguous support refuses before mutations. A denied or unknown Store
effect stops the invocation, rather than returning a partial successful batch or
requesting a retry. An unknown State result can represent a written draft/root
claim without final fact publication. Preserve the intent and original State
files; idle reconstruction must add no effect intent. Inspection and exact abort
remain explicit subsequent operations. Do not replace an unknown with an empty
successful graph result.

Exercise the worker protocol and the actual Session/State path together:

```sh
mix test test/extensions/knowledge/graph_capture_test.exs
```

The worker suite covers exact/ambiguous/forged quotes, generation mismatch and
interposition, expiry, polarity/conflict/inference/time, replacement/forgetting,
retained prior facts, closed bounds and denied/unknown stop. The separate Session
script imports the exact built artifact and uses an in-process scripted main
provider to select the real tool. It checks ordinary outer and State approvals,
published citations, generation refusal, denial with unchanged State bytes and
owner death at an incoming actual successful State result before journal commit.
Strict Saved validation and fresh idle resume preserve intent counts. That
control establishes neither a live model's relationship quality nor final-fact
commitment for the interrupted write. It needs no Input channel or model service.

Keep the boundary narrow. Currentness here means the selected retained State
source, not an original file lock or durable Session-source authority. Public
read/quote proofs remain evidence JSON that needs its consuming host adapter to
authenticate current use. `Session.Invocation` still refuses State.put/delete
and generic Collection.store when managed notes or other managed dependencies
are inherited. Do not copy a managed receipt into State or remove those guards
to extend this tool. Managed graph publication needs a separately reviewed
source/policy/owner contract. Explicit ordinary-State identity choices follow
the separate path below. Automatic identity resolution, Collection graph
capacity, installed capture and extraction-quality qualification remain separate
work; keep Graph optional and experimental.

### Follow an explicit entity choice through State CAS

The command-only `identity` export reuses ordinary State snapshot/get/put APIs;
it adds no SDK operation, model service or managed-note authority. Follow the
[operator exercise](../operator/graph.md#select-and-undo-an-entity-alias-or-merge)
from a current fact projection into alias, merge and latest-step undo.

`Evidence.graph_identity_key/1` addresses one partition selection row. Its
closed integer format 1 contains at most eight steps and 6,000 encoded bytes.
Each step binds alias/merge, original labels, the prior host State revision and
an exact source citation into its operation ID. Graph validates a fresh snapshot,
the named current source generation and unique supporting quotation, then sends
the existing State CAS with both expected row revision and namespace generation.
Finite source expiry is the existing `write_before_ms` deadline. Ordinary
approval still controls that write; a quote or stored selection grants no effect
authority.

`Evidence.graph_identity_resolution/4` derives a bounded comparison map only
after validating current facts and every active choice's full source span and
origin. Alias cannot shadow a raw fact entity, merge needs two distinct current
entities and neither operation can create a cycle. Traversal/conflict comparison
uses the map while preserving original fact objects, hashes, labels and citation
bases. Queries retain the source-token revalidation, then read the exact identity
row again, including its State operation identity. An active selection also
requires the snapshot namespace generation unchanged. Reserve and count that
extra read within the existing cumulative 512-read/16-effect limits.

Undo checks the exact current revision and latest operation ID, then removes
only that step under namespace CAS. It needs no fresh authority from an expired
or replaced supporting source because it reduces comparison data. Historical
inspection grants no current-source authority. Denied or unknown effects stop
without another action; a fresh inspect may observe an already-applied unknown,
but cannot settle it or authorize replay.

The shared Store validator recognizes the new `graph_identity` record kind;
older readers refuse it. Upgrade all artifacts sharing a partition together and
close old pinned Sessions before the first identity write. Corpus and Research
do not apply Graph choices to their own retrieval, but need compatible shared
Store readers to inspect that partition. Existing fact/source records are not
migrated or rewritten, and collection preserves the selection metadata row.
Existing per-source exports do not contain this partition-level row; do not
describe source migration as a faithful identity-selection export/import.

Extend the existing Graph protocol owner rather than building a second state
machine. Check alias→merge→undo, immutable source/fact bytes, CAS interpositions,
source expiry/replacement, forged tags/citations, tombstone refusal, bounded
requests and denied/unknown stop. The separate Session capture journey continues
to test ordinary approval and no-replay ownership; it does not by itself qualify
an identity command or real-world entity resolution.

### Retain compatible and conflicting attributed facts

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
not the measured reference artifact. The [operator example](../operator/corpus.md#add-explicit-embeddings-and-reranking)
names that route `blend`. The [comparison record](../archive/2026-10-23-p27-heldout-comparison/index.md)
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
for 32 worst-case records. Main-tool capture supplies already attributed explicit
facts through this same path without an inference action. The separately selected
model extractor derives affordable allowance before
egress. Output exceeding it leaves a draft for inspection/exact abort. Eight heads
per source allow updates to an existing kind/profile at capacity, while a ninth
refuses before draft/model work.

Extraction/rerank profiles can select `output_contract: "json_schema_v2"`; omission
retains v1 text. Recipe version and output contract differ. Structured helpers
use task-specific schema, native Ollama, 12-KiB request within unchanged SDK bounds;
v1 retains 8 KiB. Encoded task input separately permits 4096 bytes. No source/input
is shortened to fit or rerouted to another provider. See
[accounted effects](extension-effects.md#request-bounded-text-inference).

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

Query formatting belongs to the domain retrieval profile. `Profiles` accepts an
optional `query_prefix` only on dense/hybrid entries, with 1..1024 valid UTF-8
bytes and no NUL. `Corpus.rank_query/2` concatenates it with the already bounded
original query before calling the existing embedding adapter. The resulting
input remains within the adapter's 4096-byte per-input bound. The host receives
the ordinary `embedding.create` request; no SDK or native protocol was added.
The complete dispatched string supplies the canonical input digest checked on
every vector page. The original query remains in the query context for lexical
ranking, reranking and source quotations. Indexing sends unchanged source chunks,
so stored document-vector compatibility is unchanged. The host selection digest
identifies the embedding configuration; it does not additionally identify this
domain query format or attest weights. Preserve the package/options hash and
exact dispatched input when freezing an evaluation recipe.

To exercise this boundary, run the profile, graph-population and built-artifact
controls. The public Corpus driver indexes the same source and queries it through
dense/hybrid entries with and without the prefix. It verifies raw passage input,
exact query bytes, original citation and unchanged stored records. The profile
grid refuses empty, oversized, NUL and wrong-owner prefixes. These synthetic
controls establish the request transformation, not a semantic quality benefit.

For the opt-in `collection-dense` producer, Corpus `generation_produce` action
`selection` reads configured public metadata through `embedding.profile`, without
inference or a Usage charge. It returns `configured_profile`, `selection_sha256`
and `reported_model: nil`; configuration is not an observed provider model.
Keep its returned selection hash
on a v2 `embedding.create` request as `expected_selection_sha256` when the work
must use that same configuration. The host refuses a changed selection before
approval/intent; the result must still match the reported profile/model, complete
inputs and vectors. Read [the effect contract](extension-effects.md#generate-and-reconstruct-embeddings)
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
vector pages are ready. Explicit facts and guarded group selection have separate
commands; complete production and capacity qualification remain open.
The [two-page synthetic Session](../archive/2026-10-26-p30-p31-implementation/shared-producer-v4-public-session.md)
exercises the public continuation against an initially empty selected root. The
[guarded Session](../archive/2026-10-26-p30-p31-implementation/shared-producer-guard-session.md)
and [finite-TTL](../archive/2026-10-26-p30-p31-implementation/shared-producer-finite-guard-session.md)
controls exercise the private artifact's exact production delegation using a
synthetic loopback endpoint. Canonical artifact adoption is a separate build/
protocol check accepted in the
[public adoption review](../archive/2026-10-26-p30-p31-implementation/shared-producer-public-adoption-independent-review.md).
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

[Invocation training](extension-invocations.md) owns terminal output/leases/closure.
Only committed final receipt makes saved output readable. Consumers materialize the
exact delivery before interpreting status/evidence/claims/coverage; failed reads
are retained errors, not empty rankings, fallback, or repeated queries.

```sh
elixir dev/verify.exs source knowledge-complete \
  --sdk _build/dev/lib/ipse/ebin --input "$IPSE_SELECTION_ARTIFACTS"
```

The [five-check proof](../../dev/verification/knowledge_complete.exs) preserves ten
full quotes, escaped citations larger than fragments, graph bases beyond top-k,
opposite assertions, hashes, inert restart, no host-loaded domain modules, and zero
model calls. Repeat in installed mode with the same artifacts and compatible archive.

## Distinguish independent Research from the native ledger

Independent Research ranks provided sources or selected search/fetch gateway output
with BM25 and optional rerank. Its provided ledger normalizes supplied labels to open
assertions; it creates no native host receipts. Offline and MCP presets do not
retain a Corpus. Explicit provided-text retention uses the separate
`state-retained` preset and ordinary State action approvals. Default as-of
time is selected after capture so completion-stamped fetches are eligible. Explicit
safe integer fixes time; null refuses. Observations after selected time and expiry
at/before it exclude. Coverage retains raw captured bytes. Before each fetch/rerank,
sample remaining allowance once; below 1000 ms refuses, otherwise pass that same value.
An empty fetch queue ranks without requiring allowance for another fetch.
[Storage contracts](knowledge-storage.md) specify exact gateway envelopes.

Trace Research's `retain/2` implementation into `Store.start/4` with operation
`:put`. Research derives a canonical ID from the complete original body hash, fixes
generation 1/revision 0, and records the supplied ID/URI, unique exact quote and
UTF-8 byte range. Store independently validates those closed fields before any
snapshot or write. Its origin remains provided/nonhistorical; this derivation
data grants no fetch, native-source or current-use authority. Corpus's public
source route rejects the internal transfer field. An uncertain Store mutation
returns the existing unknown-effect stop rather than a known refusal.

The [operator exercise](../operator/research.md#retain-supplied-evidence-in-a-shared-corpus)
builds the two artifacts, reviews exact trust and selects the same State binding,
project scope and partition. That namespace choice is the sharing boundary;
matching source/profile names alone are insufficient. Corpus forget suppresses
the canonical body identity across supplied ID/URI/quote aliases and fresh
Sessions. A conflicting same-body origin cannot silently replace attribution.
Changed-body and fetched-source derivative suppression remain outside this mode.
The body/quote limits are 4,096/1,024 UTF-8 bytes; ambiguity includes overlapping
quote matches. `offline`, `mcp` and `mcp-model` retain their original capabilities
and exports and reject retained-store options. `state-retained` keeps its
provided-only flow and does not export `fetch_retain`.

The separate `state-fetched` preset performs one selected fetch and ordinary
State retention without search or inference. Trace `Research.fetch_retain/2`
through `Store.start_fetch_transfer/4`: Store starts the existing Adapters fetch,
accepts only its real host callback sequence, validates descriptor/result pages
and the complete fetch-v1 body/hash/URI, then constructs the private write
continuation. Caller arguments contain no body, prior receipt or destination
identity. Ordinary Store/Corpus put rejects the internal fetched-capture field.
This is shared pure package code inside one worker, not a nested effectful
extension invocation. Existing MCP/State actions retain their own approvals and
durable intent-before-effect order.

Store derives the same canonical full-body key as provided retention, carries the
actual fetch/read work into the unchanged effect/read allowances and records the
requested/observed URI, actual effect-result descriptor and exact unique quote
range. The origin is fetched data with `native_receipt: false`; the stored
receipt is not a grant or independently authenticated current-source lease.
Current managed-source/State-write guards stay in force. Same-body forgetting
covers URI/quote aliases and fresh Sessions in the exact shared namespace.

A new fetched body uses evidence-root format 2 and a version-2 capture receipt
with the original host selector base; it keeps that root and body immutable. The
format applies from its first staging claim through publication and suppression.
Provided/document roots retain their earlier format. Old Store workers must
refuse format 2 even when no selector was published, rather than treating an
unselected body as current. Match Research and Corpus artifacts from one build
and close older pinned Sessions before upgrade; their catalog cannot change in
place. New readers can inspect legacy format-1 captures but keep them untracked
and unavailable for current selection/recovery. Preserve their bytes and receipts;
do not fabricate a base revision or silently migrate their attribution.

A separate bounded
`fetch_origin` record selects a body for the configured binding and requested URI
within that partition. The initial validated State snapshot supplies a selector
base revision recorded with the capture. After known body publication, one CAS
advances the selector only under the actual resulting namespace generation and
expected selector revision. Publication order comes from those host State
revisions, never the gateway's reported timestamp. Preserve older bodies and their
captured citations; query selection marks a superseded or untracked fetched body
historical without rewriting its stored root. This is ordinary unverified State
version selection, not remote freshness or a native current-use receipt.

Snapshot revalidation includes both source roots and selectors. With 32 roots and
32 selectors, `Store.start_revalidation/3` composes at most two existing 32-token
reads. It carries cumulative counters and requires the same observed namespace
generation across them. The existing public single-call bound remains 32. Worker
continuation state stays process-local; only the bounded request/result envelope
crosses the SDK transport. Check actual encoded envelopes, including State scan
responses and paged final output, rather than assuming a token-count bound proves
the 16-KiB object limit.

For a known body followed by an unconfirmed selector, trace the explicit
command-only `Research.select_retained/2` through `Store.start_fetch_selection/4`.
Freshly load the exact source revision and pages; require its canonical body hash,
original fetch binding/URI and receipt, active metadata and original selector base.
Then make only an ordinary approved selector CAS. Forward a finite source expiry
through the existing `write_before_ms` fence. An already selected target is a
read-only observation; it cannot resolve the old unknown operation. A genuinely
later conflicting selector, even one with an older gateway timestamp, prevents
recovery from the old base. Expired/suppressed, altered and legacy untracked
captures refuse. Default same-body capture refusal remains unchanged.

Exercise denial before and after body publication, selector unknown-before and
unknown-after, independent inspection and a fresh explicit selection. Verify no
MCP request, repeated body write, attribution change or old-operation settlement
occurs during recovery. Interpose a later selection and mutate source revisions,
receipt bindings, expiry and body bytes to check refusal before a write.
Cross-backend and derivative suppression remain separate work.
The [operator task](../operator/research.md#fetch-and-retain-a-selected-source)
shows complete selection and recovery; no gateway is installed implicitly.

```sh
mix test test/extensions/knowledge/research_fetch_transfer_test.exs
IPSE_TEST_RESEARCH_FETCH_SESSION=1 mix test \
  test/extensions/knowledge/research_fetch_transfer_test.exs --only research_fetch_session
```

The pure controls use the existing adapter/Store fixture. The opt-in Linux
protected-storage Session case uses real synthetic MCP/stdIO and direct ordinary
Session approvals, with no Input/TTY or model. It binds the stored descriptor to
its actual recorded fetch, checks Corpus quote/forget/alias containment and
refused fetches with zero State mutation intents. Its interruption witness holds
the actual successful State-write callback before result append, kills the owning
Session and confirms native source-owner exit. Saved keeps that unresolved action;
explicit idle reopen must add no effect intents or replay it. Do not replace
this with a synthetic known refusal. The [dated control](../archive/2026-10-26-p30-p31-implementation/research-fetched-state-20261104.md)
records the bounded candidate, compatibility and remaining qualification gates.

Exercise independent Store forgery refusals, Corpus forwarding rejection, shared
forgetting and ordinary approval/journal/no-replay behavior with
`mix test test/extensions/knowledge/research_transfer_test.exs`. These controls
use supplied synthetic data and ordinary direct Session commands. The separate
native coexistence case exercises a reviewed registered loopback main route:

```sh
IPSE_TEST_RESEARCH_MIXED=1 mix test \
  test/extensions/knowledge/research_transfer_test.exs --only mixed_h1_coexistence
```

Run that opt-in case in the serial native-operator group with supported protected
storage. It recalls a real native-approved note, retains supplied text by an
explicit user command, then approves a model-selected Corpus read in the same
conversation. Inspect inheritance at a prefix where the invocation entry exists;
completion removes that live entry, so a final empty lookup proves no historical
property. Bind the actual delivered WorkerInput and current/confirmed output
release to the full union, then check the third provider request's exact citation.
The separate `--yes` model-selected retain must preserve the note union yet create
no State mutation intent/result or approval and leave the complete State snapshot
unchanged. Preserve its exact terminal and WorkerInput outcome; an error is not a
successful managed-derived write. Both histories must restore and reopen idle
without replay. The [dated control](../archive/2026-10-26-p30-p31-implementation/research-managed-coexistence-20261104.md)
records the bounded full pass and preserves its earlier fixture failures.

Native [`Tools.Research`](../../lib/ipse/tools/research.ex) instead captures literal
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
mix test test/extensions/knowledge/document_row_context_test.exs test/extensions/knowledge/document_acquisition_session_test.exs
mix test test/extensions/knowledge/domain_regressions_test.exs test/extensions/knowledge/graph_population_test.exs
mix test test/extensions/knowledge/packages_test.exs test/extensions/knowledge/query_completeness_test.exs
mix test test/extensions/knowledge/build_spec_test.exs
mix test test/ipse/tools/research_test.exs test/ipse/tools/research_integration_test.exs
```

Build fresh artifacts and run source/installed `knowledge` and `knowledge-complete`
with exact spans/generations/revalidation/no model calls. Storage lifecycle races
have a separate [worked exercise](knowledge-storage.md). Research MCP has its own
`knowledge-research` scenario and reviewed artifact. Protocol controls do not qualify
semantic answers. Follow [evaluation](knowledge-evaluation.md) for held-out predictions,
independent citation judgments, resource measurements, and strategy selection.
