# Session journal ownership and durability

Session owns conversation and effects. `Ipse.Journal` supplies JSONL creation,
validated reads, inactive-file appends and locked tail repair;
`Ipse.Journal.Writer` owns the active append descriptor. The Rust advisory lock
continues to exclude a second session owner. `Ipse.Session.Lock` owns that Port
independently of Session, so a Session kill or supervisor shutdown does not itself
release it. Lock files retain their inode.
The [architecture](architecture.md#persistence-and-recovery) owns the wider
recovery model; [shared budgets](budgets.md) have a separate ledger contract.

## Ownership and appends

Session acquires its lock, validates configuration and recovery sources, and
repairs only an allowed final torn record before opening its writer. The writer
validates the complete journal once for its lifetime. Initialization failure
returns an error before linking; a successful writer links to its caller and
monitors normal owner exit. Session also monitors writer loss, stops and shuts
down dependent work. There is no writer restart or automatic append retry.

Only the owner may append or close. Each call encodes the new record, checks the
open file against its path and expected length, writes and fsyncs, then replies.
Session waits for that acknowledgment before admitting an effect or offering a
lifecycle source. Input encoding and IO failures never become successful
receipts. Optional source bounds can refuse a reference while still committing
the mandatory journal event; required-source refusal writes no event.

The writer tracks its byte offset and file identity instead of rereading and
decoding previous records per append. Descriptor/path device, inode, owner,
single-link, permissions and length checks reject replacement, foreign appends,
truncation, links and permission changes. A detected write/file failure closes
the writer; mandatory journaling failure stops the session. Status reports omit
record contents and private paths.

Writer calls have an explicit five-second acknowledgment deadline. A call exit
returns `journal_write_unconfirmed` without including private call arguments;
every mandatory Session append path exits deliberately as `journal_unavailable`
on refusal. A timeout proves neither absence nor completion of a write. Session
termination shuts down owned work and kills its writer. The independent lock
guardian waits for tracked writer, root/nested worker, scope, registered resource
and delegated child-guard exits before unlocking, including when Session death
skips its termination callback. Dispatch barriers register workers before they
can act; the writer is registered before its first append. A queued append cannot
overlap a replacement writer while that functioning lock is retained. It never retries a timed-out record. If kernel
IO delays process termination, cleanup can outlast client deadlines; this contract
does not promise bounded disk latency. A stuck tracked process can retain the
lock indefinitely; do not remove its lock file or claim cleanup from a timeout.
Unexpected loss of the lock helper or guardian stops Session without appending.
The guard is an ownership mechanism, not protection from same-user interference
or proof that an unknown OS/remote effect stopped. Resume trusts only validated durable records
and keeps started effects without recorded results unknown.

These checks are not a live cryptographic prefix proof: a same-size in-place
rewrite is not revalidated on every append. The journal is exclusively owned
while its session holds the advisory lock; other programs must not edit it.
Same-user filesystem control is not an adversarial security boundary. Full
resume/source validation remains mandatory. In particular, this journal strategy
does not replace the budget ledger's stronger live prefix-hash check.

Use the stateless `Journal.append*` functions only for inactive journals under
the appropriate lock. They retain complete-file validation and its historical
cost. All active Session append paths, including feed receipts and operator-wait
sources, use the owned writer. Its BEAM participates in extension host identity;
the persisted JSONL and source-offset formats do not change.

## Recovery and growth

Appends do constant work with respect to prior journal length. Fsync is still a
synchronous durability barrier: Session waits for its writer, so slow storage can
delay replies. No universal approval-latency guarantee follows from moving IO
and repeated decoding out of Session. Caller deadlines and unknown-effect rules
still apply.

Opening, restoring and inspecting a journal still require history validation;
the journal has no cumulative disk quota or automatic rotation. Context
compaction changes effective model input, not retained journal bytes. A reviewed
[fresh-session handoff](../operator/recovery.md) is the existing way to continue
with bounded context while preserving the original evidence. Segmentation,
retention, redaction and secure erasure require explicit future contracts; an
extension must not promise them by deleting only its own retrieval state.

Regression checks cover source offsets, optional versus mandatory records,
owner-only calls, initial corruption, file changes, normal/abrupt owner exit,
writer loss during inference, controlled callback stalls beyond the acknowledgment
deadline, owned-worker cleanup, unknown-effect resume without replay, retained
memory and append CPU across 2/64 MiB
histories. Timing probes separately measure the actual filesystem and Session
approval path. See [verification evidence](testing.md#current-evidence-and-next-checks)
for measured results and platform limits; no power-failure certification is made.
