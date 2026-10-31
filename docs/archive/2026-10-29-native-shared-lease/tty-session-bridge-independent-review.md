# Independent review of the private Session/Host tty bridge

Scoped review, 2026-10-29. The [plan](../../plan.md) owns acceptance. This reviews
the [inactive bridge receipt](tty-session-bridge.md), manifest SHA-256
`8125763a87ec0ef4f620cdc5cf2c39ab6038ddc92c1ef9056ef35591e2214392`,
against the [caller wiring review](session-control-wiring-independent-review.md)
and [synthetic display repair](terminal-display-repair.md). No runtime or native
edits, model/network calls, gate changes or test reruns were made.

## Disposition

Accepted within the declared private, fixed-synthetic integration scope. No new
blocking defect was found in that scope. This is actual selected-worker,
Session/Host and native PTY integration evidence, with test rendezvous in Host;
it is not a production call site or protected-management acceptance. The
receipt's explicit activation blockers remain required work.

## Evidence verified

The [verification script](evidence/tty-session-bridge-review/review-manifest.exs)
and [result](evidence/tty-session-bridge-review/review-manifest.log) independently
verify all 64 manifest entries, the 44-file frozen source tar, all three complete
698-regular-file runtime inventories, eight retained feature BEAMs per graph,
and the exact helper in every graph. The helper SHA-256 is
`0a4b29229626ed00cdf34308b496af82f3656f1b22d736d8be5464fa0f66e7ef`.
Only Host changes between the uninstrumented and positive/identity graphs;
only LeasedTerminal additionally changes for the cancellation graph. Journal
and Writer retain their preceding caller-wiring bytes, including the Journal
metadata-alias repair. Symlink targets are not counted as physical runtime
files.

The retained test source constructs and imports a worker artifact, resolves its
explicit trust/capability configuration, checks Registry identity, invokes its
command and pauses the real Host immediately after actual action admission.
The bridge runs in that Host task. The uninstrumented Host has no bridge call
site. The worker source is retained, but teardown removed the exact selected
artifact; its actual admitted digest cannot now be independently checked
against a retained artifact archive. The cancellation test body is retained,
but the exact whole test file used by its passing run preceded a later
identity-test insertion and was not separately saved. These are real evidence
limits, not a complete frozen selected-artifact cohort.

I inspected the final two-case PTY log, separate passing cancellation log and
no-payload check, two passing Transaction cases, affected native controls and
compile marker. Earlier decoder/helper/FIFO and close failures remain in the
manifest. The first cancellation failure, which assumed original native owners
would disappear within 1.5 seconds, also remains. The corrected control observes
their actual exit instead. Intermediate diagnostic source is evidence for its
own trace only; it does not replace the final frozen source.

## Ownership, transfer and close order

Transaction identity is queried from the already retained native description;
the bridge does not release and reacquire it. The same-owner adapter checks
exact capability membership, slot, operation and original deadline, freezes
ordinary acquisition/read/mutation/release while sharing, records export order
and requires settlement in that order. Native requests additionally bind
sequence/depth, validate every retained lock, refuse duplicate active slots,
operation changes/reuse and more than 256 used operations per owner. Y/K retain
the existing authenticated FD-transfer and settlement machinery. Missing,
malformed or late replies fail through transaction-lost unknown and cleanup;
they do not authorize a retry or thaw. Native K does not independently encode
the adapter's manifest order; ordering here belongs to the trusted adapter.

The asynchronous Session identity request requires the current armed
caller/job/capability, matching guard token/operation and original deadline.
The result names the existing lock owner's pid and actual device/inode.
The bridge derives the two control identities after readiness, generates fresh
endpoint names/secrets, fixes four leases plus two owner controls, and repeats
the exact activation body. The inherited native reader performs the bounded
direct tty writes; D is write progress, not human observation or consent.

The initial real PTY failure exposed an actual integration defect: display and
slot settlement completed, but early owner-peer drop let an owner helper exit
before Session was ready to accept closure. The retained trace reaches final C
without a successful bridge return. The final native source reaps the reader,
drops the guardian's lease copies, completes each exporter C/F/G/EOF protocol
and sends final C while retaining both owner peers. It then requires the exact
operation-bound U before dropping those peers.

The final Host sequence receives C, requests Session's still-sealed
terminal-closing phase, sends U, observes guardian and Host-control clean exits,
waits for Session's own clean control exit, and then asks for Writer thaw.
Session binds the close request to the current task/job/capability and a Port
actually owned by that task; premature close is refused. Late or unexpected
control outcomes poison the operation. The same original setup deadline gates
known progress and completion; expiry may still initiate cleanup, but cannot
produce a new known success.

## Cancellation and remaining activation conditions

The cancellation fixture stops guardian and reader before activation, suspends
Writer and calls actual Session cancellation. It checks a prompt uncertain
return and actual Host death, then kills Session and guardian and waits for both
original native lock owners to exit. All four contenders remain blocked by the
stopped reader's inherited descriptions; they acquire only after it resumes and
exits. This supports the last-holder invariant and responsive cancellation
without Writer progress. It does not show hard cancellation of an admitted tty
write, post-write loss coverage, or universal terminal silence. The separate
captured-output check establishes no synthetic payload for this pre-activation
control.

Before protected activation, Session must independently authenticate the native
settled-close/owner binding and ordering: its current internal close request
trusts Host's C observation, and generic finish remains callable from settled
state. The three Transaction slots still need actual Identity, Consent and
Collection purpose/owner attestation, rather than slot numbers. The live
synthetic input reader is not bound to the matched tty. Actual management
journal ownership, held facts/expiry policy, operator input, safe redraw,
one-use Review and fresh final revalidation still require their own composed
journey and loss controls. The synthetic helper and adapter must remain outside
that production route until those conditions are reviewed.
