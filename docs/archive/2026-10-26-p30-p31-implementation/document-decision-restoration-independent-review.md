# Independent document-stage decision design review — 2026-10-29

This scoped design review compares the [restoration proposal](document-decision-restoration-design.md)
with the [requirements audit](expiry-requirements-audit.md), the original
[document boundary](document-store-boundary.md), the later
[interposition receipt](strict-deadline-interposition.md), and the actual
Collection, DocumentStage, CollectionStore, Invocation, ManagedToolUse and native
Transaction implementation. It runs no tests and changes no implementation or
gate. The [plan](../../plan.md) owns implementation and qualification status.
Source observations refer to the working tree inspected during this review,
before document deadline dispatch is restored.

## Disposition

The original document-stage contract supports a fresh final locked decision for
each exact append, seal, consuming commit and fused equivalent. It requires
expired requests to refuse, exact epochs, original one-hour stage TTL, owner and
CAS binding, serialized reclamation and one consuming commit. It does not
explicitly promise physical rename completion within the same clock millisecond.
The later strict interpretation and adverse late-rename evidence must remain
historical and explicit; the proposal is a dated change from that stronger gate,
not a claim that the old physical guarantee passed.

Reuse of the existing actual-owner `Transaction.switch_before/4` is suitable for
this narrow decision contract. No new native protocol or persisted decision-time
receipt is required by the original document result contract. This conclusion
approves neither source-derived document publication nor another boundary's
retention, consent, review or delivery semantics.

**Required scope amendment before enabling document deadline dispatch:** ordinary
document staging must not also reopen managed-input document effects. The
proposal now accepts both host refusals described below. Subject to those gates
and the focused evidence already specified in the proposal, no additional
architecture or native protocol change is required by this review. This is design
acceptance, not runtime qualification or permission to treat currently gated
journeys as working.

## Blocking scope gap and accepted amendment

The original proposed dispatch change would have a wider effect than its prose
claimed. `CollectionStore.execute/2` passes the deadline from
`ManagedToolUse.with_effect/3` to `DocumentStage.execute/6`. The old Invocation
publication refusals name `collection.call` and `collection.managed`; they do not
name `collection.store`. With ordinary allow/`--yes`, a managed-input document
action can reach this callback. A later output-withholding gate does not undo a
persisted document effect. Restoring the document deadline route alone therefore
also restores managed-derived document mutations.

The accepted amendment requires both:

- A trusted Invocation refusal for mutating `collection.store` when
  `ManagedToolUse.managed_invocation?/1` is true, before action intent and any
  ordinary approval display or dispatch.
- A trusted CollectionStore execution backstop that refuses a mutating request
  when the `with_effect` callback receives a non-null deadline, before entering
  DocumentStage or its mutation path. Use `not is_nil(deadline)` so malformed or
  unexpected non-null values cannot become an ordinary fallback. No worker flag
  selects this classification.

The root reports these guards implemented while the document deadline gate stays
closed. Their runtime behavior remains for the focused implementation controls.
Read-only requests retain their existing current-use and output rules; this
amendment does not authorize managed output or nested delivery.

The callback distinction is sufficient for the inspected implementation.
`with_effect/3` calls `prepare/3`; an active action intent selects
`action_snapshot/1`, whose dependency set is the union of inherited invocation
dependencies and newly recorded `invocation.managed_reads`. Only the exact empty
set returns `{:ok, :ordinary}` and invokes `fun.(nil)`. Every admitted nonempty
set takes `use_prepared/4`: its deadline includes the finite pending-effect
deadline and policy/source deadlines, admission requires a current safe integer,
and the callback receives that integer. Invalid or unavailable lineage refuses;
it never becomes the empty ordinary branch. `managed_invocation?/1` likewise
treats any result other than `{:ok, []}` as managed. Focused negative controls
must exercise inherited-only dependencies, newly read dependencies, unavailable
lineage, and ordinary allow versus interactive approval. No stronger worker-facing
selector or general source-authority mechanism is needed for this closure.

## Exact ownership, one-use and CAS argument

The existing Transaction controller accepts operations only from the capability's
actual caller and top retained capability. Nested ProjectIdentity and Collection
acquisitions share the native owner, with the declared lock order. The native
`T` operation opens the fixed staged file, checks private regular-file and inode
identity, syncs it, samples the wall clock, refuses equality/expiry, then renames
that exact private name to fixed `root.json` and syncs the directory while the
same native process retains the lock. No extension callback or replacement body
runs after the decision. Success consumes the private staging name.

DocumentStage reads and validates headers, owner, epoch, ordered offsets, original
body hash and target revisions before building a complete immutable Collection
commit request. These reads use separate lock acquisitions; their safety depends
on the final expected namespace generation and exact record-revision CAS under
the publication lock. That CAS must remain intact. It rejects any intervening
append, consumption, reclamation or slot reuse without rebasing or replay.
Continuation deliberately permits a different invocation within the same exact
session/project/identity; the opening invocation remains provenance and does not
become a transferable permission. Successful consumption deletes the exact
header/ready refs with publication in the same CAS; duplicate consumption must
not select a second version.

An elapsed slot can be reclaimed only by exact epoch after expiry. A contender
cannot reclaim or reuse it while the prior native owner can still replace the
root. Caller/helper loss, response loss, uncertain sync or release must preserve
unknown and stop continuation. Inspection after confirmed quiescence is a new
explicit read transaction, not automatic effect replay. The existing Transaction
owner/controller and Collection final check/release path provide the appropriate
mechanism; fresh actual-owner schedules must qualify it for the restored path.

## Expiry and result boundaries to preserve

Every new stage mutation needs its own final decision against the minimum of the
original stage expiry and every trusted inherited deadline. Opening and reads
must not renew expiry; restart must retain the same epoch and expiry. Stopping
before the native decision until equality/expiry must prevent the root switch.
Stopping after a live decision at syscall entry may produce a late physical
effect; that is the documented in-flight case, not a passed physical expiry fence.
Stage TTL controls staged transport, and does not establish later source/evidence
eligibility. The managed-input guards keep that separate unresolved obligation
outside this restoration.

The native elapsed response is an error code, not an inspectable persisted check
time. The original document API does not require State's richer elapsed shape.
Keep the existing conservative result mapping: Collection currently maps any
failure after publication staging, including a switch failure, to its unknown
path; CollectionStore preserves unknown. A trusted early non-effect refusal and
a fully synced successful effect with confirmed release retain their existing
closed outcomes. Do not narrow a generic post-staging failure to known non-effect,
invent a clock receipt, or report a lost/suspended owner as successful cleanup.
Wall-clock rollback and clock failure remain limitations of the declared host
clock contract; no monotonic or physical-time guarantee follows from this review.

The implementation evidence must include the proposed native live append/seal/
consume journey and an ordinary public Session journey; exact expiry before the
final decision; the separate late in-flight schedule; old helper/platform refusal;
competing CAS, epoch reuse and duplicate consumption; actual owner/helper loss,
contender ordering and unknown without replay; deadline minimum/restoration; and
negative controls for both new managed-document gates and every gate kept closed.
Use prior evidence only where the exact source/helper matches. No runtime control,
private fixture, paid inference, installed profile, full capacity, Word quality,
shared-generation selection or milestone completion was qualified by this review.
The parent owns the proposal, implementation, documentation reconciliation and
batched checks.
