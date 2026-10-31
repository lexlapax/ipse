# Concrete boundary for reviewed forgetting

Historical implementation direction, **2026-10-29**, from local source review.
This changes no code or gate. The [plan](../../plan.md) owns status. Read the
[original Review component](native-review-component.md),
[late-forget evidence](strict-gate-lifetime-followup.md), and
[native output experiment](../2026-10-29-native-shared-lease/output-experiment.md).
No runtime tests, model calls or network operations ran for this investigation.
Lifecycle owns the subsequent concrete terminal handoff/closure protocol design.

## Selected boundary

Keep the **complete** proposed Review facts and current display/input binding.
`ManagedLifecycle.prepare/3` places the entire target record in `facts.target`;
`Review.with_review` displays the complete escaped JSON. This includes retained
literal text and evidence, not merely mutation metadata. Do not replace it with
a metadata-only review as a shortcut around the display boundary.

The mutation and display have different admission points:

- Mutation: preserve same-owner, exact-facts, live one-use `Review.consume/3`
  inside NormalizerV3 after signed target/root revalidation under the actual
  Identity → Consent → Collection native owners. An effect consumed while live
  may finish after permit expiry; `consumed_receipt` and the outer Review wrapper
  must withhold success after expiry/loss. The recorded late forget plus unknown
  result is compatible with this original contract, not proof of rollback.
- Display: each bounded native terminal-write attempt needs a final admission
  while all actual source/Identity/Consent descriptions remain held. Stop new
  attempts after observed loss or expiry. A write already admitted immediately
  before a control closes may finish and make the result unknown. The source and
  policy locks must survive through that write/quiescence, so later revocation,
  suppression, source replacement or successor admission cannot acknowledge or
  overtake it. No instantaneous atomic BEAM-death/write guarantee is proposed.

The output experiment's poll→control-close→write counterexample is therefore
insufficient by itself to reject this contract. Its native `leases` vector retains
the transferred open descriptions across the write and drops them only after the
destination is closed (`ipse-lease-output.rs`, lines 254–274 and 284–313).
The experiment still lacks the production destination, actual-owner binding and
final-holder closure required below. Its historical failure and unavailable mode
must remain intact; it is not retroactively accepted production behavior.

## Production direction for Lifecycle

1. Integrate the existing collector's descriptor validation into the **actual
   operator-v2 reader/guardian**, which already verifies matching terminals and
   writes directly to its retained tty. Reuse kernel peer credentials, pinned
   helper identity/pidfd, one-use secret, exact device/inode, FD type/flags and
   duplicate checks from `ipse-lease-sink.rs`. Do not send managed bytes through
   the experimental FIFO writer followed by a BEAM forwarding operation.
2. Bind one immutable full display, Review nonce, operation/client and exact
   ordered lease set before activation. Collection of descriptors alone grants
   no write. The trusted host revalidates the exact project, management/display
   authority, source union and root/facts after collection and before one-use
   activation. Worker fields, raw PIDs and prior acknowledgments grant nothing.
3. Extend native `send_display`'s existing bounded writes and absolute wall-clock
   check (`ipse-operator.rs`, lines 403–415). Use the authenticated minimum
   applicable absolute expiry; do not replace it with the pipe prototype's
   setup-relative duration. A successful nonblocking write admits those exact
   bytes to the actual tty. Buffered tty bytes are already admitted output,
   not authority for another onward forwarding action after lease release.
4. Define ownership of every copied FD across the guardian's `fork`. The current
   reader writes the tty and the guardian independently reaps/restores it;
   both can inherit descriptors. Every copy capable of extending the display
   lease must be accounted for. Known closure requires the writer to be finished
   or reaped, destination quiescent, and **all** transferred copies dropped.
   Never call `LOCK_UN` on a shared open description: it unlocks every holder.
5. Authenticate an operation-bound final display/close acknowledgment to the
   exact actual native instance. Existing exporters freeze normal operations
   after export and report ordinary release unconfirmed; a sink receipt is not
   already integrated into Transaction/Session cleanup. Specify how the host
   settles this without retry, releasing/reacquiring a live original lease, or
   claiming that exporter death proves recipient closure. Partial/lost closure
   remains unknown and cannot admit a successor while a holder can still write.
6. Release display/source/policy leases **before waiting for terminal input**.
   Reuse guarded operator-v2's displayed/release/input phases; its current reader
   waits for release before input (`ipse-operator.rs`, lines 521–545), and the
   BEAM adapter sends release only after the guard unwinds (`operator.ex`,
   lines 157–195). Preserve native terminal restoration, queued-input flushing
   and exact display/input hash/nonce provenance. Then reacquire fresh mutation
   locks, revalidate full facts/epochs/root, and consume Review once. A display
   acknowledgment cannot substitute for these later checks.

## Full expired-target disclosure needs an explicit scope decision

`NormalizerV3.forget/3` expressly allows deletion when original evidence is expired
or unavailable. `Consent.forget_deferred/8` remains available with revoked/expired
**capture** permission. Those are reducing-management rules, not permission to
reuse the note for inference or to redisclose arbitrary source text.

Consequently the design must say which authority admits the complete old target
to its explicit local management review. If it uses an existing current-use grant,
it must acquire its actual source/display leases and refuse stale disclosure.
It must not accidentally make active automatic capture a prerequisite for all
disabled-store forgetting. If a distinct reducing-management display scope is
needed to show retained expired bytes for the exact selected deletion, define
and review that scope explicitly, with retained target/root authentication and
native ownership; do not infer a general expiry waiver or conceal text from the
required full review. Missing original source authority and missing stored target
are separate cases. No such policy choice is silently implemented here.

## Smallest eventual gate changes and controls

After that terminal design and native-owned journal integration are reviewed:

- Restore only standalone `Management.forget` and retention policy `session`
  into the existing `manage(..., %{"kind" => "session"})` route. Both prepare
  `managed_literal_forget`; do not enable pin/duration/supersession alongside it.
- Narrow Collection's `native_review_publication_fence_unavailable` gate to keep
  other kinds refused, permitting exact native-literal forget only through the
  checked trusted normalizer/management route. Preserve signed suppression,
  advanced import floor, accounting, exact Core binding, current management
  epoch, no headless admission and outer mode/explicit deny checks.
- Replace Management's legacy `Journal.create` before `Lock.acquire` and legacy
  Writer path with the repaired native-owned locked header/append protocol.
  Its current header and file-server append separation would revive the known
  journal ownership race. Keep durable intent before mutation, reserved result
  capacity, native close/release confirmation and read-only operation inspection.
- Reuse the old delayed-consumption control as an admitted/unknown-effect control:
  live consumption, pause after admission beyond 30 seconds, possible committed
  suppression, outer unknown, exact inspection and no replay. Add pre-consumption
  expiry/no-effect, actual full-facts PTY display, wrong/stale/replayed review,
  concurrent target/management changes, disabled capture and session-only aliases.
- Add actual terminal controls for owner/guardian/reader/exporter loss around
  write admission. Independently race revoke/suppression/source replacement:
  competitors cannot acknowledge or acquire until the final display holders stop.
  Test before-admission refusal versus after-admission unknown separately, full
  lease closure, pipe/TTY substitution, partial output, queued input and complete
  target arguments. A synthetic owner pipe or collector-only pass is insufficient.

The immediate blocker is a production **terminal ownership and authenticated
closure integration**, plus precise management-display authority and native
journal ownership. Another polling check or a blanket effect-expiry gate does
not solve these boundaries. The original Review one-use mutation contract itself
does not require a kernel-atomic physical completion deadline.
