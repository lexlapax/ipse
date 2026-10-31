# Proposed native lease handoff

This is a design for the [descriptor experiment](index.md), not an implemented
or admitted protocol. The protected supersession and managed nested-result paths
remain fail-closed. It applies only to one bounded host-owned operation and gives
workers no new authority.

## Authorities and lock order

The current publication peer validates original source proofs first. Inactive
Session sources are protected by their own source-lock helper Ports, sorted by
Session ID; a live same-Session proof comes from the owning Session and Writer
under the separately held Session lock. It then obtains the project Identity and
Consent leases through the protected native Transaction helper, in that order.
The collection observation uses its own checked view; publication later reopens
and rechecks the exact root before consuming the one-use review permit. A display
lease does not itself authorize publication or make a successor's content current.

The corresponding ownership gap is that these locks are held by native helpers
other than the process that writes the terminal or worker pipe. A BEAM monitor or
link can detect loss but cannot establish that one helper stops writing before a
different helper releases its lock. Starting another independent flock on an
already-held lock would deadlock or introduce a revalidation gap.

## Candidate handoff

1. The existing trusted owner validates the exact source proofs, project, policy,
   target, operation and deadline. It acquires source leases in their existing
   order, followed by Identity and Consent. It selects exact retained open lock
   descriptions, never worker-provided file descriptors or paths.
2. A host-created, one-use native channel transfers those same descriptions by
   `SCM_RIGHTS`, with bounded message sizes, a fresh operation binding, peer
   authentication and descriptor identity checks. The Linux experiment verifies
   only the kernel transfer/locking behavior; the authenticated channel and
   production helper support still need to be implemented and audited. The
   original helpers must keep their lock descriptions until the transfer is
   acknowledged. Any malformed or partial transfer refuses the operation.
3. The native sink retains all received descriptions through the entire guarded
   write. For terminal review, both guardian and reader inherit the same
   descriptions before the reader can write the first byte. The reader observes
   control/owner loss and the wall deadline during output. Only after the displayed
   acknowledgement and after all display writes have stopped may the native
   holders close their copies and allow operator-input waiting. The BEAM
   publication peer then reacquires and rederives current facts before spending
   the review permit. Unknown cleanup remains unknown and is not replayed.
4. For a managed result delivered to an extension worker, the bounded native sink
   would similarly hold the exact source, Identity and Consent descriptions while
   it writes the result to the already-authorized worker input pipe. The worker
   must not receive the lease descriptors or a way to select them. Delivery must
   bind the exact journaled action result and honor its deadline; any partial write
   or unconfirmed cleanup is recorded as unknown/withheld rather than continued.
5. No holder may issue `flock(LOCK_UN)` on a shared description before every
   guarded writer has stopped. The current lock helpers release by closing their
   descriptors; that behavior must remain a checked contract. Session shutdown
   must wait for or otherwise account for the native holders, including the live
   Writer/source lease, before the final description can close. Merely waiting
   for a BEAM peer's DOWN message is insufficient.

Holding the kernel descriptions prevents a separate cooperating writer from
committing a revocation or source replacement during the guarded write. It does
not by itself prove that no byte can be emitted at the exact instant a Session or
Host dies; native owner-death cancellation, buffered writes, guardian restoration,
and the ordering of the final write and final close need independent controls.
If those guarantees cannot be established, the operation stays unavailable.

## Separate sink admission still required

Descriptor receipt and the helper's X reply are only transfer observations. A
future pinned native sink must begin in an inert collecting state with no ability
to display or write the worker pipe. Its host-owned operation binding must name
the exact purpose, owner, source generations, policy, deadline and ordered expected
lease identities. For each transfer, it must authenticate the exact live helper
through a non-reusable process binding, authenticate the operation, check the
received open file's metadata against that binding, and own every received FD
with close-on-exec and cleanup on all failures. A same-UID PID check alone does
not prove executable identity or prevent PID reuse. The current fixture checks
PID/UID before sending its secret, but is not a pinned sink or a complete
process-identity protocol.

Only after all distinct expected leases have arrived and been revalidated may a
separately authenticated native admission fence transition that same sink into a
write-capable state. The fence must be tied to the still-live original Session
and Host and the exact operation, not merely a BEAM monitor, prior ACK, or X
reply. Any missing, duplicated, stale or uncertain transfer, owner loss, invalid
source or expiry destroys the collected set without writing. A complete design
must prove how that native fence orders owner death against admission and against
the final write; this document does not claim such a fence exists.

The sink and any inherited native writer must retain all descriptions until
writes have stopped, then send an independently authenticated completion and
close acknowledgment. A transferred open description can outlive its original
helper, so its release remains unknown until that protocol is established.
In particular, `--lock-export-v1` acquires a new source lock; it cannot copy an
already-live legacy Session lock. Migrating a live Session requires a separately
proven gap-free migration and preservation of source-existence checks.

## Required controls before activation

- Verify each transferred descriptor is the exact held Session/source, Identity
  or Consent lock, with retained directory and inode checks; reject missing,
  reordered, duplicate, changed and foreign descriptors, forged peers and stale
  operation bindings. Preserve existing bounds and lock ordering.
- Exercise real Session, Host, publisher, native guardian and native reader death
  at every transfer, partial display/write, acknowledgement and release boundary.
  Retain roots, journals, protected control state and terminal/worker output; prove
  cleanup and no replay rather than inferring it from a monitor.
- Race revocation, source replacement, expiry, cancellation and collection changes
  during display or worker delivery. Verify blocked policy/source changes, exact
  deadline fencing, post-display revalidation and truthful unknown outcomes.
- Test the actual managed worker result pipe and input continuation, including
  backpressure and partial writes; do not substitute a synthetic terminal or a
  host-only callback for the worker protocol.
- Review descriptor and process limits, FD inheritance/close-on-exec, platform
  support and the security of the transfer endpoint. The current experiment is
  Linux-only and is not evidence for another backend.
