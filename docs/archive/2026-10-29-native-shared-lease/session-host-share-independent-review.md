# Independent review of inactive Host-to-Session sharing

Scoped review, 2026-10-29. The [plan](../../plan.md) owns acceptance. This reviews
[the Host/Session section](session-host-share.md), manifest SHA-256
`2f98a960b31c5607b041ffea3d157b6fb75511d7ab0e1bbb78573c4c2a7d292c`,
against the prior [operation seal review](session-operation-barrier-independent-review.md)
and [Session share review](session-share-candidate-independent-review.md).
No runtime changes or test reruns were made. The receipt's deadline wording was
corrected with the section owner's coordination and root's authorization.

## Disposition

Accepted as inactive Host/Session infrastructure. No concrete blocker was found
within the declared scope. Actual selected-artifact, Host-task and worker
controls now replace the earlier synthetic Session action fixture for this
section's new tests. They run through a separately instrumented Host, whose
production counterpart has no call site invoking the new adapters. This is not
an uninstrumented production journey, output admission or terminal acceptance.
No protected gate is opened.

## State, identity and deadline boundaries

The adapters are private host primitives and are not exposed as SDK, worker or
command operations. The genuine worker requests the existing `context.available`
action. Session admits and journals that action through its normal current-task
and job checks before the test-only Host rendezvous runs. Share admission then
requires that same actual task caller and job, the exact active intent,
non-interrupted parent, matching selected extension identity, live identity and
allowed Session phase. The controlled artifact was imported, selected and
prepared through Artifact, Config and Registry, and the worker runs independently.
Foreign callers and altered intent are refused in the retained tests.

Session returns the installed seal before processing another mailbox message.
The asynchronous Writer drain does not allow ordinary Session handlers to run
in between: the seal clauses precede the normal calls and events. Source/proof
queries, action commits, job replacement and ordinary mutation calls remain
blocked. Unknown events, owner/task loss or failed requests quarantine instead
of entering the ordinary handlers. Snapshot admission rechecks session, job,
operation epoch, caller, parent, action and phase, then the inherited guard
checks the actual tracked Writer's opaque token before arming.

One monotonic deadline is created at begin. Writer and arm success replies,
export and settlement requests, export and settlement success replies,
cancellation success, and final thaw success all check that original deadline.
Neither export nor settlement resets it; the guard receives the same absolute
deadline for their native operations. A delayed timer message cannot make a
late success valid because reply handlers also read the clock.

Pre-export cancellation and post-settlement finish do not have an additional
request-time deadline refusal. They may initiate guard cancellation or physical
Writer thaw after expiry. This is cleanup, not renewed authority: every ensuing
success reply still checks the original deadline and poisons Session if late.
Even if Writer has physically thawed before that reply, Session remains sealed,
then permanently quarantined; ordinary proof/job calls and further exports
cannot become usable. The original receipt's blanket statement about checking
both requests and replies was corrected to describe this distinction. No new
refusal was added that could obstruct cleanup.

The late-Writer fixture forces the Session deadline into the past through
`:sys.replace_state`; it proves reply-side refusal in the real task path, not a
terminal timing boundary. Late arm, settlement and thaw refusal are supported
by source inspection, not additional dedicated runtime race controls here.
The five-second timer remains a mailbox deadline, not hard preemption of earlier
synchronous work or proof of complete future setup/quarantine latency.

## Transfer, settlement and uncertainty

Export requires the exact original task, job and opaque capability in armed
phase. Its recipient argument is a fixed 68-byte native request. The existing
native checks bind recipient peer, operation transport and lock device/inode;
the wrong-inode control fails closed and quarantines the actual Host operation.
Recipient construction, intended mode and binding to a future display payload
are still the trusted future caller's responsibility, not proved by accepting
those bytes.

An export acknowledgement changes only transfer state. Finish is refused until
a separate native settlement succeeds. Guard settlement uses the existing
recipient close protocol, including authenticated C/F/G exchange and recipient
endpoint EOF; the inert recipient drops its descriptor before the confirming
handshake completes. Writer's asynchronous thaw independently asks the guard
for the exact token/operation's settled or cancelled state. Session clears its
seal only on the matching successful thaw reply while caller and deadline are
still valid.

Pre-export abort cancels the armed operation and follows that same confirmed
thaw path. An abort after transfer poisons rather than treating descriptor
transfer as undone. Cancellation kills the actual Host and worker, but returns
unconfirmed; it does not infer that native IO or a recipient's descriptor has
stopped. The recorded stopped-recipient control closes Session and its exporter
while the recipient remains the last actual flock holder. A contender continues
to fail until that recipient resumes and exits. This precisely separates BEAM
cleanup from descriptor closure. Late, unsolicited or failed responses cannot
restore poisoned state, and no journal action is replayed.

The native positive covers one retained Session lock and one inert recipient.
It does not establish forked all-copy terminal closure, collector role or mode
admission, four distinct management leases, the larger source set, owner EOF
fences or an instantaneous owner-death/write boundary.

## Frozen evidence and remaining scope

[Verification](evidence/session-host-share-review/review-manifest.exs) and
[its output](evidence/session-host-share-review/review-manifest.log) validate all
25 manifest entries, seven archived source files and both complete 697-file
runtime inventories. The graph inventories differ only in
`Elixir.Ipse.Extension.Host.beam`. Both retained Host BEAMs match their respective
graphs; the instrumented source is exactly production Host plus the single
post-action-admission rendezvous. Both graphs use the same pinned helper
`a64c58bb32864d217501f750c0e5fa25abf4562bfda53fab6c4f2573115f4995`.
The Journal source exactly preserves the separately accepted metadata alias
repair. Both selected worker artifact archives retain their three regular files.

The final retained standard controls report three passes, native socket controls
three passes, and affected prior seal controls five passes. They establish
selected identity and real task plumbing, cancellation with suspended Writer,
forced late Writer refusal, actual transfer and native close before thaw,
post-transfer uncertainty and last-holder behavior, and wrong-inode refusal.
They do not supply every possible adversarial identity or scheduling race.

The initial in-memory Host instrumentation failed Registry admission because its
host digest lacked the matching on-disk BEAM. The corrected graph writes and
loads its own instrumented BEAM before admission, and is retained separately
from production. The zero-test selection and intermediate logs remain historical
evidence and are not counted as the final controls. Compiler-driver API warnings
in compile logs are not empty-warning whole-source qualification. No model,
network, terminal or aggregate test ran in this review.

Still open: actual production call-site and Host control ownership; immutable
payload and recipient construction; both owner EOF controls; authenticated
all-lease admission; matched tty and forked reader/guardian closure; per-write
admission and safe redraw; complete management lease settlement/thaw; fresh
facts/policy and identity validity at the eventual effect boundary; live one-use
approval and management integration. The generic 132-distinct-lease route still
exceeds the present 131 bound. None is discharged by this scoped acceptance.
