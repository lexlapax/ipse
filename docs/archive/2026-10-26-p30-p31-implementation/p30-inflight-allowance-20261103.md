# In-flight cross-process allowance control: setup failure, 2026-11-03

One synthetic attempt did not reach the second decision reservation. It does not
establish whether overlapping Sessions respect the shared experiment allowance.
The [prior cross-process control](p30-cross-process-allowance-20261103.md)
covered a later attempt after two calls had settled; simultaneous or in-flight
actual-Session qualification remains open.

The isolated snapshot came from commit
`dcbb07dd451f1402d28391b716b2b177e35331a7`. Its test-only fixture created a
fresh project, source Session, one-call shadow experiment, two separate
loopback origins and a second OS process with a separate Session and PTY. It
intended to hold the first decision response until the second process observed
the allowance result. This would check an in-flight admitted request, not
simultaneous entry to the reservation function.

The offline build and formatting completed. Project compilation treated
warnings as errors; the [build log](p30-inflight-allowance-20261103/build.log)
also records upstream dependency warnings. The selected direct ExUnit entry
avoided the standard test helper's HOME assignment. HOME was inherited and
unchanged; IPSE_HOME, TMPDIR, Session operator-home paths and the project were
synthetic. The standalone experiment setup's home isolation was checked from
source, not with an operating-system access trace. The synthetic decision
profile was configured with a 60-second timeout; the displayed decision request
used 30 seconds. The outer PTY bound was 150 seconds. No product timeout was
changed.

The [one-shot result](p30-inflight-allowance-20261103/task-one-shot.log)
reports **0/1 passed** in 14.3 seconds. The first synthetic decision was
assessed after its response was released. The contender's terminal reported
`operator channel unavailable` and its CLI interaction returned 1 before a
second approval or allowance result. The parent then failed its child-success
assertion. No retry was made, and the test does not prove an allowance refusal.
The [compact projection](p30-inflight-allowance-20261103/synthetic-projection.txt)
was derived from retained synthetic terminal logs without including request
content or approval codes.

In the current [native operator implementation](../../../native/ipse-operator.rs),
the probe validates the terminal and maps any subsequent channel-lock failure
to that generic message. The lock is shared per operating-system user across
terminals. The first CLI's prompt reader can hold it while the decision is
running, and its retained terminal log shows a new prompt after approval; that
is a source-supported explanation, not proof of the particular failed lock
check. A direct `Session.approve/3` substitution is not equivalent here:
the source-backed invocation follows the
[managed approval path](../../../lib/ipse/session/managed_approval.ex), which
requires the native review. The ordinary approval handler denies managed
invocations without that native admission.

The [evidence manifest](p30-inflight-allowance-20261103/evidence.sha256)
has SHA-256 `e0ff1171263d1b88c394a653dc78463545be01c43a679af8adcaed74913e0e20`.
It covers the exact fixture and launcher, scoped test log, completion and
postcheck, and source/dependency/runtime inventories. The inventories identify
the isolated tree; they do not archive every compiled artifact. Full synthetic
terminal logs and the fresh fixture root remain in volatile storage; their
hashes are `788983276a255ef6368220513b86da35d65ae4d1136ca240e4ebb958264c1912`
(parent) and `ddcb850fff48fb05af384240feaf11a2a5449326f714aec57a0c1f1276bbaf49`
(contender). The derived projection cannot independently reconstruct those
logs after their removal. The [current plan](../../plan.md) owns milestone
status.
