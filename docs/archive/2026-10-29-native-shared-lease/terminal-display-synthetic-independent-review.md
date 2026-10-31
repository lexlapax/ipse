# Independent review of the synthetic native leased display

Scoped review, 2026-10-29. The [plan](../../plan.md) owns acceptance. This reviews
[the synthetic display checkpoint](terminal-display-synthetic.md), manifest
SHA-256 `ba2dc99c6151256e22ab94bbea7a06f553b01d40c75c406ed28c0be9b48f0ab7`,
against the prior [inert review](terminal-lease-inert-independent-review.md) and
[terminal design conditions](guarded-terminal-integration-independent-review.md).
No production/native source, caller or gate edits were made. One newly authorized
focused omission counterexample ran against the exact frozen production helper;
no passing aggregate was repeated.

## Initial disposition: acceptance held

The frozen active candidate has two blocking repair conditions. Neither finding
establishes a production output or management authority exploit: no production
caller or protected gate connects to this synthetic mode.

**Active cardinality is not enforced.** The shared native `run` function accepts
`count` in1..4 for both inert and active modes. The outer operator entry only
passes the active flag and adds no four-lease check. Repeating the exact initial
body at activation therefore authenticates an incomplete manifest just as well
as a four-entry one. This contradicts the active subsection's fixed-four lease
requirement. Both owner roles are still required, but they do not replace the
missing leases.

[The exact one-lease derivative](evidence/terminal-display-review/one-lease-probe.rs)
and [its result](evidence/terminal-display-review/one-lease-probe.log) reproduce
this against production helper
`94f32c7ffdaf426d08d28d91b3df0c5e9961d80fc31cce766793e62b49cdfa6a`.
The derivative changes only the frozen fixture's three four-owner/manifest/
transfer loops to one, its request and expected-summary count to one, and the
final marker. It retains both native EOF owner controls and the existing
`display-ok` assertions. The actual helper emits D, the isolated matched PTY
receives the exact synthetic payload, and authenticated exporter settlement plus
final C complete successfully with one lease. The case exits0 with
`TTY_ONE_LEASE_ACTIVE_DISPLAY_AND_CLOSE_ACCEPTED`.

The derivative compiled with `rustc --edition=2021 -D warnings -O` and ran once
in an authorized fresh private fixture directory with isolated PTY/Unix sockets.
No actual Session, Host, Management, protected facts or public gate was involved.
The original source/helper/cohort remains unchanged. Active mode must refuse an
incomplete fixed-four manifest before collection or payload writing; inert1..4
behavior may remain explicit.

**Monotonic admission needs a post-wait check.** `synthetic_write` and
`display_frame` freshly check wall expiry after `ready_watch`, but rely on that
helper's before-poll monotonic deadline check. Its successful readiness return
does not check `Instant::now()` again. A late readiness wake or scheduling delay
can therefore reach a new tty/status syscall after the common monotonic deadline
when wall expiry is later. Final-success deadline checks reject eventual success
but cannot prevent that new admission. The existing ordinary fixture geometry
uses wall expiry no later than the five-second monotonic budget and does not
qualify this ordering.

Root confirmed that the original contract requires both clocks at new write
admission. Repair must sample monotonic time immediately after readiness and
before a new tty/status write, alongside the existing wall sampling. The reader's
private progress write also follows readiness and should preserve that same
clock boundary. A syscall already admitted before expiry may still finish late
and remain unknown; this condition does not require impossible instantaneous
cancellation. This second issue is a source inspection finding only. No second
runtime counterexample was run or claimed.

## Remaining source assessment

No additional concrete blocker was found in the frozen activation, retention
and close mechanics. The active initial body binds operation, both ordered owner
entries, lease entries, exact tty identity, wall expiry and bounded1..8192-byte
UTF-8 payload. It rejects terminal control characters except newline/tab.
Activation repeats the complete immutable body and rechecks the retained tty's
device/inode/rdev. Changed payload or manifest cannot replace the collected
inputs. The protocol has no return to activation state; repeated activation
becomes unexpected control input and fails closed. Cardinality must nevertheless
be independently enforced as above.

The initial manifest rejects duplicate address, secret and descriptor identity;
lease collection also rejects repeated exporter-PID/slot pairs. Owner collection
hardcodes Session and Host roles1/2 and binds their operation, private handshake,
peer/pidfd and exact FIFO identities. Regular leases retain the prior native
metadata/ancillary checks. These are synthetic native peers, not attested
Identity/Consent/Collection roles or actual BEAM ownership.

Both forked processes inherit the exact lock descriptions, tty/channel lock and
owner controls. The reader closes its guardian-pipe write end and watches that
pipe, both EOF controls, helper pidfds, exporter pidfds and retained lease peer
sockets. During active display the guardian additionally watches a reader pidfd,
so reader death before activation is observed without waiting for a close
request. The reader directly writes the verified tty in bounded4096-byte chunks;
no protected buffer is forwarded through BEAM.

Before each write, owner/control/peer readiness and wall freshness are checked;
loss is sticky because neither owner pipe is consumed. An already admitted
syscall may race owner death. The retained stop-hook case explicitly permits
one admitted chunk after all original owners and guardian die; the reader's
copies keep every lock held until its eventual exit. It produces no settled
operation or accepted display/close success. Bytes already queued cannot be
recalled by a later clock or process check. Emulator consumption and human
observation are not inferred.

The guardian accepts its internal D progress only while the reader and owner
watches remain valid and wall expiry is current. The v6 public D routine now
checks wall time around status readiness and after sending, repairing the
retained v4 status-backpressure failure. D means native write progress only,
not Review or effect authority. Future callers must treat partial or late native
status as unknown and apply their own original deadline/owner state. The
monotonic admission issue above remains separate from this repaired wall check.

Normal close tells the reader to exit, reaps it successfully, drops guardian
lease copies, then performs each operation/slot-bound C/F/G and exporter endpoint
EOF in manifest order. Only completed closure produces C. Error cleanup's child
guard is destroyed before parent lease vectors, killing/reaping the reader
before those parent copies drop. No `LOCK_UN` or replacement-inode trick is used.
Unconfirmed cleanup cannot authorize thaw. Physical kernel IO, kill/reap and
filesystem preparation are not hard-preemptible wall-clock operations.

## Evidence and scope

[Verification](evidence/terminal-display-review/review-manifest.exs) and
[its result](evidence/terminal-display-review/review-manifest.log) validate all50
manifest entries and32 archived regular source files. Production v6 helper and
test-interposition helper are separately pinned as
`94f32c7ffdaf426d08d28d91b3df0c5e9961d80fc31cce766793e62b49cdfa6a` and
`1bba3c00b05a44b9d1b38d56ed086be1596d6e0393794e9d52f41c6a95ae54f4`.
The production binary contains neither stop-hook marker; the hook binary has
both. The verifier also checks the omission probe is the exact described fixture
derivative. There is no separately qualified BEAM runtime graph in this native
subsection.

The13 recorded final modes and separate status-pipe repair control were inspected,
not repeated. They cover ordinary four-lease display/close, changed payload and
manifest, pre-activation reader death, wall expiry, owner loss, wrong tty,
partial owner/expiry outcomes, admitted-write loss, repeated activation and two
inert regressions. The real prefilled-pipe case reproduces late D using retained
v4 binary and final v6 fixture; v6 refuses late D/C after actual tty output and
cleans up unknown. The initial sandboxed frame-EOF attempt is distinct from the
authorized reproduction. Exact v4 source was not frozen, so its binary failure
is not an independently rebuildable v4 source cohort. The final tar reproduces
v6 only. None of these passing controls tests an incomplete active manifest or
a monotonic deadline earlier than wall expiry.

After both repair conditions are addressed, a narrow additive review is needed
before real caller or gate integration. Actual Session/Host controls and sealed
source/Writer barrier, the separate Management journal/Identity/Consent/Collection
owner path, native input/redraw and Review release sequencing, all-copy closure
and confirmed exporter settlement before thaw, real-chain backpressure/loss,
fresh policy/facts and live one-use effect admission all remain open. Four
synthetic Transaction owners are not four real management roles. The generic
132-description route still exceeds131. No production, protected-output,
management, human-observation or full-platform acceptance follows here.

## Additive v7 repair disposition

The [separate repair](terminal-display-repair.md), manifest SHA-256
`731aa89426fa645c9a68d8869e67a27edef3171da69e1e91a2db05a57a9188b6`,
closes both original conditions. Accepted for the same synthetic native scope;
no production caller, Review or protected gate is activated. The original v6
cohort and one-lease success counterexample remain unchanged.

[Repair verification](evidence/terminal-display-review/review-repair-manifest.exs)
and [its result](evidence/terminal-display-review/review-repair-manifest.log)
verify all17 additive manifest entries,32 source files and the separate
31-file negative-source archive. Only `native/ipse-terminal-lease.rs` and its
fixture differ from v6. Production helper
`3fa931bdf2d551440813507a608d9a36f7bf199801d87b89bea18a345458d318`
is separate from hook helper
`86d3bb41a29dbefd96b20cb1b1c8ff87d528a508bc072368795b1e99a4517a14`.
Production contains none of the three stop-hook markers. There is no new BEAM
runtime or caller-integration qualification.

Active count must now equal four in the initial native validation, before H,
owner/lease collection, fork or any payload write. Inert1..4 remains explicit.
The existing ordered owner roles and duplicate identity/address/secret/PID-slot
checks are preserved. The original one-lease fixture was rerun once against the
exact repaired production helper in a fresh authorized isolated PTY/socket
fixture. It now stops with `frame EOF` before H, exit1; the retained
[recheck log](evidence/terminal-display-review/one-lease-repair-recheck.log)
records that the prior unexpected-success probe no longer succeeds. The three
owner-recorded short-manifest controls additionally check counts1/2/3 refuse
before readiness and without tty output. No passing aggregate was repeated.

The tty writer and public D status writer now sample both wall and monotonic
deadlines immediately after readiness and before a new write. Their pre-wait
checks remain. The private reader D progress write also samples both clocks
after readiness before emitting progress. Final success checks remain intact.
The existing post-admission stop hook is still after admission, preserving the
explicit possibility of an already admitted syscall completing late or after
owner loss without making it known success.

The new focused scheduling control uses wall expiry10seconds after setup and
the original5-second monotonic deadline. A test-only hook stops the reader after
tty readiness but before the new check; the fixture stops the guardian, waits
5.2seconds and resumes both. The repaired control observes no tty bytes or D/C
confirmation. The independently pinned negative helper removes exactly that
one post-readiness monotonic condition from the repaired source; all other
native source files match. Its same focused fixture reports an actual
`tty write admitted after monotonic deadline`, demonstrating that the new check
is necessary in this geometry. These positive and negative logs were inspected,
not rerun by this reviewer. They do not independently interpose the public-status
or private-progress write; those checks are verified by source inspection.

Recorded active-four display/settlement, inert-four normal close and the
wall-expired prefilled D-status control also pass. These focused controls
support the narrow repair, not a new whole-path acceptance. No additional
scoped blocker remains. All real caller, target-purpose/all-lease admission,
Session/Host or management ownership, native input/redraw, all-copy closure and
Review/effect authority requirements stated above remain open.
