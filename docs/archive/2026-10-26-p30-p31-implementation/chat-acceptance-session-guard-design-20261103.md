# Same-reply acceptance: proposed Session-owned guard — 2026-11-03

This is a design for review, not implemented or verified behavior. It narrows the
[ownership reassessment](chat-acceptance-reassessment-20261103.md) to one
assistant-authored proposal whose original source is the active creating Session.
It does not adopt the quarantined draft or alter the
[frozen acceptance contract](baseline.md#confirming-a-proposed-decision).

## User and authority boundary

The host must derive the proposal from the assistant reply just completed in
this Session, journal its exact identity, version, text hash and reply source,
then actually render that proposal and a fresh `accept CODE` on the controlling
terminal. Durably record the render revision and current decision focus, and
require an actual native render acknowledgement before accepting the code;
a model assertion or queued display is not an acknowledgement.
The code selects only that rendered version and binds the project, client and
actual Session. It is not an effect permit. Journal the actual interactive
acceptance and its exact publication intent before any publication. Bare yes,
headless input, quoted tool text, a different client or Session, and stale or
reused codes cannot accept. Edits, supersession, interruption and expiry
invalidate the code; resume requires a fresh render and code for the still
pending version, not a reused receipt. The first slice
may accept one source from this Session; it must validate any supplied
references under their own authority or visibly refuse unsupported references,
never silently drop them or invent supporting facts.

The Session remains conversation, card, Writer and source owner. The terminal
review must bind the exact rendered facts to the live Session/client and its
native reader. Follow the existing leased-terminal relation and SessionSource
patterns only where they actually cover this purpose; their generic descriptor
transfers are not themselves render, source, consent or effect authority.
The same reply source must be revalidated against the active SourceIndex and
its real origin and current policy, rather than reopened as an inactive
Session or reconstructed from a caller-provided ID.

## Native final-publication guard

Keep existing Linux opcode `j` and its two-source, no-Session-control behavior
unchanged. Add a distinct purpose-specific command, not a relaxed `j`, for
the single active-source case. After the standard sequence and depth it carries
one bounded absolute wall-clock cutoff chosen by the trusted host. Native code
requires exactly three valid held transaction locks, one live Writer control, one
live Session control, and exactly one live retained source description. No
pipe, staging or incompatible transferred operation may be active. Missing,
extra, dead or substituted imports refuse; the existing sequence, per-command
and transaction lifetime checks still apply. The trusted host, not the native
lock count, establishes the existing Identity → Consent → Collection order.
Reuse authenticated one-use
owner-control and source transfers: expected helper PID and peer credentials,
operation and role, secret, descriptor device/inode and owner/mode checks,
pidfd, peer and control liveness, and the existing bounded transfer deadline.
The exact role and active-source identities must come from the actual Session
and Writer handoff; native descriptor count or PID alone does not establish
their semantic relationship.

The transaction must enter an explicit acceptance-purpose state before any
publication staging or switch. In that state, ordinary `T` is forbidden until
the new guard is armed. The guard is a readiness check only. It does not authorize a code, claim
a review, consume an effect, or make publication atomic. Native code rejects
an expired or out-of-range cutoff and derives a fixed monotonic cutoff from the
remaining wall time, capped by the original transaction lifetime. It arms
exactly one `T` attempt for this guarded state. Refuse every second guard or
arm, including before the first `T`, and every retry after any switch attempt
or owner loss. The `T` wall cutoff cannot exceed the original guarded cutoff;
a substituted later cutoff refuses. Existing `source_switch_attempted` alone
does not establish these acceptance-purpose rules. Until that attempt or abort,
prevent any import, replacement or removal of the guarded controls and source;
allow only the bounded staging and immutable-install steps required by that
publication and checks of the same owner state. Keep all imported controls
and the source live through that root switch. At its final check, native code
checks the fixed monotonic and supplied wall cutoffs as well as the same held
descriptors and locks. The host chooses the wall cutoff no later than the
applicable transfer scope, review/effect permit, source/record validity and
consent deadlines.
Do not renew a deadline on a retry or stretch the existing bounded handoff for
human think time; expire and freshly render when the relevant authority lapses.
The current native primitive receives only a wall cutoff, while the existing
Review permit uses BEAM monotonic time. Converting the permit's remaining time
to wall time does not prove that the native switch cannot outlive that permit,
especially across descheduling or clock changes. The existing BEAM permit alone
cannot serve as the native switch's final expiry fence; no binding establishes
that its separate deadline holds through the switch.
The [clock-domain assessment](session-acceptance-clock-anchor-assessment-20261103.md)
compares alternatives and records a reviewed direction for an acceptance-only
native BOOTTIME permit. That permit may be integrated only after its actual
input, owner and clock-namespace bindings to the intended transaction are
implemented and independently reviewed; they remain unimplemented.
No ordinary unfenced root switch is a fallback. An uncertain switch or cleanup
is unknown even when a later read suggests publication happened.

## Elixir binding and effect lifecycle

Within the Session's active job and resource scope, use the real
SessionSource share barrier to bind the Session, Writer, source lock, source
proof and transaction capability to this exact acceptance purpose. At the
barrier, the Writer must attest that the exact acceptance event and effect
intent are its last synced acceptance records; bind their hashes, Session,
client, proposal version and owner to a private same-process capability.
Neither serialized terms nor a digest supplied by the model constitute that
capability. Replay validation must verify the event ordering and bindings, but
reconstruction must not recreate a live review permit.

Select the exact unique Consent operation ID before reserving anything, and
durably journal that ID and the acceptance purpose before calling Consent.
Bind the reservation, Session ticket, effect intent, settlement and recovery
lookup to that same ID and project. After interruption at any boundary, inspect
this exact operation; do not invent a replacement ID, reserve again, or infer
an unstarted effect merely because its result is absent. A reservation whose
state cannot be authenticated remains visibly unknown.

Before display and again under held Identity, Consent and Collection owners at
final use, derive and authenticate the selected candidate, original source,
project/pinned policy, current grant, valid-until deadlines, root and intended
normalized publication. Recheck every dependency that could have changed
while waiting for the user. A native Review permit must come from the exact
display and explicit input, bind the exact facts, intent and normalized request,
and be claimed once. The accepted decision establishes the operator's choice;
it neither asserts independent truth nor grants workspace or service effects.
The publication path calls the new guard only after those checks, while the
owners and Writer share barrier are still held. A later read of the accepted
record must independently validate its journal, source, consent and current
eligibility; the publication receipt is not a permanent read grant. When the
acceptance link and original reply identify the same Session journal, group
their checks and acquire that Session lock once; do not recursively acquire
it as two inactive owners or mistake a lock conflict for a missing source.
The active-Session case must use its actual retained owner rather than attempt
to reopen its lock. For multiple accepted cards, group every acceptance link
and original-source obligation by journal and authenticate every individual
link under the one held owner; validating only the first link is insufficient.
The first slice may explicitly refuse multiple cards from one journal, but the
full multi-card gate remains open until this grouped case is verified.

Refusal before an effect begins may be recorded as unstarted only when that
fact is durably known. Once a publication could have started, owner loss,
timeout, failed final acknowledgement, interrupted journal/result write or
unconfirmed teardown remains unknown. Retain the intent and inspect durable
state only on explicit recovery; never automatically repeat the publication.
Duplicate delivery cannot consume another permit or publish twice. Close
source, Session and Writer shares in their established order; a cleanup
failure cannot be promoted to success. A durably recorded operator acceptance
remains a historical interaction if authority disappears afterward; separately
report publication as refused or unknown. Do not present the decision as
saved/current without a confirmed effect receipt and current-use checks.
Cancellation and owner loss must signal
the effect asynchronously and let the Session remain able to service or revoke
the pending owner handoff; it must not synchronously wait on a task that is
itself waiting on that Session. Make reservation and publication uncertainty
visible to the operator with a path to inspect the recorded operation and
current state; inspection alone neither settles an unknown reservation nor
retries the effect.

Historical replay must validate that acceptance was recorded under actual
normal mode and a non-headless operator channel, as well as its render,
Session, client and intent bindings. Later entry into planning does not change
that historical fact; tampered historical mode or using planning re-entry as
acceptance authority must refuse. Restoring history grants no live permit and
does not bypass ordinary workspace or tool approvals.

## Decisive verification before adoption

Use an actual Session, real native terminal and bundled worker with a synthetic
provider. The positive journey must produce an assistant suggestion, complete
that reply, display the same journaled proposal and fresh code in that Session,
accept it once, publish once, and demonstrate later authenticated use. Resume
must add no publication or model/effect replay. Separately exercise rejection
of altered or stale proposal/version/text, unrendered, wrong, expired, reused,
cross-client and cross-Session codes, bare yes and headless input. Prove the
actual native render acknowledgement, durable render revision and focus, and
invalidation on edit, supersession and interrupted/resumed review. Exercise
historical normal/non-headless replay, tampered historical mode, planning
re-entry, and unchanged ordinary workspace and tool approval controls.

Native and host controls must cover missing, extra, swapped and dead Writer,
Session and source descriptors, wrong device/inode, role, peer or owner; source
withdrawal, Consent revocation/expiry, root changes and review-permit expiry;
failure during transfer and loss of each owner before and during the final
switch. Test cancellation while either party is waiting on a handoff, and
verify bounded shutdown without a Session/task circular wait. Test interruption
after reservation or intent, around the switch, after publication before result,
and during share cleanup: make unknown reservation/effect status visible,
preserve unknown where required and prove no automatic replay or duplicate
publication. Interrupt after the durable operation-ID record and before,
during and after Consent reservation; confirm recovery looks up that exact ID
without creating a second reservation. Verify that a recorded interaction
survives later source or permission loss without claiming publication.

Attempt `T` before arming; arm twice before the first switch; substitute a
later `T` cutoff; and retry after a switch attempt or owner loss: every bypass
refuses. Use deterministic wall-clock rollback and forward jumps to verify the
fixed monotonic cutoff never extends and forward expiry still refuses. Verify
grouped later-use authentication of every link when multiple cards and source
evidence refer to the same Session journal, or leave the multi-card gate open
with an explicit tested refusal. Keep standalone `j`
positive and negative regressions, including its refusal of Session control.
These tests are requirements, not completed evidence; a passing descriptor
guard alone does not complete the user journey.
