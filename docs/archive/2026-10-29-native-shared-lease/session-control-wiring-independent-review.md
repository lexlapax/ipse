# Independent review of private Session and Host control wiring

Scoped review, 2026-10-29. The [plan](../../plan.md) owns acceptance. This reviews
[the wiring checkpoint](session-control-wiring.md), manifest SHA-256
`ba1b5cae42b49b56de91e19d18dedb544bc3940d1300a5910d2d47212130382e`,
against the [owner-control review](owner-controls-independent-review.md),
[Host/Session review](session-host-share-independent-review.md) and
[guarded-terminal conditions](guarded-terminal-integration-independent-review.md).
No runtime edits, native changes, model/network calls or passing test reruns
were made by this review.

## Disposition

Accepted as inactive caller wiring for the two owner controls. No concrete
blocker was found within the declared scope. Actual Session cancellation now
closes its separately owned control before killing the active Host, independently
of a suspended Writer. This is stronger evidence than the earlier test-only
Session owner callback, but still does not activate a production journey,
protected output, terminal input, all-copy closure or management review.

## Ticket and preparation boundary

Only the current task caller with the exact current job and admitted action can
obtain a controlled ticket in a share-capable Session. The parent must match a
selected live extension identity; the Session phase must be allowed and its
original operator channel's client and reader must still be alive. The binding
captures caller, job, full intent, parent, phase, complete channel map, fresh
operation and one original five-second monotonic deadline.

Host performs the pinned helper hash/path check outside Session, prepares that
binding and opens its own control Port. Its readiness wait monitors Session and
uses the original deadline. Session then checks the same caller/job/action,
non-interrupted parent, phase, channel and liveness, actual Host Port ownership,
closed preparation fields, intent digest and exact ticket/operation/deadline.
Preparation is limited to the application helper path and embedded helper hash;
an altered path cannot select a different executable. Session only performs the
narrow prepared Port open and asynchronously asks Writer to drain.

A matching start or refusal consumes the ticket. Other invalid controlled-begin
calls while unsealed also clear an outstanding ticket; that is conservative
refusal, not foreign authority to use it. A fresh ticket can only be obtained
through the current task/action checks. Preparations are ordinary trusted-host
maps, not capabilities against hostile same-VM code. The helper precheck does
not atomically bind a filesystem inode through exec; the documented cooperative
same-user filesystem assumption still applies. Neither verification nor
`Port.open` is claimed to be hard-preemptible kernel/filesystem work.

Ticket preparation does not seal Session yet. Any intervening change to job,
parent, action, phase or channel causes controlled start to refuse. Once start
queues the Writer drain, Session returns its installed seal before dispatching
another ordinary message. Source/proof work, job/action commits and channel
replacement remain behind that seal. This closes the prior gap before Writer
and guard arming; helper hashing remains outside Session and its prepared spawn
retains the kernel-blocking limitation stated above.

## Readiness, framing and deadlines

Session handles its native readiness independently of the Writer and guard
replies. It delivers the capability, transport binding and exact Writer snapshot
only after the guarded operation is armed and its own sender has emitted the
matching `R` readiness. Before delivery it rechecks task/client/reader liveness,
channel equality, Host Port ownership and the original deadline. Descriptor
identity is selected after readiness in the retained combined control, avoiding
the earlier pre-exec pipe-identity race.

Session's frame parser retains at most128bytes, permits bounded fragmentation
and limits a frame body to32bytes. It accepts only `R` in starting state, `H`
with exact operation/Session role after configuration, and `T` with that same
binding after `H`. Out-of-order, unknown, extra or mismatched frames poison.
The data handler checks the original deadline before parsing a bounded message;
all Writer/guard success replies and capability delivery also check it. Export
and settlement retain their original request-time deadline checks. Setup never
receives a new budget when readiness or another phase completes.

`T` sends a transfer notification only. It is not a proof of continued owner
liveness, complete all-lease admission or permission to write protected bytes.
The Host's later H/T parser and operation-to-payload/recipient construction remain
open. The Host readiness parser can recognize its fixed R frame before the next
Session check; Session's preparation/deadline checks still prevent an expired
request from successfully starting or progressing the controlled operation.
The unchanged native sender also has its own bounded setup timer; that does not
replace the common Session deadline or future complete-operation deadline.

Late cleanup is distinct from late success as in the prior review. Closing
controls, guard cancellation or physical Writer thaw may complete after expiry;
a late success reply still poisons Session and cannot resume proof/job/export
work. No whole-operation human-wait or terminal-write deadline is established.

## Poison, close and uncertainty

Poison first attempts to close the actual Session-owned Port, then replies
unconfirmed and kills the actual active Host. The Host's directly owned Port
closes with that task. It does not synchronously ask Writer for anything. A
previously poisoned state ignores all queued messages before any frame/reply
handler, so a late `T`, native readiness or guard success cannot change state,
send a new transfer notification or restore progress.

Bound channel-reader loss and other unexpected events enter the same quarantine
path. Reader death is observed through the existing monitor/mailbox mechanism,
not claimed to atomically preempt a native syscall. Any close failure remains
uncertain; killing BEAM tasks is not proof that native output stopped. The
existing quarantined close returns unconfirmed and never manufactures a release
signature or action result, nor automatically replays the admitted action.

Before a matching pre-export abort or post-settlement finish, Host closes its
own Port. Session verifies that exact Port is gone, then closes its own control
and requests the inherited guard cancellation or Writer thaw. A different Port
cannot substitute for the bound Host Port. Pre-export abort has no outstanding
flock transfer; finish still requires prior native flock settlement. Closing
owner controls alone does not prove every recipient read-end or forked native
copy is gone. This section correctly leaves that stronger terminal boundary open.

Operation/name/secret transport remains on private binary control channels;
secret values are not included in R/H/T frames or serialized preparation. The
Session stores neither configuration secret nor a display payload in its frame
buffer. Configuration success means queued bytes, not transfer or admission.
The native one-use/peer/role/operation/pipe checks remain those already reviewed.
There is no new worker/SDK authority or production controlled-adapter call site.

## Frozen evidence and remaining scope

[Verification](evidence/session-control-wiring-review/review-manifest.exs) and
[its result](evidence/session-control-wiring-review/review-manifest.log) verify
all25 manifest entries, eight archived source files, both complete697-file
physical regular-file inventories and both three-file artifact archives. The
inherited dependency source symlink is not traversed as runtime content. The
graphs differ only in Host BEAM, and each retained Host BEAM matches its graph.
Instrumented Host source is exactly production Host plus the single retained
post-action-admission rendezvous.

Both graphs retain helper
`a3f4c20e597820ad2618cf7f2da4c2d6f11afe80389ca52d83ece7804bde38cd`.
Lock, Journal and Writer BEAMs match the earlier owner-control graph; frozen
Journal source exactly preserves the metadata alias repair. Native provenance
remains the prior owner-control archive. The newer Runner/Session/Host changes
are separately pinned, not substituted into any earlier receipt.

The recorded final eight controls are in the `v3-nonsocket` log; the earlier
`final-nonsocket` log contains six and is not relabeled eight. They cover genuine
selected-artifact/worker/Host admission, suspended-Writer cancellation, actual
setup timeout, bound reader loss, altered preparation and consumed-ticket replay,
matching abort, bad frame, forced late frame and sticky poison. Ordering controls
use trusted same-VM interposition, not an isolation claim. The `v3-socket` case
and five `v3-seal` controls also pass. Compile logs preserve the initial bitstring
pin warning and compiler-driver API warnings rather than claiming a clean
whole-source build.

The combined native case transfers actual Session and Host control pipes to two
inert observers and the Session flock to a third recipient. With Writer and the
flock recipient stopped, actual Session cancellation returns unconfirmed in the
observed sub-second window. Both owner observers report loss before Writer is
resumed. After Session closes, a contender remains blocked until the separate
flock recipient resumes and exits. This demonstrates actual owner EOF and last
flock-holder behavior without inferring protected-write quiescence.

Still open: the production call site, later Host frame handling, complete setup/
operation timeout and recipient manifest, native matched tty/per-write admission,
forked reader/guardian inheritance and all-copy close, four management leases,
fresh policy/facts, live one-use Review consumption and end-to-end management.
The standalone CLI management owner is a different path; its native header lock
must not be closed/reacquired to imitate export or assigned Session release
semantics. The generic132-description route remains above131. No broader
activation or completion follows from this scoped acceptance.
