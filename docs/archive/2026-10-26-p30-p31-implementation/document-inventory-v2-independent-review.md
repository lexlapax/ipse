# Independent document inventory and maintenance v2 review — 2026-10-29

This is a scoped source and retained-evidence review, not P31 acceptance. The
reviewed [inventory receipt](document-descriptor-inventory.md) has SHA-256
`55952323d61ff59a09649396e819402d090696db013519c59b08c29650aabbf3`; its
[manifest](document-descriptor-inventory/manifest.json) has SHA-256
`afa3cb876e4ee6ccf9af21f8fd17331af1900272f79b0e92841327c3f586f7e0`.
The reviewed [v2 proposal](document-collection-maintenance-v2-design.md) has
SHA-256 `62f5cca802d37156719b1b48f17b7cf72a4a98b97e1d34f01d41bbaa9d18d56a`.
Those documents were not modified by this review.

## Read-only inventory disposition

No blocking defect was found in the reviewed, narrowly scoped metadata read.
`CollectionStore.prepare` derives the document namespace from the existing
project identity and selected operator binding; execution checks the Session,
invocation, live registry, current job and held project binding. The closed
request contains no caller-selected namespace or profile. `DocumentStage`
classifies the operation as a read and checks the requested generation; the
Collection entry reacquires its native lock, loads validated document-profile
metadata and checks that generation again before selecting the page. Final
native check and framed release must both succeed or the result is unknown.

Directory excludes every `host.*` key before sorting, counting or seeking. Its
exclusive cursor, 16-row request bound and tail trimming maintain ordered,
complete rows and a last-returned-key continuation within the 4 KiB result
limit. Descriptors come from validated manifest metadata and identify the
physical record hash and byte count, not the logical `value.stat` body. The
result validator checks row shape, ordering, public names, safe numbers and
size. It does not independently prove that a page or a full traversal is
complete; the honest producer and generation-pinned walk provide the scoped
semantics, and the receipt correctly makes no GC reachability attestation.

The retained pure, native and Session logs report 1, 1 and 2 passing focused
tests respectively. The pure source walks 40 maximum-length keys with maximum
safe numeric widths, including actual page shrinking. The native fixture
corrupts all seeded value objects and still obtains their manifest descriptors,
checks stale and notes-profile refusal and compares the seeded store files.
The telemetry value-read counter is emitted by the new path itself; the
corrupted-object control and source trace provide independent support for the
no-body-read claim. The public Session test exercises an independent worker,
foreign-project and private exclusion, recorded action validation, Saved
reconstruction, no mutation approval and calculated 4,227-byte Worker request
envelope. Negative controls cover missing/foreign trust, forged binding,
missing identity, stale generation and private cursor. The recorded Worker
exchanges succeeded, but the envelope figure is calculated from recorded
payloads, not a separate maximum-size stress of every possible envelope.

The operation is logically read-only: the existing Collection lock path can
create the directory and persistent lock file for an absent store. The unchanged
seeded store comparison does not establish zero filesystem changes for an
absent namespace. This distinction does not imply a new mutation grant.

Independently checked all six archived source hashes against both snapshots and
current source; all eight logs, two scripts and 705 retained runtime files match
their manifest hashes. The runtime is the documented copied prior cohort with
four modules recompiled, not a build of the whole current Host/Session source.
The helper, platform, full-scale traversal, native owner-loss schedules and
production integration are not newly qualified by these tests. No test or model
call was run as part of this review.

## Corrected maintenance design disposition

The separate metadata epoch avoids the earlier proposed read-only open/close
advancement of Collection's destructive floor and its checkpoint-clearing
behavior, provided the new manifest format and every mutation path actually
implement the specified atomic checks. The layout recipe also addresses the
earlier physical-versus-logical mismatch: original part boundaries and exact
encoding must reproduce the source descriptor before acceptance. These are
design resolutions, not implemented or tested guarantees.

One necessary transition detail remains underspecified: the proposal calls the
epoch monotone and explicitly advances it on adoption, but does not explicitly
require **each open** to advance it. If a barrier opens and closes at the same
epoch, a continuation created before opening can resume afterwards with a
matching token despite the intended fence. Specify and atomically persist a
strictly greater epoch on every successful open and adoption; define the close
transition and preserve the resulting epoch in idle state, refuse overflow,
and test a pre-open continuation after close as well as during the barrier.
Each continuation entry and any direct-finish path must check the current
epoch, including paths that resume after the barrier has closed.

Recovery correctly treats elapsed time, BEAM DOWN and an unrelated lock probe
as insufficient. Its required authenticated quiescence of the prior Session,
native effects and all retained or transferred leases remains an integration
prerequisite; the proposal does not establish that the production owners can
yet produce that evidence. Unknown operations must remain liabilities through
adoption and inspection, without replay or success inferred from timeout.

The host's proposed exact descriptor CAS, fixed namespace, private-key
exclusion and explicit maintenance authorization do not establish that a
worker's proposed deletion is unreachable. The proposal correctly assigns
ordinary document reachability traversal to the Knowledge extension, requires
conservative pending-family retention and describes deletion as separately
authorized; managed notes remain under their distinct protected contracts.
Actual complete traversal, crash continuation and useful preservation still
need implementation and adversarial tests across both root generations.

The ordered whole-workload ledger remains a blocker. The proposed union of
known and incoming operation IDs and per-value staging, acceptance, progress
and terminal reservations is the right shape; exact counts, metadata/disk
peaks and cleanup passes are not yet measured for the required full workload.
During implementation, allocate every new local operation ID outside the
reserved incoming set or refuse a conflicting identity with no lost terminal
reservation; validate this with fresh and populated target collisions. If the
required sequence exceeds the lifetime ceiling, reviewed bounded compaction is
needed before mutating maintenance, rather than treating safe refusal as useful
GC or migration completion.

Physical-layout export also needs a bounded authenticated layout operation and
tests for original part reconstruction, escaping, exact bytes and unsupported
formats. Existing logical `value.read` alone cannot supply the boundaries. The
private frontier, descriptor commitment, multi-invocation read budget,
reservation debit and recovery invariants are proposals requiring concrete
schemas and implementation. No destructive API, complete ledger, full
GC/migration/turnover run or broader milestone qualification follows here.
