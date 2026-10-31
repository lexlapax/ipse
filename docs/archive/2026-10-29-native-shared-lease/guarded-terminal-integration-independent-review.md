# Independent guarded-terminal design review — 2026-10-29

This review covers the [terminal integration proposal](guarded-terminal-integration-design.md)
with SHA-256
`42d410565173f2df13512e6d8f7426d05b249dbe7cf2f778dfb51c35a67ae790`,
the [reviewed-forget direction](../2026-10-26-p30-p31-implementation/reviewed-forget-restoration-direction.md),
and the inspected operator-v2, lease collector/transfer, Transaction,
Session.Lock, Writer, StoredSources and Runner adapters. No implementation,
gate or runtime control changed or ran for this review. The [plan](../../plan.md)
owns activation and acceptance.

## Disposition and supported boundary

The proposed reuse of the actual native operator-v2 tty writer/guardian is a
suitable implementation direction. A final admission before each bounded native
write, continuous ownership of every required open lock description through the
write and its quiescence, and a truthful unknown outcome after loss fit the
selected contract. It neither requires an instantaneous owner-death/write atomic
primitive nor promises when a terminal emulator or person consumes admitted
bytes. Buffered tty bytes do not authorize a later forwarding write.

The proposal correctly requires a new export-capable live header/resume owner
from Session startup, authenticated same-description transfer, inert collection,
separate immutable activation, explicit all-holder closure, retained peer channels,
no `LOCK_UN`, release before human input and fresh one-use effect revalidation.
A second file-server writer, a VM pidfd, a monitor relay or the current inactive
lock-export mode cannot replace these mechanisms. Management's native-owned
header/append integration and the exact management-display purpose remain
separate prerequisites.

**Accept the architecture for scoped implementation with the blocking amendments
below. Do not activate protected terminal delivery from this design receipt.**
These amendments complete the proposed small state machines; they do not require
a general workflow framework or another policy engine.

## Required implementation amendments

1. **Make the Session/Writer barrier an exact operation-bound handshake.**
   The Session first enters a single-operation freezing state that prevents any
   accepted proof/job mutation or new journal effect. Preceding Writer/native
   effects must settle before its barrier acknowledgment identifies the exact
   journal identity/offset and source-window/job snapshot. An uncertain preceding
   append prevents activation. Bind the barrier to the actual Session, Host job,
   operation and owner generation; another job or later thaw cannot reuse it.
   Writer, Session.Lock and Session must agree on frozen state before the first
   native export. A frozen filesystem flock by itself does not freeze the
   BEAM source index or pending Session messages.

   Pick a bounded fail/defer rule before calling a frozen Writer; do not leave
   an unbounded mailbox of writes or synchronously wait on an append whose native
   helper is frozen. Session must continue handling cancellation and owner loss.
   Those events poison activation immediately and close owner controls before
   any cleanup record that would need the frozen Writer. Required intent and
   capacity preparation must finish before freezing. Only the authenticated
   matching closure/thaw handshake may resume proof mutation; uncertainty enters
   quarantine. This is a scoped barrier, not a second conversation owner.

2. **Make actual-owner controls persistent loss signals.** The two Ports must
   be opened by the actual Session process and actual Host job, respectively,
   with their real read ends handed to the native guardian. Prove descriptor
   ownership on the real runtime; no other write end may keep either owner alive.
   After the authenticated handoff, use EOF-only cancellation, or an equally
   explicit sticky native loss state. Guardian and reader must not consume a
   cancellation byte and thereby let another holder observe a quiet channel.
   Poll/error/EOF cannot be cleared into renewed admission. Control descriptors
   are dedicated; changing shared open-description flags must not alter an
   unrelated channel. Each protected write checks the required controls and
   absolute expiry again, including retries after EINTR/EAGAIN. Observed loss
   poisons the operation; an already admitted attempt can finish as unknown.

3. **Separate displayed, closed, settled and input-ready phases in the actual
   BEAM adapter.** Existing operator-v2 `y` stops the guarded display loop and
   normally lets the guard unwind. In leased mode it must be displayed-only:
   neither `y`, an export `X` acknowledgment nor a BEAM message proves descriptor
   closure. Reader drop/reap, guardian drops, authenticated operation/slot-bound
   native close messages and each original exporter's framed settlement must
   precede guard unwind and input release. Session's original lock is thawed in
   place, never released/reacquired. Out-of-order, duplicated, partial and replayed
   close/thaw/input messages refuse or quarantine. Further Transaction slot
   exports must remain possible without waiting on an earlier slot's closure.

   Decide all required source/root/policy reads before the first frozen export,
   using the continuously retained proofs for activation, or specify the exact
   allowed same-owner read-only native check. Do not solve the frozen-stack
   restriction with unfenced file-server reads. Existing frozen Transaction
   `P` checks do not by themselves rederive a mutable BEAM source window.

4. **Close every output route after the protected phase.** Replace the current
   `display.rsplit(...).last()` redraw prefix with a fixed non-sensitive prompt.
   Protected buffers cannot feed redraw, fallback `IO.puts`, deferred terminal
   events, diagnostics or a later BEAM-forwarded write after lease closure.
   Only the native reader writes the protected body to the matched retained tty.
   Keep the input/restoration and queued-input rules. The separate worker-input
   pipe remains gated until its actual native writer has an equivalent binding
   and cleanup protocol; terminal integration does not qualify that sink.

5. **Make the resource and quarantine bounds concrete before activation.**
   Account for all lease FDs, retained peer sockets, exporter pidfds, owner
   controls, tty/restoration channels and transient ancillary FDs in guardian,
   reader, exporter and VM. The present collector's three-per-lease footprint
   is roughly 396 FDs at 131 leases before extra terminal/owner channels, and
   fork creates another per-process footprint. Retaining new close channels is
   not free. Use one overall finite setup deadline across collection, not 131
   independently renewed waits. Refuse insufficient FD/process/framing budgets
   before any protected write without silently reducing the supported source
   count or raising global limits.

   A failed transfer after `sendmsg` is a possible received copy. Quarantine
   retains the exact holder/slot/operation accounting, blocks further conflicting
   admission and bounds new allocations. A timeout is not confirmed cleanup.
   Clear it only after authenticated all-copy closure or independent native
   accounting of every possible holder and actual quiescence; no missing path,
   helper exit or BEAM acknowledgment alone is sufficient. Physical cleanup may
   remain unbounded for an in-flight kernel write, while status/cancellation
   remain responsive. This limitation must not become a false successful revoke.

## Exact lease-set arithmetic

The proposal's 131 calculation is 128 external source Sessions, one distinct live
Session and Identity plus Consent. The subsequently proposed
[management display scope](../2026-10-26-p30-p31-implementation/management-display-scope.md)
also requires the selected target's Collection lock through display. An immediate
management-only review needs the live management journal owner plus Identity,
Consent and Collection: four leases, without treating expired original journals
as current inference sources.

A generic operation requiring all 128 external sources, the distinct live
Session and all three target locks needs **132** distinct descriptions unless an
actual identity proves an allowed role is the same lease. Do not alias different
locks, drop the live Session, or lower the source target to claim it fits 131.
Keep that wider route gated or explicitly amend and qualify its fixed bound.
The management-only path can proceed as a small implementation within 131; this
review does not require enabling the broader route.

## Evidence required before activation

Reuse source-matched prior evidence, but require actual Session/Host-owned Port
loss, live header/resume export from initial acquisition, native matched tty
writes, the Writer/barrier schedules, protected-prefix editing/redraw, and the
full normal close/thaw/input sequence. Exercise each owner/guardian/reader/exporter
loss around transfer, activation, admitted writes and closure. Independently race
revocation, suppression, source/target replacement and successor acquisition;
none may acknowledge or pass an old writer that can still execute protected IO.

Keep before-admission refusal distinct from after-admission unknown. Test real
all-copy closure, low-resource/partial ancillary/backpressure cases, repeated
safe operations after thaw and refusal of an already-live old helper. Full facts,
real client/nonce binding, exact fresh revalidation and one-use Review consumption
remain mandatory. A deletion grant alone is not a broad expired-source display
waiver. No production activation, terminal quality, worker delivery, management
mutation or milestone completion is established by this review. The parent and
Lifecycle own proposal amendments, implementation and documentation checks.
