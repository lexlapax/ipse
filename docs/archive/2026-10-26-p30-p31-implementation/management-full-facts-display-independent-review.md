# Independent review of private full-facts management display

Scoped review, 2026-10-29. The [plan](../../plan.md) owns acceptance. This reviews
the [candidate receipt](management-full-facts-display.md), manifest SHA-256
`6132862ddd8cf60f2bb197f638880ed94edc220c10508554b6ac4117b9b1266d`,
against the [management purpose](management-display-scope.md),
[journal/control prerequisite](management-share-controls-independent-review.md)
and [held signed-target review](management-held-target-independent-review.md).
No runtime/native edits, model/network calls, gate changes or test reruns were
made by this review.

## Initial disposition: acceptance held

Two concrete deadline omissions require narrow repair. Both are source
findings, confirmed by the implementation owner; this review did not run a new
runtime counterexample or claim an observed disclosure from either omission.
The original frozen candidate remains unchanged as evidence. The target,
historical-purpose, actual-role and closure audit found no additional blocker
within the declared private display-only scope.

1. **The final success check precedes outer cleanup.** ManagementTerminal checks
   the original wall deadline before returning its successful display receipt.
   Collection, Consent and Identity then perform their own checks/releases;
   Writer/guard close and resource finish follow. Resources' final `:closed`
   branch checks its setup monotonic deadline, but the outer
   `full_facts_display_candidate/4` return has no fresh original-wall check.
   There is also no final monotonic check after resource finish. A forward wall
   change or delayed final cleanup can therefore let a known closed-success
   return after its captured budget. Check the original clocks after that
   complete composed call, before exposing known success. Preserve uncertain
   cleanup outcomes; do not reset either clock or strand cleanup on expiry.
2. **Generic status writes lack immediate post-readiness admission checks.**
   Native tty writes, display-completion D and reader D progress recheck clocks
   after readiness. Generic `frame`, used by R/H/L/C, calls `ready_watch` then
   `output.write` without a fresh post-ready clock check. It also has no wall
   expiry argument. A later Host rejection cannot establish that every new
   native status syscall was admitted before expiry. Repair the applicable
   frame admission checks; initial clock-handshake framing has no received wall
   expiry yet. The original receipt's every-status wording is too broad for
   this frozen implementation.

## Evidence verified

The [verification script](management-full-facts-display-review/review-manifest.exs)
and [result](management-full-facts-display-review/review-manifest.log) verify all
115 manifest entries, 56 source files, four complete inventories of 698 physical
regular runtime files and 14 retained feature BEAMs per graph. Graph changes
match the recorded rendering, absolute-clock and hook steps. The production
helper is `755a9dc3f77c580c4ab01475cb25bf771875d4351b4bbd3059cb16834043a176`
and contains no display stop-hook markers. The hook graph differs only in its
matching Runner and helper. Separately retained instrumented sources equal the
exact stale-snapshot, post-activation pause and pre-U close pause substitutions
in the frozen sources; their BEAMs are separately pinned.

The selected bundled artifact has digest
`26c3e913d377f1d3f2f67eab7666770506f6517e5bf7a82eb9e8c36c43d95b2b`.
All ten archived files match the final runtime bundle, its manifest digest and
nine declared file hashes/sizes. The negative native derivative changes exactly
one source line: it removes absolute deadline narrowing. Its late-status
failure is retained separately from the production helper's passing control.
Earlier relative-clock controls remain historical. The support file later
gained loss cases, so earlier observations do not all have an exact whole-file
test snapshot. Temporary signed fixture homes are intentionally absent; no
complete original operator/source journal is claimed.

## Target, roles and output

The candidate resolves an existing project and actual selected artifact recipe,
captures an existing positive management epoch, and revalidates that recipe
inside the held callback. Identity, exact epoch/fingerprint management Consent
and authenticated Collection are nested in order. The held reader validates
the signed format/live/anchor rows and selected literal, retaining original
provenance and signed deadline. ManagedLifecycle derives the complete stored
record, hash/revision, metadata, root, context and proposed operation facts.
Expired/revoked capture and unavailable originals do not become live recall or
source endorsement; this follows the accepted historical management purpose.

The Transaction stack must contain exactly three same-owner descriptions in
slots 0/1/2, with the live Identity marker and exact held Consent/Collection
capabilities. The fourth description is the management journal's original
share-capable owner. Actual CLI and tracked journal peer own the two controls;
Session/Host and synthetic controls do not substitute for them. These are
trusted same-VM checks, not protection against arbitrary host-code forgery.

Rendering reuses complete escaped Review facts/challenge and adds a timestamped
signed-deadline/source-status label. The final complete display must fit the
existing 65,536-byte bound; it contains no compact replacement or omitted facts.
The challenge is displayed but never read or accepted by this candidate.

The native clock sample precedes Host's remaining-budget calculation. Combining
that earlier sample with the remaining original budget is conservative. Native
conversion uses an earlier Instant and rounded-up monotonic sample and narrows
the initial timeout; it does not restart a relative display budget. The original
120-second wall/monotonic budgets start before preparation and the five-second
private setup bound only narrows them. Findings above concern the remaining
admission/final-return gaps, not that conservative arithmetic.

## Closure controls and limits

Writer drains/freezes before export. Activation repeats immutable operation,
payload, tty and owner/lease bindings. The reader writes directly to matched tty
while retaining the descriptions. Reader reap, guardian lease drop and every
exporter's ordered C/F/G/EOF settlement precede native C. Operation-bound U
releases owner peers; both actual senders must exit before Writer thaw. Nested
owners release before the private outer receipt. Internal close sequencing
still trusts the coordinator and is not a public authenticated close API.

The retained final wrappers pass full expired/revoked signed-target rendering
with independently matched facts/display digests and stale-epoch pre-display
refusal. Native controls cover the full display bound, elapsed monotonic
deadline and delayed readiness, with a failing one-line negative derivative.
Loss controls prove a stopped reader can retain all four actual locks after
original owners die, and that losing the journal owner after native C but before
U yields unknown rather than thaw success. An already admitted chunk can appear
after owner loss; this is not hard syscall cancellation or human observation.

Input, client/tty challenge binding, one live Review permit, reacquisition and
fresh exact target/root/epoch CAS, consumption, effect outcome and public gates
remain separate required work. These display controls do not complete that
journey or the generic 132-distinct-lease case outside the 131 bound.

## Additive deadline repair disposition

The [repair receipt](management-display-deadline-repair.md), manifest SHA-256
`4e83f484e60e270f9f5b6099277f50112d8c99ec9c38b919e5b46a6375235413`,
repairs both findings. Accepted within the original private display-only scope;
the initial findings and frozen cohort above remain historical evidence.

The [repair verification](management-display-deadline-repair-review/review-manifest.exs)
and [result](management-display-deadline-repair-review/review-manifest.log) check
all 36 entries, 44 frozen sources, 698 physical runtime files and ten retained
feature BEAMs. Relative to the prior final graph, exactly Management, Runner and
the pinned helper change. ManagementTerminal, roles, held-target readers,
Journal, Writer and Resources retain their previous bytes. Production helper
contains no test markers. The final late-return instrumentation is exactly the
frozen source with the final classifier's wall argument replaced by an elapsed
value. Intermediate classifier/instrumented evidence precedes its second
monotonic sample and is not substituted for final-source evidence.

The classifier now runs after the complete controlled call and its `after`
cleanup. It admits only known closed-success after original monotonic, original
wall and another original monotonic sample. Late completion becomes unknown;
earlier refusal/unknown classifications are preserved. Generic status framing
checks before/after readiness and after bounded writes, with received wall
expiry for H/L/C and monotonic-only R before any wall expiry is supplied.
Reader-command and activation paths also gain post-wait monotonic checks.
Cleanup remains possible on expiry; these are discrete admission checks, not
instantaneous cancellation or an atomic clock/liveness guarantee.

I inspected the final pure classifier control, actual post-cleanup elapsed-wall
interposition, final signed-target positive, native monotonic/wall late-C
controls and retained negative derivative. The latter removes only the new
post-readiness frame check and emits late C; the matching repaired helpers
refuse it. The wall control does not change the host clock or observe a real
forward jump. Earlier owner-loss controls were not rerun against this repair,
and remain attached to their original helper cohort. No passing tests were
repeated by this review, and no public/input/permit/effect gate is qualified.
