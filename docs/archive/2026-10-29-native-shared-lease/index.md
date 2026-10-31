# Native shared-lock descriptor experiment

Dated 2026-10-29. This is a development-only Linux experiment, not a production
lease-transfer feature, native-profile qualification, or P30/P31 acceptance.
The [current plan](../../plan.md) remains authoritative. The Session correction
and managed-result paths remain fail-closed while their display/use ownership
requirements are unresolved.

The later [guarded terminal integration design](guarded-terminal-integration-design.md)
and [independent review](guarded-terminal-integration-independent-review.md)
define a production implementation direction, not activation evidence. They
distinguish an admitted in-flight native write with an unknown result from an
unsupported physical cancellation guarantee. Actual retained descriptors must
order display quiescence against later source or revocation acknowledgment.
The separate [full-facts management purpose](../2026-10-26-p30-p31-implementation/management-display-scope.md)
and [scope review](../2026-10-26-p30-p31-implementation/management-display-scope-independent-review.md)
bound faithful local review of a selected stored target. The experiments below
retain their original, narrower evidence and failures.

The later [retained-close infrastructure](retained-close-infrastructure.md),
[exporter-loss follow-up](retained-close-exporter-loss.md) and
[independent review](retained-close-independent-review.md) qualify an inert
bounded collector's settlement protocol. The [Session sharing candidate](session-share-candidate.md)
and [independent review](session-share-candidate-independent-review.md) cover
original header/resume flock sharing and the Writer snapshot barrier. Neither
enables a production output sink. Session job/cancellation sealing, exact owner
controls, actual tty guardian/reader closure and activation remain separate.
The subsequent [inactive Session operation seal](session-operation-barrier.md)
and [independent review](session-operation-barrier-independent-review.md) cover
pre-drain state sealing and responsive cancellation controls. Its test task is
synthetic; actual Host authority, export and terminal delivery are still open.
The later [Host/Session transfer section](session-host-share.md) and
[independent review](session-host-share-independent-review.md) use a genuine
selected artifact and worker with a separate test-instrumented Host graph.
They qualify inactive transfer/settlement and cancellation controls; production
call sites, exact owner EOF controls, tty closure and output activation remain open.
The later [EOF-only owner controls](owner-controls.md) and
[independent review](owner-controls-independent-review.md) transfer the actual
owner-Port read ends. [Private caller wiring](session-control-wiring.md) and
[its review](session-control-wiring-independent-review.md) bind both owners to
the actual job/action/input reader and close their controls during cancellation
without waiting on Writer. These are conversation Session/Host candidates;
standalone management has a different owner pair. Production callers, matched
tty display, complete lease admission and all-copy closure remain open.

The current lease owners are distinct: the protected Transaction helper holds
project Identity and Consent flock descriptions; an inactive source has its own
source-lock helper; a live Session source is protected by the Session lock owner
and Writer's exact active-source validation. The BEAM controls those helpers over
pipes. Existing pipe protocols do not provide a way to transfer their retained
lock descriptors to the terminal guardian and reader. A Session lock also must
outlive its owner and the native display processes, not just tracked BEAM peers.

The standalone [fixture](../../../dev/fixtures/shared_lease_scm_rights.rs) uses a
private synthetic lock, a Unix socket pair and Linux `SCM_RIGHTS` to transfer an
already-held flock open description to a separate process. On this x86-64 Linux
7.2.11 host, the [final control](evidence/transfer-v8.log) killed the original
sender with SIGKILL after transfer. Both an independent contender and the actual
frozen `ipse-runner --lock` helper refused the lock while the recipient retained
it. The helper acquired it after the last holder either closed the descriptor or
was killed. The fixture also rejects a missing descriptor or a mismatched inode,
checks close-on-exec, and confirms that `flock(LOCK_UN)` on any duplicate releases
the lock for every holder. It cleans up its test children on failure.

This demonstrates kernel behavior and compatibility with the existing helper's
flock, not transfer of an actual production helper descriptor. It does not validate
an authenticated transfer channel, all source/Identity/Consent lease identities,
lock acquisition order, Session/Writer lifetime, terminal writes, native guardian
or reader death, or release after the display acknowledgement. A future integrated
design must cover those boundaries and must prohibit explicit unlock of shared
open descriptions while any display holder remains. No arbitrary worker may choose
a descriptor, path, authority, or peer. Existing native transaction and Session
lock semantics must not be weakened.
The [candidate handoff design](design.md) records the separate terminal and worker
delivery boundaries, required lock order, and controls still needed before use.

## Private native export prototype

The working tree also contains a Linux-only, additive native export primitive.
An `X` command on the retained Transaction helper selects an already-held stack
slot; the separate `--lock-export-v1` mode acquires a protected Session/source
lock without changing the existing `--lock` byte protocol. A private request
binds expected lock device/inode, recipient PID, abstract socket name and secret.
The helper validates the retained lock, same-UID kernel peer credentials, exact
PID and secret before sending one descriptor, and requires an acknowledgment.
Loss after a possible send is unconfirmed. There is no active BEAM caller and
neither gated user path is enabled. In particular, these checks do not establish
the recipient's executable identity or prevent a malicious recipient from calling
`LOCK_UN`; a future caller must admit a pinned trusted sink and enforce the full
lease protocol. A successful export or acknowledgment is not admission to write.

The isolated [v5 native control](evidence/export/transaction-export-v5.log)
exercised both helper modes. It refused wrong recipient PID, inode and secret;
verified an acknowledged descriptor retained the lock after helper death; and
verified last close released it. A descriptor delivered without acknowledgment
produced an unknown result while the recipient retained the lock. The owner-loss
case observed refusal before transfer, which does not exclude the race in which
the descriptor is sent just after control loss. The export reply identifies the
exact selected slot and duplicate export of that slot is refused. Once any slot
has been exported, a subsequent Transaction release is unconfirmed, even when
the top slot was not exported; the helper terminates and closes its own local
descriptors. A control demonstrated that the nonexported top lock then released
while the recipient retained the exported parent lock. Source release after export
is likewise unconfirmed. An acknowledgment alone does not establish the last
holder's closure: a separately authenticated sink-completion and close protocol
is still required. Source cancellation before export, invalid names and symlinks
refused or cleaned up as appropriate. The preceding
helper build also passed [legacy `--lock` controls](evidence/export/legacy-lock-export-helper.log),
and four [existing focused Transaction tests](evidence/export/transaction-existing-focused.log)
passed. The initial [compiler attempt](evidence/export/export-compile.log) failed
on a Rust expression syntax error; the retry passed.

The current native source snapshot is under
`_build/shared-lease-sol-20261029/evidence-source-export/`. Its
[source hashes](evidence/export/export-source-v5.sha256) and the
[binary/log hashes](evidence/export/export-artifacts-v5.sha256) identify the v5
cohort; its native helper SHA-256 is
`f2d253cc7af977bcad4967db1e8b231cc62dcc16d245b30a94c185d715281e05`.
The [v4 control](evidence/export/transaction-export-test-v4.log) and its
[source](evidence/export/export-source.sha256) and
[artifact hashes](evidence/export/export-artifacts.sha256) remain as historical
evidence for the earlier release behavior.
The [independent protocol review](export-independent-review.md) identified
receiver authentication and cleanup, live Session migration, control-loss ordering
and durable provenance gaps. This remains a prototype, not a complete or admitted
Session-source, terminal or managed-result transfer implementation.

The unignored [durable v5 source snapshot](evidence/export/source-v5.tar) has
SHA-256 `299be19bc2f100554fcd7c981ea1182b3727cd934ac773ada3d9c1f040699ddb`.
The v5 fixture receiver is not suitable for reuse as a sink: malformed or
truncated ancillary messages can leak descriptors. A real receiver must
authenticate the listening helper and operation, validate descriptor identity,
receive with close-on-exec and close every received descriptor on failure. The
socket deadline does not bound filesystem validation calls. Control can close
after the final liveness check and before the X reply, so the reply is not an
atomic owner-loss classification.

The `--lock-export-v1` helper acquires its own lock and can create a missing
lock file. It cannot export an already-live legacy `--lock` description. Live
Session migration must preserve source-existence checks and prove that there is
no gap in lock ownership; this prototype does neither.

## Receiver and owner-loss follow-up

The revised development fixture checks the listener PID and UID before sending
its operation secret; it takes ownership of each received descriptor before
validating the frame and checks the expected file metadata and close-on-exec.
The [focused receiver controls](evidence/export/receiver-controls-v9.log)
refused a substitute listener before disclosing the secret, a wrong inode, a bad
frame, extra descriptors and truncated ancillary data without leaking received
descriptors. The [positive controls](evidence/export/receiver-valid-v9.log)
used both real helper modes. These are fixture controls, not a pinned production
sink: PID and UID alone do not establish executable identity or defeat PID reuse.

The [owner-loss control](evidence/export/transaction-export-race-v9.log) used a
separately built test helper whose compile-time-only hook stops immediately after
the last control check. Closing the control input before releasing the hook still
produced X in both helper modes. X therefore reports a completed transfer, not
atomic owner liveness. The test hook is absent from the ordinary helper build.
The earlier sandboxed [fixture attempt](evidence/export/transaction-export-v6.log)
failed with EPERM; its [retry outside the sandbox](evidence/export/transaction-export-v6-retry.log)
passed. The unignored [source snapshot](evidence/export/source-v9.tar) and
[source, binary and log hashes](evidence/export/review-repairs-v9.sha256)
identify the follow-up cohort. The [recorded commands](evidence/export/commands-v9.md)
include the build flags and individual test invocations. The separately retained binaries are under
`_build/shared-lease-sol-20261029/`.

The [proposed separate admission](design.md#separate-sink-admission-still-required)
requires a pinned sink, all exact leases and a native owner-death fence before
any write. Those requirements are not implemented by this fixture. The two user
paths remain unavailable.

The subsequent [inert native collector](collector.md) retains up to 131 checked
lease descriptions and can report closure of its own copies. It cannot display or
deliver data, and it is not an all-leases admission or live Session migration.
The later [pipe output experiment](output-experiment.md) demonstrated a write
after synthetic owner loss; the normal helper refuses that experimental mode.
The [Session-start candidate](session-start.md) is now gated after an
owner-loss finding. A separate [native header follow-up](session-header-native.md)
changes Linux fresh Session initialization; managed output remains unavailable.
The separate [post-release receipt contract](release-receipt-contract.md) began as
a pure signed-claim prototype. Its later [Linux Session integration](release-receipt-integration.md)
and [framed resume follow-up](release-receipt-resume.md) are under independent
review and do not enable managed output. The subsequent
[native-owned journal repair](native-journal-owner.md) addresses a confirmed
helper-loss write race and is also awaiting independent review.

The next independent review found the fixture's initial poll did not bound a
subsequent partial frame. The revised v10 fixture reads nonblocking with one
absolute deadline for both header and body. Its [stall controls](evidence/export/frame-controls-v10.log)
timed out on incomplete headers and bodies and accepted a complete frame; the
[real-helper positive control](evidence/export/frame-valid-v10.log) and
[owner-loss control](evidence/export/frame-race-v10.log) also passed with the
new reader. The exact [fixture source](evidence/export/transaction-lease-export-v10.rs)
and [artifact hashes](evidence/export/frame-reader-v10.sha256) preserve that
follow-up. No runtime or user-path gate changed.

The [first sandboxed attempt](evidence/transfer.log) returned EPERM before a
success receipt; its failing stage was not recorded. The unsandboxed runs used a
private `/tmp` directory. The [first real-helper attempt](evidence/transfer-v3.log)
failed because the fixture looked for a framed helper error on stderr; the helper
actually writes that frame to stdout. The corrected run passed. The later v8 control
strengthened the wrong-inode check to require the receiver's explicit refusal
rather than accepting any error. The exact [fixture source](evidence/source-v8.rs),
strict compiler output, helper, binary and log hashes are listed in
[the final manifest](evidence/manifest-v8.sha256). The earlier
[v7 result](evidence/transfer-v7.log) and [manifest](evidence/manifest.sha256)
remain for provenance. The native helper
SHA-256 was `aed2ef0998e3fdf421c8acfe35a9d04d4107ac9194fc1dcf3aee5f1d3be7cc09`.
The build graph and executable remain under `_build/shared-lease-sol-20261029/`.

To repeat the focused experiment on a supported Linux test host, first build the
matching native Ipse helper, then use a private test directory:

```sh
rustc --edition=2021 -D warnings dev/fixtures/shared_lease_scm_rights.rs -o /tmp/ipse-shared-lease-experiment
task_dir=$(mktemp -d /tmp/ipse-shared-lease-XXXXXX)
/tmp/ipse-shared-lease-experiment "$task_dir" /absolute/path/to/ipse-runner
```

The command uses SIGKILL only on its own synthetic child processes. It does not
modify an Ipse project or invoke a model.
