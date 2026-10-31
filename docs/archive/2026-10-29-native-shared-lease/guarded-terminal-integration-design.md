# Guarded terminal lease integration: proposed protocol

Design checkpoint, 2026-10-29. This is **not implemented or approved for
activation**. Managed supersession, reviewed management effects and managed
worker-result delivery remain gated. The [reviewed-forget direction](../2026-10-26-p30-p31-implementation/reviewed-forget-restoration-direction.md)
defines the selected per-write admission boundary and the separate unresolved
authority for redisclosing a retained expired target. The [plan](../../plan.md)
owns acceptance.

## Accepted implementation amendments

The [independent review](guarded-terminal-integration-independent-review.md)
accepts the architecture subject to these requirements. The first increment
is the explicit management review of one stored target: its management journal,
Identity, Consent and Collection are four distinct leases. The separately
reviewed [management-display scope](../2026-10-26-p30-p31-implementation/management-display-scope.md)
governs this purpose and does not authorize inference or worker delivery. A
generic operation with 128 external source locks, a live Session and all three
target locks needs 132 distinct leases; it remains gated under the present 131
limit unless an actual role alias is proved or the bound is separately amended.

Before any Session export, the exact Session and Writer must complete an
operation-bound barrier after previous native appends settle. Its receipt binds
the retained journal identity and offset, source-window and job snapshot, owner
generation and exact Host operation. During the barrier, new journal/proof
mutations fail or are boundedly deferred before calling Writer; cancellation
and owner loss poison activation and close the owner controls without waiting
for a cleanup journal append. Only the authenticated matching closure/thaw
resumes the barrier; uncertain prior append or closure quarantines it.

Both exact-owner controls use dedicated EOF-only channels, with no cancellation
bytes that one reader can consume and make another appear live. Observed loss
is sticky. The legacy displayed `y` is display progress only: the actual BEAM
adapter must wait for `display_closed`, every authenticated slot close and
exporter settlement before guard unwind or input release. One overall finite
setup deadline covers every lease, and an explicit preflight accounts for 131
leases, peer sockets, pidfds, tty, controls, fork, ancillary and process limits.
Quarantine bounds new work and allocations but never turns a timeout or possible
received FD into confirmed cleanup. Revalidation after export uses only the
frozen, continuously held snapshot and explicitly allowed native identity
checks; it does not invoke an unproven fresh file-server read.

The inspected working-source SHA-256 values, in the order operator, transaction,
collector, transfer, stdio, Session.Lock, StoredSources, Runner.Operator,
Runner.Transaction and ManagedSupersession, were:

```text
5a8149ba3b6b6b55e41060ed56db1fb3ba572cef377b210c7fd3102010031e58
63d539664de74b8d9f9fec5fe783cf6c3f7cffcd8a34be8849242916abef6a34
e0a106f1b14d4552820800da7f8de61dd8a6ded45e8cae870b1ae5135eec176f
e356267c4fdc24d99b57905371de739a206562c8e16b1dd1649b1ee56afb6d34
404aa782b9fef36bc5fb140d32f14c71c6a263295d9d6fc78d4e52a6ddd61a9a
902fc28a85205f0c29127d556a7f1fd6ea6a58e422cf00778e33858eb4f58fd5
93a913ec0ddc13f7a73f5c172be75ca04194bb8c984ac1f8dba1d21c5e048770
d977c21176fec947e6791fb14df410888834bcc724f9c1423a2defe9e6622338
42712ec98540941f29ff33aff15c97ba50dabe41611bfe3dcad1c03c452278b0
16ab2d671bd98b7f5a06c02a3c5c7b57abb680485e11fa7127ff5ad7c61e1c51
```

## What exists and what must change

`StoredSources.with_verified` locks each inactive original source in Session-ID
order with `Runner.lock_source`, checks its original journal, retains a read
descriptor and repeats source/lock checks on unwind. The current live Session
uses its `Session.Lock` and Writer to resolve its exact local source. Identity
and Consent are nested in the retained native Transaction owner, in that order.
The signed collection observation and exact full Review facts are prepared in
the publication peer. These locks are not held by the current operator writer.

The Linux collector validates peer credentials, a pinned executable inode and
pidfd, a host-provided secret and each received FD's metadata. It has **no**
all-leases admission, source/policy proof, payload binding or final close
protocol. Its 131-descriptor capacity covers up to 128 external source locks,
one separate live Session lock and Identity plus Consent. The existing output
experiment writes to a pipe and is not a terminal integration.

Transaction's `exported_slots` freezes all ordinary operations and release once
any slot is shared; `P` and further `X` are the only allowed commands. Its `X`
reply reports transfer, not recipient closure or owner liveness. The source
helper exports only with `header_enabled == false`. Current fresh/resumed Linux
Sessions instead use header/resume owners, whose native process also owns every
Writer append and torn-tail repair. It cannot currently export its live lock.
The inactive `--lock-export-v1` opens and flocks a new lock; closing a live
legacy holder to use it would create a forbidden gap.

Operator-v2 directly writes to a matched tty and has a guardian and forked
reader, an authenticated nonce, displayed `y`, and a separate release-before-
input phase. Its current reader also derives the later input redraw prefix
from the last display line. That prefix can contain protected facts, so the
leased mode must replace it with a fixed, non-sensitive prompt before any lease
is released. Full proposed facts remain in the original protected display.

## One operation and its native owners

The trusted host constructs one immutable, versioned operation binding from the
actual active Session/Host job, exact client/tty, Review command and nonce,
full escaped display bytes, source union and generations, project identity,
policy/management epoch, exact root/facts and the minimum applicable absolute
wall expiry. The binding includes a fresh 128-bit operation identifier and
digest of the complete display and ordered lease manifest. The host creates a
fresh unique secret and endpoint per lease. These bytes are private runtime
capabilities, never worker/SDK fields or journal/log content. Facts, source
proofs, policies and the exact payload remain checked by existing Elixir code;
native code interprets only bounded framing, identities, FD ownership and time.

For an eligible Linux operation, acquire the actual live Session/journal owner
from first Session startup, the distinct inactive sources, Identity and Consent
in their existing global order. No path, PID, descriptor or lock is selected by
a worker. Source files, local Writer proof, policy, root and facts are rederived
under those original retained owners immediately before sharing. The guardian
may obtain the tty channel nonblockingly before those locks; it must never wait
indefinitely for a terminal while holding source/policy locks. Failure to obtain
any lock or the channel is a refusal, with no protected display.

Two dedicated owner controls represent the **actual BEAM Session process** and
the **actual Host job process**, not the VM PID. Each owner opens its own private
Port to a pinned native handoff helper; a one-use authenticated `SCM_RIGHTS`
handoff gives the guardian the actual read end of that Port's owner-control pipe.
The handoff helper stops reading after transfer. Only the corresponding BEAM
Port owns the write end; no shared reader or unrelated duplicate is permitted.
The guardian directly polls each received control for cancellation/EOF and
verifies their operation binding. This is a proposed API: prove on the real
runtime that each exact owner's death closes its end and that no other FD copy
keeps it alive. A relay process, BEAM monitor, or VM pidfd alone is insufficient.

## Proposed sequence

The names below describe closed, versioned private messages, not a new public
SDK. All frames have explicit lengths, ordered sequence numbers, finite setup
and operation deadlines, exact role/count checks and bounded partial IO.

1. **Prepare.** The native guardian starts inert, pins its executable/instance,
   authenticates both exact owner controls, obtains the actual matching tty and
   channel, and receives the immutable binding. It cannot display while inert.
   The host obtains and revalidates the complete source and policy facts under
   the original locks. Empty/missing source or management authority refuses;
   reducing deletion authority is not automatically a grant to display expired
   literal text.
2. **Collect.** For each exact lease, its owning helper receives one private
   operation-bound export request and freezes conflicting mutation/release.
   The guardian receives the **same open file description** by `SCM_RIGHTS`,
   checks the connected peer PID/UID, pinned helper/operation challenge and
   expected lock dev/inode/type/owner/link/mode, and owns the FD with
   close-on-exec. Its manifest rejects duplicate roles, identity aliases,
   secrets and endpoints. Repeated exporter PID is allowed only for distinct
   declared Transaction slots. Neither collector `L` nor exporter `X` grants
   display. Missing/partial/uncertain transfer aborts and leaves a possible
   received FD to be accounted for, not assumed absent.
3. **Activate.** After all exact exports and their host-observed responses, the
   host checks the same immutable operation, original owners, current proofs,
   policy, root and deadline. The check must happen under the continuous
   original leases: no re-lock, no rebase, and no worker callback that can
   alter the frozen display. While exported Transaction slots are frozen,
   prove that all required reads are complete *before* the first export, or
   add an explicitly read-only native check valid for retained stack members;
   do not silently re-read through an unfenced file-server process. A fresh,
   one-use activation bound to the complete manifest and body is sent to the
   same guardian. Guardian verifies its original Session and Host controls,
   exporter pidfds, tty identity and expiry before it can fork a reader or
   issue any protected write. A prior transfer ACK alone is never activation.

   A frozen filesystem lock alone is not a frozen BEAM Session or Writer state.
   The implementation needs an owner-bound, nonblocking quiescent barrier: the
   exact live job and source proof are snapshotted after preceding journal
   effects settle, and neither mutable proof state nor an unaccounted Writer
   append can advance until display closure. The Session must still process
   cancellation and owner loss. If this barrier cannot be proved, activation
   refuses; waiting on a Writer append that itself needs the frozen native
   source helper can deadlock and is not a revalidation strategy.
4. **Display.** Both guardian and its sole forked reader inherit every received
   lease FD. For each bounded tty write, the reader checks its owner and guardian
   controls and the absolute wall deadline immediately before admission. A
   write already admitted when a control dies may finish; the outcome is
   unknown. No further attempt is admitted after observed loss/expiry. Both
   holders keep every FD while any protected write may still execute. The
   complete original facts and nonce are displayed directly to the matched tty,
   never via FIFO-to-BEAM forwarding. Buffered tty bytes have already been
   admitted; the contract does not promise emulator consumption, human
   observation or retrospective recall. No `tcdrain` promise is inferred.
5. **Stop and close.** On full display, the reader reports `y` and enters a
   no-more-protected-write phase. It explicitly drops *all* of its received
   lease descriptors, acknowledges that drop over its private inherited
   guardian channel and waits without displaying protected bytes. If it dies,
   the guardian must reap it, not infer closure from a BEAM message. The
   guardian then drops all of its copies and emits one operation/nonce-bound
   `display_closed` receipt only after the reader's drop or confirmed reap and
   its own drops. This receipt proves the native writer is quiescent and the
   transferred copies are closed; it is not the operator's approval.
6. **Settle before input.** Exporters authenticate an operation-bound close
   message on their retained native peer channel and recheck their original
   lock identities before thawing. The host waits for their framed settlement
   and actual confirmed release of the display leases. Session's live owner
   thaws without releasing/reacquiring its original lock. Only then may the
   guardian permit input, using a fixed safe prompt and no protected redraw.
   Existing restoration, queued-input flush, terminal channel and exact input
   nonce rules remain. No source/Identity/Consent lease is held while awaiting
   human input.
7. **Review effect.** On real native input, the original publication peer
   reacquires and rederives current source/policy/root facts, validates the
   full approved operation and consumes `Review` exactly once in its existing
   owner process. Display closure does not convey a permit. Expired/lost review
   consumption or an unconfirmed effect continues to withhold success; no
   interrupted action is automatically retried.

The precise native close message must be received directly from the trusted
guardian, bound to the same operation and exporter slot, and verified without
assuming a BEAM-forwarded ACK authenticates FD closure. Exporter thaw/release
after a lost or malformed receipt is **not** confirmed. The helper must never
call `flock(LOCK_UN)` on an exported open description: that would unlock every
copy. On cancellation, close both input controls, stop or kill the native
reader, account for the guardian and reader with process identities and actual
reaping/pidfds, and retain any remaining FD until all possible native writers
have stopped. If exact closure cannot be proved, report unknown and quarantine
the operation; actual retained FDs keep competing flock acquisitions blocked.
Helper or guardian death alone does not establish that its peer stopped or that
an exported FD was not received. Stalled kernel IO may delay physical cleanup.
No timeout may be relabeled confirmed cleanup.

The current `ipse-lease-transfer::export` drops its peer socket after `X`; it
cannot receive the proposed close message. A new version must retain an
authenticated per-slot peer connection in the original exporter and poll it
alongside its private owner control. It must still allow the other declared
slots of the same Transaction helper to be exported without blocking on the
first slot's close. A missing ACK after `sendmsg` is a possible transfer, not a
known refusal; the exporter must freeze or terminate with unknown cleanup even
when it cannot tell whether the guardian obtained a copy.

The proposed normal close path requires a new per-operation exporter state:
`unshared → transferring → shared/frozen → all-copies-closed → thawed`, or an
unknown terminal state. The existing boolean cannot support repeated safe
operations or confirm last-holder closure. Implement and test it separately
for Transaction's distinct stack slots and the Session/source owner. For fresh
and resumed Sessions the new export-capable header/resume mode must acquire
the *original* lock at startup and preserve native-owned journal Q/W/E/T, source
identity, header and release semantics. Do not accept export while a header or
journal mutation is in progress; queue/fail new Writer calls while shared and
avoid blocking the Session GenServer on slow IO. A previously started helper
without this protocol must refuse, even if a newer helper is installed.

## Managed worker delivery is a separate native endpoint

The extension worker's actual input pipe is currently owned by the native stdio
supervisor, not the BEAM publication peer. A terminal collector or a separate
FIFO writer followed by BEAM forwarding cannot protect that path. The eventual
worker design must place the same verified lease collection and immutable
action-result binding inside the native process that actually writes the
authorized worker input pipe, or transfer that exact pipe description to a
single native writer with an independently proven ownership protocol. It must
bind the original journaled action/result, worker identity, frame bytes,
Session/Host controls, lease set and expiry; partial or lost delivery is
unknown and cannot continue the worker as a successful action. The worker
never receives a lease FD or export secret. Current worker continuation stays
gated until this real pipe path and its cleanup are tested.

## Required review and controls before activation

- Real matched-tty Session/Host tests for absent, wrong, duplicate, reordered,
  aliased, stale or substituted leases, source proof and policy changes, nonce,
  display/body/tty changes, replay and a foreign native peer. Tests must include
  live Session lock export from its initial header/resume holder and refuse an
  already-live old helper without any release/reacquire window.
- Actual Session, Host, exporter, guardian and reader death before transfer,
  during partial collection, before/after each admitted write, after `y`, during
  close, and during input/restoration. Preserve partial output and exact unknown
  receipts; prove no additional protected redraw after display lease closure.
- Independent contender processes race source replacement, revocation and
  suppression. No successful acknowledgment or successor lock may overtake an
  admitted write while any recipient can still write. Verify no `LOCK_UN`,
  same open description, all forked FD copies and actual final-holder closure.
- Full 131-lease controls, low `RLIMIT_NOFILE`, partial ancillary messages,
  channel backpressure and identity/process substitution. The current collector
  can retain roughly 396 FDs before tty, controls and transient opens; fork
  duplicates that footprint into another process. Derive the exact resource
  budget for the selected implementation, refuse insufficient limits before
  activation, and preserve the full supported source count. `F_SETFL` affects
  a shared open description, so owner/control descriptors must be dedicated.
- Complete-facts review, expired-target display authority, disabled capture,
  explicit management, wrong/replayed/expired permit, live consume followed by
  expiry and durable inspection of unknown effects. Restore Management's own
  legacy journal/header path to native-owned IO before using it for mutation.
- An actual extension worker pipe and partial-frame/backpressure test, not a
  synthetic terminal or FIFO, for the separate managed-result integration.

This is a proposal for review. No source, helper or gate change is made by this
record, and none of the above controls is claimed to have run.
