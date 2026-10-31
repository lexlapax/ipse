# Independent review of the inert matched-tty lease probe

Scoped review, 2026-10-29. The [plan](../../plan.md) owns acceptance. This reviews
[the inert terminal checkpoint](terminal-lease-inert.md), manifest SHA-256
`a6472791750540594ad05a2c061bd5e03338f5b83b05d4b36bccd2d14b18e24e`,
against the [terminal design conditions](guarded-terminal-integration-independent-review.md),
[owner-control review](owner-controls-independent-review.md) and
[caller-wiring review](session-control-wiring-independent-review.md).
No implementation/native edits, model/network calls or passing runtime repeats
were made by this review.

## Disposition

Accepted as an inert Linux matched-tty guardian/reader ownership subsection.
No concrete blocker was found in the declared collection, fork ownership and
close procedure. This accepts no protected display, payload, activation, Review,
production call site, management owner or connected Session/Host-to-tty journey.
All protected-output gates remain closed.

## Manifest, collection and watches

The mode requires fd0 and fd1 to be actual ttys with matching device/inode/rdev,
then opens and rechecks a fresh bounded tty description. It retains the existing
operator channel lock. Private control fd3 and status fd4 must be FIFOs and are
separate from tty input/output. The probe accepts no display payload and calls
no tty write or input routine.

The bounded request has a nonzero operation, exactly two owner entries in
Session/Host role order, and one to four lease entries. It checks exact body
size, slot range, nonzero exporter operations, and distinct private addresses,
secrets and device/inode identities across the complete manifest. Reusing a slot
for the same exporter PID refuses, while distinct exporters may use the same
slot number. `H` is preliminary manifest acceptance for collection, not completed
peer/FD authentication or activation.

Each owner handoff uses the prior operation/role/secret/peer/pidfd checks and
validates the actual read-only FIFO description and identity. Each lease uses
the existing authenticated regular-file receiver, including exact lock identity
and close-on-exec. Successfully collected owners retain their read end, helper
pidfd and authenticated peer. Those descriptors, plus already collected lease
exporter pidfds, are watched during subsequent connection, receive, acknowledgement
and private-frame waits. In particular, loss of the first owner while waiting
for the second cannot be hidden by polling the tty or a different fd0 pipe.

All new collection waits use explicit control/watch arguments and the same
absolute native deadline. The shared watcher rejects an oversized watch vector;
the probe's fixed manifest is much smaller than that bound. Raw ancillary
parsing and regular-file validation remain intact. On partial errors, local
owned files/sockets drop without retry or invented close confirmation. This is
still same-helper identity authentication, not attestation of arbitrary peer
mode or immutable terminal payload.

## Forked ownership and close

Fork occurs only after both owners and all lease descriptions have been
collected. Both processes inherit the exact lease open descriptions, tty/channel
lock, owner read ends and peer/pidfd state. The reader closes its copy of the
guardian-to-reader pipe's write end. Guardian death therefore leaves pipe HUP
visible to the reader; it cannot keep its own guardian-liveness writer alive.
The child also polls the inherited owner controls, their helper/peer state and
lease exporter pidfds. It consumes neither owner-control bytes nor terminal
input and exits through `_exit`, which closes every inherited OS description.

On normal close the guardian sends the private reader-close byte and waits for
that exact child to exit successfully. It then drops its own lease copies,
sends operation/slot-bound C records to the exporters, and completes each F/G
and exporter endpoint EOF in manifest order. The matched tty/channel and owner
state remain retained through the last settlement. Only afterward does the
probe emit its final C close frame. That frame reports completed probe closure,
not current source authority, input validity or effect permission.

The failure `ChildGuard` is declared after the collected lease values, so Rust's
reverse local destruction kills and reaps the surviving child before dropping
parent lease copies. Successful reap disarms that guard. A stopped reader is
killed during failure cleanup; a killed guardian cannot drop the reader's copy
for it. The recorded stopped-reader case demonstrates the resulting last-holder
behavior after all original exporters are killed. There is no forked protected
writer in this mode.

The guardian does not independently poll a child pidfd while waiting for its
close command. Reader failure is rejected during close/reap; if no close command
arrives, the guardian's global deadline also enters failure cleanup. The reader
itself polls its guardian pipe and watched loss every20ms; the single guardian
deadline drives this probe's close procedure. These observations must not become
a claim of continuous protected-write admission or an independently enforced
child write deadline. Physical kill/reap and kernel/filesystem operations are
not hard wall-clock preemptible; uncertainty never permits replacement work to
pretend old descriptor copies vanished.

Unexpected owner data remains sticky because neither process reads an owner
pipe. Unexpected control/peer input, wrong close operation, bad settlement,
exporter loss, timeout or failed read/write yields an error and no confirmed
close. Original exporters continue holding their own descriptions until their
separate release. Dropping the recipient copies never calls `LOCK_UN` or
simulates release by opening a different lock inode.

## Redraw repair and evidence limits

The existing guarded v2 reader now uses the fixed non-sensitive `approval> `
redraw prefix after release. It no longer reuses the protected final display
line while handling edits. The ordinary unguarded prefix remains unchanged.
The retained real-PTY test displays a synthetic tail, releases, types and deletes
one character, and observes the fixed prefix without the tail repeating. The
affected release-before-input test also passes. This repairs that narrow redraw
path without qualifying its old display writes as retained-lease-protected.

The five final source-matched fixture cases use real PTYs, four distinct
synthetic native Transaction owners and two native control senders. Normal
settlement proves the child is reaped and ordered exporter closure completes
while the original owners still retain locks. Guardian loss with the reader
stopped proves every flock remains unavailable after the guardian and original
exporters die, until the reader resumes and exits. Reader loss and owner-helper
loss return unconfirmed, emit no close receipt and preserve original locks until
those owners stop.

The reader-loss fixture kills the child and then sends the close request; it
does not measure immediate spontaneous guardian child-loss detection. The
partial owner-loss case occurs after the first owner descriptor and before any
lease FD is collected. It verifies that partial owner setup refuses cleanly;
source inspection covers the added watches during later lease collection. No
new runtime schedule was invented or rerun to enlarge those claims.

The fixture checks no tty output at collection, with stderr explicitly directed
to null. Probe code never writes its tty handle or accepts protected bytes. The
common wrapper can report a fixed generic refusal on stderr if a future caller
connects stderr to a tty; this is not evidence of protected output or a universal
zero-byte stderr guarantee. No terminal facts, operator input or real Review
were exercised. The two native owner senders are not actual BEAM Session/Host
owners, and their separately tested caller wiring is not connected here.

## Frozen provenance and remaining work

[Verification](evidence/terminal-lease-inert-review/review-manifest.exs) and
[its result](evidence/terminal-lease-inert-review/review-manifest.log) validate all
32 manifest entries,34 archived regular source files, all697 physical runtime
files, final fixture and operator-test binaries, and matching helper
`9b1ba1d304925279cccfd1d1bcbd5d377b9ee1f46089eed7db2fd710ac2df68b`.
The runtime is the earlier owner-control Session graph with its new Runner/helper
pin: Session, Lock, Journal and Writer exactly match that earlier graph. It is
not a coherent qualification of the newer Session-control wiring. The inherited
dependency source symlink is not followed as runtime content.

The five `v5` fixture logs, eight affected owner-control tests and two operator
PTY tests were inspected, not repeated. Earlier helper/fixture binaries and
results remain separately pinned; an initial Rust comparison-type failure was
corrected before the runtime controls. The final fixture adds explicit no-close
receipt assertions in the relevant loss cases. Compiler-driver API warnings in
the Runner compile log are not an empty-warning whole-source build.

Before active display integration, the actual matched-tty protected writer still
needs immutable payload/destination and all-lease activation, actual Session/Host
or distinct management owner binding, continuous per-write owner/expiry checks,
actual guardian observation of reader loss before further display, forked copy
accounting across writes/redraws, authenticated all-copy closure and
safe release-before-input, then fresh facts/policy and live one-use effect
admission. Four synthetic locks do not establish four real management owners.
The larger132-description route remains beyond131. No user-facing activation,
full capacity, non-Linux or final-audit acceptance follows from this subsection.
