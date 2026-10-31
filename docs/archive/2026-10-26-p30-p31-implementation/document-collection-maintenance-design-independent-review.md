# Independent review: document Collection maintenance and migration

Dated 2026-10-29. This reviews the frozen [proposal](document-collection-maintenance-design.md)
with SHA-256 `e6114d91d22197fcbbd1397564e39a6d9108590bc5fbb9a457add4761fe514e5`.
It is a design review, not implementation, authorization, or milestone acceptance.
The [plan](../../plan.md) remains authoritative. No runtime tests, model calls,
or sealed quality inputs were used.

The fixed project/profile scope, separate explicit maintenance trust, same-lock
CAS, exclusion of all `host.*` keys, conservative retention of unpublished
builder outputs, and multi-invocation scan are appropriate directions. Two
incompatibilities with existing storage must be resolved before implementing the
proposed fence and migration as written.

## Blockers

1. **Floor advancement destroys checkpoints.** The proposal advances the
   Collection floor on every maintenance open and close, including export, yet
   also promises to retain a same-floor migration checkpoint. Existing
   `Collection.prepare/3` drops `checkpoint` whenever a commit advances the
   floor. Thus an export fence can discard an existing rollback point and a
   close after migration can immediately discard the newly retained checkpoint.
   Every such advance also spends a permanent operation ID and grows lineage.
   Give the maintenance barrier its own durable epoch, fenced and changed under
   the same native lock and generation CAS, or explicitly revise and validate
   checkpoint semantics. Destructive deletion must still advance the actual
   floor and invalidate incompatible rollback. A barrier epoch must be carried
   by every relevant publication continuation and cannot be inferred solely
   from an untrusted caller's cursor.
2. **Logical bytes do not identify the original packed record.** `DocumentStage`
   stores the caller's original part boundaries in its `document_value` object;
   `value.read` concatenates those parts and returns newly sliced logical bytes.
   Different legal part boundaries produce different encoded packed objects and
   therefore different physical hashes, even for identical logical content.
   The proposed `Migration.digest/1` commits the packed hash and size, so a
   logical-only stream cannot guarantee faithful reconstruction. Specify a
   bounded, authenticated export of the original part layout or exact encoded
   packed object and its reconstruction, including escaped and Unicode values;
   alternatively define a separately versioned repacking migration and prove
   its mapping and digest transition. A plain whole-value SDK response is not a
   solution to the frame limit.

The proposed persistent fence also needs an explicit recovery transition. The
request table lists open, checkpoint and close, but the prose requires inspection,
adoption and abort after owner loss or expiry. Define a fixed-scope, separately
authorized cross-Session recovery operation that rechecks the exact fence and
generation, proves old native work has quiesced, changes the ownership epoch and
preserves unknown effects. A BEAM DOWN message or elapsed lease is not that proof.
Without this transition an interrupted owner can leave the namespace fenced
indefinitely. Reserve its terminal resource allowance before opening the fence.

## Trust and traversal

Document reachability belongs in the bundled knowledge extension; the host
should enforce the selected project/profile, explicit maintenance permission,
private-key exclusion, same-lock fence and exact generation/revision/hash/size
checks. A separate permission can authorize ordinary document deletion, with
full proposed arguments presented under existing approvals. This must remain
distinct from managed notes and their protected source/consent/output rules.

Those host checks do not independently prove that a worker's mark set is
complete. A worker can propose deleting an exact current descriptor that is
still reachable. Therefore do not describe the API itself as enforcing
reachability against a malicious worker. The useful official GC must implement
and test complete traversal of all relevant document roots, partitions, pending
work and retained dependents, and must refuse corrupt or unavailable edges.
Host-private progress records need authenticated ordering, ownership and bounds;
their privacy alone does not make a caller-supplied mark a semantic proof. No
trusted-plugin framework or generic workflow engine is required to make this
distinction.

The publication barrier must cover every ordinary mutation path at the native
generation CAS, including direct inline publication, stage creation and
consumption. Existing stage ownership intentionally ignores `invocation_id` on
continuation while retaining project, Session and extension identity; preserve
that behavior only where the new maintenance owner and adoption rules explicitly
allow it. In particular, version each continuation so a pre-barrier token cannot
resume later, while a fresh token can advance through its own authorized stage
mutations without rejecting its own changing generation or floor.

The full opening descriptor commitment need not be rehashed after every private
checkpoint if the host proves each such mutation cannot change the public record
map and checks its exact next generation. Compute and authenticate it at opening,
maintain that invariant through the fence, and recompute on recovery or another
path where the invariant is not established. This avoids repeatedly hashing an
8,192-record set during a 512-page scan while preserving completeness checks.

## Capacity and useful work

The permanent 32,768-operation ledger is an implementation prerequisite, not a
postponed test detail. Existing `Migration.reserved_operation_slots/1` assumes
32-record import pages and does not reserve the per-value `DocumentStage` writes
needed by the proposal. In a no-reuse case, preparing and accepting 8,192 inline
records needs at least 16,384 successful mutations before fence operations,
imported operation IDs, operation pages, checkpoints or larger multi-part values.
This arithmetic is illustrative, not a measured full workload. The earlier
[fused-write dry preflight](fused-document-writes.md#recalculated-recipe-and-remaining-refusal)
estimated 31,758 operations for its older initial-plus-rebuild recipe before
migration and GC; the newer shared layout may change that count. Produce an
exact ledger for the actual selected shared recipe and every maintenance stage,
including imported IDs and protected terminal reservations. If it cannot meet
the frozen workload, solve the separately reviewed bounded history/floor
compaction problem without erasing receipts or reducing the workload.

Preflight must also include private mark/frontier and plan records, stage slots,
pending and checkpoint values, manifests and physical orphan cleanup, together
with existing notes allocation. A small successful cleanup or migration is not
evidence that old-plus-staged rebuild and sustained turnover fit the envelope.

## Minimal first implementation slice

Implement a fixed-project, read-only document descriptor inventory under an
explicitly admitted maintenance capability. Reuse the existing Collection
metadata and ordered selection; exclude all `host.*` keys before pagination and
return complete bounded descriptors with generation, floor and a coverage tag.
Validate that only the fixed namespace and profile are reachable, that stale
generation and private cursors refuse, and that complete ordered multi-page
scans use zero value-object reads. Include an actual Session/trust-denial control
and full SDK frame bounds. This slice supplies useful inventory without giving
workers deletion or migration authority and without changing floor semantics.

Then resolve the barrier/checkpoint, recovery, physical representation and
operation-ledger issues above before adding a narrowly authorized destructive
GC or streamed migration. Their acceptance still needs real Session execution,
crash/unknown inspection, complete domain traversal and the frozen populated
workload. P26/P27 or released-notes conversion requires its separate admitted
source, suppression and lifecycle review; this inventory does not authorize it.
