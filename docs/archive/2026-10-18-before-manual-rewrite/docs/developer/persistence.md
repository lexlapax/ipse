> Historical reference only. Snapshot of `docs/developer/persistence.md` at `10b9dd66d06ef28718b58530a7e5b01c7c50397a` on 2026-10-18.
> Original body retained; relative links rebased for this archive.
> Use the [current manual](../../../../developer/persistence.md).

# Session journal ownership and durability

Session owns conversation and effects. `Ipse.Journal` supplies JSONL creation,
validated reads, inactive-file appends and locked tail repair;
`Ipse.Journal.Writer` owns the active append descriptor. `Ipse.Journal.Reader` decodes bounded
chunks, lines and record counts; operator-only `Journal.Limits` narrows finite
host ceilings without disabling mandatory persistence. The Rust advisory lock
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

Only the owner may append or close. Each call encodes the new record and checks
the open descriptor against its path and expected length. A private completion
owner opens a separate append descriptor, checks the same identity/protection/length,
writes and fsyncs, then closes it before replying. This adds constant work per
record; it does not reread history.
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

Active writer calls have an explicit five-second acknowledgment deadline. A call exit
returns `journal_write_unconfirmed` without including private call arguments;
mandatory Session append paths exit deliberately as `journal_unavailable` on
unconfirmed IO or invalid records. Confirmed quota exhaustion instead stops as
`journal_limit_reached`, after its terminal receipt. A timeout proves neither
absence nor completion of a write. Session
termination shuts down owned work and kills its writer. The independent lock
guardian waits for tracked writer, root/nested worker, scope, registered resource
and delegated child-guard exits, plus admitted filesystem completion owners,
before unlocking, including when Session death skips its termination callback.
Dispatch barriers register workers before they
can act; the writer is registered before its first append. A queued append cannot
overlap a replacement writer while that functioning lock is retained. It never
retries a timed-out record. A BEAM caller's `DOWN` does not prove its filesystem
IO finished: both ordinary file servers and raw dirty IO can continue after it.
`FileEffect` therefore owns admitted workspace writes, active appends, tail repair,
state critical sections and budget transactions until their synchronous calls
return. It is tracked before dispatch and is never killed by core cancellation.
Scope cleanup may time out, but the lock guardian still waits for that owner.
This does not promise bounded disk latency. A stuck tracked process can retain the
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
the appropriate lock. They validate history and reuse the writer's admission
and fsync primitives synchronously inside a filesystem completion owner. They do
not create a temporary GenServer or return while an append/close timeout leaves
queued work behind. Slow storage can keep the call pending until actual completion.
An existing Session lock guardian or task scope tracks that completion owner;
embedding callers remain responsible for their own lock lifetime. Repeatedly
opening inactive journals still has linear validation cost.
All active Session append paths, including feed receipts and operator-wait
sources, use the owned writer. Its BEAM participates in extension host identity;
the persisted JSONL and source-offset formats do not change.

## Recovery and growth

Appends do constant work with respect to prior journal length. Fsync is still a
synchronous durability barrier: Session waits for its writer, so slow storage can
delay replies. No universal approval-latency guarantee follows from moving IO
and repeated decoding out of Session. Caller deadlines and unknown-effect rules
still apply.

Each journal has finite host ceilings: 128 MiB total bytes, 100,000 events and
16 MiB per encoded JSON record, excluding its newline. Operator configuration may
lower each ceiling through top-level `journal`; project files cannot select it.
These are per-file admission/work bounds, not a process-RAM, whole-directory disk
or billing quota. Main and routed/inherited child Sessions use the operator policy.
Policy resolution reuses the existing closed schema adapter. No runtime service
or dependency is added.

The writer reserves 512 bytes and one event for `journal_limit_reached`. Normal
admission requires space for both the proposed record and that terminal receipt.
On exhaustion it writes/fsyncs the receipt once, refuses the proposed record and
stops Session before further dispatch. The receipt binds its enforced limits,
reason, previous byte offset and event count, without retaining rejected content.
No later record is valid in that sealed journal. A quota write with unconfirmed
IO keeps ordinary journal-unavailable/unknown rules; a timeout does not certify
that the terminal receipt committed. Already admitted effects can therefore
remain unknown, as with any lost result append.

Restore, repair and writer initialization decode incrementally with bounded
record and event counts, checking file size before reading and bytes during reads.
They do not allocate a whole encoded file or split it into every line first.
Decoded history is still retained for recovery, within those configured bounds.
Each reader scan is linear; complete Session startup repeats higher-level
validation/projection and can have additional costs with historical questions.
Sessions listing reads only a bounded header and does not certify the later tail.
CLI resume also discovers only that host-bounded header to recover workspace and
saved settings, then resolves operator policy before loading complete history.
The header is not a successful resume or proof that the later file fits the
operator's smaller bounds.
A legacy file over the host ceiling is refused unchanged rather than truncated.
`Journal.source_page` permits bounded inspection only for records within its
separate 1 MiB record bound; it is not a universal legacy export. Larger records
need developer-assisted bounded inspection and reviewed notes for a fresh session.
An overlong torn tail is also refused, and repair never adds a missing newline
beyond the byte limit.

Read-only saved diagnosis and handoff remain available for valid sealed journals,
including pending questions and missing started-effect results. A typed terminal
receipt is accepted independently by strict question/action reducers, while a
forged count or a subsequent record refuses restoration. An attempted answer
that cannot be journaled does not become an answered checkpoint. Sealed journals
cannot reopen for work, even with a larger policy: use an explicit reviewed
[fresh-session handoff](../operator/recovery.md), inspecting unknown effects and
asking unanswered questions again. Existing extension/runtime identity pins still
apply, including the reader and limits modules in the host digest.

Context compaction does not shrink retained evidence. There is no automatic
rotation, retention deletion, segmentation, redaction or secure erasure; these
require separate contracts. An extension must not promise them by deleting only
its own retrieval state.

Regression checks cover source offsets, optional versus mandatory records,
owner-only calls, initial corruption, file changes, normal/abrupt owner exit,
writer loss during inference, a real blocked FIFO write with Session death and
lock refusal until the reader drains, budget-lock retention, controlled callback stalls beyond the acknowledgment
deadline, owned-worker cleanup, unknown-effect resume without replay, retained
memory and append CPU across 2/64 MiB
histories. Timing probes separately measure the actual filesystem and Session
approval path. See [verification evidence](testing.md#current-evidence-and-next-checks)
for measured results and platform limits; no power-failure certification is made.
