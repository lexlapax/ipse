# Independent review of inert native owner controls

Scoped review, 2026-10-29. The [plan](../../plan.md) owns acceptance. This reviews
[the owner-control checkpoint](owner-controls.md), manifest SHA-256
`43989ae3734b17b600bbc3848789c780f36354c63df9a6dbed041311a52882a2`,
against the [Host/Session review](session-host-share-independent-review.md) and
[guarded-terminal design conditions](guarded-terminal-integration-independent-review.md).
No implementation, native source or gate edits, runtime reruns, model or network
calls were made by this review.

## Disposition

Accepted as an inert Linux owner-Port handoff and loss-observation primitive.
No concrete blocker was found within this scope. It supplies actual owner-pipe
transport and sticky loss observation, not production cancellation wiring,
output admission, a terminal writer, all-copy lease closure or a complete
operation-wide deadline. Protected output and management gates remain closed.

## Native framing, binding and loss

The pinned sender first makes its actual stdin/stdout nonblocking, verifies
stdin is a read-only FIFO, and emits the fixed `R` frame. The fixtures observe
that frame before deriving `/proc/PID/fd/0` identity. This establishes that the
selected FD belongs to the executed sender, instead of sampling the Port
launcher before exec. The observer similarly announces its inert mode before
configuration. Neither announcement is an output or owner-liveness grant.

Sender setup accepts exactly one 69-byte request behind an exact `I` length
frame: nonzero 16-byte operation, Session/Host role, recipient PID, private
abstract name and 32-byte secret. It has one five-second monotonic setup budget.
Extra queued control data or EOF refuses setup. Recipient pidfd, current helper
executable identity and Unix peer PID/UID are checked; the authenticated
challenge binds the secret, operation and role before the actual stdin read end
is transferred. No continuation or retry exists after possible `sendmsg`.
Failed acknowledgement or final transfer-frame publication reports uncertainty.

Observer setup accepts one exact 93-byte request and a bounded1..120,000ms
observation lifetime. It pins the expected sender PID/pidfd/helper, private
address/secret, device and inode; it authenticates the socket peer and operation/
role before accepting the FD. The received FD must be close-on-exec, a FIFO,
read-only and the exact supplied pipe identity. Any wrong or extra descriptor
is dropped on refusal. A transfer acknowledgement reports transport only.

The sender and observer never read the owner pipe after transfer. They only
poll it. An unexpected byte therefore cannot be consumed by one reader and
hidden from another; EOF remains visible after the last write end closes.
The observer also retains and polls the sender helper pidfd and peer stream,
so killing the handoff helper is loss even while BEAM's owner and write end
remain alive. After any detected loss it reports loss and terminates; it never
returns to a live state. Both helpers treat unexpected input, EOF, poll errors
and peer failure conservatively. The sender's eventual normal exit after loss
must not be interpreted by a future host state machine as completed output.

The one-use claim applies to this sender instance. A trusted future caller must
still choose fresh operation/name/secret values and bind the resulting controls
to its operation. There is no global operation-replay database. Same-helper
executable checks and pidfds do not attest the peer's intended helper mode or
prove an atomic no-exec interval. The checkpoint accurately leaves recipient
mode and operation/payload admission to later integration.

## Ancillary receiver and cleanup

The existing ancillary parsing was moved into `receive_raw`; the regular-file
lease wrapper still checks regular type, current UID, one link, mode0600,
zero length and exact device/inode. The shared receiver uses `MSG_CMSG_CLOEXEC`,
a bounded4096-byte control buffer, validates the ancillary headers and truncation,
requires exactly one FD with its expected marker, and checks close-on-exec.
Malformed or multiple received FDs remain owned by local `File` values and are
dropped on error. The new pipe-specific validation is applied only by the inert
owner observer. The affected recorded legacy transfer selection passed without
weakening its regular-file contract.

All newly retained resources are ordinary scoped native files/sockets/pidfds.
Setup errors drop them, and post-transfer loss exits the inert observer. There
is no inherited write-end duplicate in the observed BEAM fixture: its actual
matching pipe has one BEAM write end, owned by the Port. The received and sender
copies are read ends. This does not establish forked-reader/guardian inheritance
or the absence of every possible write-end copy in a later production process
topology.

The observer's lifetime begins after setup and is separate from the sender's
setup deadline. The sender can remain alive after handoff while its owner and
peer remain live. Allocation, frames and concurrently held descriptors are
bounded here; there is no complete future operation-wide timer. Blocking kernel
or filesystem calls are not claimed to obey a hard wall-clock bound.

## Host adapter and observed controls

Runner opens a pinned helper Port connected to its current process. Configure
and close refuse a Port owned by another process; fixed sizes, allowed roles,
nonzero values and PID bounds are checked. `Port.command(..., [:nosuspend])`
success means queued configuration only. The adapter does not consume `R` or
provide the production asynchronous frame state machine. Production callers
must observe that readiness and treat transfer, loss, unexpected frames and
helper exit separately. Trusted same-VM code can still act as trusted host code;
these private functions are not an access-control boundary against it.

The final seven Session tests exercise actual Session death with the VM alive,
actual helper death with Session alive, the one-write-end count and foreign
owner refusal, unexpected bytes, wrong role/operation, wrong peer PID, owner
death after a genuinely bound listener, and direct owner closure with Writer
suspended. The last operation is deliberately invoked through a test-only
`:sys.replace_state` callback. It does not prove production `Session.cancel`
closes a separately Session-owned Port; that wiring remains absent.

The separate real setup-deadline control observes sender exit after a stalled
bound listener within its measured4..7-second test window. The genuine Host
control uses the normal selected artifact, actual independent worker and owned
Host task at the separately instrumented admitted-action rendezvous. Ordinary
Session cancellation kills that Host and its directly owned Port; the inert
observer reports loss while Session stays alive. This proves task ownership in
that fixture, not a supported production Host call site. Three affected native
lease-transfer/close controls also passed. Their passing selections were read,
not rerun by this review.

## Frozen provenance and remaining work

[Manifest verification](evidence/owner-controls-review/review-manifest.exs) and
[its output](evidence/owner-controls-review/review-manifest.log) verify all24
manifest entries,34 regular archived source files, both complete697-file runtime
inventories and the selected three-file worker artifact. Both graphs use helper
`a3f4c20e597820ad2618cf7f2da4c2d6f11afe80389ca52d83ece7804bde38cd`.
The runtime inventories differ only in Host BEAM, and that instrumented BEAM
matches its retained archive. Its source exactly matches the prior separately
reviewed rendezvous source. Session, Lock, Journal and Writer BEAMs equal the
prior Host/Session graph, preserving the Journal metadata alias repair.

Inventory completeness here covers physical regular files, without following
the inherited `telemetry/src` link into dependency source. The verifier's first
walk followed that link and reported nine extra source files; its retained
[initial diagnostic](evidence/owner-controls-review/review-manifest-initial.log)
is a review-script correction, not a runtime or manifest mismatch. The final
walk matches every physical regular file in each graph.

The final source contains the new Linux-only helper module and reuses existing
native IO/peer/ancillary functions, with no package dependency. Earlier v2/v3
binaries and failures are pinned historical diagnostics; their complete source
cohorts were not frozen. Their intermittent pre-exec refusal and later Host
pipe-identity race are not relabeled as passing reproducible final source.
Compile logs include compiler-driver API deprecation warnings; this is not an
empty-warning whole-source qualification.

Still required: production Session and Host opening/control ownership; strict
asynchronous readiness and frame handling; original operation-wide deadline;
poisoned cancellation closing the actual Session control independently of
Writer; intended recipient and all-lease authentication; immutable payload
binding; native matched tty and per-write admission; forked reader/guardian FD
closure; complete four-lease management settlement and one-use current-policy
approval. The larger132-description route remains above the current131 limit.
No terminal content, protected write, human consumption or instantaneous
owner-death/write atomicity is established by this acceptance.
